# UnlimitedPlex Beta — Modular Multi-Instance Setup

> A modular installer for Plex + Real-Debrid with selectable services and multiple library instances (e.g. Main, 4K, Kids).

---

## What's New in Beta

| Feature | Original | Beta |
|---------|----------|------|
| Multiple instances | ❌ | ✅ Main, 4K, Kids, Anime... |
| Service selection | Fixed | Choose what to install |
| Per-instance Radarr/Sonarr | ❌ | ✅ Separate ports per instance |
| Global Prowlarr | ✅ | ✅ Single shared indexer |
| Linux TUI | ❌ | ✅ whiptail interactive menu |
| Windows GUI | ✅ | ✅ Updated 5-tab WPF GUI |

---

## Files

| File | Purpose |
|------|---------|
| `setup_beta.sh` | **🚀 Linux auto-installer** — run with a JSON config |
| `setup_beta_tui.sh` | **🖥️ Linux TUI** — interactive whiptail menu, calls setup_beta.sh |
| `windows/UnlimitedPlex-Beta.ps1` | **🪟 Windows GUI** — 5-tab WPF installer |
| `windows/Launch-UnlimitedPlex-Beta.bat` | **🪟 Windows launcher** — double-click to start |

---

## Architecture

### Global Services (installed once, shared by all instances)

| Service | Port | Path | Notes |
|---------|------|------|-------|
| Plex Media Server | 32400 | native install | Always installed |
| Zurg + Rclone | 9999 | /opt/zurg-testing | Always installed |
| Decypharr | 8282 | /opt/decypharr | Always installed |
| Prowlarr | 9696 | /opt/arr-stack | Always installed — shared indexer |
| Tautulli | 8181 | /opt/tautulli | Optional |
| Pulsarr | 3003 | /opt/pulsarr | Optional |
| NZBDav | 3000 | /opt/nzbdav | Optional — Usenet streaming |

### Per-Instance Services (one set per instance, e.g. Main, 4K, Kids)

| Service | Base Port | Port Formula |
|---------|-----------|--------------|
| Radarr | 7878 | 7878 + (index × 100) |
| Sonarr | 8989 | 8989 + (index × 100) |

**Example with 3 instances:**

| Instance | Radarr | Sonarr | Plex Libraries | Symlinks |
|----------|--------|--------|----------------|----------|
| Main (0) | 7878 | 8989 | /mnt/plex/Main/{Movies,TV} | /mnt/symlinks/main_{radarr,sonarr} |
| 4K (1) | 7978 | 9089 | /mnt/plex/4K/{Movies,TV} | /mnt/symlinks/4k_{radarr,sonarr} |
| Kids (2) | 8078 | 9189 | /mnt/plex/Kids/{Movies,TV} | /mnt/symlinks/kids_{radarr,sonarr} |

### Directory Structure

```
/opt/zurg-testing/          Zurg + Rclone (global)
/opt/arr-stack/             ALL Radarr/Sonarr instances + Prowlarr (one compose file)
/opt/decypharr/             Decypharr (global)
/opt/tautulli/              Tautulli (optional global)
/opt/pulsarr/               Pulsarr (optional global)
/opt/nzbdav/                NZBDav + Rclone sidecar (optional global)

/mnt/remote/realdebrid/     Zurg rclone mount
/mnt/remote/nzbdav/         NZBDav rclone mount (if enabled)
/mnt/symlinks/<inst>_radarr/  Decypharr symlinks per Radarr instance
/mnt/symlinks/<inst>_sonarr/  Decypharr symlinks per Sonarr instance
/mnt/plex/<Label>/Movies/   Plex library per instance
/mnt/plex/<Label>/TV/       Plex library per instance
```

### Data Flow

```
You add to Plex watchlist (Pulsarr) or request via Overseerr
    → Pulsarr syncs to all Sonarr/Radarr instances
    → Sonarr/Radarr searches via Prowlarr (shared, port 9696)
    → Torrent sent to Decypharr (qBittorrent API mock)
    → Decypharr adds to Real-Debrid, waits for cache
    → Zurg exposes files via WebDAV → Rclone mounts to /mnt/remote/realdebrid/
    → Decypharr creates symlinks in /mnt/symlinks/<inst>_radarr/ or _sonarr/
    → Sonarr/Radarr imports symlinks to /mnt/plex/<Label>/
    → Plex reads from /mnt/plex/ and streams content
```

---

## Prerequisites

- **Ubuntu 22.04, 23.10, or 24.04** (or Windows 10/11 with WSL2 + Docker Desktop)
- **Root access** (`sudo`)
- A **Real-Debrid account** and your **API token** → https://real-debrid.com/apitoken
- A **Plex claim token** → https://www.plex.tv/claim *(expires in 4 minutes)*
- *(NZBDav only)* A **Usenet provider** account

---

## Linux — Quick Start

### One-liner from GitHub (recommended)

