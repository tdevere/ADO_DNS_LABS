# Collaboration Request Email Template - Lab 2

Use this template when communicating with your instructor or Azure Support about the VNet link configuration issue.

---

## Subject Line
```
Azure Private DNS VNet Link Issue - [Your Name] - Lab 2
```

---

## Email Body

### Issue Summary
Brief description of the problem (2-3 sentences):
```
[Example: The pipeline fails when retrieving secrets from Azure Key Vault 
through a private endpoint. DNS resolution returns public IP addresses 
instead of the private endpoint IP, causing connectivity failures.]
```

---

### Azure Guided Troubleshooter Responses

**1. Does your issue involve resources in a Virtual Network (VNet)?**
- ☑️ Yes - Agent VM and Private Endpoint are in VNets
- ☐ No

**2. Are you experiencing an issue with DNS, Network connectivity, or Application-specific behavior?**
- ☑️ DNS issue - Resolving to public IP instead of private IP
- ☐ Network connectivity issue
- ☐ Application-specific behavior

**3. What DNS solution(s) does your architecture use?**
- ☑️ Azure Private DNS Zone
- ☐ Custom DNS servers
- ☐ Hybrid DNS (Azure + on-premises)

**Troubleshooter Routing**: SAP Azure / Azure DNS / DNS Resolution Failures

---

### Affected Resource Details

| Resource Type | Resource Name | Resource Group | Location | Notes |
|--------------|---------------|----------------|----------|-------|
| Key Vault | `kv-dns-lab-xxxxx` | `rg-dnslab` | `westus2` | Private endpoint enabled, public access disabled |
| Private Endpoint | `pe-keyvault-dnslab-xxxxx` | `rg-dnslab` | `westus2` | Connected to Key Vault |
| Private DNS Zone | `privatelink.vaultcore.azure.net` | `rg-dnslab` | `global` | Contains A record |
| Agent VM | `vm-agent-dnslab` | `rg-dnslab` | `westus2` | Self-hosted Azure DevOps agent |
| Agent VNet | `vnet-agent` | `rg-dnslab` | `westus2` | Address space: 10.0.0.0/16 |

---

### Azure Resource IDs (for Backend Telemetry)

**Why needed**: Resource IDs allow Azure Support or other teams within Microsoft to query backend diagnostic logs, Resource Graph history, and cross-service correlation telemetry (e.g., Private Endpoint → Key Vault calls). This data is not visible in the Portal.

#### How to Retrieve Resource IDs

**Portal Method:**
1. Navigate to resource → **Properties** blade → Copy **Resource ID**

**CLI Method:**
```bash
# Key Vault
az keyvault show --name <keyvault-name> --query id -o tsv

# Private Endpoint
az network private-endpoint show --name <pe-name> --resource-group <rg> --query id -o tsv

# Private DNS Zone
az network private-dns zone show --name privatelink.vaultcore.azure.net --resource-group <rg> --query id -o tsv

# VNet
az network vnet show --name <vnet-name> --resource-group <rg> --query id -o tsv

# Network Interface (attached to Private Endpoint)
az network nic show --ids $(az network private-endpoint show --name <pe-name> --resource-group <rg> --query 'networkInterfaces[0].id' -o tsv) --query id -o tsv
```

#### Fill in Resource IDs Below

| Resource | Resource ID (Full ARM Path) |
|----------|-----------------------------|
| **Key Vault** | `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.KeyVault/vaults/{name}` |
| **Private Endpoint** | `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateEndpoints/{name}` |
| **Network Interface (PE)** | `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/networkInterfaces/{name}` |
| **Private DNS Zone** | `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net` |
| **Agent VNet** | `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{name}` |
| **Agent VM** | `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{name}` |

---

### Timeline

- **Last successful run**: [Date/Time or "Never worked" or "Lab 1 completion"]
- **Issue first observed**: [Date/Time - when you ran break-lab.sh]
- **Recent changes**: [Example: "Infrastructure change simulated by break-lab.sh lab2"]

---

### Error Messages

**Pipeline Stage**: RetrieveConfig (Get Message from Key Vault)
**Task**: Azure Key Vault (AzureKeyVault@2)

```
[Paste exact error output from Azure DevOps pipeline here]

Example:
##[error]
AppMessage: "Public network access is disabled and request is not from a trusted service 
nor via an approved private link.
Caller: appid=***;oid=...
Vault: kv-dns-lab-xxxxx;location=westus2."
```

---

### Troubleshooting Steps Completed

*Update this section after completing STEP 5 (initial request) and STEP 10 (findings report)*

#### Initial Investigation (STEP 5)
- [ ] Verified Private DNS Zone exists
- [ ] Checked DNS resolution from Agent VM
- [ ] Reviewed pipeline error message
- [ ] Checked VNet link configuration

#### Detailed Data Collection (STEP 10)
- [ ] Listed all VNet links for Private DNS Zone
- [ ] Performed DNS lookup from Agent VM
- [ ] Verified Private Endpoint IP address
- [ ] Compared expected vs actual DNS resolution

---

### Diagnostic Evidence

*Add this information after completing STEP 7-9*

