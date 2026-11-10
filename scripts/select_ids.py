"""Pick the item IDs worth fetching a tooltip for.

Usage: python3 -I select_ids.py <dl_dir> <out_ids.json>
"""
import csv
import json
import sys
from pathlib import Path

DL, OUT = Path(sys.argv[1]), Path(sys.argv[2])
SLOT_INV = {1, 2, 3, 5, 20, 6, 7, 8, 9, 10, 11, 12, 16, 17, 28}
PROF_SKILLS = {164, 165, 197, 202, 333, 171, 2937, 2938, 2940, 2941, 2945, 2948}


def rows(name):
    with open(DL / name, encoding="utf-8", newline="") as f:
        yield from csv.DictReader(f)


craft_spells = {int(r["Spell"]) for r in rows("SkillLineAbility.csv") if int(r["SkillLine"]) in PROF_SKILLS}
crafted = {int(r["EffectItemType"]) for r in rows("SpellEffect.csv") if r["Effect"] == "24" and int(r["SpellID"]) in craft_spells}
qitems = json.loads((DL / "questie.json").read_text(encoding="utf-8"))["items"]

ids = []
for r in rows("Item.csv"):
    iid, c, s, inv = int(r["ID"]), int(r["ClassID"]), int(r["SubclassID"]), int(r["InventoryType"])
    if inv not in SLOT_INV:
        continue
    if c == 4 and s not in (0, 1, 2, 3, 8, 9):  # misc, cloth, leather, mail, idol, totem
        continue
    if c == 2 and not (inv == 17 and s in (1, 5, 6, 10)):  # 2H axe, 2H mace, polearm, staff
        continue
    if c not in (2, 4):
        continue
    qi = qitems.get(str(iid))
    if qi and (qi.get("itemLevel") or 0) > 80:
        continue
    keep = iid in crafted
    if qi:
        if qi.get("questRewards") or qi.get("vendors") or qi.get("objectDrops"):
            keep = True
        npcs = qi.get("npcDrops") or []
        if 0 < len(npcs) <= 25:
            keep = True
    elif iid >= 200000:
        keep = True  # new Forever item without Questie data: the tooltip may name its source
    if keep:
        ids.append(iid)

OUT.write_text(json.dumps(ids))
print(len(ids), "ids;", len(crafted), "crafted items overall")
