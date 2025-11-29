# Lab 3: Custom DNS Misconfiguration

## 🎯 Overview

This exercise simulates a scenario where the VNet is configured to use a custom DNS server (BIND9 at `10.1.2.50`) that is **misconfigured** and forwards all DNS queries to Google DNS (8.8.8.8) instead of Azure DNS for Azure Private Link zones.

**Scenario:**
- Your VNet is configured with a custom DNS server at `10.1.2.50` running BIND9.
- The DNS server is configured to forward **all** queries to Google DNS (8.8.8.8, 8.8.4.4).
- Google DNS cannot resolve Azure Private Link zones (e.g., `privatelink.vaultcore.azure.net`).
- **Result:** DNS queries for the Key Vault's private endpoint fail because they are forwarded to Google DNS instead of Azure DNS (168.63.129.16).

---

## 📋 Prerequisites

Before starting Lab 3, you need to build the custom DNS server image:

```bash
./scripts/build-dns-image.sh
```

This script will:
1. Create a temporary Ubuntu VM
2. Install and configure BIND9 with Google DNS forwarders (broken state)
3. Install troubleshooting tools (dig, nslookup, tcpdump)
4. Install GitHub Copilot CLI and Azure CLI
5. Capture the VM as a managed image
6. Provide the image ID to add to `terraform.tfvars`

**Add the image ID to your `terraform.tfvars`:**
```terraform
custom_dns_image_id = "/subscriptions/.../resourceGroups/rg-dns-lab-images/providers/Microsoft.Compute/images/dns-server-lab3-bind9"
```

---

## 💥 Start the Scenario

To start Lab 3, deploy the infrastructure with the DNS server:

```bash
terraform apply -var="lab_scenario=dns_exercise3"
```

This will:
- Deploy a custom DNS server VM at `10.1.2.50` with BIND9 pre-configured
- Configure the VNet to use `10.1.2.50` as its DNS server
- The DNS server forwards **all** queries to Google DNS (broken state)

> **Note:** Once deployed, you are the on-call responder. The application team reports that the Azure DevOps pipeline is failing to retrieve secrets from Key Vault.

**Verify the failure from the agent VM:**
```bash
# SSH to your agent VM
ssh azureuser@<agent-vm-public-ip>

# Test DNS resolution
nslookup <your-keyvault-name>.vault.azure.net
```

Expected result: The query will either timeout or return a public IP instead of the private endpoint IP.

---

## 🕵️ Troubleshooting Steps

### 1. Identify the Symptoms
- **Symptom:** DNS resolution for Key Vault returns wrong IP or times out.
- **Check:** What DNS server is my VM using?

```bash
resolvectl status
# Look for "DNS Servers" entry
```
*You should see `10.1.2.50` configured as the DNS server.*

### 2. Verify DNS Server Reachability
```bash
ping 10.1.2.50
```
*The DNS server should be reachable (it exists!).*

### 3. SSH to the DNS Server
```bash
# From your local machine
ssh azureuser@<agent-vm-ip>

# From the agent VM, SSH to the DNS server
ssh 10.1.2.50
```

### 4. Check BIND9 Configuration
```bash
# Check BIND9 status
sudo systemctl status bind9

# Check current configuration
sudo cat /etc/bind/named.conf.options

# Check query logs
sudo tail -f /var/log/bind/query.log
```

**What you'll discover:**
- BIND9 is forwarding **all** queries to Google DNS (8.8.8.8, 8.8.4.4)
- Google DNS cannot resolve Azure Private Link zones
- You need to configure BIND9 to forward `privatelink.vaultcore.azure.net` queries to Azure DNS (168.63.129.16)

### 5. Test Current DNS Resolution
```bash
# Test from the DNS server itself
dig @localhost <your-keyvault-name>.vault.azure.net

# What does Azure DNS return?
dig @168.63.129.16 <your-keyvault-name>.vault.azure.net

# What does Google DNS return?
dig @8.8.8.8 <your-keyvault-name>.vault.azure.net
```

