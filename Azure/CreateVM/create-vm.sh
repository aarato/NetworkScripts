#!/bin/bash

# Azure VM Creation Script
# This script creates an Azure VM based on configuration in .env file
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
required_vars=("RESOURCE_GROUP" "LOCATION" "VNET_ADDRESS_PREFIX" "SUBNET_ADDRESS_PREFIX" "VM_NAME" "VM_SIZE" "ADMIN_USERNAME" "VM_IMAGE" "CREATE_PUBLIC_IP")

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo "Error: Required variable $var is not set in .env file"
        exit 1
    fi
done

echo "Starting Azure VM creation process..."

# Set tag to VM name
TAG_KEY="VMName"
TAG_VALUE="$VM_NAME"

# Set names based on VM name
VNET_NAME="$VM_NAME-VNET"
SUBNET_NAME="$VM_NAME-SUBNET"
NSG_NAME="$VM_NAME-NSG"
PUBLIC_IP_NAME="$VM_NAME-PIP"

# Verify resource group exists
echo "Verifying resource group exists: $RESOURCE_GROUP"
if ! az group show --name $RESOURCE_GROUP &> /dev/null; then
    echo "Error: Resource group $RESOURCE_GROUP does not exist. Please create it first."
    exit 1
fi

# Create virtual network
echo "Creating virtual network: $VNET_NAME"
az network vnet create \
    --resource-group $RESOURCE_GROUP \
    --name $VNET_NAME \
    --address-prefix $VNET_ADDRESS_PREFIX \
    --subnet-name $SUBNET_NAME \
    --subnet-prefix $SUBNET_ADDRESS_PREFIX \
    --tags $TAG_KEY="$TAG_VALUE"

# Create network security group
echo "Creating network security group: $NSG_NAME"
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --name $NSG_NAME \
    --tags $TAG_KEY="$TAG_VALUE"

# Add security rules to NSG
echo "Adding security rules to network security group"
az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name $NSG_NAME \
    --name SSH \
    --protocol tcp \
    --priority 1001 \
    --destination-port-range 22 \
    --access allow

az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name $NSG_NAME \
    --name RDP \
    --protocol tcp \
    --priority 1002 \
    --destination-port-range 3389 \
    --access allow

az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name $NSG_NAME \
    --name HTTP \
    --protocol tcp \
    --priority 1003 \
    --destination-port-range 80 \
    --access allow

az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name $NSG_NAME \
    --name HTTPS \
    --protocol tcp \
    --priority 1004 \
    --destination-port-range 443 \
    --access allow

az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name $NSG_NAME \
    --name iPerf3-TCP \
    --protocol tcp \
    --priority 1005 \
    --destination-port-range 5201 \
    --access allow

az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name $NSG_NAME \
    --name iPerf3-UDP \
    --protocol udp \
    --priority 1006 \
    --destination-port-range 5201 \
    --access allow

az network nsg rule create \
    --resource-group $RESOURCE_GROUP \
    --nsg-name $NSG_NAME \
    --name ICMP \
    --protocol icmp \
    --priority 1007 \
    --destination-port-range "*" \
    --access allow

# Create public IP if requested
PUBLIC_IP_PARAM=""
if [ "$CREATE_PUBLIC_IP" = "yes" ]; then
    echo "Creating public IP: $PUBLIC_IP_NAME"
    az network public-ip create \
        --resource-group $RESOURCE_GROUP \
        --name $PUBLIC_IP_NAME \
        --allocation-method Static \
        --tags $TAG_KEY="$TAG_VALUE"
    PUBLIC_IP_PARAM="--public-ip-address $PUBLIC_IP_NAME"
fi

# Create network interface
echo "Creating network interface"
NIC_NAME="${VM_NAME}-nic"
az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name $NIC_NAME \
    --vnet-name $VNET_NAME \
    --subnet $SUBNET_NAME \
    --network-security-group $NSG_NAME \
    $PUBLIC_IP_PARAM \
    --tags $TAG_KEY="$TAG_VALUE"

# Prepare VM creation command
VM_CREATE_CMD="az vm create \
    --resource-group $RESOURCE_GROUP \
    --name $VM_NAME \
    --nics $NIC_NAME \
    --image $VM_IMAGE \
    --size $VM_SIZE \
    --admin-username $ADMIN_USERNAME \
    --tags $TAG_KEY=\"$TAG_VALUE\""

# Add authentication method based on OS
if [[ "$VM_IMAGE" == *"Win"* ]]; then
    # Windows VM - use password authentication
    if [ -n "$ADMIN_PASSWORD" ]; then
        echo "Windows VM detected - using password from .env file"
        VM_CREATE_CMD="$VM_CREATE_CMD --authentication-type password --admin-password $ADMIN_PASSWORD"
    else
        echo "Windows VM detected - password authentication will be prompted"
        VM_CREATE_CMD="$VM_CREATE_CMD --authentication-type password"
    fi
else
    # Linux VM - use SSH key authentication
    if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
        echo "Using SSH key for authentication: $SSH_KEY_PATH"
        VM_CREATE_CMD="$VM_CREATE_CMD --ssh-key-values $SSH_KEY_PATH"
    else
        echo "Generating SSH keys for Linux VM"
        VM_CREATE_CMD="$VM_CREATE_CMD --generate-ssh-keys"
    fi
fi

# Create the VM
echo "Creating virtual machine: $VM_NAME"
eval $VM_CREATE_CMD

echo ""
echo "VM creation completed successfully!"
echo "Resource Group: $RESOURCE_GROUP"
echo "VM Name: $VM_NAME"
echo "Location: $LOCATION"
echo "Tags: $TAG_KEY=$TAG_VALUE"

# Display connection information
if [ "$CREATE_PUBLIC_IP" = "yes" ]; then
    PUBLIC_IP=$(az network public-ip show --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME --query ipAddress --output tsv)
    echo "Public IP: $PUBLIC_IP"
    echo "SSH Command: ssh $ADMIN_USERNAME@$PUBLIC_IP"
fi

echo ""
echo "To view all resources created with tag $TAG_KEY=$TAG_VALUE:"
echo "az resource list --tag $TAG_KEY=\"$TAG_VALUE\" --output table"