```bash
sudo bash -c "mkdir -p /tmp/unlimitedplex && \
  curl -fsSL https://raw.githubusercontent.com/JudgeUAu/UnlimitedPlex/beta/setup_beta.sh -o /tmp/unlimitedplex/setup_beta.sh && \
  curl -fsSL https://raw.githubusercontent.com/JudgeUAu/UnlimitedPlex/beta/setup_beta_tui.sh -o /tmp/unlimitedplex/setup_beta_tui.sh && \
  chmod +x /tmp/unlimitedplex/*.sh && bash /tmp/unlimitedplex/setup_beta_tui.sh"
```

This downloads both scripts and launches the interactive TUI installer.

### Manual (if you have the files locally)

```bash
sudo bash setup_beta_tui.sh
```

### Advanced — run directly with a config file

```bash
sudo bash setup_beta.sh --config /path/to/config.json
```

See [Config JSON Format](#config-json-format) below.

---

## Windows — Quick Start

1. Install WSL2: open PowerShell as Admin → `wsl --install`
2. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) with WSL2 backend
3. Right-click `windows/Launch-UnlimitedPlex-Beta.bat` → **Run as Administrator**
4. The GUI will open — follow the tabs

---

## Linux TUI Walkthrough

The TUI (`setup_beta_tui.sh`) guides you through:

1. **Real-Debrid API token** — from https://real-debrid.com/apitoken
2. **Plex claim token** — from https://www.plex.tv/claim
3. **Timezone** — e.g. `America/New_York`, `Europe/London`, `Australia/Sydney`
4. **Zurg version** — default: `v0.9.3-final`
5. **Optional global services** — choose from Tautulli, Pulsarr, NZBDav
6. **Instance builder** — add as many instances as you need (Main, 4K, Kids, etc.)
   - For each instance: choose a name/label and select Radarr and/or Sonarr
7. **Summary screen** — review ports and paths before confirming
8. **Auto-install** — calls `setup_beta.sh` with the generated config

---

## Windows GUI Walkthrough

The GUI (`UnlimitedPlex-Beta.ps1`) has 5 tabs:

| Tab | Purpose |
|-----|---------|
| **Instances** | Add/remove instances, select Radarr/Sonarr per instance |
| **Configuration** | Enter tokens, timezone, optional global services |
| **Install** | Review summary and start installation |
| **Status** | Check running containers, open service URLs |
| **Help** | Architecture reference and port guide |

**Always-on globals** (shown as info badges, cannot be deselected):
- Plex, Zurg, Decypharr, Prowlarr

**Optional globals** (checkboxes):
- Tautulli, Pulsarr, NZBDav

**Per-instance** (selected per instance card):
- Radarr, Sonarr

---

## Config JSON Format

The TUI and Windows GUI generate this automatically. You can also write it manually:

```json
{
  "rd_token": "YOUR_REAL_DEBRID_TOKEN",
  "plex_token": "YOUR_PLEX_CLAIM_TOKEN",
  "timezone": "America/New_York",
  "zurg_version": "v0.9.3-final",
  "nzbdav_password": "changeme",
  "instances": [
    { "name": "main",  "label": "Main",  "services": ["radarr", "sonarr"] },
    { "name": "4k",    "label": "4K",    "services": ["radarr", "sonarr"] },
    { "name": "kids",  "label": "Kids",  "services": ["radarr"] }
  ],
  "global_services": ["tautulli", "pulsarr", "nzbdav"]
}
```

**Notes:**
- `name` — lowercase, no spaces (used in container names and symlink paths)
- `label` — display name (used in Plex library paths)
- `services` — array of `"radarr"` and/or `"sonarr"` (Prowlarr is always global)
- `global_services` — any combination of `"tautulli"`, `"pulsarr"`, `"nzbdav"`

---

## After Install — Manual Configuration

### 1. Prowlarr (http://YOUR_IP:9696) — Global shared indexer

1. Set up authentication (Settings → General)
2. Add the **Torrentio** indexer for Real-Debrid cached torrents
3. *(NZBDav only)* Add your Usenet indexers (NZBGeek, NZBFinder, etc.)
4. Connect to **all** Radarr and Sonarr instances (Settings → Apps):

| App | Prowlarr Server | App Server | API Key |
|-----|----------------|------------|---------|
| Radarr [Main] | `http://prowlarr:9696` | `http://radarr_main:7878` | From Radarr |
| Radarr [4K] | `http://prowlarr:9696` | `http://radarr_4k:7978` | From Radarr 4K |
| Sonarr [Main] | `http://prowlarr:9696` | `http://sonarr_main:8989` | From Sonarr |
| Sonarr [4K] | `http://prowlarr:9696` | `http://sonarr_4k:9089` | From Sonarr 4K |

> **Docker networking:** Use container names (e.g. `http://radarr_main:7878`), NOT `localhost`, when configuring services to talk to each other inside Docker.

### 2. Radarr / Sonarr (per instance)

For each instance:
1. Set authentication
2. Verify root folder: `/mnt/plex/<Label>/Movies` (Radarr) or `/mnt/plex/<Label>/TV` (Sonarr)
3. Verify **Decypharr** download client is present (auto-configured)
4. *(NZBDav only)* Verify **NZBDav** download client is present
5. Copy API key for Prowlarr connection

