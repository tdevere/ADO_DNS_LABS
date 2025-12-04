#!/bin/bash

#######################################################################
# Azure DNS Lab - Destroy Script
# Removes all lab resources created by setup.sh
# Mirrors the setup process in reverse
#######################################################################

set -e

# Logging
LOG_FILE="destroy.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Azure DNS Lab - Destroy (Cleanup) Script            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo "Log file: $LOG_FILE"
echo ""

# --- Helper Functions ---

check_prereqs() {
    echo -e "${BLUE}1️⃣  Checking Prerequisites...${NC}"
    
    local missing_tools=0
    
    for tool in az terraform jq; do
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
        az login --use-device-code
    fi
    
    SUB_NAME=$(az account show --query name -o tsv)
    SUB_ID=$(az account show --query id -o tsv)
    echo -e "${GREEN}✅ Logged in to: $SUB_NAME ($SUB_ID)${NC}"
}

load_ado_config() {
    echo -e "\n${BLUE}3️⃣  Loading ADO Configuration...${NC}"
    if [ ! -f ".ado.env" ]; then
        echo -e "${RED}❌ Configuration file .ado.env not found.${NC}"
        echo -e "${YELLOW}   Run ./setup.sh first to create the lab.${NC}"
        exit 1
    fi
    
    source .ado.env
    echo -e "${GREEN}✅ Loaded configuration from .ado.env${NC}"
    echo -e "   Organization: $ADO_ORG_URL"
    echo -e "   Project: $ADO_PROJECT"
    echo -e "   Pool: $ADO_POOL"
}

confirm_destruction() {
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                    ⚠️  WARNING ⚠️                          ║${NC}"
    echo -e "${RED}║         This will PERMANENTLY DELETE all lab resources    ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "This operation will remove:"
    echo "  • Azure Infrastructure (VMs, VNets, Key Vaults, etc.)"
    echo "  • ADO Pipeline and Service Connections"
    echo "  • ADO Agent Pool"
    echo "  • ADO Project"
    echo "  • Terraform state"
    echo ""
    read -p "Are you ABSOLUTELY SURE you want to continue? Type 'destroy' to confirm: " -r
    echo
    if [[ ! $REPLY == "destroy" ]]; then
        echo -e "${YELLOW}Destruction cancelled. No resources were removed.${NC}"
        exit 0
    fi
}

destroy_ado_resources() {
    echo -e "\n${BLUE}4️⃣  Removing ADO Resources...${NC}"
    
    # Remove Pipeline
    echo "Removing pipeline..."
    PIPELINE_ID=$(az pipelines list \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" \
        --query "[?name=='DNS-Lab-Pipeline'].id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$PIPELINE_ID" ]; then
        az pipelines delete \
            --organization "$ADO_ORG_URL" \
            --project "$ADO_PROJECT" \
            --id "$PIPELINE_ID" \
            --yes 2>/dev/null || true
        echo -e "${GREEN}✅ Pipeline removed${NC}"
    else
        echo -e "${YELLOW}⏭️  Pipeline not found (already removed)${NC}"
    fi
    
    # Remove Service Connections
    echo "Removing service connections..."
    SC_LIST=$(az devops service-endpoint list \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" \
        --query "[?starts_with(name, 'SC-DNSLAB-')].id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$SC_LIST" ]; then
        while IFS= read -r SC_ID; do
            if [ -n "$SC_ID" ]; then
                az devops service-endpoint delete \
                    --organization "$ADO_ORG_URL" \
                    --project "$ADO_PROJECT" \
                    --id "$SC_ID" \
                    --yes 2>/dev/null || true
            fi
        done <<< "$SC_LIST"
        echo -e "${GREEN}✅ Service connections removed${NC}"
    else
        echo -e "${YELLOW}⏭️  No service connections found${NC}"
    fi
    
    # Remove Agent Pool
    echo "Removing agent pool..."
    POOL_ID=$(az pipelines pool list \
        --organization "$ADO_ORG_URL" \
        --query "[?name=='$ADO_POOL'].id" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$POOL_ID" ]; then
        az pipelines pool delete \
            --id "$POOL_ID" \
            --yes 2>/dev/null || true
        echo -e "${GREEN}✅ Agent pool removed${NC}"
    else
        echo -e "${YELLOW}⏭️  Agent pool not found (already removed)${NC}"
    fi
    
    # Remove Project
    echo "Removing ADO project..."
    if az devops project show --project "$ADO_PROJECT" --organization "$ADO_ORG_URL" &>/dev/null; then
        az devops project delete \
            --organization "$ADO_ORG_URL" \
            --id "$ADO_PROJECT" \
            --yes 2>/dev/null || true
        echo -e "${GREEN}✅ ADO project removed${NC}"
    else
        echo -e "${YELLOW}⏭️  ADO project not found (already removed)${NC}"
    fi
}

destroy_infrastructure() {
    echo -e "\n${BLUE}5️⃣  Removing Azure Infrastructure (Terraform)...${NC}"
    
    if [ ! -d ".terraform" ]; then
        echo -e "${YELLOW}⏭️  Terraform not initialized. Skipping infrastructure cleanup.${NC}"
        return
    fi
    
    if [ ! -f "terraform.tfstate" ]; then
        echo -e "${YELLOW}⏭️  Terraform state not found. Skipping infrastructure cleanup.${NC}"
        return
    fi
    
    # Check if there are resources to destroy
    if terraform state list 2>/dev/null | grep -q "azurerm"; then
        echo "Running terraform destroy..."
        terraform destroy -auto-approve
        echo -e "${GREEN}✅ Infrastructure destroyed${NC}"
    else
        echo -e "${YELLOW}⏭️  No infrastructure resources found in state${NC}"
    fi
}

cleanup_local_files() {
    echo -e "\n${BLUE}6️⃣  Cleaning Up Local Files (Optional)...${NC}"
    
    echo "Local files that can be cleaned up:"
    echo "  • setup.log / destroy.log (build logs)"
    echo "  • tfplan (terraform plan file)"
    echo "  • .terraform/ (terraform cache)"
    echo ""
    read -p "Remove local terraform cache and logs? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf .terraform terraform.tfstate* tfplan setup.log destroy.log 2>/dev/null || true
        echo -e "${GREEN}✅ Local files cleaned up${NC}"
    else
        echo -e "${YELLOW}⏭️  Local files preserved${NC}"
    fi
}

# --- Main Execution Flow ---

check_prereqs
check_azure_login
load_ado_config
confirm_destruction

destroy_ado_resources
destroy_infrastructure
cleanup_local_files

echo ""
echo -e "${GREEN}🧹 Lab Cleanup Complete!${NC}"
echo ""
echo "Summary of removed resources:"
echo "  ✅ ADO Project ($ADO_PROJECT)"
echo "  ✅ ADO Pipeline (DNS-Lab-Pipeline)"
echo "  ✅ ADO Service Connections"
echo "  ✅ ADO Agent Pool ($ADO_POOL)"
echo "  ✅ Azure Infrastructure (VMs, Networks, Key Vaults, etc.)"
echo ""
echo -e "${YELLOW}To start a new lab, run: ./setup.sh${NC}"
