# Azure Support Collaboration Email Template

Use this template to draft your collaboration request to Azure Networking Support (or in this lab, your instructor).

---

**To:** Azure Networking Support (Instructor: your-instructor@email.com)  
**Subject:** Azure Private DNS Zone - Key Vault Private Endpoint Connectivity Issue  
**Priority:** High  
**Case Category:** Azure Private Link → Private DNS Zone Configuration

---

## Issue Summary

[Provide a brief 2-3 sentence description of the problem]

**Example:**
> Our Azure DevOps pipeline cannot retrieve secrets from Key Vault via its private endpoint. The pipeline was working successfully until [date/time], and now fails at the RetrieveConfig stage with a connection timeout. We've confirmed the Key Vault is healthy from the public internet, but the self-hosted agent cannot connect via the private endpoint.

---

## Azure Guided Troubleshooter Responses

**Question 1: Are the resources involved connected to or passing through an Azure Network resource?**
- ☐ Yes, resources are hosted in a Virtual Network
- ☐ No, resources are outside of a Virtual Network
- ☐ This is a request for assistance recovering deleted networking resources

**Your Answer:** _____________________

---

**Question 2: Which option best describes the problem prompting your collaboration with Azure Networking?**
- ☐ Domain Name System (DNS) resolution issue
- ☐ Network connectivity or performance issue
- ☐ Application layer issues related to HTTP/HTTPS or TLS
- ☐ Other

**Your Answer:** _____________________

**Reasoning:** _____________________

---

**Question 3: What type of DNS solution is the customer running?**
- ☐ Azure Traffic Manager
- ☐ Azure Public DNS Zone
- ☐ Azure Private DNS Zone
- ☐ Azure Private Resolver
- ☐ Azure-Provided DNS (168.63.129.16)
- ☐ Windows Custom DNS Server
- ☐ 3rd party DNS solution

**Your Answer:** _____________________

---

## Affected Resource Details

| Information | Value |
|-------------|-------|
| **Subscription ID** | `_____________________` |
| **Resource Group** | `_____________________` |
| **Key Vault Name** | `_____________________` |
| **Key Vault FQDN** | `_____________________` |
| **Private Endpoint Name** | `_____________________` |
| **Private Endpoint IP** | `_____________________` |
| **Private DNS Zone Name** | `_____________________` |
| **Agent VNet Name** | `_____________________` |
| **Agent VNet CIDR** | `_____________________` |
| **Agent VM Name** | `_____________________` |
| **Agent VM Private IP** | `_____________________` |

---

## Azure Resource IDs (for Backend Logging)

**Why Azure Support or other teams within Microsoft need these:** Resource IDs allow support engineers to query Azure Resource Graph, backend diagnostic logs, and resource health telemetry not visible in the Portal. This accelerates root cause analysis.

### How to Retrieve Resource IDs

**Portal Method:**
1. Navigate to the resource in Azure Portal
2. Go to **Properties** blade
3. Copy the **Resource ID** field (looks like `/subscriptions/{guid}/resourceGroups/{rg}/providers/...`)

**CLI Method:**
```bash
# Key Vault Resource ID
az keyvault show --name <keyvault-name> --query id -o tsv

# Private Endpoint Resource ID
az network private-endpoint show --name <pe-name> --resource-group <rg> --query id -o tsv

# Private DNS Zone Resource ID
az network private-dns zone show --name privatelink.vaultcore.azure.net --resource-group <rg> --query id -o tsv

# VNet Resource ID
az network vnet show --name <vnet-name> --resource-group <rg> --query id -o tsv

# Network Interface Resource ID (attached to Private Endpoint)
az network nic show --ids $(az network private-endpoint show --name <pe-name> --resource-group <rg> --query 'networkInterfaces[0].id' -o tsv) --query id -o tsv
```

### Fill in Resource IDs

