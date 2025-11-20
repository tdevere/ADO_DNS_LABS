#!/bin/bash

#######################################################################
# Azure DevOps Pipeline Setup Script
# Creates service connection, imports Git repo, and creates pipeline
#######################################################################

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Azure DevOps Pipeline Setup                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Check if .ado.env exists
if [ ! -f ".ado.env" ]; then
    echo -e "${RED}❌ .ado.env not found. Please run ./scripts/setup-ado-org.sh first.${NC}"
    exit 1
fi

# Load ADO configuration
source .ado.env

# 2. Get Azure subscription details
echo -e "${BLUE}1️⃣  Fetching Azure Subscription Details${NC}"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo -e "${GREEN}✅ Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)${NC}"

# 3. Get Key Vault name from Terraform
echo -e "\n${BLUE}2️⃣  Checking Infrastructure${NC}"
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}❌ terraform.tfstate not found. Please run 'terraform apply' first.${NC}"
    exit 1
fi

KV_NAME=$(terraform output -raw key_vault_name 2>/dev/null || echo "")
if [ -z "$KV_NAME" ]; then
    echo -e "${RED}❌ Could not get Key Vault name from Terraform outputs.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Key Vault: $KV_NAME${NC}"

# 4. Update pipeline.yml with Key Vault name
echo -e "\n${BLUE}3️⃣  Updating pipeline.yml${NC}"
if [ -f "pipeline.yml" ]; then
    sed -i "s/REPLACE_ME_WITH_KV_NAME/$KV_NAME/g" pipeline.yml
    echo -e "${GREEN}✅ pipeline.yml updated with Key Vault name.${NC}"
else
    echo -e "${RED}❌ pipeline.yml not found.${NC}"
    exit 1
fi

# 5. Create or verify Azure Repos repository
echo -e "\n${BLUE}4️⃣  Setting up Azure Repos Repository${NC}"
REPO_NAME="ADO_DNS_LABS"

# Check if repo exists
REPO_ID=$(az repos list \
    --organization "$ADO_ORG_URL" \
    --project "$ADO_PROJECT" \
    --query "[?name=='$REPO_NAME'].id" -o tsv 2>/dev/null || echo "")

if [ -z "$REPO_ID" ]; then
    echo -e "${YELLOW}Creating repository '$REPO_NAME'...${NC}"
    az repos create \
        --name "$REPO_NAME" \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" >/dev/null
    echo -e "${GREEN}✅ Repository created.${NC}"
else
    echo -e "${GREEN}✅ Repository already exists.${NC}"
fi

# 6. Initialize and push to Azure Repos
echo -e "\n${BLUE}5️⃣  Pushing Code to Azure Repos${NC}"

# Initialize Git if needed
if [ ! -d ".git" ]; then
    echo "Initializing Git repository..."
    git init
    git add .
    git commit -m "Initial commit - DNS Lab Setup"
fi

# Configure Azure Repos remote with PAT authentication
REMOTE_URL="https://:${ADO_PAT}@${ADO_ORG_URL#https://}/${ADO_PROJECT}/_git/${REPO_NAME}"

# Remove existing origin if it exists
git remote remove origin 2>/dev/null || true

# Add Azure Repos remote
git remote add origin "$REMOTE_URL"

# Disable Git LFS hooks temporarily (not needed for this lab)
git config --local core.hookspath /dev/null

# Push to Azure Repos
echo "Pushing to Azure Repos..."
if git push -u origin --all 2>&1; then
    echo -e "${GREEN}✅ Code pushed successfully.${NC}"
else
    echo -e "${RED}❌ Push failed.${NC}"
    echo "Try pushing manually: git push -u origin --all"
    exit 1
fi

# Re-enable hooks
git config --unset core.hookspath

# 7. Create Service Connection
echo -e "\n${BLUE}6️⃣  Creating Service Connection${NC}"
SERVICE_CONNECTION_NAME="LabConnection"

