# Plex + Real-Debrid Automated Setup

> One script to set up a complete Plex media server powered by Real-Debrid, with optional Sonarr/Radarr/Prowlarr and Usenet (NZBDav) integration.

---

## What's Included

| File | Purpose |
|------|---------|
| `setup.sh` | **🚀 Start here!** Unified launcher with setup menu |
| `setup_plex_debrid.sh` | Base setup — Docker, Zurg, Rclone, Plex, plex_debrid |
| `setup_arr_stack.sh` | *Arr stack upgrade — Sonarr, Radarr, Prowlarr, Overseerr, Decypharr |
| `setup_nzbdav.sh` | NZBDav setup — Usenet streaming via WebDAV |
| `configure_arrs.sh` | Standalone re-configuration script for arr apps |
| `verify_setup.sh` | Health check — verifies every component after setup or reboot |
| `README.md` | This documentation |

---

## Setup Options

| | Option 1: Basic | Option 2: Arr Stack | Option 3: Arr Stack + NZBDav |
|---|---|---|---|
| **Best for** | Simple, hands-off setup | Full media management | Debrid + Usenet combined |
| **Content source** | Real-Debrid only | Real-Debrid only | Real-Debrid + Usenet |
| **Content discovery** | plex_debrid (automated) | Sonarr + Radarr | Sonarr + Radarr |
| **Download client** | plex_debrid | Decypharr (qBittorrent mock) | Decypharr + NZBDav (SABnzbd mock) |
| **Request UI** | None | Overseerr + Pulsarr | Overseerr + Pulsarr |
| **Indexers** | Built into plex_debrid | Prowlarr + Torrentio | Prowlarr + Torrentio + Usenet indexers |
| **4K support** | Basic | Separate 4K instances | Separate 4K instances |
| **Complexity** | Low | Medium | Medium-High |

Option 2 and 3 run the base setup first, then add the *arr stack on top. Option 3 additionally installs NZBDav.

---

## Architecture

### Option 1: Basic Flow
```
You search in plex_debrid
    → plex_debrid adds to Real-Debrid
    → Zurg exposes files via WebDAV
    → Rclone mounts to /mnt/zurg/
    → Plex serves the content
```

### Option 2: Arr Stack Flow (Real-Debrid)
```
You add to Plex watchlist (or request via Overseerr)
    → Pulsarr syncs watchlist to Sonarr/Radarr
    → Sonarr/Radarr searches via Prowlarr (Torrentio indexer)
    → Torrent sent to Decypharr (qBittorrent API mock)
    → Decypharr adds to Real-Debrid, waits for cache
    → Zurg exposes files via WebDAV
    → Rclone mounts to /mnt/remote/realdebrid/
    → Decypharr creates symlinks in /mnt/symlinks/
    → Sonarr/Radarr imports symlinks to /mnt/plex/
    → Plex reads from /mnt/plex/ (symlinked content)
```

### Option 3: Arr Stack + NZBDav Flow (Real-Debrid + Usenet)
```
Torrent content (via Decypharr):
    → Same as Option 2 above

Usenet content (via NZBDav):
    → Sonarr/Radarr searches via Prowlarr (Usenet indexers)
    → NZB file sent to NZBDav (SABnzbd API mock)
    → NZBDav mounts NZB onto WebDAV (no downloading!)
    → Rclone sidecar mounts NZBDav WebDAV to /mnt/remote/nzbdav/
    → NZBDav creates symlinks in /mnt/remote/nzbdav/completed-symlinks/
    → Sonarr/Radarr imports symlinks to /mnt/plex/
    → Plex streams directly from Usenet provider via WebDAV
```

### Services & Ports

| Service | Port | URL | Setup |
|---------|------|-----|-------|
| Plex | 32400 | http://localhost:32400/web | All |
| Zurg | 9999 | http://localhost:9999 | All |
| Prowlarr | 9696 | http://localhost:9696 | Options 2 & 3 |
| Radarr | 7878 | http://localhost:7878 | Options 2 & 3 |
| Radarr 4K | 7879 | http://localhost:7879 | Options 2 & 3 |
| Sonarr | 8989 | http://localhost:8989 | Options 2 & 3 |
| Sonarr 4K | 8990 | http://localhost:8990 | Options 2 & 3 |
| Overseerr | 5055 | http://localhost:5055 | Options 2 & 3 |
| Pulsarr | 3003 | http://localhost:3003 | Options 2 & 3 |
| Decypharr | 8282 | http://localhost:8282 | Options 2 & 3 |
| FlareSolverr | 8191 | http://localhost:8191 | Options 2 & 3 (optional) |
| NZBDav | 3000 | http://localhost:3000 | Option 3 only |

