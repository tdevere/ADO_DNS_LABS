#!/bin/bash
#######################################################################
# Custom DNS Server Image Builder
# Creates a pre-configured BIND9 DNS server image for Lab 3
#######################################################################

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Custom DNS Server Image Builder                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Configuration
# Use a unique resource group name per run to avoid RG delete delays
SUFFIX=$(date +%Y%m%d%H%M%S)
IMAGE_RG_NAME="rg-dns-lab-images-${SUFFIX}"
IMAGE_LOCATION="westus2"
IMAGE_NAME="dns-server-lab3-bind9"
TEMP_VM_NAME="temp-dns-builder"
TEMP_NIC_NAME="temp-dns-nic"
TEMP_NSG_NAME="temp-dns-nsg"
TEMP_VNET_NAME="temp-dns-vnet"
TEMP_SUBNET_NAME="temp-dns-subnet"
TEMP_PUBLIC_IP_NAME="temp-dns-pip"

echo -e "${YELLOW}This script will:${NC}"
echo "1. Create temporary resource group"
echo "2. Deploy a temporary Ubuntu VM"
echo "3. Install and configure BIND9 with Google DNS forwarder (broken state)"
echo "4. Capture VM as a managed image"
echo "5. Clean up temporary resources"
echo "6. Output image ID for use in terraform.tfvars"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Check if az CLI is installed
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI not found. Please install it first.${NC}"
    exit 1
fi

# Check if logged in
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Not logged into Azure. Please run 'az login' first.${NC}"
    exit 1
fi

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
echo -e "${GREEN}✅ Using subscription: $SUBSCRIPTION_ID${NC}"

# Step 1: Create resource group
echo -e "\n${BLUE}1️⃣  Creating resource group${NC}"
if az group show --name "$IMAGE_RG_NAME" &> /dev/null; then
    echo -e "${YELLOW}⏭️  Resource group already exists${NC}"
else
    az group create --name "$IMAGE_RG_NAME" --location "$IMAGE_LOCATION" --output none
    echo -e "${GREEN}✅ Resource group created${NC}"
fi

# Step 2: Create temporary networking
echo -e "\n${BLUE}2️⃣  Creating temporary networking${NC}"
az network vnet create \
    --resource-group "$IMAGE_RG_NAME" \
    --name "$TEMP_VNET_NAME" \
    --address-prefix 10.200.0.0/16 \
    --subnet-name "$TEMP_SUBNET_NAME" \
    --subnet-prefix 10.200.1.0/24 \
    --output none

az network nsg create \
    --resource-group "$IMAGE_RG_NAME" \
    --name "$TEMP_NSG_NAME" \
    --output none

az network nsg rule create \
    --resource-group "$IMAGE_RG_NAME" \
    --nsg-name "$TEMP_NSG_NAME" \
    --name "AllowSSH" \
    --priority 100 \
    --source-address-prefixes '*' \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp \
    --output none

az network public-ip create \
    --resource-group "$IMAGE_RG_NAME" \
    --name "$TEMP_PUBLIC_IP_NAME" \
    --allocation-method Static \
    --sku Standard \
    --output none

az network nic create \
    --resource-group "$IMAGE_RG_NAME" \
    --name "$TEMP_NIC_NAME" \
    --vnet-name "$TEMP_VNET_NAME" \
    --subnet "$TEMP_SUBNET_NAME" \
    --network-security-group "$TEMP_NSG_NAME" \
    --public-ip-address "$TEMP_PUBLIC_IP_NAME" \
    --output none

echo -e "${GREEN}✅ Networking created${NC}"

# Step 3: Generate SSH key if needed
SSH_KEY_PATH="$HOME/.ssh/dns_image_builder_key"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "\n${BLUE}3️⃣  Generating SSH key${NC}"
    ssh-keygen -t rsa -b 2048 -f "$SSH_KEY_PATH" -N "" -C "dns-image-builder"
    echo -e "${GREEN}✅ SSH key generated${NC}"
else
    echo -e "\n${BLUE}3️⃣  Using existing SSH key${NC}"
fi

# Step 4: Create temporary VM
echo -e "\n${BLUE}4️⃣  Creating temporary VM (this takes ~3-5 minutes)${NC}"
az vm create \
    --resource-group "$IMAGE_RG_NAME" \
    --name "$TEMP_VM_NAME" \
    --location "$IMAGE_LOCATION" \
    --nics "$TEMP_NIC_NAME" \
    --image Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest \
    --size Standard_B2s \
    --admin-username azureuser \
    --ssh-key-values "${SSH_KEY_PATH}.pub" \
    --output none

