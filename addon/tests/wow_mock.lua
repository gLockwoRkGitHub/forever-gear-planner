-- A small stand-in for the WoW client API, enough to load Forever Suite in plain Lua 5.1 and drive it
-- through events. Widgets accept every method (unknown ones do nothing); the game state lives in M.game.
local M = { printed = {}, sent = {}, timers = {}, frames = {}, tooltipLines = {}, postCalls = {} }

-- --- widgets ---------------------------------------------------------------------------------------
local W = {}
local function noop() end
-- game widget methods are PascalCase: unknown ones do nothing; unset lowercase fields are nil as in the game
local meta = { __index = function(_, k) return W[k] or (type(k) == "string" and k:match("^%u") and noop) or nil end }
local function widget(kind, name, parent)
  local w = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true, _w = 300, _h = 20, _text = "",
    _scripts = {}, _checked = false, _value = 0, _min = 0, _max = 0, _events = {} }, meta)
  M.frames[#M.frames + 1] = w
  if name then _G[name] = w end
  return w
end
M.widget = widget
function W:SetSize(w, h) self._w, self._h = w, h end
function W:SetWidth(w) self._w = w end
function W:SetHeight(h) self._h = h end
function W:GetWidth() return self._w end
function W:GetHeight() return self._h end
function W:GetSize() return self._w, self._h end
function W:Show() self._shown = true; if self._scripts.OnShow then self._scripts.OnShow(self) end end
function W:Hide() self._shown = false; if self._scripts.OnHide then self._scripts.OnHide(self) end end
function W:SetShown(v) if v then self:Show() else self:Hide() end end
function W:IsShown() return self._shown end
function W:IsVisible() return self._shown end
function W:SetText(t) self._text = t end
function W:GetText() return self._text end
function W:SetScript(k, f) self._scripts[k] = f end
function W:GetScript(k) return self._scripts[k] end
function W:HookScript(k, f)
  local old = self._scripts[k]
  self._scripts[k] = function(...) if old then old(...) end; f(...) end
end
function W:CreateTexture() return widget("Texture", nil, self) end
function W:CreateFontString() return widget("FontString", nil, self) end
function W:SetChecked(v) self._checked = v and true or false end
function W:GetChecked() return self._checked end
function W:SetMinMaxValues(a, b) self._min, self._max = a, b end
function W:GetMinMaxValues() return self._min, self._max end
function W:SetValue(v) self._value = v; if self._scripts.OnValueChanged then self._scripts.OnValueChanged(self, v) end end
function W:GetValue() return self._value end
function W:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function W:GetName() return self._name end
function W:GetStringHeight() return 12 end
function W:GetEffectiveScale() return 1 end
function W:GetCenter() return 0, 0 end
function W:NumLines() return 0 end
function W:RegisterEvent(e) self._events[e] = true end
function W:UnregisterEvent(e) self._events[e] = nil end
function W:Click(button) if self._scripts.OnClick then self._scripts.OnClick(self, button or "LeftButton") end end
-- tooltips
function W:SetOwner() self._lines = {} end
function W:AddLine(t) self._lines = self._lines or {}; self._lines[#self._lines + 1] = t end
function W:AddDoubleLine(l, r) self._lines = self._lines or {}; self._lines[#self._lines + 1] = l .. " | " .. tostring(r) end
local function tooltipFor(self, id, link)
  self._lines = {}
  self._item = { id = id, link = link }
  for _, f in ipairs(M.postCalls) do f(self, { id = id, hyperlink = link }) end
end
function W:SetItemByID(id) tooltipFor(self, id, M.link(id)) end
function W:SetHyperlink(link) tooltipFor(self, tonumber(link:match("item:(%d+)")), link) end
function W:GetItem() if self._item then return "name", self._item.link, self._item.id end end

-- --- game state ----------------------------------------------------------------------------------
M.game = {
  class = { "Shaman", "SHAMAN" }, level = 34, name = "Koda",
  stats = { 110, 55, 70, 75, 60 }, ap = 290, crit = 6.5, spellCrit = 3.2, sp = 0,
  inventory = {},          -- invSlot -> link
  bags = {},               -- list of item IDs
  quests = {},             -- questID -> true
  questChoices = {},       -- links
  stats_by_link = {},      -- link -> GetItemStats table
  group = nil,             -- "PARTY" when grouped
  instance = nil,          -- { name, id }
  form = nil,
  locale = "deDE",
  professions = { 333, 393 },
}

function M.link(id, suffix)
  return ("|cff1eff00|Hitem:%d::::::%s::34:::::|h[item %d]|h|r"):format(id, suffix and tostring(suffix) or "", id)
end

-- --- globals -------------------------------------------------------------------------------------
function M.install(FS_items_lookup)
  local g = M.game
  _G.CreateFrame = function(kind, name, parent) return widget(kind, name, parent) end
  _G.UIParent = widget("Frame", "UIParent")
  _G.WorldFrame = widget("Frame", "WorldFrame")
  _G.Minimap = widget("Frame", "Minimap")
  _G.GameTooltip = widget("GameTooltip", "GameTooltip")
  _G.ItemRefTooltip = widget("GameTooltip", "ItemRefTooltip")
  _G.ChatFontNormal = {}
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) M.printed[#M.printed + 1] = msg end }
  _G.print = function(...) local t = {}; for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end; M.printed[#M.printed + 1] = table.concat(t, " ") end
  _G.UISpecialFrames = {}
  _G.SlashCmdList = {}
  _G.tinsert = table.insert
  _G.wipe = function(t) for k in pairs(t) do t[k] = nil end; return t end
  _G.geterrorhandler = function() return function(e) M.errors = M.errors or {}; M.errors[#M.errors + 1] = e; io.stderr:write("LUA ERROR: " .. tostring(e) .. "\n" .. debug.traceback() .. "\n") end end
  _G.GetTime = function() return M.now or 1000 end
  _G.time = os.time
  _G.date = os.date
  _G.GetLocale = function() return g.locale end
  _G.C_Timer = { After = function(d, f) M.timers[#M.timers + 1] = { at = (M.now or 1000) + d, f = f } end }
  _G.Enum = { TooltipDataType = { Item = 0 }, SendAddonMessageResult = { Success = 0 } }
  _G.TooltipDataProcessor = { AddTooltipPostCall = function(_, f) M.postCalls[#M.postCalls + 1] = f end }
  _G.UnitClass = function() return g.class[1], g.class[2] end
  _G.UnitLevel = function() return g.level end
  _G.UnitName = function() return g.name end
  _G.UnitStat = function(_, i) return g.stats[i], g.stats[i], 0, 0 end
  _G.UnitAttackPower = function() return g.ap, 0, 0 end
  _G.GetCritChance = function() return g.crit end
  _G.GetSpellCritChance = function() return g.spellCrit end
  _G.GetSpellBonusDamage = function() return g.sp end
  _G.GetDodgeChance = function() return g.dodge end
  _G.GetParryChance = function() return g.parry end
  _G.GetShapeshiftFormID = function() return g.form end
  _G.GetInventoryItemLink = function(_, slot) return g.inventory[slot] end
  _G.InCombatLockdown = function() return false end
  _G.UnitAffectingCombat = function() return false end
  _G.IsInGroup = function() return g.group ~= nil end
  _G.IsInRaid = function() return false end
  _G.LE_PARTY_CATEGORY_INSTANCE = 2
  _G.Ambiguate = function(n) return n end
  _G.IsInInstance = function() if g.instance then return true, "party" end; return false, "none" end
  _G.GetInstanceInfo = function() if g.instance then return g.instance.name, "party", 1, "Normal", 5, 0, false, g.instance.id end; return "Kalimdor", "none" end
  _G.GetProfessions = function() return 1, 2 end
  _G.GetProfessionInfo = function(i) return "x", nil, 1, 1, 0, 0, g.professions[i] end
  _G.C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and #g.bags or 0 end,
    GetContainerItemID = function(bag, slot) return bag == 0 and g.bags[slot] or nil end,
  }
  _G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return g.quests[id] == true end,
    GetAllCompletedQuestIDs = function() local t = {}; for id in pairs(g.quests) do t[#t + 1] = id end; return t end,
    GetTitleForQuestID = function(id) return "Quest title " .. id end,
  }
  _G.GetNumQuestChoices = function() return #g.questChoices end
  _G.GetNumQuestRewards = function() return 0 end
  _G.GetQuestID = function() return g.questID or 0 end
  _G.GetQuestItemLink = function(_, i) return g.questChoices[i] end
  _G.QuestInfoFrame = { rewardsFrame = widget("Frame", "QuestInfoRewardsFrame") }
  _G.QuestInfo_GetRewardButton = function(_, i) M.rewardButtons = M.rewardButtons or {}; M.rewardButtons[i] = M.rewardButtons[i] or widget("Button"); return M.rewardButtons[i] end
  _G.GetLootRollItemLink = function(id) return M.rollLinks and M.rollLinks[id] end
  _G.GetNumLootItems = function() return 0 end
  _G.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, channel, target) M.sent[#M.sent + 1] = { prefix = prefix, msg = msg, channel = channel, target = target }; return 0 end,
  }
  local EQUIP = { Head = "INVTYPE_HEAD", Neck = "INVTYPE_NECK", Shoulder = "INVTYPE_SHOULDER", Back = "INVTYPE_CLOAK", Chest = "INVTYPE_CHEST",
    Wrist = "INVTYPE_WRIST", Hands = "INVTYPE_HAND", Waist = "INVTYPE_WAIST", Legs = "INVTYPE_LEGS", Feet = "INVTYPE_FEET",
    Finger = "INVTYPE_FINGER", Trinket = "INVTYPE_TRINKET", ["Two-Hand"] = "INVTYPE_2HWEAPON", Relic = "INVTYPE_RELIC" }
  local function idOf(item) if type(item) == "number" then return item end; return tonumber(tostring(item):match("item:(%d+)")) end
  _G.C_Item = {
    GetItemInfo = function(item)
      local id = idOf(item)
      local it = FS_items_lookup(id) or (M.unknownItems and M.unknownItems[id])
      if not it then return nil end
      return it.n, M.link(id), it.q, it.il, it.rq, "Armor", "x", 1, EQUIP[it.sl], 134400, it.price or 120, it.classID or 4, it.subclassID or 1
    end,
    GetItemInfoInstant = function(item)
      local id = idOf(item)
      local it = FS_items_lookup(id) or (M.unknownItems and M.unknownItems[id])
      if not it then return nil end
      return id, "Armor", "x", EQUIP[it.sl], 134400, it.classID or 4, it.subclassID or 1
    end,
    GetItemStats = function(link) return g.stats_by_link[link] end,
    RequestLoadItemDataByID = function() end,
  }
end

-- --- driving -------------------------------------------------------------------------------------
function M.fire(event, ...)
  for _, f in ipairs(M.frames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

-- advance the clock by `seconds`, running timers in order (timers they start run too when due)
function M.runTimers(seconds)
  local target = (M.now or 1000) + (seconds or 30)
  for _ = 1, 5000 do
    local idx, first
    for i, t in ipairs(M.timers) do if not first or t.at < first.at then idx, first = i, t end end
    if not first or first.at > target then break end
    table.remove(M.timers, idx)
    M.now = math.max(M.now or 1000, first.at)
    first.f()
  end
  M.now = target
end

-- deliver everything sent so far as if `sender` had sent it
function M.deliver(sender, filter)
  local list = M.sent
  M.sent = {}
  for _, s in ipairs(list) do
    if not filter or s.msg:match("^" .. filter .. "\t") then M.fire("CHAT_MSG_ADDON", s.prefix, s.msg, s.channel, sender) end
  end
  return #list
end

function M.load(dir, FS)
  local toc = assert(io.open(dir .. "/ForeverSuite.toc")):read("*a")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^##") and line:match("%.lua$") then
      local path = dir .. "/" .. line:gsub("\\", "/")
      local chunk = assert(loadfile(path))
      chunk("ForeverSuite", FS)
    end
  end
end

function M.lastPrints(n)
  local out = {}
  for i = math.max(1, #M.printed - (n or 5) + 1), #M.printed do out[#out + 1] = M.printed[i] end
  return out
end

return M
