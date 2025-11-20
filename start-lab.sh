#!/bin/bash
set -e

echo "=================================================="
echo "   DNS Troubleshooting Lab - Automated Setup"
echo "=================================================="

# 1. Prerequisites Check
command -v az >/dev/null || { echo "❌ Azure CLI is not installed."; exit 1; }
command -v terraform >/dev/null || { echo "❌ Terraform is not installed."; exit 1; }
command -v jq >/dev/null || { echo "❌ jq is not installed."; exit 1; }

# 2. Azure Login
echo "Checking Azure Login..."
az account show >/dev/null 2>&1 || az login

echo "Select the Subscription to use:"
az account list --query "[].{Name:name, ID:id}" -o table
read -p "Enter Subscription ID: " SUB_ID
az account set --subscription "$SUB_ID"

# 3. Collect ADO Details
read -p "Enter Azure DevOps Org URL (e.g. https://dev.azure.com/myorg): " ADO_ORG
read -s -p "Enter Azure DevOps PAT (Full Access or Agent Pools+Service Connections): " ADO_PAT
echo ""

# 4. Run Terraform
echo "Initializing Terraform..."
terraform init

echo "Generating terraform.tfvars..."
cat > terraform.tfvars <<EOF
ado_org_url = "$ADO_ORG"
ado_pat = "$ADO_PAT"
EOF

echo "Applying Terraform (This will take ~5-10 minutes)..."
terraform apply -auto-approve

# Collect Outputs
KV_NAME=$(terraform output -raw key_vault_name)
RG_NAME=$(terraform output -raw resource_group_name)
SP_APP_ID=$(terraform output -raw sp_client_id)
SP_PASSWORD=$(terraform output -raw sp_client_secret)
SP_TENANT=$(terraform output -raw sp_tenant_id)
RG_NAME=$(terraform output -raw resource_group_name)

# 6. Configure Azure DevOps
echo "Configuring Azure DevOps..."
export AZURE_DEVOPS_EXT_PAT="$ADO_PAT"

# Create Project
echo "Creating Project 'NetworkingLab'..."
az devops project create --name "NetworkingLab" --organization "$ADO_ORG" --visibility private || echo "Project might already exist, continuing..."

# Push Code to ADO Repo
echo "Pushing code to Azure DevOps..."
# Remove https:// prefix for URL construction
CLEAN_ORG_URL=${ADO_ORG#https://}
# Construct URL with PAT for authentication
GIT_URL="https://user:$ADO_PAT@$CLEAN_ORG_URL/NetworkingLab/_git/NetworkingLab"

# We need to be in the root of the repo
git remote remove ado 2>/dev/null || true
git remote add ado "$GIT_URL"
echo "Pushing current branch to 'main' on ADO..."
git push ado HEAD:main --force

# Create Service Connection
echo "Creating Service Connection 'LabKeyVaultConnection'..."
# We need to pass the password explicitly
export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY="$SP_PASSWORD"

az devops service-endpoint azurerm create \
  --name "LabKeyVaultConnection" \
  --azure-rm-service-principal-id "$SP_APP_ID" \
  --azure-rm-subscription-id "$SUB_ID" \
  --azure-rm-subscription-name "LabSub" \
  --azure-rm-tenant-id "$SP_TENANT" \
  --organization "$ADO_ORG" \
  --project "NetworkingLab"

# Create Variable Group
echo "Creating Variable Group 'KeyVault-Variables'..."
az pipelines variable-group create \
  --name "KeyVault-Variables" \
  --authorize true \
  --variables \
    KeyVaultName="$KV_NAME" \
    ResourceGroupName="$RG_NAME" \
    SubscriptionId="$SUB_ID" \
  --organization "$ADO_ORG" \
  --project "NetworkingLab"

# Create Pipeline
echo "Creating Pipeline 'DNS-Troubleshooting'..."
az pipelines create \
  --name "DNS-Troubleshooting" \
  --repository "NetworkingLab" \
  --branch "main" \
  --yaml-path "pipeline.yml" \
  --organization "$ADO_ORG" \
  --project "NetworkingLab" \
  --repository-type tfsgit

echo "=================================================="
echo "   Setup Complete!"
echo "   1. Go to $ADO_ORG/NetworkingLab"
echo "   2. Check the Pipeline 'DNS-Troubleshooting'"
echo "   3. It should be ready to run."
echo "=================================================="
