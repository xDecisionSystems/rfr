#!/usr/bin/env bash
set -euo pipefail

mkdir -p /opt/qdrant
cd /opt/qdrant

# Ensure service user exists even if setup.sh was skipped.
if ! id -u raguser >/dev/null 2>&1; then
  useradd -m raguser
fi

# Download Qdrant native binary
curl -L https://github.com/qdrant/qdrant/releases/latest/download/qdrant-x86_64-unknown-linux-gnu.tar.gz -o qdrant.tar.gz

tar -xzf qdrant.tar.gz
chmod +x qdrant
mkdir -p /opt/qdrant/storage

# Align ownership for systemd service.
chown -R raguser:raguser /opt/qdrant

echo "Qdrant installed at /opt/qdrant/qdrant"
echo "Start with: /opt/qdrant/qdrant"
