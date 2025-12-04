#!/bin/bash

#######################################################################
# Azure DevOps Pipeline Setup Script
# Creates service connection, imports Git repo, and creates pipeline
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
echo -e "${BLUE}║         Azure DevOps Pipeline Setup                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. Check if .ado.env exists
if [ ! -f "$REPO_ROOT/.ado.env" ]; then
    echo -e "${RED}❌ .ado.env not found in $REPO_ROOT. Please run ./setup.sh first.${NC}"
    exit 1
fi

# Load ADO configuration
source "$REPO_ROOT/.ado.env"

# Install Azure DevOps extension if not present to avoid prompts
if ! az extension show --name azure-devops >/dev/null 2>&1; then
    echo "Installing Azure DevOps extension..."
    az extension add --name azure-devops
fi

# Verify Azure DevOps project exists early
if ! az devops project show --project "$ADO_PROJECT" --organization "$ADO_ORG_URL" >/dev/null 2>&1; then
    echo -e "${RED}❌ Azure DevOps project '$ADO_PROJECT' not found in '$ADO_ORG_URL'.${NC}"
    echo -e "${YELLOW}Run ./setup.sh to create and configure the organization/project.${NC}"
    exit 1
fi

# 2. Get Azure subscription details
echo -e "${BLUE}1️⃣  Fetching Azure Subscription Details${NC}"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo -e "${GREEN}✅ Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)${NC}"

# 3. Get Key Vault name from Terraform
echo -e "\n${BLUE}2️⃣  Checking Infrastructure${NC}"
if [ ! -f "$REPO_ROOT/terraform.tfstate" ]; then
    echo -e "${RED}❌ terraform.tfstate not found. Please run 'terraform apply' first.${NC}"
    exit 1
fi

# Execute terraform output from the repo root
KV_NAME=$(cd "$REPO_ROOT" && terraform output -raw key_vault_name 2>/dev/null || echo "")

if [ -z "$KV_NAME" ]; then
    echo -e "${RED}❌ Could not get Key Vault name from Terraform outputs.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Key Vault: $KV_NAME${NC}"

# 4. Check for existing service connections or generate new name
echo -e "\n${BLUE}3️⃣  Checking for Existing Service Connection${NC}"
echo "Looking for service connections matching pattern: SC-DNSLAB-*"
EXISTING_SC_LIST=$(timeout 15 az devops service-endpoint list \
    --organization "$ADO_ORG_URL" \
    --project "$ADO_PROJECT" \
    -o json 2>/dev/null | timeout 5 jq -c "[.[] | select(.name | startswith(\"SC-DNSLAB-\"))]" 2>/dev/null || echo "[]")

EXISTING_SC_COUNT=$(echo "$EXISTING_SC_LIST" | jq 'length' 2>/dev/null || echo "0")

if [ "$EXISTING_SC_COUNT" -gt 0 ]; then
    # Use the most recent existing service connection
    SERVICE_CONNECTION_NAME=$(echo "$EXISTING_SC_LIST" | jq -r '.[-1].name' 2>/dev/null)
    echo -e "${GREEN}✅ Found existing service connection: '$SERVICE_CONNECTION_NAME' (will reuse it).${NC}"
else
    # Generate dynamic service connection name (unique per project to avoid org-wide conflicts)
    SERVICE_CONNECTION_NAME="SC-DNSLAB-$(date +%s)"
    echo -e "${YELLOW}No existing service connection found.${NC}"
    echo -e "${BLUE}Will create new service connection: $SERVICE_CONNECTION_NAME${NC}"
fi

# 5. Update pipeline.yml with Key Vault name and Service Connection name
echo -e "\n${BLUE}4️⃣  Updating pipeline.yml${NC}"
PIPELINE_FILE="$REPO_ROOT/pipeline.yml"

