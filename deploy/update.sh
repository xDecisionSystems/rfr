#!/usr/bin/env bash
# update.sh
#
# Updates the rag-system on the LXC by pulling the latest code from the repo,
# reinstalling Python dependencies, and restarting services in order.
#
# Must be run as root inside the LXC (or via: pct exec <vmid> -- bash /opt/rag-system/deploy/update.sh)
#
# Usage:
#   ./deploy/update.sh [--branch <branch>] [--dry-run]

set -euo pipefail

INSTALL_DIR="/opt/rag-system"
VENV_DIR="/opt/rag-env"
BRANCH="${BRANCH:-main}"
DRY_RUN=0

QDRANT_PORT=6333
RAG_PORT=8000

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)  BRANCH="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1;   shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[update] $*"; }
die()  { echo "[update] ERROR: $*" >&2; exit 1; }
pass() { echo "[update] OK: $*"; }

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

[[ "${EUID}" -ne 0 ]] && die "Run as root."
[[ -d "$INSTALL_DIR" ]] || die "${INSTALL_DIR} not found. Has the LXC been deployed?"

# ─── Show current version ─────────────────────────────────────────────────────
read_version() {
  local f="${INSTALL_DIR}/VERSION.md"
  [[ -f "$f" ]] && grep -E '^VERSION_NAME=' "$f" | cut -d= -f2- | tr -d '"'"'" || echo "unknown"
}

OLD_VERSION="$(read_version)"
log "Current version: ${OLD_VERSION}"

# ─── Pull latest code ─────────────────────────────────────────────────────────
log "Pulling latest code (branch: ${BRANCH}) ..."
run git -C "$INSTALL_DIR" fetch --depth 1 origin "${BRANCH}"
run git -C "$INSTALL_DIR" reset --hard "origin/${BRANCH}"

NEW_VERSION="$(read_version)"
log "New version: ${NEW_VERSION}"

# ─── Confirm ──────────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "0" ]]; then
  echo ""
  read -rp "[update] Proceed with dependency update and restart? [Y/n] " CONFIRM
  CONFIRM="${CONFIRM:-Y}"
  [[ "${CONFIRM,,}" == "n" ]] && { log "Aborted."; exit 0; }
fi

# ─── Update Python dependencies ───────────────────────────────────────────────
log "Updating Python dependencies ..."
run "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
run "${VENV_DIR}/bin/pip" install --quiet -r "${INSTALL_DIR}/rag-system/requirements.txt"

# ─── Reload systemd units (in case service files changed) ─────────────────────
log "Reloading systemd units ..."
run systemctl daemon-reload

# ─── Restart Qdrant ───────────────────────────────────────────────────────────
log "Restarting qdrant ..."
run systemctl restart qdrant

log "Waiting for Qdrant on port ${QDRANT_PORT} ..."
for i in $(seq 1 15); do
  curl -sf "http://127.0.0.1:${QDRANT_PORT}/healthz" > /dev/null 2>&1 && break
  [[ "$i" == "15" ]] && die "qdrant did not come up after 30s"
  sleep 2
done
pass "qdrant"

# ─── Restart rag-api ──────────────────────────────────────────────────────────
log "Restarting rag-api ..."
run systemctl restart rag-api

for i in $(seq 1 10); do
  curl -sf "http://127.0.0.1:${RAG_PORT}/health" > /dev/null 2>&1 && break
  [[ "$i" == "10" ]] && die "rag-api did not pass health check"
  sleep 2
done
pass "rag-api"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
log "=== Update complete ==="
log "  ${OLD_VERSION} → ${NEW_VERSION}"
echo ""
systemctl is-active qdrant rag-api 2>/dev/null | \
  paste - - | awk '{printf "  qdrant:%s  rag-api:%s\n", $1, $2}'
