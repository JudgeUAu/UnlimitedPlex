#!/bin/bash
# =============================================================================
#  Auto-Configure *arr Stack
#  Configures Radarr, Sonarr, Prowlarr, and Blackhole via API
#  Run AFTER setup_arr_stack.sh has deployed all containers
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────
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

# ── Root check ───────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  error "Please run this script as root:  sudo ./configure_arrs.sh"
fi

# =============================================================================
# Helper functions
# =============================================================================

wait_for_api() {
  local name="$1" url="$2" max_wait="${3:-120}"
  local elapsed=0
  info "Waiting for $name API to be ready..."
  while [[ $elapsed -lt $max_wait ]]; do
    if curl -sf "$url" &>/dev/null; then
      success "$name API is ready."
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  warn "$name API not ready after ${max_wait}s. Skipping auto-configuration for $name."
  return 1
}

get_api_key() {
  local config_file="$1"
  if [[ -f "$config_file" ]]; then
    grep -oP '<ApiKey>\K[^<]+' "$config_file" 2>/dev/null || echo ""
  else
    echo ""
  fi
}

api_post() {
  local url="$1" api_key="$2" data="$3"
  curl -sf -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $api_key" \
    -d "$data" 2>/dev/null
}

api_get() {
  local url="$1" api_key="$2"
  curl -sf "$url" \
    -H "X-Api-Key: $api_key" 2>/dev/null
}

# Check if download client already exists
has_download_client() {
  local url="$1" api_key="$2" name="$3"
  local result
  result=$(api_get "$url/api/v3/downloadclient" "$api_key")
  echo "$result" | grep -q "&quot;name&quot;:&quot;$name&quot;" 2>/dev/null
}

# Check if root folder already exists
has_root_folder() {
  local url="$1" api_key="$2" path="$3"
  local result
  result=$(api_get "$url/api/v3/rootfolder" "$api_key")
  echo "$result" | grep -q "$(echo "$path" | sed 's/\//\\\//g')" 2>/dev/null
}

# =============================================================================
# SECTION 1 – Wait for all services and extract API keys
# =============================================================================
section "Step 1 – Extracting API Keys"

# Ensure containers are running
info "Checking container status..."
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "(prowlarr|radarr|sonarr|overseerr)" || true

# Wait for each service to generate its config
sleep 10

# Extract API keys from config.xml files
RADARR_KEY=$(get_api_key "/opt/radarr/config.xml")
RADARR4K_KEY=$(get_api_key "/opt/radarr4k/config.xml")
SONARR_KEY=$(get_api_key "/opt/sonarr/config.xml")
SONARR4K_KEY=$(get_api_key "/opt/sonarr4k/config.xml")
PROWLARR_KEY=$(get_api_key "/opt/prowlarr/config.xml")
OVERSEERR_KEY=""  # Overseerr needs manual Plex login first

# Verify we got keys
[[ -n "$RADARR_KEY" ]]   && success "Radarr API key:    ${RADARR_KEY:0:8}..." || warn "Radarr API key not found yet"
[[ -n "$RADARR4K_KEY" ]] && success "Radarr 4K API key: ${RADARR4K_KEY:0:8}..." || warn "Radarr 4K API key not found yet"
[[ -n "$SONARR_KEY" ]]   && success "Sonarr API key:    ${SONARR_KEY:0:8}..." || warn "Sonarr API key not found yet"
[[ -n "$SONARR4K_KEY" ]] && success "Sonarr 4K API key: ${SONARR4K_KEY:0:8}..." || warn "Sonarr 4K API key not found yet"
[[ -n "$PROWLARR_KEY" ]] && success "Prowlarr API key:  ${PROWLARR_KEY:0:8}..." || warn "Prowlarr API key not found yet"

# =============================================================================
# SECTION 2 – Configure Radarr
# =============================================================================
section "Step 2 – Configure Radarr"

RADARR_URL="http://localhost:7878"

