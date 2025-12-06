# Implementation Guide for ADO_DNS_LABS

## Project Purpose
This is a Terraform-based Azure DNS troubleshooting lab designed for **non-networking experts** learning Azure DevOps and DNS resolution. The labs teach systematic troubleshooting using Azure Guided Troubleshooter workflow and hierarchical thinking about Azure components.

## Critical Design Principles

### 1. **Never Use Terraform for Troubleshooting**
**Why**: During real outages, Terraform may be unreliable or unavailable.

**Pattern**: 
```markdown
❌ WRONG: Run `terraform output private_endpoint_ip`
✅ RIGHT: Navigate to Portal → Resource → Properties OR use `az` CLI commands
```

**Implementation**: All data collection steps use Portal navigation + CLI commands + REST API as alternatives.

### 2. **Hierarchical Object Notation**
**Why**: Non-experts don't understand vague pronouns like "it knows" or "the agent can't reach".

**Pattern**:
```markdown
❌ WRONG: "The task shows an error because it can't reach the endpoint"
✅ RIGHT: "**AzureKeyVault@2 task** shows an error because **Agent VM → Network Stack** can't reach **Key Vault → Private Endpoint**"
```

**Component Hierarchy Examples**:
- `Pipeline → RetrieveConfig Stage → AzureKeyVault@2 Task`
- `Agent VM → DNS Resolver → Query for keyvault-dnslab12345.vault.azure.net`
- `Private DNS Zone → A Record → IP address`
- `Private Endpoint → Network Interface → Private IP`

**Implementation Locations**:
- Error interpretation tables (STEP 2)
- Architecture explanations (STEP 3)
- Data collection rationale (STEP 6-9)
- Troubleshooting guidance (throughout)

### 3. **Guided Data Collection for Non-Experts**
**Why**: Beginners need to understand "why we need this data" before collecting it.

**Pattern**:
```markdown
## STEP 6: Analyze What We Know and Plan Data Collection

### What We Know ✅
| Evidence | What This Tells Us |
|----------|-------------------|
| Pipeline fails at AzureKeyVault@2 task | Specific task, not authentication |
| Error: "The task has timed out." | Network issue, not permissions |

### What We Don't Know ❓
- What IP does Agent VM → DNS Resolver return for keyvault-dnslab12345.vault.azure.net?
- What IP is configured in Private DNS Zone → A Record?
- Do they match?

### Why We Need This Data 🎯
**DNS Resolution Path**: Agent VM → DNS Resolver → Private DNS Zone → A Record → IP address
**Expected**: All return 10.0.2.5 (Private Endpoint IP)
**Reality**: Unknown - this is what we're about to discover!
```

**Implementation**: Every data collection step (7-9) explains:
1. What command to run
2. What output to expect
3. Why this data matters
4. How it fits into the bigger picture

### 4. **Azure Guided Troubleshooter Workflow**
**Why**: Matches real Azure Support escalation process.

**3 Required Questions** (STEP 5):
1. Does your issue involve resources in a Virtual Network (VNet)?
2. Are you experiencing an issue with DNS, Network connectivity, or Application-specific behavior?
3. What DNS solution(s) does your architecture use?

**Response Format**:
```markdown
**Your Responses**:
1. ☑️ Yes (Private Endpoint in VNet)
2. 🔹 DNS issue
3. 🔹 Azure Private DNS Zone
```

**Routing**: Always leads to "SAP Azure / Azure DNS / DNS Resolution Failures" queue.

**Integration**: Responses captured in EMAIL_TEMPLATE.md for instructor review at STEP 5 and STEP 10.

### 5. **Two Instructor Touchpoints**
**Why**: Simulates real support escalation cadence.

**Touchpoint 1 - STEP 5**: Initial collaboration request
- Send EMAIL_TEMPLATE.md with Guided Troubleshooter responses
- Include architecture diagram screenshot
- List affected resources (table format)
- Share initial error messages

**Touchpoint 2 - STEP 10**: Findings report
- Update EMAIL_TEMPLATE.md with diagnostic evidence
- Include comparison table showing IP address mismatch
- Explain what was discovered and next steps
- Request validation before implementing fix

### 6. **Exact Error Messages**
**Why**: Students must see exactly what they'll encounter in production.

**Pattern**:
```markdown
❌ WRONG: "Failed to retrieve secrets from Key Vault"
✅ RIGHT: 
##[error]The task has timed out.
Finishing: Retrieve Configuration from Key Vault
```

