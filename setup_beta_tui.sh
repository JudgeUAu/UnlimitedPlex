#!/bin/bash
# =============================================================================
#  UnlimitedPlex Beta - Linux Terminal UI (TUI)
#  Interactive service selector and instance builder
# =============================================================================

set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Please run as root: sudo bash setup_beta_tui.sh"
  exit 1
fi

# ── Install whiptail if missing ───────────────────────────────────────────────
if ! command -v whiptail &>/dev/null; then
  echo -e "${CYAN}[INFO]${NC} Installing whiptail..."
  apt-get update -qq && apt-get install -y -qq whiptail
fi

# ── Config storage ────────────────────────────────────────────────────────────
CONFIG_FILE="/tmp/unlimitedplex_config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Terminal size ─────────────────────────────────────────────────────────────
TERM_H=$(tput lines 2>/dev/null || echo 40)
TERM_W=$(tput cols  2>/dev/null || echo 80)
DLG_H=$((TERM_H - 4))
DLG_W=$((TERM_W - 8))
[[ $DLG_H -lt 20 ]] && DLG_H=20
[[ $DLG_W -lt 60 ]] && DLG_W=60
[[ $DLG_H -gt 40 ]] && DLG_H=40
[[ $DLG_W -gt 100 ]] && DLG_W=100

# =============================================================================
# WELCOME SCREEN
# =============================================================================
whiptail --title "UnlimitedPlex Beta Installer" \
  --msgbox "\
Welcome to UnlimitedPlex Beta!

This installer lets you:
  * Choose exactly which services to install
  * Create multiple instances (e.g. Main, 4K, Kids)
  * Each instance gets its own set of services

Plex Media Server is always installed.

Press OK to begin." \
  $DLG_H $DLG_W

# =============================================================================
# STEP 1 - CREDENTIALS
# =============================================================================
RD_TOKEN=$(whiptail --title "Real-Debrid API Token" \
  --inputbox "\
Enter your Real-Debrid API token.

Get it from: https://real-debrid.com/apitoken" \
  12 $DLG_W "" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }

if [[ -z "$RD_TOKEN" ]]; then
  whiptail --title "Error" --msgbox "Real-Debrid token is required." 8 40
  exit 1
fi

