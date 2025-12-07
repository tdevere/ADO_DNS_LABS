# Collaboration Request Email Template - Lab 3

Use this template when communicating with your instructor or Azure Support about the custom DNS server configuration issue.

---

## Subject Line
```
Azure Custom DNS Forwarding Issue - [Your Name] - Lab 3
```

---

## Email Body

### Issue Summary
Brief description of the problem (2-3 sentences):
```
[Example: The pipeline fails when retrieving secrets from Azure Key Vault through a private endpoint. 
The VNet is configured to use a custom DNS server (10.1.2.50) which returns public IP addresses 
instead of the private endpoint IP for Azure services, causing connectivity failures.]
```

---

### Azure Guided Troubleshooter Responses

**1. Does your issue involve resources in a Virtual Network (VNet)?**
- ☑️ Yes - Agent VM, Private Endpoint, and Custom DNS Server are in VNet
- ☐ No

**2. Are you experiencing an issue with DNS, Network connectivity, or Application-specific behavior?**
- ☑️ DNS issue - Custom DNS returns public IP instead of private IP
- ☐ Network connectivity issue
- ☐ Application-specific behavior

**3. What DNS solution(s) does your architecture use?**
- ☐ Azure Private DNS Zone only
- ☑️ Custom DNS servers (BIND9 at 10.1.2.50)
- ☐ Hybrid DNS (Azure + on-premises)

**Troubleshooter Routing**: SAP Azure / Azure DNS / Custom DNS Configuration

**⚠️ Important Note**: Custom DNS server configuration requires coordination with the DNS administrator team. Microsoft Azure Support cannot directly access or modify customer-managed DNS infrastructure. This collaboration request seeks guidance on proper Azure DNS forwarding configuration.

---

### Affected Resource Details

| Resource Type | Resource Name | Resource Group | Location | Notes |
|--------------|---------------|----------------|----------|-------|
| Key Vault | `keyvault-dnslab12345` | `rg-dnslab` | `westus2` | Private endpoint enabled, public access disabled |
| Private Endpoint | `pe-keyvault-dnslab-xxxxx` | `rg-dnslab` | `westus2` | Connected to Key Vault |
| Private DNS Zone | `privatelink.vaultcore.azure.net` | `rg-dnslab` | `global` | Contains A record, linked to VNet |
| Agent VM | `vm-agent-dnslab` | `rg-dnslab` | `westus2` | Self-hosted Azure DevOps agent |
| Agent VNet | `vnet-agent` | `rg-dnslab` | `westus2` | Address space: 10.1.0.0/16, **Custom DNS: 10.1.2.50** |
| Custom DNS Server | `vm-dns-server` | `rg-dnslab` | `westus2` | BIND9, IP: 10.1.2.50 |

---

### Azure Resource IDs (for Backend Telemetry)

**Why needed**: Resource IDs enable Azure Support or other teams within Microsoft to:
- Query Azure Resource Graph for configuration change history
- Access backend diagnostic logs for Private Endpoint connections
- Correlate cross-service telemetry (Agent VM → Custom DNS → Azure DNS → Key Vault)
- Identify region-specific infrastructure issues not visible in Portal

**Important for Custom DNS**: Since Azure Support or other teams within Microsoft cannot directly access customer-managed DNS servers, Resource IDs help correlate Azure-side infrastructure (VNet, Private DNS Zone, Private Endpoint) with the custom DNS forwarding chain.

#### How to Retrieve Resource IDs

**Portal Method:**
1. Navigate to resource in Azure Portal
2. Go to **Properties** blade
3. Copy **Resource ID** (full ARM path: `/subscriptions/.../providers/...`)

**CLI Method:**
```bash
# Key Vault
az keyvault show --name <keyvault-name> --query id -o tsv

# Private Endpoint
az network private-endpoint show --name <pe-name> --resource-group <rg> --query id -o tsv

# Private DNS Zone
az network private-dns zone show --name privatelink.vaultcore.azure.net --resource-group <rg> --query id -o tsv

# Agent VNet
az network vnet show --name <vnet-name> --resource-group <rg> --query id -o tsv

# Custom DNS Server VM
az vm show --name <vm-name> --resource-group <rg> --query id -o tsv

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
| **Custom DNS Server VM** | `/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{name}` |

---

### Timeline

- **Last successful run**: [Date/Time or "Lab 2 completion"]
- **Issue first observed**: [Date/Time - when custom DNS was configured]
- **Recent changes**: [Example: "VNet DNS settings changed from Azure-provided to custom DNS server 10.1.2.50"]

---

### Error Messages

**Pipeline Stage**: RetrieveConfig (Get Message from Key Vault)
**Task**: Azure Key Vault (AzureKeyVault@2)

```
[Paste exact error output from Azure DevOps pipeline here]

