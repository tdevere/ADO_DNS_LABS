#!/bin/bash
set -e

# Debug mode (enabled by default)
DEBUG=true
if [[ "$1" == "--quiet" ]]; then
    DEBUG=false
    shift
fi

LAB_ID=$1

if [ -z "$LAB_ID" ]; then
    echo "Usage: ./fix-lab.sh [--quiet] <lab1|lab2|lab3>"
    exit 1
fi

if [[ "$DEBUG" == "true" ]]; then
    echo "🐛 Verbose mode enabled (use --quiet to suppress)"
fi

echo "=================================================="
echo "   DNS Troubleshooting Lab - Fix Scenario: $LAB_ID"
echo "=================================================="

# Load environment variables
if [ -f ".ado.env" ]; then
    source .ado.env
else
    echo "⚠️ .ado.env file not found. You may be prompted for variables."
fi

# Set default pool if not set
ADO_POOL=${ADO_POOL:-Default}

# Get resource names from Terraform state
RG_NAME=$(terraform output -raw resource_group_name || echo "")
KV_NAME=$(terraform output -raw key_vault_name || echo "")
CORRECT_IP=$(terraform output -raw key_vault_private_ip || echo "10.1.2.5")
VNET_NAME=$(terraform output -raw vnet_name || echo "vnet-dns-lab")
ZONE_NAME="privatelink.vaultcore.azure.net"

if [ -z "$RG_NAME" ] || [ -z "$KV_NAME" ]; then
    echo "❌ Could not retrieve resource names from Terraform state."
    echo "   Ensure Terraform state exists and resources are deployed."
    exit 1
fi

echo "Restoring configuration using Azure CLI (faster, avoids Terraform conflicts)..."

case $LAB_ID in
    lab1)
        echo "🔧 Fixing Lab 1 - Restoring correct DNS A record..."
        az network private-dns record-set a update \
            --resource-group "$RG_NAME" \
            --zone-name "$ZONE_NAME" \
            --name "$KV_NAME" \
            --set "aRecords[0].ipv4Address=$CORRECT_IP" \
            --output none
        echo "  ✓ DNS A record restored to $CORRECT_IP"
        ;;
    
    lab2)
        echo "🔧 Fixing Lab 2 - Clearing stale DNS cache and restoring correct IP..."
        
        # Clear DNS cache on agent VM first
        VM_PUBLIC_IP=$(terraform output -raw vm_public_ip || echo "")
        SSH_KEY="$HOME/.ssh/terraform_lab_key"
        
        if [ ! -f "$SSH_KEY" ]; then
            echo "  ⚠ SSH key not found at $SSH_KEY"
            echo "  → Run: ./scripts/generate-ssh-key.sh"
            echo "  → Skipping VM cache clearing (not critical for this lab)"
        elif [ -n "$VM_PUBLIC_IP" ]; then
            echo "  → Removing stale /etc/hosts entry for $KV_NAME"
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" azureuser@"$VM_PUBLIC_IP" \
                "sudo sed -i '/$KV_NAME\.vault\.azure\.net/d' /etc/hosts" || echo "  ⚠ SSH failed (VM may be restarting)"
            
            echo "  → Flushing systemd-resolved DNS cache"
            ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" azureuser@"$VM_PUBLIC_IP" \
                "sudo systemd-resolve --flush-caches || sudo resolvectl flush-caches" || echo "  ⚠ Cache flush failed (continuing)"
            
            echo "  ✓ DNS cache cleared"
        fi
        
        # Restore correct DNS A record
        echo "  → Restoring DNS A record to $CORRECT_IP"
        az network private-dns record-set a update \
            --resource-group "$RG_NAME" \
            --zone-name "$ZONE_NAME" \
            --name "$KV_NAME" \
            --set "aRecords[0].ipv4Address=$CORRECT_IP" \
            --output none
        echo "  ✓ DNS A record restored"
        ;;
    
    lab3)
        echo "🔧 Fixing Lab 3 - Restoring Azure DNS servers..."
        az network vnet update \
            --resource-group "$RG_NAME" \
            --name "$VNET_NAME" \
            --dns-servers "" \
            --output none
        echo "  ✓ VNet DNS restored to Azure default (168.63.129.16)"
        ;;
    
    *)
        echo "❌ Unknown lab ID: $LAB_ID"
        exit 1
        ;;
esac

# Only use Terraform if Azure CLI fixes aren't sufficient (e.g., NSG drift)
echo ""
echo "Verifying infrastructure state with Terraform..."
if ! terraform apply -auto-approve -var="lab_scenario=base" -var="ado_org_url=${ADO_ORG_URL}" -var="ado_pat=${ADO_PAT}" -var="ado_pool_name=${ADO_POOL}" -lock=false; then
    echo "[WARN] Terraform apply failed. Checking for stuck resources (InUseSubnetCannotBeDeleted)..."
    
    # Attempt to discover RG name
    RG_NAME=$(terraform output -raw resource_group_name || az group list --query "[?starts_with(name, 'rg-dns-lab')].name" -o tsv)
    
    if [ -n "$RG_NAME" ]; then
        echo "🧹 Force-cleaning Agent VM and NIC in $RG_NAME to release subnet lock..."
        # Delete VM first (async)
        az vm delete --resource-group "$RG_NAME" --name vm-agent-dns-lab --yes --no-wait || true
        
        # Wait a bit for VM deletion to register so NIC can be deleted
        echo "Waiting for VM deletion..."
        sleep 15
        
        # Delete NIC (the actual subnet blocker)
        az network nic delete --resource-group "$RG_NAME" --name nic-agent-vm || true
        
        echo "♻️ Retrying Terraform apply..."
        terraform apply -auto-approve -var="lab_scenario=base" -var="ado_org_url=${ADO_ORG_URL}" -var="ado_pat=${ADO_PAT}" -var="ado_pool_name=${ADO_POOL}" -lock=false
    else
        echo "❌ Could not determine Resource Group to perform cleanup. Please check logs."
        exit 1
    fi
fi

echo "✅ Lab $LAB_ID is now FIXED. Configuration restored to base state."
echo "   Run the pipeline or check 'nslookup' to verify success."

# Restore success message in Key Vault
KV_NAME=$(terraform output -raw key_vault_name || echo "")
if [ -n "$KV_NAME" ]; then
    echo "Restoring success message in Key Vault..."
    if [[ "$DEBUG" == "true" ]]; then
        az keyvault secret set --vault-name "$KV_NAME" --name "AppMessage" \
            --value "Welcome to the DNS Lab! Your pipeline is working correctly."
    else
        az keyvault secret set --vault-name "$KV_NAME" --name "AppMessage" \
            --value "Welcome to the DNS Lab! Your pipeline is working correctly." > /dev/null
    fi
    echo "[OK] Key Vault message restored"
fi

# For Lab 3 specifically, the agent should come back online automatically
if [ "$LAB_ID" == "lab3" ]; then
    echo ""
    echo "⏳ Waiting 30 seconds for agent to reconnect with restored DNS..."
    sleep 30
    echo "✅ Agent should now be online. Check the agent pool in Azure DevOps."
    echo ""
    echo "   If the agent is still offline, it may have died during the DNS outage."
    echo "   Restart it by running: ./scripts/register-agent.sh"
fi
