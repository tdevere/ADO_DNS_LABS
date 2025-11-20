# DNS LAB 1: Connectivity Failure

## 🎯 Overview

This exercise simulates a common connectivity issue in Azure environments. Your application (running on the agent VM) cannot reach the Key Vault, and you need to determine why.

**Scenario:**
- You have a Key Vault with a Private Endpoint.
- The application is configured to use the Key Vault's FQDN.
- Connections are timing out.

> **Why troubleshoot outside Terraform?**
> In a real production outage, you often cannot simply "re-apply Terraform" to fix the issue. The drift might have been caused by a manual change, or the state file might be locked. You need to be able to diagnose the *actual state* of the cloud resources using CLI tools to understand what is broken before you can fix it in code.

---

## 💥 Start the Scenario

To start this exercise, you will self-inject a fault into the environment to simulate a real-world outage.

1. **Run the scenario script:**
   ```bash
   ./break-lab.sh lab1
   ```
   *This applies a change to the infrastructure to simulate the failure.*

   > **Note:** Once this script finishes, switch your mindset. You are no longer the engineer who deployed the code. You are the on-call responder who just got paged.

2. **Verify the failure:**
   ```bash
   # Try to connect to the Key Vault
   KV_NAME=$(terraform output -raw key_vault_name)
   curl -v https://${KV_NAME}.vault.azure.net
   ```
   *You should see a connection timeout or failure.*

---

## 🕵️ Troubleshooting Steps

### 1. Identify the Symptoms
- **Symptom:** "Connection refused" or "Timeout" when connecting to Key Vault.
- **Observation:** Does `nslookup` return an IP address? If so, is it the *correct* one?

### 2. Find the Truth (Correct IP)
You need to find what the IP address *should* be.

**Option A: Terraform Output**
```bash
terraform output key_vault_private_ip
```

**Option B: Azure CLI**
```bash
KV_NAME=$(terraform output -raw key_vault_name)
az network private-endpoint show \
  --name pe-kv-dns-lab \
  --resource-group $(terraform output -raw resource_group_name) \
  --query "customDnsConfigs[0].ipAddresses[0]" -o tsv
```

### 3. Compare
| Source | IP Address | Status |
|--------|------------|--------|
| DNS Resolution (`nslookup`) | ??? | ? |
| Actual Private Endpoint | ??? | ? |

<details>
<summary>🆘 Need a Hint?</summary>

1.  **Check the IP:** Does the IP returned by `nslookup` match the IP of the Private Endpoint?
2.  **Check the Record:** Use `az network private-dns record-set a list` to see what is actually in the DNS zone.
3.  **The "Split Brain":** It is possible for DNS to resolve to an IP that *does not exist* or is not the one you expect.
</details>

### 🧭 Investigation Flow (Cheat Sheet)
1. Confirm pipeline failure stage (is infra vs auth?).
2. Compare resolved IP vs private endpoint NIC IP.
3. If mismatch: inspect Private DNS A record.
4. If match but failure persists: inspect Key Vault policy / service connection.
5. If DNS shows public path: check zone link & VNet.

### 🧰 Tools Summary
| Task | Command |
|------|---------|
| Pipeline latest build | `az pipelines build list --definition-name DNS-Lab-Pipeline --top 1` |
| Resolve vault FQDN | `nslookup <kv>.vault.azure.net` |
| Direct privatelink record | `nslookup <kv>.privatelink.vaultcore.azure.net` |
| Show DNS record | `az network private-dns record-set a show --name <kv>` |
| Show private endpoint IP | `az network private-endpoint show --name pe-kv-dns-lab` |

---

## 🛠️ Fix the Issue

You need to update the DNS A record to match the actual Private Endpoint IP.

### Option 1: The "Easy" Fix (Script)
```bash
./fix-lab.sh lab1
```

### Option 2: The "Real World" Fix (Manual)
Use the Azure CLI to update the record manually:

```bash
# 1. Get variables
RG_NAME=$(terraform output -raw resource_group_name)
KV_NAME=$(terraform output -raw key_vault_name)
REAL_IP=$(terraform output -raw key_vault_private_ip)

# 2. Update the A record
az network private-dns record-set a update \
  --resource-group $RG_NAME \
  --zone-name privatelink.vaultcore.azure.net \
  --name $KV_NAME \
  --set aRecords[0].ipv4Address=$REAL_IP
```

---

## ✅ Verification

1. **Clear DNS Cache:**
   ```bash
   sudo systemd-resolve --flush-caches
   ```

2. **Test Resolution:**
   ```bash
   nslookup $KV_NAME.vault.azure.net
   # Should now match the Real IP
   ```

3. **Test Connectivity:**
   ```bash
   ./scripts/test-dns.sh $KV_NAME
   ```

---

## 🧠 Key Takeaways
- **DNS Resolution ≠ Connectivity:** Just because a name resolves doesn't mean it resolves to the *right* place.
- **Stale Records:** This often happens when a Private Endpoint is deleted and recreated, but the static DNS record isn't updated.
- **Precision Matters:** A single digit difference in an IP address breaks the entire connection.
