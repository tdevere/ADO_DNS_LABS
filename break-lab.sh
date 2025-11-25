#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

LAB_ID=${1:-}

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
RG_NAME=$(terraform output -raw resource_group_name 2>&1)
if [ $? -ne 0 ] || [ -z "$RG_NAME" ] || [[ "$RG_NAME" == *"No outputs found"* ]] || [[ "$RG_NAME" == *"Warning"* ]]; then
    echo -e "${RED}❌ ERROR: Could not retrieve resource group from Terraform output.${NC}"
    echo -e "${YELLOW}The infrastructure may not be fully deployed.${NC}"
    echo ""
    echo "To deploy the lab infrastructure, run:"
    echo "  ./setup.sh"
    exit 1
fi

# Verify the resource group actually exists in Azure
if ! az group show --name "$RG_NAME" &>/dev/null; then
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
echo "=================================================="

# Helper to run a command silently (hide stdout/stderr) but fail fast if it exits non-zero
silent() { "$@" >/dev/null 2>&1; }

# Get other resource names from Terraform
KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "")

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
        echo "✅ Lab 2 fault injected."
        echo ""
        echo "Next: Run the pipeline to reproduce the failure."
        echo "Go to Azure DevOps and queue a new run of 'DNS-Lab-Pipeline'."
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

# Default instruction for labs without specific guidance
if [ "$LAB_ID" != "lab2" ]; then
    echo "Next: Use nslookup, dig, curl to observe failure."
fi 
