#!/bin/bash
# =============================================================================
# fix_startup.sh — Updates /root/startup.sh to start NZBDav before arr-stack
# Run this on your Ubuntu server to fix the reboot issue immediately
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

log "Backing up existing startup.sh to /root/startup.sh.bak..."
cp /root/startup.sh /root/startup.sh.bak 2>/dev/null || true

log "Writing updated /root/startup.sh..."
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
log "startup.sh updated successfully!"

# Ensure cron job exists
CRON_LINE="@reboot sleep 10 && /root/startup.sh"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
FILTERED_CRON=$(echo "$EXISTING_CRON" | grep -v "startup.sh" || true)
printf '%s\n%s\n' "$FILTERED_CRON" "$CRON_LINE" | grep -v '^$' | crontab - || true
log "Cron job verified."

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN} Startup script updated!${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Boot sequence is now:"
echo "  1. /mnt set as shared mount"
echo "  2. Zurg + Rclone (Real-Debrid) started"
echo "  3. Wait for Zurg healthy + /mnt/remote/realdebrid ready"
echo "  4. NZBDav started (if installed)"
echo "  5. Wait for NZBDav healthy + /mnt/remote/nzbdav ready"
echo "  6. *arr stack started (Radarr/Sonarr/etc)"
echo "  7. Decypharr started"
echo ""
echo "Old startup.sh backed up to: /root/startup.sh.bak"
echo "Log file: /var/log/startup_arr_stack.log"
echo ""
warn "Reboot to test, or run manually: sudo /root/startup.sh"