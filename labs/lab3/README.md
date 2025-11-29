# Lab 3: Custom DNS Misconfiguration

## 🎯 The Situation

**Wednesday, 2:00 PM: The Call 📞**

Your team takes a **Priority 1** call. The application team reports that their deployment pipeline is suddenly failing to retrieve secrets from Azure Key Vault. They swear their pipeline YAML and Key Vault permissions haven't changed.

"We think it's a network issue," they say. "We heard the networking team made some DNS changes this afternoon."

**What you know from the ticket:**
- The pipeline worked fine this morning
- The failure started precisely after the announced "centralized DNS migration"
- The networking team reports they've deployed a custom DNS server (BIND9) at `10.1.2.50` and configured the VNet to use it
- The networking team says their DNS server is "production-ready" and "fully tested"
- The agent VM is healthy and can reach external sites (like `google.com`)
- The Key Vault private endpoint exists and shows as "Approved" in the Azure portal

**What you observe in the pipeline log:**
- A clear error stating: _"Public network access is disabled and request is not from a trusted service nor via an approved private link."_

**Your mission:** Investigate the failure systematically. Determine exactly how the new custom DNS server is misconfigured to cause the "public network access" error, and recommend the fix to the networking team.

> **Real-World Context**
> This is one of the most common Private Link failures in enterprise environments. Organizations use custom DNS infrastructure (BIND, Windows DNS, Infoblox) for control and policy enforcement, but if they mistakenly configure it to forward Azure Private Link zones to the wrong external DNS source, resolution **silently breaks**. The confusing part? Regular internet DNS works fine. Only Azure Private Link fails, and the error message doesn't mention DNS at all. Your task is to prove how the misdirection is occurring by inspecting the DNS server configuration itself.

---

## 📋 Prerequisites

Before starting Lab 3, you need a custom DNS server image:

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

If your instructor published the image to the Azure Compute Gallery (recommended for cross-subscription use), set `custom_dns_image_id` to the **gallery image version ID**:

```zsh
# Get the gallery image version resource ID
az sig image-version show \
   -g rg-dns-lab-images-20251129022831 \
   --gallery-name DNSLabGallery \
   --gallery-image-definition dns-server-bind9 \
   --gallery-image-version 1.0.0 \
   --query id -o tsv
```

Then in `terraform.tfvars`:

```hcl
custom_dns_image_id = "/subscriptions/fcfa67ae-efeb-417c-a966-48b4937d2918/resourceGroups/rg-dns-lab-images-20251129022831/providers/Microsoft.Compute/galleries/DNSLabGallery/images/dns-server-bind9/versions/1.0.0"
```

---

## 🏗️ Lab Architecture

This lab simulates a "split-brain" DNS configuration where:
- Your custom DNS server (BIND9) handles all queries from the VNet
- BIND9 forwards queries to the **wrong** DNS server (Google vs Azure DNS)
- Result: Internet names resolve fine, Azure Private Link names fail

```mermaid
flowchart TB
    subgraph VNet["Agent VNet 10.1.0.0/16"]
        VM["Agent VM\n10.1.1.x"]
        DNS["Custom DNS Server\nBIND9 at 10.1.2.50"]
    end
    
    subgraph Azure["Azure Platform"]
        AzureDNS["Azure DNS\n168.63.129.16"]
        PrivateZone["Private DNS Zone\nprivatelink.vaultcore.azure.net"]
        PE["Private Endpoint\n10.1.2.5"]
    end
    
    subgraph Internet["Public Internet"]
        GoogleDNS["Google DNS\n8.8.8.8"]
        PublicDNS["Public Azure DNS\n40.x.x.x"]
    end
    
    %% Broken Path (Current)
    VM -->|1. Query vault.azure.net| DNS
    DNS -->|2. Forward ALL to Google| GoogleDNS
    GoogleDNS -->|3. Return public IP| DNS
    DNS -->|4. Return wrong IP| VM
    VM -.->|5. Try to connect| PublicDNS
    PublicDNS -.->|6. BLOCKED (public access disabled)| VM
    
    %% Expected Path (After Fix)
    DNS -.->|Should forward privatelink.*| AzureDNS
    AzureDNS -.-> PrivateZone
    PrivateZone -.-> PE
    
    classDef broken stroke:#d9534f,stroke-width:3,color:#d9534f;
    classDef good stroke:#5cb85c,stroke-width:2,color:#5cb85c,stroke-dasharray: 5 5;
    
    GoogleDNS:::broken
    PublicDNS:::broken
    AzureDNS:::good
    PE:::good
```

