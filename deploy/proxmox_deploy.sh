#!/usr/bin/env bash
# proxmox_deploy.sh
#
# Creates a Proxmox LXC and deploys the research RAG system:
#   - qdrant        Native vector database          port 6333 (localhost)
#   - rag-api       FastAPI RAG query/ingest API    port 8000
#
# Requirements (local machine):
#   - SSH access to the Proxmox host as root (or a user with pct privileges)
#
# Usage:
#   ./deploy/proxmox_deploy.sh [options]
#
# Options (all have defaults; set via env var or flag):
#   --proxmox-host      Proxmox SSH target             (default: $PROXMOX_HOST or prompt)
#   --hostname-postfix  Suffix appended to hostname     (default: prompt, e.g. "aev" → rag-system-aev)
#   --vmid              LXC container ID                (default: $VMID or 200)
#   --storage           Proxmox storage pool            (default: local-lvm)
#   --bridge            LXC network bridge              (default: vmbr0)
#   --repo-url          Git repo URL                    (default: $REPO_URL or prompt)
#   --repo-branch       Git branch to deploy            (default: main)
#   --ip                Static IP (CIDR) or dhcp        (default: dhcp)
#   --gateway           Network gateway                 (required for static IP)
#   --dns               DNS server                      (default: 8.8.8.8)
#   --template          LXC template name               (auto-detected if omitted)
#   --dry-run           Print commands without executing

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
PROXMOX_HOST="${PROXMOX_HOST:-}"
VMID="${VMID:-200}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE="${BRIDGE:-vmbr0}"
REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
LXC_IP="${LXC_IP:-dhcp}"
GATEWAY="${GATEWAY:-}"
DNS="${DNS:-8.8.8.8}"
TEMPLATE="${TEMPLATE:-}"
DRY_RUN=0

LXC_HOSTNAME_BASE="rag-system"
LXC_HOSTNAME_POSTFIX="${LXC_HOSTNAME_POSTFIX:-}"
LXC_HOSTNAME=""   # resolved after prompts

INSTALL_DIR="/opt/rag-system"
VENV_DIR="/opt/rag-env"
QDRANT_DIR="/opt/qdrant"
RAG_PORT=8000
QDRANT_PORT=6333
MEMORY=2048
SWAP=512
CORES=2
DISK_SIZE="12G"

# ─── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --proxmox-host)     PROXMOX_HOST="$2";         shift 2 ;;
    --hostname-postfix) LXC_HOSTNAME_POSTFIX="$2"; shift 2 ;;
    --vmid)             VMID="$2";                 shift 2 ;;
    --storage)          STORAGE="$2";              shift 2 ;;
    --bridge)           BRIDGE="$2";               shift 2 ;;
    --repo-url)         REPO_URL="$2";             shift 2 ;;
    --repo-branch)      REPO_BRANCH="$2";          shift 2 ;;
    --ip)               LXC_IP="$2";               shift 2 ;;
    --gateway)          GATEWAY="$2";              shift 2 ;;
    --dns)              DNS="$2";                  shift 2 ;;
    --template)         TEMPLATE="$2";             shift 2 ;;
    --dry-run)          DRY_RUN=1;                 shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[deploy] $*"; }
die()  { echo "[deploy] ERROR: $*" >&2; exit 1; }

SSH_SOCKET=""

ssh_open() {
  local host="$1"
  SSH_SOCKET="$(mktemp -u /tmp/ssh-mux-XXXXXX)"
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] ssh -M -o ControlMaster=yes ... root@${host}"
    return 0
  fi
  ssh -o StrictHostKeyChecking=accept-new \
      -o ControlMaster=yes \
      -o ControlPath="${SSH_SOCKET}" \
      -o ControlPersist=yes \
      -fN "root@${host}"
  trap 'ssh_close' EXIT
}

