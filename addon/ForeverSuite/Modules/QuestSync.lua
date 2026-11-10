-- Quest sync: both addons swap the IDs of the quests they have turned in while you are grouped, so each of
-- you sees which quests the other one did alone and has to catch up on (and their rewards for you).
local _, FS = ...
local G, U, UI, Comm = FS.Gear, FS.U, FS.UI, FS.Comm

local Q = FS:NewModule("questsync", {
  title = "Quest sync",
  desc = "The Quests tab: which quests your partner has done that you have not, and the other way round. Swapped while you are grouped.",
  order = 40,
})

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function toB36(n)
  if n == 0 then return "0" end
  local s = ""
  while n > 0 do local r = n % 36; s = B36:sub(r + 1, r + 1) .. s; n = math.floor(n / 36) end
  return s
end

function Q.MyQuests()
  local ids = {}
  if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
    local ok, list = pcall(C_QuestLog.GetAllCompletedQuestIDs)
    if ok and type(list) == "table" then for _, id in ipairs(list) do ids[id] = true end end
  elseif GetQuestsCompleted then
    local ok, t = pcall(GetQuestsCompleted)
    if ok and type(t) == "table" then for id in pairs(t) do ids[id] = true end end
  end
  return ids
end

-- sorted IDs as base-36 gaps: "1a.3.f.."
function Q.Encode(ids)
  local list = {}
  for id in pairs(ids) do list[#list + 1] = id end
  table.sort(list)
  local out, prev = {}, 0
  for _, id in ipairs(list) do out[#out + 1] = toB36(id - prev); prev = id end
  return table.concat(out, ".")
end
function Q.Decode(s)
  local ids, prev = {}, 0
  for _, part in ipairs(U.split(s or "", ".")) do
    local d = tonumber(part, 36)
    if d then prev = prev + d; ids[prev] = true end
  end
  return ids
end

local lastSent = 0
function Q:SendList(force)
  if not Comm:GroupChannel() then return false end
  if not force and GetTime() - lastSent < 300 then return false end
  lastSent = GetTime()
  return Comm:Send("Q", Q.Encode(Q.MyQuests()))
end

function Q:OnList(_, name, payload)
  FS.db.questSync[name] = { at = time(), ids = Q.Decode(payload) }
  FS:Fire("QUESTS_SYNCED", name)
  FS:Fire("PARTNER_CHANGED", name)
end

function Q:OnAdd(_, name, payload)
  local rec = FS.db.questSync[name]
  if not rec then return end
  local id = tonumber(payload)
  if id then rec.ids[id] = true; rec.at = time(); FS:Fire("QUESTS_SYNCED", name) end
end

-- --- tab -----------------------------------------------------------------------------------------
local function questInfo(id)
  local items = G.questItems[id]
  local s
  if items then for _, x in ipairs(items[1].src) do if x.t == "Quest" and x.id == id then s = x end end end
  return items, s
end

local function bestReward(items)
  local st = G.State.self
  if not st or not items then return nil end
  local best
  for _, it in ipairs(items) do
    local v = G:Evaluate(st, it)
    if v and v.delta and (not best or v.delta > best.v.delta) then best = { it = it, v = v } end
  end
  return best
end

local function build(panel)
  local tab = {}
  local title = UI.Text(panel, "GameFontNormalLarge", "")
  title:SetPoint("TOPLEFT", 2, -2)
  local sub = UI.Text(panel, "GameFontHighlightSmall", "")
  sub:SetPoint("TOPLEFT", 2, -22)
  sub:SetPoint("RIGHT", -150, 0)
  sub:SetWordWrap(true)
  sub:SetTextColor(0.62, 0.6, 0.53)
  local send = UI.Flat(panel, "Swap quests now", 140, 22, function()
    if Q:SendList(true) then FS:Print("Sending your finished quests to the group.")
    else FS:Print("Join a group with your partner first.") end
  end)
  send:SetPoint("TOPRIGHT", 0, 0)
  local scroll = UI.Scroll(panel)
  scroll:SetPoint("TOPLEFT", 0, -46)
  scroll:SetPoint("BOTTOMRIGHT")
  local headers, rows, lines = UI.Pool(UI.Header), UI.Pool(UI.ItemRow), UI.Pool(UI.Line)

  local function listQuests(ids, y, header, mine)
    local list = {}
    for id in pairs(ids) do
      local items, s = questInfo(id)
      list[#list + 1] = { id = id, items = items, s = s, title = U.QuestTitle(id) or (s and s.n) }
    end
    table.sort(list, function(a, b)
      local la, lb = a.s and a.s.ql or 999, b.s and b.s.ql or 999
      if la ~= lb then return la < lb end
      return a.id < b.id
    end)
    local h = headers:Get(scroll.content)
    h:SetPoint("TOPLEFT", 0, -y)
    h:SetPoint("RIGHT", scroll.content, "RIGHT")
    h.text:SetText(header)
    h.right:SetText(#list .. " quest" .. (#list == 1 and "" or "s"))
    y = y + 26
    for _, q in ipairs(list) do
      local r = rows:Get(scroll.content)
      r:SetPoint("TOPLEFT", 0, -y)
      r:SetPoint("RIGHT", scroll.content, "RIGHT")
      local where = q.s and ((q.s.w and (q.s.w .. " · ") or "") .. "level " .. (q.s.ql or "?")) or ("quest " .. q.id)
      local best = not mine and bestReward(q.items)
      local right = best and best.v.kind == "up" and (U.colorDelta(best.v.delta)) or ""
      local rewardText = best and (" · reward " .. "|cff" .. U.qualityHex(best.it.q) .. best.it.n .. "|r") or ""
      r:SetPlain("|cffffd100" .. (q.title or ("Quest #" .. q.id)) .. "|r", "|cff9e9986" .. where .. "|r" .. rewardText, right)
      r.item = nil
      r.tip = best and ("Best reward for you: " .. best.it.n .. " (" .. U.delta(best.v.delta) .. ")") or nil
      y = y + 33
    end
    if #list == 0 then
      local l = lines:Get(scroll.content)
      l:SetPoint("TOPLEFT", 0, -y)
      l:SetPoint("RIGHT", scroll.content, "RIGHT")
      l.text:SetText("|cff888888None, you are on the same page.|r")
      y = y + 20
    end
    return y + 10
  end

  function tab:Refresh()
    headers:Reset(); rows:Reset(); lines:Reset()
    local names = {}
    for name in pairs(FS.db.questSync) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
      title:SetText("Quest sync")
      sub:SetText("Nothing from a partner yet. When you are grouped and both run Forever Suite, your finished quests are swapped automatically.")
      scroll:SetContentHeight(0)
      return
    end
    local name = self.partner and FS.db.questSync[self.partner] and self.partner or names[1]
    self.partner = name
    local rec = FS.db.questSync[name]
    local mine = Q.MyQuests()
    local theirsOnly, mineOnly = {}, {}
    for id in pairs(rec.ids) do if not mine[id] then theirsOnly[id] = true end end
    for id in pairs(mine) do if not rec.ids[id] then mineOnly[id] = true end end
    title:SetText("You and " .. name)
    sub:SetText("Their list is from " .. date("%d %b %H:%M", rec.at) .. (#names > 1 and (" · also synced: " .. table.concat(names, ", ")) or "")
      .. ". Quests only count once turned in.")
    local y = listQuests(theirsOnly, 0, name .. " did, you did not", false)
    y = listQuests(mineOnly, y, "You did, " .. name .. " did not", true)
    scroll:SetContentHeight(y)
  end
  return tab
end

function Q:OnInitialize()
  FS.Window:AddTab("quests", "Quests", 30, build, "questsync")
end

function Q:OnEnable()
  self:Listen("COMM_Q", "OnList")
  self:Listen("COMM_QA", "OnAdd")
  self:Listen("SYNC_REQUESTED", function() Q:SendList(true) end)
  self:Listen("QUESTS_SYNCED", function() FS.Window:RefreshSoon() end)
  self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
    FS:Debounce("questsync-roster", 6, function() if not U.InCombat() then Q:SendList(false) end end)
  end)
  self:RegisterEvent("QUEST_TURNED_IN", function(_, _, id)
    if id and Comm:GroupChannel() then Comm:Send("QA", tostring(id)) end
  end)
  self:RegisterEvent("QUEST_DATA_LOAD_RESULT", function()
    FS:Debounce("questsync-titles", 1, function() FS.Window:RefreshSoon() end)
  end)
  FS:Debounce("questsync-roster", 8, function() Q:SendList(false) end)
end
