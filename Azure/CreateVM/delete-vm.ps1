# Azure VM Deletion Script (PowerShell)
# This script deletes Azure VM and associated resources based on configuration in .env file
#
# Prerequisites:
# 1. Azure CLI must be installed
# 2. Must be logged in to Azure: az login
# 3. Must have an existing Resource Group

param(
    [switch]$Force,
    [switch]$WhatIf
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to load .env file
function Load-EnvFile {
    param([string]$Path = ".env")
    
    if (-not (Test-Path $Path)) {
        Write-Error "Error: .env file not found. Please create .env file with required variables."
        exit 1
    }
    
    Get-Content $Path | Where-Object { $_ -match "^[^#].*=" } | ForEach-Object {
        $key, $value = $_ -split "=", 2
        [Environment]::SetEnvironmentVariable($key.Trim(), $value.Trim(), "Process")
    }
}

# Function to prompt for confirmation
function Confirm-Action {
    param([string]$Message)
    
    if ($Force) { return $true }
    
    $response = Read-Host "$Message (yes/no)"
    return ($response -match "^[Yy]es$")
}

# Function to check if resource exists
function Test-AzureResource {
    param(
        [string]$ResourceType,
        [string]$ResourceGroup,
        [string]$Name
    )
    
    $result = $null
    switch ($ResourceType) {
        "vm" { 
            $result = az vm show --resource-group $ResourceGroup --name $Name 2>$null
        }
        "nic" { 
            $result = az network nic show --resource-group $ResourceGroup --name $Name 2>$null
        }
        "public-ip" { 
            $result = az network public-ip show --resource-group $ResourceGroup --name $Name 2>$null
        }
        "nsg" { 
            $result = az network nsg show --resource-group $ResourceGroup --name $Name 2>$null
        }
        "vnet" { 
            $result = az network vnet show --resource-group $ResourceGroup --name $Name 2>$null
        }
    }
    
    return ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($result))
}

# Load environment variables
Load-EnvFile

# Validate required variables
$requiredVars = @("RESOURCE_GROUP", "VM_NAME")

foreach ($var in $requiredVars) {
    $value = [Environment]::GetEnvironmentVariable($var)
    if ([string]::IsNullOrEmpty($value)) {
        Write-Error "Error: Required variable $var is not set in .env file"
        exit 1
    }
}

# Get environment variables
$RESOURCE_GROUP = [Environment]::GetEnvironmentVariable("RESOURCE_GROUP")
$VM_NAME = [Environment]::GetEnvironmentVariable("VM_NAME")
$CREATE_PUBLIC_IP = [Environment]::GetEnvironmentVariable("CREATE_PUBLIC_IP")

# Set tag to VM name
$TAG_KEY = "VMName"
$TAG_VALUE = $VM_NAME

# Set names based on VM name
$VNET_NAME = "$VM_NAME-VNET"
$SUBNET_NAME = "$VM_NAME-SUBNET"
$NSG_NAME = "$VM_NAME-NSG"
$PUBLIC_IP_NAME = "$VM_NAME-PIP"
$NIC_NAME = "$VM_NAME-nic"

Write-Host "Starting Azure VM deletion process..." -ForegroundColor Red
Write-Host "This will delete VM: $VM_NAME and associated resources" -ForegroundColor Red
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf: Would attempt to delete the following resources:" -ForegroundColor Yellow
    Write-Host "  VM: $VM_NAME" -ForegroundColor Yellow
    Write-Host "  Network Interface: $NIC_NAME" -ForegroundColor Yellow
    if ($CREATE_PUBLIC_IP -eq "yes") {
        Write-Host "  Public IP: $PUBLIC_IP_NAME" -ForegroundColor Yellow
    }
    Write-Host "  NSG: $NSG_NAME (with confirmation)" -ForegroundColor Yellow
    Write-Host "  VNet: $VNET_NAME (with confirmation)" -ForegroundColor Yellow
    exit 0
}

