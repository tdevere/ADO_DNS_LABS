# Standalone DNS Lab Series

## 🎯 Overview

This is a **standalone version** of the Azure DNS troubleshooting lab series designed to be run independently.

**What You'll Learn:**
- Troubleshoot DNS A record misconfigurations
- Diagnose missing Private DNS zone VNet links
- Configure custom DNS servers with conditional forwarding
- Understand Azure Private Endpoint DNS architecture

**Time Estimate:** 3-4 hours for all three labs

---

## 📋 Prerequisites

### Required

1. **Azure Subscription**
   - Active Azure subscription with Contributor role
   - Recommended: Use a dedicated subscription or resource group for lab isolation
   - Estimated cost: $5-10 per day (remember to clean up resources when done)

2. **Tools** (Auto-installed in GitHub Codespaces/devcontainer)
   - Terraform >= 1.4.0
   - Azure CLI
   - SSH client
   - DNS utilities (nslookup, dig)

3. **Knowledge Prerequisites**
   - Basic understanding of Azure networking concepts
   - Familiarity with VNets, subnets, and private endpoints
   - Basic DNS concepts
   - Terraform basics (or willingness to learn)

4. **Azure DevOps Organization**
   - Free organization at https://dev.azure.com
   - Required for running the testing pipelines
   - Run `./scripts/setup-ado-org.sh` then `./scripts/setup-pipeline.sh`
   - A service connection named **LabConnection** is required (script will create it)
   - Do NOT commit `.ado.env` (contains your PAT). It is now ignored by `.gitignore`.

### Security Note
If you accidentally committed a PAT in history, rotate it in Azure DevOps (User Settings > Personal Access Tokens) immediately.

---

## 🚀 Getting Started

### Option 1: GitHub Codespaces (Recommended - No Local Setup)

1. **Open in Codespaces:**
   - Click the "Code" button on GitHub
   - Select "Codespaces" tab
   - Click "Create codespace on main"
   - Wait for the environment to build (2-3 minutes)

2. **Authenticate to Azure:**
   ```bash
   az login --use-device-code
   ```

3. **Set your subscription:**
   ```bash
   az account list --output table
   az account set --subscription "YOUR_SUBSCRIPTION_ID"
   ```

4. **Run the setup:**
   ```bash
   # 1. Configure Azure DevOps (Required)
   ./scripts/setup-ado-org.sh

   # 2. Setup Lab Environment
   ./setup.sh
   ```

### Option 2: VS Code with DevContainer (Local)

1. **Prerequisites:**
   - Docker Desktop installed and running
   - VS Code with "Dev Containers" extension

2. **Open the repository:**
   ```bash
   git clone https://github.com/tdevere/ADOLab_Networking.git
   cd ADOLab_Networking
   code .
   ```

3. **Reopen in Container:**
   - Press `F1` or `Ctrl+Shift+P`
   - Type "Dev Containers: Reopen in Container"
   - Wait for the container to build

4. **Follow steps 2-4 from Option 1 above**

---

## 📖 Lab Guide

**Follow the comprehensive guide here:**
👉 [docs/LAB_GUIDE.md](docs/LAB_GUIDE.md)

The guide covers:
1. Infrastructure Deployment
2. Agent Registration
3. Lab Exercises (1-3)
4. Troubleshooting Steps

---

## 🗂️ Repository Structure

```
labs/dns-standalone/
├── README.md                    # This file
├── setup.sh                     # Initial setup script
├── main.tf                      # Terraform configuration
├── variables.tf                 # Terraform variables
├── outputs.tf                   # Terraform outputs
├── terraform.tfvars.example     # Example variable values
├── docs/
│   ├── LAB_GUIDE.md            # Main lab guide
│   ├── TROUBLESHOOTING.md      # Common issues and solutions
│   └── RESOURCES.md            # Manual resource creation guide
└── scripts/
    ├── generate-ssh-key.sh     # SSH key generation helper
    ├── validate-prereqs.sh     # Prerequisite checker
    └── test-dns.sh             # DNS testing helper script
```

---

## 📊 What Resources Are Created

### Automatically Created by Terraform

✅ **Infrastructure:**
- 2 Resource Groups (agent-rg, connectivity-rg)
- 2 Virtual Networks with peering
- 1 Linux VM (for testing/agent)
- 1 Azure Key Vault with private endpoint
- 1 Private DNS Zone
- Network security groups and rules

**Estimated Monthly Cost:** ~$30-50 (varies by region and runtime)

### Manually Created

⚠️ **Azure DevOps Resources:**
- Organization (one-time, free)
- Project (one-time, free)
- Agent Pool (one-time)
- Service Connections (per subscription)
- Personal Access Token (PAT)

**Cost:** Free (included in Azure DevOps free tier)

See [docs/RESOURCES.md](docs/RESOURCES.md) for detailed guidance.

---

## 🎓 Learning Modules

### Lab 1: DNS A Record Misconfiguration
**Scenario:** DNS A record points to wrong private IP  
**Symptoms:** Connection fails despite successful DNS resolution  
**Fix:** Correct the A record to point to actual private endpoint IP  
**Duration:** 60-75 minutes

### Lab 2: Missing VNet Links
**Scenario:** Private DNS zone lacks VNet links  
**Symptoms:** DNS resolution fails completely (NXDOMAIN)  
**Fix:** Create virtual network links to Private DNS zone  
**Duration:** 55-70 minutes

### Lab 3: Custom DNS Configuration
**Scenario:** Custom DNS server forwards to wrong upstream  
**Symptoms:** Queries return public IP instead of private  
**Fix:** Configure conditional forwarding to Azure DNS  
**Duration:** 75-90 minutes

---

## 📚 Additional Resources

### Documentation
- [Azure Private Link Documentation](https://learn.microsoft.com/azure/private-link/)
- [Azure Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-overview)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Troubleshooting
- See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues
- Use the `/dns-troubleshoot` prompt in Copilot Chat for AI assistance

---

## ⚠️ Important Notes

### Cost Management
- Resources incur charges while running
- Stop or deallocate VMs when not in use
- Always run `terraform destroy` when completely done
- Set up Azure cost alerts for your subscription

### Cleanup
```bash
terraform destroy -auto-approve

# Verify everything is deleted
az group list --query "[?starts_with(name, 'tf-')].name" -o table

# Manually delete any remaining resources
az group delete --name tf-agent-lab-rg --yes --no-wait
az group delete --name tf-connect-lab-rg --yes --no-wait
```

---

## 🤝 Getting Help

- **GitHub Issues:** Report bugs or request features
- **Copilot Chat:** Use `/dns-troubleshoot` for AI assistance
- **Documentation:** Check docs/ directory for detailed guides