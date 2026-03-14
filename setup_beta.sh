#!/bin/bash
# =============================================================================
#  UnlimitedPlex Beta - Modular Setup Script
#  Same structure as original scripts but with selectable instances
# =============================================================================
#
#  DIRECTORY STRUCTURE (same as original):
#    /opt/zurg-testing/          - Zurg + Rclone (global, single instance)
#    /opt/arr-stack/             - All Radarr/Sonarr/Prowlarr instances in one compose
#    /opt/decypharr/             - Decypharr (global, knows all arr instances)
#    /opt/tautulli/              - Tautulli (global, optional)
#    /opt/nzbdav/                - NZBDav + Rclone sidecar (global, optional)
#    /opt/pulsarr/               - Pulsarr (global, optional)
#
#  MOUNT STRUCTURE (same as original):
#    /mnt/remote/realdebrid/     - Zurg rclone mount
#    /mnt/remote/nzbdav/         - NZBDav rclone mount (if enabled)
#    /mnt/symlinks/<inst>_radarr/ - Decypharr symlinks per radarr instance
#    /mnt/symlinks/<inst>_sonarr/ - Decypharr symlinks per sonarr instance
#    /mnt/plex/<InstLabel>/Movies/ - Plex library dirs per instance
#    /mnt/plex/<InstLabel>/TV/     - Plex library dirs per instance
#
#  CONFIG JSON FORMAT:
#  {
#    "rd_token": "...",
#    "plex_token": "...",
#    "timezone": "America/New_York",
#    "zurg_version": "v0.9.3-final",
#    "instances": [
#      { "name": "main",  "label": "Main",  "services": ["radarr","sonarr","prowlarr"] },
#      { "name": "4k",    "label": "4K",    "services": ["radarr","sonarr"] },
#      { "name": "kids",  "label": "Kids",  "services": ["radarr","sonarr"] }
#    ],
#    "global_services": ["tautulli","nzbdav","pulsarr"],
#    "nzbdav_password": "changeme"
#  }
#
#  USAGE:
#    sudo bash setup_beta.sh --config /tmp/unlimitedplex_config.json
#
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
LOG_FILE="/var/log/unlimitedplex_beta.log"
mkdir -p "$(dirname "$LOG_FILE")"

