#!/bin/bash
set -e

LAB_ID=$1

if [ -z "$LAB_ID" ]; then
    echo "Usage: ./break-lab.sh <lab1|lab2|lab3>"
    exit 1
fi

echo "=================================================="
echo "   DNS Troubleshooting Lab - Break Scenario: $LAB_ID"
echo "=================================================="

case $LAB_ID in
    "lab1")
        echo "Applying Scenario 1..."
        terraform apply -auto-approve -var="lab_scenario=dns_exercise1"
        echo "✅ DNS LAB 1 Scenario Applied. The environment is now in a failure state."
        ;;
    "lab2")
        echo "Applying Missing VNet Link..."
        terraform apply -auto-approve -var="lab_scenario=dns_exercise2"
        echo "✅ Lab 2 is now BROKEN. The VNet link to the Private DNS Zone has been removed."
        ;;
    "lab3")
        echo "Applying Custom DNS Misconfiguration..."
        terraform apply -auto-approve -var="lab_scenario=dns_exercise3"
        echo "✅ Lab 3 is now BROKEN. The VNet is using a custom DNS server that cannot resolve the private zone."
        ;;
    *)
        echo "❌ Invalid Lab ID. Use lab1, lab2, or lab3."
        exit 1
        ;;
esac

echo "   Run the pipeline or check 'nslookup' to see the failure."
