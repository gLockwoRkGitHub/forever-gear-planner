-- Dungeon guide: which dungeon holds the most upgrades for you and your partner, and boss by boss who
-- gains what. Opens by itself when you enter a dungeon (can be switched off). Same rules as the website.
local _, FS = ...
local G, U, UI = FS.Gear, FS.U, FS.UI
local S = G.State

local Guide = FS:NewModule("dungeon", {
  title = "Dungeon guide",
  desc = "The Dungeons tab, and a summary when you enter a dungeon: which boss drops an upgrade for whom.",
  order = 20,
})

local SOON = 3   -- also count drops that become usable within this many levels

-- --- per character context and verdicts --------------------------------------------------------
local function charContext(st)
  local level = st.level
  local w = S:Weights(st, level)
  local base, pools, eqIds = {}, {}, {}
  for _, slot in ipairs(G.SLOTS) do base[slot] = G.BaselineScore(st.equipped[slot] or {}, slot, w) end
  for _, e in ipairs(st.items or {}) do eqIds[e.it.id] = true end
  for _, it in ipairs(FS.Data.items) do
    if G.Eligible(it, level, st) then
      local p = pools[it.sl]
      if not p then p = {}; pools[it.sl] = p end
      p[#p + 1] = G.ScoreW(it, w)
    end
  end
  return { st = st, level = level, w = w, base = base, pools = pools, eqIds = eqIds }
end

local function dungeonSources(it, name)
  local out = {}
  for _, s in ipairs(it.src or {}) do
    if (s.t == "Dungeon" and s.w == name) or (s.t == "Quest" and s.dq == name) then out[#out + 1] = s end
  end
  return out
end

-- kind: up, meh, later, no, have, relic
local function verdict(it, name, ctx)
  local st = ctx.st
  if not G.Wearable(it, 60, st) then return { kind = "no" } end
  if ctx.eqIds[it.id] then return { kind = "have" } end
  local gate
  for _, s in ipairs(dungeonSources(it, name)) do
    if G.SrcUsable(it, s, 60, st, true) then gate = math.min(gate or 99, s.g or 1) end
  end
  if not gate then return { kind = "no" } end
  local from = math.max(gate, G.TypeGate(it, st.prof) or 1)
  local sc = G.ScoreW(it, ctx.w)
  if it.sl == "Relic" then return { kind = from > ctx.level and "later" or "relic", from = from, sc = sc } end
  local gain = sc - (ctx.base[it.sl] or 0)
  if from > ctx.level then return { kind = "later", from = from, sc = sc, gain = gain } end
  local rank = 1
  for _, x in ipairs(ctx.pools[it.sl] or {}) do if x > sc + 1e-9 then rank = rank + 1 end end
  return { kind = gain > 0.05 and "up" or "meh", sc = sc, gain = gain, rank = rank }
end
Guide.verdict = verdict

local function rankDungeons(ctxs)
  local out = {}
  for name, items in pairs(G.dungeonItems) do
    local per, total, count = {}, 0, 0
    for _, ctx in ipairs(ctxs) do
      local best, soon = {}, {}
      for _, it in ipairs(items) do
        local v = verdict(it, name, ctx)
        if v.kind == "up" and (not best[it.sl] or v.gain > best[it.sl]) then best[it.sl] = v.gain end
        if v.kind == "later" and (v.gain or 0) > 0.05 and v.from <= ctx.level + SOON then soon[it.sl] = true end
      end
      local c, g, sn = 0, 0, 0
      for _, x in pairs(best) do c = c + 1; g = g + x end
      for _ in pairs(soon) do sn = sn + 1 end
      per[#per + 1] = { ctx = ctx, count = c, gain = g, soon = sn }
      total, count = total + g, count + c
    end
    out[#out + 1] = { name = name, per = per, total = total, count = count, range = G.DUNGEON_RANGES[name] }
  end
  table.sort(out, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    if math.abs(a.total - b.total) > 1e-9 then return a.total > b.total end
    return (a.range and a.range[1] or 99) < (b.range and b.range[1] or 99)
  end)
  return out
end

local function who(st) return "|cff" .. st.prof.color .. (st.isSelf and "You" or st.short or st.name) .. "|r" end

local function verdictText(st, v, slot)
  if v.kind == "no" then return who(st) .. " |cff777777can't use|r" end
  if v.kind == "have" then return who(st) .. " |cff999999equipped|r" end
  if v.kind == "relic" then return who(st) .. " |cff999999relic, pick by effect|r" end
  if v.kind == "later" then
    return who(st) .. " |cffffcc00from " .. v.from .. ((v.gain or 0) > 0.05 and (" · " .. U.delta(v.gain)) or "") .. "|r"
  end
  if v.kind == "up" then return who(st) .. " |cff40ff40" .. U.delta(v.gain) .. "|r |cff999999#" .. v.rank .. " " .. slot .. "|r" end
  return who(st) .. " |cff999999no upgrade · #" .. v.rank .. "|r"
end

-- --- which dungeon are we in ---------------------------------------------------------------------
function Guide:CurrentDungeon()
  if not IsInInstance then return nil end
  local inside, kind = IsInInstance()
  if not inside or (kind ~= "party" and kind ~= "raid") then return nil end
  local name, _, _, _, _, _, _, id = GetInstanceInfo()
  local known = (id and (FS.db.instanceMap[id] or G.INSTANCE_IDS[id])) or (name and G.dungeonItems[name] and name)
  return known, id, name
end

-- --- tab -----------------------------------------------------------------------------------------
local function build(panel)
  local tab = { showAll = false }
  local left = UI.Panel(panel, 0.09, 0.1, 0.12, 1)
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", 0, 0)
  left:SetWidth(250)
  local lscroll = UI.Scroll(left)
  lscroll:SetPoint("TOPLEFT", 4, -4)
  lscroll:SetPoint("BOTTOMRIGHT", -4, 4)
  local dRows = UI.Pool(function(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(46)
    b:SetBackdrop(UI.BACKDROP)
    local t = UI.Text(b, "GameFontNormal", "")
    t:SetPoint("TOPLEFT", 6, -5)
    t:SetPoint("RIGHT", -6, 0)
    b.title = t
    local m = UI.Text(b, "GameFontHighlightSmall", "")
    m:SetPoint("TOPLEFT", 6, -19)
    m:SetPoint("RIGHT", -6, 0)
    m:SetTextColor(0.62, 0.6, 0.53)
    b.meta = m
    local c = UI.Text(b, "GameFontHighlightSmall", "")
    c:SetPoint("TOPLEFT", 6, -32)
    c:SetPoint("RIGHT", -6, 0)
    b.chips = c
    return b
  end)

  local right = CreateFrame("Frame", nil, panel)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
  right:SetPoint("BOTTOMRIGHT")
  local title = UI.Text(right, "GameFontNormalLarge", "")
  title:SetPoint("TOPLEFT", 2, -2)
  local sub = UI.Text(right, "GameFontHighlightSmall", "")
  sub:SetPoint("TOPLEFT", 2, -22)
  sub:SetTextColor(0.62, 0.6, 0.53)
  local all = UI.Check(right, "All drops", function(v) tab.showAll = v; tab:Refresh() end, "Also list drops that are no upgrade for anyone.")
  all:SetPoint("TOPRIGHT", -80, 2)
  local link = UI.Flat(right, "This is the dungeon I'm in", 200, 22, function()
    if tab.selected and Guide.unknownId then
      FS.db.instanceMap[Guide.unknownId] = tab.selected
      FS:Print(("Linked this instance to %s."):format(tab.selected))
      Guide.unknownId = nil
      tab:Refresh()
    end
  end)
  link:SetPoint("TOPRIGHT", 0, -24)
  link.tip = "The game did not tell which dungeon this is. Pick it on the left and click here once."
  local dscroll = UI.Scroll(right)
  dscroll:SetPoint("TOPLEFT", 0, -50)
  dscroll:SetPoint("BOTTOMRIGHT")
  local headers, rows, lines = UI.Pool(UI.Header), UI.Pool(UI.ItemRow), UI.Pool(UI.Line)

  function tab:Select(name)
    self.selected = name
    FS.cdb.dungeon.selected = name
    self:Refresh()
  end

  function tab:Refresh()
    dRows:Reset(); headers:Reset(); rows:Reset(); lines:Reset()
    local states = S:All()
    if #states == 0 then
      title:SetText("No profile for this class")
      sub:SetText("Group with your partner: their upgrades show here too.")
      return
    end
    local ctxs = {}
    for _, st in ipairs(states) do ctxs[#ctxs + 1] = charContext(st) end
    local ranked = rankDungeons(ctxs)
    local here = Guide:CurrentDungeon()
    local selected = self.selected or here or FS.cdb.dungeon.selected
    if not selected or not G.dungeonItems[selected] then selected = ranked[1] and ranked[1].name end
    self.selected = selected

    -- left: every dungeon, those with upgrades first (the others dimmed)
    local y = 0
    for _, d in ipairs(ranked) do
      local soonAny = false
      for _, p in ipairs(d.per) do if p.soon > 0 then soonAny = true end end
      local b = dRows:Get(lscroll.content)
      b:SetPoint("TOPLEFT", 0, -y)
      b:SetPoint("RIGHT", lscroll.content, "RIGHT")
      local sel = d.name == selected
      b:SetBackdropColor(sel and 0.17 or 0.11, sel and 0.165 or 0.12, sel and 0.14 or 0.145, 1)
      b:SetBackdropBorderColor(sel and UI.GOLD[1] or 0.185, sel and UI.GOLD[2] or 0.204, sel and UI.GOLD[3] or 0.24, 1)
      b:SetAlpha((d.total > 0.05 or soonAny or sel) and 1 or 0.55)
      b.title:SetText(d.name .. (d.name == here and " |cff40ff40(here)|r" or ""))
      b.meta:SetText((d.range and ("Level " .. d.range[1] .. "-" .. d.range[2]) or "") .. (d.total > 0.05 and (" · score +" .. ("%.1f"):format(d.total)) or ""))
      local chips = {}
      for _, p in ipairs(d.per) do
        chips[#chips + 1] = who(p.ctx.st) .. " " .. (p.count > 0 and ("|cff40ff40" .. p.count .. " up|r") or "|cff888888none|r")
          .. (p.soon > 0 and (" |cffffcc00" .. p.soon .. " soon|r") or "")
      end
      b.chips:SetText(table.concat(chips, "   "))
      b:SetScript("OnClick", function() tab:Select(d.name) end)
      y = y + 50
    end
    lscroll:SetContentHeight(y)

    -- right: the selected dungeon, boss by boss
    local range = G.DUNGEON_RANGES[selected or ""]
    title:SetText(selected or "")
    local partners = #states > 1 and "" or "  ·  group with your partner to see their upgrades too"
    sub:SetText((range and ("Level " .. range[1] .. "-" .. range[2]) or "") .. partners)
    link:SetShown(Guide.unknownId ~= nil)
    all:SetChecked(self.showAll)
    if not selected then dscroll:SetContentHeight(0); return end

    local items = G.dungeonItems[selected] or {}
    local groups, order = {}, {}
    for _, bossName in ipairs(FS.Data.bosses[selected] or {}) do order[#order + 1] = bossName end
    for _, it in ipairs(items) do
      local vs, any = {}, false
      for i, ctx in ipairs(ctxs) do
        local v = verdict(it, selected, ctx)
        vs[i] = v
        if v.kind == "up" or (v.kind == "later" and (v.gain or 0) > 0.05 and v.from <= ctx.level + SOON) then any = true end
      end
      local usable = false
      for _, v in ipairs(vs) do if v.kind ~= "no" then usable = true end end
      if any or (self.showAll and usable) then
        for _, s in ipairs(dungeonSources(it, selected)) do
          local key = s.t == "Quest" and ("Quest: " .. s.n) or (s.n or "?")
          if not groups[key] then
            groups[key] = {}
            local known = false
            for _, o in ipairs(order) do if o == key then known = true end end
            if not known then order[#order + 1] = key end
          end
          groups[key][#groups[key] + 1] = { it = it, vs = vs, s = s }
        end
      end
    end
    local dy = 0
    local shown = 0
    for _, key in ipairs(order) do
      local list = groups[key]
      if list then
        local h = headers:Get(dscroll.content)
        h:SetPoint("TOPLEFT", 0, -dy)
        h:SetPoint("RIGHT", dscroll.content, "RIGHT")
        h.text:SetText(key)
        h.right:SetText("")
        dy = dy + 26
        for _, e in ipairs(list) do
          local parts = {}
          for i, v in ipairs(e.vs) do parts[#parts + 1] = verdictText(ctxs[i].st, v, e.it.sl) end
          local r = rows:Get(dscroll.content)
          r:SetPoint("TOPLEFT", 0, -dy)
          r:SetPoint("RIGHT", dscroll.content, "RIGHT")
          local chance = e.s.dc and ((" %.0f%%"):format(e.s.dc)) or ""
          r:SetItem(e.it, "", table.concat(parts, "   "), e.it.sl .. chance)
          dy = dy + 33
          shown = shown + 1
        end
        dy = dy + 6
      end
    end
    if shown == 0 then
      local l = lines:Get(dscroll.content)
      l:SetPoint("TOPLEFT", 0, 0)
      l:SetPoint("RIGHT", dscroll.content, "RIGHT")
      l.text:SetText("|cff888888No upgrades here for your levels. Tick 'All drops' to see everything.|r")
      dy = 20
    end
    dscroll:SetContentHeight(dy)
  end
  return tab
end

-- --- entering a dungeon ------------------------------------------------------------------------
function Guide:Summary(name)
  local states = S:All()
  local out = {}
  for _, st in ipairs(states) do
    local ctx = charContext(st)
    local best = {}
    for _, it in ipairs(G.dungeonItems[name] or {}) do
      local v = verdict(it, name, ctx)
      if v.kind == "up" and (not best[it.sl] or v.gain > best[it.sl].gain) then best[it.sl] = { it = it, gain = v.gain } end
    end
    local list = {}
    for _, b in pairs(best) do list[#list + 1] = b end
    table.sort(list, function(a, b) return a.gain > b.gain end)
    local parts = {}
    for i = 1, math.min(3, #list) do
      parts[#parts + 1] = U.ItemLinkFor(list[i].it.id, list[i].it.n, list[i].it.q) .. " " .. U.colorDelta(list[i].gain)
    end
    out[#out + 1] = who(st) .. ": " .. (#list > 0 and (#list .. " upgrade" .. (#list > 1 and "s" or "") .. " · " .. table.concat(parts, ", ")) or "no upgrades")
  end
  return out
end

function Guide:OnZone()
  local known, id, rawName = self:CurrentDungeon()
  local key = tostring(id or rawName)
  if not known then
    if id and IsInInstance and select(2, IsInInstance()) == "party" and self.lastKey ~= key then
      self.lastKey = key
      self.unknownId = id
      FS:Print(("Unknown dungeon '%s'. Open |cffd9a441/fs dungeons|r, pick it and click 'This is the dungeon I'm in'."):format(tostring(rawName)))
    end
    if not id then self.lastKey = nil end
    return
  end
  self.unknownId = nil
  if self.lastKey == key then return end
  self.lastKey = key
  FS:Print("|cffffffff" .. known .. "|r")
  for _, line in ipairs(self:Summary(known)) do print("   " .. line) end
  if FS.cdb.dungeon.autoOpen ~= false then
    local t = FS.Window:Tab("dungeons")
    FS.Window:Show("dungeons")
    if t and t.obj then t.obj:Select(known) end
  end
end

function Guide:OnInitialize()
  FS.Window:AddTab("dungeons", "Dungeons", 20, build, "dungeon")
end

function Guide:OnEnable()
  local function check() FS:Debounce("dungeon-zone", 2, function() Guide:OnZone() end) end
  self:RegisterEvent("PLAYER_ENTERING_WORLD", check)
  self:RegisterEvent("ZONE_CHANGED_NEW_AREA", check)
  check()
end
