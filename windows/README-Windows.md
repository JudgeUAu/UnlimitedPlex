# UnlimitedPlex — Windows Installation Guide

> Set up a complete Plex + Real-Debrid media server on Windows using Docker Desktop + WSL2, with a graphical installer.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| **Windows** | Windows 10 (version 2004+) or Windows 11 |
| **Docker Desktop** | With WSL2 backend enabled |
| **WSL2 + Ubuntu** | Ubuntu distro installed in WSL2 |
| **RAM** | 8GB+ recommended |
| **Disk** | 50GB+ free space |
| **Real-Debrid** | Account + API token → https://real-debrid.com/apitoken |
| **Plex** | Account + token → https://plex.tv/claim |

---

## Step 1 — Install WSL2 + Ubuntu

Open **PowerShell as Administrator** and run:

```powershell
wsl --install
```

This installs WSL2 and Ubuntu automatically. Reboot when prompted.

After reboot, Ubuntu will open and ask you to create a username/password — set these up.

---

## Step 2 — Install Docker Desktop

1. Download from: https://www.docker.com/products/docker-desktop/
2. Install with default settings
3. During setup, make sure **"Use WSL2 instead of Hyper-V"** is checked
4. After install, open Docker Desktop and go to:
   - **Settings → Resources → WSL Integration**
   - Enable integration for **Ubuntu**
5. Click **Apply & Restart**

---

## Step 3 — Run the Installer

1. **Right-click** `Launch-UnlimitedPlex.bat` → **Run as Administrator**
2. The GUI will open automatically

---

## Using the GUI

### Setup Tab

1. **Check Prerequisites** — Click `🔍 Check Prerequisites` to verify Docker and WSL2 are ready
2. **Choose your option:**
   - **Option 1 — Basic:** Plex + Real-Debrid only (simplest)
   - **Option 2 — Arr Stack ⭐ (recommended):** Full media management with Sonarr, Radarr, Prowlarr, Overseerr, Decypharr
   - **Option 3 — Arr Stack + NZBDav:** Everything in Option 2 + Usenet streaming
3. **Enter your tokens:**
   - Real-Debrid API token (from real-debrid.com/apitoken)
   - Plex token (from plex.tv/claim)
   - Timezone (e.g. `America/New_York`, `Europe/London`, `Australia/Sydney`)
   - *(Option 3 only)* NZBDav WebDAV password
4. **Click `🚀 Install`** — installation takes 10–20 minutes

### Log Tab

- Shows real-time output from the installation
- Use **Save Log** to save the log if you need to troubleshoot

### Services Tab

- Click **Refresh Services** to see which containers are running
- Click **Open →** next to any service to open it in your browser

---

## Service URLs (after install)

| Service | URL |
|---------|-----|
| Plex | http://localhost:32400/web |
| Prowlarr | http://localhost:9696 |
| Radarr | http://localhost:7878 |
| Radarr 4K | http://localhost:7879 |
| Sonarr | http://localhost:8989 |
| Sonarr 4K | http://localhost:8990 |
| Overseerr | http://localhost:5055 |
| Pulsarr | http://localhost:3003 |
| Decypharr | http://localhost:8282 |
| NZBDav | http://localhost:3000 *(Option 3 only)* |

---

## How It Works

The Windows installer runs the same bash scripts as the Linux version, but inside your **WSL2 Ubuntu** environment. Docker Desktop bridges WSL2 containers to Windows, so all services are accessible at `localhost` from your Windows browser.

```
Windows GUI (UnlimitedPlex.ps1)
    → copies scripts to WSL2 Ubuntu
    → runs setup scripts inside WSL2
    → Docker containers start inside WSL2
    → ports forwarded to Windows localhost
    → access services from any Windows browser
```

---

## After Install — Manual Steps

After the installer finishes, you still need to configure a few things manually:

### 1. Configure Prowlarr (http://localhost:9696)
- Set up authentication
- Add Usenet indexers *(Option 3 only)*
- Connect to Sonarr & Radarr (use container names: `http://sonarr:8989`, `http://radarr:7878`)

### 2. Configure Decypharr (http://localhost:8282)
- Verify Real-Debrid API key is set
- Enable Scheduled Repair (Settings → Repair → 6h interval)

### 3. Configure Pulsarr (http://localhost:3003)
- Connect your Plex account
- Add Sonarr and Radarr
- Select which users' watchlists to monitor

### 4. Update Plex Libraries (http://localhost:32400/web)
- Add libraries pointing to:
  - Movies → `/mnt/plex/Movies`
  - TV Shows → `/mnt/plex/TV`

### 5. NZBDav *(Option 3 only)* (http://localhost:3000)
- Create admin account
- Configure Usenet provider
- Set Rclone Mount Directory to `/mnt/remote/nzbdav`

> See the full guide in `ARR_STACK_INSTRUCTIONS.md` for detailed step-by-step instructions.

---

## Troubleshooting

### "Docker Desktop not found"
Make sure Docker Desktop is installed and **running** (check the system tray icon).

### "WSL2 distro not found"
Run in PowerShell as Administrator:
```powershell
wsl --install
# or install Ubuntu specifically:
wsl --install -d Ubuntu
```

### "Installation failed" / script errors
1. Check the **Log tab** for the specific error
2. Make sure Docker Desktop has WSL2 integration enabled for Ubuntu:
   - Docker Desktop → Settings → Resources → WSL Integration → Enable Ubuntu
3. Try running the scripts manually in WSL2:
   ```bash
   wsl -d Ubuntu
   sudo bash /root/setup.sh
   ```

### Services not accessible after reboot
Docker Desktop should auto-start containers on Windows startup. If not:
1. Open WSL2: `wsl -d Ubuntu`
2. Run: `sudo /root/startup.sh`

### Port conflicts
If a port is already in use, check what's using it:
```powershell
netstat -ano | findstr :7878
```

---

## Updating

To update to the latest version, simply re-run `Launch-UnlimitedPlex.bat`. The installer will update scripts and restart containers without losing your configuration.

---

## Uninstalling

To remove everything:
```powershell
wsl -d Ubuntu -e bash -c "cd /opt/arr-stack && docker compose down; cd /opt/nzbdav && docker compose down; cd /opt/zurg-testing && docker compose down; cd /opt/decypharr && docker compose down"
```

To remove all data:
```powershell
wsl -d Ubuntu -e bash -c "rm -rf /opt/arr-stack /opt/nzbdav /opt/zurg-testing /opt/decypharr /opt/prowlarr /opt/radarr /opt/sonarr /opt/overseerr /opt/pulsarr"
```