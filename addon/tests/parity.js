// Runs the website's own ranking code (site/app.js + site/model.js) for a few scenarios and writes the
// results as a Lua table (addon/tests/expected.lua). run.lua then checks the addon ranks the same way.
// Usage: node addon/tests/parity.js
"use strict";
const fs = require("fs");
const path = require("path");
const ROOT = path.resolve(__dirname, "..", "..");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");

global.window = { MECH: JSON.parse(read("data/mechanics.json")) };
eval(read("site/model.js"));  // defines window.LevelModel
const itemsText = read("data/items.js");
const DATA = JSON.parse(itemsText.slice(itemsText.indexOf("{"), itemsText.lastIndexOf("}") + 1));
const byId = new Map(DATA.items.map((it) => [it.id, it]));

const app = read("site/app.js");
function grab(start, end) {
  const a = app.indexOf(start), b = app.indexOf(end, a);
  if (a < 0 || b < 0) throw new Error("app.js changed, cannot find " + start);
  return app.slice(a, b);
}
const SRC = [
  grab("const PROFILES = {", "const WEIGHT_LABELS"),
  grab("const MODEL_KEYS", "function readProfile"),
  grab("function score(it)", "function statLine"),
  grab("function baselineScore", "// --- comparison"),
  grab("function ranked(items)", "function shortSource"),
  grab("function talentNumbers(", "// --- end talentNumbers"),
].join("\n");

const factory = new Function("DATA", "GEAR", "state", `
  const SLOT_ORDER = ["Two-Hand", "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger", "Trinket", "Relic"];
  const SOURCES = ["Quest", "Dungeon", "Vendor", "Crafted"];
  const gearChar = (key) => (GEAR && GEAR.chars && GEAR.chars[key]) || null;
  const charGear = (key) => { const g = gearChar(key); return g && g.items && g.items.length ? g : null; };
  const P = () => PROFILES[state.profile];
  ${SRC}
  state.weights = presetWeights(state.profile, state.preset, state.level);
  return { slotData, talentNumbers, SLOT_ORDER, weights: state.weights };
`);

// --- scenarios ----------------------------------------------------------------------------------
const INV = { "Two-Hand": [16], Head: [1], Neck: [2], Shoulder: [3], Back: [15], Chest: [5], Wrist: [9], Hands: [10],
  Waist: [6], Legs: [7], Feet: [8], Finger: [11, 12], Trinket: [13, 14], Relic: [18] };
