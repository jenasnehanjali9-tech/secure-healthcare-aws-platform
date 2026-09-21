#!/usr/bin/env bash
# Tears down all AWS resources created by this project to avoid ongoing charges.
set -euo pipefail

cd "$(dirname "$0")/../infrastructure"

echo "This will DESTROY all resources in this Terraform workspace (Aurora, S3, KMS, IAM, Config, CloudTrail)."
read -p "Type 'destroy' to confirm: " CONFIRM
if [[ "$CONFIRM" == "destroy" ]]; then
  terraform destroy
else
  echo "Aborted."
fi
