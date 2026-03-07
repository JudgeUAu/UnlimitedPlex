#!/bin/bash
# =============================================================================
#  UnlimitedPlex Beta - Modular Setup Script
#  Installs only the services you select, with multiple instance support
# =============================================================================
#
#  USAGE (called by TUI or Windows GUI - do not run directly):
#    sudo bash setup_beta.sh --config /tmp/unlimitedplex_config.json
#
#  CONFIG JSON FORMAT:
#  {
#    "rd_token": "YOUR_RD_TOKEN",
#    "plex_token": "YOUR_PLEX_TOKEN",
#    "timezone": "America/New_York",
#    "zurg_version": "v0.9.3-final",
#    "instances": [
#      {
#        "name": "main",
#        "label": "Main",
#        "services": ["zurg","radarr","sonarr","prowlarr","decypharr","pulsarr"]
#      },
#      {
#        "name": "4k",
#        "label": "4K",
#        "services": ["zurg","radarr","sonarr","decypharr"]
#      },
#      {
#        "name": "kids",
#        "label": "Kids",
#        "services": ["radarr","sonarr"]
#      }
#    ],
#    "global_services": ["tautulli","nzbdav"],
#    "nzbdav_password": "changeme"
#  }
#
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/unlimitedplex_beta.log"
mkdir -p "$(dirname "$LOG_FILE")"

