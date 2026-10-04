// MeowDB MS Classic simulator parity oracles -> golden vectors.
//
//   node tools/meowdb/oracle_vectors.mjs            (cache-first; re-running reproduces the outputs byte-for-byte)
//
// What it does
//   1. Fetches (cache-first, through lib.mjs's global rate gate) the simulator pages, the exact hashed Next.js JS chunks that
//      implement them, the guides they are checked against, and the monster/item detail pages used as fixtures.
//   2. Executes MeowDB's own client-side code VERBATIM: the cached chunk files are evaluated in a node:vm sandbox behind a
//      ~20-line webpack-runtime shim, and the exported functions (calculateDamage, calculateAccuracy, ...) are called directly.
//      The only source adaptation is ONE token added to the /formulas page module 51894 so that its module-local calculator
//      table is exported (see FORMULAS_PATCH below); React modules 95155/12115 are stubbed because they are only touched by
//      render code. Two page-component snippets (exp-calculator) are evaluated from their verbatim text with their free
//      variable bound to the module they reference.
//   3. Writes game/tests/data/parity_vectors.json ({mechanic, inputs, outputs, oracle_source} vectors) and the
//      verbatim reference extracts docs/canonical/oracles/<tool>.js.txt. Every extract is a byte-exact substring of the chunk
//      that was executed (asserted below), and every extract is syntax-checked so the slicer cannot silently truncate.
//   4. Asserts (throws on failure): calculateDamage with the Beginner input shape and no target equals the character
//      builder's beginnerDamage for every build x starter weapon; explicit-roll extremes equal per_hit min/max; mob-hit-sim
//      rows equal the XB-listed Maple Island monsters; one damage row per request. Cross-check/guide disagreements are
//      collected into `discrepancies`. Each oracle's executed_chunks is traced from the module loader.
//
// Scope: the six Maple Island monsters (1, 2, 3, 4, 5, 9) and the four weapons Sid sells (Sword, Hand Axe, Wooden Club, Razor).
//
// If MeowDB redeploys, the hashed chunk URLs below can 404 on a fresh clone (the cache is git-ignored). The script checks that
// the cached pages/webpack runtime still reference these exact files and fails loudly otherwise; update CHUNKS from the page
// HTML (<script src="/_next/static/chunks/...">) and the webpack runtime's `.u` chunk map, then review docs/canonical/oracles.md.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { fetchPage, fetchUrl, pageText, writeJson, AUTHORITY, BASE_URL } from './lib.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT_JSON = path.join(ROOT, 'game', 'tests', 'data', 'parity_vectors.json');
const OUT_TXT_DIR = path.join(ROOT, 'docs', 'canonical', 'oracles');
const ORIGIN = 'https://meowdb.com';

// ---------------------------------------------------------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------------------------------------------------------
const PAGES = {
  'dmg-simulator': '/dmg-simulator',
  'accuracy-sim': '/accuracy-sim',
  'avoidability-sim': '/avoidability-sim',
  'mob-hit-sim': '/mob-hit-sim',
  'exp-calculator': '/exp-calculator',
  'dps-table': '/dps-table',
  'character-builder': '/character-builder',
  formulas: '/formulas',
  'guide-damage': '/guides/explaining-the-damage-formula',
  'guide-exp': '/guides/exp-table-level-1-to-100',
  'guide-beginner': '/guides/beginners-guide-first-steps-in-maple-world',
};

// Exact hashed chunk files. `lazy` chunks are loaded on demand by module 47938 (`s.e(7135), s.e(6549), s.e(4790), s.e(4368)`,
// and 2150/2700/782 for the mob-hit-sim) and resolved through the webpack runtime's `.u` map; the rest are listed in the page HTML.
const CHUNKS = {
  webpack: { file: 'webpack-627aa0b35ae17090.js', role: 'webpack runtime (chunk id -> file map)' },
  calc: { file: '4790-688bba5b679fd1bc.js', lazy: true, role: 'calculator engine: module 4790 (calculateDamage/Accuracy/Avoidability/CharacterStats) + 58903 + 63584 + 64007' },
  calcDeps: { file: '4368.e968ea2f15da4f52.js', lazy: true, role: 'modules 13805 (class/AP/HP-MP helpers), 17033, 36751, 43239, 68726' },
  skills: { file: '7135-240168d5571b96bf.js', lazy: true, role: 'module 57135 (skill catalog J3, weapon/skill helpers)' },
  scrolls: { file: '6549-8ccdabf5b9357200.js', lazy: true, role: 'module 96549 (scroll catalog, used by equipment stat totals)' },
  monsterCombat: { file: '2700-281eba0f40bad0d4.js', lazy: true, role: 'module 92700 (monster sprite/touch boxes + attack ratios)' },
  mobDanger: { file: '2150.42d12b8816737776.js', lazy: true, role: 'module 42150 (mob-hit-sim computeMobDangerRows)' },
  monsters: { file: '782-bb5a5ee666dc6188.js', role: 'module 60782 (simulator monster table IW)' },
  exp: { file: '6459-e11456f2ce797f6c.js', role: 'modules 17401 (EXP table) + 27279 (cumulative EXP helpers)' },
  formulas: { file: '5253-8d210be12f2a3111.js', role: 'module 51894 (/formulas page "Try values" calculators) + 70361/92560/64007/17401' },
  formulasDeps: { file: '3997-838740702365190e.js', role: 'module 61408 (required by 51894)' },
  shared: { file: '4068-26c6ed6efe1adbc7.js', role: 'module 74920 (i18n helper required by 70361); also carries a second, semantically identical build of 13805' },
  accPage: { file: 'app/msclassic/%5Blocale%5D/accuracy-sim/page-a20e5ee27e660470.js', role: 'accuracy-sim page component + module 47938 (calculator dispatcher)' },
  avoidPage: { file: 'app/msclassic/%5Blocale%5D/avoidability-sim/page-53a8a0ece6788df6.js', role: 'avoidability-sim page component' },
  mobHitPage: { file: 'app/msclassic/%5Blocale%5D/mob-hit-sim/page-e87c924be6b6bfac.js', role: 'mob-hit-sim page component' },
  expPage: { file: 'app/msclassic/%5Blocale%5D/exp-calculator/page-21d638bf33c2d750.js', role: 'exp-calculator page component' },
  dpsPage: { file: 'app/msclassic/%5Blocale%5D/dps-table/page-db514ace2bea2564.js', role: 'dps-table page component' },
  dmgUi: { file: '4916-85509b9cd591ff3d.js', role: 'dmg-simulator UI (input assembly + display helper)' },
  builderUi: { file: '4818-741685483b96d7a7.js', role: 'character-builder UI (character-stats input assembly)' },
};
// Execution order of chunk registration. First registration of a module id wins (4368's 13805 before 4068's duplicate).
// (The two 13805 builds were compared over every class x level 1-120 for H8/lM/jQ: identical outputs.)
const EXEC_CHUNKS = ['calc', 'calcDeps', 'skills', 'scrolls', 'monsterCombat', 'mobDanger', 'monsters', 'exp', 'formulas', 'formulasDeps', 'shared'];
const PAGE_CHUNK_REFS = {
  'accuracy-sim': ['accPage', 'monsters'],
  'avoidability-sim': ['avoidPage', 'monsters'],
  'mob-hit-sim': ['mobHitPage'],
  'exp-calculator': ['expPage', 'exp', 'monsters'],
  'dps-table': ['dpsPage'],
  'dmg-simulator': ['dmgUi', 'monsters'],
  'character-builder': ['builderUi'],
  formulas: ['formulas', 'formulasDeps'],
};
const LAZY_IN_RUNTIME = ['4790-688bba5b679fd1bc', '7135-240168d5571b96bf', '6549-8ccdabf5b9357200', '2700-281eba0f40bad0d4', '782-bb5a5ee666dc6188', '4368:"e968ea2f15da4f52"', '2150:"42d12b8816737776"'];

// The single source adaptation (module-local `Y` = calculator table of the /formulas page is not exported).
const FORMULAS_PATCH = { find: '51894:(e,a,l)=>{"use strict";l.d(a,{default:()=>ea});', replace: '51894:(e,a,l)=>{"use strict";l.d(a,{default:()=>ea,__calculators:()=>Y});' };
const STUB_MODULES = { 95155: { jsx() {}, jsxs() {}, Fragment: null }, 12115: {} }; // react/jsx-runtime, react

// The six monsters on the 25 Maple Island maps (docs/canonical/monsters.md: union of map.monsters[] over those maps):
// Tutorial Jr. Sentinel, Snail, Blue Snail, Shroom, Red Snail, Orange Mushroom.
const MONSTER_IDS = ['1', '2', '3', '4', '5', '9'];
// Sid's Maple Island weapon shop sells the starter trio + Razor (game/data/canonical/shops/maple-road-sid.json); Gladius = guide example.
const ITEM_IDS = { sword: '541', gladius: '551', hand_axe: '576', wooden_club: '585', razor: '558' };
const STARTER_WEAPONS = ['sword', 'hand_axe', 'wooden_club', 'razor'];
const LEVELS = [1, 5, 8, 10];

// ---------------------------------------------------------------------------------------------------------------------------
// Fetch everything (cache-first)
// ---------------------------------------------------------------------------------------------------------------------------
const pages = {};
for (const [k, p] of Object.entries(PAGES)) pages[k] = await fetchPage(p);
const chunks = {};
for (const [k, c] of Object.entries(CHUNKS)) {
  const url = `${ORIGIN}/_next/static/chunks/${c.file}`;
  const r = await fetchUrl(url, { accept: '*/*' });
  chunks[k] = { ...c, url, retrieved_at: r.retrieved_at, text: r.text, bytes: Buffer.byteLength(r.text), sha256: crypto.createHash('sha256').update(r.text).digest('hex') };
}
const monsterPages = {};
for (const id of MONSTER_IDS) monsterPages[id] = await fetchPage(`/monsters/${id}`);
const itemPages = {};
for (const [k, id] of Object.entries(ITEM_IDS)) itemPages[k] = await fetchPage(`/item-db/${id}`);

// Derivation checks: the pages / webpack runtime must still reference the exact files we execute.
for (const [page, keys] of Object.entries(PAGE_CHUNK_REFS))
  for (const k of keys)
    if (!pages[page].html.includes(`/_next/static/chunks/${CHUNKS[k].file}`))
      throw new Error(`page ${page} no longer references ${CHUNKS[k].file}; MeowDB redeployed - refresh CHUNKS (see header)`);
for (const needle of LAZY_IN_RUNTIME)
  if (!chunks.webpack.text.includes(needle)) throw new Error(`webpack runtime no longer maps ${needle}; refresh CHUNKS`);
const dispatcher = 'Promise.all([s.e(7135),s.e(6549),s.e(4790),s.e(4368)]).then(s.bind(s,4790))';
if (!chunks.accPage.text.includes(dispatcher)) throw new Error('calculator dispatcher (module 47938) changed; review oracles');

