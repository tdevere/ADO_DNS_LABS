# Lab 2: Missing Virtual Network Link

## 📋 Objectives

**What Breaks**: The Virtual Network Link between the Agent VNet and Private DNS Zone gets deleted.

**What You'll Learn**:
- How Azure split-horizon DNS works (same FQDN, different IPs based on location)
- Why VNet links are required for Private DNS Zone resolution
- How to diagnose DNS falling back to public resolution
- Systematic data collection for VNet connectivity issues

**What You'll Fix**: Create the missing VNet link to enable private DNS resolution.

---

## 📧 Background Story

You are Jordan Chen, DevOps Engineer at Contoso HealthTech Solutions. Three weeks after resolving the DNS A record issue (Lab 1), the pipeline is failing again with Key Vault access timeouts.

Your manager wants you to follow the Azure Support troubleshooting workflow systematically before escalating.

> **Real-World Context**: This happens when a new application team spins up a VNet and assumes they can use the "centrally managed" Private DNS Zone, but forgets to link it. Or when an IaC pipeline runs in a different order than expected. The confusing part? DNS resolution "works" (returns an IP), but it's the wrong IP (public instead of private).

## Prerequisites

- Completed Lab 1 (DNS A Record Misconfiguration)
- Understanding of Azure Private DNS Zones
- Familiarity with VNet concepts

---

## STEP 1: Review the Objectives

Before breaking anything, understand what you're about to investigate:

**The Break**: We'll delete the Virtual Network Link that connects your Agent VNet to the Private DNS Zone.

**Expected Symptom**: **Agent VM → DNS Resolver** will query **Azure Recursive Resolver (168.63.129.16)**, but without the VNet link, it won't find the **Private DNS Zone → A Record**. Instead, it falls back to public DNS and returns a public IP address.

**Learning Goal**: Understand Azure's split-horizon DNS - the same FQDN (`*.vault.azure.net`) returns different IPs depending on whether your VNet is linked to the Private DNS Zone.

---

## STEP 2: Break the Lab and Observe the Failure

Run the break script:
```bash
./break-lab.sh lab2
```

**What this does** (silently, like real-world changes):
- Deletes the VNet link between Agent VNet and Private DNS Zone
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

---

## STEP 3: Understand the Architecture

Before diving into troubleshooting, understand the components involved:

### Discover Your Resources

**Azure Portal Navigation**:
1. Go to **Resource groups** → find `rg-dnslab` (or similar)
2. Look for these resources:
   - **Key Vault** (keyvault-dnslab...)
   - **Private Endpoint** (pe-keyvault-...)
   - **Private DNS Zone** (privatelink.vaultcore.azure.net)
   - **Virtual Network** (vnet-agent)
   - **Virtual Machine** (vm-agent-dnslab)

### Component Hierarchy

```
Pipeline → RetrieveConfig Stage → AzureKeyVault@2 Task
    ↓ (runs on)
Agent VM → Network Stack → DNS Resolver
    ↓ (queries)
Azure Recursive Resolver (168.63.129.16)
    ↓ (should check)
Agent VNet → VNet Link → Private DNS Zone → A Record → Private Endpoint IP
    ↓ (but without VNet link, falls back to)
Public DNS → Public IP address
```

### Split-Horizon DNS Concept

The same FQDN (`keyvault-dnslab12345.vault.azure.net`) can return **two different IP addresses**:

| Resolution Path | Returns | Used When |
|----------------|---------|-----------|
| **Private DNS Zone → A Record** | 10.1.2.x (Private Endpoint) | VNet has link to Private DNS Zone |
| **Public DNS** | 52.x.x.x (Public endpoint) | No VNet link, falls back to internet DNS |

**This is called "split-horizon DNS"** - same name, different answer based on where you're querying from.

### Update Your Email Draft

Open `EMAIL_TEMPLATE.md` in this lab folder and update:
- **Affected Resource Details** table (fill in your actual resource names)
- **Error Messages** section (paste the error from STEP 2)

---

## STEP 4: Understand the Error

Let's interpret what the error message tells us:

| What the Error Says | Hierarchical Component | What This Means |
|---------------------|------------------------|-----------------|
| "Public network access is disabled" | **Key Vault → Network Settings** blocks public IPs | Key Vault requires private endpoint access only |
| "Request is not from a trusted service" | **Pipeline → Service Principal** identity is not in exception list | Authentication succeeded, but network path is wrong |
| "Nor via an approved private link" | **Agent VM → Network Path** didn't use Private Endpoint | Connection attempt came from public IP range, not private |

