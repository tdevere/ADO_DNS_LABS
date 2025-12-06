# Lab 3: Custom DNS Server Misconfiguration

## 📋 Objectives

**What Breaks**: The VNet DNS settings change from Azure-provided DNS to a custom DNS server (10.1.2.50) that lacks proper forwarding rules for Azure Private Link zones.

**What You'll Learn**:
- How custom DNS servers interact with Azure Private DNS Zones
- Why 168.63.129.16 (Azure Recursive Resolver) is critical for Private Link
- How to diagnose DNS forwarding chain issues
- When to use conditional forwarding vs global forwarding
- Collaboration with DNS administrator teams

**What You'll Fix**: Configure conditional forwarding rule on custom DNS server to forward `*.privatelink.*` queries to Azure DNS (168.63.129.16).

---

## 📧 Background Story

You are Jordan Chen, DevOps Engineer at Contoso HealthTech Solutions. After successfully resolving two previous DNS incidents over the past six weeks (Lab 1: wrong A record, Lab 2: missing VNet link), you've become the team's DNS expert. 

The pipeline is failing again with Key Vault access errors. Your manager wants you to carefully diagnose the custom DNS setup that the networking team recently deployed.

> **Real-World Context**: Organizations often deploy custom DNS servers (BIND, Windows DNS, Infoblox) for centralized DNS management without configuring proper forwarding for Azure Private Link zones. This manifests as "public network access" errors even though private endpoints exist and VNet links are configured correctly.

---

## Prerequisites

- Completed Lab 1 (DNS A Record Misconfiguration)
- Completed Lab 2 (Missing Virtual Network Link)  
- Understanding of DNS forwarding concepts
- Custom DNS server (BIND9) deployed in lab environment

> **Note:** This lab uses a pre-built custom DNS server image with BIND9. The break script reconfigures the VNet to use this custom DNS server instead of Azure-provided DNS.

---

## STEP 1: Review the Objectives

Before breaking anything, understand what you're about to investigate:

**The Break**: We'll reconfigure **Agent VNet → DNS Settings** to use a custom DNS server (10.1.2.50) instead of **Azure Recursive Resolver (168.63.129.16)**. The custom DNS server is misconfigured—it forwards all queries to public DNS (8.8.8.8) without conditional forwarding rules for Azure Private Link zones.

**Expected Symptom**: **Agent VM → DNS Resolver** will query **Custom DNS Server (10.1.2.50)**, which forwards to **Google DNS (8.8.8.8)**, which returns public IP addresses. **Pipeline → AzureKeyVault@2 Task** fails because it attempts connection to public IP while **Key Vault → Network Firewall** blocks public access.

**Learning Goal**: Understand that custom DNS servers in Azure VNets **must** have conditional forwarding rules to send `*.privatelink.*` queries to **Azure Recursive Resolver (168.63.129.16)**. Without these rules, Private Link DNS resolution is impossible.

### The Critical IP: 168.63.129.16

**What is it?**
- **Azure Wire Server / Recursive Resolver**
- **ONLY** accessible from inside Azure VNets (not from internet or on-premises)
- **ONLY** source for Azure Private DNS Zone queries
- Required for ALL Private Link DNS resolution

**Why it matters:**
- Public DNS servers (Google 8.8.8.8, Cloudflare 1.1.1.1) have NO knowledge of Azure Private DNS Zones
- Custom DNS servers in Azure can reach 168.63.129.16 to query Private DNS Zones
- Without forwarding to 168.63.129.16, Private Link zones cannot be resolved

---

## STEP 2: Break the Lab and Observe the Failure

Run the break script:
```bash
./break-lab.sh lab3
```

**What this does** (silently, like real-world changes):
- Reconfigures **Agent VNet → DNS Settings** to use custom DNS server (10.1.2.50)
- Custom DNS server has global forwarders pointing to Google DNS (8.8.8.8)
- Custom DNS server has NO conditional forwarding rules for `*.privatelink.*` zones
- Disables public network access on Key Vault (forces private endpoint use)

Now trigger your pipeline in Azure DevOps (push a commit or click "Run pipeline").