**Key Observations:**
- The agent VM **trusts** whatever the custom DNS server tells it
- BIND9 **blindly forwards** all queries to Google DNS (8.8.8.8)
- Google DNS has **zero knowledge** of your Azure Private Link zones
- Result: Pipeline gets a public IP, tries to connect, and Key Vault rejects it

---

## 💥 Start the Scenario

### Step 1: Deploy Lab 3 Infrastructure

First, ensure you've built the custom DNS image (see Prerequisites section above). Then deploy:

```bash
terraform apply -var="lab_scenario=dns_exercise3"
```

This will:
- Deploy a custom DNS server VM at `10.1.2.50` with BIND9 pre-configured
- Configure the VNet to use `10.1.2.50` as its DNS server
- BIND9 forwards **all** queries to Google DNS (8.8.8.8, 8.8.4.4) — **broken by design**

> **Your Role:** Once deployed, you are the on-call engineer. The application team reports the pipeline is suddenly failing after the networking team's "DNS upgrade."

### Step 2: Observe the Pipeline Failure

Trigger your pipeline in Azure DevOps. You'll see this error in the "Fetch Secrets from Key Vault" step:

```
##[error]TestSecret: "Public network access is disabled and request is not from a trusted 
service nor via an approved private link.
Caller: appid=***;oid=...
Vault: kv-dns-lab-xxxxxxxx;location=westus2."
```

**Key observation:** 
- The error says "public network access is disabled"
- This implies the agent is trying to reach the **public** endpoint
- But why? The private endpoint exists...

> **Note:** The error message does **not** mention DNS. This is the challenge—DNS misconfiguration surfaces as a connectivity or permissions error.

---

## 🔍 Investigation: Systematic Troubleshooting

This is the same process you'll use on the job when DNS issues are suspected. Work through each step—don't skip ahead.

---

### STEP 1: Scope the Problem (What Do We Know?)

Before diving into DNS servers and BIND configs, gather basic information. This is what support engineers ask first.

**Answer these questions:**

1. **What stage failed?**
   - Look at your pipeline run
   - Which step shows the red ✗?
   - Answer: `___________________`

2. **What does the error say?**
   - Does it mention "public network"?
   - Does it mention DNS at all?
   - Answer: `___________________`

3. **Did this ever work?**
   - Was the pipeline working before the DNS change?
   - If yes, what changed? (Hint: networking team deployed custom DNS)
   - Answer: `___________________`

4. **What type of agent?**
   - Self-hosted in Azure VNet
   - Uses DNS servers configured on the VNet
   - Answer: `___________________`

**For this lab scenario:**
- Stage: "Fetch Secrets from Key Vault" (AzureKeyVault@2 task)
- Error: "Public network access is disabled and request is not from a trusted service..."
- History: Worked this morning, broke after networking team's DNS change
- Agent: Self-hosted Linux VM in Azure VNet configured to use custom DNS at 10.1.2.50
- Red flag: Error mentions "public network" but private endpoint exists

**Key learning:** When an error mentions "public network access" but you have a private endpoint, suspect DNS is resolving to the public IP instead of the private IP.

---

### STEP 2: Compare DNS Resolution (Public vs Private View)

Let's verify what DNS returns from different perspectives.

**Test from your Codespace (public internet view):**
```bash
KV_NAME=$(terraform output -raw key_vault_name)
nslookup ${KV_NAME}.vault.azure.net
```

**Expected output:**
```
Name:   kv-dns-lab-xxxxxxxx.vault.azure.net
Address: 40.78.x.x  # Public IP (works from internet)
```

**Test from the agent VM (private network view):**
```bash
# Get agent VM public IP
VM_IP=$(terraform output -raw vm_public_ip)

# SSH to agent VM
ssh azureuser@${VM_IP}

# Once connected, test DNS
nslookup ${KV_NAME}.vault.azure.net
```

**What you're looking for:**
- Does it return the **private** IP (10.1.2.5)?
- Or does it return a **public** IP (40.x, 13.x, 20.x, 52.x)?

