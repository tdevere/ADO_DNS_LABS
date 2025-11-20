#!/bin/bash

#######################################################################
# DNS Testing Helper Script
# Tests DNS resolution and Key Vault connectivity
#######################################################################

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Get Key Vault name from command line or terraform
if [ -z "$1" ]; then
    if [ -f "../terraform/terraform.tfvars" ]; then
        KV_NAME=$(grep "^key_vault_name" ../terraform/terraform.tfvars | cut -d'"' -f2)
    else
        echo -e "${RED}❌ Please provide Key Vault name as argument${NC}"
        echo "Usage: $0 <keyvault-name>"
        echo "Or run from labs/dns-standalone/ directory with terraform.tfvars configured"
        exit 1
    fi
else
    KV_NAME=$1
fi

echo -e "${BLUE}🧪 DNS Testing for Key Vault: ${YELLOW}$KV_NAME${NC}\n"

# Test 1: Basic DNS resolution
echo -e "${GREEN}Test 1: Basic DNS Resolution${NC}"
echo -e "Command: nslookup $KV_NAME.vault.azure.net"
echo "---"
if nslookup "$KV_NAME.vault.azure.net" > /tmp/dns_test.txt 2>&1; then
    cat /tmp/dns_test.txt
    IP=$(grep "Address:" /tmp/dns_test.txt | tail -n1 | awk '{print $2}')
    echo "---"
    if [[ $IP == 10.1.2.* ]]; then
        echo -e "${GREEN}✅ Resolves to private IP: $IP${NC}"
    elif [[ $IP == 168.* ]] || [[ $IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}❌ Resolves to public IP: $IP (WRONG!)${NC}"
        echo -e "${YELLOW}Expected private IP in range 10.1.2.x${NC}"
    else
        echo -e "${YELLOW}⚠️  Unexpected IP format: $IP${NC}"
    fi
else
    echo -e "${RED}❌ DNS resolution failed!${NC}"
    cat /tmp/dns_test.txt
fi
echo ""

# Test 2: Query Azure DNS directly
echo -e "${GREEN}Test 2: Direct Azure DNS Query${NC}"
echo -e "Command: nslookup $KV_NAME.vault.azure.net 168.63.129.16"
echo "---"
if nslookup "$KV_NAME.vault.azure.net" 168.63.129.16 > /tmp/dns_test_azure.txt 2>&1; then
    cat /tmp/dns_test_azure.txt
    IP=$(grep "Address:" /tmp/dns_test_azure.txt | tail -n1 | awk '{print $2}')
    echo "---"
    if [[ $IP == 10.1.2.* ]]; then
        echo -e "${GREEN}✅ Azure DNS returns private IP: $IP${NC}"
    else
        echo -e "${RED}❌ Azure DNS returns: $IP${NC}"
    fi
else
    echo -e "${RED}❌ Azure DNS query failed!${NC}"
    cat /tmp/dns_test_azure.txt
fi
echo ""

# Test 3: Check DNS configuration
echo -e "${GREEN}Test 3: DNS Configuration${NC}"
echo -e "Command: cat /etc/resolv.conf"
echo "---"
cat /etc/resolv.conf
echo "---"
echo ""

# Test 4: Test connectivity
echo -e "${GREEN}Test 4: HTTPS Connectivity${NC}"
echo -e "Command: curl -v --max-time 10 https://$KV_NAME.vault.azure.net"
echo "---"
if curl -v --max-time 10 "https://$KV_NAME.vault.azure.net" 2>&1 | tee /tmp/curl_test.txt | grep -q "SSL connection"; then
    echo "---"
    echo -e "${GREEN}✅ SSL/TLS handshake successful${NC}"
    echo -e "${YELLOW}(Authentication failure is expected without credentials)${NC}"
else
    echo "---"
    if grep -q "Connection timed out\|Connection refused" /tmp/curl_test.txt; then
        echo -e "${RED}❌ Connection failed - DNS might be returning wrong IP${NC}"
    else
        echo -e "${YELLOW}⚠️  Unexpected result (check logs above)${NC}"
    fi
fi
echo ""

# Summary
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""
echo -e "Key Vault: ${YELLOW}$KV_NAME.vault.azure.net${NC}"
echo ""

# Clean up
rm -f /tmp/dns_test.txt /tmp/dns_test_azure.txt /tmp/curl_test.txt

echo -e "${GREEN}Testing complete!${NC}"
echo ""
echo "For troubleshooting help, see: docs/TROUBLESHOOTING.md"
