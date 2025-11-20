#!/bin/bash
set -e

echo "Base Environment Validation"

KV_NAME=$(terraform output -raw key_vault_name)
VM_IP=$(terraform output -raw vm_public_ip)

if [ -z "$KV_NAME" ] || [ -z "$VM_IP" ]; then
  echo "Missing terraform outputs. Run 'terraform apply' first."; exit 1
fi

echo "Key Vault: $KV_NAME"
echo "VM IP: $VM_IP"

echo "Testing DNS resolution (local)..."
nslookup ${KV_NAME}.vault.azure.net || echo "Local resolution failed"

echo "Testing remote DNS + curl via SSH..."
SSH_KEY=~/.ssh/terraform_lab_key
if [ ! -f "$SSH_KEY" ]; then echo "SSH key $SSH_KEY missing"; exit 1; fi

ssh -o StrictHostKeyChecking=no -i "$SSH_KEY" azureuser@"$VM_IP" "nslookup ${KV_NAME}.vault.azure.net && curl -sv https://${KV_NAME}.vault.azure.net 2>&1 | grep -E 'Connected to|SSL certificate verify ok'" || echo "Remote tests failed"

echo "Validation complete."