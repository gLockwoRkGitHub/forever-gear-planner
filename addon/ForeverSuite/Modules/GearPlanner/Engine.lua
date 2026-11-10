-- Gear engine: scoring, eligibility and ranking, the same rules as the website (site/app.js),
-- plus turning item links from the game into scored items (exact random-suffix stats included).
local _, FS = ...
local G, U = FS.Gear, FS.U

G.byId, G.bySlot, G.dungeonItems, G.questItems = {}, {}, {}, {}

local function hasBit(v, b) return v and b and math.floor(v / b) % 2 == 1 end

function G:IndexData()
  for _, it in ipairs(FS.Data.items) do
    self.byId[it.id] = it
    local list = self.bySlot[it.sl]
    if not list then list = {}; self.bySlot[it.sl] = list end
    list[#list + 1] = it
    for _, s in ipairs(it.src or {}) do
      local d = (s.t == "Dungeon" and s.w) or (s.t == "Quest" and s.dq) or nil
      if d then
        local dl = self.dungeonItems[d]
        if not dl then dl = { set = {} }; self.dungeonItems[d] = dl end
        if not dl.set[it] then dl.set[it] = true; dl[#dl + 1] = it end
      end
      if s.t == "Quest" and s.id then
        local ql = self.questItems[s.id]
        if not ql then ql = {}; self.questItems[s.id] = ql end
        ql[#ql + 1] = it
      end
    end
  end
end

-- --- scoring ---------------------------------------------------------------------------------
function G.ScoreW(it, w)
  local s = 0
  for k, v in pairs(it.st or {}) do
    if k ~= "wpnDmg" and type(w[k]) == "number" then s = s + v * w[k] end
  end
  if it.dps and w.__model and it.sl == "Two-Hand" then return s + w.__model.weapon(it) end
  if it.dps then
    local dps = it.dps + ((it.st and it.st.wpnDmg and it.speed) and it.st.wpnDmg / it.speed or 0)
    s = s + dps * (w.dps or 0) + math.max(0, (it.speed or 0) - 3.0) * 10 * (w.slow or 0)
  end
  return s
end

-- A source counts when it is enabled, reachable at this level and open to this class.
-- Bind-on-pickup crafts can only be made by the crafter, so they need the profession.
-- Quests the character has already turned in are gone (when the game tells us).
function G.SrcUsable(it, s, level, st, ignoreToggles)
  local set = st.settings
  if (not ignoreToggles and not set.sources[s.t]) or (s.g or 0) > level then return false end
  if s.t == "Quest" and s.rc and s.rc ~= 0 and not hasBit(s.rc, st.prof.bit) then return false end
  if s.t == "Crafted" and it.bop and not set.profs[s.n] then return false end
  if s.t == "Quest" and s.id and set.hideDone and st.questDone and st.questDone(s.id) then return false end
  return true
end

local function hasClass(cl, cls)
  if type(cl) == "string" then return cl:find(cls, 1, true) ~= nil end
  for _, c in ipairs(cl) do if c == cls then return true end end
  return false
end

function G.TypeGate(it, prof) return prof.armor[it.ty] or prof.weapons[it.ty] end

-- Can this character wear the item at this level at all (type, class, professions)?
-- live = an item in hand whose real stats we know (random enchants are then fine).
function G.Wearable(it, level, st, live)
  local gate = G.TypeGate(it, st.prof)
  if not gate or level < gate then return false end
  if it.cl and not hasClass(it.cl, st.prof.cls) then return false end
  if it.rnd and not live and not st.settings.random then return false end
  if it.np and not st.settings.profs[(it.np:gsub(" %(.*$", ""))] then return false end
  return true
end

function G.Eligible(it, level, st)
  if not G.Wearable(it, level, st) then return false end
  for _, s in ipairs(it.src or {}) do if G.SrcUsable(it, s, level, st) then return true end end
  return false
end

local function isPair(slot) return slot == "Finger" or slot == "Trinket" end

-- Score of what is worn now: the weaker of two rings/trinkets (that is the one to replace), an empty slot is 0.
function G.BaselineScore(eq, slot, w)
  if #eq == 0 then return 0 end
  if isPair(slot) and #eq < 2 then return 0 end
  local best
  for _, e in ipairs(eq) do
    local sc = G.ScoreW(e, w)
    if best == nil or (isPair(slot) and sc < best) or (not isPair(slot) and sc > best) then best = sc end
  end
  return best
end
-- The equipped item an upgrade would replace (none while a ring or trinket slot is free).
function G.BaselineItem(eq, slot, w)
  if #eq == 0 or (isPair(slot) and #eq < 2) then return nil end
  local pick, best
  for _, e in ipairs(eq) do
    local sc = G.ScoreW(e, w)
    if best == nil or (isPair(slot) and sc < best) or (not isPair(slot) and sc > best) then best, pick = sc, e end
  end
  return pick
end

-- equal scores (e.g. relics, which only have special effects) fall back to item level
local function ranked(items, w)
  local out = {}
  for _, it in ipairs(items) do out[#out + 1] = { it = it, s = G.ScoreW(it, w) } end
  table.sort(out, function(a, b)
    if a.s ~= b.s then return a.s > b.s end
    if a.it.il ~= b.it.il then return (a.it.il or 0) > (b.it.il or 0) end
    return a.it.id < b.it.id
  end)
  return out
end
G.Ranked = ranked

-- Everything one slot section needs: worn items, baseline, top candidates, next upgrade within 3 levels.
function G:SlotData(st, slot, level, topN)
  local w = G.State:Weights(st, level)
  local all = self.bySlot[slot] or {}
  local eq = st.equipped[slot] or {}
  local base = st.hasGear and G.BaselineScore(eq, slot, w) or nil
  local ref = st.hasGear and G.BaselineItem(eq, slot, w) or nil
  local eqIds = {}
  for _, e in ipairs(eq) do eqIds[e.id] = true end
  local cands = {}
  for _, it in ipairs(all) do
    if not eqIds[it.id] and G.Eligible(it, level, st) then cands[#cands + 1] = it end
  end
  local pool = ranked(cands, w)
  local onlyUp = base ~= nil and st.settings.onlyUp and slot ~= "Relic"
  local top, seen = {}, {}
  for _, p in ipairs(pool) do
    if not onlyUp or p.s > base + 0.05 then
      if not seen[p.it.n] then
        seen[p.it.n] = true
        top[#top + 1] = p
        if #top >= (topN or 3) then break end
      end
    end
  end
  local best = math.max(pool[1] and pool[1].s or -math.huge, base or -math.huge)
  local nextUp
  if slot ~= "Relic" then
    for L = level + 1, math.min(60, level + 3) do
      local later = {}
      for _, it in ipairs(all) do
        if not eqIds[it.id] and G.Eligible(it, L, st) and not G.Eligible(it, level, st) then later[#later + 1] = it end
      end
      local r = ranked(later, w)
      if r[1] and r[1].s > best + 0.05 then nextUp = { L = L, it = r[1].it, s = r[1].s }; break end
    end
  end
  return { slot = slot, eq = eq, base = base, ref = ref, pool = pool, top = top, onlyUp = onlyUp, next = nextUp, w = w }
end

-- The first source of an item usable at this level, as short text.
function G.ShortSource(it, level, st)
  local s
  for _, x in ipairs(it.src or {}) do if G.SrcUsable(it, x, level, st) then s = x; break end end
  s = s or (it.src and it.src[1])
  if not s then return nil end
  if s.t == "Dungeon" then return s.t, s.w .. (s.n and not s.n:find("^trash") and (" · " .. s.n) or "") end
  if s.t == "Quest" then return s.t, s.n .. (s.w and (" · " .. s.w) or "") end
  if s.t == "Vendor" then return s.t, s.n .. (s.w and (" · " .. s.w) or "") end
  return s.t, s.n .. (it.bop and " · craft it yourself" or " · tradeable")
end

function G.StatLine(it)
  local parts = {}
  if it.dps then parts[#parts + 1] = ("%.1f DPS · %.2f speed"):format(it.dps, it.speed or 0) end
  for _, k in ipairs(G.STAT_ORDER) do
    local v = it.st and it.st[k]
    if v and v ~= 0 then parts[#parts + 1] = (v > 0 and "+" or "") .. v .. " " .. G.STAT_SHORT[k] end
  end
  if it.st and it.st.armor then parts[#parts + 1] = it.st.armor .. " Armor" end
  return #parts > 0 and table.concat(parts, ", ") or "no stats"
end

-- --- items from the game ---------------------------------------------------------------------
local STAT_KEYS = {
  ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_INTELLECT_SHORT = "int",
  ITEM_MOD_STAMINA_SHORT = "sta", ITEM_MOD_SPIRIT_SHORT = "spi", ITEM_MOD_ATTACK_POWER_SHORT = "ap",
  ITEM_MOD_FERAL_ATTACK_POWER_SHORT = "feralAp", ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp",
  ITEM_MOD_CRIT_RATING_SHORT = "critR", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "critR", ITEM_MOD_HIT_RATING_SHORT = "hitR",
  ITEM_MOD_HIT_MELEE_RATING_SHORT = "hitR", ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_EXPERTISE_RATING_SHORT = "exp",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", RESISTANCE0_NAME = "armor",
}
local SUFFIX_KEYS = { str = true, agi = true, int = true, sta = true, spi = true, ap = true, sp = true, feralAp = true }
G.EQUIP_SLOT = {
  INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back", INVTYPE_CHEST = "Chest",
  INVTYPE_ROBE = "Chest", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands", INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs",
  INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger", INVTYPE_TRINKET = "Trinket", INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_RELIC = "Relic",
}
local ARMOR_SUB = { [0] = "Misc", [1] = "Cloth", [2] = "Leather", [3] = "Mail", [4] = "Plate", [6] = "Shield", [7] = "Libram", [8] = "Idol", [9] = "Totem", [11] = "Relic" }
local WEAPON_SUB = { [1] = "Two-Handed Axe", [5] = "Two-Handed Mace", [6] = "Polearm", [8] = "Two-Handed Sword", [10] = "Staff" }

local function liveStats(link)
  local raw = U.ItemStats(link)
  if not raw then return nil end
  local st, dps = {}, nil
  for k, v in pairs(raw) do
    v = U.num(v)
    if v then
      if k == "ITEM_MOD_DAMAGE_PER_SECOND_SHORT" then dps = v
      elseif STAT_KEYS[k] then st[STAT_KEYS[k]] = (st[STAT_KEYS[k]] or 0) + v end
    end
  end
  return st, dps
end

local function weaponFromTooltip(link)
  local lines = U.TooltipLines(link)
  if not lines then return end
  for _, l in ipairs(lines) do
    local sp = l.r and l.r:match("(%d+[%.,]%d+)")
    local speed = sp and tonumber((sp:gsub(",", ".")))
    local lo, hi
    if l.l then lo, hi = l.l:match("(%d+)%s*%-%s*(%d+)") end
    if speed and lo then return tonumber(lo), tonumber(hi), speed end
  end
end

local linkCache = {}

-- An item link (or ID) as a scored item: the data entry, with exact stats for random suffixes;
-- items missing from the data are built from the game's own item info. nil if not gear we rank.
function G:ItemFromLink(link)
  if not link or U.secret(link) then return nil end
  if type(link) == "number" then return self.byId[link] end
  local hit = linkCache[link]
  if hit ~= nil then return hit or nil end
  local id = U.ItemIDFromLink(link)
  if not id then return nil end
  local base = self.byId[id]
  local out
  if base then
    if base.rnd and U.SuffixFromLink(link) ~= 0 then
      local st = liveStats(link)
      if st and next(st) then
        out = U.copy(base)
        out.st = U.copy(base.st)
        for k, v in pairs(st) do if SUFFIX_KEYS[k] or out.st[k] == nil then out.st[k] = v end end
        out.live, out.link = true, link
      else
        U.RequestItem(id)
        return base                       -- not cached yet: base stats, try again next time
      end
    else
      out = base
    end
  else
    local inst = U.ItemInfoInstant(link)
    local slot = inst and G.EQUIP_SLOT[inst.equipLoc]
    if not slot then linkCache[link] = false; return nil end
    local info = U.ItemInfo(link)
    if not info then U.RequestItem(id); return nil end
    local ty = (inst.classID == 2 and WEAPON_SUB[inst.subclassID]) or (inst.classID == 4 and ARMOR_SUB[inst.subclassID]) or "Misc"
    local st, dps = liveStats(link)
    if not st then return nil end
    out = { id = id, n = info.name, q = info.q, il = info.il, rq = info.rq or 0, sl = slot, ty = ty, st = st, src = {},
      unknown = true, live = true, link = link }
    if slot == "Two-Hand" then
      local lo, hi, speed = weaponFromTooltip(link)
      out.speed = speed or 3
      out.dps = dps or (lo and (lo + hi) / 2 / out.speed) or nil
      out.dmgMin, out.dmgMax = lo, hi
    end
  end
  linkCache[link] = out
  return out
end

function G:ClearLinkCache() linkCache = {} end

-- --- verdict for an item in hand (tooltip, quest reward, loot) --------------------------------
-- kind: "up", "down", "later" (level too low), "no" (can't use), "equipped", "relic"
function G:Evaluate(st, it)
  if not st or not it or not it.sl then return nil end
  local level = st.liveLevel or st.level
  for _, e in ipairs(st.equipped[it.sl] or {}) do
    if e.id == it.id and (not it.live or e.link == it.link or not e.live) then return { kind = "equipped" } end
  end
  local gate = G.TypeGate(it, st.prof)
  if not gate or (it.cl and not hasClass(it.cl, st.prof.cls)) then return { kind = "no" } end
  if it.np and not st.settings.profs[(it.np:gsub(" %(.*$", ""))] then return { kind = "no", why = it.np } end
  local from = math.max(gate, it.rq or 0)
  local w = G.State:Weights(st, level)
  local sc = G.ScoreW(it, w)
  if it.sl == "Relic" then return { kind = from > level and "later" or "relic", from = from, score = sc } end
  local base = st.hasGear and G.BaselineScore(st.equipped[it.sl] or {}, it.sl, w) or 0
  local d = sc - base
  if from > level then return { kind = "later", from = from, score = sc, delta = d } end
  return { kind = d > 0.05 and "up" or "down", score = sc, delta = d }
end
