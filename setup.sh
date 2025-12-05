#!/bin/bash

#######################################################################
# Azure DNS Lab - Master Setup Script
# Orchestrates the entire lab setup process
#######################################################################

set -e

# Logging
LOG_FILE="setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
        if ! command -v "$tool" &> /dev/null; then
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
    if ! az account show &> /dev/null; then
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
        if ! az devops project show --project "$ADO_PROJECT" --organization "$ADO_ORG_URL" &> /dev/null; then
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

deploy_infra() {
    echo -e "\n${BLUE}4️⃣  Deploying Infrastructure (Terraform)...${NC}"
    
    # Initialize if needed
    if [ ! -d ".terraform" ]; then
        echo "Initializing Terraform..."
        terraform init
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
        echo "Applying Terraform configuration..."
        # Variables now come from terraform.tfvars
        terraform apply -auto-approve
    fi
}

register_agent() {
    echo -e "\n${BLUE}5️⃣  Registering Agent...${NC}"
    ./scripts/register-agent.sh
}

setup_pipeline() {
    echo -e "\n${BLUE}6️⃣  Configuring Pipeline...${NC}"
    ./scripts/setup-pipeline.sh
}

validate_lab() {
    echo -e "\n${BLUE}7️⃣  Validating Lab Environment...${NC}"
    ./scripts/validate-base.sh
}

# --- Main Execution Flow ---

check_prereqs
check_azure_login
setup_ado
deploy_infra
register_agent
setup_pipeline
validate_lab

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              🎉 Lab Setup Complete!                        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "All infrastructure, agents, and pipelines are ready."
echo ""
echo -e "Next: See ${BLUE}labs/lab1/README.md${NC} to start Lab 1"
echo -e "Cleanup: Run ${BLUE}./destroy.sh${NC} when finished"
echo ""

