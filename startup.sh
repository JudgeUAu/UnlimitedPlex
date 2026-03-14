#!/bin/bash
# startup.sh – Full service startup for UnlimitedPlex
# Launched at boot via cron (@reboot)
# Services: Zurg, NZBDav, arr-stack, Decypharr, Overseerr,
#           Prowlarr, Pulsarr, Audiobookshelf, Bookshelf, Flaresolverr

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
echo "[$(date)] /mnt set as shared mount." >> "$LOG"

# ── Zurg + Rclone (Real-Debrid) ───────────────────────────────────────────────
# Unmount ALL stale realdebrid mounts (can pile up after crashes/restarts)
for i in $(seq 1 20); do
  fusermount -uz /mnt/remote/realdebrid 2>/dev/null || umount -l /mnt/remote/realdebrid 2>/dev/null || break
done

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
# Unmount ALL stale nzbdav mounts (can pile up after crashes/restarts)
for i in $(seq 1 20); do
  fusermount -uz /mnt/remote/nzbdav 2>/dev/null || umount -l /mnt/remote/nzbdav 2>/dev/null || break
done

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

# ── arr-stack (Radarr, Radarr4K, Sonarr, Sonarr4K, SonarrKids) ───────────────
echo "[$(date)] Starting arr-stack..." >> "$LOG"
cd /opt/arr-stack && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] arr-stack started." >> "$LOG"

# ── Prowlarr ──────────────────────────────────────────────────────────────────
echo "[$(date)] Starting Prowlarr..." >> "$LOG"
cd /opt/prowlarr && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Prowlarr started." >> "$LOG"

# ── Decypharr ─────────────────────────────────────────────────────────────────
echo "[$(date)] Starting Decypharr..." >> "$LOG"
cd /opt/decypharr && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Decypharr started." >> "$LOG"

# ── Overseerr ─────────────────────────────────────────────────────────────────
echo "[$(date)] Starting Overseerr..." >> "$LOG"
cd /opt/overseerr && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Overseerr started." >> "$LOG"

# ── Pulsarr ───────────────────────────────────────────────────────────────────
echo "[$(date)] Starting Pulsarr..." >> "$LOG"
cd /opt/pulsarr && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Pulsarr started." >> "$LOG"

# ── Flaresolverr ──────────────────────────────────────────────────────────────
echo "[$(date)] Starting Flaresolverr..." >> "$LOG"
cd /opt/flaresolverr && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Flaresolverr started." >> "$LOG"

# ── Audiobookshelf ────────────────────────────────────────────────────────────
echo "[$(date)] Starting Audiobookshelf..." >> "$LOG"
cd /opt/audiobookshelf && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Audiobookshelf started." >> "$LOG"

# ── Bookshelf (Audiobooks + Ebooks) ──────────────────────────────────────────
echo "[$(date)] Starting Bookshelf..." >> "$LOG"
cd /opt/bookshelf-audiobooks && docker compose up -d >> "$LOG" 2>&1
cd /opt/bookshelf-ebooks && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] Bookshelf started." >> "$LOG"

# ── Done ──────────────────────────────────────────────────────────────────────
echo "[$(date)] ============================================" >> "$LOG"
echo "[$(date)] All services started." >> "$LOG"
echo "[$(date)] ============================================" >> "$LOG"