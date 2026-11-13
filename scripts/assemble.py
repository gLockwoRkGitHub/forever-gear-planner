"""Combine Wowhead Forever tooltips, QuestieDB sources and game-table crafting data into data/items.js.

Characters: Tauren (Horde) Enhancement Shaman and Tauren Feral Druid; sources Quest/Dungeon/Vendor/Crafted.
Class restrictions are kept per item (cl) and per quest source (rc) so the planner filters per character.

Usage: python scripts/assemble.py <build_dir> <questiedb_dir> <tooltip_dir> <out_items_js> <game_build>
  build_dir holds the wago.tools CSVs, questie.json, ids.json and new_loot_ids.json.
"""
import csv
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from wowdata.itemparse import parse_tooltip  # noqa: E402

DL, QDB, TT, OUT, BUILD = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), Path(sys.argv[4]), sys.argv[5]

TAUREN_RACE_BIT = 32
SHAMAN_CLASS_BIT = 64
DRUID_CLASS_BIT = 1024
SLOTS = {1: "Head", 2: "Neck", 3: "Shoulder", 5: "Chest", 20: "Chest", 6: "Waist", 7: "Legs",
         8: "Feet", 9: "Wrist", 10: "Hands", 11: "Finger", 12: "Trinket", 16: "Back",
         17: "Two-Hand", 28: "Relic"}
ARMOR_SUBCLASS = {0: "Misc", 1: "Cloth", 2: "Leather", 3: "Mail", 8: "Idol", 9: "Totem"}
WEAPON_SUBCLASS = {1: "Two-Handed Axe", 5: "Two-Handed Mace", 6: "Polearm", 10: "Staff"}
PLAYABLE = {"Shaman", "Druid"}
# Battlegrounds and PvP reward halls: their quest rewards and vendors count as PvP, which is excluded
PVP_AREAS = {2597, 3277, 3358, 2917, 2918}
# PvP rank rewards sold by city vendors (the Forever tooltips do not show the rank requirement)
PVP_RANK_PREFIX = re.compile(r"^(Scout|Grunt|Sergeant|Senior Sergeant|First Sergeant|Stone Guard|Blood Guard|Legionnaire|"
                             r"Centurion|Champion|Lieutenant General|General|Warlord|High Warlord|Private|Corporal|"
                             r"Master Sergeant|Sergeant Major|Knight|Knight-Lieutenant|Knight-Captain|Knight-Champion|"
                             r"Lieutenant Commander|Commander|Marshal|Field Marshal|Grand Marshal)'s ")
PROFESSIONS = {164: "Blacksmithing", 165: "Leatherworking", 197: "Tailoring", 202: "Engineering",
               333: "Enchanting", 171: "Alchemy", 2937: "Alchemy", 2938: "Blacksmithing",
               2940: "Enchanting", 2941: "Engineering", 2945: "Leatherworking", 2948: "Tailoring"}


def rows(name):
    with open(DL / name, encoding="utf-8", newline="") as f:
        yield from csv.DictReader(f)


def to_int(v, default=0):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


# ---------------------------------------------------------------- reference data
item_base = {int(r["ID"]): r for r in rows("Item.csv")}
maps = {int(r["ID"]): r for r in rows("Map.csv")}
area_rows = {int(r["ID"]): r for r in rows("AreaTable.csv")}
dungeon_name_by_area, raid_areas = {}, set()
for aid, a in area_rows.items():
    m = maps.get(to_int(a["ContinentID"]))
    if m and m["InstanceType"] == "1":
        dungeon_name_by_area[aid] = m["MapName_lang"]
    elif m and m["InstanceType"] == "2":
        raid_areas.add(aid)