const SHAMAN_TALENTS = [
  { n: "Flurry", d: "Increases your attack speed by 25% for your next 3 swings after dealing a critical strike." },
  { n: "Elemental Weapons", d: "Increases the melee attack power bonus of your Rockbiter Weapon by 20%, your Windfury Weapon effect by 40% and increases the damage caused by your Flametongue Weapon and Frostbrand Weapon by 15%." },
  { n: "Stormstrike", d: "Gives you an extra attack." },
  { n: "Thundering Strikes", d: "Improves your chance to get a critical strike with your weapon attacks by 3%." },
  { n: "Mental Dexterity", d: "Increases your Attack Power by an amount equal to 66% of your Intellect." },
  { n: "Ancestral Knowledge", d: "Increases your Intellect by 5%." },
  { n: "Nature's Guidance", d: "Increases your chance to hit with melee attacks and spells by 2%." },
];
const DRUID_TALENTS = [
  { n: "Sharpened Claws", d: "Increases your critical strike chance while in Bear, Dire Bear or Cat Form by 4%." },
  { n: "Predatory Strikes", d: "Increases your melee attack power in Cat, Bear and Dire Bear Forms by 100% of your level." },
  { n: "Blood Frenzy", d: "Your critical strikes from Cat Form abilities that add combo points have a 100% chance to add an additional combo point." },
  { n: "Natural Weapons", d: "Increases the damage you deal with physical attacks in all forms by 10%." },
];
const scenarios = [
  { key: "shaman", level: 34, preset: "Level model", profs: ["Enchanting"], talents: SHAMAN_TALENTS,
    sheet: { str: 110, agi: 55, int: 75, ap: 290, crit: 6.5, spellCrit: 3.2, sp: 0 },
    gear: { "Two-Hand": [1976], Head: [273645], Chest: [8211], Legs: [6910], Feet: [7027], Hands: [4247], Finger: [2039, 1491],
      Trinket: [273840], Back: [6314], Waist: [4829], Wrist: [3230], Shoulder: [3748] },
    suffix: { 8211: { str: 6, sta: 6 } } },
  { key: "shaman", level: 41, preset: "Enhancement (estimate)", profs: ["Enchanting"], talents: SHAMAN_TALENTS,
    sheet: { str: 110, agi: 55, int: 75, ap: 290, crit: 6.5, spellCrit: 3.2, sp: 0 },
    gear: { "Two-Hand": [1976], Head: [273645], Legs: [6910], Finger: [2039] }, suffix: {} },
  { key: "druid", level: 30, preset: "Level model (Cat)", profs: [], talents: DRUID_TALENTS,
    sheet: { str: 60, agi: 70, int: 80, ap: 140, crit: 7.2, spellCrit: 4.0, sp: 0 },
    gear: { "Two-Hand": [1155], Head: [273645], Chest: [6324], Hands: [4247], Finger: [2039, 1491] }, suffix: {} },
];

const lua = (v) => {
  if (v === null || v === undefined) return "nil";
  if (typeof v === "number") return isFinite(v) ? String(v) : "nil";
  if (typeof v === "boolean") return String(v);
  if (typeof v === "string") return JSON.stringify(v);
  if (Array.isArray(v)) return "{" + v.map(lua).join(",") + "}";
  return "{" + Object.entries(v).filter(([, x]) => x !== undefined).map(([k, x]) => (/^[A-Za-z_]\w*$/.test(k) ? k : "[" + JSON.stringify(k) + "]") + "=" + lua(x)).join(",") + "}";
};

const out = [];
for (const sc of scenarios) {
  const items = [];
  const inventory = {};
  for (const [slot, ids] of Object.entries(sc.gear)) {
    ids.forEach((id, i) => {
      const base = byId.get(id);
      const st = Object.assign({}, base.st, sc.suffix[id] || {});
      items.push(Object.assign({}, base, { slot, st }));
      inventory[INV[slot][i]] = id;
    });
  }
  const GEAR = { chars: { [sc.key]: { level: sc.level, items, sheet: sc.sheet, talents: sc.talents } } };
  const state = { profile: sc.key, level: sc.level, preset: sc.preset, sources: ["Quest", "Dungeon", "Vendor", "Crafted"],
    myProfs: sc.profs, random: false, onlyUp: true, topN: 5 };
  const app = factory(DATA, GEAR, state);
  const slots = {};
  for (const slot of app.SLOT_ORDER) {
    const d = app.slotData(slot, sc.level);
    slots[slot] = { base: d.base, top: d.top.map((p) => ({ id: p.it.id, s: p.s })), next: d.next ? { L: d.next.L, id: d.next.it.id, s: d.next.s } : null };
  }
  const w = {};
  ["str", "agi", "int", "ap", "feralAp", "crit", "hit", "sp", "natureSp", "dps", "slow"].forEach((k) => { w[k] = app.weights[k]; });
  out.push({ key: sc.key, level: sc.level, preset: sc.preset, sheet: sc.sheet, tal: app.talentNumbers(sc.talents),
    inventory, suffix: sc.suffix, model: !!app.weights.__model, weights: w, slots });
}
fs.writeFileSync(path.join(__dirname, "expected.lua"), "-- generated by parity.js\nreturn " + lua(out) + "\n");
console.log("wrote expected.lua for " + out.length + " scenarios");
