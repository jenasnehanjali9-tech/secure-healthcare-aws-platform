#!/usr/bin/env bash
# Deploys the full AWS infrastructure with Terraform.
# Prerequisites: AWS CLI configured (aws configure), Terraform >= 1.5 installed.
set -euo pipefail

cd "$(dirname "$0")/../infrastructure"

echo "==> Checking AWS credentials..."
aws sts get-caller-identity

echo "==> Terraform init..."
terraform init

echo "==> Terraform validate..."
terraform validate

echo "==> Terraform plan..."
terraform plan -out=tfplan

read -p "Apply this plan? (yes/no): " CONFIRM
if [[ "$CONFIRM" == "yes" ]]; then
  terraform apply tfplan
  echo "==> Deployment complete. Outputs:"
  terraform output
else
  echo "Aborted."
fi