party_map_names = {m["MapName_lang"] for m in maps.values() if m["InstanceType"] == "1"}
raid_map_names = {m["MapName_lang"] for m in maps.values() if m["InstanceType"] == "2"}
dungeons_lua = (QDB / "support" / "Forever" / "Zones" / "dungeons.lua").read_text(encoding="utf-8")
for m in re.finditer(r'\[(\d+)\]\s*=\s*\{"([^"]+)",(nil|\{[\d,\s]*\})', dungeons_lua):
    aid, name, alts = int(m.group(1)), m.group(2), m.group(3)
    ids = [aid] + ([int(x) for x in re.findall(r"\d+", alts)] if alts != "nil" else [])
    base = area_rows.get(aid)
    mp = maps.get(to_int(base["ContinentID"])) if base else None
    if (mp and mp["InstanceType"] == "2") or name in raid_map_names:
        raid_areas.update(ids)
    elif (mp and mp["InstanceType"] == "1") or name in party_map_names or aid in dungeon_name_by_area:
        label = mp["MapName_lang"] if mp and mp["InstanceType"] == "1" else name
        for i in ids:
            dungeon_name_by_area.setdefault(i, label)

# Loot of the new Forever dungeons (boss lists from wowtbc.gg, resolved to item IDs)
new_loot = json.loads((DL / "new_loot_ids.json").read_text(encoding="utf-8"))

spell_to_skill = {}
for r in rows("SkillLineAbility.csv"):
    sk = to_int(r["SkillLine"])
    if sk in PROFESSIONS:
        spell_to_skill[to_int(r["Spell"])] = (PROFESSIONS[sk], to_int(r["MinSkillLineRank"]))
crafted = defaultdict(set)
for r in rows("SpellEffect.csv"):
    if r["Effect"] == "24" and to_int(r["SpellID"]) in spell_to_skill:
        crafted[to_int(r["EffectItemType"])].add(spell_to_skill[to_int(r["SpellID"])])

q = json.loads((DL / "questie.json").read_text(encoding="utf-8"))
qitems, qquests, qnpcs, qobjects = q["items"], q["quests"], q["npcs"], q["objects"]
npcs_by_name = defaultdict(list)
for nid, n in qnpcs.items():
    if n.get("name"):
        npcs_by_name[n["name"].lower()].append(n)


quests_by_name = defaultdict(list)
for qid_, qu_ in qquests.items():
    if qu_.get("name"):
        quests_by_name[qu_["name"].lower()].append((int(qid_), qu_))


def quest_by_name(qname, dungeon):
    """The quest behind a reward known only by the quest's name (new-dungeon loot lists): one open to a
    Tauren Shaman or Druid, preferably one that belongs to that dungeon. Gives the planner its ID, so
    quests already turned in can be left out."""
    cands = [(qid_, qu_) for qid_, qu_ in quests_by_name.get(qname.lower(), []) if quest_ok(qu_)]
    inside = [c for c in cands if dungeon_name_by_area.get(int(c[1].get("zoneOrSort") or 0)) == dungeon]
    return min(inside or cands, key=lambda c: c[0]) if cands else None


def zone_name(zid):
    a = area_rows.get(int(zid)) if zid else None
    return a["AreaName_lang"] if a else None


def spawn_zones(spawns):
    # Lua tables with keys 1..n come through as lists; their zone IDs are the positions
    if isinstance(spawns, list):
        return set(range(1, len(spawns) + 1))
    return {int(z) for z in (spawns or {})}


def npc_zones(npc):
    zones = {int(npc["zoneID"])} if npc.get("zoneID") else set()
    return zones | spawn_zones(npc.get("spawns"))


def npc_dungeon(npc):
    return next((dungeon_name_by_area[z] for z in npc_zones(npc) if z in dungeon_name_by_area), None)


def quest_ok(quest):
    races = quest.get("requiredRaces") or 0
    classes = quest.get("requiredClasses") or 0
    return not (races and not races & TAUREN_RACE_BIT) and not (classes and not classes & (SHAMAN_CLASS_BIT | DRUID_CLASS_BIT))