**Root Cause Hypothesis**: **Agent VM → DNS Resolver** is returning a public IP address instead of the **Private Endpoint → Private IP**, causing **Pipeline → AzureKeyVault@2 Task** to attempt connection over public internet (which Key Vault rejects).

**Why would DNS return public IP?** Two possible reasons:
1. **Agent VNet → VNet Link** to Private DNS Zone is missing (STEP 7 will verify)
2. **Agent VNet → DNS Settings** points to custom DNS server instead of Azure DNS (168.63.129.16)

---

## STEP 5: Complete Azure Guided Troubleshooter 🧭

Before collecting detailed data, complete the Azure Guided Troubleshooter workflow. This simulates what Azure Support uses to route your case to the right team.

### Answer These 3 Questions

<details>
<summary><strong>Question 1: Does your issue involve resources in a Virtual Network (VNet)?</strong></summary>

**Your Answer**: ☑️ **Yes**

**Why**: 
- **Agent VM** runs in Agent VNet (10.0.0.0/16)
- **Private Endpoint** connects to Key Vault from another VNet (10.1.0.0/16)
- **Private DNS Zone** requires VNet links to function

**Hint**: If both "yes" and Private Link/DNS are involved, you're in Azure Networking territory.

</details>

<details>
<summary><strong>Question 2: Are you experiencing an issue with DNS, Network connectivity, or Application-specific behavior?</strong></summary>

**Your Answer**: 🔹 **DNS issue**

**Why**: 
- The error says "not via approved private link"
- This suggests wrong IP address is being used
- DNS resolution determines which IP **Agent VM → DNS Resolver** returns
- If DNS returns public IP, connection fails at Key Vault firewall

**Hint**: "Public network access is disabled" + Private Endpoint = almost always DNS misconfiguration

</details>

<details>
<summary><strong>Question 3: What DNS solution(s) does your architecture use?</strong></summary>

**Your Answer**: 🔹 **Azure Private DNS Zone**

**Why**: 
- Resource group contains **privatelink.vaultcore.azure.net** zone
- This zone holds **A Record** pointing to **Private Endpoint IP**
- **Agent VNet** should query this zone via **VNet Link**

**Hint**: Private Endpoint scenarios typically use Azure Private DNS Zones for split-horizon DNS

</details>

### Troubleshooter Result

**Routing**: SAP Azure / Azure DNS / DNS Resolution Failures

**Next Steps**: You've provided enough context to route to DNS specialists. Now collect diagnostic evidence to attach to your collaboration request.

### Update Your Email Template

Open `EMAIL_TEMPLATE.md` and complete:
- **Azure Guided Troubleshooter Responses** section (mark your answers)
- **Timeline** section (when did it last work? when did it break?)

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
| **Key Vault → Private Endpoint** exists (Portal verification) | Private endpoint is configured and should be available |
| **Private DNS Zone** exists (Portal verification) | Zone `privatelink.vaultcore.azure.net` is present |

### What We Don't Know ❓

1. **Is Agent VNet linked to Private DNS Zone?**
   - Does **Agent VNet → VNet Link** exist?
   - If missing, **Azure Recursive Resolver (168.63.129.16)** can't query **Private DNS Zone → A Record**

2. **What IP does Agent VM DNS resolver return?**
   - Does **Agent VM → DNS Resolver** return private IP (10.1.2.x) or public IP (52.x.x.x)?
   - This tells us if split-horizon DNS is working

3. **What IP is Private Endpoint using?**
   - What's the actual IP of **Private Endpoint → Network Interface**?
   - We need to verify DNS should return this specific IP

### Why We Need This Data 🎯

**DNS Resolution Flow (Expected)**:
```
Agent VM → DNS Resolver → Azure Recursive Resolver (168.63.129.16)
    → checks: "Is Agent VNet linked to any Private DNS Zones?"
    → finds: Agent VNet → VNet Link → Private DNS Zone
    → queries: Private DNS Zone → A Record (keyvault-dnslab12345)
    → returns: 10.1.2.x (Private Endpoint IP)
```

**DNS Resolution Flow (Suspected - Broken)**:
```
Agent VM → DNS Resolver → Azure Recursive Resolver (168.63.129.16)
    → checks: "Is Agent VNet linked to any Private DNS Zones?"
    → finds: NO LINKS
    → falls back to: Public DNS on internet
    → returns: 52.x.x.x (Public IP)
```

