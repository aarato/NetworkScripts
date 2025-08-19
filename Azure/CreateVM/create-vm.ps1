# Azure VM Creation Script (PowerShell)
# This script creates an Azure VM based on configuration in .env file
#
# Prerequisites:
# 1. Azure CLI must be installed
# 2. Must be logged in to Azure: az login
# 3. Must have an existing Resource Group

param(
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

# Load environment variables
Load-EnvFile

# Validate required variables
$requiredVars = @("RESOURCE_GROUP", "LOCATION", "VNET_ADDRESS_PREFIX", "SUBNET_ADDRESS_PREFIX", "VM_NAME", "VM_SIZE", "ADMIN_USERNAME", "VM_IMAGE", "CREATE_PUBLIC_IP")

foreach ($var in $requiredVars) {
    $value = [Environment]::GetEnvironmentVariable($var)
    if ([string]::IsNullOrEmpty($value)) {
        Write-Error "Error: Required variable $var is not set in .env file"
        exit 1
    }
}

Write-Host "Starting Azure VM creation process..." -ForegroundColor Green

# Get environment variables
$RESOURCE_GROUP = [Environment]::GetEnvironmentVariable("RESOURCE_GROUP")
$LOCATION = [Environment]::GetEnvironmentVariable("LOCATION")
$VNET_ADDRESS_PREFIX = [Environment]::GetEnvironmentVariable("VNET_ADDRESS_PREFIX")
$SUBNET_ADDRESS_PREFIX = [Environment]::GetEnvironmentVariable("SUBNET_ADDRESS_PREFIX")
$VM_NAME = [Environment]::GetEnvironmentVariable("VM_NAME")
$VM_SIZE = [Environment]::GetEnvironmentVariable("VM_SIZE")
$ADMIN_USERNAME = [Environment]::GetEnvironmentVariable("ADMIN_USERNAME")
$VM_IMAGE = [Environment]::GetEnvironmentVariable("VM_IMAGE")
$CREATE_PUBLIC_IP = [Environment]::GetEnvironmentVariable("CREATE_PUBLIC_IP")
$SSH_KEY_PATH = [Environment]::GetEnvironmentVariable("SSH_KEY_PATH")
$ADMIN_PASSWORD = [Environment]::GetEnvironmentVariable("ADMIN_PASSWORD")

# Set tag to VM name
$TAG_KEY = "VMName"
$TAG_VALUE = $VM_NAME

# Set names based on VM name
$VNET_NAME = "$VM_NAME-VNET"
$SUBNET_NAME = "$VM_NAME-SUBNET"
$NSG_NAME = "$VM_NAME-NSG"
$PUBLIC_IP_NAME = "$VM_NAME-PIP"
$NIC_NAME = "$VM_NAME-nic"

if ($WhatIf) {
    Write-Host "WhatIf: Would create the following resources in existing resource group:" -ForegroundColor Yellow
    Write-Host "  Resource Group: $RESOURCE_GROUP (must exist)" -ForegroundColor Yellow
    Write-Host "  Virtual Network: $VNET_NAME" -ForegroundColor Yellow
    Write-Host "  Subnet: $SUBNET_NAME" -ForegroundColor Yellow
    Write-Host "  NSG: $NSG_NAME" -ForegroundColor Yellow
    Write-Host "  VM: $VM_NAME" -ForegroundColor Yellow
    Write-Host "  Location: $LOCATION" -ForegroundColor Yellow
    Write-Host "  Tags: ${TAG_KEY}=${TAG_VALUE}" -ForegroundColor Yellow
    exit 0
}

try {
    # Verify resource group exists
    Write-Host "Verifying resource group exists: $RESOURCE_GROUP" -ForegroundColor Cyan
    az group show --name $RESOURCE_GROUP --output none 2>$null
    if ($LASTEXITCODE -ne 0) { 
        throw "Error: Resource group $RESOURCE_GROUP does not exist. Please create it first." 
    }

    # Create virtual network
    Write-Host "Creating virtual network: $VNET_NAME" -ForegroundColor Cyan
    az network vnet create --resource-group $RESOURCE_GROUP --name $VNET_NAME --address-prefix $VNET_ADDRESS_PREFIX --subnet-name $SUBNET_NAME --subnet-prefix $SUBNET_ADDRESS_PREFIX --tags "$TAG_KEY=$TAG_VALUE"
    if ($LASTEXITCODE -ne 0) { throw "Failed to create virtual network" }

    # Create network security group
    Write-Host "Creating network security group: $NSG_NAME" -ForegroundColor Cyan
    az network nsg create --resource-group $RESOURCE_GROUP --name $NSG_NAME --tags "$TAG_KEY=$TAG_VALUE"
    if ($LASTEXITCODE -ne 0) { throw "Failed to create network security group" }

    # Add security rules to NSG
    Write-Host "Adding security rules to network security group" -ForegroundColor Cyan
    
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name SSH --protocol tcp --priority 1001 --destination-port-range 22 --access allow
    if ($LASTEXITCODE -ne 0) { throw "Failed to create SSH rule" }
    
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name RDP --protocol tcp --priority 1002 --destination-port-range 3389 --access allow
    if ($LASTEXITCODE -ne 0) { throw "Failed to create RDP rule" }
    
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name HTTP --protocol tcp --priority 1003 --destination-port-range 80 --access allow
    if ($LASTEXITCODE -ne 0) { throw "Failed to create HTTP rule" }
    
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name HTTPS --protocol tcp --priority 1004 --destination-port-range 443 --access allow
    if ($LASTEXITCODE -ne 0) { throw "Failed to create HTTPS rule" }
    
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name iPerf3-TCP --protocol tcp --priority 1005 --destination-port-range 5201 --access allow
    if ($LASTEXITCODE -ne 0) { throw "Failed to create iPerf3-TCP rule" }
    
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name iPerf3-UDP --protocol udp --priority 1006 --destination-port-range 5201 --access allow
    if ($LASTEXITCODE -ne 0) { throw "Failed to create iPerf3-UDP rule" }
    
    az network nsg rule create --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name ICMP --protocol icmp --priority 1007 --destination-port-range "*" --access allow
    if ($LASTEXITCODE -ne 0) { throw "Failed to create ICMP rule" }

    # Create public IP if requested
    $publicIpParam = ""
    if ($CREATE_PUBLIC_IP -eq "yes") {
        Write-Host "Creating public IP: $PUBLIC_IP_NAME" -ForegroundColor Cyan
        az network public-ip create --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME --allocation-method Static --tags "$TAG_KEY=$TAG_VALUE"
        if ($LASTEXITCODE -ne 0) { throw "Failed to create public IP" }
        $publicIpParam = "--public-ip-address $PUBLIC_IP_NAME"
    }

    # Create network interface
    Write-Host "Creating network interface" -ForegroundColor Cyan
    $nicCmd = "az network nic create --resource-group $RESOURCE_GROUP --name $NIC_NAME --vnet-name $VNET_NAME --subnet $SUBNET_NAME --network-security-group $NSG_NAME $publicIpParam --tags `"$TAG_KEY=$TAG_VALUE`""
    Invoke-Expression $nicCmd
    if ($LASTEXITCODE -ne 0) { throw "Failed to create network interface" }

    # Prepare VM creation command
    $vmCreateCmd = "az vm create --resource-group $RESOURCE_GROUP --name $VM_NAME --nics $NIC_NAME --image $VM_IMAGE --size $VM_SIZE --admin-username $ADMIN_USERNAME --tags `"$TAG_KEY=$TAG_VALUE`""

    # Add authentication method based on OS
    if ($VM_IMAGE -like "*Win*") {
        # Windows VM - use password authentication
        if (![string]::IsNullOrEmpty($ADMIN_PASSWORD)) {
            Write-Host "Windows VM detected - using password from .env file" -ForegroundColor Cyan
            $vmCreateCmd += " --authentication-type password --admin-password `"$ADMIN_PASSWORD`""
        } else {
            Write-Host "Windows VM detected - password authentication will be prompted" -ForegroundColor Cyan
            $vmCreateCmd += " --authentication-type password"
        }
    } else {
        # Linux VM - use SSH key authentication
        if (![string]::IsNullOrEmpty($SSH_KEY_PATH) -and (Test-Path $SSH_KEY_PATH)) {
            Write-Host "Using SSH key for authentication: $SSH_KEY_PATH" -ForegroundColor Cyan
            $vmCreateCmd += " --ssh-key-values $SSH_KEY_PATH"
        } else {
            Write-Host "Generating SSH keys for Linux VM" -ForegroundColor Cyan
            $vmCreateCmd += " --generate-ssh-keys"
        }
    }

    # Create the VM
    Write-Host "Creating virtual machine: $VM_NAME" -ForegroundColor Cyan
    Invoke-Expression $vmCreateCmd
    if ($LASTEXITCODE -ne 0) { throw "Failed to create virtual machine" }

    Write-Host ""
    Write-Host "VM creation completed successfully!" -ForegroundColor Green
    Write-Host "Resource Group: $RESOURCE_GROUP" -ForegroundColor White
    Write-Host "VM Name: $VM_NAME" -ForegroundColor White
    Write-Host "Location: $LOCATION" -ForegroundColor White
    Write-Host "Tags: ${TAG_KEY}=${TAG_VALUE}" -ForegroundColor White

    # Display connection information
    if ($CREATE_PUBLIC_IP -eq "yes") {
        $publicIp = az network public-ip show --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME --query ipAddress --output tsv
        Write-Host "Public IP: $publicIp" -ForegroundColor White
        Write-Host "SSH Command: ssh $ADMIN_USERNAME@$publicIp" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "To view all resources created with tag ${TAG_KEY}=${TAG_VALUE}:" -ForegroundColor White
    Write-Host "az resource list --tag `"${TAG_KEY}=${TAG_VALUE}`" --output table" -ForegroundColor Yellow

} catch {
    Write-Error "Error occurred during VM creation: $_"
    Write-Host "You may need to clean up partially created resources." -ForegroundColor Red
    exit 1
}