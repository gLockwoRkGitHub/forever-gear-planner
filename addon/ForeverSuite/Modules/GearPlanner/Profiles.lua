-- Character profiles, the same as on the website (site/app.js): which armor and weapons each class
-- uses from which level, and the stat-weight presets.
local _, FS = ...
local G = {}
FS.Gear = G

G.SLOTS = { "Two-Hand", "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket", "Relic" }
G.SOURCES = { "Quest", "Dungeon", "Vendor", "Crafted" }
G.PROFESSIONS = { "Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring" }

G.PROFILES = {
  shaman = {
    key = "shaman", label = "Enhancement Shaman", short = "Enh. Shaman", cls = "Shaman", classFile = "SHAMAN", bit = 64,
    color = "2b8cff",
    armor = { Misc = 1, Cloth = 1, Leather = 1, Mail = 40, Totem = 1 },
    weapons = { ["Two-Handed Axe"] = 1, ["Two-Handed Mace"] = 1, ["Staff"] = 1 },
    relic = "Totem", profs = { "Enchanting" },
    presetOrder = { "Level model", "Enhancement (estimate)" },
    presets = {
      ["Level model"] = { model = true, base = "Enhancement (estimate)" },
      ["Enhancement (estimate)"] = {
        str = 1.0, agi = 0.4, int = 0.5, sta = 0.15, spi = 0.1, ap = 0.5, feralAp = 0, crit = 10, hit = 8, critR = 0.8, hitR = 0.8,
        exp = 0.8, haste = 0.5, armor = 0.01, def = 0, dodge = 0, sp = 0.2, natureSp = 0.15, dps = 8, slow = 1.5,
      },
    },
  },
  druid = {
    key = "druid", label = "Feral Druid", short = "Feral Druid", cls = "Druid", classFile = "DRUID", bit = 1024,
    color = "ff7d0a",
    armor = { Misc = 1, Cloth = 1, Leather = 1, Idol = 1 },
    weapons = { ["Staff"] = 1, ["Two-Handed Mace"] = 1, ["Polearm"] = 20 },
    relic = "Idol", profs = {},
    presetOrder = { "Level model (Cat)", "Cat (estimate)", "Bear (tank)" },
    presets = {
      ["Level model (Cat)"] = { model = true, base = "Cat (estimate)" },
      ["Cat (estimate)"] = {
        str = 0.9, agi = 1.0, int = 0.05, sta = 0.2, spi = 0.05, ap = 0.45, feralAp = 0.45, crit = 12, hit = 12, critR = 1.0, hitR = 1.0,
        exp = 1.0, haste = 0.8, armor = 0.02, def = 0.1, dodge = 2, sp = 0, natureSp = 0, dps = 6, slow = 0,
      },
      ["Bear (tank)"] = {
        str = 0.3, agi = 0.6, int = 0.02, sta = 1.0, spi = 0.02, ap = 0.15, feralAp = 0.15, crit = 2, hit = 3, critR = 0.2, hitR = 0.3,
        exp = 0.5, haste = 0.2, armor = 0.08, def = 1.2, dodge = 15, sp = 0, natureSp = 0, dps = 1.5, slow = 0,
      },
    },
  },
}
G.CLASS_PROFILE = { SHAMAN = "shaman", DRUID = "druid" }

G.STAT_SHORT = { str = "Str", agi = "Agi", int = "Int", sta = "Sta", spi = "Spi", ap = "AP", feralAp = "Feral AP", sp = "SP",
  natureSp = "Nature SP", crit = "% Crit", hit = "% Hit", hitR = "Hit", critR = "Crit", exp = "Expertise", haste = "Haste",
  def = "Defense", dodge = "% Dodge", wpnDmg = "Wpn Dmg", armor = "Armor" }
G.STAT_ORDER = { "str", "agi", "int", "sta", "spi", "ap", "feralAp", "sp", "natureSp", "hit", "crit", "hitR", "critR", "exp", "haste", "def", "dodge", "wpnDmg" }

-- typical level ranges of the dungeons (wowtbc.gg dungeon list, WoW Forever), as on the website
G.DUNGEON_RANGES = {
  ["Ragefire Chasm"] = { 13, 18 }, ["The Hall of Thanes"] = { 13, 18 }, ["Wailing Caverns"] = { 15, 25 }, ["Ruins of Lordaeron"] = { 16, 23 },
  ["Deadmines"] = { 18, 23 }, ["Shadowfang Keep"] = { 22, 30 }, ["Stormwind Stockade"] = { 22, 30 }, ["Blackfathom Deeps"] = { 24, 32 },
  ["Excavation Site: Wetlands"] = { 26, 32 }, ["City of Dalaran"] = { 28, 34 }, ["Scarlet Monastery"] = { 28, 45 }, ["Gnomeregan"] = { 29, 38 },
  ["Razorfen Kraul"] = { 30, 40 }, ["The Drowned City"] = { 35, 40 }, ["Krol'dok Stronghold"] = { 40, 45 }, ["Razorfen Downs"] = { 40, 50 },
  ["Uldaman"] = { 42, 52 }, ["Zul'Farrak"] = { 44, 54 }, ["Maraudon"] = { 46, 55 }, ["Alcaz Prison"] = { 48, 53 }, ["Sunken Temple"] = { 50, 60 },
  ["Blackrock Depths"] = { 52, 60 }, ["Blackmaw Hold"] = { 55, 60 }, ["Blackrock Spire"] = { 55, 60 }, ["Dire Maul"] = { 58, 60 },
  ["Stratholme"] = { 58, 60 }, ["Scholomance"] = { 58, 60 },
}
-- instance IDs of the classic dungeons (the game names them in the client's language)
G.INSTANCE_IDS = {
  [389] = "Ragefire Chasm", [43] = "Wailing Caverns", [36] = "Deadmines", [33] = "Shadowfang Keep", [48] = "Blackfathom Deeps",
  [34] = "Stormwind Stockade", [90] = "Gnomeregan", [47] = "Razorfen Kraul", [189] = "Scarlet Monastery", [129] = "Razorfen Downs",
  [70] = "Uldaman", [209] = "Zul'Farrak", [349] = "Maraudon", [109] = "Sunken Temple", [230] = "Blackrock Depths",
  [229] = "Blackrock Spire", [429] = "Dire Maul", [289] = "Scholomance", [329] = "Stratholme",
}
