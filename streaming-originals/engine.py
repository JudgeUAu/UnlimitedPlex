"""
Streaming Originals - engine
Finds English-language streaming-service originals via TMDB and adds the
missing ones to Radarr (movies) and Sonarr (TV).
"""
import os
import json
import time
import threading
import xml.etree.ElementTree as ET
from datetime import date, datetime, timedelta

import requests

DATA_DIR = os.environ.get("DATA_DIR", "/data")
CFG_PATH = os.path.join(DATA_DIR, "config.json")
HIST_PATH = os.path.join(DATA_DIR, "history.json")
IDCACHE_PATH = os.path.join(DATA_DIR, "idcache.json")
TMDB = "https://api.themoviedb.org/3"
MASK = "********"

# TV originals use TMDB "networks" (reliable).
# Movies have no network concept on TMDB, so we use production companies
# (+ optionally "currently streaming on this provider") - a heuristic.
DEFAULT_SERVICES = {
    "netflix": {"label": "Netflix", "enabled": True,
                "tv_networks": [213], "movie_companies": [178464, 145174],
                "provider_id": 8, "movie_require_provider": False},
    "disney":  {"label": "Disney+", "enabled": True,
                "tv_networks": [2739], "movie_companies": [],
                "provider_id": 337, "movie_require_provider": True},
    "hbo":     {"label": "HBO / Max", "enabled": True,
                "tv_networks": [49, 3186], "movie_companies": [7429],
                "provider_id": 1899, "movie_require_provider": False},
    "prime":   {"label": "Prime Video", "enabled": True,
                "tv_networks": [1024], "movie_companies": [210099, 20580],
                "provider_id": 9, "movie_require_provider": True},
    "apple":   {"label": "Apple TV+", "enabled": True,
                "tv_networks": [2552], "movie_companies": [194232],
                "provider_id": 350, "movie_require_provider": True},
    "hulu":    {"label": "Hulu", "enabled": True,
                "tv_networks": [453], "movie_companies": [],
                "provider_id": 15, "movie_require_provider": True},
    "paramount": {"label": "Paramount+", "enabled": True,
                  "tv_networks": [4330], "movie_companies": [],
                  "provider_id": 2303, "movie_require_provider": True},
    "peacock": {"label": "Peacock", "enabled": True,
                "tv_networks": [3353], "movie_companies": [],
                "provider_id": 386, "movie_require_provider": True},
}

DEFAULT_TARGET = {
    "name": "", "type": "radarr", "enabled": False,
    "url": "", "api_key": "", "config_xml": "",
    "root_folder": "", "quality_profile_id": 0,
    # radarr only
    "min_availability": "released",
    # sonarr only
    "series_type": "standard", "monitor": "all",
    "search": True,
}

DEFAULT_CONFIG = {
    "tmdb_key": "",
    "region": "US",
    "english_only": True,
    "lookback_days": 365,          # 0 = whole back catalogue
    "max_pages": 3,                # TMDB pages (20 items each) per service
    "max_adds_per_run": 20,        # per target, per run
    "exclude_tv_genres": [10767, 10763],   # Talk, News
    "interval_hours": 0,           # 0 = manual only
    "auto_add": False,             # scheduled runs: False = preview only
    "add_movies": True,
    "add_tv": True,
    "services": DEFAULT_SERVICES,
    "targets": [
        dict(DEFAULT_TARGET, name="Radarr", type="radarr", enabled=True,
             url="http://radarr:7878", config_xml="/arr/radarr.xml"),
        dict(DEFAULT_TARGET, name="Sonarr", type="sonarr", enabled=True,
             url="http://sonarr:8989", config_xml="/arr/sonarr.xml"),
        dict(DEFAULT_TARGET, name="Radarr 4K", type="radarr", enabled=False,
             url="http://radarr4k:7878", config_xml="/arr/radarr4k.xml"),
        dict(DEFAULT_TARGET, name="Sonarr 4K", type="sonarr", enabled=False,
             url="http://sonarr4k:8989", config_xml="/arr/sonarr4k.xml"),
    ],
}


# ─── config ──────────────────────────────────────────────────────────────────
def _read_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default


def _write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp, path)


def load_config():
    saved = _read_json(CFG_PATH, {})
    cfg = json.loads(json.dumps(DEFAULT_CONFIG))
    for k, v in saved.items():
        if k == "services":
            for sk, sv in v.items():
                cfg["services"].setdefault(sk, {}).update(sv)
        else:
            cfg[k] = v
    cfg["targets"] = [dict(DEFAULT_TARGET, **t) for t in cfg["targets"]]
    return cfg


