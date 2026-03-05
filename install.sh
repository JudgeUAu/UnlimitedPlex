#!/bin/bash
# =============================================================================
#  Plex + Real-Debrid Remote Installer
#  Downloads all setup scripts from GitHub and launches the setup menu
# =============================================================================
#
#  USAGE:
#    GITHUB_TOKEN="your_token" bash <(curl -fsSL \
#      -H "Authorization: token your_token" \
#      https://raw.githubusercontent.com/JudgeUAu/UnlimitedPlex/main/install.sh)
#
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Root check ────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}[ERROR]${NC} Please run as root: sudo bash <(curl ...)"
  exit 1
fi

# ── Token check ───────────────────────────────────────────────────────────────
TOKEN="${GITHUB_TOKEN:-}"
if [ -z "$TOKEN" ]; then
  echo -e "${RED}[ERROR]${NC} GITHUB_TOKEN not set."
  echo ""
  echo "Usage:"
  echo -e "  ${YELLOW}GITHUB_TOKEN=&quot;your_token&quot; bash <(curl -fsSL \\${NC}"
  echo -e "  ${YELLOW}  -H &quot;Authorization: token your_token&quot; \\${NC}"
  echo -e "  ${YELLOW}  https://raw.githubusercontent.com/JudgeUAu/UnlimitedPlex/main/install.sh)${NC}"
  exit 1
fi

REPO="JudgeUAu/UnlimitedPlex"
BRANCH="main"
BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
INSTALL_DIR="/root/plex-setup"

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
echo -e "${BOLD}${CYAN}║${NC}     ${BOLD}🎬  Plex + Real-Debrid Remote Installer${NC}                  ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}║${NC}     ${CYAN}github.com/JudgeUAu/UnlimitedPlex${NC}                        ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ── Download scripts ──────────────────────────────────────────────────────────
echo -e "${CYAN}[INFO]${NC} Installing to: ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

SCRIPTS=(
  "setup.sh"
  "setup_plex_debrid.sh"
  "setup_arr_stack.sh"
  "setup_nzbdav.sh"
  "configure_arrs.sh"
  "verify_setup.sh"
  "README.md"
)

echo -e "${CYAN}[INFO]${NC} Downloading scripts from GitHub..."
echo ""

for script in "${SCRIPTS[@]}"; do
  HTTP_CODE=$(curl -fsSL \
    -H "Authorization: token ${TOKEN}" \
    -H "Accept: application/vnd.github.v3.raw" \
    -w "%{http_code}" \
    -o "${script}" \
    "${BASE_URL}/${script}" 2>/dev/null)

  if [ "$HTTP_CODE" = "200" ]; then
    chmod +x "${script}" 2>/dev/null || true
    echo -e "  ${GREEN}✓${NC} ${script}"
  else
    echo -e "  ${RED}✗${NC} ${script} (HTTP ${HTTP_CODE})"
    if [ "$script" = "setup.sh" ]; then
      echo -e "${RED}[ERROR]${NC} Failed to download main setup script."
      echo "  Check your token has access to the repo."
      exit 1
    fi
  fi
done

echo ""
echo -e "${GREEN}[OK]${NC} All scripts downloaded to ${INSTALL_DIR}"
echo ""

# ── Launch setup ──────────────────────────────────────────────────────────────
echo -e "${CYAN}[INFO]${NC} Launching setup menu..."
sleep 1
exec bash "${INSTALL_DIR}/setup.sh"