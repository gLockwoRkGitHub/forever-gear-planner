-- Minimap button: left click opens the window, right click the Settings tab, drag to move it.
local _, FS = ...
local M = {}
FS.Minimap = M

local function place(b)
  local a = math.rad(FS.db.minimap.angle or 200)
  local r = (Minimap:GetWidth() / 2) + 6
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function M:Create()
  if self.button or not Minimap then return end
  local b = CreateFrame("Button", "ForeverSuiteMinimapButton", Minimap)
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Book_11")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  b:SetScript("OnClick", function(_, button)
    if button == "RightButton" then FS.Window:Show("settings") else FS.Window:Toggle() end
  end)
  b:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      FS.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
      place(self)
    end)
  end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Forever Suite", 0.85, 0.64, 0.25)
    GameTooltip:AddLine("Left click: open · Right click: settings · Drag: move", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.button = b
  place(b)
end

function M:Update()
  if FS.db.minimap.hide then
    if self.button then self.button:Hide() end
  else
    self:Create()
    if self.button then self.button:Show(); place(self.button) end
  end
end

-- the game's addon menu at the minimap (where the client has one)
function ForeverSuite_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then FS.Window:Show("settings") else FS.Window:Toggle() end
end

local core = {}
FS:Listen("READY", core, function() FS.safecall(M.Update, M) end)
