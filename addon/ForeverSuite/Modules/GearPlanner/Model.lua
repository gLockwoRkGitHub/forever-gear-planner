-- Level model, a port of the website's site/model.js: how fast the character kills a typical mob at a given
-- level, from talents, character sheet and the ability ranks and mob health in the game data. Every fight
-- starts with cooldowns ready (a cat with full energy). Stat weights are the extra kill speed of one more
-- point of each stat, counted in Strength points. Keep both files in step (addon/tests/parity.js checks it).
--
-- Talents arrive as numbers (from the website import or the game's talent tooltips):
--   flurry, elemW, impSS, impWT, thunder, md, ak, hit, bloodFrenzy, predStrikes, sharpClaws, lotp  (percent values)
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
local function T_(tal, k) return (tal and tonumber(tal[k])) or 0 end

-- Questing mobs are usually a level below you; their health from the game data (median per level).
function M.mobLevel(L) return max(1, L - 1) end
function M.mobHp(L)
  local t, m = mech().mobHp or {}, M.mobLevel(L)
  local v = t[m] or t[tostring(m)]
  if v then return v end
  return max(60, 0.6 * m * m + 18 * m)
end
-- Armor: fitted to Koda's combat log (about 10% physical reduction around level 32).
function M.mobArmor(L) return 11.3 * M.mobLevel(L) end
function M.physMult(L) local a = M.mobArmor(L); return 1 - a / (a + 400 + 85 * L) end
-- Attack table, mob fought from the front (solo questing): 5% miss, dodge and parry.
local function avoidance(hitPct)
  local miss = max(0, 0.05 - hitPct / 100)
  return { miss = miss, dodge = 0.05, parry = 0.05, land = 1 - miss - 0.05 - 0.05 }
end
-- Uses of an ability with cooldown `cd`, first used at `start`, in a fight of `T` seconds (smooth).
local function uses(T, start, cd)
  if T <= start then return max(0, T / max(start, 0.5)) * 0.5 end
  return 1 + (T - start - cd > 0 and (T - start - cd) / cd or 0)
end
local CAL = { stormstrike = 1.06 }
-- Stormstrike from the game data (the data build applies the hotfix of 10 Nov 2026: 100%, 8 sec)
local function stormstrike()
  local r = (mech().stormstrike or {})[1] or {}
  return r.pct or 100, r.cd or 8, r.nature or 20
end

-- --- Enhancement Shaman: damage dealt in the first T seconds of a fight ------------------------
-- Calibrated with Koda's combat log (level 33, before the hotfix of 10 Nov 2026): Earth Shock does not grow
-- with level, Stormstrike hit about 6% harder than its weapon damage, Improved Stormstrike resets on
-- dodge/parry. Since the hotfix, Windfury Weapon and Windfury Totem both roll on every hit; the totem is
-- assumed to be down for every fight once learned.
local function shamanParts(L, s, tal, w, T)
  local flurry, elemW, storm = T_(tal, "flurry") / 100, T_(tal, "elemW") / 100, T_(tal, "storm") > 0
  local resetPct, impWT = T_(tal, "impSS") / 100, T_(tal, "impWT") / 100
  local ssPct, ssCd, ssNature = stormstrike()
  local t = avoidance(s.hit)
  local crit = min(1, s.crit / 100)
  local speed = w.speed or 2
  local wAvg = ((w.min or 0) + (w.max or 0)) / 2
  local swing = wAvg + s.ap / 14 * speed
  local whiteCrit = min(crit, t.land)
  local whiteMult = (t.land - whiteCrit) + 2 * whiteCrit
  local yellowMult = t.land * (1 + crit)
  local flurryUp = flurry > 0 and (1 - (1 - whiteCrit) ^ 3) or 0
  local phys = M.physMult(L)
  local swings = T / (speed / (1 + flurry * flurryUp))
  local ssUses = storm and uses(T, 0, ssCd) or 0                        -- Stormstrike opens, then on cooldown
  if storm and resetPct > 0 then                                        -- Improved Stormstrike: reset on dodge/parry
    local avoid = ((s.dodge or 0) + (s.parry or 0)) / 100
    ssUses = ssUses + resetPct * avoid * (T / 2) * min(1, T / ssCd)     -- mob swings every ~2 sec
  end
  local esr = rankAt(mech().earthShock, L)
  local esUses = esr and uses(T, 1.5, 6) or 0                           -- after the global cooldown
  local white = swings * swing * whiteMult * phys
  local ss = ssUses * ssPct / 100 * swing * CAL.stormstrike * yellowMult * phys
  local procs = 0.2 * t.land * (swings + ssUses)                        -- 20% per landed hit, each effect rolls
  local function extra(bonusAp) return (wAvg + (s.ap + bonusAp) / 14 * speed) * whiteMult * phys end
  local wf, wft = 0, 0
  local wfr = L >= 30 and rankAt(mech().windfury, L) or nil
  if wfr then
    wf = procs * (wfr.attacks or 1) * extra(scaled(wfr.ap, wfr.perLevel, wfr.lv, wfr.max, L) * (1 + elemW))
  end
  local wtr = rankAt(mech().windfuryTotem, L)
  if wtr then
    wft = procs * (wtr.attacks or 1) * extra(scaled(wtr.ap, wtr.perLevel, wtr.lv, wtr.max, L) * (1 + impWT))
  end
  local es = 0
  if esr then
    local dmg = esr.base * 1.04 + (esr.coef or 0) * (s.sp or 0)         -- no level scaling (combat log)
    local spellCrit = min(1, (s.spellCrit or 0) / 100)
    es = esUses * dmg * (storm and (1 + ssNature / 100) or 1) * 0.96 * (1 + 0.5 * spellCrit)
  end
  return { { "Auto attacks", white }, { "Windfury", wf }, { "Windfury Totem", wft }, { "Stormstrike", ss }, { "Earth Shock", es } }
end

-- --- Feral Druid, Cat Form: damage in the first T seconds ----------------------------------------
-- The cat's "normal damage" is assumed to be the weapon's DPS per 1.0 sec swing plus AP / 14. Fights start
-- with 100 energy; Rake first, Claw to build combo points, Ferocious Bite at 5 points.
local function catParts(L, s, tal, w, T)
  local bloodFrenzy = T_(tal, "bloodFrenzy") / 100
  local t = avoidance(s.hit)
  local crit = min(1, s.crit / 100)
  local normal = (w.dps or 0) + s.ap / 14
  local phys = M.physMult(L)
  local whiteCrit = min(crit, t.land)
  local whiteMult = (t.land - whiteCrit) + 2 * whiteCrit
  local yellowMult = t.land * (1 + crit)
  local white = T * normal * whiteMult * phys
  local pRake, pClaw, pBite = 0, 0, 0
  local claw = rankAt(mech().claw, L)
  if claw then
    local energy = 100 + 10 * T
    if T_(tal, "shiftingPower") > 0 then energy = energy + 40 * uses(T, 1, 8) end
    local cpPerHit = t.land * (1 + crit * bloodFrenzy)
    local rake, bite = rankAt(mech().rake, L), rankAt(mech().bite, L)
    local builders = 0
    if rake then
      local ticks = min(3, T / rake.period)
      pRake = rake.direct * yellowMult * phys + rake.tick * ticks * t.land   -- bleed ignores armor
      energy = energy - rake.energy
      builders = builders + 1
    end
    local biteShare = bite and cpPerHit / 5 or 0
    local n = max(0, energy / (claw.energy + biteShare * (bite and bite.energy or 0)))
    pClaw = n * (normal * claw.pct / 100 + claw.flat) * yellowMult * phys
    if bite then
      local bites = (builders + n) * biteShare
      pBite = bites * (bite.base + bite.perCp * 5 + 0.15 * s.ap) * yellowMult * phys
    end
  end
  return { { "Auto attacks", white }, { "Rake", pRake }, { "Claw", pClaw }, { "Ferocious Bite", pBite } }
end

local function sum(parts)
  local total = 0
  for _, p in ipairs(parts) do total = total + p[2] end
  return total
end

-- Fight length: the T at which the damage dealt reaches the mob's health.
local function fight(ctx, s, w)
  local H = M.mobHp(ctx.level)
  local partsOf = ctx.kind == "shaman" and shamanParts or catParts
  local function parts(T) return partsOf(ctx.level, s, ctx.tal, w, T) end
  local lo, hi = 0.2, 240
  if sum(parts(hi)) < H then return { T = hi, H = H, parts = parts(hi) } end
  for _ = 1, 40 do
    local mid = (lo + hi) / 2
    if sum(parts(mid)) >= H then hi = mid else lo = mid end
  end
  return { T = hi, H = H, parts = parts(hi) }
end

-- --- character state -------------------------------------------------------------------------
local function weaponOf(items)
  local w
  for _, e in ipairs(items or {}) do if e.slot == "Two-Hand" then w = e.it; break end end
  if not w then return { min = 0, max = 0, speed = 2, dps = 0 } end
  local spd = w.speed or 2
  local add = w.enchDmg or 0                                -- permanent "Weapon Damage +N" enchant
  local lo = (w.dmgMin or (w.dps or 0) * spd * 0.85) + add
  local hi = (w.dmgMax or (w.dps or 0) * spd * 1.15) + add
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
    sp = sh.sp or 0, dodge = sh.dodge or 0, parry = sh.parry or 0, hit = gearSum(input.items, "hit") + T_(tal, "hit") }
  local agiPerCrit, kind
  if key == "shaman" then
    kind = "shaman"
    agiPerCrit = sh.agi / max(0.5, sh.crit - T_(tal, "thunder") - 1.7)          -- base melee crit 1.7%
  else
    kind = "cat"
    if level < 20 then return nil end                                         -- Cat Form from level 20
    agiPerCrit = sh.agi / max(0.5, sh.crit - 0.9)                              -- caster-form sheet, base crit 0.9%
    s.ap = s.ap + 12 + sh.agi + T_(tal, "predStrikes") / 100 * level
    s.crit = s.crit + T_(tal, "sharpClaws") + T_(tal, "lotp")
  end
  if not finite(agiPerCrit) or agiPerCrit < 4 or agiPerCrit > 60 then agiPerCrit = 20 * curLevel / 60 end
  agiPerCrit = agiPerCrit * level / curLevel
  return { key = key, kind = kind, level = level, s = s, tal = tal, w = weaponOf(input.items), agiPerCrit = agiPerCrit,
    md = T_(tal, "md") / 100, ak = T_(tal, "ak") / 100 }
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

