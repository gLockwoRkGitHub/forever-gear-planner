"""Hourly: fetch level and equipped gear of both characters -> build/gear.json.

Source
  * Blizzard's official API when BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET are set. It reports the
    real stats of every equipped item, including random suffixes ("... of the Gorilla").
  * Otherwise the public JSON behind armorywowforever.com. It only reports item IDs, so the stats come
    from data/items.js or the item's Wowhead tooltip, and random-suffix stats are estimated.
If a character cannot be fetched, the last good result (kept in .cache/gear) is used and marked stale.

Usage: python scripts/fetch_gear.py
"""
import base64
import json
import os
import re
import statistics
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
from wowdata import tooltips  # noqa: E402
from wowdata.itemparse import parse_equip, parse_tooltip  # noqa: E402

CACHE = ROOT / ".cache" / "gear"
OUT = ROOT / "build" / "gear.json"
UA = {"User-Agent": "Mozilla/5.0 (forever-gear-planner; personal use)"}

SLOT_MAP = {"HEAD": "Head", "NECK": "Neck", "SHOULDER": "Shoulder", "BACK": "Back", "CHEST": "Chest",
            "WRIST": "Wrist", "HANDS": "Hands", "WAIST": "Waist", "LEGS": "Legs", "FEET": "Feet",
            "FINGER_1": "Finger", "FINGER_2": "Finger", "TRINKET_1": "Trinket", "TRINKET_2": "Trinket",
            "MAIN_HAND": "Two-Hand", "RANGED": "Relic"}
QUALITY = {"POOR": 0, "COMMON": 1, "UNCOMMON": 2, "RARE": 3, "EPIC": 4, "LEGENDARY": 5}
BLIZZ_STATS = {"STRENGTH": "str", "AGILITY": "agi", "INTELLECT": "int", "STAMINA": "sta", "SPIRIT": "spi",
               "ATTACK_POWER": "ap", "SPELL_POWER": "sp", "CRIT_RATING": "critR", "HIT_RATING": "hitR",
               "HASTE_RATING": "haste", "EXPERTISE_RATING": "exp", "DEFENSE_SKILL_RATING": "def",
               "DODGE_RATING": "dodgeR"}
# Classic random suffixes and the stats they add (equal share of the item's stat budget each)
SUFFIXES = {
    "of the Bear": ["str", "sta"], "of the Boar": ["str", "spi"], "of the Eagle": ["sta", "int"],
    "of the Falcon": ["agi", "int"], "of the Gorilla": ["str", "int"], "of the Monkey": ["agi", "sta"],
    "of the Owl": ["int", "spi"], "of the Tiger": ["str", "agi"], "of the Whale": ["sta", "spi"],
    "of the Wolf": ["agi", "spi"], "of Strength": ["str"], "of Agility": ["agi"], "of Intellect": ["int"],
    "of Stamina": ["sta"], "of Spirit": ["spi"], "of Power": ["ap"],
    "of the Bandit": ["agi", "sta", "ap"], "of the Beast": ["str", "agi", "sta"], "of the Elder": ["sta", "int", "spi"],
}
PRIMARY = ["str", "agi", "int", "sta", "spi"]


def log(msg):
    print(f"[{datetime.now(timezone.utc):%H:%M:%S}] {msg}", flush=True)


def get_json(url, headers=None, data=None, timeout=30):
    req = urllib.request.Request(url, headers={**UA, **(headers or {})}, data=data)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


# ------------------------------------------------------------------ item database
def load_items():
    text = (ROOT / "data" / "items.js").read_text(encoding="utf-8")
    data = json.loads(text[text.index("{"):text.rindex("}") + 1])
    return {it["id"]: it for it in data["items"]}


ITEMS = load_items()


def budget(slot, ilvl):
    """Typical primary-stat total of a green item in this slot at this item level."""
    def total(it):
        st = it["st"]
        return sum(st.get(k, 0) for k in PRIMARY) + st.get("ap", 0) / 2
    for spread in (2, 4, 7):
        sample = [total(it) for it in ITEMS.values()
                  if it["sl"] == slot and it["q"] == 2 and not it.get("rnd") and abs(it["il"] - ilvl) <= spread and total(it) > 0]
        if len(sample) >= 4:
            return statistics.median(sample)
    return max(2, round(ilvl * 0.35))


def suffix_stats(slot, ilvl, suffix):
    keys = SUFFIXES.get(suffix)
    if not keys:
        return None
    share = budget(slot, ilvl) / len(keys)
    return {k: (round(share * 2) if k == "ap" else max(1, round(share))) for k in keys}