if [[ -n "$RADARR_KEY" ]] && wait_for_api "Radarr" "$RADARR_URL/api/v3/system/status?apikey=$RADARR_KEY" 60; then

  # 2a. Add root folder
  if ! has_root_folder "$RADARR_URL" "$RADARR_KEY" "/mnt/plex/Movies"; then
    info "Adding root folder /mnt/plex/Movies..."
    api_post "$RADARR_URL/api/v3/rootfolder" "$RADARR_KEY" \
      '{"path":"/mnt/plex/Movies"}' && success "Root folder added." || warn "Failed to add root folder."
  else
    success "Root folder /mnt/plex/Movies already exists."
  fi

  # 2b. Add Torrent Blackhole download client
  if ! has_download_client "$RADARR_URL" "$RADARR_KEY" "Blackhole"; then
    info "Adding Torrent Blackhole download client..."
    api_post "$RADARR_URL/api/v3/downloadclient" "$RADARR_KEY" '{
      "enable": true,
      "protocol": "torrent",
      "priority": 1,
      "removeCompletedDownloads": true,
      "removeFailedDownloads": true,
      "name": "Blackhole",
      "fields": [
        {"name": "torrentFolder", "value": "/mnt/symlinks/radarr"},
        {"name": "watchFolder", "value": "/mnt/symlinks/radarr/completed"},
        {"name": "saveMagnetFiles", "value": true},
        {"name": "magnetFileExtension", "value": ".magnet"},
        {"name": "readOnly", "value": false}
      ],
      "implementationName": "Torrent Blackhole",
      "implementation": "TorrentBlackhole",
      "configContract": "TorrentBlackholeSettings"
    }' && success "Blackhole download client added to Radarr." || warn "Failed to add download client."
  else
    success "Blackhole download client already exists in Radarr."
  fi

  # 2c. Disable authentication requirement for local access (Forms auth with no password = no auth needed)
  info "Setting Radarr authentication to Forms (local bypass)..."
  api_post "$RADARR_URL/api/v3/config/host" "$RADARR_KEY" '{
    "authenticationMethod": "forms",
    "authenticationRequired": "disabledForLocalAddresses"
  }' &>/dev/null && success "Radarr auth configured." || warn "Could not set Radarr auth."

else
  warn "Skipping Radarr configuration."
fi

# =============================================================================
# SECTION 3 – Configure Radarr 4K
# =============================================================================
section "Step 3 – Configure Radarr 4K"

RADARR4K_URL="http://localhost:7879"

if [[ -n "$RADARR4K_KEY" ]] && wait_for_api "Radarr 4K" "$RADARR4K_URL/api/v3/system/status?apikey=$RADARR4K_KEY" 60; then

  if ! has_root_folder "$RADARR4K_URL" "$RADARR4K_KEY" "/mnt/plex/Movies - 4K"; then
    info "Adding root folder /mnt/plex/Movies - 4K..."
    api_post "$RADARR4K_URL/api/v3/rootfolder" "$RADARR4K_KEY" \
      '{"path":"/mnt/plex/Movies - 4K"}' && success "Root folder added." || warn "Failed to add root folder."
  else
    success "Root folder already exists."
  fi

  if ! has_download_client "$RADARR4K_URL" "$RADARR4K_KEY" "Blackhole"; then
    info "Adding Torrent Blackhole download client..."
    api_post "$RADARR4K_URL/api/v3/downloadclient" "$RADARR4K_KEY" '{
      "enable": true,
      "protocol": "torrent",
      "priority": 1,
      "removeCompletedDownloads": true,
      "removeFailedDownloads": true,
      "name": "Blackhole",
      "fields": [
        {"name": "torrentFolder", "value": "/mnt/symlinks/radarr4k"},
        {"name": "watchFolder", "value": "/mnt/symlinks/radarr4k/completed"},
        {"name": "saveMagnetFiles", "value": true},
        {"name": "magnetFileExtension", "value": ".magnet"},
        {"name": "readOnly", "value": false}
      ],
      "implementationName": "Torrent Blackhole",
      "implementation": "TorrentBlackhole",
      "configContract": "TorrentBlackholeSettings"
    }' && success "Blackhole download client added to Radarr 4K." || warn "Failed to add download client."
  else
    success "Blackhole download client already exists in Radarr 4K."
  fi

else
  warn "Skipping Radarr 4K configuration."
fi

# =============================================================================
# SECTION 4 – Configure Sonarr
# =============================================================================
section "Step 4 – Configure Sonarr"

SONARR_URL="http://localhost:8989"