# ---------------------------------------------------------------- assemble
ids = json.loads((DL / "ids.json").read_text())
out_items, counters, unparsed_lines = [], Counter(), Counter()
for iid in ids:
    f = TT / f"{iid}.json"
    if not f.exists():
        counters["no_tooltip_file"] += 1; continue
    data = json.loads(f.read_text(encoding="utf-8"))
    if not data.get("tooltip"):
        counters["hidden_or_missing"] += 1; continue
    base = item_base[iid]
    cls, sub, inv = to_int(base["ClassID"]), to_int(base["SubclassID"]), to_int(base["InventoryType"])
    quality = data.get("quality", 0)
    if quality < 2 or quality > 4:
        counters["quality"] += 1; continue
    p = parse_tooltip(data)
    if p["classes"] and not PLAYABLE & set(p["classes"]):
        counters["class_restricted"] += 1; continue
    if p["races"] and "Tauren" not in p["races"]:
        counters["race_restricted"] += 1; continue
    if p["reputation"] or p["pvpRank"]:
        counters["rep_or_pvp"] += 1; continue
    if p["sodLeftover"]:
        counters["season_of_discovery_leftover"] += 1; continue
    if p["req"] > 60:
        continue

    qi = qitems.get(str(iid), {})
    sources = []
    for qid in qi.get("questRewards") or []:
        quest = qquests.get(str(qid))
        if quest and quest_ok(quest) and (quest.get("zoneOrSort") or 0) not in PVP_AREAS:
            zos = quest.get("zoneOrSort") or 0
            sources.append({"t": "Quest", "n": quest.get("name"), "id": qid,
                            "w": zone_name(zos) if zos > 0 else None,
                            "ml": quest.get("requiredLevel") or 0, "ql": quest.get("questLevel") or 0,
                            "rc": quest.get("requiredClasses") or 0,
                            **({"dq": dungeon_name_by_area[zos]} if zos in dungeon_name_by_area else {})})
    drop_npcs = [qnpcs.get(str(n)) for n in (qi.get("npcDrops") or [])]
    drop_npcs = [n for n in drop_npcs if n]
    dungeon_found = False
    if drop_npcs and len(drop_npcs) <= 25:
        hits = [(n, npc_dungeon(n)) for n in drop_npcs]
        hits = [(n, d) for n, d in hits if d]
        in_raid = any(npc_zones(n) & raid_areas for n in drop_npcs)
        if hits and len(hits) * 2 >= len(drop_npcs) and not in_raid:
            hits.sort(key=lambda x: -(x[0].get("rank") or 0))
            n, d = hits[0]
            named = (n.get("rank") or 0) >= 1 and len(hits) <= 3
            sources.append({"t": "Dungeon", "n": n.get("name") if named or len(hits) == 1 else f"trash ({len(hits)} mob types)",
                            "w": d, "lv": n.get("maxLevel") or 0, "dc": p["dropChance"]})
            dungeon_found = True
    if not dungeon_found and p["droppedBy"]:
        cands = npcs_by_name.get(p["droppedBy"].lower(), [])
        in_raid = any(npc_zones(n) & raid_areas for n in cands)
        d = next((npc_dungeon(n) for n in cands if npc_dungeon(n)), None)
        if d and not in_raid:
            n = next(n for n in cands if npc_dungeon(n))
            sources.append({"t": "Dungeon", "n": p["droppedBy"], "w": d, "lv": n.get("maxLevel") or 0,
                            "dc": p["dropChance"]})
            dungeon_found = True
    if not dungeon_found and len(qi.get("objectDrops") or []) <= 3:
        for oid in qi.get("objectDrops") or []:
            obj = qobjects.get(str(oid))
            if not obj:
                continue
            zones = ({int(obj["zoneID"])} if obj.get("zoneID") else set()) | spawn_zones(obj.get("spawns"))
            d = next((dungeon_name_by_area[z] for z in zones if z in dungeon_name_by_area), None)
            if d and zones and all(z in dungeon_name_by_area for z in zones):
                sources.append({"t": "Dungeon", "n": obj.get("name"), "w": d, "lv": 0, "dc": p["dropChance"]})
                break
    for dungeon, src in new_loot.get(str(iid), []):
        if src.startswith("quest:"):
            qname = src[6:]
            if not any(s_["t"] == "Quest" and s_["n"] == qname for s_ in sources):
                src_q = {"t": "Quest", "n": qname, "w": dungeon, "ml": 0, "ql": 0, "dq": dungeon}
                found_q = quest_by_name(qname, dungeon)
                if found_q:
                    src_q.update({"id": found_q[0], "ml": found_q[1].get("requiredLevel") or 0,
                                  "ql": found_q[1].get("questLevel") or 0, "rc": found_q[1].get("requiredClasses") or 0})
                else:
                    counters["quest_by_name_unmatched"] += 1
                sources.append(src_q)
        elif not dungeon_found:
            sources.append({"t": "Dungeon", "n": "trash" if src == "trash" else src, "w": dungeon, "lv": 0,
                            "dc": p["dropChance"]})
            dungeon_found = True
    vendors = [qnpcs.get(str(n)) for n in (qi.get("vendors") or [])]
    vendors = [v for v in vendors if v and (v.get("friendlyToFaction") is None or "H" in v["friendlyToFaction"])
               and int(v.get("zoneID") or 0) not in PVP_AREAS]
    if vendors and PVP_RANK_PREFIX.match(data["name"]):
        vendors = []
    if vendors:
        v = vendors[0]
        sources.append({"t": "Vendor", "n": v.get("name"), "w": zone_name(v.get("zoneID"))})
    for prof, skill in sorted(crafted.get(iid, set()), key=lambda x: x[1])[:1]:
        sources.append({"t": "Crafted", "n": prof, "sk": skill if skill > 1 else None})
    if not sources:
        counters["no_allowed_source"] += 1; continue

    fallback = max(1, p["ilvl"] - 5)
    for s_ in sources:
        if s_["t"] == "Quest" and s_["ml"]:
            # a quest is realistic from its minimum level, but not more than 3 levels below the quest level
            s_["g"] = max(p["req"], s_["ml"], (s_["ql"] or 0) - 3)
        elif s_["t"] == "Quest" and s_["ql"]:
            s_["g"] = max(p["req"], s_["ql"] - 3)
        else:
            s_["g"] = p["req"] if p["req"] else fallback
    item = {
        "id": iid, "n": data["name"], "q": quality, "il": p["ilvl"], "rq": p["req"],
        "g": min(s_["g"] for s_ in sources),
        "sl": SLOTS[inv],
        "ty": ARMOR_SUBCLASS.get(sub) if cls == 4 else WEAPON_SUBCLASS.get(sub),
        "st": p["stats"], "src": sources,
        **({"ic": data["icon"]} if data.get("icon") else {}),
        **({"cl": p["classes"]} if p["classes"] else {}),
    }
    for k in ("dmgMin", "dmgMax", "speed", "dps"):
        if k in p:
            item[k] = p[k]
    if p["notes"]:
        item["nt"] = p["notes"]
        for l in p["notes"]:
            unparsed_lines[re.sub(r"\d+(\.\d+)?", "N", l)[:100]] += 1
    if p["random"]:
        item["rnd"] = 1
    if p["boe"]:
        item["boe"] = 1
    if p["bop"]:
        item["bop"] = 1
    if p["needsProfession"]:
        item["np"] = p["needsProfession"]
    out_items.append(item)
    counters["kept"] += 1
    for s_ in sources:
        counters["src_" + s_["t"]] += 1