**Implementation**: Run `./break-lab.sh lab1`, trigger pipeline, copy **verbatim** error output. No paraphrasing.

## Lab Structure Blueprint

### Standard Lab Flow (12 Steps)
1. **Review Objectives**: What will break, what you'll learn
2. **Run Pipeline → Observe Failure**: See exact error message
3. **Understand the Architecture**: Diagram + component discovery
4. **Understand the Error**: What failed, what this means
5. **Azure Guided Troubleshooter**: 3 questions → email instructor
6. **Analyze What We Know and Plan Data Collection**: Evidence table + action plan
7. **Data Collection Step 1**: (Lab-specific, e.g., DNS from agent)
8. **Data Collection Step 2**: (Lab-specific, e.g., Private Endpoint IP)
9. **Data Collection Step 3**: (Lab-specific, e.g., DNS A record)
10. **Compare and Report Findings**: Table with discrepancies → email instructor
11. **Fix the Issue**: Portal + CLI + REST API options
12. **Verify the Fix**: Re-run pipeline, confirm success

### Lab-Specific Customization

**Lab 1 - DNS A Record Misconfiguration**:
- Data collection: DNS from agent (10.0.2.4) vs Private Endpoint IP (10.0.2.5) vs A Record (10.0.2.4)
- Root cause: A record points to wrong IP
- Fix: Update A record to 10.0.2.5

**Lab 2 - Missing VNet Link**:
- Data collection: VNet links configured, DNS resolution from agent, Private DNS Zone settings
- Root cause: VNet link missing for agent's VNet
- Fix: Create VNet link
- Note: Needs STEP 6-12 restructure (currently old format)

**Lab 3 - Custom DNS Server**:
- Data collection: Custom DNS server IP, forwarding rules, conditional forwarders
- Root cause: Custom DNS not configured to forward to Azure DNS (168.63.129.16)
- Fix: Configure conditional forwarder
- Note: Needs STEP 6-12 restructure + customer DNS admin coordination guidance

## File Architecture

### Core Lab Files
```
labs/
  lab1/
    README.md              # Main instructions (12 steps)
    EMAIL_TEMPLATE.md      # Collaboration request template
  lab2/
    README.md              # ⚠️ Needs restructure
  lab3/
    README.md              # ⚠️ Needs restructure
```

### Key File Patterns

**README.md Structure**:
```markdown
# Lab [N]: [Scenario Name]

## Objectives
- Break: [What infrastructure breaks]
- Learn: [What concepts this teaches]
- Fix: [What they'll implement]

## Prerequisites
[List prior labs or knowledge]

## STEP 1: Review Objectives
## STEP 2: Run Pipeline → Observe Failure
[Exact error output in code block]

## STEP 3: Understand the Architecture
[Component discovery + diagram]

## STEP 4: Understand the Error
[Error interpretation table with hierarchical notation]

## STEP 5: Complete Azure Guided Troubleshooter 🧭
[3 questions with collapsible hints]

## STEP 6: Analyze What We Know and Plan Data Collection
[Evidence table + unknowns + why we need data]

## STEP 7-9: Data Collection Steps
[Portal + CLI + REST API for each data point]

## STEP 10: Compare and Report Findings
[Comparison table + email instructor]

## STEP 11: Fix the Issue
[Portal + CLI + REST API options]

## STEP 12: Verify the Fix
[Re-run pipeline + expected success output]
```

**EMAIL_TEMPLATE.md Structure**:
```markdown
# Collaboration Request Email Template

## Subject Line
Azure DNS Resolution Issue - [Your Name] - [Lab Number]

## Email Body

### Issue Summary
[Brief description]

### Azure Guided Troubleshooter Responses
1. VNet resources: ☑️ Yes / ☐ No
2. Issue type: DNS / Network / Application
3. DNS solution: Azure Private DNS / Custom / Hybrid

### Affected Resource Details
| Resource Type | Name | Resource Group |
|---------------|------|----------------|
[Table rows]

### Error Messages
[Exact output]

### Troubleshooting Steps Completed
- [ ] Verified resource exists
- [ ] Checked network connectivity
[Checklist items]

### Diagnostic Evidence
[Data collected in STEP 7-9]

### Next Steps Requested
[What you need from instructor]
```

## Common Patterns to Follow

### Data Collection Commands
**DNS Query from Agent**:
```bash
# SSH to agent
az vm run-command invoke \
  --resource-group rg-dnslab \
  --name vm-agent-dnslab \
  --command-id RunShellScript \
  --scripts "nslookup keyvault-dnslab12345.vault.azure.net"
```

