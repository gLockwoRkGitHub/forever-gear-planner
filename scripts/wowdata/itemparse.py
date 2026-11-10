"""Turn Wowhead WoW Forever tooltips (and equip-effect texts) into planner stats.

Stat keys used by the planner:
  str agi int sta spi armor ap feralAp sp natureSp hit crit (percent) hitR critR (rating points)
  exp haste def dodge (percent) wpnDmg
"""
import html
import re

PROF_NAMES = {"Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring",
              "Mining", "Herbalism", "Skinning", "Fishing", "Cooking", "First Aid"}
STAT_IDS = {"3": "agi", "4": "str", "5": "int", "6": "spi", "7": "sta"}
TOOLTIP_URL = "https://nether.wowhead.com/forever/tooltip/item/{}"


def _add(stats, key, value):
    stats[key] = round(stats.get(key, 0) + value, 2)


def parse_equip(body, stats):
    """Parse one 'Equip:' effect text into stats. Returns True when it was understood."""
    rules = [
        (r"\+(\d+) Attack Power in Cat, Bear,.*forms? only\.?", "feralAp", int),
        (r"Increased Defense \+(\d+)\.?", "def", int),
        (r"Increases your chance to dodge an attack by ([\d.]+)%\.?", "dodge", float),
        (r"\+(\d+) Attack Power\.?", "ap", int),
        (r"Increases damage and healing done by magical spells and effects by up to (\d+)\.?", "sp", int),
        (r"Increases healing done by up to \d+ and damage done by up to (\d+) for all magical spells and effects\.?", "sp", int),
        (r"Increases (?:spell power|spell damage) by (\d+)\.?", "sp", int),
        (r"Increases damage done by Nature spells and effects by up to (\d+)\.?", "natureSp", int),
        (r"Improves your chance to hit(?: with all spells and attacks)? by ([\d.]+)%\.?", "hit", float),
        (r"Improves your chance to get a critical strike(?: with all spells and attacks)? by ([\d.]+)%\.?", "crit", float),
        (r"(?:Increases your expertise by|Increases expertise by|\+)(\d+) Expertise\.?", "exp", int),
        (r"Increases your expertise by (\d+)\.?", "exp", int),
        (r"\+(\d+) Weapon Damage\.?", "wpnDmg", int),
    ]
    for pattern, key, conv in rules:
        m = re.fullmatch(pattern, body.strip(), re.I)
        if m:
            _add(stats, key, conv(m.group(1)))
            return True
    return False


def tooltip_lines(tt):
    txt = re.sub(r"<br\s*/?>", "\n", tt)
    txt = re.sub(r"</(td|th|tr|table|div)>", "\n", txt)
    txt = re.sub(r"<!--.*?-->", "", txt)
    txt = html.unescape(re.sub(r"<[^>]+>", "", txt)).replace("\xa0", " ")
    return [l.strip() for l in txt.split("\n") if l.strip()]


def parse_tooltip(data):
    """data: the JSON Wowhead returns for an item tooltip."""
    tt = data["tooltip"]
    p = {"stats": {}, "notes": []}
    m = re.search(r"<!--ilvl-->(\d+)", tt)
    p["ilvl"] = int(m.group(1)) if m else 0
    m = re.search(r"<!--rlvl-->(\d+)", tt)
    p["req"] = int(m.group(1)) if m else 0
    m = re.search(r"<!--amr-->(\d+) Armor", tt)
    if m:
        p["stats"]["armor"] = int(m.group(1))
    for m in re.finditer(r"<!--stat(\d+)-->([+-]?)(\d+)", tt):
        key = STAT_IDS.get(m.group(1))
        if key:
            _add(p["stats"], key, int(m.group(3)) * (-1 if m.group(2) == "-" else 1))
    lines = tooltip_lines(tt)
    text = "\n".join(lines)
    m = re.search(r"(\d+) - (\d+) Damage", text)
    if m:
        p["dmgMin"], p["dmgMax"] = int(m.group(1)), int(m.group(2))
    m = re.search(r"Speed ([\d.]+)", text)
    if m:
        p["speed"] = float(m.group(1))
    m = re.search(r"\(([\d.]+) damage per second\)", text)
    if m:
        p["dps"] = float(m.group(1))
    p["random"] = "<random enchantment>" in text.lower()
    p["boe"] = "Binds when equipped" in text
    p["bop"] = "Binds when picked up" in text
    m = re.search(r"Classes: ([^\n]+)", text)
    p["classes"] = [c.strip() for c in m.group(1).split(",")] if m else None
    m = re.search(r"Races: ([^\n]+)", text)
    p["races"] = [c.strip() for c in m.group(1).split(",")] if m else None
    m = re.search(r"Requires ([A-Za-z' :-]+?) - (Friendly|Honored|Revered|Exalted)", text)
    p["reputation"] = f"{m.group(1)} - {m.group(2)}" if m else None
    p["pvpRank"] = bool(re.search(r"Requires [A-Za-z ]*Rank|Requires .*Grand Marshal|Requires .*High Warlord", text))
    m = re.search(r"Requires (" + "|".join(sorted(PROF_NAMES)) + r") \((\d+)\)", text)
    p["needsProfession"] = f"{m.group(1)} ({m.group(2)})" if m else None
    m = re.search(r"Dropped by: ([^\n]+)", text)
    p["droppedBy"] = m.group(1).strip() if m else None
    m = re.search(r"Drop Chance: ([\d.]+)%", text)
    p["dropChance"] = float(m.group(1)) if m else None
    p["sodLeftover"] = "May not be in WoW: Forever" in tt

    for line in lines:
        if not (line.startswith("Equip:") or line.startswith("Chance on hit:") or line.startswith("Use:")):
            continue
        body = line.split(":", 1)[1].strip()
        if line.startswith("Equip:") and parse_equip(body, p["stats"]):
            continue
        p["notes"].append(line)
    # Forever rating lines shown as plain "+N Hit" / "+N Expertise" / "+N Critical Strike"
    for m in re.finditer(r"^\+(\d+) (Hit|Expertise|Critical Strike|Crit|Haste|Attack Power|Spell Power)$", text, re.M):
        key = {"Hit": "hitR", "Expertise": "exp", "Critical Strike": "critR", "Crit": "critR", "Haste": "haste",
               "Attack Power": "ap", "Spell Power": "sp"}[m.group(2)]
        _add(p["stats"], key, int(m.group(1)))
    return p
