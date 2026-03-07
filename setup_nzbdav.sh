#!/bin/bash
# =============================================================================
# NZBDav Setup Script
# Installs NZBDav + Rclone sidecar for Usenet streaming with Sonarr/Radarr
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# =============================================================================
# CONFIGURATION
# =============================================================================
NZBDAV_DIR="/opt/nzbdav"
NZBDAV_PORT="3000"
NZBDAV_MOUNT="/mnt/remote/nzbdav"
PUID=$(id -u)
PGID=$(id -g)
TZ="${TZ:-Etc/UTC}"

# Detect Docker Compose command
if docker compose version &>/dev/null 2>&1; then
    DOCKER_CMD="docker compose"
elif docker-compose version &>/dev/null 2>&1; then
    DOCKER_CMD="docker-compose"
else
    error "Docker Compose not found. Please install Docker first."
fi

# =============================================================================
# STEP 1: COLLECT CONFIGURATION
# =============================================================================
section "NZBDav Setup"

echo ""
echo "NZBDav is a WebDAV server that allows you to stream Usenet content"
echo "without downloading it. It integrates with Sonarr/Radarr as a SABnzbd"
echo "download client."
echo ""
echo "You will need:"
echo "  - A Usenet provider (e.g., Newshosting, UsenetExpress)"
echo "  - Usenet indexers (configured in Prowlarr)"
echo ""

# Get WebDAV password
echo -e "${YELLOW}Enter a password for the NZBDav WebDAV server:${NC}"
read -s WEBDAV_PASSWORD
echo ""
if [ -z "$WEBDAV_PASSWORD" ]; then
    error "WebDAV password cannot be empty."
fi

echo -e "${YELLOW}Confirm WebDAV password:${NC}"
read -s WEBDAV_PASSWORD_CONFIRM
echo ""
if [ "$WEBDAV_PASSWORD" != "$WEBDAV_PASSWORD_CONFIRM" ]; then
    error "Passwords do not match."
fi

# Get timezone
echo -e "${YELLOW}Enter your timezone (e.g., America/New_York, Europe/London, Etc/UTC) [${TZ}]:${NC}"
read -r TZ_INPUT
TZ="${TZ_INPUT:-$TZ}"

# Get PUID/PGID
echo -e "${YELLOW}Enter PUID (your user ID) [${PUID}]:${NC}"
read -r PUID_INPUT
PUID="${PUID_INPUT:-$PUID}"

echo -e "${YELLOW}Enter PGID (your group ID) [${PGID}]:${NC}"
read -r PGID_INPUT
PGID="${PGID_INPUT:-$PGID}"

# Ask about arr-stack integration
echo ""
echo -e "${YELLOW}Do you want to connect NZBDav to your existing arr-stack? (y/n) [y]:${NC}"
read -r ARR_INTEGRATION
ARR_INTEGRATION="${ARR_INTEGRATION:-y}"

