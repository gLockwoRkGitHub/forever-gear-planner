-- Partner sync: in a group, both addons send each other level, equipped gear, character sheet, talents and
-- planner settings. Your addon can then score every item for your partner too (tooltips, dungeon guide,
-- quest rewards). The last state of each partner is kept, so it is there when they are offline.
-- Loot hints: on a loot roll or in the loot window, a chat line says who gains how much.
local _, FS = ...
local G, U, Comm = FS.Gear, FS.U, FS.Comm
local S = G.State

local P = FS:NewModule("partner", {
  title = "Partner sync",
  desc = "In a group, swaps gear, level, talents and settings with your partner's Forever Suite, so you see their upgrade scores too.",
  order = 50,
})
local Loot = FS:NewModule("loothints", {
  title = "Loot hints",
  desc = "On a loot roll or in the loot window, a chat line says who gains how much from the item.",
  order = 55,
})

local VERSION = 1
local TYPES = { "Misc", "Cloth", "Leather", "Mail", "Plate", "Shield", "Idol", "Totem", "Two-Handed Axe", "Two-Handed Mace",
  "Staff", "Polearm", "Two-Handed Sword", "Libram", "Relic" }
local TYPE_INDEX = {}
for i, t in ipairs(TYPES) do TYPE_INDEX[t] = i end
local SLOT_INDEX = {}
for i, s in ipairs(G.SLOTS) do SLOT_INDEX[s] = i end

local function num(v) return math.floor(v) == v and tostring(v) or ("%.4g"):format(v) end