**The Missing Link**: If **Agent VNet → VNet Link** doesn't exist, **Azure Recursive Resolver** has no way to know that queries from this VNet should use the **Private DNS Zone**. It's like trying to use a private phone book without subscribing to it.

### Action Plan

We'll collect three data points:
1. **STEP 7**: Check if VNet link exists (Portal + CLI + REST API)
2. **STEP 8**: Test what IP Agent VM's DNS resolver returns (nslookup)
3. **STEP 9**: Verify Private Endpoint's actual IP (Portal + CLI)

Then in **STEP 10**, we'll compare these values in a table and identify the exact mismatch.

---

## STEP 7: Check Virtual Network Link Status

**Why We Need This**: The VNet link is what tells **Azure Recursive Resolver (168.63.129.16)** to query **Private DNS Zone → A Record** when **Agent VM → DNS Resolver** makes a DNS request.

### Understanding VNet Links

**Concept**: A VNet link is like a "subscription" that allows a VNet to "read" records from a Private DNS Zone.

**Without VNet Link**: 
- **Azure Recursive Resolver** doesn't know to check **Private DNS Zone**
- Falls back to public DNS (internet)
- Returns public IP (52.x.x.x)

**With VNet Link**:
- **Azure Recursive Resolver** checks **Private DNS Zone → A Record**
- Returns private IP (10.1.2.x)
- **Agent VM** can connect to **Private Endpoint**

### Option 1: Azure Portal (Recommended for Beginners)

1. Navigate to **Private DNS zones** in Azure Portal
2. Click on `privatelink.vaultcore.azure.net`
3. In left menu, click **Virtual network links**
4. Look for a link named something like `link-to-vnet-agent`

**What to look for**:
- Link status: **Succeeded** or **Missing**
- Linked virtual network: Should show your Agent VNet name
- Registration enabled: Typically **Disabled** for Private Link zones

### Option 2: Azure CLI

```bash
# Get your resource group name
az group list --query "[?contains(name, 'dnslab')].name" -o tsv

# Set variables (replace with your values)
RG_NAME="rg-dnslab"  # From command above

# List all VNet links
az network private-dns link vnet list \
  --resource-group $RG_NAME \
  --zone-name privatelink.vaultcore.azure.net \
  --output table
```

**Expected Output (Broken State)**:
```
(Empty - no links listed)
```

**Expected Output (Working State)**:
```
Name                    ResourceGroup    ProvisioningState    VirtualNetwork
----------------------  ---------------  -------------------  ----------------
link-to-vnet-agent      rg-dnslab        Succeeded            /subscriptions/.../vnet-agent
```

### Option 3: Azure REST API (Advanced)

```bash
# Get access token
TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Get subscription ID
SUB_ID=$(az account show --query id -o tsv)

# Set variables
RG_NAME="rg-dnslab"
ZONE_NAME="privatelink.vaultcore.azure.net"

# Call REST API
curl -X GET \
  -H "Authorization: Bearer $TOKEN" \
  "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_NAME/providers/Microsoft.Network/privateDnsZones/$ZONE_NAME/virtualNetworkLinks?api-version=2020-06-01" \
  | jq '.value[] | {name: .name, provisioningState: .properties.provisioningState, vnet: .properties.virtualNetwork.id}'
```

### Record Your Findings

**VNet Link Status**: ❌ Missing / ✅ Exists

**If exists, note details**:
- Link name: `_______________`
- Linked VNet: `_______________`
- Registration enabled: `_______________`

**Update EMAIL_TEMPLATE.md** → Diagnostic Evidence → STEP 7 section with your findings.

---

## STEP 8: Check DNS Resolution from Agent VM

**Why We Need This**: This shows what IP address **Agent VM → DNS Resolver** actually receives when querying for the Key Vault. This is the "ground truth" of what the agent sees.

### Understanding Split-Horizon DNS

**Split-Horizon Concept**: The same FQDN returns different IPs based on where you query from:

| Query Source | DNS Path | Returns |
|-------------|----------|---------|
| **Inside VNet (with link)** | Agent VNet → VNet Link → Private DNS Zone | 10.1.2.x (private) |
| **Inside VNet (no link)** | Agent VNet → Azure Resolver → Public DNS | 52.x.x.x (public) |
| **From internet** | Public DNS | 52.x.x.x (public) |

