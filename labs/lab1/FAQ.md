# Lab 1 Frequently Asked Questions

## Q: The pipeline shows a red X, but I can SSH to the VM. Isn't that proof of connectivity?

**A:** No. SSH runs on port 22 and uses the VM's public IP. The Key Vault connection uses HTTPS (port 443) to the Key Vault's *private endpoint* (10.1.2.x). Different protocols, different endpoints, different network paths.

## Q: I checked the DNS record and it looks correct. Why does the pipeline still fail?

**A:** "Looks correct" in the Azure Portal only shows what the DNS *zone* says. You need to verify what the *agent VM* actually resolves. Run `nslookup` from the agent itself:
```bash
az vm run-command invoke \
  --resource-group <rg-name> \
  --name <vm-name> \
  --command-id RunShellScript \
  --scripts "nslookup <keyvault-name>.vault.azure.net"
```

## Q: The A record points to the Private Endpoint IP. The pipeline still fails. What now?

**A:** DNS resolution is only step one. After confirming the agent resolves the correct private IP, check:
1. **Network path:** Is there a route from the VM's subnet to the Private Endpoint's subnet?
2. **NSG rules:** Are ports 443/HTTPS blocked?
3. **Key Vault access policy:** Does the service principal have `Get` and `List` secret permissions?
4. **Key Vault firewall:** Is "Allow trusted Microsoft services" enabled or is the VM's subnet whitelisted?

## Q: Why can't I just use `./fix-lab.sh lab1` immediately?

**A:** You *can*, but you won't learn the diagnostic process. In a real production outage:
- You might not have Terraform access (different team owns it)
- The Terraform state might be out of sync with Azure
- Management wants a root cause analysis, not just "I ran a script"

The lab teaches you to diagnose the issue manually so you can handle situations where automation isn't available.

## Q: What's the difference between the Private DNS Zone and the A record?

**A:** Think of it like this:
- **Private DNS Zone** (`privatelink.vaultcore.azure.net`): A namespace linked to your VNet that overrides public DNS
- **A Record** (inside the zone): The actual mapping from `<keyvault>.vault.azure.net` to the private IP (10.1.2.x)
- **VNet Link**: The "glue" that tells the VNet to use this Private DNS Zone

If the zone or VNet link is missing → VM uses public DNS → resolves to public IP.
If the A record is wrong → VM uses private DNS but gets the wrong IP.

## Q: How do I know if I'm in a "broken" state for Lab 1?

**A:** Run the verification script:
```bash
./scripts/verify-lab.sh lab1
```

It checks:
- DNS resolution from the agent VM
- A record value vs. Private Endpoint IP
- VNet link existence

## Q: The Private Endpoint IP is 10.1.2.4, but I see 10.1.2.5 in the A record. Is that the issue?

**A:** Yes! That's **the exact misconfiguration** in Lab 1. The A record points to a non-existent IP (10.1.2.5), so connections fail. To fix:
```bash
# Check current A record
az network private-dns record-set a show \
  --zone-name privatelink.vaultcore.azure.net \
  --resource-group <rg> \
  --name <keyvault-name>

# Get the correct Private Endpoint IP
az network private-endpoint show \
  --resource-group <rg> \
  --name <pe-name> \
  --query 'customDnsConfigs[0].ipAddresses[0]' -o tsv

# Update the A record
az network private-dns record-set a remove-record \
  --zone-name privatelink.vaultcore.azure.net \
  --resource-group <rg> \
  --record-set-name <keyvault-name> \
  --ipv4-address <wrong-ip>

az network private-dns record-set a add-record \
  --zone-name privatelink.vaultcore.azure.net \
  --resource-group <rg> \
  --record-set-name <keyvault-name> \
  --ipv4-address <correct-ip>
```

## Q: Can I delete and recreate the Private Endpoint instead of fixing the DNS record?

**A:** Yes, but it's overkill. Deleting the Private Endpoint disrupts **all** services using it (not just your pipeline). In production, you'd get escalated to a change advisory board. The DNS fix is surgical—it only touches the A record, minimizing blast radius.

## Q: Why does Azure DNS sometimes return cached results?

**A:** DNS uses TTL (Time To Live) to cache records. Even after you fix the A record in Azure, the agent VM might cache the old value for 60-300 seconds. Flush the cache:
```bash
# On Linux agent
sudo systemd-resolve --flush-caches

# Verify cache is cleared
sudo systemd-resolve --statistics
```

## Q: What does "split-horizon DNS" mean?

**A:** It means the same hostname resolves to different IPs depending on where you query from:
- **Inside the VNet** (agent VM): `<keyvault>.vault.azure.net` → private IP (10.1.2.x)
- **Outside the VNet** (your laptop): `<keyvault>.vault.azure.net` → public IP (e.g., 20.x.x.x)

Azure uses Private DNS Zones to create this split-horizon behavior. When you link a Private DNS Zone to a VNet, resources in that VNet see the private records. Everyone else sees public DNS.

## Q: Can I break multiple labs at once?

**A:** Technically yes, but it defeats the learning objective. Each lab isolates one specific failure mode. Breaking multiple labs creates a "too many variables" situation that makes diagnosis harder. Stick to one lab at a time.

## Q: After fixing Lab 1, how do I reset to try again?

**A:** Run:
```bash
./fix-lab.sh lab1
```

This resets to the "base" working state. Then you can `./break-lab.sh lab1` to re-introduce the fault and practice the diagnostic process again.
