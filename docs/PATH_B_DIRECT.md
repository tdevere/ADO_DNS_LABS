# Path B: Simplified Direct VM Testing

## 🎯 Overview

This path focuses on DNS troubleshooting without requiring Azure DevOps setup. You'll deploy infrastructure, SSH directly to test VMs, and manually test DNS resolution and Key Vault connectivity.

**Perfect for students who want to:**
- Focus on DNS concepts
- Avoid Azure DevOps complexity
- Get hands-on quickly
- Learn real-world troubleshooting skills

**Time Estimate:** 3-4 hours for all three labs

---

## 📋 Prerequisites

Before starting, ensure you have completed:

✅ Azure subscription with Contributor access  
✅ SSH key pair generated (`~/.ssh/terraform_lab_key`)  
✅ Azure CLI authenticated (`az login`)  
✅ Terraform installed  
✅ Setup script completed (`./setup.sh`)

---

## 🚀 Getting Started

### Step 1: Deploy Base Infrastructure

From the `labs/dns-standalone/terraform` directory:

```bash
cd labs/dns-standalone/terraform

# Review what will be created
terraform plan

# Deploy infrastructure (takes ~5-10 minutes)
terraform apply

# Note the outputs - you'll need these
terraform output
```

**What Gets Deployed:**
- 2 Resource groups
- 2 Virtual networks with peering
- 1 Linux VM (agent-vm) for testing
- 1 Azure Key Vault with private endpoint
- 1 Private DNS zone with proper configuration
- Network security groups

**Important Outputs:**
```bash
# Get VM public IP for SSH
terraform output -raw agent_vm_public_ip

# Get Key Vault name for testing
terraform output -raw key_vault_name

# Get Private Endpoint IP (what DNS should return)
terraform output -raw key_vault_private_ip
```

---

### Step 2: Create Test Secret in Key Vault

Before testing, create a secret in the Key Vault:

```bash
# Get Key Vault name
KV_NAME=$(terraform output -raw key_vault_name)

# Create test secret
az keyvault secret set \
  --vault-name $KV_NAME \
  --name "TestSecret" \
  --value "HelloFromDNSLab"

# Verify secret exists
az keyvault secret show \
  --vault-name $KV_NAME \
  --name "TestSecret" \
  --query "value" -o tsv
```

---

### Step 3: Verify Base Configuration Works

Connect to the VM and test basic functionality:

```bash
# Get VM public IP
VM_IP=$(terraform output -raw agent_vm_public_ip)
KV_NAME=$(terraform output -raw key_vault_name)

# SSH to the VM
ssh -i ~/.ssh/terraform_lab_key azureuser@$VM_IP

# Once connected, test DNS resolution
nslookup $KV_NAME.vault.azure.net
# Expected: Should return private IP (10.1.2.x)

# Test Key Vault connectivity
curl -v https://$KV_NAME.vault.azure.net
# Expected: SSL handshake succeeds (even if auth fails)
```

**If everything works, you're ready for the labs! 🎉**

---

## 🧪 Lab Exercises

### Lab 1: DNS A Record Misconfiguration (EXE_04)

**Scenario:** DNS A record points to wrong IP address.

#### Deploy the Failure

```bash
# From labs/dns-standalone/terraform directory
cd labs/dns-standalone/terraform

# Switch to exercise 1
terraform apply -var="lab_scenario=dns_exercise1"
```

**What Changed:**
- DNS A record now points to 10.1.2.50 (wrong IP)
- Private endpoint still at correct IP (10.1.2.4)

#### Troubleshoot

SSH to the VM and diagnose:

```bash
# SSH to VM
ssh -i ~/.ssh/terraform_lab_key azureuser@$VM_IP

# Get Key Vault name (pass as env var or type it)
KV_NAME="your-kv-name"

# Test DNS resolution
nslookup $KV_NAME.vault.azure.net
# Question: What IP does it return?
# Expected: 10.1.2.50 (WRONG!)

# What SHOULD it be?
# Check Terraform output: terraform output -raw key_vault_private_ip
# Expected: 10.1.2.4 (CORRECT)

# Try to connect
curl -v --max-time 5 https://$KV_NAME.vault.azure.net
# Expected: Connection timeout (nothing at 10.1.2.50)
```

#### Identify the Issue

From your local machine:

```bash
# Check what the A record contains
az network private-dns record-set a show \
  --resource-group tf-connect-lab-rg \
  --zone-name privatelink.vaultcore.azure.net \
  --name $KV_NAME \
  --query "aRecords[0].ipv4Address" -o tsv
# Expected: 10.1.2.50 (WRONG!)

# What should it be?
terraform output -raw key_vault_private_ip
# Expected: 10.1.2.4 (CORRECT)
```

#### Fix the Issue

