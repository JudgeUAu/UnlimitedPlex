#!/bin/bash
# =============================================================================
#  Sonarr + Radarr + Prowlarr + Decypharr Setup Script
#  Upgrades existing Plex + Zurg + Real-Debrid setup with *arr stack
#  Based on: https://savvyguides.wiki/sailarrsguide/
#  Decypharr: https://github.com/sirrobot01/decypharr
# =============================================================================
#
#  USAGE:
#    chmod +x setup_arr_stack.sh
#    sudo ./setup_arr_stack.sh
#
#  PREREQUISITES:
#    - Existing Zurg + Rclone + Plex setup (from setup_plex_debrid.sh)
#    - Docker installed and running
#    - Real-Debrid API token
#    - Plex token
#
#  WHAT THIS SCRIPT DOES:
#    1. Updates Zurg config for symlink workflow
#    2. Creates directory structure for symlinks and Plex libraries
#    3. Updates Rclone mount to expose __all__ torrents
#    4. Deploys Sonarr, Radarr, Prowlarr, Overseerr, Pulsarr via Docker
#    5. Deploys Decypharr (qBittorrent mock with Real-Debrid support)
#    6. Installs custom Prowlarr debrid indexers (Torrentio)
#    7. Auto-configures all *arr apps via API
#
# =============================================================================

set -euo pipefail

# ── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $*${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

# ── Root check ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run this script as root:  sudo ./setup_arr_stack.sh"
fi

