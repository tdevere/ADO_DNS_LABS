#!/bin/bash
set -e

LAB_ID=$1

if [ -z "$LAB_ID" ]; then
    echo "Usage: ./fix-lab.sh <lab1|lab2|lab3>"
    exit 1
fi

echo "=================================================="
echo "   DNS Troubleshooting Lab - Fix Scenario: $LAB_ID"
echo "=================================================="

echo "Restoring Correct Configuration..."
terraform apply -auto-approve -var="lab_scenario=base"

echo "✅ Lab is now FIXED. Configuration restored to base state."
echo "   Run the pipeline or check 'nslookup' to verify success."