| Resource | Resource ID |
|----------|-------------|
| **Key Vault** | `/subscriptions/_____/resourceGroups/_____/providers/Microsoft.KeyVault/vaults/_____` |
| **Private Endpoint** | `/subscriptions/_____/resourceGroups/_____/providers/Microsoft.Network/privateEndpoints/_____` |
| **Network Interface (PE)** | `/subscriptions/_____/resourceGroups/_____/providers/Microsoft.Network/networkInterfaces/_____` |
| **Private DNS Zone** | `/subscriptions/_____/resourceGroups/_____/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net` |
| **Agent VNet** | `/subscriptions/_____/resourceGroups/_____/providers/Microsoft.Network/virtualNetworks/_____` |
| **Agent VM** | `/subscriptions/_____/resourceGroups/_____/providers/Microsoft.Compute/virtualMachines/_____` |

---

## Issue Timeline

| Timestamp | Event |
|-----------|-------|
| `_____________________` | Last successful pipeline run |
| `_____________________` | First failed pipeline run |
| `_____________________` | Issue reported to team |
| `_____________________` | Troubleshooting initiated |

---

## Error Messages

**Pipeline Error Output:**
```
[Paste exact error message from Azure DevOps pipeline logs]
```

**Example:**
```
##[error]Failed to retrieve AppMessage from Key Vault
##[error]AzureKeyVault task failed with error: Connection timed out after 60 seconds
```

---

## Troubleshooting Steps Completed

1. ☐ Verified Key Vault is accessible from public internet (Step 5A)
   - **Result:** _____________________

2. ☐ Compared successful vs. failed pipeline runs (Step 4)
   - **Observation:** _____________________

3. ☐ Checked service connection permissions in Azure DevOps
   - **Result:** _____________________

4. ☐ Verified Private Endpoint status in Azure Portal
   - **Result:** _____________________

5. ☐ Tested DNS resolution from agent VM (Step 6)
   - **Expected IP:** _____________________
   - **Actual IP:** _____________________
   - **Command used:** `nslookup <key-vault-fqdn>`

6. ☐ Checked Network Security Group rules
   - **Result:** _____________________

---

## Diagnostic Evidence

**Attach or include:**
- [ ] Screenshot of pipeline failure (RetrieveConfig stage)
- [ ] Screenshot of last successful run
- [ ] Output of `nslookup` from agent VM
- [ ] Output of `az network private-dns record-set a show`
- [ ] Output of `az network private-endpoint show`
- [ ] Network diagram (if available)

---

## Expected Behavior

[Describe what should happen]

**Example:**
> The self-hosted agent should be able to resolve the Key Vault FQDN (`kv-dns-lab-xxxxx.vault.azure.net`) to the private endpoint IP address (e.g., `10.1.2.4` - check with `terraform output -raw key_vault_private_ip`) and successfully retrieve the AppMessage secret during the RetrieveConfig stage.

---

## Actual Behavior

[Describe what is actually happening]

**Example:**
> DNS resolution from the agent VM returns IP `10.1.2.50` instead of the correct private endpoint IP (use `terraform output -raw key_vault_private_ip` to verify). The agent attempts to connect to the wrong IP address, resulting in a connection timeout. The RetrieveConfig stage fails, and subsequent stages (Build, Deploy) never execute.

---

## Business Impact

**Severity:** ☐ Critical  ☐ High  ☐ Medium  ☐ Low

**Impact Description:**
[Describe how this affects your operations]

**Example:**
> Our CI/CD pipeline is completely blocked. Development team cannot deploy updates to production environment. Estimated impact: 20 developers blocked, potential revenue loss if hotfix deployment is needed.

---

## Additional Context

[Any other relevant information]

**Example:**
- This infrastructure was deployed via Terraform 2 weeks ago
- No manual changes were made to DNS records (to our knowledge)
- Issue started Monday morning after weekend maintenance window
- Similar setup works in our dev environment without issues

---

## Requested Action

[What do you need from Azure Support?]

**Example:**
> Please investigate the Private DNS Zone configuration and verify:
> 1. Whether the A record for the Key Vault has been modified
> 2. If there are any Azure platform issues affecting DNS resolution
> 3. Guidance on preventing this type of drift in the future

---

## Attachments

1. `pipeline-failure-screenshot.png`
2. `nslookup-output.txt`
3. `private-dns-record-output.txt`
4. `network-diagram.pdf` (optional)

---

**Note:** Before sending this email, complete STEP 6 in the lab to test DNS resolution from the agent VM. You may discover the root cause yourself and not need to send this collaboration request!