log()     { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
info()    { echo -e "${CYAN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; }
step()    { echo -e "\n${BOLD}${MAGENTA}━━━ $* ━━━${NC}\n" | tee -a "$LOG_FILE"; }
progress(){ echo -e "${BLUE}[STEP]${NC}  $*" | tee -a "$LOG_FILE"; }

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run as root: sudo bash setup_beta.sh --config /path/to/config.json"
  exit 1
fi

# ── Parse args ────────────────────────────────────────────────────────────────
CONFIG_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    *) error "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]]; then
  error "Config file not found: $CONFIG_FILE"
  exit 1
fi

# ── Parse JSON config (using python3 for reliability) ─────────────────────────
parse_json() {
  python3 -c "
import json, sys
data = json.load(open('$CONFIG_FILE'))
print(data.get('$1', ''))
"
}

parse_json_list() {
  python3 -c "
import json, sys
data = json.load(open('$CONFIG_FILE'))
val = data.get('$1', [])
print('\n'.join(val) if isinstance(val, list) else val)
"
}

parse_instances() {
  python3 -c "
import json
data = json.load(open('$CONFIG_FILE'))
for inst in data.get('instances', []):
    svcs = ','.join(inst.get('services', []))
    print(f&quot;{inst['name']}|{inst['label']}|{svcs}&quot;)
"
}

RD_TOKEN=$(parse_json "rd_token")
PLEX_TOKEN=$(parse_json "plex_token")
TZ=$(parse_json "timezone")
ZURG_VERSION=$(parse_json "zurg_version")
NZBDAV_PASSWORD=$(parse_json "nzbdav_password")

if [[ -z "$RD_TOKEN" ]]; then
  error "rd_token is required in config"
  exit 1
fi
if [[ -z "$PLEX_TOKEN" ]]; then
  error "plex_token is required in config"
  exit 1
fi
[[ -z "$TZ" ]]           && TZ="America/New_York"
[[ -z "$ZURG_VERSION" ]] && ZURG_VERSION="v0.9.3-final"
[[ -z "$NZBDAV_PASSWORD" ]] && NZBDAV_PASSWORD="changeme"

export RD_TOKEN PLEX_TOKEN TZ ZURG_VERSION NZBDAV_PASSWORD
export DEBIAN_FRONTEND=noninteractive

# ── Port allocation ───────────────────────────────────────────────────────────
# Base ports - each instance offsets by instance_index * 100
# Instance 0 (main): base ports
# Instance 1 (4k):   base + 100
# Instance 2 (kids): base + 200
# etc.
PORT_ZURG=9999
PORT_RADARR=7878
PORT_SONARR=8989
PORT_PROWLARR=9696
PORT_DECYPHARR=8282
PORT_PULSARR=3003
PORT_TAUTULLI=8181
PORT_NZBDAV=3000
PORT_PLEX=32400   # Plex is always single instance

get_port() {
  local base_port=$1
  local instance_idx=$2
  echo $((base_port + instance_idx * 100))
}

# ── Directory helpers ─────────────────────────────────────────────────────────
BASE_DIR="/opt/unlimitedplex"
mkdir -p "$BASE_DIR"

# =============================================================================
# STEP 0 - SYSTEM UPDATE & DEPENDENCIES
# =============================================================================
step "Step 0 - System Update & Dependencies"

progress "Updating package lists..."
apt-get update -qq 2>&1 | tail -5
progress "Installing dependencies..."
apt-get install -y -qq \
  curl wget git unzip jq python3 python3-pip \
  ca-certificates gnupg lsb-release \
  fuse3 nfs-common \
  2>&1 | tail -5
log "Dependencies installed"

# =============================================================================
# STEP 1 - INSTALL DOCKER
# =============================================================================
step "Step 1 - Install Docker"

if command -v docker &>/dev/null; then
  log "Docker already installed: $(docker --version)"
else
  progress "Installing Docker..."
  curl -fsSL https://get.docker.com | bash 2>&1 | tail -10
  systemctl enable docker
  systemctl start docker
  log "Docker installed: $(docker --version)"
fi

# Ensure docker compose plugin works
if ! docker compose version &>/dev/null; then
  progress "Installing docker-compose-plugin..."
  apt-get install -y -qq docker-compose-plugin 2>&1 | tail -3
fi
log "Docker Compose: $(docker compose version)"

# =============================================================================
# STEP 2 - SHARED MOUNT SETUP
# =============================================================================
step "Step 2 - Shared Mount Setup"

progress "Setting up /mnt as shared mount point..."
mount --bind /mnt /mnt 2>/dev/null || true
mount --make-shared /mnt 2>/dev/null || true

# Ensure fuse is available
modprobe fuse 2>/dev/null || true
echo "user_allow_other" >> /etc/fuse.conf 2>/dev/null || true

log "Shared mount configured"

# =============================================================================
# STEP 3 - INSTALL PLEX MEDIA SERVER (always required)
# =============================================================================
step "Step 3 - Install Plex Media Server"

PLEX_DIR="$BASE_DIR/plex"
mkdir -p "$PLEX_DIR/config" "$PLEX_DIR/transcode"
mkdir -p /mnt/plex/movies /mnt/plex/tv /mnt/plex/movies4k /mnt/plex/tv4k /mnt/plex/kids/movies /mnt/plex/kids/tv

if docker ps -a --format '{{.Names}}' | grep -q '^plexmediaserver$'; then
  log "Plex container already exists - skipping"
else
  progress "Deploying Plex Media Server..."
  cat > "$PLEX_DIR/docker-compose.yml" << EOF
services:
  plex:
    image: plexinc/pms-docker:latest
    container_name: plexmediaserver
    restart: unless-stopped
    network_mode: host
    environment:
      - PLEX_CLAIM=${PLEX_TOKEN}
      - TZ=${TZ}
      - PLEX_UID=0
      - PLEX_GID=0
    volumes:
      - ${PLEX_DIR}/config:/config
      - ${PLEX_DIR}/transcode:/transcode
      - /mnt/plex:/mnt/plex:rshared
      - /mnt/remote:/mnt/remote:rshared
EOF
  cd "$PLEX_DIR" && docker compose up -d
  log "Plex Media Server deployed on port $PORT_PLEX"
fi

# =============================================================================
# STEP 4 - INSTALL TAUTULLI (global service - single instance)
# =============================================================================
install_tautulli() {
  step "Installing Tautulli (Plex Analytics)"
  local DIR="$BASE_DIR/tautulli"
  mkdir -p "$DIR/config"

  cat > "$DIR/docker-compose.yml" << EOF
services:
  tautulli:
    image: ghcr.io/tautulli/tautulli:latest
    container_name: tautulli
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      - PUID=0
      - PGID=0
    volumes:
      - ${DIR}/config:/config
    ports:
      - "${PORT_TAUTULLI}:8181"
    networks:
      - arr-network

networks:
  arr-network:
    external: true
    name: arr-stack_arr-network
EOF
  cd "$DIR" && docker compose up -d
  log "Tautulli deployed on port $PORT_TAUTULLI"
}

# =============================================================================
# STEP 5 - INSTALL NZBDAV (global service - single instance)
# =============================================================================
install_nzbdav() {
  step "Installing NZBDav (Usenet Streaming)"
  local DIR="$BASE_DIR/nzbdav"
  local PORT="${PORT_NZBDAV}"
  mkdir -p "$DIR/config" /mnt/remote/nzbdav

  cat > "$DIR/docker-compose.yml" << EOF
services:
  nzbdav:
    image: ghcr.io/debridmediamanager/nzbdav:latest
    container_name: nzbdav
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      - WEBDAV_PASSWORD=${NZBDAV_PASSWORD}
    volumes:
      - ${DIR}/config:/config
    ports:
      - "${PORT}:3000"
    networks:
      - arr-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 10s
      timeout: 5s
      retries: 5

  nzbdav_rclone:
    image: rclone/rclone:latest
    container_name: nzbdav_rclone
    restart: unless-stopped
    depends_on:
      nzbdav:
        condition: service_healthy
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse
    volumes:
      - /mnt:/mnt:rshared
    command: >
      mount
      :webdav,url=http://nzbdav:3000/,user=nzbdav,pass=${NZBDAV_PASSWORD}
      /mnt/remote/nzbdav
      --allow-other
      --vfs-cache-mode=off
      --buffer-size=32M
      --no-checksum
      --log-level=INFO
    networks:
      - arr-network

networks:
  arr-network:
    external: true
    name: arr-stack_arr-network
EOF
  cd "$DIR" && docker compose up -d nzbdav
  log "NZBDav deployed on port $PORT"
  info "NZBDav rclone sidecar will start after NZBDav is healthy"
  cd "$DIR" && docker compose up -d nzbdav_rclone
}

# =============================================================================
# STEP 6 - INSTALL ZURG (per instance)
# =============================================================================
install_zurg() {
  local INST_NAME="$1"
  local INST_LABEL="$2"
  local INST_IDX="$3"
  local PORT=$(get_port $PORT_ZURG $INST_IDX)
  local DIR="$BASE_DIR/instances/$INST_NAME/zurg"
  mkdir -p "$DIR"

  step "Installing Zurg for instance: $INST_LABEL (port $PORT)"

  cat > "$DIR/config.yml" << EOF
# Zurg config for instance: ${INST_LABEL}
zurg: v1
token: ${RD_TOKEN}
port: 9999
concurrent_workers: 32
check_for_changes_every_secs: 10
enable_repair: false
cache_network_test_results: true
serve_from_rclone: false
retain_folder_name_extension: false
retain_rd_torrent_name: false
directories:
  shows:
    group_order: 15
    group: media
    filters:
      - regex: '(?i)\b(s\d{2}e\d{2}|season\s?\d+|complete.series|miniseries)\b'
  movies:
    group_order: 20
    group: media
    filters:
      - regex: '.*'
EOF

  cat > "$DIR/docker-compose.yml" << EOF
services:
  zurg_${INST_NAME}:
    image: ghcr.io/debridmediamanager/zurg-testing:${ZURG_VERSION}
    container_name: zurg_${INST_NAME}
    restart: unless-stopped
    healthcheck:
      test: curl -f http://localhost:9999/dav/version.txt || exit 1
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 10s
    volumes:
      - ${DIR}/config.yml:/app/config.yml
    ports:
      - "${PORT}:9999"
    networks:
      - arr-network

  rclone_${INST_NAME}:
    image: rclone/rclone:latest
    container_name: rclone_${INST_NAME}
    restart: unless-stopped
    depends_on:
      zurg_${INST_NAME}:
        condition: service_healthy
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse
    volumes:
      - /mnt:/mnt:rshared
    command: >
      mount
      :http,url=http://zurg_${INST_NAME}:9999/dav/
      /mnt/remote/${INST_NAME}
      --allow-other
      --dir-cache-time=10s
      --vfs-cache-mode=full
      --vfs-cache-max-size=20G
      --vfs-cache-max-age=24h
      --buffer-size=32M
      --log-level=INFO
    networks:
      - arr-network

networks:
  arr-network:
    external: true
    name: arr-stack_arr-network
EOF

  mkdir -p /mnt/remote/$INST_NAME
  cd "$DIR" && docker compose up -d
  log "Zurg + Rclone deployed for instance: $INST_LABEL"
}

# =============================================================================
# STEP 7 - INSTALL PROWLARR (per instance)
# =============================================================================
install_prowlarr() {
  local INST_NAME="$1"
  local INST_LABEL="$2"
  local INST_IDX="$3"
  local PORT=$(get_port $PORT_PROWLARR $INST_IDX)
  local DIR="$BASE_DIR/instances/$INST_NAME/prowlarr"
  mkdir -p "$DIR/config"

  step "Installing Prowlarr for instance: $INST_LABEL (port $PORT)"

  cat >> "$BASE_DIR/instances/$INST_NAME/docker-compose.yml" << EOF

  prowlarr_${INST_NAME}:
    image: ghcr.io/hotio/prowlarr:release
    container_name: prowlarr_${INST_NAME}
    restart: unless-stopped
    environment:
      - PUID=0
      - PGID=0
      - TZ=${TZ}
    volumes:
      - ${DIR}/config:/config
      - /mnt:/mnt:rshared
    ports:
      - "${PORT}:9696"
    networks:
      - arr-network
EOF
  log "Prowlarr queued for instance: $INST_LABEL on port $PORT"
}

# =============================================================================
# STEP 8 - INSTALL RADARR (per instance)
# =============================================================================
install_radarr() {
  local INST_NAME="$1"
  local INST_LABEL="$2"
  local INST_IDX="$3"
  local PORT=$(get_port $PORT_RADARR $INST_IDX)
  local DIR="$BASE_DIR/instances/$INST_NAME/radarr"
  mkdir -p "$DIR/config"
  mkdir -p /mnt/plex/${INST_NAME}/movies

  step "Installing Radarr for instance: $INST_LABEL (port $PORT)"

  cat >> "$BASE_DIR/instances/$INST_NAME/docker-compose.yml" << EOF

  radarr_${INST_NAME}:
    image: ghcr.io/hotio/radarr:release
    container_name: radarr_${INST_NAME}
    restart: unless-stopped
    environment:
      - PUID=0
      - PGID=0
      - TZ=${TZ}
    volumes:
      - ${DIR}/config:/config
      - /mnt:/mnt:rshared
    ports:
      - "${PORT}:7878"
    networks:
      - arr-network
EOF
  log "Radarr queued for instance: $INST_LABEL on port $PORT"
}

# =============================================================================
# STEP 9 - INSTALL SONARR (per instance)
# =============================================================================
install_sonarr() {
  local INST_NAME="$1"
  local INST_LABEL="$2"
  local INST_IDX="$3"
  local PORT=$(get_port $PORT_SONARR $INST_IDX)
  local DIR="$BASE_DIR/instances/$INST_NAME/sonarr"
  mkdir -p "$DIR/config"
  mkdir -p /mnt/plex/${INST_NAME}/tv

  step "Installing Sonarr for instance: $INST_LABEL (port $PORT)"

  cat >> "$BASE_DIR/instances/$INST_NAME/docker-compose.yml" << EOF

  sonarr_${INST_NAME}:
    image: ghcr.io/hotio/sonarr:release
    container_name: sonarr_${INST_NAME}
    restart: unless-stopped
    environment:
      - PUID=0
      - PGID=0
      - TZ=${TZ}
    volumes:
      - ${DIR}/config:/config
      - /mnt:/mnt:rshared
    ports:
      - "${PORT}:8989"
    networks:
      - arr-network
EOF
  log "Sonarr queued for instance: $INST_LABEL on port $PORT"
}

# =============================================================================
# STEP 10 - INSTALL DECYPHARR (per instance)
# =============================================================================
install_decypharr() {
  local INST_NAME="$1"
  local INST_LABEL="$2"
  local INST_IDX="$3"
  local PORT=$(get_port $PORT_DECYPHARR $INST_IDX)
  local DIR="$BASE_DIR/instances/$INST_NAME/decypharr"
  mkdir -p "$DIR/config"

  step "Installing Decypharr for instance: $INST_LABEL (port $PORT)"

  # Decypharr config
  cat > "$DIR/config/config.yml" << EOF
# Decypharr config for instance: ${INST_LABEL}
debrid:
  type: realdebrid
  api_key: ${RD_TOKEN}

server:
  port: 8282
  host: 0.0.0.0

download_dir: /mnt/remote/${INST_NAME}
EOF

  cat >> "$BASE_DIR/instances/$INST_NAME/docker-compose.yml" << EOF

  decypharr_${INST_NAME}:
    image: cy01/blackhole:latest
    container_name: decypharr_${INST_NAME}
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    volumes:
      - ${DIR}/config:/config
      - /mnt:/mnt:rshared
    ports:
      - "${PORT}:8282"
    networks:
      - arr-network
EOF
  log "Decypharr queued for instance: $INST_LABEL on port $PORT"
}

# =============================================================================
# STEP 11 - INSTALL PULSARR (per instance)
# =============================================================================
install_pulsarr() {
  local INST_NAME="$1"
  local INST_LABEL="$2"
  local INST_IDX="$3"
  local PORT=$(get_port $PORT_PULSARR $INST_IDX)
  local DIR="$BASE_DIR/instances/$INST_NAME/pulsarr"
  mkdir -p "$DIR/config"

  step "Installing Pulsarr for instance: $INST_LABEL (port $PORT)"

  cat >> "$BASE_DIR/instances/$INST_NAME/docker-compose.yml" << EOF

  pulsarr_${INST_NAME}:
    image: lakker/pulsarr:latest
    container_name: pulsarr_${INST_NAME}
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    volumes:
      - ${DIR}/config:/config
    ports:
      - "${PORT}:3003"
    networks:
      - arr-network
EOF
  log "Pulsarr queued for instance: $INST_LABEL on port $PORT"
}

# =============================================================================
# STEP 12 - CREATE DOCKER NETWORK
# =============================================================================
step "Step 12 - Create Docker Network"

if ! docker network ls --format '{{.Name}}' | grep -q '^arr-stack_arr-network$'; then
  docker network create arr-stack_arr-network 2>/dev/null || true
  log "Docker network created: arr-stack_arr-network"
else
  log "Docker network already exists"
fi

# =============================================================================
# STEP 13 - PROCESS INSTANCES
# =============================================================================
step "Step 13 - Processing Instances"

INST_IDX=0
while IFS='|' read -r INST_NAME INST_LABEL INST_SERVICES; do
  [[ -z "$INST_NAME" ]] && continue

  step "Setting up instance: $INST_LABEL ($INST_NAME) [index $INST_IDX]"
  info "Services: $INST_SERVICES"

  INST_DIR="$BASE_DIR/instances/$INST_NAME"
  mkdir -p "$INST_DIR"

  # Initialize instance docker-compose.yml header
  cat > "$INST_DIR/docker-compose.yml" << EOF
# UnlimitedPlex Beta - Instance: ${INST_LABEL}
# Auto-generated by setup_beta.sh

services:
EOF

  # Process each service for this instance
  IFS=',' read -ra SVCS <<< "$INST_SERVICES"
  for SVC in "${SVCS[@]}"; do
    SVC=$(echo "$SVC" | tr -d '[:space:]')
    case "$SVC" in
      zurg)       install_zurg       "$INST_NAME" "$INST_LABEL" "$INST_IDX" ;;
      radarr)     install_radarr     "$INST_NAME" "$INST_LABEL" "$INST_IDX" ;;
      sonarr)     install_sonarr     "$INST_NAME" "$INST_LABEL" "$INST_IDX" ;;
      prowlarr)   install_prowlarr   "$INST_NAME" "$INST_LABEL" "$INST_IDX" ;;
      decypharr)  install_decypharr  "$INST_NAME" "$INST_LABEL" "$INST_IDX" ;;
      pulsarr)    install_pulsarr    "$INST_NAME" "$INST_LABEL" "$INST_IDX" ;;
      *) warn "Unknown service: $SVC - skipping" ;;
    esac
  done

  # Append network section to instance compose file
  cat >> "$INST_DIR/docker-compose.yml" << EOF