**If it returns a public IP from the agent VM:**
✗ **This is the problem.** The agent is getting the wrong answer from DNS.

**Critical question:** *Why is DNS returning a public IP when the private endpoint exists?*

---

### STEP 3: Investigate the DNS Resolution Path

Now we need to understand **how** the agent gets its DNS answer.

**Check what DNS server the agent is using:**
```bash
# On the agent VM
resolvectl status
```

**Expected output:**
```
Link 2 (eth0)
    Current Scopes: DNS
         Protocols: +DefaultRoute +LLMNR -mDNS -DNSOverTLS DNSSEC=no/unsupported
Current DNS Server: 10.1.2.50
       DNS Servers: 10.1.2.50
```

✓ **What this tells us:** The agent is configured to use `10.1.2.50` (the custom DNS server). This confirms the networking team's change is active on the agent VNet.

**So the question becomes:** *Why is the custom DNS server returning the public IP?*

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

### STEP 5: Investigate the Custom DNS Server Configuration

Now we need to look inside the DNS server to understand its forwarding behavior.

**SSH to the DNS server:**
```bash
# From the agent VM
ssh 10.1.2.50

# Or directly from your Codespace
DNS_IP=$(terraform output -raw dns_server_ip)
ssh azureuser@${DNS_IP}
```

**Check BIND9 status:**
```bash
sudo systemctl status named
```

**Check the forwarding configuration:**
```bash
sudo cat /etc/bind/named.conf.options

# Check query logs
sudo tail -f /var/log/bind/query.log
```

**What you'll discover:**
```bash
options {
    directory "/var/cache/bind";
    
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    
    dnssec-validation auto;
    listen-on { any; };
    listen-on-v6 { any; };
    allow-query { any; };
};
```

✗ **ROOT CAUSE FOUND:** BIND9 is configured to forward **all** queries to Google DNS (8.8.8.8, 8.8.4.4).

**Why this breaks Azure Private Link:**
- Google DNS has no knowledge of your private endpoint
- Google DNS can only resolve public Azure DNS records
- Azure Private Link zones (`*.privatelink.*`) **only** exist in Azure DNS (168.63.129.16)
- Result: BIND9 asks Google → Google returns public IP → agent tries public endpoint → Key Vault rejects

**The Solution:**
You need **conditional forwarding**. Think of BIND9 as a receptionist—it needs to be told:
- "For the Private Phone Book (`*.privatelink.*`), call Azure's Central Directory (168.63.129.16)."
- "For everything else, call Google (8.8.8.8)."

BIND9 should:
1. Forward `*.privatelink.*` queries → Azure DNS (168.63.129.16)
2. Forward everything else → Google DNS (8.8.8.8, 8.8.4.4) or your preferred DNS

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

Now that you've identified the root cause, you need to configure BIND9 to use **conditional forwarding**.

### Understanding Conditional Forwarding

Instead of forwarding **all** queries to one destination, you want:

| DNS Query Type | Forward To | Why? |
|----------------|------------|------|
| `*.privatelink.vaultcore.azure.net` | Azure DNS (168.63.129.16) | Only Azure DNS knows private endpoint IPs |
| `*.privatelink.blob.core.windows.net` | Azure DNS (168.63.129.16) | Same for Storage accounts |
| `*.privatelink.database.windows.net` | Azure DNS (168.63.129.16) | Same for SQL databases |
| Everything else (e.g., `google.com`, `github.com`) | Google DNS (8.8.8.8) | Regular internet domains |

**BIND9 Configuration Approach:**
- Create a separate config file for Azure Private Link zones
- Include it in `named.conf.local`
- Define conditional forwarders using `zone` statements

---

### Option 1: The "On-The-Job" Fix (Helper Script)

In production environments, you want **tested**, **repeatable** fixes. A helper script is pre-installed:

```bash
# SSH to the DNS server
ssh 10.1.2.50

# Check current status
sudo /usr/local/bin/toggle-azure-dns.sh status

# Enable Azure DNS forwarding for privatelink zones
sudo /usr/local/bin/toggle-azure-dns.sh enable

# Verify BIND9 restarted successfully
sudo systemctl status named
```

