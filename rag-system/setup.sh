#!/usr/bin/env bash
set -euo pipefail

apt update && apt upgrade -y

# Core dependencies
apt install -y python3 python3-venv python3-pip build-essential curl git

# Create project user (optional)
if ! id -u raguser >/dev/null 2>&1; then
  useradd -m raguser
fi

# Python virtual environment
python3 -m venv /opt/rag-env
source /opt/rag-env/bin/activate
pip install --upgrade pip

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pip install -r "${SCRIPT_DIR}/requirements.txt"

echo "Base Debian setup complete."
echo "Activate environment with: source /opt/rag-env/bin/activate"
