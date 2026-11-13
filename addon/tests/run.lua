-- Loads the built addon into a mocked game client and checks it:
--   1. parity: same stat weights and the same top-5 per slot as the website (expected.lua from parity.js)
--   2. every module runs: window tabs, tooltip, quest reward, partner and quest sync, dungeon guide, loot hint
-- Usage (repo root): python scripts/build_addon.py && node addon/tests/parity.js && lua5.1 addon/tests/run.lua
local DIR = arg[1] or "build/addon/ForeverSuite"
local expected = dofile("addon/tests/expected.lua")
local function say(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end io.write(table.concat(t, " "), "\n") end
local fails, checks = 0, 0
local function check(cond, msg)
  checks = checks + 1
  if not cond then fails = fails + 1; say("FAIL: " .. msg) end
end
local function near(a, b) return math.abs((a or 0) - (b or 0)) <= 1e-6 * math.max(1, math.abs(b or 0)) end
local function find(list, pat) for _, s in ipairs(list) do if tostring(s):find(pat) then return s end end return nil end

local function importText(sc, name)
  local function map(t)
    local keys = {}
    for k, v in pairs(t) do if type(v) == "number" then keys[#keys + 1] = k end end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. ":" .. t[k] end
    return table.concat(out, ",")
  end
  return ("FS1~2026-11-10 12:00~k=%s;n=%s;p=%s;src=Quest,Dungeon,Vendor,Crafted;pf=%s;rnd=0;up=1;lv=%d;t=%s;sh=%s;sl=%d%s")
    :format(sc.key, name, sc.preset, sc.key == "shaman" and "Enchanting" or "", sc.level, map(sc.tal), map(sc.sheet), sc.level,
      sc.we and (";we=" .. sc.we) or "")
end

local function boot(sc)
  local M = dofile("addon/tests/wow_mock.lua")
  local FS = {}
  M.install(function(id) return FS.Gear and FS.Gear.byId and FS.Gear.byId[id] end)
  local g = M.game
  g.class = sc.key == "shaman" and { "Shaman", "SHAMAN" } or { "Druid", "DRUID" }
  g.name = sc.key == "shaman" and "Koda" or "Tato"
  g.level = sc.level
  g.stats = { sc.sheet.str, sc.sheet.agi, 50, sc.sheet.int, 40 }
  -- the live sheet carries buffs (+40 AP): the website's sheet for the same level must win
  g.ap, g.crit, g.spellCrit, g.sp = sc.sheet.ap + 40, sc.sheet.crit, sc.sheet.spellCrit, sc.sheet.sp
  g.dodge, g.parry = sc.sheet.dodge, sc.sheet.parry
  g.professions = sc.key == "shaman" and { 333, 393 } or { 393, 182 }
  for inv, id in pairs(sc.inventory) do
    local suffix = sc.suffix[tostring(id)]
    local link = M.link(id, suffix and 1234 or nil)
    g.inventory[tonumber(inv)] = link
    if suffix then
      g.stats_by_link[link] = { ITEM_MOD_STRENGTH_SHORT = suffix.str, ITEM_MOD_STAMINA_SHORT = suffix.sta, RESISTANCE0_NAME = 80 }
    end
  end
  ForeverSuiteDB, ForeverSuiteCharDB = nil, nil
  M.load(DIR, FS)
  M.fire("ADDON_LOADED", "ForeverSuite")
  M.fire("PLAYER_LOGIN")
  M.runTimers(5)
  return M, FS
end

-- --- 1. parity with the website ------------------------------------------------------------------
for i, sc in ipairs(expected) do
  local M, FS = boot(sc)
  local G = FS.Gear
  local S = G.State
  check(FS.ready, "scenario " .. i .. ": addon ready")
  local data = assert(FS.Import.Parse(importText(sc, sc.key == "shaman" and "Koda Ashmane" or "Tato Mcpaw")))
  FS.Import.Apply(data)
  S:Set("topN", 5)
  local st = S.self
  check(st and st.key == sc.key, "scenario " .. i .. ": profile " .. sc.key)
  check(st.talSrc == "website", "scenario " .. i .. ": talents from the import")
  check(st.sheetSrc == "website", "scenario " .. i .. ": character sheet from the import (same level)")
  if sc.key == "shaman" then
    check(st.tal.md == 100 and st.tal.impWT == 30, "scenario " .. i .. ": Mental Dexterity from rank 3 (100%), Improved Weapon Totems 30%")
  end
  if sc.we then check(st.equipped["Two-Hand"][1].enchDmg == 5, "scenario " .. i .. ": weapon enchant from the import") end
  local w = S:Weights(st, sc.level)
  check((w.__model ~= nil) == sc.model, "scenario " .. i .. ": model used " .. tostring(sc.model))
  for k, v in pairs(sc.weights) do
    check(near(w[k], v), ("scenario %d: weight %s lua %s js %s"):format(i, k, tostring(w[k]), tostring(v)))
  end
  local slotsOk = 0
  for slot, exp in pairs(sc.slots) do
    local d = G:SlotData(st, slot, sc.level, 5)
    local ok = near(d.base, exp.base) and #d.top == #exp.top
    for j, p in ipairs(exp.top) do
      local got = d.top[j]
      if not got or got.it.id ~= p.id or not near(got.s, p.s) then ok = false end
    end
    if exp.next then ok = ok and d.next and d.next.it.id == exp.next.id and d.next.L == exp.next.L and near(d.next.s, exp.next.s)
    else ok = ok and d.next == nil end
    if not ok then
      local got = {}
      for _, p in ipairs(d.top) do got[#got + 1] = p.it.id .. "=" .. ("%.3f"):format(p.s) end
      local want = {}
      for _, p in ipairs(exp.top) do want[#want + 1] = p.id .. "=" .. ("%.3f"):format(p.s) end
      say(("  %s base lua %.3f js %.3f\n    lua %s\n    js  %s"):format(slot, d.base or -1, exp.base or -1, table.concat(got, " "), table.concat(want, " ")))
    else
      slotsOk = slotsOk + 1
    end
    check(ok, ("scenario %d (%s %d): slot %s matches the website"):format(i, sc.key, sc.level, slot))
  end
  say(("scenario %d: %s level %d, %s: %d slots match"):format(i, sc.key, sc.level, sc.preset, slotsOk))
  check(not M.errors, "scenario " .. i .. ": no Lua errors")
end

-- --- 2. modules in action (shaman scenario) ---------------------------------------------------------
local M, FS = boot(expected[1])
FS.Import.Apply(assert(FS.Import.Parse(importText(expected[1], "Koda Ashmane"))))
local G, S = FS.Gear, FS.Gear.State
M.printed = {}

-- window and all tabs
SlashCmdList.FOREVERSUITE("")
check(FS.Window.frame and FS.Window.frame:IsShown(), "window opens with /fs")
for _, tab in ipairs({ "overview", "gear", "dungeons", "quests", "settings" }) do
  SlashCmdList.FOREVERSUITE(tab)
  check(FS.Window.current == tab, "tab " .. tab .. " opens")
end
S:SetPreviewLevel(40)
M.runTimers(1)
check(S.self.level == 40, "preview level 40")
SlashCmdList.FOREVERSUITE("gear")
S:SetPreviewLevel(nil)
check(S.self.level == S.self.liveLevel, "back to live level")

-- overview tab: rows by gain, a click opens the slot on the Gear tab
SlashCmdList.FOREVERSUITE("overview")
local ov = FS.Window:Tab("overview")
check(ov and ov.obj and FS.Window.current == "overview", "overview tab opens")
local firstRow
for _, f in ipairs(M.frames) do
  if f._shown and f.onClick and f.item and f._parent and f._parent._parent and f._parent._parent._parent == ov.panel then firstRow = firstRow or f end
end
check(firstRow ~= nil, "overview lists upgrades")
if firstRow then firstRow:Click() end
check(FS.Window.current == "gear", "overview row opens the Gear tab")

-- tooltip line on an item
GameTooltip:SetItemByID(10570)
check(find(GameTooltip._lines or {}, "Forever Suite"), "tooltip shows the score line")
say("tooltip: " .. tostring(find(GameTooltip._lines or {}, "Forever Suite")))
-- an item missing from the data, built from the game's item info
M.unknownItems = { [999001] = { n = "Mystery Cleaver", q = 2, il = 30, rq = 25, sl = "Two-Hand", classID = 2, subclassID = 1 } }
M.game.stats_by_link[M.link(999001)] = { ITEM_MOD_STRENGTH_SHORT = 10, ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 24.5 }
GameTooltip:SetHyperlink(M.link(999001))
check(find(GameTooltip._lines or {}, "Forever Suite"), "tooltip works for items not in the data")
say("unknown item tooltip: " .. tostring(find(GameTooltip._lines or {}, "Forever Suite")))

-- quest reward
M.game.questChoices = { M.link(10570), M.link(4247), M.link(7027) }
M.fire("QUEST_COMPLETE")
M.runTimers(1)
check(find(M.printed, "Best reward"), "quest reward announced")
say("quest reward: " .. tostring(find(M.printed, "Best reward")))

-- partner sync: send our state, receive a druid partner
M.game.group = "PARTY"
FS:Fire("SYNC_REQUESTED")
M.runTimers(10)
local sentState
for _, s in ipairs(M.sent) do if s.msg:match("^S\t") then sentState = true end end
check(sentState, "own state sent to the group")
local P = FS.modules.partner
local own = P.Encode(S.self)
local druid = own:gsub("k=shaman", "k=druid"):gsub("p=Level model", "p=Level model (Cat)")
-- our own messages come back from the group under our full Forever name: never a partner
local echo = M.deliver("Koda Ashmane")
M.runTimers(5)
check(echo > 0 and not S.partners["Koda Ashmane"] and FS.db.partners["Koda Ashmane"] == nil, "own echoed messages are not a partner")
check(FS.db.selfNames["Koda Ashmane"], "own full name learned from the echo")
-- a partner's addon has its own token: send as if from Tato Mcpaw's client
local function asPartner(kind, payload)
  local mine = FS.Comm.token
  FS.Comm.token = "beef0001"
  M.sent = {}
  FS.Comm:Send(kind, payload)
  M.runTimers(10)
  FS.Comm.token = mine
  M.deliver("Tato Mcpaw", kind)
  M.runTimers(5)
end
asPartner("S", druid)
local tato = S.partners["Tato Mcpaw"]
check(tato and tato.key == "druid", "partner Tato received as druid")
GameTooltip:SetItemByID(10400)
local line = find(GameTooltip._lines or {}, "Forever Suite") or ""
check(line:find("Tato") and not line:find("Mcpaw"), "tooltip shows the partner by first name")
local _, yous = line:gsub("You", "")
check(yous == 1 and not line:find("Koda"), "tooltip shows you once, as You")
say("tooltip with partner: " .. line)
-- an older version stored your own echo as a partner: it is dropped
FS.db.partners["Koda Ashmane"] = { payload = own, at = 1 }
FS.db.questSync["Koda Ashmane"] = { at = 1, ids = {} }
FS:ForgetSelf()
check(FS.db.partners["Koda Ashmane"] == nil and FS.db.questSync["Koda Ashmane"] == nil, "stored self entries removed")

-- quest sync
M.game.quests = { [6481] = true, [1164] = true }
local enc = FS.modules.questsync.Encode({ [6481] = true, [1445] = true, [31] = true })
local dec = FS.modules.questsync.Decode(enc)
check(dec[6481] and dec[1445] and dec[31], "quest list survives encoding")
asPartner("Q", enc)
check(FS.db.questSync["Tato Mcpaw"] and FS.db.questSync["Tato Mcpaw"].ids[1445], "partner quests stored")
SlashCmdList.FOREVERSUITE("quests")

-- quests tab grouped by zone (quest table built into the addon)
FS.Data.questZones = { "Sunken Temple", "The Barrens" }
FS.Data.quests[1445] = { "The Temple of Atal'Hakkar", 1, 50, 38 }
FS.Data.quests[31] = { "Aquatic Form", 2, 16, 16 }
SlashCmdList.FOREVERSUITE("quests")
local seen = {}
for _, f in ipairs(M.frames) do if f._kind == "FontString" and f._parent and f._parent._shown then seen[f._text] = true end end
check(seen["Sunken Temple"] and seen["The Barrens"], "quests grouped under zone headers")
check(seen["|cffffd100The Temple of Atal'Hakkar|r"] or seen["|cffffd100Quest title 1445|r"], "quest listed by title")

-- rewards of a quest already turned in are left out, also those known only by the quest's name
local furs = G.byId[271719]
check(furs and furs.src[1].id == 98823, "name-only quest reward gets the quest ID (Furs of the Earthen Ring)")
local function inBack()
  for _, p in ipairs(G:SlotData(S.self, "Back", 34, 10).pool) do if p.it.id == 271719 then return true end end
  return false
end
check(inBack(), "Furs listed while Earthen Echo is open")
M.game.quests[98823] = true
M.fire("QUEST_TURNED_IN", 98823)
M.runTimers(2)
check(not inBack(), "Furs gone once Earthen Echo is turned in")
S:Set("hideDone", false)
check(inBack(), "Furs back with 'Hide finished quests' off")
S:Set("hideDone", true)
-- a reward the data knows only by quest name learns the quest ID at the quest giver
local cloak, trousers
for _, it in ipairs(FS.Data.items) do
  if it.n == "Catacomb Cloak" then cloak = it end
  if it.n == "Deepgrave Trousers" then trousers = it end
end
if cloak and trousers and not cloak.src[1].id then
  M.game.questID = 99001
  M.game.questChoices = { M.link(cloak.id) }
  M.fire("QUEST_DETAIL")
  check(cloak.src[1].id == 99001 and FS.db.questIds[cloak.id] == 99001, "quest ID learned from the quest giver")
  check(trousers.src[1].id == 99001, "other rewards of the same quest learn it too")
  M.game.questChoices = {}
  M.game.questID = nil
else
  say("(skipped: no name-only quest reward in the data)")
end

-- source switches on the Gear tab
S:Set("sources", { "Quest", "Vendor", "Crafted" })
local dungeonOnly = false
for _, p in ipairs(G:SlotData(S.self, "Legs", 34, 10).pool) do
  local any = false
  for _, s in ipairs(p.it.src) do if s.t ~= "Dungeon" and G.SrcUsable(p.it, s, 34, S.self) then any = true end end
  if not any then dungeonOnly = true end
end
check(not dungeonOnly, "dungeon drops hidden when Dungeon is switched off")
S:Set("sources", nil)

-- dungeon guide: entering the Deadmines on a German client
M.game.instance = { name = "Die Todesminen", id = 36 }
M.fire("PLAYER_ENTERING_WORLD")
M.runTimers(5)
check(find(M.printed, "Deadmines"), "dungeon recognised by its instance ID")
check(FS.Window.current == "dungeons", "Dungeons tab opens on entering")
for _, l in ipairs(M.lastPrints(3)) do say("dungeon: " .. l) end
M.game.instance = { name = "Halle der Thane", id = 9999 }
M.fire("PLAYER_ENTERING_WORLD")
M.runTimers(5)
check(find(M.printed, "Unknown dungeon"), "unknown dungeon asks to be linked")
M.game.instance = nil

-- loot roll hint
M.rollLinks = { [7] = M.link(10570) }
M.fire("START_LOOT_ROLL", 7)
check(find(M.printed, "Roll"), "loot roll hint")
say("loot: " .. tostring(find(M.printed, "Roll")))

-- a text copied from the website (Addon tab), pasted with a line break in it
local SAMPLE = "FS1~2026-11-10 16:04~k=shaman;n=Koda Ashmane;p=Level model;src=Quest,Dungeon,Vendor,Crafted;pf=Enchanting;rnd=0;up=1;lv=34;t=ak:0,bloodFrenzy:0,elemW:0,flurry:25,hit:0,lotp:0,md:66,predStrikes:0,sharpClaws:0,shiftingPower:0,storm:1,thunder:0;sh=agi:55,ap:290,crit:6.5,int:75,sp:0,spellCrit:3.2,str:110~k=druid;n=Tato Mcpaw;p=Level model (Cat);src=Quest,Dungeon,Vendor,Crafted;pf=;rnd=0;up=1;lv=30;t=ak:0,bloodFrenzy:0,elemW:0,flurry:0,hit:0,lotp:0,md:0,predStrikes:0,sharpClaws:4,shiftingPower:0,storm:0,thunder:0;sh=agi:70,ap:140,crit:7.2,int:80,sp:0,spellCrit:4,str:60"
local imp = FS.Import.Parse("  " .. SAMPLE:sub(1, 120) .. "\n" .. SAMPLE:sub(121) .. "  ")
check(imp and imp.chars.shaman and imp.chars.druid, "website text: both characters")
check(imp and imp.chars.shaman.tal.flurry == 25 and imp.chars.shaman.tal.storm == 1, "website text: shaman talents")
check(imp and imp.chars.druid.sheet.agi == 70 and imp.chars.druid.preset == "Level model (Cat)", "website text: druid sheet and preset")
check(imp and #imp.chars.druid.profs == 0 and imp.chars.shaman.profs[1] == "Enchanting", "website text: professions")
check(FS.Import.Parse("hello") == nil, "rejects other text")

-- Cat and Bear for a druid in the tooltip (module druidforms), switchable
GameTooltip:SetItemByID(10400)
local formsLine = find(GameTooltip._lines or {}, "Forever Suite") or ""
check(formsLine:find("Tato") and formsLine:find("Cat") and formsLine:find("Bear"), "druid partner shows Cat and Bear")
check(not formsLine:find("You |cffaaaaaaCat"), "the shaman has no Cat/Bear split")
say("tooltip with forms: " .. formsLine)
FS:SetModuleEnabled("druidforms", false)
GameTooltip:SetItemByID(10400)
local plainLine = find(GameTooltip._lines or {}, "Forever Suite") or ""
check(plainLine:find("Tato") and not plainLine:find("Bear"), "Cat/Bear can be switched off")
FS:SetModuleEnabled("druidforms", true)
local bearW = S:Weights(tato, tato.level, "Bear (tank)")
check(bearW.sta == 1.0 and bearW.armor == 0.08, "Bear weights used for the Bear score")

-- dungeon quests: lines with pre-quests, status for you and the partner
local DQ = FS.DQ
check(DQ and DQ.enabled, "dungeon quest module on")
local necklace = DQ.Steps(2341, S:All())
local names = {}
for _, id in ipairs(necklace) do names[#names + 1] = id end
check(table.concat(names, ",") == "2283,2284,2318,2338,2339,2340,2341", "Uldaman necklace line in order: " .. table.concat(names, ","))
local lineMe = DQ.LineStatus(S.self, necklace)
check(lineMe.kind == "level" and lineMe.min == 37 and lineMe.step == 1, "necklace line: from level 37 at step 1")
local tubers = DQ.Steps(1221, S:All())
check(#tubers == 1 and DQ.LineStatus(S.self, tubers).kind == "ready", "Blueleaf Tubers ready to pick up")
M.game.active[1221] = true
check(DQ.LineStatus(S.self, tubers).kind == "log", "in your quest log")
M.game.active[1221] = nil
M.game.quests[1221] = true
check(DQ.LineStatus(S.self, tubers).kind == "done", "done once turned in")
M.game.quests[1221] = nil
-- the partner's quest log arrives with QL
asPartner("QL", FS.modules.questsync.Encode({ [1144] = true }))
check(FS.db.questSync["Tato Mcpaw"].active and FS.db.questSync["Tato Mcpaw"].active[1144], "partner quest log stored")
check(DQ.LineStatus(tato, DQ.Steps(1144, S:All())).kind == "log", "partner has Willix in the log")
-- a line in the middle: steps 1-2 done, step 3 starts inside the dungeon
M.game.level = 40; S:Refresh("level")
M.game.quests[2283], M.game.quests[2284] = true, true
local mid = DQ.LineStatus(S.self, DQ.Steps(2341, S:All()))
check(mid.kind == "ready" and mid.step == 3 and mid.total == 7, "necklace line: step 3 of 7 ready")
-- view: Dungeons tab, Quests
SlashCmdList.FOREVERSUITE("dungeons")
local dtab = FS.Window:Tab("dungeons")
dtab.obj:Select("Uldaman")
dtab.obj:SetMode("quests")
local qv = dtab.obj.qview
check(qv and qv.dungeon == "Uldaman" and #qv.lines >= 5, "quests view shows Uldaman's lines (" .. (qv and #qv.lines or 0) .. ")")
qv.expanded[2341] = true
qv:Render("Uldaman")
local stepRows, pinned = 0, nil
for _, f in ipairs(M.frames) do
  if f._shown and f.num and f.questName and f.badge then
    stepRows = stepRows + 1
    if f.start and f.start.m and not pinned then pinned = f end
  end
end
check(stepRows == 7, "expanded necklace line shows 7 steps (" .. stepRows .. ")")
if pinned then pinned:Click() end
check(#M.game.waypoints == 1 and M.game.waypoints[1].m, "click on a step sets a map pin")
qv:ToggleAll()
qv.onlyOpen = false; qv:Render("Razorfen Kraul")
check(#qv.lines == 4, "Razorfen Kraul: 4 lines with 'Only open' off (" .. #qv.lines .. ")")
-- entering a dungeon lists quests not picked up
M.printed = {}
M.game.instance = { name = "Kral der Klingenhauer", id = 47 }
M.fire("PLAYER_ENTERING_WORLD")
M.runTimers(5)
check(find(M.printed, "quests not picked up"), "entering a dungeon lists quests not picked up")
for _, l in ipairs(M.lastPrints(3)) do say("enter: " .. l) end
M.game.instance = nil
dtab.obj:SetMode("loot")
M.game.level = 34; S:Refresh("level")

-- XP bars
local XB = FS.modules.xpbar
M.sent = {}
XB:Send(true)
M.runTimers(2)
local xpSent = false
for _, m in ipairs(M.sent) do if m.msg:match("^XP\t") then xpSent = true end end
check(xpSent, "own XP sent")
asPartner("XP", "lv=34;mx=60000;rs=0;xp=48000")
check(XB.frame and XB.frame:IsShown(), "XP frame shows with a partner")
local diffText = XB.frame.diff:GetText() or ""
check(diffText:find("Tato is ahead"), "XP frame says who is ahead: " .. diffText)
say("xp: " .. (XB.frame.bars[1].text:GetText() or "") .. " " .. (XB.frame.bars[1].right:GetText() or "") .. " | " ..
  (XB.frame.bars[2].text:GetText() or "") .. " " .. (XB.frame.bars[2].right:GetText() or "") .. " | " .. diffText)
FS:SetModuleEnabled("xpbar", false)
check(not XB.frame:IsShown(), "XP frame hides when switched off")
FS:SetModuleEnabled("xpbar", true)

-- modules off and on again
for _, m in ipairs(FS.moduleList) do
  FS:SetModuleEnabled(m.id, false)
  check(not m.enabled, "module " .. m.id .. " switches off")
  FS:SetModuleEnabled(m.id, true)
  check(m.enabled, "module " .. m.id .. " switches on")
end
SlashCmdList.FOREVERSUITE("settings")
SlashCmdList.FOREVERSUITE("modules")

-- weights tooltip and window refresh after gear change
M.game.inventory[16] = M.link(10570)
M.fire("PLAYER_EQUIPMENT_CHANGED", 16)
M.runTimers(2)
check(S.self.equipped["Two-Hand"][1].id == 10570, "gear change picked up")

-- hover and click everything on every tab once
for _, tab in ipairs({ "overview", "gear", "dungeons", "quests", "settings" }) do
  SlashCmdList.FOREVERSUITE(tab)
  M.runTimers(1)
  local snapshot = {}
  for _, f in ipairs(M.frames) do snapshot[#snapshot + 1] = f end
  for _, f in ipairs(snapshot) do
    if f._shown then
      for _, script in ipairs({ "OnEnter", "OnLeave", "OnClick", "OnMouseWheel", "OnDragStart", "OnDragStop", "OnMouseDown", "OnMouseUp" }) do
        local fn = f._scripts[script]
        if fn then
          local ok, err = pcall(fn, f, script == "OnMouseWheel" and -1 or "LeftButton")
          check(ok, "UI " .. tab .. " " .. script .. ": " .. tostring(err))
        end
      end
    end
  end
  M.runTimers(2)
end
-- the import dialog with a pasted text
SlashCmdList.FOREVERSUITE("import")
FS.Import.frame.edit:SetText(SAMPLE)
check(FS.Import.frame:IsShown(), "import dialog opens")

check(not M.errors, "no Lua errors in the module run")
-- a class without a profile: the window, tooltips and partners still work
do
  local sc = expected[1]
  local M2, FS2 = boot(setmetatable({ key = "warrior" }, { __index = sc }))
  M2.game.class = { "Warrior", "WARRIOR" }
  M2.fire("PLAYER_ENTERING_WORLD")
  M2.runTimers(5)
  check(FS2.Gear.State.self == nil, "warrior: no profile")
  for _, tab in ipairs({ "overview", "gear", "dungeons", "quests", "settings" }) do SlashCmdList.FOREVERSUITE(tab) end
  GameTooltip:SetItemByID(10400)
  check(not M2.errors, "warrior: no Lua errors")
end

-- a druid in Cat Form: the model keeps the caster-form sheet it saw last
do
  local sc
  for _, x in ipairs(expected) do if x.key == "druid" then sc = sc or x end end
  local M3, FS3 = boot(sc)
  local S3 = FS3.Gear.State
  check(S3.self.sheetSrc == "game", "druid: sheet from the game in caster form")
  M3.game.form = 1
  M3.game.ap = 999
  M3.fire("UPDATE_SHAPESHIFT_FORM")
  M3.runTimers(3)
  check(S3.self.sheet.ap == sc.sheet.ap + 40 and S3.self.sheetSrc == "saved", "druid: cat form does not change the sheet")
  -- an imported sheet from another level is not used: the game's own counts
  FS3.Import.Apply(assert(FS3.Import.Parse(("FS1~x~k=druid;n=Tato;p=Level model (Cat);sh=str:1,agi:1,ap:1,crit:1;sl=%d"):format(sc.level - 1))))
  check(S3.self.sheetSrc ~= "website", "druid: website sheet of an older level is ignored")
  check(not M3.errors, "druid: no Lua errors")
end

say(("%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
