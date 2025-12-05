# Lab 2: Private Endpoint Connectivity Scenario

## Company Profile

**Contoso HealthTech Solutions**  
A healthcare SaaS provider with 850 employees, offering HIPAA-compliant patient management and telehealth platforms to medical practices across North America. After successfully resolving a DNS A record issue three weeks ago (Lab 1), the team has implemented better monitoring and documentation practices for their Azure DevOps pipelines.

**Infrastructure:** Azure-based cloud platform with Azure DevOps for CI/CD, self-hosted build agents in Azure VNets, and Private DNS zones for internal service resolution.

---

## Character Profiles

| Name | Role | Tenure | Technical Level | Communication Style |
|------|------|--------|-----------------|---------------------|
| **Maya Patel** | Senior Application Developer | 3 years | 3/5 - Strong in application code, limited infrastructure knowledge | Direct, solution-focused, more organized after Lab 1 |
| **Jordan Chen** | DevOps Engineer | 2 years | 4/5 - Azure expert, growing DNS troubleshooting skills | Analytical, methodical, applies past learnings |
| **Sam Rodriguez** | Engineering Manager | 5 years | 4/5 - Former DevOps, now in leadership | Supportive, process-oriented |

---

## Internal Email Thread

### Email 1: Pipeline Failure Report

```
From: Maya Patel <maya.patel@contosohealthtech.com>
To: DevOps Team <devops@contosohealthtech.com>
Date: Tuesday, December 23, 2024 10:15 AM
Subject: Patient Portal Pipeline Failing - Key Vault Access Issue

Hey DevOps team,

Our deployment pipeline is failing again with Key Vault access errors. Before you ask - 
I already checked the DNS records like we did last time, and they look correct. The 
nslookup shows the private IP (10.1.2.15) as expected.

Pipeline: PatientPortal-CI-CD
Error: Timeout accessing Key Vault after 60 seconds
Last successful run: Yesterday at 4:30 PM

This is blocking our year-end release that needs to go out before the holiday break. 
The error is different from the Lab 1 incident - no 403 Forbidden this time, just 
straight timeouts.

Can you investigate?

Thanks,
Maya

-- 
Maya Patel | Senior Application Developer
Contoso HealthTech Solutions
```

---

### Email 2: Investigation Findings

```
From: Jordan Chen <jordan.chen@contosohealthtech.com>
To: Maya Patel <maya.patel@contosohealthtech.com>
Cc: DevOps Team <devops@contosohealthtech.com>
Date: Tuesday, December 23, 2024 1:42 PM
Subject: RE: Patient Portal Pipeline Failing - Key Vault Access Issue

Maya,

Good catch checking DNS first - that saved time. I've been investigating for the past 
couple hours, and this is definitely different from the A record issue we had in Lab 1.

**What I Verified:**

1. **DNS Resolution - Working ✓**
   ```
   nslookup kv-contoso-prod-7a3f.vault.azure.net
   Result: 10.1.2.15 (correct private IP)
   ```

2. **Service Principal Permissions - Valid ✓**
   - Key Vault access policy shows our SP has Get/List secrets
   - No changes to permissions since yesterday

3. **Private Endpoint - Exists ✓**
   - Checked in Azure Portal
   - Private endpoint "pe-kv-contoso-prod" is provisioned
   - Shows as "Approved" connection state

4. **Network Connectivity - Failing ✗**
   ```
   # From build agent VM:
   curl -v https://kv-contoso-prod-7a3f.vault.azure.net
   Result: Connection timeout after 60 seconds
   
   # Agent can reach internet:
   curl -I https://github.com
   Result: 200 OK (works fine)
   ```

**What's Strange:**

DNS is resolving correctly to the private IP, but the agent still cannot establish a 
connection to the Key Vault. It's like the network path is blocked somehow, even though 
the private endpoint exists.

I ran a quick check of the Private DNS zone configuration:

```
az network private-dns link vnet list \
    --resource-group rg-contoso-prod \
    --zone-name privatelink.vaultcore.azure.net
```

Need to dig deeper into whether the DNS zone is properly integrated with our VNet.

**My Plan:**

Following the Azure Support troubleshooting workflow we learned from Lab 1, I want to 
systematically validate:
- Private DNS zone virtual network links
- Network Security Groups (NSGs) 
- Route tables
- Any recent changes to VNet configuration

Before opening a support case, I think we can solve this ourselves if I work through 
the diagnostic steps methodically.

Jordan

-- 
Jordan Chen | DevOps Engineer
Contoso HealthTech Solutions
```

---

### Email 3: Manager Support

```
From: Sam Rodriguez <sam.rodriguez@contosohealthtech.com>
To: Jordan Chen <jordan.chen@contosohealthtech.com>
Cc: Maya Patel <maya.patel@contosohealthtech.com>, DevOps Team <devops@contosohealthtech.com>
Date: Tuesday, December 23, 2024 3:20 PM
Subject: RE: Patient Portal Pipeline Failing - Great troubleshooting approach

Jordan,

Excellent systematic approach - this is exactly what we should be doing. Your DNS 
validation work saved us hours compared to last time.

I like that you're following the troubleshooting workflow before escalating. Since DNS 
resolution is working but connectivity is failing, focus on **validating the Private 
DNS zone VNet links**. That's the integration point between DNS and network connectivity.

Document what you find as you go. If we need to open a support case, we'll have all the 
evidence ready. But I have a feeling you'll figure this out.

Maya - Jordan will update you once he identifies the issue. We should still be able to 
deploy before holiday break.

Sam

-- 
Sam Rodriguez | Engineering Manager, Platform & DevOps
Contoso HealthTech Solutions
```

---

## Lab Scenario: Your Role

You are **Jordan Chen**, the DevOps Engineer who successfully resolved the DNS A record issue in Lab 1. Now you're facing a different networking problem. This time DNS resolution is working correctly, but the agent still cannot reach the Key Vault private endpoint.

### Situation
- **Environment**: Self-hosted Azure DevOps agent running in Azure VNet
- **What's Working**: DNS resolves to private IP (10.1.2.15), service principal permissions valid
- **What's Broken**: Cannot establish network connection to Key Vault, connection timeouts
- **Recent Context**: Successfully fixed similar issue 3 weeks ago (wrong A record)

### Your Task
Use the Azure Support troubleshooting workflow to validate the Private DNS zone configuration. Focus on ensuring the DNS zone is properly linked to the VNet where the build agent resides. DNS resolution working correctly suggests the zone exists, but network connectivity failing indicates a potential VNet link issue.

**Available Tools:**
- SSH access to the build agent VM
- `nslookup`, `dig`, `curl` command-line tools  
- Azure Portal access to review Private DNS zone VNet links
- Azure CLI for querying DNS zone configuration
- Terraform state files showing infrastructure configuration

### Success Criteria
- Identify why the agent cannot reach the Key Vault despite correct DNS resolution
- Validate Private DNS zone virtual network links
- Fix the configuration so network connectivity is restored
- Pipeline successfully retrieves secrets from Key Vault via private endpoint
- Document the root cause and resolution

### What You'll Learn
- How Private DNS zone VNet links enable connectivity
- Difference between DNS resolution and network connectivity
- Validating VNet integration for Private DNS zones
- Azure private endpoint troubleshooting methodology
- Building on previous DNS troubleshooting knowledge

---

**Ready to begin troubleshooting?** Continue to the hands-on exercises in [README.md](README.md).
