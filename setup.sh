#!/bin/bash

#######################################################################
# Azure DNS Lab - Setup Script
# This script helps students set up the standalone DNS lab environment
#######################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Header
clear
cat << 'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║        🧪 Azure DNS Troubleshooting Lab Setup              ║
║                                                            ║
║  This wizard will help you set up the DNS lab environment ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝

EOF

echo -e "${BLUE}📋 Prerequisites Check${NC}\n"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "  ${GREEN}✅${NC} $2"
    else
        echo -e "  ${RED}❌${NC} $2"
    fi
}

# Check prerequisites
PREREQS_OK=true

# Check Azure CLI
if command_exists az; then
    AZ_VERSION=$(az version --output json 2>/dev/null | jq -r '."azure-cli"' 2>/dev/null || echo "unknown")
    print_status 0 "Azure CLI installed (version: $AZ_VERSION)"
else
    print_status 1 "Azure CLI not found - Please install: https://docs.microsoft.com/cli/azure/install-azure-cli"
    PREREQS_OK=false
fi

# Check Terraform
if command_exists terraform; then
    TF_VERSION=$(terraform version -json 2>/dev/null | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | cut -d' ' -f2 || echo "unknown")
    print_status 0 "Terraform installed (version: $TF_VERSION)"
else
    print_status 1 "Terraform not found - Please install: https://www.terraform.io/downloads"
    PREREQS_OK=false
fi

# Check SSH
if command_exists ssh; then
    print_status 0 "SSH client available"
else
    print_status 1 "SSH client not found"
    PREREQS_OK=false
fi

# Check DNS utilities
if command_exists nslookup; then
    print_status 0 "DNS utilities available (nslookup)"
else
    print_status 1 "nslookup not found - Install dnsutils package"
fi

# Check jq
if command_exists jq; then
    print_status 0 "jq available (for JSON parsing)"
else
    print_status 1 "jq not found - Install jq package (optional but recommended)"
fi

echo ""

if [ "$PREREQS_OK" = false ]; then
    echo -e "${RED}❌ Some required tools are missing. Please install them and run this script again.${NC}"
    exit 1
fi

# Check Azure authentication
echo -e "${BLUE}🔐 Azure Authentication Check${NC}\n"

if az account show &>/dev/null; then
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    SUBSCRIPTION_ID=$(az account show --query id -o tsv)
    echo -e "  ${GREEN}✅${NC} Authenticated to Azure"
    echo -e "  📌 Current subscription: ${YELLOW}$SUBSCRIPTION_NAME${NC}"
    echo -e "  🆔 Subscription ID: ${YELLOW}$SUBSCRIPTION_ID${NC}"
    echo ""
    
    read -p "Is this the correct subscription for the lab? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Please set the correct subscription:${NC}"
        echo "  az account list --output table"
        echo "  az account set --subscription \"YOUR_SUBSCRIPTION_ID\""
        exit 1
    fi
else
    echo -e "  ${RED}❌${NC} Not authenticated to Azure"
    echo -e "${YELLOW}Please run: az login${NC}"
    exit 1
fi

# Check SSH key
echo -e "\n${BLUE}🔑 SSH Key Check${NC}\n"

SSH_KEY_PATH="$HOME/.ssh/terraform_lab_key"
SSH_PUB_KEY_PATH="$HOME/.ssh/terraform_lab_key.pub"

if [ -f "$SSH_PUB_KEY_PATH" ]; then
    echo -e "  ${GREEN}✅${NC} SSH key found: $SSH_PUB_KEY_PATH"
else
    echo -e "  ${RED}❌${NC} SSH key not found: $SSH_PUB_KEY_PATH"
    echo ""
    read -p "Would you like to generate an SSH key now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Generating SSH key...${NC}"
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "terraform-lab-key"
        chmod 600 "$SSH_KEY_PATH"
        chmod 644 "$SSH_PUB_KEY_PATH"
        echo -e "${GREEN}✅ SSH key generated successfully${NC}"
    else
        echo -e "${RED}❌ SSH key is required. Please generate one manually or run this script again.${NC}"
        exit 1
    fi
fi

# Choose lab path
echo -e "\n${BLUE}📖 Choose Your Lab Path${NC}\n"

cat << 'EOF'
Two paths are available:

  A) Full Experience (with Azure DevOps)
     - Includes pipeline testing
     - Requires Azure DevOps setup (~30-40 min)
     - Best for: Learning CI/CD integration

  B) Simplified (Direct VM Testing) ⭐ RECOMMENDED
     - Focus on DNS troubleshooting
     - No Azure DevOps needed (~15-20 min)
     - Best for: Learning DNS concepts quickly