if [ -f "$PIPELINE_FILE" ]; then
    UPDATED=false
    
    # Update Key Vault Name
    if grep -q 'REPLACE_ME_WITH_KV_NAME' "$PIPELINE_FILE"; then
        sed -i "s/REPLACE_ME_WITH_KV_NAME/$KV_NAME/g" "$PIPELINE_FILE"
        UPDATED=true
    else
        # Force update existing value if it differs
        sed -i "s/value: '.*'  # Placeholder replaced by setup-pipeline.sh/value: '$KV_NAME'  # Placeholder replaced by setup-pipeline.sh/" "$PIPELINE_FILE"
        UPDATED=true
    fi

    # Update Service Connection Name - direct replacement in ConnectedServiceName
    sed -i "s/ConnectedServiceName: 'SC-DNSLAB-[0-9]*'/ConnectedServiceName: '$SERVICE_CONNECTION_NAME'/g" "$PIPELINE_FILE"
    UPDATED=true

    if [ "$UPDATED" = true ]; then
        echo -e "${GREEN}✅ Updated pipeline.yml with Key Vault and Service Connection names.${NC}"
    else
        echo -e "${YELLOW}⏭️  pipeline.yml already configured.${NC}"
    fi
else
    echo -e "${RED}❌ pipeline.yml not found at $PIPELINE_FILE.${NC}"
    exit 1
fi

# 6. Commit pipeline.yml changes BEFORE pushing to trigger pipeline with correct config
echo -e "\n${BLUE}5️⃣  Committing Updated Pipeline Configuration${NC}"
cd "$REPO_ROOT"
if git diff --quiet pipeline.yml; then
    echo -e "${GREEN}✅ pipeline.yml already committed.${NC}"
else
    echo "Committing updated pipeline.yml..."
    git add pipeline.yml
    git commit -m "Update pipeline.yml with service connection and Key Vault names" || true
    echo -e "${GREEN}✅ pipeline.yml committed.${NC}"
fi

# 7. Create or verify Azure Repos repository
echo -e "\n${BLUE}6️⃣  Setting up Azure Repos Repository${NC}"
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

# 7. Initialize and push to Azure Repos
echo -e "\n${BLUE}7️⃣  Pushing Code to Azure Repos${NC}"

# Move to repo root for git operations
cd "$REPO_ROOT"

# Initialize Git if needed
if [ ! -d ".git" ]; then
    echo "Initializing Git repository..."
    git init
    git add .
    git commit -m "Initial commit - DNS Lab Setup"
fi

# Configure Azure Repos remote with PAT authentication
REMOTE_URL="https://:${ADO_PAT}@${ADO_ORG_URL#https://}/${ADO_PROJECT}/_git/${REPO_NAME}"

# Determine if origin needs update
CURRENT_ORIGIN_URL=$(git remote get-url origin 2>/dev/null || echo '')
if [ -z "$CURRENT_ORIGIN_URL" ]; then
    echo "Adding Azure Repos remote 'origin'..."
    git remote add origin "$REMOTE_URL"
elif [ "$CURRENT_ORIGIN_URL" != "$REMOTE_URL" ]; then
    echo -e "${YELLOW}⚠️  Existing origin remote differs. Replacing with Azure Repos remote.${NC}"
    git remote remove origin
    git remote add origin "$REMOTE_URL"
else
    echo -e "${GREEN}✅ Origin remote already points to Azure Repos.${NC}"
fi

# Disable Git LFS hooks temporarily (not needed for this lab) only if pushing
echo "Pushing to Azure Repos (all branches)..."
git config --local core.hookspath /dev/null
if git push -u origin --all 2>&1; then
    echo -e "${GREEN}✅ Code pushed successfully.${NC}"
else
    echo -e "${RED}❌ Push failed.${NC}"
    echo "Try manually: git push -u origin --all"
    git config --unset core.hookspath || true
    exit 1
fi
git config --unset core.hookspath || true

# 8. Create Service Connection
echo -e "\n${BLUE}8️⃣  Creating Service Connection${NC}"
# SERVICE_CONNECTION_NAME already set dynamically above