networks:
  arr-network:
    external: true
    name: arr-stack_arr-network
EOF

  # Deploy instance
  progress "Deploying instance: $INST_LABEL..."
  cd "$INST_DIR" && docker compose up -d 2>&1 | tail -10
  log "Instance $INST_LABEL deployed"

  INST_IDX=$((INST_IDX + 1))
done < <(parse_instances)

# =============================================================================
# STEP 14 - GLOBAL SERVICES
# =============================================================================
step "Step 14 - Global Services"

GLOBAL_SERVICES=$(parse_json_list "global_services")
while IFS= read -r SVC; do
  [[ -z "$SVC" ]] && continue
  case "$SVC" in
    tautulli) install_tautulli ;;
    nzbdav)   install_nzbdav ;;
    *) warn "Unknown global service: $SVC - skipping" ;;
  esac
done <<< "$GLOBAL_SERVICES"

# =============================================================================
# STEP 15 - GENERATE STARTUP SCRIPT
# =============================================================================
step "Step 15 - Generate Startup Script"

STARTUP_SCRIPT="/root/startup.sh"
cat > "$STARTUP_SCRIPT" << 'STARTUP_EOF'
#!/bin/bash
# UnlimitedPlex Beta - Auto-generated startup script
# Generated by setup_beta.sh - do not edit manually