**Expected Error Output**:
```
Starting: Retrieve Configuration from Key Vault
==============================================================================
Task         : Azure Key Vault
Description  : Download Azure Key Vault secrets
Version      : 2.x.x
==============================================================================
Key vault name: keyvault-dnslab12345
Downloading secret value for: AppMessage
##[error]AppMessage: "Public network access is disabled and request is not from a trusted service nor via an approved private link.
Caller: appid=***;oid=...;
Vault: keyvault-dnslab12345;location=westus2"

##[error]Failed to fetch the value of secret AppMessage. Error: Public network access is disabled
Finishing: Retrieve Configuration from Key Vault
```

📸 **Take a screenshot** of this error - you'll need it for your collaboration request.

**Alternative Symptom** (if agent goes offline):
If DNS is completely broken, the agent may go offline and cannot even poll Azure DevOps. Check:
1. Azure DevOps → Project Settings → Agent Pools → DNS-Lab-Pool
2. Agent status shows **Offline**
3. Pipeline sits in "Queued" state indefinitely

---

## STEP 3: Understand the Architecture

Before diving into troubleshooting, understand the new component introduced in Lab 3:

### Discover Your Resources

**Azure Portal Navigation**:
1. Go to **Resource groups** → find `rg-dnslab`
2. Look for these resources:
   - **Key Vault** (keyvault-dnslab...)
   - **Private Endpoint** (pe-keyvault-...)
   - **Private DNS Zone** (privatelink.vaultcore.azure.net)
   - **Virtual Network** (vnet-agent)
   - **Virtual Machine** (vm-agent-dnslab - the agent)
   - **Virtual Machine** (vm-dns-server - **NEW in Lab 3**)

### Component Hierarchy with Custom DNS

```
Pipeline → RetrieveConfig Stage → AzureKeyVault@2 Task
    ↓ (runs on)
Agent VM → Network Stack → DNS Resolver
    ↓ (queries - CHANGED IN LAB 3)
Custom DNS Server (10.1.2.50) [BIND9]
    ↓ (forwards to - MISCONFIGURED)
Google DNS (8.8.8.8) [Public DNS, no Private Link knowledge]
    ↓ (returns)
Public IP Address (52.x.x.x) ← WRONG!

Expected path:
Custom DNS Server (10.1.2.50)
    ↓ (should forward *.privatelink.* to)
Azure Recursive Resolver (168.63.129.16)
    ↓ (queries)
Agent VNet → VNet Link → Private DNS Zone → A Record
    ↓ (returns)
Private IP Address (10.1.2.5) ← CORRECT!
```

### Key Difference from Labs 1-2

| Aspect | Labs 1-2 | Lab 3 |
|--------|----------|-------|
| **VNet DNS Settings** | Azure-provided (168.63.129.16) | Custom DNS server (10.1.2.50) |
| **DNS Query Path** | Direct to Azure Recursive Resolver | Through custom DNS server first |
| **Problem Location** | Private DNS Zone config | Custom DNS server forwarding rules |
| **Fix Involves** | Portal/CLI to fix Azure resources | DNS administrator to configure BIND9 |

### Update Your Email Draft

Open `EMAIL_TEMPLATE.md` in this lab folder and update:
- **Affected Resource Details** table (add Custom DNS Server row)
- **Error Messages** section (paste the error from STEP 2)
- **Timeline** section (note when custom DNS was deployed)

---

## STEP 4: Understand the Error

Let's interpret what the error message tells us:

| What the Error Says | Hierarchical Component | What This Means |
|---------------------|------------------------|-----------------|
| "Public network access is disabled" | **Key Vault → Network Settings** blocks public IPs | Key Vault requires private endpoint access only |
| "Request is not from a trusted service" | **Pipeline → Service Principal** identity is not in exception list | Authentication succeeded, but network path is wrong |
| "Nor via an approved private link" | **Agent VM → Network Path** didn't use Private Endpoint | Connection attempt came from public IP range, not private |

**Root Cause Hypothesis**: **Agent VM → DNS Resolver** is returning a public IP address instead of the **Private Endpoint → Private IP**, causing **Pipeline → AzureKeyVault@2 Task** to attempt connection over public internet (which Key Vault rejects).

**But wait...** Labs 1 and 2 had similar symptoms. What's different this time?