// ---------------------------------------------------------------------------------------------------------------------------
// Verbatim execution: minimal webpack runtime in a vm sandbox
// ---------------------------------------------------------------------------------------------------------------------------
const factories = {};
const moduleOrigin = {}; // webpack module id -> CHUNKS key of the chunk whose registration won (first wins)
let registering = null;
const sandbox = { self: {} };
sandbox.self.webpackChunk_N_E = {
  push([, mods]) {
    for (const [id, f] of Object.entries(mods))
      if (!(id in factories)) {
        factories[id] = f;
        moduleOrigin[id] = registering;
      }
  },
};
vm.createContext(sandbox);
const executedText = {};
for (const k of EXEC_CHUNKS) {
  let text = chunks[k].text;
  if (k === 'formulas') {
    if (text.split(FORMULAS_PATCH.find).length !== 2) throw new Error('formulas module 51894 header changed; review FORMULAS_PATCH');
    text = text.replace(FORMULAS_PATCH.find, FORMULAS_PATCH.replace);
  }
  executedText[k] = text;
  registering = k;
  vm.runInContext(text, sandbox, { filename: CHUNKS[k].file });
}
registering = null;
const moduleCache = {};
function req(id) {
  if (id in STUB_MODULES) return STUB_MODULES[id];
  if (moduleCache[id]) return moduleCache[id].exports;
  const f = factories[id];
  if (!f) throw new Error(`webpack module ${id} not loaded`);
  const m = (moduleCache[id] = { exports: {} });
  f(m, m.exports, req);
  return m.exports;
}
req.d = (ex, getters) => {
  for (const k in getters) if (!Object.prototype.hasOwnProperty.call(ex, k)) Object.defineProperty(ex, k, { enumerable: true, get: getters[k] });
};
req.r = (ex) => Object.defineProperty(ex, '__esModule', { value: true });
req.o = (o, p) => Object.prototype.hasOwnProperty.call(o, p);
req.n = (m) => {
  const g = m && m.__esModule ? () => m.default : () => m;
  req.d(g, { a: g });
  return g;
};
req.e = () => Promise.resolve();

const calc = req(4790); // calculator engine (what the simulators' worker-less path calls)
const K = calc.FORMULA_PARITY_KERNELS_PRIVATE; // MeowDB's own exported parity kernels
const classHelpers = req(13805); // jQ: total stat points by level, lM: MeowDB AP plan, H8: base HP/MP
const monsterTable = req(60782).IW;
const mobDanger = req(42150);
const expTable = req(17401); // jy: EXP to next level (lv 1..99), ML: lookup, Bq: cumulative through level
const expCum = req(27279); // H1: total EXP at (level, exp), Se: = jy, Mg: max level 100
const formulasCalcs = req(51894).__calculators;
const skillCatalog = req(57135); // J3: skill catalog; XB: the monster filter behind the dmg-sim / mob-hit-sim / exp-calculator lists
const skillByKey = (key) => {
  const s = skillCatalog.J3.find((x) => x.key === key);
  if (!s) throw new Error(`skill ${key} not in catalog J3`);
  return s;
};

// Provenance: which chunk files' code actually runs when a top-level module is required (fresh module cache, same
// factories; the module bodies only define functions/tables). Sorted in EXEC_CHUNKS order, so the output is deterministic.
function traceExecutedChunks(topIds) {
  const seen = new Set();
  const cache = {};
  const r = (id) => {
    if (id in STUB_MODULES) return STUB_MODULES[id];
    seen.add(String(id));
    if (cache[id]) return cache[id].exports;
    const m = (cache[id] = { exports: {} });
    factories[id](m, m.exports, r);
    return m.exports;
  };
  Object.assign(r, { d: req.d, r: req.r, o: req.o, n: req.n, e: req.e });
  for (const id of topIds) r(id);
  const keys = new Set([...seen].map((id) => moduleOrigin[id]));
  return EXEC_CHUNKS.filter((k) => keys.has(k));
}

// Evaluate verbatim page-component snippets in the same realm, with their free variables bound.
function evalSnippet(snippet, freeVars) {
  const names = Object.keys(freeVars);
  const fn = vm.runInContext(`(function(${names.join(',')}){return (${snippet});})`, sandbox);
  return fn(...names.map((n) => freeVars[n]));
}

