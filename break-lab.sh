#!/bin/bash
set -euo pipefail

# Debug mode (enabled by default)
DEBUG=true
if [[ "$1" == "--quiet" ]]; then
    DEBUG=false
    shift
fi

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

LAB_ID=${1:-}

if [[ "$DEBUG" == "true" ]]; then
    echo -e "${CYAN}🐛 Verbose mode enabled (use --quiet to suppress)${NC}"
fi

if [ -z "$LAB_ID" ]; then
    echo "Usage: ./break-lab.sh <lab1|lab2|lab3>"; exit 1
fi

# Check if Terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}❌ ERROR: No Terraform state found.${NC}"
    echo -e "${YELLOW}Did you run './setup.sh' first?${NC}"
    echo ""
    echo "To deploy the lab infrastructure, run:"
    echo "  ./setup.sh"
    exit 1
fi

# Check if resources are actually deployed
RG_NAME=$(terraform output -raw resource_group_name || echo "")
if [ -z "$RG_NAME" ]; then
    echo -e "${RED}❌ ERROR: Could not retrieve resource group from Terraform output.${NC}"
    echo -e "${YELLOW}The infrastructure may not be fully deployed.${NC}"
    echo ""
    echo "To deploy the lab infrastructure, run:"
    echo "  ./setup.sh"
    exit 1
fi

# Verify the resource group actually exists in Azure
if [[ "$DEBUG" == "true" ]]; then
    echo -e "${CYAN}Checking: az group show --name '$RG_NAME'${NC}"
fi
az group show --name "$RG_NAME" > /dev/null || RG_EXISTS=false

if [[ "${RG_EXISTS:-true}" == "false" ]]; then
    echo -e "${RED}❌ ERROR: Resource group '$RG_NAME' does not exist in Azure.${NC}"
    echo -e "${YELLOW}The Terraform state is stale or infrastructure was manually deleted.${NC}"
    echo ""
    echo "To redeploy, run:"
    echo "  ./setup.sh"
    exit 1
fi

echo -e "${GREEN}✓ Infrastructure verified${NC}"
echo "=================================================="
echo "   DNS Troubleshooting Lab - Break Scenario: $LAB_ID"
echo "================================================="

# Get other resource names from Terraform
KV_NAME=$(terraform output -raw key_vault_name || echo "")

# Static names from Terraform config (no suffixes in these resources)
ZONE_NAME="privatelink.vaultcore.azure.net"
VNET_NAME="vnet-dns-lab"
VNET_LINK_NAME="link-vnet-dns-lab"

