# Sonarr + Radarr + Prowlarr + Blackhole Setup Instructions

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
9. [Update Blackhole .env with API Keys](#9-update-blackhole-env-with-api-keys)
10. [Configure Overseerr](#10-configure-overseerr)
10b. [Configure Pulsarr](#10b-configure-pulsarr)
11. [Update Plex Libraries](#11-update-plex-libraries)
12. [Testing the Workflow](#12-testing-the-workflow)
13. [Optional: Remove plex_debrid](#13-optional-remove-plex_debrid)
14. [Troubleshooting](#14-troubleshooting)
15. [Useful Commands](#15-useful-commands)
16. [File Locations](#16-file-locations)

---

## 1. Overview

This guide walks you through configuring the *arr stack that replaces `plex_debrid` with a more powerful setup:

**Before (plex_debrid):**
```
You search → plex_debrid finds torrent → Real-Debrid downloads → Zurg mounts → Plex plays
```

**After (*arr stack):**
```
You add to Plex watchlist (Pulsarr) or request via Overseerr → Sonarr/Radarr searches via Prowlarr → 
Blackhole checks Real-Debrid cache → Creates symlinks → 
Sonarr/Radarr imports & renames → Plex plays
```

### Benefits
- Proper file naming and organization (Trash Guides compatible)
- Quality profiles (auto-upgrade 720p → 1080p → 4K)
- Separate libraries for HD, 4K, Anime
- Custom formats (HDR, Atmos, Remux filtering)
- Multi-user request management via Overseerr
- Automatic torrent repair
- Better metadata matching

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
| Plex | 32400 | http://localhost:32400/web | Media server |
| Zurg | 9999 | http://localhost:9999 | Real-Debrid mount |

> **⚠️ NETWORKING NOTE:** The `localhost` URLs above are for accessing services **from your browser on the host machine**. When configuring services to talk to **each other** inside Docker (e.g., Prowlarr → Sonarr, Overseerr → Radarr), you **MUST use container names** instead:
> - `http://sonarr:8989`, `http://radarr:7878`, `http://prowlarr:9696`, etc.
> - `localhost` inside a container refers to that container itself, NOT the host.

### Directory Structure

```
/mnt
├── remote/
│   └── realdebrid/          ← Rclone mount (all RD torrents)
│       ├── __all__/         ← Blackhole reads from here
│       ├── movies/          ← Zurg sorted movies
│       └── shows/           ← Zurg sorted shows
├── symlinks/
│   ├── radarr/
│   │   ├── completed/       ← Blackhole puts movie symlinks here
│   │   └── processing/      ← Blackhole working directory
│   ├── radarr4k/
│   │   ├── completed/
│   │   └── processing/
│   ├── sonarr/
│   │   ├── completed/       ← Blackhole puts show symlinks here
│   │   └── processing/
│   └── sonarr4k/
│       ├── completed/
│       └── processing/
└── plex/
    ├── Movies/              ← Radarr imports here (Plex library)
    ├── Movies - 4K/         ← Radarr 4K imports here
    ├── Movies - Anime/      ← Optional anime movies
    ├── TV/                  ← Sonarr imports here (Plex library)
    ├── TV - 4K/             ← Sonarr 4K imports here
    └── TV - Anime/          ← Optional anime shows
```

### How the Symlink Flow Works

1. **You request** a movie/show via Overseerr (or manually in Sonarr/Radarr)
2. **Sonarr/Radarr** searches for releases via Prowlarr indexers
3. **Sonarr/Radarr** sends the `.torrent`/`.magnet` file to the Blackhole folder (`/mnt/symlinks/radarr/`)
4. **Blackhole script** picks it up and:
   - Sends the torrent to Real-Debrid
   - Checks if it's already cached (instant availability)
   - If not cached and `FAIL_IF_NOT_CACHED=true`, fails it → Sonarr/Radarr tries next release
   - If cached, waits for it to appear on the Zurg/Rclone mount
   - Creates a **symlink** from `/mnt/remote/realdebrid/__all__/[torrent]` → `/mnt/symlinks/radarr/completed/[torrent]`
5. **Sonarr/Radarr** detects the completed download in the watch folder
6. **Sonarr/Radarr imports** it: creates a hardlink/symlink to `/mnt/plex/Movies/Movie Name (Year)/Movie Name (Year).mkv`
7. **Plex** detects the new file and adds it to your library

---

## 3. Running the Setup Script

```bash
# On your server:
chmod +x /root/setup_arr_stack.sh
sudo /root/setup_arr_stack.sh
```

The script will:
- Auto-detect your Real-Debrid token and Plex token from existing config
- Create all directories
- Update Zurg config for symlink workflow
- Deploy all Docker containers
- Install Torrentio indexer for Prowlarr
- Configure Blackhole .env template

**Wait for all containers to start** (about 30 seconds), then proceed with the manual steps below.

---

## 4. Configure Prowlarr

**URL:** http://localhost:9696

### 4a. Initial Setup
1. Open Prowlarr in your browser
2. Set up authentication (username/password)
3. Go to **Settings → General**
4. **Copy the API Key** – you'll need this later

### 4b. Add Torrentio Indexer
1. Go to **Indexers → Add Indexer (+)**
2. Search for **"Torrentio"** (custom indexer installed by the script)
3. If Torrentio doesn't appear:
   - The custom definition file should be at `/opt/prowlarr/Definitions/Custom/torrentio.yml`
   - Restart Prowlarr: `docker restart prowlarr`
4. Configure Torrentio:
   - **Name:** Torrentio
   - Leave defaults or adjust as needed
5. Click **Test** then **Save**

### 4c. Add Additional Public Indexers (Optional)
1. Go to **Indexers → Add Indexer (+)**
2. Add any public indexers you want:
   - **1337x**
   - **RARBG** (if available)
   - **The Pirate Bay**
   - **EZTV** (for TV shows)
   - **Nyaa** (for anime)
3. Test each one and save

### 4d. Connect Prowlarr to Sonarr & Radarr
1. Go to **Settings → Apps**
2. Click **+** to add each app:

**Add Radarr:**
```
Name: Radarr
Sync Level: Full Sync
Prowlarr Server: http://prowlarr:9696
Radarr Server: http://radarr:7878
API Key: [Radarr's API key - get from Radarr Settings → General]
```
Click **Test** → **Save**

**Add Radarr 4K:**
```
Name: Radarr 4K
Sync Level: Full Sync
Prowlarr Server: http://prowlarr:9696
Radarr Server: http://radarr4k:7878
API Key: [Radarr 4K's API key]
```

**Add Sonarr:**
```
Name: Sonarr
Sync Level: Full Sync
Prowlarr Server: http://prowlarr:9696
Sonarr Server: http://sonarr:8989
API Key: [Sonarr's API key - get from Sonarr Settings → General]
```

**Add Sonarr 4K:**
```
Name: Sonarr 4K
Sync Level: Full Sync
Prowlarr Server: http://prowlarr:9696
Sonarr Server: http://sonarr4k:8989
API Key: [Sonarr 4K's API key]
```

---

## 5. Configure Radarr

**URL:** http://localhost:7878

### 5a. Get API Key
1. Go to **Settings → General**
2. **Copy the API Key** – save this for Blackhole and Prowlarr

### 5b. Set Root Folder
1. Go to **Settings → Media Management**
2. Scroll down to **Root Folders**
3. Click **Add Root Folder**
4. Enter: `/mnt/plex/Movies`
5. Click **OK**

### 5c. Configure Naming (Recommended)
1. Go to **Settings → Media Management**
2. Enable **Rename Movies**
3. Use the recommended naming scheme from [Trash Guides](https://trash-guides.info/Radarr/Radarr-recommended-naming-scheme/):
   ```
   Standard Movie Format:
   {Movie CleanTitle} {(Release Year)} {imdb-{ImdbId}} {edition-{Edition Tags}} {[Custom Formats]}{[Quality Full]}{[MediaInfo 3D]}{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[Mediainfo VideoCodec]}{-Release Group}
   
   Movie Folder Format:
   {Movie CleanTitle} ({Release Year})
   ```

### 5d. Add Blackhole Download Client
1. Go to **Settings → Download Clients**
2. Click **+** → Select **Torrent Blackhole**
3. Configure:
   ```
   Name:              Blackhole
   Enable:            Yes
   Torrent Folder:    /mnt/symlinks/radarr
   Watch Folder:      /mnt/symlinks/radarr/completed
   Read Only:         No
   ```
4. **⚠️ IMPORTANT:** Check the box **"Save Magnet Files"** and set extension to `.magnet`
   - This is critical because Torrentio provides magnet links, not .torrent files
   - Without this, the blackhole script will report "No torrent files found"
5. Under **Completed Download Handling:**
   - Enable **Remove Completed**
6. Click **Test** → **Save**

### 5e. Quality Profiles (Optional but Recommended)
1. Go to **Settings → Profiles**
2. Edit the default profile or create new ones
3. Recommended: Follow [Trash Guides Quality Profiles](https://trash-guides.info/Radarr/radarr-setup-quality-profiles/)

---

## 6. Configure Radarr 4K

**URL:** http://localhost:7879

Repeat the same steps as Radarr (Section 5) with these differences:

| Setting | Value |
|---------|-------|
| Root Folder | `/mnt/plex/Movies - 4K` |
| Torrent Folder | `/mnt/symlinks/radarr4k` |
| Watch Folder | `/mnt/symlinks/radarr4k/completed` |
| Quality Profile | Set to prefer 4K/2160p releases |

---

## 7. Configure Sonarr

**URL:** http://localhost:8989

### 7a. Get API Key
1. Go to **Settings → General**
2. **Copy the API Key**

### 7b. Set Root Folder
1. Go to **Settings → Media Management**
2. **Root Folders → Add Root Folder**
3. Enter: `/mnt/plex/TV`

### 7c. Configure Naming (Recommended)
1. Enable **Rename Episodes**
2. Use [Trash Guides naming scheme](https://trash-guides.info/Sonarr/Sonarr-recommended-naming-scheme/):
   ```
   Standard Episode Format:
   {Series TitleYear} - S{season:00}E{episode:00} - {Episode CleanTitle} [{Custom Formats }{Quality Full}]{[MediaInfo VideoDynamicRangeType]}{[Mediainfo AudioCodec}{ Mediainfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}
   
   Series Folder Format:
   {Series TitleYear} {imdb-{ImdbId}}
   
   Season Folder Format:
   Season {season:00}
   ```

### 7d. Add Blackhole Download Client
1. Go to **Settings → Download Clients**
2. Click **+** → **Torrent Blackhole**
3. Configure:
   ```
   Name:              Blackhole
   Enable:            Yes
   Torrent Folder:    /mnt/symlinks/sonarr
   Watch Folder:      /mnt/symlinks/sonarr/completed
   Read Only:         No
   ```
4. **⚠️ IMPORTANT:** Check the box **"Save Magnet Files"** and set extension to `.magnet`
   - Torrentio sends magnet links, not .torrent files — this setting is required
5. Enable **Remove Completed**
6. Click **Test** → **Save**

---

## 8. Configure Sonarr 4K

**URL:** http://localhost:8990

Repeat the same steps as Sonarr (Section 7) with these differences:

| Setting | Value |
|---------|-------|
| Root Folder | `/mnt/plex/TV - 4K` |
| Torrent Folder | `/mnt/symlinks/sonarr4k` |
| Watch Folder | `/mnt/symlinks/sonarr4k/completed` |
| Quality Profile | Set to prefer 4K/2160p releases |

---

## 9. Update Blackhole .env with API Keys

Now that you have all the API keys, update the Blackhole configuration:

```bash
nano /opt/blackhole/.env
```

Replace these placeholders with the actual API keys you copied:

```
SONARR_API_KEY=paste_sonarr_api_key_here
SONARR_API_KEY_4K=paste_sonarr4k_api_key_here
RADARR_API_KEY=paste_radarr_api_key_here
RADARR_API_KEY_4K=paste_radarr4k_api_key_here
OVERSEERR_API_KEY=paste_overseerr_api_key_here
```

Also verify these are correct:
```
PLEX_SERVER_MOVIE_LIBRARY_ID=1    ← Check your actual Plex library IDs
PLEX_SERVER_TV_SHOW_LIBRARY_ID=2  ← Check your actual Plex library IDs
```

**To find your Plex library IDs:**
```bash
curl -s "http://localhost:32400/library/sections?X-Plex-Token=YOUR_PLEX_TOKEN" | grep -oP 'key="\K\d+|title="\K[^"]+'
```

Save the file, then restart Blackhole:
```bash
cd /opt/blackhole && docker compose --profile blackhole down && docker compose --profile blackhole up -d
cd /opt/blackhole && docker compose --profile repair down && docker compose --profile repair up -d
```

---

## 10. Configure Overseerr

**URL:** http://localhost:5055

### 10a. Initial Setup
1. Open Overseerr and click **Sign in with Plex**
2. Sign in with your Plex account
3. Select your Plex server from the list

### 10b. Connect Plex
1. Configure your Plex server connection
2. Sync your Plex libraries

### 10c. Add Radarr
1. Go to **Settings → Services → Radarr**
2. Click **Add Radarr Server**
3. Configure:
   ```
   Default Server:    Yes
   Server Name:       Radarr
   Hostname:          radarr
   Port:              7878
   API Key:           [Radarr API key]
   Quality Profile:   Select your preferred profile
   Root Folder:       /mnt/plex/Movies
   ```
4. Click **Test** → **Save**
5. Optionally add Radarr 4K as a second server (non-default, Hostname: `radarr4k`, Port: `7878`)

### 10d. Add Sonarr
1. Go to **Settings → Services → Sonarr**
2. Click **Add Sonarr Server**
3. Configure:
   ```
   Default Server:    Yes
   Server Name:       Sonarr
   Hostname:          sonarr
   Port:              8989
   API Key:           [Sonarr API key]
   Quality Profile:   Select your preferred profile
   Root Folder:       /mnt/plex/TV
   ```
4. Click **Test** → **Save**
5. Optionally add Sonarr 4K as a second server (non-default, Hostname: `sonarr4k`, Port: `8989`)

### 10e. Get Overseerr API Key
1. Go to **Settings → General**
2. Copy the **API Key**
3. Add it to `/opt/blackhole/.env` as `OVERSEERR_API_KEY`

---

## 10b. Configure Pulsarr

**URL:** http://localhost:3003

Pulsarr monitors Plex watchlists and automatically sends content to Sonarr/Radarr. Users just add to their Plex watchlist — no extra app or login needed.

### 10b-1. Initial Setup
1. Open Pulsarr at `http://localhost:3003`
2. Follow the setup wizard

### 10b-2. Connect to Plex
1. Enter your **Plex token** (same one used during setup)
2. Pulsarr will connect to your Plex server and discover users

### 10b-3. Add Sonarr
1. Go to **Settings → Sonarr**
2. Configure:
   ```
   URL:              http://sonarr:8989
   API Key:          [Sonarr API key]
   Quality Profile:  Select your preferred profile
   Root Folder:      /mnt/plex/TV
   ```
3. Click **Test** → **Save**
4. Optionally add Sonarr 4K (`http://sonarr4k:8989`)

### 10b-4. Add Radarr
1. Go to **Settings → Radarr**
2. Configure:
   ```
   URL:              http://radarr:7878
   API Key:          [Radarr API key]
   Quality Profile:  Select your preferred profile
   Root Folder:      /mnt/plex/Movies
   ```
3. Click **Test** → **Save**
4. Optionally add Radarr 4K (`http://radarr4k:7878`)

### 10b-5. Configure Watchlist Monitoring
1. Go to **Settings → Users**
2. Select which Plex users' watchlists to monitor
3. Configure content routing rules (optional):
   - Route 4K content to 4K instances
   - Route by genre, user, language, etc.

### 10b-6. How It Works
- Users add a movie/show to their **Plex watchlist** (from any Plex app)
- Pulsarr detects the addition in real-time (Plex Pass) or within 5 minutes
- Content is automatically sent to the appropriate Sonarr/Radarr instance
- Once downloaded, it appears in Plex — no extra steps needed!

> **Pulsarr vs Overseerr:** Pulsarr works directly from the Plex app (watchlist), while Overseerr provides a separate Netflix-like web UI. You can use both — they complement each other.

---

## 11. Update Plex Libraries

### Remove Old Libraries
1. Open Plex: http://localhost:32400/web
2. Go to **Settings → Manage → Libraries**
3. Remove any libraries pointing to `/mnt/zurg/movies` or `/mnt/zurg/shows`

### Add New Libraries
Add these libraries:

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

## 12. Testing the Workflow

### Test 1: Search in Radarr
1. Open Radarr (http://localhost:7878)
2. Click **Add New** → Search for a popular movie
3. Add it and click **Search Monitored**
4. Watch the Activity tab – it should:
   - Find releases via Prowlarr/Torrentio
   - Send to Blackhole
   - Blackhole checks RD cache
   - Creates symlink
   - Radarr imports it

### Test 2: Check Blackhole Logs
```bash
docker logs blackhole --tail 50 -f
```
You should see:
- Torrent file detected
- Checking Real-Debrid cache
- Symlink created
- Import notification

### Test 3: Verify Symlinks
```bash
# Check if symlinks exist
ls -la /mnt/symlinks/radarr/completed/
ls -la /mnt/plex/Movies/

# Verify symlink targets
find /mnt/plex/Movies -type l -exec ls -la {} \;
```

### Test 4: Check Plex
1. Open Plex
2. Verify the movie appears in your library
3. Try playing it

---

## 13. Optional: Remove plex_debrid

Once you've confirmed the *arr stack is working, you can remove plex_debrid:

```bash
# Stop plex_debrid screen session
screen -X -S pd quit

# Stop folder monitor
screen -X -S monitor quit

# Remove plex_debrid
rm -rf ~/plex_debrid
rm -f /root/monitor_folders.sh

# Remove old cron entries if any
crontab -l | grep -v "plex_debrid" | crontab -
```

---

## 14. Troubleshooting

### Blackhole reports "No torrent files found"
**Most common cause:** The **"Save Magnet Files"** checkbox is not enabled in Radarr/Sonarr's Torrent Blackhole download client settings. Torrentio provides magnet links, not `.torrent` files, so you must:
1. Go to each arr app → **Settings → Download Clients** → Edit the Blackhole client
2. Check **"Save Magnet Files"** and set extension to `.magnet`
3. Click **Save**

### Blackhole not picking up torrents
```bash
# Check Blackhole logs
docker logs blackhole --tail 100

# Verify .env is correct
cat /opt/blackhole/.env | grep -E "(API_KEY|MOUNT|WATCH)"

# Check symlink directories exist
ls -la /mnt/symlinks/radarr/
ls -la /mnt/symlinks/sonarr/

# Restart Blackhole
cd /opt/blackhole && docker compose --profile blackhole restart
```

### "Not cached" errors
This means the torrent isn't available on Real-Debrid's cache. Options:
1. Wait and try again (popular torrents get cached quickly)
2. Set `BLACKHOLE_FAIL_IF_NOT_CACHED=false` in `.env` (will download uncached, slower)
3. Search for a different release in Sonarr/Radarr

### Symlinks broken / "file not found"
```bash
# Check if Rclone mount is working
ls /mnt/remote/realdebrid/__all__/

# If mount is stale, restart
cd /opt/zurg-testing && docker compose down
sudo fusermount -uz /mnt/remote/realdebrid
sudo mount --bind /mnt /mnt && sudo mount --make-shared /mnt
cd /opt/zurg-testing && docker compose up -d
```

### Sonarr/Radarr can't see files
Make sure all containers have `/mnt:/mnt` volume mapping. Check:
```bash
docker inspect radarr | grep -A5 "Mounts"
docker inspect sonarr | grep -A5 "Mounts"
docker inspect blackhole | grep -A5 "Mounts"
```

### Prowlarr can't connect to Sonarr/Radarr
**⚠️ IMPORTANT: Since all containers run on the same Docker network (`arr-stack`), you MUST use container names — NOT `localhost` or `127.0.0.1`.**

Inside a Docker container, `localhost` refers to the container itself, not the host machine. Use these URLs:

| App | URL to use inside Docker |
|-----|--------------------------|
| Prowlarr | `http://prowlarr:9696` |
| Sonarr | `http://sonarr:8989` |
| Sonarr 4K | `http://sonarr4k:8989` |
| Radarr | `http://radarr:7878` |
| Radarr 4K | `http://radarr4k:7878` |
| Overseerr | `http://overseerr:5055` |
| Pulsarr | `http://pulsarr:3003` |

**Only use `http://localhost:PORT` when accessing services from your browser on the host machine.**

If still failing, verify all containers are on the same network:
```bash
docker network inspect arr-stack | grep -A2 "Name"
```

### Containers not starting after reboot
```bash
# Run startup script manually
sudo /root/startup.sh

# Or start individually
cd /opt/zurg-testing && docker compose up -d
cd /opt/arr-stack && docker compose up -d
cd /opt/blackhole && docker compose --profile blackhole up -d
```

### Permission issues
```bash
# Fix ownership on all directories
sudo chown -R 1000:1000 /mnt/plex /mnt/symlinks
sudo chown -R 1000:1000 /opt/{prowlarr,radarr,radarr4k,sonarr,sonarr4k,overseerr,pulsarr}
```

---

## 15. Useful Commands

### Container Management
```bash
# View all containers
docker ps

# View specific logs
docker logs blackhole --tail 50 -f
docker logs radarr --tail 50 -f
docker logs sonarr --tail 50 -f
docker logs prowlarr --tail 50 -f
docker logs zurg --tail 50 -f
docker logs rclone --tail 50 -f

# Restart everything
cd /opt/zurg-testing && docker compose restart
cd /opt/arr-stack && docker compose restart
cd /opt/blackhole && docker compose --profile blackhole restart

# Stop everything
cd /opt/arr-stack && docker compose down
cd /opt/blackhole && docker compose --profile blackhole down
cd /opt/zurg-testing && docker compose down

# Update containers
cd /opt/arr-stack && docker compose pull && docker compose up -d
cd /opt/blackhole && docker compose --profile blackhole pull && docker compose --profile blackhole up -d
```

### Symlink Management
```bash
# Check symlinks
find /mnt/plex -type l -ls

# Find broken symlinks
find /mnt/plex -type l ! -exec test -e {} \; -print

# Count items in libraries
echo "Movies: $(ls /mnt/plex/Movies/ 2>/dev/null | wc -l)"
echo "TV: $(ls /mnt/plex/TV/ 2>/dev/null | wc -l)"
echo "Movies 4K: $(ls '/mnt/plex/Movies - 4K/' 2>/dev/null | wc -l)"
echo "TV 4K: $(ls '/mnt/plex/TV - 4K/' 2>/dev/null | wc -l)"
```

### Real-Debrid Mount
```bash
# Check mount
ls /mnt/remote/realdebrid/
ls /mnt/remote/realdebrid/__all__/ | head -20

# Check Zurg web interface
curl -s http://localhost:9999/http | head -20
```

---

## 16. File Locations

| Component | Config Path |
|-----------|-------------|
| Zurg config | `/opt/zurg-testing/config.yml` |
| Zurg compose | `/opt/zurg-testing/docker-compose.yml` |
| Rclone config | `/opt/zurg-testing/rclone.conf` |
| *arr stack compose | `/opt/arr-stack/docker-compose.yml` |
| Blackhole scripts | `/opt/blackhole/` |
| Blackhole config | `/opt/blackhole/.env` |
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
| Startup script | `/root/startup.sh` |
| Startup log | `/var/log/startup_arr_stack.log` |

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────┐
│                    REQUEST FLOW                          │
│                                                         │
│  User → Overseerr → Sonarr/Radarr → Prowlarr           │
│                          ↓                              │
│                    Torrent Blackhole                     │
│                          ↓                              │
│                  Blackhole Script                        │
│                    ↓           ↓                         │
│              Check RD Cache   Send to RD                │
│                    ↓                                    │
│              Create Symlink                             │
│                    ↓                                    │
│           Sonarr/Radarr Import                          │
│                    ↓                                    │
│              /mnt/plex/...                              │
│                    ↓                                    │
│                Plex Plays                               │
└─────────────────────────────────────────────────────────┘

PORTS:
  Prowlarr:  9696    Radarr:    7878    Radarr4K:  7879
  Sonarr:    8989    Sonarr4K:  8990    Overseerr: 5055
  Pulsarr:   3003
  Plex:      32400   Zurg:      9999
```

---

*Based on [A Sailarr's Guide to Plex + Real-Debrid](https://savvyguides.wiki/sailarrsguide/) and [westsurname/scripts](https://github.com/westsurname/scripts)*