#!/bin/bash
# =============================================================================
#  Plex + Real-Debrid Setup Script (Zurg & Rclone)
#  Based on: https://docs.google.com/document/d/114URAz5h5jarpo1xz4GyFUzRzoBnOKVQPxH0-2R5KC8
#  Updated with fixes from community troubleshooting
# =============================================================================
#
#  USAGE:
#    chmod +x setup_plex_debrid.sh
#    sudo ./setup_plex_debrid.sh
#
#  WHAT THIS SCRIPT DOES:
#    1. Checks / installs Docker (removes snap Docker if present)
#    2. Clones & configures Zurg + Rclone containers
#    3. Installs Plex Media Server
#    4. Installs Python 3 & Pip
#    5. Installs plex_debrid
#    6. Creates monitor_folders.sh (Plex library refresh workaround)
#    7. Creates startup.sh and registers it as a @reboot cron job
#    8. Adds required PATH entries to ~/.bashrc
#
#  PREREQUISITES:
#    - Ubuntu 22.04 / 23.10 / 24.04 (local or remote)
#    - A Real-Debrid account + API token  (https://real-debrid.com/apitoken)
#    - A Plex account + Plex token        (https://www.plexopedia.com/plex-media-server/general/plex-token/)
#    - Internet access
#
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

# ── Helpers ──────────────────────────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $*${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

# ── Root check ───────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run this script as root:  sudo ./setup_plex_debrid.sh"
fi

