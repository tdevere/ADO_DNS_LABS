# Lab 3 Setup Guide: Building the Custom DNS Server Image

## Overview

Lab 3 requires a pre-built custom DNS server image with BIND9 configured in a "broken" state (forwarding to Google DNS). This guide walks through building that image.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Contributor access to an Azure subscription
- SSH key generated (or script will create one)
- Terraform installed
- Approximately 15-20 minutes for image build

## Build Process

### Step 1: Run the Build Script

```bash
cd /workspaces/ADO_DNS_LABS
./scripts/build-dns-image.sh
```

### What the Script Does

1. **Creates Temporary Infrastructure:**
   - Resource Group: `rg-dns-lab-images` (location: eastus)
   - VNet, Subnet, NSG, Public IP
   - Ubuntu 22.04 VM (Standard_B2s)

2. **Installs and Configures Software:**
   - BIND9 DNS server
   - Configures Google DNS as default forwarder (8.8.8.8, 8.8.4.4)
   - Creates Azure DNS conditional forwarder template at `/etc/bind/azure-privatelink.conf`
   - Installs GitHub Copilot CLI
   - Installs Azure CLI
   - Installs troubleshooting tools (dig, nslookup, tcpdump, netstat)
   - Creates helper script at `/usr/local/bin/toggle-azure-dns.sh`
   - Enables DNS query logging to `/var/log/bind/query.log`

3. **Captures the Image:**
   - Generalizes the VM with `waagent -deprovision+user`
   - Creates managed image: `dns-server-lab3-bind9`
   - Cleans up temporary resources (VM, NIC, NSG, VNet, etc.)

4. **Outputs the Image ID:**
   ```
   Image ID: /subscriptions/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/resourceGroups/rg-dns-lab-images/providers/Microsoft.Compute/images/dns-server-lab3-bind9
   ```

### Step 2: Update terraform.tfvars

Add the image ID to your `terraform.tfvars`:

```terraform
custom_dns_image_id = "/subscriptions/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX/resourceGroups/rg-dns-lab-images/providers/Microsoft.Compute/images/dns-server-lab3-bind9"
```


### Step 2: Publish to Azure Compute Gallery (for student access)

If students will deploy from their own subscriptions, publish the managed image to an Azure Compute Gallery and share it.