> **⚠️ Docker Networking:** The `localhost` URLs above are for your **browser only**. When configuring services to talk to **each other** inside Docker (e.g., Prowlarr → Sonarr, Overseerr → Radarr), use **container names**:
> `http://sonarr:8989`, `http://radarr:7878`, `http://prowlarr:9696`, `http://nzbdav:3000`, etc.
> Inside a container, `localhost` refers to that container itself, not the host.

---

## Prerequisites

- **Ubuntu 22.04, 23.10, or 24.04** (local machine, VPS, or VM)
- **Root access** (`sudo`)
- A **Real-Debrid account** and your **API token** → https://real-debrid.com/apitoken
- A **Plex account** and your **Plex token** → https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/
- *(Option 3 only)* A **Usenet provider** account (e.g., Newshosting, UsenetExpress)
- *(Option 3 only)* **Usenet indexers** configured in Prowlarr (e.g., NZBGeek, NZBFinder)
- Internet access from the server

---

## Quick Start

### 1. Copy files to your server

```bash
# Option A – copy the zip via scp and extract
scp plex_debrid_setup.zip root@YOUR_SERVER_IP:/root/
ssh root@YOUR_SERVER_IP "cd /root && unzip -o plex_debrid_setup.zip"

# Option B – copy individual files
scp setup.sh setup_plex_debrid.sh setup_arr_stack.sh setup_nzbdav.sh verify_setup.sh root@YOUR_SERVER_IP:/root/
```

### 2. Make it executable

```bash
chmod +x /root/setup.sh
```

### 3. Run it

```bash
sudo /root/setup.sh
```

You'll see a menu:
- **[1] Basic Setup** — Plex + plex_debrid
- **[2] Arr Stack** — Plex + Sonarr/Radarr/Prowlarr/Overseerr/Decypharr
- **[3] Arr Stack + NZBDav** — Everything in Option 2 + Usenet streaming

> **Tip:** You can also run scripts directly:
> ```bash
> sudo ./setup_plex_debrid.sh    # Base setup only
> sudo ./setup_arr_stack.sh      # Add *arr stack to existing base setup
> sudo ./setup_nzbdav.sh         # Add NZBDav to existing arr stack
> ```

### 4. Interactive prompts

The script will ask for:
- Your **Real-Debrid API token**
- Your **Plex token** (can be skipped and set later)
- The **Zurg version** to use (default: `v0.9.3-final`)
- Whether this is a **remote server** (affects port-forwarding helpers)
- *(Option 3 only)* **WebDAV password** for NZBDav

Skip prompts with environment variables:
```bash
sudo RD_API_TOKEN="your_rd_token" PLEX_TOKEN="your_plex_token" /root/setup.sh
```

---

## What Each Setup Does

### Base Setup (All Options)

1. **System update** — `apt update && apt upgrade`, installs essential tools (git, curl, screen, inotify-tools, fuse3)
2. **Docker** — Detects and removes Snap Docker (incompatible with FUSE mounts), installs Docker CE via official apt repo
3. **Zurg & Rclone** — Pulls Docker image, writes `config.yml`, `docker-compose.yml`, `rclone.conf`, starts containers with health checks
4. **Plex Media Server** — Adds Plex repo, installs and enables `plexmediaserver`
5. **Python 3 & Pip** — Installs if not already present
6. **plex_debrid** — Clones repo, installs Python requirements
7. **Folder Monitor** — Creates `monitor_folders.sh` (inotify-based Plex library refresh)
8. **Startup Automation** — Creates `startup.sh` with `@reboot` cron job
9. **SSH helpers** *(remote servers only)* — Generates `connect.bat` and `connect.sh`
10. **VPN / IP check** — Checks if your server IP is blocked by Real-Debrid

### Arr Stack Adds (Options 2 & 3)