### 3. Decypharr (http://YOUR_IP:8282) — Global

1. Settings → Debrid: verify Real-Debrid API key and mount path `/mnt/remote/realdebrid/__all__`
2. Settings → Repair: enable Scheduled Repair (interval: 6h)
3. The `arrs[]` array in `/opt/decypharr/config.json` is auto-populated with all Radarr/Sonarr instances

### 4. Pulsarr (http://YOUR_IP:3003) — Optional global

1. Connect to Plex (enter your Plex token)
2. Add **all** Sonarr instances
3. Add **all** Radarr instances
4. Select which Plex users' watchlists to monitor

### 5. Tautulli (http://YOUR_IP:8181) — Optional global

1. Connect to Plex Media Server
2. Configure notifications as desired

### 6. NZBDav (http://YOUR_IP:3000) — Optional global

1. Create admin account on first launch
2. Settings → Usenet: configure your Usenet provider
3. Settings → WebDAV: set WebDAV password (use the one you entered during setup)
4. Settings → Arr Integration: add all Radarr/Sonarr instances

### 7. Plex (http://YOUR_IP:32400/web)

Add libraries for each instance:
- **Movies** → `/mnt/plex/<Label>/Movies`
- **TV Shows** → `/mnt/plex/<Label>/TV`

Recommended settings:
- ✅ Enable "Scan my Library Automatically"
- ✅ Enable "Run a partial scan when changes are detected"
- ❌ Disable "Enable video preview thumbnails"
- ❌ Disable "Perform extensive media analysis"

---

## Service Links

After install, your service links are saved to `/root/unlimitedplex_links.txt`:

```bash
cat /root/unlimitedplex_links.txt
```

---

## Boot & Startup

The installer creates `/root/startup.sh` with a `@reboot` cron job. Services start in this order:

```
1. /mnt set as shared mount
2. Zurg + Rclone started → wait for healthy
3. NZBDav started (if enabled) → wait for healthy → rclone sidecar started
4. arr-stack started (all Radarr/Sonarr instances + Prowlarr)
5. Decypharr started
6. Tautulli started (if enabled)
7. Pulsarr started (if enabled)
```

Check startup log:
```bash
cat /var/log/unlimitedplex_startup.log
```

Run manually after reboot:
```bash
sudo bash /root/startup.sh
```

---

## Troubleshooting

### Services not starting after reboot
```bash
sudo bash /root/startup.sh
cat /var/log/unlimitedplex_startup.log
```

### Stale mount (Input/output error)
```bash
cd /opt/zurg-testing && docker compose down
sudo fusermount -uz /mnt/remote/realdebrid
sudo mount --bind /mnt /mnt && sudo mount --make-shared /mnt
cd /opt/zurg-testing && docker compose up -d
```

### Decypharr not creating symlinks
```bash
docker logs decypharr --tail 50
cat /opt/decypharr/config.json   # verify arrs[] has all instances
```

### Prowlarr can't connect to Radarr/Sonarr
Use container names inside Docker:

| Instance | Radarr URL | Sonarr URL |
|----------|-----------|-----------|
| Main | `http://radarr_main:7878` | `http://sonarr_main:8989` |
| 4K | `http://radarr_4k:7978` | `http://sonarr_4k:9089` |
| Kids | `http://radarr_kids:8078` | `http://sonarr_kids:9189` |

### Check all containers
```bash
docker ps
```

### Restart everything
```bash
cd /opt/zurg-testing && docker compose restart
cd /opt/arr-stack && docker compose restart
cd /opt/decypharr && docker compose restart
```

---

## Useful Commands

```bash
# View all running containers
docker ps

# Logs
docker logs zurg --tail 50 -f
docker logs decypharr --tail 50 -f
docker logs prowlarr --tail 50 -f
docker logs radarr_main --tail 50 -f
docker logs sonarr_main --tail 50 -f
docker logs radarr_4k --tail 50 -f

# Restart stacks
cd /opt/arr-stack && docker compose restart
cd /opt/decypharr && docker compose restart
cd /opt/zurg-testing && docker compose restart

# View service links
cat /root/unlimitedplex_links.txt

# View install log
cat /var/log/unlimitedplex_beta.log

# View startup log
cat /var/log/unlimitedplex_startup.log
```

---

## Credits

- [Zurg](https://github.com/debridmediamanager/zurg-testing) — Real-Debrid WebDAV server
- [Decypharr](https://github.com/sirrobot01/decypharr) — qBittorrent API mock for Real-Debrid
- [NZBDav](https://github.com/nzbdav-dev/nzbdav) — Usenet WebDAV streaming
- [Prowlarr](https://github.com/Prowlarr/Prowlarr) — Indexer manager
- [Pulsarr](https://github.com/jamcalli/Pulsarr) — Plex watchlist sync
- [Tautulli](https://github.com/Tautulli/Tautulli) — Plex analytics
- [Sailarr's Guide](https://savvyguides.wiki/sailarrsguide/) — Arr stack + symlinks
- [Trash Guides](https://trash-guides.info/) — Best practices