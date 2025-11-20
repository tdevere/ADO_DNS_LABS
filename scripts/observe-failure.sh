#!/bin/bash
# Purpose: Collect symptom artifacts after drift injection.
set -euo pipefail

KV_NAME=$(terraform output -raw key_vault_name)
VM_IP=$(terraform output -raw vm_public_ip)
PIPELINE_NAME="DNS-Lab-Pipeline"

echo "Collecting pipeline latest run status..."
az pipelines build list --definition-name "$PIPELINE_NAME" --top 1 --query "[0].{id:id,status:status,result:result}" -o table || echo "Pipeline query failed"

echo "Agent VM DNS test (nslookup)..."
ssh -o StrictHostKeyChecking=no -i ~/.ssh/terraform_lab_key azureuser@"$VM_IP" "nslookup ${KV_NAME}.vault.azure.net" || echo "Remote nslookup failed"

echo "Agent VM curl connectivity (expect SSL ok, secret failure):"
ssh -o StrictHostKeyChecking=no -i ~/.ssh/terraform_lab_key azureuser@"$VM_IP" "curl -sv https://${KV_NAME}.vault.azure.net 2>&1 | grep -E 'Connected to|certificate'" || true

echo "Private DNS record currently set to:" 
az network private-dns record-set a show --name "$KV_NAME" --zone-name privatelink.vaultcore.azure.net --resource-group rg-dns-lab --query "arecords[].ipv4Address" -o tsv || echo "Record fetch failed"

echo "Artifacts collected. Begin analysis: compare resolved IP vs expected private endpoint NIC IP."