LOG="/var/log/unlimitedplex_startup.log"
echo "[$(date)] Startup script running..." >> "$LOG"

# Ensure /mnt is shared
mount --bind /mnt /mnt 2>/dev/null || true
mount --make-shared /mnt 2>/dev/null || true
modprobe fuse 2>/dev/null || true

# Start Plex
echo "[$(date)] Starting Plex..." >> "$LOG"
cd /opt/unlimitedplex/plex && docker compose up -d >> "$LOG" 2>&1

STARTUP_EOF

# Add instance startups dynamically
INST_IDX=0
while IFS='|' read -r INST_NAME INST_LABEL INST_SERVICES; do
  [[ -z "$INST_NAME" ]] && continue
  cat >> "$STARTUP_SCRIPT" << EOF

# Start instance: ${INST_LABEL}
echo "[\$(date)] Starting instance: ${INST_LABEL}..." >> "\$LOG"
cd $BASE_DIR/instances/$INST_NAME && docker compose up -d >> "\$LOG" 2>&1

# Wait for Zurg/rclone mount if zurg is in this instance
if echo "$INST_SERVICES" | grep -q "zurg"; then
  WAIT=0
  while [[ \$WAIT -lt 120 ]]; do
    if ls /mnt/remote/$INST_NAME &>/dev/null; then
      echo "[\$(date)] Mount ready: /mnt/remote/$INST_NAME" >> "\$LOG"
      break
    fi
    sleep 5; WAIT=\$((WAIT + 5))
  done