echo -e "${GREEN}✅ VM created${NC}"

# Get VM public IP
VM_IP=$(az network public-ip show \
    --resource-group "$IMAGE_RG_NAME" \
    --name "$TEMP_PUBLIC_IP_NAME" \
    --query ipAddress -o tsv)

echo -e "${YELLOW}VM IP: $VM_IP${NC}"

# Step 5: Wait for VM to be ready
echo -e "\n${BLUE}5️⃣  Waiting for VM to be ready${NC}"
sleep 30
echo -e "${GREEN}✅ VM ready${NC}"

# Step 6: Install and configure BIND9
echo -e "\n${BLUE}6️⃣  Installing and configuring BIND9${NC}"

# Create configuration script
cat > /tmp/configure-dns.sh << 'EOF'
#!/bin/bash
set -e

echo "=== Installing BIND9 ==="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 bind9utils bind9-doc

echo "=== Configuring BIND9 with Google DNS forwarder (broken state) ==="
sudo tee /etc/bind/named.conf.options > /dev/null << 'BINDCONF'
options {
    directory "/var/cache/bind";
    
    // Forward all queries to Google DNS (BROKEN - won't resolve Azure privatelink)
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    
    forward only;
    
    // Allow queries from any source
    allow-query { any; };
    
    // Enable recursion
    recursion yes;
    
    // Listen on all interfaces
    listen-on { any; };
    listen-on-v6 { any; };
    
    // DNSSEC validation
    dnssec-validation auto;
};
BINDCONF

echo "=== Enabling query logging ==="
sudo tee /etc/bind/named.conf.local > /dev/null << 'BINDCONF'
// Query logging for troubleshooting
logging {
    channel query_log {
        file "/var/log/named/query.log" versions 3 size 5m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category queries { query_log; };
};

// Placeholder for conditional forwarder (students will add this)
// zone "privatelink.vaultcore.azure.net" {
//     type forward;
//     forward only;
//     forwarders { 168.63.129.16; };
// };
BINDCONF

sudo mkdir -p /var/log/named
sudo chown bind:bind /var/log/named

echo "=== Checking BIND configuration ==="
sudo named-checkconf

echo "=== Restarting BIND9 ==="
sudo systemctl restart named
sudo systemctl enable named

echo "=== Verifying BIND9 status ==="
sudo systemctl status named --no-pager

echo "=== BIND9 configuration complete ==="

echo "=== Creating Azure privatelink conditional forwarder template ==="
sudo tee /etc/bind/azure-privatelink.conf > /dev/null << 'AZURECONF'
// Azure Private Link DNS Forwarder
// Forwards privatelink queries to Azure DNS (168.63.129.16)
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};
AZURECONF

echo "=== Creating toggle-azure-dns.sh helper script ==="
sudo tee /usr/local/bin/toggle-azure-dns.sh > /dev/null << 'TOGGLESCRIPT'
#!/bin/bash
# Helper script to enable/disable Azure DNS forwarding

set -e

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

case "$1" in
    enable)
        echo "Enabling Azure DNS forwarding for privatelink zones..."
        
        # Check if already included
        if grep -q "include \"/etc/bind/azure-privatelink.conf\";" /etc/bind/named.conf.local; then
            echo "Azure DNS forwarding is already enabled."
            exit 0
        fi
        
        # Add include statement
        echo '' >> /etc/bind/named.conf.local
        echo '// Azure Private Link DNS Forwarding' >> /etc/bind/named.conf.local
        echo 'include "/etc/bind/azure-privatelink.conf";' >> /etc/bind/named.conf.local
        
        # Restart BIND9
        systemctl restart bind9
        
        echo "✅ Azure DNS forwarding enabled. BIND9 restarted."
        echo "Test with: nslookup <your-keyvault>.vault.azure.net"
        ;;
        
    disable)
        echo "Disabling Azure DNS forwarding..."
        
        # Remove include statement
        sed -i '/include "\/etc\/bind\/azure-privatelink.conf";/d' /etc/bind/named.conf.local
        sed -i '/Azure Private Link DNS Forwarding/d' /etc/bind/named.conf.local
        
        # Restart BIND9
        systemctl restart bind9
        
        echo "✅ Azure DNS forwarding disabled. BIND9 restarted."
        ;;
        
    status)
        if grep -q "include \"/etc/bind/azure-privatelink.conf\";" /etc/bind/named.conf.local; then
            echo "Azure DNS forwarding: ENABLED"
        else
            echo "Azure DNS forwarding: DISABLED"
        fi
        
        echo ""
        echo "BIND9 status:"
        systemctl status bind9 --no-pager | head -n 5
        ;;
        
    *)
        echo "Usage: $0 {enable|disable|status}"
        echo ""
        echo "  enable  - Forward privatelink queries to Azure DNS (168.63.129.16)"
        echo "  disable - Revert to Google DNS for all queries"
        echo "  status  - Check current configuration"
        exit 1
        ;;
