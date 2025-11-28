# Lab 2 Frequently Asked Questions

## Q: I see a public IP, but the pipeline still passes. Why?

**A:** Check if "public network access" is enabled on your Key Vault. In a real production scenario with proper security, the firewall would block public access, and your pipeline would fail. For this lab, we focus on DNS resolution, so some flexibility exists.

## Q: The VNet link exists, but I still get a public IP. What's wrong?

**A:** Two possibilities:
1. **DNS cache:** Flush caches on the agent VM (`sudo systemd-resolve --flush-caches`)
2. **Custom DNS servers:** Check `az network vnet show --query dhcpOptions.dnsServers` - if set, you're in Lab 3 territory

## Q: Can I just use Terraform to fix this?

**A:** Yes! `./fix-lab.sh lab2` runs `terraform apply` with `lab_scenario=base`, which recreates the VNet link. However, we teach the manual method too because:
- In production, you might not have Terraform access during an outage
- Understanding the Azure CLI helps you diagnose similar issues
- It reinforces the "what actually changed" investigation mindset

## Q: Why don't we use Terraform to break the lab?

**A:** The break scripts use Azure CLI to simulate "someone else made a manual change" (infrastructure drift). This mimics real-world scenarios where changes happen outside your IaC pipeline.

## Q: What's the difference between `registration-enabled true` and `false`?

**A:** 
- `false` (default for private zones): VNet can query records, but VMs don't auto-register
- `true`: VNet can query AND VMs automatically create A records for themselves
- For `privatelink.*` zones (used with Private Endpoints), you typically use `false` because Terraform/ARM manages the records

## Q: How do I know if I'm in a "broken" state for Lab 2?

**A:** Run the verification script:
```bash
./scripts/verify-lab.sh lab2
```

It will tell you if the VNet link is missing.

## Q: Can I break multiple labs at once?

**A:** Yes, but it's not recommended for learning. Each lab focuses on one specific issue. Breaking multiple labs creates a "too many variables" situation that makes diagnosis harder.
