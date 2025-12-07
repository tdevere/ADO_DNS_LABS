#!/bin/bash

#######################################################################
# ADO Setup Assistant
# Guides students through Azure DevOps Organization setup
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

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Azure DevOps Setup Assistant                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Check Prerequisites
echo -e "${BLUE}📋 Checking Prerequisites...${NC}"
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI (az) is not installed.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Azure CLI installed${NC}"

# 2. Organization Setup
echo -e "\n${BLUE}1️⃣  Azure DevOps Organization${NC}"

# Check if ADO_ORG_URL is already set (from .ado.env)
if [[ -z "$ADO_ORG_URL" ]]; then
    echo "You need an Azure DevOps Organization to run the pipelines."
    echo "If you don't have one, create it for free at: https://dev.azure.com"
    echo ""
    read -p "Enter your Azure DevOps Org URL (e.g., https://dev.azure.com/myorg): " ADO_ORG_URL
else
    echo -e "${GREEN}✅ Using organization: $ADO_ORG_URL${NC}"
fi

# Remove trailing slash if present
ADO_ORG_URL=${ADO_ORG_URL%/}

if [[ -z "$ADO_ORG_URL" ]]; then
    echo -e "${RED}❌ Organization URL is required.${NC}"
    exit 1
fi

# 3. PAT Creation & Validation
echo -e "\n${BLUE}2️⃣  Personal Access Token (PAT)${NC}"

# Check if ADO_PAT is already set (from .ado.env)
if [[ -z "$ADO_PAT" ]]; then
    echo "You need a PAT with the following scopes:"
    echo "  - ${YELLOW}Agent Pools${NC}: Read & Manage"
    echo "  - ${YELLOW}Service Connections${NC}: Read, Query & Manage"
    echo ""
    echo "Create one here: ${ADO_ORG_URL}/_usersSettings/tokens"
    echo ""
    read -s -p "Enter your PAT: " ADO_PAT
    echo ""
else
    echo -e "${GREEN}✅ Using existing PAT from environment${NC}"
fi

echo -e "\nTesting PAT validity..."

# Test PAT by listing projects
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -u ":$ADO_PAT" "${ADO_ORG_URL}/_apis/projects?api-version=6.0")

if [[ "$RESPONSE" == "200" ]]; then
    echo -e "${GREEN}✅ PAT is valid!${NC}"
else
    echo -e "${RED}❌ PAT validation failed (HTTP $RESPONSE).${NC}"
    echo "Please check your PAT and Organization URL."
    exit 1
fi

# 4. Configure Local Environment
echo -e "\n${BLUE}3️⃣  Configuring Local Environment${NC}"
echo "Logging in to Azure DevOps CLI..."
echo "$ADO_PAT" | az devops login --organization "$ADO_ORG_URL"

# 5. Project Setup
echo -e "\n${BLUE}4️⃣  Project Setup${NC}"

# Check if ADO_PROJECT is already set (from .ado.env)
if [[ -z "$ADO_PROJECT" ]]; then
    DEFAULT_PROJECT="NetworkingLab"
    read -p "Enter Project Name [Default: $DEFAULT_PROJECT]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-$DEFAULT_PROJECT}
else
    echo -e "${GREEN}✅ Using project: $ADO_PROJECT${NC}"
    PROJECT_NAME="$ADO_PROJECT"
fi

echo "Checking if project '$PROJECT_NAME' exists..."
if az devops project show --project "$PROJECT_NAME" --organization "$ADO_ORG_URL" &> /dev/null; then
    echo -e "${GREEN}✅ Project '$PROJECT_NAME' exists.${NC}"
else
    echo -e "${YELLOW}Creating project '$PROJECT_NAME'...${NC}"
    az devops project create --name "$PROJECT_NAME" --organization "$ADO_ORG_URL" --visibility private
    echo -e "${GREEN}✅ Project created.${NC}"
fi

# 6. Agent Pool Setup
echo -e "\n${BLUE}5️⃣  Agent Pool Setup${NC}"

# Check if ADO_POOL is already set (from .ado.env)
if [[ -z "$ADO_POOL" ]]; then
    DEFAULT_POOL="DNS-Lab-Pool"
    read -p "Enter Agent Pool Name [Default: $DEFAULT_POOL]: " POOL_NAME
    POOL_NAME=${POOL_NAME:-$DEFAULT_POOL}
else
    echo -e "${GREEN}✅ Using pool: $ADO_POOL${NC}"
    POOL_NAME="$ADO_POOL"
fi

echo "Checking if pool '$POOL_NAME' exists..."
POOL_ID=$(az pipelines pool list --organization "$ADO_ORG_URL" --query "[?name=='$POOL_NAME'].id" -o tsv)

if [[ -n "$POOL_ID" ]]; then
    echo -e "${GREEN}✅ Agent Pool '$POOL_NAME' exists (ID: $POOL_ID).${NC}"
else
    echo -e "${YELLOW}Creating agent pool '$POOL_NAME'...${NC}"
    # Use REST API since 'az pipelines pool create' is not available in all CLI versions
    CREATE_POOL_RESPONSE=$(curl -s -X POST \
        -u ":$ADO_PAT" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"$POOL_NAME\", \"autoProvision\": true, \"poolType\": \"automation\"}" \
        "$ADO_ORG_URL/_apis/distributedtask/pools?api-version=6.0")
    
    # Check if creation was successful (look for the pool name in response)
    if echo "$CREATE_POOL_RESPONSE" | grep -q "\"name\":\"$POOL_NAME\""; then
        echo -e "${GREEN}✅ Agent Pool created.${NC}"
    else
        echo -e "${RED}❌ Failed to create agent pool.${NC}"
        echo "Response: $CREATE_POOL_RESPONSE"
        echo "Please create the pool manually at: $ADO_ORG_URL/_settings/agentpools"
        exit 1
    fi
fi

# 7. Save Configuration
echo -e "\n${BLUE}💾 Saving Configuration${NC}"
CONFIG_FILE="$REPO_ROOT/.ado.env"
cat > "$CONFIG_FILE" <<EOF
export ADO_ORG_URL="$ADO_ORG_URL"
export ADO_PAT="$ADO_PAT"
export ADO_PROJECT="$PROJECT_NAME"
export ADO_POOL="$POOL_NAME"
EOF

echo -e "${GREEN}✅ Configuration saved to $CONFIG_FILE${NC}"
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Setup Complete! 🚀                               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next Steps:"
echo "1. Deploy infrastructure:"
echo "   terraform plan -out=tfplan && terraform apply tfplan"
echo ""
echo "2. Register the agent on the VM:"
echo "   ./scripts/register-agent.sh"
echo ""
echo "3. Setup pipeline and service connection:"
echo "   ./scripts/setup-pipeline.sh"
echo ""