# Ask for confirmation
if (-not (Confirm-Action "Are you sure you want to delete the VM and ALL associated resources (VM, NIC, Public IP, Disk, NSG, VNet)?")) {
    Write-Host "Deletion cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Proceeding with deletion..." -ForegroundColor Red

try {
    # Check if VM exists and delete it
    Write-Host "Step 1/6: Checking if VM exists..." -ForegroundColor Cyan
    if (-not (Test-AzureResource "vm" $RESOURCE_GROUP $VM_NAME)) {
        Write-Host "VM $VM_NAME not found in resource group $RESOURCE_GROUP" -ForegroundColor Yellow
    } else {
        Write-Host "Deleting virtual machine: $VM_NAME (this may take a few minutes)" -ForegroundColor Cyan
        az vm delete --resource-group $RESOURCE_GROUP --name $VM_NAME --yes
        Write-Host "VM deletion completed" -ForegroundColor Green
    }

    # Delete network interface
    Write-Host "Step 2/6: Deleting network interface..." -ForegroundColor Cyan
    if (Test-AzureResource "nic" $RESOURCE_GROUP $NIC_NAME) {
        Write-Host "Deleting network interface: $NIC_NAME" -ForegroundColor Cyan
        az network nic delete --resource-group $RESOURCE_GROUP --name $NIC_NAME
        Write-Host "Network interface deleted" -ForegroundColor Green
    } else {
        Write-Host "Network interface $NIC_NAME not found" -ForegroundColor Yellow
    }

    # Delete public IP if it exists
    Write-Host "Step 3/6: Deleting public IP..." -ForegroundColor Cyan
    if ($CREATE_PUBLIC_IP -eq "yes" -and ![string]::IsNullOrEmpty($PUBLIC_IP_NAME)) {
        if (Test-AzureResource "public-ip" $RESOURCE_GROUP $PUBLIC_IP_NAME) {
            Write-Host "Deleting public IP: $PUBLIC_IP_NAME" -ForegroundColor Cyan
            az network public-ip delete --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME
            Write-Host "Public IP deleted" -ForegroundColor Green
        } else {
            Write-Host "Public IP $PUBLIC_IP_NAME not found" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No public IP to delete" -ForegroundColor Yellow
    }

    # Delete OS disk
    Write-Host "Step 4/6: Deleting OS disk..." -ForegroundColor Cyan
    
    # Try multiple methods to find the OS disk
    $actualDisk = $null
    
    # Method 1: Look for disk with VM name tag
    $diskQuery1 = "[?tags.$TAG_KEY=='$TAG_VALUE'].name"
    $actualDisk = az disk list --resource-group $RESOURCE_GROUP --query $diskQuery1 --output tsv 2>$null
    
    # Method 2: Look for disk containing VM name
    if ([string]::IsNullOrEmpty($actualDisk)) {
        $diskQuery2 = "[?contains(name, '$VM_NAME')].name"
        $actualDisk = az disk list --resource-group $RESOURCE_GROUP --query $diskQuery2 --output tsv 2>$null
    }
    
    # Method 3: Look for orphaned OS disks (no attached VM)
    if ([string]::IsNullOrEmpty($actualDisk)) {
        $diskQuery3 = "[?diskState=='Unattached' && contains(name, 'OsDisk')].name"
        $orphanedDisks = az disk list --resource-group $RESOURCE_GROUP --query $diskQuery3 --output tsv 2>$null
        if (![string]::IsNullOrEmpty($orphanedDisks)) {
            $actualDisk = ($orphanedDisks -split "`n")[0]  # Take first orphaned OS disk
        }
    }
    
    if (![string]::IsNullOrEmpty($actualDisk)) {
        Write-Host "Deleting OS disk: $actualDisk" -ForegroundColor Cyan
        az disk delete --resource-group $RESOURCE_GROUP --name $actualDisk --yes
        Write-Host "OS disk deleted" -ForegroundColor Green
    } else {
        Write-Host "No OS disk found for VM (may have been auto-deleted)" -ForegroundColor Yellow
    }

    # Delete network security group
    Write-Host "Step 5/6: Deleting network security group..." -ForegroundColor Cyan
    if (Test-AzureResource "nsg" $RESOURCE_GROUP $NSG_NAME) {
        Write-Host "Deleting network security group: $NSG_NAME" -ForegroundColor Cyan
        az network nsg delete --resource-group $RESOURCE_GROUP --name $NSG_NAME
        Write-Host "Network security group deleted" -ForegroundColor Green
    } else {
        Write-Host "Network security group $NSG_NAME not found" -ForegroundColor Yellow
    }

    # Delete virtual network
    Write-Host "Step 6/6: Deleting virtual network..." -ForegroundColor Cyan
    if (Test-AzureResource "vnet" $RESOURCE_GROUP $VNET_NAME) {
        Write-Host "Deleting virtual network: $VNET_NAME" -ForegroundColor Cyan
        az network vnet delete --resource-group $RESOURCE_GROUP --name $VNET_NAME
        Write-Host "Virtual network deleted" -ForegroundColor Green
    } else {
        Write-Host "Virtual network $VNET_NAME not found" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Deletion process completed!" -ForegroundColor Green
    Write-Host "Some background deletions may still be in progress." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To check remaining resources with tag ${TAG_KEY}=${TAG_VALUE}:" -ForegroundColor White
    Write-Host "az resource list --resource-group $RESOURCE_GROUP --tag `"${TAG_KEY}=${TAG_VALUE}`" --output table" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To monitor deletion progress:" -ForegroundColor White
    Write-Host "az group show --name $RESOURCE_GROUP --query 'properties.provisioningState'" -ForegroundColor Yellow

    Write-Host ""
    Write-Host "VM deletion process completed!" -ForegroundColor Green

} catch {
    Write-Error "Error occurred during VM deletion: $_"
    Write-Host "Some resources may not have been deleted completely." -ForegroundColor Red
    exit 1
}