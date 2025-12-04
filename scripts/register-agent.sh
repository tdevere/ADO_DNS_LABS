#!/bin/bash

#######################################################################
# Post-Deployment Agent Registration
# Configures the self-hosted agent on the deployed VM
#######################################################################

set -e

# Determine script location and repo root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'


# Load config if exists
if [ -f "$REPO_ROOT/.ado.env" ]; then
    source "$REPO_ROOT/.ado.env"
fi

echo -e "${BLUE}Agent Registration Wizard${NC}
"

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
if [ -f "$REPO_ROOT/terraform.tfstate" ]; then
    echo "Attempting to get VM IP from Terraform..."
    VM_IP=$(cd "$REPO_ROOT" && terraform output -raw vm_public_ip 2>/dev/null || echo "")
fi

if [[ -z "$VM_IP" ]]; then
    read -p "Enter Agent VM Public IP: " VM_IP
else
    echo -e "Found VM IP: ${YELLOW}$VM_IP${NC}"
    # Auto-confirm if running in non-interactive mode or just proceed
    # read -p "Is this correct? (y/n): " -n 1 -r
    # echo ""
    # if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    #     read -p "Enter Agent VM Public IP: " VM_IP
    # fi
fi

SSH_KEY_PATH="$HOME/.ssh/terraform_lab_key"
SSH_PUB_KEY_PATH="${SSH_KEY_PATH}.pub"

# Ensure we have a key pair; auto-generate if missing
if [ ! -f "$SSH_KEY_PATH" ] || [ ! -f "$SSH_PUB_KEY_PATH" ]; then
    echo -e "${YELLOW}⚠️  SSH key pair missing. Generating automatically...${NC}"
    "$SCRIPT_DIR/generate-ssh-key.sh" --force >/dev/null 2>&1 || { echo -e "${RED}❌ Failed to generate SSH key${NC}"; exit 1; }
fi

# Extract public key content
LOCAL_PUB_KEY="$(cat "$SSH_PUB_KEY_PATH" 2>/dev/null || echo '')"
if [ -z "$LOCAL_PUB_KEY" ]; then
    echo -e "${RED}❌ ERROR: Unable to read local public key${NC}"
    exit 1
fi

# Read terraform.tfvars public key value
TFVARS_FILE="$REPO_ROOT/terraform.tfvars"
TFVARS_PUB_KEY="$(grep -E '^admin_ssh_key' "$TFVARS_FILE" 2>/dev/null | sed 's/admin_ssh_key\s*=\s*"//; s/"\s*$//')"

if [ -z "$TFVARS_PUB_KEY" ]; then
    echo -e "${YELLOW}⚠️  admin_ssh_key not found in terraform.tfvars. Inserting current key...${NC}"
    echo "admin_ssh_key = \"$LOCAL_PUB_KEY\"" >> "$TFVARS_FILE"
    TFVARS_PUB_KEY="$LOCAL_PUB_KEY"
fi

# If mismatch, auto-repair tfvars and re-apply Terraform to push new key
if [ "$TFVARS_PUB_KEY" != "$LOCAL_PUB_KEY" ]; then
    echo -e "${YELLOW}⚠️  Public key mismatch between local key and terraform.tfvars. Auto-repairing...${NC}"
    cp "$TFVARS_FILE" "${TFVARS_FILE}.bak_$(date +%s)"
    # Replace line
    sed -i "s|^admin_ssh_key.*|admin_ssh_key = \"$LOCAL_PUB_KEY\"|" "$TFVARS_FILE"
    echo -e "${BLUE}Applying Terraform to update VM authorized key...${NC}"
    cd "$REPO_ROOT"
    terraform apply -auto-approve -lock=false >/dev/null 2>&1 || {
        echo -e "${RED}❌ Terraform apply failed while updating SSH key${NC}"; exit 1; }
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✓ VM SSH key updated via Terraform${NC}"
fi

# Re-fetch VM IP after potential apply
VM_IP=$(cd "$REPO_ROOT" && terraform output -raw vm_public_ip 2>/dev/null || echo "$VM_IP")

chmod 600 "$SSH_KEY_PATH" 2>/dev/null || true
chmod 644 "$SSH_PUB_KEY_PATH" 2>/dev/null || true