info()    { echo -e "${CYAN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
success() { echo -e "${GREEN}[OK]${NC}    $*" | tee -a "$LOG_FILE"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"
            echo -e "${BOLD}${CYAN}  $*${NC}" | tee -a "$LOG_FILE"
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n" | tee -a "$LOG_FILE"; }

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run as root: sudo bash setup_beta.sh --config /path/to/config.json"
fi

# ── Parse args ────────────────────────────────────────────────────────────────
CONFIG_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    *) error "Unknown argument: $1" ;;
  esac
done

[[ -z "$CONFIG_FILE" || ! -f "$CONFIG_FILE" ]] && error "Config file not found: $CONFIG_FILE"

# ── Parse JSON config ─────────────────────────────────────────────────────────
py3() { python3 -c "$@"; }

RD_TOKEN=$(py3 "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('rd_token',''))")
PLEX_TOKEN=$(py3 "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('plex_token',''))")
TZ=$(py3 "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('timezone','America/New_York'))")
ZURG_VERSION=$(py3 "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('zurg_version','v0.9.3-final'))")
NZBDAV_PASSWORD=$(py3 "import json; d=json.load(open('$CONFIG_FILE')); print(d.get('nzbdav_password','changeme'))")

[[ -z "$RD_TOKEN" ]]   && error "rd_token is required in config"
[[ -z "$PLEX_TOKEN" ]] && error "plex_token is required in config"
[[ -z "$TZ" ]]         && TZ="America/New_York"
[[ -z "$ZURG_VERSION" ]] && ZURG_VERSION="v0.9.3-final"

export DEBIAN_FRONTEND=noninteractive
PUID=0
PGID=0
DOCKER_NETWORK="arr-stack_arr-network"
ZURG_DIR="/opt/zurg-testing"
ARR_DIR="/opt/arr-stack"
DECYPHARR_DIR="/opt/decypharr"

# ── Read instances from JSON ──────────────────────────────────────────────────
# Returns: name|label|service1,service2,...
get_instances() {
  python3 - "$CONFIG_FILE" << 'PYINST'
import json, sys
d = json.load(open(sys.argv[1]))
for i in d.get('instances', []):
    svcs = ','.join(i.get('services', []))
    print(f"{i['name']}|{i['label']}|{svcs}")
PYINST
}

# Returns global services one per line
get_global_services() {
  python3 - "$CONFIG_FILE" << 'PYGLOB'
import json, sys
d = json.load(open(sys.argv[1]))
for s in d.get('global_services', []):
    print(s)
PYGLOB
}

has_global_service() {
  get_global_services | grep -q "^$1$"
}

instance_has_service() {
  local INST_SVCS="$1"
  local SVC="$2"
  echo "$INST_SVCS" | tr ',' '\n' | grep -q "^${SVC}$"
}

# ── Port allocation ───────────────────────────────────────────────────────────
# Base ports - each instance offsets by index * 100
PORT_RADARR=7878
PORT_SONARR=8989
PORT_PROWLARR=9696  # Global single instance

get_port() { echo $(( $1 + $2 * 100 )); }

# =============================================================================
# STEP 0 - SYSTEM UPDATE & DEPENDENCIES
# =============================================================================
section "Step 0 - System Update & Dependencies"

info "Updating package lists..."
apt-get update -y 2>&1 | tail -3
info "Installing essential tools..."
apt-get install -y git curl wget screen inotify-tools libxml2-utils fuse3 python3 python3-pip 2>&1 | tail -5
success "Dependencies installed."

# =============================================================================
# STEP 1 - INSTALL DOCKER (same logic as original)
# =============================================================================
section "Step 1 - Install Docker"

if snap list docker &>/dev/null 2>&1; then
  warn "Snap Docker detected - removing and reinstalling via apt..."
  snap remove docker
  rm -f /usr/local/bin/docker 2>/dev/null || true
fi

if command -v docker &>/dev/null && ! snap list docker &>/dev/null 2>&1; then
  success "Docker already installed: $(docker --version)"
else
  info "Installing Docker via official script..."
  apt-get remove -y docker docker-engine docker.io 2>/dev/null || true
  apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  success "Docker installed: $(docker --version)"
fi

# Start Docker
if systemctl list-units --type=service 2>/dev/null | grep -q "docker.service"; then
  systemctl start docker  || true
  systemctl enable docker || true
fi

if ! docker info &>/dev/null 2>&1; then
  error "Cannot connect to Docker daemon. Please ensure Docker is running."
fi
success "Docker is running."

# =============================================================================
# STEP 2 - SHARED MOUNT SETUP
# =============================================================================
section "Step 2 - Shared Mount Setup"

info "Setting /mnt as shared mount..."
if ! mountpoint -q /mnt 2>/dev/null; then
  mount --bind /mnt /mnt 2>/dev/null || true
fi
mount --make-shared /mnt 2>/dev/null || true
modprobe fuse 2>/dev/null || true
grep -q "user_allow_other" /etc/fuse.conf 2>/dev/null || echo "user_allow_other" >> /etc/fuse.conf
success "Shared mount configured."

# =============================================================================
# STEP 3 - DIRECTORY STRUCTURE (same as original)
# =============================================================================
section "Step 3 - Create Directory Structure"

info "Creating Plex library directories..."
# Base Plex dirs
mkdir -p /mnt/plex

# Create per-instance Plex dirs
while IFS='|' read -r INST_NAME INST_LABEL INST_SVCS; do
  [[ -z "$INST_NAME" ]] && continue
  mkdir -p "/mnt/plex/${INST_LABEL}/Movies"
  mkdir -p "/mnt/plex/${INST_LABEL}/TV"
  info "  Created: /mnt/plex/${INST_LABEL}/{Movies,TV}"
done < <(get_instances)
success "Plex library directories created."

info "Creating symlink directories..."
# Create per-instance symlink dirs (for Decypharr)
while IFS='|' read -r INST_NAME INST_LABEL INST_SVCS; do
  [[ -z "$INST_NAME" ]] && continue
  if instance_has_service "$INST_SVCS" "radarr"; then
    mkdir -p "/mnt/symlinks/${INST_NAME}_radarr"
    info "  Created: /mnt/symlinks/${INST_NAME}_radarr"
  fi
  if instance_has_service "$INST_SVCS" "sonarr"; then
    mkdir -p "/mnt/symlinks/${INST_NAME}_sonarr"
    info "  Created: /mnt/symlinks/${INST_NAME}_sonarr"
  fi
done < <(get_instances)
success "Symlink directories created."

info "Creating mount directories..."
mkdir -p /mnt/remote/realdebrid
has_global_service "nzbdav" && mkdir -p /mnt/remote/nzbdav || true
success "Mount directories created."

chown -R "${PUID}:${PGID}" /mnt/plex /mnt/symlinks /opt/decypharr 2>/dev/null || true

# =============================================================================
# STEP 4 - INSTALL PLEX MEDIA SERVER (native, same as original)
# =============================================================================
section "Step 4 - Install Plex Media Server"

if systemctl is-active --quiet plexmediaserver 2>/dev/null; then
  success "Plex Media Server already running."
else
  info "Adding Plex repository..."
  curl https://downloads.plex.tv/plex-keys/PlexSign.key \
    | gpg --dearmor \
    | tee /usr/share/keyrings/plex-archive-keyring.gpg > /dev/null
  echo "deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] \
https://downloads.plex.tv/repo/deb public main" \
    | tee /etc/apt/sources.list.d/plex.list
  apt-get update -y
  apt-get install -y libusb-dev || true
  apt-get install -y plexmediaserver
  systemctl enable plexmediaserver
  systemctl start plexmediaserver
  success "Plex Media Server installed and started."
fi

# Inject Plex token if provided
PLEX_PREFS="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"
if [[ -n "$PLEX_TOKEN" ]]; then
  info "Plex token provided - will inject after Zurg setup."
fi

# =============================================================================
# STEP 5 - ZURG & RCLONE (global, single instance - same as original)
# =============================================================================
section "Step 5 - Zurg & Rclone Setup"

docker pull "ghcr.io/debridmediamanager/zurg-testing:${ZURG_VERSION}" 2>&1 | tail -3

if [[ -d "$ZURG_DIR" ]]; then
  warn "$ZURG_DIR already exists - updating config only."
else
  info "Cloning Zurg repository..."
  git clone https://github.com/debridmediamanager/zurg-testing.git "$ZURG_DIR"
fi

info "Writing Zurg config.yml..."
cp "$ZURG_DIR/config.yml" "$ZURG_DIR/config.yml.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
cat > "$ZURG_DIR/config.yml" << ZURG_CONFIG
# Zurg configuration - UnlimitedPlex Beta
zurg: v1
token: ${RD_TOKEN}
port: 9999
api_rate_limit_per_minute: 60
torrents_rate_limit_per_minute: 25
concurrent_workers: 32
check_for_changes_every_secs: 10
ignore_renames: true
retain_rd_torrent_name: true
retain_folder_name_extension: true
enable_repair: false
auto_delete_rar_torrents: false
get_torrents_count: 5000
serve_from_rclone: true
cache_network_test_results: true
on_library_update: sh plex_update.sh "\$@"
mount_path: /mnt/remote/realdebrid
plex_server_url: http://localhost:32400
plex_token: ${PLEX_TOKEN}

directories:
  shows:
    group: media
    group_order: 10
    filters:
      - has_episodes: true
  movies:
    group: media
    group_order: 20
    only_show_the_biggest_file: true
    filters:
      - regex: /.*/
ZURG_CONFIG
success "Zurg config.yml written."

info "Writing Zurg docker-compose.yml..."
cat > "$ZURG_DIR/docker-compose.yml" << COMPOSE_CONFIG
services:
  zurg:
    image: ghcr.io/debridmediamanager/zurg-testing:${ZURG_VERSION}
    container_name: zurg
    restart: unless-stopped
    healthcheck:
      test: curl -f http://localhost:9999/dav/version.txt || exit 1
      interval: 30s
      timeout: 15s
      retries: 20
      start_period: 300s
    ports:
      - "9999:9999"
    volumes:
      - ${ZURG_DIR}/config.yml:/app/config.yml
      - ${ZURG_DIR}/data:/app/data
      - ${ZURG_DIR}/plex_update.sh:/app/plex_update.sh

  rclone:
    image: rclone/rclone:latest
    container_name: rclone
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse:rwm
    volumes:
      - ${ZURG_DIR}/rclone.conf:/config/rclone/rclone.conf
      - /mnt/remote/realdebrid:/mnt/remote/realdebrid:shared
    command: >
      mount zurg: /mnt/remote/realdebrid
      --allow-other
      --allow-non-empty
      --dir-cache-time 10s
      --vfs-cache-mode full
      --vfs-read-chunk-size 8M
      --vfs-read-chunk-size-limit 2G
      --buffer-size 32M
      --log-level INFO
    depends_on:
      zurg:
        condition: service_healthy
COMPOSE_CONFIG
success "Zurg docker-compose.yml written."

info "Writing rclone.conf..."
cat > "$ZURG_DIR/rclone.conf" << RCLONE_CONF
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
RCLONE_CONF

info "Writing plex_update.sh..."
cat > "$ZURG_DIR/plex_update.sh" << 'PLEX_UPDATE'
#!/bin/bash
PLEX_HOST="localhost"
PLEX_PORT="32400"
PLEX_TOKEN="PLEX_TOKEN_PLACEHOLDER"
MOUNT_POINT="/mnt/remote/realdebrid"
for arg in "$@"; do
    modified_arg="${MOUNT_POINT}/${arg}"
    encoded_arg=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${modified_arg}'))")
    section_id=$(curl -s "http://${PLEX_HOST}:${PLEX_PORT}/library/sections?X-Plex-Token=${PLEX_TOKEN}" \
        | xmllint --xpath "//Directory[Location/@path='${modified_arg}']/@key" - 2>/dev/null \
        | sed 's/key="//;s/"//')
    if [[ -n "$section_id" ]]; then
        curl -s "http://${PLEX_HOST}:${PLEX_PORT}/library/sections/${section_id}/refresh?path=${encoded_arg}&X-Plex-Token=${PLEX_TOKEN}" > /dev/null
    fi
done
PLEX_UPDATE
chmod +x "$ZURG_DIR/plex_update.sh"

# Inject Plex token into plex_update.sh
if [[ -n "$PLEX_TOKEN" ]]; then
  sed -i "s/PLEX_TOKEN_PLACEHOLDER/${PLEX_TOKEN}/" "$ZURG_DIR/plex_update.sh"
  success "Plex token injected into plex_update.sh"
fi

# Clean up stale mounts and start
docker stop rclone zurg 2>/dev/null || true
docker rm   rclone zurg 2>/dev/null || true
fusermount -uz /mnt/remote/realdebrid 2>/dev/null || true
umount -l /mnt/remote/realdebrid 2>/dev/null || true
mkdir -p /mnt/remote/realdebrid

info "Starting Zurg & Rclone..."
(cd "$ZURG_DIR" && docker compose up -d) 2>&1 | tail -5

info "Waiting for Zurg to become healthy..."
ZURG_WAIT=0
while [[ $ZURG_WAIT -lt 600 ]]; do
  HEALTH=$(docker inspect --format '{{.State.Health.Status}}' zurg 2>/dev/null || echo "unknown")
  [[ "$HEALTH" == "healthy" ]] && { success "Zurg is healthy!"; break; }
  [[ "$HEALTH" == "unhealthy" ]] && { warn "Zurg unhealthy - may still be indexing. Continuing..."; break; }
  echo -ne "  Zurg: ${HEALTH} - waited ${ZURG_WAIT}s\r"
  sleep 10; ZURG_WAIT=$((ZURG_WAIT + 10))
done

# =============================================================================
# STEP 6 - DOCKER NETWORK
# =============================================================================
section "Step 6 - Docker Network"

if ! docker network ls --format '{{.Name}}' | grep -q "^${DOCKER_NETWORK}$"; then
  docker network create "$DOCKER_NETWORK" 2>/dev/null || true
  success "Docker network created: $DOCKER_NETWORK"
else
  success "Docker network already exists: $DOCKER_NETWORK"
fi

# =============================================================================
# STEP 7 - ARR STACK (all instances in one docker-compose)
# =============================================================================
section "Step 7 - Deploy Arr Stack"

mkdir -p "$ARR_DIR"

info "Building arr-stack docker-compose.yml with all instances..."
cat > "$ARR_DIR/docker-compose.yml" << 'ARR_HEADER'
# UnlimitedPlex Beta - Arr Stack
# Auto-generated by setup_beta.sh - all instances in one compose file

services:
ARR_HEADER

INST_IDX=0
while IFS='|' read -r INST_NAME INST_LABEL INST_SVCS; do
  [[ -z "$INST_NAME" ]] && continue

  info "Adding instance to arr-stack: $INST_LABEL"

  # RADARR
  if instance_has_service "$INST_SVCS" "radarr"; then
    RADARR_PORT=$(get_port $PORT_RADARR $INST_IDX)
    mkdir -p "$ARR_DIR/radarr_${INST_NAME}/config"
    cat >> "$ARR_DIR/docker-compose.yml" << EOF

  radarr_${INST_NAME}:
    image: ghcr.io/hotio/radarr:release
    container_name: radarr_${INST_NAME}
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${ARR_DIR}/radarr_${INST_NAME}/config:/config
      - /mnt:/mnt:rshared
    ports:
      - "${RADARR_PORT}:7878"
    networks:
      - arr-network
EOF
    info "  Radarr [${INST_LABEL}] -> port ${RADARR_PORT}"
  fi

  # SONARR
  if instance_has_service "$INST_SVCS" "sonarr"; then
    SONARR_PORT=$(get_port $PORT_SONARR $INST_IDX)
    mkdir -p "$ARR_DIR/sonarr_${INST_NAME}/config"
    cat >> "$ARR_DIR/docker-compose.yml" << EOF

  sonarr_${INST_NAME}:
    image: ghcr.io/hotio/sonarr:release
    container_name: sonarr_${INST_NAME}
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${ARR_DIR}/sonarr_${INST_NAME}/config:/config
      - /mnt:/mnt:rshared
    ports:
      - "${SONARR_PORT}:8989"
    networks:
      - arr-network
EOF
    info "  Sonarr [${INST_LABEL}] -> port ${SONARR_PORT}"
  fi

  INST_IDX=$((INST_IDX + 1))
done < <(get_instances)

# PROWLARR - Global single instance (shared by all arr instances)
mkdir -p "$ARR_DIR/prowlarr/config"
cat >> "$ARR_DIR/docker-compose.yml" << EOF

  prowlarr:
    image: ghcr.io/hotio/prowlarr:release
    container_name: prowlarr
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${ARR_DIR}/prowlarr/config:/config
      - /mnt:/mnt:rshared
    ports:
      - "${PORT_PROWLARR}:9696"
    networks:
      - arr-network
EOF
info "  Prowlarr (global) -> port ${PORT_PROWLARR}"

# Append network section
cat >> "$ARR_DIR/docker-compose.yml" << EOF

networks:
  arr-network:
    name: ${DOCKER_NETWORK}
    external: true
EOF

success "Arr-stack docker-compose.yml written."

info "Starting arr-stack..."
(cd "$ARR_DIR" && docker compose up -d) 2>&1 | tail -10
success "Arr-stack deployed."

# =============================================================================
# STEP 8 - DECYPHARR (global, single instance, knows all arr instances)
# =============================================================================
section "Step 8 - Deploy Decypharr"

mkdir -p "$DECYPHARR_DIR"

info "Writing Decypharr docker-compose.yml..."
cat > "$DECYPHARR_DIR/docker-compose.yml" << DECYPHARR_COMPOSE
services:
  decypharr:
    image: cy01/blackhole:latest
    container_name: decypharr
    restart: unless-stopped
    ports:
      - "8282:8282"
    volumes:
      - /mnt:/mnt:rshared
      - ${DECYPHARR_DIR}:/app
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - UMASK=002
    devices:
      - /dev/fuse:/dev/fuse:rwm
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8282"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s

networks:
  default:
    name: ${DOCKER_NETWORK}
    external: true
DECYPHARR_COMPOSE

info "Building Decypharr config.json with all arr instances..."

# Use Python to generate valid JSON - avoids all shell quoting issues
INST_PIPE_DATA=""
while IFS='|' read -r INST_NAME INST_LABEL INST_SVCS; do
  [[ -z "$INST_NAME" ]] && continue
  [[ -n "$INST_PIPE_DATA" ]] && INST_PIPE_DATA="${INST_PIPE_DATA};"
  INST_PIPE_DATA="${INST_PIPE_DATA}${INST_NAME}|${INST_LABEL}|${INST_SVCS}"
done < <(get_instances)

python3 - "$DECYPHARR_DIR/config.json" "$RD_TOKEN" "$INST_PIPE_DATA" << 'DECYPHARR_PY'
import json, sys

config_file = sys.argv[1]
rd_token = sys.argv[2]
inst_data = sys.argv[3]

arrs = []
if inst_data.strip():
    for entry in inst_data.split(";"):
        parts = entry.split("|")
        if len(parts) < 3:
            continue
        inst_name = parts[0]
        inst_svcs = parts[2].split(",")
        if "radarr" in inst_svcs:
            arrs.append({
                "name": f"radarr_{inst_name}",
                "type": "radarr",
                "host": f"http://radarr_{inst_name}:7878",
                "api_key": "",
                "download_folder": f"/mnt/symlinks/{inst_name}_radarr"
            })
        if "sonarr" in inst_svcs:
            arrs.append({
                "name": f"sonarr_{inst_name}",
                "type": "sonarr",
                "host": f"http://sonarr_{inst_name}:8989",
                "api_key": "",
                "download_folder": f"/mnt/symlinks/{inst_name}_sonarr"
            })

config = {
    "port": "8282",
    "download_folder": "/mnt/symlinks",
    "log_level": "info",
    "debrids": [
        {
            "name": "realdebrid",
            "type": "realdebrid",
            "api_key": rd_token,
            "mount_path": "/mnt/remote/realdebrid/__all__",
            "download_uncached": False
        }
    ],
    "arrs": arrs,
    "qbittorrent": {
        "port": "8282",
        "download_folder": "/mnt/symlinks"
    },
    "rclone": {
        "enabled": False
    },
    "repair": {
        "enabled": True,
        "interval": "6h"
    }
}

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
DECYPHARR_PY
success "Decypharr config.json written."

info "Starting Decypharr..."
(cd "$DECYPHARR_DIR" && docker compose up -d) 2>&1 | tail -5
sleep 5
success "Decypharr deployed on port 8282."

# =============================================================================
# STEP 9 - TAUTULLI (global, optional)
# =============================================================================
if has_global_service "tautulli"; then
  section "Step 9 - Deploy Tautulli"
  TAUTULLI_DIR="/opt/tautulli"
  mkdir -p "$TAUTULLI_DIR/config"

  cat > "$TAUTULLI_DIR/docker-compose.yml" << TAUTULLI_COMPOSE
services:
  tautulli:
    image: ghcr.io/tautulli/tautulli:latest
    container_name: tautulli
    restart: unless-stopped
    environment:
      - TZ=${TZ}
      - PUID=${PUID}
      - PGID=${PGID}
    volumes:
      - ${TAUTULLI_DIR}/config:/config
    ports:
      - "8181:8181"
    networks:
      - arr-network

networks:
  arr-network:
    name: ${DOCKER_NETWORK}
    external: true
TAUTULLI_COMPOSE

  (cd "$TAUTULLI_DIR" && docker compose up -d) 2>&1 | tail -3
  success "Tautulli deployed on port 8181."
fi

# =============================================================================
# STEP 10 - PULSARR (global, optional)
# =============================================================================
if has_global_service "pulsarr"; then
  section "Step 10 - Deploy Pulsarr"
  PULSARR_DIR="/opt/pulsarr"
  mkdir -p "$PULSARR_DIR/config"

  cat > "$PULSARR_DIR/docker-compose.yml" << PULSARR_COMPOSE
services:
  pulsarr:
    image: lakker/pulsarr:latest
    container_name: pulsarr
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    volumes:
      - ${PULSARR_DIR}/config:/config
    ports:
      - "3003:3003"
    networks:
      - arr-network

networks:
  arr-network:
    name: ${DOCKER_NETWORK}
    external: true
PULSARR_COMPOSE

  (cd "$PULSARR_DIR" && docker compose up -d) 2>&1 | tail -3
  success "Pulsarr deployed on port 3003."
fi

# =============================================================================
# STEP 11 - NZBDAV (global, optional)
# =============================================================================
if has_global_service "nzbdav"; then
  section "Step 11 - Deploy NZBDav"
  NZBDAV_DIR="/opt/nzbdav"
  mkdir -p "$NZBDAV_DIR/config"
  mkdir -p /mnt/remote/nzbdav

  # Generate obscured password for rclone
  NZBDAV_PASS_OBSCURED=$(docker run --rm rclone/rclone:latest obscure "${NZBDAV_PASSWORD}" 2>/dev/null || echo "${NZBDAV_PASSWORD}")

  # Write rclone.conf for NZBDav
  cat > "$NZBDAV_DIR/rclone.conf" << RCLONE_CONF
[nzbdav]
type = webdav
url = http://nzbdav:3000/
vendor = other
user = nzbdav
pass = ${NZBDAV_PASS_OBSCURED}
RCLONE_CONF

  cat > "$NZBDAV_DIR/docker-compose.yml" << NZBDAV_COMPOSE
services:
  nzbdav:
    image: nzbdav/nzbdav:0.5.34
    container_name: nzbdav
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    volumes:
      - ${NZBDAV_DIR}/config:/config
      - /mnt:/mnt
    ports:
      - "3000:3000"
    networks:
      - arr-network
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:3000/"]
      interval: 10s
      timeout: 5s
      retries: 12
      start_period: 30s

  nzbdav_rclone:
    image: rclone/rclone:latest
    container_name: nzbdav_rclone
    restart: unless-stopped
    depends_on:
      nzbdav:
        condition: service_healthy
        restart: true
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse:rwm
    volumes:
      - /mnt:/mnt:rshared
      - ${NZBDAV_DIR}/rclone.conf:/config/rclone/rclone.conf
    command: >
      mount nzbdav: /mnt/remote/nzbdav
        --allow-other
        --allow-non-empty
        --links
        --use-cookies
        --vfs-cache-mode=off
        --buffer-size=32M
        --dir-cache-time=20s
        --log-level=INFO
    networks:
      - arr-network

networks:
  arr-network:
    name: ${DOCKER_NETWORK}
    external: true
NZBDAV_COMPOSE

  info "Starting NZBDav..."
  (cd "$NZBDAV_DIR" && docker compose up -d nzbdav) 2>&1 | tail -3
  info "Waiting for NZBDav to be healthy (up to 2 min)..."
  WAIT=0
  while [[ $WAIT -lt 120 ]]; do
    if curl -sf "http://localhost:3000/" &>/dev/null; then
      success "NZBDav is healthy."
      break
    fi
    sleep 5; WAIT=$((WAIT + 5))
  done
  info "Starting NZBDav rclone sidecar..."
  (cd "$NZBDAV_DIR" && docker compose up -d nzbdav_rclone) 2>&1 | tail -3
  success "NZBDav deployed on port 3000."
  warn "NOTE: Open http://YOUR_IP:3000 to configure your usenet provider credentials."
  warn "      After configuring, set WebDAV user=nzbdav password=${NZBDAV_PASSWORD} in NZBDav settings."
fi

# =============================================================================
# STEP 12 - GENERATE STARTUP SCRIPT (same structure as original)
# =============================================================================
section "Step 12 - Generate Startup Script"

cat > /root/startup.sh << 'STARTUP_HEADER'
#!/bin/bash
# UnlimitedPlex Beta - Startup Script
# Auto-generated by setup_beta.sh

LOG="/var/log/unlimitedplex_startup.log"
echo "[$(date)] startup.sh triggered" >> "$LOG"

sleep 15

# Ensure /mnt is shared
if ! mountpoint -q /mnt 2>/dev/null; then
  mount --bind /mnt /mnt 2>/dev/null || true
fi
mount --make-shared /mnt 2>/dev/null || true
modprobe fuse 2>/dev/null || true

# Start Zurg + Rclone
echo "[$(date)] Starting Zurg + Rclone..." >> "$LOG"
cd /opt/zurg-testing && docker compose up -d >> "$LOG" 2>&1

# Wait for Zurg to be healthy
WAIT=0
while [[ $WAIT -lt 300 ]]; do
  HEALTH=$(docker inspect --format '{{.State.Health.Status}}' zurg 2>/dev/null || echo "unknown")
  [[ "$HEALTH" == "healthy" ]] && break
  sleep 10; WAIT=$((WAIT + 10))
done
echo "[$(date)] Zurg status: $HEALTH" >> "$LOG"

STARTUP_HEADER

# Build startup.sh using Python to avoid set -e issues with has_global_service
GLOBAL_SVCS_LIST=$(get_global_services | tr '\n' ',' | sed 's/,$//')

python3 - "/root/startup.sh" "$GLOBAL_SVCS_LIST" << 'STARTUP_PY'
import sys

startup_file = sys.argv[1]
global_svcs = [s.strip() for s in sys.argv[2].split(',') if s.strip()]

lines = []
lines.append('#!/bin/bash')
lines.append('# UnlimitedPlex Beta - Startup Script')
lines.append('# Auto-generated by setup_beta.sh')
lines.append('')
lines.append('LOG="/var/log/unlimitedplex_startup.log"')
lines.append('echo "[$(date)] startup.sh triggered" >> "$LOG"')
lines.append('')
lines.append('sleep 15')
lines.append('')
lines.append('# Ensure /mnt is shared')
lines.append('if ! mountpoint -q /mnt 2>/dev/null; then')
lines.append('  mount --bind /mnt /mnt 2>/dev/null || true')
lines.append('fi')
lines.append('mount --make-shared /mnt 2>/dev/null || true')
lines.append('modprobe fuse 2>/dev/null || true')
lines.append('')
lines.append('# Start Zurg + Rclone')
lines.append('echo "[$(date)] Starting Zurg + Rclone..." >> "$LOG"')
lines.append('cd /opt/zurg-testing && docker compose up -d >> "$LOG" 2>&1')
lines.append('')
lines.append('# Wait for Zurg to be healthy')
lines.append('WAIT=0')
lines.append('while [[ $WAIT -lt 300 ]]; do')
lines.append('  HEALTH=$(docker inspect --format \'{{.State.Health.Status}}\' zurg 2>/dev/null || echo "unknown")')
lines.append('  [[ "$HEALTH" == "healthy" ]] && break')
lines.append('  sleep 10; WAIT=$((WAIT + 10))')
lines.append('done')
lines.append('echo "[$(date)] Zurg status: $HEALTH" >> "$LOG"')

if 'nzbdav' in global_svcs:
    lines.append('')
    lines.append('# Start NZBDav (before arr-stack)')
    lines.append('echo "[$(date)] Starting NZBDav..." >> "$LOG"')
    lines.append('cd /opt/nzbdav && docker compose up -d nzbdav >> "$LOG" 2>&1')
    lines.append('WAIT=0')
    lines.append('while [[ $WAIT -lt 120 ]]; do')
    lines.append('  if curl -sf http://localhost:3000/ &>/dev/null; then')
    lines.append('    echo "[$(date)] NZBDav ready" >> "$LOG"')
    lines.append('    break')
    lines.append('  fi')
    lines.append('  sleep 5; WAIT=$((WAIT + 5))')
    lines.append('done')
    lines.append('cd /opt/nzbdav && docker compose up -d nzbdav_rclone >> "$LOG" 2>&1')
    lines.append('WAIT=0')
    lines.append('while [[ $WAIT -lt 120 ]]; do')
    lines.append('  if ls /mnt/remote/nzbdav &>/dev/null; then')
    lines.append('    echo "[$(date)] NZBDav mount ready" >> "$LOG"')
    lines.append('    break')
    lines.append('  fi')
    lines.append('  sleep 5; WAIT=$((WAIT + 5))')
    lines.append('done')

lines.append('')
lines.append('# Start arr-stack (all instances)')
lines.append('echo "[$(date)] Starting arr-stack..." >> "$LOG"')
lines.append('cd /opt/arr-stack && docker compose up -d >> "$LOG" 2>&1')
lines.append('')
lines.append('# Start Decypharr')
lines.append('echo "[$(date)] Starting Decypharr..." >> "$LOG"')
lines.append('cd /opt/decypharr && docker compose up -d >> "$LOG" 2>&1')

if 'tautulli' in global_svcs:
    lines.append('')
    lines.append('echo "[$(date)] Starting Tautulli..." >> "$LOG"')
    lines.append('cd /opt/tautulli && docker compose up -d >> "$LOG" 2>&1')

if 'pulsarr' in global_svcs:
    lines.append('')
    lines.append('echo "[$(date)] Starting Pulsarr..." >> "$LOG"')
    lines.append('cd /opt/pulsarr && docker compose up -d >> "$LOG" 2>&1')

lines.append('')
lines.append('echo "[$(date)] All services started." >> "$LOG"')

with open(startup_file, 'w') as f:
    f.write('\n'.join(lines) + '\n')
STARTUP_PY

chmod +x /root/startup.sh

# Register cron job
CRON_LINE="@reboot sleep 15 && bash /root/startup.sh"
(crontab -l 2>/dev/null | grep -v "startup.sh"; echo "$CRON_LINE") | crontab -
success "Startup script written: /root/startup.sh"
success "Cron job registered: $CRON_LINE"


# =============================================================================
# COMPLETE - PRINT SUMMARY
# =============================================================================
section "Setup Complete!"

# Auto-detect server IP
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ -z "$SERVER_IP" ]] && SERVER_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
[[ -z "$SERVER_IP" ]] && SERVER_IP="YOUR_IP"

echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  UnlimitedPlex Beta - Installation Complete!${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BOLD}${CYAN}  ── Global Services ──────────────────────────────────────────────────────${NC}"
echo -e "  ${CYAN}Plex Media Server:${NC}  http://${SERVER_IP}:32400/web"
echo -e "  ${CYAN}Zurg:${NC}               http://${SERVER_IP}:9999"
echo -e "  ${CYAN}Decypharr:${NC}          http://${SERVER_IP}:8282"
echo -e "  ${CYAN}Prowlarr:${NC}           http://${SERVER_IP}:9696"
has_global_service "tautulli" && echo -e "  ${CYAN}Tautulli:${NC}           http://${SERVER_IP}:8181" || true
has_global_service "pulsarr"  && echo -e "  ${CYAN}Pulsarr:${NC}            http://${SERVER_IP}:3003" || true
has_global_service "nzbdav"   && echo -e "  ${CYAN}NZBDav:${NC}             http://${SERVER_IP}:3000" || true
echo ""

INST_IDX=0
while IFS='|' read -r INST_NAME INST_LABEL INST_SVCS; do
  [[ -z "$INST_NAME" ]] && continue
  echo -e "${BOLD}${CYAN}  ── Instance: ${INST_LABEL} ──────────────────────────────────────────────────${NC}"
  instance_has_service "$INST_SVCS" "radarr" && echo -e "  ${CYAN}Radarr [${INST_LABEL}]:${NC}  http://${SERVER_IP}:$(get_port $PORT_RADARR $INST_IDX)" || true
  instance_has_service "$INST_SVCS" "sonarr" && echo -e "  ${CYAN}Sonarr [${INST_LABEL}]:${NC}  http://${SERVER_IP}:$(get_port $PORT_SONARR $INST_IDX)" || true
  echo -e "  ${YELLOW}Plex libs:${NC} /mnt/plex/${INST_LABEL}/{Movies,TV}"
  echo -e "  ${YELLOW}Symlinks:${NC}  /mnt/symlinks/${INST_NAME}_{radarr,sonarr}"
  echo ""
  INST_IDX=$((INST_IDX + 1))
