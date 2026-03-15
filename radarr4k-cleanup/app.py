#!/usr/bin/env python3
"""
Radarr 4K Cleanup - Web UI
A small Flask app that provides a browser-based button interface
to scan and remove movies with no known 4K release from Radarr 4K.
"""

import os
import json
import time
import threading
import requests
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from flask import Flask, render_template, jsonify, request, Response
import queue

app = Flask(__name__)

# ─── Config (from env vars with fallbacks) ────────────────────────────────────
RADARR_HOST    = os.environ.get("RADARR_HOST",    "http://radarr4k:7878")
RADARR_API_KEY = os.environ.get("RADARR_API_KEY", "")
TMDB_API_KEY   = os.environ.get("TMDB_API_KEY",   "")
TMDB_BASE      = "https://api.themoviedb.org/3"

# Global state
scan_state = {
    "running":   False,
    "progress":  0,
    "total":     0,
    "phase":     "idle",   # idle | scanning | confirming | deleting | done
    "results":   None,     # dict with keep/delete/uncertain/skip lists
    "log":       [],
    "started":   None,
    "finished":  None,
}
scan_lock = threading.Lock()
log_queue = queue.Queue()


# ─── Helpers ──────────────────────────────────────────────────────────────────

def get_api_key():
    """Return API key — env var first, then Radarr config.xml."""
    if RADARR_API_KEY:
        return RADARR_API_KEY
    try:
        tree = ET.parse("/config/config.xml")
        return tree.getroot().findtext("ApiKey") or ""
    except Exception:
        return ""


def radarr_get(endpoint, params=None):
    api_key = get_api_key()
    url     = f"{RADARR_HOST}/api/v3/{endpoint}"
    r = requests.get(url, headers={"X-Api-Key": api_key}, params=params, timeout=30)
    r.raise_for_status()
    return r.json()


def radarr_delete(movie_id, delete_files=False):
    api_key = get_api_key()
    url     = f"{RADARR_HOST}/api/v3/movie/{movie_id}"
    params  = {"deleteFiles": str(delete_files).lower(), "addImportExclusion": "true"}
    r = requests.delete(url, headers={"X-Api-Key": api_key}, params=params, timeout=30)
    r.raise_for_status()
    return r.status_code


def file_is_4k(movie_file):
    if not movie_file:
        return False
    q    = movie_file.get("quality", {}).get("quality", {})
    res  = q.get("resolution", 0)
    name = q.get("name", "").lower()
    return res >= 2160 or "2160" in name or "4k" in name or "uhd" in name


def tmdb_has_4k_release(tmdb_id):
    """
    Returns (has_4k: True/False/None, reason: str)
    True  = confirmed 4K exists
    False = confirmed NO 4K
    None  = uncertain
    """
    if not TMDB_API_KEY:
        return None, "No TMDB key configured"

    try:
        time.sleep(0.26)
        params = {"api_key": TMDB_API_KEY, "append_to_response": "watch/providers"}
        r = requests.get(f"{TMDB_BASE}/movie/{tmdb_id}", params=params, timeout=15)
        if r.status_code == 404:
            return None, "Not found on TMDB"
        r.raise_for_status()
        data = r.json()
    except Exception as e:
        return None, f"TMDB error: {e}"

    year_str   = (data.get("release_date") or "")[:4]
    year_int   = int(year_str) if year_str.isdigit() else 0
    budget     = data.get("budget",     0) or 0
    revenue    = data.get("revenue",    0) or 0
    popularity = data.get("popularity", 0) or 0
    vote_count = data.get("vote_count", 0) or 0
    status     = data.get("status",    "")

    # Not released yet
    if status in ("In Production", "Planned", "Pre-Production", "Post Production"):
        return None, f"Not yet released (status: {status})"

    # Too new for physical 4K release
    release_str = data.get("release_date", "") or ""
    if release_str:
        try:
            rel_date = datetime.strptime(release_str, "%Y-%m-%d").replace(tzinfo=timezone.utc)
            days_since = (datetime.now(timezone.utc) - rel_date).days
            if days_since < 90:
                return None, f"Only released {days_since} days ago — 4K disc may not exist yet"
        except Exception:
            pass

    if year_int == 0:
        return None, "Unknown release year"

    # Check streaming providers for 4K
    providers_data = data.get("watch/providers", {}).get("results", {})
    for country_code, country_data in providers_data.items():
        for category in ("flatrate", "buy", "rent"):
            for provider in country_data.get(category, []):
                pname = provider.get("provider_name", "").lower()
                if "4k" in pname or "uhd" in pname:
                    return True, f"4K available on {provider.get('provider_name')} ({country_code})"

    is_major = (budget > 10_000_000 or revenue > 10_000_000 or
                vote_count > 500 or popularity > 20)

    # Pre-UHD era (before 2016) + not major → no 4K
    if year_int < 2016 and not is_major:
        return False, (f"Pre-UHD era ({year_int}), not a major release "
                       f"(votes={vote_count}, popularity={popularity:.1f})")

    # Pre-2013 + obscure → definitely no 4K
    if year_int < 2013 and vote_count < 50 and popularity < 5:
        return False, (f"Pre-2013 obscure film "
                       f"(votes={vote_count}, popularity={popularity:.1f})")

    # Post-2016 + major → likely has 4K but uncertain
    if year_int >= 2016 and is_major:
        return None, (f"Post-2016 major release (votes={vote_count}, "
                      f"popularity={popularity:.1f}) — likely has 4K")

    # Post-2016 but indie/small
    if year_int >= 2016 and not is_major:
        return False, (f"{year_int} small/indie release "
                       f"(votes={vote_count}, popularity={popularity:.1f}, budget=${budget:,})")

    return None, f"Uncertain ({year_int}, votes={vote_count}, popularity={popularity:.1f})"