# Test SSH connectivity before attempting agent registration
echo -e "${BLUE}Testing SSH connectivity to $VM_IP...${NC}"
if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 -o BatchMode=yes -i "$SSH_KEY_PATH" "azureuser@$VM_IP" "echo 'SSH OK'" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Direct SSH failed. Attempting automated recovery...${NC}"
    RG_NAME="$(terraform output -raw resource_group_name 2>/dev/null || echo '')"
    VM_NAME="$(terraform output -raw vm_name 2>/dev/null || echo '')"
    if [ -z "$VM_NAME" ]; then
        # Fallback: discover VM by public IP
        VM_NAME=$(az vm list -d --query "[?publicIps=='$VM_IP'].name | [0]" -o tsv 2>/dev/null || echo "")
    fi
    if [ -z "$RG_NAME" ] || [ -z "$VM_NAME" ]; then
        echo -e "${RED}❌ Unable to determine VM name/resource group for key injection${NC}"
        echo " RG: '$RG_NAME'  VM: '$VM_NAME'"
        echo "Run: terraform output resource_group_name && terraform output vm_name"
        exit 1
    fi
    echo -e "${BLUE}Using VM '$VM_NAME' in resource group '$RG_NAME' for key injection${NC}"
    INJECT_SCRIPT="set -e; mkdir -p /home/azureuser/.ssh; touch /home/azureuser/.ssh/authorized_keys; grep -q '${LOCAL_PUB_KEY}' /home/azureuser/.ssh/authorized_keys || echo '${LOCAL_PUB_KEY}' >> /home/azureuser/.ssh/authorized_keys; chmod 700 /home/azureuser/.ssh; chmod 600 /home/azureuser/.ssh/authorized_keys"
    if az vm run-command invoke --command-id RunShellScript --name "$VM_NAME" --resource-group "$RG_NAME" --scripts "$INJECT_SCRIPT" >/dev/null 2>&1; then
        sleep 6
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 -o BatchMode=yes -i "$SSH_KEY_PATH" "azureuser@$VM_IP" "echo 'SSH OK'" 2>/dev/null; then
            echo -e "${GREEN}✓ SSH connectivity restored via run-command injection${NC}"
        else
            echo -e "${RED}❌ SSH still failing after injection${NC}"
            echo "Diagnostics:"
            echo "  az vm get-instance-view -n $VM_NAME -g $RG_NAME --query instanceView.statuses"
            echo "  az network nsg show -g $RG_NAME -n ${VM_NAME}-nsg"
            echo "Consider full rebuild: terraform apply -replace=azurerm_linux_virtual_machine.vm"
            exit 1
        fi
    else
        echo -e "${RED}❌ Failed run-command key injection${NC}"
        echo "Check az login and permissions: az account show"
        echo "Manual fix: 'az vm run-command invoke' with a simple echo of the key."
        exit 1
    fi
else
    echo -e "${GREEN}✓ SSH connectivity verified${NC}"
fi

echo -e "${GREEN}✓ Proceeding with agent configuration${NC}"

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
    echo "Agent already configured. Removing old agent from Azure DevOps and VM..."
    
    # First, try to deregister from Azure DevOps (graceful removal)
    if [ -f ".agent" ]; then
        AGENT_ID=\$(cat .agent | grep -oP '(?<="agentId":)\d+' || echo "")
        if [ -n "\$AGENT_ID" ]; then
            echo "Deregistering agent ID \$AGENT_ID from Azure DevOps..."
            # Attempt graceful removal via config.sh --remove if config exists
            if [ -f "config.sh" ]; then
                ./config.sh remove --unattended --auth pat --token "$ADO_PAT" 2>/dev/null || true
            fi
        fi
    fi
    
    # Find and stop all agent services
    for svc in /etc/systemd/system/vsts.agent.*.service; do
        if [ -f "\$svc" ]; then
            sudo systemctl stop "\$(basename \$svc)" 2>/dev/null || true
            sudo systemctl disable "\$(basename \$svc)" 2>/dev/null || true
            sudo rm -f "\$svc" || true
        fi
    done
    sudo systemctl daemon-reload || true
    
    # Remove local agent config and state files
    rm -f .agent .credentials .credentials_rsaparams .runner .path .env .service || true
    rm -rf _diag _work || true
    
    echo "Old agent removed. Proceeding with fresh registration..."
fi

# Configure
echo "--> Running config.sh..."
echo "Y" | ./config.sh --unattended \
  --url "$ADO_ORG_URL" \
  --auth pat --token "$ADO_PAT" \
  --pool "$ADO_POOL" \
  --agent "$AGENT_NAME" \
  --replace \
  --acceptteeeula

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
