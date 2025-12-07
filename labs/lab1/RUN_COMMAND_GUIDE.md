# Azure VM Run Command: Alternative to SSH

## What is `az vm run-command`?

Azure VM Run Command allows you to execute scripts on Azure VMs through the Azure control plane (ARM API) without requiring direct network access or SSH credentials. This is useful when troubleshooting VMs that have no public IP, blocked SSH ports, or strict security policies.

---

## When to Use This Method

### ✅ Use `az vm run-command` when:
- **No SSH access** - Customer security policy blocks SSH/RDP
- **No public IP** - VM only has private IP and no Bastion configured
- **Compliance requirements** - Need audit trail for every command (logged in Azure Activity Log)
- **SSH is broken** - Network issues prevent SSH connectivity (the very problem you're troubleshooting)
- **Quick one-off checks** - Need to run a single diagnostic command without full session

### ❌ Don't use `az vm run-command` when:
- **Interactive troubleshooting needed** - Multiple commands, editors, or tools like `tcpdump`
- **Speed matters** - SSH is much faster for iterative diagnostics
- **SSH already available** - If you have SSH access, use it (more efficient)

---

## Example: Test DNS Resolution from Agent VM

### Scenario
You need to see what IP the agent VM resolves for the Key Vault FQDN, but:
- The VM has no public IP
- Customer hasn't configured Bastion
- Security policy blocks SSH access from external networks
- You have Azure RBAC permissions (Contributor or Virtual Machine Contributor)

### Command

```bash
# Get resource details
RG_NAME=$(az group list --query "[?contains(name, 'rg-dns-lab')].name" -o tsv)
VM_NAME=$(az vm list --resource-group "$RG_NAME" --query "[?contains(name, 'agent')].name" -o tsv)
KV_NAME=$(az keyvault list --resource-group "$RG_NAME" --query "[0].name" -o tsv)

# Run nslookup on the agent VM without SSH
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "nslookup ${KV_NAME}.vault.azure.net"
```

### Example Output

```json
{
  "value": [
    {
      "code": "ProvisioningState/succeeded",
      "displayStatus": "Provisioning succeeded",
      "level": "Info",
      "message": "Enable succeeded: \n[stdout]\nServer:\t\t127.0.0.53\nAddress:\t127.0.0.53#53\n\nNon-authoritative answer:\nName:\tkv-dns-lab-c4cbb3dd.vault.azure.net\nAddress: 10.1.2.50\n\n[stderr]\n",
      "time": null
    }
  ]
}
```

**Parse the output:**
```bash
# Extract just the DNS resolution result
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "nslookup ${KV_NAME}.vault.azure.net" \
  --query "value[0].message" -o tsv | grep "Address:"
```

**Result:**
```
Address: 10.1.2.50
```

---

## Comparison: Run Command vs SSH

| Aspect | `az vm run-command invoke` | SSH (`ssh azureuser@<ip>`) |
|--------|---------------------------|---------------------------|
| **Access Required** | ✅ Azure RBAC only (Contributor) | ❌ SSH key + NSG rule allowing port 22 |
| **No Public IP Needed** | ✅ Works through Azure ARM API | ❌ Requires public IP or Bastion/VPN |
| **Audit Trail** | ✅ Logged in Azure Activity Log | ⚠️ May not be logged (depends on VM config) |
| **Compliance Friendly** | ✅ No credential sharing | ❌ Requires sharing SSH private key |
| **Speed** | ⚠️ Slower (15-30 seconds per command) | ✅ Fast (interactive, <1 second) |
| **Interactive** | ❌ One-off commands only | ✅ Full shell session, tab completion |
| **Multi-step Debugging** | ❌ Must send new command each time | ✅ Run multiple commands quickly |
| **Interactive Tools** | ❌ Can't use `tcpdump`, `top -c`, editors | ✅ Full control over VM environment |
| **Works When SSH Broken** | ✅ Independent of VM networking | ❌ Fails if NSG blocks or network down |
| **Cost** | ✅ Free (part of VM service) | ✅ Free (if you have access) |

---

## Additional Examples

### Check DNS Server Configuration
```bash
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "cat /etc/resolv.conf"
```

### Test Connectivity to Private Endpoint
```bash
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "curl -v https://${KV_NAME}.vault.azure.net"
```

### Check Network Routes
```bash
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "ip route show"
```

### Collect Multiple Diagnostics at Once
```bash
az vm run-command invoke \
  --resource-group "$RG_NAME" \
  --name "$VM_NAME" \
  --command-id RunShellScript \
  --scripts "
    echo '=== DNS Configuration ==='
    cat /etc/resolv.conf
    echo ''
    echo '=== DNS Resolution ==='
    nslookup ${KV_NAME}.vault.azure.net
    echo ''
    echo '=== Connectivity Test ==='
    curl -v -m 5 https://${KV_NAME}.vault.azure.net 2>&1 | head -20
  "
```

---

## Limitations & Workarounds

### Limitation 1: Slow Execution
- **Problem:** Each command takes 15-30 seconds to execute
- **Workaround:** Combine multiple commands in one script block (see example above)

### Limitation 2: Not Interactive
- **Problem:** Can't use interactive tools like `vim`, `less`, `top`
- **Workaround:** Use non-interactive alternatives (`cat`, `grep`, `ps aux`)

### Limitation 3: Limited Output
- **Problem:** Output may be truncated for very long responses
- **Workaround:** Redirect output to a file, then read the file in chunks:
  ```bash
  # Write diagnostic output to file
  az vm run-command invoke ... --scripts "tcpdump -i eth0 -c 100 > /tmp/capture.txt 2>&1"
  
  # Read the file in chunks
  az vm run-command invoke ... --scripts "head -50 /tmp/capture.txt"
  ```

### Limitation 4: Requires Azure Permissions
- **Problem:** Need Virtual Machine Contributor role or higher
- **Workaround:** Request temporary elevated access, or use Pipeline Logs method instead

---

## Security Considerations

### ✅ Advantages
1. **No credential exposure** - No SSH keys transmitted or stored
2. **Audit trail** - Every command logged in Azure Activity Log with timestamp and user identity
3. **Network-independent** - Works even if VM networking is completely broken
4. **RBAC-controlled** - Permissions managed through Azure AD/Entra ID

### ⚠️ Risks
1. **Privilege escalation** - User with VM Contributor can run commands as root
2. **Command logging** - Avoid passing secrets in `--scripts` parameter (will be logged)
3. **No session isolation** - Commands run as root, can modify system state

**Best Practice:** Use for read-only diagnostics during troubleshooting. For configuration changes, prefer IaC or change management processes.

---

## When to Recommend This to Customers

| Customer Scenario | Recommendation |
|-------------------|----------------|
| "We can't SSH to production VMs" | ✅ **Use Run Command** - Provides diagnostics without SSH |
| "We need audit logs for compliance" | ✅ **Use Run Command** - All commands logged in Activity Log |
| "The VM has no public IP and no Bastion" | ✅ **Use Run Command** - Works through ARM API |
| "I need to troubleshoot multiple things interactively" | ❌ **Recommend Azure Bastion instead** - Better UX for deep troubleshooting |
| "SSH is working fine" | ❌ **Use SSH** - Faster and more flexible |
| "I need to run tcpdump or live monitoring" | ⚠️ **SSH or Serial Console better** - Run Command not ideal for long-running tools |

---

## Resources

- **Official Docs:** [Run scripts in your VM by using action Run Commands](https://learn.microsoft.com/en-us/azure/virtual-machines/run-command-overview)
- **Azure CLI Reference:** [`az vm run-command`](https://learn.microsoft.com/en-us/cli/azure/vm/run-command)
- **Supported Commands:** `RunShellScript` (Linux), `RunPowerShellScript` (Windows)