print(dict(counters))
print("Most common unscored effect lines:")
for k, v in unparsed_lines.most_common(25):
    print(" ", v, k)
# ---------------------------------------------------------------- dungeon bosses in fight order
# DungeonEncounter gives the order per instance map; Questie the level and rank; Wowhead the creature type.
NPC_CACHE = TT.parent / "npcs"
NPC_URL = "https://nether.wowhead.com/forever/tooltip/npc/{}"
RANKS = {1: "Elite", 2: "Rare Elite", 3: "Boss", 4: "Rare"}


def npc_type(nid):
    import urllib.request
    NPC_CACHE.mkdir(parents=True, exist_ok=True)
    f = NPC_CACHE / f"{nid}.json"
    if not f.exists():
        try:
            req = urllib.request.Request(NPC_URL.format(nid), headers={"User-Agent": "forever-gear-planner"})
            with urllib.request.urlopen(req, timeout=30) as r:
                f.write_bytes(r.read())
        except Exception:  # noqa: BLE001
            return None
    try:
        tip = json.loads(f.read_text(encoding="utf-8")).get("tooltip", "")
    except ValueError:
        return None
    m = re.search(r"Level [^<]*?(?:\d+|\?\?)\s+([A-Z][A-Za-z ]+?)\s*(?:\([^)]*\))?\s*<", tip)
    return m.group(1).strip() if m else None


