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
| [Access Reliability Scenario](labs/lab1/README.md) | Pipeline secret retrieval shows inconsistent behavior; investigate layers (agent, network, name resolution). |
| [Private Endpoint Connectivity](labs/lab2/README.md) | Network access to private resources fails intermittently; investigate connectivity patterns without assuming root cause. |

---

## 🧹 Cleanup
Destroy lab resources when finished:
```bash
terraform destroy -auto-approve
```
