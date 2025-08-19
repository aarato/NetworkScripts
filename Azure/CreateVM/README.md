# Azure VM Creation and Deletion Scripts

This directory contains Azure CLI scripts for creating and deleting virtual machines in Azure with configurable parameters.

## Files

- `.env.example` - Template configuration file (copy to `.env` and modify)
- `create-vm.sh` / `create-vm.ps1` - Scripts to create Azure VM and associated resources
- `delete-vm.sh` / `delete-vm.ps1` - Scripts to delete Azure VM and associated resources

## Prerequisites

1. **Azure CLI installed and configured**
   - Linux/Ubuntu: `curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash`
   - Or via apt: `sudo apt-get update && sudo apt-get install azure-cli`
   - Verify installation: `az --version`
2. **Bash shell** (Linux/macOS/WSL/Git Bash on Windows)
3. Valid Azure subscription
4. Existing Azure Resource Group
5. Appropriate permissions to create/delete resources in the resource group
6. Logged in to Azure CLI (see Authentication section below)

## Authentication

**Interactive login (with browser):**
```bash
az login
```

**For SSH/headless environments (service principal):**
```bash
az login --service-principal \
  --username <app-id> \
  --password <password-or-cert> \
  --tenant <tenant-id>
```

**Or using environment variables:**
```bash
export AZURE_CLIENT_ID=<app-id>
export AZURE_CLIENT_SECRET=<password>
export AZURE_TENANT_ID=<tenant-id>
az login --service-principal \
  --username $AZURE_CLIENT_ID \
  --password $AZURE_CLIENT_SECRET \
  --tenant $AZURE_TENANT_ID
```

**Verify authentication:**
```bash
az account show
```

## Usage

### 1. Configure Environment Variables

Copy the example file and edit with your configuration:

```bash
cp .env.example .env
```

Then edit the `.env` file with your desired configuration:

```bash
# Required variables
RESOURCE_GROUP=myResourceGroup
LOCATION=eastus
VNET_ADDRESS_PREFIX=10.0.0.0/16
SUBNET_ADDRESS_PREFIX=10.0.1.0/24
VM_NAME=myVM
VM_SIZE=Standard_B2s
# VM_SIZE=Standard_D2s_v3  # Recommended for Windows (2 vCPU, 8GB RAM)
ADMIN_USERNAME=azureuser

# VM Image - Choose operating system
VM_IMAGE=Ubuntu2204
# VM_IMAGE=Win2022Datacenter  # Windows Server 2022

CREATE_PUBLIC_IP=yes
SSH_KEY_PATH=  # Optional: path to SSH public key
ADMIN_PASSWORD=  # Optional: Windows VM password (SECURITY RISK if stored)
```

**Windows Password Requirements:**
For Windows VMs, passwords must meet Azure/Windows complexity requirements:
- **Length**: 12-72 characters
- **Complexity**: Must contain 3 of the following 4 categories:
  - Lowercase letters (a-z)
  - Uppercase letters (A-Z)
  - Numbers (0-9)
  - Special characters (!, @, #, $, %, ^, &, *, etc.)
- **Restrictions**: 
  - Cannot contain the username or computer name
  - Cannot be common/simple passwords

**Example valid passwords:**
- `SecureAdmin2024!`
- `MyComplexP@ssw0rd`
- `Azure#VM$2024`

**Note:** Resource names are automatically generated based on VM name:
- VNet: `VMNAME-VNET`
- Subnet: `VMNAME-SUBNET`
- NSG: `VMNAME-NSG`
- Public IP: `VMNAME-PIP`
- NIC: `VMNAME-nic`

**Supported VM Images:**
- `Ubuntu2204` - Ubuntu 22.04 LTS (default, recommended for Linux workloads)
- `Ubuntu2004` - Ubuntu 20.04 LTS (long-term support)
- `Win2022Datacenter` - Windows Server 2022
- `CentOS85Gen2` - CentOS 8.5
- `Debian11` - Debian 11
- `RHEL85Gen2` - Red Hat Enterprise Linux 8.5

**Ubuntu-specific notes:**
- Ubuntu images come with `cloud-init` pre-configured for automated setup
- SSH keys are automatically configured for the `ubuntu` user on Ubuntu VMs
- Package manager: `apt` (use `sudo apt update && sudo apt upgrade` after VM creation)

### 2. Create VM

**Linux/Ubuntu/macOS/WSL/Git Bash:**
```bash
chmod +x create-vm.sh
./create-vm.sh
```

**PowerShell:**
```powershell
.\create-vm.ps1
```

**Note for Ubuntu/Linux users:** The bash scripts are designed to work on all Unix-like systems including Ubuntu 18.04+, Debian, CentOS, and macOS.

### 3. Delete VM

**Linux/Ubuntu/macOS/WSL/Git Bash:**
```bash
chmod +x delete-vm.sh
./delete-vm.sh
```

**PowerShell:**
```powershell
.\delete-vm.ps1
```

## Features

- **Configurable VNet range**: Set custom virtual network address space
- **Region selection**: Deploy to any Azure region
- **Operating system choice**: Ubuntu 22.04 or Windows Server 2022
- **Public IP option**: Choose whether to create a public IP
- **Resource tagging**: Tag all resources for easy identification
- **Authentication**: SSH keys for Linux VMs, password authentication for Windows VMs
- **Network security**: Automatically creates NSG with access for SSH, RDP, HTTP, and HTTPS
- **Safe deletion**: Interactive prompts to prevent accidental deletions

## Resources Created

The create script will create (in existing Resource Group):
- Virtual Network with subnet
- Network Security Group with rules for:
  - SSH (port 22) - Linux access
  - RDP (port 3389) - Windows access
  - HTTP (port 80) - Web traffic
  - HTTPS (port 443) - Secure web traffic
  - iPerf3 TCP/UDP (port 5201) - Network performance testing
  - ICMP - Ping and network diagnostics
- Public IP (if enabled)
- Network Interface
- Virtual Machine
- OS Disk

All resources are tagged with VMName=<VM_NAME> for easy identification and management.

**Resource naming convention:**
- VM: `<VM_NAME>`
- VNet: `<VM_NAME>-VNET`
- Subnet: `<VM_NAME>-SUBNET`
- NSG: `<VM_NAME>-NSG`
- Public IP: `<VM_NAME>-PIP`
- NIC: `<VM_NAME>-nic`

## PowerShell Additional Features

**Testing mode:**
```powershell
.\create-vm.ps1 -WhatIf
.\delete-vm.ps1 -WhatIf
```

**Force delete without prompts:**
```powershell
.\delete-vm.ps1 -Force
```

## Notes

- **Resource Group must exist before running scripts**
- The delete script provides options to selectively delete resources
- **Resource Group is never deleted by the scripts**
- Background deletions are used for better performance
- The script validates required environment variables before execution
- Authentication is automatic: SSH keys for Linux, password prompt for Windows
- Windows passwords must meet complexity requirements (see configuration section)
- All resource names are automatically generated with VM name prefix (e.g., MYVM-VNET, MYVM-NSG)
- NSG includes ports for both Linux (SSH) and Windows (RDP) access plus web traffic and ICMP