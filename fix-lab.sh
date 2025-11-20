#!/bin/bash
set -e

echo "=================================================="
echo "   DNS Troubleshooting Lab - Fix Scenario"
echo "=================================================="

echo "Restoring Correct DNS Configuration..."
terraform apply -auto-approve -var="lab_scenario=base"

echo "✅ Lab is now FIXED. The DNS record points to the correct Private Endpoint IP."
echo "   Run the pipeline 'DNS-Troubleshooting' to verify success."