dungeon_by_boss = defaultdict(Counter)  # boss name -> dungeon names used by the items' sources
for it in out_items:
    for s_ in it["src"]:
        if s_["t"] == "Dungeon":
            dungeon_by_boss[s_["n"]][s_["w"]] += 1
encounters = defaultdict(list)
for r in rows("DungeonEncounter.csv"):
    encounters[to_int(r["MapID"])].append(r)
bosses = {}
for mid, rs in encounters.items():
    m = maps.get(mid)
    if not m or m["InstanceType"] != "1":
        continue
    diffs = {to_int(r["DifficultyID"]) for r in rs}
    keep = {d for d in diffs if d in (0, 1)} or {min(diffs)}
    rs = sorted((r for r in rs if to_int(r["DifficultyID"]) in keep), key=lambda r: to_int(r["OrderIndex"]))
    names = list(dict.fromkeys(r["Name_lang"] for r in rs))
    votes = Counter()
    for n in names:
        votes.update(dungeon_by_boss.get(n, {}))
    dname = votes.most_common(1)[0][0] if votes else m["MapName_lang"]
    out = []
    for n in names:
        # only trust an NPC record that spawns in this dungeon (new Forever dungeons are often missing)
        cands = npcs_by_name.get(n.lower(), [])
        npc = next((c for c in cands if npc_dungeon(c) in (dname, m["MapName_lang"])), None)
        nid = next((k for k, v in qnpcs.items() if v is npc), None) if npc else None
        b = {"n": n}
        if npc:
            lv = npc.get("maxLevel") or npc.get("minLevel")
            if lv and lv <= 63:
                b["lv"] = lv
            if RANKS.get(npc.get("rank")):
                b["rk"] = RANKS[npc["rank"]]
        if nid:
            ty = npc_type(nid)
            if ty:
                b["ty"] = ty
        out.append(b)
    bosses[dname] = out
print("bosses for", len(bosses), "dungeons:", ", ".join(sorted(bosses)))
payload = {"generated": date.today().isoformat(), "build": BUILD, "count": len(out_items), "items": out_items, "bosses": bosses}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("window.GEAR_DATA = " + json.dumps(payload, separators=(",", ":")) + ";\n", encoding="utf-8")
print("written", OUT, f"{OUT.stat().st_size / 1024:.0f} KB")

# ---------------------------------------------------------------- quests for the addon's quest sync
# Every quest open to a Tauren Shaman or Druid: name, zone, quest level, minimum level. The addon groups
# the quests one partner has done and the other has not by zone. Negative zoneOrSort values are quest
# categories (class quests, professions, holidays).
QUEST_SORT = {-22: "Seasonal", -24: "Herbalism", -25: "Battlegrounds", -61: "Warlock", -81: "Warrior", -82: "Shaman",
              -101: "Fishing", -121: "Blacksmithing", -141: "Paladin", -161: "Mage", -162: "Rogue", -181: "Alchemy",
              -182: "Leatherworking", -201: "Engineering", -221: "Treasure Map", -261: "Hunter", -262: "Priest",
              -263: "Druid", -264: "Tailoring", -284: "Special", -304: "Cooking", -324: "First Aid", -344: "Legendary",
              -364: "Darkmoon Faire", -365: "Ahn'Qiraj War", -366: "Lunar Festival", -367: "Reputation", -368: "Invasion",
              -369: "Midsummer", -370: "Brewfest", -374: "Noblegarden", -375: "Pilgrim's Bounty", -376: "Love is in the Air"}