Example:
##[error]AppMessage: "Public network access is disabled and request is not from a trusted service 
nor via an approved private link.
Caller: appid=***;oid=...
Vault: keyvault-dnslab12345;location=westus2."
```

---

### Troubleshooting Steps Completed

*Update this section after completing STEP 5 (initial request) and STEP 10 (findings report)*

#### Initial Investigation (STEP 5)
- [ ] Verified VNet is using custom DNS server (not Azure-provided 168.63.129.16)
- [ ] Checked DNS resolution from Agent VM
- [ ] Reviewed pipeline error message
- [ ] Confirmed Private Endpoint exists

#### Detailed Data Collection (STEP 10)
- [ ] Verified VNet DNS settings point to custom DNS server
- [ ] Tested DNS resolution through custom DNS server
- [ ] Queried Azure DNS (168.63.129.16) directly from Agent VM
- [ ] Inspected custom DNS server forwarding configuration
- [ ] Compared DNS responses from different DNS servers

---

### Diagnostic Evidence

*Add this information after completing STEP 7-9*

#### STEP 7: VNet DNS Configuration
**Command Used**:
```bash
az network vnet show \
  --resource-group rg-dnslab \
  --name vnet-agent \
  --query 'dhcpOptions.dnsServers' -o table
```

**Result**:
```
[Paste output here]

Example when using custom DNS:
Result
----------
10.1.2.50
```

**Agent VM DNS Configuration** (`/etc/resolv.conf`):
```
[Paste /etc/resolv.conf content]

Example:
nameserver 10.1.2.50
search internal.cloudapp.net
```

**Analysis**: 
```
[Example: VNet DHCP options configure 10.1.2.50 as DNS server. Agent VM → Network Stack → DNS Resolver 
uses custom DNS server (10.1.2.50) instead of Azure Recursive Resolver (168.63.129.16). This means 
DNS queries follow: Agent VM → Custom DNS Server → ??? (need to verify forwarding rules)]
```

---

#### STEP 8: DNS Resolution Testing

**Test 1: DNS Resolution from Agent VM (uses custom DNS)**
**Command Used**:
```bash
nslookup keyvault-dnslab12345.vault.azure.net
```

**Result**:
```
[Paste output here]

Example when broken:
Server:         10.1.2.50
Address:        10.1.2.50#53

Non-authoritative answer:
Name:   keyvault-dnslab12345.vault.azure.net
Address: 52.154.x.x  <-- PUBLIC IP (Wrong!)
```

**Test 2: Query Custom DNS Server Directly**
**Command Used**:
```bash
dig @10.1.2.50 keyvault-dnslab12345.vault.azure.net
```

**Result**:
```
[Paste output here]

Example:
;; ANSWER SECTION:
keyvault-dnslab12345.vault.azure.net. 60 IN A 52.154.x.x
```

**Test 3: Query Azure DNS Directly (bypass custom DNS)**
**Command Used**:
```bash
dig @168.63.129.16 keyvault-dnslab12345.vault.azure.net
```

**Result**:
```
[Paste output here]

Example when working:
;; ANSWER SECTION:
keyvault-dnslab12345.privatelink.vaultcore.azure.net. 10 IN A 10.1.2.5
```

**Analysis**:
```
[Example: Custom DNS Server (10.1.2.50) returns public IP 52.154.x.x. However, Azure Recursive Resolver 
(168.63.129.16) correctly returns private IP 10.1.2.5. This indicates Custom DNS Server → Forwarding Rules 
are NOT forwarding Azure Private Link queries to Azure DNS. Instead, Custom DNS Server forwards to public 
DNS (e.g., 8.8.8.8), which only knows public Azure records.]
```

---

#### STEP 9: Custom DNS Server Forwarding Configuration

**Method 1: Check BIND9 Configuration Files**
**Commands Used**:
```bash
# SSH to custom DNS server
ssh azureuser@10.1.2.50