1. **Updates Zurg config** — Enables `serve_from_rclone: true` for symlink workflow
2. **Directory structure** — Creates `/mnt/plex/`, `/mnt/symlinks/`, `/mnt/remote/realdebrid/`
3. **Updates Rclone mount** — Exposes `__all__` torrents at `/mnt/remote/realdebrid/`
4. **Deploys Docker containers** — Sonarr, Sonarr 4K, Radarr, Radarr 4K, Prowlarr, Overseerr, Pulsarr (all on `arr-stack` network)
5. **Deploys Decypharr** — qBittorrent API mock for Real-Debrid at `/opt/decypharr/`
6. **Installs Torrentio indexer** — Custom Prowlarr indexer for debrid-cached torrents
7. **Auto-configures arr apps** — Adds root folders, download clients, and Prowlarr connections via API
8. **Updates startup script** — Adds all new services to boot automation

### NZBDav Adds (Option 3 only)

1. **Creates directories** — `/opt/nzbdav/config` and `/mnt/remote/nzbdav/` mount point
2. **Generates Rclone config** — Auto-obscures WebDAV password for Rclone
3. **Deploys NZBDav container** — WebDAV streaming server at port 3000
4. **Deploys Rclone sidecar** — Mounts NZBDav WebDAV to `/mnt/remote/nzbdav/` with optimized streaming flags
5. **Connects to arr-stack network** — Allows Sonarr/Radarr to reach NZBDav by hostname
6. **Auto-configures arr apps** — Adds NZBDav as SABnzbd download client to all arr apps

---

## After Setup: Basic (Option 1)

### Step 1 — Connect to Plex (remote server only)

```bash
# Windows
connect.bat

# Linux / Mac
bash connect.sh
```

### Step 2 — Set up Plex

1. Open `http://localhost:32400/web`
2. Sign in with your Plex account
3. Add libraries:
   - **Movies** → `/mnt/zurg/movies`
   - **TV Shows** → `/mnt/zurg/shows`
4. Configure settings:
   - ✅ Enable "Scan my Library Automatically"
   - ✅ Enable "Run a partial scan when changes are detected"
   - ❌ Disable "Enable video preview thumbnails"
   - ❌ Disable "Perform extensive media analysis" (Scheduled Tasks)

### Step 3 — First-time plex_debrid setup

```bash
screen -S pd
cd ~/plex_debrid && python3 main.py
```

Follow the wizard, then detach: `Ctrl+A, D`

---

## After Setup: Arr Stack (Options 2 & 3)

> **Full step-by-step guide:** See `ARR_STACK_INSTRUCTIONS.md` for detailed configuration of every service.

### Step 1 — Configure Prowlarr (http://localhost:9696)

1. Set up authentication (Settings → General)
2. Add **Torrentio** indexer (auto-installed at `/opt/prowlarr/Definitions/Custom/torrentio.yml`)
3. *(Option 3)* Add your **Usenet indexers** (NZBGeek, NZBFinder, etc.)
4. Connect to Sonarr & Radarr (Settings → Apps):

   | App | Prowlarr Server | App Server | API Key |
   |-----|----------------|------------|---------|
   | Radarr | `http://prowlarr:9696` | `http://radarr:7878` | From Radarr |
   | Radarr 4K | `http://prowlarr:9696` | `http://radarr4k:7878` | From Radarr 4K |
   | Sonarr | `http://prowlarr:9696` | `http://sonarr:8989` | From Sonarr |
   | Sonarr 4K | `http://prowlarr:9696` | `http://sonarr4k:8989` | From Sonarr 4K |

### Step 2 — Configure Radarr (http://localhost:7878)

1. Set authentication, add root folder `/mnt/plex/Movies`
2. Verify **Decypharr [RD]** download client is present (auto-configured)
3. *(Option 3)* Verify **NZBDav** download client is present (auto-configured)
4. Copy API key for Prowlarr

### Step 3 — Configure Sonarr (http://localhost:8989)

1. Set authentication, add root folder `/mnt/plex/TV`
2. Verify **Decypharr [RD]** download client is present (auto-configured)
3. *(Option 3)* Verify **NZBDav** download client is present (auto-configured)
4. Copy API key for Prowlarr

