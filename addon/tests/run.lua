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
  return ("FS1~2026-11-10 12:00~k=%s;n=%s;p=%s;src=Quest,Dungeon,Vendor,Crafted;pf=%s;rnd=0;up=1;lv=%d;t=%s;sh=%s")
    :format(sc.key, name, sc.preset, sc.key == "shaman" and "Enchanting" or "", sc.level, map(sc.tal), map(sc.sheet))
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
  g.ap, g.crit, g.spellCrit, g.sp = sc.sheet.ap, sc.sheet.crit, sc.sheet.spellCrit, sc.sheet.sp
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
for _, tab in ipairs({ "gear", "dungeons", "quests", "settings" }) do
  SlashCmdList.FOREVERSUITE(tab)
  check(FS.Window.current == tab, "tab " .. tab .. " opens")
end
S:SetPreviewLevel(40)
M.runTimers(1)
check(S.self.level == 40, "preview level 40")
SlashCmdList.FOREVERSUITE("gear")
S:SetPreviewLevel(nil)
check(S.self.level == S.self.liveLevel, "back to live level")

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
M.sent = {}
FS.Comm:Send("S", druid)
M.runTimers(10)
M.deliver("Tato", "S")
M.runTimers(5)
check(S.partners.Tato and S.partners.Tato.key == "druid", "partner Tato received as druid")
GameTooltip:SetItemByID(10400)
local line = find(GameTooltip._lines or {}, "Forever Suite") or ""
check(line:find("Tato"), "tooltip shows the partner too")
say("tooltip with partner: " .. line)

-- quest sync
M.game.quests = { [6481] = true, [1164] = true }
local enc = FS.modules.questsync.Encode({ [6481] = true, [1445] = true, [31] = true })
local dec = FS.modules.questsync.Decode(enc)
check(dec[6481] and dec[1445] and dec[31], "quest list survives encoding")
M.sent = {}
FS.Comm:Send("Q", enc)
M.runTimers(10)
M.deliver("Tato", "Q")
check(FS.db.questSync.Tato and FS.db.questSync.Tato.ids[1445], "partner quests stored")
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
for _, tab in ipairs({ "gear", "dungeons", "quests", "settings" }) do
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
  for _, tab in ipairs({ "gear", "dungeons", "quests", "settings" }) do SlashCmdList.FOREVERSUITE(tab) end
  GameTooltip:SetItemByID(10400)
  check(not M2.errors, "warrior: no Lua errors")
end

-- a druid in Cat Form: the model keeps the caster-form sheet it saw last
do
  local sc = expected[3]
  local M3, FS3 = boot(sc)
  local S3 = FS3.Gear.State
  check(S3.self.sheetSrc == "game", "druid: sheet from the game in caster form")
  M3.game.form = 1
  M3.game.ap = 999
  M3.fire("UPDATE_SHAPESHIFT_FORM")
  M3.runTimers(3)
  check(S3.self.sheet.ap == sc.sheet.ap and S3.self.sheetSrc == "saved", "druid: cat form does not change the sheet")
  check(not M3.errors, "druid: no Lua errors")
end

say(("%d checks, %d failed"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)