ssh_close() {
  if [[ -n "$SSH_SOCKET" && "$DRY_RUN" != "1" ]]; then
    ssh -o ControlPath="${SSH_SOCKET}" -O exit "root@${PROXMOX_HOST}" 2>/dev/null || true
  fi
}

ssh_run() {
  local host="$1"; shift
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] ssh root@${host} $*"
    return 0
  fi
  ssh -o ControlPath="${SSH_SOCKET}" "root@${host}" "$@"
}

lxc_exec() {
  local vmid="$1"; shift
  ssh_run "$PROXMOX_HOST" "pct exec ${vmid} -- bash -c $(printf '%q' "$*")"
}

# ─── Prompt for required values ───────────────────────────────────────────────
if [[ -z "$PROXMOX_HOST" ]]; then
  read -rp "Proxmox host (IP or hostname): " PROXMOX_HOST
fi
[[ -z "$PROXMOX_HOST" ]] && die "PROXMOX_HOST is required."

if [[ -z "$REPO_URL" ]]; then
  read -rp "Git repo URL (e.g. https://github.com/org/repo): " REPO_URL
fi
[[ -z "$REPO_URL" ]] && die "REPO_URL is required."

log "Opening SSH connection to ${PROXMOX_HOST} ..."
ssh_open "$PROXMOX_HOST"

# ─── Search for existing rag-system deployments ───────────────────────────────
log "Searching for existing rag-system containers on ${PROXMOX_HOST} ..."
EXISTING_STACKS="$(ssh_run "$PROXMOX_HOST" \
  "pct list | awk 'NR>1 {print \$1}' | while read id; do
     h=\$(pct config \$id 2>/dev/null | awk -F': ' '/^hostname:/{print \$2}')
     case \"\$h\" in ${LXC_HOSTNAME_BASE}*) echo \"\$id \$h\" ;; esac
   done" || true)"

if [[ -n "$EXISTING_STACKS" ]]; then
  echo ""
  echo "  Existing rag-system containers on ${PROXMOX_HOST}:"
  while IFS= read -r line; do
    echo "    VMID $(echo "$line" | awk '{print $1}')  hostname: $(echo "$line" | awk '{print $2}')"
  done <<< "$EXISTING_STACKS"
fi

# ─── Resolve hostname postfix ─────────────────────────────────────────────────
if [[ -z "$LXC_HOSTNAME_POSTFIX" ]]; then
  echo ""
  read -rp "Hostname postfix (leave blank for none, e.g. 'aev' → ${LXC_HOSTNAME_BASE}-aev): " LXC_HOSTNAME_POSTFIX
fi
if [[ -n "$LXC_HOSTNAME_POSTFIX" ]]; then
  LXC_HOSTNAME="${LXC_HOSTNAME_BASE}-${LXC_HOSTNAME_POSTFIX}"
else
  LXC_HOSTNAME="${LXC_HOSTNAME_BASE}"
fi
log "Hostname: ${LXC_HOSTNAME}"

# ─── Resolve VMID ─────────────────────────────────────────────────────────────
FOUND_VMID="$(echo "$EXISTING_STACKS" | awk -v h="$LXC_HOSTNAME" '$2==h{print $1}')"

if [[ -n "$FOUND_VMID" ]]; then
  log "Found existing '${LXC_HOSTNAME}' at VMID ${FOUND_VMID} — will destroy and redeploy."
  VMID="$FOUND_VMID"
else
  log "No existing '${LXC_HOSTNAME}' — finding next available VMID ..."
  NEXT_VMID="$(ssh_run "$PROXMOX_HOST" \
    "pvesh get /cluster/nextid 2>/dev/null || \
     { used=\$(pct list | awk 'NR>1{print \$1}' | sort -n); \
       id=100; for u in \$used; do [ \$id -lt \$u ] && break; id=\$((u+1)); done; echo \$id; }" \
    | tr -d '[:space:]"' || echo "")"
  if [[ "$NEXT_VMID" =~ ^[0-9]+$ ]]; then
    VMID="$NEXT_VMID"
  fi
  read -rp "VMID for new container [${VMID}]: " VMID_INPUT
  VMID="${VMID_INPUT:-${VMID}}"
  [[ "$VMID" =~ ^[0-9]+$ ]] || die "VMID must be a number."
