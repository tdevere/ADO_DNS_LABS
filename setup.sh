#!/bin/bash

#######################################################################
# Azure DNS Lab - Master Setup Script
# Orchestrates the entire lab setup process
#######################################################################

set -e

# Debug mode (enabled by default for better troubleshooting)
DEBUG=true
if [[ "$1" == "--quiet" ]]; then
    DEBUG=false
elif [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: $0 [--quiet]"
    echo ""
    echo "Azure DNS Lab Setup Script"
    echo ""
    echo "Options:"
    echo "  --quiet    Suppress verbose command output (not recommended)"
    echo "  --help     Show this help message"
    exit 0
fi

if [[ "$DEBUG" == "true" ]]; then
    echo "🐛 Verbose mode enabled (use --quiet to suppress)"
fi

# Logging
LOG_FILE="setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Timing
START_TIME=$(date +%s)

# Progress spinner
show_spinner() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(((i + 1) % 10))
        printf "\r${CYAN}${spin:$i:1} ${message}${NC}"
        sleep 0.1
    done
    printf "\r"
}

elapsed_time() {
    local end_time=$(date +%s)
    local elapsed=$((end_time - START_TIME))
    printf "${CYAN}[%02d:%02d elapsed]${NC}" $((elapsed / 60)) $((elapsed % 60))
}

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Azure DNS Lab Setup Wizard                       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo "Log file: $LOG_FILE"
echo ""

# --- Helper Functions ---

check_prereqs() {
    echo -e "${BLUE}1️⃣  Checking Prerequisites...${NC}"
    
    local missing_tools=0
    
    for tool in az terraform jq ssh; do
        if [[ "$DEBUG" == "true" ]]; then
            command -v "$tool" || true
        fi
        if ! command -v "$tool" > /dev/null 2>&1; then
            echo -e "${RED}❌ Missing tool: $tool${NC}"
            missing_tools=1
        else
            echo -e "${GREEN}✅ Found: $tool${NC}"
        fi
    done

    if [ $missing_tools -eq 1 ]; then
        echo -e "${RED}Please install missing tools and try again.${NC}"
        exit 1
    fi
}

check_azure_login() {
    echo -e "\n${BLUE}2️⃣  Checking Azure Login...${NC}"
    
    if [[ "$DEBUG" == "true" ]]; then
        echo "Running: az account show"
        az account show || LOGGED_IN=false
    else
        az account show > /dev/null 2>&1 || LOGGED_IN=false
    fi
    
    if [[ "${LOGGED_IN:-true}" == "false" ]]; then
        echo -e "${YELLOW}⚠️  Not logged in. Launching login...${NC}"
        
        # Load tenant from .ado.env if available
        if [ -f ".ado.env" ]; then
            source .ado.env
        fi
        
        if [ -n "$AZURE_TENANT" ]; then
            echo -e "${BLUE}Using tenant: $AZURE_TENANT${NC}"
            az login --tenant "$AZURE_TENANT" --use-device-code
        else
            az login --use-device-code
        fi
    fi
    
    SUB_NAME=$(az account show --query name -o tsv)
    SUB_ID=$(az account show --query id -o tsv)
    echo -e "${GREEN}✅ Logged in to: $SUB_NAME ($SUB_ID)${NC}"
}

