# Manual Resource Creation Guide

## Overview

This guide explains which resources need to be created manually before running the DNS labs, and provides step-by-step instructions for each.

---

## Required Resources (All Paths)

### 1. Azure Subscription

**What:** An active Azure subscription with appropriate permissions.

**Why Needed:** All Azure resources will be deployed to this subscription.

**Cost:** Varies by subscription type
- Free tier: $200 credit for 30 days (sufficient for labs)
- Pay-as-you-go: ~$5-10 per day for running lab resources

**How to Create:**
1. Visit https://azure.microsoft.com/free/
2. Sign up with Microsoft account
3. Provide payment method (won't be charged during free trial)
4. Complete verification process

**Required Permissions:**
- **Contributor** role at subscription or resource group level
- Ability to create resource groups, VNets, VMs, Key Vaults

**Verification:**
```bash
# Check your subscriptions
az login
az account list --output table

# Verify permissions
az role assignment list --assignee $(az account show --query user.name -o tsv) --output table
```

---

### 2. SSH Key Pair (for VM Access)

**What:** RSA SSH key pair for authenticating to Linux VMs.

**Why Needed:** Terraform requires public key to configure VM access; private key needed for SSH connection.

**Cost:** Free

**How to Create:**

**Option A: Using provided script (Recommended)**
```bash
cd labs/dns-standalone/scripts
./generate-ssh-key.sh
```

**Option B: Manual creation**

Linux/Mac/WSL:
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/terraform_lab_key -N ""
chmod 600 ~/.ssh/terraform_lab_key
chmod 644 ~/.ssh/terraform_lab_key.pub
```

Windows PowerShell:
```powershell
ssh-keygen -t rsa -b 4096 -f $env:USERPROFILE\.ssh\terraform_lab_key
```

**Verification:**
```bash
# Check key exists
ls -l ~/.ssh/terraform_lab_key*

# View public key (needed for terraform.tfvars)
cat ~/.ssh/terraform_lab_key.pub
```

---

## Optional Resources (Path A Only - Azure DevOps)

These resources are **only required if you choose Path A** (Full Pipeline Experience). 

### Summary Table

#### Path B (Recommended - Direct VM Testing)

| Resource | Required? | Creation Method | Estimated Time |
|----------|-----------|----------------|----------------|
| Azure Subscription | ✅ Yes | Manual (one-time) | 10-15 min |
| SSH Key Pair | ✅ Yes | Script/Manual | 1 min |
| Azure DevOps Org | ❌ No | N/A | N/A |

**Total Setup Time:** ~15-20 minutes

#### Path A (Full Pipeline Experience)

| Resource | Required? | Creation Method | Estimated Time |
|----------|-----------|----------------|----------------|
| Azure Subscription | ✅ Yes | Manual (one-time) | 10-15 min |
| SSH Key Pair | ✅ Yes | Script/Manual | 1 min |
| Azure DevOps Org | ✅ Yes | Manual (one-time) | 5 min |
| Azure DevOps Project | ✅ Yes | Portal/CLI | 2 min |
| Personal Access Token | ✅ Yes | Portal | 3 min |
| Agent Pool | ✅ Yes | Portal/CLI | 2 min |
| Service Connection | ✅ Yes | Portal (after Terraform) | 5 min |

**Total Setup Time:** ~30-40 minutes

For detailed Azure DevOps setup instructions, see the original [EXE_02_CONFIGURE_ADO](../../EXE_02_CONFIGURE_ADO/EXE_02_CONFIGURE_ADO.md) documentation.

---

## Best Approach for Students

### Recommended: Path B (Direct VM Testing)

**Why This is Better for a Standalone Lab:**

1. **Minimal External Dependencies**
   - Only requires Azure subscription (which students already need)
   - No third-party service setup (Azure DevOps)
   - Focuses on DNS troubleshooting, not CI/CD setup

2. **Faster Time to Learning**
   - 15-20 minutes setup vs 30-40 minutes
   - Start troubleshooting DNS issues immediately
   - Less context switching between Azure and Azure DevOps

3. **Lower Complexity**
   - Fewer moving parts
   - Easier troubleshooting
   - More focused learning objectives

4. **Real-World Relevance**
   - SSH to VMs is common in production troubleshooting
   - Direct DNS testing mirrors real debugging workflows
   - Skills transfer to any cloud provider

5. **Student Subscription Friendly**
   - Students can use their own Azure subscriptions
   - No need to create Azure DevOps organizations
   - Works in any Azure tenant

### When to Use Path A

Path A (with Azure DevOps) is valuable when:
- Students specifically need to learn Azure DevOps integration
- Course curriculum includes CI/CD pipelines
- Building on existing Azure DevOps knowledge
- Preparing for Azure DevOps-focused roles

---

## Cost Management

### Estimated Costs (Path B)

**Per Day (8 hours runtime):**
- 1x Standard_B1ms Linux VM: ~$1.50
- 2x Virtual Networks: ~$0.10
- 1x Key Vault: ~$0.05
- Storage & misc: ~$0.10
- **Total: ~$2/day** or **~$15/week**

**Cost Saving Tips:**
```bash
# Stop VMs when not in use (keeps infrastructure)
az vm deallocate --resource-group tf-agent-lab-rg --name agent-vm

# Start VMs when needed
az vm start --resource-group tf-agent-lab-rg --name agent-vm

# Destroy everything when done for the day (requires rebuild)
terraform destroy -auto-approve
```

---

## Next Steps

After understanding resource requirements:

**Path B (Recommended):**
1. Ensure Azure subscription is ready
2. Generate SSH keys
3. Continue to [PATH_B_DIRECT.md](PATH_B_DIRECT.md)

**Path A (Advanced):**
1. Complete Path B requirements
2. Create Azure DevOps resources
3. Continue to [PATH_A_WITH_ADO.md](PATH_A_WITH_ADO.md)

---

**Questions?** See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or open a GitHub issue.