def item_from_db_or_tooltip(iid):
    if iid in ITEMS:
        it = ITEMS[iid]
        out = {"st": dict(it["st"]), "ty": it.get("ty"), "base": it["n"], "rnd": bool(it.get("rnd"))}
        for k in ("dps", "speed"):
            if k in it:
                out[k] = it[k]
        return out
    tooltips.fetch_one(iid, CACHE / "tooltips", max_age_days=30)
    data = tooltips.load(iid, CACHE / "tooltips")
    if not data:
        return None
    p = parse_tooltip(data)
    out = {"st": p["stats"], "ty": None, "base": data.get("name"), "rnd": p["random"]}
    for k in ("dps", "speed"):
        if k in p:
            out[k] = p[k]
    return out


# ------------------------------------------------------------------ armorywowforever.com
def fetch_armory(region, server, name):
    url = f"https://armorywowforever.com/api/character/forever/{region}/{server}/{urllib.parse.quote(name)}"
    d = get_json(url)
    items = []
    for i in d.get("items", []):
        slot = SLOT_MAP.get(i.get("slot"))
        if not slot:
            continue
        info = item_from_db_or_tooltip(i["id"]) or {"st": {}, "base": i["name"], "rnd": False}
        entry = {"slot": slot, "raw": i["slot"], "id": i["id"], "n": i["name"], "q": QUALITY.get(i.get("quality"), 1),
                 "il": i.get("ilvl") or 0, "st": info["st"], "ty": info.get("ty")}
        for k in ("dps", "speed"):
            if k in info:
                entry[k] = info[k]
        if i.get("enchant"):
            entry["ench"] = i["enchant"]
        base = info.get("base") or ""
        if base and i["name"] != base and i["name"].startswith(base):
            suffix = i["name"][len(base):].strip()
            entry["sfx"] = suffix
            extra = suffix_stats(slot, entry["il"], suffix)
            if extra:
                for k, v in extra.items():
                    entry["st"][k] = entry["st"].get(k, 0) + v
                entry["est"] = True
            else:
                entry["est"] = "unknown"
        items.append(entry)
    return {"name": d.get("name", name), "level": d.get("level"), "lastLogin": d.get("lastLogin"),
            "source": "armory", "items": items}


# ------------------------------------------------------------------ Blizzard API
VERBOSE = bool(os.environ.get("GEAR_VERBOSE"))
def blizzard_token(region, cid, secret):
    auth = base64.b64encode(f"{cid}:{secret}".encode()).decode()
    d = get_json("https://oauth.battle.net/token", headers={"Authorization": f"Basic {auth}",
                 "Content-Type": "application/x-www-form-urlencoded"}, data=b"grant_type=client_credentials")
    return d["access_token"]


def blizzard_try(region, token, ns, realm, name_slug, what=""):
    """WoW Forever has no realms: /profile/wow/character/{name}-{surname}. realm is only used as a fallback."""
    path = f"{realm}/{name_slug}" if realm else name_slug
    url = (f"https://{region}.api.blizzard.com/profile/wow/character/{path}{what}"
           f"?namespace={ns}&locale=en_US")
    return get_json(url, headers={"Authorization": f"Bearer {token}"})


def blizzard_locate(region, token, server, name, remembered):
    """Find the URL form that works for this character; remembered between runs."""
    if remembered:
        try:
            blizzard_try(region, token, remembered["ns"], remembered.get("realm"), remembered["slug"])
            return remembered
        except urllib.error.HTTPError:
            pass
    ns = f"profile-forever-{region}"
    low = name.lower().strip()
    names = list(dict.fromkeys([low.replace(" ", "-"), urllib.parse.quote(low), low.replace(" ", "")]))
    tried = []
    for realm in (None, server):
        codes = []
        for slug in names:
            try:
                blizzard_try(region, token, ns, realm, slug)
                log(f"Blizzard API: found {name} as {ns}/{realm + '/' if realm else ''}{slug}")
                return {"ns": ns, "realm": realm, "slug": slug}
            except urllib.error.HTTPError as e:
                codes.append(f"{slug} {e.code}")
        tried.append(f"{realm or '(no realm)'}: " + ", ".join(codes))
    raise RuntimeError("Blizzard API: character not found (it shows up from level 10, after logging out). Tried "
                       + "; ".join(tried))


