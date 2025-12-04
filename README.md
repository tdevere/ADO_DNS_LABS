# Azure DNS Troubleshooting Labs

## 🎯 Overview

Hands-on Azure DNS and private endpoint troubleshooting. After this single README you can start any lab module directly—no separate guide needed.

**What You'll Do:**
- Deploy baseline infra with Terraform (VNet, VM, Key Vault + private endpoint, Private DNS zone)
- Register a self‑hosted Azure DevOps agent
- Configure and run a pipeline that validates DNS + secret access
- Introduce and diagnose DNS failures (A record drift, missing VNet link, custom DNS forwarding)

**Estimated Time:** 3–4 hours for full series (current enabled: Lab 1; others optional / commented).

---

## 📋 Prerequisites

| Requirement | Notes |
|-------------|-------|
| Azure Subscription | Contributor rights |
| Azure DevOps Org + PAT | Create at https://dev.azure.com (PAT needs: Service Connections + Agent Pools) |
| Codespaces (recommended) | Repo already dev‑container enabled |
| CLI Tools | Azure CLI, Terraform (preinstalled here) |

---

## 🚀 Quick Start

1. **Configure `.ado.env`**
   ```bash
   cp .ado.env.example .ado.env
   code .ado.env  # Add your ADO org URL and PAT
   ```
   
   Required variables:
   - `ADO_ORG_URL` - Your Azure DevOps organization URL
   - `ADO_PAT` - Personal Access Token (Agent Pools + Service Connections permissions)
   - `ADO_PROJECT` - Project name (default: DNSLAB)
   - `ADO_POOL` - Agent pool name (default: DNS-Lab-Pool)

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
Lab 3 deploys a custom DNS server from a pre-configured managed image. The image ID is already set in `terraform.tfvars`. See `labs/lab3/README.md` for details on the custom DNS setup.

---

## ❓ Common Issues

**Pipeline fails with "Service connection not found"**
- Wait 1-2 minutes after setup completes for Azure to propagate permissions
- The service connection is auto-created with all required Azure permissions

**Agent not connecting**
- Check VM is running: `az vm list --resource-group rg-dnslab-* --output table`
- SSH to VM and check agent status: `sudo systemctl status azure-devops-agent`

**DNS resolution not working**
- Verify you're testing from the DNS client VM
- Use `nslookup` or `dig` to test DNS queries
- Check Private DNS zone VNet links in Azure Portal

---

## 🧹 Cleanup
Destroy lab resources when finished:
```bash
terraform destroy -auto-approve
```