### Step 4 — Configure Pulsarr (http://localhost:3003)

1. Open the web UI and follow the setup wizard
2. Connect to Plex (enter your Plex token)
3. Add Sonarr (URL: `http://sonarr:8989`, API key from above)
4. Add Radarr (URL: `http://radarr:7878`, API key from above)
5. Select which Plex users' watchlists to monitor
6. Users just add to their Plex watchlist → Pulsarr handles the rest!

### Step 5 — Configure Overseerr (http://localhost:5055) *(Optional)*

1. Sign in with Plex account
2. Add Radarr server (Hostname: `radarr`, Port: `7878`)
3. Add Sonarr server (Hostname: `sonarr`, Port: `8989`)
4. Optionally add 4K servers (Hostname: `radarr4k`/`sonarr4k`)

### Step 6 — Update Plex Libraries

Point libraries to the symlink paths:
- **Movies** → `/mnt/plex/Movies`
- **Movies - 4K** → `/mnt/plex/Movies - 4K`
- **TV Shows** → `/mnt/plex/TV`
- **TV Shows - 4K** → `/mnt/plex/TV - 4K`

---

## After Setup: NZBDav (Option 3 only)

### Step 1 — Create Admin Account

Open `http://localhost:3000` and create your admin username and password.

### Step 2 — Configure Usenet Provider (Settings → Usenet)

- **Host:** your provider (e.g., `news.newshosting.com`)
- **Port:** `563`
- **Username / Password:** your Usenet credentials
- **Max Connections:** your provider's max (e.g., `100`)
- **Use SSL:** Checked

### Step 3 — Configure WebDAV (Settings → WebDAV)

- **Set WebDAV Password:** the password you entered during setup
- **Enforce Read-Only:** Unchecked (recommended)

### Step 4 — Configure Rclone Mount (Settings → SABnzbd)

- **Rclone Mount Directory:** `/mnt/remote/nzbdav`

### Step 5 — Configure Arr Integration (Settings → Radarr/Sonarr)

Add each arr app:

| App | Host | Port | API Key |
|-----|------|------|---------|
| Radarr | `http://radarr:7878` | 7878 | From Radarr Settings → General |
| Radarr 4K | `http://radarr4k:7878` | 7879 | From Radarr 4K Settings → General |
| Sonarr | `http://sonarr:8989` | 8989 | From Sonarr Settings → General |
| Sonarr 4K | `http://sonarr4k:8989` | 8990 | From Sonarr 4K Settings → General |

Configure **Automatic Queue Management** rules (Settings → Radarr/Sonarr):
- **Remove, Blocklist, and Search:** No files found eligible for import / No audio tracks / Sample
- **Remove and Blocklist:** Not an upgrade for existing file
- **Remove:** Episode/Movie file already imported

### Step 6 — Verify NZBDav Mount

```bash
ls -la /mnt/remote/nzbdav/
# Should show: .ids  completed-symlinks  content  nzbs
```

---

## FlareSolverr (Optional — for Cloudflare-protected indexers)

FlareSolverr bypasses Cloudflare challenges for Prowlarr indexers.

### Install

Add to your `/opt/arr-stack/docker-compose.yml`:

```yaml
  flaresolverr:
    image: ghcr.io/flaresolverr/flaresolverr:latest
    container_name: flaresolverr
    environment:
      - LOG_LEVEL=info
      - TZ=Etc/UTC
    ports:
      - "8191:8191"
    restart: unless-stopped
    networks:
      - arr-stack
```

Then start it:
```bash
cd /opt/arr-stack && docker compose up -d flaresolverr
```

### Connect to arr-stack network (if installed separately)

```bash
docker network connect arr-stack flaresolverr
```

### Configure in Prowlarr

1. Go to **Settings → Indexers → Options**
2. Set **FlareSolverr URL** to `http://flaresolverr:8191`
3. Click **Test** then **Save**

> **⚠️ Note:** Use `http://flaresolverr:8191` (container name), NOT `localhost:8191`. Inside Docker containers, `localhost` refers to the container itself.

---

## Zurg Configuration

### Directory Sorting (Movies vs Shows)