setup_ado() {
    echo -e "\n${BLUE}3️⃣  Configuring Azure DevOps...${NC}"
    if [ -f ".ado.env" ]; then
        echo -e "${GREEN}✅ Found existing configuration (.ado.env)${NC}"
        source .ado.env
        
        # Set PAT for Azure DevOps CLI
        export AZURE_DEVOPS_EXT_PAT="$ADO_PAT"
        
        # Verify the project exists
        echo "Verifying ADO project exists..."
        if [[ "$DEBUG" == "true" ]]; then
            echo "Running: az devops project show --project '$ADO_PROJECT' --organization '$ADO_ORG_URL'"
            az devops project show --project "$ADO_PROJECT" --organization "$ADO_ORG_URL" || PROJECT_EXISTS=false
        else
            az devops project show --project "$ADO_PROJECT" --organization "$ADO_ORG_URL" > /dev/null 2>&1 || PROJECT_EXISTS=false
        fi
        
        if [[ "${PROJECT_EXISTS:-true}" == "false" ]]; then
            echo -e "${YELLOW}⚠️  Project '$ADO_PROJECT' not found. Running setup wizard...${NC}"
            ./scripts/setup-ado-org.sh
        else
            echo -e "${GREEN}✅ Project '$ADO_PROJECT' exists.${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  No configuration found. Starting ADO setup wizard...${NC}"
        ./scripts/setup-ado-org.sh
        if [ -f ".ado.env" ]; then
            source .ado.env
        else
            echo -e "${RED}❌ ADO setup failed or cancelled.${NC}"
            exit 1
        fi
    fi
}

generate_ssh_key() {
    echo -e "\n${BLUE}4️⃣  Generating SSH Key for VM Access...${NC}"
    ./scripts/generate-ssh-key.sh --force
    
    # Update terraform.tfvars with the public key
    SSH_PUB_KEY=$(cat "$HOME/.ssh/terraform_lab_key.pub")
    TFVARS_FILE="terraform.tfvars"
    
    if grep -q "^admin_ssh_key" "$TFVARS_FILE"; then
        # Escape special characters for sed
        ESCAPED_KEY=$(echo "$SSH_PUB_KEY" | sed 's|/|\\/|g')
        sed -i "s|^admin_ssh_key.*|admin_ssh_key = \"$ESCAPED_KEY\"|" "$TFVARS_FILE"
    else
        echo "admin_ssh_key = \"$SSH_PUB_KEY\"" >> "$TFVARS_FILE"
    fi
    echo -e "${GREEN}✅ SSH key configured in terraform.tfvars${NC}"
}

deploy_infra() {
    echo -e "\n${BLUE}5️⃣  Deploying Infrastructure (Terraform)...${NC}"
    local step_start=$(date +%s)
    
    # Initialize if needed
    if [ ! -d ".terraform" ]; then
        echo -e "${CYAN}→ Initializing Terraform (downloading providers)...${NC}"
        terraform init | grep -E '(Initializing|Installing|Terraform has been)' || terraform init
        echo -e "${GREEN}  ✓ Terraform initialized${NC}"
    fi

    # Update terraform.tfvars with ADO variables from .ado.env
    echo "Updating terraform.tfvars with ADO configuration..."
    TFVARS_FILE="terraform.tfvars"
    
    # Update ado_org_url
    if grep -q "^ado_org_url" "$TFVARS_FILE"; then
        sed -i "s|^ado_org_url.*|ado_org_url = \"$ADO_ORG_URL\"|" "$TFVARS_FILE"
    else
        echo "ado_org_url = \"$ADO_ORG_URL\"" >> "$TFVARS_FILE"
    fi
    
    # Update ado_pat
    if grep -q "^ado_pat" "$TFVARS_FILE"; then
        sed -i "s|^ado_pat.*|ado_pat = \"$ADO_PAT\"|" "$TFVARS_FILE"
    else
        echo "ado_pat = \"$ADO_PAT\"" >> "$TFVARS_FILE"
    fi
    
    # Update ado_pool_name
    if grep -q "^ado_pool_name" "$TFVARS_FILE"; then
        sed -i "s|^ado_pool_name.*|ado_pool_name = \"$ADO_POOL\"|" "$TFVARS_FILE"
    else
        echo "ado_pool_name = \"$ADO_POOL\"" >> "$TFVARS_FILE"
    fi

    # Check if already applied
    if terraform state list | grep -q "azurerm_virtual_machine"; then
        echo -e "${GREEN}✅ Infrastructure appears to be deployed.${NC}"
    else
        echo -e "${CYAN}→ Planning infrastructure deployment...${NC}"
        if [[ "$DEBUG" == "true" ]]; then
            terraform plan -out=tfplan -detailed-exitcode || true
        else
            terraform plan -out=tfplan -detailed-exitcode -compact-warnings > /dev/null 2>&1 || true
        fi
        
        RESOURCE_COUNT=$(terraform show -json tfplan 2>/dev/null | jq -r '.resource_changes | length' 2>/dev/null || echo "unknown")
        echo -e "${CYAN}→ Deploying $RESOURCE_COUNT Azure resources (this takes ~5-7 minutes)${NC}"
        echo -e "${CYAN}  Resources: Resource Group, VNet, Subnet, NSGs, Key Vault, Private Endpoint, DNS Zone, VM...${NC}"
        
        # Show progress during apply
        terraform apply -auto-approve tfplan 2>&1 | while read line; do
            if [[ $line == *"Creating..."* ]] || [[ $line == *"Creation complete"* ]] || [[ $line == *"Still creating"* ]]; then
                echo -e "${CYAN}  $line${NC}"
            elif [[ $line == *"Apply complete"* ]]; then
                echo -e "${GREEN}  $line${NC}"
            fi
        done
        
        local step_end=$(date +%s)
        local step_elapsed=$((step_end - step_start))
        echo -e "${GREEN}  ✓ Infrastructure deployed in ${step_elapsed}s${NC}"
    fi
}

