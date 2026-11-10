-- Small helpers shared by all modules, and thin wrappers around game functions whose name or
-- shape differs between game versions (each wrapper fails soft and returns nil).
local _, FS = ...
local U = {}
FS.U = U

function U.split(s, sep)
  local out = {}
  if not s or s == "" then return out end
  local start = 1
  while true do
    local i = s:find(sep, start, true)
    if not i then out[#out + 1] = s:sub(start); break end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + #sep
  end
  return out
end

function U.copy(t)
  local o = {}
  for k, v in pairs(t or {}) do o[k] = v end
  return o
end

function U.round(v, d)
  local m = 10 ^ (d or 0)
  return math.floor(v * m + 0.5) / m
end

-- 4.2 -> "+4.2", -1.25 -> "-1.3"
function U.delta(d)
  return (d >= 0 and "+" or "-") .. ("%.1f"):format(math.abs(d))
end

function U.colorDelta(d)
  if d > 0.05 then return "|cff40ff40" .. U.delta(d) .. "|r" end
  if d < -0.05 then return "|cffff5050" .. U.delta(d) .. "|r" end
  return "|cffa0a0a0" .. "±0" .. "|r"
end

local QUALITY_HEX = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
function U.qualityHex(q) return QUALITY_HEX[q or 1] or "ffffff" end

U.SOURCE_HEX = { Quest = "e8c35a", Dungeon = "d9785a", Vendor = "7fc28a", Crafted = "6fb3d9" }

function U.secret(v)
  return issecretvalue ~= nil and issecretvalue(v) or false
end

-- a plain number, or nil (secret values, nil, NaN)
function U.num(v)
  if v == nil or U.secret(v) then return nil end
  v = tonumber(v)
  if not v or v ~= v then return nil end
  return v
end

-- --- game wrappers ---------------------------------------------------------------------------
local C_Item = C_Item

function U.ItemInfo(item)
  local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not f then return end
  local ok, name, link, quality, ilvl, minLevel, _, _, _, equipLoc, icon, sellPrice, classID, subclassID = pcall(f, item)
  if not ok or not name then return end
  return { name = name, link = link, q = quality, il = ilvl, rq = minLevel, equipLoc = equipLoc, icon = icon,
    price = sellPrice, classID = classID, subclassID = subclassID }
end

function U.ItemInfoInstant(item)
  local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if not f then return end
  local ok, id, _, _, equipLoc, icon, classID, subclassID = pcall(f, item)
  if not ok or not id then return end
  return { id = id, equipLoc = equipLoc, icon = icon, classID = classID, subclassID = subclassID }
end

function U.ItemStats(link)
  local f = (C_Item and C_Item.GetItemStats) or GetItemStats
  if not f then return end
  local ok, t = pcall(f, link)
  if ok and type(t) == "table" then return t end
end

function U.RequestItem(id)
  if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
end

function U.ItemIDFromLink(link)
  if type(link) ~= "string" or U.secret(link) then return end
  return tonumber(link:match("item:(%-?%d+)"))
end

-- random suffix of a link ("item:id:enchant:g1:g2:g3:g4:suffix:..."), 0 if none
function U.SuffixFromLink(link)
  if type(link) ~= "string" then return 0 end
  local body = link:match("item:([%-%d:]+)")
  if not body then return 0 end
  local f = U.split(body, ":")
  return tonumber(f[7] or "") or 0
end

function U.ItemLinkFor(id, name, q)
  local info = U.ItemInfo(id)
  if info and info.link then return info.link end
  return ("|cff%s|Hitem:%d::::::::::::|h[%s]|h|r"):format(U.qualityHex(q), id, name or ("item " .. id))
end

-- tooltip lines of an item link, as text pairs (for weapon damage / speed of items not in the data)
function U.TooltipLines(link)
  if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return end
  local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
  if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return end
  local out = {}
  for _, line in ipairs(data.lines) do
    local l, r = line.leftText, line.rightText
    if U.secret(l) then l = nil end
    if U.secret(r) then r = nil end
    out[#out + 1] = { l = l, r = r }
  end
  return out
end

function U.QuestDone(id)
  if not id then return false end
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
    if ok then return v and true or false end
  end
  if IsQuestFlaggedCompleted then
    local ok, v = pcall(IsQuestFlaggedCompleted, id)
    if ok then return v and true or false end
  end
  return false
end

function U.QuestTitle(id)
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
    if ok and t and t ~= "" and not U.secret(t) then return t end
    if C_QuestLog.RequestLoadQuestByID then pcall(C_QuestLog.RequestLoadQuestByID, id) end
  end
end

function U.InCombat()
  return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
end

-- the player's name without realm
function U.Me()
  local n = UnitName("player")
  return n
end

-- a character's first name for display ("Tato Mcpaw" -> "Tato"; WoW Forever names have a surname)
function U.FirstName(name)
  return name and (name:match("^(%S+)") or name) or name
end

-- is this sender name one of your own? (the game may name you "Koda" or "Koda Ashmane")
function U.IsMe(name)
  if not name then return false end
  local me = UnitName("player")
  if not me or U.secret(me) then return false end
  if name == me or (FS.db and FS.db.selfNames and FS.db.selfNames[name]) then return true end
  return name:sub(1, #me + 1) == me .. " " or me:sub(1, #name + 1) == name .. " "
end

function U.ShortName(name)
  if not name then return name end
  if Ambiguate then
    local ok, s = pcall(Ambiguate, name, "none")
    if ok and s then name = s end
  end
  return (name:match("^([^%-]+)")) or name
end

function U.InsertLink(link)
  if not link then return end
  if HandleModifiedItemClick then
    local ok, handled = pcall(HandleModifiedItemClick, link)
    if ok and handled then return true end
  end
  if ChatEdit_InsertLink then
    local ok, done = pcall(ChatEdit_InsertLink, link)
    if ok and done then return true end
  end
  if ChatFrameUtil and ChatFrameUtil.InsertLink then pcall(ChatFrameUtil.InsertLink, link) end
end

-- the player's crafting professions (English names as in the item data), from the skill line IDs
local SKILL_LINES = { [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
  [165] = "Leatherworking", [197] = "Tailoring" }
function U.Professions()
  if not GetProfessions or not GetProfessionInfo then return nil end
  local ok, a, b = pcall(GetProfessions)
  if not ok then return nil end
  local out = {}
  local list = { a, b }
  for i = 1, 2 do
    local idx = list[i]
    if idx then
      local ok2, _, _, _, _, _, _, skillLine = pcall(GetProfessionInfo, idx)
      if ok2 and SKILL_LINES[skillLine] then out[SKILL_LINES[skillLine]] = true end
    end
  end
  return out
end