### Get Key Vault Name

**From Pipeline Logs** (STEP 2):
```
Key vault name: keyvault-dnslab12345
```

**From Azure Portal**:
1. Resource groups → `rg-dnslab`
2. Look for Key Vault resource (starts with `keyvault-dnslab`)

### Test DNS Resolution

```bash
# SSH to Agent VM (get IP from Portal or CLI)
VM_NAME="vm-agent-dnslab"
RG_NAME="rg-dnslab"

# Get VM public IP
VM_PUBLIC_IP=$(az vm show \
  --resource-group $RG_NAME \
  --name $VM_NAME \
  --show-details \
  --query 'publicIps' -o tsv)

# SSH to VM
ssh azureuser@$VM_PUBLIC_IP

# Once on the VM, test DNS resolution
nslookup keyvault-dnslab12345.vault.azure.net
```

**Expected Output (Broken - No VNet Link)**:
```
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
Name:   keyvault-dnslab12345.vault.azure.net
Address: 52.154.123.45  <-- PUBLIC IP (Azure public range)
```

**Expected Output (Working - With VNet Link)**:
```
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
Name:   keyvault-dnslab12345.vault.azure.net
Address: 10.1.2.5  <-- PRIVATE IP (VNet range)
```

### Interpreting the Output

| Field | Meaning |
|-------|---------|
| `Server: 168.63.129.16` | **Agent VM → DNS Resolver** is using **Azure Recursive Resolver** (correct!) |
| `Address: 52.x.x.x` | **Azure Recursive Resolver** returned public IP (PROBLEM: no VNet link) |
| `Address: 10.1.2.x` | **Azure Recursive Resolver** returned private IP (WORKING: VNet link exists) |

### Record Your Findings

**DNS Resolution Result**:
- Resolved to: `_______________` (IP address)
- Is this private (10.x.x.x) or public (52.x/13.x/20.x)? `_______________`

**Update EMAIL_TEMPLATE.md** → Diagnostic Evidence → STEP 8 section with your findings.

---

## STEP 9: Verify Private Endpoint IP Address

**Why We Need This**: We need to know what IP **Private DNS Zone → A Record** *should* return. Then we can compare it with what **Agent VM → DNS Resolver** *actually* returns (from STEP 8).

### Understanding Private Endpoint IPs

**Private Endpoint Components**:
```
Private Endpoint → Network Interface → Private IP Configuration → IP Address
```

The **Private Endpoint** gets a **Network Interface** in a VNet, which has a **Private IP** assigned. The **Private DNS Zone → A Record** should point to this IP.

### Option 1: Azure Portal

1. Navigate to **Private endpoints** in Azure Portal
2. Find your endpoint (e.g., `pe-keyvault-dnslab12345`)
3. Click on it to open details
4. Look for **Network interface** section
5. Click the network interface name
6. Look for **IP configurations** → **Private IP address**

### Option 2: Azure CLI

```bash
# Set variables
RG_NAME="rg-dnslab"
PE_NAME="pe-keyvault-dnslab12345"  # From Portal or naming convention

# Get Network Interface ID from Private Endpoint
NIC_ID=$(az network private-endpoint show \
  --name $PE_NAME \
  --resource-group $RG_NAME \
  --query 'networkInterfaces[0].id' -o tsv)

# Get Private IP from Network Interface
az network nic show --ids $NIC_ID \
  --query 'ipConfigurations[0].privateIPAddress' -o tsv
```

**Expected Output**:
```
10.1.2.5
```

### Option 3: Check DNS Zone A Record

You can also see what IP the **Private DNS Zone → A Record** is configured with:

```bash
# Get Key Vault resource name (without .vault.azure.net)
KV_RESOURCE_NAME="keyvault-dnslab12345"

# Query A record
az network private-dns record-set a show \
  --resource-group $RG_NAME \
  --zone-name privatelink.vaultcore.azure.net \
  --name $KV_RESOURCE_NAME \
  --query 'aRecords[0].ipv4Address' -o tsv
```

**Expected Output**:
```
10.1.2.5
```

### Record Your Findings

**Private Endpoint IP**: `_______________`

**DNS Zone A Record IP**: `_______________`

**Do they match?**: ✅ Yes / ❌ No

**Update EMAIL_TEMPLATE.md** → Diagnostic Evidence → STEP 9 section with your findings.