PLEX_TOKEN=$(whiptail --title "Plex Claim Token" \
  --inputbox "\
Enter your Plex claim token.

Get it from: https://www.plex.tv/claim
(Token expires in 4 minutes - get it just before clicking OK)" \
  12 $DLG_W "" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }

if [[ -z "$PLEX_TOKEN" ]]; then
  whiptail --title "Error" --msgbox "Plex token is required." 8 40
  exit 1
fi

# =============================================================================
# STEP 2 - TIMEZONE
# =============================================================================
TIMEZONE=$(whiptail --title "Timezone" \
  --inputbox "\
Enter your timezone (TZ database format).

Examples:
  America/New_York
  America/Los_Angeles
  Europe/London
  Australia/Sydney" \
  14 $DLG_W "America/New_York" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }

[[ -z "$TIMEZONE" ]] && TIMEZONE="America/New_York"

# =============================================================================
# STEP 3 - ZURG VERSION
# =============================================================================
ZURG_VERSION=$(whiptail --title "Zurg Version" \
  --inputbox "\
Enter the Zurg version to install.

Latest stable: v0.9.3-final
Leave default unless you need a specific version." \
  10 $DLG_W "v0.9.3-final" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }

[[ -z "$ZURG_VERSION" ]] && ZURG_VERSION="v0.9.3-final"

# =============================================================================
# STEP 4 - GLOBAL SERVICES
# =============================================================================
GLOBAL_RESULT=$(whiptail --title "Global Services" \
  --checklist "\
Select global services (installed once, shared across all instances):" \
  $DLG_H $DLG_W 4 \
  "tautulli" "Tautulli - Plex analytics & monitoring" ON \
  "nzbdav"   "NZBDav   - Usenet streaming via WebDAV" OFF \
  3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }

# Parse global services
GLOBAL_SERVICES=()
for svc in $GLOBAL_RESULT; do
  svc=$(echo "$svc" | tr -d '"')
  GLOBAL_SERVICES+=("$svc")
done

# If NZBDav selected, get password
NZBDAV_PASSWORD="changeme"
if [[ " ${GLOBAL_SERVICES[*]} " =~ " nzbdav " ]]; then
  NZBDAV_PASSWORD=$(whiptail --title "NZBDav Password" \
    --passwordbox "\
Enter a password for NZBDav WebDAV access:" \
    8 $DLG_W "changeme" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }
  [[ -z "$NZBDAV_PASSWORD" ]] && NZBDAV_PASSWORD="changeme"
fi

# =============================================================================
# STEP 5 - INSTANCE BUILDER
# =============================================================================
INSTANCES=()

add_instance() {
  # Get instance label
  local LABEL
  LABEL=$(whiptail --title "Instance Name" \
    --inputbox "\
Enter a name for this instance.

Examples: Main, 4K, Kids, Anime, Documentary
(Use short names, no spaces)" \
    10 $DLG_W "" 3>&1 1>&2 2>&3) || return 1

  [[ -z "$LABEL" ]] && return 1

  # Sanitize name (lowercase, no spaces)
  local NAME
  NAME=$(echo "$LABEL" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/_*$//')

  # Select services for this instance
  local SVCS
  SVCS=$(whiptail --title "Services for: $LABEL" \
    --checklist "\
Select services to install for the '$LABEL' instance:

Note: Zurg is required for Real-Debrid streaming.
Decypharr is required for Radarr/Sonarr to work with Real-Debrid." \
    $DLG_H $DLG_W 8 \
    "zurg"      "Zurg       - Real-Debrid mount (required for RD)"  ON  \
    "radarr"    "Radarr     - Movie management"                      ON  \
    "sonarr"    "Sonarr     - TV show management"                    ON  \
    "prowlarr"  "Prowlarr   - Indexer manager"                       ON  \
    "decypharr" "Decypharr  - qBittorrent mock for Real-Debrid"      ON  \
    "pulsarr"   "Pulsarr    - Plex watchlist sync"                   OFF \
    3>&1 1>&2 2>&3) || return 1

  # Parse selected services
  local SVC_LIST=""
  for svc in $SVCS; do
    svc=$(echo "$svc" | tr -d '"')
    [[ -n "$SVC_LIST" ]] && SVC_LIST="${SVC_LIST},"
    SVC_LIST="${SVC_LIST}${svc}"
  done

  if [[ -z "$SVC_LIST" ]]; then
    whiptail --title "Warning" --msgbox "No services selected for '$LABEL'. Instance will be skipped." 8 50
    return 1
  fi

  INSTANCES+=("${NAME}|${LABEL}|${SVC_LIST}")
  return 0
}

# Add first instance
whiptail --title "Instance Builder" \
  --msgbox "\
Now you'll set up your instances.

An instance is a separate set of services.
For example:
  - 'Main'  for regular movies/TV
  - '4K'    for 4K content
  - 'Kids'  for children's content

You'll be asked to add instances one at a time.
Press OK to add your first instance." \
  $DLG_H $DLG_W

add_instance || { whiptail --title "Error" --msgbox "At least one instance is required." 8 40; exit 1; }

# Loop to add more instances
while true; do
  if whiptail --title "Add Another Instance?" \
    --yesno "\
You have ${#INSTANCES[@]} instance(s) configured.

Would you like to add another instance?
(e.g. 4K, Kids, Anime)" \
    10 $DLG_W; then
    add_instance || true
  else
    break
  fi
done

if [[ ${#INSTANCES[@]} -eq 0 ]]; then
  whiptail --title "Error" --msgbox "No instances configured. Exiting." 8 40
  exit 1
fi

# =============================================================================
# STEP 6 - SUMMARY
# =============================================================================
SUMMARY="Plex Media Server: Always installed\n\n"
SUMMARY+="Global Services:\n"
if [[ ${#GLOBAL_SERVICES[@]} -eq 0 ]]; then
  SUMMARY+="  (none)\n"
else
  for svc in "${GLOBAL_SERVICES[@]}"; do
    SUMMARY+="  - $svc\n"
  done
fi
SUMMARY+="\nInstances:\n"
IDX=0
for inst in "${INSTANCES[@]}"; do
  IFS='|' read -r INAME ILABEL ISVCS <<< "$inst"
  SUMMARY+="  [$IDX] $ILABEL ($INAME)\n"
  IFS=',' read -ra SLIST <<< "$ISVCS"
  for s in "${SLIST[@]}"; do
    SUMMARY+="       - $s\n"
  done
  IDX=$((IDX + 1))
done
SUMMARY+="\nTimezone: $TIMEZONE"
SUMMARY+="\nZurg Version: $ZURG_VERSION"

whiptail --title "Installation Summary" \
  --scrolltext \
  --msgbox "$SUMMARY" \
  $DLG_H $DLG_W

# Confirm
if ! whiptail --title "Confirm Installation" \
  --yesno "\
Ready to install UnlimitedPlex Beta with the selected configuration.

This will:
  - Install Docker (if not present)
  - Deploy Plex Media Server
  - Deploy ${#INSTANCES[@]} instance(s)
  - Deploy global services

This may take 10-20 minutes.

Proceed with installation?" \
  $DLG_H $DLG_W; then
  echo "Installation cancelled."
  exit 0
fi

# =============================================================================
# STEP 7 - GENERATE CONFIG JSON
# =============================================================================
python3 - << PYEOF
import json

instances = []
for inst in [$(printf '"%s",' "${INSTANCES[@]}" | sed 's/,$//')]:
    parts = inst.split('|')
    name, label, svcs = parts[0], parts[1], parts[2]
    instances.append({
        "name": name,
        "label": label,
        "services": svcs.split(',')
    })

global_svcs = [$(printf '"%s",' "${GLOBAL_SERVICES[@]}" | sed 's/,$//' 2>/dev/null || echo '')]
global_svcs = [s for s in global_svcs if s]

config = {
    "rd_token": "$RD_TOKEN",
    "plex_token": "$PLEX_TOKEN",
    "timezone": "$TIMEZONE",
    "zurg_version": "$ZURG_VERSION",
    "nzbdav_password": "$NZBDAV_PASSWORD",
    "instances": instances,
    "global_services": global_svcs
}

with open("$CONFIG_FILE", "w") as f:
    json.dump(config, f, indent=2)

print(f"Config written to $CONFIG_FILE")
PYEOF

# =============================================================================
# STEP 8 - RUN INSTALLER
# =============================================================================
clear
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  UnlimitedPlex Beta - Starting Installation${NC}"
echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Config file:${NC} $CONFIG_FILE"
echo -e "${CYAN}Log file:${NC}    /var/log/unlimitedplex_beta.log"
echo ""

if [[ ! -f "$SCRIPT_DIR/setup_beta.sh" ]]; then
  echo -e "${RED}[ERROR]${NC} setup_beta.sh not found in $SCRIPT_DIR"
  exit 1
fi

chmod +x "$SCRIPT_DIR/setup_beta.sh"
bash "$SCRIPT_DIR/setup_beta.sh" --config "$CONFIG_FILE"