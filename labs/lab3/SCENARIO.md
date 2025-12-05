# Lab 3: Custom DNS Server Misconfiguration Scenario

## Company Profile

**Contoso HealthTech Solutions**  
A healthcare SaaS provider with 850 employees, offering HIPAA-compliant patient management and telehealth platforms to medical practices across North America. After successfully resolving two DNS-related incidents over the past six weeks (Lab 1: wrong A record, Lab 2: missing VNet link), the DevOps team has become highly skilled at diagnosing Azure networking issues.

**Infrastructure:** Azure-based cloud platform with Azure DevOps for CI/CD, self-hosted build agents in Azure VNets, Private DNS zones for internal service resolution, and custom DNS infrastructure for enterprise integration.

---

## Character Profiles

| Name | Role | Tenure | Technical Level | Communication Style |
|------|------|--------|-----------------|---------------------|
| **Maya Patel** | Senior Application Developer | 3 years | 4/5 - Strong in application code, now competent in infrastructure | Methodical, proactive, teaches others |
| **Jordan Chen** | DevOps Engineer | 2 years | 5/5 - Azure expert, advanced DNS troubleshooting | Confident, systematic, recognizes patterns |
| **Sam Rodriguez** | Engineering Manager | 5 years | 4/5 - Former DevOps, strong in strategy | Strategic, aware of organizational considerations |

---

## Internal Email Thread

### Email 1: Proactive Problem Report

```
From: Maya Patel <maya.patel@contosohealthtech.com>
To: DevOps Team <devops@contosohealthtech.com>
Date: Thursday, January 16, 2025 8:30 AM
Subject: Build Agent Offline - Initial Diagnostics Complete

Hey team,

Our build agent went offline overnight and I've already run through the diagnostics 
we learned from the previous DNS incidents.

**What I've Verified:**

1. **DNS A Record (Lab 1 Check)** ✓
   - Checked Private DNS zone for Key Vault A record
   - Points to correct private IP: 10.1.2.15
   - No changes since last week

2. **VNet Link (Lab 2 Check)** ✓
   - Private DNS zone has virtual network link to agent VNet
   - Link status: "Completed"
   - No recent modifications

3. **Pipeline Status** ✗
   - Last successful run: Yesterday 11:47 PM
   - Current status: Agent shows "Offline" in Azure DevOps pool
   - Cannot queue new runs

**What's Different This Time:**

I SSH'd into the agent VM (it's still running and accessible), but when I tried to 
test connectivity to Azure services, nothing works:

```bash
# Cannot resolve Azure DevOps
nslookup dev.azure.com
# Result: Timeout or SERVFAIL

# Cannot resolve Key Vault
nslookup kv-contoso-prod-7a3f.vault.azure.net  
# Result: Timeout or SERVFAIL
```

The agent can't reach ANY Azure services. This is different from Lab 1 (wrong IP) 
and Lab 2 (VNet link issue) where DNS resolution worked but gave the wrong answer.

This looks more infrastructure-level than the previous incidents. Passing to DevOps 
for investigation.

Maya

-- 
Maya Patel | Senior Application Developer
Contoso HealthTech Solutions
```

---

### Email 2: Advanced Diagnostic Investigation

```
From: Jordan Chen <jordan.chen@contosohealthtech.com>
To: Maya Patel <maya.patel@contosohealthtech.com>
Cc: DevOps Team <devops@contosohealthtech.com>
Date: Thursday, January 16, 2025 11:05 AM
Subject: RE: Build Agent Offline - Root Cause Identified

Maya,

Excellent initial diagnostics - you saved us hours by ruling out Lab 1 and Lab 2 
scenarios first. I've found the root cause, and this one is more complex than our 
previous incidents.

**Confirmed Your Findings:**

All your checks were correct:
- DNS A record: ✓ Correct (10.1.2.15)
- VNet link: ✓ Present and valid
- Agent VM: ✓ Running and accessible via SSH

**New Discovery - Custom DNS Configuration:**

I dug deeper into why DNS resolution is completely broken on the agent:

```bash
# From agent VM - check what DNS server it's using
cat /etc/resolv.conf
nameserver 10.1.2.50

# This should normally show Azure's resolver
# Expected: nameserver 168.63.129.16 (Azure default)
# Actual: nameserver 10.1.2.50 (custom DNS server)
```

Then I checked the VNet configuration:

```bash
az network vnet show \
    --resource-group rg-contoso-prod \
    --name vnet-agent \
    --query dhcpOptions.dnsServers

