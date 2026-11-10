-- Gear tab: per slot what you wear and the best upgrades for your level (or a level you pick),
-- with where they come from. Same ranking as the website's Gear tab.
local _, FS = ...
local G, U, UI = FS.Gear, FS.U, FS.UI
local S = G.State

local Planner = FS:NewModule("planner", {
  title = "Gear planner",
  desc = "The Gear tab: best upgrades per slot for your level, from quests, dungeons, vendors and crafting.",
  order = 10,
})

local SRC_HEX = U.SOURCE_HEX
local WEIGHT_NAMES = { str = "Strength", agi = "Agility", int = "Intellect", ap = "Attack Power", feralAp = "Feral AP",
  crit = "Crit (per %)", hit = "Hit (per %)", sp = "Spell Power", natureSp = "Nature damage" }

local function sourceText(it, level, st)
  local t, txt = G.ShortSource(it, level, st)
  if not t then return "" end
  return "|cff" .. (SRC_HEX[t] or "aaaaaa") .. t .. "|r " .. txt
end

local function wornText(eq, w)
  if #eq == 0 then return "|cff888888empty|r" end
  local parts = {}
  for _, e in ipairs(eq) do
    parts[#parts + 1] = "|cff" .. U.qualityHex(e.q) .. (e.n or "?") .. "|r " .. ("%.1f"):format(G.ScoreW(e, w))
  end
  return "worn: " .. table.concat(parts, ", ")
end

local function modelStatus(st, w)
  local p = st.prof.presets[st.settings.preset]
  if not p.model then
    local custom = next(st.settings.weights or {}) and " · custom weights" or ""
    return st.settings.preset .. custom
  end
  if w.__noModel then
    if st.key == "druid" and st.level < 20 then return "|cffffcc00Level model needs Cat Form (20): using the estimate|r" end
    return "|cffffcc00No character sheet yet: using the estimate|r"
  end
  local tal
  if st.talSrc == "game" then tal = "talents from the game"
  elseif st.talSrc == "website" then tal = "talents from the website" .. (st.talDate and (" (" .. st.talDate:sub(1, 10) .. ")") or "")
  else tal = "|cffffcc00no talents: import them from the website|r" end
  return "Level model · " .. tal
end

local function weightTooltip(owner, st, w)
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
  GameTooltip:AddLine("Stat weights at level " .. st.level, 1, 0.82, 0)
  local keys = { "str", "agi", "int", "ap", "feralAp", "crit", "hit", "sp", "natureSp" }
  for _, k in ipairs(keys) do
    local v = w[k]
    if v and v > 0 then GameTooltip:AddDoubleLine(WEIGHT_NAMES[k], ("%.2f"):format(v), 0.8, 0.8, 0.8, 1, 1, 1) end
  end
  local m = w.__model
  if m then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Kills a level-%d mob (%d health) in %.1f sec"):format(m.mobLevel, m.fight.H, m.fight.T), 1, 0.82, 0)
    for _, part in ipairs(m.detail.parts) do
      if part[2] > 0.05 then GameTooltip:AddDoubleLine(part[1], ("%.1f"):format(part[2]), 0.8, 0.8, 0.8, 1, 1, 1) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Weights = how much faster you kill, in Strength points. Two-handers are valued by their damage and speed.", 0.6, 0.6, 0.6, true)
    local src = { game = "the game", saved = "saved (last caster form)", website = "the website" }
    GameTooltip:AddLine("Character sheet: " .. (src[st.sheetSrc] or "none") .. ". Talents: " .. (st.talSrc and src[st.talSrc] or "none") .. ".", 0.6, 0.6, 0.6, true)
  else
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Fixed weights (estimate preset). Weapons: DPS × weapon-DPS weight.", 0.6, 0.6, 0.6, true)
  end
  GameTooltip:Show()
end

local function build(panel)
  local tab = {}
  local head = CreateFrame("Frame", nil, panel)
  head:SetPoint("TOPLEFT")
  head:SetPoint("TOPRIGHT")
  head:SetHeight(86)

  local name = UI.Text(head, "GameFontNormalLarge", "")
  name:SetPoint("TOPLEFT", 2, -2)

  local live = UI.Flat(head, "Live", 46, 22, function() S:SetPreviewLevel(nil) end)
  live:SetPoint("TOPRIGHT", 0, 0)
  live.tip = "Back to your level in the game"
  local up = UI.Flat(head, ">", 24, 22, function() local st = S.self; if st then S:SetPreviewLevel(st.level + 1) end end)
  up:SetPoint("RIGHT", live, "LEFT", -6, 0)
  local lv = UI.Text(head, "GameFontNormal", "", "CENTER")
  lv:SetWidth(70)
  lv:SetPoint("RIGHT", up, "LEFT", -4, 0)
  local down = UI.Flat(head, "<", 24, 22, function() local st = S.self; if st then S:SetPreviewLevel(st.level - 1) end end)
  down:SetPoint("RIGHT", lv, "LEFT", -4, 0)

  local preset = UI.Flat(head, "", 200, 22, function()
    local st = S.self
    if not st then return end
    local order = st.prof.presetOrder
    local idx = 1
    for i, n in ipairs(order) do if n == st.settings.preset then idx = i end end
    S:Set("preset", order[idx % #order + 1])
  end)
  preset:SetPoint("TOPLEFT", 0, -32)
  preset.tip = "Click to switch the stat weights"
  local topN = UI.Flat(head, "", 60, 22, function()
    local st = S.self
    if not st then return end
    local n = st.settings.topN
    S:Set("topN", n == 3 and 5 or n == 5 and 10 or 3)
  end)
  topN:SetPoint("LEFT", preset, "RIGHT", 6, 0)
  topN.tip = "Items per slot"
  local onlyUp = UI.Check(head, "Only upgrades", function(v) S:Set("onlyUp", v) end,
    "Hide items that are not better than what you wear.")
  onlyUp:SetPoint("LEFT", topN, "RIGHT", 8, 0)
  local status = CreateFrame("Button", nil, head)
  status:SetHeight(22)
  status:SetPoint("LEFT", onlyUp.labelText, "RIGHT", 14, 0)
  status:SetPoint("RIGHT", 0, 0)
  local statusText = UI.Text(status, "GameFontHighlightSmall", "", "RIGHT")
  statusText:SetAllPoints()
  statusText:SetTextColor(0.62, 0.6, 0.53)
  status:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- third row: where items may come from, and finished quests (same settings as the Settings tab)
  local fromLabel = UI.Text(head, "GameFontHighlightSmall", "From")
  fromLabel:SetPoint("TOPLEFT", 2, -66)
  fromLabel:SetTextColor(0.62, 0.6, 0.53)
  local srcButtons = {}
  local prev = fromLabel
  for _, src in ipairs(G.SOURCES) do
    local b = UI.Flat(head, src, 78, 22, function()
      local st = S.self
      if not st then return end
      local set = U.copy(st.settings.sources)
      set[src] = (not set[src]) or nil
      S:Set("sources", S.SetToList(set, G.SOURCES))
    end)
    b:SetPoint("LEFT", prev, "RIGHT", prev == fromLabel and 8 or 4, 0)
    b.tip = ({ Quest = "Quest rewards", Dungeon = "Dungeon drops and dungeon quests", Vendor = "Items from vendors",
      Crafted = "Crafted items" })[src] .. ": click to show or hide"
    srcButtons[src] = b
    prev = b
  end
  local hideDone = UI.Check(head, "Hide finished quests", function(v) S:Set("hideDone", v) end,
    "Leave out rewards of quests you have already turned in (whichever reward you picked).")
  hideDone:SetPoint("LEFT", prev, "RIGHT", 10, 0)

  local scroll = UI.Scroll(panel)
  scroll:SetPoint("TOPLEFT", 0, -90)
  scroll:SetPoint("BOTTOMRIGHT", 0, 0)
  local content = scroll.content
  local headers = UI.Pool(UI.Header)
  local rows = UI.Pool(UI.ItemRow)
  local lines = UI.Pool(UI.Line)

  local msg = UI.Text(panel, "GameFontHighlight", "", "LEFT")
  msg:SetPoint("TOPLEFT", 4, -96)
  msg:SetPoint("RIGHT", -4, 0)
  msg:SetWordWrap(true)

  function tab:Refresh()
    local st = S.self
    headers:Reset(); rows:Reset(); lines:Reset()
    if not st then
      head:Hide(); scroll:Hide()
      local _, cls = UnitClass("player")
      msg:SetText("Forever Suite ranks gear for two profiles: Enhancement Shaman and Feral Druid. This character is a "
        .. (cls or "?"):lower() .. ", so the Gear tab has nothing to show. Tooltips, partner and quest sync still work.")
      msg:Show()
      return
    end
    msg:Hide(); head:Show(); scroll:Show()
    local w = S:Weights(st, st.level)
    name:SetText("|cff" .. st.prof.color .. (st.name or "") .. "|r  |cffa0a0a0" .. st.prof.label .. "|r")
    local preview = st.level ~= st.liveLevel
    lv:SetText((preview and "|cffffcc00" or "") .. "Level " .. st.level .. (preview and "|r" or ""))
    live:SetShown(preview)
    preset.label:SetText("Weights: " .. st.settings.preset)
    topN.label:SetText("Top " .. st.settings.topN)
    onlyUp:SetChecked(st.settings.onlyUp)
    hideDone:SetChecked(st.settings.hideDone)
    for src, b in pairs(srcButtons) do
      local on = st.settings.sources[src] and true or false
      b:SetActive(on)
      b.label:SetText(on and ("|cff" .. SRC_HEX[src] .. src .. "|r") or ("|cff777777" .. src .. "|r"))
    end
    statusText:SetText(modelStatus(st, w))
    status:SetScript("OnEnter", function(self) weightTooltip(self, st, w) end)

    local y = 0
    for _, slot in ipairs(G.SLOTS) do
      local d = G:SlotData(st, slot, st.level, st.settings.topN)
      local h = headers:Get(content)
      h:SetPoint("TOPLEFT", 0, -y)
      h:SetPoint("RIGHT", content, "RIGHT")
      h.text:SetText(slot == "Relic" and ("Relic · " .. st.prof.relic) or slot)
      h.right:SetText(wornText(d.eq, d.w))
      y = y + 26
      for _, p in ipairs(d.top) do
        local r = rows:Get(content)
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", content, "RIGHT")
        local sub = sourceText(p.it, st.level, st)
        if st.bags and st.bags[p.it.id] then sub = "|cff40ff40in your bags|r · " .. sub end
        local rightText = d.base and U.colorDelta(p.s - d.base) or ("%.1f"):format(p.s)
        r:SetItem(p.it, rightText, sub, ("score %.1f"):format(p.s) .. ((p.it.rq or 0) > 0 and (" · req " .. p.it.rq) or ""))
        r:SetAlpha(1)
        y = y + 33
      end
      if #d.top == 0 then
        local l = lines:Get(content)
        l:SetPoint("TOPLEFT", 0, -y)
        l:SetPoint("RIGHT", content, "RIGHT")
        l.text:SetText("|cff888888" .. (#d.pool == 0 and "Nothing with these filters at this level." or "No upgrade at this level.") .. "|r")
        y = y + 20
      end
      if d.next then
        local r = rows:Get(content)
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", content, "RIGHT")
        local gain = d.base and (d.next.s - d.base) or d.next.s
        r:SetItem(d.next.it, "|cffffcc00" .. U.delta(gain) .. "|r", "|cffffcc00from level " .. d.next.L .. "|r · " .. sourceText(d.next.it, d.next.L, st),
          ("score %.1f"):format(d.next.s))
        r:SetAlpha(0.75)
        y = y + 33
      end
      y = y + 8
    end
    scroll:SetContentHeight(y)
  end
  return tab
end

function Planner:OnInitialize()
  FS.Window:AddTab("gear", "Gear", 10, build, "planner")
end