```yaml
directories:
  shows:
    group: media
    group_order: 10          # Evaluated FIRST
    filters:
      - has_episodes: true   # Intelligent episode detection
  movies:
    group: media
    group_order: 20          # Gets everything else
    only_show_the_biggest_file: true
    filters:
      - regex: /.*/          # Catch-all for remaining content
```

### Adding Anime Sorting (Optional)

```yaml
  anime:
    group: media
    group_order: 5
    filters:
      - and:
        - has_episodes: true
        - any_file_inside_regex: /^\[/
        - any_file_inside_not_regex: /s\d\de\d\d/i
```

---

## Directory Structure

### Basic Setup
```
/opt/zurg-testing/
├── config.yml              # Zurg configuration
├── docker-compose.yml      # Zurg + Rclone containers
├── rclone.conf             # Rclone configuration
└── plex_update.sh          # Plex library refresh hook

/mnt/zurg/                  # Rclone mount point
├── movies/
└── shows/
```

### Arr Stack (additional)
```
/opt/arr-stack/
└── docker-compose.yml      # Sonarr, Radarr, Prowlarr, Overseerr, Pulsarr

/opt/decypharr/
└── config.json             # Decypharr configuration

/opt/sonarr/                # Sonarr config
/opt/sonarr4k/              # Sonarr 4K config
/opt/radarr/                # Radarr config
/opt/radarr4k/              # Radarr 4K config
/opt/prowlarr/              # Prowlarr config + custom indexers
/opt/overseerr/             # Overseerr config
/opt/pulsarr/               # Pulsarr config

/mnt/remote/realdebrid/     # Rclone mount (__all__ torrents)
/mnt/symlinks/
├── radarr/                 # Radarr symlinks
├── radarr4k/               # Radarr 4K symlinks
├── sonarr/                 # Sonarr symlinks
└── sonarr4k/               # Sonarr 4K symlinks
/mnt/plex/
├── Movies/
├── Movies - 4K/
├── TV/
└── TV - 4K/
```

### NZBDav (additional, Option 3)
```
/opt/nzbdav/
├── docker-compose.yml      # NZBDav + Rclone sidecar
├── config/                 # NZBDav config and database
└── rclone.conf             # Rclone config for NZBDav WebDAV

/mnt/remote/nzbdav/         # Rclone mount of NZBDav WebDAV
├── .ids/                   # Streamable content (internal)
├── completed-symlinks/     # Symlinks for arr apps
├── content/                # Browsable content
└── nzbs/                   # NZB files
```

---

## Verification

```bash
chmod +x /root/verify_setup.sh
/root/verify_setup.sh
```

---

## Troubleshooting

### Stale mount (Input/output error)

```bash
cd /opt/zurg-testing && docker compose down
sudo fusermount -uz /mnt/zurg
sudo umount -l /mnt/zurg
sudo rm -rf /mnt/zurg && sudo mkdir -p /mnt/zurg
sudo mount --bind /mnt /mnt
sudo mount --make-shared /mnt
docker compose up -d
```

### Decypharr symlinks not importing

Decypharr creates a nested directory structure that Radarr/Sonarr can't import. Fix by restarting the arr-stack:

```bash
cd /opt/arr-stack && docker compose restart
```

If the issue persists, check the symlink structure:
```bash
ls -laR /mnt/symlinks/radarr4k/
```

The symlink should point to a valid file in `/mnt/remote/realdebrid/__all__/`.

### Prowlarr can't connect to Sonarr/Radarr

**Use container names, not `localhost`:**

| App | URL inside Docker |
|-----|-------------------|
| Prowlarr | `http://prowlarr:9696` |
| Sonarr | `http://sonarr:8989` |
| Sonarr 4K | `http://sonarr4k:8989` |
| Radarr | `http://radarr:7878` |
| Radarr 4K | `http://radarr4k:7878` |
| Overseerr | `http://overseerr:5055` |
| Decypharr | `http://decypharr:8282` |
| NZBDav | `http://nzbdav:3000` |

Verify all containers are on the same network:
```bash
docker network inspect arr-stack | grep -A2 "Name"
```

### FlareSolverr "Connection refused" or "Resource temporarily unavailable"

FlareSolverr must be on the same Docker network as Prowlarr:

