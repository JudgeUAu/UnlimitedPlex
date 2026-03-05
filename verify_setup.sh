#!/bin/bash
# =============================================================================
#  Plex + Real-Debrid Setup Verification Script
#  Run this after setup or reboot to check all components are working.
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() { echo -e "  ${GREEN}✓${NC} $*"; ((PASS++)); }
check_fail() { echo -e "  ${RED}✗${NC} $*"; ((FAIL++)); }
check_warn() { echo -e "  ${YELLOW}⚠${NC} $*"; ((WARN++)); }
section()    { echo -e "\n${BOLD}${CYAN}── $* ──${NC}"; }

echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  Plex + Real-Debrid Health Check${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"

# ── Docker ───────────────────────────────────────────────────────────
section "Docker"

if command -v docker &>/dev/null; then
  check_pass "Docker installed: $(docker --version 2>/dev/null | head -1)"
else
  check_fail "Docker not found"
fi

if docker info &>/dev/null 2>&1; then
  check_pass "Docker daemon is running"
else
  check_fail "Docker daemon is not running"
fi

# Check it's not snap Docker
if snap list docker &>/dev/null 2>&1; then
  check_fail "Docker is installed via Snap (should be apt/official)"
else
  check_pass "Docker is NOT snap (good)"
fi

# ── Zurg Container ──────────────────────────────────────────────────
section "Zurg Container"

ZURG_STATUS=$(docker inspect --format '{{.State.Status}}' zurg-testing-zurg-1 2>/dev/null || echo "not found")
if [[ "$ZURG_STATUS" == "running" ]]; then
  check_pass "Zurg container is running"
else
  check_fail "Zurg container status: $ZURG_STATUS"
fi

ZURG_HEALTH=$(docker inspect --format '{{.State.Health.Status}}' zurg-testing-zurg-1 2>/dev/null || echo "unknown")
if [[ "$ZURG_HEALTH" == "healthy" ]]; then
  check_pass "Zurg container is healthy"
elif [[ "$ZURG_HEALTH" == "unknown" ]]; then
  check_warn "Zurg health check not configured or not available"
else
  check_fail "Zurg container health: $ZURG_HEALTH"
fi

ZURG_RESTART=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' zurg-testing-zurg-1 2>/dev/null || echo "not found")
if [[ "$ZURG_RESTART" == "unless-stopped" || "$ZURG_RESTART" == "always" ]]; then
  check_pass "Zurg restart policy: $ZURG_RESTART"
else
  check_warn "Zurg restart policy: $ZURG_RESTART (expected: unless-stopped)"
fi

# Test Zurg HTTP endpoint
if curl -sf http://localhost:9999/http &>/dev/null; then
  check_pass "Zurg HTTP endpoint responding on port 9999"
else
  check_fail "Zurg HTTP endpoint not responding on port 9999"
fi

# ── Rclone Container ────────────────────────────────────────────────
section "Rclone Container"

RCLONE_STATUS=$(docker inspect --format '{{.State.Status}}' zurg-testing-rclone-1 2>/dev/null || echo "not found")
if [[ "$RCLONE_STATUS" == "running" ]]; then
  check_pass "Rclone container is running"
else
  check_fail "Rclone container status: $RCLONE_STATUS"
fi

RCLONE_RESTART=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' zurg-testing-rclone-1 2>/dev/null || echo "not found")
if [[ "$RCLONE_RESTART" == "unless-stopped" || "$RCLONE_RESTART" == "always" ]]; then
  check_pass "Rclone restart policy: $RCLONE_RESTART"
else
  check_warn "Rclone restart policy: $RCLONE_RESTART (expected: unless-stopped)"
fi

# ── Mount Point ──────────────────────────────────────────────────────
section "Mount Point (/mnt/zurg)"

if mountpoint -q /mnt/zurg 2>/dev/null; then
  check_pass "/mnt/zurg is a mount point"
elif ls /mnt/zurg/ &>/dev/null; then
  check_warn "/mnt/zurg is accessible but not detected as mount point"
else
  check_fail "/mnt/zurg is not accessible (stale mount or missing)"
fi

if [[ -d "/mnt/zurg/movies" ]]; then
  MOVIE_COUNT=$(ls /mnt/zurg/movies/ 2>/dev/null | wc -l)
  check_pass "Movies directory exists ($MOVIE_COUNT items)"
else
  check_fail "Movies directory not found at /mnt/zurg/movies/"
fi

if [[ -d "/mnt/zurg/shows" ]]; then
  SHOW_COUNT=$(ls /mnt/zurg/shows/ 2>/dev/null | wc -l)
  check_pass "Shows directory exists ($SHOW_COUNT items)"
else
  check_fail "Shows directory not found at /mnt/zurg/shows/"
fi

# Check /mnt is shared
if findmnt -n -o PROPAGATION /mnt 2>/dev/null | grep -q "shared"; then
  check_pass "/mnt has shared propagation"
else
  check_warn "/mnt may not have shared propagation (rclone may fail after reboot)"
fi

# ── Zurg Config ──────────────────────────────────────────────────────
section "Zurg Configuration"

ZURG_DIR="/opt/zurg-testing"

if [[ -f "$ZURG_DIR/config.yml" ]]; then
  check_pass "config.yml exists"

  # Check for correct group_order
  SHOWS_ORDER=$(grep -A3 "shows:" "$ZURG_DIR/config.yml" | grep "group_order" | awk '{print $2}')
  MOVIES_ORDER=$(grep -A3 "movies:" "$ZURG_DIR/config.yml" | grep "group_order" | awk '{print $2}')

  if [[ -n "$SHOWS_ORDER" && -n "$MOVIES_ORDER" ]]; then
    if [[ "$SHOWS_ORDER" -lt "$MOVIES_ORDER" ]]; then
      check_pass "Shows group_order ($SHOWS_ORDER) < Movies group_order ($MOVIES_ORDER) – correct priority"
    else
      check_fail "Shows group_order ($SHOWS_ORDER) should be less than Movies group_order ($MOVIES_ORDER)"
    fi
  else
    check_warn "Could not read group_order values from config.yml"
  fi

  # Check for has_episodes filter
  if grep -q "has_episodes: true" "$ZURG_DIR/config.yml"; then
    check_pass "Shows filter uses has_episodes: true"
  else
    check_warn "Shows filter does not use has_episodes: true – may not sort correctly"
  fi

  # Check for only_show_the_biggest_file
  if grep -q "only_show_the_biggest_file: true" "$ZURG_DIR/config.yml"; then
    check_pass "Movies uses only_show_the_biggest_file: true"
  else
    check_warn "Movies missing only_show_the_biggest_file setting"
  fi

  # Check for zurg version header
  if grep -q "^zurg: v1" "$ZURG_DIR/config.yml"; then
    check_pass "Config has zurg: v1 version header"
  else
    check_fail "Config missing 'zurg: v1' version header"
  fi

  # Check for RD token
  if grep -q "^token:" "$ZURG_DIR/config.yml"; then
    check_pass "Real-Debrid token is set"
  else
    check_fail "Real-Debrid token not found in config"
  fi

  # Check for Plex integration
  if grep -q "plex_server_url" "$ZURG_DIR/config.yml"; then
    check_pass "Plex server URL configured in Zurg"
  else
    check_warn "Plex server URL not in Zurg config (native Plex integration disabled)"
  fi

  if grep -q "plex_token" "$ZURG_DIR/config.yml"; then
    TOKEN_VAL=$(grep "plex_token" "$ZURG_DIR/config.yml" | awk '{print $2}')
    if [[ "$TOKEN_VAL" == "PLEX_TOKEN_PLACEHOLDER" || -z "$TOKEN_VAL" ]]; then
      check_warn "Plex token is placeholder – needs to be set"
    else
      check_pass "Plex token is configured in Zurg"
    fi
  else
    check_warn "Plex token not in Zurg config"
  fi
else
  check_fail "config.yml not found at $ZURG_DIR/config.yml"
fi

if [[ -f "$ZURG_DIR/docker-compose.yml" ]]; then
  check_pass "docker-compose.yml exists"
else
  check_fail "docker-compose.yml not found"
fi

if [[ -f "$ZURG_DIR/rclone.conf" ]]; then
  check_pass "rclone.conf exists"
else
  check_fail "rclone.conf not found"
fi

if [[ -f "$ZURG_DIR/plex_update.sh" ]]; then
  check_pass "plex_update.sh exists"
  # Check if token placeholder is still there
  if grep -q "PLEX_TOKEN_PLACEHOLDER" "$ZURG_DIR/plex_update.sh"; then
    check_warn "plex_update.sh still has PLEX_TOKEN_PLACEHOLDER – needs Plex token"
  else
    check_pass "plex_update.sh has Plex token configured"
  fi
else
  check_fail "plex_update.sh not found"
fi

# ── Plex Media Server ───────────────────────────────────────────────
section "Plex Media Server"

if systemctl is-active --quiet plexmediaserver 2>/dev/null; then
  check_pass "Plex Media Server is running"
else
  check_fail "Plex Media Server is not running"
fi

if systemctl is-enabled --quiet plexmediaserver 2>/dev/null; then
  check_pass "Plex Media Server is enabled (starts on boot)"
else
  check_warn "Plex Media Server is not enabled for boot"
fi

if curl -sf http://localhost:32400/identity &>/dev/null; then
  check_pass "Plex responding on port 32400"
else
  check_fail "Plex not responding on port 32400"
fi

# ── Python & plex_debrid ────────────────────────────────────────────
section "Python & plex_debrid"

if command -v python3 &>/dev/null; then
  check_pass "Python 3 installed: $(python3 --version)"
else
  check_fail "Python 3 not found"
fi

if command -v pip3 &>/dev/null; then
  check_pass "Pip3 installed: $(pip3 --version 2>/dev/null | head -1)"
else
  check_fail "Pip3 not found"
fi

# Check for plex_debrid in multiple locations
PLEX_DEBRID_FOUND=false
for dir in /root/plex_debrid /home/*/plex_debrid; do
  if [[ -d "$dir" && -f "$dir/main.py" ]]; then
    check_pass "plex_debrid found at $dir"
    PLEX_DEBRID_FOUND=true
    break
  fi
done
if [[ "$PLEX_DEBRID_FOUND" == "false" ]]; then
  check_fail "plex_debrid not found"
fi

# ── Screen Sessions ─────────────────────────────────────────────────
section "Screen Sessions"

if command -v screen &>/dev/null; then
  check_pass "screen is installed"
else
  check_fail "screen not found"
fi

if screen -list 2>/dev/null | grep -q "\.pd"; then
  check_pass "plex_debrid screen session 'pd' is running"
else
  check_warn "plex_debrid screen session 'pd' is not running"
fi

if screen -list 2>/dev/null | grep -q "\.monitor"; then
  check_pass "Folder monitor screen session 'monitor' is running"
else
  check_warn "Folder monitor screen session 'monitor' is not running"
fi

# ── Startup Automation ──────────────────────────────────────────────
section "Startup Automation"

if [[ -f "/root/startup.sh" ]]; then
  check_pass "startup.sh exists"
  if [[ -x "/root/startup.sh" ]]; then
    check_pass "startup.sh is executable"
  else
    check_fail "startup.sh is not executable"
  fi
else
  check_fail "startup.sh not found"
fi

if [[ -f "/root/monitor_folders.sh" ]]; then
  check_pass "monitor_folders.sh exists"
else
  check_fail "monitor_folders.sh not found"
fi

if crontab -l 2>/dev/null | grep -q "startup.sh"; then
  check_pass "@reboot cron job registered"
else
  check_fail "@reboot cron job not found"
fi

# ── Essential Tools ─────────────────────────────────────────────────
section "Essential Tools"

for tool in git curl wget inotifywait xmllint; do
  if command -v "$tool" &>/dev/null; then
    check_pass "$tool is available"
  else
    check_fail "$tool not found"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────
echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  Health Check Summary${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"

echo -e "  ${GREEN}✓ Passed:${NC}  $PASS"
echo -e "  ${YELLOW}⚠ Warnings:${NC} $WARN"
echo -e "  ${RED}✗ Failed:${NC}  $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}All critical checks passed!${NC}\n"
  if [[ $WARN -gt 0 ]]; then
    echo -e "  ${YELLOW}Some warnings detected – review above for details.${NC}\n"
  fi
else
  echo -e "  ${RED}${BOLD}Some checks failed – review above for details.${NC}\n"
fi