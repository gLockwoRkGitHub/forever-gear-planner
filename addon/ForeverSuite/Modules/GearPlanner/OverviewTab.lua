-- Overview tab: one row per slot with what you wear, the best upgrade, where it comes from and the gain,
-- biggest gain first, and where to go for the most upgrades. Same as the website's "Upgrade overview".
-- A click on a row opens that slot on the Gear tab.
local _, FS = ...
local G, U, UI = FS.Gear, FS.U, FS.UI
local S = G.State

-- where an item can be fetched (dungeon or zone), for "best places to go"
local function placeOf(it, level, st)
  for _, s in ipairs(it.src or {}) do
    if G.SrcUsable(it, s, level, st) then
      if s.t == "Dungeon" then return s.w end
      if s.t == "Quest" then return s.dq or s.w end
      if s.t == "Vendor" then return s.w end
      return nil
    end
  end
end

local function build(panel)
  local tab = {}
  local title = UI.Text(panel, "GameFontNormalLarge", "Upgrade overview")
  title:SetPoint("TOPLEFT", 2, -2)
  local lvl = UI.Text(panel, "GameFontHighlightSmall", "", "RIGHT")
  lvl:SetPoint("TOPRIGHT", -2, -6)
  lvl:SetTextColor(0.62, 0.6, 0.53)
  local summary = UI.Text(panel, "GameFontHighlight", "")
  summary:SetPoint("TOPLEFT", 2, -26)
  summary:SetPoint("RIGHT", -2, 0)
  summary:SetWordWrap(true)
  summary:SetJustifyV("TOP")
  local scroll = UI.Scroll(panel)
  scroll:SetPoint("TOPLEFT", 0, -60)
  scroll:SetPoint("BOTTOMRIGHT")
  local rows = UI.Pool(UI.ItemRow)

  local function openSlot(slot)
    FS.Window:Show("gear")
    local t = FS.Window:Tab("gear")
    if t and t.obj and t.obj.ScrollToSlot then t.obj:ScrollToSlot(slot) end
  end

  function tab:Refresh()
    rows:Reset()
    local st = S.self
    if not st then
      summary:SetText("No profile for this class: Forever Suite ranks gear for Enhancement Shaman and Feral Druid.")
      lvl:SetText("")
      scroll:SetContentHeight(0)
      return
    end
    local level = st.level
    lvl:SetText("level " .. level .. (level ~= st.liveLevel and " (preview)" or "") .. " · click a row to open the slot")
    local list = {}
    for _, slot in ipairs(G.SLOTS) do
      if slot ~= "Relic" then
        local d = G:SlotData(st, slot, level, 1)
        local best
        for _, p in ipairs(d.pool) do if p.s > (d.base or 0) + 0.05 then best = p; break end end
        list[#list + 1] = { slot = slot, d = d, best = best, gain = best and (best.s - (d.base or 0)) or nil }
      end
    end
    local withUp, without = {}, {}
    for _, r in ipairs(list) do if r.best then withUp[#withUp + 1] = r else without[#without + 1] = r end end
    table.sort(withUp, function(a, b) return a.gain > b.gain end)

    local places = {}
    for _, r in ipairs(withUp) do
      local p = placeOf(r.best.it, level, st)
      if p then places[p] = (places[p] or 0) + 1 end
    end
    local top = {}
    for name, n in pairs(places) do if n > 1 then top[#top + 1] = { name = name, n = n } end end
    table.sort(top, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    local text = ("|cffffffff%d of %d slots|r can be upgraded at level %d."):format(#withUp, #list, level)
    if #top > 0 then
      local parts = {}
      for i = 1, math.min(3, #top) do parts[#parts + 1] = top[i].name .. " (" .. top[i].n .. (i == 1 and " slots" or "") .. ")" end
      text = text .. " Best places to go: " .. table.concat(parts, ", ") .. "."
    end
    summary:SetText(text)

    local y = 0
    for _, r in ipairs(withUp) do
      local row = rows:Get(scroll.content)
      row:SetPoint("TOPLEFT", 0, -y)
      row:SetPoint("RIGHT", scroll.content, "RIGHT")
      local ref = r.d.ref
      local worn = ref and ("|cff" .. U.qualityHex(ref.q) .. ref.n .. "|r") or (#r.d.eq > 0 and "one free slot" or "empty")
      local t, txt = G.ShortSource(r.best.it, level, st)
      local where = t and ("|cff" .. (U.SOURCE_HEX[t] or "aaaaaa") .. t .. "|r " .. txt) or ""
      row:SetItem(r.best.it, U.colorDelta(r.gain), "|cffd9a441" .. r.slot .. "|r · replaces " .. worn .. " · " .. where,
        ("score %.1f"):format(r.best.s))
      local slot = r.slot
      row.onClick = function() openSlot(slot) end
      y = y + 33
    end
    for _, r in ipairs(without) do
      local row = rows:Get(scroll.content)
      row:SetPoint("TOPLEFT", 0, -y)
      row:SetPoint("RIGHT", scroll.content, "RIGHT")
      local nx = r.d.next
      row:SetPlain("|cff888888" .. r.slot .. "|r", "|cff888888no upgrade now" ..
        (nx and (" · level " .. nx.L .. ": " .. nx.it.n) or "") .. "|r", "|cff666666-|r")
      local slot = r.slot
      row.onClick = function() openSlot(slot) end
      y = y + 33
    end
    scroll:SetContentHeight(y)
  end
  return tab
end

local core = {}
FS:Listen("READY", core, function() FS.Window:AddTab("overview", "Overview", 5, build, "planner") end)
