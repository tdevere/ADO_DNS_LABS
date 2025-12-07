#!/bin/bash

#######################################################################
# SSH Key Generation Script
# Generates an RSA SSH key pair for Terraform lab use
#######################################################################

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

FORCE="$1"
echo -e "${GREEN}🔑 SSH Key Generation for DNS Lab${NC}\n"

# Default key path
SSH_KEY_PATH="$HOME/.ssh/terraform_lab_key"
SSH_PUB_KEY_PATH="${SSH_KEY_PATH}.pub"

# Check if key already exists
if [ -f "$SSH_PUB_KEY_PATH" ]; then
    if [[ "$FORCE" == "--force" ]]; then
        echo -e "${YELLOW}⚠️  --force specified, regenerating SSH key at: $SSH_PUB_KEY_PATH${NC}"
    else
        echo -e "${YELLOW}⚠️  SSH key already exists at: $SSH_PUB_KEY_PATH${NC}"
        echo ""
        read -p "Do you want to overwrite it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}✅ Using existing SSH key${NC}"
            echo ""
            echo "Public key:"
            cat "$SSH_PUB_KEY_PATH"
            echo ""
            exit 0
        fi
        echo -e "${YELLOW}Overwriting existing key...${NC}"
    fi
fi

# Ensure .ssh directory exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Generate SSH key
echo -e "${GREEN}Generating RSA 4096-bit SSH key...${NC}"
ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "terraform-dns-lab-key"

# Set proper permissions
chmod 600 "$SSH_KEY_PATH"
chmod 644 "$SSH_PUB_KEY_PATH"

# Success message
echo ""
echo -e "${GREEN}✅ SSH key generated successfully!${NC}"
echo ""
echo "Private key: $SSH_KEY_PATH"
echo "Public key:  $SSH_PUB_KEY_PATH"
echo ""
echo -e "${YELLOW}📋 Your public key (copy this to terraform.tfvars):${NC}"
echo ""
cat "$SSH_PUB_KEY_PATH"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Copy the public key above"
echo "2. Edit terraform.tfvars"
echo "3. Set admin_ssh_key = \"<paste-public-key-here>\""
echo ""