# Check BIND9 forwarders
sudo cat /etc/bind/named.conf.options | grep -A 10 forwarders
```

**Result**:
```
[Paste configuration here]

Example when broken:
forwarders {
    8.8.8.8;  // Google DNS
    8.8.4.4;  // Google DNS secondary
};
```

**Method 2: Check for Conditional Forwarding Rules**
**Commands Used**:
```bash
# Check for zone-specific forwarding
sudo grep -r "privatelink" /etc/bind/
```

**Result**:
```
[Paste results here]

Example when broken:
(No output - no conditional forwarding rules exist)
```

**Analysis**:
```
[Example: Custom DNS Server → Global Forwarders point to Google DNS (8.8.8.8). No conditional forwarding 
rules exist for *.privatelink.* zones. This means ALL DNS queries, including Private Link queries, are 
forwarded to Google DNS. Google DNS has NO knowledge of Azure Private Link zones, so it returns public 
IP addresses. Missing configuration: Conditional forwarder for privatelink.vaultcore.azure.net → 168.63.129.16]
```

---

### Comparison Table (STEP 10)

| Component | Expected Value | Actual Value | Match? |
|-----------|---------------|--------------|--------|
| **VNet → DNS Settings** | 168.63.129.16 (Azure) or custom with proper forwarding | 10.1.2.50 (custom) | ⚠️ Using custom |
| **Custom DNS → Forwarders** | 168.63.129.16 for `*.privatelink.*` | 8.8.8.8 (public DNS) | ❌ MISMATCH |
| **Custom DNS → DNS Response** | 10.1.2.x (private) | 52.x.x.x (public) | ❌ MISMATCH |
| **Azure DNS (168.63.129.16) → Response** | 10.1.2.5 (private) | 10.1.2.5 (private) | ✅ |
| **Private Endpoint → NIC → IP** | 10.1.2.5 | 10.1.2.5 | ✅ |
| **Agent VM → DNS Resolver → Response** | 10.1.2.5 (private) | 52.x.x.x (public) | ❌ MISMATCH |

**Root Cause Identified**:
```
[Example: Custom DNS Server (10.1.2.50) is configured with global forwarders pointing to Google DNS (8.8.8.8) 
without conditional forwarding rules for Azure Private Link zones. Query path: Agent VM → Custom DNS Server 
→ Google DNS (8.8.8.8) → returns public IP. Missing component: Custom DNS Server → Conditional Forwarder 
→ Azure Recursive Resolver (168.63.129.16) for zone privatelink.vaultcore.azure.net. Without this rule, 
Custom DNS Server never queries Azure Private DNS Zone, resulting in public IP resolution.]
```

---

### DNS Resolution Flow Diagrams

**Current (Broken) Flow**:
```
Agent VM → Custom DNS Server (10.1.2.50)
    → checks local zones (no match)
    → forwards to global forwarders (8.8.8.8 - Google DNS)
    → Google DNS queries public Azure DNS
    → returns public IP 52.x.x.x
    → Agent VM attempts connection to public IP
    → Key Vault firewall rejects (public access disabled)
```

**Expected (Working) Flow**:
```
Agent VM → Custom DNS Server (10.1.2.50)
    → checks local zones (no match)
    → checks zone-specific forwarding rules
    → finds rule: *.privatelink.vaultcore.azure.net → 168.63.129.16
    → forwards to Azure Recursive Resolver (168.63.129.16)
    → Azure DNS checks Private DNS Zone (linked to VNet)
    → Private DNS Zone → A Record returns 10.1.2.5
    → Agent VM connects to private IP successfully
