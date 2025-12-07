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

## 💰 Cost Reminder

This lab uses Azure resources that are already deployed. **After completing all labs**, remember to destroy infrastructure to avoid ongoing charges:

```bash
terraform destroy
```

**Estimated cost for this lab:** $0.15 - $0.50 (1-2 hours)

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

### 🧠 Connecting the Dots: Why "Public Access Disabled" = DNS Issue?

Students often ask: *"The error says 'Public network access is disabled'. Shouldn't we just enable public access?"*

**No.** Here is the mental model:

1. **The "Back Door" Analogy**:
   - **The Goal**: You want to enter the building via the secure **Back Door** (Private Endpoint).
   - **The Mistake**: Your GPS (DNS) sent you to the **Front Door** (Public Endpoint).
   - **The Result**: The bouncer at the Front Door says "Sorry, Front Door is locked (Public Access Disabled). Go around to the back."

2. **What the Agent Experienced**:
   - The agent asked DNS: "Where is `keyvault.vault.azure.net`?"
   - DNS replied: "It's at `52.x.x.x` (Public IP)."
   - Agent went to `52.x.x.x`.
   - Key Vault Firewall saw the request coming from the internet and rejected it.

**Conclusion**: The error isn't that the Front Door is locked (that's intentional!). The error is that **DNS sent you to the Front Door** instead of the Back Door.

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

**Critical Note**: This answer differs from Labs 1-2! Custom DNS means Azure Support or other teams within Microsoft may need to coordinate with your DNS administrator team, as they cannot directly access or modify customer-managed DNS infrastructure.

</details>

### Troubleshooter Result

**Routing**: SAP Azure / Azure DNS / Custom DNS Configuration

**Next Steps**: You've identified this involves custom DNS. Now collect diagnostic evidence showing how the custom DNS server is misconfigured.

**⚠️ Important**: In production, custom DNS issues require collaboration with DNS administrator team. Azure Support or other teams within Microsoft can provide guidance on proper forwarding configuration but cannot modify customer DNS servers.

### Update Your Email Template