fi
EOF
  INST_IDX=$((INST_IDX + 1))
done < <(parse_instances)

# Add global services to startup
while IFS= read -r SVC; do
  [[ -z "$SVC" ]] && continue
  case "$SVC" in
    tautulli)
      cat >> "$STARTUP_SCRIPT" << EOF

# Start Tautulli
echo "[\$(date)] Starting Tautulli..." >> "\$LOG"
cd $BASE_DIR/tautulli && docker compose up -d >> "\$LOG" 2>&1
EOF
      ;;
    nzbdav)
      cat >> "$STARTUP_SCRIPT" << EOF

# Start NZBDav
echo "[\$(date)] Starting NZBDav..." >> "\$LOG"
cd $BASE_DIR/nzbdav && docker compose up -d nzbdav >> "\$LOG" 2>&1
WAIT=0
while [[ \$WAIT -lt 120 ]]; do
  if curl -sf http://localhost:${PORT_NZBDAV}/ &>/dev/null; then
    echo "[\$(date)] NZBDav ready" >> "\$LOG"
    break
  fi
  sleep 5; WAIT=\$((WAIT + 5))
done
cd $BASE_DIR/nzbdav && docker compose up -d nzbdav_rclone >> "\$LOG" 2>&1
EOF
      ;;
  esac
