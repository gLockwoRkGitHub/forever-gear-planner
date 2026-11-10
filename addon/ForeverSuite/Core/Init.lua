-- Forever Suite: core. Module registry, saved settings, event dispatch, internal messages, slash command.
-- Every feature is a module that can be switched on and off (Settings tab or /fs module <id> on|off).
local ADDON, FS = ...
_G.ForeverSuite = FS

FS.name = "Forever Suite"
FS.Data = { items = {} }
FS.modules, FS.moduleList = {}, {}

local unpack, select, type, pairs, ipairs = unpack, select, type, pairs, ipairs

-- --- printing --------------------------------------------------------------------------------
function FS:Print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  DEFAULT_CHAT_FRAME:AddMessage("|cffd9a441Forever Suite|r " .. table.concat(parts, " "))
end
function FS:Debug(...)
  if ForeverSuiteDB and ForeverSuiteDB.debug then self:Print("|cff888888[debug]|r", ...) end
end

-- Run fn and report an error without breaking the caller (one module's bug must not stop the others).
local function safecall(fn, ...)
  local n, args = select("#", ...), { ... }
  return xpcall(function() return fn(unpack(args, 1, n)) end, geterrorhandler())
end
FS.safecall = safecall

-- --- saved settings --------------------------------------------------------------------------
local DB_DEFAULTS = {
  modules = {},          -- module id -> true/false (nil: module default)
  imported = nil,        -- last website import: { date, chars = { shaman = {...}, druid = {...} } }
  partners = {},         -- name -> last known state of a partner (Partner module)
  questSync = {},        -- name -> { at, ids = { [questID] = true } }
  instanceMap = {},      -- instanceID -> dungeon name (dungeons the game did not name in English)
  questIds = {},         -- itemID -> questID, learned at quest givers for rewards the data knows only by quest name
  selfNames = {},        -- names your own group messages came back with (never a partner)
  minimap = { angle = 200, hide = false },
  window = {},
  debug = false,
}
local CHAR_DEFAULTS = {
  gear = {},             -- per-character planner settings (see State.lua)
  sheet = nil,           -- last caster-form character sheet (druids read it outside forms)
  dungeon = {},          -- dungeon guide settings
}
local function fill(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then dst[k] = {}; fill(dst[k], v) else dst[k] = v end
    elseif type(v) == "table" and type(dst[k]) == "table" then
      fill(dst[k], v)
    end
  end
  return dst
end

-- --- events ----------------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}  -- event -> { owner -> fn }
FS.eventFrame = frame
frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for owner, fn in pairs(list) do safecall(fn, owner, event, ...) end
end)
function FS:On(event, owner, fn)
  if not handlers[event] then
    handlers[event] = {}
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then self:Debug("event not available:", event) end
  end
  handlers[event][owner] = fn
end
function FS:Off(event, owner)
  local list = handlers[event]
  if not list then return end
  list[owner] = nil
  if next(list) == nil then handlers[event] = nil; pcall(frame.UnregisterEvent, frame, event) end
end

-- internal messages between modules ("GEAR_CHANGED", "PARTNER_CHANGED", "SETTINGS_CHANGED", ...)
local listeners = {}
function FS:Listen(msg, owner, fn) listeners[msg] = listeners[msg] or {}; listeners[msg][owner] = fn end
function FS:Unlisten(msg, owner) if listeners[msg] then listeners[msg][owner] = nil end end
function FS:Fire(msg, ...)
  local list = listeners[msg]
  if not list then return end
  for owner, fn in pairs(list) do safecall(fn, owner, msg, ...) end
end

-- one call after `delay` seconds, however often it is asked for meanwhile
local pending = {}
function FS:Debounce(key, delay, fn)
  if pending[key] then return end
  pending[key] = true
  C_Timer.After(delay, function() pending[key] = nil; safecall(fn) end)
end

-- --- modules ---------------------------------------------------------------------------------
local Module = {}
Module.__index = Module
function Module:RegisterEvent(event, fn)
  self._events = self._events or {}
  self._events[event] = true
  FS:On(event, self, type(fn) == "function" and fn or self[fn or event])
end
function Module:UnregisterEvent(event)
  if self._events then self._events[event] = nil end
  FS:Off(event, self)
end
function Module:Listen(msg, fn)
  self._msgs = self._msgs or {}
  self._msgs[msg] = true
  FS:Listen(msg, self, type(fn) == "function" and fn or self[fn or msg])
end
function Module:IsEnabled() return self.enabled end

