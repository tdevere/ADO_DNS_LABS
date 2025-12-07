# Lab 1: DNS Troubleshooting Scenario

## Company Profile

**Contoso HealthTech Solutions**  
A healthcare SaaS provider with 850 employees, offering HIPAA-compliant patient management and telehealth platforms to medical practices across North America. The company recently completed a security enhancement project, migrating all Azure Key Vaults to private endpoints to meet compliance requirements and eliminate public internet exposure of sensitive configuration data.

**Infrastructure:** Azure-based cloud platform with Azure DevOps for CI/CD, self-hosted build agents in Azure VNets, and Private DNS zones for internal service resolution.

---

## Character Profiles

| Name | Role | Tenure | Technical Level | Communication Style |
|------|------|--------|-----------------|---------------------|
| **Maya Patel** | Senior Application Developer | 3 years | 3/5 - Strong in application code, limited infrastructure knowledge | Direct, solution-focused |
| **Jordan Chen** | DevOps Engineer | 2 years | 4/5 - Azure expert, moderate networking experience | Analytical, detailed |
| **Sam Rodriguez** | Engineering Manager | 5 years | 4/5 - Former DevOps, now in leadership | Pragmatic, escalation-oriented |

---

## Internal Email Thread

### Email 1: Production Pipeline Failure

```
From: Maya Patel <maya.patel@contosohealthtech.com>
To: DevOps Team <devops@contosohealthtech.com>
Date: Monday, December 2, 2024 9:47 AM
Subject: URGENT: Patient Portal Pipeline Failing Since This Morning

Hey DevOps team,

Our patient portal deployment pipeline (PatientPortal-CI-CD) started failing overnight 
and I'm blocked on releasing the appointment scheduling hotfix. 

The pipeline worked perfectly on Friday afternoon when I tested the staging deployment. 
No code changes were pushed over the weekend. I tried re-running it three times this 
morning - same result every time.

Error from the logs:
"Failed to fetch secrets from Azure Key Vault. Operation returned an invalid status 
code 'Forbidden'"

The Key Vault task times out after about 45 seconds, then throws the 403 error. 
Everything else in the pipeline (checkout, build, tests) completes successfully.

Can someone take a look? We have a client demo at 2 PM and this fix needs to be in 
production.

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
Date: Monday, December 2, 2024 11:23 AM
Subject: RE: URGENT: Patient Portal Pipeline Failing Since This Morning

Maya,

I've been digging into this for the past hour. Here's what I've found:

**What I Checked:**
1. Service Connection (SC-ContosoProd-KV) - Valid, not expired
2. Key Vault access policies - Build agent service principal still has Get/List permissions
3. Key Vault firewall - Shows "Disabled public network access" (expected after last week's 
   private endpoint migration)
4. Build agent (vm-build-prod-01) - Healthy, can reach internet (tested with curl to 
   github.com)

**The Weird Part:**
I SSH'd into the build agent and ran some tests:

```bash
# This returns a public IP address (20.x.x.x range)
nslookup kv-contoso-prod-7a3f.vault.azure.net

# Agent can't reach the Key Vault
curl -I https://kv-contoso-prod-7a3f.vault.azure.net
# Result: Connection timeout after 60 seconds
```

**My Theory:**
The agent is trying to resolve the Key Vault FQDN and getting a public IP address instead 
of the private endpoint IP (should be 10.1.2.x range). Since we disabled public access 
last week, that public IP refuses connections - hence the 403/timeout.

This looks like a DNS resolution issue with the private endpoint setup. The VNet should 
be using the Private DNS zone to resolve *.vault.azure.net to private IPs, but something 
isn't working correctly.

**Recommendation:**
I'm not deep enough in Azure networking to troubleshoot Private DNS zone configuration 
safely (don't want to break other services). I think we should open a support case with 
Microsoft and have them validate the DNS setup. 

I can provide all the diagnostic output to speed things up.

Jordan

-- 
Jordan Chen | DevOps Engineer
Contoso HealthTech Solutions
```

---

### Email 3: Management Response

```
From: Sam Rodriguez <sam.rodriguez@contosohealthtech.com>
To: Jordan Chen <jordan.chen@contosohealthtech.com>
Cc: Maya Patel <maya.patel@contosohealthtech.com>, DevOps Team <devops@contosohealthtech.com>
Date: Monday, December 2, 2024 2:15 PM
Subject: RE: URGENT: Patient Portal Pipeline Failing - Support Case Opened

Team,

I've opened a Premier Support case with Microsoft (Case #2024120200847) and provided 
Jordan's diagnostic information. ETA for initial response is 2-4 hours.

In the meantime, Jordan - can you document the troubleshooting steps you took? If this 
is a DNS config issue on our end, I want to make sure we can fix it ourselves next time 
instead of waiting on support.

Maya - talked to the client, we've pushed the demo to tomorrow morning. They're fine 
with it. Take the afternoon to prep other materials.

Will update this thread when support responds.

Sam

-- 
Sam Rodriguez | Engineering Manager, Platform & DevOps
Contoso HealthTech Solutions
```

---

## Lab Scenario: Your Role

You are **Jordan Chen**, the DevOps Engineer investigating this issue. While waiting for Microsoft Support to respond (which could take hours), you decide to dig deeper into the DNS configuration yourself. 

### Situation
- **Environment**: Self-hosted Azure DevOps agent running in Azure VNet
- **What's Working**: Agent can reach public internet, authentication is valid
- **What's Broken**: Agent cannot resolve Key Vault private endpoint correctly
- **Recent Change**: Key Vault migrated to private endpoint with Private DNS zone last week

### Your Task
Use DNS diagnostic tools and the Azure Portal to identify why the build agent is resolving the Key Vault FQDN to a public IP address instead of the private endpoint IP. The Private DNS zone exists, but something in the configuration is preventing proper name resolution.

**Available Tools:**
- SSH access to the build agent VM
- `nslookup`, `dig`, `curl` command-line tools
- Azure Portal access to review Private DNS zone configuration
- Terraform state files showing infrastructure configuration

### Success Criteria
- Identify the root cause of the DNS resolution failure
- Fix the configuration so the agent resolves the Key Vault to its private IP (10.1.2.x)
- Pipeline successfully retrieves secrets from Key Vault via private endpoint
- Document the fix for the team

### What You'll Learn
- How Private DNS zones integrate with Azure VNets
- DNS A record configuration and validation
- Troubleshooting private endpoint connectivity
- Azure networking fundamentals for DevOps scenarios

---

**Ready to begin troubleshooting?** Continue to the hands-on exercises in [README.md](README.md).
