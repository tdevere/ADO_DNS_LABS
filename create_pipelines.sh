#!/bin/bash
set -e

# Check if logged in
echo "Checking Azure DevOps authentication..."
az account show > /dev/null 2>&1 || { echo "Please run 'az login' first."; exit 1; }

ORG_URL="https://dev.azure.com/AIADOLAB"
PROJECT="ADO-Pipeline-Network-Troubleshooting-Labs"
REPO="ADO-Pipeline-Network-Troubleshooting-Labs"

echo "Configuring defaults..."
az devops configure --defaults organization=$ORG_URL project=$PROJECT

echo "Creating 'Setup Lab' pipeline..."
az pipelines create --name "Setup Lab" \
    --description "Pipeline to setup the lab environment" \
    --repository $REPO \
    --branch main \
    --yaml-path azure-pipelines-setup.yml \
    --skip-first-run

echo "Creating 'Break Lab' pipeline..."
az pipelines create --name "Break Lab" \
    --description "Pipeline to break the lab environment" \
    --repository $REPO \
    --branch main \
    --yaml-path azure-pipelines-break.yml \
    --skip-first-run

echo "Creating 'Destroy Lab' pipeline..."
az pipelines create --name "Destroy Lab" \
    --description "Pipeline to destroy the lab environment" \
    --repository $REPO \
    --branch main \
    --yaml-path azure-pipelines-destroy.yml \
    --skip-first-run

echo "All pipelines created successfully!"