fi

# ─── Select storage ───────────────────────────────────────────────────────────
STORAGE_LIST=()
if [[ "$STORAGE" == "local-lvm" ]]; then
  log "Querying available storage on ${PROXMOX_HOST} ..."
  STORAGE_RAW="$(ssh_run "$PROXMOX_HOST" \
    "pvesm status --content rootdir 2>/dev/null | awk 'NR>1 && \$3==\"active\" {print \$1, \$2}'" \
    || true)"

  if [[ -n "$STORAGE_RAW" ]]; then
    mapfile -t STORAGE_LIST <<< "$STORAGE_RAW"
    echo ""
    echo "Available storage pools for LXC rootfs:"
    for i in "${!STORAGE_LIST[@]}"; do
      echo "  [$i] ${STORAGE_LIST[$i]}"
    done
    echo ""
    read -rp "Select storage index [0]: " STORAGE_CHOICE
    STORAGE_CHOICE="${STORAGE_CHOICE:-0}"
    STORAGE="$(echo "${STORAGE_LIST[$STORAGE_CHOICE]}" | awk '{print $1}')"
    log "Using storage: ${STORAGE}"
  else
    log "Could not query storage — using default: ${STORAGE}"
  fi
fi

if [[ "$LXC_IP" != "dhcp" && -z "$GATEWAY" ]]; then
  read -rp "Gateway IP (required for static IP): " GATEWAY
  [[ -z "$GATEWAY" ]] && die "GATEWAY is required when using a static IP."
fi

# ─── Detect or select LXC template ───────────────────────────────────────────
log "Querying available Debian templates on ${PROXMOX_HOST} ..."
TEMPLATES_RAW="$(ssh_run "$PROXMOX_HOST" \
  "pvesm status --content vztmpl 2>/dev/null | awk 'NR>1 {print \$1}' | \
   while read storage; do
     pveam list \"\$storage\" 2>/dev/null | awk 'NR>1 {print \$1}'
   done | grep -i 'debian' | sort -rV" \
  || true)"

if [[ -z "$TEMPLATE" ]]; then
  if [[ -z "$TEMPLATES_RAW" ]]; then
    die "No Debian templates found. Download one with: pveam download local debian-12-standard_*.tar.zst"
  fi
  mapfile -t TEMPLATE_LIST <<< "$TEMPLATES_RAW"
  log "Available Debian templates:"
  for i in "${!TEMPLATE_LIST[@]}"; do
    echo "  [$i] ${TEMPLATE_LIST[$i]}"
  done
  read -rp "Select template index or press Enter for newest (${TEMPLATE_LIST[0]}): " TMPL_CHOICE
  if [[ -z "$TMPL_CHOICE" || "$TMPL_CHOICE" == "auto" ]]; then
    TEMPLATE="${TEMPLATE_LIST[0]}"
  else
    TEMPLATE="${TEMPLATE_LIST[$TMPL_CHOICE]}"
  fi
fi
log "Using template: ${TEMPLATE}"

# ─── Select .env file ─────────────────────────────────────────────────────────
SEARCH_DIR="$(pwd)"
mapfile -t ENV_FILES < <(find "$SEARCH_DIR" -maxdepth 2 -name ".env*" -type f | sort)

ENV_FILE=""
echo ""
if [[ "${#ENV_FILES[@]}" -eq 0 ]]; then
  echo "  No .env files found in ${SEARCH_DIR} — will use .env.example from repo."
