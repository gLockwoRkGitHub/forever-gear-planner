"""Rank tables of the abilities the level model uses, read from the WoW Forever game tables.

Usage: python scripts/extract_mechanics.py <build_dir> <out_json>
  build_dir holds SpellName.csv, SpellLevels.csv, SpellEffect.csv, SpellPower.csv, SpellCooldowns.csv (wago.tools).

Per rank: learn level (lv), level up to which the values still grow (max), and the numbers the model needs.
Damage of a rank at character level L = base + perLevel * (min(L, max) - lv).
"""
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

DL, OUT = Path(sys.argv[1]), Path(sys.argv[2])


def rows(name):
    with open(DL / f"{name}.csv", encoding="utf-8", newline="") as f:
        yield from csv.DictReader(f)


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


names = defaultdict(list)
for r in rows("SpellName"):
    names[r["Name_lang"]].append(int(r["ID"]))
levels = {int(r["SpellID"]): r for r in rows("SpellLevels") if r["DifficultyID"] == "0"}
power = defaultdict(list)
for r in rows("SpellPower"):
    power[int(r["SpellID"])].append(r)
effects = defaultdict(dict)
for r in rows("SpellEffect"):
    if r["DifficultyID"] == "0":
        effects[int(r["SpellID"])][int(r["EffectIndex"])] = r
cooldowns = {}
if (DL / "SpellCooldowns.csv").exists():
    cooldowns = {int(r["SpellID"]): r for r in rows("SpellCooldowns") if r["DifficultyID"] == "0"}

# Server hotfixes the game tables on wago.tools do not show yet. Each applies only while the table still has
# the value from before the hotfix, so a later change in the game data wins.
# 10 Nov 2026 (Blizzard, "WoW: Forever Hotfixes"): Stormstrike 100% weapon damage (was 150%), 8 sec cooldown
# (was 6); Mental Dexterity converts 33/66/100% of Intellect (was 50/100/150%), not readable from the tables.
HOTFIXES = {"stormstrike": {"pct": (150, 100), "cd": (6, 8)}}
MENTAL_DEXTERITY = [33, 66, 100]


def ranks(name, power_type=None, need=lambda e: True):
    """Player ranks of a spell: has a learn level, the right power type, and passes `need`."""
    out = []
    for sid in names.get(name, []):
        lv = levels.get(sid)
        if not lv or int(lv["BaseLevel"]) <= 0:
            continue
        pw = power.get(sid, [])
        if power_type is not None and not any(int(p["PowerType"]) == power_type for p in pw):
            continue
        eff = effects.get(sid, {})
        if not need(eff):
            continue
        out.append((int(lv["BaseLevel"]), int(lv["MaxLevel"] or 0), sid, eff, pw))
    out.sort()
    # one rank per learn level (the game data has a few duplicates)
    seen, uniq = set(), []
    for x in out:
        if x[0] not in seen:
            seen.add(x[0]); uniq.append(x)
    return uniq


def eff_of(eff, effect_type, aura=None):
    for e in eff.values():
        if int(e["Effect"]) == effect_type and (aura is None or int(e["EffectAura"]) == aura):
            return e
    return None


mech = {}

# --- Shaman -------------------------------------------------------------------------------
mech["earthShock"] = [
    {"lv": lv, "max": mx, "id": sid, "base": num(e["EffectBasePointsF"]), "perLevel": num(e["EffectRealPointsPerLevel"]),
     "coef": num(e["EffectBonusCoefficient"])}
    for lv, mx, sid, eff, _ in ranks("Earth Shock", 0, lambda f: eff_of(f, 2) is not None)
    for e in [eff_of(eff, 2)]]
mech["windfury"] = [
    {"lv": lv, "max": mx, "id": sid, "ap": num(e["EffectBasePointsF"]), "perLevel": num(e["EffectRealPointsPerLevel"]),
     "attacks": int(num(x["EffectBasePointsF"])) if x else 1}
    for lv, mx, sid, eff, _ in ranks("Windfury Weapon", None, lambda f: eff_of(f, 6, 99) is not None)
    for e, x in [(eff_of(eff, 6, 99), eff_of(eff, 19))]]

# Windfury Totem: the weapon enchant it puts on party members (one extra attack with bonus attack power).
# Since the hotfix of 10 Nov 2026 it works together with the shaman's own Windfury Weapon.
mech["windfuryTotem"] = [
    {"lv": lv, "max": mx, "id": sid, "ap": num(e["EffectBasePointsF"]), "perLevel": num(e["EffectRealPointsPerLevel"]),
     "attacks": int(num(x["EffectBasePointsF"])) if x else 1}
    for lv, mx, sid, eff, _ in ranks("Windfury Totem", None, lambda f: eff_of(f, 6, 99) is not None and eff_of(f, 19) is not None)
    for e, x in [(eff_of(eff, 6, 99), eff_of(eff, 19))]]