# ── Banner ───────────────────────────────────────────────────────────
clear
echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  ____  _             ____       _     _     _     _
 |  _ \| | _____  __ |  _ \  ___| |__ | |__ (_) __| |
 | |_) | |/ _ \ \/ / | | | |/ _ \ '_ \| '_ \| |/ _` |
 |  __/| |  __/>  <  | |_| |  __/ |_) | |_) | | (_| |
 |_|   |_|\___/_/\_\ |____/ \___|_.__/|_.__/|_|\__,_|

  + Real-Debrid  ·  Zurg  ·  Rclone  ·  plex_debrid
EOF
echo -e "${NC}"
echo -e "  Setup script based on the Newbie Guide by the community\n"

# =============================================================================
# SECTION 0 – Collect user credentials
# =============================================================================
section "Step 0 – Configuration"

# ── Real-Debrid API token ────────────────────────────────────────────
if [[ -z "${RD_API_TOKEN:-}" ]]; then
  echo -e "  Get your Real-Debrid API token from: ${YELLOW}https://real-debrid.com/apitoken${NC}"
  read -rp "  Enter your Real-Debrid API token: " RD_API_TOKEN
fi
[[ -z "$RD_API_TOKEN" ]] && error "Real-Debrid API token cannot be empty."

# ── Plex token ───────────────────────────────────────────────────────
# NOTE: Plex token is collected AFTER Plex is installed (see Section 4).
# We set it empty here and prompt for it later.
PLEX_TOKEN="${PLEX_TOKEN:-}"

# ── Zurg version ─────────────────────────────────────────────────────
ZURG_VERSION="${ZURG_VERSION:-v0.9.3-final}"
echo -e "\n  Using Zurg version: ${YELLOW}${ZURG_VERSION}${NC}"
read -rp "  Press Enter to keep this version or type a different one: " USER_ZURG_VERSION
[[ -n "$USER_ZURG_VERSION" ]] && ZURG_VERSION="$USER_ZURG_VERSION"

# ── Remote or local server ───────────────────────────────────────────
echo ""
read -rp "  Is this a REMOTE server (VPS/Linode)? [y/N]: " IS_REMOTE
IS_REMOTE="${IS_REMOTE,,}"   # lowercase

if [[ "$IS_REMOTE" == "y" || "$IS_REMOTE" == "yes" ]]; then
  PLEX_URL="http://localhost:8888/web"
  ZURG_URL="http://localhost:8889"
  info "Remote mode – Plex accessible at $PLEX_URL"
else
  PLEX_URL="http://localhost:32400/web"
  ZURG_URL="http://localhost:9999"
  info "Local mode – Plex accessible at $PLEX_URL"
fi

success "Configuration collected."

# =============================================================================
# SECTION 1 – System update & essential tools
# =============================================================================
section "Step 1 – System Update"

info "Running apt update & upgrade..."
apt-get update -y
apt-get upgrade -y
success "System updated."

info "Installing essential tools (git, curl, screen, inotify-tools, libxml2-utils, fuse3)..."
apt-get install -y git curl wget screen inotify-tools libxml2-utils fuse3
success "Essential tools installed."

# =============================================================================
# SECTION 2 – Install Docker
# =============================================================================
section "Step 2 – Install Docker"

# ── Remove snap Docker if present and reinstall via apt ──────────────
if snap list docker &>/dev/null 2>&1; then
  warn "Docker is installed via Snap. Snap Docker has AppArmor restrictions that"
  warn "prevent rclone from working (cannot create shared mounts)."
  warn "Removing snap Docker and reinstalling via official apt packages..."
  snap remove docker
  # Clean up any leftover snap docker files
  rm -f /usr/local/bin/docker 2>/dev/null || true
  success "Snap Docker removed."
fi

if command -v docker &>/dev/null && ! snap list docker &>/dev/null 2>&1; then
  success "Docker is already installed (non-snap): $(docker --version)"
else
  info "Removing any old Docker packages..."
  apt-get remove -y docker docker-engine docker.io 2>/dev/null || true

  info "Installing Docker prerequisites..."
  apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

  info "Adding Docker GPG key..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  info "Adding Docker stable repository..."
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -y
  info "Installing Docker Engine..."
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  success "Docker installed: $(docker --version)"
fi

# Also handle non-root Docker access (add current user to docker group if not root)
if [[ $EUID -ne 0 ]] && ! groups | grep -q docker; then
  info "Adding current user to docker group..."
  usermod -aG docker "$USER" || warn "Could not add user to docker group – you may need to use sudo with docker commands."
fi

info "Starting Docker service..."
# Docker Desktop / some installs use a socket rather than docker.service
if systemctl list-units --type=service 2>/dev/null | grep -q "docker.service"; then
  systemctl start docker   || warn "docker.service start failed – may already be running via socket."
  systemctl enable docker  || warn "docker.service enable failed – skipping."
else
  warn "docker.service unit not found – Docker may be running via Docker Desktop or socket activation. Skipping systemctl start."
fi

if systemctl list-units --type=service 2>/dev/null | grep -q "containerd.service"; then
  systemctl enable containerd || warn "containerd.service enable failed – skipping."
fi

# ── Ensure the invoking user is in the docker group ──────────────────
# When run via "sudo ./setup.sh", SUDO_USER is the original user
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  # Create docker group if it doesn't exist
  if ! getent group docker &>/dev/null; then
    info "Creating docker group..."
    groupadd docker
    success "docker group created."
  fi
  # Add socket to docker group
  chgrp docker /var/run/docker.sock 2>/dev/null || true
  chmod g+rw /var/run/docker.sock 2>/dev/null || true
  if ! groups "$REAL_USER" | grep -q '\bdocker\b'; then
    info "Adding '$REAL_USER' to the docker group..."
    usermod -aG docker "$REAL_USER"
    success "User '$REAL_USER' added to docker group."
    warn "NOTE: Group membership takes effect in NEW shell sessions."
    warn "After this script finishes, run: newgrp docker  (or log out and back in)"
  else
    success "User '$REAL_USER' is already in the docker group."
  fi
fi

# ── Set DOCKER_CMD: find a way to reach the Docker socket ────────────
DOCKER_CMD="docker"

if docker info &>/dev/null 2>&1; then
  success "Docker is running and accessible as root."
elif [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
  info "Root cannot reach Docker socket – trying as user '$REAL_USER'..."

  # Option 1: sudo -u REAL_USER (works if user is in docker group in current session)
  if sudo -u "$REAL_USER" docker info &>/dev/null 2>&1; then
    DOCKER_CMD="sudo -u $REAL_USER docker"
    success "Docker accessible via: $DOCKER_CMD"

  # Option 2: sg docker (activates group without re-login)
  elif sg docker -c "docker info" &>/dev/null 2>&1; then
    DOCKER_CMD="sg docker -c docker"
    success "Docker accessible via sg docker."

  # Option 3: run directly with socket group set
  elif sudo -u "$REAL_USER" sg docker -c "docker info" &>/dev/null 2>&1; then
    DOCKER_CMD="sudo -u $REAL_USER sg docker -c docker"
    success "Docker accessible via sudo + sg docker."

  else
    error "Cannot connect to Docker socket. Please log out and back in (or run 'newgrp docker') then re-run this script."
  fi
else
  error "Cannot connect to Docker daemon. Please ensure Docker is running and re-run the script."
fi
success "Using Docker command: $DOCKER_CMD"

info "Running hello-world test..."
$DOCKER_CMD run --rm hello-world | grep -i "hello from docker" \
  && success "Docker hello-world test passed." \
  || warn "hello-world test output unexpected – Docker may still be fine."

# =============================================================================
# SECTION 3 – Zurg & Rclone
# =============================================================================
section "Step 3 – Zurg & Rclone Setup"

ZURG_DIR="/opt/zurg-testing"

info "Pulling Zurg Docker image (${ZURG_VERSION})..."
$DOCKER_CMD pull "ghcr.io/debridmediamanager/zurg-testing:${ZURG_VERSION}"

if [[ -d "$ZURG_DIR" ]]; then
  warn "Directory $ZURG_DIR already exists – skipping git clone."
else
  info "Cloning Zurg repository to $ZURG_DIR..."
  git clone https://github.com/debridmediamanager/zurg-testing.git "$ZURG_DIR"
fi

info "Files in $ZURG_DIR:"
ls -1 "$ZURG_DIR"

# ── config.yml ───────────────────────────────────────────────────────
# Uses official filter syntax from:
# https://github.com/debridmediamanager/zurg-testing/wiki/Config-v0.9
#
# KEY: shows (group_order: 10) is evaluated FIRST via has_episodes: true
#      movies (group_order: 20) catches everything else with regex: /.*/
#      Both are in group: media so duplicates are handled correctly.
info "Writing config.yml..."
cat > "$ZURG_DIR/config.yml" << ZURG_CONFIG
# Zurg configuration
# Generated by setup_plex_debrid.sh

zurg: v1
token: ${RD_API_TOKEN}
port: 9999
concurrent_workers: 20
check_for_changes_every_secs: 10
enable_repair: true
ignore_renames: true
retain_folder_name_extension: true
retain_rd_torrent_name: true
auto_analyze_new_torrents: true
cache_network_test_results: true
on_library_update: sh plex_update.sh "\$@"
mount_path: /mnt/zurg

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
if [[ ! -f "$ZURG_DIR/config.yml" ]]; then
  error "config.yml was not created at $ZURG_DIR/config.yml – check permissions."
fi
success "config.yml written."

# ── docker-compose.yml ───────────────────────────────────────────────
info "Writing docker-compose.yml..."
cat > "$ZURG_DIR/docker-compose.yml" << COMPOSE_CONFIG
services:
  zurg:
    image: ghcr.io/debridmediamanager/zurg-testing:${ZURG_VERSION}
    container_name: zurg-testing-zurg-1
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
    container_name: zurg-testing-rclone-1
    restart: unless-stopped
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined
    devices:
      - /dev/fuse:/dev/fuse:rwm
    volumes:
      - ${ZURG_DIR}/rclone.conf:/config/rclone/rclone.conf
      - /mnt/zurg:/mnt/zurg:shared
    command: >
      mount zurg: /mnt/zurg
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
success "docker-compose.yml written."

# Verify the file was actually written
if [[ ! -f "$ZURG_DIR/docker-compose.yml" ]]; then
  error "docker-compose.yml was not created at $ZURG_DIR/docker-compose.yml – check permissions."
fi
info "docker-compose.yml contents:"
cat "$ZURG_DIR/docker-compose.yml"

# ── rclone.conf ──────────────────────────────────────────────────────
info "Writing rclone.conf..."
cat > "$ZURG_DIR/rclone.conf" << RCLONE_CONF
[zurg]
type = webdav
url = http://zurg:9999/dav
vendor = other
pacer_min_sleep = 0
RCLONE_CONF
success "rclone.conf written."

# ── plex_update.sh ───────────────────────────────────────────────────
info "Writing plex_update.sh (Plex token will be injected after Plex setup)..."
cat > "$ZURG_DIR/plex_update.sh" << 'PLEX_UPDATE'
#!/bin/bash
# Triggered by Zurg on_library_update hook
# Sends a partial scan request to Plex for the changed path

PLEX_HOST="localhost"
PLEX_PORT="32400"
PLEX_TOKEN="PLEX_TOKEN_PLACEHOLDER"
MOUNT_POINT="/mnt/zurg"

for arg in "$@"; do
    modified_arg="${MOUNT_POINT}/${arg}"
    encoded_arg=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${modified_arg}'))")
    section_id=$(curl -s "http://${PLEX_HOST}:${PLEX_PORT}/library/sections?X-Plex-Token=${PLEX_TOKEN}" \
        | xmllint --xpath "//Directory[Location/@path='${modified_arg}']/@key" - 2>/dev/null \
        | sed 's/key="//;s/"//')

    if [[ -n "$section_id" ]]; then
        final_url="http://${PLEX_HOST}:${PLEX_PORT}/library/sections/${section_id}/refresh?path=${encoded_arg}&X-Plex-Token=${PLEX_TOKEN}"
        curl -s "$final_url" > /dev/null
        echo "All updated sections refreshed"
    fi
done
PLEX_UPDATE

chmod +x "$ZURG_DIR/plex_update.sh"
success "plex_update.sh written and made executable (token will be set after Plex setup)."

# ── Create mount point ───────────────────────────────────────────────
# Clean up any broken/stale mounts on /mnt/zurg first
info "Checking for stale mounts on /mnt/zurg..."

# Stop any existing containers that may hold the mount
$DOCKER_CMD stop zurg-testing-rclone-1 2>/dev/null || true
$DOCKER_CMD rm zurg-testing-rclone-1 2>/dev/null || true
$DOCKER_CMD stop zurg-testing-zurg-1 2>/dev/null || true
$DOCKER_CMD rm zurg-testing-zurg-1 2>/dev/null || true
sleep 2

# Unmount any stale FUSE mounts
if mountpoint -q /mnt/zurg 2>/dev/null || ls /mnt/zurg &>/dev/null; then
  warn "Stale mount or directory detected on /mnt/zurg – cleaning up..."
  fusermount -uz /mnt/zurg 2>/dev/null || true
  umount -l /mnt/zurg 2>/dev/null || true
  umount -f /mnt/zurg 2>/dev/null || true
  sleep 2
fi

# Remove and recreate the mount point cleanly
rm -rf /mnt/zurg 2>/dev/null || true
mkdir -p /mnt/zurg 2>/dev/null || {
  warn "/mnt/zurg could not be created – trying harder..."
  fusermount -uz /mnt/zurg 2>/dev/null || true
  umount -l /mnt/zurg 2>/dev/null || true
  sleep 2
  rm -rf /mnt/zurg 2>/dev/null || true
  mkdir -p /mnt/zurg || error "Cannot create /mnt/zurg – please run: sudo umount -l /mnt/zurg && sudo mkdir -p /mnt/zurg"
}

# Make /mnt a shared mount so rclone can bind-mount inside it
# /mnt must be a proper mount point first (bind mount it to itself if needed)
info "Setting /mnt as a shared mount (required for rclone)..."
if ! mountpoint -q /mnt 2>/dev/null; then
  info "/mnt is not a mount point – creating bind mount..."
  mount --bind /mnt /mnt 2>/dev/null || warn "Could not bind mount /mnt."
fi

if mount --make-shared /mnt 2>/dev/null; then
  success "/mnt set as shared mount."
else
  warn "Could not set /mnt as shared mount – trying alternative..."
  mount --make-rshared / 2>/dev/null || warn "Could not set shared mount. Rclone may fail."
fi

success "Mount point /mnt/zurg ready."

# ── Add Zurg dir to PATH ────────────────────────────────────────────
BASHRC="/root/.bashrc"
if ! grep -q "zurg-testing" "$BASHRC"; then
  echo "export PATH=\$PATH:${ZURG_DIR}" >> "$BASHRC"
  success "Added ${ZURG_DIR} to PATH in $BASHRC"
fi

# ── Start containers ─────────────────────────────────────────────────
info "Starting Zurg & Rclone containers..."
# Debug: verify file exists and show compose version
info "Verifying compose file exists..."
ls -la "$ZURG_DIR/docker-compose.yml" || error "docker-compose.yml not found at $ZURG_DIR/docker-compose.yml"
info "Docker compose version:"
$DOCKER_CMD compose version 2>/dev/null || warn "Could not get compose version"

# Try multiple methods to start containers
info "Starting containers..."
COMPOSE_OK=false
if (cd "$ZURG_DIR" && $DOCKER_CMD compose up -d) 2>&1; then
  COMPOSE_OK=true
  success "Containers started via docker compose."
elif $DOCKER_CMD compose --project-directory "$ZURG_DIR" --file "$ZURG_DIR/docker-compose.yml" up -d 2>&1; then
  COMPOSE_OK=true
  success "Containers started via docker compose with explicit paths."
fi

if [[ "$COMPOSE_OK" == "false" ]]; then
  error "All methods to start containers failed. Check the output above for details."
fi

# Wait for Zurg to become healthy (large libraries can take several minutes to index)
info "Waiting for Zurg to become healthy (large libraries can take 5-10 minutes)..."
ZURG_WAIT=0
ZURG_MAX_WAIT=600  # 10 minutes
while [[ $ZURG_WAIT -lt $ZURG_MAX_WAIT ]]; do
  ZURG_HEALTH=$($DOCKER_CMD inspect --format '{{.State.Health.Status}}' zurg-testing-zurg-1 2>/dev/null || echo "unknown")
  if [[ "$ZURG_HEALTH" == "healthy" ]]; then
    success "Zurg is healthy!"
    break
  elif [[ "$ZURG_HEALTH" == "unhealthy" ]]; then
    warn "Zurg reported unhealthy — checking logs..."
    $DOCKER_CMD logs --tail=20 zurg-testing-zurg-1 2>/dev/null || true
    warn "Zurg may still be indexing. Waiting a bit longer..."
    sleep 30
    ZURG_HEALTH2=$($DOCKER_CMD inspect --format '{{.State.Health.Status}}' zurg-testing-zurg-1 2>/dev/null || echo "unknown")
    if [[ "$ZURG_HEALTH2" == "healthy" ]]; then
      success "Zurg is now healthy!"
      break
    fi
    warn "Zurg still not healthy. Continuing anyway — it may finish indexing in the background."
    break
  fi
  echo -ne "  Zurg status: ${ZURG_HEALTH} — waited ${ZURG_WAIT}s / ${ZURG_MAX_WAIT}s\r"
  sleep 10
  ZURG_WAIT=$((ZURG_WAIT + 10))
done
if [[ $ZURG_WAIT -ge $ZURG_MAX_WAIT ]]; then
  warn "Zurg did not become healthy within ${ZURG_MAX_WAIT}s — it may still be indexing your library."
  warn "Check status with: docker logs zurg-testing-zurg-1"
  warn "Once healthy, rclone will mount automatically. Continue with the rest of the setup."
fi

info "Container status:"
$DOCKER_CMD ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || $DOCKER_CMD ps

info "Verifying container restart policies..."
ZURG_POLICY=$($DOCKER_CMD inspect --format '{{.HostConfig.RestartPolicy.Name}}' zurg-testing-zurg-1 2>/dev/null || echo "not found")
RCLONE_POLICY=$($DOCKER_CMD inspect --format '{{.HostConfig.RestartPolicy.Name}}' zurg-testing-rclone-1 2>/dev/null || echo "not found")
echo "  zurg   restart policy: ${ZURG_POLICY}"
echo "  rclone restart policy: ${RCLONE_POLICY}"

info "Verifying rclone mount..."
sleep 5
if ls /mnt/zurg/ &>/dev/null; then
  success "rclone mount is accessible."
  echo "  Contents of /mnt/zurg/:"
  ls /mnt/zurg/
else
  warn "rclone mount not yet accessible – it may take a moment. Check with: ls /mnt/zurg/"
fi

# =============================================================================
# SECTION 4 – Install Plex Media Server
# =============================================================================
section "Step 4 – Install Plex Media Server"

if systemctl is-active --quiet plexmediaserver 2>/dev/null; then
  success "Plex Media Server is already running."
else
  info "Adding Plex repository..."
  curl https://downloads.plex.tv/plex-keys/PlexSign.key \
    | gpg --dearmor \
    | tee /usr/share/keyrings/plex-archive-keyring.gpg > /dev/null

  echo "deb [signed-by=/usr/share/keyrings/plex-archive-keyring.gpg] \
https://downloads.plex.tv/repo/deb public main" \
    | tee /etc/apt/sources.list.d/plex.list

  apt-get update -y

  info "Installing libusb-dev..."
  apt-get install -y libusb-dev || warn "libusb-dev install failed – continuing."

  info "Installing Plex Media Server..."
  apt-get install -y plexmediaserver

  systemctl enable plexmediaserver
  systemctl start plexmediaserver
  success "Plex Media Server installed and started."
fi

info "Plex service status:"
systemctl status plexmediaserver.service --no-pager | head -5

# ── Inject Plex server settings into Zurg config ────────────────────
# Now that Plex is installed, add plex_server_url and plex_token to config.yml
# This enables Zurg's native Plex integration for library updates

# ── Auto-read Plex token from Preferences.xml (Ubuntu/Debian) ───────
PLEX_PREFS="/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml"

echo ""
info "Attempting to read Plex token from Preferences.xml..."

# Plex may need a moment to write the file on first start
for i in {1..6}; do
  if [[ -f "$PLEX_PREFS" ]]; then
    AUTO_TOKEN=$(grep -oP 'PlexOnlineToken="\K[^"]+' "$PLEX_PREFS" 2>/dev/null || true)
    if [[ -n "$AUTO_TOKEN" ]]; then
      PLEX_TOKEN="$AUTO_TOKEN"
      success "Plex token auto-detected from Preferences.xml"
      break
    fi
  fi
  info "Preferences.xml not ready yet, waiting 10s... (attempt $i/6)"
  sleep 10
done

# If auto-detection failed, fall back to manual entry
if [[ -z "$PLEX_TOKEN" ]]; then
  warn "Could not auto-read Plex token. This usually means Plex hasn't been signed in to yet."
  echo ""
  echo -e "  ${BOLD}To get your token manually:${NC}"
  echo -e "  1. Open Plex: ${YELLOW}${PLEX_URL}${NC} and sign in with your Plex account"
  echo -e "  2. Once signed in, the token will be written to:"
  echo -e "     ${YELLOW}${PLEX_PREFS}${NC}"
  echo -e "  3. You can then run this command to extract it:"
  echo -e "     ${YELLOW}grep -oP 'PlexOnlineToken=&quot;\\\\K[^&quot;]+' &quot;${PLEX_PREFS}&quot;${NC}"
  echo ""
  read -rp "  Enter your Plex token (or press Enter to skip for now): " PLEX_TOKEN
fi

if [[ -n "$PLEX_TOKEN" ]]; then
  # Inject token into plex_update.sh
  sed -i "s/PLEX_TOKEN_PLACEHOLDER/${PLEX_TOKEN}/" "$ZURG_DIR/plex_update.sh"
  success "Plex token injected into plex_update.sh"

  # Add Plex integration to Zurg config.yml if not already present
  if ! grep -q "plex_server_url" "$ZURG_DIR/config.yml"; then
    sed -i "/^mount_path:/a plex_server_url: http://localhost:32400\nplex_token: ${PLEX_TOKEN}" "$ZURG_DIR/config.yml"
    success "Plex server URL and token added to Zurg config.yml"
  else
    # Update existing plex_token
    sed -i "s/^plex_token:.*/plex_token: ${PLEX_TOKEN}/" "$ZURG_DIR/config.yml"
    success "Plex token updated in Zurg config.yml"
  fi

  # Restart Zurg to pick up the new Plex settings
  info "Restarting Zurg to apply Plex integration settings..."
  (cd "$ZURG_DIR" && $DOCKER_CMD compose restart zurg) 2>/dev/null || warn "Could not restart Zurg – restart manually with: cd $ZURG_DIR && docker compose restart"
else
  warn "Plex token not set. After signing in to Plex, run:"
  warn "  PLEX_TOKEN=\$(grep -oP 'PlexOnlineToken=&quot;\\\\K[^&quot;]+' &quot;${PLEX_PREFS}&quot;)"
  warn "  sed -i &quot;s/PLEX_TOKEN_PLACEHOLDER/\${PLEX_TOKEN}/&quot; ${ZURG_DIR}/plex_update.sh"
  warn "  # Also add to Zurg config:"
  warn "  echo -e &quot;plex_server_url: http://localhost:32400\nplex_token: \${PLEX_TOKEN}&quot; >> ${ZURG_DIR}/config.yml"
fi

# =============================================================================
# SECTION 5 – Python 3 & Pip
# =============================================================================
section "Step 5 – Python 3 & Pip"

if command -v python3 &>/dev/null; then
  success "Python 3 already installed: $(python3 --version)"
else
  info "Installing Python 3..."
  apt-get update -y
  apt-get install -y python3
  success "Python 3 installed: $(python3 --version)"
fi

if command -v pip3 &>/dev/null; then
  success "Pip3 already installed: $(pip3 --version)"
else
  info "Installing pip3..."
  apt-get install -y python3-pip
  success "Pip3 installed: $(pip3 --version)"
fi

# =============================================================================
# SECTION 6 – plex_debrid
# =============================================================================
section "Step 6 – plex_debrid Installation"

# Install in the real user's home directory if available, otherwise /root
if [[ -n "${REAL_USER:-}" && "$REAL_USER" != "root" ]]; then
  PLEX_DEBRID_DIR="/home/$REAL_USER/plex_debrid"
else
  PLEX_DEBRID_DIR="/root/plex_debrid"
fi

if [[ -d "$PLEX_DEBRID_DIR" ]]; then
  warn "plex_debrid directory already exists – pulling latest changes..."
  git -C "$PLEX_DEBRID_DIR" pull
else
  info "Cloning plex_debrid to $PLEX_DEBRID_DIR..."
  git clone https://github.com/itsToggle/plex_debrid "$PLEX_DEBRID_DIR"
fi

# Fix ownership if installed in user's home
if [[ -n "${REAL_USER:-}" && "$REAL_USER" != "root" ]]; then
  chown -R "$REAL_USER:$REAL_USER" "$PLEX_DEBRID_DIR"
fi

info "Installing Python requirements..."
pip3 install -r "$PLEX_DEBRID_DIR/requirements.txt" \
  --break-system-packages \
  --ignore-installed \
  2>&1 || {
    warn "Standard pip install failed, trying with --user flag..."
    pip3 install -r "$PLEX_DEBRID_DIR/requirements.txt" \
      --break-system-packages \
      --ignore-installed \
      --user \
      2>&1 || warn "pip install had errors but may still work. Continuing..."
  }
success "plex_debrid requirements installed."

# =============================================================================
# SECTION 7 – Plex Library Refresh Workaround (monitor_folders.sh)
# =============================================================================
section "Step 7 – Plex Library Refresh Workaround"

info "Verifying libxml2-utils (xmllint) is available..."
command -v xmllint &>/dev/null && success "xmllint already installed." || { apt-get install -y libxml2-utils && success "libxml2-utils installed."; }

info "Creating /root/monitor_folders.sh..."
cat > /root/monitor_folders.sh << 'MONITOR_SCRIPT'
#!/bin/bash
# monitor_folders.sh
# Watches /mnt/zurg/movies and /mnt/zurg/shows
# for any changes and triggers plex_update.sh to refresh the Plex library.

MOVIES_DIR="/mnt/zurg/movies"
SHOWS_DIR="/mnt/zurg/shows"
PLEX_UPDATE_SCRIPT="/opt/zurg-testing/plex_update.sh"
LOG_FILE="/var/log/monitor_folders.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

# Ensure inotifywait is available
if ! command -v inotifywait &>/dev/null; then
    apt-get install -y inotify-tools >> "$LOG_FILE" 2>&1
fi

log "Starting folder monitor..."
log "  Watching: $MOVIES_DIR"
log "  Watching: $SHOWS_DIR"

inotifywait -m -r -e create -e delete -e moved_to -e moved_from \
    --format '%w%f %e' \
    "$MOVIES_DIR" "$SHOWS_DIR" 2>>"$LOG_FILE" | \
while read -r changed_path event; do
    # Determine relative path for plex_update.sh
    if [[ "$changed_path" == "$MOVIES_DIR"* ]]; then
        rel_path="movies/$(basename "$changed_path")"
    else
        rel_path="shows/$(basename "$changed_path")"
    fi
    log "Change detected [$event]: $changed_path  →  triggering refresh for $rel_path"
    bash "$PLEX_UPDATE_SCRIPT" "$rel_path" >> "$LOG_FILE" 2>&1
done
MONITOR_SCRIPT

chmod +x /root/monitor_folders.sh
success "monitor_folders.sh created and made executable."

info "Verifying inotify-tools is available..."
command -v inotifywait &>/dev/null && success "inotify-tools already installed." || { apt-get install -y inotify-tools && success "inotify-tools installed."; }

# =============================================================================
# SECTION 8 – startup.sh & cron job
# =============================================================================
section "Step 8 – Startup Automation"

info "Creating /root/startup.sh..."
cat > /root/startup.sh << STARTUP_SCRIPT
#!/bin/bash
# startup.sh
# Launched at boot via cron (@reboot).
# Starts plex_debrid and the folder monitor in named screen sessions.

LOG="/var/log/startup_plex_debrid.log"
echo "[\$(date)] startup.sh triggered" >> "\$LOG"

# Give Docker containers time to fully start
sleep 15

# Ensure /mnt is a shared mount (required after reboot)
if ! mountpoint -q /mnt 2>/dev/null; then
  mount --bind /mnt /mnt 2>/dev/null || true
fi
mount --make-shared /mnt 2>/dev/null || true

# ── Start plex_debrid in a screen named 'pd' ────────────────────────
if screen -list | grep -q "\\.pd"; then
    echo "[\$(date)] Screen 'pd' already running – skipping." >> "\$LOG"
else
    echo "[\$(date)] Starting plex_debrid in screen 'pd'..." >> "\$LOG"
    screen -dmS pd bash -c "cd ${PLEX_DEBRID_DIR} && python3 main.py >> \$LOG 2>&1"
fi

# ── Start folder monitor in a screen named 'monitor' ────────────────
if screen -list | grep -q "\\.monitor"; then
    echo "[\$(date)] Screen 'monitor' already running – skipping." >> "\$LOG"
else
    echo "[\$(date)] Starting monitor_folders.sh in screen 'monitor'..." >> "\$LOG"
    screen -dmS monitor bash -c "/root/monitor_folders.sh >> \$LOG 2>&1"
fi

echo "[\$(date)] startup.sh complete." >> "\$LOG"
STARTUP_SCRIPT

chmod +x /root/startup.sh
success "startup.sh created and made executable."

# ── Add /root to PATH ───────────────────────────────────────────────
if ! grep -q 'PATH=.*:/root' "$BASHRC" 2>/dev/null; then
  echo 'export PATH=$PATH:/root' >> "$BASHRC"
  success "Added /root to PATH in $BASHRC"
fi

info "Verifying screen is available..."
command -v screen &>/dev/null && success "screen already installed." || { apt-get install -y screen && success "screen installed."; }

# ── Register cron job ────────────────────────────────────────────────
info "Registering @reboot cron job..."
CRON_LINE="@reboot sleep 10 && /root/startup.sh"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
FILTERED_CRON=$(echo "$EXISTING_CRON" | grep -v "startup.sh" || true)
printf '%s\n%s\n' "$FILTERED_CRON" "$CRON_LINE" | grep -v '^$' | crontab - || true
success "Cron job registered: $CRON_LINE"

# =============================================================================
# SECTION 9 – SSH Port-Forwarding helper (remote servers only)
# =============================================================================
if [[ "$IS_REMOTE" == "y" || "$IS_REMOTE" == "yes" ]]; then
  section "Step 9 – SSH Port-Forwarding Helper"

  SERVER_IP=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")
  info "Detected server IP: $SERVER_IP"

  info "Creating connect.bat (Windows batch file)..."
  cat > /root/connect.bat << BAT_FILE
@echo off
REM SSH Port-Forwarding for Plex + Real-Debrid setup
REM Run this on your LOCAL Windows machine to access remote services
REM
REM  localhost:8888  ->  remote:32400  (Plex)
REM  localhost:8889  ->  remote:9999   (Zurg)
REM  localhost:8890  ->  remote:5055   (Overseerr - optional)
REM  localhost:8891  ->  remote:9117   (Jackett   - optional)

ssh -L 8888:localhost:32400 ^
    -L 8889:localhost:9999  ^
    -L 8890:localhost:5055  ^
    -L 8891:localhost:9117  ^
    root@${SERVER_IP}
BAT_FILE
  success "connect.bat created at /root/connect.bat"

  info "Creating connect.sh (Linux/Mac shell script)..."
  cat > /root/connect.sh << SH_FILE
#!/bin/bash
# SSH Port-Forwarding for Plex + Real-Debrid setup
# Run this on your LOCAL machine to access remote services
#
#  localhost:8888  ->  remote:32400  (Plex)
#  localhost:8889  ->  remote:9999   (Zurg)
#  localhost:8890  ->  remote:5055   (Overseerr - optional)
#  localhost:8891  ->  remote:9117   (Jackett   - optional)

ssh -L 8888:localhost:32400 \
    -L 8889:localhost:9999  \
    -L 8890:localhost:5055  \
    -L 8891:localhost:9117  \
    root@${SERVER_IP}
SH_FILE
  chmod +x /root/connect.sh
  success "connect.sh created at /root/connect.sh"
fi

# =============================================================================
# SECTION 10 – VPN check
# =============================================================================
section "Step 10 – Real-Debrid VPN / IP Check"

info "Checking if your server IP is blocked by Real-Debrid..."
IPV4_RESULT=$(curl -s -4 https://real-debrid.com/vpn 2>/dev/null | grep -i "blocked" || echo "Could not check IPv4")
IPV6_RESULT=$(curl -s -6 https://real-debrid.com/vpn 2>/dev/null | grep -i "blocked" || echo "Could not check IPv6")

echo "  IPv4 check: $IPV4_RESULT"
echo "  IPv6 check: $IPV6_RESULT"

if echo "$IPV4_RESULT $IPV6_RESULT" | grep -qi "not blocked"; then
  success "Your IP is NOT blocked by Real-Debrid. No VPN needed."
elif echo "$IPV4_RESULT $IPV6_RESULT" | grep -qi "blocked"; then
  warn "Your IP appears to be BLOCKED by Real-Debrid."
  warn "You will need to set up a whitelisted VPN."
  warn "See: https://real-debrid.com/vpn for the list of supported VPNs."
else
  warn "Could not determine block status. Check manually: https://real-debrid.com/vpn"
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
section "Setup Complete!"

echo -e "${GREEN}${BOLD}All steps completed successfully!${NC}\n"
echo -e "${BOLD}Next steps (manual):${NC}"
echo ""
echo -e "  ${CYAN}1. Set up Plex:${NC}"
echo -e "     Open ${YELLOW}${PLEX_URL}${NC} in your browser"
echo -e "     - Add Movie library  → /mnt/zurg/movies"
echo -e "     - Add TV Show library → /mnt/zurg/shows"
echo -e "     - Disable 'Enable video preview thumbnails'"
echo -e "     - Enable 'Scan my Library Automatically'"
echo -e "     - Enable 'Run a partial scan when changes are detected'"
echo -e "     - Disable 'Perform extensive media analysis' (Scheduled Tasks)"
echo ""
echo -e "  ${CYAN}1b. If the Plex token was not auto-detected (not signed in yet):${NC}"
echo -e "     Sign in to Plex, then run:"
echo -e "     ${YELLOW}PLEX_TOKEN=\$(grep -oP 'PlexOnlineToken=&quot;\\\\K[^&quot;]+' &quot;/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Preferences.xml&quot;)${NC}"
echo -e "     ${YELLOW}sed -i &quot;s/PLEX_TOKEN_PLACEHOLDER/\${PLEX_TOKEN}/&quot; ${ZURG_DIR}/plex_update.sh${NC}"
echo -e "     ${YELLOW}sed -i &quot;s/^plex_token:.*/plex_token: \${PLEX_TOKEN}/&quot; ${ZURG_DIR}/config.yml${NC}"
echo -e "     ${YELLOW}cd ${ZURG_DIR} && docker compose restart${NC}"
echo ""
echo -e "  ${CYAN}2. Verify Zurg:${NC}"
echo -e "     Open ${YELLOW}${ZURG_URL}${NC} → click the HTTP folder"
echo -e "     You should see 'movies' and 'shows' directories"
echo ""
echo -e "  ${CYAN}3. First-time plex_debrid setup:${NC}"
echo -e "     ${YELLOW}screen -S pd${NC}"
echo -e "     ${YELLOW}cd ${PLEX_DEBRID_DIR} && python3 main.py${NC}"
echo -e "     - Follow the setup wizard"
echo -e "     - Plex server address: ${YELLOW}http://localhost:32400/${NC}"
echo -e "     - After setup: Settings > UI Settings > Show Menu at Startup → false"
echo -e "     - Detach screen: ${YELLOW}Ctrl+A, D${NC}"
echo ""
echo -e "  ${CYAN}4. Launch startup script (starts all screens):${NC}"
echo -e "     ${YELLOW}/root/startup.sh${NC}"
echo ""
echo -e "  ${CYAN}5. Verify everything after reboot:${NC}"
echo -e "     ${YELLOW}docker ps${NC}                              # Zurg + Rclone containers"
echo -e "     ${YELLOW}systemctl status plexmediaserver${NC}       # Plex"
echo -e "     ${YELLOW}ls /mnt/zurg/${NC}                          # rclone mount"
echo -e "     ${YELLOW}ls /mnt/zurg/movies/${NC}                   # movies folder"
echo -e "     ${YELLOW}ls /mnt/zurg/shows/${NC}                    # shows folder"
echo -e "     ${YELLOW}screen -d -r pd${NC}                        # plex_debrid screen"
echo -e "     ${YELLOW}screen -d -r monitor${NC}                   # folder monitor screen"
echo ""
echo -e "  ${CYAN}6. Useful screen commands:${NC}"
echo -e "     ${YELLOW}screen -ls${NC}                             # list all screens"
echo -e "     ${YELLOW}screen -S <name>${NC}                       # create new screen"
echo -e "     ${YELLOW}screen -d -r <name>${NC}                    # attach to screen"
echo -e "     ${YELLOW}Ctrl+A, D${NC}                              # detach from screen"
echo ""
if [[ "$IS_REMOTE" == "y" || "$IS_REMOTE" == "yes" ]]; then
  echo -e "  ${CYAN}7. Connect from your local machine:${NC}"
  echo -e "     Windows: copy ${YELLOW}/root/connect.bat${NC} to your PC and run it"
  echo -e "     Linux/Mac: copy ${YELLOW}/root/connect.sh${NC} to your machine and run it"
  echo ""
fi
echo -e "${BOLD}${GREEN}Enjoy your Plex + Real-Debrid setup!${NC}\n"