done <<< "$GLOBAL_SERVICES"

cat >> "$STARTUP_SCRIPT" << 'STARTUP_EOF'

echo "[$(date)] All services started." >> "$LOG"
STARTUP_EOF

chmod +x "$STARTUP_SCRIPT"

# Register cron job
(crontab -l 2>/dev/null | grep -v startup.sh; echo "@reboot sleep 15 && bash /root/startup.sh") | crontab -
log "Startup script generated: $STARTUP_SCRIPT"
log "Cron job registered for @reboot"

# =============================================================================
# STEP 16 - SAVE INSTANCE MANIFEST
# =============================================================================
step "Step 16 - Save Instance Manifest"

MANIFEST="$BASE_DIR/instances.json"
cp "$CONFIG_FILE" "$MANIFEST"
log "Instance manifest saved: $MANIFEST"

# =============================================================================
# COMPLETE - PRINT SUMMARY
# =============================================================================
step "Setup Complete!"

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  UnlimitedPlex Beta - Installation Complete!${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${CYAN}Plex Media Server:${NC}  http://YOUR_IP:${PORT_PLEX}/web"
echo ""

# Print per-instance services
INST_IDX=0
while IFS='|' read -r INST_NAME INST_LABEL INST_SERVICES; do
  [[ -z "$INST_NAME" ]] && continue
  echo -e "  ${BOLD}${MAGENTA}Instance: $INST_LABEL${NC}"
  IFS=',' read -ra SVCS <<< "$INST_SERVICES"
  for SVC in "${SVCS[@]}"; do
    SVC=$(echo "$SVC" | tr -d '[:space:]')
    case "$SVC" in
      zurg)       echo -e "    ${CYAN}Zurg:${NC}       http://YOUR_IP:$(get_port $PORT_ZURG $INST_IDX)" ;;
      radarr)     echo -e "    ${CYAN}Radarr:${NC}     http://YOUR_IP:$(get_port $PORT_RADARR $INST_IDX)" ;;
      sonarr)     echo -e "    ${CYAN}Sonarr:${NC}     http://YOUR_IP:$(get_port $PORT_SONARR $INST_IDX)" ;;
      prowlarr)   echo -e "    ${CYAN}Prowlarr:${NC}   http://YOUR_IP:$(get_port $PORT_PROWLARR $INST_IDX)" ;;
      decypharr)  echo -e "    ${CYAN}Decypharr:${NC}  http://YOUR_IP:$(get_port $PORT_DECYPHARR $INST_IDX)" ;;
      pulsarr)    echo -e "    ${CYAN}Pulsarr:${NC}    http://YOUR_IP:$(get_port $PORT_PULSARR $INST_IDX)" ;;
    esac
  done
  echo ""
  INST_IDX=$((INST_IDX + 1))
done < <(parse_instances)

# Print global services
while IFS= read -r SVC; do
  [[ -z "$SVC" ]] && continue
  case "$SVC" in
    tautulli) echo -e "  ${CYAN}Tautulli:${NC}   http://YOUR_IP:${PORT_TAUTULLI}" ;;
    nzbdav)   echo -e "  ${CYAN}NZBDav:${NC}     http://YOUR_IP:${PORT_NZBDAV}" ;;
  esac
done <<< "$GLOBAL_SERVICES"

echo ""
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Log file: $LOG_FILE"
echo -e "  Config:   $MANIFEST"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""