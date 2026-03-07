# Arr Stack Setup Instructions

## Complete step-by-step guide for configuring the *arr stack after running `setup_arr_stack.sh`

---

## Table of Contents

1. [Overview](#1-overview)
2. [Architecture](#2-architecture)
3. [Running the Setup Script](#3-running-the-setup-script)
4. [Configure Prowlarr](#4-configure-prowlarr)
5. [Configure Radarr](#5-configure-radarr)
6. [Configure Radarr 4K](#6-configure-radarr-4k)
7. [Configure Sonarr](#7-configure-sonarr)
8. [Configure Sonarr 4K](#8-configure-sonarr-4k)
9. [Configure Decypharr](#9-configure-decypharr)
10. [Configure Overseerr](#10-configure-overseerr)
11. [Configure Pulsarr](#11-configure-pulsarr)
12. [NZBDav Setup (Option 3 only)](#12-nzbdav-setup-option-3-only)
13. [FlareSolverr (Optional)](#13-flaresolverr-optional)
14. [Update Plex Libraries](#14-update-plex-libraries)
15. [Testing the Workflow](#15-testing-the-workflow)
16. [Boot & Startup Behaviour](#16-boot--startup-behaviour)
17. [Troubleshooting](#17-troubleshooting)
18. [Useful Commands](#18-useful-commands)
19. [File Locations](#19-file-locations)

---

## 1. Overview

This guide walks you through configuring the *arr stack that replaces `plex_debrid` with a more powerful, fully automated media management setup.

**Before (plex_debrid):**
```
You search → plex_debrid finds torrent → Real-Debrid downloads → Zurg mounts → Plex plays
```

**After (*arr stack with Decypharr):**
```
You add to Plex watchlist (Pulsarr) or request via Overseerr
    → Sonarr/Radarr searches via Prowlarr (Torrentio indexer)
    → Torrent sent to Decypharr (qBittorrent API mock)
    → Decypharr adds to Real-Debrid, waits for cache
    → Zurg exposes files via WebDAV → Rclone mounts to /mnt/remote/realdebrid/
    → Decypharr creates symlinks in /mnt/symlinks/
    → Sonarr/Radarr imports symlinks to /mnt/plex/
    → Plex reads from /mnt/plex/ and streams content
```

**With NZBDav (Option 3 — Usenet):**
```
Sonarr/Radarr searches via Prowlarr (Usenet indexers)
    → NZB sent to NZBDav (SABnzbd API mock)
    → NZBDav streams NZB via WebDAV (no downloading!)
    → Rclone sidecar mounts NZBDav WebDAV to /mnt/remote/nzbdav/
    → NZBDav creates symlinks in /mnt/remote/nzbdav/completed-symlinks/
    → Sonarr/Radarr imports symlinks to /mnt/plex/
    → Plex streams directly from Usenet provider
```

### Benefits over plex_debrid
- Proper file naming and organisation (Trash Guides compatible)
- Quality profiles with auto-upgrade (720p → 1080p → 4K)
- Separate 4K instances for movies and TV
- Custom formats (HDR, Atmos, Remux filtering)
- Multi-user request management via Overseerr
- Plex watchlist integration via Pulsarr
- Automatic torrent repair via Decypharr
- Optional Usenet streaming via NZBDav

---

## 2. Architecture

### Services & Ports

| Service | Port | URL | Purpose |
|---------|------|-----|---------|
| Prowlarr | 9696 | http://localhost:9696 | Indexer manager |
| Radarr | 7878 | http://localhost:7878 | Movie management (HD) |
| Radarr 4K | 7879 | http://localhost:7879 | Movie management (4K) |
| Sonarr | 8989 | http://localhost:8989 | TV show management (HD) |
| Sonarr 4K | 8990 | http://localhost:8990 | TV show management (4K) |
| Overseerr | 5055 | http://localhost:5055 | Request management (web UI) |
| Pulsarr | 3003 | http://localhost:3003 | Plex watchlist → Sonarr/Radarr |
| Decypharr | 8282 | http://localhost:8282 | qBittorrent mock for Real-Debrid |
| FlareSolverr | 8191 | http://localhost:8191 | Cloudflare bypass (optional) |
| NZBDav | 3000 | http://localhost:3000 | Usenet WebDAV streaming (Option 3) |
| Plex | 32400 | http://localhost:32400/web | Media server |
| Zurg | 9999 | http://localhost:9999 | Real-Debrid WebDAV |

> **⚠️ NETWORKING NOTE:** The `localhost` URLs above are for your **browser on the host machine only**. When configuring services to talk to **each other inside Docker** (e.g. Prowlarr → Sonarr, Overseerr → Radarr), you **MUST use container names**:
> `http://sonarr:8989`, `http://radarr:7878`, `http://prowlarr:9696`, `http://nzbdav:3000`, etc.
> Inside a container, `localhost` refers to that container itself — NOT the host.

### Directory Structure

```
/mnt
├── remote/
│   ├── realdebrid/          ← Rclone mount (all RD torrents via Zurg)
│   │   └── __all__/         ← Decypharr reads symlink targets from here
│   └── nzbdav/              ← Rclone sidecar mount (NZBDav WebDAV) [Option 3]
│       ├── .ids/            ← Streamable content (internal)
│       ├── completed-symlinks/ ← Symlinks for arr apps
│       ├── content/         ← Browsable content
│       └── nzbs/            ← NZB files
├── symlinks/
│   ├── radarr/              ← Decypharr movie symlinks
│   ├── radarr4k/            ← Decypharr 4K movie symlinks
│   ├── sonarr/              ← Decypharr TV symlinks
│   └── sonarr4k/            ← Decypharr 4K TV symlinks
└── plex/
    ├── Movies/              ← Radarr imports here (Plex library)
    ├── Movies - 4K/         ← Radarr 4K imports here
    ├── Movies - Anime/      ← Optional anime movies
    ├── TV/                  ← Sonarr imports here (Plex library)
    ├── TV - 4K/             ← Sonarr 4K imports here
    └── TV - Anime/          ← Optional anime shows
```

### How the Symlink Flow Works (Real-Debrid)

1. **You request** a movie/show via Overseerr or Pulsarr (Plex watchlist)
2. **Sonarr/Radarr** searches for releases via Prowlarr (Torrentio indexer)
3. **Sonarr/Radarr** sends the torrent/magnet to **Decypharr** (qBittorrent API)
4. **Decypharr**:
   - Adds the torrent to Real-Debrid
   - Waits for it to appear on the Zurg/Rclone mount at `/mnt/remote/realdebrid/__all__/`
   - Creates a **symlink** in `/mnt/symlinks/radarr/` pointing to the actual file
5. **Sonarr/Radarr** detects the completed download
6. **Sonarr/Radarr imports** it to `/mnt/plex/Movies/Movie Name (Year)/`
7. **Plex** detects the new file and adds it to your library

### How the Symlink Flow Works (NZBDav / Usenet)

1. **Sonarr/Radarr** searches via Prowlarr (Usenet indexers)
2. **Sonarr/Radarr** sends the NZB to **NZBDav** (SABnzbd API)
3. **NZBDav** streams the NZB via WebDAV — no downloading to disk
4. **Rclone sidecar** mounts NZBDav WebDAV to `/mnt/remote/nzbdav/`
5. **NZBDav** creates symlinks in `/mnt/remote/nzbdav/completed-symlinks/`
6. **Sonarr/Radarr** imports symlinks to `/mnt/plex/`
7. **Plex** streams directly from the Usenet provider

---

## 3. Running the Setup Script

```bash
chmod +x /root/setup.sh
sudo /root/setup.sh
```

Choose your option:
- **[1] Basic Setup** — Plex + plex_debrid only
- **[2] Arr Stack** — Full *arr stack with Decypharr (Real-Debrid)
- **[3] Arr Stack + NZBDav** — Everything in Option 2 + Usenet streaming

Or run scripts directly:
```bash
sudo /root/setup_arr_stack.sh      # Add *arr stack to existing base setup
sudo /root/setup_nzbdav.sh         # Add NZBDav to existing arr stack
```

The script auto-configures:
- Root folders for all arr apps
- Decypharr as qBittorrent download client in all arr apps
- Prowlarr connections to all arr apps
- Torrentio indexer in Prowlarr
- NZBDav as SABnzbd download client (Option 3)
- Startup script with correct boot order

**Wait ~30 seconds after the script finishes** for all containers to initialise, then proceed with the manual steps below.

---

## 4. Configure Prowlarr

**URL:** http://localhost:9696

### 4a. Initial Setup
1. Open Prowlarr in your browser
2. Set up authentication (Settings → General → Authentication)
3. Go to **Settings → General** and **copy the API Key** — you'll need this for Overseerr

### 4b. Verify Torrentio Indexer
The script auto-installs the Torrentio indexer. To verify:
1. Go to **Indexers**
2. You should see **Torrentio** listed
3. If not: `docker restart prowlarr` and check again
4. Click **Test** to verify it's working

### 4c. Add Usenet Indexers (Option 3 only)
1. Go to **Indexers → Add Indexer (+)**
2. Add your Usenet indexers (e.g. NZBGeek, NZBFinder, DrunkenSlug)
3. Enter your indexer API key and test each one

### 4d. Add FlareSolverr (if installed)
1. Go to **Settings → Indexers → Options**
2. Set **FlareSolverr URL** to `http://flaresolverr:8191`
3. Click **Test** then **Save**

> ⚠️ Use `http://flaresolverr:8191` (container name) — NOT `localhost:8191`

### 4e. Connect Prowlarr to Sonarr & Radarr
1. Go to **Settings → Apps**
2. Add each app:

**Add Radarr:**
```
Name:             Radarr
Sync Level:       Full Sync
Prowlarr Server:  http://prowlarr:9696
Radarr Server:    http://radarr:7878
API Key:          [from Radarr Settings → General]
```

**Add Radarr 4K:**
```
Name:             Radarr 4K
Prowlarr Server:  http://prowlarr:9696
Radarr Server:    http://radarr4k:7878
API Key:          [from Radarr 4K Settings → General]
```

**Add Sonarr:**
```
Name:             Sonarr
Prowlarr Server:  http://prowlarr:9696
Sonarr Server:    http://sonarr:8989
API Key:          [from Sonarr Settings → General]
```

**Add Sonarr 4K:**
```
Name:             Sonarr 4K
Prowlarr Server:  http://prowlarr:9696
Sonarr Server:    http://sonarr4k:8989
API Key:          [from Sonarr 4K Settings → General]
```

Click **Test** → **Save** for each.

---

## 5. Configure Radarr

**URL:** http://localhost:7878

### 5a. Get API Key
1. Go to **Settings → General**
2. Copy the **API Key** — needed for Prowlarr, Overseerr, Pulsarr, and Decypharr

### 5b. Verify Root Folder
1. Go to **Settings → Media Management → Root Folders**
2. Should already show `/mnt/plex/Movies` (auto-configured by script)
3. If missing, click **Add Root Folder** and enter `/mnt/plex/Movies`

### 5c. Verify Download Clients
1. Go to **Settings → Download Clients**
2. You should see **Decypharr [RD]** (qBittorrent, auto-configured)
3. *(Option 3)* You should also see **NZBDav** (SABnzbd, auto-configured)
4. If missing, see [Section 9](#9-configure-decypharr) to add manually

### 5d. Configure Naming (Recommended)
1. Go to **Settings → Media Management**
2. Enable **Rename Movies**
3. Recommended format (Trash Guides):
   ```
   Standard Movie Format:
   {Movie CleanTitle} {(Release Year)} {imdb-{ImdbId}} {edition-{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[Mediainfo VideoCodec]}{-Release Group}

   Movie Folder Format:
   {Movie CleanTitle} ({Release Year})
   ```

### 5e. Quality Profiles (Optional)
Follow [Trash Guides Quality Profiles](https://trash-guides.info/Radarr/radarr-setup-quality-profiles/) for recommended settings.

---

## 6. Configure Radarr 4K

**URL:** http://localhost:7879

Repeat the same steps as Radarr (Section 5) with these differences:

| Setting | Value |
|---------|-------|
| Root Folder | `/mnt/plex/Movies - 4K` |
| Quality Profile | Set to prefer 4K/2160p releases |

---

## 7. Configure Sonarr

**URL:** http://localhost:8989

### 7a. Get API Key
1. Go to **Settings → General**
2. Copy the **API Key**

### 7b. Verify Root Folder
1. Go to **Settings → Media Management → Root Folders**
2. Should already show `/mnt/plex/TV` (auto-configured)
3. If missing, add `/mnt/plex/TV`

### 7c. Verify Download Clients
1. Go to **Settings → Download Clients**
2. You should see **Decypharr [RD]** (auto-configured)
3. *(Option 3)* You should also see **NZBDav** (auto-configured)

### 7d. Configure Naming (Recommended)
1. Enable **Rename Episodes**
2. Recommended format (Trash Guides):
   ```
   Standard Episode Format:
   {Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Custom Formats }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}

   Series Folder Format:
   {Series TitleYear} {imdb-{ImdbId}}

   Season Folder Format:
   Season {season:00}
   ```

---

## 8. Configure Sonarr 4K

**URL:** http://localhost:8990

Repeat the same steps as Sonarr (Section 7) with these differences:

| Setting | Value |
|---------|-------|
| Root Folder | `/mnt/plex/TV - 4K` |
| Quality Profile | Set to prefer 4K/2160p releases |

---

## 9. Configure Decypharr

**URL:** http://localhost:8282

Decypharr acts as a **qBittorrent API mock** — Sonarr/Radarr think they're talking to qBittorrent, but Decypharr handles everything via Real-Debrid.

### 9a. First Login
1. Open `http://localhost:8282`
2. Set up login credentials (or skip if not required)

### 9b. Verify Real-Debrid Settings
1. Go to **Settings → Debrid**
2. Verify:
   - **Provider:** Real-Debrid
   - **API Key:** your RD token (auto-filled by script)
   - **Mount/Rclone Folder:** `/mnt/remote/realdebrid/__all__`

### 9c. Verify Download Settings
1. Go to **Settings → qBittorrent**
2. Verify **Download Folder:** `/mnt/symlinks`

### 9d. Enable Scheduled Repair
1. Go to **Settings → Repair**
2. Enable **Scheduled Repair:** Yes
3. **Interval:** 6h

### 9e. Verify Arr App Connections
The script auto-injects API keys into `config.json`. Verify in Decypharr:
1. Go to **Settings → Arrs**
2. Each arr app should be listed with its host and API key:
   - Radarr: `http://radarr:7878`
   - Radarr 4K: `http://radarr4k:7878`
   - Sonarr: `http://sonarr:8989`
   - Sonarr 4K: `http://sonarr4k:8989`

### 9f. Verify Download Client in Radarr/Sonarr
The script auto-adds Decypharr as a download client. To verify in each arr app:
1. Go to **Settings → Download Clients**
2. You should see **Decypharr [RD]** with:
   - **Type:** qBittorrent
   - **Host:** `decypharr`
   - **Port:** `8282`
   - **Username:** `http://radarr:7878` (the arr app's own URL)
   - **Password:** the arr app's API key

---

## 10. Configure Overseerr

**URL:** http://localhost:5055

### 10a. Initial Setup
1. Open Overseerr and click **Sign in with Plex**
2. Sign in with your Plex account
3. Select your Plex server from the list

### 10b. Add Radarr
1. Go to **Settings → Services → Radarr → Add Radarr Server**
2. Configure:
   ```
   Default Server:    Yes
   Server Name:       Radarr
   Hostname:          radarr
   Port:              7878
   API Key:           [Radarr API key]
   Quality Profile:   Select your preferred profile
   Root Folder:       /mnt/plex/Movies
   ```
3. Click **Test** → **Save**
4. Optionally add Radarr 4K (Hostname: `radarr4k`, Port: `7878`, Root: `/mnt/plex/Movies - 4K`)

### 10c. Add Sonarr
1. Go to **Settings → Services → Sonarr → Add Sonarr Server**
2. Configure:
   ```
   Default Server:    Yes
   Server Name:       Sonarr
   Hostname:          sonarr
   Port:              8989
   API Key:           [Sonarr API key]
   Quality Profile:   Select your preferred profile
   Root Folder:       /mnt/plex/TV
   ```
3. Click **Test** → **Save**
4. Optionally add Sonarr 4K (Hostname: `sonarr4k`, Port: `8989`, Root: `/mnt/plex/TV - 4K`)

---

## 11. Configure Pulsarr

**URL:** http://localhost:3003

Pulsarr monitors Plex watchlists and automatically sends content to Sonarr/Radarr. Users just add to their Plex watchlist — no extra app needed.

### 11a. Initial Setup
1. Open Pulsarr at `http://localhost:3003`
2. Follow the setup wizard
3. Enter your **Plex token**

### 11b. Add Sonarr
1. Go to **Settings → Sonarr**
2. Configure:
   ```
   URL:              http://sonarr:8989
   API Key:          [Sonarr API key]
   Quality Profile:  Select your preferred profile
   Root Folder:      /mnt/plex/TV
   ```
3. Optionally add Sonarr 4K (`http://sonarr4k:8989`)

### 11c. Add Radarr
1. Go to **Settings → Radarr**
2. Configure:
   ```
   URL:              http://radarr:7878
   API Key:          [Radarr API key]
   Quality Profile:  Select your preferred profile
   Root Folder:      /mnt/plex/Movies
   ```
3. Optionally add Radarr 4K (`http://radarr4k:7878`)

### 11d. Configure Watchlist Monitoring
1. Go to **Settings → Users**
2. Select which Plex users' watchlists to monitor
3. Configure routing rules (optional): route 4K content to 4K instances

### 11e. How It Works
- Users add a movie/show to their **Plex watchlist** (from any Plex app)
- Pulsarr detects the addition in real-time (Plex Pass) or within 5 minutes
- Content is automatically sent to the appropriate Sonarr/Radarr instance
- Once downloaded, it appears in Plex — no extra steps needed!

> **Pulsarr vs Overseerr:** Pulsarr works directly from the Plex app (watchlist), while Overseerr provides a separate Netflix-like web UI. You can use both — they complement each other.

---

## 12. NZBDav Setup (Option 3 only)

**URL:** http://localhost:3000

NZBDav streams Usenet content via WebDAV — nothing is downloaded to disk. Sonarr/Radarr see it as a SABnzbd download client.

### 12a. Create Admin Account
1. Open `http://localhost:3000`
2. Create your admin username and password on first login

### 12b. Configure Usenet Provider (Settings → Usenet)
```
Host:             your provider (e.g. news.newshosting.com)
Port:             563
Username:         your Usenet username
Password:         your Usenet password
Max Connections:  your provider's max (e.g. 100)
Use SSL:          Checked
```

### 12c. Configure WebDAV (Settings → WebDAV)
```
WebDAV Password:    the password you entered during setup
Enforce Read-Only:  Unchecked (recommended)
```

### 12d. Configure Rclone Mount (Settings → SABnzbd)
```
Rclone Mount Directory: /mnt/remote/nzbdav
```

### 12e. Configure Arr Integration (Settings → Radarr/Sonarr)
Add each arr app:

| App | Host | Port | API Key |
|-----|------|------|---------|
| Radarr | `http://radarr:7878` | 7878 | From Radarr Settings → General |
| Radarr 4K | `http://radarr4k:7878` | 7879 | From Radarr 4K Settings → General |
| Sonarr | `http://sonarr:8989` | 8989 | From Sonarr Settings → General |
| Sonarr 4K | `http://sonarr4k:8989` | 8990 | From Sonarr 4K Settings → General |

### 12f. Configure Queue Management Rules (Settings → Radarr/Sonarr)
Set these automatic queue management rules:
- **Remove, Blocklist, and Search:** No files found eligible for import / No audio tracks / Sample
- **Remove and Blocklist:** Not an upgrade for existing file
- **Remove:** Episode/Movie file already imported

### 12g. Verify NZBDav Download Client in Radarr/Sonarr
1. Go to **Settings → Download Clients** in each arr app
2. You should see **NZBDav** (SABnzbd type, auto-configured)
3. Verify:
   - **Host:** `nzbdav`
   - **Port:** `3000`
   - **API Key:** from NZBDav Settings → SABnzbd

### 12h. Verify NZBDav Mount
```bash
ls -la /mnt/remote/nzbdav/
# Should show: .ids  completed-symlinks  content  nzbs
```

---

## 13. FlareSolverr (Optional)

FlareSolverr bypasses Cloudflare challenges for Prowlarr indexers.

### 13a. Install
Add to `/opt/arr-stack/docker-compose.yml` under `services:`:

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

### 13b. Configure in Prowlarr
1. Go to **Settings → Indexers → Options**
2. Set **FlareSolverr URL** to `http://flaresolverr:8191`
3. Click **Test** then **Save**

> ⚠️ Use `http://flaresolverr:8191` (container name) — NOT `localhost:8191`

---

## 14. Update Plex Libraries

### Remove Old Libraries (if upgrading from Basic setup)
1. Open Plex: http://localhost:32400/web
2. Go to **Settings → Manage → Libraries**
3. Remove any libraries pointing to `/mnt/zurg/movies` or `/mnt/zurg/shows`

### Add New Libraries

| Library Name | Type | Path |
|-------------|------|------|
| Movies | Movies | `/mnt/plex/Movies` |
| Movies - 4K | Movies | `/mnt/plex/Movies - 4K` |
| Movies - Anime | Movies | `/mnt/plex/Movies - Anime` |
| TV Shows | TV Shows | `/mnt/plex/TV` |
| TV Shows - 4K | TV Shows | `/mnt/plex/TV - 4K` |
| TV Shows - Anime | TV Shows | `/mnt/plex/TV - Anime` |

### Plex Settings
For each library:
- ✅ **Scan my Library Automatically**
- ✅ **Run a partial scan when changes are detected**
- ❌ **Enable video preview thumbnails** (disable)

Under **Settings → Scheduled Tasks:**
- ❌ **Perform extensive media analysis during maintenance** (disable)

---

## 15. Testing the Workflow

### Test 1: Search in Radarr
1. Open Radarr (http://localhost:7878)
2. Click **Add New** → search for a popular movie
3. Add it and click **Search Monitored**
4. Watch the **Activity** tab — it should:
   - Find releases via Prowlarr/Torrentio
   - Send to Decypharr (qBittorrent)
   - Decypharr adds to Real-Debrid
   - Symlink created in `/mnt/symlinks/radarr/`
   - Radarr imports to `/mnt/plex/Movies/`

### Test 2: Check Decypharr Logs
```bash
docker logs decypharr --tail 50 -f
```
You should see:
- Torrent received
- Real-Debrid cache check
- Symlink created
- Import notification sent

### Test 3: Verify Symlinks
```bash
# Check symlinks exist
ls -la /mnt/symlinks/radarr/
ls -la /mnt/plex/Movies/

# Verify symlink targets are valid
find /mnt/plex/Movies -type l -exec ls -la {} \;
```

### Test 4: Check Plex
1. Open Plex
2. Verify the movie appears in your library
3. Try playing it — it should stream instantly

### Test 5: NZBDav (Option 3)
```bash
# Check NZBDav is healthy
curl http://localhost:3000/health

# Check mount is ready
ls -la /mnt/remote/nzbdav/

# Check Rclone sidecar logs
docker logs nzbdav_rclone --tail 50
```

---

## 16. Boot & Startup Behaviour

The setup script installs a `/root/startup.sh` that runs at boot via cron (`@reboot`). It starts all services in the correct order:

```
1. /mnt set as shared mount (required for rshared propagation)
2. Zurg + Rclone started (Real-Debrid)
3. Wait for Zurg healthy + /mnt/remote/realdebrid ready
4. NZBDav started (if installed)
5. Wait for NZBDav healthy
6. NZBDav rclone sidecar started
7. Wait for /mnt/remote/nzbdav ready  ← critical: arr-stack waits for this
8. *arr stack started (Radarr/Sonarr/Prowlarr/etc)
9. Decypharr started
```

> **Why this order matters:** Arr containers use `/mnt:/mnt:rshared` volume mounts. If the arr-stack starts before `/mnt/remote/nzbdav/` is mounted, Radarr/Sonarr will report "directory does not appear to exist inside the container". The startup script waits for the mount to be ready before starting arr containers.

### Check Startup Log
```bash
cat /var/log/startup_arr_stack.log
```

### Update Existing Startup Script
If you installed before this fix, run:
```bash
sudo bash /root/fix_startup.sh
```

### Manual Startup (after reboot issues)
```bash
sudo /root/startup.sh
```

---

## 17. Troubleshooting

### "Directory does not appear to exist inside the container" (NZBDav)
This means the arr container started before `/mnt/remote/nzbdav/` was mounted.

**Fix 1 — Restart arr-stack after NZBDav is mounted:**
```bash
# Verify NZBDav mount is ready
ls /mnt/remote/nzbdav/

# Then restart arr-stack
cd /opt/arr-stack && docker compose restart
```

**Fix 2 — Update startup script (permanent fix):**
```bash
sudo bash /root/fix_startup.sh
sudo reboot
```

**Fix 3 — Verify rshared is set:**
```bash
docker inspect radarr | grep -A5 "Mounts"
# Should show: /mnt:/mnt:rshared
```

### Decypharr not creating symlinks
```bash
# Check logs
docker logs decypharr --tail 100

# Verify RD mount is working
ls /mnt/remote/realdebrid/__all__/ | head -10

# Verify config
cat /opt/decypharr/config.json

# Check port type (must be string, not number)
grep '"port"' /opt/decypharr/config.json
# Should show: "port": "8282"  (with quotes around 8282)

# Fix if needed
sed -i 's/"port": 8282/"port": "8282"/g' /opt/decypharr/config.json
docker restart decypharr
```

### Prowlarr can't connect to Sonarr/Radarr
Use container names, not `localhost`:

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
| FlareSolverr | `http://flaresolverr:8191` |

Verify all containers are on the same network:
```bash
docker network inspect arr-stack | grep -A2 "Name"
```

### FlareSolverr "Connection refused" or "Resource temporarily unavailable"
```bash
# Connect FlareSolverr to arr-stack network
docker network connect arr-stack flaresolverr

# Test from Prowlarr container
docker exec prowlarr curl http://flaresolverr:8191
```
In Prowlarr, use `http://flaresolverr:8191` — NOT `localhost:8191`.

### NZBDav mount not working after reboot
```bash
# Check NZBDav is running
docker ps | grep nzbdav

# Check NZBDav health
curl http://localhost:3000/health

# Check rclone sidecar logs
docker logs nzbdav_rclone --tail 50

# Restart NZBDav stack
cd /opt/nzbdav && docker compose restart

# Check mount
ls -la /mnt/remote/nzbdav/
```

### Stale Rclone mount (Input/output error)
```bash
# For Real-Debrid mount
cd /opt/zurg-testing && docker compose down
sudo fusermount -uz /mnt/remote/realdebrid
sudo umount -l /mnt/remote/realdebrid 2>/dev/null || true
sudo mount --bind /mnt /mnt && sudo mount --make-shared /mnt
cd /opt/zurg-testing && docker compose up -d

# For NZBDav mount
cd /opt/nzbdav && docker compose down
sudo fusermount -uz /mnt/remote/nzbdav
sudo umount -l /mnt/remote/nzbdav 2>/dev/null || true
cd /opt/nzbdav && docker compose up -d
```

### Containers not starting after reboot
```bash
# Run startup script manually
sudo /root/startup.sh

# Check startup log
cat /var/log/startup_arr_stack.log

# Or start individually
cd /opt/zurg-testing && docker compose up -d
cd /opt/nzbdav && docker compose up -d          # Option 3 only
cd /opt/arr-stack && docker compose up -d
cd /opt/decypharr && docker compose up -d
```

### Permission issues
```bash
sudo chown -R 1000:1000 /mnt/plex /mnt/symlinks
sudo chown -R 1000:1000 /opt/{prowlarr,radarr,radarr4k,sonarr,sonarr4k,overseerr,pulsarr}
```

---

## 18. Useful Commands

### Container Management
```bash
# View all containers
docker ps

# View logs
docker logs radarr --tail 50 -f
docker logs sonarr --tail 50 -f
docker logs prowlarr --tail 50 -f
docker logs decypharr --tail 50 -f
docker logs pulsarr --tail 50 -f
docker logs nzbdav --tail 50 -f           # Option 3
docker logs nzbdav_rclone --tail 50 -f   # Option 3

# Restart stacks
cd /opt/zurg-testing && docker compose restart
cd /opt/arr-stack && docker compose restart
cd /opt/decypharr && docker compose restart
cd /opt/nzbdav && docker compose restart  # Option 3

# Update containers
cd /opt/arr-stack && docker compose pull && docker compose up -d
cd /opt/decypharr && docker compose pull && docker compose up -d
```

### Symlink Management
```bash
# Check symlinks
find /mnt/plex -type l -ls

# Find broken symlinks
find /mnt/plex -type l ! -exec test -e {} \; -print

# Count items in libraries
echo "Movies:     $(ls /mnt/plex/Movies/ 2>/dev/null | wc -l)"
echo "Movies 4K:  $(ls '/mnt/plex/Movies - 4K/' 2>/dev/null | wc -l)"
echo "TV:         $(ls /mnt/plex/TV/ 2>/dev/null | wc -l)"
echo "TV 4K:      $(ls '/mnt/plex/TV - 4K/' 2>/dev/null | wc -l)"
```

### Mount Checks
```bash
# Real-Debrid mount
ls /mnt/remote/realdebrid/__all__/ | head -20

# NZBDav mount (Option 3)
ls -la /mnt/remote/nzbdav/

# All mounts
mount | grep /mnt
```

### Health Check
```bash
/root/verify_setup.sh
```

---

## 19. File Locations

| Component | Config Path |
|-----------|-------------|
| Zurg config | `/opt/zurg-testing/config.yml` |
| Zurg compose | `/opt/zurg-testing/docker-compose.yml` |
| Rclone config | `/opt/zurg-testing/rclone.conf` |
| *arr stack compose | `/opt/arr-stack/docker-compose.yml` |
| Decypharr config | `/opt/decypharr/config.json` |
| Decypharr compose | `/opt/decypharr/docker-compose.yml` |
| NZBDav compose | `/opt/nzbdav/docker-compose.yml` |
| NZBDav config | `/opt/nzbdav/config/` |
| NZBDav rclone config | `/opt/nzbdav/rclone.conf` |
| Prowlarr config | `/opt/prowlarr/` |
| Prowlarr indexers | `/opt/prowlarr/Definitions/Custom/` |
| Radarr config | `/opt/radarr/` |
| Radarr 4K config | `/opt/radarr4k/` |
| Sonarr config | `/opt/sonarr/` |
| Sonarr 4K config | `/opt/sonarr4k/` |
| Overseerr config | `/opt/overseerr/` |
| Pulsarr config | `/opt/pulsarr/` |
| Plex libraries | `/mnt/plex/` |
| Symlinks | `/mnt/symlinks/` |
| RD mount | `/mnt/remote/realdebrid/` |
| NZBDav mount | `/mnt/remote/nzbdav/` |
| Startup script | `/root/startup.sh` |
| Startup log | `/var/log/startup_arr_stack.log` |

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────┐
│                    REQUEST FLOW                          │
│                                                         │
│  User → Overseerr/Pulsarr → Sonarr/Radarr → Prowlarr  │
│                          ↓                              │
│              Decypharr (qBittorrent API)                │
│                    ↓           ↓                        │
│             Real-Debrid     NZBDav (Usenet)             │
│                    ↓           ↓                        │
│           /mnt/remote/realdebrid/__all__/               │
│           /mnt/remote/nzbdav/completed-symlinks/        │
│                    ↓                                    │
│              Symlinks created                           │
│                    ↓                                    │
│           Sonarr/Radarr Import                          │
│                    ↓                                    │
│              /mnt/plex/...                              │
│                    ↓                                    │
│                Plex Plays                               │
└─────────────────────────────────────────────────────────┘

PORTS:
  Prowlarr:     9696    Radarr:       7878    Radarr4K:  7879
  Sonarr:       8989    Sonarr4K:     8990    Overseerr: 5055
  Pulsarr:      3003    Decypharr:    8282    NZBDav:    3000
  FlareSolverr: 8191    Plex:        32400    Zurg:      9999

BOOT ORDER (startup.sh):
  /mnt shared → Zurg+Rclone → NZBDav → NZBDav mount ready
  → arr-stack → Decypharr
```

---

*Based on [Sailarr's Guide to Plex + Real-Debrid](https://savvyguides.wiki/sailarrsguide/), [Trash Guides](https://trash-guides.info/), [Decypharr](https://github.com/sirrobot01/decypharr), and [NZBDav](https://github.com/nzbdav-dev/nzbdav)*