**Private Endpoint IP**:
```bash
# Get NIC ID from private endpoint
az network private-endpoint show \
  --name pe-keyvault-dnslab12345 \
  --resource-group rg-dnslab \
  --query 'networkInterfaces[0].id' -o tsv

# Get private IP from NIC
az network nic show --ids <NIC_ID> \
  --query 'ipConfigurations[0].privateIPAddress' -o tsv
```

**DNS A Record**:
```bash
az network private-dns record-set a show \
  --resource-group rg-dnslab \
  --zone-name privatelink.vaultcore.azure.net \
  --name keyvault-dnslab12345 \
  --query 'aRecords[0].ipv4Address' -o tsv
```

### Error Interpretation Table Format
```markdown
| What Failed | Hierarchical Component | What This Means |
|-------------|------------------------|-----------------|
| Task timeout | **Pipeline → RetrieveConfig Stage → AzureKeyVault@2 Task** times out after 60 seconds | **Agent VM → Network Stack** cannot establish connection to **Key Vault → Private Endpoint** |
| DNS resolution | **Agent VM → DNS Resolver** queries for keyvault-dnslab12345.vault.azure.net | Need to verify what IP **Private DNS Zone → A Record** returns |
```

### Comparison Table Format (STEP 10)
```markdown
| Component | Expected Value | Actual Value | Match? |
|-----------|---------------|--------------|--------|
| **Private Endpoint → NIC → Private IP** | 10.0.2.5 | 10.0.2.5 | ✅ |
| **Private DNS Zone → A Record → IP** | 10.0.2.5 | 10.0.2.4 | ❌ MISMATCH |
| **Agent VM → DNS Resolver → Response** | 10.0.2.5 | 10.0.2.4 | ❌ MISMATCH |

**Root Cause**: Private DNS Zone A record points to incorrect IP address (10.0.2.4 instead of 10.0.2.5).
```

## Implementation Checklist

### When Creating New Labs
- [ ] Copy Lab 1 README.md structure (12 steps)
- [ ] Run `./break-lab.sh labN` and copy **exact** error output
- [ ] Create architecture diagram with component hierarchy
- [ ] Verify Guided Troubleshooter questions apply
- [ ] Document data collection commands (Portal + CLI + REST API)
- [ ] Create comparison table showing expected vs actual
- [ ] Provide 3 fix options (Portal primary, CLI secondary, REST API advanced)
- [ ] Write verification steps with expected success output
- [ ] Test end-to-end as student (no terraform commands!)

### When Editing Existing Labs
- [ ] Replace vague pronouns with hierarchical notation
- [ ] Ensure all terraform commands removed from troubleshooting
- [ ] Verify error messages match actual pipeline output
- [ ] Add "why we need this data" explanations to data collection
- [ ] Check EMAIL_TEMPLATE.md references at STEP 5 and STEP 10
- [ ] Confirm Portal navigation is primary, CLI is secondary
- [ ] Test that non-networking expert can follow instructions

### When Reviewing Content
- [ ] Grep for vague terms: `the task|it knows|the agent|it waits|it returns`
- [ ] Check for terraform in troubleshooting: `terraform output|terraform show`
- [ ] Verify hierarchical notation: `Component → Subcomponent`
- [ ] Confirm instructor touchpoints at STEP 5 and STEP 10
- [ ] Validate error messages are verbatim (no paraphrasing)

## Known Issues and Workarounds

### Issue: Tools Disabled Mid-Implementation
**Context**: Hierarchical notation implementation interrupted when `replace_string_in_file` tool disabled.

**Workaround**: 
1. Document pattern in this guide
2. Use `grep_search` to find all instances
3. Batch replacements when tools re-enabled
4. Test pattern on one section first

**Pattern to Apply**:
```markdown
# In STEP 2 error table:
OLD: "The task shows an error... it knows what to get from Key Vault"
NEW: "**AzureKeyVault@2 task** shows an error... **task configuration** specifies which secrets to retrieve"

# In STEP 4:
OLD: "the agent can't reach the endpoint"
NEW: "**Agent VM → Network Stack** can't reach **Key Vault → Private Endpoint**"

# In STEP 6:
OLD: "DNS returns the IP address"
NEW: "**Private DNS Zone → A Record** returns the IP address"
```

### Issue: Labs 2 & 3 Have Old Structure
**Status**: Lab 1 restructured with new 12-step format. Labs 2 & 3 still have old format (6 steps).

