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
    echo -e "${RED}[FAIL] SSH key not found at $SSH_KEY_PATH${NC}"
    exit 1
fi

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