**Three Possible Root Causes**:
1. **Lab 1 scenario**: DNS A record points to wrong IP ← Check with `az network private-dns record-set a show`
2. **Lab 2 scenario**: VNet link missing ← Check with `az network private-dns link vnet list`
3. **Lab 3 scenario (NEW)**: Custom DNS server misconfigured ← Check **Agent VNet → DNS Settings** and **Custom DNS Server → Forwarding Rules**

---

## STEP 5: Complete Azure Guided Troubleshooter 🧭

Before collecting detailed data, complete the Azure Guided Troubleshooter workflow.

### Answer These 3 Questions

<details>
<summary><strong>Question 1: Does your issue involve resources in a Virtual Network (VNet)?</strong></summary>

**Your Answer**: ☑️ **Yes**

**Why**: 
- **Agent VM** runs in Agent VNet (10.1.0.0/16)
- **Custom DNS Server VM** runs in Agent VNet (10.1.2.50)
- **Private Endpoint** connects to Key Vault from VNet (10.1.2.5)
- **Private DNS Zone** requires VNet links to function

**Hint**: Custom DNS in VNets adds complexity to troubleshooting.

</details>

<details>
<summary><strong>Question 2: Are you experiencing an issue with DNS, Network connectivity, or Application-specific behavior?</strong></summary>

**Your Answer**: 🔹 **DNS issue**

**Why**: 
- The error says "not via approved private link"
- This suggests wrong IP address is being used
- DNS resolution determines which IP **Agent VM → DNS Resolver** returns
- If DNS returns public IP, connection fails at Key Vault firewall

**Hint**: Even though a custom DNS server is involved, the symptom is still DNS resolution returning wrong IP.

</details>

<details>
<summary><strong>Question 3: What DNS solution(s) does your architecture use?</strong></summary>

**Your Answer**: 🔹 **Custom DNS servers** (BIND9 at 10.1.2.50)

**Why**: 
- **Agent VNet → DNS Settings** points to 10.1.2.50 (not Azure-provided 168.63.129.16)
- **Custom DNS Server** is BIND9 running on a VM
- **Private DNS Zone** still exists and is linked to VNet
- Problem is **Custom DNS Server → Forwarding Rules**, not Private DNS Zone configuration

**Critical Note**: This answer differs from Labs 1-2! Custom DNS means Microsoft Azure Support may need to coordinate with your DNS administrator team, as they cannot directly access or modify customer-managed DNS infrastructure.

</details>

### Troubleshooter Result

**Routing**: SAP Azure / Azure DNS / Custom DNS Configuration

**Next Steps**: You've identified this involves custom DNS. Now collect diagnostic evidence showing how the custom DNS server is misconfigured.

**⚠️ Important**: In production, custom DNS issues require collaboration with DNS administrator team. Azure Support can provide guidance on proper forwarding configuration but cannot modify customer DNS servers.

### Update Your Email Template

