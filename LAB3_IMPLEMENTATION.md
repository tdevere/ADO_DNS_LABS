# Lab 3 Implementation Complete ✅

## Summary of Changes

The prompt has been successfully executed. Lab 3 (Custom DNS Misconfiguration) is now fully implemented with all required components.

## Files Created

1. **`cloud-init-dns.yaml`** - Complete cloud-init configuration for DNS server
2. **`docs/LAB3_IMAGE_BUILD.md`** - Comprehensive image build guide

## Files Modified

1. **`variables.tf`** - Added `custom_dns_image_id` variable
2. **`main.tf`** - Added DNS server VM resources (NIC and VM)
3. **`outputs.tf`** - Added DNS server outputs
4. **`scripts/build-dns-image.sh`** - Enhanced with:
   - Azure DNS conditional forwarder template
   - Toggle helper script
   - GitHub Copilot CLI installation
   - Azure CLI installation
   - Additional troubleshooting tools
5. **`labs/lab3/README.md`** - Complete rewrite with step-by-step guide

## Architecture

```
VNet with Custom DNS [10.1.2.50]
├── Agent VM (uses custom DNS)
└── DNS Server VM (10.1.2.50)
    ├── BIND9 (Port 53)
    ├── Default: Forwards to Google DNS (BROKEN)
    └── Fixed: Forwards privatelink.* to Azure DNS (168.63.129.16)
```

## How It Works

### Broken State (Default)
- BIND9 forwards ALL queries to Google DNS (8.8.8.8)
- Google DNS cannot resolve Azure Private Link zones
- Key Vault resolution fails

### Fixed State (After Configuration)
- BIND9 has conditional forwarder for `privatelink.vaultcore.azure.net`
- Conditional forwarder sends queries to Azure DNS (168.63.129.16)
- Azure DNS resolves private endpoint IP
- Key Vault resolution succeeds

## Usage

### 1. Build the DNS Server Image
```bash
./scripts/build-dns-image.sh
```

### 2. Add Image ID to terraform.tfvars
```terraform
custom_dns_image_id = "/subscriptions/.../images/dns-server-lab3-bind9"
```

### 3. Deploy Lab 3
```bash
terraform apply -var="lab_scenario=dns_exercise3"
```

### 4. Students Troubleshoot
Students will:
- Identify DNS misconfiguration
- SSH to DNS server (10.1.2.50)
- Analyze BIND9 configuration
- Enable Azure DNS forwarding using helper script
- Verify the fix

### 5. Helper Script
```bash
# Check status
sudo /usr/local/bin/toggle-azure-dns.sh status

# Enable Azure DNS forwarding
sudo /usr/local/bin/toggle-azure-dns.sh enable

# Disable (revert to broken state)
sudo /usr/local/bin/toggle-azure-dns.sh disable
```

## Key Learning Objectives

Students learn:
- How VNet custom DNS settings work
- Why 168.63.129.16 is critical for Azure Private Link
- BIND9 configuration and conditional forwarding
- DNS troubleshooting with dig, nslookup, query logs
- Best practices for custom DNS in hybrid environments

## Testing Checklist

- [ ] Run `./scripts/build-dns-image.sh` successfully
- [ ] Add image ID to terraform.tfvars
- [ ] Deploy with `terraform apply -var="lab_scenario=dns_exercise3"`
- [ ] Verify DNS server running at 10.1.2.50
- [ ] Verify BIND9 status with `sudo systemctl status bind9`
- [ ] Test broken state (Key Vault resolution fails)
- [ ] Run `sudo /usr/local/bin/toggle-azure-dns.sh enable`
- [ ] Test fixed state (Key Vault resolution succeeds)
- [ ] Check query logs: `sudo tail -f /var/log/bind/query.log`
- [ ] Destroy with `terraform destroy`

## Next Steps

1. Test the complete implementation
2. Run through the lab as a student would
3. Verify all documentation is accurate
4. Share with students

---

**All prompt requirements have been implemented successfully!**
