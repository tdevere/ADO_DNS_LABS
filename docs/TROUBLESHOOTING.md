# Troubleshooting Guide

## Common Issues

- **Pipeline validation error (ConnectedServiceName not found)**
  - Cause: Service connection name mismatch or not authorized.
  - Fix: Ensure a service connection named `LabConnection` exists and is authorized for all pipelines.

- **Key Vault access fails**
  - `403 Forbidden` during curl is expected if not authenticated; SSL handshake success means network path is good.
  - Secret task fails: Verify access policy (non-RBAC) or RBAC role assignment for the service principal.

- **DNS returns public IP**
  - Cause: Private DNS zone not linked or record missing.
  - Fix: Check private DNS zone link, record, and VNet peering.

- **Git push fails with git-lfs hook**
  - Cause: Repo initialized with LFS, binary absent.
  - Fix: Disable hooks (`git config core.hookspath /dev/null`) or install `git-lfs`.

- **Azure DevOps CLI prompts for extension install**
  - Fix: Script auto-installs `azure-devops` extension. Re-run script.

## Verification Script

Run `./scripts/validate-base.sh` to confirm base lab health (DNS + KV connectivity).
