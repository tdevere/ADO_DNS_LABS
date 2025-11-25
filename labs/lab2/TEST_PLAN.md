# Lab 2 Testing Checklist

## Pre-deployment Tests
- [ ] Terraform plan shows VNet link will be created
- [ ] Base infrastructure deploys successfully
- [ ] Pipeline runs and passes (green)

## Break Scenario Tests
- [ ] `./break-lab.sh lab2` completes without error
- [ ] VNet link is deleted (verify in Portal or CLI)
- [ ] `./scripts/verify-lab.sh lab2` shows "No VNet links"
- [ ] `nslookup` from VM returns public IP
- [ ] Pipeline fails at KeyVault Access stage

## Student Investigation Path
- [ ] README instructions are clear
- [ ] Students can identify the public IP symptom
- [ ] CLI commands in README execute successfully
- [ ] Diagnostic outputs match expected values in README
- [ ] Students can articulate why DNS falls back to public

## Fix Scenario Tests
### Hotfix Path (Azure CLI)
- [ ] Manual `az network private-dns link vnet create` succeeds
- [ ] DNS resolution changes to private IP
- [ ] Pipeline re-run succeeds

### IaC Path
- [ ] `./fix-lab.sh lab2` completes successfully
- [ ] VNet link is restored
- [ ] Terraform state is consistent
- [ ] Pipeline re-run succeeds

## Verification Tests
- [ ] `./scripts/verify-lab.sh lab2` shows "VNet link exists"
- [ ] `nslookup` returns 10.1.2.x IP
- [ ] curl/wget to Key Vault succeeds (or fails with 403 auth error, which is expected)
- [ ] Pipeline all stages green

## Documentation Tests
- [ ] No broken links in README
- [ ] Code blocks are properly formatted
- [ ] Mermaid diagram renders correctly
- [ ] Learning objectives are clear

## Edge Cases
- [ ] Can break Lab 2 while Lab 1 is broken
- [ ] Can switch from Lab 2 to Lab 1 and back
- [ ] Fix script handles "link already exists" gracefully
- [ ] Break script handles "link already deleted" gracefully

## Integration Tests
- [ ] Lab 2 doesn't interfere with Lab 1 functionality
- [ ] Can cycle: base → lab1 → base → lab2 → base
- [ ] No orphaned resources after fix
- [ ] Terraform state remains consistent across lab switches

## Time Estimation
- [ ] Fresh student can complete in 45-60 minutes
- [ ] Investigation steps are achievable without hints
- [ ] Fix verification is clear and unambiguous
