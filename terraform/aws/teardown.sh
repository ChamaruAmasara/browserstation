#!/bin/bash

# Teardown script for BrowserStation on AWS
# This script destroys both Kubernetes resources (02-k8s) and infrastructure (01-infra)

set -e  # Exit on error

echo "🔥 Starting BrowserStation teardown..."
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're in the right directory
if [ ! -d "01-infra" ] || [ ! -d "02-k8s" ]; then
    print_error "This script must be run from the terraform/aws directory"
    exit 1
fi

# Confirm destruction
echo -e "${YELLOW}⚠️  WARNING: This will destroy all BrowserStation resources in AWS!${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    print_status "Teardown cancelled."
    exit 0
fi

# Destroy 02-k8s first (depends on 01-infra)
print_status "Destroying Kubernetes resources (02-k8s)..."
cd 02-k8s

# Check if terraform state exists
if [ -f "terraform.tfstate" ] || [ -d ".terraform" ]; then
    print_status "Running terraform destroy on 02-k8s..."
    if terraform destroy -auto-approve; then
        print_status "Kubernetes resources destroyed successfully!"
    else
        print_warning "Some Kubernetes resources may not have been destroyed. Check AWS console."
        print_warning "You may need to manually delete LoadBalancer security groups."
    fi
else
    print_status "No terraform state found in 02-k8s, skipping..."
fi

cd ..

# Destroy 01-infra
print_status "Destroying infrastructure (01-infra)..."
cd 01-infra

# Check if terraform state exists
if [ -f "terraform.tfstate" ] || [ -d ".terraform" ]; then
    print_status "Running terraform destroy on 01-infra..."
    
    # Sometimes VPC deletion fails due to leftover resources
    MAX_RETRIES=3
    RETRY_COUNT=0
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if terraform destroy -auto-approve; then
            print_status "Infrastructure destroyed successfully!"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                print_warning "Destroy failed (attempt $RETRY_COUNT/$MAX_RETRIES). Retrying in 30 seconds..."
                print_warning "This often happens due to leftover ENIs or security groups."
                sleep 30
            else
                print_error "Infrastructure destruction failed after $MAX_RETRIES attempts!"
                print_error "You may need to manually clean up resources in AWS console:"
                print_error "  - Check for leftover security groups created by Kubernetes"
                print_error "  - Check for ENIs (Elastic Network Interfaces) in the VPC"
                print_error "  - Check EC2 instances are terminated"
                exit 1
            fi
        fi
    done
else
    print_status "No terraform state found in 01-infra, skipping..."
fi

cd ..

# Summary
echo ""
print_status "✅ Teardown completed!"
echo ""
echo "Note: Always verify in AWS Console that all resources have been deleted:"
echo "  - EKS Cluster"
echo "  - EC2 Instances" 
echo "  - VPC and subnets"
echo "  - Security Groups"
echo "  - Load Balancers"
echo "  - ECR Repository"