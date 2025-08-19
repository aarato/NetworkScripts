#!/bin/bash

# Azure VM Deletion Script
# This script deletes Azure VM and associated resources based on configuration in .env file
#
# Prerequisites:
# 1. Azure CLI must be installed
# 2. Must be logged in to Azure: az login (interactive) or az login --service-principal (automated)
# 3. Must have an existing Resource Group

set -e

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Error: .env file not found. Please create .env file with required variables."
    exit 1
fi

# Validate required variables
required_vars=("RESOURCE_GROUP" "VM_NAME")

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is not set in .env file"
        exit 1
    fi
done

# Set tag to VM name
TAG_KEY="VMName"
TAG_VALUE="$VM_NAME"

# Set names based on VM name
VNET_NAME="$VM_NAME-VNET"
SUBNET_NAME="$VM_NAME-SUBNET"
NSG_NAME="$VM_NAME-NSG"
PUBLIC_IP_NAME="$VM_NAME-PIP"

echo "Starting Azure VM deletion process..."
echo "This will delete VM: $VM_NAME and associated resources"
echo ""

# Ask for confirmation
read -p "Are you sure you want to delete the VM and ALL associated resources (VM, NIC, Public IP, Disk, NSG, VNet)? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Deletion cancelled."
    exit 0
fi

echo ""
echo "Proceeding with deletion..."

# Check if VM exists and delete it
echo "Step 1/6: Checking if VM exists..."
if ! az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME &> /dev/null; then
    echo "VM $VM_NAME not found in resource group $RESOURCE_GROUP"
else
    echo "Deleting virtual machine: $VM_NAME (this may take a few minutes)"
    az vm delete \
        --resource-group $RESOURCE_GROUP \
        --name $VM_NAME \
        --yes
    echo "VM deletion completed"
fi

# Delete network interface
NIC_NAME="${VM_NAME}-nic"
echo "Step 2/6: Deleting network interface..."
if az network nic show --resource-group $RESOURCE_GROUP --name $NIC_NAME &> /dev/null; then
    echo "Deleting network interface: $NIC_NAME"
    az network nic delete \
        --resource-group $RESOURCE_GROUP \
        --name $NIC_NAME
    echo "Network interface deleted"
else
    echo "Network interface $NIC_NAME not found"
fi

# Delete public IP if it exists
echo "Step 3/6: Deleting public IP..."
if [ "$CREATE_PUBLIC_IP" = "yes" ] && [ -n "$PUBLIC_IP_NAME" ]; then
    if az network public-ip show --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME &> /dev/null; then
        echo "Deleting public IP: $PUBLIC_IP_NAME"
        az network public-ip delete \
            --resource-group $RESOURCE_GROUP \
            --name $PUBLIC_IP_NAME
        echo "Public IP deleted"
    else
        echo "Public IP $PUBLIC_IP_NAME not found"
    fi
else
    echo "No public IP to delete"
fi

# Delete OS disk
echo "Step 4/6: Deleting OS disk..."

# Try multiple methods to find the OS disk
ACTUAL_DISK=""

# Method 1: Look for disk with VM name tag
ACTUAL_DISK=$(az disk list --resource-group $RESOURCE_GROUP --query "[?tags.$TAG_KEY=='$TAG_VALUE'].name" --output tsv 2>/dev/null || true)

# Method 2: Look for disk containing VM name
if [ -z "$ACTUAL_DISK" ]; then
    ACTUAL_DISK=$(az disk list --resource-group $RESOURCE_GROUP --query "[?contains(name, '$VM_NAME')].name" --output tsv 2>/dev/null || true)
fi

# Method 3: Look for orphaned OS disks (no attached VM)
if [ -z "$ACTUAL_DISK" ]; then
    ACTUAL_DISK=$(az disk list --resource-group $RESOURCE_GROUP --query "[?diskState=='Unattached' && contains(name, 'OsDisk')].name" --output tsv 2>/dev/null | head -1 || true)
fi

if [ -n "$ACTUAL_DISK" ]; then
    echo "Deleting OS disk: $ACTUAL_DISK"
    az disk delete \
        --resource-group $RESOURCE_GROUP \
        --name $ACTUAL_DISK \
        --yes
    echo "OS disk deleted"
else
    echo "No OS disk found for VM (may have been auto-deleted)"
fi

# Delete network security group
echo "Step 5/6: Deleting network security group..."
if az network nsg show --resource-group $RESOURCE_GROUP --name $NSG_NAME &> /dev/null; then
    echo "Deleting network security group: $NSG_NAME"
    az network nsg delete \
        --resource-group $RESOURCE_GROUP \
        --name $NSG_NAME
    echo "Network security group deleted"
else
    echo "Network security group $NSG_NAME not found"
fi

# Delete virtual network
echo "Step 6/6: Deleting virtual network..."
if az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME &> /dev/null; then
    echo "Deleting virtual network: $VNET_NAME"
    az network vnet delete \
        --resource-group $RESOURCE_GROUP \
        --name $VNET_NAME
    echo "Virtual network deleted"
else
    echo "Virtual network $VNET_NAME not found"
fi

echo ""
echo "Deletion process completed!"
echo "Some background deletions may still be in progress."
echo ""
echo "To check remaining resources with tag $TAG_KEY=$TAG_VALUE:"
echo "az resource list --resource-group $RESOURCE_GROUP --tag $TAG_KEY=\"$TAG_VALUE\" --output table"
echo ""
echo "To monitor deletion progress:"
echo "az group show --name $RESOURCE_GROUP --query 'properties.provisioningState'"

echo ""
echo "VM deletion process completed!"