#### STEP 7: VNet Link Status
**Command Used**:
```bash
az network private-dns link vnet list \
  --resource-group rg-dnslab \
  --zone-name privatelink.vaultcore.azure.net \
  --output table
```

**Result**:
```
[Paste output here - should be empty or missing Agent VNet]

Example when broken:
Name                    ResourceGroup    ProvisioningState    VirtualNetwork
```

**Analysis**: 
```
[Example: No VNet links found. Agent VNet is not linked to the Private DNS Zone.]
```

---

#### STEP 8: DNS Resolution from Agent VM
**Command Used**:
```bash
nslookup kv-dns-lab-xxxxx.vault.azure.net
```

**Result**:
```
[Paste output here]

Example when broken:
Server:         168.63.129.16
Address:        168.63.129.16#53

Non-authoritative answer:
Name:   kv-dns-lab-xxxxx.vault.azure.net
Address: 52.154.x.x  <-- PUBLIC IP (Wrong!)
```

**Analysis**:
```
[Example: Agent VM → DNS Resolver queries Azure Recursive Resolver (168.63.129.16), 
which returns public IP because Agent VNet has no link to Private DNS Zone. 
Falls back to public DNS resolution.]
```

---

#### STEP 9: Private Endpoint Configuration
**Command Used** (get Private Endpoint NIC):
```bash
az network private-endpoint show \
  --name pe-keyvault-dnslab-xxxxx \
  --resource-group rg-dnslab \
  --query 'networkInterfaces[0].id' -o tsv
```

**Command Used** (get Private IP):
```bash
az network nic show --ids [NIC-ID] \
  --query 'ipConfigurations[0].privateIPAddress' -o tsv
```

**Result**:
```
[Paste actual private IP]

Example:
10.1.2.5
```

**Analysis**:
```
[Example: Private Endpoint exists with correct IP (10.1.2.5), but DNS doesn't return this IP 
because Agent VNet → Private DNS Zone link is missing.]
```

---

### Comparison Table (STEP 10)

| Component | Expected Value | Actual Value | Match? |
|-----------|---------------|--------------|--------|
| **Private DNS Zone → A Record** | Points to 10.1.2.x | Points to 10.1.2.x | ✅ |
| **Agent VNet → VNet Link** | Linked to Private DNS Zone | **NOT LINKED** | ❌ MISMATCH |
| **Agent VM → DNS Resolver → Response** | Returns 10.1.2.x (private) | Returns 52.x.x.x (public) | ❌ MISMATCH |
| **Pipeline → AzureKeyVault@2 Task** | Connects to private IP | Attempts public IP (rejected) | ❌ MISMATCH |

**Root Cause Identified**:
```
[Example: Agent VNet lacks Virtual Network Link to Private DNS Zone. Without this link, 
Azure Recursive Resolver (168.63.129.16) cannot query the Private DNS Zone on behalf of 
the Agent VNet, causing DNS queries to fall back to public DNS resolution.]
```

---

### Network Architecture

**Split-Horizon DNS Path**:
```
Current (Broken):
Agent VM → Azure DNS (168.63.129.16) → [No VNet Link] → Public DNS → Public IP 52.x.x.x

Expected (Working):
Agent VM → Azure DNS (168.63.129.16) → [VNet Link] → Private DNS Zone → Private IP 10.1.2.x
```

**Key Components**:
- **Agent VNet**: 10.0.0.0/16 (contains Agent VM)
- **Private Endpoint VNet**: 10.1.0.0/16 (contains Private Endpoint)
- **Azure Recursive Resolver**: 168.63.129.16 (Azure DNS service)
- **Private DNS Zone**: privatelink.vaultcore.azure.net (contains A record)
- **Missing Component**: VNet Link between Agent VNet and Private DNS Zone

[Optional: Attach architecture diagram screenshot]

---

### Next Steps Requested

*For STEP 5 (initial request)*:
```
[Example: Requesting guidance on VNet link configuration best practices 
and validation that creating the link will resolve the issue.]
```

*For STEP 10 (findings report)*:
```
[Example: I have identified that the Agent VNet is not linked to the Private DNS Zone. 
I plan to create a VNet link with registration-enabled set to false. 
Please confirm this is the correct approach before I implement the fix.]
```

---

### Additional Context

**Environment Details**:
- Azure Subscription: [ID or name]
- Azure DevOps Organization: [Org name]
- Agent Pool: DNS-Lab-Pool
- Agent OS: Ubuntu 22.04
- Pipeline: [Pipeline name]

**Business Impact**:
```
[Example: Pipeline deployments are blocked. Development team cannot deploy 
application updates until Key Vault connectivity is restored.]
```

---

## Template Usage Instructions

1. **STEP 5** (Initial Request): Complete sections through "Troubleshooting Steps Completed (Initial)"
2. **STEP 7-9** (Data Collection): Add diagnostic evidence as you collect data
3. **STEP 10** (Findings Report): Complete comparison table and root cause analysis
4. **Send to Instructor**: Copy completed template into email or support ticket

---

**Remember**: This simulates real-world collaboration with Azure Support or your networking team. In production, thorough documentation accelerates problem resolution and demonstrates systematic troubleshooting approach.