register_agent() {
    echo -e "\n${BLUE}6️⃣  Registering Agent...${NC}"
    local step_start=$(date +%s)
    echo -e "${CYAN}→ Configuring self-hosted agent on VM (2-3 minutes)${NC}"
    echo -e "${CYAN}  Steps: Download agent → Install → Register → Start service${NC}"
    
    ./scripts/register-agent.sh 2>&1 | grep -E '(Configuring|Downloading|Installing|Registered|Started)' || ./scripts/register-agent.sh
    
    local step_end=$(date +%s)
    local step_elapsed=$((step_end - step_start))
    echo -e "${GREEN}  ✓ Agent registered in ${step_elapsed}s${NC}"
}

setup_pipeline() {
    echo -e "\n${BLUE}7️⃣  Configuring Pipeline...${NC}"
    local step_start=$(date +%s)
    echo -e "${CYAN}→ Creating Azure DevOps service connection and pipeline${NC}"
    
    ./scripts/setup-pipeline.sh
    
    local step_end=$(date +%s)
    local step_elapsed=$((step_end - step_start))
    echo -e "${GREEN}  ✓ Pipeline configured in ${step_elapsed}s${NC}"
}

validate_lab() {
    echo -e "\n${BLUE}8️⃣  Validating Lab Environment...${NC}"
    ./scripts/validate-base.sh
}

show_ssh_info() {
    echo -e "\n${GREEN}🔑 SSH Access Information:${NC}"
    echo -e "Private key location: ${BLUE}~/.ssh/terraform_lab_key${NC}"
    echo -e "To SSH into VMs: ${BLUE}ssh -i ~/.ssh/terraform_lab_key azureuser@<VM_IP>${NC}"
    echo ""
}

# --- Main Execution Flow ---

check_prereqs
check_azure_login
setup_ado
generate_ssh_key
deploy_infra
register_agent
setup_pipeline
validate_lab
show_ssh_info

TOTAL_TIME=$(($(date +%s) - START_TIME))
MINUTES=$((TOTAL_TIME / 60))
SECONDS=$((TOTAL_TIME % 60))

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              🎉 Lab Setup Complete!                        ║${NC}"
echo -e "${GREEN}║           Total time: ${MINUTES}m ${SECONDS}s                              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "All infrastructure, agents, and pipelines are ready."
echo ""
echo -e "Next: See ${BLUE}labs/lab1/README.md${NC} to start Lab 1"
echo -e "Cleanup: Run ${BLUE}./destroy.sh${NC} when finished"
echo ""

