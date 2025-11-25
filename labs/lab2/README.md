# Lab 2: Missing VNet Link Misconfiguration

## 🎯 Overview

This exercise simulates a common but confusing DNS issue where the Private DNS Zone exists and contains the correct records, but the client Virtual Network (VNet) is not linked to the zone. This results in "Split-Horizon" DNS behavior where the client resolves the public IP address instead of the private endpoint IP.

## 🌍 Real-World Scenario

**Tuesday, 10:00 AM:** A developer reports that the deployment pipeline is behaving strangely. Sometimes it connects to Key Vault successfully, sometimes it times out. When you check the logs, you notice the agent is resolving the Key Vault to a **public IP address** instead of the private endpoint IP.

**What you know:**
- The Private DNS Zone exists and has the correct A record
- The Private Endpoint is deployed and healthy
- DNS resolution "works" (returns an IP, no errors)
- The pipeline worked yesterday

**What you don't know:**
- Last night, the infrastructure team deployed a new VNet for another project
- They used a script that accidentally deleted and recreated the Private DNS Zone
- The zone was recreated but the VNet links were not restored
- No one documented the change

**Your mission:** Figure out why DNS is returning the public IP and restore private connectivity.

> **Real-World Context**
> This happens when a new application team spins up a VNet and assumes they can use the "centrally managed" Private DNS Zone, but forgets to link it. Or when an IaC pipeline runs in a different order than expected, creating the zone before the link. The confusing part? DNS "works" – it just returns the wrong answer (public IP). Traffic might succeed if public access is enabled, masking the misconfiguration.

## 🏗️ Lab Architecture

```
Agent VNet (10.0.0.0/16)
  └─ Agent VM (10.0.1.x)
       │
       │ ❌ MISSING LINK
       ▼
Private DNS Zone: privatelink.vaultcore.azure.net
  └─ A Record: <keyvault-name> -> 10.1.2.x (Correct Private IP)

Result:
Agent VM -> DNS Query -> Azure Recursive Resolver (168.63.129.16)
  -> Checks linked zones -> None found
  -> Falls back to Public DNS
  -> Resolves to Public IP (e.g., 52.x.x.x)
```

---

## 💥 Start the Scenario

To start this exercise, you will self-inject a fault into the environment to simulate a real-world outage.

1. **Run the scenario script:**
   ```bash
   ./break-lab.sh lab2
   ```
   *This removes the Virtual Network Link between the Agent VNet and the Private DNS Zone.*

   > **Note:** Once this script finishes, switch your mindset. You are the on-call responder. The application team reports that they are suddenly connecting to the public endpoint instead of the private one.

2. **Verify the failure:**

Connect to your Agent VM and check how the Key Vault name resolves.

```bash
# 1. Get Key Vault Name
KV_NAME=$(terraform output -raw key_vault_name)

# 2. Test DNS Resolution
nslookup ${KV_NAME}.vault.azure.net
```

**Expected Output (Broken State):**
```text
Non-authoritative answer:
Name:   kv-dns-lab-xxxx.vault.azure.net
Address: 52.154.x.x  <-- PUBLIC IP (Wrong for Private Link)
```

---

## 🔍 Investigation: Systematic Troubleshooting

### STEP 1: Scope the Problem (What Do We Know?)

Before jumping into Azure CLI commands, answer these questions:

1. **What symptom are we seeing?**
   - Pipeline: `___________________`
   - DNS resolution: `___________________`
   - IP type (public/private): `___________________`

2. **What's different from Lab 1?**
   - Lab 1: DNS returned wrong private IP (10.1.2.50 instead of 10.1.2.4)
   - Lab 2: DNS returns `___________________`

3. **What does the pipeline DNS check show?**
   - Go to your failed pipeline run
   - Check the "DNS Resolution Validation" stage
   - What IP did it resolve? `___________________`

**For this lab scenario:**
- DNS is "working" (no NXDOMAIN errors)
- But it's returning the public IP (52.x, 13.x, or 20.x range)
- This means the Private DNS Zone isn't being consulted
- **Why?** Let's find out...

---

### STEP 2: Analyze the Symptoms

| Observation | Conclusion |
|-------------|------------|
| `nslookup` returns an IP | DNS is working generally. |
| IP is Public (not 10.x.x.x) | We are hitting the public endpoint, not the private one. |
| Private Endpoint exists | Confirmed via Terraform/Portal. |

### STEP 3: Check Private DNS Zone Links

The most common cause for resolving a Public IP when a Private Endpoint exists is a missing **Virtual Network Link**.

**Check via Azure CLI:**

```bash
# Get Resource Group Name
RG_NAME=$(terraform output -raw resource_group_name)

# List all VNet links for the zone
az network private-dns link vnet list \
  --resource-group $RG_NAME \
  --zone-name privatelink.vaultcore.azure.net \
  --output table
```

**Expected output (when broken):**
```
(No output - empty list)
```

**Result:**
- If the list is empty or your VNet is missing, the link does not exist.
- The Private DNS Zone cannot answer queries for VNets that are not linked to it.

---

### STEP 4: Verify the DNS Zone Has the Correct Record

Even though the link is missing, let's confirm the zone itself is configured correctly:

