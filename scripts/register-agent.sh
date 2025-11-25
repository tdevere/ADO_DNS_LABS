#!/bin/bash

#######################################################################
# Post-Deployment Agent Registration
# Configures the self-hosted agent on the deployed VM
#######################################################################

set -e

# Colors
GREEN=''
YELLOW=''
RED=''
BLUE=''
NC=''


# Load config if exists
if [ -f ".ado.env" ]; then
    source .ado.env
fi

echo -e "${BLUE}Agent Registration Wizard${NC}\n"

# 1. Gather Information
if [[ -z "$ADO_ORG_URL" ]]; then
    read -p "Enter Azure DevOps Org URL: " ADO_ORG_URL
fi

if [[ -z "$ADO_PAT" ]]; then
    read -s -p "Enter PAT: " ADO_PAT
    echo ""
fi

if [[ -z "$ADO_POOL" ]]; then
    read -p "Enter Agent Pool Name [Default: DNS-Lab-Pool]: " ADO_POOL
    ADO_POOL=${ADO_POOL:-DNS-Lab-Pool}
fi

# Get VM IP from Terraform if possible
VM_IP=""
if [ -f "terraform.tfstate" ]; then
    echo "Attempting to get VM IP from Terraform..."
    VM_IP=$(terraform output -raw vm_public_ip 2>/dev/null || echo "")
fi

if [[ -z "$VM_IP" ]]; then
    read -p "Enter Agent VM Public IP: " VM_IP
else
    echo -e "Found VM IP: ${YELLOW}$VM_IP${NC}"
    read -p "Is this correct? (y/n): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        read -p "Enter Agent VM Public IP: " VM_IP
    fi
fi

SSH_KEY_PATH="$HOME/.ssh/terraform_lab_key"
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}❌ ERROR: SSH key not found at $SSH_KEY_PATH${NC}"
    echo -e "${YELLOW}The SSH key may not have been generated or the VM was recreated with a different key.${NC}"
    echo ""
    echo "To fix this issue:"
    echo "1. Check if the key exists in Terraform state:"
    echo "   terraform output -raw ssh_private_key"
    echo ""
    echo "2. If the VM was recreated, regenerate the SSH key:"
    echo "   ./scripts/generate-ssh-key.sh"
    echo "   # Update terraform.tfvars with the new public key"
    echo "   terraform apply -auto-approve"
    echo ""
    echo "3. Or manually copy the private key from terraform.tfstate:"
    echo "   terraform output -raw ssh_private_key > $SSH_KEY_PATH"
    echo "   chmod 600 $SSH_KEY_PATH"
    exit 1
fi

# Validate SSH key permissions
if [ "$(stat -c %a "$SSH_KEY_PATH" 2>/dev/null || stat -f %A "$SSH_KEY_PATH" 2>/dev/null)" != "600" ]; then
    echo -e "${YELLOW}⚠️  Warning: SSH key has incorrect permissions. Fixing...${NC}"
    chmod 600 "$SSH_KEY_PATH"
fi

# Test SSH connectivity before attempting agent registration
echo -e "${BLUE}Testing SSH connectivity to $VM_IP...${NC}"
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes -i "$SSH_KEY_PATH" "azureuser@$VM_IP" "echo 'SSH OK'" 2>/dev/null; then
    echo -e "${RED}❌ ERROR: Cannot connect to VM via SSH${NC}"
    echo -e "${YELLOW}This usually means:${NC}"
    echo "  1. The SSH public key in terraform.tfvars doesn't match the private key at $SSH_KEY_PATH"
    echo "  2. The VM was recreated but the SSH key wasn't updated"
    echo "  3. The VM's public IP changed"
    echo ""
    echo "Diagnostic steps:"
    echo "1. Verify the VM is running:"
    echo "   az vm show --resource-group <rg> --name <vm-name> --query 'provisioningState'"
    echo ""
    echo "2. Check the current public IP:"
    echo "   terraform output -raw vm_public_ip"
    echo ""
    echo "3. Verify SSH key fingerprint matches:"
    echo "   ssh-keygen -lf $SSH_KEY_PATH"
    echo "   az vm show --resource-group <rg> --name <vm-name> --query 'osProfile.linuxConfiguration.ssh.publicKeys[0].keyData' -o tsv | ssh-keygen -lf -"
    echo ""
    echo "4. If keys don't match, regenerate and redeploy:"
    echo "   ./scripts/generate-ssh-key.sh"
    echo "   # Update terraform.tfvars with new public key"
    echo "   terraform apply -auto-approve"
    exit 1
fi

echo -e "${GREEN}✓ SSH connectivity verified${NC}"

# 2. Prepare Agent Script
AGENT_NAME="dns-lab-agent-$(date +%s)"
echo -e "\n${BLUE}Configuring agent '$AGENT_NAME' on $VM_IP...${NC}"

# We will run this script on the remote VM
# Note: The agent is already downloaded by cloud-init to /home/azureuser/azagent
REMOTE_SCRIPT=$(cat <<EOF
set -e
echo "--> Configuring Agent..."
mkdir -p /home/azureuser/azagent
cd /home/azureuser/azagent

# Download agent if not present (cloud-init might have failed due to DNS)
if [ ! -f "config.sh" ]; then
    echo "Agent not found. Downloading..."
    curl -O https://download.agent.dev.azure.com/agent/4.264.2/vsts-agent-linux-x64-4.264.2.tar.gz
    tar zxvf vsts-agent-linux-x64-4.264.2.tar.gz
fi

# Check if already configured
if [ -f ".agent" ]; then
    echo "Agent already configured. Removing old config..."
    sudo ./svc.sh stop || true
    sudo ./svc.sh uninstall || true
    ./config.sh remove --auth pat --token "$ADO_PAT" || true
fi

# Configure
echo "--> Running config.sh..."
./config.sh --unattended \
  --url "$ADO_ORG_URL" \
  --auth pat --token "$ADO_PAT" \
  --pool "$ADO_POOL" \
  --agent "$AGENT_NAME" \
  --replace \
  --acceptTeeEula

# Install and Start Service
echo "--> Installing Service..."
sudo ./svc.sh install
echo "--> Starting Service..."
sudo ./svc.sh start

echo "--> Agent Status:"
sudo ./svc.sh status
EOF
)

# 3. Execute on VM
echo "Connecting via SSH..."
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "azureuser@$VM_IP" "$REMOTE_SCRIPT"

echo -e "\n${GREEN}[OK] Agent registered successfully!${NC}"
echo "You can now run pipelines targeting the '$ADO_POOL' pool."
