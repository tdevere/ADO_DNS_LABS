#!/bin/bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo "=================================================="
echo "   DNS Lab Infrastructure Health Check"
echo "=================================================="
echo ""

# Check Terraform state
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}✗ Terraform state not found${NC}"
    echo "  Run: ./setup.sh"
    exit 1
fi
echo -e "${GREEN}✓ Terraform state exists${NC}"

# Get resource names
RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "")
VM_NAME=$(terraform output -raw vm_name 2>/dev/null || echo "")
VM_PUBLIC_IP=$(terraform output -raw vm_public_ip 2>/dev/null || echo "")
ZONE_NAME="privatelink.vaultcore.azure.net"

if [ -z "$RG_NAME" ]; then
    echo -e "${RED}✗ Cannot retrieve resource group from Terraform${NC}"
    exit 1
fi

# Check Resource Group
if az group show --name "$RG_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ Resource group exists: $RG_NAME${NC}"
else
    echo -e "${RED}✗ Resource group not found: $RG_NAME${NC}"
    exit 1
fi

# Check Key Vault
if [ -n "$KV_NAME" ]; then
    if az keyvault show --name "$KV_NAME" &>/dev/null; then
        echo -e "${GREEN}✓ Key Vault exists: $KV_NAME${NC}"
        
        # Check public access
        PUBLIC_ACCESS=$(az keyvault show --name "$KV_NAME" --query "properties.publicNetworkAccess" -o tsv)
        if [ "$PUBLIC_ACCESS" == "Enabled" ]; then
            echo -e "${GREEN}  ✓ Public network access: Enabled${NC}"
        else
            echo -e "${YELLOW}  ⚠ Public network access: Disabled (may block Terraform)${NC}"
        fi
    else
        echo -e "${RED}✗ Key Vault not found: $KV_NAME${NC}"
    fi
fi

# Check DNS Zone
if az network private-dns zone show --resource-group "$RG_NAME" --name "$ZONE_NAME" &>/dev/null; then
    echo -e "${GREEN}✓ Private DNS Zone exists: $ZONE_NAME${NC}"
    
    # Check A record
    if [ -n "$KV_NAME" ]; then
        CURRENT_IP=$(az network private-dns record-set a show \
            --resource-group "$RG_NAME" \
            --zone-name "$ZONE_NAME" \
            --name "$KV_NAME" \
            --query "aRecords[0].ipv4Address" -o tsv 2>/dev/null || echo "")
        
        EXPECTED_IP=$(terraform output -raw key_vault_private_ip 2>/dev/null || echo "10.1.2.5")
        
        if [ "$CURRENT_IP" == "$EXPECTED_IP" ]; then
            echo -e "${GREEN}  ✓ DNS A record: $CURRENT_IP (correct)${NC}"
        elif [ -n "$CURRENT_IP" ]; then
            echo -e "${YELLOW}  ⚠ DNS A record: $CURRENT_IP (expected: $EXPECTED_IP) - Lab may be broken${NC}"
        else
            echo -e "${RED}  ✗ DNS A record not found${NC}"
        fi
    fi
    
    # Check VNet link
    VNET_LINK=$(az network private-dns link vnet list \
        --resource-group "$RG_NAME" \
        --zone-name "$ZONE_NAME" \
        --query "[0].name" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$VNET_LINK" ]; then
        echo -e "${GREEN}  ✓ VNet link exists: $VNET_LINK${NC}"
    else
        echo -e "${YELLOW}  ⚠ VNet link not found - Lab 2 (old version) may be active${NC}"
    fi
else
    echo -e "${RED}✗ Private DNS Zone not found${NC}"
fi

# Check VM
if [ -n "$VM_NAME" ]; then
    VM_STATE=$(az vm get-instance-view \
        --resource-group "$RG_NAME" \
        --name "$VM_NAME" \
        --query "instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus" -o tsv 2>/dev/null || echo "")
    
    if [ "$VM_STATE" == "VM running" ]; then
        echo -e "${GREEN}✓ VM is running: $VM_NAME${NC}"
        
        # Check SSH connectivity
        if [ -n "$VM_PUBLIC_IP" ] && [ -f "$HOME/.ssh/terraform_lab_key" ]; then
            if timeout 5 ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                -i "$HOME/.ssh/terraform_lab_key" azureuser@"$VM_PUBLIC_IP" "echo 'SSH OK'" &>/dev/null; then
                echo -e "${GREEN}  ✓ SSH connectivity: OK${NC}"
            else
                echo -e "${YELLOW}  ⚠ SSH connectivity: Failed (check NSG rules)${NC}"
            fi
        fi
    elif [ -n "$VM_STATE" ]; then
        echo -e "${YELLOW}⚠ VM state: $VM_STATE${NC}"
    else
        echo -e "${RED}✗ VM not found: $VM_NAME${NC}"
    fi
fi

# Check NSG rules
NSG_SSH_RULE=$(az network nsg rule show \
    --resource-group "$RG_NAME" \
    --nsg-name "nsg-agent-vm" \
    --name "SSH" \
    --query "name" -o tsv 2>/dev/null || echo "")

if [ -n "$NSG_SSH_RULE" ]; then
    echo -e "${GREEN}✓ NSG SSH rule exists${NC}"
else
    echo -e "${YELLOW}⚠ NSG SSH rule missing (drift detected)${NC}"
    echo -e "${YELLOW}  Fix: terraform apply -auto-approve${NC}"
fi

echo ""
echo "=================================================="
echo "Health check complete!"
echo "=================================================="