Open `EMAIL_TEMPLATE.md` and complete:
- **Azure Guided Troubleshooter Responses** section (mark answer #3 as "Custom DNS servers")
- **Timeline** section (when was custom DNS deployed?)
- **Additional Context** section (DNS administrator contact if production)

💾 **Save your progress** - you'll send this to your instructor at STEP 10.

---

## 💡 TA Note: Before Escalating to Azure Networking Team

When troubleshooting private endpoint connectivity issues in production environments, Azure Support follows a systematic diagnostic process before escalating to specialized teams. This ensures the issue is well-documented and simple misconfigurations are caught early.

### Standard Troubleshooting Workflow

**Note:** Lab 3 involves custom DNS infrastructure, which falls under **Step 4: Review Network Policies**. Custom DNS servers are a common enterprise requirement but require proper configuration to work with Azure Private DNS zones.

Before opening a collaboration ticket with the Azure Networking Team, complete these diagnostic steps:

| Step | Description | Tools/Commands |
|------|-------------|----------------|
| **1. Run Guided Troubleshooter** | Perform initial diagnostics for DNS, NSG, and firewall issues | Azure Portal → Resource → Diagnose and Solve Problems |
| **2. Validate DNS Zone Links** | Ensure private DNS zones are linked to relevant VNets | `az network private-dns link vnet list` |
| **3. Test Endpoint Reachability** | Confirm connectivity to required endpoints over TLS 443 | `curl -v https://<endpoint>`, `telnet <ip> 443` |
| **4. Review Network Policies** | Check NSGs, route tables, subnet delegations, **and VNet DNS server settings** | Network Watcher, `az network nsg rule list`, `az network vnet show --query dhcpOptions.dnsServers` |
| **5. Verify Proxy Settings** | Ensure proxy variables are correctly configured | `echo $HTTP_PROXY`, `echo $HTTPS_PROXY` |
| **6. Collect Evidence** | Attach GT results, Network Watcher logs, and diagrams | Screenshots, command output, architecture diagrams |

### Why This Matters

**In this lab:** You have full control of the environment and can fix issues directly. However, understanding this workflow prepares you for real-world scenarios where:

- Custom DNS servers are managed by separate networking/infrastructure teams
- Support engineers will ask for this data before escalating internally
- Documenting your troubleshooting steps helps justify infrastructure changes to management
- You may need to explain why custom DNS requires specific forwarding rules

### For This Exercise

You'll focus on **Step 4** (reviewing VNet DNS configuration and custom DNS server setup). In production, you'd complete all six steps before escalating. The goal is to understand why the custom DNS server is preventing Azure service resolution.

**Key Questions to Answer:**
- Is the VNet configured to use a custom DNS server instead of Azure's default (168.63.129.16)?
- Is the custom DNS server properly configured to forward Azure service queries to Azure DNS?
- Does the custom DNS server need conditional forwarding rules for *.azure.com, *.vault.azure.net, etc.?

**Critical Concept:** When using custom DNS servers in Azure VNets, those servers MUST forward queries for Azure services to Azure's recursive resolver (168.63.129.16). Without proper forwarding, Private DNS zones cannot be queried, and all Azure service resolution fails.

Once you've gathered diagnostic evidence:
- ✅ **If you identify the issue:** Document the finding and implement the fix (VNet DNS settings or custom DNS forwarding)
- ⚠️ **If the issue remains unclear:** This is when you'd escalate to the Azure Networking Team with your complete diagnostic data

---

## 🔍 Investigation: Systematic Troubleshooting

Since the agent is offline, you can't use pipeline logs. You must investigate from the VM itself.

### STEP 1: Access the Agent VM

Use the SSH key provided in the lab environment:

```bash
# Get the VM's public IP
VM_IP=$(terraform output -raw vm_public_ip)

# SSH into the VM
ssh azureuser@$VM_IP
```

### STEP 2: Verify Connectivity

Once inside the VM, check if you can reach Azure DevOps.

**1. Test DNS resolution:**
```bash
nslookup dev.azure.com
```
*Does it return an IP address? Or does it time out/fail?*

**2. Test HTTP connectivity:**
```bash
curl -I https://dev.azure.com/ADOTrainingLab/
```
*Does it connect? Or do you get "Could not resolve host"?*

**3. Check DNS configuration:**
```bash
cat /etc/resolv.conf
```
*What nameserver is the VM using? Is it the custom DNS server (10.1.2.50)?*

---

### STEP 3: Investigate the Custom DNS Server

Now that you know the VM is using `10.1.2.50` and failing to resolve names, let's look at that server.

**1. Test the custom DNS server directly:**
```bash
dig @10.1.2.50 dev.azure.com
```
*Does the server answer? If not, is it even running?*

**2. Test the custom DNS server with a known public domain:**
```bash
dig @10.1.2.50 google.com
```
*Does it forward queries to the internet?*

**Discovery:**
The custom DNS server is configured to be an authoritative-only server for internal zones. It has **no forwarders** configured for public domains. This means it drops any query for `dev.azure.com`, `github.com`, or `microsoft.com`.

Without public DNS resolution, the agent cannot:
- Connect to Azure DevOps to get jobs
- Download artifacts
- Reach Azure Key Vault (public endpoint)

---

## 🛠️ Fix the Issue

You have identified the root cause: **The custom DNS server is missing forwarders.**

### Option 1: Fix the DNS Server (The "Right" Fix)

In a real scenario, you would ask the networking team to configure forwarding on their BIND server. Since you don't have access to the DNS server VM in this lab, we will simulate the fix by reverting to Azure DNS.

### Option 2: Revert to Azure DNS (The Lab Fix)

To restore service immediately, we will revert the VNet configuration to use Azure's default DNS.

**1. Run the fix script:**
```bash
# Run this from your Codespace (not the agent VM)
./fix-lab.sh lab3
```

**2. Verify the fix:**
- Wait 30 seconds for the agent to reconnect.
- Check Azure DevOps → Agent Pools. Is the agent **Online**?
- Run the pipeline again. Does it succeed?

---

## 🧠 Reflection

1. **Why did the agent go offline?**
   - The agent polls `dev.azure.com` to ask for work.
   - When DNS broke, it couldn't resolve the URL, so it couldn't connect.

2. **Why didn't we see an error in the pipeline logs?**
   - Because the pipeline never started! The agent couldn't pick up the job.

3. **How would you prevent this in production?**
   - **Monitoring:** Alert on agent offline status.
   - **DNS Redundancy:** Configure a secondary DNS server (e.g., Azure DNS `168.63.129.16`) as a backup in the VNet settings.
   - **Hybrid DNS:** Ensure custom DNS servers have proper forwarders to Azure DNS or public resolvers (8.8.8.8).

---

## 🧹 Cleanup

When you're done with the lab, destroy the infrastructure to save costs:

```bash
./scripts/cleanup.sh
```

```
   - Does the Key Vault have a private endpoint? (Check Azure portal)
   - Is the private endpoint "Approved"?
   - What DNS server is the VNet configured to use?

4. **What's different from Labs 1-2?**
   - In Labs 1-2, the VNet used Azure-provided DNS
   - What's different now?

**🤔 Think about it:**
- If the error says "public network access" but a private endpoint exists, what might be wrong?
- Why would introducing a custom DNS server break Private Link connectivity?

<details>
<summary>💡 Hint: DNS Resolution Path</summary>

When the agent VM queries DNS:
1. It uses whatever DNS server the VNet is configured with
2. That DNS server determines where to look for answers
3. If the DNS server doesn't know about Azure Private Link zones, what will it return?
</details>

---

### STEP 2: Analyze DNS Resolution

**Your investigation approach:**

You need to compare what DNS returns from different perspectives.

**Questions to answer:**
1. What IP does DNS return when you query from the **internet** (your Codespace)?
2. What IP does DNS return when you query from the **agent VM** (inside the VNet)?
3. Are these IPs the same or different?
4. What IP **should** the agent VM be getting?

**Useful commands:**
```bash
# Get Key Vault name
KV_NAME=$(terraform output -raw key_vault_name)

# Test from Codespace (public perspective)
nslookup ${KV_NAME}.vault.azure.net

# Test from agent VM (private perspective)
VM_IP=$(terraform output -raw vm_public_ip)
ssh azureuser@${VM_IP}
nslookup ${KV_NAME}.vault.azure.net
```

**🤔 What to look for:**
- Public IP addresses typically start with: 13.x, 20.x, 40.x, 52.x, 104.x
- Private IP addresses typically start with: 10.x, 172.16-31.x, 192.168.x
- The private endpoint IP is `10.1.2.5` (you can verify in Azure portal)

<details>
<summary>💡 Hint: Split-Horizon DNS</summary>

Key Vault has **two** DNS records:
- **Public DNS:** Returns a public IP (for internet access)
- **Private DNS:** Returns a private IP (when private endpoint is configured)

Which one should the agent VM be getting?
</details>

---

### STEP 3: Investigate the DNS Chain

If the agent VM is getting the wrong IP, you need to understand **why**.

**Key questions:**
1. What DNS server is the agent VM configured to use?
2. Is it using Azure-provided DNS (168.63.129.16) or a custom DNS server?
3. If it's using a custom DNS server, where is that server getting its answers?

**Discovery tasks:**
- Check the agent VM's DNS configuration
  - Hint: On Linux, `resolvectl status` shows DNS settings
- Identify the DNS server IP
- Compare to the custom DNS server IP mentioned in the ticket (10.1.2.50)

**🤔 Think about it:**
- If the agent is using the custom DNS server, why would it return a public IP?
- Where does a DNS server get answers when it doesn't know them itself?
- What's the technical term for this behavior?

<details>
<summary>💡 Hint: DNS Forwarding</summary>

When a DNS server doesn't have an authoritative answer, it **forwards** the query to another DNS server (called an "upstream" DNS server or "forwarder"). The question is: where is the custom DNS server forwarding queries?
</details>

---

### STEP 4: Test the Custom DNS Server Directly

Let's query the custom DNS server explicitly to see what it's doing:

```bash
# From the agent VM, query the custom DNS directly
dig @10.1.2.50 ${KV_NAME}.vault.azure.net

# What does it return?
```

**Expected output (broken):**
```
;; ANSWER SECTION:
kv-dns-lab-xxxxxxxx.vault.azure.net. 60 IN A 40.78.x.x
```

✗ **Problem confirmed:** The custom DNS server is returning a public IP.

**Now test Azure DNS directly:**
```bash
# Query Azure DNS (168.63.129.16) instead
dig @168.63.129.16 ${KV_NAME}.vault.azure.net
```

**Expected output:**
```
;; ANSWER SECTION:
kv-dns-lab-xxxxxxxx.privatelink.vaultcore.azure.net. 10 IN A 10.1.2.5
```

✓ **Azure DNS knows the private IP!** So why isn't the custom DNS server asking Azure DNS?

---

### STEP 5: Inspect the Custom DNS Server

> 💡 **Reminder:** If you need to escalate this issue to Azure Support, refer to the **Azure Guided Troubleshooter workflow** in [Lab 1 STEP 5B](../lab1/README.md#step-5b-run-azure-guided-troubleshooter-and-prepare-collaboration-request). For this lab's DNS issue, you would answer:
> - **Q1:** Yes (resources in VNet)
> - **Q2:** DNS resolution issue
> - **Q3:** Custom DNS Server (NOT Azure Private DNS Zone)
>
> Use the [EMAIL_TEMPLATE.md](../lab1/EMAIL_TEMPLATE.md) to draft your collaboration request. **Note:** Custom DNS server issues may require customer's DNS administrator involvement, as Microsoft Support cannot directly access customer-managed DNS infrastructure.

The custom DNS server is the key to understanding this failure.

**Your mission:**
Connect to the DNS server and investigate its configuration.

**Discovery questions:**
1. What DNS software is running? (Hint: Check the ticket—BIND9)
2. Where does BIND9 forward queries it doesn't know about?
3. Does it forward **all** queries to the same place?
4. Or does it use **conditional forwarding** (different destinations for different domains)?

**Investigation approach:**
```bash
# SSH to the DNS server
ssh 10.1.2.50

# Check service status
sudo systemctl status named

# Look at BIND9 configuration files
ls -la /etc/bind/

# Key file to examine: named.conf.options
# This file defines forwarders
```

**🤔 What to look for:**
- What IP addresses are listed as "forwarders"?
- Do you see `168.63.129.16` (Azure DNS)?
- Do you see public DNS servers like `8.8.8.8` (Google), `1.1.1.1` (Cloudflare)?
- Are there any conditional forwarding rules for `*.privatelink.*` zones?

<details>
<summary>💡 Hint: The Problem with Universal Forwarding</summary>

If BIND9 forwards **all** queries to a public DNS server (like Google DNS):
- That public DNS server only knows about **public** Azure records
- It has **zero knowledge** of your Azure Private Link zones
- Result: It returns the public IP

**The fix:** Configure **conditional forwarding**:
- Forward `*.privatelink.*` queries → Azure DNS (168.63.129.16)
- Forward everything else → Your preferred public DNS
</details>

---

### STEP 6: Prove the Theory

Before making changes, let's confirm the behavior with explicit tests:

**Test what Google DNS returns:**
```bash
dig @8.8.8.8 ${KV_NAME}.vault.azure.net
```

**Expected:** Public IP (40.x, 13.x, 20.x, 52.x range)

**Test what Azure DNS returns:**
```bash
dig @168.63.129.16 ${KV_NAME}.vault.azure.net
```

**Expected:** Private IP (10.1.2.5)

**Check BIND9 query logs to see forwarding behavior:**
```bash
sudo tail -f /var/log/named/query.log
```

From another terminal, trigger a query:
```bash
dig @10.1.2.50 ${KV_NAME}.vault.azure.net
```

**What you'll see in the logs:**
```
client @0x... 10.1.1.x#xxxxx (kv-dns-lab-xxx.vault.azure.net): query: ...
forwarding to 8.8.8.8
```

✓ **Proof:** BIND9 is forwarding the query to Google DNS (8.8.8.8), not Azure DNS.

---

## 🛠️ Fix the Issue

### Understanding the Root Cause

If you've discovered that the custom DNS server forwards all queries to a public DNS server (like Google DNS), you now understand why Private Link resolution fails:

- Public DNS servers only know about **public** Azure records
- Azure Private Link zones (`*.privatelink.*`) only exist in **Azure DNS** (168.63.129.16)
- The fix: Configure the custom DNS server to use **conditional forwarding**

**What is conditional forwarding?**

Instead of forwarding all queries to one place, you forward different types of queries to different DNS servers:

| Query Type | Forward To | Why? |
|------------|------------|------|
| `*.privatelink.*` zones | Azure DNS (168.63.129.16) | Only Azure DNS knows private endpoint IPs |
| Everything else | Public DNS (Google, Cloudflare, etc.) | Regular internet domains |

### Fix Options

You have two approaches:

**Option 1: Quick Fix (Hotfix Script)**

SSH to the DNS server and run the helper script:

```bash
ssh 10.1.2.50
sudo /usr/local/bin/toggle-azure-dns.sh enable
sudo systemctl status named  # Verify service restarted
```

**Option 2: Infrastructure Fix (Terraform)**

Update the DNS server configuration via Terraform and redeploy:

```bash
./fix-lab.sh lab3
```

This reapplies the Terraform configuration with the correct BIND9 settings.

**🤔 Which should you choose?**

- **Hotfix:** Fastest way to restore service (minutes)
- **Terraform:** Proper infrastructure-as-code approach (5-10 minutes)

In a real outage, you'd likely hotfix first, then update Terraform afterward.

<details>
<summary>💡 What the fix actually does</summary>

The fix adds conditional forwarding rules to BIND9's configuration:

```bind
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forwarders { 168.63.129.16; };  // Azure DNS
};
```

This tells BIND9: "For queries matching `*.privatelink.vaultcore.azure.net`, forward to Azure DNS instead of your global forwarders."
</details>

---

## ✅ Verify the Fix

### 1. Verify DNS Resolution

Test that DNS now returns the correct private IP:

```bash
# Get Key Vault name
KV_NAME=$(terraform output -raw key_vault_name)

