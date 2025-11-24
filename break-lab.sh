#!/bin/bash
set -euo pipefail

LAB_ID=${1:-}

if [ -z "$LAB_ID" ]; then
    echo "Usage: ./break-lab.sh <lab1|lab2|lab3>"; exit 1
fi

echo "=================================================="
echo "   DNS Troubleshooting Lab - Break Scenario: $LAB_ID"
echo "=================================================="

# Helper to run a command silently (hide stdout/stderr) but fail fast if it exits non-zero
silent() { "$@" >/dev/null 2>&1; }

# Discover resource names without triggering interactive Terraform operations
# Prefer terraform outputs if already present; fall back to Azure CLI discovery.
KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || az keyvault list --query "[?starts_with(name, 'kv-dns-lab')].name | [0]" -o tsv || echo "")
RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || {
    [ -n "$KV_NAME" ] && az resource list --name "$KV_NAME" --resource-type Microsoft.KeyVault/vaults --query "[0].resourceGroup" -o tsv; } || echo "")

if [ -z "$KV_NAME" ] || [ -z "$RG_NAME" ]; then
    echo "❌ Unable to discover lab resources. Ensure the base lab has been deployed (run ./start-lab.sh)."; exit 1
fi

# Static names from Terraform config (no suffixes in these resources)
ZONE_NAME="privatelink.vaultcore.azure.net"
VNET_NAME="vnet-dns-lab"
VNET_LINK_NAME="link-vnet-dns-lab"

case $LAB_ID in
    lab1)
        echo "Injecting Lab 1 fault (wrong A record)..."
        # Try update first; if it fails, recreate with bad IP
        if ! silent az network private-dns record-set a update \
                --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$KV_NAME" \
                --set aRecords[0].ipv4Address=10.1.2.50; then
            silent az network private-dns record-set a delete --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$KV_NAME" --yes || true
            silent az network private-dns record-set a create --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$KV_NAME" --ttl 300 --ipv4-addresses 10.1.2.50
        fi
        echo "✅ Lab 1 fault injected. Begin troubleshooting."
        ;;
    lab2)
        echo "Injecting Lab 2 fault (remove VNet link)..."
        silent az network private-dns link vnet delete \
            --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$VNET_LINK_NAME" --yes || true
        echo "✅ Lab 2 fault injected. Begin troubleshooting."
        ;;
    lab3)
        echo "Injecting Lab 3 fault (custom DNS server)..."
        silent az network vnet update --resource-group "$RG_NAME" --name "$VNET_NAME" --dns-servers 10.1.2.50
        echo "✅ Lab 3 fault injected. Begin troubleshooting."
        ;;
    *)
        echo "❌ Invalid Lab ID. Use lab1, lab2, or lab3."; exit 1
        ;;
esac

echo "Next: Use nslookup, dig, curl to observe failure." 