if [[ "$ARR_INTEGRATION" =~ ^[Yy]$ ]]; then
    # Get Radarr API key
    RADARR_API_KEY=""
    if [ -f "/opt/radarr/config.xml" ]; then
        RADARR_API_KEY=$(grep -oP '<ApiKey>\K[^<]+' /opt/radarr/config.xml 2>/dev/null || true)
        log "Auto-detected Radarr API key"
    fi
    if [ -z "$RADARR_API_KEY" ]; then
        echo -e "${YELLOW}Enter Radarr API key (Settings > General > Security):${NC}"
        read -r RADARR_API_KEY
    fi

    # Get Radarr 4K API key
    RADARR4K_API_KEY=""
    if [ -f "/opt/radarr4k/config.xml" ]; then
        RADARR4K_API_KEY=$(grep -oP '<ApiKey>\K[^<]+' /opt/radarr4k/config.xml 2>/dev/null || true)
        log "Auto-detected Radarr 4K API key"
    fi
    if [ -z "$RADARR4K_API_KEY" ]; then
        echo -e "${YELLOW}Enter Radarr 4K API key (leave blank to skip):${NC}"
        read -r RADARR4K_API_KEY
    fi

    # Get Sonarr API key
    SONARR_API_KEY=""
    if [ -f "/opt/sonarr/config.xml" ]; then
        SONARR_API_KEY=$(grep -oP '<ApiKey>\K[^<]+' /opt/sonarr/config.xml 2>/dev/null || true)
        log "Auto-detected Sonarr API key"
    fi
    if [ -z "$SONARR_API_KEY" ]; then
        echo -e "${YELLOW}Enter Sonarr API key (Settings > General > Security):${NC}"
        read -r SONARR_API_KEY
    fi

    # Get Sonarr 4K API key
    SONARR4K_API_KEY=""
    if [ -f "/opt/sonarr4k/config.xml" ]; then
        SONARR4K_API_KEY=$(grep -oP '<ApiKey>\K[^<]+' /opt/sonarr4k/config.xml 2>/dev/null || true)
        log "Auto-detected Sonarr 4K API key"
    fi
    if [ -z "$SONARR4K_API_KEY" ]; then
        echo -e "${YELLOW}Enter Sonarr 4K API key (leave blank to skip):${NC}"
        read -r SONARR4K_API_KEY
    fi
fi

# =============================================================================
# STEP 2: CREATE DIRECTORIES
# =============================================================================
section "Step 1: Creating Directories"

log "Creating NZBDav directories..."
mkdir -p "$NZBDAV_DIR/config"
mkdir -p "$NZBDAV_MOUNT"
chown -R "$PUID:$PGID" "$NZBDAV_MOUNT" 2>/dev/null || true

log "Directories created:"
log "  Config: $NZBDAV_DIR/config"
log "  Mount:  $NZBDAV_MOUNT"

# =============================================================================
# STEP 3: GENERATE RCLONE CONFIG
# =============================================================================
section "Step 2: Generating Rclone Config"

log "Generating obscured WebDAV password for Rclone..."
OBSCURED_PASSWORD=$(docker run --rm rclone/rclone obscure "$WEBDAV_PASSWORD" 2>/dev/null)
if [ -z "$OBSCURED_PASSWORD" ]; then
    error "Failed to generate obscured password. Is Docker running?"
fi
log "Password obscured successfully."

# Create rclone.conf
cat > "$NZBDAV_DIR/rclone.conf" << EOF
[nzbdav]
type = webdav
url = http://nzbdav:${NZBDAV_PORT}/
vendor = other
user = admin
pass = ${OBSCURED_PASSWORD}
EOF

log "Rclone config created at $NZBDAV_DIR/rclone.conf"

# =============================================================================
# STEP 4: CREATE DOCKER COMPOSE
# =============================================================================
section "Step 3: Creating Docker Compose"

# Determine network - use arr-stack if it exists, otherwise create nzbdav network
NETWORK_NAME="nzbdav"
NETWORK_SECTION=""
if docker network inspect arr-stack &>/dev/null 2>&1; then
    NETWORK_NAME="arr-stack"
    log "Using existing arr-stack Docker network"
else
    NETWORK_SECTION="
networks:
  nzbdav:
    name: nzbdav
    driver: bridge"
    log "Will create new nzbdav Docker network"
fi

cat > "$NZBDAV_DIR/docker-compose.yml" << EOF
services:
  nzbdav:
    image: nzbdav/nzbdav:latest
    container_name: nzbdav
    restart: unless-stopped
    healthcheck:
      test: curl -f http://localhost:3000/health || exit 1
      interval: 1m
      retries: 3
      start_period: 30s
      timeout: 10s
    ports:
      - "${NZBDAV_PORT}:3000"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${NZBDAV_DIR}/config:/config
      - /mnt:/mnt
    networks:
      - ${NETWORK_NAME}

  nzbdav_rclone:
    image: rclone/rclone:latest
    container_name: nzbdav_rclone
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - /mnt:/mnt:rshared
      - ${NZBDAV_DIR}/rclone.conf:/config/rclone/rclone.conf
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse:rwm
    depends_on:
      nzbdav:
        condition: service_healthy
        restart: true
    command: >
      mount nzbdav: /mnt/remote/nzbdav
        --uid=${PUID}
        --gid=${PGID}
        --allow-other
        --links
        --use-cookies
        --vfs-cache-mode=off
        --buffer-size=32M
        --dir-cache-time=20s
        --no-checksum
    networks:
      - ${NETWORK_NAME}

