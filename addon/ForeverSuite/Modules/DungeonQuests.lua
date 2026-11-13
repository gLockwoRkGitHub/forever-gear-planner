-- Dungeon preparation: the quest lines of a dungeon with every pre-quest that has to be done first, where each
-- step starts and ends, what to do inside and what it gives, with the status for you and your partner.
-- Shown as the "Quests" view of the Dungeons tab: one collapsible card per quest line.
local _, FS = ...
local G, U, UI = FS.Gear, FS.U, FS.UI
local S = G.State

local DQ = FS:NewModule("dungeonprep", {
  title = "Dungeon quests",
  desc = "Dungeons tab, view Quests: each dungeon's quest lines with all pre-quests, quest givers and map pins, for you and your partner.",
  order = 21,
})
FS.DQ = DQ

local ICON = {
  done = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t",
  log = "|TInterface\\GossipFrame\\ActiveQuestIcon:13:13|t",
  ready = "|TInterface\\GossipFrame\\AvailableQuestIcon:13:13|t",
  level = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:13:13|t",
  wait = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:13:13|t",
  na = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:13:13|t",
}

local function quests() return FS.Data.dq or {} end
local function hasBit(v, b) return v and b and math.floor(v / b) % 2 == 1 end

-- --- what a character has done / carries ----------------------------------------------------------
-- returns done(id), inLog(id), known (false: no quest data from that partner yet)
local function questState(st)
  if st.isSelf then
    local onQuest = FS.modules.questsync and FS.modules.questsync.OnQuest
    return U.QuestDone, function(id) return onQuest and onQuest(id) or false end, true
  end
  local rec = FS.db.questSync[st.name]
  if not rec then return function() return false end, function() return false end, false end
  return function(id) return rec.ids[id] == true end, function(id) return rec.active and rec.active[id] == true or false end, true
end

