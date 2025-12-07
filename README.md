# Azure DNS Troubleshooting Labs

## 🎯 Overview

Hands-on Azure DNS and private endpoint troubleshooting. After this single README you can start any lab module directly—no separate guide needed.

**What You'll Do:**
- Deploy baseline infra with Terraform (VNet, VM, Key Vault + private endpoint, Private DNS zone)
- Register a self‑hosted Azure DevOps agent
- Configure and run a pipeline that validates DNS + secret access
- Introduce and diagnose DNS failures (A record drift, missing VNet link, custom DNS forwarding)

**Estimated Time:** 3–4 hours for all three labs.

---

## 📋 Prerequisites

| Requirement | Notes |
|-------------|-------|
| Azure Subscription | Contributor rights |
| Azure DevOps Org + PAT | Create at https://dev.azure.com (PAT needs: Service Connections + Agent Pools) |
| Codespaces (recommended) | Repo already dev‑container enabled |
| CLI Tools | Azure CLI, Terraform (preinstalled here) |

---

## 💰 Cost Management

This lab deploys Azure resources that incur charges. Estimated costs:

| Resource | Approximate Cost |
|----------|------------------|
| Standard_B2s VM | ~$0.04/hour (~$30/month) |
| Key Vault | ~$0.03 per 10k operations |
| Public IP Address | ~$0.004/hour |
| Private DNS Zone | ~$0.50/month |
| **Total if left running** | **~$35-40/month** |

**To minimize costs:**
- ✅ Run `./setup.sh` to deploy infrastructure
- ✅ Complete labs (3-4 hours)
- ✅ Run `terraform destroy` **immediately after completion**
- ✅ Set up [Azure Cost Management alerts](https://portal.azure.com/#view/Microsoft_Azure_CostManagement/Menu/~/costanalysis) to monitor spending

**Estimated cost for full lab completion:** $0.50 - $2.00 (assuming 3-4 hours + cleanup)

⚠️ **Remember:** Azure charges by the hour for running VMs. Don't leave resources running overnight.

---

## 🚀 Quick Start

1. **Configure Environment Variables**
   
   Copy the example file and configure your Azure DevOps details:
   ```bash
   cp .ado.env.example .ado.env
   ```
   
   Edit `.ado.env` and provide:
   - `ADO_ORG_URL` - Your Azure DevOps organization URL (e.g., https://dev.azure.com/yourorg)
   - `ADO_PAT` - Personal Access Token (required scopes: Agent Pools, Service Connections, Build, Code, Project and Team)
   - `ADO_PROJECT` - Project name (default: ADO-DNS-Lab)
   - `ADO_POOL` - Agent pool name (default: DNS-Lab-Pool)
   - `AZURE_TENANT` - Azure tenant domain (e.g., contoso.onmicrosoft.com)

2. **Run Setup (One Command)**
   ```bash
   ./setup.sh
   ```
   
   This creates:
   - Azure DevOps project, agent pool, service connection, and pipeline
   - Azure infrastructure (VNet, VM, Key Vault, DNS zones)
   - Self-hosted agent registered and running
   
   **Takes ~5-10 minutes**. When complete, proceed to `labs/lab1/README.md`

---

## 🧹 Cleanup

Remove all resources when finished:

```bash
./destroy.sh
```

Removes Azure DevOps project, pipelines, service connections, agent pool, and all Azure infrastructure. Requires typing `destroy` to confirm

---

## 🧪 Modules

| Module | Description |
|--------|-------------|
| [Lab 1: Access Reliability Scenario](labs/lab1/README.md) | Pipeline secret retrieval shows inconsistent behavior; investigate layers (agent, network, name resolution). |
| [Lab 2: Private Endpoint Connectivity](labs/lab2/README.md) | Network access to private resources fails intermittently; investigate connectivity patterns without assuming root cause. |
| [Lab 3: Custom DNS Misconfiguration](labs/lab3/README.md) | VNet configured to use custom DNS server; pipeline fails after networking team's "DNS upgrade." Investigate DNS resolution path and forwarding behavior. |

---

## 🎓 Lab Progression

**Recommended order for learning:**
1. **Lab 1** - Introduces Private DNS zone concepts and VNet links
2. **Lab 2** - Reinforces Private DNS troubleshooting with different symptoms
3. **Lab 3** - Advanced scenario with custom DNS server (uses pre-built image)

**Lab 3 Note:**
Lab 3 deploys a custom DNS server from a pre-configured managed image. The image ID is already set in `terraform.tfvars`. See `labs/lab3/README.md` for details on the custom DNS setup.

---

## 🎯 About This Lab

This hands-on lab teaches Azure Private DNS troubleshooting through realistic DevOps pipeline failures. Each lab introduces different DNS misconfigurations that mirror real-world scenarios. Work through the exercises to build practical skills in diagnosing and resolving DNS issues in Azure.

When finished, run `./destroy.sh` to remove all resources.
