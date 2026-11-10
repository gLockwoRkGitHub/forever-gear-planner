-- Import from the website: the planner page (Addon tab) copies a text with both characters' talents,
-- character sheet, weights and filters. Pasted here, it fills in what the game cannot tell the addon
-- (talents on non-English clients) and takes over the filters and weights picked on the page.
--
-- Format: FS1~<date>~<char>~<char>   char = k=shaman;n=Koda Ashmane;p=<preset>;w=str:1,agi:0.4;
--         src=Quest,Dungeon;pf=Enchanting;rnd=0;up=1;lv=34;t=flurry:25,storm:1;sh=str:120,agi:60,...;
--         sl=34 (level of the sheet); we=271766:5 (weapon damage enchant on the equipped two-hander)
local _, FS = ...
local G, U = FS.Gear, FS.U
local Imp = {}
FS.Import = Imp

function Imp.Parse(text)
  text = (text or ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  local start = text:find("FS1~", 1, true)
  if not start then return nil, "This is not a Forever Suite text. Copy it from the planner page, tab Addon." end
  text = text:sub(start)
  local parts = U.split(text, "~")
  local out = { date = parts[2], chars = {} }
  for i = 3, #parts do
    local kv = {}
    for _, pair in ipairs(U.split(parts[i], ";")) do
      local k, v = pair:match("^%s*([%a]+)=(.*)$")
      if k then kv[k] = v end
    end
    local key = kv.k
    if key and G.PROFILES[key] then
      local list = function(s) local o = {}; for _, x in ipairs(U.split(s or "", ",")) do if x ~= "" then o[#o + 1] = x end end; return o end
      out.chars[key] = {
        name = kv.n, preset = kv.p, weights = FS.Comm.decodeMap(kv.w), sources = kv.src and list(kv.src) or nil,
        profs = kv.pf and list(kv.pf) or nil, random = kv.rnd == "1", onlyUp = kv.up ~= "0", level = tonumber(kv.lv),
        tal = kv.t and FS.Comm.decodeMap(kv.t) or nil, sheet = kv.sh and FS.Comm.decodeMap(kv.sh) or nil,
        sheetLevel = tonumber(kv.sl), weaponEnchant = kv.we and FS.Comm.decodeMap(kv.we) or nil,
      }
    end
  end
  if not next(out.chars) then return nil, "The text has no character in it." end
  return out
end

-- Store the import and take over the page's settings for the character you are playing.
function Imp.Apply(data)
  FS.db.imported = data
  local st = G.State.self
  local mine = st and data.chars[st.key]
  if mine then
    local db = FS.cdb.gear
    if mine.preset and st.prof.presets[mine.preset] then db.preset = mine.preset end
    db.weights = next(mine.weights or {}) and mine.weights or nil
    if mine.sources then db.sources = mine.sources end
    if mine.profs then db.profs = mine.profs end
    db.random = mine.random
    db.onlyUp = mine.onlyUp
  end
  G.State:Refresh("all")
  FS:Fire("IMPORTED")
  local names = {}
  for key, c in pairs(data.chars) do names[#names + 1] = (c.name or key) .. " (" .. key .. ")" end
  table.sort(names)
  return mine, table.concat(names, ", ")
end

-- --- dialog ----------------------------------------------------------------------------------
function Imp:ShowDialog()
  if not self.frame then self:CreateDialog() end
  self.frame.edit:SetText("")
  self.frame.status:SetText("Planner page → tab |cffd9a441Addon|r → |cffd9a441Copy text for the addon|r, then paste it here (Ctrl+V).")
  self.frame:Show()
  self.frame.edit:SetFocus()
end

function Imp:CreateDialog()
  local UI = FS.UI
  local f = UI.Window("ForeverSuiteImport", "Import from the website", 520, 300)
  f:SetFrameStrata("DIALOG")
  local box = UI.Panel(f, 0.05, 0.055, 0.07, 1)
  box:SetPoint("TOPLEFT", 14, -40)
  box:SetPoint("BOTTOMRIGHT", -14, 74)
  local sf = CreateFrame("ScrollFrame", nil, box)
  sf:SetPoint("TOPLEFT", 6, -6)
  sf:SetPoint("BOTTOMRIGHT", -6, 6)
  local edit = CreateFrame("EditBox", nil, sf)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(470)
  edit:SetMaxLetters(0)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  sf:SetScrollChild(edit)
  sf:EnableMouse(true)
  sf:SetScript("OnMouseDown", function() edit:SetFocus() end)
  f.edit = edit
  local status = UI.Text(f, "GameFontHighlightSmall", "", "LEFT")
  status:SetPoint("BOTTOMLEFT", 16, 46)
  status:SetPoint("RIGHT", -16, 0)
  status:SetWordWrap(true)
  f.status = status
  local go = UI.Button(f, "Import", 110, 24, function()
    local data, err = Imp.Parse(edit:GetText())
    if not data then status:SetText("|cffff6060" .. err .. "|r"); return end
    local mine, names = Imp.Apply(data)
    local msg = "Imported " .. names .. (data.date and (" from " .. data.date) or "") .. "."
    if not mine and G.State.self then msg = msg .. " Nothing in it for this character's class." end
    status:SetText("|cff40ff40" .. msg .. "|r")
    FS:Print(msg)
  end)
  go:SetPoint("BOTTOMRIGHT", -14, 14)
  local close = UI.Button(f, "Close", 90, 24, function() f:Hide() end)
  close:SetPoint("RIGHT", go, "LEFT", -8, 0)
  self.frame = f
end