---

## STEP 10: Compare Findings and Report to Instructor

Now let's compile all the data you collected into a comparison table to identify the exact problem.

### Comparison Table

Fill in this table with your findings from STEP 7-9:

| Component | Expected Value | Actual Value | Match? |
|-----------|---------------|--------------|--------|
| **Private Endpoint → NIC → Private IP** | 10.1.2.x | _________ | ☐ ✅ / ☐ ❌ |
| **Private DNS Zone → A Record → IP** | 10.1.2.x | _________ | ☐ ✅ / ☐ ❌ |
| **Agent VNet → VNet Link** | Exists and linked | _________ | ☐ ✅ / ☐ ❌ |
| **Agent VM → DNS Resolver → Response** | 10.1.2.x (private) | _________ | ☐ ✅ / ☐ ❌ |

### Root Cause Analysis

Based on your comparison table, answer these questions:

**Q1**: Does the Private Endpoint have a valid private IP?
- Answer: `_______` (Yes/No)

**Q2**: Does the Private DNS Zone A record point to the correct IP?
- Answer: `_______` (Yes/No)

**Q3**: Is the Agent VNet linked to the Private DNS Zone?
- Answer: `_______` (Yes/No) ← **This is likely your problem!**

**Q4**: What IP did the Agent VM's DNS resolver return?
- Answer: `_______` (Private 10.x or Public 52.x?)

**Root Cause Statement** (complete this):
```
The pipeline fails because [Agent VNet → VNet Link] is ________ (missing/misconfigured).
Without this link, [Azure Recursive Resolver (168.63.129.16)] cannot query 
[Private DNS Zone → A Record], causing [Agent VM → DNS Resolver] to fall back 
to public DNS and receive a public IP (52.x.x.x) instead of the private endpoint 
IP (10.1.2.x). When [Pipeline → AzureKeyVault@2 Task] attempts to connect to 
this public IP, [Key Vault → Network Firewall] rejects the request because 
"public network access is disabled."
```

### Update and Send Email to Instructor

1. Open `EMAIL_TEMPLATE.md`
2. Complete the **Diagnostic Evidence** section (STEP 7-9 findings)
3. Fill in the **Comparison Table (STEP 10)** section
4. Complete the **Root Cause Identified** section
5. Update **Next Steps Requested** to request validation of your fix plan

**Subject Line**:
```
Azure Private DNS VNet Link Issue - [Your Name] - Lab 2
```

**Key Points to Include**:
- All three data points collected (VNet link status, DNS resolution, Private Endpoint IP)
- Comparison table showing the mismatch
- Root cause: Missing VNet link between Agent VNet and Private DNS Zone
- Proposed fix: Create VNet link with `registration-enabled: false`

📧 **Send the email to your instructor** and wait for confirmation before proceeding to STEP 11.

---

## STEP 11: Fix the Issue

Once your instructor confirms your analysis is correct, you can implement the fix.

### Understanding the Fix

You need to create a **Virtual Network Link** that connects **Agent VNet** to **Private DNS Zone**. This link tells **Azure Recursive Resolver (168.63.129.16)** to query **Private DNS Zone → A Record** when **Agent VNet** makes DNS queries.

### Option 1: Azure Portal (Recommended)

1. Navigate to **Private DNS zones**
2. Click on `privatelink.vaultcore.azure.net`
3. In left menu, click **Virtual network links**
4. Click **+ Add** at the top
5. Fill in the form:
   - **Link name**: `link-to-vnet-agent` (or any descriptive name)
   - **Subscription**: Select your subscription
   - **Virtual network**: Select your Agent VNet (e.g., `vnet-agent`)
   - **Enable auto registration**: ☐ **Leave unchecked** (we only need resolution, not registration)
6. Click **OK**
7. Wait for deployment to complete (~30 seconds)

**Why `registration-enabled: false`?**
- **Registration enabled = true**: VNet VMs automatically create A records in the zone
- **Registration enabled = false**: VNet can only *read* existing records (what we want)
- For Private Link zones (`privatelink.*`), registration should typically be **false** because records are managed by the Private Endpoint, not by VMs

### Option 2: Azure CLI

