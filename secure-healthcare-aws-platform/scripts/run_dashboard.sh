#!/usr/bin/env bash
# Sets up a virtual environment and launches the Streamlit dashboard in demo mode
# (uses the bundled synthetic data — no AWS account required).
set -euo pipefail

cd "$(dirname "$0")/../dashboard"

if [[ ! -d ".venv" ]]; then
  echo "==> Creating virtual environment..."
  python3 -m venv .venv
fi

source .venv/bin/activate

echo "==> Installing dependencies..."
pip install -q -r requirements.txt

echo "==> Launching dashboard on http://localhost:8501 ..."
streamlit run app.py