Result: ["10.1.2.50"]
```

**Root Cause:**

The VNet is configured to use a custom DNS server (10.1.2.50) instead of Azure's 
default DNS resolver. This custom DNS server either:
1. Doesn't exist / isn't running
2. Isn't configured to forward Azure service queries properly

This explains why:
- The agent went offline (can't resolve dev.azure.com to check for jobs)
- ALL Azure service resolution fails (not just Key Vault)
- The symptoms are different from Lab 1 & Lab 2

**Why This Matters:**

When you use a custom DNS server in Azure VNets, that server MUST forward queries 
for Azure services (*.azure.com, *.vault.azure.net, etc.) to Azure's recursive 
resolver (168.63.129.16). If it doesn't, all Azure service connectivity breaks.

Our Private DNS zones don't help here because the VNet never asks Azure DNS - it 
only asks 10.1.2.50, which isn't responding or forwarding correctly.

**Next Steps:**

I need to determine:
1. Why is the VNet using a custom DNS server?
2. Who manages/owns 10.1.2.50?
3. Was this intentional or a misconfiguration?

This is more advanced than Lab 1 & Lab 2 - involves custom DNS infrastructure design. 
Will investigate VNet DNS settings and consult with networking team if needed.

Jordan

-- 
Jordan Chen | DevOps Engineer
Contoso HealthTech Solutions
```

---

### Email 3: Strategic Guidance

```
From: Sam Rodriguez <sam.rodriguez@contosohealthtech.com>
To: Jordan Chen <jordan.chen@contosohealthtech.com>
Cc: Maya Patel <maya.patel@contosohealthtech.com>, DevOps Team <devops@contosohealthtech.com>
Date: Thursday, January 16, 2025 2:45 PM
Subject: RE: Build Agent Offline - Excellent Diagnostic Work

Jordan,

Outstanding root cause analysis. You've become an expert at Azure DNS troubleshooting 
over these past few weeks - really impressive progression from Lab 1 to now.

Maya - great job doing the initial validation. This is exactly the process we want: 
check the known failure patterns first, then escalate with good data.

**Before We Make Changes:**

Custom DNS servers are usually configured for a reason (hybrid connectivity, on-prem 
integration, etc.). Before we modify the VNet DNS settings, I need you to:

1. **Document Current State**
   - VNet DNS configuration (you've done this ✓)
   - Any documentation on why custom DNS was configured
   - Check if other VNets use the same custom DNS server

2. **Validate the Custom DNS Server**
   - Does 10.1.2.50 actually exist as a VM/resource?
   - If yes, is it supposed to be a DNS server?
   - Check if it was part of a larger architecture design

3. **Determine Ownership**
   - Is this managed by our team or the networking team?
   - Was there a recent change/migration that affected this?

4. **Risk Assessment**
   - If we change VNet DNS back to Azure default, what breaks?
   - Are there other services/agents depending on custom DNS?

**Resolution Options:**

Based on what you find:
- **Option A:** Remove custom DNS, let VNet use Azure default (safest, fastest)
- **Option B:** Fix the custom DNS server forwarding rules (if it's supposed to exist)
- **Option C:** Escalate to networking team if custom DNS is required for business reasons

This falls under **Step 4** of the Azure Support troubleshooting workflow (Review 
Network Policies). Custom DNS configuration is a network policy decision, not just a 
DNS record fix.

Document everything you find. If custom DNS is required for legitimate reasons but 
misconfigured, we may need networking team collaboration.

Sam

-- 
Sam Rodriguez | Engineering Manager, Platform & DevOps
Contoso HealthTech Solutions
```

---

## Lab Scenario: Your Role

You are **Jordan Chen**, the DevOps Engineer who has successfully resolved two previous DNS incidents. You're now the team's DNS expert, and you've discovered that the VNet is configured to use a custom DNS server that isn't working correctly. This is the most complex DNS issue you've faced so far.

### Situation
- **Environment**: Self-hosted Azure DevOps agent running in Azure VNet with custom DNS configuration
- **What's Working**: Agent VM is running, SSH access works, DNS A record and VNet link are correct
- **What's Broken**: Agent offline in Azure DevOps, cannot resolve ANY Azure service FQDNs
- **Root Cause**: VNet configured to use custom DNS server (10.1.2.50) that doesn't properly forward queries

### Your Task
Investigate the VNet DNS configuration and understand why the custom DNS server is failing. Determine whether to remove the custom DNS configuration or fix the custom DNS server's forwarding rules. Restore agent connectivity so the pipeline can succeed.

**Available Tools:**
- SSH access to the build agent VM
- `nslookup`, `dig`, `cat /etc/resolv.conf` command-line tools
- Azure Portal access to review VNet DNS settings
- Azure CLI for querying and modifying VNet configuration
- Terraform state files showing infrastructure configuration

### Success Criteria
- Identify why the VNet is using a custom DNS server
- Determine whether custom DNS is required or a misconfiguration
- Fix VNet DNS settings to restore Azure service name resolution
- Agent comes back online in Azure DevOps
- Pipeline successfully retrieves secrets from Key Vault via private endpoint
- Document the custom DNS architecture and resolution approach

### What You'll Learn
- How VNet DNS server settings work in Azure
- The role of Azure's recursive resolver (168.63.129.16)
- Why custom DNS servers need conditional forwarding to Azure DNS
- When custom DNS is appropriate vs. problematic
- How DNS affects agent connectivity to Azure DevOps
- Advanced Azure networking troubleshooting methodology

---

**Ready to begin troubleshooting?** Continue to the hands-on exercises in [README.md](README.md).