networks:
  ${NETWORK_NAME}:
    external: true
EOF

# If using new network, update compose to not use external
if [ "$NETWORK_NAME" = "nzbdav" ]; then
    cat > "$NZBDAV_DIR/docker-compose.yml" << EOF
services:
  nzbdav:
    image: nzbdav/nzbdav:latest
    container_name: nzbdav
    restart: unless-stopped
    healthcheck:
      test: curl -f http://localhost:3000/health || exit 1
      interval: 1m
      retries: 3
      start_period: 30s
      timeout: 10s
    ports:
      - "${NZBDAV_PORT}:3000"
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - ${NZBDAV_DIR}/config:/config
      - /mnt:/mnt
    networks:
      - nzbdav

  nzbdav_rclone:
    image: rclone/rclone:latest
    container_name: nzbdav_rclone
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - /mnt:/mnt:rshared
      - ${NZBDAV_DIR}/rclone.conf:/config/rclone/rclone.conf
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse:rwm
    depends_on:
      nzbdav:
        condition: service_healthy
        restart: true
    command: >
      mount nzbdav: /mnt/remote/nzbdav
        --uid=${PUID}
        --gid=${PGID}
        --allow-other
        --links
        --use-cookies
        --vfs-cache-mode=off
        --buffer-size=32M
        --dir-cache-time=20s
        --no-checksum
    networks:
      - nzbdav

networks:
  nzbdav:
    name: nzbdav
    driver: bridge
EOF
fi

log "Docker Compose created at $NZBDAV_DIR/docker-compose.yml"

# =============================================================================
# STEP 5: PREPARE MOUNT POINT
# =============================================================================
section "Step 4: Preparing Mount Point"

# Clean up any stale mounts
if mountpoint -q "$NZBDAV_MOUNT" 2>/dev/null; then
    warn "Stale mount detected at $NZBDAV_MOUNT, cleaning up..."
    fusermount -uz "$NZBDAV_MOUNT" 2>/dev/null || umount -l "$NZBDAV_MOUNT" 2>/dev/null || true
    sleep 2
fi

# Ensure /mnt is a shared mount
if ! mount | grep -q "on /mnt type"; then
    log "Setting up /mnt as shared mount..."
    mount --bind /mnt /mnt 2>/dev/null || true
    mount --make-shared /mnt 2>/dev/null || true
else
    mount --make-shared /mnt 2>/dev/null || true
fi

log "Mount point ready at $NZBDAV_MOUNT"

# =============================================================================
# STEP 6: START CONTAINERS
# =============================================================================
section "Step 5: Starting NZBDav Containers"

log "Starting NZBDav..."
(cd "$NZBDAV_DIR" && $DOCKER_CMD up -d nzbdav)

log "Waiting for NZBDav to be healthy (up to 60 seconds)..."
for i in $(seq 1 12); do
    if curl -sf "http://localhost:${NZBDAV_PORT}/health" &>/dev/null; then
        log "NZBDav is healthy!"
        break
    fi
    if [ "$i" -eq 12 ]; then
        warn "NZBDav health check timed out. Check logs: docker logs nzbdav"
    fi
    sleep 5
done

log "Starting Rclone sidecar..."
(cd "$NZBDAV_DIR" && $DOCKER_CMD up -d nzbdav_rclone)

