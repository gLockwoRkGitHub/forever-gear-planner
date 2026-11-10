"""Weekly item database refresh: game tables + QuestieDB + Wowhead tooltips -> data/items.js.

Steps
  1. Game tables of the newest WoW Forever build from wago.tools (CSV).
  2. QuestieDB (sparse clone): Forever item/quest/NPC data plus the newest generated Forever delta,
     taken from master or a newer `forever-baseDB-update-*` branch.
  3. Pick candidate items, fetch their Wowhead tooltips (cached), resolve the new-dungeon loot lists.
  4. Assemble data/items.js and data/items-meta.json.

Usage: python scripts/build_items.py            (work files go to .cache/)
"""
import json
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from wowdata import tooltips  # noqa: E402

CACHE = ROOT / ".cache"
WORK = CACHE / "build"
TT_DIR = CACHE / "tooltips"
QDB = CACHE / "questiedb"
DELTA = WORK / "delta"
TABLES = ["Item", "ItemSparse", "SpellEffect", "SkillLineAbility", "SkillLine", "AreaTable", "Map", "DungeonEncounter"]
QDB_URL = "https://github.com/Questie/QuestieDB"
QDB_PATHS = ["data/Forever", "src/corrections/Forever/generated", "src/corrections/enum", "support/Forever/Zones"]
DELTA_FILES = ["foreverBaseItem.lua", "foreverBaseQuest.lua", "foreverBaseNpc.lua", "foreverBaseObject.lua"]
UA = {"User-Agent": "forever-gear-planner (github actions)"}


def log(msg):
    print(f"[{datetime.now(timezone.utc):%H:%M:%S}] {msg}", flush=True)


def run(cmd, cwd=None, capture=False):
    res = subprocess.run(cmd, cwd=cwd, check=True, text=True, capture_output=capture)
    return res.stdout.strip() if capture else None


def http_get(url, timeout=180):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def game_tables():
    builds = json.loads(http_get("https://wago.tools/api/builds"))
    version = builds["wowf"][0]["version"]  # wowf = WoW Forever
    log(f"game build {version}")
    for t in TABLES:
        data = http_get(f"https://wago.tools/db2/{t}/csv?build={version}")
        if data.startswith(b"{"):
            raise RuntimeError(f"wago.tools has no table {t} for {version}: {data[:200]!r}")
        (WORK / f"{t}.csv").write_bytes(data)
    return version


def questiedb():
    if not (QDB / ".git").exists():
        run(["git", "clone", "--depth", "1", "--filter=blob:none", "--sparse", QDB_URL, str(QDB)])
        run(["git", "sparse-checkout", "set"] + QDB_PATHS, cwd=QDB)
    else:
        run(["git", "fetch", "--depth", "1", "origin", "master"], cwd=QDB)
        run(["git", "reset", "--hard", "FETCH_HEAD"], cwd=QDB)
    # Newest generated Forever delta: master or a pending forever-baseDB-update-* branch.
    # Each import adds entries, so the branch whose item delta has the most entries is the newest import
    # (a later commit on master can be unrelated to the data).
    heads = run(["git", "ls-remote", "--heads", "origin"], cwd=QDB, capture=True).splitlines()
    branches = ["master"] + [h.split("refs/heads/")[1] for h in heads if "forever-basedb-update" in h.lower()]
    best = None
    for br in branches:
        run(["git", "fetch", "--depth", "1", "--filter=blob:none", "origin", br], cwd=QDB)
        sha = run(["git", "rev-parse", "FETCH_HEAD"], cwd=QDB, capture=True)
        item_delta = run(["git", "show", f"{sha}:src/corrections/Forever/generated/foreverBaseItem.lua"], cwd=QDB, capture=True)
        entries = sum(1 for line in item_delta.splitlines() if line.startswith("        ["))
        ts = int(run(["git", "log", "-1", "--format=%ct", sha], cwd=QDB, capture=True))
        if best is None or (entries, ts) > (best[0], best[1]):
            best = (entries, ts, br, sha)
    entries, ts, branch, sha = best
    best = (ts, branch, sha)
    log(f"Forever delta from {branch}: {entries} item entries ({datetime.fromtimestamp(ts, timezone.utc):%Y-%m-%d})")
    DELTA.mkdir(parents=True, exist_ok=True)
    for f in DELTA_FILES:
        content = run(["git", "show", f"{best[2]}:src/corrections/Forever/generated/{f}"], cwd=QDB, capture=True)
        (DELTA / f).write_text(content + "\n", encoding="utf-8")
    return best[1]


def main():
    t0 = time.time()
    WORK.mkdir(parents=True, exist_ok=True)
    TT_DIR.mkdir(parents=True, exist_ok=True)
    py = sys.executable
    version = game_tables()
    branch = questiedb()
    log("loading QuestieDB")
    run([py, str(ROOT / "scripts/load_questie.py"), str(QDB), str(DELTA), str(WORK / "questie.json")])
    log("selecting items")
    run([py, str(ROOT / "scripts/select_ids.py"), str(WORK), str(WORK / "ids.json")])
    ids = json.loads((WORK / "ids.json").read_text())
    log(f"fetching {len(ids)} tooltips")
    tooltips.fetch_many(ids, TT_DIR)
    run([py, str(ROOT / "scripts/match_new_loot.py"), str(WORK), str(TT_DIR), str(ROOT / "data/sources/new_dungeon_loot.json")])
    extra = json.loads((WORK / "ids_extra.json").read_text())
    if extra:
        tooltips.fetch_many(extra, TT_DIR, log_every=0)
    log("assembling")
    run([py, str(ROOT / "scripts/assemble.py"), str(WORK), str(QDB), str(TT_DIR), str(ROOT / "data/items.js"), version])
    meta = {
        "generated": datetime.now(timezone.utc).isoformat(timespec="minutes"),
        "gameBuild": version,
        "questieDelta": branch,
        "minutes": round((time.time() - t0) / 60, 1),
    }
    (ROOT / "data/items-meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    log(f"done: {meta}")


if __name__ == "__main__":
    main()