-- Weights in Strength points (kill speed = 1 / fight length), plus a weapon valuation and the fight breakdown.
function M.weights(ctx)
  local base = fight(ctx, ctx.s, ctx.w)
  local function speedOf(f) return 1 / f.T end
  local per = {}
  for k, step in pairs(STEP) do
    per[k] = (speedOf(fight(ctx, withStats(ctx, { [k] = step }), ctx.w)) - speedOf(base)) / step
  end
  local unit = per.str
  if not unit or unit == 0 then unit = 1 end
  local w = {}
  for k, v in pairs(per) do w[k] = max(0, v / unit) end
  if ctx.kind ~= "shaman" then w.sp, w.natureSp = 0, 0 end
  if ctx.kind == "shaman" then w.feralAp = 0 end
  local zero = speedOf(fight(ctx, ctx.s, { min = 0, max = 0, speed = 2, dps = 0 }))
  local cache = {}
  return {
    w = w, unit = unit, ctx = ctx, fight = base, dps = base.H / base.T, mobLevel = M.mobLevel(ctx.level),
    detail = { total = sum(base.parts), parts = base.parts },
    -- a two-hander's worth: kill speed with it against no weapon, in Strength points
    weapon = function(it)
      local v = cache[it]
      if v then return v end
      local add = (it.st and it.st.wpnDmg) or 0
      local spd = it.speed or 2
      local lo = (it.dmgMin or (it.dps or 0) * spd * 0.85) + add
      local hi = (it.dmgMax or (it.dps or 0) * spd * 1.15) + add
      v = (speedOf(fight(ctx, ctx.s, { min = lo, max = hi, speed = spd, dps = (lo + hi) / 2 / spd })) - zero) / unit
      cache[it] = v
      return v
    end,
  }
