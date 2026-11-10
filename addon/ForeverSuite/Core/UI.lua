-- Shared widgets in the planner's look: dark panels, gold accent, item rows with game tooltips.
-- Built from plain frames and long-standing templates only, so they survive UI reskins.
local _, FS = ...
local U = FS.U
local UI = {}
FS.UI = UI

UI.GOLD = { 0.85, 0.64, 0.25 }
UI.BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 }

function UI.Panel(parent, r, g, b, a)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop(UI.BACKDROP)
  f:SetBackdropColor(r or 0.11, g or 0.12, b or 0.145, a or 1)
  f:SetBackdropBorderColor(0.185, 0.204, 0.24, 1)
  return f
end

function UI.Text(parent, font, text, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetText(text or "")
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

function UI.Button(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w or 100, h or 22)
  b:SetText(text or "")
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

-- flat button (tabs, cycle buttons)
function UI.Flat(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w or 100, h or 22)
  b:SetBackdrop(UI.BACKDROP)
  b:SetBackdropColor(0.137, 0.153, 0.18, 1)
  b:SetBackdropBorderColor(0.185, 0.204, 0.24, 1)
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER")
  fs:SetText(text or "")
  b.label = fs
  b:SetFontString(fs)
  b:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1)
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function(self)
    if not self.active then self:SetBackdropBorderColor(0.185, 0.204, 0.24, 1) end
    if self.tip then GameTooltip:Hide() end
  end)
  function b:SetActive(on)
    self.active = on
    if on then
      self:SetBackdropColor(0.17, 0.165, 0.14, 1)
      self:SetBackdropBorderColor(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 1)
      self.label:SetTextColor(1, 1, 1)
    else
      self:SetBackdropColor(0.137, 0.153, 0.18, 1)
      self:SetBackdropBorderColor(0.185, 0.204, 0.24, 1)
      self.label:SetTextColor(0.75, 0.73, 0.66)
    end
  end
  if onClick then b:SetScript("OnClick", onClick) end
  return b
end

function UI.Check(parent, label, onClick, tip)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  local fs = UI.Text(parent, "GameFontHighlight", label)
  fs:SetPoint("LEFT", c, "RIGHT", 2, 1)
  c.labelText = fs
  if onClick then c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end) end
  if tip then
    c:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return c
end

-- a movable window with title and close button (closes with Escape)
function UI.Window(name, title, w, h)
  local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetBackdrop(UI.BACKDROP)
  f:SetBackdropColor(0.078, 0.086, 0.10, 0.97)
  f:SetBackdropBorderColor(0.3, 0.27, 0.2, 1)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  local bar = f:CreateTexture(nil, "ARTWORK")
  bar:SetColorTexture(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.9)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(2)
  local t = UI.Text(f, "GameFontNormalLarge", title)
  t:SetPoint("TOPLEFT", 14, -12)
  f.title = t
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  if name then tinsert(UISpecialFrames, name) end
  return f
end

-- scroll area: returns the scroll frame; put rows on scroll.content and call scroll:SetContentHeight(h)
function UI.Scroll(parent)
  local sf = CreateFrame("ScrollFrame", nil, parent)
  local content = CreateFrame("Frame", nil, sf)
  content:SetSize(1, 1)
  sf:SetScrollChild(content)
  sf.content = content
  local bar = CreateFrame("Slider", nil, sf)
  bar:SetOrientation("VERTICAL")
  bar:SetWidth(6)
  bar:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 0, 0)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints()
  track:SetColorTexture(1, 1, 1, 0.04)
  local thumb = bar:CreateTexture(nil, "OVERLAY")
  thumb:SetColorTexture(UI.GOLD[1], UI.GOLD[2], UI.GOLD[3], 0.55)
  thumb:SetSize(6, 40)
  bar:SetThumbTexture(thumb)
  bar:SetMinMaxValues(0, 0)
  bar:SetValueStep(1)
  bar:SetValue(0)
  bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
  sf.bar = bar
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta)
    local lo, hi = bar:GetMinMaxValues()
    bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - delta * 48)))
  end)
  sf:SetScript("OnSizeChanged", function(self, w)
    content:SetWidth(math.max(1, (w or self:GetWidth()) - 10))
    if self.contentHeight then self:SetContentHeight(self.contentHeight) end
  end)
  function sf:SetContentHeight(h)
    self.contentHeight = h
    content:SetHeight(math.max(1, h))
    local max = math.max(0, h - self:GetHeight())
    bar:SetMinMaxValues(0, max)
    bar:SetShown(max > 0)
    if bar:GetValue() > max then bar:SetValue(max) end
  end
  function sf:ScrollToTop() bar:SetValue(0) end
  return sf
end

-- --- item rows ---------------------------------------------------------------------------------
local function rowEnter(self)
  if not self.item then
    if self.tip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
    return
  end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  local it = self.item
  if it.link then GameTooltip:SetHyperlink(it.link)
  elseif GameTooltip.SetItemByID then GameTooltip:SetItemByID(it.id)
  else GameTooltip:SetHyperlink("item:" .. it.id) end
  if self.extra then
    GameTooltip:AddLine(" ")
    for _, l in ipairs(self.extra) do GameTooltip:AddLine(l, 0.8, 0.78, 0.7, true) end
  end
  GameTooltip:Show()
