#!/bin/bash
# startup.sh – Full service startup for UnlimitedPlex
# Launched at boot via cron (@reboot)

LOG="/var/log/startup_arr_stack.log"
echo "[$(date)] ============================================" >> "$LOG"
echo "[$(date)] startup.sh triggered" >> "$LOG"

# ── Wait for system and Docker to settle ─────────────────────────────────────
sleep 20

WAIT=0
while [[ $WAIT -lt 60 ]]; do
  docker info &>/dev/null && break
  echo "[$(date)] Waiting for Docker daemon..." >> "$LOG"
  sleep 5; WAIT=$((WAIT + 5))
done
echo "[$(date)] Docker is ready." >> "$LOG"

# ── Load fuse + shared mount ──────────────────────────────────────────────────
modprobe fuse 2>/dev/null || true
grep -q "user_allow_other" /etc/fuse.conf 2>/dev/null || echo "user_allow_other" >> /etc/fuse.conf

if ! mountpoint -q /mnt 2>/dev/null; then
  mount --bind /mnt /mnt 2>/dev/null || true
fi
mount --make-shared /mnt 2>/dev/null || true
mount --make-rshared /mnt 2>/dev/null || true
echo "[$(date)] /mnt set as shared+rshared mount." >> "$LOG"

# ── Zurg + Rclone (Real-Debrid) ───────────────────────────────────────────────
# Kill any lingering rclone processes mounting realdebrid
pkill -f "rclone mount zurg" 2>/dev/null || true
sleep 2
# Unmount ALL stale realdebrid mounts (can pile up after crashes/restarts)
for i in $(seq 1 30); do
  fusermount -uz /mnt/remote/realdebrid 2>/dev/null && continue
  umount -f /mnt/remote/realdebrid 2>/dev/null && continue
  break
done
# Verify clean - use lazy unmount as final fallback (max 5 attempts)
UMOUNT_TRIES=0
while mount | grep -q "/mnt/remote/realdebrid" && [[ $UMOUNT_TRIES -lt 5 ]]; do
  echo "[$(date)] WARNING: realdebrid mount still present, forcing lazy unmount (attempt $UMOUNT_TRIES)..." >> "$LOG"
  umount -l /mnt/remote/realdebrid 2>/dev/null || true
  sleep 2
  UMOUNT_TRIES=$((UMOUNT_TRIES + 1))
done
echo "[$(date)] realdebrid mount cleanup done." >> "$LOG"
echo "[$(date)] Starting Zurg + Rclone..." >> "$LOG"
cd /opt/zurg-testing && docker compose up -d >> "$LOG" 2>&1

echo "[$(date)] Waiting for Zurg to be healthy..." >> "$LOG"
WAIT=0
while [[ $WAIT -lt 300 ]]; do
  STATUS=$(docker inspect --format '{{.State.Health.Status}}' zurg 2>/dev/null || echo "unknown")
  if [[ "$STATUS" == "healthy" ]]; then
    echo "[$(date)] Zurg is healthy." >> "$LOG"
    break
  fi
  sleep 10; WAIT=$((WAIT + 10))
done

echo "[$(date)] Waiting for /mnt/remote/realdebrid mount..." >> "$LOG"
WAIT=0
while [[ $WAIT -lt 120 ]]; do
  if mountpoint -q /mnt/remote/realdebrid 2>/dev/null || ls /mnt/remote/realdebrid &>/dev/null; then
    echo "[$(date)] /mnt/remote/realdebrid is ready." >> "$LOG"
    break
  fi
  sleep 5; WAIT=$((WAIT + 5))
done

# ── NZBDav + Rclone sidecar (Usenet) ─────────────────────────────────────────
# Kill any lingering rclone processes mounting nzbdav
pkill -f "rclone mount nzbdav" 2>/dev/null || true
sleep 2
# Unmount ALL stale nzbdav mounts (can pile up after crashes/restarts)
for i in $(seq 1 30); do
  fusermount -uz /mnt/remote/nzbdav 2>/dev/null && continue
  umount -f /mnt/remote/nzbdav 2>/dev/null && continue
  break
done
# Verify clean - use lazy unmount as final fallback (max 5 attempts)
UMOUNT_TRIES=0
while mount | grep -q "/mnt/remote/nzbdav" && [[ $UMOUNT_TRIES -lt 5 ]]; do
  echo "[$(date)] WARNING: nzbdav mount still present, forcing lazy unmount (attempt $UMOUNT_TRIES)..." >> "$LOG"
  umount -l /mnt/remote/nzbdav 2>/dev/null || true
  sleep 2
  UMOUNT_TRIES=$((UMOUNT_TRIES + 1))
done
echo "[$(date)] nzbdav mount cleanup done (ghost mounts may persist in WSL2 - this is OK)." >> "$LOG"
echo "[$(date)] Starting NZBDav..." >> "$LOG"
cd /opt/nzbdav && docker compose up -d nzbdav >> "$LOG" 2>&1

echo "[$(date)] Waiting for NZBDav to be healthy..." >> "$LOG"
WAIT=0
while [[ $WAIT -lt 120 ]]; do
  if curl -sf "http://localhost:3000/" &>/dev/null; then
    echo "[$(date)] NZBDav is healthy." >> "$LOG"
    break
  fi
  sleep 5; WAIT=$((WAIT + 5))
done

echo "[$(date)] Starting NZBDav rclone sidecar..." >> "$LOG"
cd /opt/nzbdav && docker compose up -d nzbdav_rclone >> "$LOG" 2>&1

echo "[$(date)] Waiting for /mnt/remote/nzbdav mount..." >> "$LOG"
WAIT=0
while [[ $WAIT -lt 120 ]]; do
  if mountpoint -q /mnt/remote/nzbdav 2>/dev/null || ls /mnt/remote/nzbdav &>/dev/null; then
    echo "[$(date)] /mnt/remote/nzbdav is ready." >> "$LOG"
    break
  fi
  sleep 5; WAIT=$((WAIT + 5))
done

# ── arr-stack (Radarr, Radarr4K, Sonarr, Sonarr4K, SonarrKids,
#               Prowlarr, Overseerr, Pulsarr, Audiobookshelf, Bookshelf) ──────
echo "[$(date)] Starting arr-stack..." >> "$LOG"
cd /opt/arr-stack && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] arr-stack started." >> "$LOG"

# ── Decypharr (has its own compose file) ─────────────────────────────────────
echo "[$(date)] Starting Decypharr..." >> "$LOG"
cd /opt/decypharr && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Decypharr started." >> "$LOG"

# ── Flaresolverr (has its own compose file) ───────────────────────────────────
echo "[$(date)] Starting Flaresolverr..." >> "$LOG"
cd /opt/flaresolverr && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Flaresolverr started." >> "$LOG"

# ── Done ──────────────────────────────────────────────────────────────────────
echo "[$(date)] ============================================" >> "$LOG"
echo "[$(date)] All services started." >> "$LOG"
echo "[$(date)] ============================================" >> "$LOG"