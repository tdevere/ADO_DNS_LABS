# Standalone DNS Lab Series

## 🎯 Overview

This is a **standalone version** of the Azure DNS troubleshooting lab series (EXE_04, EXE_05, EXE_06) designed to be run independently without requiring the full Azure DevOps setup from EXE_01 and EXE_02.

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

### Optional (for Full Pipeline Experience)

4. **Azure DevOps Organization**
   - Free organization at https://dev.azure.com
   - Only needed if you want to test with pipelines
   - **Alternative:** Use direct VM testing without pipelines (see Path B below)

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
   cd labs/dns-standalone
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

### Option 3: Local Installation (Traditional)

1. **Install required tools:**
   - [Terraform](https://www.terraform.io/downloads.html)
   - [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
   - SSH client (built-in on Linux/Mac, use Git Bash on Windows)

2. **Clone and authenticate:**
   ```bash
   git clone https://github.com/tdevere/ADOLab_Networking.git
   cd ADOLab_Networking
   az login
   az account set --subscription "YOUR_SUBSCRIPTION_ID"
   ```

3. **Run the setup:**
   ```bash
   cd labs/dns-standalone
   chmod +x setup.sh
   ./setup.sh
   ```

---

## 📖 Lab Paths

### Path A: Full Experience (with Azure DevOps)

**For students who want the complete pipeline testing experience.**

**Additional Setup Required:**
1. Create Azure DevOps organization (free)
2. Register self-hosted agents on lab VMs
3. Create service connections
4. Run pipelines for testing

**Time:** ~4-5 hours total
**Complexity:** Intermediate to Advanced

**Follow:** See [docs/PATH_A_WITH_ADO.md](docs/PATH_A_WITH_ADO.md)

### Path B: Simplified (Direct VM Testing) 🌟 Recommended

**For students who want to focus on DNS troubleshooting without Azure DevOps complexity.**

**What's Different:**
- No Azure DevOps organization needed
- No agents to register
- No pipelines to configure
- Test DNS directly from VMs using SSH
- All DNS learning objectives still met

**Time:** ~3-4 hours total
**Complexity:** Intermediate

**Follow:** See [docs/PATH_B_DIRECT.md](docs/PATH_B_DIRECT.md) (Default)

---

## 🗂️ Repository Structure

```
labs/dns-standalone/
├── README.md                    # This file
├── setup.sh                     # Initial setup script
├── terraform/                   # Simplified Terraform configs
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── docs/
│   ├── PATH_A_WITH_ADO.md      # Full ADO pipeline path
│   ├── PATH_B_DIRECT.md        # Simplified direct testing path
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

### Manually Created (Optional)

Only for Path A (Full ADO experience):

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

### Lab 1: DNS A Record Misconfiguration (EXE_04)
**Scenario:** DNS A record points to wrong private IP  
**Symptoms:** Connection fails despite successful DNS resolution  
**Fix:** Correct the A record to point to actual private endpoint IP  
**Duration:** 60-75 minutes

### Lab 2: Missing VNet Links (EXE_05)
**Scenario:** Private DNS zone lacks VNet links  
**Symptoms:** DNS resolution fails completely (NXDOMAIN)  
**Fix:** Create virtual network links to Private DNS zone  
**Duration:** 55-70 minutes

### Lab 3: Custom DNS Configuration (EXE_06)
**Scenario:** Custom DNS server forwards to wrong upstream  
**Symptoms:** Queries return public IP instead of private  
**Fix:** Configure conditional forwarding to Azure DNS  
**Duration:** 75-90 minutes

---

## 🛠️ Quick Commands Reference

### Setup & Authentication
```bash
# Azure login
az login

# Set subscription
az account set --subscription "YOUR_SUBSCRIPTION_ID"

# Run setup wizard
cd labs/dns-standalone && ./setup.sh
```

### Infrastructure Management
```bash
# Deploy infrastructure (from labs/dns-standalone/terraform/)
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Switch to DNS exercise 1
terraform apply -var="lab_scenario=dns_exercise1"

# Switch back to base
terraform apply -var="lab_scenario=base"

# Destroy everything (when done)
terraform destroy -auto-approve
```

### Testing
```bash
# SSH to test VM
ssh -i ~/.ssh/terraform_lab_key azureuser@<VM_PUBLIC_IP>

# Test DNS resolution
nslookup <keyvault-name>.vault.azure.net

# Test with specific DNS server
nslookup <keyvault-name>.vault.azure.net 168.63.129.16

# Test Key Vault connectivity
curl -v https://<keyvault-name>.vault.azure.net
```

---

## 📚 Additional Resources

### Documentation
- [Azure Private Link Documentation](https://learn.microsoft.com/azure/private-link/)
- [Azure Private DNS Zones](https://learn.microsoft.com/azure/dns/private-dns-overview)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)

### Troubleshooting
- See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues
- Use the `/dns-troubleshoot` prompt in Copilot Chat for AI assistance

### Original Full Labs
- This is a simplified standalone version
- Original full labs with all prerequisites: [labs/EXE_04_DNS_A_RECORD/](../EXE_04_DNS_A_RECORD/)
- Complete lab series overview: [labs/DNS_LABS_COMPLETE_SUMMARY.md](../DNS_LABS_COMPLETE_SUMMARY.md)

---

## ⚠️ Important Notes

### Cost Management
- Resources incur charges while running
- Stop or deallocate VMs when not in use
- Always run `terraform destroy` when completely done
- Set up Azure cost alerts for your subscription

### Security Best Practices
- This is a **learning lab** - not production-ready
- Uses password authentication (disabled for production)
- Public IPs for SSH (use Azure Bastion in production)
- Permissive NSG rules (restrict in production)

### Cleanup
```bash
# From labs/dns-standalone/terraform/
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

---

## 📝 License

This project is licensed under the MIT License. See the repository root for details.

---

**Ready to start?** Choose your path (A or B) and dive into the labs! 🚀
