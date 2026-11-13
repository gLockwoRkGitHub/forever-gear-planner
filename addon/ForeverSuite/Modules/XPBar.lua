-- XP bars: a small movable frame with your and your partner's experience (level, progress, rested), so you
-- see who is ahead. The partner's addon sends its XP after each change (outside combat).
local _, FS = ...
local U, UI, Comm = FS.U, FS.UI, FS.Comm

local X = FS:NewModule("xpbar", {
  title = "XP bars",
  desc = "A small bar frame with your and your partner's experience. Drag it to move it; it shows while you are grouped with a partner.",
  order = 60,
})

X.partners = {}       -- name -> { level, xp, max, rest, at }
local W, BAR_H = 240, 14

local function myXP()
  local lv = U.num(UnitLevel("player")) or 1
  local xp = U.num(UnitXP and UnitXP("player")) or 0
  local max = U.num(UnitXPMax and UnitXPMax("player")) or 0
  local rest = U.num(GetXPExhaustion and GetXPExhaustion()) or 0
  return { level = lv, xp = xp, max = max, rest = rest }
end

-- level with the fraction of the current level, e.g. 35.48
local function progress(d)
  if not d or not d.level then return 0 end
  return d.level + ((d.max or 0) > 0 and (d.xp or 0) / d.max or 0)
end

local lastSent
function X:Send(force)
  if not Comm:GroupChannel() then return false end
  if U.InCombat() then FS:Debounce("xp-combat", 5, function() X:Send(force) end); return false end
  local d = myXP()
  local payload = Comm.encode({ lv = d.level, xp = d.xp, mx = d.max, rs = d.rest })
  if not force and payload == lastSent then return false end
  lastSent = payload
  return Comm:Send("XP", payload)
end

function X:OnXP(_, name, payload)
  local t = Comm.decode(payload)
  local lv = tonumber(t.lv)
  if not lv then return end
  self.partners[name] = { level = lv, xp = tonumber(t.xp) or 0, max = tonumber(t.mx) or 0, rest = tonumber(t.rs) or 0, at = GetTime() }
  self:Update()
end

-- --- frame ---------------------------------------------------------------------------------------------
local function makeBar(parent)
  local b = CreateFrame("StatusBar", nil, parent, "BackdropTemplate")
  b:SetSize(W - 16, BAR_H)
  b:SetBackdrop(UI.BACKDROP)
  b:SetBackdropColor(0.05, 0.05, 0.07, 0.9)
  b:SetBackdropBorderColor(0.185, 0.204, 0.24, 1)
  b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  b:SetMinMaxValues(0, 1)
  -- rested part: a lighter bar behind the XP bar
  local rest = CreateFrame("StatusBar", nil, b)
  rest:SetAllPoints()
  rest:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  rest:SetStatusBarColor(0.25, 0.45, 0.85, 0.45)
  rest:SetMinMaxValues(0, 1)
  rest:SetFrameLevel(b:GetFrameLevel())
  b.rest = rest
  local text = UI.Text(b, "GameFontHighlightSmall", "", "LEFT")
  text:SetPoint("LEFT", 4, 0)
  b.text = text
  local right = UI.Text(b, "GameFontHighlightSmall", "", "RIGHT")
  right:SetPoint("RIGHT", -4, 0)
  b.right = right
  return b
end