def save_config(new, old=None):
    """Save config; a masked secret means 'keep the existing value'."""
    old = old or load_config()
    if new.get("tmdb_key") == MASK:
        new["tmdb_key"] = old.get("tmdb_key", "")
    old_by_name = {t["name"]: t for t in old.get("targets", [])}
    for t in new.get("targets", []):
        if t.get("api_key") == MASK:
            t["api_key"] = old_by_name.get(t["name"], {}).get("api_key", "")
    _write_json(CFG_PATH, new)


def masked(cfg):
    out = json.loads(json.dumps(cfg))
    if out.get("tmdb_key"):
        out["tmdb_key"] = MASK
    for t in out["targets"]:
        if t.get("api_key"):
            t["api_key"] = MASK
    out["tmdb_key_from_env"] = bool(os.environ.get("TMDB_API_KEY"))
    return out


def tmdb_key(cfg):
    return cfg.get("tmdb_key") or os.environ.get("TMDB_API_KEY", "")


def target_key(t):
    if t.get("api_key"):
        return t["api_key"]
    p = t.get("config_xml")
    if p:
        try:
            return ET.parse(p).getroot().findtext("ApiKey") or ""
        except Exception:
            return ""
    return ""


# ─── TMDB ────────────────────────────────────────────────────────────────────
def tmdb_get(key, path, **params):
    params["api_key"] = key
    for attempt in range(3):
        r = requests.get(f"{TMDB}/{path}", params=params, timeout=20)
        if r.status_code == 429:
            time.sleep(2 + attempt * 2)
            continue
        r.raise_for_status()
        return r.json()
    raise RuntimeError("TMDB rate limited")


def discover_tv(cfg, key, svc, since, today):
    nets = "|".join(str(n) for n in svc["tv_networks"])
    if not nets:
        return []
    out = []
    for page in range(1, int(cfg["max_pages"]) + 1):
        p = {"with_networks": nets, "sort_by": "first_air_date.desc",
             "first_air_date.lte": today, "page": page}
        if cfg["english_only"]:
            p["with_original_language"] = "en"
        if since:
            p["first_air_date.gte"] = since
        if cfg["exclude_tv_genres"]:
            p["without_genres"] = ",".join(str(g) for g in cfg["exclude_tv_genres"])
        d = tmdb_get(key, "discover/tv", **p)
        for r in d.get("results", []):
            out.append({"kind": "tv", "tmdb_id": r["id"], "title": r.get("name"),
                        "date": r.get("first_air_date"), "service": svc["label"]})
        if page >= d.get("total_pages", 1):
            break
    return out


def discover_movies(cfg, key, svc, since, today):
    cos = "|".join(str(c) for c in svc["movie_companies"])
    if not cos:
        return []
    out = []
    for page in range(1, int(cfg["max_pages"]) + 1):
        p = {"with_companies": cos, "sort_by": "primary_release_date.desc",
             "primary_release_date.lte": today, "page": page}
        if cfg["english_only"]:
            p["with_original_language"] = "en"
        if since:
            p["primary_release_date.gte"] = since
        if svc.get("movie_require_provider") and svc.get("provider_id"):
            p.update({"watch_region": cfg["region"],
                      "with_watch_providers": svc["provider_id"],
                      "with_watch_monetization_types": "flatrate"})
        d = tmdb_get(key, "discover/movie", **p)
        for r in d.get("results", []):
            out.append({"kind": "movie", "tmdb_id": r["id"], "title": r.get("title"),
                        "date": r.get("release_date"), "service": svc["label"]})
        if page >= d.get("total_pages", 1):
            break
    return out