-- The steps of a quest line in the order they are done (pre-quests first). Of "one of these" pre-quests
-- the one somebody already did is taken, else the first.
function DQ.Steps(endId, states)
  local Q, out, seen = quests(), {}, {}
  local doneBy = {}
  for i, st in ipairs(states or {}) do doneBy[i] = (questState(st)) end
  local function anyDone(id)
    for _, f in ipairs(doneBy) do if f(id) then return true end end
    return false
  end
  local function visit(id, depth)
    if seen[id] or depth > 40 then return end
    seen[id] = true
    local q = Q[id]
    if not q then return end
    for _, p in ipairs(q.pg or {}) do visit(p, depth + 1) end
    if q.ps and #q.ps > 0 then
      local pick = q.ps[1]
      for _, p in ipairs(q.ps) do if anyDone(p) then pick = p; break end end
      visit(pick, depth + 1)
    end
    out[#out + 1] = id
  end
  visit(endId, 0)
  return out
end

-- Status of one step for one character:
-- done, log, ready (can be picked up now), level (too low: .min), wait (an earlier step first), na, unknown
function DQ.StepStatus(st, id, done, inLog, known)
  local q = quests()[id]
  if not q then return { kind = "na" } end
  if q.rc and q.rc ~= 0 and not hasBit(q.rc, st.prof.bit) then return { kind = "na" } end
  if not known then return { kind = "unknown" } end
  if done(id) then return { kind = "done" } end
  for _, x in ipairs(q.x or {}) do if done(x) then return { kind = "na", why = "excl" } end end
  if inLog(id) then return { kind = "log" } end
  for _, p in ipairs(q.pg or {}) do if not done(p) then return { kind = "wait" } end end
  if q.ps and #q.ps > 0 then
    local any = false
    for _, p in ipairs(q.ps) do if done(p) then any = true end end
    if not any then return { kind = "wait" } end
  end
  if (st.liveLevel or st.level or 1) < (q.min or 0) then return { kind = "level", min = q.min } end
  return { kind = "ready" }
end

-- Status of a whole line for one character: the first step that is not done decides.
-- { kind, step = index of that step, total, min }
function DQ.LineStatus(st, steps)
  local done, inLog, known = questState(st)
  local total = #steps
  local endId = steps[total]
  local last = DQ.StepStatus(st, endId, done, inLog, known)
  if last.kind == "na" or last.kind == "unknown" or last.kind == "done" then
    return { kind = last.kind, step = total, total = total }
  end
  for i, id in ipairs(steps) do
    local s = DQ.StepStatus(st, id, done, inLog, known)
    if s.kind ~= "done" and s.kind ~= "na" then
      s.step, s.total = i, total
      if s.kind == "wait" then s.kind = "ready" end   -- a skipped option of "one of": the next one counts
      return s
    end
  end
  return { kind = "done", step = total, total = total }
end

-- lines of a dungeon still to pick up for a character (ready or level-gated, not in the log)
function DQ.Open(dungeon, st, states)
  local out = {}
  for _, endId in ipairs((FS.Data.dqLines or {})[dungeon] or {}) do
    local steps = DQ.Steps(endId, states)
    local s = DQ.LineStatus(st, steps)
    if s.kind == "ready" then out[#out + 1] = { id = endId, steps = steps, status = s } end
  end
  return out
end

local function whoName(st) return "|cff" .. st.prof.color .. (st.isSelf and "You" or st.short or st.name) .. "|r" end

function DQ.StatusText(s, short)
  local k = s.kind
  if k == "done" then return ICON.done .. " |cff40ff40done|r" end
  if k == "log" then
    return ICON.log .. " |cffffd100" .. ((s.total or 1) > 1 and s.step < s.total and ("step " .. s.step .. "/" .. s.total .. " in log") or "in log") .. "|r"
  end
  if k == "ready" then
    local txt
    if (s.total or 1) <= 1 or s.step == s.total and s.step == 1 then txt = "pick up"
    elseif s.step == 1 then txt = short and ("start (" .. s.total .. " steps)") or ("start the line (" .. s.total .. " steps)")
    else txt = "step " .. s.step .. "/" .. s.total end
    return ICON.ready .. " |cffffffff" .. txt .. "|r"
  end
  if k == "level" then
    return ICON.level .. " |cffff9933" .. ((s.total or 1) > 1 and ("step " .. s.step .. ": ") or "") .. "from level " .. s.min .. "|r"
  end
  if k == "wait" then return ICON.wait .. " |cff999999after the step before|r" end
  if k == "unknown" then return "|cff888888? no quest data yet|r" end
  return ICON.na .. " |cff777777" .. (s.why == "excl" and "other choice done" or "not for this class") .. "|r"
end

-- where a quest starts / ends, as text
local function placeText(p, dungeon)
  if not p then return "|cff888888unknown|r" end
  local who = p.n or "?"
  if p.t == "item" then return "item |cffffffff" .. who .. "|r" .. (dungeon and " (drops in the dungeon)" or "") end
  if p["in"] then return "|cffffffff" .. who .. "|r · inside " .. p["in"] end
  local where = p.z or "?"
  if p.x then where = where .. (" (%.0f, %.0f)"):format(p.x, p.y) end
  return "|cffffffff" .. who .. "|r · " .. where
end
DQ.PlaceText = placeText

-- a map pin to a quest giver (game waypoint, and TomTom if installed)
function DQ.Waypoint(p)
  if not p or not p.m or not p.x then return false end
  local done = false
  if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
    local ok = pcall(function()
      C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(p.m, p.x / 100, p.y / 100))
      if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    end)
    done = ok
  end
  if TomTom and TomTom.AddWaypoint then
    done = pcall(TomTom.AddWaypoint, TomTom, p.m, p.x / 100, p.y / 100, { title = p.n }) or done
  end
  FS:Print(done and ("Map pin: %s, %s (%.1f, %.1f)"):format(p.n or "?", p.z or "?", p.x, p.y) or "This client has no map pins.")
  return done
end

-- --- view ------------------------------------------------------------------------------------------
local CARD_H, STEP_H, INDENT, STATUS_W = 46, 34, 30, 200

local function makeCard(parent)
  local c = CreateFrame("Button", nil, parent, "BackdropTemplate")
  c:SetHeight(CARD_H)
  c:SetBackdrop(UI.BACKDROP)
  c:SetBackdropColor(0.11, 0.12, 0.145, 1)
  c:SetBackdropBorderColor(0.185, 0.204, 0.24, 1)
  local hl = c:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 1, -1)
  hl:SetPoint("BOTTOMRIGHT", -1, 1)
  hl:SetColorTexture(1, 1, 1, 0.04)
  local ex = c:CreateTexture(nil, "ARTWORK")
  ex:SetSize(14, 14)
  ex:SetPoint("TOPLEFT", 8, -8)
  c.expand = ex
  local status = UI.Text(c, "GameFontHighlightSmall", "", "RIGHT")
  status:SetPoint("TOPRIGHT", -8, -7)
  status:SetWidth(STATUS_W)
  status:SetJustifyV("TOP")
  if status.SetWordWrap then status:SetWordWrap(true) end
  status:SetSpacing(3)
  c.status = status
  local title = UI.Text(c, "GameFontNormal", "")
  title:SetPoint("TOPLEFT", 28, -7)
  title:SetPoint("RIGHT", status, "LEFT", -8, 0)
  c.title = title
  local sub = UI.Text(c, "GameFontHighlightSmall", "")
  sub:SetPoint("TOPLEFT", 28, -25)
  sub:SetPoint("RIGHT", status, "LEFT", -8, 0)
  sub:SetTextColor(0.62, 0.6, 0.53)
  c.sub = sub
  return c