function X:Create()
  if self.frame then return end
  local f = CreateFrame("Frame", "ForeverSuiteXP", UIParent, "BackdropTemplate")
  f:SetSize(W, 66)
  f:SetBackdrop(UI.BACKDROP)
  f:SetBackdropColor(0.078, 0.086, 0.10, 0.85)
  f:SetBackdropBorderColor(0.3, 0.27, 0.2, 1)
  f:SetFrameStrata("LOW")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  local pos = FS.db.xpFrame or {}
  FS.db.xpFrame = pos
  f:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "TOP", pos.x or 0, pos.y or -120)
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
  end)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Experience", 0.85, 0.64, 0.25)
    for _, row in ipairs(X.rows or {}) do
      local d = row.d
      GameTooltip:AddDoubleLine(row.label, ("level %d · %s / %s XP"):format(d.level, BreakUpLargeNumbers and BreakUpLargeNumbers(d.xp) or d.xp,
        BreakUpLargeNumbers and BreakUpLargeNumbers(d.max) or d.max), 1, 1, 1, 0.8, 0.8, 0.8)
      if (d.rest or 0) > 0 then GameTooltip:AddDoubleLine(" ", ("rested %d XP"):format(d.rest), 1, 1, 1, 0.4, 0.6, 1) end
      if row.toLevel then GameTooltip:AddDoubleLine(" ", ("%d XP to level %d"):format(row.toLevel, d.level + 1), 1, 1, 1, 0.7, 0.7, 0.7) end
    end
    GameTooltip:AddLine("Drag to move. /fs module xpbar off hides it.", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f.bars = { makeBar(f), makeBar(f) }
  f.bars[1]:SetPoint("TOPLEFT", 8, -8)
  f.bars[2]:SetPoint("TOPLEFT", 8, -8 - BAR_H - 4)
  local diff = UI.Text(f, "GameFontHighlightSmall", "", "CENTER")
  diff:SetPoint("BOTTOM", 0, 7)
  diff:SetTextColor(0.75, 0.73, 0.66)
  f.diff = diff
  f:Hide()
  self.frame = f
end

local function fill(bar, label, color, d)
  local frac = (d.max or 0) > 0 and math.min(1, (d.xp or 0) / d.max) or 0
  local restFrac = (d.max or 0) > 0 and math.min(1, ((d.xp or 0) + (d.rest or 0)) / d.max) or 0
  bar:SetValue(frac)
  bar.rest:SetValue(restFrac)
  local r, g, b = tonumber(color:sub(1, 2), 16) / 255, tonumber(color:sub(3, 4), 16) / 255, tonumber(color:sub(5, 6), 16) / 255
  bar:SetStatusBarColor(r * 0.8, g * 0.8, b * 0.8, 1)
  bar.text:SetText("|cff" .. color .. label .. "|r  " .. d.level)
  bar.right:SetText(("%d%%"):format(frac * 100 + 0.5) .. ((d.rest or 0) > 0 and (" |cff6699ff+%d%%|r"):format(math.min(150, d.rest / math.max(1, d.max) * 100) + 0.5) or ""))
end

-- the partner to compare with: the freshest one that is in your group
local function partner()
  local best, bestName
  for name, d in pairs(X.partners) do
    local inGroup = true
    if UnitInParty then inGroup = UnitInParty(name) or UnitInParty(U.FirstName(name)) or false end
    if inGroup and (not best or d.at > best.at) then best, bestName = d, name end
  end
  return best, bestName
end

function X:Update()
  if not self.enabled then return end
  self:Create()
  local f = self.frame
  local p, pname = partner()
  if not p or not Comm:GroupChannel() then f:Hide(); return end
  local me = myXP()
  local myColor = (FS.Gear.State.self and FS.Gear.State.self.prof.color) or "d9a441"
  local st = FS.Gear.State.partners[pname]
  local theirColor = st and st.prof.color or "ff7d0a"
  fill(f.bars[1], "You", myColor, me)
  fill(f.bars[2], U.FirstName(pname), theirColor, p)
  self.rows = {
    { label = "You", d = me, toLevel = me.max > 0 and (me.max - me.xp) or nil },
    { label = U.FirstName(pname), d = p, toLevel = p.max > 0 and (p.max - p.xp) or nil },
  }
  local gap = progress(p) - progress(me)
  local who = gap > 0 and U.FirstName(pname) or "You"
  if math.abs(gap) < 0.02 then f.diff:SetText("Level and pace: even")
  else f.diff:SetText(("%s %s ahead by %.2f levels"):format(who, gap > 0 and "is" or "are", math.abs(gap))) end
  f:Show()
end

function X:OnEnable()
  self:Listen("COMM_XP", "OnXP")
  self:Listen("COMM_H", function() FS:Debounce("xp-hello", 3, function() X:Send(true) end) end)
  self:Listen("SYNC_REQUESTED", function() X:Send(true) end)
  local function changed() FS:Debounce("xp-send", 4, function() X:Send(false) end); X:Update() end
  self:RegisterEvent("PLAYER_XP_UPDATE", changed)
  self:RegisterEvent("PLAYER_LEVEL_UP", changed)
  self:RegisterEvent("UPDATE_EXHAUSTION", changed)
  self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    FS:Debounce("xp-roster", 5, function() X:Send(true); X:Update() end)
  end)
  FS:Debounce("xp-start", 7, function() X:Send(true); X:Update() end)
end

function X:OnDisable()
  if self.frame then self.frame:Hide() end
end