# ─── *arr ────────────────────────────────────────────────────────────────────
class Arr:
    def __init__(self, t):
        self.t = t
        self.base = t["url"].rstrip("/") + "/api/v3"
        self.h = {"X-Api-Key": target_key(t)}

    def get(self, path, **params):
        r = requests.get(f"{self.base}/{path}", headers=self.h, params=params, timeout=60)
        r.raise_for_status()
        return r.json()

    def post(self, path, body):
        r = requests.post(f"{self.base}/{path}", headers=self.h, json=body, timeout=60)
        if r.status_code >= 400:
            raise RuntimeError(f"{r.status_code}: {r.text[:200]}")
        return r.json()

    def info(self):
        status = self.get("system/status")
        return {"version": status.get("version"),
                "root_folders": [x["path"] for x in self.get("rootfolder")],
                "profiles": [{"id": p["id"], "name": p["name"]}
                             for p in self.get("qualityprofile")]}

    def defaults(self):
        """Resolve root folder / quality profile if left blank."""
        t = self.t
        root = t.get("root_folder")
        prof = int(t.get("quality_profile_id") or 0)
        if not root:
            roots = self.get("rootfolder")
            if not roots:
                raise RuntimeError("no root folder configured in " + t["name"])
            root = roots[0]["path"]
        if not prof:
            profs = self.get("qualityprofile")
            if not profs:
                raise RuntimeError("no quality profile in " + t["name"])
            prof = profs[0]["id"]
        return root, prof


