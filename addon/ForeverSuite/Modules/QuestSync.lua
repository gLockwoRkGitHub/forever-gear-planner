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

-- quests in your quest log right now (IDs)
function Q.MyActive()
  local ids = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    for i = 1, (ok and n or 0) do
      local ok2, info = pcall(C_QuestLog.GetInfo, i)
      if ok2 and type(info) == "table" and not info.isHeader and info.questID and info.questID > 0 then ids[info.questID] = true end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    local ok, n = pcall(GetNumQuestLogEntries)
    for i = 1, (ok and n or 0) do
      local ok2, _, _, _, isHeader, _, _, _, questID = pcall(GetQuestLogTitle, i)
      if ok2 and not isHeader and questID and questID > 0 then ids[questID] = true end
    end
  end
  return ids
end

-- is this quest in your quest log?
function Q.OnQuest(id)
  if C_QuestLog and C_QuestLog.IsOnQuest then
    local ok, v = pcall(C_QuestLog.IsOnQuest, id)
    if ok then return v and true or false end
  end
  return Q.MyActive()[id] or false
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
  local ok = Comm:Send("Q", Q.Encode(Q.MyQuests()))
  Q:SendActive()
  return ok
end

-- the quest log, so the partner sees which dungeon quests you already carry
function Q:SendActive()
  if not Comm:GroupChannel() then return false end
  return Comm:Send("QL", Q.Encode(Q.MyActive()))
end

function Q:OnList(_, name, payload)
  local old = FS.db.questSync[name]
  FS.db.questSync[name] = { at = time(), ids = Q.Decode(payload), active = old and old.active or nil, activeAt = old and old.activeAt }
  FS:Fire("QUESTS_SYNCED", name)
  FS:Fire("PARTNER_CHANGED", name)
end

function Q:OnAdd(_, name, payload)
  local rec = FS.db.questSync[name]
  if not rec then return end
  local id = tonumber(payload)
  if id then
    rec.ids[id] = true; rec.at = time()
    if rec.active then rec.active[id] = nil end
    FS:Fire("QUESTS_SYNCED", name)
  end
end

