# Instructor Setup Guide

This guide is for instructors setting up the lab environment. Students should not need to reference this document.

---

## Lab 3: Custom DNS Server Image Setup

Lab 3 requires a pre-built Azure VM image with BIND9 DNS server configured. Follow these steps to create and distribute the image to students.

### Option 1: Build Custom Azure VM Image (Recommended)

This creates a managed image that can be referenced in Terraform via `source_image_id`.

#### Step 1: Create Image Build Script

Create `scripts/build-dns-image.sh`:

```bash
#!/bin/bash
set -e

RESOURCE_GROUP="rg-dns-lab-images-$(date +%Y%m%d%H%M%S)"
LOCATION="westus2"
VM_NAME="dns-image-builder"
IMAGE_NAME="dns-server-lab3-bind9"

echo "Creating resource group: $RESOURCE_GROUP"
az group create --name $RESOURCE_GROUP --location $LOCATION

echo "Creating temporary VM for image build..."
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --public-ip-sku Standard

VM_IP=$(az vm show -d -g $RESOURCE_GROUP -n $VM_NAME --query publicIps -o tsv)

echo "Waiting for VM to be ready..."
sleep 30

echo "Installing BIND9 and tools..."
ssh -o StrictHostKeyChecking=no azureuser@$VM_IP << 'ENDSSH'
# Update system
sudo apt-get update
sudo apt-get upgrade -y

# Install BIND9 and DNS tools
sudo apt-get install -y bind9 bind9utils bind9-doc dnsutils

# Install troubleshooting tools
sudo apt-get install -y curl wget git jq tcpdump

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Install GitHub Copilot CLI
sudo npm install -g @githubnext/github-copilot-cli 2>/dev/null || echo "Copilot CLI installation skipped"

# Configure BIND9 - Default (broken) state
sudo tee /etc/bind/named.conf.options > /dev/null << 'EOF'
options {
    directory "/var/cache/bind";
    
    // Default forwarders - sends ALL queries to Google DNS
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    
    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { any; };
    allow-query { any; };
    
    // Enable query logging
    querylog yes;
};
EOF

# Create Azure Private Link conditional forwarders (disabled by default)
sudo tee /etc/bind/azure-privatelink.conf > /dev/null << 'EOF'
// Azure Private Link DNS Forwarding
// When enabled, these zones will forward to Azure DNS instead of global forwarders

zone "privatelink.vaultcore.azure.net" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.blob.core.windows.net" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.table.core.windows.net" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.queue.core.windows.net" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.file.core.windows.net" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.database.windows.net" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.sql.azuresynapse.net" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.azurecr.io" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.azurewebsites.net" {
    type forward;
    forwarders { 168.63.129.16; };
};
EOF

# Create toggle script
sudo tee /usr/local/bin/toggle-azure-dns.sh > /dev/null << 'EOF'
#!/bin/bash
# Toggle Azure DNS conditional forwarding for Private Link zones

NAMED_CONF_LOCAL="/etc/bind/named.conf.local"
AZURE_CONF="/etc/bind/azure-privatelink.conf"
INCLUDE_LINE='include "/etc/bind/azure-privatelink.conf";'

case "$1" in
    enable)
        if grep -qF "$INCLUDE_LINE" "$NAMED_CONF_LOCAL"; then
            echo "Azure DNS forwarding already enabled"
        else
            echo "$INCLUDE_LINE" | sudo tee -a "$NAMED_CONF_LOCAL" > /dev/null
            echo "Azure DNS forwarding enabled"
            sudo named-checkconf
            sudo systemctl restart named
            echo "BIND9 restarted successfully"
        fi
        ;;
    disable)
        sudo sed -i "\|$INCLUDE_LINE|d" "$NAMED_CONF_LOCAL"
        echo "Azure DNS forwarding disabled"
        sudo named-checkconf
        sudo systemctl restart named
        echo "BIND9 restarted successfully"
        ;;
    status)
        if grep -qF "$INCLUDE_LINE" "$NAMED_CONF_LOCAL"; then
            echo "Azure DNS forwarding: ENABLED"
        else
            echo "Azure DNS forwarding: DISABLED (forwarding all to Google DNS)"
        fi
        ;;
    *)
        echo "Usage: $0 {enable|disable|status}"
        exit 1
        ;;
esac
EOF

sudo chmod +x /usr/local/bin/toggle-azure-dns.sh

# Enable query logging
sudo mkdir -p /var/log/named
sudo chown bind:bind /var/log/named
sudo tee -a /etc/bind/named.conf > /dev/null << 'EOF'

// Query logging
logging {
    channel query_log {
        file "/var/log/named/query.log" versions 3 size 10m;
        severity info;
        print-time yes;
        print-category yes;
    };
    category queries { query_log; };
};
EOF

# Restart BIND9 to apply configuration
sudo systemctl restart named
sudo systemctl enable named

# Clean up
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
history -c
ENDSSH

echo "Deallocating VM for image capture..."
az vm deallocate --resource-group $RESOURCE_GROUP --name $VM_NAME

echo "Generalizing VM..."
az vm generalize --resource-group $RESOURCE_GROUP --name $VM_NAME

echo "Creating managed image..."
az image create \
  --resource-group $RESOURCE_GROUP \
  --name $IMAGE_NAME \
  --source $VM_NAME

IMAGE_ID=$(az image show --resource-group $RESOURCE_GROUP --name $IMAGE_NAME --query id -o tsv)

echo "============================================"
echo "Image created successfully!"
echo "Image ID: $IMAGE_ID"
echo ""
echo "Add this to your terraform.tfvars:"
echo "custom_dns_image_id = \"$IMAGE_ID\""
echo "============================================"
```

