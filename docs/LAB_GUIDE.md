# Azure DNS Troubleshooting Lab Guide

## 🎯 Overview

This guide covers the Azure DNS troubleshooting lab series. You'll deploy infrastructure, configure your Azure DevOps agent, and solve three distinct DNS challenges.

**What You'll Do:**
- Deploy infrastructure with Terraform
- Configure a self-hosted Azure DevOps agent
- Troubleshoot DNS A record misconfigurations
- Diagnose missing Private DNS zone VNet links
- Configure custom DNS servers with conditional forwarding

**Time Estimate:** 3-4 hours for all three labs

---

## 🤖 AI Lab Assistant

This lab is designed to work with **GitHub Copilot**. You can use the AI agent to help you configure the environment, switch lab scenarios, and troubleshoot issues.

👉 **[View AI Prompts Cheat Sheet](AI_PROMPTS.md)**

---

## 📋 Prerequisites

Before starting, ensure you have completed the setup in the [README](../README.md):

✅ Azure subscription with Contributor access  
✅ Azure DevOps Organization & PAT configured  
✅ Setup script completed (`./setup.sh`)  
✅ ADO Setup script completed (`./scripts/setup-ado-org.sh`)

---

## 🚀 Getting Started

### Step 1: Deploy Base Infrastructure

From the root directory:

```bash
# Review what will be created and save the plan
terraform plan -out=tfplan

# Deploy infrastructure (takes ~5-10 minutes)
terraform apply tfplan
```

> **Note:** The `tfplan` file contains sensitive information and is automatically ignored by `.gitignore` to prevent accidental commits.

**What Gets Deployed:**
- 2 Resource groups
- 2 Virtual networks with peering
- 1 Linux VM (agent-vm) for testing
- 1 Azure Key Vault with private endpoint
- 1 Private DNS zone with proper configuration
- Network security groups

### Step 2: Register Self-Hosted Agent

Now that the VM is running, register it as an agent in your Azure DevOps pool:

```bash
./scripts/register-agent.sh
```

This script will:
1. SSH into the VM
2. Configure the Azure DevOps agent
3. Connect it to your "DNS-Lab-Pool"

### Step 3: Configure Pipeline & Service Connection

Run the automated setup script to configure Azure DevOps:

```bash
./scripts/setup-pipeline.sh
```

This script will:
- Update `pipeline.yml` with your Key Vault name
- Create (or verify) the `LabConnection` service connection
- Push code to Azure Repos
- Create the pipeline in Azure DevOps
If you see a message about a non-standard connection (e.g. `AzureLabConnection`), rename it to `LabConnection` in Azure DevOps or let the script create the correct one.

### Step 3.1: Base Validation (Optional)
Run the validation helper:
```bash
./scripts/validate-base.sh
```
Expected:
- DNS resolves Key Vault to private IP (10.1.2.x)
- SSL handshake succeeds (403 is fine)

### Pipeline Troubleshooting Quick Reference
### Exercise 1: Pipeline Failure Investigation
After baseline success, you will simulate a production issue by introducing configuration drift yourself.

**Rules of Engagement:**
1.  **Roleplay:** You are the Incident Responder. You did not cause the issue (even though you just ran the script).
2.  **Black Box:** Do not look at the Terraform code or `tfplan` to find the answer.
3.  **Tools:** Use only standard troubleshooting tools (`nslookup`, `curl`, `az cli`) and the provided scripts.

Use the scenario guide:
`docs/EXERCISE1_SCENARIO.md`

Start collection using:
```bash
./scripts/observe-failure.sh
```
Do not fix until you have at least two hypotheses.

| Symptom | Cause | Fix |
|--------|-------|-----|
| ConnectedServiceName not found | Missing or misnamed service connection | Ensure `LabConnection` exists & is authorized for all pipelines |
| Key Vault secret task fails | Missing access policy / RBAC role | Script grants permissions; else set policy manually |
| DNS resolves to public IP | Private DNS zone not linked | Link zone to VNet, verify record, check peering |
| Git push blocked by LFS | LFS hooks without binary | Disable hooks or install `git-lfs` |

> **Note:** If the script encounters issues, follow the manual instructions it provides.

---

### Step 4: Verify Base Configuration Works

Connect to the VM and test basic functionality:

```bash
# Get VM public IP
VM_IP=$(terraform output -raw vm_public_ip)
KV_NAME=$(terraform output -raw key_vault_name)

# SSH to the VM # Once connected, test DNS resolution
ssh -i ~/.ssh/terraform_lab_key azureuser@"$VM_IP" "nslookup ${KV_NAME}.vault.azure.net"

# Expected: Should return private IP (10.1.2.x)

# Test Key Vault connectivity
ssh -i ~/.ssh/terraform_lab_key azureuser@"$VM_IP" "curl -v https://${KV_NAME}.vault.azure.net"
# Expected: SSL handshake succeeds (even if auth fails)
```

**If everything works, you're ready for the labs! 🎉**

---

## 🧪 Lab Exercises

Once your environment is set up and verified, proceed to the individual lab workbooks:

| Lab | Description | Estimated Time |
| :--- | :--- | :--- |
| **[Lab 1: Connectivity Failure](../labs/lab1/README.md)** | Diagnose why the pipeline cannot reach Key Vault. | 60 min |
| **[Lab 2: Missing VNet Link](../labs/lab2/README.md)** | Fix "Split-Horizon" DNS issues where private zones are unreachable. | 45 min |
| **[Lab 3: Custom DNS Misconfiguration](../labs/lab3/README.md)** | Troubleshoot custom DNS forwarders and conditional forwarding. | 60 min |

---

## 🧹 Cleanup

When finished with all labs:

```bash
# From labs/dns-standalone/terraform directory
cd labs/dns-standalone/terraform
terraform destroy -auto-approve
```

---

## 🎓 Summary

You've completed three DNS troubleshooting scenarios:

1. **DNS LAB 1:** Wrong DNS A record
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