esac
TOGGLESCRIPT

sudo chmod +x /usr/local/bin/toggle-azure-dns.sh

echo "=== Installing GitHub Copilot CLI ==="
curl -fsSL https://github.com/cli/cli/releases/download/v2.40.0/gh_2.40.0_linux_amd64.tar.gz | sudo tar xz -C /usr/local --strip-components=1

echo "=== Installing Azure CLI ==="
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

echo "=== Installing additional troubleshooting tools ==="
sudo apt-get install -y tcpdump dnsutils net-tools

echo "=== Configuration complete ==="
EOF

# Copy and execute configuration script
scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" /tmp/configure-dns.sh azureuser@${VM_IP}:/tmp/
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" azureuser@${VM_IP} 'bash /tmp/configure-dns.sh'

echo -e "${GREEN}✅ BIND9 installed and configured${NC}"

# Step 7: Generalize VM
echo -e "\n${BLUE}7️⃣  Generalizing VM${NC}"
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" azureuser@${VM_IP} 'sudo waagent -deprovision+user -force'
echo -e "${GREEN}✅ VM generalized${NC}"

# Step 8: Deallocate VM
echo -e "\n${BLUE}8️⃣  Deallocating VM${NC}"
az vm deallocate --resource-group "$IMAGE_RG_NAME" --name "$TEMP_VM_NAME" --output none
az vm generalize --resource-group "$IMAGE_RG_NAME" --name "$TEMP_VM_NAME" --output none
echo -e "${GREEN}✅ VM deallocated and generalized${NC}"

# Step 9: Capture image
echo -e "\n${BLUE}9️⃣  Capturing VM image${NC}"
az image create \
    --resource-group "$IMAGE_RG_NAME" \
    --name "$IMAGE_NAME" \
    --source "$TEMP_VM_NAME" \
    --output none

IMAGE_ID=$(az image show \
    --resource-group "$IMAGE_RG_NAME" \
    --name "$IMAGE_NAME" \
    --query id -o tsv)

echo -e "${GREEN}✅ Image created${NC}"
echo -e "${YELLOW}Image ID: $IMAGE_ID${NC}"

# Step 10: Clean up temporary resources
echo -e "\n${BLUE}🔟  Cleaning up temporary resources${NC}"
az vm delete --resource-group "$IMAGE_RG_NAME" --name "$TEMP_VM_NAME" --yes --output none
az network nic delete --resource-group "$IMAGE_RG_NAME" --name "$TEMP_NIC_NAME" --output none
az network public-ip delete --resource-group "$IMAGE_RG_NAME" --name "$TEMP_PUBLIC_IP_NAME" --output none
az network nsg delete --resource-group "$IMAGE_RG_NAME" --name "$TEMP_NSG_NAME" --output none
az network vnet delete --resource-group "$IMAGE_RG_NAME" --name "$TEMP_VNET_NAME" --output none

echo -e "${GREEN}✅ Temporary resources cleaned up${NC}"

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Image Creation Complete!                           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Image Details:${NC}"
echo "  Resource Group: $IMAGE_RG_NAME"
echo "  Image Name: $IMAGE_NAME"
echo "  Location: $IMAGE_LOCATION"
echo ""
echo -e "${YELLOW}Add this to your terraform.tfvars:${NC}"
echo ""
echo "custom_dns_image_id = \"$IMAGE_ID\""
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Add the image ID to terraform.tfvars"
echo "2. Run: terraform apply -var=\"lab_scenario=lab3\""
echo "3. Test DNS server deployment"
echo ""
echo -e "${GREEN}Done!${NC}"