function Q:OnActive(_, name, payload)
  local rec = FS.db.questSync[name]
  if not rec then rec = { at = time(), ids = {} }; FS.db.questSync[name] = rec end
  rec.active, rec.activeAt = Q.Decode(payload), time()
  FS:Fire("QUESTS_SYNCED", name)
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
  scroll:SetPoint("TOPLEFT", 0, -76)
  scroll:SetPoint("BOTTOMRIGHT")
  local headers, rows, lines = UI.Pool(UI.Header), UI.Pool(UI.ItemRow), UI.Pool(UI.Line)

  -- which list to show: what the partner did and you did not (catch up), or the other way round
  local view = "theirs"
  local theirsBtn = UI.Flat(panel, "", 230, 22, function() view = "theirs"; tab:Refresh(); scroll:ScrollToTop() end)
  theirsBtn:SetPoint("TOPLEFT", 0, -48)
  local mineBtn = UI.Flat(panel, "", 230, 22, function() view = "mine"; tab:Refresh(); scroll:ScrollToTop() end)
  mineBtn:SetPoint("LEFT", theirsBtn, "RIGHT", 6, 0)

  -- quest name, zone and levels: the quest table built into the addon, else the reward data, else the game
  local function questMeta(id)
    local D = FS.Data
    local q = D.quests and D.quests[id]
    local items, s = questInfo(id)
    return {
      id = id, items = items,
      zone = (q and D.questZones[q[2]]) or (s and (s.dq or s.w)) or "Unknown zone",
      level = (q and q[3]) or (s and s.ql) or 0,
      minLevel = (q and q[4]) or (s and s.ml) or 0,
      title = U.QuestTitle(id) or (q and q[1]) or (s and s.n) or ("Quest #" .. id),
    }
  end

  -- one list, grouped by zone; zones in leveling order (lowest quest level first)
  local function listQuests(ids, y, mine)
    local zones, order = {}, {}
    for id in pairs(ids) do
      local m = questMeta(id)
      local z = zones[m.zone]
      if not z then z = { name = m.zone, quests = {}, lo = 999, hi = 0 }; zones[m.zone] = z; order[#order + 1] = z end
      z.quests[#z.quests + 1] = m
      if m.level > 0 then z.lo, z.hi = math.min(z.lo, m.level), math.max(z.hi, m.level) end
    end
    local last = { ["Unknown zone"] = true, Other = true }
    table.sort(order, function(a, b)
      if (last[a.name] or false) ~= (last[b.name] or false) then return not last[a.name] end
      if a.lo ~= b.lo then return a.lo < b.lo end
      return a.name < b.name
    end)
    for _, z in ipairs(order) do
      table.sort(z.quests, function(a, b)
        if a.level ~= b.level then return a.level < b.level end
        return a.title < b.title
      end)
      local h = headers:Get(scroll.content)
      h:SetPoint("TOPLEFT", 0, -y)
      h:SetPoint("RIGHT", scroll.content, "RIGHT")
      h.text:SetText(z.name)
      local range = z.hi > 0 and (z.lo == z.hi and ("level " .. z.lo) or ("level " .. z.lo .. "-" .. z.hi)) or ""
      h.right:SetText(#z.quests .. " quest" .. (#z.quests == 1 and "" or "s") .. (range ~= "" and (" · " .. range) or ""))
      y = y + 26
      for _, q in ipairs(z.quests) do
        local r = rows:Get(scroll.content)
        r:SetPoint("TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", scroll.content, "RIGHT")
        local best = not mine and bestReward(q.items)
        local right = best and best.v.kind == "up" and U.colorDelta(best.v.delta) or ""
        local info = {}
        if q.level > 0 then info[#info + 1] = "level " .. q.level end
        if q.minLevel > 0 and q.minLevel ~= q.level then info[#info + 1] = "from " .. q.minLevel end
        if best then info[#info + 1] = "reward |cff" .. U.qualityHex(best.it.q) .. best.it.n .. "|r" end
        r:SetPlain("|cffffd100" .. q.title .. "|r", "|cff9e9986" .. table.concat(info, " · ") .. "|r", right)
        r.tip = best and ("Best reward for you: " .. best.it.n .. " (" .. U.delta(best.v.delta) .. ")") or nil
        y = y + 33
      end
      y = y + 6
    end
    if #order == 0 then
      local l = lines:Get(scroll.content)
      l:SetPoint("TOPLEFT", 0, -y)
      l:SetPoint("RIGHT", scroll.content, "RIGHT")
      l.text:SetText("|cff888888None, you are on the same page.|r")
      y = y + 20
    end
    return y
  end

  function tab:Refresh()
    headers:Reset(); rows:Reset(); lines:Reset()
    local names = {}
    for name in pairs(FS.db.questSync) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
      title:SetText("Quest sync")
      sub:SetText("Nothing from a partner yet. When you are grouped and both run Forever Suite, your finished quests are swapped automatically.")
      theirsBtn:Hide(); mineBtn:Hide()
      scroll:SetContentHeight(0)
      return
    end
    local name = self.partner and FS.db.questSync[self.partner] and self.partner or names[1]
    self.partner = name
    local rec = FS.db.questSync[name]
    local mine = Q.MyQuests()
    local theirsOnly, mineOnly = {}, {}
    local nt, nm = 0, 0
    for id in pairs(rec.ids) do if not mine[id] then theirsOnly[id] = true; nt = nt + 1 end end
    for id in pairs(mine) do if not rec.ids[id] then mineOnly[id] = true; nm = nm + 1 end end
    title:SetText("You and " .. U.FirstName(name))
    sub:SetText("Their list is from " .. date("%d %b %H:%M", rec.at) .. (#names > 1 and (" · also synced: " .. table.concat(names, ", ")) or "")
      .. ". Quests only count once turned in.")
    theirsBtn:Show(); mineBtn:Show()
    local short = U.FirstName(name)
    theirsBtn.label:SetText(short .. " did, you not (" .. nt .. ")")
    mineBtn.label:SetText("You did, " .. short .. " not (" .. nm .. ")")
    theirsBtn:SetActive(view == "theirs")
    mineBtn:SetActive(view == "mine")
    local y = listQuests(view == "theirs" and theirsOnly or mineOnly, 0, view == "mine")
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
  self:Listen("COMM_QL", "OnActive")
  local function logChanged()
    FS:Debounce("questsync-log", 4, function()
      if U.InCombat() then FS:Debounce("questsync-log-combat", 6, logChanged) else Q:SendActive() end
    end)
  end
  self:RegisterEvent("QUEST_ACCEPTED", logChanged)
  self:RegisterEvent("QUEST_REMOVED", logChanged)
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