```

---

### Network Architecture

**Key Components**:
- **Agent VNet**: 10.1.0.0/16 (contains Agent VM and Custom DNS Server)
- **Agent VM**: 10.1.1.x (uses Custom DNS Server for DNS)
- **Custom DNS Server**: 10.1.2.50 (BIND9, missing conditional forwarding)
- **Private Endpoint**: 10.1.2.5 (Key Vault private endpoint)
- **Azure Recursive Resolver**: 168.63.129.16 (only accessible from Azure VNets)
- **Private DNS Zone**: privatelink.vaultcore.azure.net (contains A record → 10.1.2.5)

[Optional: Attach architecture diagram screenshot]

---

### Critical DNS Concept: 168.63.129.16

**What is 168.63.129.16?**
- Azure's Wire Server / Recursive Resolver
- **ONLY** accessible from within Azure VNets (not from internet or on-premises)
- **ONLY** source for Azure Private DNS Zone resolution
- Required for Private Link DNS resolution

**Why Custom DNS Must Forward to 168.63.129.16:**
- Public DNS servers (Google, Cloudflare, etc.) have NO knowledge of Azure Private DNS Zones
- Azure Private DNS Zones exist ONLY in Azure's infrastructure
- Custom DNS servers in Azure VNets can reach 168.63.129.16 to query Private DNS Zones
- Without forwarding to 168.63.129.16, Private Link resolution is impossible

---

### Next Steps Requested

*For STEP 5 (initial request)*:
```
[Example: Requesting guidance on configuring conditional forwarding rules in BIND9 for Azure Private Link zones. 
Need validation that forwarding *.privatelink.* zones to 168.63.129.16 is the correct approach.]
```

*For STEP 10 (findings report)*:
```
[Example: I have identified that the Custom DNS Server lacks conditional forwarding rules for Azure Private Link zones. 
I plan to add the following BIND9 configuration:

zone "privatelink.vaultcore.azure.net" {
    type forward;
    forward only;
    forwarders { 168.63.129.16; };
};

Please confirm this approach is correct and whether additional zones (privatelink.blob.core.windows.net, etc.) 
should be configured similarly for other Azure services using Private Endpoints.]
```

---

### Additional Context

**Environment Details**:
- Azure Subscription: [ID or name]
- Azure DevOps Organization: [Org name]
- Agent Pool: DNS-Lab-Pool
- Agent OS: Ubuntu 22.04
- DNS Server OS: Ubuntu 22.04
- DNS Server Software: BIND9 9.18.x
- Pipeline: [Pipeline name]

**Custom DNS Server Management**:
- DNS Server IP: 10.1.2.50
- Administrator Contact: [If production: provide DNS admin team contact]
- Configuration Management: [Manual / Terraform / Ansible / etc.]
- Change Control Process: [If production: reference change ticket/approval]

**Business Impact**:
```
[Example: Pipeline deployments are blocked. Development team cannot deploy application updates 
until DNS resolution is fixed. Custom DNS server was recently deployed for centralized DNS 
management but Azure Private Link forwarding rules were not configured.]
```

---

### Special Considerations for Custom DNS

**Important Notes for Azure Support**:
1. Custom DNS server (10.1.2.50) is customer-managed infrastructure
2. Microsoft Support may provide configuration guidance but cannot directly modify customer DNS servers
3. DNS administrator with access to BIND9 configuration files will be required to implement fix
4. Testing should include querying 168.63.129.16 directly from DNS server to verify Azure DNS accessibility

**Questions for DNS Administrator Team**:
- [ ] Can the custom DNS server reach 168.63.129.16? (Test: `dig @168.63.129.16 google.com`)
- [ ] Are there firewall rules blocking UDP/TCP port 53 to 168.63.129.16?
- [ ] Is there a change control process for modifying BIND9 configuration?
- [ ] Should conditional forwarding be added for other `*.privatelink.*` zones?
- [ ] What is the rollback plan if conditional forwarding causes issues?

---

## Template Usage Instructions

1. **STEP 5** (Initial Request): Complete sections through "Troubleshooting Steps Completed (Initial)"
2. **STEP 7-9** (Data Collection): Add diagnostic evidence showing custom DNS misconfiguration
3. **STEP 10** (Findings Report): Complete comparison table and DNS flow diagrams
4. **Send to Instructor**: Copy completed template into email or support ticket

**Note**: Include DNS administrator team if this were production (custom DNS requires their involvement).

---

**Remember**: Custom DNS issues require collaboration with DNS administrator team. In production, Microsoft Azure Support provides guidance but cannot directly modify customer-managed DNS infrastructure. This template helps document findings for both Azure Support and your internal DNS team.