**Blocker**: Can't launch lab series until all three labs have consistent structure.

**Next Steps**:
1. Apply Lab 1 STEP 6-12 pattern to Lab 2 (Missing VNet Link)
2. Apply Lab 1 STEP 6-12 pattern to Lab 3 (Custom DNS)
3. Adjust Lab 3 for complexity (custom DNS requires customer DNS admin)
4. Create INSTRUCTOR_GUIDE.md with answer keys

### Issue: No Instructor Guide
**Status**: EMAIL_TEMPLATE.md exists, but no answer key for instructors.

**Impact**: Instructors can't efficiently review student submissions.

**Required Content**:
- Expected findings for each data collection step
- Common mistakes and how to guide students
- Time estimates for each lab
- Grading rubric for collaboration requests

## Terminology Standards

### Preferred Terms
- "Collaboration request" (not "support case" or "support ticket")
- "Component → Subcomponent" (not "it" or "the task")
- "Agent VM → DNS Resolver" (not "the agent's DNS")
- "Private DNS Zone → A Record" (not "the A record")
- "Pipeline → Stage → Task" (not "the pipeline task")

### Avoided Terms
- ❌ "it knows" → Use "task configuration specifies"
- ❌ "the agent" → Use "Agent VM" or "Agent VM → Component"
- ❌ "the task" → Use "AzureKeyVault@2 task" or "Pipeline → Stage → Task"
- ❌ "DNS returns" → Use "Private DNS Zone → A Record returns"
- ❌ "support case" → Use "collaboration request"

## Git Workflow

### Branch Strategy
- Main branch: `main` (stable, tested labs)
- Feature branch: `feature/pipeline-nodejs-app` (current development)

### Commit Message Format
```
<Action> <Component>: <brief description>

- Bullet point details
- More specifics
- Why this change matters
```

**Examples**:
```
Fix Lab 1 STEP 2: show actual timeout error message

- Replace generic 'Failed to retrieve' with actual AzureKeyVault@2 timeout output
- Update error interpretation to focus on timeout (60 seconds)
- Students now see exact error they'll encounter in their pipelines
```

```
Restructure Lab 1 STEP 6-12: guided data collection for non-experts

- Add "What We Know/Don't Know" evidence table
- Explain why each data point is needed
- Create comparison table at STEP 10
- Replace all terraform commands with Portal/CLI/REST API
```

### Dual Push Strategy
```bash
git push origin feature/pipeline-nodejs-app  # Azure DevOps
git push public feature/pipeline-nodejs-app  # GitHub
```

## Testing Protocol

### Before Committing Lab Changes
1. **Run break script**: `./break-lab.sh lab1`
2. **Trigger pipeline**: Verify error matches documentation
3. **Follow instructions as student**: No prior knowledge assumption
4. **Collect data**: Verify all Portal/CLI/REST API commands work
5. **Run fix script**: `./fix-lab.sh lab1`
6. **Re-run pipeline**: Verify success output

### Validation Checklist
- [ ] Error message is verbatim from pipeline
- [ ] No terraform commands in troubleshooting steps
- [ ] All Portal navigation paths tested
- [ ] All CLI commands return expected output
- [ ] REST API examples include authentication
- [ ] Hierarchical notation used consistently
- [ ] EMAIL_TEMPLATE.md referenced at correct steps
- [ ] Non-expert can understand without networking background

## Future Enhancements

### Pending Implementation
1. **Complete hierarchical notation** in Lab 1 (~20 remaining instances)
2. **Restructure Lab 2** with 12-step format
3. **Restructure Lab 3** with 12-step format
4. **Create INSTRUCTOR_GUIDE.md** with answer keys
5. **Add time estimates** for each lab
6. **Create architecture diagrams** for STEP 6 concept explanations

### Potential Additions
- Video walkthroughs for each lab
- Automated validation scripts
- Interactive architecture diagrams
- Common mistakes database
- Student feedback integration

## Contact and Contribution

This lab series is maintained for Azure DNS troubleshooting education. When contributing:

1. Follow hierarchical notation pattern
2. Test all commands as non-expert
3. Remove terraform from troubleshooting
4. Use exact error messages
5. Explain "why" for every data collection step
6. Maintain two instructor touchpoints (STEP 5 and STEP 10)

---

**Last Updated**: December 6, 2025  
**Current Status**: Lab 1 complete, Labs 2&3 need restructure, instructor guide needed  
**Readiness Assessment**: 70% ready for pilot testing