else
  echo "  Available .env files:"
  echo "    [0] (none — use .env.example from repo)"
  for i in "${!ENV_FILES[@]}"; do
    echo "    [$((i+1))] ${ENV_FILES[$i]}"
  done
  read -rp "  Select index or type a path [0]: " ENV_CHOICE
  ENV_CHOICE="${ENV_CHOICE:-0}"
  if [[ "$ENV_CHOICE" != "0" && "$ENV_CHOICE" =~ ^[0-9]+$ ]]; then
    idx=$((ENV_CHOICE - 1))
    if [[ "$idx" -ge 0 && "$idx" -lt "${#ENV_FILES[@]}" ]]; then
      ENV_FILE="${ENV_FILES[$idx]}"
      log "Using env file: ${ENV_FILE}"
    else
      echo "  Invalid index — will use .env.example from repo."
    fi
  elif [[ "$ENV_CHOICE" != "0" ]]; then
    expanded="${ENV_CHOICE/#\~/$HOME}"
    if [[ -f "$expanded" ]]; then
      ENV_FILE="$expanded"
      log "Using env file: ${ENV_FILE}"
    else
      echo "  File not found: ${expanded} — will use .env.example from repo."
    fi
  fi
fi

# ─── Confirm before proceeding ────────────────────────────────────────────────
echo ""
echo "  Proxmox host : ${PROXMOX_HOST}"
echo "  VMID         : ${VMID}"
echo "  Hostname     : ${LXC_HOSTNAME}"
echo "  IP           : ${LXC_IP}"
echo "  Template     : ${TEMPLATE}"
echo "  Memory       : ${MEMORY} MB    Disk: ${DISK_SIZE}    Cores: ${CORES}"
echo "  Repo         : ${REPO_URL} (branch: ${REPO_BRANCH})"
echo "  Install dir  : ${INSTALL_DIR}"
echo "  Env file     : ${ENV_FILE:-(repo .env.example)}"
echo ""
echo "  Services to install:"
echo "    qdrant     port ${QDRANT_PORT} (localhost only)"
echo "    rag-api    port ${RAG_PORT}"
echo ""
if [[ "$DRY_RUN" == "1" ]]; then
  echo "  *** DRY RUN — no changes will be made ***"
  echo ""
fi
read -rp "Proceed? [Y/n] " CONFIRM
CONFIRM="${CONFIRM:-y}"
[[ "${CONFIRM,,}" == "y" ]] || { log "Aborted."; exit 0; }

# ─── Destroy existing container if needed ────────────────────────────────────
EXISTS="$(ssh_run "$PROXMOX_HOST" "pct list | awk 'NR>1 {print \$1}' | grep -w '${VMID}' || true")"
if [[ -n "$EXISTS" ]]; then
  EXISTING_HOSTNAME="$(ssh_run "$PROXMOX_HOST" \
    "pct config ${VMID} | awk -F': ' '/^hostname:/{print \$2}'" || echo "unknown")"
  echo ""
  if [[ "$EXISTING_HOSTNAME" != "$LXC_HOSTNAME" ]]; then
    echo "  WARNING: VMID ${VMID} is occupied by '${EXISTING_HOSTNAME}',"
    echo "           which is NOT a rag-system container."
  else
    echo "  VMID ${VMID} ('${EXISTING_HOSTNAME}') will be permanently destroyed and redeployed."
  fi
  echo ""
  read -rp "  Destroy VMID ${VMID} ('${EXISTING_HOSTNAME}')? [Y/n] " CONFIRM_DESTROY
  CONFIRM_DESTROY="${CONFIRM_DESTROY:-y}"
  [[ "${CONFIRM_DESTROY,,}" == "y" ]] || die "Aborted."
  log "Stopping and destroying VMID ${VMID} ..."
  ssh_run "$PROXMOX_HOST" "pct stop ${VMID} --skiplock 1 2>/dev/null || true"
  ssh_run "$PROXMOX_HOST" "pct destroy ${VMID} --purge 1"
fi

# ─── Create LXC ───────────────────────────────────────────────────────────────
NET_CONFIG="name=eth0,bridge=${BRIDGE},ip=dhcp"
if [[ "$LXC_IP" != "dhcp" ]]; then
  NET_CONFIG="name=eth0,bridge=${BRIDGE},ip=${LXC_IP},gw=${GATEWAY}"
