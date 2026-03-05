#!/bin/bash
# =============================================================================
#  Plex + Real-Debrid Unified Setup Script
#  A single entry point for all setup options
# =============================================================================
#
#  USAGE:
#    chmod +x setup.sh
#    sudo ./setup.sh
#
#  OPTIONS:
#    Option 1: Basic Setup      — Plex + Zurg + Rclone + plex_debrid
#    Option 2: Arr Stack        — Plex + Zurg + Rclone + Sonarr/Radarr/Prowlarr/Overseerr/Decypharr
#    Option 3: Arr Stack + NZBDav — Option 2 + NZBDav for Usenet streaming
#
#  Both options 2 and 3 install the core stack (Docker, Zurg, Rclone, Plex).
#  Option 3 runs the full arr stack FIRST, then adds NZBDav on top.
#
# =============================================================================

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m' # No Colour

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Please run this script as root:  sudo ./setup.sh"
  exit 1
fi

# ── Check that sub-scripts exist ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

check_script() {
  if [[ ! -f "$SCRIPT_DIR/$1" ]]; then
    echo -e "${RED}[ERROR]${NC} Missing: $1"
    echo -e "        Make sure all scripts are in the same directory."
    exit 1
  fi
  chmod +x "$SCRIPT_DIR/$1"
}

check_script "setup_plex_debrid.sh"
check_script "setup_arr_stack.sh"
check_script "setup_nzbdav.sh"

# ── Display Banner ────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
echo -e "${BOLD}${CYAN}║${NC}     ${BOLD}🎬  Plex + Real-Debrid Automated Setup${NC}                   ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}║${NC}     ${DIM}Zurg • Rclone • Docker • Plex${NC}                           ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Display Options ───────────────────────────────────────────────────────────
echo -e "${BOLD}  Choose your setup:${NC}"
echo ""
echo -e "  ${BOLD}${GREEN}[1]${NC}  ${BOLD}Basic Setup${NC} — Plex + plex_debrid"
echo -e "       ${DIM}├── Docker, Zurg, Rclone, Plex Media Server${NC}"
echo -e "       ${DIM}├── plex_debrid for automated content discovery${NC}"
echo -e "       ${DIM}├── Folder monitor for Plex library refresh${NC}"
echo -e "       ${DIM}└── Startup automation with cron${NC}"
echo ""
echo -e "  ${BOLD}${MAGENTA}[2]${NC}  ${BOLD}Arr Stack Setup${NC} — Plex + Sonarr/Radarr/Prowlarr"
echo -e "       ${DIM}├── Everything from Basic Setup${NC}"
echo -e "       ${DIM}├── Sonarr + Sonarr 4K (TV show management)${NC}"
echo -e "       ${DIM}├── Radarr + Radarr 4K (Movie management)${NC}"
echo -e "       ${DIM}├── Prowlarr (Indexer manager + Torrentio)${NC}"
echo -e "       ${DIM}├── Overseerr (Request management UI)${NC}"
echo -e "       ${DIM}├── Decypharr (Real-Debrid qBittorrent mock)${NC}"
echo -e "       ${DIM}└── Replaces plex_debrid with full *arr stack${NC}"
echo ""
echo -e "  ${BOLD}${BLUE}[3]${NC}  ${BOLD}Arr Stack + NZBDav${NC} — Option 2 + Usenet Streaming"
echo -e "       ${DIM}├── Everything from Arr Stack Setup${NC}"
echo -e "       ${DIM}├── NZBDav (Usenet WebDAV streaming server)${NC}"
echo -e "       ${DIM}├── Rclone sidecar for NZBDav WebDAV mount${NC}"
echo -e "       ${DIM}├── SABnzbd-compatible API for Sonarr/Radarr${NC}"
echo -e "       ${DIM}└── Stream Usenet content without downloading${NC}"
echo ""
echo -e "  ${DIM}[q]  Quit${NC}"
echo ""

# ── Helper: run a step script ─────────────────────────────────────────────────
run_step() {
  local step_num="$1"
  local step_total="$2"
  local step_label="$3"
  local script="$4"

  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${CYAN}  STEP ${step_num} of ${step_total}: ${step_label}${NC}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  sleep 1

  bash "$SCRIPT_DIR/$script"
  local EXIT_CODE=$?

  if [[ $EXIT_CODE -ne 0 ]]; then
    echo ""
    echo -e "${RED}[ERROR]${NC} Step failed (exit code: $EXIT_CODE)."
    echo -e "        Fix the issues above and re-run: ${YELLOW}sudo ./setup.sh${NC}"
    exit $EXIT_CODE
  fi

  echo ""
  echo -e "${GREEN}[OK]${NC}  ${step_label} completed successfully!"
}

