#!/bin/bash
# Purpose: Introduce DNS drift for training scenario without revealing cause.
# Action: Change the Key Vault privatelink A record to an incorrect IP.
# Reversal handled by separate fix script or terraform re-apply.

set -euo pipefail

if ! command -v az >/dev/null; then
  echo "Azure CLI required."; exit 1
fi

KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "")
DNS_RG=$(terraform output -raw dns_resource_group 2>/dev/null || echo "rg-dns-lab")
ZONE_NAME="privatelink.vaultcore.azure.net"
WRONG_IP="10.1.2.50"

if [ -z "$KV_NAME" ]; then
  echo "Key Vault name not found via terraform outputs."; exit 1
fi

echo "Injecting drift: setting A record for ${KV_NAME}.privatelink.vaultcore.azure.net to ${WRONG_IP}".

# Fetch existing record
EXISTING=$(az network private-dns record-set a show \
  --name "$KV_NAME" \
  --zone-name "$ZONE_NAME" \
  --resource-group "$DNS_RG" 2>/dev/null || true)

if [ -n "$EXISTING" ]; then
  # Remove existing records
  IPS=$(echo "$EXISTING" | jq -r '.arecords[].ipv4Address' 2>/dev/null || echo "")
  for IP in $IPS; do
    az network private-dns record-set a remove-record \
      --ipv4-address "$IP" \
      --name "$KV_NAME" \
      --zone-name "$ZONE_NAME" \
      --resource-group "$DNS_RG" >/dev/null
  done
else
  # Create empty record set if missing
  az network private-dns record-set a create \
    --name "$KV_NAME" \
    --zone-name "$ZONE_NAME" \
    --resource-group "$DNS_RG" >/dev/null
fi

# Add incorrect IP
az network private-dns record-set a add-record \
  --ipv4-address "$WRONG_IP" \
  --name "$KV_NAME" \
  --zone-name "$ZONE_NAME" \
  --resource-group "$DNS_RG" >/dev/null

echo "Drift injected. Pipeline secret access should now fail."
echo "Run: ./scripts/observe-failure.sh (after creation) or re-run pipeline manually."