if [[ -n "$SONARR_KEY" ]] && wait_for_api "Sonarr" "$SONARR_URL/api/v3/system/status?apikey=$SONARR_KEY" 60; then

  if ! has_root_folder "$SONARR_URL" "$SONARR_KEY" "/mnt/plex/TV"; then
    info "Adding root folder /mnt/plex/TV..."
    api_post "$SONARR_URL/api/v3/rootfolder" "$SONARR_KEY" \
      '{"path":"/mnt/plex/TV"}' && success "Root folder added." || warn "Failed to add root folder."
  else
    success "Root folder already exists."
  fi

  if ! has_download_client "$SONARR_URL" "$SONARR_KEY" "Blackhole"; then
    info "Adding Torrent Blackhole download client..."
    api_post "$SONARR_URL/api/v3/downloadclient" "$SONARR_KEY" '{
      "enable": true,
      "protocol": "torrent",
      "priority": 1,
      "removeCompletedDownloads": true,
      "removeFailedDownloads": true,
      "name": "Blackhole",
      "fields": [
        {"name": "torrentFolder", "value": "/mnt/symlinks/sonarr"},
        {"name": "watchFolder", "value": "/mnt/symlinks/sonarr/completed"},
        {"name": "saveMagnetFiles", "value": true},
        {"name": "magnetFileExtension", "value": ".magnet"},
        {"name": "readOnly", "value": false}
      ],
      "implementationName": "Torrent Blackhole",
      "implementation": "TorrentBlackhole",
      "configContract": "TorrentBlackholeSettings"
    }' && success "Blackhole download client added to Sonarr." || warn "Failed to add download client."
  else
    success "Blackhole download client already exists in Sonarr."
  fi

else
  warn "Skipping Sonarr configuration."
fi

# =============================================================================
# SECTION 5 – Configure Sonarr 4K
# =============================================================================
section "Step 5 – Configure Sonarr 4K"

SONARR4K_URL="http://localhost:8990"

if [[ -n "$SONARR4K_KEY" ]] && wait_for_api "Sonarr 4K" "$SONARR4K_URL/api/v3/system/status?apikey=$SONARR4K_KEY" 60; then

  if ! has_root_folder "$SONARR4K_URL" "$SONARR4K_KEY" "/mnt/plex/TV - 4K"; then
    info "Adding root folder /mnt/plex/TV - 4K..."
    api_post "$SONARR4K_URL/api/v3/rootfolder" "$SONARR4K_KEY" \
      '{"path":"/mnt/plex/TV - 4K"}' && success "Root folder added." || warn "Failed to add root folder."
  else
    success "Root folder already exists."
  fi

  if ! has_download_client "$SONARR4K_URL" "$SONARR4K_KEY" "Blackhole"; then
    info "Adding Torrent Blackhole download client..."
    api_post "$SONARR4K_URL/api/v3/downloadclient" "$SONARR4K_KEY" '{
      "enable": true,
      "protocol": "torrent",
      "priority": 1,
      "removeCompletedDownloads": true,
      "removeFailedDownloads": true,
      "name": "Blackhole",
      "fields": [
        {"name": "torrentFolder", "value": "/mnt/symlinks/sonarr4k"},
        {"name": "watchFolder", "value": "/mnt/symlinks/sonarr4k/completed"},
        {"name": "saveMagnetFiles", "value": true},
        {"name": "magnetFileExtension", "value": ".magnet"},
        {"name": "readOnly", "value": false}
      ],
      "implementationName": "Torrent Blackhole",
      "implementation": "TorrentBlackhole",
      "configContract": "TorrentBlackholeSettings"
    }' && success "Blackhole download client added to Sonarr 4K." || warn "Failed to add download client."
  else
    success "Blackhole download client already exists in Sonarr 4K."
  fi

else
  warn "Skipping Sonarr 4K configuration."
fi

# =============================================================================
# SECTION 6 – Configure Prowlarr (connect to all *arrs)
# =============================================================================
section "Step 6 – Configure Prowlarr"

PROWLARR_URL="http://localhost:9696"