done < <(get_instances)

echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "  ${YELLOW}Tip:${NC} Copy any URL above and paste it into your browser to open the service."
echo -e "  ${YELLOW}Log:${NC} $LOG_FILE"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Write a quick-access links file
LINKS_FILE="/root/unlimitedplex_links.txt"
{
  echo "UnlimitedPlex Beta - Service Links"
  echo "Generated: $(date)"
  echo "Server IP: ${SERVER_IP}"
  echo "════════════════════════════════════"
  echo ""
  echo "Global Services:"
  echo "  Plex:       http://${SERVER_IP}:32400/web"
  echo "  Zurg:       http://${SERVER_IP}:9999"
  echo "  Decypharr:  http://${SERVER_IP}:8282"
  echo "  Prowlarr:   http://${SERVER_IP}:9696"
  has_global_service "tautulli" && echo "  Tautulli:   http://${SERVER_IP}:8181" || true
  has_global_service "pulsarr"  && echo "  Pulsarr:    http://${SERVER_IP}:3003" || true
  has_global_service "nzbdav"   && echo "  NZBDav:     http://${SERVER_IP}:3000" || true
  echo ""
  INST_IDX=0
  while IFS='|' read -r INST_NAME INST_LABEL INST_SVCS; do
    [[ -z "$INST_NAME" ]] && continue
    echo "Instance: ${INST_LABEL}"
    instance_has_service "$INST_SVCS" "radarr" && echo "  Radarr:  http://${SERVER_IP}:$(get_port $PORT_RADARR $INST_IDX)" || true
    instance_has_service "$INST_SVCS" "sonarr" && echo "  Sonarr:  http://${SERVER_IP}:$(get_port $PORT_SONARR $INST_IDX)" || true
    echo ""
    INST_IDX=$((INST_IDX + 1))
  done < <(get_instances)
} > "$LINKS_FILE"
success "Service links saved to: $LINKS_FILE"