create_service_connection() {
    local name="$1"
    echo -e "${YELLOW}Creating Service Connection '$name'...${NC}"
    
    # Create service principal for the service connection
    SP_NAME="sp-ado-lab-$(date +%s)"
    echo "[DEBUG] SP_NAME: $SP_NAME"
    echo "[DEBUG] SUBSCRIPTION_ID: $SUBSCRIPTION_ID"
    echo "Creating service principal: $SP_NAME (this may take 30-60 seconds)..."
    
    echo "[DEBUG] Running: az ad sp create-for-rbac with timeout 120s"
    SP_OUTPUT=$(timeout 120 az ad sp create-for-rbac \
        --name "$SP_NAME" \
        --role Contributor \
        --scopes "/subscriptions/$SUBSCRIPTION_ID" \
        --query "{appId:appId, password:password, tenant:tenant}" -o json 2>&1)
    
    SP_EXIT_CODE=$?
    echo "[DEBUG] az ad sp create-for-rbac exit code: $SP_EXIT_CODE"
    
    if [ $SP_EXIT_CODE -eq 124 ]; then
        echo -e "${RED}❌ Service principal creation TIMED OUT (120 seconds).${NC}"
        exit 1
    elif [ $SP_EXIT_CODE -ne 0 ]; then
        echo -e "${RED}❌ Service principal creation FAILED with exit code $SP_EXIT_CODE.${NC}"
        echo "Response: $SP_OUTPUT"
        exit 1
    fi
    
    echo "[DEBUG] SP_OUTPUT (first 300 chars): ${SP_OUTPUT:0:300}"
    
    APP_ID=$(echo "$SP_OUTPUT" | jq -r '.appId' 2>/dev/null || echo "")
    SP_PASSWORD=$(echo "$SP_OUTPUT" | jq -r '.password' 2>/dev/null || echo "")
    
    echo "[DEBUG] Extracted APP_ID: $APP_ID"
    echo "[DEBUG] SP_PASSWORD length: ${#SP_PASSWORD}"
    
    if [ -z "$APP_ID" ] || [ "$APP_ID" == "null" ]; then
        echo -e "${RED}❌ Failed to extract App ID from service principal.${NC}"
        echo "Response: $SP_OUTPUT"
        exit 1
    fi
    
    echo "✓ Service Principal created with App ID: $APP_ID"
    
    # Wait for service principal propagation
    echo "Waiting 15 seconds for service principal to propagate..."
    sleep 15
    
    # Get Project ID for robust reference
    echo "[DEBUG] Running: az devops project show"
    PROJECT_ID=$(az devops project show --project "$ADO_PROJECT" --organization "$ADO_ORG_URL" --query id -o tsv 2>/dev/null || echo "")
    
    echo "[DEBUG] PROJECT_ID: $PROJECT_ID"
    
    if [ -z "$PROJECT_ID" ]; then
        echo -e "${RED}❌ Could not retrieve project ID.${NC}"
        exit 1
    fi
    
    # Create service connection configuration file
    SC_CONFIG_FILE="sc_config_$(date +%s).json"
    echo "[DEBUG] Creating config file: $SC_CONFIG_FILE"
    cat <<EOF > "$SC_CONFIG_FILE"
{
  "name": "$name",
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
        "id": "$PROJECT_ID",
        "name": "$ADO_PROJECT"
      },
      "name": "$name"
    }
  ]
}
EOF

    echo "[DEBUG] Config file created, size: $(wc -c < "$SC_CONFIG_FILE") bytes"
    echo "Creating service endpoint (this may take 20-30 seconds)..."
    echo "[DEBUG] Running: az devops service-endpoint create with timeout 60s"
    
    # Use the generic create command which takes the JSON config (including the key)
    # This avoids interactive prompts while using the robust CLI client
    SC_RESPONSE=$(timeout 60 az devops service-endpoint create \
        --service-endpoint-configuration "$SC_CONFIG_FILE" \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" \
        --output json 2>&1)
    
    SC_EXIT_CODE=$?
    echo "[DEBUG] az devops service-endpoint create exit code: $SC_EXIT_CODE"
    
    # Clean up config file immediately to protect secrets
    rm -f "$SC_CONFIG_FILE"
    echo "[DEBUG] Config file deleted"
    
    if [ $SC_EXIT_CODE -eq 124 ]; then
        echo -e "${RED}❌ Service endpoint creation TIMED OUT (60 seconds).${NC}"
        echo "[DEBUG] This usually means the Azure DevOps CLI is hanging."
        exit 1
    elif [ $SC_EXIT_CODE -ne 0 ]; then
        echo "[DEBUG] Exit code was non-zero but not timeout"
    fi
    
    echo "[DEBUG] SC_RESPONSE (first 500 chars): ${SC_RESPONSE:0:500}"
    
    SERVICE_ENDPOINT_ID=$(echo "$SC_RESPONSE" | jq -r '.id' 2>/dev/null || echo "")
    
    # Check if response contains an error
    if echo "$SC_RESPONSE" | grep -q "ERROR:"; then
        ERROR_MSG="$SC_RESPONSE"
    else
        ERROR_MSG=$(echo "$SC_RESPONSE" | jq -r '.message' 2>/dev/null || echo "")
    fi
    
    if [ -n "$SERVICE_ENDPOINT_ID" ] && [ "$SERVICE_ENDPOINT_ID" != "null" ] && [ -z "$ERROR_MSG" -o "$ERROR_MSG" == "null" ]; then
        echo -e "${GREEN}✅ Service Connection created (ID: $SERVICE_ENDPOINT_ID).${NC}"
    else
        # Show error if present
        if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
            echo -e "${RED}API Error: $ERROR_MSG${NC}"
        fi
        
        if echo "$SC_RESPONSE" | grep -q 'DuplicateServiceConnectionException'; then
            echo -e "${YELLOW}⚠️ Service connection '$name' already exists (duplicate detected).${NC}"
            # Try to find it in the current project first
            SERVICE_ENDPOINT_ID=$(az devops service-endpoint list \
                --organization "$ADO_ORG_URL" \
                --project "$ADO_PROJECT" \
                --query "[?name=='$name'].id" -o tsv 2>/dev/null || echo "")

            if [ -z "$SERVICE_ENDPOINT_ID" ]; then
                echo -e "${YELLOW}⏭️  Not found in current project. Searching org for existing endpoint...${NC}"
                # Search across the org via REST and try to link to this project
                ORG_SC_MATCH=$(curl -s -u ":$ADO_PAT" "${ADO_ORG_URL}/_apis/serviceendpoint/endpoints?api-version=7.1-preview.4" | jq -r ".value[] | select(.name == \"$name\") | .id" 2>/dev/null || echo "")
                if [ -n "$ORG_SC_MATCH" ]; then
                    echo -e "${YELLOW}Found existing service endpoint ID in org: $ORG_SC_MATCH. Linking to project '${ADO_PROJECT}'...${NC}"
                    LINK_PAYLOAD=$(cat <<EOF
{
  "name": "$name",
  "serviceEndpointProjectReferences": [
    {
      "projectReference": { "name": "$ADO_PROJECT" },
      "name": "$name"
    }
  ]
}
EOF
)
                    LINK_RESP=$(curl -s -X PATCH \
                        -u ":$ADO_PAT" \
                        -H "Content-Type: application/json" \
                        -d "$LINK_PAYLOAD" \
                        "${ADO_ORG_URL}/_apis/serviceendpoint/endpoints/$ORG_SC_MATCH?api-version=7.1-preview.4")
                    SERVICE_ENDPOINT_ID=$(echo "$LINK_RESP" | jq -r '.id' 2>/dev/null || echo "")
                    if [ -n "$SERVICE_ENDPOINT_ID" ] && [ "$SERVICE_ENDPOINT_ID" != "null" ]; then
                        echo -e "${GREEN}✅ Linked existing endpoint to project (ID: $SERVICE_ENDPOINT_ID).${NC}"
                    else
                        echo -e "${YELLOW}⚠️ Linking may require manual approval in ADO UI.${NC}"
                        echo "Open: ${ADO_ORG_URL}/${ADO_PROJECT}/_settings/adminservices and approve/use '$name'."
                    fi
                else
                    echo -e "${RED}❌ Duplicate reported but no matching endpoint found in org by name '$name'.${NC}"
                    echo "Please check other projects for a similarly named connection and either delete or rename it, then re-run."
                    exit 1
                fi
            fi
        else
            echo -e "${RED}❌ Failed to create service connection '$name'.${NC}"
            echo "Response: $SC_RESPONSE"
            echo "1. Go to: ${ADO_ORG_URL}/${ADO_PROJECT}/_settings/adminservices"
            echo "2. Click 'New service connection' > 'Azure Resource Manager'"
            echo "3. Select 'Service principal (automatic)'"
            echo "4. Name it exactly: $name"
            exit 1
        fi
    fi
}