Open `EMAIL_TEMPLATE.md` and complete:
- **Azure Guided Troubleshooter Responses** section (mark answer #3 as "Custom DNS servers")
- **Timeline** section (when was custom DNS deployed?)
- **Additional Context** section (DNS administrator contact if production)

💾 **Save your progress** - you'll send this to your instructor at STEP 10.

---

## STEP 6: Analyze What We Know and Plan Data Collection

Now that you've answered the Guided Troubleshooter questions, let's organize what we know and identify what we need to discover.

### What We Know ✅

| Evidence Source | What This Tells Us |
|----------------|-------------------|
| **Pipeline → AzureKeyVault@2 Task** error | Failed at Key Vault secret retrieval, not authentication |
| Error message: "Public network access is disabled" | **Key Vault → Network Settings** requires private endpoint access |
| Error message: "Not via approved private link" | **Agent VM → Network Path** attempted connection over public route |
| **Key Vault → Private Endpoint** exists (Portal verification) | Private endpoint is configured (10.1.2.5) |
| **Private DNS Zone** exists and linked (from Lab 2) | Zone `privatelink.vaultcore.azure.net` is present and linked |
| **Lab context**: Just deployed custom DNS server | **Agent VNet → DNS Settings** likely changed |

### What We Don't Know ❓

1. **Is Agent VNet using custom DNS?**
   - Does **Agent VNet → DNS Settings** point to custom DNS (10.1.2.50) or Azure DNS (168.63.129.16)?
   - This determines which DNS server **Agent VM → DNS Resolver** queries

2. **What IP does custom DNS return?**
   - Does **Custom DNS Server (10.1.2.50)** return private IP (10.1.2.5) or public IP (52.x.x.x)?
   - This tells us if custom DNS knows about Private Link zones

3. **Where does custom DNS forward queries?**
   - What are **Custom DNS Server → Global Forwarders** configured to?
   - Are there **Custom DNS Server → Conditional Forwarding Rules** for `*.privatelink.*` zones?
   - Does it forward to Azure DNS (168.63.129.16) or public DNS (8.8.8.8)?

### Why We Need This Data 🎯

**DNS Resolution Flow with Custom DNS (Expected)**:
```
Agent VM → DNS Resolver → Custom DNS Server (10.1.2.50)
    → checks local zones (no match for vault.azure.net)
    → checks conditional forwarding rules
    → finds rule: *.privatelink.vaultcore.azure.net → 168.63.129.16
    → forwards to Azure Recursive Resolver (168.63.129.16)
    → Azure DNS queries: Agent VNet → VNet Link → Private DNS Zone → A Record
    → returns: 10.1.2.5 (Private Endpoint IP)
```

**DNS Resolution Flow (Suspected - Broken)**:
```
Agent VM → DNS Resolver → Custom DNS Server (10.1.2.50)
    → checks local zones (no match)
    → NO conditional forwarding rules exist
    → falls back to global forwarders (8.8.8.8 - Google DNS)
    → Google DNS queries public Azure DNS
    → returns: 52.x.x.x (Public IP)
```

**The Critical Difference**: **Custom DNS Server → Conditional Forwarding Rules** for `*.privatelink.*` zones MUST forward to **Azure Recursive Resolver (168.63.129.16)**. Without this, public DNS servers (Google, Cloudflare) have NO knowledge of Azure Private Link zones.

### Action Plan

We'll collect three data points:
1. **STEP 7**: Check VNet DNS settings (using custom DNS or Azure DNS?)
2. **STEP 8**: Test DNS resolution chain (custom DNS → where does it forward?)
3. **STEP 9**: Inspect custom DNS server forwarding configuration (BIND9 config files)

Then in **STEP 10**, we'll compare these values and identify the missing forwarding rule.

---

## STEP 7: Check VNet DNS Configuration

**Why We Need This**: The VNet DNS settings determine which DNS server **Agent VM → DNS Resolver** uses. If it's using custom DNS (10.1.2.50) instead of Azure DNS (168.63.129.16), we need to verify the custom DNS server is properly configured.

### Understanding VNet DNS Settings

**Concept**: Each VNet in Azure can use:
- **Default (Azure-provided)**: 168.63.129.16 (automatic, requires no configuration)
- **Custom**: Your own DNS server IP addresses (requires proper forwarding rules)

### Option 1: Azure Portal

1. Navigate to **Virtual networks** in Azure Portal
2. Click on `vnet-agent`
3. In left menu, click **DNS servers**
4. Check the setting:
   - **Default (Azure-provided)**: ✅ Uses 168.63.129.16 automatically
   - **Custom**: ⚠️ Shows custom DNS server IPs

### Option 2: Azure CLI

```bash
# Set variables
RG_NAME="rg-dnslab"
VNET_NAME="vnet-agent"

# Check VNet DNS settings
az network vnet show \
  --resource-group $RG_NAME \
  --name $VNET_NAME \
  --query 'dhcpOptions.dnsServers' -o table
```

**Expected Output (Lab 3 - Custom DNS)**:
```
Result
----------
10.1.2.50
```

**Comparison (Labs 1-2 - Azure DNS)**:
```
Result
----------
(Empty - uses Azure-provided 168.63.129.16 by default)
```

### Option 3: Check from Agent VM

SSH to Agent VM and check its actual DNS configuration:

```bash
# Get Agent VM public IP
VM_PUBLIC_IP=$(az vm show \
  --resource-group rg-dnslab \
  --name vm-agent-dnslab \
  --show-details \
  --query 'publicIps' -o tsv)

# SSH to VM
ssh azureuser@$VM_PUBLIC_IP

# Check DNS resolver configuration
cat /etc/resolv.conf
```

**Expected Output (Custom DNS)**:
```
nameserver 10.1.2.50
search internal.cloudapp.net
```

**Comparison (Azure DNS)**:
```
nameserver 168.63.129.16
search internal.cloudapp.net
```

### Interpreting the Results

| VNet DNS Setting | Agent VM /etc/resolv.conf | DNS Query Path |
|------------------|---------------------------|----------------|
| Default (Azure) | nameserver 168.63.129.16 | Agent VM → Azure Recursive Resolver (direct) |
| Custom (10.1.2.50) | nameserver 10.1.2.50 | Agent VM → Custom DNS Server → ??? |

**If using custom DNS**, we need to verify where **Custom DNS Server → Forwarding Rules** send queries.

### Record Your Findings

**VNet DNS Setting**: ☐ Default (Azure) / ☑️ Custom (10.1.2.50)

**Agent VM DNS Resolver**: `_______________` (from /etc/resolv.conf)

**Update EMAIL_TEMPLATE.md** → Diagnostic Evidence → STEP 7 section with your findings.

---

## STEP 8: Test DNS Resolution Through the Chain

**Why We Need This**: We need to identify where in the DNS query chain the public IP is being returned. By querying different DNS servers directly, we can pinpoint the problem.

### Understanding the DNS Query Chain

With custom DNS, queries go through multiple hops:
```
Agent VM → Custom DNS Server (10.1.2.50)
    → forwards to ??? (we need to discover this)
    → returns IP to Agent VM
```

We'll test each DNS server independently to find where the problem occurs.

### Test 1: DNS Resolution from Agent VM (uses custom DNS)

**Command**:
```bash
# SSH to Agent VM
ssh azureuser@$VM_PUBLIC_IP

# Get Key Vault name from pipeline logs or Portal
KV_NAME="keyvault-dnslab12345"  # Replace with your actual name

# Test DNS resolution (uses /etc/resolv.conf DNS server)
nslookup $KV_NAME.vault.azure.net
```

**Expected Output (Broken)**:
```
Server:         10.1.2.50
Address:        10.1.2.50#53

Non-authoritative answer:
Name:   keyvault-dnslab12345.vault.azure.net
Address: 52.154.x.x  <-- PUBLIC IP (Wrong!)
```

**Analysis**: **Agent VM → DNS Resolver** queries **Custom DNS Server (10.1.2.50)**, which returns public IP.

### Test 2: Query Custom DNS Server Directly

**Command**:
```bash
# From Agent VM, query custom DNS explicitly
dig @10.1.2.50 $KV_NAME.vault.azure.net
```

**Expected Output (Broken)**:
```
;; ANSWER SECTION:
keyvault-dnslab12345.vault.azure.net. 60 IN A 52.154.x.x  <-- PUBLIC IP
```

**Analysis**: **Custom DNS Server (10.1.2.50)** returns public IP. But where did it get this answer?

### Test 3: Query Google DNS Directly (Public DNS)

**Command**:
```bash
# Query Google DNS
dig @8.8.8.8 $KV_NAME.vault.azure.net
```

**Expected Output**:
```
;; ANSWER SECTION:
keyvault-dnslab12345.vault.azure.net. 60 IN A 52.154.x.x  <-- PUBLIC IP (expected from public DNS)
```

**Analysis**: **Google DNS (8.8.8.8)** only knows public Azure records. This is expected - public DNS has NO knowledge of Private Link zones.

### Test 4: Query Azure DNS Directly

**Command**:
```bash
# Query Azure Recursive Resolver
dig @168.63.129.16 $KV_NAME.vault.azure.net
```

**Expected Output (Working)**:
```
;; ANSWER SECTION:
keyvault-dnslab12345.privatelink.vaultcore.azure.net. 10 IN A 10.1.2.5  <-- PRIVATE IP (correct!)
```

**Analysis**: **Azure Recursive Resolver (168.63.129.16)** correctly returns private IP by querying **Agent VNet → VNet Link → Private DNS Zone**.

### Comparison Table

| DNS Server Queried | IP Returned | Conclusion |
|--------------------|-------------|------------|
| **Agent VM default** (uses custom DNS) | 52.x.x.x (public) | ❌ Wrong IP |
| **Custom DNS (10.1.2.50)** directly | 52.x.x.x (public) | ❌ Problem here! |
| **Google DNS (8.8.8.8)** directly | 52.x.x.x (public) | ✅ Expected (public DNS doesn't know Private Link) |
| **Azure DNS (168.63.129.16)** directly | 10.1.2.5 (private) | ✅ Correct! |

**Root Cause Hypothesis**: **Custom DNS Server (10.1.2.50) → Forwarding Rules** are sending queries to **Google DNS (8.8.8.8)** instead of **Azure Recursive Resolver (168.63.129.16)**.

### Record Your Findings

**Agent VM DNS Resolution**: Returns `_______________` (IP address)

**Custom DNS Server (10.1.2.50)**: Returns `_______________` (IP address)

**Azure DNS (168.63.129.16)**: Returns `_______________` (IP address)

**Update EMAIL_TEMPLATE.md** → Diagnostic Evidence → STEP 8 section with your findings.

---

## STEP 9: Inspect Custom DNS Server Forwarding Configuration

**Why We Need This**: We've proven that **Custom DNS Server (10.1.2.50)** returns the wrong IP. Now we need to inspect its configuration to see WHERE it's forwarding queries and WHY it's not using Azure DNS.

### Understanding BIND9 Forwarding

**BIND9 Configuration Structure**:
```
/etc/bind/
├── named.conf                    # Main config file
├── named.conf.options           # Global forwarders defined here
└── named.conf.local             # Zone-specific (conditional) forwarders
```

**Two types of forwarding**:
1. **Global Forwarders**: Default destination for all queries
2. **Conditional Forwarding**: Zone-specific destinations (e.g., `*.privatelink.*` → 168.63.129.16)

### Check Global Forwarders

**Command**:
```bash
# SSH to custom DNS server
ssh azureuser@10.1.2.50

# Check global forwarders configuration
sudo cat /etc/bind/named.conf.options | grep -A 10 "forwarders"
```

**Expected Output (Broken)**:
```
forwarders {
    8.8.8.8;      // Google DNS
    8.8.4.4;      // Google DNS secondary
};
```

**Analysis**: **Custom DNS Server → Global Forwarders** points to Google DNS. Google DNS has NO knowledge of Azure Private DNS Zones!

### Check Conditional Forwarding Rules

**Command**:
```bash
# Check for zone-specific forwarding rules
sudo grep -r "privatelink" /etc/bind/

# Check named.conf.local for zone definitions
sudo cat /etc/bind/named.conf.local
```

**Expected Output (Broken)**:
```
(No output - no conditional forwarding rules exist)
```

**Expected Output (Working)**:
```
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};
```

### Verify 168.63.129.16 is Reachable

Before blaming configuration, verify the custom DNS server CAN reach Azure DNS:

**Command**:
```bash
# From custom DNS server, test connectivity to Azure DNS
dig @168.63.129.16 google.com

# Should return an answer if connectivity exists
```

**Expected Output**:
```
;; ANSWER SECTION:
google.com.             60      IN      A       142.250.x.x
```

✅ **Connectivity confirmed**: Custom DNS server CAN reach 168.63.129.16. The problem is purely configuration (missing conditional forwarding rules).

### Check BIND9 Query Logs (Optional)

**Command**:
```bash
# Enable query logging (if not already enabled)
sudo rndc querylog on

# Monitor logs in real-time
sudo tail -f /var/log/syslog | grep named

# From Agent VM, trigger a query
dig @10.1.2.50 keyvault-dnslab12345.vault.azure.net
```

**Expected Log Output**:
```
named[PID]: client @0x... 10.1.1.x#xxxxx (keyvault-dnslab12345.vault.azure.net): query: ...
named[PID]: forwarding 'keyvault-dnslab12345.vault.azure.net' to 8.8.8.8
```

✓ **Proof**: BIND9 is forwarding to 8.8.8.8 (Google DNS), not 168.63.129.16 (Azure DNS).

### Record Your Findings

**Global Forwarders**: `_______________` (e.g., 8.8.8.8, 8.8.4.4)

**Conditional Forwarding for `*.privatelink.*`**: ☐ Exists / ☑️ **Missing**

**168.63.129.16 Reachability**: ☐ Can reach / ☐ Cannot reach

**Update EMAIL_TEMPLATE.md** → Diagnostic Evidence → STEP 9 section with your findings.

---

## STEP 10: Compare Findings and Report to Instructor

Now let's compile all the data you collected into a comparison table to identify the exact problem.

### Comparison Table

Fill in this table with your findings from STEP 7-9:

| Component | Expected Value | Actual Value | Match? |
|-----------|---------------|--------------|--------|
| **Agent VNet → DNS Settings** | 168.63.129.16 (Azure) **OR** custom with conditional forwarding | 10.1.2.50 (custom) | ⚠️ Custom |
| **Custom DNS → Global Forwarders** | 168.63.129.16 **OR** public DNS (if conditional forwarding exists) | _________ | ☐ ✅ / ☐ ❌ |
| **Custom DNS → Conditional Forwarding for `*.privatelink.*`** | Forwards to 168.63.129.16 | _________ | ☐ ✅ / ☐ ❌ |
| **Custom DNS → DNS Response** | 10.1.2.5 (private) | _________ | ☐ ✅ / ☐ ❌ |
| **Azure DNS (168.63.129.16) → Response** | 10.1.2.5 (private) | 10.1.2.5 (private) | ✅ |
| **Private Endpoint → NIC → IP** | 10.1.2.5 | 10.1.2.5 | ✅ |
| **Agent VM → DNS Resolver → Response** | 10.1.2.5 (private) | _________ | ☐ ✅ / ☐ ❌ |

### Root Cause Analysis

Based on your comparison table, answer these questions:

**Q1**: Is the Agent VNet using custom DNS or Azure-provided DNS?
- Answer: `_______` (Custom/Azure-provided)

**Q2**: What does the custom DNS server's global forwarders point to?
- Answer: `_______` (8.8.8.8/168.63.129.16/other)

**Q3**: Does the custom DNS server have conditional forwarding rules for `*.privatelink.vaultcore.azure.net`?
- Answer: `_______` (Yes/No) ← **This is likely your problem!**

**Q4**: What IP did the Agent VM's DNS resolver return?
- Answer: `_______` (Private 10.1.2.x or Public 52.x?)

**Q5**: What IP did Azure DNS (168.63.129.16) return when queried directly?
- Answer: `_______` (Should be 10.1.2.5)

**Root Cause Statement** (complete this):
```
The pipeline fails because [Custom DNS Server (10.1.2.50) → Global Forwarders] points to 
________ (public DNS like 8.8.8.8) without [Custom DNS Server → Conditional Forwarding Rules] 
for *.privatelink.* zones. When [Agent VM → DNS Resolver] queries for Key Vault, 
[Custom DNS Server] forwards to ________, which only knows public Azure records and returns 
public IP 52.x.x.x. When [Pipeline → AzureKeyVault@2 Task] attempts to connect to this public IP, 
[Key Vault → Network Firewall] rejects the request because "public network access is disabled."

Missing configuration: Conditional forwarder rule in BIND9:
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forwarders { 168.63.129.16; };
};
```

### DNS Flow Diagrams

**Current (Broken) Flow**:
```
Agent VM (10.1.1.x)
    ↓ queries
Custom DNS Server (10.1.2.50)
    ↓ checks local zones (no match)
    ↓ no conditional forwarding rules
    ↓ forwards to global forwarders
Google DNS (8.8.8.8)
    ↓ queries public Azure DNS
Public IP: 52.x.x.x
    ↓ Agent VM attempts connection
Key Vault Firewall: REJECTED (public access disabled)
```

**Expected (Working) Flow**:
```
Agent VM (10.1.1.x)
    ↓ queries
Custom DNS Server (10.1.2.50)
    ↓ checks local zones (no match)
    ↓ checks conditional forwarding rules
    ↓ matches: *.privatelink.vaultcore.azure.net → 168.63.129.16
Azure Recursive Resolver (168.63.129.16)
    ↓ queries Agent VNet → VNet Link → Private DNS Zone
Private DNS Zone → A Record
    ↓ returns
Private IP: 10.1.2.5
    ↓ Agent VM connects successfully
Key Vault: ACCEPTED (via Private Endpoint)
```

### Update and Send Email to Instructor

1. Open `EMAIL_TEMPLATE.md`
2. Complete the **Diagnostic Evidence** section (STEP 7-9 findings)
3. Fill in the **Comparison Table (STEP 10)** section
4. Complete the **Root Cause Identified** section
5. Update **Next Steps Requested** section:

**Proposed Fix**:
```
Add conditional forwarding rule to BIND9 configuration (/etc/bind/named.conf.local):

zone "privatelink.vaultcore.azure.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};

Then reload BIND9: sudo rndc reload
```

**Questions for Instructor**:
- Is this the correct approach for Azure Private Link with custom DNS?
- Should we add rules for other `*.privatelink.*` zones (blob.core.windows.net, etc.)?
- In production, would we coordinate with DNS administrator team or revert to Azure-provided DNS?

📧 **Send the email to your instructor** and wait for confirmation before proceeding to STEP 11.

---

## STEP 11: Fix the Issue

Once your instructor confirms your analysis is correct, you can implement the fix.

### Understanding the Fix

You need to add **conditional forwarding rules** to **Custom DNS Server (10.1.2.50) → BIND9 Configuration** that tell it to forward queries for `*.privatelink.vaultcore.azure.net` to **Azure Recursive Resolver (168.63.129.16)** instead of **Google DNS (8.8.8.8)**.

**What is Conditional Forwarding?**

Instead of forwarding ALL queries to one destination, you forward different zones to different DNS servers:

| Query Type | Forward To | Why? |
|------------|------------|------|
| `*.privatelink.vaultcore.azure.net` | Azure DNS (168.63.129.16) | Only Azure DNS knows private endpoint IPs |
| `*.privatelink.blob.core.windows.net` | Azure DNS (168.63.129.16) | For Storage Account private endpoints |
| Everything else | Public DNS (8.8.8.8, 1.1.1.1, etc.) | Regular internet domains |

### Option 1: Add Conditional Forwarding (Production Approach)

**Step-by-step**:

```bash
# 1. SSH to custom DNS server
ssh azureuser@10.1.2.50

# 2. Edit BIND9 local configuration
sudo nano /etc/bind/named.conf.local

# 3. Add this zone configuration:
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};

# 4. Save and exit (Ctrl+X, Y, Enter)

# 5. Validate configuration syntax
sudo named-checkconf

# 6. Reload BIND9 configuration
sudo rndc reload

# 7. Verify service is running
sudo systemctl status named
```

**Expected Output**:
```
● named.service - BIND Domain Name Server
   Loaded: loaded (/lib/systemd/system/named.service; enabled)
   Active: active (running)
```

### Option 2: Use Helper Script (Lab Shortcut)

The lab includes a helper script for quick configuration:

```bash
# SSH to custom DNS server
ssh azureuser@10.1.2.50

# Run helper script to enable Azure DNS forwarding
sudo /usr/local/bin/toggle-azure-dns.sh enable

# Verify BIND9 reloaded
sudo systemctl status named
```

### Option 3: Revert to Azure-Provided DNS (Alternative)

If custom DNS is not required, you can revert **Agent VNet → DNS Settings** back to Azure-provided:

**Azure Portal**:
1. Navigate to **Virtual networks** → `vnet-agent`
2. Click **DNS servers** in left menu
3. Select **Default (Azure-provided)**
4. Click **Save**
5. **Restart Agent VM** for DNS changes to take effect

**Azure CLI**:
```bash
# Remove custom DNS servers (reverts to Azure-provided)
az network vnet update \
  --resource-group rg-dnslab \
  --name vnet-agent \
  --dns-servers ""

# Restart Agent VM to pick up new DNS settings
az vm restart \
  --resource-group rg-dnslab \
  --name vm-agent-dnslab
```

### Option 4: Use Fix Script (Quick Lab Reset)

To quickly restore the lab to working state:

```bash
# From your Codespace/terminal
./fix-lab.sh lab3
```

⚠️ **Note**: This script may either configure BIND9 forwarding OR revert to Azure DNS depending on lab scenario design.

### What Makes the Fix Work?

**Before Fix**:
```
Custom DNS (10.1.2.50)
├── Global Forwarders: 8.8.8.8
└── Conditional Forwarding: (none)

Query: keyvault-dnslab12345.vault.azure.net
  → Matches no zones
  → Uses global forwarders → 8.8.8.8
  → Returns: 52.x.x.x (public)
```

**After Fix**:
```
Custom DNS (10.1.2.50)
├── Global Forwarders: 8.8.8.8
└── Conditional Forwarding:
    └── privatelink.vaultcore.azure.net → 168.63.129.16

Query: keyvault-dnslab12345.vault.azure.net
  → Matches privatelink zone rule!
  → Forwards to 168.63.129.16
  → Returns: 10.1.2.5 (private)
```

---

## STEP 12: Verify the Fix

### Test 1: Verify Conditional Forwarding Rule Exists

```bash
# SSH to custom DNS server
ssh azureuser@10.1.2.50

# Check if conditional forwarding rule was added
sudo grep -A 4 "privatelink.vaultcore.azure.net" /etc/bind/named.conf.local
```

**Expected Output**:
```
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};
```

✅ **Success Criteria**: Zone configuration exists with forwarder pointing to 168.63.129.16

### Test 2: Re-test DNS Resolution from Agent VM

SSH back to the Agent VM and test DNS again:

```bash
# SSH to Agent VM
ssh azureuser@$VM_PUBLIC_IP

# Test DNS resolution
nslookup keyvault-dnslab12345.vault.azure.net
```

**Expected Output (Fixed)**:
```
Server:         10.1.2.50
Address:        10.1.2.50#53

Non-authoritative answer:
Name:   keyvault-dnslab12345.vault.azure.net
Address: 10.1.2.5  <-- PRIVATE IP (Fixed!)
```

✅ **Success Criteria**: Returns private IP (10.1.2.5) instead of public IP (52.x.x.x)

**What changed?**
- Before: **Custom DNS (10.1.2.50)** → global forwarders (8.8.8.8) → returns 52.x.x.x
- After: **Custom DNS (10.1.2.50)** → conditional forwarding (168.63.129.16) → returns 10.1.2.5

### Test 3: Verify Custom DNS Forwarding Path (Optional)

```bash
# From custom DNS server, enable query logging
ssh azureuser@10.1.2.50
sudo rndc querylog on

# Monitor logs
sudo tail -f /var/log/syslog | grep "forwarding"

# From Agent VM (in another terminal), trigger query
dig keyvault-dnslab12345.vault.azure.net
```

**Expected Log Output**:
```
named[PID]: forwarding 'keyvault-dnslab12345.vault.azure.net' to 168.63.129.16
```

✅ **Success Criteria**: Logs show forwarding to 168.63.129.16, not 8.8.8.8

### Test 4: Re-run the Pipeline

1. Go to Azure DevOps
2. Navigate to your pipeline
3. Click **Run pipeline** (or push a new commit)

**Expected Output** (all stages succeed):

```
✅ RetrieveConfig Stage
   ✓ Retrieve Configuration from Key Vault
     Downloaded secret: AppMessage

✅ Build Stage
   ✓ Install dependencies
   ✓ Create application package

✅ Deploy Stage
   ✓ Display message: "Hello from Azure Key Vault via Private Endpoint!"
```

✅ **Success Criteria**: All three stages complete with green checkmarks

### Test 5: Verify Connection Uses Private IP (Optional)

```bash
# SSH to Agent VM during pipeline run
# Check active connections to Key Vault
sudo netstat -tnp | grep :443 | grep keyvault

# Should show connection to 10.1.2.5:443 (private), not 52.x.x.x:443 (public)
```

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

If the pipeline still fails, revisit the DNS configuration and verify **Custom DNS Server (10.1.2.50) → Conditional Forwarding Rules** are forwarding `*.privatelink.*` queries to **Azure Recursive Resolver (168.63.129.16)**.

---

## 🧠 Key Learning Points

### 1. Custom DNS Requires Conditional Forwarding

**Critical Rule**: When using custom DNS servers with Azure Private Link, you **cannot** forward all queries to a single public DNS server.

| Zone Type | Must Forward To | Why? |
|-----------|-----------------|------|
| `*.privatelink.*` zones | Azure DNS (168.63.129.16) | Only Azure DNS knows private endpoint IPs |
| `*.azure.com`, `*.microsoft.com` | Azure DNS (168.63.129.16) **OR** public DNS | Azure services work either way |
| Everything else | Your preferred DNS (Google, on-prem, etc.) | Regular internet resolution |

**BIND9 Configuration Example**:
```bind
# Conditional forwarding for Private Link zones
zone "privatelink.vaultcore.azure.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};

zone "privatelink.blob.core.windows.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};

# Global forwarders for everything else
forwarders {
    8.8.8.8;  // Google DNS
    8.8.4.4;
};
```

### 2. The Special IP: 168.63.129.16

**What is it?**
- Azure Wire Server / Recursive Resolver
- **Only** accessible from within Azure VNets (not from internet or on-premises)
- **Only** source for Azure Private DNS Zone resolution
- Cannot be queried from outside Azure

**Why it matters:**
- Public DNS servers (Google 8.8.8.8, Cloudflare 1.1.1.1) have **zero** knowledge of Azure Private DNS Zones
- Azure Private Link zones exist **only** in Azure's infrastructure
- Custom DNS servers in Azure VNets can reach 168.63.129.16
- Without forwarding to 168.63.129.16, Private Link resolution is impossible

**Test 168.63.129.16 accessibility**:
```bash
# From inside Azure VNet: Works
dig @168.63.129.16 google.com

# From internet: Fails (not routable)
dig @168.63.129.16 google.com
```

### 3. Hierarchical DNS Troubleshooting

Using component hierarchy helps you diagnose custom DNS systematically:

```
Pipeline → AzureKeyVault@2 Task (fails with "public network" error)
    ↓ runs on
Agent VM → DNS Resolver (what IP did it get?)
    ↓ queries
Custom DNS Server (10.1.2.50) (what does its config say?)
    ↓ checks
Custom DNS → Local Zones (any matches?)
    ↓ checks
Custom DNS → Conditional Forwarding Rules (any zone-specific rules?)
    ↓ NO RULES, falls back to
Custom DNS → Global Forwarders (where do these point?)
    ↓ points to
Google DNS (8.8.8.8) (only knows public records)
    ↓ returns
Public IP (52.x.x.x) ← WRONG!
```

Walk down this chain to find where the break occurs.

### 4. Lab Comparison: Identifying Scenarios

When you see "public network access disabled" errors in production, use this decision tree:

| Aspect | Lab 1 | Lab 2 | Lab 3 |
|--------|-------|-------|-------|
| **Root Cause** | DNS A record points to wrong IP | VNet link missing | Custom DNS misconfigured |
| **VNet DNS Setting** | Azure-provided (168.63.129.16) | Azure-provided (168.63.129.16) | Custom DNS (10.1.2.50) |
| **DNS Query Path** | Direct to Azure DNS | Direct to Azure DNS | Through custom DNS first |
| **What's Missing** | Correct A record IP | VNet link to Private DNS Zone | Conditional forwarding rule |
| **DNS Returns** | Wrong private IP (10.1.2.4) | Public IP (52.x.x.x) | Public IP (52.x.x.x) |
| **Key Diagnostic** | Check A record IP | Check VNet links | Check custom DNS forwarders |
| **Fix Approach** | Update A record | Create VNet link | Add conditional forwarding |
| **Fix Location** | Private DNS Zone | Private DNS Zone | Custom DNS server config |

**Decision Tree**:
```
Start: "Public network access disabled" error
    ↓
Q: What does Agent VNet → DNS Settings show?
    ├─ Azure-provided (empty/168.63.129.16)
    │   ↓
    │   Q: Does VNet link exist?
    │   ├─ Yes → Lab 1 (check A record IP)
    │   └─ No → Lab 2 (create VNet link)
    │
    └─ Custom DNS (10.1.2.50 or other IP)
        ↓
        → Lab 3 (check conditional forwarding rules)
```

### 5. Error Messages Are Misleading

```
"Public network access is disabled and request is not from a trusted service 
nor via an approved private link"
```

This error **never mentions DNS**, but DNS misconfiguration is often the cause. The error tells you **what** failed (wrong network path) but not **why** (DNS returned wrong IP).

**Troubleshooting Flow**:
1. See "public network access" error → Think: "DNS issue?"
2. Check if private endpoint exists → If yes, definitely DNS
3. Check VNet DNS settings → Custom or Azure-provided?
4. If custom → Check forwarding rules
5. If Azure-provided → Check VNet links (Lab 2) or A records (Lab 1)

### 6. Production Considerations

**When deploying custom DNS in Azure:**

✅ **Do**:
- Configure conditional forwarding for ALL `*.privatelink.*` zones you use
- Test DNS resolution from VMs before deploying applications
- Document custom DNS configuration in runbooks
- Set up monitoring for DNS server availability
- Have rollback plan (revert to Azure-provided DNS)

❌ **Don't**:
- Forward ALL queries to public DNS (8.8.8.8, 1.1.1.1) without conditional rules
- Assume public DNS knows about Private Link zones
- Deploy custom DNS without testing Private Endpoint connectivity
- Forget to update DNS configuration when adding new Private Link services

**Common Mistake**:
"We tested the DNS server and it resolves google.com fine!"
→ Must test with **actual Private Link FQDNs**, not just public domains

### 7. Reusable Troubleshooting Process

**Next time you see Private Link issues with custom DNS:**

| Step | Question | Tool |
|------|----------|------|
| 1 | Is VNet using custom DNS? | `az network vnet show --query dhcpOptions.dnsServers` |
| 2 | What IP does custom DNS return? | `dig @<custom-dns-ip> <keyvault>.vault.azure.net` |
| 3 | What IP does Azure DNS return? | `dig @168.63.129.16 <keyvault>.vault.azure.net` |
| 4 | Can custom DNS reach 168.63.129.16? | `dig @168.63.129.16 google.com` (from DNS server) |
| 5 | Global forwarders configured? | Check `/etc/bind/named.conf.options` |
| 6 | Conditional forwarding for `*.privatelink.*`? | Check `/etc/bind/named.conf.local` |
| 7 | After fix, DNS cache cleared? | Restart VM or `sudo systemd-resolve --flush-caches` |

---

## 📊 Lab Series Comparison

Understanding how all three labs relate:

### Symptom Similarity

All three labs show the **same error message**:
```
"Public network access is disabled and request is not from a trusted service 
nor via an approved private link"
```

But the **root causes are different**!

### Diagnostic Path

```
Error: "Public network access disabled"
    ↓
1. Check: Does Private Endpoint exist?
   ├─ No → Create Private Endpoint (not covered in labs)
   └─ Yes →
       ↓
2. Check: VNet DNS Settings?
   ├─ Azure-provided →
   │   ↓
   │   3a. Check: VNet Links exist?
   │   ├─ No → Lab 2 (Missing VNet Link)
   │   └─ Yes →
   │       ↓
   │       3b. Check: A Record IP correct?
   │       ├─ No → Lab 1 (Wrong A Record)
   │       └─ Yes → Other issue (NSG? Route table?)
   │
   └─ Custom DNS →
       ↓
       4. Check: Conditional forwarding configured?
       ├─ No → Lab 3 (Custom DNS Misconfiguration)
       └─ Yes → Check: Forwarding to 168.63.129.16?
           ├─ No → Lab 3 (Wrong forwarder IP)
           └─ Yes → Other issue (Custom DNS server down?)
```

### Key Differentiators

| What to Check | Lab 1 | Lab 2 | Lab 3 |
|---------------|-------|-------|-------|
| **VNet DNS Settings** | Azure-provided | Azure-provided | **Custom DNS** |
| **VNet Links** | ✅ Exist | ❌ **Missing** | ✅ Exist |
| **A Record IP** | ❌ **Wrong** | ✅ Correct | ✅ Correct |
| **Custom DNS Forwarding** | N/A | N/A | ❌ **Missing** |

### Real-World Application

When you encounter similar errors in production:

1. **First**: Check VNet DNS settings
   - Custom DNS? → Think Lab 3
   - Azure-provided? → Think Lab 1 or Lab 2

2. **Second**: Query DNS from affected VM
   - Returns public IP? → DNS configuration issue
   - Returns wrong private IP? → Lab 1 (A record)
   - Returns correct private IP? → Not DNS, check network path

3. **Third**: If custom DNS involved
   - Can you query 168.63.129.16 directly from VM and get correct IP?
   - If yes → Custom DNS forwarding issue (Lab 3)
   - If no → VNet link or A record issue (Lab 1 or 2)

---

## 🎓 Next Steps

- Review all three labs' comparison table to understand scenario differences
- Practice identifying which scenario applies based on symptoms
- Consider how you'd handle custom DNS in your production environment
- Think about automation: Infrastructure-as-Code for BIND9 configuration

**Real-world application**:
When you encounter "public network access" errors in production:
1. Check if private endpoints exist
2. Verify DNS resolution (public vs private IP)
3. Check VNet DNS settings (Azure-provided vs custom)
4. If custom DNS, verify conditional forwarding for `*.privatelink.*` zones to 168.63.129.16

**Congratulations!** You've completed all three DNS troubleshooting labs and learned systematic diagnosis of Azure Private Link DNS issues.

---

### 📺 Recommended Resources

**Official Documentation:**
- [Azure Private Endpoint DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Private Link DNS integration scenarios](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns-integration)
- [Azure DNS Private Resolver](https://learn.microsoft.com/en-us/azure/dns/dns-private-resolver-overview)
- [Custom DNS server configuration for Azure VNets](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-networks-name-resolution-for-vms-and-role-instances)

**Video Resources:**
- [Azure Private Link and DNS Integration Scenarios](https://www.youtube.com/watch?v=vJXMF_jHb2Y) by John Savill
- [Azure Private Endpoint DNS Configuration](https://www.youtube.com/watch?v=j9QmMEWmcfo) by John Savill

---

Good luck with your Azure DNS troubleshooting journey! 🚀

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