if [[ -n "$PROWLARR_KEY" ]] && wait_for_api "Prowlarr" "$PROWLARR_URL/api/v1/system/status?apikey=$PROWLARR_KEY" 60; then

  # Helper to add an app to Prowlarr
  add_prowlarr_app() {
    local app_name="$1" impl="$2" server_url="$3" api_key="$4" sync_categories="$5"

    # Check if already exists
    local existing
    existing=$(api_get "$PROWLARR_URL/api/v1/applications" "$PROWLARR_KEY")
    if echo "$existing" | grep -q "&quot;name&quot;:&quot;$app_name&quot;" 2>/dev/null; then
      success "$app_name already connected to Prowlarr."
      return 0
    fi

    info "Connecting $app_name to Prowlarr..."
    api_post "$PROWLARR_URL/api/v1/applications" "$PROWLARR_KEY" "{
      &quot;name&quot;: &quot;$app_name&quot;,
      &quot;syncLevel&quot;: &quot;fullSync&quot;,
      &quot;implementation&quot;: &quot;$impl&quot;,
      &quot;configContract&quot;: &quot;${impl}Settings&quot;,
      &quot;fields&quot;: [
        {&quot;name&quot;: &quot;prowlarrUrl&quot;, &quot;value&quot;: &quot;http://prowlarr:9696&quot;},
        {&quot;name&quot;: &quot;baseUrl&quot;, &quot;value&quot;: &quot;$server_url&quot;},
        {&quot;name&quot;: &quot;apiKey&quot;, &quot;value&quot;: &quot;$api_key&quot;},
        {&quot;name&quot;: &quot;syncCategories&quot;, &quot;value&quot;: [$sync_categories]}
      ]
    }" && success "$app_name connected to Prowlarr." || warn "Failed to connect $app_name."
  }

  # Radarr categories: 2000 (Movies), 2010, 2020, 2030, 2040, 2045, 2050, 2060, 2070, 2080
  # Sonarr categories: 5000 (TV), 5010, 5020, 5030, 5040, 5045, 5050, 5060, 5070, 5080

  [[ -n "$RADARR_KEY" ]]   && add_prowlarr_app "Radarr"    "Radarr" "http://radarr:7878"    "$RADARR_KEY"   "2000,2010,2020,2030,2040,2045,2050,2060,2070,2080"
  [[ -n "$RADARR4K_KEY" ]] && add_prowlarr_app "Radarr 4K" "Radarr" "http://radarr4k:7878"  "$RADARR4K_KEY" "2000,2010,2020,2030,2040,2045,2050,2060,2070,2080"
  [[ -n "$SONARR_KEY" ]]   && add_prowlarr_app "Sonarr"    "Sonarr" "http://sonarr:8989"    "$SONARR_KEY"   "5000,5010,5020,5030,5040,5045,5050,5060,5070,5080"
  [[ -n "$SONARR4K_KEY" ]] && add_prowlarr_app "Sonarr 4K" "Sonarr" "http://sonarr4k:8989"  "$SONARR4K_KEY" "5000,5010,5020,5030,5040,5045,5050,5060,5070,5080"

  # Add Torrentio indexer if not already present
  info "Checking for Torrentio indexer..."
  EXISTING_INDEXERS=$(api_get "$PROWLARR_URL/api/v1/indexer" "$PROWLARR_KEY")
  if echo "$EXISTING_INDEXERS" | grep -qi "torrentio" 2>/dev/null; then
    success "Torrentio indexer already configured."
  else
    info "Adding Torrentio indexer..."
    # Get the indexer schema for Torrentio (custom definition)
    api_post "$PROWLARR_URL/api/v1/indexer" "$PROWLARR_KEY" '{
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
    }' && success "Torrentio indexer added." || warn "Could not add Torrentio indexer automatically. You may need to add it manually in Prowlarr → Indexers."
  fi

else
  warn "Skipping Prowlarr configuration."
fi

# =============================================================================
# SECTION 7 – Update Blackhole .env with real API keys
# =============================================================================
section "Step 7 – Update Blackhole .env"

BLACKHOLE_ENV="/opt/blackhole/.env"

