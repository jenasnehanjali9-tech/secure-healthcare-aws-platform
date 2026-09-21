#!/usr/bin/env bash
# Launches the dashboard pointed at your real, deployed AWS account.
# Run this AFTER `terraform apply` has succeeded and AWS credentials are configured.
set -euo pipefail

cd "$(dirname "$0")/../dashboard"

if [[ ! -d ".venv" ]]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
pip install -q -r requirements.txt

export USE_LIVE_AWS=true
export AWS_REGION="${AWS_REGION:-us-east-1}"

echo "==> Launching dashboard in LIVE AWS mode (region: $AWS_REGION) on http://localhost:8501 ..."
streamlit run app.py