-- def: { title, desc, default = true, order }
function FS:NewModule(id, def)
  local m = setmetatable(def or {}, Module)
  m.id = id
  m.enabled = false
  if m.default == nil then m.default = true end
  self.modules[id] = m
  self.moduleList[#self.moduleList + 1] = m
  table.sort(self.moduleList, function(a, b) return (a.order or 50) < (b.order or 50) end)
  return m
end

function FS:ModuleWanted(id)
  local m = self.modules[id]
  local v = ForeverSuiteDB.modules[id]
  if v == nil then return m.default end
  return v
end

local function enable(m)
  if m.enabled then return end
  m.enabled = true
  if m.OnEnable then safecall(m.OnEnable, m) end
end
local function disable(m)
  if not m.enabled then return end
  m.enabled = false
  if m._events then for ev in pairs(m._events) do FS:Off(ev, m) end; m._events = nil end
  if m._msgs then for msg in pairs(m._msgs) do FS:Unlisten(msg, m) end; m._msgs = nil end
  if m.OnDisable then safecall(m.OnDisable, m) end
end

function FS:SetModuleEnabled(id, on)
  local m = self.modules[id]
  if not m then return false end
  ForeverSuiteDB.modules[id] = on and true or false
  if on then enable(m) else disable(m) end
  self:Fire("MODULES_CHANGED", id, on)
  return true
end

-- --- start-up --------------------------------------------------------------------------------
local core = {}
FS:On("ADDON_LOADED", core, function(_, _, name)
  if name ~= ADDON then return end
  ForeverSuiteDB = fill(type(ForeverSuiteDB) == "table" and ForeverSuiteDB or {}, DB_DEFAULTS)
  ForeverSuiteCharDB = fill(type(ForeverSuiteCharDB) == "table" and ForeverSuiteCharDB or {}, CHAR_DEFAULTS)
  FS.db, FS.cdb = ForeverSuiteDB, ForeverSuiteCharDB
  FS:Off("ADDON_LOADED", core)
end)

-- your own names never count as partner (older versions stored your echoed messages as one)
function FS:ForgetSelf(name)
  if name then FS.db.selfNames[name] = true end
  local gone = false
  for _, store in ipairs({ FS.db.partners, FS.db.questSync }) do
    for n in pairs(store) do if FS.U.IsMe(n) then store[n] = nil; gone = true end end
  end
  if FS.Gear and FS.Gear.State then
    for n in pairs(FS.Gear.State.partners) do if FS.U.IsMe(n) then FS.Gear.State.partners[n] = nil; gone = true end end
  end
  if gone then FS:Fire("PARTNER_CHANGED") end
end
FS:Listen("SELF_NAME", core, function(_, _, name) FS:ForgetSelf(name) end)

FS:On("PLAYER_LOGIN", core, function()
  safecall(FS.ForgetSelf, FS)
  if FS.Gear then safecall(FS.Gear.Init, FS.Gear) end
  for _, m in ipairs(FS.moduleList) do
    if m.OnInitialize then safecall(m.OnInitialize, m) end
  end
  for _, m in ipairs(FS.moduleList) do
    if FS:ModuleWanted(m.id) then enable(m) end
  end
  FS.ready = true
  FS:Fire("READY")
end)

-- --- slash command ---------------------------------------------------------------------------
local function help()
  FS:Print("commands:")
  print("  /fs                  open or close the window")
  print("  /fs overview | gear | dungeons | quests | settings   open a tab")
  print("  /fs import           paste the text from the website")
  print("  /fs modules          list modules")
  print("  /fs module <id> on|off")
  print("  /fs sync             send your gear to your group now")
  print("  /fs debug            toggle debug messages")
end

SLASH_FOREVERSUITE1 = "/fs"
SLASH_FOREVERSUITE2 = "/foreversuite"
SlashCmdList.FOREVERSUITE = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "" then
    if FS.Window then FS.Window:Toggle() end
  elseif cmd == "overview" or cmd == "gear" or cmd == "dungeons" or cmd == "quests" or cmd == "settings" then
    if FS.Window then FS.Window:Show(cmd) end
  elseif cmd == "import" then
    if FS.Import then FS.Import:ShowDialog() end
  elseif cmd == "modules" then
    for _, m in ipairs(FS.moduleList) do
      print(("  %s  |cff%s%s|r  %s"):format(m.id, m.enabled and "40ff40" or "ff6060", m.enabled and "on" or "off", m.title or ""))
    end
  elseif cmd == "module" then
    local id, onoff = rest:match("^(%S+)%s*(%S*)$")
    if not id or not FS.modules[id] then FS:Print("unknown module. /fs modules lists them."); return end
    local on = onoff == "" and not FS.modules[id].enabled or onoff == "on"
    FS:SetModuleEnabled(id, on)
    FS:Print(FS.modules[id].title, on and "on" or "off")
  elseif cmd == "sync" then
    FS:Fire("SYNC_REQUESTED")
  elseif cmd == "debug" then
    FS.db.debug = not FS.db.debug
    FS:Print("debug", FS.db.debug and "on" or "off")
  else
    help()
  end
end