if [[ -f "$BLACKHOLE_ENV" ]]; then
  info "Injecting API keys into Blackhole .env..."

  [[ -n "$RADARR_KEY" ]]   && sed -i "s/REPLACE_WITH_RADARR_API_KEY/$RADARR_KEY/"     "$BLACKHOLE_ENV" && success "Radarr key injected."
  [[ -n "$RADARR4K_KEY" ]] && sed -i "s/REPLACE_WITH_RADARR4K_API_KEY/$RADARR4K_KEY/" "$BLACKHOLE_ENV" && success "Radarr 4K key injected."
  [[ -n "$SONARR_KEY" ]]   && sed -i "s/REPLACE_WITH_SONARR_API_KEY/$SONARR_KEY/"     "$BLACKHOLE_ENV" && success "Sonarr key injected."
  [[ -n "$SONARR4K_KEY" ]] && sed -i "s/REPLACE_WITH_SONARR4K_API_KEY/$SONARR4K_KEY/" "$BLACKHOLE_ENV" && success "Sonarr 4K key injected."

  # Restart Blackhole to pick up new keys
  info "Restarting Blackhole..."
  (cd /opt/blackhole && docker compose --profile blackhole up -d) 2>&1
  success "Blackhole restarted with real API keys."
else
  warn "Blackhole .env not found at $BLACKHOLE_ENV"
fi

# =============================================================================
# FINAL SUMMARY
# =============================================================================
section "Auto-Configuration Complete!"

echo -e "${GREEN}${BOLD}The following was configured automatically:${NC}\n"

echo -e "  ${CYAN}Radarr (http://localhost:7878):${NC}"
echo -e "    ✅ Root folder: /mnt/plex/Movies"
echo -e "    ✅ Download client: Torrent Blackhole (Save Magnet: Yes)"
echo ""
echo -e "  ${CYAN}Radarr 4K (http://localhost:7879):${NC}"
echo -e "    ✅ Root folder: /mnt/plex/Movies - 4K"
echo -e "    ✅ Download client: Torrent Blackhole (Save Magnet: Yes)"
echo ""
echo -e "  ${CYAN}Sonarr (http://localhost:8989):${NC}"
echo -e "    ✅ Root folder: /mnt/plex/TV"
echo -e "    ✅ Download client: Torrent Blackhole (Save Magnet: Yes)"
echo ""
echo -e "  ${CYAN}Sonarr 4K (http://localhost:8990):${NC}"
echo -e "    ✅ Root folder: /mnt/plex/TV - 4K"
echo -e "    ✅ Download client: Torrent Blackhole (Save Magnet: Yes)"
echo ""
echo -e "  ${CYAN}Prowlarr (http://localhost:9696):${NC}"
echo -e "    ✅ Connected to: Radarr, Radarr 4K, Sonarr, Sonarr 4K"
echo -e "    ✅ Torrentio indexer added"
echo ""
echo -e "  ${CYAN}Blackhole:${NC}"
echo -e "    ✅ API keys injected into .env"
echo ""

echo -e "${BOLD}API Keys (save these):${NC}"
echo ""
echo -e "  Radarr:     ${YELLOW}${RADARR_KEY:-NOT FOUND}${NC}"
echo -e "  Radarr 4K:  ${YELLOW}${RADARR4K_KEY:-NOT FOUND}${NC}"
echo -e "  Sonarr:     ${YELLOW}${SONARR_KEY:-NOT FOUND}${NC}"
echo -e "  Sonarr 4K:  ${YELLOW}${SONARR4K_KEY:-NOT FOUND}${NC}"
echo -e "  Prowlarr:   ${YELLOW}${PROWLARR_KEY:-NOT FOUND}${NC}"
echo ""

echo -e "${BOLD}Still requires manual setup:${NC}"
echo ""
echo -e "  ${YELLOW}1. Overseerr (http://localhost:5055):${NC}"
echo -e "     - Sign in with Plex account"
echo -e "     - Add Radarr server (hostname: radarr, port: 7878, key: $RADARR_KEY)"
echo -e "     - Add Sonarr server (hostname: sonarr, port: 8989, key: $SONARR_KEY)"
echo ""
echo -e "  ${YELLOW}2. Plex Libraries:${NC}"
echo -e "     - Movies  → /mnt/plex/Movies"
echo -e "     - TV      → /mnt/plex/TV"
echo -e "     - Remove old /mnt/zurg/ libraries"
echo ""
echo -e "  ${YELLOW}3. Prowlarr Torrentio (if auto-add failed):${NC}"
echo -e "     - Indexers → Add → Search 'Torrentio' → Configure"
echo ""
echo -e "${BOLD}${GREEN}Your *arr stack is ready to use!${NC}\n"