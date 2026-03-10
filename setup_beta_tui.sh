#!/bin/bash
# =============================================================================
#  UnlimitedPlex Beta - Linux Terminal UI (TUI)
#  Interactive service selector and instance builder
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Please run as root: sudo bash setup_beta_tui.sh"
  exit 1
fi

# Install whiptail if missing
if ! command -v whiptail &>/dev/null; then
  echo -e "${CYAN}[INFO]${NC} Installing whiptail..."
  apt-get update -qq && apt-get install -y -qq whiptail
fi

CONFIG_FILE="/tmp/unlimitedplex_config.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TERM_H=$(tput lines 2>/dev/null || echo 40)
TERM_W=$(tput cols  2>/dev/null || echo 80)
DLG_H=$((TERM_H - 4)); DLG_W=$((TERM_W - 8))
[[ $DLG_H -lt 20 ]] && DLG_H=20
[[ $DLG_W -lt 60 ]] && DLG_W=60
[[ $DLG_H -gt 40 ]] && DLG_H=40
[[ $DLG_W -gt 100 ]] && DLG_W=100

# =============================================================================
# WELCOME
# =============================================================================
whiptail --title "UnlimitedPlex Beta Installer" --msgbox "\
Welcome to UnlimitedPlex Beta!

This installer lets you:
  * Choose which arr services to install per instance
  * Create multiple instances (e.g. Main, 4K, Kids)
  * Each instance gets its own Radarr/Sonarr/Prowlarr

The following are always installed (global):
  * Plex Media Server
  * Zurg + Rclone  (Real-Debrid mount)
  * Decypharr      (qBittorrent mock for RD)

Optional global services (installed once, shared):
  * Tautulli, Pulsarr, NZBDav

Press OK to begin." $DLG_H $DLG_W

# =============================================================================
# CREDENTIALS
# =============================================================================
RD_TOKEN=$(whiptail --title "Real-Debrid API Token" \
  --inputbox "Enter your Real-Debrid API token.\n\nGet it from: https://real-debrid.com/apitoken" \
  10 $DLG_W "" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }
[[ -z "$RD_TOKEN" ]] && { whiptail --title "Error" --msgbox "Real-Debrid token is required." 8 40; exit 1; }

PLEX_TOKEN=$(whiptail --title "Plex Claim Token" \
  --inputbox "Enter your Plex claim token.\n\nGet it from: https://www.plex.tv/claim\n(Token expires in 4 minutes)" \
  10 $DLG_W "" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }
[[ -z "$PLEX_TOKEN" ]] && { whiptail --title "Error" --msgbox "Plex token is required." 8 40; exit 1; }

TIMEZONE=$(whiptail --title "Timezone" \
  --inputbox "Enter your timezone (TZ database format).\n\nExamples: America/New_York, Europe/London, Australia/Sydney" \
  10 $DLG_W "America/New_York" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }
[[ -z "$TIMEZONE" ]] && TIMEZONE="America/New_York"

ZURG_VERSION=$(whiptail --title "Zurg Version" \
  --inputbox "Enter the Zurg version to install.\n\nLatest stable: v0.9.3-final" \
  8 $DLG_W "v0.9.3-final" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }
[[ -z "$ZURG_VERSION" ]] && ZURG_VERSION="v0.9.3-final"

