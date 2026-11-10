(function () {
  "use strict";
  const DATA = window.GEAR_DATA;
  // Equipped gear and level per character, fetched hourly from the armory or Blizzard's API
  const GEAR = window.GEAR_STATE || null;
  const gearChar = (key) => (GEAR && GEAR.chars && GEAR.chars[key]) || null;
  const charGear = (key) => { const g = gearChar(key); return g && g.items && g.items.length ? g : null; };
  const armoryLevel = (key) => { const g = gearChar(key); return g && g.level ? g.level : null; };
  const charName = (key) => { const g = gearChar(key); return g && g.name ? g.name.split(" ")[0] : null; };
  const SLOT_ORDER = ["Two-Hand", "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket", "Relic"];
  const SOURCES = ["Quest", "Dungeon", "Vendor", "Crafted"];
  const PROFESSIONS = ["Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring"];

  // --- character profiles ---------------------------------------------------------------
  // armor / weapons: allowed item types and the level from which each can be used.
  const PROFILES = {
    shaman: {
      label: "Enhancement Shaman", short: "Enh. Shaman", tag: "Shaman", cls: "Shaman", bit: 64, color: "#2b8cff",
      sub: "Tauren Enhancement Shaman · 2H axes, maces, staves · mail from 40",
      armor: { Misc: 1, Cloth: 1, Leather: 1, Mail: 40, Totem: 1 },
      weapons: { "Two-Handed Axe": 1, "Two-Handed Mace": 1, "Staff": 1 },
      relic: "Totem", profs: ["Enchanting"], level: 34,
      hide: ["feralAp", "def", "dodge"],
      presets: {
        "Enhancement": {
          str: 1.0, agi: 0.4, int: 0.5, sta: 0.15, spi: 0.1, ap: 0.5, feralAp: 0, crit: 10, hit: 8, critR: 0.8, hitR: 0.8,
          exp: 0.8, haste: 0.5, armor: 0.01, def: 0, dodge: 0, sp: 0.2, natureSp: 0.15, dps: 8, slow: 1.5
        }
      }
    },
    druid: {
      label: "Feral Druid", short: "Feral Druid", tag: "Druid", cls: "Druid", bit: 1024, color: "#ff7d0a",
      sub: "Tauren Feral Druid · staves, 2H maces, polearms from 20 · cloth and leather",
      armor: { Misc: 1, Cloth: 1, Leather: 1, Idol: 1 },
      weapons: { "Staff": 1, "Two-Handed Mace": 1, "Polearm": 20 },
      relic: "Idol", profs: [], level: 34,
      hide: ["natureSp"],
      presets: {
        "Cat (DPS)": {
          str: 0.9, agi: 1.0, int: 0.05, sta: 0.2, spi: 0.05, ap: 0.45, feralAp: 0.45, crit: 12, hit: 12, critR: 1.0, hitR: 1.0,
          exp: 1.0, haste: 0.8, armor: 0.02, def: 0.1, dodge: 2, sp: 0, natureSp: 0, dps: 6, slow: 0
        },
        "Bear (tank)": {
          str: 0.3, agi: 0.6, int: 0.02, sta: 1.0, spi: 0.02, ap: 0.15, feralAp: 0.15, crit: 2, hit: 3, critR: 0.2, hitR: 0.3,
          exp: 0.5, haste: 0.2, armor: 0.08, def: 1.2, dodge: 15, sp: 0, natureSp: 0, dps: 1.5, slow: 0
        }
      }
    }
  };
  const WEIGHT_LABELS = {
    str: "Strength", agi: "Agility", int: "Intellect", sta: "Stamina", spi: "Spirit", ap: "Attack Power",
    feralAp: "Feral AP (forms)", crit: "Crit (per %)", hit: "Hit (per %)", critR: "Crit (per point)", hitR: "Hit (per point)",
    exp: "Expertise", haste: "Haste", armor: "Armor", def: "Defense", dodge: "Dodge (per %)", sp: "Spell Power",
    natureSp: "Nature spell dmg", dps: "Weapon DPS", slow: "Slow bonus / 0.1 s"
  };
  const WEIGHT_GROUPS = [
    ["Primary stats", ["str", "agi", "int", "sta", "spi"]],
    ["Offense", ["ap", "feralAp", "crit", "hit", "critR", "hitR", "exp", "haste"]],
    ["Defense", ["armor", "def", "dodge"]],
    ["Spells", ["sp", "natureSp"]],
    ["Weapon", ["dps", "slow"]]
  ];
  const STAT_SHORT = { str: "Str", agi: "Agi", int: "Int", sta: "Sta", spi: "Spi", ap: "AP", feralAp: "Feral AP", sp: "SP",
    natureSp: "Nature SP", crit: "% Crit", hit: "% Hit", hitR: "Hit", critR: "Crit", exp: "Expertise", haste: "Haste",
    def: "Defense", dodge: "% Dodge", wpnDmg: "Wpn Dmg" };

  // --- persisted settings (per-viewer convenience only) -----------------------------------
  const store = {
    get(k, d) { try { const v = localStorage.getItem("fgp_" + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem("fgp_" + k, JSON.stringify(v)); } catch (e) { /* storage unavailable */ } }
  };
  const state = {
    profile: PROFILES[store.get("profile", "shaman")] ? store.get("profile", "shaman") : "shaman",
    slot: SLOT_ORDER.includes(store.get("slot", "All")) ? store.get("slot", "All") : "All",
    topN: store.get("topN", 5)
  };
  const P = () => PROFILES[state.profile];
  // per-character keys; the shaman also reads settings saved by the earlier single-character version
  function pget(k, d) {
    const legacy = state.profile === "shaman" ? store.get(k, d) : d;
    return store.get(state.profile + "_" + k, legacy);
  }
  function pset(k, v) { store.set(state.profile + "_" + k, v); }

  // Settings of any character; the active one lives in `state`, the other is read from storage.
  // Level: what the armory reports, unless it was set by hand since the armory last reported that level.
  function resolveLevel(key, get) {
    const a = armoryLevel(key);
    if (!a) return get("level", PROFILES[key].level);
    const ov = store.get(key + "_levelOverride", null);
    return ov && ov.a === a ? ov.v : a;
  }
  function saveLevel(key, v) {
    const a = armoryLevel(key);
    if (a) store.set(key + "_levelOverride", v === a ? null : { v: v, a: a });
    else store.set(key + "_level", v);
  }
  function longLabel(key) { return (charName(key) ? charName(key) + " · " : "") + PROFILES[key].label; }

  function readProfile(key) {
    const prof = PROFILES[key];
    const get = (k, d) => store.get(key + "_" + k, key === "shaman" ? store.get(k, d) : d);
    const presetNames = Object.keys(prof.presets);
    const preset = presetNames.includes(get("preset", presetNames[0])) ? get("preset", presetNames[0]) : presetNames[0];
    return {
      level: resolveLevel(key, get),
      onlyUp: get("onlyUp", true),
      sources: get("sources", SOURCES.slice()),
      myProfs: get("myProfs", prof.profs.slice()),
      random: get("random", false),
      preset: preset,
      weights: Object.assign({}, prof.presets[preset], get("weights", {}))
    };
  }
  function loadProfile() { Object.assign(state, readProfile(state.profile)); }
  function profileState(key) { return key === state.profile ? state : readProfile(key); }

  const $ = (id) => document.getElementById(id);
  function el(tag, cls, text) { const e = document.createElement(tag); if (cls) e.className = cls; if (text !== undefined) e.textContent = text; return e; }

  // --- character switch -------------------------------------------------------------------
  const sw = $("charSwitch");
  Object.entries(PROFILES).forEach(([key, prof]) => {
    const b = el("button"); b.type = "button"; b.dataset.k = key; b.style.setProperty("--cc", prof.color);
    b.appendChild(el("span", "dot")); b.appendChild(el("span", "lab-long", longLabel(key))); b.appendChild(el("span", "lab-short", charName(key) || prof.short));
    b.addEventListener("click", () => {
      if (state.profile === key) return;
      state.profile = key; store.set("profile", key); applyProfile();
    });
    sw.appendChild(b);
  });

  // --- controls ---------------------------------------------------------------------------
  const slotSel = $("slot");
  ["All"].concat(SLOT_ORDER).forEach((s) => { const o = el("option", "", s === "All" ? "All slots" : s); o.value = s; slotSel.appendChild(o); });
  slotSel.value = SLOT_ORDER.includes(state.slot) ? state.slot : "All";
  slotSel.addEventListener("change", () => { state.slot = slotSel.value; store.set("slot", state.slot); render(); window.scrollTo({ top: 0 }); });
  [3, 5, 10].forEach((n) => {
    const l = el("label", "chip");
    const r = el("input"); r.type = "radio"; r.name = "topN"; r.value = n; r.checked = state.topN === n;
    r.addEventListener("change", () => { state.topN = n; store.set("topN", n); render(); });
    l.appendChild(r); l.appendChild(el("span", "", "Top " + n)); $("topNBox").appendChild(l);
  });

  function chipGroup(box, all, key) {
    box.innerHTML = "";
    all.forEach((name) => {
      const l = el("label", "chip"); l.dataset.k = name;
      const c = el("input"); c.type = "checkbox"; c.checked = state[key].includes(name);
      c.addEventListener("change", () => {
        state[key] = all.filter((x) => x === name ? c.checked : state[key].includes(x));
        pset(key, state[key]); render();
      });
      l.appendChild(c); l.appendChild(el("span", "", name)); box.appendChild(l);
    });
  }
  $("optRandom").addEventListener("change", (e) => { state.random = e.target.checked; pset("random", state.random); render(); });
  $("optOnlyUp").addEventListener("change", (e) => { state.onlyUp = e.target.checked; pset("onlyUp", state.onlyUp); render(); });

  // Filters / weights panels: one open at a time, Escape closes
  const panels = [["btnFilters", "panelFilters"], ["btnWeights", "panelWeights"]];
  function openPanel(id) {
    let any = false;
    panels.forEach(([b, p]) => {
      const open = p === id && $(p).hidden;
      $(p).hidden = !open; $(b).setAttribute("aria-expanded", String(open));
      any = any || open;
    });
    document.body.classList.toggle("sheet-open", any);  // on phones the panel is a full-screen sheet
  }
  panels.forEach(([b, p]) => $(b).addEventListener("click", () => openPanel(p)));
  document.querySelectorAll("[data-close]").forEach((b) => b.addEventListener("click", () => openPanel(null)));
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") openPanel(null); });

  function setLevel(v) {
    v = Math.max(1, Math.min(60, Math.round(+v || 1)));
    state.level = v; $("level").value = v; $("levelRange").value = v; saveLevel(state.profile, v); updateLevelSource(); render();
    if (view === "dungeons") renderDungeons();
  }
  function updateLevelSource() {
    const b = $("lvSrc"), a = armoryLevel(state.profile);
    b.hidden = !a;
    if (!a) return;
    const manual = state.level !== a;
    b.textContent = manual ? "↺ " + a : "live";
    b.disabled = !manual;
    b.title = manual ? "Back to your live level (" + a + ")" : "Your level in the game, updated every hour";
  }
  $("lvSrc").addEventListener("click", () => { const a = armoryLevel(state.profile); if (a) setLevel(a); });
  $("level").addEventListener("change", (e) => setLevel(e.target.value));
  $("levelRange").addEventListener("input", (e) => setLevel(e.target.value));
  $("lvDown").addEventListener("click", () => setLevel(state.level - 1));
  $("lvUp").addEventListener("click", () => setLevel(state.level + 1));
  document.addEventListener("keydown", (e) => {
    if (e.target.tagName === "INPUT" || e.target.tagName === "SELECT" || e.target.tagName === "BUTTON") return;
    if (e.key === "ArrowLeft") setLevel(state.level - 1);
    if (e.key === "ArrowRight") setLevel(state.level + 1);
  });

  // --- stat weights -----------------------------------------------------------------------
  function saveWeights() {
    const base = P().presets[state.preset];
    const diff = {}; Object.keys(state.weights).forEach((k) => { if (state.weights[k] !== base[k]) diff[k] = state.weights[k]; });
    pset("weights", diff); pset("preset", state.preset);
  }
  function buildWeights() {
    const wgrid = $("wgrid"); wgrid.innerHTML = "";
    const presetBox = $("presetBox"); presetBox.innerHTML = "";
    const names = Object.keys(P().presets);
    if (names.length > 1) {
      presetBox.appendChild(el("span", "lbl", "Preset"));
      names.forEach((n) => {
        const b = el("button", "preset", n); b.type = "button"; b.setAttribute("aria-pressed", String(n === state.preset));
        b.addEventListener("click", () => {
          state.preset = n; state.weights = Object.assign({}, P().presets[n]); saveWeights(); buildWeights(); render();
        });
        presetBox.appendChild(b);
      });
    }
    WEIGHT_GROUPS.forEach(([title, keys]) => {
      const shown = keys.filter((k) => !P().hide.includes(k));
      if (!shown.length) return;
      const fs = el("fieldset", "group"); fs.appendChild(el("legend", "lbl", title));
      shown.forEach((k) => {
        const d = el("div", "wrow");
        const l = el("label", "", WEIGHT_LABELS[k]); l.htmlFor = "w_" + k;
        const i = el("input"); i.type = "number"; i.step = "0.05"; i.id = "w_" + k; i.value = state.weights[k];
        i.setAttribute("inputmode", "decimal");
        i.addEventListener("change", () => { state.weights[k] = parseFloat(i.value) || 0; saveWeights(); render(); });
        d.appendChild(l); d.appendChild(i); fs.appendChild(d);
      });
      wgrid.appendChild(fs);
    });
  }
  $("wReset").addEventListener("click", () => { state.weights = Object.assign({}, P().presets[state.preset]); saveWeights(); buildWeights(); render(); });

  function updateSummaries() {
    const src = state.sources.length === SOURCES.length ? "all sources" : (state.sources.length ? state.sources.join(", ") : "no sources");
    const prof = state.myProfs.length ? state.myProfs.join(", ") : "no professions";
    $("filterSum").textContent = "Top " + state.topN + " · " + src + " · " + prof + (state.random ? " · random enchants" : "")
      + (state.onlyUp && charGear(state.profile) ? " · only upgrades" : "");
    const base = P().presets[state.preset];
    const custom = Object.keys(base).some((k) => state.weights[k] !== base[k]);
    const names = Object.keys(P().presets);
    $("weightSum").textContent = (names.length > 1 ? state.preset : "default") + (custom ? " · custom" : "");
  }

  // --- scoring and eligibility ------------------------------------------------------------
  function score(it) { return scoreW(it, state.weights); }
  function scoreW(it, w) {
    let s = 0;
    for (const k in it.st) { if (k !== "wpnDmg" && w[k] !== undefined) s += it.st[k] * w[k]; }
    if (it.dps) {
      const dps = it.dps + (it.st.wpnDmg && it.speed ? it.st.wpnDmg / it.speed : 0);
      s += dps * w.dps + Math.max(0, (it.speed || 0) - 3.0) * 10 * w.slow;
    }
    return s;
  }

  // A source counts when it is enabled, reachable at this level and open to this class.
  // Bind-on-pickup crafts can only be made by the crafter, so they need the profession.
  function srcUsableFor(it, s, level, prof, st, ignoreToggles) {
    if ((!ignoreToggles && !st.sources.includes(s.t)) || s.g > level) return false;
    if (s.t === "Quest" && s.rc && !(s.rc & prof.bit)) return false;
    if (s.t === "Crafted" && it.bop && !st.myProfs.includes(s.n)) return false;
    return true;
  }
  function srcUsable(it, s, level) { return srcUsableFor(it, s, level, P(), state); }

  // Can this character wear the item at this level at all (type, class, professions)?
  function wearable(it, level, prof, st) {
    const minLevel = prof.armor[it.ty] !== undefined ? prof.armor[it.ty] : prof.weapons[it.ty];
    if (minLevel === undefined || level < minLevel) return false;
    if (it.cl && !it.cl.includes(prof.cls)) return false;
    if (it.rnd && !st.random) return false;
    if (it.np && !st.myProfs.includes(it.np.split(" (")[0])) return false;
    return true;
  }
  function eligibleFor(it, level, prof, st) {
    return wearable(it, level, prof, st) && it.src.some((s) => srcUsableFor(it, s, level, prof, st));
  }
  function eligible(it, level) { return eligibleFor(it, level, P(), state); }

  function statLine(it) {
    const parts = [];
    if (it.dps) parts.push(it.dps.toFixed(1) + " DPS · " + (it.speed || 0).toFixed(2) + " speed");
    ["str", "agi", "int", "sta", "spi", "ap", "feralAp", "sp", "natureSp", "hit", "crit", "hitR", "critR", "exp", "haste", "def", "dodge", "wpnDmg"]
      .forEach((k) => { if (it.st[k]) parts.push((it.st[k] > 0 ? "+" : "") + it.st[k] + " " + STAT_SHORT[k]); });
    if (it.st.armor) parts.push(it.st.armor + " Armor");
    return parts.join(", ") || "no stats";
  }

  function sourceText(s, it) {
    if (s.t === "Quest") return s.n + (s.w ? " (" + s.w + ")" : "") + (s.ql ? " · quest lvl " + s.ql : "") + (s.rc ? " · class quest" : "");
    if (s.t === "Dungeon") return s.n + " — " + s.w + (s.dc ? " · " + s.dc + "%" : "");
    if (s.t === "Vendor") return s.n + (s.w ? " — " + s.w : "");
    if (s.t === "Crafted") return s.n + (s.sk ? " (" + s.sk + ")" : "") + (it.bop ? " · BoP, craft it yourself" : " · tradeable");
    return s.n || "";
  }

  // Score of what is worn now: the weaker of two rings/trinkets (that is the one to replace), an empty slot is 0.
  function baselineScore(eq, slot, w) {
    if (!eq.length) return 0;
    const scores = eq.map((e) => scoreW(e, w));
    if (slot === "Finger" || slot === "Trinket") return eq.length < 2 ? 0 : Math.min.apply(null, scores);
    return Math.max.apply(null, scores);
  }
  function fmtDelta(d) { return (d > 0 ? "+" : "−") + Math.abs(d).toFixed(1); }

  // The equipped item an upgrade would replace: the weaker of two rings/trinkets (none while one is free).
  function baselineItem(eq, slot, w) {
    if (!eq.length) return null;
    if ((slot === "Finger" || slot === "Trinket") && eq.length < 2) return null;
    const pick = (slot === "Finger" || slot === "Trinket") ? Math.min : Math.max;
    const target = pick.apply(null, eq.map((e) => scoreW(e, w)));
    return eq.find((e) => scoreW(e, w) === target) || eq[0];
  }

  // --- comparison with the equipped item, like the in-game tooltip -------------------------
  const DIFF_KEYS = ["str", "agi", "int", "sta", "spi", "ap", "feralAp", "sp", "natureSp", "hit", "crit", "hitR", "critR", "exp", "haste", "def", "dodge", "wpnDmg", "armor"];
  function fmtNum(v) { const a = Math.abs(v); return Number.isInteger(a) ? String(a) : String(+a.toFixed(2)); }
  function statDiff(it, ref, w) {
    const parts = [];
    if (it.dps || ref.dps) {
      const d = (it.dps || 0) - (ref.dps || 0);
      if (Math.abs(d) >= 0.05) parts.push({ d, txt: (d > 0 ? "+" : "−") + Math.abs(d).toFixed(1) + " DPS", z: !w.dps });
    }
    DIFF_KEYS.forEach((k) => {
      const d = ((it.st && it.st[k]) || 0) - ((ref.st && ref.st[k]) || 0);
      if (Math.abs(d) < 1e-9) return;
      parts.push({ d, txt: (d > 0 ? "+" : "−") + fmtNum(d) + " " + (k === "armor" ? "Armor" : STAT_SHORT[k]), z: !w[k] && k !== "wpnDmg" });
    });
    return parts;
  }
  function diffLine(it, ref, w, slot) {
    const d = el("div", "diff");
    if (!ref) { d.appendChild(document.createTextNode(slot === "Finger" || slot === "Trinket" ? "Fills your free " + slot.toLowerCase() + " slot" : "Fills an empty slot")); return d; }
    const parts = statDiff(it, ref, w);
    d.appendChild(document.createTextNode("vs. " + ref.n + ": "));
    if (!parts.length) d.appendChild(document.createTextNode("same stats"));
    parts.forEach((x) => {
      const sp = el("span", (x.d > 0 ? "pos" : "neg") + (x.z ? " z" : ""), x.txt);
      if (x.z) sp.title = "Weight 0 for this character, not scored";
      d.appendChild(sp);
    });
    return d;
  }

  function itemLink(it) {
    const a = el("a", "q" + it.q, it.n); a.href = "https://www.wowhead.com/forever/item=" + it.id; a.target = "_blank"; a.rel = "noopener";
    return a;
  }

  function equippedLine(eq, w, slot, ref) {
    const d = el("div", "eq");
    d.appendChild(el("span", "lbl", "Equipped"));
    if (!eq.length) d.appendChild(el("span", "eq-none", "empty slot"));
    eq.forEach((e) => {
      const span = el("span", "eq-item");
      span.appendChild(itemLink(e));
      const note = e.est === true ? " · suffix stats estimated" : (e.est === "unknown" ? " · suffix stats unknown" : "");
      const swap = eq.length > 1 && e === ref ? " · weaker one, replace this" : "";
      span.appendChild(el("span", "meta", "score " + scoreW(e, w).toFixed(1) + swap + note));
      if (slot !== "Relic" && slot !== "Trinket") span.appendChild(el("span", "eq-stats", statLine(e) + (e.ench ? " · " + e.ench : "")));
      d.appendChild(span);
    });
    return d;
  }

  function itemRow(it, idx, level, sc, base, ref, slot) {
    const li = el("li", "row");
    li.appendChild(el("div", "rank", String(idx + 1)));
    const body = el("div");
    const nm = el("div", "name");
    nm.appendChild(itemLink(it));
    nm.appendChild(el("span", "meta", it.ty + (it.rq ? " · req " + it.rq : "") + " · ilvl " + it.il + (it.boe ? " · BoE" : "")));
    body.appendChild(nm);
    body.appendChild(el("div", "stats", statLine(it)));
    if (base !== null && base !== undefined && slot !== "Relic") body.appendChild(diffLine(it, ref, state.weights, slot));
    it.src.filter((s) => srcUsable(it, s, level)).forEach((s) => {
      const d = el("div", "src"); d.appendChild(el("span", "tag " + s.t, s.t));
      d.appendChild(document.createTextNode(sourceText(s, it))); body.appendChild(d);
    });
    (it.nt || []).forEach((n) => body.appendChild(el("div", "note", n + " (not scored)")));
    if (it.rnd) body.appendChild(el("div", "note", "Random enchantment — base stats only"));
    if (it.np) body.appendChild(el("div", "note", "Requires " + it.np + " to equip"));
    li.appendChild(body);
    let box;
    if (base === null || base === undefined) { box = el("div", "score", sc.toFixed(1)); box.appendChild(el("small", "", "score")); }
    else {
      const dlt = sc - base;
      box = el("div", "score " + (dlt > 0.05 ? "up" : "down"), fmtDelta(dlt));
      box.appendChild(el("small", "", "score " + sc.toFixed(1)));
      box.title = "Gain over what you wear (score " + base.toFixed(1) + ")";
    }
    li.appendChild(box);
    return li;
  }

  function ranked(items) {
    // equal scores (e.g. relics, which only have special effects) fall back to item level
    return items.map((it) => ({ it, s: score(it) })).sort((a, b) => (b.s - a.s) || (b.it.il - a.it.il));
  }

  // Everything one slot card (and its overview row) needs.
  function slotData(slot, level) {
    const all = DATA.items.filter((it) => it.sl === slot);
    const g = charGear(state.profile);
    const eq = g ? g.items.filter((e) => e.slot === slot) : [];
    const base = g ? baselineScore(eq, slot, state.weights) : null;
    const ref = g ? baselineItem(eq, slot, state.weights) : null;
    const eqIds = new Set(eq.map((e) => e.id));
    const pool = ranked(all.filter((it) => eligible(it, level) && !eqIds.has(it.id)));
    const ups = base === null ? pool : pool.filter((p) => p.s > base + 0.05);
    const onlyUp = base !== null && state.onlyUp && slot !== "Relic";
    const seen = new Set(); const top = [];
    for (const p of (onlyUp ? ups : pool)) { if (seen.has(p.it.n)) continue; seen.add(p.it.n); top.push(p); if (top.length >= state.topN) break; }
    const best = Math.max(pool.length ? pool[0].s : -Infinity, base === null ? -Infinity : base);
    let next = null;
    for (let L = level + 1; L <= Math.min(60, level + 3) && !next && slot !== "Relic"; L++) {
      const cand = ranked(all.filter((it) => eligible(it, L) && !eligible(it, level) && !eqIds.has(it.id)));
      if (cand.length && cand[0].s > best + 0.05) next = Object.assign({ L }, cand[0]);
    }
    return { slot, g, eq, base, ref, pool, ups, onlyUp, top, next };
  }

  function shortSource(it, level) {
    const s = it.src.find((x) => srcUsable(it, x, level)) || it.src[0];
    if (!s) return null;
    if (s.t === "Dungeon") return { t: s.t, txt: s.w, loc: s.w };
    if (s.t === "Quest") return { t: s.t, txt: s.n + (s.w ? " · " + s.w : ""), loc: s.dq || s.w };
    if (s.t === "Vendor") return { t: s.t, txt: s.n + (s.w ? " · " + s.w : ""), loc: s.w };
    return { t: s.t, txt: s.n + (it.bop ? " · craft it yourself" : " · tradeable"), loc: null };
  }

  function slotTitle(slot) { return slot === "Relic" ? "Relic · " + P().relic : slot; }

  // One row per slot: what you wear, the best upgrade, where it drops, the gain. Click jumps to the slot card.
  function renderOverview(out, rows, level) {
    const hasGear = rows.some((r) => r.g);
    const card = el("section", "card wide");
    const h = el("h2", "", hasGear ? "Upgrade overview" : "Best item per slot");
    h.appendChild(el("small", "", "level " + level + " · select a row to jump to the slot"));
    card.appendChild(h);
    const list = rows.filter((r) => r.slot !== "Relic").map((r) => {
      const best = hasGear ? (r.ups[0] || null) : (r.pool[0] || null);
      return Object.assign({ best, gain: best ? (hasGear ? best.s - r.base : best.s) : null }, r);
    });
    const withUp = list.filter((r) => r.best).sort((a, b) => b.gain - a.gain);
    const without = list.filter((r) => !r.best);

    const sum = el("div", "ov-sum");
    if (hasGear) {
      const places = {};
      withUp.forEach((r) => { const s = shortSource(r.best.it, level); if (s && s.loc) places[s.loc] = (places[s.loc] || 0) + 1; });
      const top = Object.entries(places).filter((x) => x[1] > 1).sort((a, b) => b[1] - a[1]).slice(0, 3);
      sum.appendChild(el("b", "", withUp.length + " of " + list.length + " slots"));
      sum.appendChild(document.createTextNode(" can be upgraded at level " + level + "."));
      if (top.length) sum.appendChild(document.createTextNode(" Best places to go: " + top.map((x, i) => x[0] + " (" + x[1] + (i ? "" : " slots") + ")").join(", ") + "."));
    } else {
      sum.appendChild(document.createTextNode("No gear data for this character, so this shows the best item per slot instead of upgrades."));
    }
    card.appendChild(sum);

    const head = el("div", "ov-row ov-head");
    ["Slot", hasGear ? "Equipped" : "", "Best " + (hasGear ? "upgrade" : "item"), "Where", hasGear ? "Gain" : "Score"].forEach((t) => head.appendChild(el("span", "", t)));
    card.appendChild(head);
    withUp.concat(without).forEach((r) => {
      const b = el("button", "ov-row" + (r.best ? "" : " none")); b.type = "button";
      b.appendChild(el("span", "ov-slot", r.slot));
      const eqTxt = !hasGear ? "" : (r.ref ? r.ref.n : (r.eq.length ? "one free slot" : "empty"));
      b.appendChild(el("span", "ov-eq", eqTxt));
      const up = el("span", "ov-up");
      if (r.best) { up.appendChild(el("span", "ov-arrow", "→")); const n = el("b", "q" + r.best.it.q, r.best.it.n); up.appendChild(n); }
      else up.textContent = "no upgrade now" + (r.next ? " · level " + r.next.L + ": " + r.next.it.n : "");
      b.appendChild(up);
      const src = el("span", "ov-src");
      const ss = r.best ? shortSource(r.best.it, level) : null;
      if (ss) { src.appendChild(el("span", "tag " + ss.t, ss.t)); src.appendChild(document.createTextNode(ss.txt)); }
      b.appendChild(src);
      b.appendChild(el("span", "ov-gain", r.best ? (hasGear ? "+" + r.gain.toFixed(1) : r.gain.toFixed(1)) : "—"));
      b.addEventListener("click", () => { const c = $("slot-" + r.slot); if (c) c.scrollIntoView({ behavior: "smooth", block: "start" }); });
      card.appendChild(b);
    });
    out.appendChild(card);
  }

  function render() {
    updateSummaries();
    updateGearAge();
    const level = state.level;
    const out = $("results"); out.innerHTML = "";
    out.classList.toggle("single", state.slot !== "All");
    const rows = (state.slot === "All" ? SLOT_ORDER : [state.slot]).map((slot) => slotData(slot, level));
    if (state.slot === "All") renderOverview(out, rows, level);
    rows.forEach((r) => {
      const slot = r.slot;
      const card = el("section", "card"); card.id = "slot-" + slot;
      const h = el("h2", "", slotTitle(slot));
      const count = (r.base !== null && slot !== "Relic" ? r.ups.length + " upgrade" + (r.ups.length === 1 ? "" : "s") + " · " : "")
        + r.pool.length + " option" + (r.pool.length === 1 ? "" : "s") + " at level " + level + (slot === "Finger" || slot === "Trinket" ? " · 2 slots" : "");
      h.appendChild(el("small", "", count));
      card.appendChild(h);
      if (r.g) card.appendChild(equippedLine(r.eq, state.weights, slot, r.ref));
      if (!r.top.length) {
        card.appendChild(el("div", "empty", r.onlyUp ? "No upgrade at level " + level + " from the selected sources. What you wear is ahead."
          : "Nothing found for this level with the selected sources."));
      } else {
        const ol = el("ol");
        r.top.forEach((p, i) => ol.appendChild(itemRow(p.it, i, level, p.s, slot === "Relic" ? null : r.base, r.ref, slot)));
        card.appendChild(ol);
      }
      if (slot === "Relic") card.appendChild(el("div", "next", "Relics only carry special effects, so they are sorted by item level. Pick by effect."));
      if (r.next) {
        const d = el("div", "next");
        d.appendChild(document.createTextNode("Coming up at level " + r.next.L + ": "));
        d.appendChild(el("b", "", r.next.it.n));
        const gain = r.base !== null ? " · " + fmtDelta(r.next.s - r.base) + " over what you wear" : " · score " + r.next.s.toFixed(1);
        d.appendChild(document.createTextNode(" (" + r.next.it.src.map((s) => s.t).join("/") + gain + ")"));
        card.appendChild(d);
      }
      out.appendChild(card);
    });
  }

  // --- gear freshness in the header -----------------------------------------------------
  function ago(iso) {
    const t = new Date(iso);
    if (isNaN(t)) return "";
    const m = Math.round((Date.now() - t) / 60000);
    if (m < 2) return "just now";
    if (m < 60) return m + " min ago";
    const h = Math.round(m / 60);
    return h < 24 ? h + " h ago" : t.toLocaleDateString(undefined, { day: "numeric", month: "short" });
  }
  function updateGearAge() {
    const box = $("gearAge");
    if (!GEAR || !GEAR.fetched) { box.textContent = ""; return; }
    const g = view === "gear" ? gearChar(state.profile) : null;
    const when = (g && g.fetchedAt) || GEAR.fetched;
    const src = g && g.source ? (g.source === "blizzard" ? "Blizzard" : "armory") : null;
    box.textContent = "gear updated " + ago(when) + (src ? " via " + src : "") + (g && g.stale ? " (latest fetch failed)" : "");
    box.title = new Date(when).toLocaleString();
  }

  // --- views ------------------------------------------------------------------------------
  const VIEWS = ["gear", "dungeons", "addons"];
  let view = "gear";
  function showView(v) {
    view = VIEWS.includes(v) ? v : "gear";
    VIEWS.forEach((x) => { $("view-" + x).hidden = x !== view; });
    document.querySelectorAll(".tabs a").forEach((a) => a.setAttribute("aria-current", a.dataset.v === view ? "page" : "false"));
    $("charSwitch").hidden = view !== "gear";
    $("charSub").textContent = view === "gear" ? P().sub
      : view === "dungeons" ? "Which dungeon helps you both most, each at your own level"
      : "What a WoW Forever addon could add to this planner";
    updateGearAge();
    openPanel(null);
    if (view === "dungeons") renderDungeons();
  }
  window.addEventListener("hashchange", () => showView(location.hash.slice(1)));

  // --- dungeon planner --------------------------------------------------------------------
  // Typical level ranges (wowtbc.gg dungeon list, WoW Forever).
  const DUNGEON_RANGES = {
    "Ragefire Chasm": [13, 18], "The Hall of Thanes": [13, 18], "Wailing Caverns": [15, 25], "Ruins of Lordaeron": [16, 23],
    "Deadmines": [18, 23], "Shadowfang Keep": [22, 30], "Stormwind Stockade": [22, 30], "Blackfathom Deeps": [24, 32],
    "Excavation Site: Wetlands": [26, 32], "City of Dalaran": [28, 34], "Scarlet Monastery": [28, 45], "Gnomeregan": [29, 38],
    "Razorfen Kraul": [30, 40], "The Drowned City": [35, 40], "Krol'dok Stronghold": [40, 45], "Razorfen Downs": [40, 50],
    "Uldaman": [42, 52], "Zul'Farrak": [44, 54], "Maraudon": [46, 55], "Alcaz Prison": [48, 53], "Sunken Temple": [50, 60],
    "Blackrock Depths": [52, 60], "Blackmaw Hold": [55, 60], "Blackrock Spire": [55, 60], "Dire Maul": [58, 60],
    "Stratholme": [58, 60], "Scholomance": [58, 60]
  };
  const DUNGEON_NOTES = { "Stormwind Stockade": "in Stormwind — hard to reach for Horde" };
  const CHARS = Object.keys(PROFILES);
  const SOON = 3;  // also count drops that become usable within this many levels

  // Which dungeon sources an item has: boss drops and dungeon quest rewards.
  function dungeonSources(it, name) {
    return it.src.filter((s) => (s.t === "Dungeon" && s.w === name) || (s.t === "Quest" && s.dq === name));
  }
  const DUNGEON_ITEMS = {};
  DATA.items.forEach((it) => {
    it.src.forEach((s) => {
      const d = s.t === "Dungeon" ? s.w : (s.t === "Quest" && s.dq ? s.dq : null);
      if (!d) return;
      (DUNGEON_ITEMS[d] = DUNGEON_ITEMS[d] || new Set()).add(it);
    });
  });

  // Per character: the best item per slot from quests, vendors and crafting (no dungeons), and
  // all scores per slot for ranking. A dungeon drop is an upgrade when it beats that baseline.
  function charContext(key) {
    const prof = PROFILES[key], st = profileState(key), level = st.level;
    const base = {}, pools = {}, g = charGear(key);
    const eqIds = new Set(g ? g.items.map((e) => e.id) : []);
    if (g) SLOT_ORDER.forEach((slot) => { base[slot] = baselineScore(g.items.filter((e) => e.slot === slot), slot, st.weights); });
    DATA.items.forEach((it) => {
      if (!eligibleFor(it, level, prof, st)) return;
      const sc = scoreW(it, st.weights);
      (pools[it.sl] = pools[it.sl] || []).push(sc);
      if (g) return;
      const outside = it.src.some((s) => s.t !== "Dungeon" && !s.dq && srcUsableFor(it, s, level, prof, st));
      if (outside && (base[it.sl] === undefined || sc > base[it.sl])) base[it.sl] = sc;
    });
    Object.values(pools).forEach((a) => a.sort((x, y) => y - x));
    return { key, prof, st, level, base, pools, eqIds, hasGear: !!g };
  }

  // Verdict for one dungeon item and one character.
  function verdict(it, name, ctx) {
    const { prof, st, level } = ctx;
    if (!wearable(it, 60, prof, st)) return { kind: "no" };
    if (ctx.eqIds.has(it.id)) return { kind: "have" };
    const srcs = dungeonSources(it, name).filter((s) => srcUsableFor(it, s, 60, prof, st, true));
    if (!srcs.length) return { kind: "no" };
    const gate = Math.min.apply(null, srcs.map((s) => s.g));
    const typeGate = prof.armor[it.ty] !== undefined ? prof.armor[it.ty] : prof.weapons[it.ty];
    const from = Math.max(gate, typeGate || 1);
    const sc = scoreW(it, st.weights);
    if (it.sl === "Relic") return { kind: from > level ? "later" : "relic", from, sc };
    const baseline = ctx.base[it.sl] || 0;
    const gain = sc - baseline;
    if (from > level) return { kind: "later", from, sc, gain };
    const pool = ctx.pools[it.sl] || [];
    const rank = 1 + pool.filter((x) => x > sc + 1e-9).length;
    return { kind: gain > 0.05 ? "up" : "meh", sc, gain, rank };
  }

  function rankDungeons(ctxs) {
    return Object.keys(DUNGEON_ITEMS).map((name) => {
      const per = {};
      ctxs.forEach((ctx) => {
        const bestBySlot = {}, soonBySlot = {};
        DUNGEON_ITEMS[name].forEach((it) => {
          const v = verdict(it, name, ctx);
          if (v.kind === "up" && (!bestBySlot[it.sl] || v.gain > bestBySlot[it.sl])) bestBySlot[it.sl] = v.gain;
          if (v.kind === "later" && v.gain > 0.05 && v.from <= ctx.level + SOON) soonBySlot[it.sl] = true;
        });
        const gains = Object.values(bestBySlot);
        per[ctx.key] = { count: gains.length, gain: gains.reduce((a, b) => a + b, 0), soon: Object.keys(soonBySlot).length };
      });
      const total = Object.values(per).reduce((a, p) => a + p.gain, 0);
      const count = Object.values(per).reduce((a, p) => a + p.count, 0);
      return { name, per, total, count, range: DUNGEON_RANGES[name] };
    }).sort((a, b) => (b.count - a.count) || (b.total - a.total) || ((a.range ? a.range[0] : 99) - (b.range ? b.range[0] : 99)));
  }

  function fitText(range, levels) {
    if (!range) return "";
    const lo = Math.min.apply(null, levels), hi = Math.max.apply(null, levels);
    if (hi < range[0] - 2) return "too high for now";
    if (lo > range[1] + 2) return "below your level";
    return "fits your levels";
  }

  function charChip(prof, text, kind) {
    const c = el("span", "vchip " + kind); c.style.setProperty("--cc", prof.color);
    c.appendChild(el("span", "dot")); c.appendChild(el("b", "", prof.tag)); c.appendChild(document.createTextNode(" " + text));
    return c;
  }

  function verdictChip(prof, v, slot) {
    if (v.kind === "no") return charChip(prof, "can't use", "no");
    if (v.kind === "have") return charChip(prof, "equipped", "meh");
    if (v.kind === "relic") return charChip(prof, "relic · pick by effect", "meh");
    if (v.kind === "later") return charChip(prof, "from level " + v.from + (v.gain > 0.05 ? " · +" + v.gain.toFixed(1) : ""), "later");
    if (v.kind === "up") return charChip(prof, "+" + v.gain.toFixed(1) + " · #" + v.rank + " " + slot, "up");
    return charChip(prof, "no upgrade · #" + v.rank + " " + slot, "meh");
  }

  function renderDungeons() {
    const ctxs = CHARS.map(charContext);
    // level steppers, one per character
    const lv = $("dLevels"); lv.innerHTML = "";
    ctxs.forEach((ctx) => {
      const box = el("div", "dlevel"); box.style.setProperty("--cc", ctx.prof.color);
      box.appendChild(el("span", "dot"));
      const dn0 = el("span", "dname"); dn0.appendChild(el("span", "lab-long", longLabel(ctx.key)));
      dn0.appendChild(el("span", "lab-short", charName(ctx.key) || ctx.prof.short)); box.appendChild(dn0);
      if (armoryLevel(ctx.key) && armoryLevel(ctx.key) !== ctx.level) {
        const r = el("button", "lvsrc", "↺ " + armoryLevel(ctx.key)); r.type = "button";
        r.title = "Back to the live level"; r.addEventListener("click", () => set(armoryLevel(ctx.key)));
        box.appendChild(r);
      }
      const set = (v) => {
        v = Math.max(1, Math.min(60, Math.round(+v || 1)));
        saveLevel(ctx.key, v);
        if (ctx.key === state.profile) { state.level = v; $("level").value = v; $("levelRange").value = v; updateLevelSource(); render(); }
        renderDungeons();
      };
      const dn = el("button", "", "−"); dn.type = "button"; dn.setAttribute("aria-label", ctx.prof.label + " level down");
      const inp = el("input"); inp.type = "number"; inp.min = 1; inp.max = 60; inp.value = ctx.level; inp.setAttribute("inputmode", "numeric");
      inp.id = "dlv_" + ctx.key; inp.setAttribute("aria-label", ctx.prof.label + " level");
      const up = el("button", "", "+"); up.type = "button"; up.setAttribute("aria-label", ctx.prof.label + " level up");
      dn.addEventListener("click", () => set(ctx.level - 1));
      up.addEventListener("click", () => set(ctx.level + 1));
      inp.addEventListener("change", () => set(inp.value));
      const stepper = el("div", "level-box"); stepper.appendChild(dn); stepper.appendChild(inp); stepper.appendChild(up);
      box.appendChild(stepper);
      lv.appendChild(box);
    });

    const ranked = rankDungeons(ctxs);
    const levels = ctxs.map((c) => c.level);
    const useful = ranked.filter((d) => d.total > 0.05 || CHARS.some((k) => d.per[k].soon));
    const rest = ranked.filter((d) => !useful.includes(d));
    let selected = store.get("dungeon", null);
    if (!DUNGEON_ITEMS[selected]) selected = (useful[0] || ranked[0]).name;

    const list = $("dList"); list.innerHTML = "";
    useful.forEach((d, i) => {
      const b = el("button", "drow"); b.type = "button"; b.setAttribute("aria-pressed", String(d.name === selected));
      const top = el("div", "drow-top");
      top.appendChild(el("span", "drank", String(i + 1)));
      top.appendChild(el("span", "dtitle", d.name));
      top.appendChild(el("span", "dscore", d.count + " upgrade" + (d.count === 1 ? "" : "s")));
      b.appendChild(top);
      const meta = el("div", "drow-meta", (d.range ? "Level " + d.range[0] + "–" + d.range[1] + " · " : "") + fitText(d.range, levels)
        + (d.total > 0.05 ? " · score +" + d.total.toFixed(1) : "") + (DUNGEON_NOTES[d.name] ? " · " + DUNGEON_NOTES[d.name] : ""));
      b.appendChild(meta);
      const chips = el("div", "drow-chips");
      ctxs.forEach((ctx) => {
        const p = d.per[ctx.key];
        const txt = (p.count ? p.count + " upgrade" + (p.count > 1 ? "s" : "") : "no upgrades") + (p.soon ? " · " + p.soon + " soon" : "");
        chips.appendChild(charChip(ctx.prof, txt, p.count ? "up" : (p.soon ? "later" : "meh")));
      });
      b.appendChild(chips);
      b.addEventListener("click", () => {
        store.set("dungeon", d.name); renderDungeons();
        if (window.matchMedia("(max-width: 760px)").matches) $("dDetail").scrollIntoView({ behavior: "smooth", block: "start" });
      });
      list.appendChild(b);
    });
    if (!useful.length) list.appendChild(el("p", "empty", "No dungeon has an upgrade for your current levels."));
    if (rest.length) {
      const p = el("p", "drest");
      p.appendChild(el("b", "", "No upgrades right now: "));
      p.appendChild(document.createTextNode(rest.map((d) => d.name).join(", ")));
      list.appendChild(p);
    }
    renderDungeonDetail(selected, ctxs, levels);
  }

  function renderDungeonDetail(name, ctxs, levels) {
    const box = $("dDetail"); box.innerHTML = "";
    const range = DUNGEON_RANGES[name];
    const head = el("div", "dhead");
    const ht = el("div");
    ht.appendChild(el("h2", "", name));
    ht.appendChild(el("p", "drow-meta", (range ? "Level " + range[0] + "–" + range[1] + " · " : "") + fitText(range, levels)
      + (DUNGEON_NOTES[name] ? " · " + DUNGEON_NOTES[name] : "")));
    head.appendChild(ht);
    const onlyUp = store.get("dOnlyUp", true);
    const tg = el("label", "chip"); const tgi = el("input"); tgi.type = "checkbox"; tgi.checked = onlyUp;
    tgi.addEventListener("change", () => { store.set("dOnlyUp", tgi.checked); renderDungeonDetail(name, ctxs, levels); });
    tg.appendChild(tgi); const tgl = el("span", "", "Only upgrades"); tg.appendChild(tgl);
    head.appendChild(tg);
    box.appendChild(head);
    // an item matters when it is an upgrade now or soon for one of you (relics: always, pick by effect)
    const matters = (vs) => vs.some((x) => x.v.kind === "up" || x.v.kind === "relic" || (x.v.kind === "later" && x.v.gain > 0.05));
    let folded = 0;

    // group by boss; quests and trash last
    const groups = new Map();
    let hidden = 0;
    DUNGEON_ITEMS[name].forEach((it) => {
      const verdicts = ctxs.map((ctx) => ({ ctx, v: verdict(it, name, ctx) }));
      if (verdicts.every((x) => x.v.kind === "no")) { hidden++; return; }
      if (onlyUp && !matters(verdicts)) { folded++; return; }
      dungeonSources(it, name).forEach((s) => {
        const key = s.t === "Quest" ? "Quest: " + s.n : (/^trash/.test(s.n) ? "Trash" : s.n);
        if (!groups.has(key)) groups.set(key, []);
        const arr = groups.get(key);
        if (!arr.some((x) => x.it === it)) arr.push({ it, verdicts, best: Math.max.apply(null, verdicts.map((x) => x.v.gain || -999)) });
      });
    });
    const upsIn = (k) => groups.get(k).filter((x) => x.verdicts.some((y) => y.v.kind === "up")).length;
    const order = Array.from(groups.keys()).sort((a, b) => {
      const w = (k) => k.startsWith("Quest: ") ? 2 : (k === "Trash" ? 1 : 0);
      return (w(a) - w(b)) || (upsIn(b) - upsIn(a));
    });
    if (!order.length) box.appendChild(el("p", "empty", "Nothing here is an upgrade for either of you right now or within " + SOON + " levels."));
    order.forEach((key) => {
      const sec = el("section", "boss");
      const items = groups.get(key).sort((a, b) => b.best - a.best);
      const h = el("h3", "", key);
      const ups = items.filter((x) => x.verdicts.some((y) => y.v.kind === "up")).length;
      if (ups) h.appendChild(el("small", "", ups + " upgrade" + (ups > 1 ? "s" : "")));
      sec.appendChild(h);
      const ol = el("ol");
      items.forEach(({ it, verdicts }) => {
        const li = el("li", "ditem");
        const nm = el("div", "name");
        const a = el("a", "q" + it.q, it.n); a.href = "https://www.wowhead.com/forever/item=" + it.id; a.target = "_blank"; a.rel = "noopener";
        nm.appendChild(a);
        const drop = dungeonSources(it, name).find((s) => s.dc);
        nm.appendChild(el("span", "meta", it.sl + " · " + it.ty + " · req " + (it.rq || "–") + (drop ? " · " + drop.dc + "%" : "")));
        li.appendChild(nm);
        li.appendChild(el("div", "stats", statLine(it)));
        const chips = el("div", "vchips");
        verdicts.forEach(({ ctx, v }) => chips.appendChild(verdictChip(ctx.prof, v, it.sl)));
        li.appendChild(chips);
        ol.appendChild(li);
      });
      sec.appendChild(ol);
      box.appendChild(sec);
    });
    if (folded) tgl.textContent = "Only upgrades · " + folded + " hidden";
    if (hidden) box.appendChild(el("p", "drest", hidden + " more drop" + (hidden > 1 ? "s" : "") + " that neither of you can use."));
    box.appendChild(el("p", "drest", (ctxs.every((c) => c.hasGear)
      ? "Upgrade = better score than what that character wears now."
      : "Upgrade = better score than what the character wears now where gear data exists, otherwise than the best quest, vendor or crafted item at that level.") + " #rank = place among everything available in that slot. Dungeons are ranked by the number of upgrades for both of you; the score gain breaks ties. Uses each character's own weights, professions and filters from the Gear tab."));
  }

  function applyProfile() {
    loadProfile();
    const prof = P();
    document.documentElement.style.setProperty("--cc", prof.color);
    sw.querySelectorAll("button").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.k === state.profile)));
    $("charSub").textContent = prof.sub;
    chipGroup($("srcBox"), SOURCES, "sources");
    chipGroup($("profBox"), PROFESSIONS, "myProfs");
    $("optRandom").checked = state.random;
    $("optOnlyUp").checked = state.onlyUp;
    $("optOnlyUpBox").hidden = !charGear(state.profile);
    updateLevelSource();
    buildWeights();
    $("level").value = state.level; $("levelRange").value = state.level;
    render();
    if (view === "dungeons") renderDungeons();
  }

  let info = DATA.count + " items · game build " + DATA.build + " · item data " + DATA.generated;
  if (GEAR && GEAR.fetched) {
    const when = new Date(GEAR.fetched);
    const fmt = isNaN(when) ? GEAR.fetched : when.toLocaleString(undefined, { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
    const srcs = Array.from(new Set(Object.values(GEAR.chars || {}).map((c) => c.source).filter(Boolean)));
    info += " · gear " + fmt + (srcs.length ? " via " + srcs.map((s) => s === "blizzard" ? "Blizzard API" : "armory").join(" + ") : "");
    if (Object.values(GEAR.chars || {}).some((c) => c.stale)) info += " (partly older)";
  }
  $("dataInfo").textContent = info;
  applyProfile();
  showView(location.hash.slice(1));
})();
