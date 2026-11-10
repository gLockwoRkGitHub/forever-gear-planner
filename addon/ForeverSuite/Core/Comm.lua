-- Addon messages between group members running Forever Suite. Long payloads are split into parts
-- (the game allows 255 bytes per message) and sent at a calm pace so the game does not throttle them.
-- Received payloads are announced as internal message "COMM_<KIND>" (sender, payload, channel).
local _, FS = ...
local U = FS.U
local Comm = {}
FS.Comm = Comm

Comm.PREFIX = "ForeverSuite"
local PART = 220          -- payload bytes per message
local INTERVAL = 0.35     -- seconds between messages
local queue, sending = {}, false
local buffers = {}        -- sender..id -> { n, parts = {}, got }
local counter = 0

local function register()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comm.PREFIX)
  elseif RegisterAddonMessagePrefix then
    pcall(RegisterAddonMessagePrefix, Comm.PREFIX)
  end
end

function Comm:GroupChannel()
  if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
end

local function rawSend(msg, channel, target)
  local f = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not f then return false end
  local ok, res = pcall(f, Comm.PREFIX, msg, channel, target)
  if not ok then return false end
  if res == nil or res == true or res == 0 then return true end
  if Enum and Enum.SendAddonMessageResult and res == Enum.SendAddonMessageResult.Success then return true end
  return false, res
end

local function pump()
  local item = queue[1]
  if not item then sending = false; return end
  local ok = rawSend(item.msg, item.channel, item.target)
  if ok then
    table.remove(queue, 1)
    C_Timer.After(INTERVAL, pump)
  else
    item.tries = (item.tries or 0) + 1
    if item.tries > 6 then
      FS:Debug("dropped message after retries", item.channel)
      table.remove(queue, 1)
    end
    C_Timer.After(2, pump)   -- throttled or blocked for now (e.g. during a boss fight): try again later
  end
end

-- Send `payload` (string) of type `kind` (letters only) to the group, or to `target` by whisper.
function Comm:Send(kind, payload, channel, target)
  channel = channel or (target and "WHISPER") or self:GroupChannel()
  if not channel then return false end
  counter = (counter % 999) + 1
  local n = math.max(1, math.ceil(#payload / PART))
  for i = 1, n do
    local part = payload:sub((i - 1) * PART + 1, i * PART)
    queue[#queue + 1] = { msg = kind .. "\t" .. counter .. "\t" .. i .. "\t" .. n .. "\t" .. part, channel = channel, target = target }
  end
  if not sending then sending = true; pump() end
  return true
end

function Comm:Busy() return #queue end

local me
local function onMessage(_, _, prefix, text, channel, sender)
  if prefix ~= Comm.PREFIX or type(text) ~= "string" or U.secret(text) then return end
  me = me or U.Me()
  local who = U.ShortName(sender)
  if not who or who == me then return end
  local kind, id, i, n, part = text:match("^(%a+)\t(%d+)\t(%d+)\t(%d+)\t(.*)$")
  if not kind then return end
  i, n = tonumber(i), tonumber(n)
  local key = who .. ":" .. id
  local b = buffers[key]
  if not b or b.n ~= n then b = { n = n, parts = {}, got = 0, at = GetTime() }; buffers[key] = b end
  if not b.parts[i] then b.parts[i] = part; b.got = b.got + 1 end
  if b.got >= n then
    buffers[key] = nil
    FS:Fire("COMM_" .. kind, who, table.concat(b.parts), channel)
  end
end

-- drop half-received payloads after a while
local function sweep()
  local now = GetTime()
  for k, b in pairs(buffers) do if now - b.at > 120 then buffers[k] = nil end end
  C_Timer.After(60, sweep)
end

local core = {}
FS:On("PLAYER_LOGIN", core, function()
  register()
  FS:On("CHAT_MSG_ADDON", Comm, onMessage)
  C_Timer.After(60, sweep)
end)

-- --- tiny key/value encoding used by the payloads -------------------------------------------------
-- { a = 1, b = "x" } -> "a=1;b=x"   (values must not contain ";" or "=")
function Comm.encode(t)
  local parts = {}
  for k, v in pairs(t) do
    if v ~= nil then parts[#parts + 1] = k .. "=" .. tostring(v) end
  end
  table.sort(parts)
  return table.concat(parts, ";")
end
function Comm.decode(s)
  local t = {}
  for _, pair in ipairs(U.split(s or "", ";")) do
    local k, v = pair:match("^([^=]+)=(.*)$")
    if k then t[k] = v end
  end
  return t
end
-- { str = 5, agi = 1.5 } <-> "str:5,agi:1.5"
function Comm.encodeMap(m)
  local parts = {}
  for k, v in pairs(m or {}) do
    if type(v) == "number" then parts[#parts + 1] = k .. ":" .. (math.floor(v) == v and tostring(v) or ("%.4g"):format(v))
    elseif v == true then parts[#parts + 1] = k .. ":1" end
  end
  table.sort(parts)
  return table.concat(parts, ",")
end
function Comm.decodeMap(s)
  local m = {}
  for _, pair in ipairs(U.split(s or "", ",")) do
    local k, v = pair:match("^([^:]+):(.*)$")
    if k then m[k] = tonumber(v) end
  end
  return m
end