def log(msg, level="info"):
    entry = {"time": datetime.now().strftime("%H:%M:%S"), "msg": msg, "level": level}
    scan_state["log"].append(entry)
    log_queue.put(entry)


# ─── Background scan ──────────────────────────────────────────────────────────

def run_scan():
    with scan_lock:
        scan_state["running"]  = True
        scan_state["progress"] = 0
        scan_state["phase"]    = "scanning"
        scan_state["results"]  = None
        scan_state["log"]      = []
        scan_state["started"]  = datetime.now().isoformat()
        scan_state["finished"] = None

    results = {"keep": [], "delete": [], "uncertain": [], "skip": []}

    try:
        log("🔗 Connecting to Radarr 4K...")
        sys_status = radarr_get("system/status")
        log(f"✅ Connected — Radarr v{sys_status.get('version','?')}", "success")

        log("🎬 Fetching movie list...")
        movies = radarr_get("movie")
        total  = len(movies)
        scan_state["total"] = total
        log(f"✅ Found {total} movies", "success")

        if not TMDB_API_KEY:
            log("⚠️  No TMDB key — accuracy limited. Set TMDB_API_KEY env var.", "warning")

        for i, movie in enumerate(movies):
            scan_state["progress"] = i + 1
            title    = movie.get("title", "Unknown")
            year     = movie.get("year", 0)
            tmdb_id  = movie.get("tmdbId", 0)
            has_file = movie.get("hasFile", False)
            m_status = movie.get("status", "").lower()
            mfile    = movie.get("movieFile")

            # Already has 4K file
            if has_file and file_is_4k(mfile or {}):
                results["keep"].append({"movie": movie, "reason": "Already has 4K file"})
                log(f"✅ KEEP  — {title} ({year}) — has 4K file")
                continue

            # Not released yet
            if m_status == "announced":
                results["skip"].append({"movie": movie, "reason": f"Not yet released"})
                log(f"⏭  SKIP  — {title} ({year}) — not released")
                continue

            # TMDB check
            if TMDB_API_KEY and tmdb_id:
                has_4k, reason = tmdb_has_4k_release(tmdb_id)
                if has_4k is True:
                    results["keep"].append({"movie": movie, "reason": reason})
                    log(f"✅ KEEP  — {title} ({year}) — {reason}")
                elif has_4k is False:
                    results["delete"].append({"movie": movie, "reason": reason})
                    log(f"🗑  DELETE — {title} ({year}) — {reason}", "danger")
                else:
                    results["uncertain"].append({"movie": movie, "reason": reason})
                    log(f"❓ UNSURE — {title} ({year}) — {reason}", "warning")
            else:
                results["uncertain"].append({"movie": movie,
                    "reason": "No TMDB key — cannot determine 4K availability"})
                log(f"❓ UNSURE — {title} ({year}) — no TMDB key", "warning")

    except Exception as e:
        log(f"❌ Error during scan: {e}", "danger")
        scan_state["running"] = False
        scan_state["phase"]   = "error"
        return

    scan_state["results"]  = results
    scan_state["phase"]    = "confirming"
    scan_state["running"]  = False
    scan_state["finished"] = datetime.now().isoformat()

    log(f"✅ Scan complete — {len(results['delete'])} to delete, "
        f"{len(results['keep'])} keep, {len(results['uncertain'])} uncertain", "success")


