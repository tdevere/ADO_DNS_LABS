#!/bin/bash
set -euo pipefail

LAB_ID=${1:-}
if [ -z "$LAB_ID" ]; then
    echo "Usage: ./scripts/verify-lab.sh <lab1|lab2|lab3>"
    exit 1
fi

# Get resource info
KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "")
RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
ZONE_NAME="privatelink.vaultcore.azure.net"

if [ -z "$KV_NAME" ]; then
    echo "❌ Lab not deployed. Run ./setup.sh first."
    exit 1
fi

echo "========================================"
echo "  Lab $LAB_ID Verification"
echo "========================================"

# Common check: DNS resolution
echo -e "\n🔍 Checking DNS Resolution..."
if command -v nslookup >/dev/null; then
    RESOLVED_IP=$(nslookup "${KV_NAME}.vault.azure.net" | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | tail -1 || echo "FAILED")
    echo "Resolved IP: $RESOLVED_IP"
    
    if [[ $RESOLVED_IP == 10.1.2.* ]]; then
        echo "✅ Private IP detected"
    elif [[ $RESOLVED_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "⚠️  Public IP detected (may be expected for Lab 2)"
    else
        echo "❌ DNS resolution failed"
    fi
fi

# Lab-specific checks
case $LAB_ID in
    lab1)
        echo -e "\n🔍 Lab 1 Specific Checks..."
        echo "Checking DNS A record vs Private Endpoint IP..."
        
        PE_IP=$(az network private-endpoint show \
            --resource-group "$RG_NAME" --name pe-kv-dns-lab \
            --query "customDnsConfigs[0].ipAddresses[0]" -o tsv 2>/dev/null)
        
        DNS_RECORD=$(az network private-dns record-set a show \
            --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" \
            --name "$KV_NAME" --query "aRecords[0].ipv4Address" -o tsv 2>/dev/null)
        
        echo "Private Endpoint IP: $PE_IP"
        echo "DNS A Record IP:     $DNS_RECORD"
        
        if [ "$PE_IP" = "$DNS_RECORD" ]; then
            echo "✅ IPs match - Lab 1 is FIXED"
        else
            echo "❌ Mismatch detected - This is the Lab 1 fault"
        fi
        ;;
        
    lab2)
        echo -e "\n🔍 Lab 2 Specific Checks..."
        echo "Checking VNet Link status..."
        
        LINK_COUNT=$(az network private-dns link vnet list \
            --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" \
            --query "length([])" -o tsv 2>/dev/null || echo "0")
        
        echo "VNet Links found: $LINK_COUNT"
        
        if [ "$LINK_COUNT" = "0" ]; then
            echo "❌ No VNet links - This is the Lab 2 fault"
            echo "   Result: VM queries Azure DNS, gets public IP"
        else
            echo "✅ VNet link exists - Lab 2 is FIXED"
            az network private-dns link vnet list \
                --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" \
                -o table
        fi
        ;;
        
    lab3)
        echo -e "\n🔍 Lab 3 Specific Checks..."
        echo "Checking VNet DNS servers configuration..."
        
        DNS_SERVERS=$(az network vnet show \
            --resource-group "$RG_NAME" --name vnet-dns-lab \
            --query "dhcpOptions.dnsServers" -o tsv 2>/dev/null || echo "")
        
        if [ -z "$DNS_SERVERS" ]; then
            echo "✅ Using Azure DNS (168.63.129.16) - Lab 3 is FIXED"
        else
            echo "❌ Custom DNS servers configured: $DNS_SERVERS"
            echo "   This is the Lab 3 fault"
        fi
        ;;
        
    *)
        echo "❌ Unknown lab ID: $LAB_ID"
        exit 1
        ;;
esac

echo -e "\n========================================"
