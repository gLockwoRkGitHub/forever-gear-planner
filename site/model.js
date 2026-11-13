// Level model: how fast each character kills a typical mob at a given level, from their talents, their
// character sheet and the ability ranks in the game data. Leveling fights are short (5–10 sec), so every fight
// starts with all cooldowns ready (and a cat with full energy). Stat weights are the extra kill speed from one
// more point of a stat, counted in Strength points. Analytic (expected values, no dice), so it is instant.
//
// Calibrated with Koda's combat log (10 Nov 2026, level 33 vs Daggerspine Sirens, level 31–32, before that day's hotfix):
//   melee, Windfury and Stormstrike lose about 10% to armor; Earth Shock does not grow with level
//   (131–140, x1.2 after Stormstrike); Stormstrike hit about 6% harder than its weapon damage.
// Hotfix 10 Nov 2026: Stormstrike 100% weapon damage and 8 sec cooldown (was 150%, 6 sec); Mental Dexterity
// 33/66/100% of Intellect (was 50/100/150%); Windfury Weapon and Windfury Totem both proc on the same attacks.
// The values come from data/mechanics.json (scripts/extract_mechanics.py applies the hotfix to the game tables).
// Calibrated with Koda's advanced combat log (13 Nov 2026, level 35, 107 solo kills, after the hotfix): typical
//   quest mobs are 2 levels below you, have 1.3x the Classic health from QuestieDB and ~1,200-1,600 armor
//   (level 30-37, ~28% physical reduction); Stormstrike hits 1.04x its weapon damage; Windfury Totem was up
//   in about a third of the fights. Model vs log: kill 12.5 vs 12.6 sec, same damage split within 3 points.
window.LevelModel = (function () {
  "use strict";
  const MECH = window.MECH || {};
  const CAL = { stormstrike: 1.04, wfTotemUptime: 0.33, hpScale: 1.3 };
  const SS = Object.assign({ pct: 100, cd: 8, nature: 20 }, (MECH.stormstrike || [])[0] || {});

  // --- helpers ----------------------------------------------------------------------------
  function talent(talents, name) { return (talents || []).find((t) => t.n === name) || null; }
  function tnum(talents, name, re) {
    const t = talent(talents, name);
    const m = t && re.exec(t.d || "");
    return m ? parseFloat(m[1]) : 0;
  }
  function hitFromTalents(talents) {
    return (talents || []).reduce((s, t) => { const m = /chance to hit by (\d+(?:\.\d+)?)%/i.exec(t.d || ""); return s + (m ? +m[1] : 0); }, 0);
  }
  function rankAt(list, L) { let r = null; (list || []).forEach((x) => { if (x.lv <= L) r = x; }); return r; }
  // Mental Dexterity in % of Intellect: from the talent rank (hotfix values), else from its tooltip text
  function mentalDexterity(tal) {
    const t = talent(tal, "Mental Dexterity");
    if (!t) return 0;
    const table = MECH.mentalDexterity || [33, 66, 100], r = +t.r || 0;
    if (r >= 1 && r <= table.length) return table[r - 1];
    const m = /equal to (\d+)%/.exec(t.d || "");
    return m ? +m[1] : 0;
  }
  function scaled(base, perLevel, lv, max, L) { return base + (perLevel || 0) * Math.max(0, Math.min(L, max || L) - lv); }
  // Questing mobs: median 2 levels below you in Koda's combat log.
  function mobLevel(L) { return Math.max(1, L - 2); }
  function mobHp(L) {
    const t = MECH.mobHp || {}, m = mobLevel(L);
    if (t[m]) return t[m] * CAL.hpScale;                                   // Forever mobs: 1.3x Classic health
    return CAL.hpScale * Math.max(60, 0.6 * m * m + 18 * m);
  }
  // Armor of normal mobs, fitted to the combat log (level 30: ~1,200, level 37: ~1,600).
  function mobArmor(L) { return 1150 * Math.pow(mobLevel(L) / 30, 1.2); }
  function physMult(L) { const a = mobArmor(L); return 1 - a / (a + 400 + 85 * L); }
  // Attack table, mob fought from the front (solo questing): 5% miss, dodge and parry.
  function avoidance(hitPct) {
    const miss = Math.max(0, 0.05 - hitPct / 100), dodge = 0.05, parry = 0.05;
    return { miss, dodge, parry, land: 1 - miss - dodge - parry };
  }
  // Uses of an ability with cooldown `cd`, first used at `start`, in a fight of `T` seconds (smooth).
  function uses(T, start, cd) { return T <= start ? Math.max(0, T / Math.max(start, 0.5)) * 0.5 : 1 + (T - start - cd > 0 ? (T - start - cd) / cd : 0); }

  // --- Enhancement Shaman: damage dealt in the first T seconds of a fight ---------------------
  // Stats: ap, crit (%), hit (%), sp, spellCrit (%), dodge/parry (%); weapon {min, max, speed}.
  // Windfury Totem procs alongside Windfury Weapon; it was down in about a third of the fights in the log.
  function shamanParts(L, s, tal, w, T) {
    const flurry = tnum(tal, "Flurry", /by (\d+(?:\.\d+)?)%/) / 100;
    const elemW = tnum(tal, "Elemental Weapons", /Windfury Weapon effect by (\d+)%/) / 100;
    const impWT = tnum(tal, "Improved Weapon Totems", /Windfury Totem by (\d+)%/) / 100;
    const storm = !!talent(tal, "Stormstrike");
    const resetPct = tnum(tal, "Improved Stormstrike", /(\d+)% chance to reset/) / 100;
    const t = avoidance(s.hit);
    const crit = Math.min(1, s.crit / 100);
    const speed = w.speed || 2;
    const wAvg = ((w.min || 0) + (w.max || 0)) / 2;
    const swing = wAvg + s.ap / 14 * speed;
    const whiteCrit = Math.min(crit, t.land), whiteMult = (t.land - whiteCrit) + 2 * whiteCrit;
    const yellowMult = t.land * (1 + crit);
    const flurryUp = flurry ? 1 - Math.pow(1 - whiteCrit, 3) : 0;
    const phys = physMult(L);
    const swings = T / (speed / (1 + flurry * flurryUp));                 // log: about 1.8 swings per 6 sec fight
    let ssUses = storm ? uses(T, 0, SS.cd) : 0;                           // Stormstrike opens, then on cooldown
    if (storm && resetPct) {                                              // Improved Stormstrike: reset on dodge/parry
      const avoid = ((s.dodge || 0) + (s.parry || 0)) / 100;
      ssUses += resetPct * avoid * (T / 2) * Math.min(1, T / SS.cd);      // mob swings every ~2 sec
    }
    const esr = rankAt(MECH.earthShock, L);
    const esUses = esr ? uses(T, 1.5, 6) : 0;                             // after the global cooldown
    const out = { "Auto attacks": swings * swing * whiteMult * phys, "Windfury": 0, "Windfury Totem": 0, "Stormstrike": 0, "Earth Shock": 0 };
    out.Stormstrike = ssUses * SS.pct / 100 * swing * CAL.stormstrike * yellowMult * phys;
    const procs = 0.2 * t.land * (swings + ssUses);                       // 20% per landed hit, each effect rolls
    const extra = (bonusAp) => (wAvg + (s.ap + bonusAp) / 14 * speed) * whiteMult * phys;
    const wfr = L >= 30 ? rankAt(MECH.windfury, L) : null;
    if (wfr) {
      const bonusAp = scaled(wfr.ap, wfr.perLevel, wfr.lv, wfr.max, L) * (1 + elemW);
      out.Windfury = procs * (wfr.attacks || 1) * extra(bonusAp);
    }
    const wft = rankAt(MECH.windfuryTotem, L);
    if (wft) {
      const bonusAp = scaled(wft.ap, wft.perLevel, wft.lv, wft.max, L) * (1 + impWT);
      out["Windfury Totem"] = CAL.wfTotemUptime * procs * (wft.attacks || 1) * extra(bonusAp);
    }
    if (esr) {
      const dmg = esr.base * 1.04 + (esr.coef || 0) * (s.sp || 0);        // no level scaling (combat log)
      const spellCrit = Math.min(1, (s.spellCrit || 0) / 100);
      out["Earth Shock"] = esUses * dmg * (storm ? 1 + SS.nature / 100 : 1) * 0.96 * (1 + 0.5 * spellCrit);
    }
    return out;
  }

  // --- Feral Druid, Cat Form: damage in the first T seconds --------------------------------
  // Assumption: in Forever, the cat's "normal damage" is the weapon's DPS per 1.0 sec swing plus AP / 14.
  // Fights start with 100 energy; Rake first, Claw to build combo points, Ferocious Bite at 5 points.
  function catParts(L, s, tal, w, T) {
    const bloodFrenzy = tnum(tal, "Blood Frenzy", /Combo Points have a (\d+)% chance/) / 100;
    const t = avoidance(s.hit);
    const crit = Math.min(1, s.crit / 100);
    const normal = (w.dps || 0) + s.ap / 14;
    const phys = physMult(L);
    const whiteCrit = Math.min(crit, t.land), whiteMult = (t.land - whiteCrit) + 2 * whiteCrit;
    const yellowMult = t.land * (1 + crit);
    const out = { "Auto attacks": T * normal * whiteMult * phys, "Rake": 0, "Claw": 0, "Ferocious Bite": 0 };
    const claw = rankAt(MECH.claw, L);
    if (!claw) return out;
    let energy = 100 + 10 * T;
    if (talent(tal, "Shifting Power")) energy += 40 * uses(T, 1, 8);
    const cpPerHit = t.land * (1 + crit * bloodFrenzy);
    const rake = rankAt(MECH.rake, L), bite = rankAt(MECH.bite, L);
    let builders = 0;
    if (rake) {
      const ticks = Math.min(3, T / rake.period);
      out.Rake = rake.direct * yellowMult * phys + rake.tick * ticks * t.land;   // bleed ignores armor
      energy -= rake.energy; builders += 1;
    }
    // remaining energy: Claws, plus one Bite per 5 combo points
    const biteShare = bite ? cpPerHit / 5 : 0;
    const n = Math.max(0, energy / (claw.energy + biteShare * bite.energy));
    out.Claw = n * (normal * claw.pct / 100 + claw.flat) * yellowMult * phys;
    if (bite) {
      const bites = (builders + n) * biteShare;
      out["Ferocious Bite"] = bites * (bite.base + bite.perCp * 5 + 0.15 * s.ap) * yellowMult * phys;
    }
    return out;
  }

  function sum(o) { return Object.values(o).reduce((a, b) => a + b, 0); }
  // Fight length: the T at which the damage dealt reaches the mob's health.
  function fight(ctx, s, w) {
    const H = mobHp(ctx.level);
    const parts = (T) => ctx.kind === "shaman" ? shamanParts(ctx.level, s, ctx.tal, w, T) : catParts(ctx.level, s, ctx.tal, w, T);
    let lo = 0.2, hi = 240;
    if (sum(parts(hi)) < H) return { T: hi, H, parts: parts(hi) };
    for (let i = 0; i < 40; i++) { const mid = (lo + hi) / 2; if (sum(parts(mid)) >= H) hi = mid; else lo = mid; }
    return { T: hi, H, parts: parts(hi) };
  }

  // --- character state from the sheet and talents ------------------------------------------
  function weaponOf(gear) {
    const w = gear && gear.items ? gear.items.find((e) => e.slot === "Two-Hand") : null;
    if (!w) return { min: 0, max: 0, speed: 2, dps: 0 };
    const extra = /Weapon Damage \+(\d+)/.exec(w.ench || "");
    const add = extra ? +extra[1] : 0;
    const min = (w.dmgMin || (w.dps || 0) * (w.speed || 2) * 0.85) + add;
    const max = (w.dmgMax || (w.dps || 0) * (w.speed || 2) * 1.15) + add;
    return { min, max, speed: w.speed || 2, dps: (min + max) / 2 / (w.speed || 2) };
  }
  function gearSum(gear, key) { return (gear && gear.items || []).reduce((s, e) => s + ((e.st || {})[key] || 0), 0); }

  // Everything the model needs for one character, or null when the data is missing.
  function context(key, gear, level) {
    if (!gear || !gear.sheet || !gear.talents) return null;
    const sh = gear.sheet, tal = gear.talents, curLevel = gear.level || level;
    const s = { str: sh.str, agi: sh.agi, int: sh.int, ap: sh.ap, crit: sh.crit, spellCrit: sh.spellCrit || 0, sp: sh.sp || 0,
      dodge: sh.dodge || 0, parry: sh.parry || 0, hit: gearSum(gear, "hit") + hitFromTalents(tal) };
    let agiPerCrit, kind;
    if (key === "shaman") {
      kind = "shaman";
      const talentCrit = tnum(tal, "Thundering Strikes", /by (\d+)%/);
      agiPerCrit = sh.agi / Math.max(0.5, sh.crit - talentCrit - 1.7);         // base melee crit 1.7%
    } else {
      kind = "cat";
      if (level < 20) return null;                                             // Cat Form from level 20
      agiPerCrit = sh.agi / Math.max(0.5, sh.crit - 0.9);                       // caster-form sheet, base crit 0.9%
      // Cat Form: +12 AP plus Agility; Predatory Strikes: % of level; Sharpened Claws and Leader of the Pack: crit
      s.ap += 12 + sh.agi + tnum(tal, "Predatory Strikes", /by (\d+)% of your level/) / 100 * level;
      s.crit += tnum(tal, "Sharpened Claws", /by (\d+)%/) + (talent(tal, "Leader of the Pack") ? tnum(tal, "Leader of the Pack", /by (\d+)%/) : 0);
    }
    if (!isFinite(agiPerCrit) || agiPerCrit < 4 || agiPerCrit > 60) agiPerCrit = 20 * curLevel / 60;
    agiPerCrit *= level / curLevel;                                            // the ratio grows with level
    return { key, kind, level, s, tal, w: weaponOf(gear), agiPerCrit,
      md: mentalDexterity(tal) / 100, ak: tnum(tal, "Ancestral Knowledge", /Intellect by (\d+)%/) / 100 };
  }

  // Character stats after adding item stats `d` (str, agi, int, ap, feralAp, crit, hit, sp, natureSp).
  function withStats(ctx, d) {
    const s = Object.assign({}, ctx.s);
    const str = d.str || 0, agi = d.agi || 0, int = (d.int || 0) * (1 + ctx.ak);
    s.ap += 2 * str + (d.ap || 0);
    if (ctx.kind === "shaman") s.ap += ctx.md * int;
    else s.ap += agi + (d.feralAp || 0);                      // Cat Form: 1 AP per Agility
    s.crit += agi / ctx.agiPerCrit + (d.crit || 0);
    s.hit += d.hit || 0;
    s.sp += (d.sp || 0) + (ctx.kind === "shaman" ? (d.natureSp || 0) : 0);
    return s;
  }

  const STEP = { str: 10, agi: 10, int: 10, ap: 20, feralAp: 20, crit: 1, hit: 1, sp: 20, natureSp: 20 };
  // Weights in Strength points (kill speed = 1 / fight length), plus a weapon valuation and the fight breakdown.
  function weights(ctx) {
    const base = fight(ctx, ctx.s, ctx.w), speedOf = (f) => 1 / f.T;
    const per = {};
    Object.keys(STEP).forEach((k) => {
      per[k] = (speedOf(fight(ctx, withStats(ctx, { [k]: STEP[k] }), ctx.w)) - speedOf(base)) / STEP[k];
    });
    const unit = per.str || 1;
    const w = {};
    Object.keys(per).forEach((k) => { w[k] = Math.max(0, per[k] / unit); });
    if (ctx.kind !== "shaman") w.sp = w.natureSp = 0;
    if (ctx.kind === "shaman") w.feralAp = 0;
    const zero = speedOf(fight(ctx, ctx.s, { min: 0, max: 0, speed: 2, dps: 0 }));
    return {
      w, unit, main: "str", fight: base, dps: base.H / base.T, mobLevel: mobLevel(ctx.level),
      detail: { total: sum(base.parts), parts: base.parts },
      // a two-hander's worth: kill speed with it against no weapon, in Strength points
      weapon(it) {
        const add = (it.st && it.st.wpnDmg) || 0;
        const spd = it.speed || 2;
        const min = (it.dmgMin || it.dps * spd * 0.85) + add, max = (it.dmgMax || it.dps * spd * 1.15) + add;
        return (speedOf(fight(ctx, ctx.s, { min, max, speed: spd, dps: (min + max) / 2 / spd })) - zero) / unit;
      }
    };
  }

  return { context, weights, mobArmor, physMult, mobHp, mobLevel, mentalDexterity };
})();