end

-- --- talents from their tooltip text (English client), same rules as model.js -----------------
-- talents: list of { n = name, d = description, r = rank }
function M.talentNumbers(talents)
  local byName, rankOf = {}, {}
  for _, t in ipairs(talents or {}) do byName[t.n] = t.d or ""; rankOf[t.n] = tonumber(t.r) end
  local function num(name, pat)
    local d = byName[name]
    local v = d and d:match(pat)
    return v and tonumber(v) or 0
  end
  -- Mental Dexterity: from the rank (hotfix values in the game data build), else from the tooltip text
  local function mentalDexterity()
    if not byName["Mental Dexterity"] then return 0 end
    local table_, r = mech().mentalDexterity or { 33, 66, 100 }, rankOf["Mental Dexterity"]
    if r and table_[r] then return table_[r] end
    return num("Mental Dexterity", "equal to (%d+)%%")
  end
  local hit = 0
  for _, t in ipairs(talents or {}) do
    local v = (t.d or ""):lower():match("chance to hit by (%d+%.?%d*)%%")
    if v then hit = hit + tonumber(v) end
  end
  return {
    flurry = num("Flurry", "by (%d+%.?%d*)%%"),
    elemW = num("Elemental Weapons", "Windfury Weapon effect by (%d+)%%"),
    impSS = num("Improved Stormstrike", "(%d+)%% chance to reset"),
    storm = byName["Stormstrike"] and 1 or 0,
    thunder = num("Thundering Strikes", "by (%d+)%%"),
    md = mentalDexterity(),
    impWT = num("Improved Weapon Totems", "Windfury Totem by (%d+)%%"),
    ak = num("Ancestral Knowledge", "Intellect by (%d+)%%"),
    hit = hit,
    bloodFrenzy = num("Blood Frenzy", "Combo Points have a (%d+)%% chance"),
    shiftingPower = byName["Shifting Power"] and 1 or 0,
    predStrikes = num("Predatory Strikes", "by (%d+)%% of your level"),
    sharpClaws = num("Sharpened Claws", "by (%d+)%%"),
    lotp = num("Leader of the Pack", "by (%d+)%%"),
  }
end