zones_out, zone_index, quests_out = [], {}, {}
for qid_, qu_ in qquests.items():
    zos = int(qu_.get("zoneOrSort") or 0)
    if not qu_.get("name") or not quest_ok(qu_) or zos in PVP_AREAS:
        continue
    zname = (dungeon_name_by_area.get(zos) or zone_name(zos)) if zos > 0 else QUEST_SORT.get(zos)
    zname = zname or "Other"
    if zname not in zone_index:
        zone_index[zname] = len(zones_out)
        zones_out.append(zname)
    quests_out[str(qid_)] = [qu_["name"], zone_index[zname], qu_.get("questLevel") or 0, qu_.get("requiredLevel") or 0]
# ---------------------------------------------------------------- dungeon quests with their pre-quest chains
# For the addon's dungeon preparation: per dungeon the quests a Tauren Shaman or Druid can do there, and every
# quest that has to be done before (preQuestSingle: one of them, preQuestGroup: all of them), each with its quest
# giver, where to find it (zone, coordinates, map ID for a waypoint), where to turn it in and the objectives.
ui_map = {}
uimap_lua = QDB / "support" / "Forever" / "Zones" / "areaIdToUiMapId.lua"
if uimap_lua.exists():
    for m in re.finditer(r"\[(\d+)\]\s*=\s*(\d+)", uimap_lua.read_text(encoding="utf-8")):
        if int(m.group(2)):
            ui_map[int(m.group(1))] = int(m.group(2))


def place(rec):
    """Zone, coordinates and map ID of an NPC or object; inside a dungeon only its name."""
    if not rec:
        return {}
    spawns = rec.get("spawns") or {}
    zones = list(spawns.items()) if isinstance(spawns, dict) else [(str(i + 1), v) for i, v in enumerate(spawns)]
    if rec.get("zoneID"):
        zones.sort(key=lambda kv: int(kv[0]) != int(rec["zoneID"]))
    for zid, coords in zones:
        zid = int(zid)
        if zid in dungeon_name_by_area:
            return {"in": dungeon_name_by_area[zid]}
        pts = [c for c in (coords or []) if isinstance(c, list) and len(c) >= 2 and c[0] >= 0 and c[1] >= 0]
        if pts and zone_name(zid):
            out = {"z": zone_name(zid), "x": round(pts[0][0], 1), "y": round(pts[0][1], 1)}
            if ui_map.get(zid):
                out["m"] = ui_map[zid]
            return out
    zid = int(rec.get("zoneID") or 0)
    if zid in dungeon_name_by_area:
        return {"in": dungeon_name_by_area[zid]}
    return {"z": zone_name(zid)} if zone_name(zid) else {}


def who(refs):
    """Quest giver or turn-in from Questie's startedBy / finishedBy: {npcs}, {objects}, {items}."""
    if isinstance(refs, dict):          # sparse Lua tables come through as {position: value}
        refs = [refs.get(k) or refs.get(str(k)) for k in (1, 2, 3)]
    refs = refs or []
    for kind, table in (("npc", qnpcs), ("obj", qobjects), ("item", qitems)):
        i = {"npc": 0, "obj": 1, "item": 2}[kind]
        ids = refs[i] if len(refs) > i and refs[i] else []
        if isinstance(ids, dict):
            ids = list(ids.values())
        for rid in ids:
            rec = table.get(str(rid))
            if not rec or not rec.get("name"):
                continue
            if kind == "npc" and rec.get("friendlyToFaction") and "H" not in rec["friendlyToFaction"]:
                continue
            out = {"t": kind, "n": rec["name"]}
            if kind != "item":
                out.update(place(rec))
            return out
    return None


