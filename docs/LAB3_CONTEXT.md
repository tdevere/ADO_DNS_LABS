# Lab 3 Planning: Pure DNS Scenario (VNet Link Only)

## Context
This file captures context for creating Lab 3 on a new branch in the future.

## Scenario Design
**Lab 3: Split-Horizon DNS - Missing VNet Link**

### Fault Injection
- **Only remove VNet link** from Private DNS Zone to VNet
- **Keep public network access enabled** on Key Vault

### Expected Behavior
- DNS resolution returns **public IPs** (13.66.x.x, 40.78.x.x) instead of private endpoint IP (10.1.2.5)
- Pipeline **may still succeed** if public endpoints are reachable
- Key learning: DNS split-horizon behavior and VNet link requirement

### Implementation Changes Needed

#### break-lab.sh lab3
```bash
lab3)
    echo "Injecting Lab 3 fault..."
    silent az network private-dns link vnet delete \
        --resource-group "$RG_NAME" --zone-name "$ZONE_NAME" --name "$VNET_LINK_NAME" --yes || true
    echo "✅ Lab 3 fault injected."
    echo ""
    echo "Next: Run diagnostic commands to observe DNS behavior."
    echo "Try: nslookup $KV_NAME.vault.azure.net from the agent VM"
    ;;
```

#### fix-lab.sh
- Use terraform apply to restore VNet link
- No special Key Vault public access handling needed

#### labs/lab3/README.md
**Title:** Split-Horizon DNS Configuration

**Overview:** Investigate DNS resolution inconsistencies where queries return public IPs instead of private endpoint addresses. Learn about Azure Private DNS VNet links and split-horizon DNS behavior.

**Scenario:** Private DNS zone exists with correct A records, but VNet is not linked to the zone. Clients fall back to Azure public DNS, resolving to public endpoints.

**Key Concepts:**
- Private DNS Zone VNet links
- Split-horizon DNS (public vs private resolution)
- DNS resolution path in Azure networking
- CNAME → A record resolution chain

**Diagnostic Focus:**
- Compare DNS results from VNet vs external clients
- Examine Private DNS Zone link status
- Verify A record configuration
- Understand fallback behavior

### Branch Strategy
1. Create new branch from `main`: `feature/lab3-dns-split-horizon`
2. Current `lab3` content moves to `lab4` on separate branch
3. Implement pure DNS scenario as described above

### Technical Notes
- Public access enabled means pipeline might succeed even with wrong IPs (if NSG/firewall allow)
- Consider adding NSG rule to block public Key Vault IPs to force observable failure
- Alternative: Monitor DNS resolution in pipeline and fail if public IP detected

### Related Files
- `break-lab.sh` - Add lab3 case
- `fix-lab.sh` - May not need special handling
- `labs/lab3/README.md` - New content focused on DNS
- `README.md` - Update module table with new Lab 3

### Success Criteria
Student should be able to:
1. Observe DNS returning public IPs via `nslookup`/`dig`
2. Compare with expected private IP
3. Identify missing VNet link in Private DNS Zone
4. Restore link and verify DNS now returns private IP
5. Understand split-horizon DNS concept