---

## 🛠️ Fix the Issue

You need to configure BIND9 to forward Azure Private Link queries to Azure DNS (168.63.129.16) instead of Google DNS.

### Option 1: The "Easy" Fix (Helper Script)
A helper script is pre-installed on the DNS server:

```bash
# SSH to the DNS server
ssh 10.1.2.50

# Check current status
sudo /usr/local/bin/toggle-azure-dns.sh status

# Enable Azure DNS forwarding for privatelink zones
sudo /usr/local/bin/toggle-azure-dns.sh enable

# Verify BIND9 restarted successfully
sudo systemctl status bind9
```

### Option 2: The "Real World" Fix (Manual)
Edit the BIND9 configuration manually:

```bash
# SSH to the DNS server
ssh 10.1.2.50

# Check if azure-privatelink.conf exists
cat /etc/bind/azure-privatelink.conf

# Edit named.conf.local to include the Azure DNS forwarder
sudo nano /etc/bind/named.conf.local

# Add these lines at the end:
# // Azure Private Link DNS Forwarding
# include "/etc/bind/azure-privatelink.conf";

# Check configuration is valid
sudo named-checkconf

# Restart BIND9
sudo systemctl restart bind9

# Verify it's running
sudo systemctl status bind9
```

### What This Does
The fix adds a conditional forwarder that:
1. Keeps Google DNS as the default forwarder for internet queries
2. Adds a **specific** forwarder for `privatelink.vaultcore.azure.net` to Azure DNS (168.63.129.16)
3. Azure DNS resolves the private endpoint IP correctly

---

## ✅ Verification

1. **Test DNS Resolution from the DNS Server:**
   ```bash
   # SSH to the DNS server
   ssh 10.1.2.50
   
   # Test Key Vault resolution
   dig @localhost <your-keyvault-name>.vault.azure.net
   
   # Should now return the private endpoint IP (10.1.2.x)
   ```

2. **Test from the Agent VM:**
   ```bash
   # SSH to the agent VM
   ssh azureuser@<agent-vm-ip>
   
   # Test resolution
   nslookup <your-keyvault-name>.vault.azure.net
   
   # Should return the private endpoint IP
   ```

3. **Check BIND9 Query Logs:**
   ```bash
   # SSH to the DNS server
   ssh 10.1.2.50
   
   # Watch the logs
   sudo tail -f /var/log/bind/query.log
   
   # From another terminal, query the Key Vault
   # You should see the query being forwarded to 168.63.129.16
   ```

4. **Test the Pipeline:**
   Re-run your Azure DevOps pipeline. It should now successfully retrieve secrets from Key Vault.

---

## 🧠 Key Takeaways

- **Custom DNS Complexity:** Using custom DNS servers requires proper configuration. They **must** forward Azure Private Link queries to Azure DNS (168.63.129.16), not external DNS providers.

- **Conditional Forwarding:** BIND9 (and other DNS servers) support conditional forwarding, which allows you to route specific domains to specific DNS servers while using a default forwarder for everything else.

- **168.63.129.16:** Azure's internal DNS resolver. It's the only DNS server that can resolve:
  - Azure Private Link zones (privatelink.*)
  - Azure-provided DNS for VMs
  - Custom Private DNS zones linked to VNets

- **Real-World Application:** In enterprise environments with custom DNS servers, you must configure them to forward:
  - `*.privatelink.*` → 168.63.129.16
  - `*.azure.net` → 168.63.129.16 (or use conditional forwarding)
  - Everything else → Your regular forwarders (e.g., on-premises DNS, public DNS)

- **Troubleshooting Tools:**
  - `dig` and `nslookup` for DNS queries
  - `tcpdump` for packet capture
  - BIND9 query logs for understanding DNS flow
  - `resolvectl status` to check client DNS configuration

---

## 🔄 Reset to Base State

To reset the lab environment:

```bash
terraform apply -var="lab_scenario=base"
```

Or destroy everything:

```bash
terraform destroy
```