end
local function rowClick(self)
  if self.item and IsModifiedClick and (IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP")) then
    U.InsertLink(self.item.link or U.ItemLinkFor(self.item.id, self.item.n, self.item.q))
  elseif self.onClick then
    self.onClick(self)
  end
end

-- a row: icon, name, right-hand value, second line
function UI.ItemRow(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(32)
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.05)
  local rank = UI.Text(r, "GameFontDisable", "", "CENTER")
  rank:SetWidth(16)
  rank:SetPoint("LEFT", 2, 0)
  r.rank = rank
  local ic = r:CreateTexture(nil, "ARTWORK")
  ic:SetSize(24, 24)
  ic:SetPoint("LEFT", 4, 0)
  ic:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  r.icon = ic
  local right = UI.Text(r, "GameFontNormal", "", "RIGHT")
  right:SetPoint("RIGHT", -6, 5)
  r.right = right
  local right2 = UI.Text(r, "GameFontDisableSmall", "", "RIGHT")
  right2:SetPoint("RIGHT", -6, -8)
  r.right2 = right2
  local name = UI.Text(r, "GameFontHighlight", "")
  name:SetPoint("TOPLEFT", ic, "TOPRIGHT", 8, 1)
  name:SetPoint("RIGHT", right, "LEFT", -8, 0)
  r.name = name
  local sub = UI.Text(r, "GameFontHighlightSmall", "")
  sub:SetPoint("BOTTOMLEFT", ic, "BOTTOMRIGHT", 8, -1)
  sub:SetPoint("RIGHT", right2, "LEFT", -8, 0)
  sub:SetTextColor(0.62, 0.6, 0.53)
  r.sub = sub
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetScript("OnEnter", rowEnter)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", rowClick)
  function r:SetItem(it, rightText, subText, right2Text)
    self.item = it
    self.extra, self.onClick, self.tip = nil, nil, nil
    self:SetRank(nil)
    self.icon:SetTexture(it and it.ic and ("Interface\\Icons\\" .. it.ic) or (it and U.ItemInfoInstant(it.id) and U.ItemInfoInstant(it.id).icon) or 134400)
    self.icon:Show()
    self.name:SetText(it and ("|cff" .. U.qualityHex(it.q) .. (it.n or "?") .. "|r") or "")
    self.right:SetText(rightText or "")
    self.right2:SetText(right2Text or "")
    self.sub:SetText(subText or "")
  end
  -- a rank number in front of the icon (nil: none)
  function r:SetRank(n)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("LEFT", n and 22 or 4, 0)
    self.rank:SetText(n and tostring(n) or "")
  end
  function r:SetPlain(text, subText, rightText)
    self.item = nil
    self.extra, self.onClick, self.tip = nil, nil, nil
    self:SetRank(nil)
    self.icon:Hide()
    self.name:SetText(text or "")
    self.sub:SetText(subText or "")
    self.right:SetText(rightText or "")
    self.right2:SetText("")
  end
  return r
end

-- reusable widget pools for list views
function UI.Pool(make)
  local pool = { items = {}, used = 0 }
  function pool:Get(parent)
    self.used = self.used + 1
    local w = self.items[self.used]
    if not w then w = make(parent); self.items[self.used] = w end
    w:ClearAllPoints()
    w:Show()
    return w
  end
  function pool:Reset()
    for _, w in ipairs(self.items) do w:Hide() end
    self.used = 0
  end
  return pool
end

-- a section header line inside a list
function UI.Header(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(24)
  local line = f:CreateTexture(nil, "BACKGROUND")
  line:SetColorTexture(1, 1, 1, 0.06)
  line:SetPoint("BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", 0, 0)
  line:SetHeight(1)
  local t = UI.Text(f, "GameFontNormal", "")
  t:SetPoint("LEFT", 4, 0)
  f.text = t
  local r = UI.Text(f, "GameFontHighlightSmall", "", "RIGHT")
  r:SetPoint("RIGHT", -6, 0)
  r:SetPoint("LEFT", t, "RIGHT", 10, 0)
  r:SetTextColor(0.62, 0.6, 0.53)
  f.right = r
  return f
end

-- a one-line note about an item (hover shows the item), e.g. "Coming up at level 35: ..."
function UI.ItemNote(parent)
  local f = CreateFrame("Button", nil, parent)
  f:SetHeight(20)
  local hl = f:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.04)
  local r = UI.Text(f, "GameFontHighlightSmall", "", "RIGHT")
  r:SetPoint("RIGHT", -6, 0)
  f.right = r
  local t = UI.Text(f, "GameFontHighlightSmall", "")
  t:SetPoint("LEFT", 6, 0)
  t:SetPoint("RIGHT", r, "LEFT", -8, 0)
  f.text = t
  f:SetScript("OnEnter", rowEnter)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  f:SetScript("OnClick", rowClick)
  return f
end

-- a plain line of text inside a list
function UI.Line(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(18)
  local t = UI.Text(f, "GameFontHighlightSmall", "")
  t:SetPoint("LEFT", 6, 0)
  t:SetPoint("RIGHT", -6, 0)
  f.text = t
  return f
end

function UI.ClassHex(prof) return prof and prof.color or "ffffff" end
