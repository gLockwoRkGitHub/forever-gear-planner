-- Character states the engine ranks for: yourself (level, gear, sheet and talents read live from the game)
-- and partners (sent by their Forever Suite in the group). Also the stat weights per state and level.
local _, FS = ...
local G, U = FS.Gear, FS.U
local S = {}
G.State = S

S.partners = {}           -- name -> state
S.previewLevel = nil      -- level picked in the window (nil: live level)

-- inventory slot -> planner slot (16 main hand, 18 the relic slot of classic clients)
G.INV = { [1] = "Head", [2] = "Neck", [3] = "Shoulder", [15] = "Back", [5] = "Chest", [9] = "Wrist", [10] = "Hands",
  [6] = "Waist", [7] = "Legs", [8] = "Feet", [11] = "Finger", [12] = "Finger", [13] = "Trinket", [14] = "Trinket",
  [16] = "Two-Hand", [18] = "Relic" }

local function set(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end
function S.SetToList(s, order)
  local out = {}
  for _, v in ipairs(order) do if s and s[v] then out[#out + 1] = v end end
  return out
end

-- --- settings --------------------------------------------------------------------------------
-- Your planner settings live per character; nil means default.
function S:Settings(prof)
  local db = FS.cdb.gear
  if db.profile ~= prof.key then
    for k in pairs(db) do db[k] = nil end
    db.profile = prof.key
  end
  local detected = U.Professions()
  return {
    preset = (db.preset and prof.presets[db.preset]) and db.preset or prof.presetOrder[1],
    weights = db.weights or {},
    sources = db.sources and set(db.sources) or set(G.SOURCES),
    profs = db.profs and set(db.profs) or detected or set(prof.profs),
    profsAuto = db.profs == nil,
    profsDetected = detected ~= nil,
    random = db.random == true,
    onlyUp = db.onlyUp ~= false,
    hideDone = db.hideDone ~= false,
    topN = db.topN or 3,
  }
end

function S:Set(key, value)
  FS.cdb.gear[key] = value
  self:Refresh("settings")
end

-- --- reading the game ------------------------------------------------------------------------
local function liveSheet()
  local function stat(i)
    if not UnitStat then return nil end
    local ok, _, eff = pcall(UnitStat, "player", i)
    return ok and U.num(eff) or nil
  end
  local sh = { str = stat(1), agi = stat(2), sta = stat(3), int = stat(4), spi = stat(5) }
  if UnitAttackPower then
    local ok, base, pos, neg = pcall(UnitAttackPower, "player")
    if ok and U.num(base) then sh.ap = U.num(base) + (U.num(pos) or 0) + (U.num(neg) or 0) end
  end
  if GetCritChance then local ok, v = pcall(GetCritChance); sh.crit = ok and U.num(v) or nil end
  if GetSpellCritChance then local ok, v = pcall(GetSpellCritChance, 4); sh.spellCrit = ok and U.num(v) or nil end
  if GetSpellBonusDamage then local ok, v = pcall(GetSpellBonusDamage, 4); sh.sp = ok and U.num(v) or nil end
  if GetDodgeChance then local ok, v = pcall(GetDodgeChance); sh.dodge = ok and U.num(v) or nil end
  if GetParryChance then local ok, v = pcall(GetParryChance); sh.parry = ok and U.num(v) or nil end
  if not (sh.str and sh.agi and sh.ap and sh.crit) then return nil end
  return sh
end

-- talents with their tooltip text; only on English clients (the model reads English descriptions)
local scanTip
local function scanTalents()
  if not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return nil end
  if not (GetLocale and GetLocale():find("^en")) then return nil end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "ForeverSuiteScanTip", nil, "GameTooltipTemplate")
  end
  local list, described = {}, false
  local okTabs, tabs = pcall(GetNumTalentTabs)
  if not okTabs or not tabs then return nil end
  for tab = 1, tabs do
    local okN, n = pcall(GetNumTalents, tab)
    for i = 1, (okN and n or 0) do
      local ok, name, _, _, _, rank = pcall(GetTalentInfo, tab, i)
      if ok and name and (tonumber(rank) or 0) > 0 then
        local text = {}
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        if pcall(scanTip.SetTalent, scanTip, tab, i) then
          for l = 2, scanTip:NumLines() do
            local fs = _G["ForeverSuiteScanTipTextLeft" .. l]
            local t = fs and fs:GetText()
            if t and not U.secret(t) then text[#text + 1] = t end
          end
        end
        scanTip:Hide()
        local d = table.concat(text, " ")
        if d ~= "" then described = true end
        list[#list + 1] = { n = name, d = d, r = tonumber(rank) }
      end
    end
  end
  if not described and #list > 0 then return nil end
  return FS.Model.talentNumbers(list), #list
end

local function imported(key)
  local imp = FS.db.imported
  return imp and imp.chars and imp.chars[key], imp and imp.date
end

-- The character sheet the level model starts from. The website's (Blizzard's, taken at logout, without
-- buffs) when it is for your current level, so addon and website rank the same; otherwise the game's own,
-- read live (buffs included). Druids: only the caster-form sheet counts.
function S:ReadSheet(st)
  local sh = liveSheet()
  if sh and st.key == "druid" and GetShapeshiftFormID then
    local ok, form = pcall(GetShapeshiftFormID)
    if ok and form then sh = nil end
  end
  if sh then FS.cdb.sheet = sh end
  local imp = imported(st.key)
  if imp and imp.sheet and imp.sheetLevel and imp.sheetLevel == st.liveLevel then
    st.sheet, st.sheetSrc = imp.sheet, "website"
  elseif sh then
    st.sheet, st.sheetSrc = sh, "game"
  elseif FS.cdb.sheet then
    st.sheet, st.sheetSrc = FS.cdb.sheet, "saved"
  else
    st.sheet, st.sheetSrc = imp and imp.sheet, imp and imp.sheet and "website" or nil
  end
end

function S:ReadTalents(st)
  local ok, tal, count = pcall(scanTalents)
  if ok and tal then
    st.tal, st.talSrc, st.talCount = tal, "game", count
    return
  end
  local imp, date = imported(st.key)
  if imp and imp.tal then
    st.tal, st.talSrc, st.talDate = imp.tal, "website", date
  else
    st.tal, st.talSrc = {}, nil
  end
end

function S:ScanEquipped(st)
  st.equipped, st.items = {}, {}
  for inv, slot in pairs(G.INV) do
    local link = GetInventoryItemLink and GetInventoryItemLink("player", inv)
    if link and not U.secret(link) then
      local it = G:ItemFromLink(link)
      local imp = imported(st.key)
      local we = imp and imp.weaponEnchant
      if it and slot == "Two-Hand" and we and we[tostring(it.id)] then
        it = U.copy(it)                                   -- permanent weapon damage enchant (website import)
        it.enchDmg = we[tostring(it.id)]
      end
      if it and (it.sl == slot or (slot == "Two-Hand" and it.sl == "Two-Hand")) then
        local list = st.equipped[slot] or {}
        list[#list + 1] = it
        st.equipped[slot] = list
        st.items[#st.items + 1] = { slot = slot, it = it, inv = inv }
      end
    end
  end
  st.hasGear = true
end

function S:ScanBags(st)
  st.bags = {}
  local num = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C_Container and C_Container.GetContainerItemID) or GetContainerItemID
  if not num or not itemID then return end
  for bag = 0, 4 do
    local ok, n = pcall(num, bag)
    for slot = 1, (ok and n or 0) do
      local ok2, id = pcall(itemID, bag, slot)
      if ok2 and id then st.bags[id] = true end
    end
  end
end

function S:BuildSelf()
  local _, classFile = UnitClass("player")
  local key = G.CLASS_PROFILE[classFile or ""]
  if not key then self.self = nil; return end
  local st = self.self or {}
  st.key, st.prof, st.isSelf = key, G.PROFILES[key], true
  st.name = U.Me()
  st.liveLevel = UnitLevel("player") or 1
  st.level = self.previewLevel or st.liveLevel
  st.settings = self:Settings(st.prof)
  st.questDone = U.QuestDone
  self:ScanEquipped(st)
  self:ScanBags(st)
  self:ReadSheet(st)
  self:ReadTalents(st)
  st.version = (st.version or 0) + 1
  st._w = nil
  self.self = st
end

-- what = "gear" | "level" | "sheet" | "settings" | "quests" | "bags" | "all"
function S:Refresh(what)
  local st = self.self
  if not st then self:BuildSelf(); FS:Fire("STATE_CHANGED", "all"); return end
  if what == "bags" then self:ScanBags(st); FS:Fire("STATE_CHANGED", what); return end
  if what == "gear" then self:ScanEquipped(st); self:ReadSheet(st) end
  if what == "level" then
    st.liveLevel = UnitLevel("player") or st.liveLevel
    st.level = self.previewLevel or st.liveLevel
    self:ReadSheet(st); self:ReadTalents(st)
  end
  if what == "sheet" then self:ReadSheet(st); self:ReadTalents(st) end
  if what == "settings" then st.settings = self:Settings(st.prof) end
  if what == "all" then self:BuildSelf() end
  st.version = (st.version or 0) + 1
  st._w = nil
  FS:Fire("STATE_CHANGED", what)
end

function S:SetPreviewLevel(L)
  if L then L = math.max(1, math.min(60, math.floor(L + 0.5))) end
  if self.self and L == self.self.liveLevel then L = nil end
  self.previewLevel = L
  if self.self then self.self.level = L or self.self.liveLevel end
  FS:Fire("STATE_CHANGED", "preview")
end

-- --- partner states (built from what their addon sent) -----------------------------------------
-- data: { key, name, level, settings = {preset, weights, sources, profs, random}, sheet, tal, talSrc,
--         gear = { { slot, id, st = {...} or nil, ty, dps, speed, dmgMin, dmgMax } }, done = set or nil }
function S:SetPartner(name, data)
  local prof = data and G.PROFILES[data.key]
  if not prof then self.partners[name] = nil; return end
  local st = { key = data.key, prof = prof, name = name, short = U.FirstName(name), isSelf = false, liveLevel = data.level, level = data.level,
    sheet = data.sheet, tal = data.tal or {}, talSrc = data.talSrc, at = data.at, hasGear = true, equipped = {}, items = {} }
  local s = data.settings or {}
  st.settings = {
    preset = (s.preset and prof.presets[s.preset]) and s.preset or prof.presetOrder[1],
    weights = s.weights or {},
    sources = s.sources and set(s.sources) or set(G.SOURCES),
    profs = set(s.profs or prof.profs),
    random = s.random == true, onlyUp = true, hideDone = data.done ~= nil, topN = 3,
  }
  if data.done then st.questDone = function(id) return data.done[id] == true end end
  for _, g in ipairs(data.gear or {}) do
    local base = G.byId[g.id]
    local it
    if base and not g.st and not g.enchDmg then
      it = base
    elseif base then
      it = U.copy(base); it.st = U.copy(base.st)
      for k, v in pairs(g.st or {}) do it.st[k] = v end
      it.live = g.st ~= nil
      it.enchDmg = g.enchDmg
    else
      it = { id = g.id, n = "item " .. g.id, sl = g.slot, ty = g.ty or "Misc", st = g.st or {}, src = {}, unknown = true,
        dps = g.dps, speed = g.speed, dmgMin = g.dmgMin, dmgMax = g.dmgMax, q = 1, il = 0 }
      local info = U.ItemInfo(g.id)
      if info then it.n, it.q, it.il = info.name, info.q, info.il end
    end
    local list = st.equipped[g.slot] or {}
    list[#list + 1] = it
    st.equipped[g.slot] = list
    st.items[#st.items + 1] = { slot = g.slot, it = it }
  end
  st.version = 1
  self.partners[name] = st
end

function S:Partners()
  local out = {}
  for _, st in pairs(self.partners) do out[#out + 1] = st end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- yourself first, then partners
function S:All()
  local out = {}
  if self.self then out[1] = self.self end
  for _, p in ipairs(self:Partners()) do out[#out + 1] = p end
  return out
end

-- --- stat weights ----------------------------------------------------------------------------
-- preset: another weight preset than the character's own (e.g. "Bear (tank)" for the tooltip)
function S:Weights(st, level, preset)
  level = level or st.level
  if not st._w or st._w.version ~= st.version then st._w = { version = st.version } end
  local prof, cfg = st.prof, st.settings
  preset = (preset and prof.presets[preset]) and preset or cfg.preset
  local key = preset == cfg.preset and level or (preset .. "@" .. level)
  local hit = st._w[key]
  if hit then return hit end
  local p = prof.presets[preset]
  local w
  if not p.model then
    w = U.copy(p)
    if preset == cfg.preset then
      for k, v in pairs(cfg.weights or {}) do if type(v) == "number" then w[k] = v end end
    end
  else
    w = U.copy(prof.presets[p.base])
    local ctx = FS.Model.context(st.key, { sheet = st.sheet, tal = st.tal, items = st.items, level = st.liveLevel or level }, level)
    local m = ctx and FS.Model.weights(ctx)
    if m then
      for _, k in ipairs(FS.Model.KEYS) do w[k] = m.w[k] end
      w.dps, w.slow, w.__model = 0, 0, m
    else
      w.__noModel = true
    end
  end
  st._w[key] = w
  return w
end

-- --- start-up and game events ------------------------------------------------------------------
function G:Init()
  self:IndexData()
  S:BuildSelf()
  local o = {}
  local function later(what, delay)
    FS:Debounce("state:" .. what, delay or 0.4, function() S:Refresh(what) end)
  end
  FS:On("PLAYER_EQUIPMENT_CHANGED", o, function() later("gear") end)
  FS:On("PLAYER_LEVEL_UP", o, function() later("level", 1) end)
  FS:On("CHARACTER_POINTS_CHANGED", o, function() later("sheet", 1) end)
  FS:On("PLAYER_TALENT_UPDATE", o, function() later("sheet", 1) end)
  FS:On("PLAYER_REGEN_ENABLED", o, function() later("sheet", 3) end)
  FS:On("UPDATE_SHAPESHIFT_FORM", o, function() later("sheet", 1) end)
  FS:On("SKILL_LINES_CHANGED", o, function() later("settings", 1) end)
  FS:On("QUEST_TURNED_IN", o, function() later("quests", 1) end)
  FS:On("BAG_UPDATE_DELAYED", o, function() later("bags", 0.5) end)
  FS:On("PLAYER_ENTERING_WORLD", o, function() later("all", 2) end)
  local function learnQuest()
    local qid = GetQuestID and GetQuestID()
    if not qid or qid == 0 or U.secret(qid) then return end
    local ids = {}
    for _, kind in ipairs({ "choice", "reward" }) do
      local f = kind == "choice" and GetNumQuestChoices or GetNumQuestRewards
      local okN, n = pcall(f or function() return 0 end)
      for i = 1, (okN and n or 0) do
        local ok, link = pcall(GetQuestItemLink, kind, i)
        local id = ok and U.ItemIDFromLink(link)
        if id then ids[#ids + 1] = id end
      end
    end
    if G:LearnQuestRewards(qid, ids) then later("quests", 0.5) end
  end
  FS:On("QUEST_DETAIL", o, learnQuest)
  FS:On("QUEST_COMPLETE", o, learnQuest)
  FS:On("GET_ITEM_INFO_RECEIVED", o, function(_, _, id)
    local st = S.self
    if not st then return end
    for _, e in ipairs(st.items or {}) do
      if e.it.id == id and e.it.rnd and not e.it.live then G:ClearLinkCache(); later("gear", 1); return end
    end
  end)
end