# ── Get User Choice ───────────────────────────────────────────────────────────
while true; do
  echo -ne "  ${BOLD}Enter your choice [1/2/3/q]: ${NC}"
  read -r choice
  case "$choice" in
    1)
      echo ""
      echo -e "  ${GREEN}▶ Starting Basic Setup (Plex + plex_debrid)...${NC}"
      echo ""
      sleep 1
      bash "$SCRIPT_DIR/setup_plex_debrid.sh"
      exit $?
      ;;

    2)
      echo ""
      echo -e "  ${MAGENTA}▶ Starting Arr Stack Setup...${NC}"
      echo -e "  ${DIM}  Step 1: Base setup (Docker, Zurg, Rclone, Plex)${NC}"
      echo -e "  ${DIM}  Step 2: *arr stack (Sonarr, Radarr, Prowlarr, Overseerr, Decypharr)${NC}"

      run_step 1 2 "Base Setup (Docker + Zurg + Rclone + Plex)" "setup_plex_debrid.sh"
      run_step 2 2 "*Arr Stack (Sonarr + Radarr + Prowlarr + Decypharr)" "setup_arr_stack.sh"

      echo ""
      echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
      echo -e "${BOLD}${GREEN}  ✅ Full Arr Stack Setup Complete!${NC}"
      echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
      echo ""
      echo -e "  ${CYAN}Next steps:${NC} See ${YELLOW}ARR_STACK_INSTRUCTIONS.md${NC} for configuration."
      echo ""
      exit 0
      ;;

    3)
      echo ""
      echo -e "  ${BLUE}▶ Starting Arr Stack + NZBDav Setup...${NC}"
      echo -e "  ${DIM}  Step 1: Base setup (Docker, Zurg, Rclone, Plex)${NC}"
      echo -e "  ${DIM}  Step 2: *arr stack (Sonarr, Radarr, Prowlarr, Overseerr, Decypharr)${NC}"
      echo -e "  ${DIM}  Step 3: NZBDav (Usenet streaming via WebDAV)${NC}"

      run_step 1 3 "Base Setup (Docker + Zurg + Rclone + Plex)" "setup_plex_debrid.sh"
      run_step 2 3 "*Arr Stack (Sonarr + Radarr + Prowlarr + Decypharr)" "setup_arr_stack.sh"
      run_step 3 3 "NZBDav (Usenet Streaming)" "setup_nzbdav.sh"

      echo ""
      echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
      echo -e "${BOLD}${GREEN}  ✅ Full Arr Stack + NZBDav Setup Complete!${NC}"
      echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════════${NC}"
      echo ""
      echo -e "  ${CYAN}Services running:${NC}"
      echo -e "  ${DIM}  • Plex Media Server    → http://localhost:32400/web${NC}"
      echo -e "  ${DIM}  • Radarr               → http://localhost:7878${NC}"
      echo -e "  ${DIM}  • Radarr 4K            → http://localhost:7879${NC}"
      echo -e "  ${DIM}  • Sonarr               → http://localhost:8989${NC}"
      echo -e "  ${DIM}  • Sonarr 4K            → http://localhost:8990${NC}"
      echo -e "  ${DIM}  • Prowlarr             → http://localhost:9696${NC}"
      echo -e "  ${DIM}  • Overseerr            → http://localhost:5055${NC}"
      echo -e "  ${DIM}  • Decypharr            → http://localhost:8282${NC}"
      echo -e "  ${DIM}  • NZBDav               → http://localhost:3000${NC}"
      echo ""
      echo -e "  ${CYAN}Next steps:${NC}"
      echo -e "  ${DIM}  1. See ${YELLOW}ARR_STACK_INSTRUCTIONS.md${NC}${DIM} for arr stack configuration${NC}"
      echo -e "  ${DIM}  2. Open NZBDav at http://localhost:3000 and:${NC}"
      echo -e "  ${DIM}     - Configure your Usenet provider (Settings > Usenet)${NC}"
      echo -e "  ${DIM}     - Set WebDAV password (Settings > WebDAV)${NC}"
      echo -e "  ${DIM}     - Set Rclone mount dir to /mnt/remote/nzbdav (Settings > SABnzbd)${NC}"
      echo -e "  ${DIM}     - Add Radarr/Sonarr instances (Settings > Radarr/Sonarr)${NC}"
      echo ""
      exit 0
      ;;

    q|Q|quit|exit)
      echo ""
      echo -e "  ${DIM}Setup cancelled.${NC}"
      echo ""
      exit 0
      ;;
    *)
      echo -e "  ${RED}Invalid choice.${NC} Please enter ${BOLD}1${NC}, ${BOLD}2${NC}, ${BOLD}3${NC}, or ${BOLD}q${NC}."
      ;;
  esac
done