end

local function makeStep(parent)
  local r = CreateFrame("Button", nil, parent)
  r:SetHeight(STEP_H)
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 1, 1, 0.04)
  -- timeline: a line through all badges, a badge with the step number
  local line = r:CreateTexture(nil, "BACKGROUND")
  line:SetColorTexture(0.85, 0.64, 0.25, 0.35)
  line:SetWidth(2)
  line:SetPoint("TOP", r, "TOPLEFT", INDENT + 9, 0)
  line:SetPoint("BOTTOM", r, "BOTTOMLEFT", INDENT + 9, 0)
  r.line = line
  local badge = CreateFrame("Frame", nil, r, "BackdropTemplate")
  badge:SetSize(18, 18)
  badge:SetPoint("LEFT", INDENT, 0)
  badge:SetBackdrop(UI.BACKDROP)
  badge:SetBackdropColor(0.078, 0.086, 0.10, 1)
  badge:SetBackdropBorderColor(0.85, 0.64, 0.25, 0.8)
  local num = UI.Text(badge, "GameFontNormalSmall", "", "CENTER")
  num:SetAllPoints()
  r.badge, r.num = badge, num
  local status = UI.Text(r, "GameFontHighlightSmall", "", "RIGHT")
  status:SetPoint("RIGHT", -8, 0)
  status:SetWidth(STATUS_W)
  if status.SetWordWrap then status:SetWordWrap(true) end
  status:SetSpacing(2)
  r.status = status
  local name = UI.Text(r, "GameFontHighlight", "")
  name:SetPoint("TOPLEFT", INDENT + 28, -3)
  name:SetPoint("RIGHT", status, "LEFT", -8, 0)
  r.name = name
  local sub = UI.Text(r, "GameFontHighlightSmall", "")
  sub:SetPoint("TOPLEFT", INDENT + 28, -18)
  sub:SetPoint("RIGHT", status, "LEFT", -8, 0)
  sub:SetTextColor(0.62, 0.6, 0.53)
  r.sub = sub
  r:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.questName or "", 1, 0.82, 0)
    if self.start then GameTooltip:AddLine("Start: " .. placeText(self.start), 0.9, 0.9, 0.9, true) end
    if self.finish then GameTooltip:AddLine("Turn in: " .. placeText(self.finish), 0.9, 0.9, 0.9, true) end
    for _, o in ipairs(self.objectives or {}) do GameTooltip:AddLine(o, 0.75, 0.75, 0.7, true) end
    if self.start and self.start.m then GameTooltip:AddLine("Click: map pin to the quest giver", 0.4, 0.8, 1) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self) if self.start then DQ.Waypoint(self.start) end end)
  return r
end

local function makeText(parent)
  local f = CreateFrame("Frame", nil, parent)
  local t = UI.Text(f, "GameFontHighlightSmall", "")
  t:SetPoint("TOPLEFT", 0, 0)               -- width is set on every use (wrapped text needs a fixed width)
  if t.SetWordWrap then t:SetWordWrap(true) end
  t:SetJustifyV("TOP")
  t:SetSpacing(2)
  f.text = t
  -- a map pin button, used by single-step lines
  local pin = UI.Flat(f, "Map pin", 70, 18)
  pin:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, 0)
  pin:Hide()
  f.pin = pin
  return f
end