```bash
# Example: publish the image (adjust values)
### Step 3: Deploy Lab 3

```bash
terraform apply -var="lab_scenario=dns_exercise3"
```

This will:
- Deploy the DNS server VM from your custom image at `10.1.2.50`
- Configure the VNet to use `10.1.2.50` as its DNS server
- Deploy the agent VM (which will use the custom DNS server)

# Or share privately to specific subscriptions (no community sharing)
./scripts/publish-image-to-gallery.sh \

## Image Configuration Details

### BIND9 Default Configuration (Broken State)

**File:** `/etc/bind/named.conf.options`

```
options {
    directory "/var/cache/bind";
```

#### Students: How to consume the gallery image

- You will receive a gallery image reference (image definition + version)
- Terraform `custom_dns_image_id` can be set to the gallery image resource ID, or you can switch to using `source_image_id` in the VM block if preferred
- Alternatively, use `cloud-init-dns.yaml` to build the DNS server on a stock Ubuntu image (no gallery needed)
    
    // Forward all queries to Google DNS (BROKEN)
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    
    forward only;
    allow-query { any; };
    recursion yes;
    listen-on { any; };
    listen-on-v6 { any; };
    dnssec-validation auto;
};
```

### Azure DNS Conditional Forwarder Template

**File:** `/etc/bind/azure-privatelink.conf`

```
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};
```

This file exists but is **not included** in `named.conf.local` by default.

### Helper Script

**File:** `/usr/local/bin/toggle-azure-dns.sh`

Students will use this to enable/disable Azure DNS forwarding:

```bash
# Check status
sudo /usr/local/bin/toggle-azure-dns.sh status

# Enable Azure DNS forwarding
sudo /usr/local/bin/toggle-azure-dns.sh enable

# Disable Azure DNS forwarding (revert to Google DNS)
sudo /usr/local/bin/toggle-azure-dns.sh disable
```

### DNS Query Logging

**File:** `/var/log/bind/query.log`

Students can monitor DNS queries in real-time:

```bash
sudo tail -f /var/log/bind/query.log
```

## Troubleshooting the Build Process

### Build Script Fails at SSH Connection

**Problem:** Cannot connect to temporary VM

**Solutions:**
- Wait 60 seconds after VM creation before retrying
- Check NSG rules allow SSH from your IP
- Verify SSH key was generated correctly

### BIND9 Configuration Fails

**Problem:** `named-checkconf` fails

**Solutions:**
- Check syntax in configuration files
- Verify all paths exist (`/var/log/bind`, `/etc/bind`, etc.)
- Review error messages in build script output

### Image Capture Fails

**Problem:** Cannot create managed image

**Solutions:**
- Ensure VM is deallocated and generalized
- Verify you have Contributor permissions
- Check for quota limits on managed images

### Re-building the Image

If you need to rebuild the image:

```bash
# Delete the old image
az image delete \
  --resource-group rg-dns-lab-images \
  --name dns-server-lab3-bind9

# Run the build script again
./scripts/build-dns-image.sh
```

## Testing the Image

After building and deploying:

1. **Verify DNS server is running:**
   ```bash
   # SSH to the DNS server (from agent VM or bastion)
   ssh 10.1.2.50
   
   # Check BIND9 status
   sudo systemctl status bind9
   ```

2. **Test broken state (default):**
   ```bash
   # Query Key Vault (should fail or return wrong IP)
   dig @localhost your-keyvault-name.vault.azure.net
   ```

3. **Enable Azure DNS forwarding:**
   ```bash
   sudo /usr/local/bin/toggle-azure-dns.sh enable
   ```

4. **Test fixed state:**
   ```bash
   # Query Key Vault (should return private IP)
   dig @localhost your-keyvault-name.vault.azure.net
   ```

## Cost Considerations

- **Build Process:** ~$0.50 (temporary VM runs for ~10 minutes)
- **Image Storage:** ~$0.50/month (standard managed disk snapshot)
- **Running Lab 3:** ~$3.50/day (DNS server VM + agent VM)

**Recommendation:** Destroy infrastructure when not in use:
```bash
terraform destroy
```

The image will remain in `rg-dns-lab-images` for future use.

## Advanced: Customizing the Image

To add additional tools or configurations to the image:

1. **Edit the build script:**
   ```bash
   nano scripts/build-dns-image.sh
   ```

2. **Add your commands to the configuration script section:**
   ```bash
   echo "=== Installing custom tool ==="
   sudo apt-get install -y your-custom-tool
   ```

3. **Rebuild the image:**
   ```bash
   ./scripts/build-dns-image.sh
   ```

4. **Update terraform.tfvars with the new image ID**

## Appendix: Manual Image Creation

If you prefer to create the image manually without the script:

1. Create a Ubuntu 22.04 VM in Azure Portal
2. SSH to the VM
3. Run the configuration commands from the build script
4. Generalize the VM: `sudo waagent -deprovision+user -force`
5. In Azure Portal: Stop the VM → Capture → Create Image
6. Use the image ID in `terraform.tfvars`

## Next Steps

Once the image is built and configured in `terraform.tfvars`:

1. Review the [Lab 3 README](../../labs/lab3/README.md)
2. Deploy Lab 3: `terraform apply -var="lab_scenario=dns_exercise3"`
3. Follow the troubleshooting exercises
4. Learn about custom DNS configuration in Azure

---

**Questions or Issues?**
- Check the [TROUBLESHOOTING.md](../TROUBLESHOOTING.md) guide
- Review BIND9 logs: `sudo journalctl -u bind9 -f`
- Verify network connectivity: `ping 168.63.129.16`
