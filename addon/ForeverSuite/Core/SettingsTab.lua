-- Settings tab: switch modules on and off, planner filters, website import, partners, data version.
local _, FS = ...
local G, U, UI = FS.Gear, FS.U, FS.UI
local S = G.State

local function build(panel)
  local tab = {}
  local scroll = UI.Scroll(panel)
  scroll:SetAllPoints()
  local c = scroll.content
  local y = 0
  local function section(title)
    local h = UI.Header(c)
    h:SetPoint("TOPLEFT", 0, -y)
    h:SetPoint("RIGHT", c, "RIGHT", 0, 0)
    h.text:SetText(title)
    y = y + 30
    return h
  end
  local function note(text, indent, height)
    local fs = UI.Text(c, "GameFontHighlightSmall", text)
    fs:SetPoint("TOPLEFT", indent or 4, -y)
    fs:SetPoint("RIGHT", c, "RIGHT", -8, 0)
    fs:SetWordWrap(true)
    fs:SetJustifyV("TOP")
    fs:SetTextColor(0.62, 0.6, 0.53)
    y = y + (height or 18)
    return fs
  end

  -- modules
  section("Modules")
  local modChecks = {}
  for _, m in ipairs(FS.moduleList) do
    local cb = UI.Check(c, m.title, function(v) FS:SetModuleEnabled(m.id, v) end)
    cb:SetPoint("TOPLEFT", 0, -y)
    cb.labelText:SetFontObject("GameFontNormal")
    modChecks[m.id] = cb
    y = y + 22
    note(m.desc or "", 28, 28)
  end

  -- planner filters
  local plannerHead = section("Gear planner (this character)")
  local srcChecks, profChecks = {}, {}
  local x = 0
  for _, src in ipairs(G.SOURCES) do
    local cb = UI.Check(c, "|cff" .. U.SOURCE_HEX[src] .. src .. "|r", function(v)
      local st = S.self
      if not st then return end
      local s = U.copy(st.settings.sources)
      s[src] = v or nil
      S:Set("sources", S.SetToList(s, G.SOURCES))
    end)
    cb:SetPoint("TOPLEFT", x, -y)
    srcChecks[src] = cb
    x = x + 120
  end
  y = y + 26
  note("Where an item may come from.", 4)
  y = y + 6
  x = 0
  for i, p in ipairs(G.PROFESSIONS) do
    local cb = UI.Check(c, p, function(v)
      local st = S.self
      if not st then return end
      local s = U.copy(st.settings.profs)
      s[p] = v or nil
      S:Set("profs", S.SetToList(s, G.PROFESSIONS))
    end)
    cb:SetPoint("TOPLEFT", x, -y)
    profChecks[p] = cb
    x = x + 160
    if i % 3 == 0 then x = 0; y = y + 24 end
  end
  local auto = UI.Flat(c, "Detect professions", 150, 22, function() S:Set("profs", nil) end)
  auto:SetPoint("TOPLEFT", 0, -y - 2)
  local profNote = UI.Text(c, "GameFontHighlightSmall", "")
  profNote:SetPoint("LEFT", auto, "RIGHT", 10, 0)
  profNote:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  profNote:SetTextColor(0.62, 0.6, 0.53)
  y = y + 30
  note("Professions unlock bind-on-pickup crafts and gear that needs the profession to equip.", 4)
  y = y + 6
  local random = UI.Check(c, "Random-enchant items (\"of the Bear\")", function(v) S:Set("random", v) end,
    "List items with random stats. In the list they are scored on base stats; in tooltips on their real stats.")
  random:SetPoint("TOPLEFT", 0, -y)
  y = y + 24
  local hideDone = UI.Check(c, "Hide rewards of quests you have turned in", function(v) S:Set("hideDone", v) end)
  hideDone:SetPoint("TOPLEFT", 0, -y)
  y = y + 24
  local autoOpen = UI.Check(c, "Open the Dungeons tab when entering a dungeon", function(v) FS.cdb.dungeon.autoOpen = v end)
  autoOpen:SetPoint("TOPLEFT", 0, -y)
  y = y + 24
  local mini = UI.Check(c, "Minimap button", function(v) FS.db.minimap.hide = not v; if FS.Minimap then FS.Minimap:Update() end end)
  mini:SetPoint("TOPLEFT", 0, -y)
  y = y + 32

  -- import
  section("Website")
  local importBtn = UI.Flat(c, "Import from the website", 190, 22, function() FS.Import:ShowDialog() end)
  importBtn:SetPoint("TOPLEFT", 0, -y)
  local importNote = UI.Text(c, "GameFontHighlightSmall", "")
  importNote:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
  importNote:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  importNote:SetWordWrap(true)
  y = y + 30
  note("Brings talents, character sheet, stat weights and filters from the planner page (tab Addon, 'Copy text for the addon').", 4)
  y = y + 10

  -- partners
  section("Partners")
  local partnerNote = UI.Text(c, "GameFontHighlightSmall", "")
  partnerNote:SetPoint("TOPLEFT", 4, -y)
  partnerNote:SetPoint("RIGHT", c, "RIGHT", -8, 0)
  partnerNote:SetWordWrap(true)
  y = y + 34
  local sendBtn = UI.Flat(c, "Send my gear now", 150, 22, function() FS:Fire("SYNC_REQUESTED") end)
  sendBtn:SetPoint("TOPLEFT", 0, -y)
  local forget = UI.Flat(c, "Forget partners", 130, 22, function()
    local m = FS.modules.partner
    if m and m.Forget then m:Forget() end
    wipe(FS.db.questSync)
    tab:Refresh()
  end)
  forget:SetPoint("LEFT", sendBtn, "RIGHT", 8, 0)
  y = y + 34

  section("Data")
  local dataNote = note("", 4)
  y = y + 20
  scroll:SetContentHeight(y)

  function tab:Refresh()
    for id, cb in pairs(modChecks) do cb:SetChecked(FS.modules[id].enabled) end
    local st = S.self
    for src, cb in pairs(srcChecks) do cb:SetChecked(st and st.settings.sources[src] or false); cb:SetEnabled(st ~= nil) end
    for p, cb in pairs(profChecks) do cb:SetChecked(st and st.settings.profs[p] or false); cb:SetEnabled(st ~= nil) end
    plannerHead.right:SetText(st and ("|cff" .. st.prof.color .. st.prof.label .. "|r") or "no profile for this class")
    if st then
      profNote:SetText(st.settings.profsAuto and (st.settings.profsDetected and "detected from your professions" or "profile default")
        or "set by hand")
    end
    random:SetChecked(st and st.settings.random or false)
    hideDone:SetChecked(st and st.settings.hideDone or false)
    autoOpen:SetChecked(FS.cdb.dungeon.autoOpen ~= false)
    mini:SetChecked(not FS.db.minimap.hide)
    local imp = FS.db.imported
    if imp then
      local names = {}
      for key, ch in pairs(imp.chars) do names[#names + 1] = (ch.name or key) end
      table.sort(names)
      importNote:SetText("Last import: " .. table.concat(names, ", ") .. (imp.date and (" · " .. imp.date) or ""))
    else
      importNote:SetText("|cffffcc00Nothing imported yet.|r")
    end
    local plist = {}
    for name, rec in pairs(FS.db.partners) do
      local data = FS.modules.partner and FS.modules.partner.Decode and FS.modules.partner.Decode(rec.payload)
      plist[#plist + 1] = name .. (data and (" (" .. data.key .. ", level " .. data.level .. ")") or "") .. " · " .. date("%d %b %H:%M", rec.at)
    end
    table.sort(plist)
    partnerNote:SetText(#plist > 0 and ("Known: " .. table.concat(plist, "; ")) or
      "No partner yet. Group up; both addons then swap gear and quests by themselves.")
    local m = FS.Data.meta or {}
    dataNote:SetText(("%d items · game build %s · item data %s · addon %s"):format(m.count or #FS.Data.items, m.build or "?", m.generated or "?", m.version or "?"))
  end
  return tab
end

local core = {}
FS:Listen("READY", core, function() FS.Window:AddTab("settings", "Settings", 90, build) end)