**What the script does:**
1. Checks if `/etc/bind/azure-privatelink.conf` exists (the conditional forwarder config)
2. Adds `include "/etc/bind/azure-privatelink.conf";` to `/etc/bind/named.conf.local`
3. Validates the config with `named-checkconf`
4. Restarts BIND9 (`systemctl restart named`)

> **Real-World Tip:** Always use version-controlled scripts for DNS changes. Ad-hoc edits lead to "it works on my machine" issues.

---

### Option 2: The "Learning" Fix (Manual Configuration)

If you want to understand exactly what changes, do it manually:

**Step 1: Inspect the conditional forwarder config:**
```bash
cat /etc/bind/azure-privatelink.conf
```

You'll see:
```bind
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forwarders { 168.63.129.16; };
};

zone "privatelink.blob.core.windows.net" {
    type forward;
    forwarders { 168.63.129.16; };
};
```

**Step 2: Enable the config by including it:**
```bash
sudo nano /etc/bind/named.conf.local

# Add at the end:
// Azure Private Link DNS Forwarding
include "/etc/bind/azure-privatelink.conf";
```

**Step 3: Validate syntax (critical!):**
```bash
sudo named-checkconf
```

If no output → config is valid. If errors → fix before restarting.

**Step 4: Restart BIND9:**
```bash
sudo systemctl restart named

# Verify it's running
sudo systemctl status named
```

---

### What This Fix Does

**Before:**
```
Agent → BIND9 → Google DNS (8.8.8.8) → Returns public IP → Agent tries public endpoint → BLOCKED
```

**After:**
```
Agent → BIND9 → Checks query type:
  ├─ *.privatelink.* → Azure DNS (168.63.129.16) → Returns private IP (10.1.2.5) → SUCCESS
  └─ Everything else → Google DNS (8.8.8.8) → Returns public IP → (works for internet domains)
```

The fix is **additive**—you keep Google DNS for internet queries and add Azure DNS for Private Link zones.

---

## ✅ Verification

### 1. Verify DNS Resolution from the DNS Server

SSH to the DNS server and test resolution:

```bash
# SSH to the DNS server
ssh 10.1.2.50

# Get Key Vault name
KV_NAME=$(az keyvault list --query "[0].name" -o tsv)

# Test Key Vault resolution
dig @localhost ${KV_NAME}.vault.azure.net
```

**Expected output (after fix):**
```
;; ANSWER SECTION:
kv-dns-lab-xxxxxxxx.privatelink.vaultcore.azure.net. 10 IN A 10.1.2.5
```

✓ **What changed:** Now returns the private endpoint IP (10.1.2.5) instead of public IP.

---

### 2. Verify DNS Resolution from the Agent VM

Exit the DNS server and test from the agent VM:

```bash
# SSH to the agent VM
VM_IP=$(terraform output -raw vm_public_ip)
ssh azureuser@${VM_IP}

# Test resolution
nslookup ${KV_NAME}.vault.azure.net
```

**Expected output:**
```
Server:         10.1.2.50
Address:        10.1.2.50#53

Non-authoritative answer:
Name:   kv-dns-lab-xxxxxxxx.vault.azure.net
Address: 10.1.2.5
```

✓ **Proof:** The agent now gets the correct private IP via the custom DNS server.

---

### 3. Monitor BIND9 Query Logs

Watch the logs to see the forwarding behavior change:

```bash
# SSH to the DNS server
ssh 10.1.2.50

# Watch query logs in real-time
sudo tail -f /var/log/named/query.log
```

From another terminal, trigger a query from the agent:

```bash
dig ${KV_NAME}.vault.azure.net
```

**What you'll see in the logs (after fix):**
```
client @0x... 10.1.1.x#xxxxx (kv-dns-lab-xxx.vault.azure.net): query: ...
forwarding to **168.63.129.16**
```

✓ **Confirmation:** BIND9 is now forwarding to Azure DNS (**168.63.129.16**) instead of Google DNS.

---

### 4. Test the Pipeline (End-to-End Validation)

The ultimate test: does the pipeline work now?

**Run your Azure DevOps pipeline:**
1. Go to Azure DevOps → Pipelines
2. Queue a new run of the DNS-Lab-Pipeline
3. Watch the "Fetch Secrets from Key Vault" step