# =============================================================================
# GLOBAL SERVICES
# =============================================================================
GLOBAL_RESULT=$(whiptail --title "Global Services (optional)" \
  --checklist "\
These are installed ONCE and shared across all instances.
Always installed: Plex, Zurg, Decypharr, Prowlarr." \
  $DLG_H $DLG_W 3 \
  "tautulli" "Tautulli - Plex analytics & monitoring (port 8181)" ON  \
  "pulsarr"  "Pulsarr  - Plex watchlist sync (port 3003)"         OFF \
  "nzbdav"   "NZBDav   - Usenet streaming via WebDAV (port 3000)" OFF \
  3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }

GLOBAL_SERVICES=()
for svc in $GLOBAL_RESULT; do
  GLOBAL_SERVICES+=("$(echo "$svc" | tr -d '"')")
done

NZBDAV_PASSWORD="changeme"
if printf '%s\n' "${GLOBAL_SERVICES[@]}" | grep -q "^nzbdav$"; then
  NZBDAV_PASSWORD=$(whiptail --title "NZBDav Password" \
    --passwordbox "Enter a password for NZBDav WebDAV access:" \
    8 $DLG_W "changeme" 3>&1 1>&2 2>&3) || { echo "Cancelled."; exit 0; }
  [[ -z "$NZBDAV_PASSWORD" ]] && NZBDAV_PASSWORD="changeme"
fi

# =============================================================================
# INSTANCE BUILDER
# =============================================================================
INSTANCES=()

whiptail --title "Instance Builder" --msgbox "\
Now you'll set up your instances.

An instance = a separate Radarr + Sonarr + Prowlarr set.
Each instance gets its own:
  - Ports (base + index*100)
  - Symlink dirs (/mnt/symlinks/<name>_radarr, etc.)
  - Plex library dirs (/mnt/plex/<Label>/Movies, /TV)

Examples:
  Main  -> Radarr:7878  Sonarr:8989  Prowlarr:9696
  4K    -> Radarr:7978  Sonarr:9089  Prowlarr:9796
  Kids  -> Radarr:8078  Sonarr:9189  Prowlarr:9896

Press OK to add your first instance." $DLG_H $DLG_W

add_instance() {
  local LABEL
  LABEL=$(whiptail --title "Instance Name" \
    --inputbox "Enter a name for this instance.\n\nExamples: Main, 4K, Kids, Anime\n(Short names, no spaces)" \
    10 $DLG_W "" 3>&1 1>&2 2>&3) || return 1
  [[ -z "$LABEL" ]] && return 1

  local NAME
  NAME=$(echo "$LABEL" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '_' | sed 's/_*$//')

  local SVCS
  SVCS=$(whiptail --title "Services for: $LABEL" \
    --checklist "\
Select which arr services to install for '$LABEL'.

Note: Zurg, Decypharr and Prowlarr are global.
Only Radarr and Sonarr are per-instance." \
    $DLG_H $DLG_W 2 \
    "radarr" "Radarr - Movie management"   ON  \
    "sonarr" "Sonarr - TV show management" ON  \
    3>&1 1>&2 2>&3) || return 1

  local SVC_LIST=""
  for svc in $SVCS; do
    svc=$(echo "$svc" | tr -d '"')
    [[ -n "$SVC_LIST" ]] && SVC_LIST="${SVC_LIST},"
    SVC_LIST="${SVC_LIST}${svc}"
  done

  if [[ -z "$SVC_LIST" ]]; then
    whiptail --title "Warning" --msgbox "No services selected for '$LABEL'. Instance skipped." 8 50
    return 1
  fi

  INSTANCES+=("${NAME}|${LABEL}|${SVC_LIST}")
  return 0
}

add_instance || { whiptail --title "Error" --msgbox "At least one instance is required." 8 40; exit 1; }

while true; do
  if whiptail --title "Add Another Instance?" \
    --yesno "You have ${#INSTANCES[@]} instance(s) configured.\n\nAdd another? (e.g. 4K, Kids, Anime)" \
    10 $DLG_W; then
    add_instance || true
  else
    break
  fi
done

[[ ${#INSTANCES[@]} -eq 0 ]] && { whiptail --title "Error" --msgbox "No instances configured. Exiting." 8 40; exit 1; }

# =============================================================================
# SUMMARY
# =============================================================================
IDX=0
SUMMARY="Always installed (global):\n"
SUMMARY+="  - Plex Media Server (port 32400)\n"
SUMMARY+="  - Zurg + Rclone     (port 9999)\n"
SUMMARY+="  - Decypharr         (port 8282)\n"
SUMMARY+="  - Prowlarr          (port 9696)\n\n"

SUMMARY+="Optional global services:\n"
if [[ ${#GLOBAL_SERVICES[@]} -eq 0 ]]; then
  SUMMARY+="  (none selected)\n"
else
  for svc in "${GLOBAL_SERVICES[@]}"; do
    case "$svc" in
      tautulli) SUMMARY+="  - Tautulli (port 8181)\n" ;;
      pulsarr)  SUMMARY+="  - Pulsarr  (port 3003)\n" ;;
      nzbdav)   SUMMARY+="  - NZBDav   (port 3000)\n" ;;
    esac
  done
fi

SUMMARY+="\nInstances (Radarr + Sonarr only):\n"
for inst in "${INSTANCES[@]}"; do
  IFS='|' read -r INAME ILABEL ISVCS <<< "$inst"
  RADARR_PORT=$((7878 + IDX * 100))
  SONARR_PORT=$((8989 + IDX * 100))
  SUMMARY+="  [$IDX] $ILABEL ($INAME)\n"
  echo "$ISVCS" | grep -q "radarr" && SUMMARY+="       Radarr: port $RADARR_PORT\n"
  echo "$ISVCS" | grep -q "sonarr" && SUMMARY+="       Sonarr: port $SONARR_PORT\n"
  SUMMARY+="       Plex libs: /mnt/plex/$ILABEL/{Movies,TV}\n"
  IDX=$((IDX + 1))
done

whiptail --title "Installation Summary" --scrolltext --msgbox "$SUMMARY" $DLG_H $DLG_W

if ! whiptail --title "Confirm Installation" \
  --yesno "Ready to install UnlimitedPlex Beta.\n\nThis may take 10-20 minutes.\n\nProceed?" \
  10 $DLG_W; then
  echo "Installation cancelled."
  exit 0
fi

# =============================================================================
# GENERATE CONFIG JSON (using Python to avoid shell quoting issues)
# =============================================================================

# Build pipe-delimited instance data for Python
INST_DATA=""
for inst in "${INSTANCES[@]}"; do
  [[ -n "$INST_DATA" ]] && INST_DATA="${INST_DATA};"
  INST_DATA="${INST_DATA}${inst}"
done

# Build comma-delimited global services for Python
GLOBAL_DATA=""
for svc in "${GLOBAL_SERVICES[@]}"; do
  [[ -n "$GLOBAL_DATA" ]] && GLOBAL_DATA="${GLOBAL_DATA},"
  GLOBAL_DATA="${GLOBAL_DATA}${svc}"
done

python3 - "$CONFIG_FILE" "$RD_TOKEN" "$PLEX_TOKEN" "$TIMEZONE" "$ZURG_VERSION" "$NZBDAV_PASSWORD" "$INST_DATA" "$GLOBAL_DATA" << 'PYEOF'
import json, sys

config_file = sys.argv[1]
rd_token = sys.argv[2]
plex_token = sys.argv[3]
timezone = sys.argv[4]
zurg_version = sys.argv[5]
nzbdav_password = sys.argv[6]
inst_data = sys.argv[7]
global_data = sys.argv[8]

# Parse instances: "name|label|svc1,svc2;name2|label2|svc1"
instances = []
if inst_data.strip():
    for entry in inst_data.split(";"):
        parts = entry.split("|")
        if len(parts) == 3:
            instances.append({
                "name": parts[0],
                "label": parts[1],
                "services": [s.strip() for s in parts[2].split(",") if s.strip()]
            })

# Parse global services: "tautulli,pulsarr,nzbdav"
global_services = [s.strip() for s in global_data.split(",") if s.strip()] if global_data.strip() else []

config = {
    "rd_token": rd_token,
    "plex_token": plex_token,
    "timezone": timezone,
    "zurg_version": zurg_version,
    "nzbdav_password": nzbdav_password,
    "instances": instances,
    "global_services": global_services
}

with open(config_file, "w") as f:
    json.dump(config, f, indent=2)
PYEOF

echo -e "${GREEN}[OK]${NC} Config written to $CONFIG_FILE"

# =============================================================================
# RUN INSTALLER
# =============================================================================
clear
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  UnlimitedPlex Beta - Starting Installation${NC}"
echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Config:${NC} $CONFIG_FILE"
echo -e "${CYAN}Log:${NC}    /var/log/unlimitedplex_beta.log"
echo ""

[[ ! -f "$SCRIPT_DIR/setup_beta.sh" ]] && { echo -e "${RED}[ERROR]${NC} setup_beta.sh not found in $SCRIPT_DIR"; exit 1; }

chmod +x "$SCRIPT_DIR/setup_beta.sh"
bash "$SCRIPT_DIR/setup_beta.sh" --config "$CONFIG_FILE"