#!/bin/bash
set -e

echo "=================================================="
echo "   DNS Troubleshooting Lab - Break Scenario"
echo "=================================================="

echo "Applying DNS Misconfiguration..."
terraform apply -auto-approve -var="lab_scenario=dns_exercise1"

echo "✅ Lab is now BROKEN. The DNS record points to the wrong IP."
echo "   Run the pipeline 'DNS-Troubleshooting' to see the failure."
