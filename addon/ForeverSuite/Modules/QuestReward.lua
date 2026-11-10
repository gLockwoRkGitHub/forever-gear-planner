-- Best quest reward: when a quest lets you choose a reward, the best one for you gets a gold star and a
-- line in chat (with your partner's pick, if their addon has sent their gear). If no reward is an upgrade,
-- the one that sells for the most gets a coin.
local _, FS = ...
local G, U = FS.Gear, FS.U
local S = G.State

local QR = FS:NewModule("questreward", {
  title = "Best quest reward",
  desc = "Marks the best quest reward for you with a star, or the most valuable one to sell.",
  order = 35,
})

local marks = {}

local function rewardButton(i)
  local frame = QuestInfoFrame and QuestInfoFrame.rewardsFrame or QuestInfoRewardsFrame
  if QuestInfo_GetRewardButton and frame then
    local ok, b = pcall(QuestInfo_GetRewardButton, frame, i)
    if ok and b then return b end
  end
  if frame and frame.RewardButtons then return frame.RewardButtons[i] end
  return _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
end

local function mark(i, texture)
  local b = rewardButton(i)
  if not b then return end
  local m = marks[b]
  if not m then
    m = b:CreateTexture(nil, "OVERLAY", nil, 7)
    m:SetSize(22, 22)
    m:SetPoint("TOPLEFT", b, "TOPLEFT", -6, 6)
    marks[b] = m
  end
  m:SetTexture(texture)
  m:Show()
end

local function clearMarks() for _, m in pairs(marks) do m:Hide() end end

local function choices()
  local n = GetNumQuestChoices and GetNumQuestChoices() or 0
  local out = {}
  for i = 1, n do
    local ok, link = pcall(GetQuestItemLink, "choice", i)
    if ok and link and not U.secret(link) then
      local it = G:ItemFromLink(link)
      local info = U.ItemInfo(link)
      out[#out + 1] = { i = i, link = link, it = it, price = info and info.price or 0 }
    end
  end
  return out, n
end

function QR:Evaluate(announce)
  clearMarks()
  local list, n = choices()
  if n < 2 then return end
  local me = S.self
  local best
  if me then
    for _, c in ipairs(list) do
      local v = c.it and G:Evaluate(me, c.it)
      if v and v.kind == "up" and (not best or v.delta > best.v.delta) then best = { c = c, v = v } end
    end
  end
  if best then
    mark(best.c.i, "Interface\\COMMON\\ReputationStar")
  else
    local rich
    for _, c in ipairs(list) do if (c.price or 0) > 0 and (not rich or c.price > rich.price) then rich = c end end
    if rich then mark(rich.i, "Interface\\MONEYFRAME\\UI-GoldIcon") end
  end
  if not announce then return end
  local lines = {}
  if best then lines[#lines + 1] = "You: " .. best.c.link .. " " .. U.colorDelta(best.v.delta) end
  for _, p in ipairs(S:Partners()) do
    local pb
    for _, c in ipairs(list) do
      local v = c.it and G:Evaluate(p, c.it)
      if v and v.kind == "up" and (not pb or v.delta > pb.v.delta) then pb = { c = c, v = v } end
    end
    if pb then lines[#lines + 1] = "|cff" .. p.prof.color .. p.name .. "|r: " .. pb.c.link .. " " .. U.colorDelta(pb.v.delta) end
  end
  if #lines == 0 then
    if me then FS:Print("No reward is an upgrade. The gold coin marks the one that sells for the most.") end
  else
    FS:Print("Best reward  " .. table.concat(lines, "   "))
  end
end

function QR:OnEnable()
  local function later(announce)
    C_Timer.After(0.15, function() if QR.enabled then FS.safecall(QR.Evaluate, QR, announce) end end)
  end
  self:RegisterEvent("QUEST_COMPLETE", function() later(true) end)
  self:RegisterEvent("QUEST_DETAIL", function() later(false) end)
  self:RegisterEvent("QUEST_FINISHED", clearMarks)
end

function QR:OnDisable() clearMarks() end
