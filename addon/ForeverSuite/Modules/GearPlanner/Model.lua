-- Level model, a port of the website's site/model.js: expected damage per second of the character at a
-- given level, from talents, character sheet and the ability ranks in the game data. Stat weights are the
-- extra damage of one more point of each stat, counted in Strength points. Keep both files in step.
--
-- Talents arrive as numbers (from the website import or the game's talent tooltips):
--   flurry, elemW, thunder, md, ak, hit, bloodFrenzy, predStrikes, sharpClaws, lotp  (percent values)
--   storm, shiftingPower                                                             (1 if learned)
local _, FS = ...
local M = {}
FS.Model = M

local max, min = math.max, math.min

local function mech() return FS.Data.mech or {} end
local function rankAt(list, L)
  local r
  for _, x in ipairs(list or {}) do if x.lv <= L then r = x end end
  return r
end
local function scaled(base, perLevel, lv, cap, L) return base + (perLevel or 0) * max(0, min(L, cap or L) - lv) end
local function T(tal, k) return (tal and tonumber(tal[k])) or 0 end

-- Normal mobs: armor grows with level (rough fit of Classic values); physical damage taken after armor.
function M.mobArmor(L) return max(20, 57 * L - 400) end
function M.physMult(L) local a = M.mobArmor(L); return 1 - a / (a + 400 + 85 * L) end
-- Attack table against a mob of your level, fought from the front: 5% miss, dodge and parry.
local function avoidance(hitPct)
  local miss = max(0, 0.05 - hitPct / 100)
  return { miss = miss, dodge = 0.05, parry = 0.05, land = 1 - miss - 0.10 }
end

-- --- Enhancement Shaman ----------------------------------------------------------------------
local function shamanDps(L, s, tal, w, detail)
  local flurry, elemW, storm = T(tal, "flurry") / 100, T(tal, "elemW") / 100, T(tal, "storm") > 0
  local t = avoidance(s.hit)
  local crit = min(1, s.crit / 100)
  local speed = w.speed or 2
  local wAvg = ((w.min or 0) + (w.max or 0)) / 2
  local swing = wAvg + s.ap / 14 * speed
  local whiteCrit = min(crit, t.land)
  local whiteHit = t.land - whiteCrit
  local whiteMult = whiteHit + 2 * whiteCrit
  local yellowMult = t.land * (1 + crit)
  local flurryUp = flurry > 0 and (1 - (1 - whiteCrit) ^ 3) or 0
  local swingsPerSec = (1 / speed) * (1 + flurry * flurryUp)
  local ssPerSec = storm and 1 / 6 or 0                     -- Stormstrike: 6 sec cooldown in Forever
  local phys = M.physMult(L)
  local white = swingsPerSec * swing * whiteMult * phys
  local ss = ssPerSec * 1.5 * swing * yellowMult * phys
  local wf = 0
  local wfr = L >= 30 and rankAt(mech().windfury, L) or nil
  if wfr then
    local bonusAp = scaled(wfr.ap, wfr.perLevel, wfr.lv, wfr.max, L) * (1 + elemW)
    local procsPerSec = 0.2 * t.land * (swingsPerSec + ssPerSec)
    wf = procsPerSec * (wfr.attacks or 1) * (wAvg + (s.ap + bonusAp) / 14 * speed) * whiteMult * phys
  end
  local es = 0
  local esr = rankAt(mech().earthShock, L)
  if esr then
    local dmg = scaled(esr.base, esr.perLevel, esr.lv, esr.max, L) * 1.04 + (esr.coef or 0) * (s.sp or 0)
    local spellCrit = min(1, (s.spellCrit or 0) / 100)
    es = dmg * (storm and 1.2 or 1) * 0.96 * (1 + 0.5 * spellCrit) / 6
  end
  local total = white + ss + wf + es
  if detail then return { total = total, parts = { { "Auto attacks", white }, { "Windfury", wf }, { "Stormstrike", ss }, { "Earth Shock", es } } } end
  return total
end

-- --- Feral Druid, Cat Form -------------------------------------------------------------------
local function catDps(L, s, tal, w, detail)
  local bloodFrenzy = T(tal, "bloodFrenzy") / 100
  local t = avoidance(s.hit)
  local crit = min(1, s.crit / 100)
  local normal = (w.dps or 0) + s.ap / 14
  local phys = M.physMult(L)
  local whiteCrit = min(crit, t.land)
  local whiteMult = (t.land - whiteCrit) + 2 * whiteCrit
  local yellowMult = t.land * (1 + crit)
  local white = normal * whiteMult * phys
  local energy = 10
  if T(tal, "shiftingPower") > 0 then energy = energy + 40 / 8 end
  local claw = rankAt(mech().claw, L)
  if not claw then
    if detail then return { total = white, parts = { { "Auto attacks", white } } } end
    return white
  end
  local builderCost, builderDmg = claw.energy, (normal * claw.pct / 100 + claw.flat) * yellowMult * phys
  local cpPerHit = t.land * (1 + crit * bloodFrenzy)
  local rake, rip = rankAt(mech().rake, L), rankAt(mech().rip, L)
  local builders, cost, dmg = 5 / cpPerHit, 0, 0
  local pRake, pClaw, pRip = 0, 0, 0
  if rake then
    local rd = rake.direct * yellowMult * phys + rake.tick * 3 * t.land
    cost, dmg, pRake, builders = cost + rake.energy, dmg + rd, rd, builders - 1
  end
  builders = max(0, builders)
  cost, dmg, pClaw = cost + builders * builderCost, dmg + builders * builderDmg, builders * builderDmg
  if rip then
    local rd = ((rip.tick + rip.tickPerCp * 5) * (12 / rip.period) + 0.24 * s.ap) * t.land
    cost, dmg, pRip = cost + rip.energy, dmg + rd, rd
  end
  local cycle = cost / energy
  local total = white + dmg / cycle
  if detail then
    return { total = total, parts = { { "Auto attacks", white }, { "Claw", pClaw / cycle }, { "Rake", pRake / cycle }, { "Rip", pRip / cycle } } }
  end
  return total
end

-- --- character state -------------------------------------------------------------------------
local function weaponOf(items)
  local w
  for _, e in ipairs(items or {}) do if e.slot == "Two-Hand" then w = e.it; break end end
  if not w then return { min = 0, max = 0, speed = 2, dps = 0 } end
  local spd = w.speed or 2
  local lo = w.dmgMin or (w.dps or 0) * spd * 0.85
  local hi = w.dmgMax or (w.dps or 0) * spd * 1.15
  return { min = lo, max = hi, speed = spd, dps = (lo + hi) / 2 / spd }
end
M.weaponOf = weaponOf

local function gearSum(items, key)
  local s = 0
  for _, e in ipairs(items or {}) do s = s + ((e.it.st and e.it.st[key]) or 0) end
  return s
end

local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end

-- Everything the model needs for one character, or nil when data is missing.
-- input: { sheet = {str, agi, int, ap, crit, spellCrit, sp}, tal = {...}, items = { {slot, it} }, level = current level }
function M.context(key, input, level)
  local sh = input and input.sheet
  if not sh or not sh.str or not sh.agi or not sh.ap or not sh.crit then return nil end
  local tal = input.tal or {}
  local curLevel = input.level or level
  local s = { str = sh.str, agi = sh.agi, int = sh.int or 0, ap = sh.ap, crit = sh.crit, spellCrit = sh.spellCrit or 0,
    sp = sh.sp or 0, hit = gearSum(input.items, "hit") + T(tal, "hit") }
  local agiPerCrit, kind
  if key == "shaman" then
    kind = "shaman"
    agiPerCrit = sh.agi / max(0.5, sh.crit - T(tal, "thunder") - 1.7)          -- base melee crit 1.7%
  else
    kind = "cat"
    if level < 20 then return nil end                                         -- Cat Form from level 20
    agiPerCrit = sh.agi / max(0.5, sh.crit - 0.9)                              -- caster-form sheet, base crit 0.9%
    s.ap = s.ap + 12 + sh.agi + T(tal, "predStrikes") / 100 * level
    s.crit = s.crit + T(tal, "sharpClaws") + T(tal, "lotp")
  end
  if not finite(agiPerCrit) or agiPerCrit < 4 or agiPerCrit > 60 then agiPerCrit = 20 * curLevel / 60 end
  agiPerCrit = agiPerCrit * level / curLevel
  return { key = key, kind = kind, level = level, s = s, tal = tal, w = weaponOf(input.items), agiPerCrit = agiPerCrit,
    md = T(tal, "md") / 100, ak = T(tal, "ak") / 100 }
end

local function dpsOf(ctx, s, w, detail)
  if ctx.kind == "shaman" then return shamanDps(ctx.level, s, ctx.tal, w, detail) end
  return catDps(ctx.level, s, ctx.tal, w, detail)
end

local function withStats(ctx, d)
  local s = {}
  for k, v in pairs(ctx.s) do s[k] = v end
  local str, agi, int = d.str or 0, d.agi or 0, (d.int or 0) * (1 + ctx.ak)
  s.ap = s.ap + 2 * str + (d.ap or 0)
  if ctx.kind == "shaman" then s.ap = s.ap + ctx.md * int
  else s.ap = s.ap + agi + (d.feralAp or 0) end                               -- Cat Form: 1 AP per Agility
  s.crit = s.crit + agi / ctx.agiPerCrit + (d.crit or 0)
  s.hit = s.hit + (d.hit or 0)
  s.sp = s.sp + (d.sp or 0) + (ctx.kind == "shaman" and (d.natureSp or 0) or 0)
  return s
end

local STEP = { str = 10, agi = 10, int = 10, ap = 20, feralAp = 20, crit = 1, hit = 1, sp = 20, natureSp = 20 }
M.KEYS = { "str", "agi", "int", "ap", "feralAp", "crit", "hit", "sp", "natureSp" }

-- Weights in Strength points, plus a weapon valuation and the damage breakdown.
function M.weights(ctx)
  local base = dpsOf(ctx, ctx.s, ctx.w)
  local per = {}
  for k, step in pairs(STEP) do
    per[k] = (dpsOf(ctx, withStats(ctx, { [k] = step }), ctx.w) - base) / step
  end
  local unit = per.str
  if not unit or unit == 0 then unit = 1 end
  local w = {}
  for k, v in pairs(per) do w[k] = max(0, v / unit) end
  if ctx.kind ~= "shaman" then w.sp, w.natureSp = 0, 0 end
  if ctx.kind == "shaman" then w.feralAp = 0 end
  local zero = dpsOf(ctx, ctx.s, { min = 0, max = 0, speed = 2, dps = 0 })
  local cache = {}
  return {
    w = w, unit = unit, dps = base, ctx = ctx,
    detail = dpsOf(ctx, ctx.s, ctx.w, true),
    -- a two-hander's worth: its damage (and speed) against no weapon, in Strength points
    weapon = function(it)
      local v = cache[it]
      if v then return v end
      local add = (it.st and it.st.wpnDmg) or 0
      local spd = it.speed or 2
      local lo = (it.dmgMin or (it.dps or 0) * spd * 0.85) + add
      local hi = (it.dmgMax or (it.dps or 0) * spd * 1.15) + add
      v = (dpsOf(ctx, ctx.s, { min = lo, max = hi, speed = spd, dps = (lo + hi) / 2 / spd }) - zero) / unit
      cache[it] = v
      return v
    end,
  }
end

-- --- talents from their tooltip text (English client), same rules as model.js -----------------
-- talents: list of { n = name, d = description }
function M.talentNumbers(talents)
  local byName = {}
  for _, t in ipairs(talents or {}) do byName[t.n] = t.d or "" end
  local function num(name, pat)
    local d = byName[name]
    local v = d and d:match(pat)
    return v and tonumber(v) or 0
  end
  local hit = 0
  for _, t in ipairs(talents or {}) do
    local v = (t.d or ""):lower():match("chance to hit by (%d+%.?%d*)%%")
    if v then hit = hit + tonumber(v) end
  end
  return {
    flurry = num("Flurry", "by (%d+%.?%d*)%%"),
    elemW = num("Elemental Weapons", "Windfury Weapon effect by (%d+)%%"),
    storm = byName["Stormstrike"] and 1 or 0,
    thunder = num("Thundering Strikes", "by (%d+)%%"),
    md = num("Mental Dexterity", "equal to (%d+)%%"),
    ak = num("Ancestral Knowledge", "Intellect by (%d+)%%"),
    hit = hit,
    bloodFrenzy = num("Blood Frenzy", "Combo Points have a (%d+)%% chance"),
    shiftingPower = byName["Shifting Power"] and 1 or 0,
    predStrikes = num("Predatory Strikes", "by (%d+)%% of your level"),
    sharpClaws = num("Sharpened Claws", "by (%d+)%%"),
    lotp = num("Leader of the Pack", "by (%d+)%%"),
  }
end