```bash
# Set variables
RG_NAME="rg-dnslab"
ZONE_NAME="privatelink.vaultcore.azure.net"
LINK_NAME="link-to-vnet-agent"

# Get Agent VNet ID
VNET_ID=$(az network vnet show \
  --resource-group $RG_NAME \
  --name vnet-agent \
  --query 'id' -o tsv)

# Create VNet link
az network private-dns link vnet create \
  --resource-group $RG_NAME \
  --zone-name $ZONE_NAME \
  --name $LINK_NAME \
  --virtual-network $VNET_ID \
  --registration-enabled false

# Verify link was created
az network private-dns link vnet show \
  --resource-group $RG_NAME \
  --zone-name $ZONE_NAME \
  --name $LINK_NAME \
  --output table
```

**Expected Output**:
```
Name                   ResourceGroup    ProvisioningState    RegistrationEnabled    VirtualNetworkId
---------------------  ---------------  -------------------  ---------------------  ------------------
link-to-vnet-agent     rg-dnslab        Succeeded            False                  /subscriptions/.../vnet-agent
```

### Option 3: Azure REST API (Advanced)

```bash
# Get access token
TOKEN=$(az account get-access-token --query accessToken -o tsv)

# Get subscription and VNet details
SUB_ID=$(az account show --query id -o tsv)
RG_NAME="rg-dnslab"
ZONE_NAME="privatelink.vaultcore.azure.net"
LINK_NAME="link-to-vnet-agent"

# Get VNet ID
VNET_ID=$(az network vnet show \
  --resource-group $RG_NAME \
  --name vnet-agent \
  --query 'id' -o tsv)

# Create VNet link via REST API
curl -X PUT \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "properties": {
      "virtualNetwork": {
        "id": "'$VNET_ID'"
      },
      "registrationEnabled": false
    },
    "location": "global"
  }' \
  "https://management.azure.com/subscriptions/$SUB_ID/resourceGroups/$RG_NAME/providers/Microsoft.Network/privateDnsZones/$ZONE_NAME/virtualNetworkLinks/$LINK_NAME?api-version=2020-06-01"
```

### Alternative: Use Fix Script (Quick Reset)

If you just want to restore the lab to working state quickly:

```bash
./fix-lab.sh lab2
```

⚠️ **Note**: This script uses Terraform to restore everything. In production, you'd use Portal/CLI/REST API as shown above.

---

## STEP 12: Verify the Fix

### Test 1: Verify VNet Link Exists

```bash
az network private-dns link vnet list \
  --resource-group rg-dnslab \
  --zone-name privatelink.vaultcore.azure.net \
  --output table
```

**Expected Output**:
```
Name                   ResourceGroup    ProvisioningState    VirtualNetworkId
---------------------  ---------------  -------------------  ------------------
link-to-vnet-agent     rg-dnslab        Succeeded            /subscriptions/.../vnet-agent
```

✅ **Success Criteria**: Link shows `ProvisioningState: Succeeded`

### Test 2: Re-test DNS Resolution from Agent VM

SSH back to the Agent VM and test DNS again:

```bash
nslookup keyvault-dnslab12345.vault.azure.net
```

**Expected Output (Fixed)**:
```
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
Name:   keyvault-dnslab12345.vault.azure.net
Address: 10.1.2.5  <-- PRIVATE IP (Fixed!)
```

✅ **Success Criteria**: Returns private IP (10.1.2.x) instead of public IP (52.x.x.x)

**What changed?**
- Before: **Azure Recursive Resolver** → no VNet link → falls back to public DNS → returns 52.x.x.x
- After: **Azure Recursive Resolver** → finds VNet link → queries **Private DNS Zone** → returns 10.1.2.5

### Test 3: Re-run the Pipeline

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

### Test 4: Verify Connection Uses Private IP

Optional verification - check agent's network connections:

```bash
# SSH to Agent VM
# Run during pipeline execution to see active connections
sudo netstat -tnp | grep :443 | grep keyvault
```

You should see connections to `10.1.2.5:443` (private) instead of `52.x.x.x:443` (public).

---

---

## 🧠 Key Learning Points

### 1. Split-Horizon DNS Architecture

**Concept**: The same FQDN (`keyvault-dnslab12345.vault.azure.net`) returns different IP addresses depending on the query source.

| Query Source | DNS Resolution Path | Returns |
|-------------|---------------------|---------|
| **VNet with link** | Agent VNet → VNet Link → Private DNS Zone → A Record | 10.1.2.x (private) |
| **VNet without link** | Agent VNet → Azure Resolver → Public DNS | 52.x.x.x (public) |
| **Internet** | Public DNS | 52.x.x.x (public) |

