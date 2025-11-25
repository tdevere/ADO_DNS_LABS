# Standalone DNS Lab Series

## 🎯 Overview

This lab simulates real-world Azure networking scenarios. You will play the role of a **Support Engineer** troubleshooting pipeline failures caused by infrastructure drift and DNS misconfigurations.

**What You'll Learn:**
- Troubleshoot DNS A record misconfigurations
- Diagnose missing Private DNS zone VNet links
- Understand Azure Private Endpoint DNS architecture

**Time Estimate:** 1-2 hours

---

## 📋 Prerequisites

1. **Azure Subscription** (Contributor role required)
2. **Azure DevOps Organization** (Free at https://dev.azure.com)

---

## 🚀 Getting Started (Codespaces)

This lab is designed to run in **GitHub Codespaces**. No local setup is required.

### 1. Authenticate to Azure
In the terminal below, run:
```bash
az login --use-device-code
```

### 2. Set your Subscription
Select the subscription you want to use for the lab:
```bash
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 3. Setup the Environment
Run the setup script. This will configure your Azure DevOps organization and deploy the base infrastructure.
```bash
./setup.sh
```
*Follow the prompts to enter your ADO Organization URL and PAT.*

---

## 🎓 Start the Labs

Once setup is complete, proceed to the first scenario:

| Module | Description |
| :--- | :--- |
| **[DNS LAB 1: Connectivity Failure](labs/lab1/README.md)** | Diagnose why the pipeline cannot reach Key Vault despite successful DNS resolution. |
<!-- | **[Lab 2: Missing VNet Link](labs/lab2/README.md)** | Fix "Split-Horizon" DNS issues where private zones are unreachable. | -->
<!-- | **[Lab 3: Custom DNS Misconfiguration](labs/lab3/README.md)** | Troubleshoot custom DNS forwarders and conditional forwarding. | -->

---

## 🧹 Cleanup

When you are finished with all labs, destroy the resources to avoid costs:

```bash
terraform destroy -auto-approve
```