# Create or retrieve service connection
if [ "$EXISTING_SC_COUNT" -gt 0 ]; then
    # Retrieve existing service connection details
    SERVICE_ENDPOINT_ID=$(echo "$EXISTING_SC_LIST" | jq -r '[-1].id' 2>/dev/null)
    echo -e "${GREEN}✅ Using existing service connection (ID: $SERVICE_ENDPOINT_ID).${NC}"
    
    # Get APP_ID for later use in Key Vault access grant
    APP_ID=$(echo "$EXISTING_SC_LIST" | jq -r '[-1].authorization.parameters.serviceprincipalid' 2>/dev/null)
else
    # Create new service connection
    create_service_connection "$SERVICE_CONNECTION_NAME"
fi

# Authorize Service Connection for all pipelines and grant Key Vault access
if [ -n "$SERVICE_ENDPOINT_ID" ] && [ "$SERVICE_ENDPOINT_ID" != "null" ]; then
    echo "Authorizing service connection for all pipelines..."
    az devops service-endpoint update \
        --id "$SERVICE_ENDPOINT_ID" \
        --enable-for-all true \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" >/dev/null 2>&1 || true

    # Some connections require manual approval; surface clear guidance
    APPROVAL_STATE=$(az devops service-endpoint show \
        --id "$SERVICE_ENDPOINT_ID" \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" \
        --query "isReady" -o tsv 2>/dev/null || echo "")
    if [ "$APPROVAL_STATE" != "True" ] && [ "$APPROVAL_STATE" != "true" ]; then
        echo -e "${YELLOW}⚠️ Service connection pending approval. Please approve it in ADO UI.${NC}"
        echo "Open: ${ADO_ORG_URL}/${ADO_PROJECT}/_settings/adminservices and approve '$SERVICE_CONNECTION_NAME'."
    else
        echo -e "${GREEN}✅ Service Connection authorized for use.${NC}"
    fi

    # Grant Key Vault permissions
    echo "Granting Key Vault access to Service Connection..."
    
    # Get Service Principal ID from the connection (try different query paths)
    SP_ID=$(az devops service-endpoint show \
        --id "$SERVICE_ENDPOINT_ID" \
        --organization "$ADO_ORG_URL" \
        --project "$ADO_PROJECT" \
        --query "authorization.parameters.serviceprincipalid" -o tsv 2>/dev/null || echo "")
    
    # Fallback: use the APP_ID from creation if SP_ID query failed
    if [ -z "$SP_ID" ] && [ -n "$APP_ID" ]; then
        echo -e "${YELLOW}Using Service Principal from creation: $APP_ID${NC}"
        SP_ID="$APP_ID"
    fi
    
    if [ -n "$SP_ID" ]; then
        echo "Service Principal App ID: $SP_ID"
        
        # Get the object ID of the service principal (needed for Terraform KV access policy)
        echo "Resolving Service Principal Object ID for Terraform..."
        SP_OBJECT_ID=$(az ad sp show --id "$SP_ID" --query id -o tsv 2>/dev/null || echo "")
        
        if [ -n "$SP_OBJECT_ID" ]; then
            echo "Service Principal Object ID: $SP_OBJECT_ID"
            
            # Update terraform.tfvars with the service principal object ID and ADO variables
            TFVARS_FILE="$REPO_ROOT/terraform.tfvars"
            if [ -f "$TFVARS_FILE" ]; then
                echo "Updating $TFVARS_FILE with azure_devops_sp_object_id and ADO variables..."
                
                # Source .ado.env to get ADO variables
                if [ -f "$REPO_ROOT/.ado.env" ]; then
                    source "$REPO_ROOT/.ado.env"
                fi
                
                # Update azure_devops_sp_object_id
                if grep -q "^azure_devops_sp_object_id" "$TFVARS_FILE"; then
                    sed -i "s/^azure_devops_sp_object_id.*/azure_devops_sp_object_id = \"$SP_OBJECT_ID\"/" "$TFVARS_FILE"
                else
                    echo "azure_devops_sp_object_id = \"$SP_OBJECT_ID\"" >> "$TFVARS_FILE"
                fi
                
                # Update ado_org_url
                if grep -q "^ado_org_url" "$TFVARS_FILE"; then
                    sed -i "s|^ado_org_url.*|ado_org_url = \"$ADO_ORG_URL\"|" "$TFVARS_FILE"
                else
                    echo "ado_org_url = \"$ADO_ORG_URL\"" >> "$TFVARS_FILE"
                fi
                
                # Update ado_pat (sensitive)
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
                
                echo -e "${GREEN}✅ terraform.tfvars updated with all required variables.${NC}"
                
                # Apply Terraform to grant Key Vault access via access policy
                echo "Running terraform apply to grant Key Vault access policy..."
                cd "$REPO_ROOT"
                
                # Now terraform.tfvars contains all required variables, so just run apply
                if terraform apply -auto-approve 2>&1 | tee -a "$REPO_ROOT/setup.log"; then
                    echo -e "${GREEN}✅ Terraform applied successfully. Key Vault access policy granted.${NC}"
                else
                    echo -e "${YELLOW}⚠️ Terraform apply had issues. Check setup.log for details.${NC}"
                    # Continue; manual verification may be needed
                fi
            else
                echo -e "${YELLOW}⚠️ terraform.tfvars not found at $TFVARS_FILE. Skipping Terraform update.${NC}"
            fi
        else
            echo -e "${RED}❌ Could not resolve Service Principal Object ID.${NC}"
        fi

    else
        echo -e "${RED}❌ Could not retrieve Service Principal ID from Service Connection.${NC}"
        echo "Please manually grant Key Vault access to the Service Principal used by '$SERVICE_CONNECTION_NAME'."
    fi
fi

# 9. Create Pipeline
echo -e "\n${BLUE}9️⃣  Creating Pipeline${NC}"
PIPELINE_NAME="DNS-Lab-Pipeline"

# Check if pipeline already exists
EXISTING_PIPELINE=$(az pipelines list \
    --organization "$ADO_ORG_URL" \
    --project "$ADO_PROJECT" \
    --query "[?name=='$PIPELINE_NAME'].id" -o tsv 2>/dev/null || echo "")

if [ -n "$EXISTING_PIPELINE" ]; then
    echo -e "${YELLOW}⚠️  Pipeline '$PIPELINE_NAME' already exists (ID: $EXISTING_PIPELINE).${NC}"
    PIPELINE_ID="$EXISTING_PIPELINE"
    # Optional: queue a run to surface agent availability issues early
    echo -e "${BLUE}🔄 Queuing a pipeline run to verify agent availability...${NC}"
    if az pipelines run --id "$PIPELINE_ID" --organization "$ADO_ORG_URL" --project "$ADO_PROJECT" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Pipeline run queued.${NC}"
    else
        echo -e "${YELLOW}⚠️  Unable to auto-queue run (permissions or agent missing). You can trigger manually in the UI.${NC}"
    fi
else
    echo -e "${YELLOW}Creating pipeline '$PIPELINE_NAME'...${NC}"
    
    # First, delete any old pipelines with conflicting names to avoid stale definitions
    echo "Checking for existing pipelines to clean up..."
    OLD_PIPELINES=$(az pipelines list --organization "$ADO_ORG_URL" --project "$ADO_PROJECT" --query "[?name=='$PIPELINE_NAME'].id" -o tsv 2>/dev/null || echo "")
    if [ -n "$OLD_PIPELINES" ]; then
        while IFS= read -r OLD_ID; do
            if [ -n "$OLD_ID" ]; then
                echo "  Removing old pipeline (ID: $OLD_ID)..."
                az pipelines delete --organization "$ADO_ORG_URL" --project "$ADO_PROJECT" --id "$OLD_ID" --yes 2>/dev/null || true
            fi
        done <<< "$OLD_PIPELINES"
    fi
    
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
        echo -e "${YELLOW}ℹ️  Pipeline is set to 'trigger: none' - it will not run automatically.${NC}"
        echo -e "${YELLOW}    Students can manually trigger it when ready for testing.${NC}"
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

# Pipeline YAML uses dynamically generated service connection name from variables
# No hardcoded service connection references

# Summary
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║              Pipeline Setup Complete! 🎉                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}✅ Service Connection: $SERVICE_CONNECTION_NAME (dynamically generated)${NC}"
echo -e "${GREEN}✅ Repository: $REPO_NAME${NC}"
echo -e "${GREEN}✅ Pipeline: $PIPELINE_NAME${NC}"
echo ""
echo "Agent Pool Check (DNS-Lab-Pool):"

