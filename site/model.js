// Level model: expected damage per second of the two characters at a given level, from their talents,
// their character sheet and the ability ranks in the game data. Stat weights are the extra damage of one
// more point of each stat, expressed in points of the main stat (Shaman: Strength, Druid: Agility).
// Deliberately analytic (expected values, no dice), so it runs instantly for every level.
window.LevelModel = (function () {
  "use strict";
  const MECH = window.MECH || {};

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
  function scaled(base, perLevel, lv, max, L) { return base + (perLevel || 0) * Math.max(0, Math.min(L, max || L) - lv); }
  // Normal mobs: armor grows with level (rough fit of Classic values); physical damage taken after armor.
  function mobArmor(L) { return Math.max(20, 57 * L - 400); }
  function physMult(L) { const a = mobArmor(L); return 1 - a / (a + 400 + 85 * L); }
  // Attack table against a mob of your level, fought from the front (solo questing): 5% miss, dodge and parry.
  function avoidance(hitPct) {
    const miss = Math.max(0, 0.05 - hitPct / 100), dodge = 0.05, parry = 0.05;
    return { miss, dodge, parry, land: 1 - miss - dodge - parry };
  }

  // --- Enhancement Shaman -------------------------------------------------------------------
  // Stats: str, agi, int, ap (extra AP), crit (%), hit (%), sp; weapon {min, max, speed}.
  function shamanDps(L, s, tal, w, detail) {
    const flurry = tnum(tal, "Flurry", /by (\d+(?:\.\d+)?)%/) / 100;
    const elemW = tnum(tal, "Elemental Weapons", /Windfury Weapon effect by (\d+)%/) / 100;
    const storm = !!talent(tal, "Stormstrike");
    const t = avoidance(s.hit);
    const crit = Math.min(1, s.crit / 100);
    const speed = w.speed || 2;
    const wAvg = ((w.min || 0) + (w.max || 0)) / 2;
    const swing = wAvg + s.ap / 14 * speed;
    const whiteCrit = Math.min(crit, t.land), whiteHit = t.land - whiteCrit;
    const whiteMult = whiteHit + 2 * whiteCrit;               // one-roll table for auto attacks
    const yellowMult = t.land * (1 + crit);                    // two rolls for abilities: land, then crit
    const flurryUp = flurry ? 1 - Math.pow(1 - whiteCrit, 3) : 0;
    const swingsPerSec = (1 / speed) * (1 + flurry * flurryUp);
    const ssPerSec = storm ? 1 / 6 : 0;                       // Stormstrike: 6 sec cooldown in Forever
    const phys = physMult(L);
    const white = swingsPerSec * swing * whiteMult * phys;
    const ss = ssPerSec * 1.5 * swing * yellowMult * phys;     // 150% weapon damage
    let wf = 0;
    const wfr = L >= 30 ? rankAt(MECH.windfury, L) : null;
    if (wfr) {
      const bonusAp = scaled(wfr.ap, wfr.perLevel, wfr.lv, wfr.max, L) * (1 + elemW);
      const procsPerSec = 0.2 * t.land * (swingsPerSec + ssPerSec);   // 20% per landed hit
      wf = procsPerSec * (wfr.attacks || 1) * (wAvg + (s.ap + bonusAp) / 14 * speed) * whiteMult * phys;
    }
    let es = 0;
    const esr = rankAt(MECH.earthShock, L);
    if (esr) {
      const dmg = scaled(esr.base, esr.perLevel, esr.lv, esr.max, L) * 1.04 + (esr.coef || 0) * (s.sp || 0);
      const spellCrit = Math.min(1, (s.spellCrit || 0) / 100);
      es = dmg * (storm ? 1.2 : 1) * 0.96 * (1 + 0.5 * spellCrit) / 6;   // every 6 sec (shock cooldown), 4% spell miss
    }
    const total = white + ss + wf + es;
    if (detail) return { total, parts: { "Auto attacks": white, "Windfury": wf, "Stormstrike": ss, "Earth Shock": es } };
    return total;
  }

  // --- Feral Druid, Cat Form ----------------------------------------------------------------
  // Assumption: in Forever, the cat's "normal damage" is the weapon's DPS per 1.0 sec swing plus AP / 14.
  function catDps(L, s, tal, w, detail) {
    const bloodFrenzy = tnum(tal, "Blood Frenzy", /Combo Points have a (\d+)% chance/) / 100;
    const shredRed = tnum(tal, "Shredding Attacks", /Shred ability by (\d+)/);
    const t = avoidance(s.hit);
    const crit = Math.min(1, s.crit / 100);
    const normal = (w.dps || 0) + s.ap / 14;                   // per 1.0 sec cat swing
    const phys = physMult(L);
    const whiteCrit = Math.min(crit, t.land), whiteMult = (t.land - whiteCrit) + 2 * whiteCrit;
    const yellowMult = t.land * (1 + crit);
    const white = normal * whiteMult * phys;
    let energy = 10;                                           // per second
    if (talent(tal, "Shifting Power")) energy += 40 / 8;
    const claw = rankAt(MECH.claw, L);
    if (!claw) return detail ? { total: white, parts: { "Auto attacks": white } } : white;
    const builder = { cost: claw.energy, dmg: (normal * claw.pct / 100 + claw.flat) * yellowMult * phys };
    void shredRed;  // solo you face the mob, so Claw; Shred needs you behind it
    const cpPerHit = t.land * (1 + crit * bloodFrenzy);       // extra combo point on crit (Blood Frenzy)
    const rake = rankAt(MECH.rake, L), rip = rankAt(MECH.rip, L);
    // one cycle: Rake (if known), builders up to 5 combo points, Rip
    let builders = 5 / cpPerHit, cost = 0, dmg = 0;
    const parts = { "Auto attacks": white, "Claw": 0, "Rake": 0, "Rip": 0 };
    if (rake) {
      const rd = (rake.direct * yellowMult * phys + rake.tick * 3 * t.land);   // bleed ignores armor
      cost += rake.energy; dmg += rd; parts.Rake = rd; builders -= 1;
    }
    builders = Math.max(0, builders);
    cost += builders * builder.cost; dmg += builders * builder.dmg; parts.Claw = builders * builder.dmg;
    if (rip) {
      const rd = ((rip.tick + rip.tickPerCp * 5) * (12 / rip.period) + 0.24 * s.ap) * t.land;   // 5 points, bleed
      cost += rip.energy; dmg += rd; parts.Rip = rd;
    }
    const cycle = cost / energy;
    Object.keys(parts).forEach((k) => { if (k !== "Auto attacks") parts[k] = parts[k] / cycle; });
    const total = white + dmg / cycle;
    return detail ? { total, parts } : total;
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
      hit: gearSum(gear, "hit") + hitFromTalents(tal) };
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
      md: tnum(tal, "Mental Dexterity", /equal to (\d+)%/) / 100, ak: tnum(tal, "Ancestral Knowledge", /Intellect by (\d+)%/) / 100 };
  }

  function dpsOf(ctx, s, w, detail) {
    return ctx.kind === "shaman" ? shamanDps(ctx.level, s, ctx.tal, w, detail) : catDps(ctx.level, s, ctx.tal, w, detail);
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
  // Weights in points of the main stat, plus a weapon valuation and the damage breakdown.
  function weights(ctx) {
    const base = dpsOf(ctx, ctx.s, ctx.w);
    const per = {};
    Object.keys(STEP).forEach((k) => {
      per[k] = (dpsOf(ctx, withStats(ctx, { [k]: STEP[k] }), ctx.w) - base) / STEP[k];
    });
    const main = "str";                                         // weights in Strength points for both
    const unit = per[main] || 1;
    const w = {};
    Object.keys(per).forEach((k) => { w[k] = Math.max(0, per[k] / unit); });
    if (ctx.kind !== "shaman") w.sp = w.natureSp = 0;
    if (ctx.kind === "shaman") w.feralAp = 0;
    const zero = dpsOf(ctx, ctx.s, { min: 0, max: 0, speed: 2, dps: 0 });
    return {
      w, unit, main, dps: base,
      detail: dpsOf(ctx, ctx.s, ctx.w, true),
      // a two-hander's worth: its damage (and speed) against no weapon, in main-stat points
      weapon(it) {
        const add = (it.st && it.st.wpnDmg) || 0;
        const spd = it.speed || 2;
        const min = (it.dmgMin || it.dps * spd * 0.85) + add, max = (it.dmgMax || it.dps * spd * 1.15) + add;
        return (dpsOf(ctx, ctx.s, { min, max, speed: spd, dps: (min + max) / 2 / spd }) - zero) / unit;
      }
    };
  }

  return { context, weights, mobArmor, physMult };
})();