fi

# ZFS storage uses bare integer, others use G suffix.
DISK_SIZE_NUM="${DISK_SIZE//G/}"
ROOTFS_ARG="${STORAGE}:${DISK_SIZE}"
for entry in "${STORAGE_LIST[@]+"${STORAGE_LIST[@]}"}"; do
  name="$(echo "$entry" | awk '{print $1}')"
  stype="$(echo "$entry" | awk '{print $2}')"
  if [[ "$name" == "$STORAGE" && "$stype" == "zfspool" ]]; then
    ROOTFS_ARG="${STORAGE}:${DISK_SIZE_NUM}"
    break
  fi
done

log "Creating LXC ${VMID} (${LXC_HOSTNAME}) ..."
ssh_run "$PROXMOX_HOST" \
  "pct create ${VMID} ${TEMPLATE} \
    --hostname ${LXC_HOSTNAME} \
    --storage ${STORAGE} \
    --rootfs ${ROOTFS_ARG} \
    --memory ${MEMORY} \
    --swap ${SWAP} \
    --cores ${CORES} \
    --net0 ${NET_CONFIG} \
    --nameserver ${DNS} \
    --unprivileged 1 \
    --features nesting=1 \
    --start 1 \
    --onboot 1"

log "Waiting for LXC to be ready ..."
ssh_run "$PROXMOX_HOST" "sleep 6"

# ─── Locale ───────────────────────────────────────────────────────────────────
log "Configuring locale ..."
lxc_exec "$VMID" "
  apt-get update -qq
  apt-get install -y -qq locales
  sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
  locale-gen en_US.UTF-8
  update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
"

# ─── System packages ──────────────────────────────────────────────────────────
log "Installing system packages ..."
lxc_exec "$VMID" "
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3 python3-venv python3-pip build-essential curl git
"

# ─── Create raguser ───────────────────────────────────────────────────────────
log "Creating raguser ..."
lxc_exec "$VMID" "
  id -u raguser >/dev/null 2>&1 || useradd -m raguser
"

# ─── Clone repo ───────────────────────────────────────────────────────────────
log "Cloning ${REPO_URL} (branch: ${REPO_BRANCH}) ..."
lxc_exec "$VMID" "
  git clone --branch ${REPO_BRANCH} --depth 1 ${REPO_URL} ${INSTALL_DIR}
"

# ─── Upload .env file ─────────────────────────────────────────────────────────
ENV_DEST="${INSTALL_DIR}/.env"
if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  log "Uploading ${ENV_FILE} → LXC:${ENV_DEST} ..."
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[dry-run] scp ${ENV_FILE} → LXC:${ENV_DEST}"
  else
    tmp_remote="$(ssh_run "$PROXMOX_HOST" "mktemp")"
    scp -o ControlPath="${SSH_SOCKET}" "$ENV_FILE" "root@${PROXMOX_HOST}:${tmp_remote}"
    ssh_run "$PROXMOX_HOST" \
      "pct push ${VMID} ${tmp_remote} ${ENV_DEST} --perms 0600 && rm -f ${tmp_remote}"
  fi
  log "Env file uploaded."
else
  log "No env file supplied — copying .env.example ..."
  lxc_exec "$VMID" "cp ${INSTALL_DIR}/rag-system/.env.example ${ENV_DEST}"
  log "Edit ${ENV_DEST} on VMID ${VMID} to add your Azure OpenAI keys before using the API."
fi

# ─── Install Qdrant (native binary) ───────────────────────────────────────────
log "Installing Qdrant ..."
lxc_exec "$VMID" "bash ${INSTALL_DIR}/rag-system/install_qdrant.sh"

log "Installing Qdrant systemd service ..."
lxc_exec "$VMID" "
  cp ${INSTALL_DIR}/rag-system/deploy/qdrant.service /etc/systemd/system/qdrant.service
  systemctl daemon-reload
  systemctl enable qdrant
  systemctl start qdrant