**Option 1: Via Terraform (Recommended)**
```bash
cd labs/dns-standalone/terraform
terraform apply -var="lab_scenario=base"
```

**Option 2: Via Azure CLI (Manual)**
```bash
# Get correct IP
CORRECT_IP=$(terraform output -raw key_vault_private_ip)

# Update A record
az network private-dns record-set a update \
  --resource-group tf-connect-lab-rg \
  --zone-name privatelink.vaultcore.azure.net \
  --name $KV_NAME \
  --set aRecords[0].ipv4Address=$CORRECT_IP
```

#### Verify the Fix

```bash
# SSH back to VM
ssh -i ~/.ssh/terraform_lab_key azureuser@$VM_IP

# Test DNS again
nslookup $KV_NAME.vault.azure.net
# Expected: Now returns 10.1.2.4 ✅

# Test connectivity
curl -v https://$KV_NAME.vault.azure.net
# Expected: SSL handshake succeeds ✅
```

**🎓 Key Learnings:**
- DNS can resolve successfully but return wrong IP
- Connection failures don't always mean DNS is broken
- Always verify the IP returned matches expected private endpoint
- A records must be kept in sync with private endpoint IPs

---

### Lab 2: Missing VNet Links (EXE_05)

**Scenario:** Private DNS zone exists but VNet links are missing.

#### Deploy the Failure

```bash
cd labs/dns-standalone/terraform
terraform apply -var="lab_scenario=dns_exercise2"
```

**What Changed:**
- VNet links removed from Private DNS zone
- A record still correct (this is NOT Lab 1)
- VMs can't reach Private DNS zone

#### Troubleshoot

```bash
# SSH to VM
ssh -i ~/.ssh/terraform_lab_key azureuser@$VM_IP

# Test DNS resolution
nslookup $KV_NAME.vault.azure.net
# Expected: NXDOMAIN or falls back to public IP
```

#### Identify the Issue

From your local machine:

```bash
# Check if VNet links exist
az network private-dns link vnet list \
  --resource-group tf-connect-lab-rg \
  --zone-name privatelink.vaultcore.azure.net \
  --output table
# Expected: Empty list (no links!)

# Verify A record is correct (to rule out Lab 1 issue)
az network private-dns record-set a show \
  --resource-group tf-connect-lab-rg \
  --zone-name privatelink.vaultcore.azure.net \
  --name $KV_NAME \
  --query "aRecords[0].ipv4Address" -o tsv
# Expected: Correct IP (10.1.2.4)

# So A record is fine, but VNet links missing!
```

#### Fix the Issue

**Option 1: Via Terraform (Recommended)**
```bash
cd labs/dns-standalone/terraform
terraform apply -var="lab_scenario=base"
```

**Option 2: Via Azure CLI (Manual)**
```bash
# Get VNet IDs
AGENT_VNET_ID=$(az network vnet show \
  --resource-group tf-agent-lab-rg \
  --name agent-vnet \
  --query id -o tsv)

CONNECT_VNET_ID=$(az network vnet show \
  --resource-group tf-connect-lab-rg \
  --name connect-vnet \
  --query id -o tsv)

# Create VNet link for agent VNet
az network private-dns link vnet create \
  --resource-group tf-connect-lab-rg \
  --zone-name privatelink.vaultcore.azure.net \
  --name agent-vnet-link \
  --virtual-network $AGENT_VNET_ID \
  --registration-enabled false

# Create VNet link for connectivity VNet
az network private-dns link vnet create \
  --resource-group tf-connect-lab-rg \
  --zone-name privatelink.vaultcore.azure.net \
  --name connect-vnet-link \
  --virtual-network $CONNECT_VNET_ID \
  --registration-enabled false
```

#### Verify the Fix

```bash
# Check VNet links exist
az network private-dns link vnet list \
  --resource-group tf-connect-lab-rg \
  --zone-name privatelink.vaultcore.azure.net \
  --output table
# Expected: 2 links shown

# SSH to VM and test
ssh -i ~/.ssh/terraform_lab_key azureuser@$VM_IP
nslookup $KV_NAME.vault.azure.net
# Expected: Now returns private IP ✅
```

**🎓 Key Learnings:**
- VNet peering enables network connectivity, NOT DNS sharing
- Private DNS zones require explicit VNet links
- Without VNet links, VMs can't resolve private DNS records
- Each VNet needs its own link to access the Private DNS zone

---

### Lab 3: Custom DNS Server (EXE_06)

**Scenario:** Custom DNS server forwards to wrong upstream.

#### Deploy the Failure

```bash
cd labs/dns-standalone/terraform
terraform apply -var="lab_scenario=dns_exercise3"
```

**What Changed:**
- Custom DNS server deployed at 10.0.1.100
- Agent VM configured to use custom DNS first
- Custom DNS forwards to Google (8.8.8.8) instead of Azure DNS