# Check if service connection already exists
EXISTING_SC=$(az devops service-endpoint list \
    --organization "$ADO_ORG_URL" \
    --project "$ADO_PROJECT" \
    --query "[?name=='$SERVICE_CONNECTION_NAME'].id" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_SC" ]; then
    echo -e "${YELLOW}⚠️  Service Connection '$SERVICE_CONNECTION_NAME' already exists.${NC}"
    SERVICE_ENDPOINT_ID="$EXISTING_SC"
else
    echo -e "${YELLOW}Creating Service Connection '$SERVICE_CONNECTION_NAME'...${NC}"
    
    # Create service principal for the service connection
    SP_NAME="sp-ado-lab-$(date +%s)"
    SP_OUTPUT=$(az ad sp create-for-rbac \
        --name "$SP_NAME" \
        --role Contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID" \
        --query "{appId:appId, password:password, tenant:tenant}" -o json)
    
    APP_ID=$(echo "$SP_OUTPUT" | jq -r '.appId')
    SP_PASSWORD=$(echo "$SP_OUTPUT" | jq -r '.password')
    
    # Wait for service principal propagation
    echo "Waiting for service principal to propagate..."
    sleep 10
    
    # Create service connection using REST API
    SERVICE_CONNECTION_JSON=$(cat <<EOF
{
  "name": "$SERVICE_CONNECTION_NAME",
  "type": "azurerm",
  "url": "https://management.azure.com/",
  "authorization": {
    "parameters": {
      "tenantid": "$TENANT_ID",
      "serviceprincipalid": "$APP_ID",
      "authenticationType": "spnKey",
      "serviceprincipalkey": "$SP_PASSWORD"
    },
    "scheme": "ServicePrincipal"
  },
  "data": {
    "subscriptionId": "$SUBSCRIPTION_ID",
    "subscriptionName": "$SUBSCRIPTION_NAME",
    "environment": "AzureCloud",
    "scopeLevel": "Subscription",
    "creationMode": "Manual"
  },
  "isShared": false,
  "isReady": true,
  "serviceEndpointProjectReferences": [
    {
      "projectReference": {
        "name": "$ADO_PROJECT"
      },
      "name": "$SERVICE_CONNECTION_NAME"
    }
  ]
}
EOF
)
    
    SC_RESPONSE=$(curl -s -X POST \
        -u ":$ADO_PAT" \
        -H "Content-Type: application/json" \
        -d "$SERVICE_CONNECTION_JSON" \
        "${ADO_ORG_URL}/${ADO_PROJECT}/_apis/serviceendpoint/endpoints?api-version=7.1-preview.4")
    
    SERVICE_ENDPOINT_ID=$(echo "$SC_RESPONSE" | jq -r '.id' 2>/dev/null || echo "")
    
    if [ -n "$SERVICE_ENDPOINT_ID" ] && [ "$SERVICE_ENDPOINT_ID" != "null" ]; then
        echo -e "${GREEN}✅ Service Connection created (ID: $SERVICE_ENDPOINT_ID).${NC}"
    else
        # Detect duplicate error where connection already exists but not listed
        if echo "$SC_RESPONSE" | grep -q 'DuplicateServiceConnectionException'; then
            echo -e "${YELLOW}⚠️ Service connection '$SERVICE_CONNECTION_NAME' already exists (duplicate detected).${NC}"
            # Try to fetch the ID of the existing connection
            SERVICE_ENDPOINT_ID=$(az devops service-endpoint list \
                --organization "$ADO_ORG_URL" \
                --project "$ADO_PROJECT" \
                --query "[?name=='$SERVICE_CONNECTION_NAME'].id" -o tsv 2>/dev/null || echo "")

            # Fallback: Check for AzureLabConnection if LabConnection is not found
            if [ -z "$SERVICE_ENDPOINT_ID" ]; then
                FALLBACK_SC="AzureLabConnection"
                FALLBACK_ID=$(az devops service-endpoint list \
                    --organization "$ADO_ORG_URL" \
                    --project "$ADO_PROJECT" \
                    --query "[?name=='$FALLBACK_SC'].id" -o tsv 2>/dev/null || echo "")
                
                if [ -n "$FALLBACK_ID" ]; then
                    SERVICE_ENDPOINT_ID="$FALLBACK_ID"
                    echo -e "${YELLOW}⚠️ Using existing connection '$FALLBACK_SC' instead of '$SERVICE_CONNECTION_NAME'.${NC}"
                    USE_FALLBACK_CONNECTION="true"
                fi
            fi
        else
            echo -e "${RED}❌ Failed to create service connection.${NC}"
            echo "Response: $SC_RESPONSE"
            echo ""
            echo -e "${YELLOW}Please create the service connection manually:${NC}"
            echo "1. Go to: ${ADO_ORG_URL}/${ADO_PROJECT}/_settings/adminservices"
            echo "2. Click 'New service connection' > 'Azure Resource Manager'"
            echo "3. Select 'Service principal (automatic)'"
            echo "4. Name it: $SERVICE_CONNECTION_NAME"
            exit 1
        fi
    fi
fi

# Authorize Service Connection for all pipelines and grant Key Vault access
if [ -n "$SERVICE_ENDPOINT_ID" ] && [ "$SERVICE_ENDPOINT_ID" != "null" ]; then
    echo "Authorizing service connection for all pipelines..."
    az devops service-endpoint update \
        --id "$SERVICE_ENDPOINT_ID" \
        --enable-for-all true \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" >/dev/null 2>&1
    echo -e "${GREEN}✅ Service Connection authorized.${NC}"

    # Grant Key Vault permissions
    echo "Granting Key Vault access to Service Connection..."
    
    # Get Service Principal ID from the connection
    SP_ID=$(az devops service-endpoint show \
        --id "$SERVICE_ENDPOINT_ID" \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" \
        --query "authorization.parameters.serviceprincipalid" -o tsv 2>/dev/null || echo "")
    
    if [ -n "$SP_ID" ]; then
        echo "Service Principal ID: $SP_ID"
        # Check if Key Vault uses RBAC or Access Policies
        KV_RBAC=$(az keyvault show --name "$KV_NAME" --query "properties.enableRbacAuthorization" -o tsv 2>/dev/null || echo "false")
        
        if [ "$KV_RBAC" == "true" ]; then
            echo "Key Vault uses RBAC. Assigning 'Key Vault Secrets User' role..."
            az role assignment create \
                --assignee "$SP_ID" \
                --role "Key Vault Secrets User" \
                --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$(az keyvault show --name "$KV_NAME" --query resourceGroup -o tsv)/providers/Microsoft.KeyVault/vaults/$KV_NAME" >/dev/null 2>&1 || echo "Role assignment might already exist."
        else
            echo "Key Vault uses Access Policies. Setting policy..."
            az keyvault set-policy \
                --name "$KV_NAME" \
                --spn "$SP_ID" \
                --secret-permissions get list >/dev/null 2>&1
        fi
        echo -e "${GREEN}✅ Key Vault permissions granted.${NC}"
    else
        echo -e "${YELLOW}⚠️ Could not retrieve Service Principal ID. Please manually grant Key Vault access.${NC}"
    fi
fi

# 8. Create Pipeline
echo -e "\n${BLUE}7️⃣  Creating Pipeline${NC}"
PIPELINE_NAME="DNS-Lab-Pipeline"

# Check if pipeline already exists
EXISTING_PIPELINE=$(az pipelines list \
    --organization "$ADO_ORG_URL" \
    --project "$ADO_PROJECT" \
    --query "[?name=='$PIPELINE_NAME'].id" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_PIPELINE" ]; then
    echo -e "${YELLOW}⚠️  Pipeline '$PIPELINE_NAME' already exists.${NC}"
    PIPELINE_ID="$EXISTING_PIPELINE"
else
    echo -e "${YELLOW}Creating pipeline '$PIPELINE_NAME'...${NC}"
    
    # Create pipeline using Azure CLI
    # Capture output and error
    PIPELINE_OUTPUT=$(az pipelines create \
        --name "$PIPELINE_NAME" \
        --repository "ADO_DNS_LABS" \
        --repository-type tfsgit \
        --branch main \
        --yml-path "/pipeline.yml" \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" \
        --output json 2>&1)
    
    # Extract ID if successful (check if output is valid JSON and has id)
    PIPELINE_ID=$(echo "$PIPELINE_OUTPUT" | jq -r '.id' 2>/dev/null || echo "")
    
    if [ -n "$PIPELINE_ID" ] && [ "$PIPELINE_ID" != "null" ]; then
        echo -e "${GREEN}✅ Pipeline created (ID: $PIPELINE_ID).${NC}"
    else
        echo -e "${YELLOW}⚠️  Could not create pipeline automatically.${NC}"
        echo -e "${RED}Error details:${NC}"
        echo "$PIPELINE_OUTPUT"
        echo ""
        echo "Please create it manually:"
        echo "1. Go to: ${ADO_ORG_URL}/${ADO_PROJECT}/_build"
        echo "2. Click 'New pipeline'"
        echo "3. Select 'Azure Repos Git'"
        echo "4. Select 'ADO_DNS_LABS' repository"
        echo "5. Select 'Existing Azure Pipelines YAML file'"
        echo "6. Path: /pipeline.yml"
    fi
fi

# Update pipeline variable if using fallback connection
if [ "$USE_FALLBACK_CONNECTION" == "true" ] && [ -n "$PIPELINE_ID" ]; then
    echo "Updating pipeline variable 'ServiceConnectionName' to '$FALLBACK_SC'..."
    az pipelines variable create \
        --pipeline-id "$PIPELINE_ID" \
        --name "ServiceConnectionName" \
        --value "$FALLBACK_SC" \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" >/dev/null 2>&1
    echo -e "${GREEN}✅ Pipeline variable updated.${NC}"
fi

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Pipeline Setup Complete! 🎉                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Service Connection: $SERVICE_CONNECTION_NAME${NC}"
echo -e "${GREEN}✅ Repository: $REPO_NAME${NC}"
echo -e "${GREEN}✅ Pipeline: $PIPELINE_NAME${NC}"
echo -e "${GREEN}✅ Key Vault: $KV_NAME${NC}"
echo ""
echo "Next Steps:"
echo "1. View pipeline: ${ADO_ORG_URL}/${ADO_PROJECT}/_build"
echo "2. Run the pipeline to test baseline configuration"
echo "3. Continue to Lab 1: docs/LAB_GUIDE.md"
echo ""
