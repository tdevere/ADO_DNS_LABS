#!/bin/bash
set -e

LAB_ID=$1

if [ -z "$LAB_ID" ]; then
    echo "Usage: ./fix-lab.sh <lab1|lab2|lab3>"
    exit 1
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

echo "Restoring configuration using Infrastructure as Code..."

# For Lab 2, re-enable Key Vault public access first so Terraform can connect
if [ "$LAB_ID" == "lab2" ]; then
    echo "🔓 Restoring network connectivity for Lab 2..."
    KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "")
    if [ -n "$KV_NAME" ]; then
        az keyvault update --name "$KV_NAME" --public-network-access Enabled || true
    fi
fi

if ! terraform apply -auto-approve -var="lab_scenario=base" -var="ado_org_url=${ADO_ORG_URL}" -var="ado_pat=${ADO_PAT}" -var="ado_pool_name=${ADO_POOL}" -lock=false; then
    echo "⚠️ Terraform apply failed. Checking for stuck resources (InUseSubnetCannotBeDeleted)..."
    
    # Attempt to discover RG name
    RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || az group list --query "[?starts_with(name, 'rg-dns-lab')].name" -o tsv)
    
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
