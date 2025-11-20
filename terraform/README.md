# Standalone DNS Lab Terraform Configuration

## Overview

This directory contains the Terraform configuration for the standalone DNS lab. The configuration files are symlinked to the base lab to avoid duplication while maintaining a simplified standalone experience.

## Structure

```
terraform/
├── README.md                    # This file
├── main.tf                      # Symlink to ../../base_lab/main.tf
├── variables.tf                 # Symlink to ../../base_lab/variables.tf
├── outputs.tf                   # Symlink to ../../base_lab/outputs.tf
├── versions.tf                  # Symlink to ../../base_lab/versions.tf
├── dns-server-init.sh          # Symlink to ../../base_lab/dns-server-init.sh
├── terraform.tfvars.example    # Symlink to ../../base_lab/terraform.tfvars.example
└── terraform.tfvars            # Created by setup.sh (not in version control)
```

## Quick Start

### 1. Run Setup Script (Recommended)

The easiest way to get started:

```bash
cd labs/dns-standalone
./setup.sh
```

This will:
- Check prerequisites
- Authenticate to Azure
- Generate SSH key (if needed)
- Create terraform.tfvars with your SSH public key
- Initialize Terraform

### 2. Manual Setup (Alternative)

If you prefer manual setup:

```bash
# Navigate to this directory
cd labs/dns-standalone/terraform

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars
# - Add your SSH public key
# - Change key_vault_name (must be globally unique)
# - Optionally customize resource names
nano terraform.tfvars

# Initialize Terraform
terraform init
```

## Configuration

### Required Variables

Edit `terraform.tfvars` and set:

```hcl
# SSH public key (REQUIRED)
admin_ssh_key = "ssh-rsa AAAA... your-key-here"

# Key Vault name (must be globally unique)
key_vault_name = "lab-kv-YOUR-UNIQUE-ID"

# Admin password for VMs
admin_password = "ChangeMe!2025"

# Lab scenario (for DNS exercises)
lab_scenario = "base"  # Options: base, dns_exercise1, dns_exercise2, dns_exercise3
```

### Optional Customization

You can also customize:
- Resource group names
- VNet address spaces
- Subnet prefixes
- VM sizes
- Azure regions

See `terraform.tfvars.example` for all available options.

## Usage

### Deploy Infrastructure

```bash
# Preview changes
terraform plan

# Deploy (takes 5-10 minutes)
terraform apply

# Auto-approve (skip confirmation)
terraform apply -auto-approve
```

### Switch Lab Scenarios

```bash
# Base configuration (everything working)
terraform apply -var="lab_scenario=base"

# Exercise 1: Wrong DNS A record
terraform apply -var="lab_scenario=dns_exercise1"

# Exercise 2: Missing VNet links
terraform apply -var="lab_scenario=dns_exercise2"

# Exercise 3: Custom DNS misconfiguration
terraform apply -var="lab_scenario=dns_exercise3"
```

### Get Outputs

```bash
# Show all outputs
terraform output

# Get specific output
terraform output -raw agent_vm_public_ip
terraform output -raw key_vault_name
terraform output -raw key_vault_private_ip

# Copy output to clipboard (Linux)
terraform output -raw agent_vm_public_ip | xclip -selection clipboard

# Copy output to clipboard (Mac)
terraform output -raw agent_vm_public_ip | pbcopy
```

### Destroy Resources

```bash
# Preview what will be destroyed
terraform plan -destroy

# Destroy everything
terraform destroy

# Auto-approve destruction
terraform destroy -auto-approve
```

## What Gets Created

### Resource Groups
- `tf-agent-lab-rg` (agent environment)
- `tf-connect-lab-rg` (connectivity environment)

### Network Resources
- 2 Virtual Networks (agent-vnet, connect-vnet)
- VNet peering between them
- 3 Subnets
- Network security groups

### Compute Resources
- 1 Linux VM (Ubuntu, Standard_B1ms) - for testing/agent
- 1 Custom DNS server VM (only in dns_exercise3)

### Key Vault Resources
- 1 Azure Key Vault
- 1 Private Endpoint for Key Vault
- 1 Private DNS Zone (privatelink.vaultcore.azure.net)
- VNet links to Private DNS zone

## Cost Estimate

**Approximate costs (per day, 8 hours runtime):**
- Linux VM (B1ms): ~$1.50
- Virtual Networks: ~$0.10
- Key Vault: ~$0.05
- Private Endpoint: ~$0.05
- DNS Server VM (exercise 3 only): ~$1.50

**Total:** ~$2-3.50 per day

**Cost Saving Tips:**
```bash
# Deallocate VMs when not in use (keeps infrastructure)
terraform destroy -target=azurerm_linux_virtual_machine.agent_vm

# Or stop via Azure CLI
az vm deallocate --resource-group tf-agent-lab-rg --name agent-vm

# Destroy everything when done for the day
terraform destroy -auto-approve
```

## Troubleshooting

### "Key Vault name already exists"

Key Vault names are globally unique. Edit `terraform.tfvars`:

```hcl
key_vault_name = "lab-kv-YOUR-INITIALS-$(date +%s)"
```

Or use a random suffix:
```bash
# Generate unique name
echo "lab-kv-$(openssl rand -hex 4)"
```

### "Cannot create public IP"

If you hit Azure quota limits:
- Check your subscription quotas
- Request quota increase
- Use a different region

```bash
# Check quotas
az vm list-usage --location westus2 --output table
```

### "Terraform state locked"

If terraform operations fail midway:

```bash
# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### "SSH key format invalid"

Ensure your SSH key is RSA format:

```bash
# Regenerate key
ssh-keygen -t rsa -b 4096 -f ~/.ssh/terraform_lab_key -N ""

# View key to copy
cat ~/.ssh/terraform_lab_key.pub
```

## Advanced Usage

### Remote State (Multi-User Scenarios)

For teams or persistent state:

1. Create Azure Storage account:
```bash
az storage account create \
  --name tfstatednslab \
  --resource-group terraform-state-rg \
  --location westus2 \
  --sku Standard_LRS
```

2. Create container:
```bash
az storage container create \
  --name tfstate \
  --account-name tfstatednslab
```

3. Configure backend in `versions.tf`:
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatednslab"
    container_name       = "tfstate"
    key                  = "dns-lab.tfstate"
  }
}
```

4. Reinitialize:
```bash
terraform init -reconfigure
```

### Import Existing Resources

If you have existing resources:

```bash
# Import resource group
terraform import azurerm_resource_group.agent_rg /subscriptions/SUBSCRIPTION_ID/resourceGroups/tf-agent-lab-rg

# Import VM
terraform import azurerm_linux_virtual_machine.agent_vm /subscriptions/SUBSCRIPTION_ID/resourceGroups/tf-agent-lab-rg/providers/Microsoft.Compute/virtualMachines/agent-vm
```

## Next Steps

After deploying infrastructure:

**Path B (Direct Testing):**
1. See [../docs/PATH_B_DIRECT.md](../docs/PATH_B_DIRECT.md)
2. SSH to VM and start troubleshooting
3. Work through DNS exercises

**Path A (Pipeline Testing):**
1. See [../docs/PATH_A_WITH_ADO.md](../docs/PATH_A_WITH_ADO.md)
2. Register agents on VMs
3. Create service connections
4. Run pipeline tests

## Documentation

- **Main README:** [../README.md](../README.md)
- **Resources Guide:** [../docs/RESOURCES.md](../docs/RESOURCES.md)
- **Troubleshooting:** [../docs/TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md)

## Support

- GitHub Issues: Report bugs or request features
- Copilot Chat: Use `/dns-troubleshoot` for AI assistance