// ---------------------------------------------------------------------------------------------------------------------------
// Verbatim slicer (string/template aware) for the reference extracts
// ---------------------------------------------------------------------------------------------------------------------------
function skipString(s, i) {
  const q = s[i++];
  while (i < s.length) {
    if (s[i] === '\\') i += 2;
    else if (s[i] === q) return i + 1;
    else i++;
  }
  throw new Error('unterminated string');
}
function skipTemplate(s, i) {
  i++;
  while (i < s.length) {
    const c = s[i];
    if (c === '\\') i += 2;
    else if (c === '`') return i + 1;
    else if (c === '$' && s[i + 1] === '{') i = scan(s, i + 2, 'close') + 1;
    else i++;
  }
  throw new Error('unterminated template');
}
// modes: 'item' stop before a top-level , or ; or an unmatched closer; 'stmt' include a top-level ; (or stop before an unmatched
// closer); 'fn' stop after the closing brace that returns depth to 0; 'group' stop after the first balanced bracket group;
// 'close' stop at the unmatched closer (used inside template ${ }).
function scan(s, start, mode) {
  let depth = 0;
  for (let i = start; i < s.length; ) {
    const c = s[i];
    if (c === '"' || c === "'") { i = skipString(s, i); continue; }
    if (c === '`') { i = skipTemplate(s, i); continue; }
    if (c === '(' || c === '[' || c === '{') { depth++; i++; continue; }
    if (c === ')' || c === ']' || c === '}') {
      if (depth === 0) return i;
      depth--; i++;
      if (depth === 0 && ((mode === 'fn' && c === '}') || mode === 'group')) return i;
      continue;
    }
    if (depth === 0 && mode === 'item' && (c === ',' || c === ';')) return i;
    if (depth === 0 && mode === 'stmt' && c === ';') return i + 1;
    i++;
  }
  return s.length;
}
function moduleRange(text, id) {
  const re = new RegExp(`[{,]${id}:\\(`, 'g');
  const m = re.exec(text);
  if (!m || re.exec(text)) throw new Error(`module ${id} not found exactly once`);
  const start = m.index + 1;
  return [start, scan(text, start, 'item')];
}
// spec: {chunk, module?, needle, skip?, mode, title, check?}
function extract(spec) {
  const text = chunks[spec.chunk].text;
  const [lo, hi] = spec.module ? moduleRange(text, spec.module) : [0, text.length];
  if (spec.whole) return { ...spec, text: text.slice(lo, hi) };
  const scope = text.slice(lo, hi);
  const at = scope.indexOf(spec.needle);
  if (at < 0 || scope.indexOf(spec.needle, at + 1) >= 0) throw new Error(`needle not unique in ${spec.chunk}/${spec.module}: ${spec.needle}`);
  const start = lo + at + (spec.skip ?? 0);
  const end = scan(text, start, spec.mode);
  return { ...spec, text: text.slice(start, end) };
}
function syntaxCheck(x) {
  const wrap = {
    fn: (t) => t,
    module: (t) => `({${t}})`,
    item: (t) => (/^[A-Za-z_$][\w$]*=/.test(t) ? `let ${t}` : /^("[^"]*"|[A-Za-z_$][\w$]*|\d+):/.test(t) ? `({${t}})` : `(${t})`),
    stmt: (t) => t,
    group: (t) => `(${t})`,
  }[x.whole ? 'module' : x.mode];
  try {
    new vm.Script(wrap(x.text));
  } catch (e) {
    throw new Error(`extract "${x.title}" is not a complete construct: ${e.message}`);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// Fixtures from real detail pages (cross-checked against the simulator's embedded tables)
// ---------------------------------------------------------------------------------------------------------------------------
const plain = (v) => JSON.parse(JSON.stringify(v)); // detach from the vm realm, drop undefined
const lines = (html) => pageText(html).split('\n').map((s) => s.trim()).filter(Boolean);
const after = (ls, label, from = 0) => {
  const i = ls.indexOf(label, from);
  return i < 0 ? null : ls[i + 1];
};
const dashNum = (v) => (v == null ? null : v === '—' ? 0 : Number(v.replace(/,/g, '')));
const discrepancies = [];
const notes = [];

const monsters = {};
for (const id of MONSTER_IDS) {
  const sim = monsterTable.find((m) => String(m.id) === id);
  const ls = lines(monsterPages[id].html);
  const lv = ls.indexOf('Level');
  const touchBase = (ls.find((x) => /^Base \d+$/.test(x)) ?? '').replace('Base ', '');
  const page = {
    level: dashNum(ls[lv + 1]),
    hp: dashNum(after(ls, 'HP', lv)),
    exp: dashNum(after(ls, 'EXP', lv)),
    touch_dmg_display: after(ls, 'Touch DMG', lv),
    touch_dmg_base: Number(touchBase),
    m_dmg: dashNum(after(ls, 'M.DMG', lv)),
    p_def: dashNum(after(ls, 'P.DEF', lv)),
    m_def: dashNum(after(ls, 'M.DEF', lv)),
    acc: dashNum(after(ls, 'ACC', lv)),
    avoid: dashNum(after(ls, 'AVOID', lv)),
  };
  const simView = { level: sim.level, hp: sim.hp, exp: sim.exp, touch_dmg_base: sim.pdmg, m_dmg: sim.mdmg, p_def: sim.pdef, m_def: sim.mdef, acc: sim.acc, avoid: sim.avoid };
  for (const [f, v] of Object.entries(simView))
    if (page[f] !== v) discrepancies.push(`monster ${id} ${f}: detail page ${page[f]} vs simulator table (module 60782) ${v}`);
  monsters[id] = {
    id,
    name: sim.name,
    level: sim.level,
    hp: sim.hp,
    exp: sim.exp,
    pdmg: sim.pdmg,
    mdmg: sim.mdmg,
    pdef: sim.pdef,
    mdef: sim.mdef,
    acc: sim.acc,
    avoid: sim.avoid,
    element: sim.element,
    boss: (sim.tags ?? []).includes('boss'),
    detail_page_touch_dmg_display: page.touch_dmg_display,
    // module 57135 XB = the filter behind the dmg-simulator target list, mob-hit-sim rows and exp-calculator monster list
    // (hp > 0, exp > 0, name not starting "Tutorial", not invincible, not "(alt)"). accuracy-sim/avoidability-sim only drop invincible mobs.
    listed_by_dmg_sim_mob_hit_sim_exp_calc: Boolean(skillCatalog.XB(sim)),
    source: { url: monsterPages[id].url, retrieved_at: monsterPages[id].retrieved_at },
    cross_check: 'detail page level/HP/EXP/touch base/M.DMG/P.DEF/M.DEF/ACC/AVOID equal the simulator table (module 60782)',
  };
}

const SUBTYPE_TO_SIM = { 'One-Handed Sword': '1H Sword', 'One-Handed Axe': '1H Axe', 'One-Handed Blunt Weapon': '1H Blunt', Dagger: 'Dagger' };
const items = {};
for (const [k, id] of Object.entries(ITEM_IDS)) {
  const ls = lines(itemPages[k].html);
  const db = ls.indexOf('Item Database');
  const name = ls[db + 2];
  const subtype = ls[ls.indexOf('Equip', db) + 2];
  const watk = Number(after(ls, 'W.ATK', db).replace('+', ''));
  const reqLv = after(ls, 'REQ LEV', db);
  const speed = Number((/\((\d+)\)$/.exec(after(ls, 'Attack Speed', db) ?? '') ?? [])[1]);
  const wm = ls.indexOf('Weapon Multipliers', db);
  const pageMult = { swing: parseFloat(after(ls, 'Swing', wm)), stab: parseFloat(after(ls, 'Stab', wm)) };
  if (!SUBTYPE_TO_SIM[subtype] || !Number.isFinite(watk) || !Number.isFinite(speed) || wm < 0 || !Number.isFinite(pageMult.swing) || !Number.isFinite(pageMult.stab))
    throw new Error(`could not parse item ${id}`);
  const simType = SUBTYPE_TO_SIM[subtype];
  const engineMult = plain(calc.weaponRollsForScripts(simType)); // module 4790 table f: {swing, stab}
  if (engineMult.swing !== pageMult.swing || engineMult.stab !== pageMult.stab)
    discrepancies.push(`item ${id} weapon multipliers: detail page swing ${pageMult.swing} / stab ${pageMult.stab} vs simulator table f (${simType}) ${engineMult.swing} / ${engineMult.stab}`);
  items[k] = {
    id,
    name,
    subtype,
    sim_weapon_type: simType,
    watk,
    attack_speed: speed,
    level_req: reqLv ? Number(reqLv) : 0,
    weapon_multipliers: pageMult,
    source: { url: itemPages[k].url, retrieved_at: itemPages[k].retrieved_at },
    cross_check: 'detail page "Weapon Multipliers" swing/stab equal the simulator table f (module 4790 weaponRollsForScripts)',
  };
}
// Equipment object in the shape the character builder passes to calculateCharacterStats (clean item: no scrolls/variance).
const equipWeapon = (it) => (it ? { name: it.name, subtype: it.subtype, levelReq: it.level_req, stats: { watk: it.watk }, appliedScrolls: [] } : null);

// ---------------------------------------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------------------------------------
const vectors = [];
const V = (mechanic, case_id, inputs, outputs, oracle_source, extra = {}) => vectors.push({ mechanic, case_id, inputs: plain(inputs), outputs: plain(outputs), oracle_source, ...extra });
const SRC = {
  stats: { oracle: 'character-builder', function: 'calculateCharacterStats (module 4790 export, operation "character-stats")' },
  dmg: { oracle: 'dmg-simulator', function: 'calculateDamage (module 4790 export, operation "damage")' },
  kernels: { oracle: 'dmg-simulator', function: 'FORMULA_PARITY_KERNELS_PRIVATE (module 4790 export)' },
  acc: { oracle: 'accuracy-sim', function: 'calculateAccuracy (module 58903 export c, operation "accuracy")' },
  avoid: { oracle: 'avoidability-sim', function: 'calculateAvoidability (module 4790 export, operation "avoidability")' },
  incoming: { oracle: 'avoidability-sim', function: 'incomingDamage (module 4790 export eP)' },
  mobhit: { oracle: 'mob-hit-sim', function: 'computeMobDangerRows (module 42150 export, operation "mob-danger")' },
  exp: { oracle: 'exp-calculator', function: 'modules 17401 (jy/ML/Bq) + 27279 (H1) + page validation/remaining-EXP IIFE' },
  formulas: (key) => ({ oracle: 'formulas-page', function: `module 51894 calculator "${key}".calculate` }),
};
const formulasCalc = (key, values) => {
  const c = formulasCalcs[key];
  const defaults = Object.fromEntries(c.fields.map((f) => [f.key, f.defaultValue]));
  const vals = { ...defaults, ...values };
  return { inputs: vals, outputs: plain(c.calculate(vals)) };
};
const num = (v) => Number(String(v).replace(/[,%\s]/g, ''));
const fpRow = (outputs, label) => outputs.find((r) => r.label === label);
// Cross-check record: the second MeowDB implementation's inputs/outputs plus an explicit agreement verdict.
const xc = (key, fp, agrees, note) => ({ oracle_source: SRC.formulas(key), inputs: fp.inputs, outputs: fp.outputs, agrees, ...(note ? { note } : {}) });
const dmgDisplay = evalSnippet(extract({ chunk: 'dmgUi', needle: 'function E(e){return isFinite(e)&&0!==e?Math.floor(e)', mode: 'fn' }).text, {});

// MeowDB's Beginner damage path: character builder -> beginnerDamage (eI) builds this exact input for en(): Dagger/Claw ->
// basic_attack_thief (mainClass Thief, primary LUK, secondary STR+DEX); Bow/Crossbow -> basic_attack_bowman (DEX / STR);
// every other weapon -> basic_attack_warrior (STR / DEX); masteryLvl 0, no crit. We pass the same shape to calculateDamage,
// adding a target and the skill key. Section 1 asserts that, with no target, calculateDamage reproduces eI's beginnerDamage.
function beginnerDamageInput(level, stats, weapon, target, critMode) {
  const wt = weapon.sim_weapon_type;
  const thief = wt === 'Dagger' || wt === 'Claw';
  const bow = wt === 'Bow' || wt === 'Crossbow';
  return {
    mainClass: thief ? 'Thief' : bow ? 'Bowman' : 'Warrior',
    subJob: thief ? 'Thief (1st)' : bow ? 'Bowman (1st)' : 'Warrior (1st)',
    level,
    primary: thief ? stats.luk : bow ? stats.dex : stats.str,
    secondary: thief ? stats.str + stats.dex : bow ? stats.str : stats.dex,
    totalInt: stats.int,
    totalLuk: stats.luk,
    baseWatk: Math.max(0, stats.watk || weapon.watk || 0),
    extraWatk: 0,
    matk: stats.matk,
    matkIncludesDerived: true,
    bonusAp: stats.attackPower,
    masteryLvl: 0,
    weaponType: wt,
    weaponAttackSpeed: 6,
    activePassiveKeys: [],
    ...(critMode === 'window' ? { critRateOverride: 0, critDamageOverride: 0 } : {}),
    elementalTier: 'neutral',
    healAlliesInRange: 0,
    boosterActive: false,
    target,
    includeSkillKeys: [thief ? 'basic_attack_thief' : bow ? 'basic_attack_bowman' : 'basic_attack_warrior'],
  };
}
const targetOf = (m) => ({ level: m.level, hp: m.hp, pdef: m.pdef, mdef: m.mdef, element: m.element, avoid: m.avoid, boss: m.boss });
const rowOut = (res) => {
  if (res.rows.length !== 1) throw new Error(`calculateDamage returned ${res.rows.length} rows; expected exactly the requested basic attack`);
  const r = res.rows[0];
  return {
    per_hit: r.perHit,
    per_cast: r.perCast,
    per_cast_avg_with_crit: r.perCastAvgCrit,
    display: { min: dmgDisplay(r.perHit.min), max: dmgDisplay(r.perHit.max), avg: dmgDisplay(r.perCast.avg), avg_with_crit: dmgDisplay(r.perCastAvgCrit) },
    weapon_multiplier: r.weaponMultiplier,
    bonuses: res.bonuses,
  };
};

// ---------------------------------------------------------------------------------------------------------------------------
// 1. Beginner builds (character builder)
// ---------------------------------------------------------------------------------------------------------------------------
const builds = [];
for (const level of LEVELS) {
  const total = classHelpers.jQ(level);
  const meow = plain(classHelpers.lM('beginner', level));
  const free = total - 16;
  const split = { str: 4 + Math.ceil(free / 2), dex: 4 + Math.floor(free / 2), int: 4, luk: 4 };
  builds.push({ level, plan: 'meowdb_ap_plan', ap: meow, total_stat_points: total });
  builds.push({ level, plan: 'synthetic_str_dex_split', ap: split, total_stat_points: total });
}
const synth = (plan) => (plan === 'synthetic_str_dex_split' ? { synthetic_inputs: true } : {});
const SYNTH_PLAN_NOTE = 'synthetic_str_dex_split is a test AP split (STR ceil(free/2), DEX floor(free/2)), not a MeowDB recommendation';
const weaponAllowed = (b, weaponKey) => b.level >= items[weaponKey].level_req; // Razor needs Lv 5 (the builder itself does not enforce it)
const buildStats = {}; // `${level}:${plan}:${weaponKey}` -> calculateCharacterStats(...).stats
const buildWindow = {}; // same key -> beginnerDamage
for (const b of builds) {
  for (const weaponKey of [...STARTER_WEAPONS, null]) {
    if (weaponKey && !weaponAllowed(b, weaponKey)) continue;
    const weapon = weaponKey ? items[weaponKey] : null;
    const input = { klass: 'beginner', subJob: null, level: b.level, ap: b.ap, equipment: { weapon: equipWeapon(weapon) }, skillBonuses: null };
    const out = plain(calc.calculateCharacterStats(input));
    if (weaponKey) {
      buildStats[`${b.level}:${b.plan}:${weaponKey}`] = out.stats;
      buildWindow[`${b.level}:${b.plan}:${weaponKey}`] = out.beginnerDamage;
      // Fidelity check: the calculateDamage input shape used below reproduces MeowDB's own Beginner window exactly.
      const viaSim = rowOut(calc.calculateDamage(beginnerDamageInput(b.level, out.stats, weapon, null, 'window'))).per_hit;
      if (JSON.stringify(plain(viaSim)) !== JSON.stringify(out.beginnerDamage))
        throw new Error(`beginner input shape drifted: calculateDamage ${JSON.stringify(viaSim)} vs beginnerDamage ${JSON.stringify(out.beginnerDamage)} (lv${b.level} ${b.plan} ${weaponKey})`);
    }
    const skill = weaponKey ? beginnerDamageInput(b.level, out.stats, weapon, null, 'window').includeSkillKeys[0] : null;
    V('character_stats_and_damage_window', `beginner_lv${b.level}_${b.plan}_${weaponKey ?? 'no_weapon'}`, { ...input, weapon_item_id: weapon?.id ?? null, plan: b.plan }, out, SRC.stats, {
      ...synth(b.plan),
      notes: [
        weaponKey
          ? `beginnerDamage = character stat-window range: one basic attack, before defense/level gap/crit (MeowDB models it as ${skill} with mastery 0)`
          : 'No weapon: MeowDB returns beginnerDamage = null; no MeowDB simulator models bare-handed damage (gap)',
        ...(weaponKey === 'razor' ? ['Razor is a Dagger: basic_attack_thief, primary LUK, secondary STR+DEX (eI); REQ LEV 5, so only levels >= 5 are generated'] : []),
        ...(b.plan === 'synthetic_str_dex_split' ? [SYNTH_PLAN_NOTE] : []),
      ],
    });
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// 2. Beginner damage vs the six Maple Island monsters (dmg-simulator engine)
//    Sword: every build. Hand Axe / Wooden Club / Razor: MeowDB AP-plan builds (Razor from Lv 5).
// ---------------------------------------------------------------------------------------------------------------------------
const TUTORIAL_NOTE = 'Tutorial Jr. Sentinel (1) is not offered by the dmg-simulator target list (module 57135 XB drops names starting "Tutorial"); this vector applies the same calculateDamage engine to its simulator-table (module 60782) stats';
for (const b of builds) {
  for (const weaponKey of STARTER_WEAPONS) {
    if (!weaponAllowed(b, weaponKey) || (weaponKey !== 'sword' && b.plan !== 'meowdb_ap_plan')) continue;
    const weapon = items[weaponKey];
    const stats = buildStats[`${b.level}:${b.plan}:${weaponKey}`];
    for (const id of MONSTER_IDS) {
      const m = monsters[id];
      for (const critMode of ['window', 'default_crit']) {
        const input = beginnerDamageInput(b.level, stats, weapon, targetOf(m), critMode);
        V('beginner_damage_vs_monster', `beginner_lv${b.level}_${b.plan}_${weaponKey}_vs_${id}_${critMode}`, { ...input, plan: b.plan, monster_id: id, weapon_item_id: weapon.id }, rowOut(calc.calculateDamage(input)), SRC.dmg, {
          ...synth(b.plan),
          notes: [
            critMode === 'window' ? 'critRateOverride 0 (no crits): per_hit min/max are the defended/level-scaled roll extremes' : 'default crit: 5% rate, +20% damage (MeowDB base values); per_cast_avg_with_crit is the crit expectation',
            ...(m.listed_by_dmg_sim_mob_hit_sim_exp_calc ? [] : [TUTORIAL_NOTE]),
            ...(b.plan === 'synthetic_str_dex_split' ? [SYNTH_PLAN_NOTE] : []),
          ],
        });
      }
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// 2b. Explicit-roll vectors: one hit with chosen action and rolls (FORMULA_PARITY_KERNELS_PRIVATE.physicalRawRollForAction = J,
//     then finalRoll = er). MeowDB's sampler eh draws, per cast: action (inherit melee: swing if rng() < 0.6, else stab), then
//     per hit: J(base = rng(), stat = rng()) and a crit draw. These vectors pin J/er at fixed rolls so the game's sampler can be
//     tested deterministically; the extremes are asserted to equal the per_hit min/max of section 2.
// ---------------------------------------------------------------------------------------------------------------------------
const ROLLS = [[0, 0], [1, 1], [0.5, 0.5], [0, 1], [1, 0], [0.25, 0.75]];
const ROLL_TARGETS = ['2', '9']; // same level (gap 0) and Orange Mushroom (gap 7 at Lv 1)
for (const weaponKey of STARTER_WEAPONS) {
  const level = Math.max(1, items[weaponKey].level_req);
  const b = builds.find((x) => x.level === level && x.plan === 'meowdb_ap_plan');
  if (!b) throw new Error(`no meowdb_ap_plan build at level ${level}`);
  const weapon = items[weaponKey];
  const stats = buildStats[`${b.level}:${b.plan}:${weaponKey}`];
  const extremes = {};
  for (const action of ['swing', 'stab']) {
    for (const [base, stat] of ROLLS) {
      const out = { raw: null, final_by_monster: {} };
      for (const id of ROLL_TARGETS) {
        const input = beginnerDamageInput(b.level, stats, weapon, targetOf(monsters[id]), 'window');
        const priv = K.privateDamageInput(input); // ew(): the input calculateDamage hands to the kernels
        if (priv.physicalDamageMultiplier !== 1 || priv.comboOrdinaryMultiplier !== 1) throw new Error('unexpected Beginner damage multiplier');
        const skill = skillByKey(input.includeSkillKeys[0]);
        const raw = K.physicalRawRollForAction(priv, skill, action, base, stat);
        if (out.raw !== null && out.raw !== raw) throw new Error('raw roll depends on target');
        out.raw = raw;
        const fin = {
          final_truncated: K.finalRoll(raw, priv, skill, 0, 0, 0, true),
          final_untruncated: K.finalRoll(raw, priv, skill, 0, 0, 0, false),
          with_crit_20pct_truncated: K.finalRoll(raw, priv, skill, 0, 20, 0, true),
        };
        out.final_by_monster[id] = fin;
        const e = (extremes[id] ??= { min: Infinity, max: -Infinity });
        if (base === 0 && stat === 0) e.min = Math.min(e.min, fin.final_truncated);
        if (base === 1 && stat === 1) e.max = Math.max(e.max, fin.final_truncated);
      }
      const skillKey = beginnerDamageInput(b.level, stats, weapon, null, 'window').includeSkillKeys[0];
      V('physical_roll_explicit', `beginner_lv${b.level}_${weaponKey}_${action}_base${base}_stat${stat}`, {
        plan: b.plan, level: b.level, weapon_item_id: weapon.id, weaponType: weapon.sim_weapon_type, skill: skillKey, action, baseRoll: base, statRoll: stat,
        damage_input: beginnerDamageInput(b.level, stats, weapon, null, 'window'), monster_ids: ROLL_TARGETS,
      }, out, { ...SRC.kernels, function: 'FORMULA_PARITY_KERNELS_PRIVATE.physicalRawRollForAction (= J) on privateDamageInput (= ew), then finalRoll (= er)' }, {
        synthetic_inputs: true,
        notes: ['Roll values are test points. raw = J(ew(damage_input), skill, action, baseRoll, statRoll); final = er(raw, ew(damage_input with target = monster), skill, ignore 0, critDmg 0|20, ironArrow 0, truncate). For a Beginner the en() pre-multiplier (physicalDamageMultiplier x combo) is 1.'],
      });
    }
  }
  for (const id of ROLL_TARGETS) {
    const ref = vectors.find((v) => v.mechanic === 'beginner_damage_vs_monster' && v.case_id === `beginner_lv${b.level}_${b.plan}_${weaponKey}_vs_${id}_window`);
    if (!ref || ref.outputs.per_hit.min !== extremes[id].min || ref.outputs.per_hit.max !== extremes[id].max)
      throw new Error(`explicit-roll extremes ${JSON.stringify(extremes[id])} != per_hit of ${weaponKey} vs ${id}`);
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// 3. Accuracy / hit chance (accuracy-sim) + synthetic grid cross-checked against the /formulas page calculator
// ---------------------------------------------------------------------------------------------------------------------------
for (const b of builds) {
  const stats = buildStats[`${b.level}:${b.plan}:sword`];
  for (const id of MONSTER_IDS) {
    const m = monsters[id];
    const input = { attackType: 'physical', acc: stats.acc, charLevel: b.level, monLevel: m.level, monAvoid: m.avoid };
    V('accuracy_hit_chance_vs_monster', `beginner_lv${b.level}_${b.plan}_vs_${id}`, { ...input, plan: b.plan, monster_id: id }, calc.calculateAccuracy(input), SRC.acc, {
      ...synth(b.plan),
      notes: ['Every Maple Island monster has AVOID 0, so the oracle returns hitRate 100 via its avoid<=0 early return', ...(b.plan === 'synthetic_str_dex_split' ? [SYNTH_PLAN_NOTE] : [])],
    });
  }
}
for (const playerLevel of [1, 10]) {
  for (const monLevel of [playerLevel, playerLevel + 3, playerLevel + 10, playerLevel + 20]) {
    for (const monAvoid of [0, 5, 10, 20]) {
      const base = { attackType: 'physical', charLevel: playerLevel, monLevel, monAvoid };
      const full = calc.calculateAccuracy({ ...base, acc: 0 });
      V('accuracy_acc_milestones', `plv${playerLevel}_mlv${monLevel}_avoid${monAvoid}`, base, { min: full.min, max: full.max, milestones: full.milestones }, SRC.acc, {
        synthetic_inputs: true,
        notes: ['min = ACC where the hit chance first exceeds 0, max = ACC for 100%; milestones = ACC for 25/50/75/90/95/100% (bisection, 64 steps). The page displays Math.ceil of each.'],
      });
      for (const acc of [8, 15, 25, 40, 80]) {
        const input = { ...base, acc };
        const hitRate = calc.calculateAccuracy(input).hitRate;
        const fp = formulasCalc('outgoing-hit', { accuracy: acc, playerLevel, mobLevel: monLevel, mobAvoid: monAvoid });
        V('accuracy_hit_chance_grid', `acc${acc}_plv${playerLevel}_mlv${monLevel}_avoid${monAvoid}`, input, { hitRate, outgoing_hit_rate_pct: calc.outgoingHitRate(acc, monAvoid, playerLevel, monLevel) }, SRC.acc, {
          synthetic_inputs: true,
          cross_checks: [xc('outgoing-hit', fp, Math.abs(num(fpRow(fp.outputs, 'Hit chance').minimum) - hitRate) <= 0.05 + 1e-9)],
        });
      }
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------------------
// 4. Avoid / incoming damage (avoidability-sim, mob-hit-sim) + grid cross-checked against /formulas
// ---------------------------------------------------------------------------------------------------------------------------
for (const b of builds) {
  const stats = buildStats[`${b.level}:${b.plan}:sword`];
  for (const id of MONSTER_IDS) {
    const m = monsters[id];
    const input = { charLevel: b.level, charAvoid: stats.avoid, charWdef: stats.wdef, charMdef: stats.mdef, shieldWdef: 0, clawGuardLevel: 0, monLevel: m.level, monAcc: m.acc, monPdmg: m.pdmg, monMdmg: m.mdmg };
    V('avoid_and_incoming_damage_vs_monster', `beginner_lv${b.level}_${b.plan}_vs_${id}`, { ...input, plan: b.plan, monster_id: id }, calc.calculateAvoidability(input), SRC.avoid, {
      ...synth(b.plan),
      notes: [
        'No armor modeled: charWdef/charMdef are the derived floor(STR/4)/floor(INT/4) only',
        'magic.* is the kernel output for M.DMG 0 (taken clamps to 1); the page hides the magic block when M.DMG is 0',
        ...(b.plan === 'synthetic_str_dex_split' ? [SYNTH_PLAN_NOTE] : []),
      ],
    });
  }
  const dangerInput = { charLevel: b.level, charHp: stats.hp, charMp: stats.mp, charWdef: stats.wdef, charMdef: stats.mdef };
  const rows = plain(mobDanger.computeMobDangerRows(dangerInput)).filter((r) => MONSTER_IDS.includes(String(r.mob.id)));
  const expectIds = MONSTER_IDS.filter((id) => monsters[id].listed_by_dmg_sim_mob_hit_sim_exp_calc);
  if (rows.map((r) => String(r.mob.id)).sort().join() !== [...expectIds].sort().join()) throw new Error('mob-hit-sim rows do not match the XB-listed Maple Island monsters');
  const omitted = MONSTER_IDS.filter((id) => !expectIds.includes(id));
  V('mob_hit_danger', `beginner_lv${b.level}_${b.plan}`, { ...dangerInput, plan: b.plan }, Object.fromEntries(rows.map((r) => [String(r.mob.id), { name: r.mob.name, levelDiff: r.levelDiff, ...r.danger }])), SRC.mobhit, {
    ...synth(b.plan),
    notes: [
      ...(omitted.length ? [`No row for ${omitted.map((id) => `${monsters[id].name} (${id})`).join(', ')}: computeMobDangerRows lists only IW.filter(XB), which drops names starting "Tutorial". Its contact damage is covered by avoid_and_incoming_damage_vs_monster and monster_touch_damage_display.`] : []),
      ...(b.plan === 'synthetic_str_dex_split' ? [SYNTH_PLAN_NOTE] : []),
    ],
  });
}
for (const id of MONSTER_IDS) {
  const m = monsters[id];
  const out = calc.incomingDamage(m.pdmg, 0, 1);
  const display = `${out.rawMin}-${out.rawMax}`;
  V('monster_touch_damage_display', `monster_${id}_raw_range`, { monster_attack: m.pdmg, player_def: 0, player_level: 1 }, { ...out, display }, SRC.incoming, {
    cross_checks: [{ oracle_source: { oracle: 'monster-page', function: 'Touch DMG display' }, inputs: { monster_id: id, url: m.source.url }, outputs: { display: m.detail_page_touch_dmg_display }, agrees: m.detail_page_touch_dmg_display === display }],
  });
}
for (const [plv, mlv] of [[1, 1], [5, 3], [10, 8], [10, 15], [20, 8]]) {
  for (const avoid of [0, 6, 20, 50, 150]) {
    for (const monAcc of [33, 62]) {
      const fp = formulasCalc('incoming-hit', { mobAccuracy: monAcc, playerAvoid: avoid, playerLevel: plv, mobLevel: mlv });
      const pct = calc.incomingHitRate(monAcc, avoid, plv, mlv);
      V('incoming_hit_chance_grid', `macc${monAcc}_avoid${avoid}_plv${plv}_mlv${mlv}`, { monAcc, charAvoid: avoid, charLevel: plv, monLevel: mlv }, { monster_hit_chance_pct: pct, dodge_rate_pct: 100 - pct }, { oracle: 'avoidability-sim', function: 'incomingHitRate (module 4790 export e_)' }, {
        synthetic_inputs: true,
        cross_checks: [xc('incoming-hit', fp, Math.abs(num(fpRow(fp.outputs, 'Monster hit chance').minimum) - pct) <= 0.05 + 1e-9)],
      });
    }
  }
}
for (const atk of [3, 17, 100, 1000]) {
  for (const def of [0, 3, 14, 50, 300]) {
    for (const lvl of [1, 10, 30]) {
      const fp = formulasCalc('incoming-damage', { attack: atk, defense: def, level: lvl });
      const dmg = calc.incomingDamage(atk, def, lvl);
      const row = fpRow(fp.outputs, 'Damage taken');
      V('incoming_damage_curve', `atk${atk}_def${def}_lv${lvl}`, { monster_attack: atk, player_def: def, player_level: lvl }, dmg, SRC.incoming, {
        synthetic_inputs: true,
        cross_checks: [xc('incoming-damage', fp, num(row.minimum) === dmg.takenMin && num(row.maximum) === dmg.takenMax)],
      });
    }
  }
}
for (const shield of [0, 1, 20, 100, 500]) {
  const fp = formulasCalc('guards', { guard: 'shield', shield });
  const g = calc.guardChanceFor(shield, 0);
  V('shield_guard_chance', `shield_wdef_${shield}`, { shield_wdef: shield, claw_guard_level: 0 }, { guard_chance: g }, { oracle: 'avoidability-sim', function: 'guardChanceFor (module 4790 export eC)' }, {
    synthetic_inputs: true,
    cross_checks: [xc('guards', fp, Math.abs(num(fpRow(fp.outputs, 'Shield Guard chance').minimum) - 100 * g) <= 0.05 + 1e-9)],
  });
}

// ---------------------------------------------------------------------------------------------------------------------------
// 5. Level gap, defense curve, clamp, crit
// ---------------------------------------------------------------------------------------------------------------------------
const PLV = 10;
for (const gap of [-5, 0, 1, 5, 9, 10, 20]) {
  const fp = formulasCalc('level-gap', { raw: 1000, levelGap: Math.max(0, gap) });
  const scale = K.levelScale(PLV, PLV + gap);
  V('level_gap_scale', `gap_${gap}`, { player_level: PLV, target_level: PLV + gap, gap }, { level_scale: scale }, { ...SRC.kernels, function: 'FORMULA_PARITY_KERNELS_PRIVATE.levelScale (= function Z)' }, {
    cross_checks: [xc('level-gap', fp, Math.abs(num(fpRow(fp.outputs, 'Damage multiplier').minimum) - 100 * scale) <= 0.05 + 1e-9, gap < 0 ? 'formulas page input is "Monster levels above you" (min 0); a negative gap is entered as 0' : undefined)],
  });
}
const finalRollInput = (pdef, mdef, targetLevel) => ({ level: PLV, target: { level: targetLevel, pdef, mdef, element: '' }, elementalTier: 'neutral', amplificationDamagePct: 0 });
const basicAttack = { key: 'basic_attack_warrior', isMagic: false };
for (const raw of [14.59776, 60.63376, 100, 1000, 150000]) {
  for (const def of [0, 10, 30, 100, 500]) {
    const t = finalRollInput(def, 0, PLV);
    const fp = formulasCalc('monster-defense', { raw, defense: def });
    const untrunc = K.finalRoll(raw, t, basicAttack, 0, 0, 0, false);
    const shown = num(fpRow(fp.outputs, 'Damage after defense').minimum);
    V('defense_curve_and_final_clamp', `raw${raw}_pdef${def}`, { raw, pdef: def, player_level: PLV, target_level: PLV, wdef_ignore: 0, crit_damage_pct: 0 }, {
      final_truncated: K.finalRoll(raw, t, basicAttack, 0, 0, 0, true),
      final_untruncated: untrunc,
      with_crit_20pct_truncated: K.finalRoll(raw, t, basicAttack, 0, 20, 0, true),
    }, { ...SRC.kernels, function: 'FORMULA_PARITY_KERNELS_PRIVATE.finalRoll (= function er)' }, {
      synthetic_inputs: true,
      cross_checks: [xc('monster-defense', fp, untrunc >= 99999 ? shown >= 99999 : Math.abs(shown - untrunc) <= 0.5 + 1e-9, 'formulas page shows the defended value before the 1..99,999 clamp, rounded to an integer for display')],
    });
  }
}
for (const raw of [100, 1000]) {
  for (const def of [30]) {
    for (const ign of [0.2, 1]) {
      const t = finalRollInput(def, 0, PLV);
      V('defense_ignore', `raw${raw}_pdef${def}_ignore${ign}`, { raw, pdef: def, wdef_ignore: ign }, { final_truncated: K.finalRoll(raw, t, basicAttack, ign, 0, 0, true) }, { ...SRC.kernels, function: 'FORMULA_PARITY_KERNELS_PRIVATE.finalRoll (= function er)' }, { synthetic_inputs: true });
    }
  }
}
for (const raw of [100, 1000]) {
  const t = finalRollInput(0, 30, PLV);
  V('magic_defense_curve', `raw${raw}_mdef30`, { raw, mdef: 30, skill: 'energy_bolt (magic)' }, { final_truncated: K.finalRoll(raw, t, { key: 'energy_bolt', isMagic: true }, 0, 0, 0, true) }, { ...SRC.kernels, function: 'FORMULA_PARITY_KERNELS_PRIVATE.finalRoll (= function er)' }, { synthetic_inputs: true });
}
for (const value of [0, 0.4, 1.7, 99999.9, 150000]) {
  const fp = formulasCalc('clamp', { value });
  const fin = K.finalRoll(value, finalRollInput(0, 0, PLV), basicAttack, 0, 0, 0, true);
  V('final_clamp', `value_${value}`, { value }, { final: fin }, { ...SRC.kernels, function: 'FORMULA_PARITY_KERNELS_PRIVATE.finalRoll (= function er), no defense' }, {
    synthetic_inputs: true,
    cross_checks: [xc('clamp', fp, num(fpRow(fp.outputs, 'Final damage').minimum) === fin)],
  });
}
for (const [normal, cd, cr] of [[1000, 20, 5], [60, 20, 5], [172, 20, 5], [1000, 50, 20], [14, 20, 5]]) {
  const fp = formulasCalc('critical', { normal, criticalDamage: cd, criticalRate: cr });
  V('crit_expectation', `normal${normal}_cd${cd}_cr${cr}`, fp.inputs, fp.outputs, SRC.formulas('critical'), {
    synthetic_inputs: true,
    notes: ['inputs are the exact /formulas "critical" calculator fields (criticalDamage and criticalRate in percent); outputs are its display strings (toLocaleString, maximumFractionDigits 0)'],
  });
}

// ---------------------------------------------------------------------------------------------------------------------------
// 6. Guide worked examples
// ---------------------------------------------------------------------------------------------------------------------------
const gText = lines(pages['guide-damage'].html);
const nextAfterPrefix = (prefix) => {
  const i = gText.findIndex((l) => l.startsWith(prefix));
  return i < 0 ? null : gText[i + 1];
};
const guideL30 = {
  acc: Number(nextAfterPrefix('floor((1.2 × 30 + 2 × 30 + 0.6 × 4) / 2.5 + 10)')),
  eva: Number(nextAfterPrefix('floor(4 / 3) + floor(30 / 6) + 5')),
  magic: Number(nextAfterPrefix('floor(4 / 2)')),
  wdef: Number(nextAfterPrefix('floor(132 / 4)')),
  mdef: Number(nextAfterPrefix('floor(4 / 4)')),
  window: (gText.find((l) => /^Character-window damage range: \d+-\d+$/.test(l)) ?? '').replace('Character-window damage range: ', ''),
  power_strike: nextAfterPrefix('A skill applies its own damage value on top.'),
  available_ap: Number(gText[gText.indexOf('Available AP') + 2]),
  weapon_watk: Number((/^with (\d+)$/.exec(gText[gText.indexOf('Gladius', gText.indexOf('Worked example: level 30 Warrior')) + 1] ?? '') ?? [])[1]),
};
{
  const m = /^(\d+) STR \+ (\d+) DEX \+ (\d+) INT \+ (\d+) LUK$/.exec(gText[gText.indexOf('AP plan') + 1] ?? '');
  if (!m) throw new Error('damage guide: could not parse the level-30 AP plan line');
  guideL30.ap_plan = { str: Number(m[1]), dex: Number(m[2]), int: Number(m[3]), luk: Number(m[4]) };
}
// Inputs come from the guide text; MeowDB's own AP plan (13805 lM) and stat-point total (jQ) are recorded as cross-checks.
const l30Input = { klass: 'warrior', subJob: null, level: 30, ap: guideL30.ap_plan, equipment: { weapon: equipWeapon(items.gladius) }, skillBonuses: null };
const l30 = plain(calc.calculateCharacterStats(l30Input));
const l30Plan = plain(classHelpers.lM('warrior', 30));
V('guide_example_lv30_warrior_stats', 'gladius_lv30_warrior', { ...l30Input, weapon_item_id: items.gladius.id }, l30, SRC.stats, {
  guide_expected: { url: pages['guide-damage'].url, ap_plan: guideL30.ap_plan, available_ap: guideL30.available_ap, weapon_watk: guideL30.weapon_watk, acc: guideL30.acc, eva: guideL30.eva, magic: guideL30.magic, wdef: guideL30.wdef, mdef: guideL30.mdef },
  agrees_with_guide:
    l30.stats.acc === guideL30.acc && l30.stats.avoid === guideL30.eva && l30.stats.matk === guideL30.magic && l30.stats.wdef === guideL30.wdef && l30.stats.mdef === guideL30.mdef &&
    l30.stats.watk === guideL30.weapon_watk && classHelpers.jQ(30) === guideL30.available_ap,
  cross_checks: [
    { oracle_source: { oracle: 'character-builder', function: 'module 13805 lM (MeowDB default AP plan) and jQ (total stat points)' }, inputs: { klass: 'warrior', level: 30 }, outputs: { ap_plan: l30Plan, total_stat_points: classHelpers.jQ(30) }, agrees: JSON.stringify(l30Plan) === JSON.stringify(guideL30.ap_plan) && classHelpers.jQ(30) === guideL30.available_ap, note: 'the guide calls 132/30/4/4 "the typical AP plan produced by current level-30 Warrior weapon requirements"' },
  ],
});
const l30Dmg = {
  mainClass: 'Warrior', subJob: 'Warrior (1st)', level: 30, primary: l30.primary, secondary: l30.secondary, totalInt: l30.stats.int, totalLuk: l30.stats.luk, baseWatk: items.gladius.watk, extraWatk: 0, matk: l30.stats.matk, matkIncludesDerived: true, bonusAp: 0,
  masteryLvl: 0, weaponType: items.gladius.sim_weapon_type, weaponAttackSpeed: items.gladius.attack_speed, activePassiveKeys: [], critRateOverride: 0, critDamageOverride: 0, elementalTier: 'neutral', healAlliesInRange: 0, boosterActive: false,
  target: null, includeSkillKeys: ['basic_attack_warrior', 'power_strike'],
};
const l30Res = plain(calc.calculateDamage(l30Dmg));
const rowByKey = (res, key) => res.rows.find((r) => r.skillKey === key);
const winRow = rowByKey(l30Res, 'basic_attack_warrior');
const psRow = rowByKey(l30Res, 'power_strike');
const fpPhys = (skill) => formulasCalc('physical-damage', { skill, mastery: 0, attack: items.gladius.watk, primary: l30.primary, secondary: l30.secondary, multiplier: items.gladius.weapon_multipliers.swing, attackPower: 0 });
const fpL30 = fpPhys(100);
const fpPS = fpPhys(skillByKey('power_strike').coefficient);
const fpDerived = formulasCalc('derived-stats', { level: 30, ...guideL30.ap_plan });
const fpRaw = (fp) => [fpRow(fp.outputs, 'Raw damage').minimum, fpRow(fp.outputs, 'Raw damage').maximum].map(num);
V('guide_example_lv30_warrior_damage_window', 'gladius_lv30_warrior_basic_attack', { ...l30Dmg, weapon_item_id: items.gladius.id }, { basic_attack: { per_hit: winRow.perHit, per_cast: winRow.perCast, display_min: dmgDisplay(winRow.perHit.min), display_max: dmgDisplay(winRow.perHit.max) }, power_strike: { per_hit: psRow.perHit, per_cast: psRow.perCast, display_min: dmgDisplay(psRow.perHit.min), display_max: dmgDisplay(psRow.perHit.max) } }, SRC.dmg, {
  guide_expected: { url: pages['guide-damage'].url, window: guideL30.window, power_strike: guideL30.power_strike },
  agrees_with_guide: `${winRow.perCast.min}-${winRow.perCast.max}` === guideL30.window && `${psRow.perCast.min}-${psRow.perCast.max}` === guideL30.power_strike,
  cross_checks: [
    xc('physical-damage', fpL30, fpRaw(fpL30).join('-') === guideL30.window, `Gladius example: formulas page displays ${fpRaw(fpL30).join('-')} (untruncated raw range rounded by toLocaleString, maximumFractionDigits 0); guide, character window and dmg-simulator truncate to ${guideL30.window}`),
    xc('physical-damage', fpPS, fpRaw(fpPS).join('-') === guideL30.power_strike, `Power Strike (skill 260): formulas page displays ${fpRaw(fpPS).join('-')}; guide and dmg-simulator give ${guideL30.power_strike}`),
    xc('derived-stats', fpDerived, ['Warrior ACC', 'EVA', 'Magic', 'WDEF', 'MDEF'].map((l) => num(fpRow(fpDerived.outputs, l).minimum)).join() === [l30.stats.acc, l30.stats.avoid, l30.stats.matk, l30.stats.wdef, l30.stats.mdef].join()),
  ],
});

// Beginner guide: starter weapon hits-to-kill vs a level 1 Snail at 13/4/4/4 (all 9 creation AP in STR).
const bText = lines(pages['guide-beginner'].html);
const wi = bText.indexOf('Weapon', bText.findIndex((l) => l.startsWith('Against a level 1 Snail')));
const guideHits = {};
for (let i = wi + 4; i < wi + 4 + 12; i += 4) guideHits[bText[i]] = [bText[i + 1], bText[i + 2], bText[i + 3]].map((s) => Number(s.replace(' hits', '')));
const guideBeginnerAp = (() => {
  const s = bText.findIndex((l) => l.startsWith('Against a level 1 Snail'));
  const m = /\((\d+) STR,\s*(\d+)\s*DEX\s*,\s*(\d+) INT,\s*(\d+)\s*LUK/.exec(bText.slice(s, s + 8).join(' '));
  if (!m) throw new Error('beginner guide: could not parse the starter-weapon stat line');
  return { str: Number(m[1]), dex: Number(m[2]), int: Number(m[3]), luk: Number(m[4]) };
})();
if (JSON.stringify(guideBeginnerAp) !== JSON.stringify(plain(classHelpers.lM('beginner', 1))))
  discrepancies.push(`beginner guide starter-weapon stats ${JSON.stringify(guideBeginnerAp)} differ from MeowDB's AP plan lM("beginner", 1)`);
const snail = monsters['2'];
for (const k of ['sword', 'hand_axe', 'wooden_club']) {
  const it = items[k];
  const input = { klass: 'beginner', subJob: null, level: 1, ap: guideBeginnerAp, equipment: { weapon: equipWeapon(it) }, skillBonuses: null };
  const bd = plain(calc.calculateCharacterStats(input)).beginnerDamage;
  const hits = [bd.min, bd.avg, bd.max].map((d) => Math.ceil(snail.hp / d));
  const expected = guideHits[it.name];
  V('guide_example_beginner_starter_weapon_hits', `lv1_13str_${k}_vs_snail`, { ...input, weapon_item_id: it.id, monster_id: '2', monster_hp: snail.hp }, { beginner_damage: bd, hits_at_min_avg_max: hits }, SRC.stats, {
    notes: ['hits = ceil(Snail HP / damage) computed here from the oracle output; Snail has 0 P.DEF and is same level, so the stat-window range is the landed range'],
    guide_expected: { url: pages['guide-beginner'].url, hits_at_min_avg_max: expected ?? null },
    agrees_with_guide: Array.isArray(expected) && expected.join() === hits.join(),
  });
}

// ---------------------------------------------------------------------------------------------------------------------------
// 7. EXP (exp-calculator) levels 1-30, checked against the EXP table guide
// ---------------------------------------------------------------------------------------------------------------------------
const expIIFE = extract({ chunk: 'expPage', needle: '(function(e,t,r){if(!Number.isInteger(e)||e<1||e>=d.Mg)', mode: 'group' });
const expRemaining = evalSnippet(expIIFE.text, { d: expCum });
const killsSnippet = extract({ chunk: 'expPage', needle: 'P=w&&E?(t=w.expRemaining', skip: 2, mode: 'item' });
const kills = (w, E) => evalSnippet(`(()=>{let t,r;return ${killsSnippet.text}})()`, { w, E });
const eText = lines(pages['guide-exp'].html);
const guideExp = {};
{
  let i = eText.indexOf('Cumulative from lv 1');
  for (let lv = 1; lv <= 30; lv++) {
    i = eText.indexOf(String(lv), i + 1);
    guideExp[lv] = { exp_to_next: Number(eText[i + 1].replace(/,/g, '')), cumulative_through_level: Number(eText[i + 2].replace(/,/g, '')) };
  }
}
for (let lv = 1; lv <= 30; lv++) {
  const res = plain(expRemaining(lv, 0, lv + 1));
  const fp = formulasCalc('exp-table', { level: lv });
  const out = {
    exp_to_next_level: expTable.ML(lv),
    total_exp_at_level_start: expCum.H1(lv, 0),
    cumulative_through_level: expTable.Bq(lv),
    calculator_result_lv_to_next: res,
    ...(lv <= 10 ? { kills_lv_to_next_by_monster: Object.fromEntries(MONSTER_IDS.map((id) => [id, kills(res.result, { exp: monsters[id].exp })])) } : {}),
  };
  V('exp_requirement', `level_${lv}`, { level: lv, current_exp: 0, target_level: lv + 1 }, out, SRC.exp, {
    guide_expected: { url: pages['guide-exp'].url, ...guideExp[lv] },
    agrees_with_guide: guideExp[lv].exp_to_next === out.exp_to_next_level && guideExp[lv].cumulative_through_level === out.cumulative_through_level,
    cross_checks: [xc('exp-table', fp, num(fpRow(fp.outputs, 'EXP to next level').minimum) === out.exp_to_next_level && num(fpRow(fp.outputs, 'Total from Lv 1').minimum) === out.cumulative_through_level)],
    ...(lv <= 10 ? { notes: ['kills = Math.ceil(expRemaining / monster EXP) (exp-calculator page expression); no level-difference or party EXP modifiers are applied by the calculator', 'Tutorial Jr. Sentinel (1) is not in the exp-calculator monster list (module 57135 XB); its kill count uses the same expression with its simulator-table EXP'] } : {}),
  });
}
V('exp_calculator_validation', 'lv10_to_lv30_default', { currentLevel: 10, currentExp: 0, targetLevel: 30 }, expRemaining(10, 0, 30), SRC.exp, { notes: ['the exp-calculator page default inputs'] });
V('exp_calculator_validation', 'reject_exp_at_requirement', { currentLevel: 1, currentExp: 15, targetLevel: 2 }, expRemaining(1, 15, 2), SRC.exp);
V('exp_calculator_validation', 'reject_target_not_above_current', { currentLevel: 5, currentExp: 0, targetLevel: 5 }, expRemaining(5, 0, 5), SRC.exp);
V('exp_calculator_validation', 'max_level_99_to_100', { currentLevel: 99, currentExp: 0, targetLevel: 100 }, expRemaining(99, 0, 100), SRC.exp);

// Self-consistency: every vector agrees with its cross-checks where the comparison is exact.
{
  const kernelZero = calc.incomingDamage(0, 0, 1);
  const dangerZero = plain(mobDanger.computeMobDangerRows({ charLevel: 1, charHp: 50, charMp: 5, charWdef: 3, charMdef: 1 })).find((r) => String(r.mob.id) === '2').danger;
  if (kernelZero.takenMin !== dangerZero.magicDamageMinAfterDef)
    discrepancies.push(`zero attack: incomingDamage(0, ...) (avoidability-sim kernel) returns taken ${kernelZero.takenMin} (clamp to >= 1) while mob-hit-sim guards attack <= 0 to ${dangerZero.magicDamageMinAfterDef}; chosen: 0 (a monster with M.DMG 0 deals no magic damage)`);
  const lv1 = vectors.find((v) => v.case_id === 'beginner_lv1_meowdb_ap_plan_sword_vs_2_default_crit');
  const closed = lv1.outputs.per_cast.avg * (1 + 0.05 * 0.2);
  if (Math.abs(closed - lv1.outputs.per_cast_avg_with_crit) > 1e-9)
    discrepancies.push(`crit expectation rounding path: guide Normal x (1 + c x d) = ${closed} for the Lv1 Sword vs Snail case, dmg-simulator perCastAvgCrit = ${lv1.outputs.per_cast_avg_with_crit} (mixes separately 0.1-rounded normal and crit averages); same formula, simulator value kept in the vectors`);
}
for (const v of vectors) {
  if (v.agrees_with_guide === false) discrepancies.push(`${v.mechanic}/${v.case_id}: simulator output disagrees with the guide (${JSON.stringify(v.guide_expected)})`);
  for (const c of v.cross_checks ?? []) if (c.agrees === false) discrepancies.push(`${v.mechanic}/${v.case_id}: ${c.oracle_source.oracle} (${c.oracle_source.function}) disagrees${c.note ? ' - ' + c.note : ''}`);
}

// ---------------------------------------------------------------------------------------------------------------------------
// Verbatim reference extracts -> docs/canonical/oracles/<tool>.js.txt
// ---------------------------------------------------------------------------------------------------------------------------
const C4790 = (needle, mode, title, extra = {}) => ({ chunk: 'calc', module: '4790', needle, mode, title, ...extra });
const EXTRACTS = {
  'dmg-simulator': [
    C4790('let f={', 'stmt', 'weapon action multipliers f + MeowDB weapon subtype -> simulator weapon type w'),
    C4790('function b(e)', 'fn', 'b: subtype -> weapon type'),
    C4790('let M=(', 'stmt', 'M: clamp, k: finite-or-default'),
    C4790('function y(e)', 'fn', 'y: close-range actions for ranged weapons'),
    C4790('let v={', 'stmt', 'v: damage action per skill key (basic_attack_* = "inherit")'),
    C4790('let R={', 'stmt', 'R: elemental multipliers; H: amplification MP skills; L: magic/heal/pierce flags; B: passive bonuses'),
    C4790('function E(e)', 'fn', 'E: mastery factor (MasteryLevel/10 + 0.1) * 0.8, level clamped 0-10'),
    C4790('function F(e,t,a,i,r)', 'fn', 'F: MIN (both rolls 0) / MAX (both rolls 1) / midpoint of the raw roll'),
    C4790('function J(e,t,a,i,r,n,l)', 'fn', 'J: raw physical roll (base roll i, stat roll r)'),
    C4790('function K(e,t)', 'fn', 'K: action resolution (inherit = min of mins / max of maxes, avg 60% swing + 40% stab)'),
    C4790('function j(e,t)', 'fn', 'j: weapon multiplier info'),
    C4790('function G(e,t,a)', 'fn', 'G: ordinary magic raw roll'),
    C4790('function X(e,t)', 'fn', 'X: element tier lookup from the monster element string'),
    C4790('let z={', 'stmt', 'z: element composition pairs'),
    C4790('function V(e,t)', 'fn', 'V: element rating 0-3'),
    C4790('function Q(e,t)', 'fn', 'Q: elemental multiplier'),
    C4790('function Z(e,t)', 'fn', 'Z: level-gap scale (attacker level e, target level t)'),
    C4790('function er(e,t,a)', 'fn', 'er: final roll = defense curve * element * level scale, then clamp(1, 99999) and trunc'),
    C4790('function en(e,t)', 'fn', 'en: per-hit {min,max,avg} (avg rounded to 0.1)'),
    C4790('function el(e,t,a)', 'fn', 'el: per-hit range for one explicit action'),
    C4790('function eg(e)', 'fn', 'eg: passive totals incl. base crit 5% / +20%'),
    C4790('function ew(e)', 'fn', 'ew: merge passive totals into the damage input'),
    C4790('function eb(e)', 'fn', 'eb = calculateDamage'),
    C4790('function ex(e,t)', 'fn', 'ex: row assembly (perHit = en(..., 7th arg false): min/max still trunc(clamp) - that flag only drops the Shadow Partner mirror; avg = round(10*x)/10 of the untruncated midpoint; perCastAvgCrit = crit expectation)'),
    C4790('let eH=', 'stmt', 'eH = FORMULA_PARITY_KERNELS_PRIVATE'),
    C4790('function eu()', 'fn', 'eu: xorshift32 RNG with fixed seed 0x6d2b79f5 (MeowDB Monte Carlo summaries only; not a game RNG)'),
    C4790('function ed(e,t,a,i,r)', 'fn', 'ed: one sampled raw roll = J(input, skill, action, base = rng(), stat = rng())'),
    C4790('function eh(e,t,a,i,r,n,l)', 'fn', 'eh: one sampled cast: action draw once per cast (inherit melee: swing if rng() < 0.6 else stab), then per hit: raw roll (ed), crit draw rng() < critRate, er'),
    { chunk: 'skills', module: '57135', needle: '{key:"basic_attack_warrior",', mode: 'item', title: 'skill catalog entry: basic_attack_warrior' },
    { chunk: 'skills', module: '57135', needle: '{key:"basic_attack_thief",', mode: 'item', title: 'skill catalog entry: basic_attack_thief (Claw, Dagger: the Beginner path for the Razor)' },
    { chunk: 'skills', module: '57135', needle: '{key:"power_strike",', mode: 'item', title: 'skill catalog entry: power_strike' },
    { chunk: 'dmgUi', needle: 'function E(e){return isFinite(e)&&0!==e?Math.floor(e)', mode: 'fn', title: 'dmg-simulator table display: floor + en-US grouping' },
    { chunk: 'dmgUi', needle: 'aG=(0,r.useMemo)(()=>({mainClass:', mode: 'item', title: 'dmg-simulator input assembly' },
  ],
  'accuracy-sim': [
    { chunk: 'calc', module: '58903', whole: true, title: 'module 58903: outgoingHitRate (i) + calculateAccuracy (r)' },
    { chunk: 'accPage', module: '47938', needle: 'async function c(e,a){', mode: 'fn', title: 'module 47938 dispatcher: operation -> calculator export' },
    { chunk: 'accPage', module: '40168', needle: 'F=(0,i.useMemo)(()=>({operation:"accuracy"', mode: 'item', title: 'accuracy-sim input assembly (acc = typed ACC + potion)' },
    { chunk: 'accPage', module: '40168', needle: 'h=[{id:"none",acc:0', mode: 'item', title: 'accuracy potions' },
    { chunk: 'accPage', module: '40168', needle: 'q=I>=99.5?{', mode: 'item', title: 'hit-rate display label (>=99.5 shows "100%", else toFixed(1))' },
  ],
  'avoidability-sim': [
    C4790('function u(e)', 'fn', 'u: shield guard chance'),
    C4790('function e_(e,t,a,i)', 'fn', 'e_ = incomingHitRate'),
    C4790('function eP(e,t,a)', 'fn', 'eP = incomingDamage (rolls 1.1 / 1.3 / 1.5)'),
    C4790('function eC(e,t)', 'fn', 'eC = guardChanceFor'),
    C4790('function eS(e)', 'fn', 'eS = calculateAvoidability'),
    { chunk: 'avoidPage', needle: 'U=(0,r.useMemo)(()=>({operation:"avoidability"', mode: 'item', title: 'avoidability-sim input assembly' },
  ],
  'mob-hit-sim': [
    { chunk: 'mobDanger', module: '42150', whole: true, title: 'module 42150: computeMobDangerRows' },
    { chunk: 'skills', module: '57135', needle: 'function W(e){return!!e&&e.hp>0', mode: 'fn', title: 'module 57135 XB (= W): monster list filter (drops hp/exp 0, names starting "Tutorial", invincible, "(alt)")' },
    C4790('function eP(e,t,a)', 'fn', 'eP = incomingDamage'),
    { chunk: 'monsterCombat', module: '92700', needle: ',2:{sprite', skip: 1, mode: 'item', title: 'monsterCombat[2] Snail (no attacks: contact uses P.DMG at 100%)' },
    { chunk: 'monsterCombat', module: '92700', needle: ',9:{sprite', skip: 1, mode: 'item', title: 'monsterCombat[9] Orange Mushroom' },
    { chunk: 'mobHitPage', needle: 'K=(0,u.useMemo)(()=>({operation:"mob-danger"', mode: 'item', title: 'mob-hit-sim input assembly' },
  ],
  'exp-calculator': [
    { chunk: 'exp', module: '17401', whole: true, title: 'module 17401: EXP table jy (lv 1-99), ML, Bq' },
    { chunk: 'exp', module: '27279', needle: 'let m=r.jy,h=100,p=(()=>{', mode: 'stmt', title: 'module 27279: cumulative prefix sums p, max level h=100' },
    { chunk: 'exp', module: '27279', needle: 'function b(e,t){if(!Number.isFinite(e)||e<1||e>h)', mode: 'fn', title: 'module 27279 b = H1: total EXP at (level, exp)' },
    { chunk: 'expPage', needle: '(function(e,t,r){if(!Number.isInteger(e)||e<1||e>=d.Mg)', mode: 'group', title: 'exp-calculator validation + EXP remaining (executed verbatim, d = module 27279)' },
    { chunk: 'expPage', needle: 'P=w&&E?(t=w.expRemaining', mode: 'item', title: 'kills needed = Math.ceil(expRemaining / mob EXP) (executed verbatim)' },
  ],
  'character-builder': [
    C4790('function eD(e,t,a,i,r)', 'fn', 'eD = statDerivedAccuracy'),
    C4790('function eT(e,t,a,r,n)', 'fn', 'eT: final stats (ACC, EVA, WDEF, MDEF, Magic, HP/MP)'),
    C4790('function eA(e,t,a)', 'fn', 'eA: primary/secondary stat by weapon'),
    C4790('function eI(e)', 'fn', 'eI = calculateCharacterStats (incl. beginnerDamage window)'),
    { chunk: 'calcDeps', module: '13805', needle: 'function x(e){', mode: 'fn', title: '13805 x = jQ: total stat points 25 + 5 * (level - 1)' },
    { chunk: 'calcDeps', module: '13805', needle: 'function T(e,t,n){', mode: 'fn', title: '13805 T = lM: MeowDB default AP plan' },
    { chunk: 'calcDeps', module: '13805', needle: 'let P={hp:50,mp:5}', mode: 'stmt', title: '13805 base HP/MP constants' },
    { chunk: 'calcDeps', module: '13805', needle: 'function F(e,t){', mode: 'fn', title: '13805 F = H8: base HP/MP by class and level' },
    { chunk: 'calcDeps', module: '17033', whole: true, title: 'module 17033: weapon-requirement DEX/LUK/STR breakpoints used by the AP plan' },
    { chunk: 'builderUi', needle: 'ta=(0,l.useMemo)(()=>({operation:"character-stats"', mode: 'item', title: 'character-builder input assembly' },
  ],
  'dps-table': [{ chunk: 'dpsPage', needle: 'let s={level:70,pdef:e,mdef:a,element:m[T]}', mode: 'stmt', title: 'dps-table: level-70 builds re-run through calculateDamage with a custom target' }],
  formulas: [
    { chunk: 'formulas', module: '51894', needle: 'M=(e,a)=>{let l=Number(e[a]);', mode: 'item', title: 'M: numeric field' },
    { chunk: 'formulas', module: '51894', needle: 'D=(e,a,l)=>Math.min(l,Math.max(a,e))', mode: 'item', title: 'D: clamp' },
    { chunk: 'formulas', module: '51894', needle: 'function A(e){', mode: 'fn', title: 'A: en-US number display (toLocaleString, maximumFractionDigits default 2)' },
    { chunk: 'formulas', module: '51894', needle: 'let S=function(e,a){', mode: 'stmt', title: 'S/E: exact/range result rows' },
    { chunk: 'formulas', module: '51894', needle: 'function T(e,a,l){', mode: 'fn', title: 'T: P(hit) for A*R >= target with R ~ U(1-f, 1+f)' },
    { chunk: 'formulas', module: '51894', needle: 'let W=e=>', mode: 'stmt', title: 'W: mastery factor, R: percent display' },
    { chunk: 'formulas', module: '51894', needle: 'function I(e){', mode: 'fn', title: 'I: level-gap scale' },
    ...['"derived-stats":{', '"outgoing-hit":{', '"physical-damage":{', '"monster-defense":{', '"level-gap":{', 'critical:{', 'clamp:{', '"incoming-hit":{', 'guards:{', '"incoming-damage":{', '"exp-table":{', '"ap-sp":{', '"hp-mp":{'].map((n) => ({ chunk: 'formulas', module: '51894', needle: n, mode: 'item', title: `calculator ${n.replace(/[":{]/g, '')}` })),
  ],
};
// chunks = files the reference text (.js.txt) is sliced from. exec = top-level webpack modules each oracle runs (their full
// dependency closure is traced into executed_chunks) + chunks whose page-component snippets are evaluated verbatim.
const ORACLES = {
  'dmg-simulator': { page: 'dmg-simulator', chunks: ['calc', 'skills', 'dmgUi'], exec: { modules: ['4790'], snippets: ['dmgUi'] } },
  'accuracy-sim': { page: 'accuracy-sim', chunks: ['calc', 'accPage'], exec: { modules: ['4790'], snippets: [] } },
  'avoidability-sim': { page: 'avoidability-sim', chunks: ['calc', 'avoidPage'], exec: { modules: ['4790'], snippets: [] } },
  'mob-hit-sim': { page: 'mob-hit-sim', chunks: ['mobDanger', 'skills', 'calc', 'monsterCombat', 'mobHitPage'], exec: { modules: ['42150'], snippets: [] } },
  'exp-calculator': { page: 'exp-calculator', chunks: ['exp', 'expPage'], exec: { modules: ['27279', '60782'], snippets: ['expPage'] } },
  'character-builder': { page: 'character-builder', chunks: ['calc', 'calcDeps', 'builderUi'], exec: { modules: ['4790'], snippets: [] } },
  'dps-table': { page: 'dps-table', chunks: ['dpsPage'], exec: { modules: [], snippets: [] } },
  formulas: { page: 'formulas', chunks: ['formulas'], exec: { modules: ['51894'], snippets: [] } },
};
const chunkMeta = (k) => ({ url: chunks[k].url, retrieved_at: chunks[k].retrieved_at, bytes: chunks[k].bytes, sha256: chunks[k].sha256 });
const executedChunks = (o) => [...traceExecutedChunks(o.exec.modules), ...o.exec.snippets].map(chunkMeta);
fs.mkdirSync(OUT_TXT_DIR, { recursive: true });
for (const [tool, specs] of Object.entries(EXTRACTS)) {
  const o = ORACLES[tool];
  const parts = [
    `// ${AUTHORITY} - "${tool}" parity-oracle reference: VERBATIM client-side source (minified, unmodified).`,
    `// Page: ${pages[o.page].url} (retrieved_at ${pages[o.page].retrieved_at})`,
    ...o.chunks.map((k) => `// Chunk: ${chunks[k].url} (retrieved_at ${chunks[k].retrieved_at}, ${chunks[k].bytes} bytes, sha256 ${chunks[k].sha256})`),
    '// Each block is a byte-exact substring of the chunk named in its header; tools/meowdb/oracle_vectors.mjs asserts this and',
    '// executes these chunks to produce game/tests/data/parity_vectors.json. Meaning of every function: docs/canonical/oracles.md.',
    '// Reference text only - MeowDB code, not part of the game. Do not ship.',
    '',
  ];
  specs.forEach((spec, i) => {
    const x = extract(spec);
    syntaxCheck(x);
    if (!chunks[spec.chunk].text.includes(x.text)) throw new Error('extract is not a substring of its chunk');
    if (spec.chunk !== 'formulas' && executedText[spec.chunk] !== undefined && !executedText[spec.chunk].includes(x.text)) throw new Error('extract not in executed text');
    const where = spec.module ? `module ${spec.module} in ${CHUNKS[spec.chunk].file}` : CHUNKS[spec.chunk].file;
    parts.push(`// ---- [${i + 1}] ${spec.title} -- ${where}`, x.text, '');
  });
  if (tool === 'formulas') parts.push(`// Execution adaptation (the only one): in the executed copy, "${FORMULAS_PATCH.find}" is replaced by "${FORMULAS_PATCH.replace}" so the module-local calculator table Y is reachable.`, '');
  fs.writeFileSync(path.join(OUT_TXT_DIR, `${tool}.js.txt`), parts.join('\n'));
}

// ---------------------------------------------------------------------------------------------------------------------------
// Output
// ---------------------------------------------------------------------------------------------------------------------------
const oracles = Object.fromEntries(
  Object.entries(ORACLES).map(([k, o]) => [
    k,
    {
      page_url: pages[o.page].url,
      page_retrieved_at: pages[o.page].retrieved_at,
      chunks: o.chunks.map(chunkMeta),
      executed_chunks: executedChunks(o),
      reference_text: `docs/canonical/oracles/${k}.js.txt`,
      ...(o.exec.modules.length ? {} : { note: 'not executed: no vectors come from this oracle' }),
    },
  ]),
);
oracles['formulas-page'] = oracles.formulas;
delete oracles.formulas;
oracles['monster-page'] = { page_url: `${BASE_URL}/monsters/<id>`, note: 'Touch DMG range shown on each monster detail page' };

const out = {
  id: 'parity_vectors',
  name: 'MeowDB simulator parity vectors (golden outputs of MeowDB client-side calculators)',
  source: { authority: AUTHORITY, url: pages['dmg-simulator'].url, retrieved_at: pages['dmg-simulator'].retrieved_at },
  field_sources: {
    guide_examples: { url: pages['guide-damage'].url, retrieved_at: pages['guide-damage'].retrieved_at },
    beginner_guide: { url: pages['guide-beginner'].url, retrieved_at: pages['guide-beginner'].retrieved_at },
    exp_guide: { url: pages['guide-exp'].url, retrieved_at: pages['guide-exp'].retrieved_at },
  },
  generator: 'tools/meowdb/oracle_vectors.mjs',
  execution: 'MeowDB chunk files executed verbatim in node:vm behind a minimal webpack runtime; single adaptation = export of /formulas module-local calculator table; React modules stubbed',
  units: {
    damage: 'HP points; per_hit/per_cast min and max are trunc(clamp(x, 1, 99999)); avg fields are the untruncated midpoint rounded to 0.1 (Math.round(10x)/10); display.* strings are what the dmg-simulator table shows (Math.floor + en-US grouping)',
    hit_rates: 'percent 0-100 unless the key says chance/fraction (0-1)',
    levels: 'character/monster level',
    exp: 'EXP points',
  },
  oracles,
  fixtures: {
    monsters,
    items,
    beginner_builds: builds.map((b) => ({ ...b, stats_with_sword: buildStats[`${b.level}:${b.plan}:sword`] })),
  },
  vectors,
  discrepancies,
  notes: [
    'meowdb_ap_plan = module 13805 lM("beginner", level): all free AP in STR (matches the Beginner guide advice); synthetic_str_dex_split is test input only (STR gets ceil(free/2), DEX floor(free/2)), not a MeowDB recommendation.',
    'Beginners are not a class in the dmg-simulator; MeowDB models a Beginner basic attack as the matching 1st-job basic attack with mastery 0 (character-builder beginnerDamage): basic_attack_warrior (STR/DEX) for Sword, Axe and Blunt weapons, basic_attack_thief (LUK/STR+DEX) for the Razor (Dagger). Beginner vectors reuse exactly that input shape; the script asserts that calculateDamage with no target reproduces beginnerDamage for every build and weapon.',
    'Monsters: the six on the 25 Maple Island maps (1 Tutorial Jr. Sentinel, 2 Snail, 3 Blue Snail, 4 Shroom, 5 Red Snail, 9 Orange Mushroom). The MeowDB dmg-simulator, mob-hit-sim and exp-calculator lists hide Tutorial Jr. Sentinel (module 57135 XB); accuracy-sim and avoidability-sim offer it. Its vectors run the same engines on its simulator-table stats; mob_hit_danger has no row for it.',
    'Weapons: the Maple Island weapon shop (Sid) sells Sword, Hand Axe, Wooden Club and Razor (REQ LEV 5). Sword is run for every build; the other three for the MeowDB AP-plan builds (Razor from level 5).',
    'Random rolls (MeowDB sampler eh): per cast, one action draw (inherit melee: swing if rng() < 0.6, else stab; Bow/Crossbow/Claw shoot); per hit, raw = J(base = rng(), stat = rng()) with two independent U(0,1) draws, then a crit draw rng() < critRate/100, then er (defense, element, level scale, crit, clamp, trunc). physical_roll_explicit pins J and er at fixed rolls.',
    'Compare floating outputs (hit/dodge percentages, ACC/AVOID milestones, final_untruncated, level_scale, expected damage) with a tolerance (1e-9 relative); compare truncated integers and display strings exactly; avg fields are MeowDB-rounded to 0.1.',
    ...notes,
  ],
  gaps: [
    'No MeowDB simulator models bare-handed (no weapon) damage: calculateCharacterStats returns beginnerDamage = null without a weapon, and calculateDamage needs a weapon type.',
    'All six Maple Island monsters have AVOID 0, so monster-specific hit-chance vectors are all 100%; the curve itself is covered by the synthetic accuracy grid.',
    'dps-table only re-runs server-supplied level-70 2nd-job builds through calculateDamage; it has no Beginner content and produces no separate vectors.',
    'None of the six Maple Island monsters has P.DEF (only Red Snail has M.DEF 30), so the physical defense curve is only covered by synthetic inputs; no armor is modeled for the Beginner (WDEF/MDEF are the derived floor(STR/4)/floor(INT/4) only).',
    'MeowDB exposes no per-roll oracle beyond its private kernels: physical_roll_explicit calls J/er at chosen rolls, but the sampler itself (eh, seeded xorshift) is not exported, so the action-draw probability (0.6 swing) and crit draw are documented from its source, not vectorized.',
    'Tutorial Jr. Sentinel (1) is hidden from the dmg-simulator, mob-hit-sim and exp-calculator monster lists (module 57135 XB). Its damage, accuracy, avoid and EXP vectors apply the same engines to its simulator-table stats; no MeowDB tool shows those exact results.',
  ],
};
writeJson(OUT_JSON, out);
console.log(`wrote ${path.relative(ROOT, OUT_JSON)}: ${vectors.length} vectors, ${discrepancies.length} discrepancies; extracts in ${path.relative(ROOT, OUT_TXT_DIR)}`);