# ─── runner ──────────────────────────────────────────────────────────────────
class Runner:
    def __init__(self):
        self.lock = threading.Lock()
        self.state = {"running": False, "dry": True, "log": [], "result": None,
                      "started": None, "finished": None}
        self.idcache = _read_json(IDCACHE_PATH, {})

    def log(self, msg, level="info"):
        self.state["log"].append({"t": datetime.now().strftime("%H:%M:%S"),
                                  "msg": msg, "level": level})
        self.state["log"] = self.state["log"][-600:]

    def start(self, dry):
        if not self.lock.acquire(blocking=False):
            return False
        threading.Thread(target=self._run, args=(dry,), daemon=True).start()
        return True

    def _run(self, dry):
        st = self.state
        st.update(running=True, dry=dry, log=[], result=None,
                  started=datetime.now().isoformat(), finished=None)
        result = {"targets": [], "candidates": {"movie": 0, "tv": 0}}
        try:
            self._do(dry, result)
        except Exception as e:
            self.log(f"Run failed: {e}", "danger")
            result["error"] = str(e)
        finally:
            st.update(running=False, result=result, finished=datetime.now().isoformat())
            self.lock.release()

    def tvdb_id(self, key, tmdb_id):
        k = str(tmdb_id)
        if k not in self.idcache:
            d = tmdb_get(key, f"tv/{tmdb_id}/external_ids")
            self.idcache[k] = d.get("tvdb_id")
            time.sleep(0.05)
        return self.idcache[k]

    def _do(self, dry, result):
        cfg = load_config()
        key = tmdb_key(cfg)
        if not key:
            raise RuntimeError("No TMDB API key set")
        today = date.today().isoformat()
        since = ""
        if int(cfg["lookback_days"]) > 0:
            since = (date.today() - timedelta(days=int(cfg["lookback_days"]))).isoformat()
        self.log(f"{'PREVIEW' if dry else 'LIVE RUN'} - lookback since {since or 'forever'}, "
                 f"english_only={cfg['english_only']}")

        movies, shows = {}, {}
        for sk, svc in cfg["services"].items():
            if not svc.get("enabled"):
                continue
            if cfg["add_tv"]:
                for c in discover_tv(cfg, key, svc, since, today):
                    shows.setdefault(c["tmdb_id"], c)
            if cfg["add_movies"]:
                for c in discover_movies(cfg, key, svc, since, today):
                    movies.setdefault(c["tmdb_id"], c)
            self.log(f"{svc['label']}: scanned")
        result["candidates"] = {"movie": len(movies), "tv": len(shows)}
        self.log(f"Candidates: {len(movies)} movies, {len(shows)} shows")

        for t in cfg["targets"]:
            if not t.get("enabled"):
                continue
            tr = {"name": t["name"], "type": t["type"], "added": [], "planned": [],
                  "skipped_existing": 0, "errors": []}
            result["targets"].append(tr)
            try:
                if t["type"] == "radarr":
                    self._radarr(cfg, t, list(movies.values()), dry, tr)
                else:
                    self._sonarr(cfg, key, t, list(shows.values()), dry, tr)
            except Exception as e:
                tr["errors"].append(str(e))
                self.log(f"[{t['name']}] error: {e}", "danger")

        _write_json(IDCACHE_PATH, self.idcache)
        self.log("Done.", "success")

    # -- radarr --
    def _radarr(self, cfg, t, cands, dry, tr):
        a = Arr(t)
        root, prof = a.defaults()
        have = {m["tmdbId"] for m in a.get("movie")}
        try:
            have |= {e["tmdbId"] for e in a.get("exclusions")}   # e.g. cleanup-tool blocklist
        except Exception:
            pass
        todo = [c for c in cands if c["tmdb_id"] not in have]
        tr["skipped_existing"] = len(cands) - len(todo)
        self.log(f"[{t['name']}] {len(todo)} new movies ({tr['skipped_existing']} already present/excluded)")
        for c in todo[: int(cfg["max_adds_per_run"])]:
            item = {"title": c["title"], "date": c["date"], "service": c["service"],
                    "tmdb_id": c["tmdb_id"]}
            if dry:
                tr["planned"].append(item)
                self.log(f"[{t['name']}] would add: {c['title']} ({c['date']}) via {c['service']}")
                continue
            try:
                look = a.get("movie/lookup/tmdb", tmdbId=c["tmdb_id"])
                body = dict(look)
                body.update({"qualityProfileId": prof, "rootFolderPath": root,
                             "monitored": True,
                             "minimumAvailability": t["min_availability"],
                             "addOptions": {"searchForMovie": bool(t["search"])}})
                a.post("movie", body)
                tr["added"].append(item)
                self._history(t["name"], "movie", item)
                self.log(f"[{t['name']}] ADDED: {c['title']} ({c['date']}) via {c['service']}", "success")
            except Exception as e:
                tr["errors"].append(f"{c['title']}: {e}")
                self.log(f"[{t['name']}] failed {c['title']}: {e}", "danger")
            time.sleep(0.3)

    # -- sonarr --
    def _sonarr(self, cfg, key, t, cands, dry, tr):
        a = Arr(t)
        root, prof = a.defaults()
        series = a.get("series")
        have_tvdb = {s.get("tvdbId") for s in series}
        have_tmdb = {s.get("tmdbId") for s in series if s.get("tmdbId")}
        try:
            for e in a.get("importlistexclusion"):
                have_tvdb.add(e.get("tvdbId"))
        except Exception:
            pass
        todo, no_tvdb = [], 0
        for c in cands:
            if c["tmdb_id"] in have_tmdb:
                continue
            tvdb = self.tvdb_id(key, c["tmdb_id"])
            if not tvdb:
                no_tvdb += 1
                continue
            if tvdb in have_tvdb:
                continue
            todo.append(dict(c, tvdb_id=tvdb))
        tr["skipped_existing"] = len(cands) - len(todo) - no_tvdb
        self.log(f"[{t['name']}] {len(todo)} new shows ({tr['skipped_existing']} present/excluded, "
                 f"{no_tvdb} without a TVDB id)")
        for c in todo[: int(cfg["max_adds_per_run"])]:
            item = {"title": c["title"], "date": c["date"], "service": c["service"],
                    "tmdb_id": c["tmdb_id"], "tvdb_id": c["tvdb_id"]}
            if dry:
                tr["planned"].append(item)
                self.log(f"[{t['name']}] would add: {c['title']} ({c['date']}) via {c['service']}")
                continue
            try:
                res = a.get("series/lookup", term=f"tvdb:{c['tvdb_id']}")
                if not res:
                    raise RuntimeError("not found in Sonarr lookup")
                body = dict(res[0])
                body.update({"qualityProfileId": prof, "rootFolderPath": root,
                             "monitored": True, "seasonFolder": True,
                             "seriesType": t["series_type"],
                             "addOptions": {"monitor": t["monitor"],
                                            "searchForMissingEpisodes": bool(t["search"]),
                                            "searchForCutoffUnmetEpisodes": False}})
                a.post("series", body)
                tr["added"].append(item)
                self._history(t["name"], "tv", item)
                self.log(f"[{t['name']}] ADDED: {c['title']} ({c['date']}) via {c['service']}", "success")
            except Exception as e:
                tr["errors"].append(f"{c['title']}: {e}")
                self.log(f"[{t['name']}] failed {c['title']}: {e}", "danger")
            time.sleep(0.3)

    def _history(self, target, kind, item):
        h = _read_json(HIST_PATH, [])
        h.insert(0, dict(item, target=target, kind=kind,
                         added_at=datetime.now().isoformat(timespec="seconds")))
        _write_json(HIST_PATH, h[:1000])


def scheduler_loop(runner):
    last = 0.0
    while True:
        time.sleep(30)
        try:
            cfg = load_config()
            hrs = float(cfg.get("interval_hours") or 0)
            if hrs > 0 and time.time() - last >= hrs * 3600:
                if runner.start(dry=not cfg.get("auto_add")):
                    last = time.time()
        except Exception:
            pass
