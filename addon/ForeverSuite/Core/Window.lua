-- The suite's main window: one tab per feature. Modules add their tab with Window:AddTab; a tab
-- whose module is switched off is hidden.
local _, FS = ...
local UI = FS.UI
local W = { tabs = {} }
FS.Window = W

-- builder(parent) returns an object with :Refresh(); module = id of the module that owns the tab (optional)
function W:AddTab(id, title, order, builder, module)
  self.tabs[#self.tabs + 1] = { id = id, title = title, order = order, builder = builder, module = module }
  table.sort(self.tabs, function(a, b) return a.order < b.order end)
  if self.frame then self:LayoutTabs() end
end

local function tabVisible(t)
  return not t.module or (FS.modules[t.module] and FS.modules[t.module].enabled)
end

function W:Create()
  local f = UI.Window("ForeverSuiteWindow", "Forever Suite", 840, 580)
  local pos = FS.db.window
  if pos.point then
    f:ClearAllPoints()
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
  end
  if pos.w and pos.h then f:SetSize(pos.w, pos.h) end
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
  end)
  f:SetResizable(true)
  if f.SetResizeBounds then pcall(f.SetResizeBounds, f, 640, 420, 1400, 1100)
  elseif f.SetMinResize then pcall(f.SetMinResize, f, 640, 420) end
  local grip = CreateFrame("Button", nil, f)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", -2, 2)
  grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
  grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
  grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
  grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
  grip:SetScript("OnMouseUp", function()
    f:StopMovingOrSizing()
    pos.w, pos.h = f:GetSize()
    W:RefreshVisible()
  end)

  local ver = UI.Text(f, "GameFontDisableSmall", FS.Data.meta and FS.Data.meta.version or "")
  ver:SetPoint("LEFT", f.title, "RIGHT", 10, -1)

  local tabBar = CreateFrame("Frame", nil, f)
  tabBar:SetPoint("TOPLEFT", 12, -40)
  tabBar:SetPoint("TOPRIGHT", -12, -40)
  tabBar:SetHeight(24)
  f.tabBar = tabBar
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 12, -70)
  body:SetPoint("BOTTOMRIGHT", -12, 16)
  f.body = body
  f:SetScript("OnShow", function() W:RefreshVisible() end)
  self.frame = f
  self:LayoutTabs()
  FS:Listen("STATE_CHANGED", W, function() W:RefreshSoon() end)
  FS:Listen("PARTNER_CHANGED", W, function() W:RefreshSoon() end)
  FS:Listen("IMPORTED", W, function() W:RefreshSoon() end)
  FS:Listen("MODULES_CHANGED", W, function()
    W:LayoutTabs()
    local cur = W.current and W:Tab(W.current)
    if not cur or not tabVisible(cur) then W:Select("settings") else W:RefreshSoon() end
  end)
end

function W:Tab(id)
  for _, t in ipairs(self.tabs) do if t.id == id then return t end end
end

function W:LayoutTabs()
  local x = 0
  for _, t in ipairs(self.tabs) do
    if not t.button then
      t.button = UI.Flat(self.frame.tabBar, t.title, 110, 24, function() W:Select(t.id) end)
    end
    if tabVisible(t) then
      t.button:ClearAllPoints()
      t.button:SetPoint("LEFT", x, 0)
      t.button:Show()
      x = x + 114
    else
      t.button:Hide()
      if t.panel then t.panel:Hide() end
    end
  end
end

function W:Select(id)
  local t = self:Tab(id)
  if not t or not tabVisible(t) then
    for _, x in ipairs(self.tabs) do if tabVisible(x) then t = x; break end end
  end
  if not t then return end
  for _, x in ipairs(self.tabs) do
    if x.panel then x.panel:SetShown(x == t) end
    if x.button then x.button:SetActive(x == t) end
  end
  if not t.panel then
    t.panel = CreateFrame("Frame", nil, self.frame.body)
    t.panel:SetAllPoints()
    t.obj = t.builder(t.panel)
  end
  t.panel:Show()
  self.current = t.id
  FS.db.window.tab = t.id
  if t.obj and t.obj.Refresh then FS.safecall(t.obj.Refresh, t.obj) end
end

function W:Show(id)
  if not self.frame then self:Create() end
  self.frame:Show()
  self:Select(id or self.current or FS.db.window.tab or "overview")
end

function W:Toggle()
  if self.frame and self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

function W:IsShown() return self.frame and self.frame:IsShown() end

function W:RefreshVisible()
  if not self:IsShown() then return end
  local t = self.current and self:Tab(self.current)
  if t and t.obj and t.obj.Refresh then FS.safecall(t.obj.Refresh, t.obj) end
end

function W:RefreshSoon()
  if not self:IsShown() then return end
  FS:Debounce("window", 0.15, function() W:RefreshVisible() end)
end