-- the view: created once by the Dungeons tab, filled by :Render(dungeon)
function DQ:CreateView(parent)
  local v = { expanded = {}, onlyOpen = FS.cdb.dungeon.onlyOpenQuests ~= false }
  local scroll = UI.Scroll(parent)
  scroll:SetPoint("TOPLEFT", 0, -54)
  scroll:SetPoint("BOTTOMRIGHT")
  v.scroll = scroll
  local content = scroll.content
  local cards, steps, texts = UI.Pool(makeCard), UI.Pool(makeStep), UI.Pool(makeText)
  local items, heads, lines = UI.Pool(UI.ItemRow), UI.Pool(UI.Header), UI.Pool(UI.Line)

  local function place(w, y, indent)
    w:SetPoint("TOPLEFT", indent or 0, -y)
    w:SetPoint("RIGHT", content, "RIGHT", 0, 0)
  end

  function v:SetShown(on) scroll:SetShown(on) end
  function v:ToggleAll()
    local anyClosed = false
    for _, l in ipairs(self.lines or {}) do if not self.expanded[l.id] then anyClosed = true end end
    for _, l in ipairs(self.lines or {}) do self.expanded[l.id] = anyClosed end
    self:Render(self.dungeon)
  end

  function v:Render(dungeon)
    cards:Reset(); steps:Reset(); texts:Reset(); items:Reset(); heads:Reset(); lines:Reset()
    for _, t in ipairs(texts.items) do t.pin:Hide() end
    self.dungeon = dungeon
    local states = S:All()
    local Q = quests()
    local y = 0
    local list = {}
    for _, endId in ipairs((FS.Data.dqLines or {})[dungeon or ""] or {}) do
      local st = DQ.Steps(endId, states)
      local per, relevant, open = {}, false, false
      for i, s in ipairs(states) do
        per[i] = DQ.LineStatus(s, st)
        if per[i].kind ~= "na" then relevant = true end
        if per[i].kind ~= "na" and per[i].kind ~= "done" then open = true end
      end
      if #states == 0 then relevant, open = true, true end
      if relevant and (open or not self.onlyOpen) then list[#list + 1] = { id = endId, steps = st, per = per } end
    end
    self.lines = list

    -- summary
    local width = content:GetWidth()
    local sum = texts:Get(content)
    place(sum, y, 2)
    sum.text:SetWidth(math.max(100, width - 8))
    local total = #((FS.Data.dqLines or {})[dungeon or ""] or {})
    local parts = {}
    for i, s in ipairs(states) do
      local pick, logged = 0, 0
      for _, l in ipairs(list) do
        if l.per[i].kind == "ready" then pick = pick + 1 elseif l.per[i].kind == "log" then logged = logged + 1 end
      end
      parts[#parts + 1] = whoName(s) .. ": " .. pick .. " to pick up, " .. logged .. " in log"
    end
    sum.text:SetText((total == 0 and "No quests known for this dungeon." or
      (#list .. " of " .. total .. " quest lines" .. (self.onlyOpen and " still open" or "") .. "   ") .. table.concat(parts, "   ")))
    sum:SetHeight(18)
    y = y + 24

    for _, l in ipairs(list) do
      local q = Q[l.id] or {}
      local first = Q[l.steps[1]] or {}
      local open = self.expanded[l.id]
      local card = cards:Get(content)
      place(card, y)
      card.expand:SetTexture(open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
      local n = #l.steps
      card.title:SetText("|cffffd100" .. (q.n or "?") .. "|r |cff888888[" .. (q.lv or "?") .. "]" ..
        (n > 1 and (" · " .. n .. " steps") or "") .. "|r")
      local startTxt = first.s and first.s["in"] and ("Starts inside: " .. placeText(first.s)) or ("Start: " .. placeText(first.s, true))
      card.sub:SetText(startTxt)
      local st = {}
      for i, s in ipairs(states) do
        local best
        for _, id in ipairs(l.steps) do
          for _, it in ipairs(G.questItems[id] or {}) do
            local e = G:Evaluate(s, it)
            if e and e.kind == "up" and (not best or e.delta > best) then best = e.delta end
          end
        end
        st[#st + 1] = whoName(s) .. " " .. DQ.StatusText(l.per[i], true) .. (best and ("  " .. U.colorDelta(best)) or "")
      end
      card.status:SetText(table.concat(st, "\n"))
      local h = math.max(CARD_H, (#states > 1 and 40 or 26) + 8)
      card:SetHeight(h)
      local id = l.id
      card:SetScript("OnClick", function() v.expanded[id] = not v.expanded[id]; v:Render(v.dungeon) end)
      y = y + h + 2

      if open then
        y = y + 4
        -- the steps, as a timeline
        if n > 1 then
          for i, sid in ipairs(l.steps) do
            local sq = Q[sid] or {}
            local r = steps:Get(content)
            place(r, y)
            r.num:SetText(tostring(i))
            r.line:ClearAllPoints()
            r.line:SetPoint("TOP", r, "TOPLEFT", INDENT + 9, i == 1 and -STEP_H / 2 or 0)
            r.line:SetPoint("BOTTOM", r, "BOTTOMLEFT", INDENT + 9, i == n and STEP_H / 2 or 0)
            r.name:SetText((sid == l.id and "|cffffd100" or "|cffffffff") .. (sq.n or "?") .. "|r |cff888888[" .. (sq.lv or "?") .. "]|r"
              .. (sq.d and sq.d == dungeon and " |cffd9785a· in this dungeon|r" or ""))
            local where = "Start: " .. placeText(sq.s, true)
            if sq.e then where = where .. "   Turn in: " .. placeText(sq.e) end
            r.sub:SetText(where)
            local chips = {}
            for _, s in ipairs(states) do
              local done, inLog, known = questState(s)
              chips[#chips + 1] = whoName(s) .. " " .. DQ.StatusText(DQ.StepStatus(s, sid, done, inLog, known), true)
            end
            r.status:SetText(table.concat(chips, "\n"))
            r.questName, r.start, r.finish, r.objectives = sq.n, sq.s, sq.e, sq.o
            y = y + STEP_H
          end
          y = y + 4
        else
          local r = texts:Get(content)
          place(r, y, INDENT)
          r.text:SetWidth(math.max(100, width - INDENT - 90))
          r.text:SetText("|cff888888Start:|r " .. placeText(q.s, true) .. (q.e and ("   |cff888888Turn in:|r " .. placeText(q.e)) or ""))
          r:SetHeight(18)
          y = y + 20
          if q.s and q.s.m then
            local giver = q.s
            r.pin:SetScript("OnClick", function() DQ.Waypoint(giver) end)
            r.pin.tip = "Map pin to " .. (giver.n or "the quest giver")
            r.pin:Show()
          end
        end
        -- what to do (the dungeon step's objectives)
        local task = q.o or {}
        if #task > 0 then
          local t = texts:Get(content)
          place(t, y, INDENT)
          t.text:SetWidth(math.max(100, width - INDENT - 12))
          t.text:SetText("|cff888888Task:|r " .. table.concat(task, " "))
          local th = math.max(16, (t.text:GetStringHeight() or 14) + 4)
          t:SetHeight(th)
          y = y + th + 4
        end
        -- rewards of all steps, scored for each of you
        local seen = {}
        for _, sid in ipairs(l.steps) do
          for _, it in ipairs(G.questItems[sid] or {}) do
            if not seen[it.id] then
              seen[it.id] = true
              local row = items:Get(content)
              place(row, y, INDENT)
              local scores = {}
              for _, s in ipairs(states) do
                local e = G:Evaluate(s, it)
                if e and e.delta and (e.kind == "up" or e.kind == "down") then scores[#scores + 1] = whoName(s) .. " " .. U.colorDelta(e.delta)
                elseif e and e.kind == "later" then scores[#scores + 1] = whoName(s) .. " |cffffcc00lvl " .. e.from .. "|r" end
              end
              row:SetItem(it, table.concat(scores, "  "), (sid ~= l.id and ("from " .. (Q[sid] and Q[sid].n or "?")) or "reward") .. " · " .. G.StatLine(it))
              y = y + 33
            end
          end
        end
        y = y + 10
      end
    end
    if #list == 0 and total > 0 then
      local t = lines:Get(content)
      place(t, y)
      t.text:SetText("|cff888888All quest lines here are done. Untick 'Only open' to see them.|r")
      y = y + 20
    end
    scroll:SetContentHeight(y + 8)
  end
  return v
end

-- --- entering a dungeon: which quests did you not pick up? ---------------------------------------------
function DQ:EnterMessage(dungeon)
  if not self.enabled then return end
  local states = S:All()
  for _, st in ipairs(states) do
    local open = DQ.Open(dungeon, st, states)
    if #open > 0 then
      local names = {}
      for i = 1, math.min(4, #open) do
        local q = quests()[open[i].id]
        local first = quests()[open[i].steps[open[i].status.step]] or q
        local inside = first and first.s and first.s["in"]
        names[#names + 1] = (q and q.n or "?") .. (inside and " |cff40ff40(starts inside)|r" or "")
      end
      print("   " .. whoName(st) .. " |cffffd100quests not picked up:|r " .. table.concat(names, ", ") .. (#open > 4 and (" +" .. (#open - 4)) or ""))
    end
  end
end