#### Troubleshoot

```bash
# SSH to VM
ssh -i ~/.ssh/terraform_lab_key azureuser@$VM_IP

# Check DNS configuration
cat /etc/resolv.conf
# Expected: nameserver 10.0.1.100 (custom DNS)
#           nameserver 168.63.129.16 (Azure DNS as fallback)

# Test DNS resolution
nslookup $KV_NAME.vault.azure.net
# Expected: Returns public IP or NXDOMAIN (WRONG!)

# Test bypassing custom DNS - query Azure DNS directly
nslookup $KV_NAME.vault.azure.net 168.63.129.16
# Expected: Returns private IP! (Azure DNS works fine)
```

#### Identify the Issue

The problem is with the custom DNS server. SSH to it:

```bash
# Get DNS server public IP
DNS_SERVER_IP=$(terraform output -raw custom_dns_server_public_ip)

# SSH to DNS server
ssh -i ~/.ssh/terraform_lab_key azureuser@$DNS_SERVER_IP

# Check BIND configuration
sudo cat /etc/bind/named.conf.options
# Look for: forwarders { 8.8.8.8; };
# This is WRONG - should forward Azure queries to 168.63.129.16

# Check conditional forwarders
sudo cat /etc/bind/named.conf.local
# Expected: Empty or no conditional forwarder for privatelink
```

#### Fix the Issue

On the DNS server:

```bash
# Edit BIND configuration
sudo nano /etc/bind/named.conf.local

# Add this configuration:
# zone "privatelink.vaultcore.azure.net" {
#     type forward;
#     forward only;
#     forwarders { 168.63.129.16; };
# };

# Save and exit (Ctrl+O, Enter, Ctrl+X)

# Check configuration syntax
sudo named-checkconf

# Restart BIND
sudo systemctl restart bind9

# Verify BIND is running
sudo systemctl status bind9
```

#### Verify the Fix

```bash
# On DNS server, test resolution
nslookup $KV_NAME.vault.azure.net localhost
# Expected: Returns private IP ✅

# SSH back to agent VM
ssh -i ~/.ssh/terraform_lab_key azureuser@$VM_IP

# Clear DNS cache
sudo systemd-resolve --flush-caches

# Test DNS resolution
nslookup $KV_NAME.vault.azure.net
# Expected: Now returns private IP via custom DNS ✅

# Test connectivity
curl -v https://$KV_NAME.vault.azure.net
# Expected: SSL handshake succeeds ✅
```

**🎓 Key Learnings:**
- Custom DNS servers need conditional forwarders for Azure
- Azure DNS (168.63.129.16) is authoritative for privatelink zones
- Public DNS servers (Google, Cloudflare) don't know about private zones
- Enterprise environments require proper DNS forwarding configuration

---

## 🧹 Cleanup

When finished with all labs:

```bash
# From labs/dns-standalone/terraform directory
terraform destroy -auto-approve

# Verify resources deleted
az group list --query "[?starts_with(name, 'tf-')].name" -o table

# If any remain, delete manually
az group delete --name tf-agent-lab-rg --yes --no-wait
az group delete --name tf-connect-lab-rg --yes --no-wait
```

---

## 🎓 Summary

You've completed three DNS troubleshooting scenarios:

1. **Lab 1 (EXE_04):** Wrong DNS A record
   - Symptom: DNS works but returns wrong IP
   - Fix: Correct the A record

2. **Lab 2 (EXE_05):** Missing VNet links
   - Symptom: DNS fails completely (NXDOMAIN)
   - Fix: Create VNet links to Private DNS zone

3. **Lab 3 (EXE_06):** Custom DNS misconfiguration
   - Symptom: Returns public IP instead of private
   - Fix: Configure conditional forwarding to Azure DNS

**Real-World Application:**
These scenarios mirror common production issues when deploying Azure private endpoints. You now have the skills to:
- Diagnose DNS failures systematically
- Use appropriate tools (nslookup, dig, Azure CLI)
- Understand Azure Private DNS architecture
- Configure hybrid DNS environments

---

## 📚 Next Steps

- Review [../EXE_04_DNS_A_RECORD/EXE_04_DNS_A_RECORD.md](../../EXE_04_DNS_A_RECORD/EXE_04_DNS_A_RECORD.md) for detailed explanations
- Review [../EXE_05_DNS_ZONE_LINK/EXE_05_DNS_ZONE_LINK.md](../../EXE_05_DNS_ZONE_LINK/EXE_05_DNS_ZONE_LINK.md)
- Review [../EXE_06_CUSTOM_DNS/EXE_06_CUSTOM_DNS.md](../../EXE_06_CUSTOM_DNS/EXE_06_CUSTOM_DNS.md)
- Explore other labs in the repository
- Apply these skills to your own Azure environments

---

**Questions?** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or open a GitHub issue.