**Expected output (success):**
```
Starting: Fetch Secrets from Key Vault
==============================================================================
Task         : Azure Key Vault
Description  : Download Azure Key Vault secrets
Version      : 2.259.2
==============================================================================
SubscriptionId: fcfa67ae-efeb-417c-a966-48b4937d2918.
Key vault name: kv-dns-lab-xxxxxxxx.
Downloading secret value for: TestSecret.
✓ Got secret: TestSecret
Finishing: Fetch Secrets from Key Vault
```

✓ **Success:** The pipeline can now retrieve secrets because DNS returns the private endpoint IP.

---

## 🧠 Key Takeaways

### 1. Custom DNS Is a Double-Edged Sword
Organizations deploy custom DNS servers (BIND, Windows DNS, Infoblox) for valid reasons:
- Policy enforcement (block certain domains)
- Conditional forwarding to on-prem DNS
- Audit logging for compliance
- Split-horizon DNS for hybrid environments

**But:** If you treat Azure Private Link zones like regular internet domains and forward them to external DNS (Google, Cloudflare, OpenDNS), **resolution silently breaks**. The error manifests as connectivity failures, not DNS errors.

### 2. Conditional Forwarding Is Required
You **cannot** use a single global forwarder when using Azure Private Link. You need:

| DNS Zone Pattern | Must Forward To | Why? |
|------------------|-----------------|------|
| `*.privatelink.vaultcore.azure.net` | Azure DNS (168.63.129.16) | Only Azure knows private endpoint IPs |
| `*.privatelink.blob.core.windows.net` | Azure DNS (168.63.129.16) | Storage account private endpoints |
| `*.privatelink.database.windows.net` | Azure DNS (168.63.129.16) | SQL database private endpoints |
| `*.azure.net` (optional) | Azure DNS (168.63.129.16) | Azure-provided VM DNS, etc. |
| Everything else | Your preferred DNS (Google, on-prem, etc.) | Regular internet resolution |

**BIND9 Implementation:**
```bind
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forwarders { 168.63.129.16; };
};
```

### 3. The Special IP: 168.63.129.16
This is Azure's **Wire Server** (also called the "Azure Recursive Resolver"). It's the only DNS server that can resolve:
- Azure Private Link zones (`*.privatelink.*`)
- Azure-provided DNS for VMs
- Private DNS zones linked to VNets

**Critical:** This IP is **only reachable from within Azure VNets**. You cannot query it from your laptop or on-prem network.

### 4. Error Messages Are Misleading
Notice the error message:
```
Public network access is disabled and request is not from a trusted service 
nor via an approved private link.
```

**What it doesn't say:** "DNS is returning the wrong IP."

**What it implies:** "You're trying to use the public endpoint, and I'm blocking you."

**Reality:** DNS misconfiguration is surfacing as an access control error. You must interpret "public network access" errors as potential DNS issues when private endpoints exist.

### 5. Troubleshooting Workflow for Custom DNS

When you suspect custom DNS issues:

1. **Compare DNS answers:**
   - Query from the affected VM → Wrong IP?
   - Query Azure DNS directly (`@168.63.129.16`) → Correct IP?
   - Query external DNS (`@8.8.8.8`) → Wrong IP?

2. **Check DNS server config:**
   - What DNS server is the VM using? (`resolvectl status`)
   - What forwarders is that DNS server using? (Check BIND9, Windows DNS, etc.)
   - Are there conditional forwarders for `*.privatelink.*`?

3. **Verify forwarding behavior:**
   - Check DNS server logs (BIND9 query logs, Windows DNS debug logs)
   - Watch queries in real-time: `sudo tail -f /var/log/named/query.log`
   - Confirm which upstream DNS is queried (should be 168.63.129.16 for privatelink zones)

4. **Test the fix:**
   - Add conditional forwarders
   - Restart DNS service
   - Clear DNS cache on clients if needed
   - Re-test resolution from affected VM

### 6. Real-World Gotchas

**Scenario:** "We have hundreds of Private Link endpoints. Do we need a forwarder for each one?"

**Answer:** No. You forward by **zone**, not by resource. One forwarder for `privatelink.vaultcore.azure.net` covers all Key Vault private endpoints. One for `privatelink.blob.core.windows.net` covers all Storage accounts.