```bash
KV_NAME=$(terraform output -raw key_vault_name)

az network private-dns record-set a show \
  --resource-group $RG_NAME \
  --zone-name privatelink.vaultcore.azure.net \
  --name $KV_NAME \
  --query "aRecords[0].ipv4Address" -o tsv
```

**Expected output:**
```
10.1.2.5
```

This confirms the zone has the correct private IP. The problem is that our VNet can't see this zone.

---

### STEP 5: Root Cause Identification

| Resource | Status | Result |
|----------|--------|--------|
| Private DNS Zone | ✅ Exists | Contains correct A record |
| A Record in Zone | ✅ Correct | Points to 10.1.2.5 |
| VNet Link | ❌ **Missing** | Zone can't answer queries from VNet |
| Client DNS Query | ⚠️ Falls back | Queries public DNS, gets public IP |

**Root Cause:** Without the VNet link, Azure's recursive resolver (168.63.129.16) doesn't know to check the Private DNS Zone for this VNet's queries. It falls back to public DNS.

**How DNS resolution works:**
1. Agent VM sends DNS query to Azure DNS (168.63.129.16)
2. Azure DNS checks: "Is this VNet linked to any Private DNS Zones?"
3. No links found → Azure DNS forwards query to public internet DNS
4. Public DNS returns the public IP for `*.vault.azure.net`
5. Agent connects to public endpoint (fails if firewall blocks, or succeeds but bypasses Private Link)

---

## 🛠️ Fix the Issue

You have two choices. As a Support Engineer, you often have to decide between a quick "Hotfix" to get production running and a "Proper" fix to ensure consistency.

### Option 1: The "Hotfix" (Manual Azure CLI)
*Use this when production is down and you need immediate recovery.*
```bash
# 1. Get Variables
RG_NAME=$(terraform output -raw resource_group_name)
VNET_ID=$(az network vnet show --resource-group $RG_NAME --name vnet-dns-lab --query id -o tsv)

# 2. Create the Link
az network private-dns link vnet create \
  --resource-group $RG_NAME \
  --zone-name privatelink.vaultcore.azure.net \
  --name link-vnet-dns-lab \
  --virtual-network $VNET_ID \
  --registration-enabled false
```

### Option 2: The "Proper" Fix (Infrastructure as Code)
*Use this to ensure your Terraform state matches reality.*

```bash
./fix-lab.sh lab2
```
*Note: In this lab, `fix-lab.sh` just runs `terraform apply` to enforce the configuration defined in `main.tf`.*

---

## ✅ Verify the Fix

### 1. Check DNS Resolution (from the VM)

SSH back into the agent VM (if you aren't there already) and test again:

```bash
# Clear DNS cache first (important!)
sudo systemd-resolve --flush-caches

# Test resolution
KV_NAME=$(terraform output -raw key_vault_name)
nslookup ${KV_NAME}.vault.azure.net
```

**Expected Output (Fixed State):**
```text
Name:   kv-dns-lab-xxxx.privatelink.vaultcore.azure.net
Address: 10.1.2.5  <-- PRIVATE IP (Correct)
```
✅ **Success!** The DNS now resolves to the correct Private Endpoint IP.

### 2. Automated Verification (Optional)

Run the lab-specific verification script:
```bash
./scripts/verify-lab.sh lab2
```

This will check VNet link status and DNS resolution automatically.

### 3. Re-run the Pipeline
1. Go back to Azure DevOps.
2. Find your failed pipeline run.
3. Click **"Rerun failed jobs"**.

It should now succeed (green checkmarks everywhere)! 🎉

---

## 🧠 Key Learning Points

1. **Split-Horizon DNS**
   - Azure uses the *same* DNS name (e.g., `vault.azure.net`) for both public and private access.
   - The "view" you get depends on where you are coming from.
   - Without a VNet Link, you get the "Public View".
   - With a VNet Link, you get the "Private View".

2. **The "Public IP" Symptom**
   - If you are troubleshooting Private Link and see a Public IP, **90% of the time it is a missing VNet Link**.
   - The other 10% is usually a custom DNS server misconfiguration (Lab 3).

3. **Registration Enabled vs Disabled**
   - `registration-enabled false`: The VNet can *read* records from the zone (Resolution).
   - `registration-enabled true`: The VNet can *read* AND auto-register its own VM hostnames into the zone.
   - For Private Link zones (`privatelink.*`), we usually keep registration **disabled**.

4. **Systematic Investigation**  
   Follow the path: Observe (what's happening) → Locate (what should happen) → Compare (find the gap) → Understand (why) → Fix.

### Reusable Troubleshooting Process

Next time you see private resources resolving to public IPs:

1. Verify the Private DNS Zone exists and has correct records
2. Check if the client's VNet is linked to the zone
3. Check VNet DNS settings (Azure DNS vs custom)
4. Test DNS from within the VNet (not from your laptop)
5. Clear DNS caches after fixing
6. Verify with both `nslookup` and actual connection test

---

### 📺 Recommended Watching

If you want to truly master this topic, these videos are the gold standard:
- [Azure Private Link and DNS - The Missing Manual](https://www.youtube.com/watch?v=UVR9lhUGAyU) by John Savill
- [Azure Private Endpoint DNS Configuration](https://www.youtube.com/watch?v=j9QmMEWmcfo) by John Savill

---

## 🎓 Next Steps

- **Lab 3:** Custom DNS Misconfiguration (DNS server can't resolve private zones)

Good luck! 🚀
