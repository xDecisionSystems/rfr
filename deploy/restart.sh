#!/usr/bin/env bash
# restart.sh
#
# Restarts all rag-system services in dependency order.
# Must be run as root inside the LXC.
#
# Usage:
#   ./deploy/restart.sh            # restart all
#   ./deploy/restart.sh --status   # show service status only

set -euo pipefail

QDRANT_PORT=6333
RAG_PORT=8000

STATUS_ONLY=0
[[ "${1:-}" == "--status" ]] && STATUS_ONLY=1

log()  { echo "[restart] $*"; }
pass() { echo "[restart] OK: $*"; }
fail() { echo "[restart] FAIL: $*" >&2; exit 1; }

SERVICES=(qdrant rag-api)

if [[ "$STATUS_ONLY" == "1" ]]; then
  echo "Service status:"
  for svc in "${SERVICES[@]}"; do
    status="$(systemctl is-active "$svc" 2>/dev/null || echo inactive)"
    echo "  ${svc}: ${status}"
  done
  exit 0
fi

# Qdrant must be healthy before rag-api starts.
log "Restarting qdrant ..."
systemctl restart qdrant

log "Waiting for Qdrant on port ${QDRANT_PORT} ..."
for i in $(seq 1 15); do
  curl -sf "http://127.0.0.1:${QDRANT_PORT}/healthz" > /dev/null 2>&1 && break
  [[ "$i" == "15" ]] && fail "qdrant did not come up"
  sleep 2
done
pass "qdrant"

log "Restarting rag-api ..."
systemctl restart rag-api

log "Waiting for rag-api on port ${RAG_PORT} ..."
for i in $(seq 1 10); do
  curl -sf "http://127.0.0.1:${RAG_PORT}/health" > /dev/null 2>&1 && break
  [[ "$i" == "10" ]] && fail "rag-api did not pass health check"
  sleep 2
done
pass "rag-api"

echo ""
echo "All services restarted successfully."
echo ""
systemctl is-active "${SERVICES[@]}" 2>/dev/null | \
  paste - - | awk '{printf "  qdrant:%s  rag-api:%s\n", $1, $2}'