# ── Banner ─────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
     _                  ____  _             _
    / \   _ __ _ __    / ___|| |_ __ _  ___| | __
   / _ \ | '__| '__|   \___ \| __/ _` |/ __| |/ /
  / ___ \| |  | |       ___) | || (_| | (__|   <
 /_/   \_\_|  |_|      |____/ \__\__,_|\___|_|\_\

  Sonarr · Radarr · Prowlarr · Overseerr · Decypharr
  + Zurg · Rclone · Plex · Real-Debrid
EOF
echo -e "${NC}"
echo -e "  Upgrade script: adds *arr stack with Decypharr (qBittorrent mock)\n"

# =============================================================================
# SECTION 0 – Collect configuration
# =============================================================================
section "Step 0 – Configuration"

# ── Detect existing setup ──────────────────────────────────────────────────
ZURG_DIR="/opt/zurg-testing"

if [[ ! -d "$ZURG_DIR" ]]; then
  error "Zurg directory not found at $ZURG_DIR. Please run setup_plex_debrid.sh first."
fi

if [[ ! -f "$ZURG_DIR/config.yml" ]]; then
  error "Zurg config.yml not found. Please run setup_plex_debrid.sh first."
fi

# ── Read existing tokens from Zurg config ─────────────────────────────────
RD_API_TOKEN=$(grep "^token:" "$ZURG_DIR/config.yml" | awk '{print $2}' | tr -d '"' || echo "")
if [[ -z "$RD_API_TOKEN" ]]; then
  echo -e "  Get your Real-Debrid API token from: ${YELLOW}https://real-debrid.com/apitoken${NC}"
  read -rp "  Enter your Real-Debrid API token: " RD_API_TOKEN
fi
[[ -z "$RD_API_TOKEN" ]] && error "Real-Debrid API token cannot be empty."
success "Real-Debrid token: ${RD_API_TOKEN:0:8}..."

# ── Plex token ─────────────────────────────────────────────────────────────
PLEX_TOKEN=$(grep "^plex_token:" "$ZURG_DIR/config.yml" | awk '{print $2}' | tr -d '"' || echo "")
if [[ -z "$PLEX_TOKEN" ]]; then
  PLEX_PREFS="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"
  PLEX_TOKEN=$(grep -oP 'PlexOnlineToken="\K[^"]+' "$PLEX_PREFS" 2>/dev/null || echo "")
fi
if [[ -z "$PLEX_TOKEN" ]]; then
  read -rp "  Enter your Plex token: " PLEX_TOKEN
fi
[[ -z "$PLEX_TOKEN" ]] && error "Plex token cannot be empty."
success "Plex token: ${PLEX_TOKEN:0:8}..."

# ── Get user/group IDs ─────────────────────────────────────────────────────
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "root")}"
if [[ "$REAL_USER" != "root" ]]; then
  PUID=$(id -u "$REAL_USER")
  PGID=$(id -g "$REAL_USER")
else
  PUID=1000
  PGID=1000
fi
info "Using PUID=$PUID, PGID=$PGID"

# ── Timezone ───────────────────────────────────────────────────────────────
TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
info "Timezone: $TZ"

# ── Plex server details ────────────────────────────────────────────────────
PLEX_SERVER_HOST="http://plex:32400"
PLEX_MACHINE_ID=$(curl -s "http://localhost:32400/identity?X-Plex-Token=${PLEX_TOKEN}" 2>/dev/null | grep -oP 'machineIdentifier="\K[^"]+' || echo "")
if [[ -z "$PLEX_MACHINE_ID" ]]; then
  warn "Could not auto-detect Plex Machine ID. You'll need to set this manually later."
  PLEX_MACHINE_ID="REPLACE_ME"
fi
info "Plex Machine ID: $PLEX_MACHINE_ID"

# ── Docker network ─────────────────────────────────────────────────────────
DOCKER_NETWORK="arr-stack"

success "Configuration collected."

# =============================================================================
# SECTION 1 – Create directory structure
# =============================================================================
section "Step 1 – Create Directory Structure"

info "Creating Plex library directories..."
mkdir -p /mnt/plex/{Movies,"Movies - 4K","Movies - Anime",TV,"TV - 4K","TV - Anime"}
success "Plex library directories created."

info "Creating symlink directories..."
mkdir -p /mnt/symlinks/{radarr,radarr4k,radarranime,sonarr,sonarr4k,sonarranime}
success "Symlink directories created."

info "Creating Real-Debrid mount directory..."
mkdir -p /mnt/remote/realdebrid
success "Mount directory created."

info "Creating Decypharr config directory..."
mkdir -p /opt/decypharr
success "Decypharr config directory created."

# Fix ownership
chown -R "$PUID:$PGID" /mnt/plex /mnt/symlinks /opt/decypharr 2>/dev/null || true

info "Directory structure:"
echo "  /mnt"
echo "  ├── plex/"
echo "  │   ├── Movies/"
echo "  │   ├── Movies - 4K/"
echo "  │   ├── Movies - Anime/"
echo "  │   ├── TV/"
echo "  │   ├── TV - 4K/"
echo "  │   └── TV - Anime/"
echo "  ├── symlinks/"
echo "  │   ├── radarr/"
echo "  │   ├── radarr4k/"
echo "  │   ├── radarranime/"
echo "  │   ├── sonarr/"
echo "  │   ├── sonarr4k/"
echo "  │   └── sonarranime/"
echo "  └── remote/"
echo "      └── realdebrid/  (rclone mount → __all__ torrents)"

# =============================================================================
# SECTION 2 – Update Zurg config for symlink workflow
# =============================================================================
section "Step 2 – Update Zurg Config"

info "Backing up current Zurg config..."
cp "$ZURG_DIR/config.yml" "$ZURG_DIR/config.yml.backup.$(date +%Y%m%d%H%M%S)"
success "Backup created."

info "Writing updated config.yml for symlink workflow..."
cat > "$ZURG_DIR/config.yml" << ZURG_CONFIG
# Zurg configuration
# Updated for Sonarr/Radarr + Decypharr symlink workflow

zurg: v1
token: ${RD_API_TOKEN}
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
success "Zurg config updated for symlink workflow."
info "Key changes: serve_from_rclone: true, retain_rd_torrent_name: true"

# =============================================================================
# SECTION 3 – Update Zurg Docker Compose
# =============================================================================
section "Step 3 – Update Zurg Docker Compose"

info "Writing updated docker-compose.yml..."
ZURG_VERSION=$(grep "image:.*zurg-testing" "$ZURG_DIR/docker-compose.yml" 2>/dev/null | grep -oP 'v[\d.]+[-\w]*' || echo "v0.9.3-final")
info "Detected Zurg version: $ZURG_VERSION"

cat > "$ZURG_DIR/docker-compose.yml" << COMPOSE_CONFIG
services:
  zurg:
    image: ghcr.io/debridmediamanager/zurg-testing:${ZURG_VERSION}
    container_name: zurg
    restart: unless-stopped
    healthcheck:
      test: curl -f localhost:9999/dav/version.txt || exit 1
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
success "Zurg docker-compose.yml updated."

# Update rclone.conf to mount __all__
info "Updating rclone.conf to expose __all__ torrents..."
cat > "$ZURG_DIR/rclone.conf" << RCLONE_CONF
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
RCLONE_CONF
success "rclone.conf updated."

# Restart Zurg + Rclone with new config
info "Restarting Zurg + Rclone with updated config..."
(cd "$ZURG_DIR" && docker compose down) 2>/dev/null || true
sleep 3

# Clean up stale mount
fusermount -uz /mnt/remote/realdebrid 2>/dev/null || true
umount -l /mnt/remote/realdebrid 2>/dev/null || true
mkdir -p /mnt/remote/realdebrid

# Ensure /mnt is a shared mount
if ! mountpoint -q /mnt 2>/dev/null; then
  mount --bind /mnt /mnt 2>/dev/null || true
fi
mount --make-shared /mnt 2>/dev/null || true

(cd "$ZURG_DIR" && docker compose up -d) 2>&1
success "Zurg + Rclone restarted."

# =============================================================================
# SECTION 4 – Create Docker network
# =============================================================================
section "Step 4 – Docker Network"

if docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
  success "Docker network '$DOCKER_NETWORK' already exists."
else
  info "Creating Docker network '$DOCKER_NETWORK'..."
  docker network create "$DOCKER_NETWORK"
  success "Docker network created."
fi

# Connect Zurg containers to arr-stack network
docker network connect "$DOCKER_NETWORK" zurg 2>/dev/null && info "Zurg connected to $DOCKER_NETWORK." || true
docker network connect "$DOCKER_NETWORK" rclone 2>/dev/null && info "Rclone connected to $DOCKER_NETWORK." || true

# =============================================================================
# SECTION 5 – Deploy *arr stack
# =============================================================================
section "Step 5 – Deploy *arr Stack (Sonarr/Radarr/Prowlarr/Overseerr/Pulsarr)"

ARR_DIR="/opt/arr-stack"
mkdir -p "$ARR_DIR"

info "Writing arr-stack docker-compose.yml..."
cat > "$ARR_DIR/docker-compose.yml" << ARR_COMPOSE
services:
  # ── Prowlarr (Indexer Manager) ─────────────────────────────────────────
  prowlarr:
    image: ghcr.io/hotio/prowlarr:release
    container_name: prowlarr
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    ports:
      - "9696:9696"
    volumes:
      - /opt/prowlarr:/config
      - /opt/prowlarr/Definitions/Custom:/Custom
      - /mnt:/mnt:rshared

  # ── Radarr (Movies) ────────────────────────────────────────────────────
  radarr:
    image: ghcr.io/hotio/radarr:release
    container_name: radarr
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    ports:
      - "7878:7878"
    volumes:
      - /opt/radarr:/config
      - /mnt:/mnt:rshared
    depends_on:
      - prowlarr

  # ── Radarr 4K ──────────────────────────────────────────────────────────
  radarr4k:
    image: ghcr.io/hotio/radarr:release
    container_name: radarr4k
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    ports:
      - "7879:7878"
    volumes:
      - /opt/radarr4k:/config
      - /mnt:/mnt:rshared
    depends_on:
      - prowlarr

  # ── Sonarr (TV Shows) ──────────────────────────────────────────────────
  sonarr:
    image: ghcr.io/hotio/sonarr:release
    container_name: sonarr
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    ports:
      - "8989:8989"
    volumes:
      - /opt/sonarr:/config
      - /mnt:/mnt:rshared
    depends_on:
      - prowlarr

  # ── Sonarr 4K ──────────────────────────────────────────────────────────
  sonarr4k:
    image: ghcr.io/hotio/sonarr:release
    container_name: sonarr4k
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    ports:
      - "8990:8989"
    volumes:
      - /opt/sonarr4k:/config
      - /mnt:/mnt:rshared
    depends_on:
      - prowlarr

  # ── Overseerr (Request Management) ────────────────────────────────────
  overseerr:
    image: sctx/overseerr:latest
    container_name: overseerr
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    ports:
      - "5055:5055"
    volumes:
      - /opt/overseerr:/app/config

  # ── Pulsarr (Plex Watchlist → Sonarr/Radarr) ──────────────────────────
  pulsarr:
    image: lakker/pulsarr:latest
    container_name: pulsarr
    restart: unless-stopped
    environment:
      - TZ=${TZ}
    ports:
      - "3003:3003"
    volumes:
      - /opt/pulsarr/data:/app/data
      - /opt/pulsarr/.env:/app/.env

networks:
  default:
    name: ${DOCKER_NETWORK}
    external: true
ARR_COMPOSE
success "arr-stack docker-compose.yml written."

# Create config dirs
mkdir -p /opt/{prowlarr,radarr,radarr4k,sonarr,sonarr4k,overseerr,pulsarr/data}
chown -R "$PUID:$PGID" /opt/{prowlarr,radarr,radarr4k,sonarr,sonarr4k,overseerr,pulsarr} 2>/dev/null || true

info "Starting *arr stack containers..."
(cd "$ARR_DIR" && docker compose up -d) 2>&1
success "*arr stack containers started."

# =============================================================================
# SECTION 6 – Deploy Decypharr
# =============================================================================
section "Step 6 – Deploy Decypharr (qBittorrent Mock for Real-Debrid)"

info "Decypharr replaces Blackhole — it acts as a qBittorrent server that"
info "Sonarr/Radarr connect to, and handles all Real-Debrid downloads + symlinks."

DECYPHARR_DIR="/opt/decypharr"
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
success "Decypharr docker-compose.yml written."

info "Writing Decypharr config.json..."
cat > "$DECYPHARR_DIR/config.json" << DECYPHARR_CONFIG
{
  "port": "8282",
  "download_folder": "/mnt/symlinks",
  "log_level": "info",
  "debrids": [
    {
      "name": "realdebrid",
      "type": "realdebrid",
      "api_key": "${RD_API_TOKEN}",
      "mount_path": "/mnt/remote/realdebrid/__all__",
      "download_uncached": false
    }
  ],
  "arrs": [
    {
      "name": "radarr",
      "type": "radarr",
      "host": "http://radarr:7878",
      "api_key": "",
      "download_folder": "/mnt/symlinks/radarr"
    },
    {
      "name": "radarr4k",
      "type": "radarr",
      "host": "http://radarr4k:7878",
      "api_key": "",
      "download_folder": "/mnt/symlinks/radarr4k"
    },
    {
      "name": "sonarr",
      "type": "sonarr",
      "host": "http://sonarr:8989",
      "api_key": "",
      "download_folder": "/mnt/symlinks/sonarr"
    },
    {
      "name": "sonarr4k",
      "type": "sonarr",
      "host": "http://sonarr4k:8989",
      "api_key": "",
      "download_folder": "/mnt/symlinks/sonarr4k"
    }
  ],
  "qbittorrent": {
    "port": "8282",
    "download_folder": "/mnt/symlinks"
  },
  "rclone": {
    "enabled": false
  },
  "repair": {
    "enabled": true,
    "interval": "6h"
  }
}
DECYPHARR_CONFIG
success "Decypharr config.json written."

info "Starting Decypharr container..."
(cd "$DECYPHARR_DIR" && docker compose up -d) 2>&1

info "Waiting for Decypharr to start..."
sleep 10

DECYPHARR_STATUS=$(docker inspect --format '{{.State.Status}}' decypharr 2>/dev/null || echo "unknown")
if [[ "$DECYPHARR_STATUS" == "running" ]]; then
  success "Decypharr is running at http://localhost:8282"
else
  warn "Decypharr status: $DECYPHARR_STATUS — check logs: docker logs decypharr"
fi

# =============================================================================
# SECTION 7 – Install custom Prowlarr indexers
# =============================================================================
section "Step 7 – Install Custom Prowlarr Indexers"

PROWLARR_CUSTOM_DIR="/opt/prowlarr/Definitions/Custom"
mkdir -p "$PROWLARR_CUSTOM_DIR"

info "Downloading Torrentio debrid indexer for Prowlarr..."
curl -fsSL "https://raw.githubusercontent.com/dreulavelle/Prowlarr-Indexers/main/Custom/torrentio.yml" \
  -o "$PROWLARR_CUSTOM_DIR/torrentio.yml" 2>/dev/null \
  && success "Torrentio indexer installed." \
  || warn "Could not download Torrentio indexer. You can add it manually later."

# Fix ownership
chown -R "$PUID:$PGID" "$PROWLARR_CUSTOM_DIR" 2>/dev/null || true

info "Restarting Prowlarr to pick up new indexers..."
docker restart prowlarr 2>/dev/null || warn "Could not restart Prowlarr."
success "Custom indexers installed."

# =============================================================================
# SECTION 7b – Auto-configure *arr apps via API
# =============================================================================
section "Step 7b – Auto-Configure *arr Apps"

info "Waiting for all services to fully initialize..."
sleep 30

# ── Helper functions ───────────────────────────────────────────────────────
wait_for_api() {
  local name="$1" url="$2" max_wait="${3:-90}"
  local elapsed=0
  info "Waiting for $name API..."
  while [[ $elapsed -lt $max_wait ]]; do
    if curl -sf "$url" &>/dev/null; then
      success "$name API is ready."
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  warn "$name API not ready after ${max_wait}s."
  return 1
}

get_api_key() {
  local config_file="$1"
  [[ -f "$config_file" ]] && grep -oP '<ApiKey>\K[^<]+' "$config_file" 2>/dev/null || echo ""
}

api_post() {
  local url="$1" api_key="$2" data="$3"
  curl -sf -X POST "$url" -H "Content-Type: application/json" -H "X-Api-Key: $api_key" -d "$data" 2>/dev/null
}

api_get() {
  local url="$1" api_key="$2"
  curl -sf "$url" -H "X-Api-Key: $api_key" 2>/dev/null
}

has_download_client() {
  local url="$1" api_key="$2" name="$3"
  api_get "$url/api/v3/downloadclient" "$api_key" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    names = [d.get('name','') for d in data]
    sys.exit(0 if '$name' in names else 1)
except: sys.exit(1)
" 2>/dev/null
}

has_root_folder() {
  local url="$1" api_key="$2" path="$3"
  api_get "$url/api/v3/rootfolder" "$api_key" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    paths = [d.get('path','') for d in data]
    sys.exit(0 if '$path' in paths else 1)
except: sys.exit(1)
" 2>/dev/null
}

# ── Extract API keys ───────────────────────────────────────────────────────
info "Extracting API keys from config files..."
RADARR_KEY=$(get_api_key "/opt/radarr/config.xml")
RADARR4K_KEY=$(get_api_key "/opt/radarr4k/config.xml")
SONARR_KEY=$(get_api_key "/opt/sonarr/config.xml")
SONARR4K_KEY=$(get_api_key "/opt/sonarr4k/config.xml")
PROWLARR_KEY=$(get_api_key "/opt/prowlarr/config.xml")

[[ -n "$RADARR_KEY" ]]   && success "Radarr API key:    ${RADARR_KEY:0:8}..."   || warn "Radarr key not found"
[[ -n "$RADARR4K_KEY" ]] && success "Radarr 4K API key: ${RADARR4K_KEY:0:8}..." || warn "Radarr 4K key not found"
[[ -n "$SONARR_KEY" ]]   && success "Sonarr API key:    ${SONARR_KEY:0:8}..."   || warn "Sonarr key not found"
[[ -n "$SONARR4K_KEY" ]] && success "Sonarr 4K API key: ${SONARR4K_KEY:0:8}..." || warn "Sonarr 4K key not found"
[[ -n "$PROWLARR_KEY" ]] && success "Prowlarr API key:  ${PROWLARR_KEY:0:8}..." || warn "Prowlarr key not found"

# ── Configure each *arr app ────────────────────────────────────────────────
# Decypharr acts as a qBittorrent server — connect via qBittorrent download client
configure_arr_app() {
  local app_name="$1" app_url="$2" api_key="$3" root_path="$4" category="$5"

  if [[ -z "$api_key" ]]; then
    warn "Skipping $app_name – no API key."
    return 1
  fi

  if ! wait_for_api "$app_name" "$app_url/api/v3/system/status?apikey=$api_key" 60; then
    return 1
  fi

  # Add root folder
  if ! has_root_folder "$app_url" "$api_key" "$root_path"; then
    info "  Adding root folder: $root_path"
    api_post "$app_url/api/v3/rootfolder" "$api_key" \
      "{&quot;path&quot;:&quot;$root_path&quot;}" && success "  Root folder added." || warn "  Failed to add root folder."
  else
    success "  Root folder $root_path already exists."
  fi

  # Add Decypharr as qBittorrent download client
  if ! has_download_client "$app_url" "$api_key" "Decypharr"; then
    info "  Adding Decypharr as qBittorrent download client..."
    api_post "$app_url/api/v3/downloadclient" "$api_key" "{
      &quot;enable&quot;: true,
      &quot;protocol&quot;: &quot;torrent&quot;,
      &quot;priority&quot;: 1,
      &quot;removeCompletedDownloads&quot;: true,
      &quot;removeFailedDownloads&quot;: true,
      &quot;name&quot;: &quot;Decypharr&quot;,
      &quot;fields&quot;: [
        {&quot;name&quot;: &quot;host&quot;, &quot;value&quot;: &quot;decypharr&quot;},
        {&quot;name&quot;: &quot;port&quot;, &quot;value&quot;: 8282},
        {&quot;name&quot;: &quot;username&quot;, &quot;value&quot;: &quot;http://${app_url#http://}&quot;},
        {&quot;name&quot;: &quot;password&quot;, &quot;value&quot;: &quot;${api_key}&quot;},
        {&quot;name&quot;: &quot;category&quot;, &quot;value&quot;: &quot;${category}&quot;},
        {&quot;name&quot;: &quot;useSsl&quot;, &quot;value&quot;: false}
      ],
      &quot;implementationName&quot;: &quot;qBittorrent&quot;,
      &quot;implementation&quot;: &quot;QBittorrent&quot;,
      &quot;configContract&quot;: &quot;QBittorrentSettings&quot;
    }" && success "  Decypharr download client added." || warn "  Failed to add download client."
  else
    success "  Decypharr download client already exists."
  fi
}

info "Configuring Radarr..."
configure_arr_app "Radarr" "http://localhost:7878" "$RADARR_KEY" \
  "/mnt/plex/Movies" "radarr"

info "Configuring Radarr 4K..."
configure_arr_app "Radarr 4K" "http://localhost:7879" "$RADARR4K_KEY" \
  "/mnt/plex/Movies - 4K" "radarr4k"

info "Configuring Sonarr..."
configure_arr_app "Sonarr" "http://localhost:8989" "$SONARR_KEY" \
  "/mnt/plex/TV" "sonarr"

info "Configuring Sonarr 4K..."
configure_arr_app "Sonarr 4K" "http://localhost:8990" "$SONARR4K_KEY" \
  "/mnt/plex/TV - 4K" "sonarr4k"

# ── Configure Prowlarr app connections ────────────────────────────────────
if [[ -n "$PROWLARR_KEY" ]] && wait_for_api "Prowlarr" "http://localhost:9696/api/v1/system/status?apikey=$PROWLARR_KEY" 60; then

  add_prowlarr_app() {
    local app_name="$1" impl="$2" server_url="$3" api_key="$4" sync_cats="$5"
    local existing
    existing=$(api_get "http://localhost:9696/api/v1/applications" "$PROWLARR_KEY")
    if echo "$existing" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    names = [d.get('name','') for d in data]
    sys.exit(0 if '$app_name' in names else 1)
except: sys.exit(1)
" 2>/dev/null; then
      success "  $app_name already connected to Prowlarr."
      return 0
    fi
    info "  Connecting $app_name to Prowlarr..."
    api_post "http://localhost:9696/api/v1/applications" "$PROWLARR_KEY" "{
      &quot;name&quot;: &quot;$app_name&quot;,
      &quot;syncLevel&quot;: &quot;fullSync&quot;,
      &quot;implementation&quot;: &quot;$impl&quot;,
      &quot;configContract&quot;: &quot;${impl}Settings&quot;,
      &quot;fields&quot;: [
        {&quot;name&quot;: &quot;prowlarrUrl&quot;, &quot;value&quot;: &quot;http://prowlarr:9696&quot;},
        {&quot;name&quot;: &quot;baseUrl&quot;, &quot;value&quot;: &quot;$server_url&quot;},
        {&quot;name&quot;: &quot;apiKey&quot;, &quot;value&quot;: &quot;$api_key&quot;},
        {&quot;name&quot;: &quot;syncCategories&quot;, &quot;value&quot;: [$sync_cats]}
      ]
    }" && success "  $app_name connected." || warn "  Failed to connect $app_name."
  }

  info "Connecting apps to Prowlarr..."
  [[ -n "$RADARR_KEY" ]]   && add_prowlarr_app "Radarr"    "Radarr" "http://radarr:7878"   "$RADARR_KEY"   "2000,2010,2020,2030,2040,2045,2050,2060,2070,2080"
  [[ -n "$RADARR4K_KEY" ]] && add_prowlarr_app "Radarr 4K" "Radarr" "http://radarr4k:7878" "$RADARR4K_KEY" "2000,2010,2020,2030,2040,2045,2050,2060,2070,2080"
  [[ -n "$SONARR_KEY" ]]   && add_prowlarr_app "Sonarr"    "Sonarr" "http://sonarr:8989"   "$SONARR_KEY"   "5000,5010,5020,5030,5040,5045,5050,5060,5070,5080"
  [[ -n "$SONARR4K_KEY" ]] && add_prowlarr_app "Sonarr 4K" "Sonarr" "http://sonarr4k:8989" "$SONARR4K_KEY" "5000,5010,5020,5030,5040,5045,5050,5060,5070,5080"

  # Add Torrentio indexer
  EXISTING_IDX=$(api_get "http://localhost:9696/api/v1/indexer" "$PROWLARR_KEY")
  if echo "$EXISTING_IDX" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    names = [d.get('name','').lower() for d in data]
    sys.exit(0 if 'torrentio' in names else 1)
except: sys.exit(1)
" 2>/dev/null; then
    success "  Torrentio indexer already configured."
  else
    info "  Adding Torrentio indexer..."
    api_post "http://localhost:9696/api/v1/indexer" "$PROWLARR_KEY" '{
      "name": "Torrentio",
      "enable": true,
      "appProfileId": 1,
      "definitionName": "torrentio",
      "implementation": "Cardigann",
      "configContract": "CardigannSettings",
      "fields": [
        {"name": "definitionFile", "value": "torrentio"},
        {"name": "baseUrl", "value": "https://torrentio.strem.fun"}
      ],
      "priority": 25
    }' && success "  Torrentio indexer added." || warn "  Could not add Torrentio automatically. Add it manually in Prowlarr → Indexers."
  fi
else
  warn "Skipping Prowlarr app connections."
fi

# ── Inject API keys into Decypharr config.json ────────────────────────────
info "Injecting API keys into Decypharr config.json..."
DECYPHARR_CONFIG_FILE="$DECYPHARR_DIR/config.json"
if [[ -f "$DECYPHARR_CONFIG_FILE" ]]; then
  # Use python3 to safely update the JSON
  python3 << PYEOF
import json

config_file = "$DECYPHARR_CONFIG_FILE"
with open(config_file, 'r') as f:
    config = json.load(f)

key_map = {
    "radarr":   "${RADARR_KEY}",
    "radarr4k": "${RADARR4K_KEY}",
    "sonarr":   "${SONARR_KEY}",
    "sonarr4k": "${SONARR4K_KEY}",
}

for arr in config.get("arrs", []):
    name = arr.get("name", "")
    if name in key_map and key_map[name]:
        arr["api_key"] = key_map[name]

with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)

print("  API keys injected into config.json")
PYEOF
  success "Decypharr config.json updated with API keys."

  info "Restarting Decypharr with updated config..."
  docker restart decypharr 2>/dev/null && success "Decypharr restarted." || warn "Could not restart Decypharr."
else
  warn "Decypharr config.json not found — configure manually at http://localhost:8282"
fi

success "Auto-configuration complete!"

# =============================================================================
# SECTION 8 – Update Plex libraries
# =============================================================================
section "Step 8 – Plex Library Configuration"

echo -e "  ${BOLD}You need to update your Plex libraries to point to the new paths:${NC}"
echo ""
echo -e "  ${CYAN}Old paths (remove these):${NC}"
echo -e "     /mnt/zurg/movies"
echo -e "     /mnt/zurg/shows"
echo ""
echo -e "  ${CYAN}New paths (add these):${NC}"
echo -e "     ${YELLOW}Movies${NC}        → /mnt/plex/Movies"
echo -e "     ${YELLOW}Movies - 4K${NC}   → /mnt/plex/Movies - 4K"
echo -e "     ${YELLOW}Movies - Anime${NC} → /mnt/plex/Movies - Anime"
echo -e "     ${YELLOW}TV${NC}            → /mnt/plex/TV"
echo -e "     ${YELLOW}TV - 4K${NC}       → /mnt/plex/TV - 4K"
echo -e "     ${YELLOW}TV - Anime${NC}    → /mnt/plex/TV - Anime"
echo ""
echo -e "  ${BOLD}Plex Settings to configure:${NC}"
echo -e "     ✅ Enable 'Scan my Library Automatically'"
echo -e "     ✅ Enable 'Run a partial scan when changes are detected'"
echo -e "     ❌ Disable 'Enable video preview thumbnails'"
echo -e "     ❌ Disable 'Perform extensive media analysis'"

# =============================================================================
# SECTION 9 – Update startup script
# =============================================================================
section "Step 9 – Update Startup Script"

info "Updating /root/startup.sh for arr stack..."
cat > /root/startup.sh << 'STARTUP_SCRIPT'
#!/bin/bash
# startup.sh – *arr stack with Decypharr + NZBDav
# Launched at boot via cron (@reboot)

LOG="/var/log/startup_arr_stack.log"
echo "[$(date)] startup.sh triggered" >> "$LOG"

# Wait for system to settle
sleep 15

# Ensure /mnt is a shared mount (required for rshared propagation into containers)
if ! mountpoint -q /mnt 2>/dev/null; then
  mount --bind /mnt /mnt 2>/dev/null || true
fi
mount --make-shared /mnt 2>/dev/null || true
echo "[$(date)] /mnt set as shared mount." >> "$LOG"

# ── Start Zurg + Rclone (Real-Debrid) ────────────────────────────────────────
echo "[$(date)] Starting Zurg + Rclone..." >> "$LOG"
cd /opt/zurg-testing && docker compose up -d >> "$LOG" 2>&1

# Wait for Zurg to be healthy
echo "[$(date)] Waiting for Zurg to be healthy..." >> "$LOG"
WAIT=0
while [[ $WAIT -lt 300 ]]; do
  STATUS=$(docker inspect --format '{{.State.Health.Status}}' zurg 2>/dev/null || echo "unknown")
  if [[ "$STATUS" == "healthy" ]]; then
    echo "[$(date)] Zurg is healthy." >> "$LOG"
    break
  fi
  sleep 10
  WAIT=$((WAIT + 10))
done

# Wait for Real-Debrid rclone mount to be ready
echo "[$(date)] Waiting for /mnt/remote/realdebrid mount..." >> "$LOG"
WAIT=0
while [[ $WAIT -lt 120 ]]; do
  if mountpoint -q /mnt/remote/realdebrid 2>/dev/null || ls /mnt/remote/realdebrid &>/dev/null; then
    echo "[$(date)] /mnt/remote/realdebrid is ready." >> "$LOG"
    break
  fi
  sleep 5
  WAIT=$((WAIT + 5))
done

# ── Start NZBDav + Rclone sidecar (Usenet) ───────────────────────────────────
if [ -f /opt/nzbdav/docker-compose.yml ]; then
  echo "[$(date)] Starting NZBDav..." >> "$LOG"
  cd /opt/nzbdav && docker compose up -d nzbdav >> "$LOG" 2>&1

  # Wait for NZBDav to be healthy before starting rclone sidecar
  echo "[$(date)] Waiting for NZBDav to be healthy..." >> "$LOG"
  WAIT=0
  while [[ $WAIT -lt 120 ]]; do
    if curl -sf "http://localhost:3000/health" &>/dev/null; then
      echo "[$(date)] NZBDav is healthy." >> "$LOG"
      break
    fi
    sleep 5
    WAIT=$((WAIT + 5))
  done

  # Start rclone sidecar (mounts WebDAV to /mnt/remote/nzbdav)
  echo "[$(date)] Starting NZBDav rclone sidecar..." >> "$LOG"
  cd /opt/nzbdav && docker compose up -d nzbdav_rclone >> "$LOG" 2>&1

  # Wait for NZBDav rclone mount to be ready before starting arr-stack
  echo "[$(date)] Waiting for /mnt/remote/nzbdav mount..." >> "$LOG"
  WAIT=0
  while [[ $WAIT -lt 120 ]]; do
    if ls /mnt/remote/nzbdav &>/dev/null; then
      echo "[$(date)] /mnt/remote/nzbdav is ready." >> "$LOG"
      break
    fi
    sleep 5
    WAIT=$((WAIT + 5))
  done

  if ! ls /mnt/remote/nzbdav &>/dev/null; then
    echo "[$(date)] WARNING: /mnt/remote/nzbdav not ready after 120s - starting arr-stack anyway." >> "$LOG"
  fi
else
  echo "[$(date)] NZBDav not installed, skipping." >> "$LOG"
fi

# ── Start *arr stack ──────────────────────────────────────────────────────────
# Starts AFTER all mounts are ready so containers see /mnt/remote/nzbdav correctly
echo "[$(date)] Starting *arr stack..." >> "$LOG"
cd /opt/arr-stack && docker compose up -d >> "$LOG" 2>&1

# ── Start Decypharr ───────────────────────────────────────────────────────────
echo "[$(date)] Starting Decypharr..." >> "$LOG"
cd /opt/decypharr && docker compose up -d >> "$LOG" 2>&1

echo "[$(date)] startup.sh complete." >> "$LOG"
STARTUP_SCRIPT

chmod +x /root/startup.sh
success "startup.sh updated."

# Ensure cron job exists
CRON_LINE="@reboot sleep 10 && /root/startup.sh"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
FILTERED_CRON=$(echo "$EXISTING_CRON" | grep -v "startup.sh" || true)
printf '%s\n%s\n' "$FILTERED_CRON" "$CRON_LINE" | grep -v '^$' | crontab - || true
success "Cron job verified."

# =============================================================================
# FINAL SUMMARY
# =============================================================================
section "Setup Complete!"

echo -e "${GREEN}${BOLD}*arr stack with Decypharr deployed successfully!${NC}\n"
echo -e "${BOLD}Access your services:${NC}"
echo ""
echo -e "  ${CYAN}Service${NC}          ${CYAN}URL${NC}                          ${CYAN}Port${NC}"
echo -e "  ─────────────────────────────────────────────────────"
echo -e "  Prowlarr         ${YELLOW}http://localhost:9696${NC}         9696"
echo -e "  Radarr           ${YELLOW}http://localhost:7878${NC}         7878"
echo -e "  Radarr 4K        ${YELLOW}http://localhost:7879${NC}         7879"
echo -e "  Sonarr           ${YELLOW}http://localhost:8989${NC}         8989"
echo -e "  Sonarr 4K        ${YELLOW}http://localhost:8990${NC}         8990"
echo -e "  Overseerr        ${YELLOW}http://localhost:5055${NC}         5055"
echo -e "  Pulsarr          ${YELLOW}http://localhost:3003${NC}         3003"
echo -e "  Decypharr        ${YELLOW}http://localhost:8282${NC}         8282"
echo -e "  Plex             ${YELLOW}http://localhost:32400/web${NC}    32400"
echo -e "  Zurg             ${YELLOW}http://localhost:9999${NC}         9999"
echo ""
echo -e "${BOLD}Auto-configured (done by script):${NC}"
echo ""
echo -e "  ✅ Radarr:     Root folder + Decypharr qBittorrent download client"
echo -e "  ✅ Radarr 4K:  Root folder + Decypharr qBittorrent download client"
echo -e "  ✅ Sonarr:     Root folder + Decypharr qBittorrent download client"
echo -e "  ✅ Sonarr 4K:  Root folder + Decypharr qBittorrent download client"
echo -e "  ✅ Prowlarr:   Connected to all 4 *arr apps + Torrentio indexer"
echo -e "  ✅ Decypharr:  API keys injected into config.json"
echo ""
echo -e "${BOLD}API Keys:${NC}"
echo ""
echo -e "  Radarr:     ${YELLOW}${RADARR_KEY:-check /opt/radarr/config.xml}${NC}"
echo -e "  Radarr 4K:  ${YELLOW}${RADARR4K_KEY:-check /opt/radarr4k/config.xml}${NC}"
echo -e "  Sonarr:     ${YELLOW}${SONARR_KEY:-check /opt/sonarr/config.xml}${NC}"
echo -e "  Sonarr 4K:  ${YELLOW}${SONARR4K_KEY:-check /opt/sonarr4k/config.xml}${NC}"
echo -e "  Prowlarr:   ${YELLOW}${PROWLARR_KEY:-check /opt/prowlarr/config.xml}${NC}"
echo ""
echo -e "${BOLD}Decypharr Setup (complete via Web UI at http://localhost:8282):${NC}"
echo ""
echo -e "  ${CYAN}1. Open http://localhost:8282${NC}"
echo -e "     a. Set up login credentials (or skip)"
echo -e "     b. Go to Settings → Debrid"
echo -e "        - Provider: Real-Debrid"
echo -e "        - API Key: ${YELLOW}${RD_API_TOKEN:0:8}...${NC} (already in config.json)"
echo -e "        - Mount/Rclone Folder: /mnt/remote/realdebrid/__all__"
echo -e "     c. Go to Settings → qBittorrent"
echo -e "        - Download Folder: /mnt/symlinks"
echo -e "     d. Go to Settings → Repair"
echo -e "        - Enable Scheduled Repair: Yes"
echo -e "        - Interval: 6h"
echo ""
echo -e "  ${CYAN}2. Verify Sonarr/Radarr download clients:${NC}"
echo -e "     Each *arr app should show 'Decypharr' as a qBittorrent client"
echo -e "     Host: decypharr  Port: 8282"
echo -e "     Username: http://<arr-host>:<port>  Password: <arr-api-key>"
echo ""
echo -e "  ${CYAN}3. Configure Pulsarr (http://localhost:3003):${NC}"
echo -e "     a. Connect to Plex (enter your Plex token)"
echo -e "     b. Add Sonarr (URL: ${YELLOW}http://sonarr:8989${NC}, API key: ${YELLOW}${SONARR_KEY:-see above}${NC})"
echo -e "     c. Add Radarr (URL: ${YELLOW}http://radarr:7878${NC}, API key: ${YELLOW}${RADARR_KEY:-see above}${NC})"
echo -e "     → Users just add to their Plex watchlist and Pulsarr handles the rest!"
echo ""
echo -e "  ${CYAN}4. Configure Overseerr (http://localhost:5055):${NC}"
echo -e "     a. Sign in with your Plex account"
echo -e "     b. Add Radarr (hostname: ${YELLOW}radarr${NC}, port: ${YELLOW}7878${NC})"
echo -e "     c. Add Sonarr (hostname: ${YELLOW}sonarr${NC}, port: ${YELLOW}8989${NC})"
echo ""
echo -e "  ${CYAN}5. Update Plex libraries:${NC}"
echo -e "     Point libraries to /mnt/plex/ directories (see Step 8 above)"
echo ""
echo -e "${BOLD}Useful commands:${NC}"
echo ""
echo -e "  ${YELLOW}docker ps${NC}                                      # All containers"
echo -e "  ${YELLOW}docker logs decypharr --tail 50 -f${NC}             # Decypharr logs"
echo -e "  ${YELLOW}docker logs radarr --tail 50 -f${NC}                # Radarr logs"
echo -e "  ${YELLOW}docker logs sonarr --tail 50 -f${NC}                # Sonarr logs"
echo -e "  ${YELLOW}cd /opt/arr-stack && docker compose restart${NC}    # Restart *arrs"
echo -e "  ${YELLOW}cd /opt/decypharr && docker compose restart${NC}    # Restart Decypharr"
echo -e "  ${YELLOW}cd /opt/zurg-testing && docker compose restart${NC} # Restart Zurg"
echo ""
echo -e "${BOLD}How Decypharr works:${NC}"
echo ""
echo -e "  Sonarr/Radarr → sends magnet/torrent to Decypharr (qBittorrent API)"
echo -e "  Decypharr     → adds to Real-Debrid, waits for cache"
echo -e "  Decypharr     → creates symlink in /mnt/symlinks/<category>/"
echo -e "  Plex          → detects new symlink → scans library → content available!"
echo ""