**Scenario:** "Can we just point our VNet to use 168.63.129.16 directly and skip custom DNS?"

**Answer:** Yes, if you don't need custom DNS features. But if you need conditional forwarding to on-prem DNS, policy enforcement, or logging, you must use a custom DNS server **with proper conditional forwarding**.

**Scenario:** "The networking team says they tested the DNS server and it works."

**Answer:** Ask what they tested. If they only tested `google.com` or `microsoft.com`, they didn't test Private Link zones. Always test resolution of actual Private Link FQDNs.

### 7. Tools You Used in This Lab

- **`dig`**: DNS query tool (more detailed than nslookup)
- **`nslookup`**: Simple DNS query tool
- **`resolvectl status`**: Shows DNS configuration on Linux
- **`named-checkconf`**: Validates BIND9 configuration syntax
- **`systemctl status named`**: Checks BIND9 service status
- **BIND9 query logs**: Real-time DNS query tracking
- **Azure CLI**: Automation and scripting (pre-installed on DNS server)
- **GitHub CLI**: Documentation access (pre-installed on DNS server)

---

## 📝 Reflection Questions

Before moving on, test your understanding:

1. **Why didn't the error message explicitly mention DNS?**
   - Hint: The Key Vault sees the agent connecting from a public IP range, not from the expected private endpoint.

2. **Could you have diagnosed this without SSH access to the DNS server?**
   - Hint: What did the agent VM's `nslookup` tell you? Could you query Azure DNS directly from the agent?

3. **Why does Google DNS return an answer at all for `*.vault.azure.net`?**
   - Hint: Key Vault has both a public endpoint and a private endpoint. Split-horizon DNS.

4. **What would happen if you disabled public access on the Key Vault _before_ fixing DNS?**
   - Hint: The agent would try the public IP and be blocked. Same failure, but faster.

5. **Why is 168.63.129.16 the only DNS server that knows about Private Link zones?**
   - Hint: Who manages the `privatelink.vaultcore.azure.net` zone? Where does it exist?

6. **Could you solve this by creating a custom Private DNS zone instead of using conditional forwarding?**
   - Hint: Yes, but you'd need to maintain A records manually every time you create a new private endpoint. Conditional forwarding is more scalable.

7. **What other Azure services have `*.privatelink.*` zones?**
   - Storage (blob, file, queue, table), SQL Database, Cosmos DB, Container Registry, App Service, etc.

8. **How would you automate this fix in Terraform?**
   - Hint: Use `cloud-init` or `custom_data` to configure BIND9 during VM deployment, or use Azure VM extensions to run scripts post-deployment.

---

## 🔄 Reset to Base State

To reset the lab environment:

```bash
terraform apply -var="lab_scenario=base"
```

This will:
- Remove the custom DNS server VM
- Reset VNet DNS settings to use Azure-provided DNS
- Keep the base infrastructure (agent VM, Key Vault, private endpoint)

Or destroy everything:

```bash
terraform destroy
```

---

## 🎓 Next Steps

You've now completed all three DNS troubleshooting scenarios:

1. **Lab 1:** Missing VNet link (Private DNS Zone not linked to agent VNet)
2. **Lab 2:** Missing VNet link (variation with different symptoms)
3. **Lab 3:** Custom DNS misconfiguration (BIND9 forwarding to wrong DNS)

**Challenge:** Can you identify which lab scenario applies when you see these symptoms in production?

| Symptom | Most Likely Cause | Lab |
|---------|-------------------|-----|
| `nslookup` returns public IP from agent VM | Missing VNet link **or** custom DNS misconfiguration | Lab 1, 2, or 3 |
| Private DNS zone exists but VNet not listed in "Virtual network links" | Missing VNet link | Lab 1 or 2 |
| Custom DNS server exists (check VNet DNS settings) | Custom DNS misconfiguration | Lab 3 |
| `nslookup` times out or returns NXDOMAIN | DNS server unreachable or zone doesn't exist | Investigate further |

**Pro Tip:** Always check VNet DNS settings first:
```bash
az network vnet show --resource-group <rg> --name <vnet> --query "dhcpOptions.dnsServers"
```

- Empty list = Azure-provided DNS (168.63.129.16 automatically)
- Custom IP = Check that DNS server's configuration