# Resolve pool ID first (CLI requires pool-id for agent listing)
POOL_ID=$(az pipelines pool list --organization "$ADO_ORG_URL" --query "[?name=='DNS-Lab-Pool'].id" -o tsv 2>/dev/null || echo '')
if [ -z "$POOL_ID" ]; then
    echo -e "${YELLOW}  ⚠️ Pool 'DNS-Lab-Pool' not found. It will be created automatically when an agent registers.${NC}"
    echo -e "${YELLOW}  Next: run ./scripts/register-agent.sh to create and attach agent.${NC}"
else
    AGENT_NAMES=$(az pipelines agent list --organization "$ADO_ORG_URL" --pool-id "$POOL_ID" --query '[].name' -o tsv 2>/dev/null || echo '')
    if [ -n "$AGENT_NAMES" ]; then
        echo -e "${GREEN}  ✓ Agent(s) registered: ${AGENT_NAMES}${NC}"
    else
        # Fallback: REST API query for agents (sometimes CLI misses newly registered agents due to caching)
        REST_AGENTS=$(curl -s -u :"$ADO_PAT" "${ADO_ORG_URL}/${ADO_PROJECT}/_apis/distributedtask/pools/$POOL_ID/agents?api-version=7.1-preview.1" | jq -r '.value[].name' 2>/dev/null || echo '')
        if [ -n "$REST_AGENTS" ]; then
            echo -e "${GREEN}  ✓ Agent(s) registered (REST): ${REST_AGENTS}${NC}"
        else
            echo -e "${YELLOW}  ⚠️ No agents detected yet in pool (ID: $POOL_ID).${NC}"
            echo "      If you just ran register-agent, wait ~30s and re-run this check:"
            echo "      az pipelines agent list --organization '$ADO_ORG_URL' --pool-id $POOL_ID --query '[].name' -o tsv"
        fi
    fi
fi
echo -e "${GREEN}✅ Key Vault: $KV_NAME${NC}"

echo ""
echo "Next Steps:"
echo "1. View pipeline: ${ADO_ORG_URL}/${ADO_PROJECT}/_build"
echo "2. Run the pipeline to test baseline configuration"
echo "3. Continue to Lab 1: docs/LAB_GUIDE.md"
echo ""