# Test from agent VM
VM_IP=$(terraform output -raw vm_public_ip)
ssh azureuser@${VM_IP}
nslookup ${KV_NAME}.vault.azure.net
```

**What to look for:**
- ✅ Should return `10.1.2.5` (private endpoint IP)
- ❌ Should NOT return a public IP (40.x, 13.x, 20.x, etc.)

### 2. Test the Pipeline

**Run your Azure DevOps pipeline:**
1. Go to Azure DevOps → Pipelines
2. Queue a new run
3. Watch the three stages execute: RetrieveConfig, Build, Deploy

**Success criteria:**
- ✅ RetrieveConfig stage: Successfully retrieves AppMessage from Key Vault
- ✅ Build stage: Creates and packages Node.js app
- ✅ Deploy stage: Runs app and displays success message
- ✅ No "public network access" or DNS resolution errors

If the pipeline still fails, revisit the DNS configuration and verify the custom DNS server is forwarding `*.privatelink.*` queries to Azure DNS (168.63.129.16).

---

## 📊 Lab Comparison: Understanding the Differences

This table helps you identify which lab scenario applies when you see similar symptoms in production:

| Aspect | Lab 1 | Lab 2 | Lab 3 (This Lab) |
|--------|-------|-------|------------------|
| **Root Cause** | Private DNS Zone not linked to VNet | Private DNS Zone not linked to VNet | Custom DNS misconfiguration |
| **DNS Server** | Azure-provided (168.63.129.16) | Azure-provided (168.63.129.16) | Custom DNS at 10.1.2.50 |
| **What's Missing** | VNet link in Private DNS Zone | VNet link in Private DNS Zone | Conditional forwarding to Azure DNS |
| **DNS Query Returns** | Public IP (Azure DNS has no link) | Public IP (Azure DNS has no link) | Public IP (forwarded to wrong DNS) |
| **Key Diagnostic** | Check Private DNS Zone links | Check Private DNS Zone links | Check custom DNS forwarders |
| **Fix Approach** | Add VNet link via portal/Terraform | Add VNet link via portal/Terraform | Configure conditional forwarding |
| **Real-World Trigger** | Forgot to link zone during deployment | Zone link removed accidentally | Migrated to custom DNS without proper config |

**How to identify which scenario you're facing:**

```bash
# Step 1: Check VNet DNS settings
az network vnet show -g <rg> -n <vnet> --query "dhcpOptions.dnsServers"