EOF

read -p "Which path would you like to follow? (A/B): " -n 1 -r LAB_PATH
echo ""

if [[ $LAB_PATH =~ ^[Aa]$ ]]; then
    CHOSEN_PATH="A"
    echo -e "${YELLOW}You chose Path A (Full Experience with Azure DevOps)${NC}"
    echo -e "Next steps:"
    echo -e "  1. See ${BLUE}docs/PATH_A_WITH_ADO.md${NC} for Azure DevOps setup"
    echo -e "  2. See ${BLUE}docs/RESOURCES.md${NC} for resource creation guide"
    echo -e "  3. Continue with Terraform deployment below"
else
    CHOSEN_PATH="B"
    echo -e "${GREEN}You chose Path B (Simplified Direct Testing) ⭐${NC}"
    echo -e "Next steps:"
    echo -e "  1. See ${BLUE}docs/PATH_B_DIRECT.md${NC} for lab guide"
    echo -e "  2. Continue with Terraform deployment below"
fi

# Terraform setup
echo -e "\n${BLUE}🏗️  Terraform Configuration${NC}\n"

cd terraform

if [ ! -f "terraform.tfvars" ]; then
    if [ -f "terraform.tfvars.example" ]; then
        echo -e "${YELLOW}Creating terraform.tfvars from example...${NC}"
        cp terraform.tfvars.example terraform.tfvars
        
        # Insert SSH public key
        SSH_PUB_KEY=$(cat "$SSH_PUB_KEY_PATH")
        
        # Use sed to update the SSH key in terraform.tfvars
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s|^admin_ssh_key.*|admin_ssh_key = \"$SSH_PUB_KEY\"|" terraform.tfvars
        else
            # Linux
            sed -i "s|^admin_ssh_key.*|admin_ssh_key = \"$SSH_PUB_KEY\"|" terraform.tfvars
        fi
        
        echo -e "${GREEN}✅ terraform.tfvars created${NC}"
        echo -e "${YELLOW}📝 Please review and customize terraform.tfvars if needed:${NC}"
        echo -e "   - key_vault_name (must be globally unique)"
        echo -e "   - resource group names"
        echo -e "   - admin_password"
        echo ""
        read -p "Press Enter to continue after reviewing terraform.tfvars..."
    else
        echo -e "${RED}❌ terraform.tfvars.example not found${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ terraform.tfvars already exists${NC}"
fi

# Initialize Terraform
echo -e "\n${BLUE}🔧 Terraform Initialization${NC}\n"

if [ ! -d ".terraform" ]; then
    echo -e "${YELLOW}Initializing Terraform...${NC}"
    terraform init
    echo -e "${GREEN}✅ Terraform initialized${NC}"
else
    echo -e "${GREEN}✅ Terraform already initialized${NC}"
fi

# Summary
echo -e "\n${GREEN}✅ Setup Complete!${NC}\n"

cat << EOF
╔════════════════════════════════════════════════════════════╗
║                   🎉 Setup Successful                      ║
╚════════════════════════════════════════════════════════════╝

Next Steps:

1. Review your Terraform configuration:
   ${BLUE}cd terraform${NC}
   ${BLUE}terraform plan${NC}

2. Deploy the infrastructure:
   ${BLUE}terraform apply${NC}

3. Follow your chosen lab path:
EOF

if [ "$CHOSEN_PATH" = "A" ]; then
    echo -e "   ${BLUE}Path A:${NC} docs/PATH_A_WITH_ADO.md"
    echo -e "   - Register Azure DevOps agents"
    echo -e "   - Create service connections"
    echo -e "   - Run pipeline tests"
else
    echo -e "   ${BLUE}Path B:${NC} docs/PATH_B_DIRECT.md"
    echo -e "   - SSH to test VM"
    echo -e "   - Run DNS troubleshooting exercises"
    echo -e "   - Test directly from VMs"
fi

echo ""
echo -e "4. When finished, clean up resources:"
echo -e "   ${BLUE}terraform destroy${NC}"
echo ""
echo -e "📚 Documentation: ${BLUE}labs/dns-standalone/README.md${NC}"
echo -e "❓ Troubleshooting: ${BLUE}docs/TROUBLESHOOTING.md${NC}"
echo ""
echo -e "${GREEN}Happy troubleshooting! 🚀${NC}"
echo ""
