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
                sources.append({"t": "Quest", "n": qname, "w": dungeon, "ml": 0, "ql": 0, "dq": dungeon})
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
payload = {"generated": date.today().isoformat(), "build": BUILD, "count": len(out_items), "items": out_items}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("window.GEAR_DATA = " + json.dumps(payload, separators=(",", ":")) + ";\n", encoding="utf-8")
print("written", OUT, f"{OUT.stat().st_size / 1024:.0f} KB")