# Empty/null? → Using Azure DNS → Check for Lab 1/2 scenarios
# Custom IP? → Using custom DNS → Check for Lab 3 scenario

# Step 2: If using Azure DNS, check Private DNS Zone links
az network private-dns link vnet list -g <rg> -z <zone-name>

# No links or VNet missing? → Lab 1 or 2

# Step 3: If using custom DNS, SSH and check forwarders
ssh <custom-dns-ip>
sudo cat /etc/bind/named.conf.options  # Or equivalent for your DNS software
```

---

## 🧠 Key Takeaways

### 1. Custom DNS Requires Conditional Forwarding

When using custom DNS servers with Azure Private Link, you **cannot** forward all queries to a single destination:

| Zone Type | Must Forward To | Why? |
|-----------|-----------------|------|
| `*.privatelink.*` | Azure DNS (168.63.129.16) | Only Azure DNS knows private endpoint IPs |
| Everything else | Your preferred DNS (Google, on-prem, etc.) | Regular internet resolution |

### 2. The Special IP: 168.63.129.16

- Azure's Wire Server (recursive resolver)
- **Only** reachable from within Azure VNets
- **Only** source for Private Link zone resolution
- Cannot be queried from on-premises or internet

### 3. Error Messages Are Misleading

```
"Public network access is disabled..."
```

This error **doesn't mention DNS**, but DNS misconfiguration is often the cause. When you see this error with a private endpoint present, always check DNS resolution first.

### 4. Troubleshooting Custom DNS Issues

**Quick diagnostic workflow:**

1. Check VNet DNS settings → Using custom DNS?
2. Query from affected VM → Getting public IP?
3. Query Azure DNS directly (`@168.63.129.16`) → Getting private IP?
4. SSH to custom DNS server → Check forwarders
5. Look for conditional forwarding rules for `*.privatelink.*`

### 5. Common Misconceptions

❌ "We tested the DNS server and it works"
- Test must include actual Private Link FQDNs, not just `google.com`

❌ "We need a forwarder for each private endpoint"
- You forward by **zone**, not by resource
- One rule for `privatelink.vaultcore.azure.net` covers all Key Vaults

❌ "Public DNS should know about our private endpoints"
- Public DNS (Google, Cloudflare) only knows public records
- Private Link zones exist **only** in Azure DNS

---

## 📝 Reflection Questions

Test your understanding before moving on:

1. **Why didn't the error message mention DNS?**
   - What does Key Vault see when the agent connects using a public IP?
   - How does this relate to the "public network access" message?

2. **Could you diagnose this without SSH access to the DNS server?**
   - What did comparing DNS results tell you?
   - Could you query Azure DNS directly from the agent VM?

3. **Why does public DNS return an answer for `*.vault.azure.net`?**
   - Does Key Vault have a public endpoint?
   - What is "split-horizon DNS"?

4. **What other Azure services use `*.privatelink.*` zones?**
   - Think about services you've used with private endpoints
   - Hint: Storage, SQL, Cosmos DB, Container Registry...

5. **How would you automate this fix in production?**
   - Could you use Terraform/cloud-init to configure BIND9?
   - How would you ensure all Private Link zones are covered?

---

## 🔄 Reset to Base State

```bash
./fix-lab.sh lab3
# or
terraform apply -var="lab_scenario=base"
```

---

## 🎓 Congratulations!

You've completed Lab 3 and learned how custom DNS misconfiguration breaks Azure Private Link resolution.

**What you mastered:**
- Diagnosing DNS resolution failures with custom DNS servers
- Understanding conditional forwarding requirements
- Troubleshooting BIND9 configuration
- Distinguishing between VNet link issues and DNS server misconfiguration

**Next steps:**
- Review the lab comparison table to understand scenario differences
- Practice identifying which scenario applies based on symptoms
- Consider how you'd handle this in your production environment

**Real-world application:**
When you encounter "public network access" errors in production:
1. Check if private endpoints exist
2. Verify DNS resolution (public vs private IP)
3. Check VNet DNS settings (Azure-provided vs custom)
4. If custom DNS, verify conditional forwarding for `*.privatelink.*` zones