def fetch_blizzard(region, server, name, token, remembered):
    loc = blizzard_locate(region, token, server, name, remembered)
    prof = blizzard_try(region, token, loc["ns"], loc.get("realm"), loc["slug"])
    eq = blizzard_try(region, token, loc["ns"], loc.get("realm"), loc["slug"], "/equipment")
    items = []
    for i in eq.get("equipped_items", []):
        slot = SLOT_MAP.get(i.get("slot", {}).get("type"))
        if not slot:
            continue
        st = {}
        for s in i.get("stats", []):
            key = BLIZZ_STATS.get(s.get("type", {}).get("type"))
            if key and not s.get("is_negated"):
                st[key] = st.get(key, 0) + s.get("value", 0)
        if i.get("armor", {}).get("value"):
            st["armor"] = i["armor"]["value"]
        for sp in i.get("spells", []):
            desc = (sp.get("description") or "").strip()
            if desc.startswith("Equip:"):
                desc = desc[6:].strip()
            parse_equip(desc, st)
        entry = {"slot": slot, "raw": i["slot"]["type"], "id": i["item"]["id"], "n": i.get("name"),
                 "q": QUALITY.get(i.get("quality", {}).get("type"), 1), "il": i.get("level", {}).get("value", 0),
                 "st": st, "ty": ITEMS.get(i["item"]["id"], {}).get("ty")}
        w = i.get("weapon")
        if w:
            entry["dps"] = w.get("dps", {}).get("value")
            entry["speed"] = round((w.get("attack_speed", {}).get("value") or 0) / 1000, 2)
        # Equip effects Blizzard words differently (e.g. spell power on staves): fill missing stats from item data
        info = item_from_db_or_tooltip(i["item"]["id"])
        for k, v in (info or {}).get("st", {}).items():
            st.setdefault(k, v)
        # permanent enchants only (skips weapon imbues like Windfury), without the "Enchanted: " prefix
        ench = [re.sub(r"^Enchanted:\s*", "", e["display_string"]) for e in i.get("enchantments", [])
                if e.get("display_string") and e.get("enchantment_slot", {}).get("type") != "TEMPORARY"]
        if ench:
            entry["ench"] = "; ".join(ench)
        items.append(entry)
    full = prof.get("name") or name
    if prof.get("surname") and prof["surname"].lower() not in full.lower():
        full = f"{full} {prof['surname']}"
    return {"name": full, "level": prof.get("level"),
            "lastLogin": prof.get("last_login_timestamp"), "source": "blizzard", "items": items}, loc


# ------------------------------------------------------------------ main
def log_items(label, result):
    log(f"  {label}:")
    for e in result.get("items", []):
        log(f"    {e['slot']:<9} {e.get('n')} (ilvl {e.get('il')}) {e.get('st')}"
            + (f" dps {e.get('dps')} speed {e.get('speed')}" if e.get("dps") else "")
            + (f" [{e['ench']}]" if e.get("ench") else "") + (" (estimated)" if e.get("est") else ""))


def main():
    cfg = json.loads((ROOT / "characters.json").read_text(encoding="utf-8"))
    region = cfg["region"]
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / "tooltips").mkdir(exist_ok=True)
    prev_path = CACHE / "gear.json"
    prev = json.loads(prev_path.read_text(encoding="utf-8")) if prev_path.exists() else {"chars": {}}
    loc_path = CACHE / "blizzard-locations.json"
    locations = json.loads(loc_path.read_text(encoding="utf-8")) if loc_path.exists() else {}

    cid, secret = os.environ.get("BLIZZARD_CLIENT_ID"), os.environ.get("BLIZZARD_CLIENT_SECRET")
    token = None
    if cid and secret:
        try:
            token = blizzard_token(region, cid, secret)
            log("Blizzard API: token ok")
        except Exception as e:  # noqa: BLE001
            log(f"Blizzard API: no token ({e}); using the armory")

    out = {"fetched": datetime.now(timezone.utc).isoformat(timespec="minutes"), "chars": {}}
    for c in cfg["characters"]:
        key, name, server = c["key"], c["name"], c.get("server", "normal")
        result = None
        if token:
            try:
                result, loc = fetch_blizzard(region, server, name, token, locations.get(key))
                locations[key] = loc
            except Exception as e:  # noqa: BLE001
                log(f"{name}: Blizzard API failed ({e}); trying the armory")
        if result is None:
            try:
                result = fetch_armory(region, server, name)
            except Exception as e:  # noqa: BLE001
                log(f"{name}: armory failed ({e})")
        if result is None and key in prev["chars"]:
            result = dict(prev["chars"][key], stale=True)
            log(f"{name}: using the last good result from {prev.get('fetched')}")
        if result is None:
            result = {"name": name, "level": None, "items": [], "source": None, "error": "not available"}
        result["fetchedAt"] = out["fetched"] if not result.get("stale") else prev.get("fetched")
        out["chars"][key] = result
        log(f"{name}: level {result.get('level')}, {len(result.get('items', []))} items via {result.get('source')}"
            + (" (stale)" if result.get("stale") else ""))
        if VERBOSE and not result.get("stale"):
            log_items(result.get("source"), result)
            if result.get("source") == "blizzard":
                try:
                    log_items("armory, for comparison", fetch_armory(region, server, name))
                except Exception as e:  # noqa: BLE001
                    log(f"  armory for comparison failed ({e})")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, separators=(",", ":")), encoding="utf-8")
    good = {"fetched": out["fetched"], "chars": {k: v for k, v in out["chars"].items() if v.get("items") and not v.get("stale")}}
    for k, v in prev["chars"].items():
        good["chars"].setdefault(k, v)
    prev_path.write_text(json.dumps(good), encoding="utf-8")
    loc_path.write_text(json.dumps(locations), encoding="utf-8")


if __name__ == "__main__":
    main()
