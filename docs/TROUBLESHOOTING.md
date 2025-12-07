# ADO DNS Labs - Troubleshooting Guide

## SSH Connection Issues

### Symptom: SSH Connection Hangs/Times Out

**Error:**
```
ssh azureuser@<VM_IP>
# Connection hangs indefinitely
```

**Diagnosis:**
1. Check if VM is running:
   ```bash
   az vm get-instance-view \
     --resource-group <RG_NAME> \
     --name <VM_NAME> \
     --query "instanceView.statuses[?starts_with(code, 'PowerState')].displayStatus" -o tsv
   ```
   Expected: `VM running`

2. Check NSG rules:
   ```bash
   az network nsg rule list \
     --resource-group <RG_NAME> \
     --nsg-name nsg-agent-vm \
     --query "[?destinationPortRange=='22'].{Name:name,Access:access,Priority:priority}" -o table
   ```
   Expected: Should see an `Allow` rule for port 22

3. Test basic connectivity:
   ```bash
   # Can you reach the IP?
   ping -c 4 <VM_IP>
   
   # Is port 22 responding?
   nc -zv <VM_IP> 22
   ```

**Root Cause:**
NSG rules were missing (empty security groups). This can happen if:
- Terraform state drifted from actual Azure resources
- NSG was manually modified in Portal
- Terraform apply failed partway through

**Fix:**
Restore NSG rules using Terraform:
```bash
terraform apply -auto-approve \
  -target=azurerm_network_security_group.nsg \
  -target=azurerm_network_security_group.subnet_nsg
```

---

### Symptom: "Permission denied (publickey)"

**Error:**
```
ssh azureuser@<VM_IP>
azureuser@<VM_IP>: Permission denied (publickey).
```

**Diagnosis:**
- ✅ SSH port 22 is reachable (good!)
- ❌ You don't have the correct SSH private key

**Root Cause:**
The VM uses SSH key authentication (`disable_password_authentication = true`), but you're not providing the private key.

**Fix:**
Use the SSH key generated during setup:
```bash
ssh -i ~/.ssh/terraform_lab_key azureuser@<VM_IP>
```

If the key doesn't exist, regenerate it:
```bash
./scripts/generate-ssh-key.sh --force
terraform apply -auto-approve  # Re-deploy VM with new public key
```

---

## Lab 1 Specific Issues

### DNS A Record Shows Wrong IP

**Symptom:** Pipeline times out connecting to Key Vault

**Diagnosis:**
```bash
# From agent VM:
nslookup <kv-name>.vault.azure.net

# Check DNS zone:
az network private-dns record-set a show \
  --resource-group <RG_NAME> \
  --zone-name privatelink.vaultcore.azure.net \
  --name <kv-name> \
  --query "aRecords[0].ipv4Address" -o tsv

# Check actual Private Endpoint IP:
az network private-endpoint show \
  --resource-group <RG_NAME> \
  --name pe-kv-dns-lab \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv
```

**Expected:** All three should return the same IP (e.g., `10.1.2.5`)

**Fix (if DNS A record is wrong):**
```bash
# Get correct IP
CORRECT_IP=$(az network private-endpoint show \
  --resource-group <RG_NAME> \
  --name pe-kv-dns-lab \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv)

# Update DNS record
terraform apply -auto-approve -target=azurerm_private_dns_a_record.kv_record
```

---

## Infrastructure Drift Detection

### Check for Drift

Compare Terraform state with actual Azure resources:
```bash
terraform plan
```

Look for resources showing `~` (modify) or `+` (create) when nothing should have changed.

### Common Drift Scenarios

1. **NSG rules modified manually**
   - Symptom: `terraform plan` shows security rules being added/removed
   - Fix: `terraform apply -target=azurerm_network_security_group.nsg`

2. **DNS A record changed**
   - Symptom: `terraform plan` shows `records` changing
   - Fix: `terraform apply -target=azurerm_private_dns_a_record.kv_record`

3. **VNet link removed**
   - Symptom: DNS resolution returns public IPs from agent
   - Fix: `terraform apply -target=azurerm_private_dns_zone_virtual_network_link.link`

---

## Azure DevOps Agent Issues

### Agent Offline/Not Responding

**Check agent status:**
```bash
# From Azure DevOps Portal
Organization Settings → Agent Pools → DNS-Lab-Pool → Agents tab

# From agent VM
ssh -i ~/.ssh/terraform_lab_key azureuser@<VM_IP>
sudo systemctl status azureagent
```

**Restart agent:**
```bash
ssh -i ~/.ssh/terraform_lab_key azureuser@<VM_IP>
cd /home/azureuser/agent
sudo ./svc.sh stop
sudo ./svc.sh start
```

---

## Key Vault Access Issues

### "Public network access is disabled"

**Error in Terraform:**
```
Error: making Read request on Azure KeyVault Secret AppMessage: 
StatusCode=403 Code="Forbidden" Message="Public network access is disabled"
```

**Root Cause:**
Terraform is running from Codespace (outside the private network) and Key Vault blocks public access.

**Options:**

1. **Temporarily enable public access** (for Terraform operations only):
   ```bash
   az keyvault update \
     --name <kv-name> \
     --resource-group <RG_NAME> \
     --public-network-access Enabled
   
   # Run Terraform
   terraform apply
   
   # Disable again
   az keyvault update \
     --name <kv-name> \
     --resource-group <RG_NAME> \
     --public-network-access Disabled
   ```

2. **Use targeted apply** (skip Key Vault secret refresh):
   ```bash
   terraform apply -target=azurerm_network_security_group.nsg
   ```

3. **Run Terraform from agent VM** (inside private network):
   ```bash
   ssh -i ~/.ssh/terraform_lab_key azureuser@<VM_IP>
   git clone <your-repo>
   cd ADO_DNS_LABS
   terraform apply
   ```

---

## General Azure CLI Tips

### Session Expired
```bash
az login --use-device-code
```

### Wrong Subscription Selected
```bash
az account list --output table
az account set --subscription "<subscription-name-or-id>"
```

### Resource Not Found
Verify you're in the correct resource group:
```bash
az group list --query "[?contains(name, 'dns-lab')].name" -o tsv
```

---

## Need More Help?

1. Check pipeline logs in Azure DevOps
2. Review Terraform state: `terraform state list`
3. Check Azure Portal for resource status
4. Review cloud-init logs on agent VM: `sudo cat /var/log/cloud-init-output.log`