**Key Insight**: It's not that DNS "fails" - it succeeds but returns the wrong answer. Without **Agent VNet → VNet Link**, **Azure Recursive Resolver (168.63.129.16)** has no way to know it should query **Private DNS Zone → A Record**.

### 2. Virtual Network Link Purpose

**VNet Link = "Phone Book Subscription"**

```
Without Link:
Agent VM → DNS Resolver → Azure Recursive Resolver
    ↓
    Checks: "Any Private DNS Zones for this VNet?"
    ↓
    Answer: "No links found"
    ↓
    Falls back to Public DNS → Returns 52.x.x.x

With Link:
Agent VM → DNS Resolver → Azure Recursive Resolver
    ↓
    Checks: "Any Private DNS Zones for this VNet?"
    ↓
    Answer: "Yes, linked to privatelink.vaultcore.azure.net"
    ↓
    Queries Private DNS Zone → Returns 10.1.2.x
```

### 3. Registration Enabled vs Disabled

| Setting | Behavior | Use Case |
|---------|----------|----------|
| `registration-enabled: false` | VNet can **read** records from zone | ✅ Private Link zones (`privatelink.*`) |
| `registration-enabled: true` | VNet can **read** AND **write** (auto-register VM hostnames) | ✅ Internal VM name resolution |

**For Private Endpoints**: Always use `false` because **Private Endpoint → A Record** is automatically managed by Azure, not by VMs.

### 4. Common Symptom Recognition

**"Public network access is disabled" + Private Endpoint = 90% VNet Link Missing**

When you see this error pattern:
1. ✅ **First check**: VNet link exists? (STEP 7)
2. ✅ **Second check**: DNS returns private IP? (STEP 8)
3. ✅ **Third check**: Private Endpoint IP matches A record? (STEP 9)

The remaining 10% is usually **custom DNS server misconfiguration** (covered in Lab 3).

### 5. Hierarchical Troubleshooting Thinking

Using component hierarchy helps you diagnose systematically:

```
Pipeline → AzureKeyVault@2 Task (fails with "public network" error)
    ↓ runs on
Agent VM → DNS Resolver (what IP did it get?)
    ↓ queries
Azure Recursive Resolver (168.63.129.16) (did it check Private DNS Zone?)
    ↓ checks for
Agent VNet → VNet Link (does this exist?)
    ↓ should query
Private DNS Zone → A Record (what IP is configured?)
    ↓ should return
Private Endpoint → Network Interface → Private IP (what's the actual IP?)
```

Walk down this chain during diagnosis to find where the break occurs.

### 6. Reusable Troubleshooting Process

**Next time you see private resources resolving to public IPs:**

| Step | Question | Tool |
|------|----------|------|
| 1 | Does Private DNS Zone exist? | Portal → Private DNS zones |
| 2 | Does A record point to correct IP? | `az network private-dns record-set a show` |
| 3 | Is VNet linked to zone? | `az network private-dns link vnet list` |
| 4 | What IP does VNet DNS return? | `nslookup` from inside VNet |
| 5 | VNet DNS settings correct? | Portal → VNet → DNS servers (should be "Default Azure") |
| 6 | After fixing, DNS cache cleared? | Restart VM or wait ~5 minutes |

> **Critical**: During troubleshooting, **never rely on Terraform output or state**. Use Azure Portal, Azure CLI, and REST API to discover current configuration. Terraform is a provisioning tool, not a diagnostic tool.

---

### 📺 Recommended Watching

**Official Documentation:**
- [Azure Private Endpoint DNS configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Private Link DNS integration scenarios](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns-integration)
- [Review pipeline logs and diagnostics (Azure DevOps)](https://learn.microsoft.com/en-us/azure/devops/pipelines/troubleshooting/review-logs?view=azure-devops&tabs=windows-agent)
 - [Troubleshoot Azure Private Endpoint connectivity](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-troubleshoot)

**Video Resources:**
- [Azure Private Link and DNS Integration Scenarios](https://www.youtube.com/watch?v=vJXMF_jHb2Y) by John Savill
- [Azure Private Endpoint DNS Configuration](https://www.youtube.com/watch?v=j9QmMEWmcfo) by John Savill

---

## 🎓 Next Steps

- **Lab 3:** Custom DNS Misconfiguration (DNS server can't resolve private zones)

Good luck! 🚀
