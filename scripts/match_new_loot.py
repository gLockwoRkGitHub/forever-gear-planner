"""Resolve the boss/quest loot lists of the new Forever dungeons (item names) to item IDs.

Usage: python scripts/match_new_loot.py <build_dir> <tooltip_dir> <loot_json>
Writes <build_dir>/new_loot_ids.json and adds unknown IDs to <build_dir>/ids.json
(their IDs also go to <build_dir>/ids_extra.json so they can be fetched).
"""
import csv
import glob
import json
import os
import sys
from pathlib import Path

DL, TT, LOOT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
SLOT_INV = {1, 2, 3, 5, 20, 6, 7, 8, 9, 10, 11, 12, 16, 17, 28}


def rows(name):
    with open(DL / name, encoding="utf-8", newline="") as f:
        yield from csv.DictReader(f)


names = {}
for iid, it in json.loads((DL / "questie.json").read_text(encoding="utf-8"))["items"].items():
    if it.get("name"):
        names.setdefault(it["name"].lower(), set()).add(int(iid))
for r in rows("ItemSparse.csv"):
    names.setdefault(r["Display_lang"].lower(), set()).add(int(r["ID"]))
for f in glob.glob(str(TT / "*.json")):
    try:
        d = json.loads(Path(f).read_text(encoding="utf-8"))
    except ValueError:
        continue
    if d.get("name"):
        names.setdefault(d["name"].lower(), set()).add(int(os.path.basename(f)[:-5]))

base = {int(r["ID"]): r for r in rows("Item.csv")}


def ours(i):
    r = base.get(i)
    if not r:
        return False
    c, s, inv = int(r["ClassID"]), int(r["SubclassID"]), int(r["InventoryType"])
    if inv not in SLOT_INV:
        return False
    if c == 4:
        return s in (0, 1, 2, 3, 8, 9)
    if c == 2:
        return inv == 17 and s in (1, 5, 6, 10)
    return False


loot = json.loads(LOOT.read_text(encoding="utf-8"))
res, unknown = {}, []
for dungeon, bosses in loot.items():
    if dungeon.startswith("_"):
        continue
    for src, items in bosses.items():
        for nm in items:
            found = [i for i in names.get(nm.lower(), ()) if ours(i)]
            if not names.get(nm.lower()):
                unknown.append(nm)
            for i in found:
                res.setdefault(str(i), []).append([dungeon, src])
(DL / "new_loot_ids.json").write_text(json.dumps(res), encoding="utf-8")
ids = json.loads((DL / "ids.json").read_text())
have = set(ids)
extra = sorted(int(i) for i in res if int(i) not in have)
(DL / "ids_extra.json").write_text(json.dumps(extra))
(DL / "ids.json").write_text(json.dumps(sorted(have | set(extra))))
print(f"new-dungeon loot: {len(res)} items matched, {len(extra)} extra to fetch, unknown names: {unknown}")