def ok_ids(ids):
    return [int(x) for x in (ids or []) if str(x) in qquests and quest_ok(qquests[str(x)])]


dq_quests, dq_by_dungeon = {}, defaultdict(list)


def add_quest(qid, depth=0):
    if qid in dq_quests or depth > 40:
        return
    qu = qquests.get(str(qid))
    if not qu:
        return
    rec = {"n": qu.get("name"), "lv": qu.get("questLevel") or 0, "min": qu.get("requiredLevel") or 0}
    if qu.get("requiredClasses"):
        rec["rc"] = qu["requiredClasses"]
    s_ = who(qu.get("startedBy"))
    if s_:
        rec["s"] = s_
    e_ = who(qu.get("finishedBy"))
    if e_ and (not s_ or e_["n"] != s_["n"]):
        rec["e"] = e_
    obj = [o.strip() for o in (qu.get("objectivesText") or []) if o and o.strip()]
    if obj:
        rec["o"] = [o[:220] for o in obj[:4]]
    single, group = ok_ids(qu.get("preQuestSingle")), ok_ids(qu.get("preQuestGroup"))
    if single:
        rec["ps"] = single
    if group:
        rec["pg"] = group
    excl = ok_ids(qu.get("exclusiveTo"))
    if excl:
        rec["x"] = excl
    zos = int(qu.get("zoneOrSort") or 0)
    if zos in dungeon_name_by_area:
        rec["d"] = dungeon_name_by_area[zos]
    dq_quests[qid] = rec
    for p_ in single + group:
        add_quest(p_, depth + 1)


for qid_, qu_ in qquests.items():
    zos = int(qu_.get("zoneOrSort") or 0)
    if zos in dungeon_name_by_area and qu_.get("name") and quest_ok(qu_) and (qu_.get("requiredLevel") or 0) <= 60:
        dq_by_dungeon[dungeon_name_by_area[zos]].append(int(qid_))
        add_quest(int(qid_))


def closure(qid, seen=None):
    """All quests that come before `qid` (every option of preQuestSingle)."""
    seen = set() if seen is None else seen
    for p_ in dq_quests.get(qid, {}).get("ps", []) + dq_quests.get(qid, {}).get("pg", []):
        if p_ not in seen:
            seen.add(p_)
            closure(p_, seen)
    return seen


# one entry per quest line: the quests no other quest of the same dungeon builds on (its pre-quests are the steps)
for d_, ids in dq_by_dungeon.items():
    before = set()
    for i in ids:
        before |= closure(i)
    ends = [i for i in ids if i not in before]
    first = {i: min([dq_quests[j]["lv"] for j in closure(i) | {i} if j in dq_quests]) for i in ends}
    dq_by_dungeon[d_] = sorted(ends, key=lambda i: (first[i], dq_quests[i]["lv"], dq_quests[i]["n"]))
DQ_OUT = OUT.parent / "dungeon_quests.json"
DQ_OUT.write_text(json.dumps({"dungeons": dq_by_dungeon, "quests": {str(k): v for k, v in sorted(dq_quests.items())}},
                             separators=(",", ":"), ensure_ascii=False) + "\n", encoding="utf-8")
chains = sum(1 for d_ in dq_by_dungeon.values() for i in d_ if dq_quests[i].get("ps") or dq_quests[i].get("pg"))
print("written", DQ_OUT, f"{sum(len(v) for v in dq_by_dungeon.values())} quest lines in {len(dq_by_dungeon)} dungeons,",
      f"{chains} with pre-quests, {len(dq_quests)} quests in all")

QUESTS_OUT = OUT.parent / "quests.json"
QUESTS_OUT.write_text(json.dumps({"zones": zones_out, "quests": quests_out}, separators=(",", ":")) + "\n", encoding="utf-8")
print("written", QUESTS_OUT, f"{len(quests_out)} quests in {len(zones_out)} zones")
