#!/bin/bash
# Streaming Originals - installer. Run as root on the server:
#   curl -fsSL https://raw.githubusercontent.com/JudgeUAu/UnlimitedPlex/beta/streaming-originals/install.sh | bash
set -e
DIR=/opt/streaming-originals
RAW=https://raw.githubusercontent.com/JudgeUAu/UnlimitedPlex/beta/streaming-originals
NET=${ARR_NETWORK:-arr-stack}
TZ_VAL=${TZ:-Australia/Sydney}

mkdir -p $DIR/templates $DIR/data
for f in Dockerfile app.py engine.py templates/index.html; do
  curl -fsSL "$RAW/$f" -o "$DIR/$f"
done

# Mount each instance's config.xml (read-only) so API keys are picked up automatically
MOUNTS=""
for pair in radarr:radarr radarr4k:radarr4k sonarr:sonarr sonarr4k:sonarr4k; do
  name=${pair%%:*}
  [ -f /opt/$name/config.xml ] && MOUNTS="$MOUNTS -v /opt/$name/config.xml:/arr/$name.xml:ro"
done

docker network inspect "$NET" >/dev/null 2>&1 || { echo "Docker network '$NET' not found. Run: docker network ls"; exit 1; }
docker build -q -t streaming-originals "$DIR" >/dev/null
docker rm -f streaming-originals >/dev/null 2>&1 || true
docker run -d --name streaming-originals --restart unless-stopped \
  --network "$NET" -p 7501:7501 -e TZ="$TZ_VAL" \
  ${TMDB_API_KEY:+-e TMDB_API_KEY="$TMDB_API_KEY"} \
  -v $DIR/data:/data $MOUNTS streaming-originals >/dev/null

IP=$(hostname -I | awk '{print $1}')
echo "Streaming Originals running: http://$IP:7501"
echo "Open Settings, add your TMDB key, enable targets, press Test, Save, then Preview."