def run_delete(delete_files=False):
    results = scan_state.get("results")
    if not results:
        return

    to_delete = results.get("delete", [])
    if not to_delete:
        scan_state["phase"] = "done"
        return

    scan_state["phase"]   = "deleting"
    scan_state["running"] = True
    deleted = []
    failed  = []

    log(f"🗑️  Starting deletion of {len(to_delete)} movies...", "danger")

    for item in to_delete:
        movie = item["movie"]
        title = movie["title"]
        year  = movie.get("year", "?")
        mid   = movie["id"]
        try:
            radarr_delete(mid, delete_files=delete_files)
            log(f"✅ Deleted & blocklisted: {title} ({year})", "success")
            deleted.append(movie)
        except Exception as e:
            log(f"❌ Failed to delete {title} ({year}): {e}", "danger")
            failed.append({"movie": movie, "error": str(e)})
        time.sleep(0.2)

    scan_state["running"]  = False
    scan_state["phase"]    = "done"
    scan_state["finished"] = datetime.now().isoformat()
    log(f"✅ Done — deleted {len(deleted)}, failed {len(failed)}", "success")


# ─── Routes ───────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html",
        radarr_host=RADARR_HOST,
        has_tmdb=bool(TMDB_API_KEY))


@app.route("/api/status")
def api_status():
    s = scan_state
    results_summary = None
    if s["results"]:
        r = s["results"]
        results_summary = {
            "keep":      [{"id": x["movie"]["id"], "title": x["movie"]["title"],
                           "year": x["movie"].get("year"), "reason": x["reason"]}
                          for x in r["keep"]],
            "delete":    [{"id": x["movie"]["id"], "title": x["movie"]["title"],
                           "year": x["movie"].get("year"), "tmdbId": x["movie"].get("tmdbId"),
                           "reason": x["reason"]}
                          for x in r["delete"]],
            "uncertain": [{"id": x["movie"]["id"], "title": x["movie"]["title"],
                           "year": x["movie"].get("year"), "tmdbId": x["movie"].get("tmdbId"),
                           "reason": x["reason"]}
                          for x in r["uncertain"]],
            "skip":      [{"id": x["movie"]["id"], "title": x["movie"]["title"],
                           "year": x["movie"].get("year"), "reason": x["reason"]}
                          for x in r["skip"]],
        }
    return jsonify({
        "running":  s["running"],
        "progress": s["progress"],
        "total":    s["total"],
        "phase":    s["phase"],
        "results":  results_summary,
        "started":  s["started"],
        "finished": s["finished"],
    })


@app.route("/api/log")
def api_log():
    return jsonify(scan_state["log"])


@app.route("/api/scan", methods=["POST"])
def api_scan():
    if scan_state["running"]:
        return jsonify({"error": "Scan already running"}), 409
    scan_state["phase"] = "idle"
    t = threading.Thread(target=run_scan, daemon=True)
    t.start()
    return jsonify({"started": True})


@app.route("/api/delete", methods=["POST"])
def api_delete():
    if scan_state["running"]:
        return jsonify({"error": "Operation already running"}), 409
    if scan_state["phase"] not in ("confirming",):
        return jsonify({"error": "No scan results to act on"}), 400

    data         = request.get_json() or {}
    delete_files = data.get("deleteFiles", False)

    t = threading.Thread(target=run_delete, args=(delete_files,), daemon=True)
    t.start()
    return jsonify({"started": True})


@app.route("/api/reset", methods=["POST"])
def api_reset():
    scan_state["running"]  = False
    scan_state["progress"] = 0
    scan_state["total"]    = 0
    scan_state["phase"]    = "idle"
    scan_state["results"]  = None
    scan_state["log"]      = []
    scan_state["started"]  = None
    scan_state["finished"] = None
    return jsonify({"reset": True})


@app.route("/api/config")
def api_config():
    """Test connectivity and return config status."""
    api_key = get_api_key()
    radarr_ok  = False
    radarr_ver = ""
    try:
        s = radarr_get("system/status")
        radarr_ok  = True
        radarr_ver = s.get("version", "?")
    except Exception as e:
        radarr_ver = str(e)

    tmdb_ok = False
    if TMDB_API_KEY:
        try:
            r = requests.get(f"{TMDB_BASE}/configuration",
                             params={"api_key": TMDB_API_KEY}, timeout=10)
            tmdb_ok = r.status_code == 200
        except Exception:
            pass

    return jsonify({
        "radarr_host":  RADARR_HOST,
        "radarr_ok":    radarr_ok,
        "radarr_ver":   radarr_ver,
        "api_key_set":  bool(api_key),
        "tmdb_key_set": bool(TMDB_API_KEY),
        "tmdb_ok":      tmdb_ok,
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7500, debug=False)