```bash
# Connect FlareSolverr to arr-stack network
docker network connect arr-stack flaresolverr

# Test from Prowlarr container
docker exec prowlarr curl http://flaresolverr:8191
```

In Prowlarr, use `http://flaresolverr:8191` — NOT `localhost:8191`.

### NZBDav mount not working

```bash
# Check NZBDav is healthy
curl http://localhost:3000/health

# Check Rclone sidecar logs
docker logs nzbdav_rclone --tail 50

# Check mount
ls -la /mnt/remote/nzbdav/

# Restart NZBDav stack
cd /opt/nzbdav && docker compose restart
```

### Decypharr port type error

If Decypharr logs show "cannot unmarshal number into Go struct field Config.port of type string":

```bash
sed -i 's/"port": 8282/"port": "8282"/g' /opt/decypharr/config.json
docker restart decypharr
```

### After reboot, mount not working

```bash
sudo mount --bind /mnt /mnt
sudo mount --make-shared /mnt
cd /opt/zurg-testing && docker compose restart
cd /opt/arr-stack && docker compose restart
cd /opt/nzbdav && docker compose restart  # Option 3 only
```

### Docker permission issues

```bash
sudo usermod -aG docker $USER
newgrp docker
sudo chgrp docker /var/run/docker.sock
sudo chmod g+rw /var/run/docker.sock
```

### Snap Docker (must remove)

```bash
sudo snap remove docker
curl -fsSL https://get.docker.com | sh
```

---

## Useful Commands

### Core Services
```bash
docker ps                                        # All containers
docker logs zurg-testing-zurg-1 --tail 50 -f     # Zurg logs
docker logs zurg-testing-rclone-1 --tail 50 -f   # Rclone logs
cd /opt/zurg-testing && docker compose restart    # Restart Zurg + Rclone
systemctl status plexmediaserver                  # Plex status
```

### Arr Stack
```bash
docker logs radarr --tail 50 -f                   # Radarr logs
docker logs sonarr --tail 50 -f                   # Sonarr logs
docker logs prowlarr --tail 50 -f                 # Prowlarr logs
docker logs decypharr --tail 50 -f                # Decypharr logs
docker logs pulsarr --tail 50 -f                  # Pulsarr logs
cd /opt/arr-stack && docker compose restart        # Restart all *arrs
```

### NZBDav
```bash
docker logs nzbdav --tail 50 -f                   # NZBDav logs
docker logs nzbdav_rclone --tail 50 -f            # NZBDav Rclone logs
cd /opt/nzbdav && docker compose restart           # Restart NZBDav
ls -la /mnt/remote/nzbdav/                        # Check mount
curl http://localhost:3000/health                  # Health check
```

### Health Check
```bash
/root/verify_setup.sh
```

---

## Security Notes

- **Real-Debrid API token**: Visible in `config.yml`. Restrict permissions:
  ```bash
  chmod 600 /opt/zurg-testing/config.yml
  chmod 600 /opt/decypharr/config.json
  ```
- **Plex token**: Visible in `config.yml` and `plex_update.sh`. Revoke by changing your Plex password.
- **Arr API keys**: Visible in each app's config. Regenerate in each app's Settings → General.
- **NZBDav WebDAV password**: Stored in `/opt/nzbdav/rclone.conf` (obscured). Change in NZBDav Settings → WebDAV.
- **Regenerate all tokens** if they were ever exposed in terminal output or logs.

---

## Credits

- [A Newbie guide for Plex+Real-Debrid using Zurg & Rclone](https://docs.google.com/document/d/114URAz5h5jarpo1xz4GyFUzRzoBnOKVQPxH0-2R5KC8)
- [Sailarr's Guide (Arr Stack + Symlinks)](https://savvyguides.wiki/sailarrsguide/)
- [Zurg Config v0.9 Wiki](https://github.com/debridmediamanager/zurg-testing/wiki/Config-v0.9)
- [Decypharr (qBittorrent mock)](https://github.com/sirrobot01/decypharr)
- [NZBDav (Usenet WebDAV streaming)](https://github.com/nzbdav-dev/nzbdav)
- [FlareSolverr (Cloudflare bypass)](https://github.com/FlareSolverr/FlareSolverr)
- [Prowlarr Torrentio Indexer](https://github.com/dreulavelle/Prowlarr-Indexers)