case $LAB_ID in
    lab1)
        echo "Injecting Lab 1 fault..."
        
        # Check if lab is already broken
        CURRENT_DNS_IP=$(az network private-dns record-set a show \
            --resource-group "$RG_NAME" \
            --zone-name "$ZONE_NAME" \
            --name "$KV_NAME" \
            --query "aRecords[0].ipv4Address" -o tsv 2>/dev/null || echo "")
        
        if [[ "$CURRENT_DNS_IP" == "10.1.2.50" ]]; then
            echo "⚠️  Lab 1 is already broken (DNS points to 10.1.2.50)"
            echo "→  Run './fix-lab.sh lab1' first to restore it, then break it again"
            exit 0
        fi
        
        echo "  >> Modifying DNS configuration..."
        az network private-dns record-set a update \
            --resource-group "$RG_NAME" \
            --zone-name "$ZONE_NAME" \
            --name "$KV_NAME" \
            --set 'aRecords[0].ipv4Address=10.1.2.50' \
            --output none || {
                # If update fails, recreate
                echo "  >> Record doesn't exist, creating..."
                az network private-dns record-set a delete --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$KV_NAME" --yes --output none || true
                az network private-dns record-set a create --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$KV_NAME" --output none
                az network private-dns record-set a add-record --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --record-set-name "$KV_NAME" --ipv4-address 10.1.2.50 --output none
            }
        echo "  [OK] DNS configuration modified"
        
        # Update Key Vault secret with error message
        if [[ "$DEBUG" == "true" ]]; then
            az keyvault secret set --vault-name "$KV_NAME" --name "AppMessage" \
                --value "ERROR: Cannot reach Key Vault. Check your DNS configuration."
        else
            az keyvault secret set --vault-name "$KV_NAME" --name "AppMessage" \
                --value "ERROR: Cannot reach Key Vault. Check your DNS configuration." > /dev/null
        fi
        
        # Restart the agent to pick up DNS changes
        echo "  >> Restarting agent VM..."
        VM_NAME=$(terraform output -raw vm_name)
        if [ -n "$VM_NAME" ]; then
            if [[ "$DEBUG" == "true" ]]; then
                az vm restart --resource-group "$RG_NAME" --name "$VM_NAME"
            else
                az vm restart --resource-group "$RG_NAME" --name "$VM_NAME" > /dev/null
            fi
            echo "  [OK] Agent VM restarted"
        fi
        
        echo ""
        echo "[SUCCESS] Lab 1 fault injected. Begin troubleshooting."
        echo "Hint: Run the pipeline and observe the failure, then use DNS diagnostic tools."
        ;;
    lab2)
        echo "Injecting Lab 2 fault (Stale DNS Cache)..."
        
        # Simulate a Private Endpoint recreation scenario:
        # 1. Change the DNS A record to a NEW (invalid) IP to simulate endpoint recreation
        # 2. Pre-populate the agent's DNS cache with the OLD (correct) IP so it's stale
        
        # Get current correct IP
        CURRENT_IP=$(terraform output -raw key_vault_private_ip || echo "10.1.2.5")
        NEW_IP="10.1.2.50"  # Simulated new IP
        
        echo "  >> Modifying DNS records..."
        # Update DNS A record to new IP
        az network private-dns record-set a update \
            --resource-group "$RG_NAME" \
            --zone-name "$ZONE_NAME" \
            --name "$KV_NAME" \
            --set "aRecords[0].ipv4Address=$NEW_IP" \
            --output none || {
                echo "  >> Record doesn't exist, creating..."
                az network private-dns record-set a delete --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$KV_NAME" --yes --output none || true
                az network private-dns record-set a create --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$KV_NAME" --output none
                az network private-dns record-set a add-record --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --record-set-name "$KV_NAME" --ipv4-address "$NEW_IP" --output none
            }
        echo "  [OK] DNS records modified"
        
        echo "  >> Configuring agent environment..."
        # SSH to the VM and populate its DNS cache with the OLD IP
        VM_NAME=$(terraform output -raw vm_name)
        VM_PUBLIC_IP=$(terraform output -raw vm_public_ip)
        SSH_KEY="$HOME/.ssh/terraform_lab_key"
        
        if [ ! -f "$SSH_KEY" ]; then
            echo "  ⚠ SSH key not found at $SSH_KEY"
            echo "  → Run: ./scripts/generate-ssh-key.sh"
            echo "  → Skipping cache configuration (not critical)"
        elif [ -n "$VM_NAME" ] && [ -n "$VM_PUBLIC_IP" ]; then
            # Ensure VM is running before SSH
            echo "  → Checking VM state..."
            VM_STATE=$(az vm get-instance-view --resource-group "$RG_NAME" --name "$VM_NAME" --query "instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus" -o tsv)
            if [[ "$VM_STATE" != "VM running" ]]; then
                echo "  → VM not running, starting..."
                az vm start --resource-group "$RG_NAME" --name "$VM_NAME" --no-wait
                sleep 30  # Wait for VM to boot
            fi
            
            # Add stale entry to /etc/hosts to force cache (systemd-resolved will use this)
            echo "  → Injecting stale DNS entry..."
            if [[ "$DEBUG" == "true" ]]; then
                echo -e "${CYAN}Running: ssh azureuser@$VM_PUBLIC_IP 'configure DNS cache'${NC}"
            fi
            
            if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" azureuser@"$VM_PUBLIC_IP" \
                "echo '$CURRENT_IP $KV_NAME.vault.azure.net' | sudo tee -a /etc/hosts" > /dev/null; then
                echo "  [OK] Agent cache configured"
            else
                echo "  ⚠ SSH failed, but continuing (VM may need more time to boot)"
            fi
        fi
        
        # Update Key Vault secret with error message
        silent az keyvault secret set --vault-name "$KV_NAME" --name "AppMessage" \
            --value "ERROR: Connection timeout! DNS cache may be stale after endpoint recreation."
        
        # Restart the agent to ensure it uses the cached DNS
        echo "  → Restarting agent to apply cached DNS..."
        if [ -n "$VM_NAME" ]; then
            silent az vm restart --resource-group "$RG_NAME" --name "$VM_NAME"
            echo "  ✓ Agent VM restarted"
        fi
        
        echo ""
        echo "✅ Lab 2 fault injected (Stale DNS Cache scenario)."
        echo ""
        echo "Scenario:"
        echo "  • Private Endpoint was recreated with new IP ($NEW_IP)"
        echo "  • Agent's DNS cache still has old IP ($CURRENT_IP)"
        echo "  • Agent will timeout trying to reach stale cached address"
        echo ""
        echo "Next: Run the pipeline to reproduce the failure."
        echo "Go to Azure DevOps and queue a new run of 'DNS-Lab-Pipeline'."
        echo ""
        echo "Students will learn:"
        echo "  • How DNS caching affects Private Endpoint connectivity"
        echo "  • How to diagnose stale cache with nslookup vs /etc/hosts"
        echo "  • How to flush DNS cache on Linux (systemd-resolved)"
        ;;
    lab3)
        echo "Injecting Lab 3 fault..."
        silent az network vnet update --resource-group "$RG_NAME" --name "$VNET_NAME" --dns-servers 10.1.2.50
        # Update Key Vault secret with error message
        silent az keyvault secret set --vault-name "$KV_NAME" --name "AppMessage" \
            --value "ERROR: Custom DNS server misconfigured! Check VNet DNS settings."
        
        echo "✅ Lab 3 fault injected."
        echo ""
        echo "⚠️  The agent will go offline because it can't resolve dev.azure.com"
        echo "   This is EXPECTED! Students will troubleshoot DNS resolution."
        echo ""
        echo "   To diagnose: SSH to the VM and run:"
        echo "     nslookup dev.azure.com"
        echo "     curl -I https://dev.azure.com/ADOTrainingLab/"
        echo ""
        echo "   To restore: ./fix-lab.sh lab3"
        ;;
    *)
        echo "❌ Invalid Lab ID. Use lab1, lab2, or lab3."; exit 1
        ;;
esac

# Default instruction for labs without specific guidance
if [ "$LAB_ID" != "lab2" ]; then
    echo "Next: Use nslookup, dig, curl to observe failure."
fi 