# Stormstrike: weapon damage (%), cooldown (sec), bonus to the next Nature spells (%)
ss = []
for lv, mx, sid, eff, _ in ranks("Stormstrike", None, lambda f: eff_of(f, 31) is not None):
    cd = cooldowns.get(sid)
    ss.append({"lv": lv, "id": sid, "pct": num(eff_of(eff, 31)["EffectBasePointsF"]),
               "cd": num(cd["RecoveryTime"]) / 1000 if cd and num(cd["RecoveryTime"]) else 6.0,
               "nature": num(eff_of(eff, 6, 271)["EffectBasePointsF"]) if eff_of(eff, 6, 271) else 20.0})
for r in ss:
    for k, (before, after) in HOTFIXES["stormstrike"].items():
        if r[k] == before:
            print(f"hotfix: Stormstrike {k} {before} -> {after} (game tables not updated yet)")
            r[k] = float(after)
        elif r[k] != after:
            print(f"note: Stormstrike {k} is {r[k]} in the game tables (hotfix said {after}); using the tables")
mech["stormstrike"] = ss
mech["mentalDexterity"] = MENTAL_DEXTERITY

# --- Druid (Cat Form) ---------------------------------------------------------------------
ENERGY = 3


def cost(pw):
    return next((int(num(p["ManaCost"])) for p in pw if int(p["PowerType"]) == ENERGY), 0)


def weapon_attack(name):
    return [{"lv": lv, "id": sid, "pct": num(eff_of(eff, 31)["EffectBasePointsF"]), "flat": num(eff_of(eff, 58)["EffectBasePointsF"]),
             "energy": cost(pw)}
            for lv, mx, sid, eff, pw in ranks(name, ENERGY, lambda f: eff_of(f, 31) is not None and eff_of(f, 58) is not None)]


mech["claw"] = weapon_attack("Claw")
mech["shred"] = weapon_attack("Shred")
mech["rake"] = [
    {"lv": lv, "id": sid, "direct": num(eff_of(eff, 2)["EffectBasePointsF"]), "tick": num(eff_of(eff, 6, 3)["EffectBasePointsF"]),
     "period": num(eff_of(eff, 6, 3)["EffectAuraPeriod"]) / 1000, "energy": cost(pw)}
    for lv, mx, sid, eff, pw in ranks("Rake", ENERGY, lambda f: eff_of(f, 2) is not None and eff_of(f, 6, 3) is not None)]
mech["rip"] = [
    {"lv": lv, "id": sid, "tick": num(e["EffectBasePointsF"]), "tickPerCp": num(e["EffectPointsPerResource"]),
     "period": num(e["EffectAuraPeriod"]) / 1000, "energy": cost(pw)}
    for lv, mx, sid, eff, pw in ranks("Rip", ENERGY, lambda f: eff_of(f, 6, 3) is not None)
    for e in [eff_of(eff, 6, 3)]]
mech["bite"] = [
    {"lv": lv, "id": sid, "base": num(e["EffectBasePointsF"]), "perCp": num(e["EffectPointsPerResource"]), "energy": cost(pw)}
    for lv, mx, sid, eff, pw in ranks("Ferocious Bite", ENERGY, lambda f: eff_of(f, 2) is not None)
    for e in [eff_of(eff, 2)]]

# --- typical mob health per level (median of normal, single-level NPCs in QuestieDB) ---------
qfile = DL / "questie.json"
if qfile.exists():
    import statistics
    by_level = defaultdict(list)
    for n in json.loads(qfile.read_text(encoding="utf-8"))["npcs"].values():
        lv, hp = n.get("minLevel"), n.get("maxLevelHealth")
        if n.get("rank", 0) == 0 and lv and lv == n.get("maxLevel") and hp and lv <= 63:
            by_level[lv].append(hp)
    mech["mobHp"] = {str(lv): round(statistics.median(v)) for lv, v in sorted(by_level.items()) if len(v) >= 5}

for k, v in mech.items():
    if isinstance(v, list) and v and isinstance(v[0], dict):
        print(f"{k}: {len(v)} ranks, levels {[r['lv'] for r in v]}")
    else:
        print(f"{k}: {v if isinstance(v, list) else str(len(v)) + ' levels'}")
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(mech, indent=1), encoding="utf-8")
