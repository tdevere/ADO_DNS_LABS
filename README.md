# Azure DNS Troubleshooting Labs

## 🎯 Overview

Hands-on Azure DNS and private endpoint troubleshooting. After this single README you can start any lab module directly—no separate guide needed.

**What You'll Do:**
- Deploy baseline infra with Terraform (VNet, VM, Key Vault + private endpoint, Private DNS zone)
- Register a self‑hosted Azure DevOps agent
- Configure and run a pipeline that validates DNS + secret access
- Introduce and diagnose DNS failures (A record drift, missing VNet link, custom DNS forwarding)

**Estimated Time:** 3–4 hours for full series (current enabled: Lab 1; others optional / commented).

👉 AI helper prompts: `docs/AI_PROMPTS.md`

---

## 📋 Prerequisites

| Requirement | Notes |
|-------------|-------|
| Azure Subscription | Contributor rights |
| Azure DevOps Org + PAT | Create at https://dev.azure.com (PAT needs: Service Connections + Agent Pools) |
| Codespaces (recommended) | Repo already dev‑container enabled |
| CLI Tools | Azure CLI, Terraform (preinstalled here) |

---

## 🚀 Setup

1. **Configure Environment Variables**
   Create a file named `.ado.env` in the root of the repository and add your Azure DevOps details.
   
   ```bash
   cp .ado.env.example .ado.env
   code .ado.env
   ```
   
   **Required Variables:**
   ```bash
   export ADO_ORG_URL="https://dev.azure.com/your-org"
   export ADO_PAT="your-personal-access-token"
   export ADO_PROJECT="NetworkingLab"
   export ADO_POOL="DNS-Lab-Pool"
   ```
   > **PAT Requirements:** Scopes must include **Agent Pools (Read & Manage)** and **Service Connections (Read, Query & Manage)**.

2. **Run the Setup Wizard**
   This script orchestrates the entire setup process (Azure Login, Terraform, Agent Registration, Pipeline Setup).

   ```bash
   ./setup.sh
   ```

---

## 🧹 Cleanup (Destroy)

To remove all lab resources and start fresh:

```bash
./destroy.sh
```

This script:
- Removes ADO resources (Project, Pipeline, Service Connections, Agent Pool)
- Destroys Azure infrastructure (VMs, Networks, Key Vaults, etc.)
- Optionally cleans up local Terraform files
- **Requires confirmation** - you must type `destroy` to proceed

**Use cases:**
- End of training session to avoid ongoing costs
- Reset lab to clean state for new student
- Remove resources from shared subscription

---

## ✅ Validation (Automated)
The setup script runs validation automatically. To re-run validation at any time:
```bash
./scripts/validate-base.sh
```
Confirms:
- Private DNS resolves `<kv>.vault.azure.net` to `10.1.2.x`
- TLS handshake to Key Vault (403 is fine—auth not required for DNS test)

Manual spot checks:
```bash
KV_NAME=$(terraform output -raw key_vault_name)
VM_IP=$(terraform output -raw vm_public_ip)
ssh -i ~/.ssh/terraform_lab_key azureuser@"$VM_IP" "nslookup ${KV_NAME}.vault.azure.net"
ssh -i ~/.ssh/terraform_lab_key azureuser@"$VM_IP" "curl -sv https://${KV_NAME}.vault.azure.net" | true
```

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
Lab 3 deploys a custom DNS server from a pre-configured managed image. The image ID is already set in `terraform.tfvars`. If you need to rebuild the image, see [Lab 3 Image Build Guide](docs/LAB3_IMAGE_BUILD.md).

If students are working from their own subscriptions, instructors can publish the image to an Azure Compute Gallery and share access. See "Publish to Azure Compute Gallery" in [Lab 3 Image Build Guide](docs/LAB3_IMAGE_BUILD.md).

---

## 🧹 Cleanup
Destroy lab resources when finished:
```bash
terraform destroy -auto-approve
```