log "Waiting for Rclone mount (up to 60 seconds)..."
for i in $(seq 1 12); do
    if ls "$NZBDAV_MOUNT" &>/dev/null; then
        log "Rclone mount is ready!"
        break
    fi
    if [ "$i" -eq 12 ]; then
        warn "Rclone mount not ready yet. Check logs: docker logs nzbdav_rclone"
    fi
    sleep 5
done

# =============================================================================
# STEP 7: CONNECT TO ARR-STACK NETWORK (if needed)
# =============================================================================
if [[ "$ARR_INTEGRATION" =~ ^[Yy]$ ]] && [ "$NETWORK_NAME" = "nzbdav" ]; then
    section "Step 6: Connecting to arr-stack Network"

    if docker network inspect arr-stack &>/dev/null 2>&1; then
        log "Connecting nzbdav to arr-stack network..."
        docker network connect arr-stack nzbdav 2>/dev/null || log "nzbdav already on arr-stack network"
        docker network connect arr-stack nzbdav_rclone 2>/dev/null || log "nzbdav_rclone already on arr-stack network"
        log "Connected to arr-stack network"
    fi
fi

# =============================================================================
# STEP 8: AUTO-CONFIGURE ARR APPS
# =============================================================================
if [[ "$ARR_INTEGRATION" =~ ^[Yy]$ ]]; then
    section "Step 7: Auto-Configuring Arr Apps"

    log "Waiting for NZBDav API to be ready..."
    sleep 5

    # Get NZBDav SABnzbd API key from config
    NZBDAV_API_KEY=""
    for i in $(seq 1 12); do
        if [ -f "$NZBDAV_DIR/config/settings.json" ]; then
            NZBDAV_API_KEY=$(python3 -c "import json; d=json.load(open('$NZBDAV_DIR/config/settings.json')); print(d.get('sabnzbd',{}).get('apiKey',''))" 2>/dev/null || true)
        fi
        if [ -n "$NZBDAV_API_KEY" ]; then
            log "Auto-detected NZBDav API key"
            break
        fi
        sleep 5
    done

    if [ -z "$NZBDAV_API_KEY" ]; then
        warn "Could not auto-detect NZBDav API key."
        warn "You will need to manually add NZBDav as a download client in Radarr/Sonarr."
        warn "Go to NZBDav Settings > SABnzbd to find your API key."
    else
        log "NZBDav API key: $NZBDAV_API_KEY"

        # Add NZBDav as SABnzbd download client to Radarr
        add_nzbdav_to_arr() {
            local name="$1"
            local host="$2"
            local port="$3"
            local api_key="$4"
            local arr_name="$5"

            log "Adding NZBDav to $arr_name..."
            RESPONSE=$(curl -sf -X POST "http://localhost:${port}/api/v3/downloadclient" \
                -H "X-Api-Key: $api_key" \
                -H "Content-Type: application/json" \
                -d "{
                    &quot;name&quot;: &quot;NZBDav&quot;,
                    &quot;enable&quot;: true,
                    &quot;protocol&quot;: &quot;usenet&quot;,
                    &quot;priority&quot;: 1,
                    &quot;removeCompletedDownloads&quot;: true,
                    &quot;removeFailedDownloads&quot;: true,
                    &quot;implementation&quot;: &quot;Sabnzbd&quot;,
                    &quot;configContract&quot;: &quot;SabnzbdSettings&quot;,
                    &quot;fields&quot;: [
                        {&quot;name&quot;: &quot;host&quot;, &quot;value&quot;: &quot;nzbdav&quot;},
                        {&quot;name&quot;: &quot;port&quot;, &quot;value&quot;: 3000},
                        {&quot;name&quot;: &quot;apiKey&quot;, &quot;value&quot;: &quot;$NZBDAV_API_KEY&quot;},
                        {&quot;name&quot;: &quot;tvCategory&quot;, &quot;value&quot;: &quot;tv&quot;},
                        {&quot;name&quot;: &quot;recentTvPriority&quot;, &quot;value&quot;: 0},
                        {&quot;name&quot;: &quot;olderTvPriority&quot;, &quot;value&quot;: 0},
                        {&quot;name&quot;: &quot;useSsl&quot;, &quot;value&quot;: false}
                    ]
                }" 2>/dev/null || true)

            if echo "$RESPONSE" | grep -q '"id"'; then
                log "  ✓ NZBDav added to $arr_name"
            else
                warn "  ✗ Failed to add NZBDav to $arr_name (may already exist)"
            fi
        }

        # Add to each arr app
        [ -n "$RADARR_API_KEY" ]   && add_nzbdav_to_arr "NZBDav" "radarr"   "7878" "$RADARR_API_KEY"   "Radarr"
        [ -n "$RADARR4K_API_KEY" ] && add_nzbdav_to_arr "NZBDav" "radarr4k" "7879" "$RADARR4K_API_KEY" "Radarr 4K"
        [ -n "$SONARR_API_KEY" ]   && add_nzbdav_to_arr "NZBDav" "sonarr"   "8989" "$SONARR_API_KEY"   "Sonarr"
        [ -n "$SONARR4K_API_KEY" ] && add_nzbdav_to_arr "NZBDav" "sonarr4k" "8990" "$SONARR4K_API_KEY" "Sonarr 4K"
    fi
