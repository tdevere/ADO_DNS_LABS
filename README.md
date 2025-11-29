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

## 🚀 Setup (Single Pass)

1. Azure login:
```bash
az login --use-device-code
```
2. Select subscription:
```bash
az account set --subscription "<SUBSCRIPTION_ID>"
```
3. Deploy infrastructure & prepare ADO (prompts for Org URL + PAT):
```bash
./setup.sh
```
4. Register self-hosted agent in pool `DNS-Lab-Pool`:
```bash
./scripts/register-agent.sh
```
5. Create / update pipeline & service connection (injects Key Vault name):
```bash
./scripts/setup-pipeline.sh
```
	Expected results:
	- `pipeline.yml` KeyVaultName replaced with dynamic value
	- Service connection `LabConnection` authorized for all pipelines
	- Key Vault access policy (or RBAC role) granted for secrets get/list

---

## ✅ Optional Base Validation
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