"

log "Waiting for Qdrant on port ${QDRANT_PORT} ..."
lxc_exec "$VMID" "
  for i in \$(seq 1 15); do
    curl -sf http://127.0.0.1:${QDRANT_PORT}/healthz > /dev/null 2>&1 && exit 0
    sleep 2
  done
  echo 'Qdrant did not start in time'; exit 1
"
log "Qdrant PASSED."

# ─── Python venv + rag-api ────────────────────────────────────────────────────
log "Creating Python venv and installing dependencies ..."
lxc_exec "$VMID" "
  python3 -m venv ${VENV_DIR}
  ${VENV_DIR}/bin/pip install --quiet --upgrade pip
  ${VENV_DIR}/bin/pip install --quiet -r ${INSTALL_DIR}/rag-system/requirements.txt
"

log "Installing rag-api systemd service ..."
lxc_exec "$VMID" "
  cat > /etc/systemd/system/rag-api.service <<'EOF'
[Unit]
Description=Research RAG FastAPI Service
After=network.target qdrant.service
Requires=qdrant.service

[Service]
Type=simple
User=raguser
WorkingDirectory=${INSTALL_DIR}/rag-system
EnvironmentFile=${ENV_DEST}
ExecStart=${VENV_DIR}/bin/uvicorn api.main:app --host 0.0.0.0 --port ${RAG_PORT}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable rag-api
  systemctl start rag-api
"

log "Waiting for rag-api on port ${RAG_PORT} ..."
lxc_exec "$VMID" "
  for i in \$(seq 1 15); do
    curl -sf http://127.0.0.1:${RAG_PORT}/health > /dev/null 2>&1 && exit 0
    sleep 2
  done
  echo 'rag-api did not start in time'; exit 1
"
log "rag-api PASSED."

# ─── Summary ──────────────────────────────────────────────────────────────────
log ""
log "=== Deployment complete ==="
log ""

LXC_ACTUAL_IP="$(ssh_run "$PROXMOX_HOST" \
  "pct exec ${VMID} -- hostname -I 2>/dev/null | awk '{print \$1}'" || echo "(check manually)")"

echo "  rag-api health  http://${LXC_ACTUAL_IP}:${RAG_PORT}/health"
echo "  rag-api docs    http://${LXC_ACTUAL_IP}:${RAG_PORT}/docs"
echo "  Qdrant          http://${LXC_ACTUAL_IP}:${QDRANT_PORT}/dashboard  (localhost inside LXC)"
echo ""
echo "  Next steps:"
if [[ -z "$ENV_FILE" ]]; then
  echo "    1. Add Azure OpenAI keys to ${ENV_DEST} on VMID ${VMID},"
  echo "       then restart: pct exec ${VMID} -- bash ${INSTALL_DIR}/deploy/restart.sh"
else
  echo "    1. Env file uploaded from ${ENV_FILE} — verify Azure keys are correct."
fi
echo "    2. Place PDFs in ${INSTALL_DIR}/rag-system/data/papers/ and POST to /ingest."
echo "       Or run: pct exec ${VMID} -- bash -c 'source ${VENV_DIR}/bin/activate && python ${INSTALL_DIR}/rag-system/scripts/ingest_folder.py'"
echo ""

# ─── Optional Tailscale ───────────────────────────────────────────────────────
read -rp "Install Tailscale on VMID ${VMID}? [Y/n] " INSTALL_TAILSCALE
INSTALL_TAILSCALE="${INSTALL_TAILSCALE:-y}"
if [[ "${INSTALL_TAILSCALE,,}" == "y" ]]; then
  log "Installing Tailscale on VMID ${VMID} ..."
  ssh_run "$PROXMOX_HOST" \
    "bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/addon/add-tailscale-lxc.sh)\" -- ${VMID}"
  log "Tailscale install complete."
fi