fi

# =============================================================================
# DONE
# =============================================================================
section "NZBDav Setup Complete!"

echo ""
echo -e "${GREEN}✓ NZBDav is running!${NC}"
echo ""
echo -e "${BLUE}Service URLs:${NC}"
echo "  NZBDav Web UI:  http://localhost:${NZBDAV_PORT}"
echo "  WebDAV Mount:   $NZBDAV_MOUNT"
echo ""
echo -e "${YELLOW}IMPORTANT - Manual Steps Required:${NC}"
echo ""
echo "1. Open NZBDav at http://localhost:${NZBDAV_PORT}"
echo "   - Create your admin account on first login"
echo ""
echo "2. Configure Usenet Provider (Settings > Usenet):"
echo "   - Host: your usenet provider (e.g., news.newshosting.com)"
echo "   - Port: 563"
echo "   - Username/Password: your usenet credentials"
echo "   - Max Connections: your provider's max (e.g., 100)"
echo "   - Use SSL: Checked"
echo ""
echo "3. Configure WebDAV (Settings > WebDAV):"
echo "   - Set WebDAV Password: ${WEBDAV_PASSWORD}"
echo "   - Enforce Read-Only: Unchecked (recommended)"
echo ""
echo "4. Configure Rclone Mount (Settings > SABnzbd):"
echo "   - Rclone Mount Directory: ${NZBDAV_MOUNT}"
echo ""
echo "5. Configure Arr Integration (Settings > Radarr/Sonarr):"
echo "   - Add each arr app with its host and API key"
echo ""
if [ -z "${NZBDAV_API_KEY:-}" ]; then
echo "6. Add NZBDav as Download Client in Radarr/Sonarr:"
echo "   - Type: SABnzbd"
echo "   - Host: nzbdav"
echo "   - Port: 3000"
echo "   - API Key: (found in NZBDav Settings > SABnzbd)"
echo ""
fi
echo -e "${BLUE}Useful Commands:${NC}"
echo "  Check status:    docker ps | grep nzbdav"
echo "  View logs:       docker logs nzbdav"
echo "  Rclone logs:     docker logs nzbdav_rclone"
echo "  Check mount:     ls -la ${NZBDAV_MOUNT}"
echo "  Restart:         cd ${NZBDAV_DIR} && docker compose restart"
echo ""
echo -e "${BLUE}Mount Structure (after first download):${NC}"
echo "  ${NZBDAV_MOUNT}/.ids/              - Streamable content"
echo "  ${NZBDAV_MOUNT}/completed-symlinks/ - Symlinks for arr apps"
echo "  ${NZBDAV_MOUNT}/content/            - Browsable content"
echo "  ${NZBDAV_MOUNT}/nzbs/               - NZB files"
echo ""