-- one equipped item: slotIndex!id[!k_v+k_v...]  (stats only where the data alone is not enough)
local function encodeItem(slot, it)
  local s = SLOT_INDEX[slot] .. "!" .. it.id
  local extra = {}
  if it.live or it.unknown then
    for k, v in pairs(it.st or {}) do if type(v) == "number" then extra[#extra + 1] = k .. "_" .. num(v) end end
  end
  if it.enchDmg then extra[#extra + 1] = "_enchDmg_" .. num(it.enchDmg) end
  if it.unknown then
    extra[#extra + 1] = "_ty_" .. (TYPE_INDEX[it.ty] or 1)
    for _, k in ipairs({ "dps", "speed", "dmgMin", "dmgMax" }) do
      if it[k] then extra[#extra + 1] = "_" .. k .. "_" .. num(it[k]) end
    end
  end
  table.sort(extra)
  if #extra > 0 then s = s .. "!" .. table.concat(extra, "+") end
  return s
end

local function decodeItem(s)
  local f = U.split(s, "!")
  local slot, id = G.SLOTS[tonumber(f[1] or "")], tonumber(f[2] or "")
  if not slot or not id then return nil end
  local g = { slot = slot, id = id }
  if f[3] then
    for _, pair in ipairs(U.split(f[3], "+")) do
      local k, v = pair:match("^(.+)_([%-%d%.e]+)$")
      v = tonumber(v)
      if k and v then
        if k == "_ty" then g.ty = TYPES[v]
        elseif k:sub(1, 1) == "_" then g[k:sub(2)] = v
        else g.st = g.st or {}; g.st[k] = v end
      end
    end
  end
  return g
end

function P.Encode(st)
  local set = st.settings
  local gear = {}
  for _, e in ipairs(st.items or {}) do gear[#gear + 1] = encodeItem(e.slot, e.it) end
  return Comm.encode({
    v = VERSION, k = st.key, lv = st.liveLevel,
    p = set.preset, w = Comm.encodeMap(set.weights),
    src = table.concat(S.SetToList(set.sources, G.SOURCES), ","),
    pf = table.concat(S.SetToList(set.profs, G.PROFESSIONS), ","),
    rnd = set.random and 1 or 0,
    t = Comm.encodeMap(st.tal), ts = st.talSrc, sh = st.sheet and Comm.encodeMap(st.sheet) or nil,
    g = table.concat(gear, "/"),
  })
end

function P.Decode(payload)
  local t = Comm.decode(payload)
  if tonumber(t.v) ~= VERSION or not G.PROFILES[t.k or ""] then return nil end
  local list = function(s) local o = {}; for _, x in ipairs(U.split(s or "", ",")) do if x ~= "" then o[#o + 1] = x end end; return o end
  local gear = {}
  for _, s in ipairs(U.split(t.g or "", "/")) do local g = decodeItem(s); if g then gear[#gear + 1] = g end end
  return {
    key = t.k, level = tonumber(t.lv) or 1,
    settings = { preset = t.p, weights = Comm.decodeMap(t.w), sources = list(t.src), profs = list(t.pf), random = t.rnd == "1" },
    tal = Comm.decodeMap(t.t), talSrc = t.ts, sheet = t.sh and Comm.decodeMap(t.sh) or nil, gear = gear,
  }
end

-- rebuild a partner's state (also after quests were swapped, so their done quests are known)
function P:Apply(name)
  local rec = FS.db.partners[name]
  local data = rec and P.Decode(rec.payload)
  if not data then return end
  data.at = rec.at
  local q = FS.db.questSync[name]
  data.done = q and q.ids or nil
  S:SetPartner(name, data)
  FS:Fire("PARTNER_CHANGED", name)
end

local lastPayload, lastSentAt = nil, 0
function P:SendState(force)
  local st = S.self
  if not st or not Comm:GroupChannel() then return false end
  if U.InCombat() then
    FS:Debounce("partner-send-combat", 5, function() P:SendState(force) end)
    return false
  end
  local payload = P.Encode(st)
  if not force and payload == lastPayload and GetTime() - lastSentAt < 600 then return false end
  lastPayload, lastSentAt = payload, GetTime()
  return Comm:Send("S", payload)
end

function P:OnState(_, name, payload)
  if not P.Decode(payload) then return end
  local known = FS.db.partners[name] ~= nil
  FS.db.partners[name] = { payload = payload, at = time() }
  self:Apply(name)
  if not known then
    FS:Print(("Partner %s synced. Tooltips and the Dungeons tab now show their upgrades too."):format(name))
    FS:Debounce("partner-reply", 2, function() P:SendState(true) end)
  end
end

function P:Forget()
  wipe(FS.db.partners)
  wipe(S.partners)
  FS:Fire("PARTNER_CHANGED")
end

function P:OnEnable()
  for name in pairs(FS.db.partners) do self:Apply(name) end
  self:Listen("COMM_S", "OnState")
  self:Listen("COMM_H", function() FS:Debounce("partner-hello", 2, function() P:SendState(true) end) end)
  self:Listen("QUESTS_SYNCED", function(_, _, name) if FS.db.partners[name] then P:Apply(name) end end)
  self:Listen("SYNC_REQUESTED", function()
    if P:SendState(true) then Comm:Send("H", "1"); FS:Print("Sending your gear to the group.")
    else FS:Print("Join a group with your partner first.") end
  end)
  self:Listen("STATE_CHANGED", function(_, _, what)
    if what == "preview" or what == "bags" then return end
    FS:Debounce("partner-send", 5, function() P:SendState(false) end)
  end)
  self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    FS:Debounce("partner-roster", 4, function()
      if Comm:GroupChannel() and P:SendState(false) then Comm:Send("H", "1") end
    end)
  end)
  FS:Debounce("partner-roster", 6, function()
    if Comm:GroupChannel() and P:SendState(true) then Comm:Send("H", "1") end
  end)
end

function P:OnDisable()
  wipe(S.partners)
  FS:Fire("PARTNER_CHANGED")
end

-- --- loot hints --------------------------------------------------------------------------------
local function hint(prefix, link)
  local it = G:ItemFromLink(link)
  if not it then return end
  local parts, any, bestName, bestGain = {}, false, nil, 0.05
  for _, st in ipairs(S:All()) do
    local v = G:Evaluate(st, it)
    if v and (v.kind == "up" or v.kind == "down") then
      parts[#parts + 1] = "|cff" .. st.prof.color .. (st.isSelf and "You" or st.name) .. "|r " .. U.colorDelta(v.delta)
      if v.kind == "up" then
        any = true
        if v.delta > bestGain then bestGain, bestName = v.delta, st.isSelf and "you" or st.name end
      end
    end
  end
  if any then
    FS:Print(prefix .. " " .. link .. "  " .. table.concat(parts, " · ") .. (bestName and #parts > 1 and ("  → " .. bestName) or ""))
  end
end

function Loot:OnEnable()
  self:RegisterEvent("START_LOOT_ROLL", function(_, _, rollID)
    local ok, link = pcall(GetLootRollItemLink, rollID)
    if ok and link and not U.secret(link) then hint("Roll", link) end
  end)
  self:RegisterEvent("LOOT_OPENED", function()
    if not GetNumLootItems then return end
    for i = 1, GetNumLootItems() do
      local ok, link = pcall(GetLootSlotLink, i)
      if ok and link and not U.secret(link) then hint("Loot", link) end
    end
  end)
end