#### Step 2: Run the Build Script

```bash
chmod +x scripts/build-dns-image.sh
./scripts/build-dns-image.sh
```

⏳ This takes approximately 10-15 minutes.

#### Step 3: Distribute Image ID to Students

Add the image ID to the student's `terraform.tfvars.example`:

```hcl
custom_dns_image_id = "/subscriptions/YOUR_SUB_ID/resourceGroups/rg-dns-lab-images-TIMESTAMP/providers/Microsoft.Compute/images/dns-server-lab3-bind9"
```

### Option 2: Azure Compute Gallery (Multi-Subscription)

If you need to share the image across multiple subscriptions, use Azure Compute Gallery:

```bash
# Create gallery
az sig create \
  --resource-group rg-dns-lab-images \
  --gallery-name DNSLabGallery \
  --location westus2

# Create image definition
az sig image-definition create \
  --resource-group rg-dns-lab-images \
  --gallery-name DNSLabGallery \
  --gallery-image-definition dns-server-bind9 \
  --publisher LabPublisher \
  --offer DNSLabs \
  --sku bind9-ubuntu2204 \
  --os-type Linux \
  --os-state Generalized \
  --hyper-v-generation V2

# Create image version from managed image
az sig image-version create \
  --resource-group rg-dns-lab-images \
  --gallery-name DNSLabGallery \
  --gallery-image-definition dns-server-bind9 \
  --gallery-image-version 1.0.0 \
  --target-regions "westus2" \
  --managed-image /subscriptions/.../images/dns-server-lab3-bind9

# Get gallery image version ID
az sig image-version show \
  --resource-group rg-dns-lab-images \
  --gallery-name DNSLabGallery \
  --gallery-image-definition dns-server-bind9 \
  --gallery-image-version 1.0.0 \
  --query id -o tsv
```

Grant students' subscriptions access to the gallery:

```bash
az role assignment create \
  --assignee <student-service-principal-id> \
  --role "Reader" \
  --scope "/subscriptions/.../resourceGroups/rg-dns-lab-images/providers/Microsoft.Compute/galleries/DNSLabGallery"
```

---

## Terraform Configuration

Students' `main.tf` should include:

```hcl
resource "azurerm_network_interface" "dns_server" {
  count               = var.lab_scenario == "lab3" ? 1 : 0
  name                = "nic-dns-server"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.dns.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.2.50"
  }
}

resource "azurerm_linux_virtual_machine" "dns_server" {
  count                 = var.lab_scenario == "lab3" ? 1 : 0
  name                  = "vm-dns-server"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  network_interface_ids = [azurerm_network_interface.dns_server[0].id]
  size                  = "Standard_B2s"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_id = var.custom_dns_image_id

  admin_username = "azureuser"
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("~/.ssh/id_rsa.pub")
  }
}
```

---

## Testing the Image

After building the image, test it:

```bash
# Deploy a test VM using the image
az vm create \
  --resource-group rg-test \
  --name vm-dns-test \
  --image <IMAGE_ID> \
  --admin-username azureuser \
  --generate-ssh-keys

# SSH and verify
ssh azureuser@<VM_IP>

# Check BIND9 is running
sudo systemctl status named

# Check default forwarders (should be Google DNS)
sudo cat /etc/bind/named.conf.options

# Test toggle script
sudo /usr/local/bin/toggle-azure-dns.sh status  # Should show DISABLED
sudo /usr/local/bin/toggle-azure-dns.sh enable
sudo /usr/local/bin/toggle-azure-dns.sh status  # Should show ENABLED
```

---

## Troubleshooting

### BIND9 Won't Start

```bash
# Check configuration syntax
sudo named-checkconf

# Check detailed logs
sudo journalctl -u named -n 50
```

### Query Logging Not Working

```bash
# Verify log directory permissions
ls -la /var/log/named
sudo chown bind:bind /var/log/named

# Restart BIND9
sudo systemctl restart named
```

### Azure CLI/Copilot CLI Missing

These are optional. If installation fails during image build, students can still complete the lab without them.

---

## Cost Optimization

**Image storage costs:**
- Managed images: ~$0.05/month per image
- Azure Compute Gallery: Similar, but better for cross-subscription sharing

**Recommendation:** Delete the image build resource group after capturing the image to save on the temporary VM costs.

```bash
az group delete --name rg-dns-lab-images-TIMESTAMP --yes --no-wait
```

Keep only the managed image or gallery image version.
