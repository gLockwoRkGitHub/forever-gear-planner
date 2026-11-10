"""Fetch Wowhead WoW Forever item tooltips with an on-disk cache.

Cache policy: a found tooltip is reused for `max_age_days`; a missing one (404, or an item
Blizzard still hides) is asked for again on every run, because items get revealed over time.
"""
import json
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from .itemparse import TOOLTIP_URL

USER_AGENT = "Mozilla/5.0 (forever-gear-planner; personal use)"


def _fresh(path, max_age_days):
    if not path.exists():
        return False
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return False
    if not data.get("tooltip"):
        return False  # missing last time: try again
    return (time.time() - path.stat().st_mtime) < max_age_days * 86400


def fetch_one(iid, cache_dir, max_age_days=21):
    path = Path(cache_dir) / f"{iid}.json"
    if _fresh(path, max_age_days):
        return "cached"
    for attempt in range(4):
        try:
            req = urllib.request.Request(TOOLTIP_URL.format(iid), headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=20) as r:
                body = r.read().decode("utf-8")
            json.loads(body)  # only store valid JSON
            path.write_text(body, encoding="utf-8")
            return "ok"
        except urllib.error.HTTPError as e:
            if e.code == 404:
                path.write_text(json.dumps({"error": "404"}), encoding="utf-8")
                return "missing"
            time.sleep(2 * (attempt + 1))
        except Exception:
            time.sleep(2 * (attempt + 1))
    return "failed"


def fetch_many(ids, cache_dir, workers=6, max_age_days=21, log_every=1000):
    Path(cache_dir).mkdir(parents=True, exist_ok=True)
    counts, start = {}, time.time()
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(fetch_one, i, cache_dir, max_age_days) for i in ids]
        for n, f in enumerate(as_completed(futs), 1):
            res = f.result()
            counts[res] = counts.get(res, 0) + 1
            if log_every and n % log_every == 0:
                print(f"  tooltips {n}/{len(ids)} {counts} {time.time() - start:.0f}s", flush=True)
    print(f"  tooltips done {counts} {time.time() - start:.0f}s", flush=True)
    return counts


def load(iid, cache_dir):
    path = Path(cache_dir) / f"{iid}.json"
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return None
    return data if data.get("tooltip") else None
