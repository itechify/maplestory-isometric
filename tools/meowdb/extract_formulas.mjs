#!/usr/bin/env node
// MeowDB MS Classic -> game/data/canonical/formulas/*.json
//
// Domain: formulas, progression and the Beginner class.
// Run: node tools/meowdb/extract_formulas.mjs   (cache-first; re-running reproduces the JSON byte-for-byte)
//
// How this works:
// - Every MeowDB page is loaded through lib.mjs (cache-first, globally rate-limited).
// - Formula strings are stored VERBATIM and every one is asserted against the page text (V()). If MeowDB rewords a
//   formula after a --refresh, the run fails and lists every string that no longer matches instead of writing stale data.
// - Tables (EXP, HP/MP, weapon multipliers, reach, speed ladder, skill levels) are parsed from the page text and
//   cross-checked against the second MeowDB page that publishes the same table.
// - Hit rectangles come from MeowDB's own client-derived JSON (schemaVersion 1) shipped in a /character-builder JS chunk;
//   it is cross-checked against the SVG overlays on /guides/weapon-reach and the reach table on /formulas/targeting.
// - The /formulas page's calculator JS is used as the rounding oracle: short code excerpts are asserted, not executed.
// - No Date.now(), no random, no fromCache in output; retrieved_at comes from the cache meta.
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchPage, fetchUrl, pageText, rsc, jsonAt, source, writeJson } from './lib.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT = path.join(ROOT, 'game', 'data', 'canonical', 'formulas');
const ORIGIN = 'https://meowdb.com';

// ---------------------------------------------------------------------------------------------------------------
// Page loading
// ---------------------------------------------------------------------------------------------------------------
const PAGES = {
  acc: '/formulas',
  tgt: '/formulas/targeting',
  dmg: '/formulas/damage',
  dtk: '/formulas/damage-taken',
  spd: '/formulas/attack-speed',
  lvl: '/formulas/leveling',
  spn: '/formulas/spawns',
  gdmg: '/guides/explaining-the-damage-formula',
  gspd: '/guides/attack-speed-and-animation-times',
  greach: '/guides/weapon-reach',
  ghpmp: '/guides/hp-mp-gain-explained',
  gexp: '/guides/exp-table-level-1-to-100',
  gspawn: '/guides/spawn-engine-respawn-and-map-capacity',
  gbeg: '/guides/beginners-guide-first-steps-in-maple-world',
  gmove: '/guides/speed-jump-and-movement',
  ggloss: '/guides/maplestory-classic-glossary',
  gwhat: '/guides/what-is-maplestory-classic-worlds',
  guides: '/guides',
  cls: '/classes',
  clsb: '/classes/beginner',
  skills: '/skills',
  sk0001000: '/skills/beginner/three-snails',
  sk0001001: '/skills/beginner/recovery',
  sk0001002: '/skills/beginner/nimble-feet',
  expcalc: '/exp-calculator',
  dmgsim: '/dmg-simulator',
  cb: '/character-builder',
  q1016: '/quest-tracker/1016',
  q1017: '/quest-tracker/1017',
  q1018: '/quest-tracker/1018',
  npc3: '/npcs/3',
  map40: '/maps/000000040',
  mon2: '/monsters/2',
  i541: '/item-db/541',
  i576: '/item-db/576',
  i585: '/item-db/585',
  i558: '/item-db/558',
  i271: '/item-db/271',
  i522: '/item-db/522',
  i525: '/item-db/525',
  q1013: '/quest-tracker/1013',
  ieb: '/npc-shops/item-efficiency/beginner',
};

// Whitespace-normalise; also drop the spaces pageText leaves around inline links ("W.ATK ;" -> "W.ATK;", "( 1 x)" -> "(1 x)").
const norm = (s) => String(s).replace(/\s+/g, ' ').replace(/ ([.,;:!?)%])/g, '$1').replace(/([(~]) /g, '$1').trim();
const P = {};
for (const [key, p] of Object.entries(PAGES)) {
  const r = await fetchPage(p);
  const lines = pageText(r.html).split('\n').map((s) => s.trim()).filter(Boolean);
  P[key] = { url: r.url, retrieved_at: r.retrieved_at, html: r.html, lines, text: norm(lines.join(' ')) };
}
const src = (key) => ({ url: P[key].url, retrieved_at: P[key].retrieved_at });
const mainSource = (key) => source(P[key].url, P[key].retrieved_at);

// ---------------------------------------------------------------------------------------------------------------
// Verbatim assertions and text helpers
// ---------------------------------------------------------------------------------------------------------------
const missing = [];
/** Assert that s appears verbatim (whitespace-normalised) in page `key`; returns s unchanged. */
function V(key, s) {
  if (!P[key].text.includes(norm(s))) missing.push(`[${key}] ${s}`);
  return s;
}
/** Assert several strings at once. */
const VV = (key, arr) => arr.map((s) => V(key, s));
function check(cond, msg) {
  if (!cond) missing.push(`[check] ${msg}`);
}
/** Index of the first line equal to `line` at or after `from`. */
function idx(key, line, from = 0) {
  const i = P[key].lines.indexOf(line, from);
  if (i < 0) missing.push(`[${key}] line not found: ${line}`);
  return i;
}
/** Index right after a run of consecutive header lines (nth occurrence). */
function afterHeader(key, header, nth = 0) {
  const L = P[key].lines;
  let seen = 0;
  for (let i = 0; i + header.length <= L.length; i++) {
    if (header.every((h, j) => L[i + j] === h)) {
      if (seen++ === nth) return i + header.length;
    }
  }
  missing.push(`[${key}] header not found: ${header.join(' | ')} (#${nth})`);
  return -1;
}
/** Lines from just after `start` (nth occurrence) up to (not including) the first line equal to `end`. */
function block(key, start, end, nth = 0) {
  const L = P[key].lines;
  let i = -1;
  for (let k = 0, seen = 0; k < L.length; k++) if (L[k] === start && seen++ === nth) { i = k; break; }
  if (i < 0) { missing.push(`[${key}] block start not found: ${start}`); return []; }
  const out = [];
  for (let k = i + 1; k < L.length && L[k] !== end; k++) out.push(L[k]);
  return out;
}
/** Fixed-width table rows (ncols lines per row) starting at line index `at`, `nrows` rows. */
function rows(key, at, ncols, nrows) {
  const L = P[key].lines;
  const out = [];
  for (let r = 0; r < nrows; r++) out.push(L.slice(at + r * ncols, at + (r + 1) * ncols));
  return out;
}
const num = (s) => (s === undefined || s === null ? NaN : Number(String(s).replace(/,/g, '')));
const isNum = (s) => /^-?[\d,]+(\.\d+)?$/.test(String(s));
const dashNull = (s) => (s === '-' || s === 'Not used' || s === '—' ? null : num(s));
const pct = (s) => (s === '-' ? null : num(String(s).replace('%', '')));

// ---------------------------------------------------------------------------------------------------------------
// JS chunks (hit zones, calculator code, character-builder module)
// ---------------------------------------------------------------------------------------------------------------
function chunkPaths(key) {
  return [...new Set([...P[key].html.matchAll(/\/_next\/static\/chunks\/[^"'\s]+?\.js/g)].map((m) => m[0]))].sort();
}
async function findChunk(key, needle) {
  for (const c of chunkPaths(key)) {
    const r = await fetchUrl(ORIGIN + c);
    if (r.text.includes(needle)) return { url: r.url, retrieved_at: r.retrieved_at, text: r.text };
  }
  throw new Error(`no chunk of ${PAGES[key]} contains ${needle}`);
}
function unescapeJsSingle(s) {
  return s.replace(/\\(x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|[\s\S])/g, (m, e) => {
    if (e[0] === 'x' && e.length === 3) return String.fromCharCode(parseInt(e.slice(1), 16));
    if (e[0] === 'u' && e.length === 5) return String.fromCharCode(parseInt(e.slice(1), 16));
    return { n: '\n', r: '\r', t: '\t', b: '\b', f: '\f', 0: '\0' }[e] ?? e;
  });
}
function jsonParseBlobs(text) {
  const out = [];
  for (const m of text.matchAll(/JSON\.parse\('((?:[^'\\]|\\.)*)'\)/g)) {
    try { out.push(JSON.parse(unescapeJsSingle(m[1]))); } catch { /* not JSON */ }
  }
  return out;
}
const hitChunk = await findChunk('cb', '"source":"COT2 client');
const HZ = jsonParseBlobs(hitChunk.text).find((o) => o && o.schemaVersion === 1 && o.sets && o.families);
check(!!HZ, 'hit zone JSON (schemaVersion 1) parsed from character-builder chunk');
const calcChunk = await findChunk('acc', 'Math.trunc(1.0548*e[a-2])');
const builderChunk = await findChunk('cb', 'let P={hp:50,mp:5},A={hp:16,mp:12},F=10');
/** Assert a code excerpt exists in a chunk; returns it. */
function C(chunk, excerpt) {
  if (!chunk.text.includes(excerpt)) missing.push(`[chunk ${chunk.url}] ${excerpt}`);
  return excerpt;
}
const chunkSrc = (chunk, pageKey) => ({ url: chunk.url, retrieved_at: chunk.retrieved_at, loaded_by: P[pageKey].url });

// ---------------------------------------------------------------------------------------------------------------
// Shared constants transcribed from the pages
// ---------------------------------------------------------------------------------------------------------------
const STATUS = {
  current: 'Current (MeowDB: matches current COT2 play)',
  model: "MeowDB's Model (MeowDB's own model of the mechanic; not a confirmed game constant)",
  unconfirmed: 'Unconfirmed (MeowDB labels this card Unconfirmed)',
  historical: 'Historical (MeowDB: historical reference table, not yet verified in current play)',
  confirmed: 'Confirmed (MeowDB states it was measured/confirmed in COT2)',
  plain: 'Published formula (no status label on the MeowDB card)',
};
// Card titles that MeowDB tags with a status badge; asserted below so a relabel is noticed.
VV('spn', ['Respawn Times MeowDB\'s Model', 'Mobs per Map MeowDB\'s Model', 'Kills and EXP per Hour MeowDB\'s Model']);
VV('lvl', ['EXP Lost on Death MeowDB\'s Model']);
VV('spd', ['Attack Speed and DPS MeowDB\'s Model']);
VV('dtk', ['Knockback Airtime MeowDB\'s Model', 'Defensive Skills MeowDB\'s Model']);
VV('dmg', ['Heal Unconfirmed', 'Meso Explosion Unconfirmed', 'Mortal Blow MeowDB\'s Model']);
// Every weapon item page states that a normal attack picks one standing presentation with equal odds (used by damage.json and attack_styles.json).
const EQUAL_ODDS = 'A normal attack picks one of the attacks, each with equal odds (60% swing, 40% thrust), and the averages use those attacks. Crouched attack is left out of average calculations.';
for (const k of ['i541', 'i576', 'i585', 'i558']) V(k, EQUAL_ODDS);

// ===============================================================================================================
// 1. EXP table
// ===============================================================================================================
function parseExpLeveling() {
  const at = afterHeader('lvl', ['EXP Table', 'Level', 'EXP to next level', 'Total from Lv 1']);
  const L = P.lvl.lines;
  const out = [];
  for (let i = at; i + 2 < L.length && isNum(L[i]); i += 3) out.push({ level: num(L[i]), exp_to_next: num(L[i + 1]), total: num(L[i + 2]) });
  return out;
}
function parseExpGuide() {
  const at = afterHeader('gexp', ['Level', 'EXP to next', 'Cumulative from lv 1', 'Milestone']);
  const L = P.gexp.lines;
  const out = [];
  let expect = 1;
  for (let i = at; i < L.length; i++) {
    if (L[i] === String(expect) && isNum(L[i + 1]) && isNum(L[i + 2])) {
      out.push({ level: expect, exp_to_next: num(L[i + 1]), total: num(L[i + 2]) });
      expect++;
      i += 2;
    }
    if (L[i] === 'Confidence boundary:') break;
  }
  return out;
}
function expFormula(level, prev) {
  if (level <= 5) return (Math.floor(level ** 2 / 2) + 15) * level;
  if (level <= 50) { const q = Math.floor(level ** 2 / 3); return (q + 19) * q; }
  return Math.trunc(prev * 1.0548);
}
const expLv = parseExpLeveling();
const expGuide = parseExpGuide();
check(expLv.length === 99, `leveling tab EXP table has 99 rows (got ${expLv.length})`);
check(expGuide.length === 99, `EXP guide table has 99 rows (got ${expGuide.length})`);
const expDiscrepancies = [];
{
  let prev = 0, cum = 0;
  for (let i = 0; i < expLv.length; i++) {
    const a = expLv[i], g = expGuide[i];
    const f = expFormula(a.level, prev);
    cum += a.exp_to_next;
    check(a.level === i + 1, `EXP row ${i} level`);
    if (f !== a.exp_to_next) expDiscrepancies.push(`Lv ${a.level}: leveling tab ${a.exp_to_next} vs published formula ${f}`);
    if (cum !== a.total) expDiscrepancies.push(`Lv ${a.level}: leveling tab total ${a.total} vs running sum ${cum}`);
    if (!g || g.exp_to_next !== a.exp_to_next || g.total !== a.total) expDiscrepancies.push(`Lv ${a.level}: leveling tab ${a.exp_to_next}/${a.total} vs EXP guide ${g?.exp_to_next}/${g?.total}`);
    prev = a.exp_to_next;
  }
}
check(expDiscrepancies.length === 0, `EXP sources agree: ${expDiscrepancies.join('; ')}`);
// Calculator code (rounding oracle) for the EXP table.
const expCode = C(calcChunk, 'for(let a=1;a<=99;a+=1)if(a<=5)e.push((Math.floor(a**2/2)+15)*a);else if(a<=50){let l=Math.floor(a**2/3);e.push((l+19)*l)}else e.push(Math.trunc(1.0548*e[a-2]))');
const partyCode = C(calcChunk, 'l=a<=1?0:Math.min(30,(a-1)*10)');

const expTable = {
  id: 'exp_table',
  name: 'EXP to next level',
  value_kind: 'exp_to_next',
  semantics: [
    'exp_to_next for level L = EXP needed to go from level L (at 0 EXP) to level L+1. It is NOT cumulative.',
    'total_from_lv1 for level L = cumulative EXP from level 1 at 0 EXP to reach level L+1 (sum of exp_to_next for levels 1..L). MeowDB: "' +
      V('lvl', 'Total from Lv 1 is all the EXP needed to reach the next level, starting from level 1.') + '"',
    'Level-up resets the EXP bar to 0 (glossary: "' + V('ggloss', 'Hitting the next level. Resets your EXP bar to 0.') + '").',
  ],
  level_min: 1,
  level_max_listed: 99,
  level_cap: 100,
  level_cap_note: V('gwhat', 'Level 100. Nexon set the maximum character level at Lv. 100 in its Founder\'s Access release notes.'),
  confidence: {
    current_levels: [1, 49],
    historical_levels: [50, 99],
    statements: [
      V('lvl', 'Values through level 49 match current play. Level 50 and up follow the historical table.'),
      V('gexp', 'Levels 1 to 49 are confirmed in the current game. Levels 50 to 99 reproduce a historical reference table and remain planning estimates until they are verified in current play.'),
      V('expcalc', 'Levels 1 through 49 match current MapleStory Classic play. Levels 50 through 99 remain a historical planning reference until current play reaches them.'),
    ],
  },
  formula_segments: [
    { levels: [1, 5], formula: V('lvl', '(floor(level² / 2) + 15) × level'), status: V('lvl', 'Current') },
    { levels: [6, 50], formula: [V('lvl', 'q = floor(level² / 3)'), V('lvl', '(q + 19) × q')], status: V('lvl', 'Current through Lv 49') },
    { levels: [51, 99], formula: V('lvl', "trunc(previous level's EXP × 1.0548)"), status: V('lvl', 'Historical') },
  ],
  levels: expLv.map((r) => ({
    level: r.level,
    exp_to_next: r.exp_to_next,
    total_from_lv1: r.total,
    status: r.level <= 49 ? 'current' : 'historical',
  })),
  party_bonus: {
    status: STATUS.confirmed,
    bonus_exp_pct_by_party_size: { 1: 0, 2: 10, 3: 20, 4: 30, 5: 30, 6: 30 },
    statements: [
      V('gexp', 'Party bonus EXP by party size, measured in COT2 by Ryan.'),
      V('gexp', 'The bonus caps at four members.'),
      V('gbeg', 'A member who has not attacked for 15 seconds stops receiving party EXP until they attack again.'),
      V('map40', 'COT2 grants +10% with two players, +20% with three, and +30% with four to six. The EXP figure above is the map\'s total base EXP output before party sharing or bonuses.'),
    ],
    party_inactivity_cutoff_s: 15,
    calculator_code: partyCode,
    gaps: ['How party EXP is split between members (by damage, level, or evenly) is not documented on MeowDB.'],
  },
  parity_examples: [
    { level: 10, exp_to_next: 1716, note: V('expcalc', 'Level 10 needs 1,716 EXP.') },
    { from_level: 10, to_level: 30, exp_remaining: 545290, note: V('expcalc', '545,290 EXP remaining. 20 levels to go.') },
    { level: 5, worked: V('gexp', 'Level 5: (12 + 15) × 5 =') },
    { level: 49, worked: V('gexp', 'Level 49: (800 + 19) × 800 =') },
    { level: 51, worked: V('gexp', 'Level 51: trunc(709,716 × 1.0548) =') },
  ],
  cross_checks: [
    'All 99 rows of the /formulas/leveling table equal the /guides/exp-table-level-1-to-100 table, the running sum, and the published formula (checked by the extractor).',
    'MeowDB calculator code (rounding oracle): ' + expCode,
  ],
  source: mainSource('lvl'),
  field_sources: {
    confidence: src('gexp'),
    level_cap_note: src('gwhat'),
    'party_bonus.statements': src('gexp'),
    party_inactivity_cutoff_s: src('gbeg'),
    parity_examples: src('expcalc'),
    'cross_checks.calculator_code': chunkSrc(calcChunk, 'acc'),
  },
  discrepancies: [
    {
      topic: 'Level cap',
      values: [
        { url: P.gwhat.url, value: 100, text: V('gwhat', 'Level 100. Nexon set the maximum character level at Lv. 100 in its Founder\'s Access release notes.') },
        { url: P.gexp.url, value: null, text: V('gexp', 'Nexon has never announced a level cap for Classic.') },
      ],
      chosen: 100,
      reason: 'The "What is MapleStory Classic World?" guide (updated 2026-10-03) cites Nexon\'s Founder\'s Access release notes and is newer than the EXP guide (updated 2026-09-18).',
    },
    {
      topic: 'Level 50 status',
      values: [
        { url: P.lvl.url, text: 'Formula row "6-50" is labelled "Current through Lv 49".' },
        { url: P.gexp.url, text: 'Formula row "6 to 50"; "Levels 1 to 49 are confirmed in the current game."' },
      ],
      chosen: 'Level 50 uses the 6-50 formula value (709,716) but is marked historical',
      reason: 'Both pages agree the confirmed boundary is level 49; the value itself is identical on both pages.',
    },
  ],
};

// ===============================================================================================================
// 2. HP / MP gain
// ===============================================================================================================
function parseHpMpLeveling() {
  const at = afterHeader('lvl', ['Class', 'HP / level', 'MP / level', 'HP / advancement', 'MP / advancement']);
  return rows('lvl', at, 5, 5).map(([cls, hp, mp, hpa, mpa]) => ({ cls, hp: num(hp), mp: num(mp), hpa: dashNull(hpa), mpa: dashNull(mpa) }));
}
const hpLv = parseHpMpLeveling();
{
  const at = afterHeader('ghpmp', ['Class', 'Max HP per level', 'Max MP per level']);
  const g = rows('ghpmp', at, 3, 5);
  const at2 = afterHeader('ghpmp', ['Class', 'Max HP per advancement', 'Max MP per advancement', 'Total', 'Measured at']);
  // "Measured at" can wrap onto two lines, so look rows up by class name instead of fixed width.
  const L2 = P.ghpmp.lines;
  const g2 = ['Warrior', 'Bowman', 'Thief', 'Magician'].map((c) => { const i = L2.indexOf(c, at2); return [c, L2[i + 1], L2[i + 2], L2[i + 3]]; });
  for (const r of hpLv) {
    const a = g.find((x) => x[0] === r.cls);
    check(a && num(a[1]) === r.hp && num(a[2]) === r.mp, `HP/MP per level for ${r.cls} agrees between leveling tab and HP/MP guide`);
    const b = g2.find((x) => x[0] === r.cls);
    if (r.cls !== 'Beginner') check(b && num(b[1]) === r.hpa && num(b[2]) === r.mpa, `HP/MP per advancement for ${r.cls} agrees`);
  }
}
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
const hpFormulas = VV('lvl', [
  'B = min(Level, 10) - 1',
  'C = max(0, Level - 10)',
  'A = 1 + [2nd job at Lv 30+] + [3rd job at Lv 70+]',
  'BeginnerHP = 50 + 16 × (Level - 1)',
  'BeginnerMP = 5 + 12 × (Level - 1)',
  'JobHP = 50 + 16 × B + HPAdv × A + HPPerLevel × C',
  'JobMP = 5 + 12 × B + MPAdv × A + MPPerLevel × C',
  'TotalHP = trunc(JobHP × (1 + MaxHP% / 100)) + EquipmentHP',
  'TotalMP = trunc(JobMP × (1 + MaxMP% / 100)) + EquipmentMP',
]);
const hpBuilderCode = C(builderChunk, 'let P={hp:50,mp:5},A={hp:16,mp:12},F=10,O={warrior:{perLevel:{hp:28,mp:12},advancement:{hp:350,mp:150}},bowman:{perLevel:{hp:22,mp:17},advancement:{hp:250,mp:250}},thief:{perLevel:{hp:22,mp:17},advancement:{hp:250,mp:250}},magician:{perLevel:{hp:16,mp:22},advancement:{hp:150,mp:350}}}');
function beginnerHpMp(level) { return { hp: 50 + 16 * (level - 1), mp: 5 + 12 * (level - 1) }; }
function jobHpMp(cls, level, second, third) {
  const r = hpLv.find((x) => slug(x.cls) === cls);
  const B = Math.min(level, 10) - 1, Cc = Math.max(0, level - 10), A = 1 + (second && level >= 30 ? 1 : 0) + (third && level >= 70 ? 1 : 0);
  return { hp: 50 + 16 * B + r.hpa * A + r.hp * Cc, mp: 5 + 12 * B + r.mpa * A + r.mp * Cc };
}
check(beginnerHpMp(10).hp === 194 && beginnerHpMp(10).mp === 113, 'Beginner Lv10 = 194 HP / 113 MP');
check(jobHpMp('warrior', 11, false, false).hp === 572 && jobHpMp('warrior', 11, false, false).mp === 275, 'Warrior Lv11 = 572/275');
check(jobHpMp('warrior', 50, true, false).hp === 2014 && jobHpMp('warrior', 50, true, false).mp === 893, 'Warrior Lv50 = 2,014/893 (leveling tab calculator default)');

const hpMpGain = {
  id: 'hp_mp_gain',
  name: 'Max HP / Max MP growth per class and level',
  status: STATUS.confirmed,
  status_note: 'Per-level HP/MP ' + V('ghpmp', 'gain is a flat number based on your class. First, second, and third job advancements grant the same class bonus. Every figure below is measured from COT2, including a level 11 Warrior catch-up and Grummash\'s level 100 third-job characters.'),
  random_range: null,
  random_range_note: V('ghpmp', 'All five classes are confirmed. Sampled level-ups showed zero variance.'),
  starting: { base_hp: 50, base_mp: 5, note: [V('ghpmp', 'A character starts with 50 base HP and 5 base MP'), V('ghpmp', 'A Beginner at level 10 has 194 HP and 113 MP.')].join('. ') },
  per_class: Object.fromEntries(hpLv.map((r) => [slug(r.cls), {
    name: r.cls,
    max_hp_per_level: r.hp,
    max_mp_per_level: r.mp,
    max_hp_per_advancement: r.hpa,
    max_mp_per_advancement: r.mpa,
  }])),
  branches_use_base_class_rates: V('ghpmp', 'Branches use their base class rates. Hunter and Crossbowman take the Bowman numbers, Bandit and Assassin take the Thief numbers.'),
  advancement_levels: { first_job: 10, second_job: 30, third_job: 70 },
  formulas: hpFormulas,
  percent_bonus_rule: V('ghpmp', 'The percentage skill applies after the flat bonus, then the result rounds down.'),
  int_gives_mp: false,
  int_gives_mp_note: V('ghpmp', 'INT does not give additional MP here.'),
  hp_washing_note: V('ghpmp', 'HP washing is dead in MSCW.'),
  ap_into_hp_mp: null,
  ap_into_hp_mp_note: 'MeowDB documents no rule (allowed or not, gain per AP) for spending AP on Max HP or Max MP. The HP/MP formulas above have no AP term, the Beginner\'s guide and the formulas tab describe AP only as STR/DEX/INT/LUK points, and the HP/MP guide says HP washing is dead. The glossary, however, says AP is "used to raise STR / DEX / INT / LUK / HP / MP" and that Max HP/MP gets "a small AP contribution". See discrepancies.',
  job_advancement_heals: false,
  job_advancement_heal_note: V('ghpmp', 'Unlike leveling up, job advancing does not heal you. It only raises your max HP and MP.'),
  late_advancement_note: V('ghpmp', 'A level 11 Beginner advanced to Warrior with 572 Max HP, 275 Max MP, all Warrior skills at rank 0, and 4 unspent SP. Those are the same base pools and first-job SP as an on-time level 11 Warrior.'),
  late_advancement_caveat: V('ghpmp', 'This directly confirms level 11 Warrior catch-up; later levels and other classes still need direct tests.'),
  equipment_and_skills_note: V('ghpmp', 'Equipment can provide additional HP and MP. Warriors and magicians carry a skill: Max HP Increase and Max MP Increase each reach +25% (of your base) at max level.'),
  parity_examples: [
    { class: 'beginner', level: 10, max_hp: 194, max_mp: 113 },
    { class: 'warrior', level: 11, max_hp: 572, max_mp: 275, note: 'late advancement from a level 11 Beginner' },
    { class: 'warrior', level: 50, second_job: true, max_hp: 2014, max_mp: 893, note: '/formulas/leveling calculator default' },
  ],
  calculator_code: hpBuilderCode,
  source: mainSource('lvl'),
  field_sources: {
    status_note: src('ghpmp'), random_range_note: src('ghpmp'), starting: src('ghpmp'), branches_use_base_class_rates: src('ghpmp'),
    percent_bonus_rule: src('ghpmp'), int_gives_mp_note: src('ghpmp'), hp_washing_note: src('ghpmp'), job_advancement_heal_note: src('ghpmp'),
    late_advancement_note: src('ghpmp'), late_advancement_caveat: src('ghpmp'), equipment_and_skills_note: src('ghpmp'), calculator_code: chunkSrc(builderChunk, 'cb'),
  },
  gaps: [
    'Rule for putting AP into Max HP / Max MP (allowed or not, and the gain per AP) is not documented on MeowDB.',
    'How much a level-up heals (full HP/MP or not) is not stated; only implied by "Unlike leveling up, job advancing does not heal you".',
  ],
  discrepancies: [
    {
      topic: 'AP contribution to HP/MP',
      values: [
        { url: P.ggloss.url, text: V('ggloss', 'Max HP/MP goes up with level, plus a small AP contribution.') },
        { url: P.ggloss.url, text: 'AP: ' + V('ggloss', 'Earned at every level up. You get 5 per level. Used to raise STR / DEX / INT / LUK / HP / MP.') },
        { url: P.ghpmp.url, text: 'HP washing is dead in MSCW. INT does not give additional MP here. (No AP term in any HP/MP formula.)' },
        { url: P.gbeg.url, text: V('gbeg', 'then get 5 AP per level for STR, DEX, INT, and LUK.') },
      ],
      chosen: 'No AP term (ap_into_hp_mp = null); AP is allocated to STR/DEX/INT/LUK only',
      reason: 'The HP/MP guide is the dedicated, COT2-measured mechanics page (measured level-ups with zero variance) and the Beginner\'s guide (updated 2026-10-02) lists only the four stats; the glossary entries are one-line definitions. Unresolved: whether AP can be put into Max HP / Max MP, and how much it gives, remains a gap.',
    },
  ],
};

// ===============================================================================================================
// 3. Derived stats and accuracy
// ===============================================================================================================
const derivedLines = VV('acc', [
  'Common = 1.2 × DEX + 2 × Level + 0.6 × LUK',
  'Beginner ACC = floor(Common / 2.5 + 5)',
  'Warrior ACC = floor(Common / 2.5 + 10)',
  'Bowman ACC = floor(Common / 4.8 + 20)',
  'Thief ACC = floor(Common / 4 + 15)',
  'Magician ACC = floor((1.2 × INT + 2 × Level + 0.6 × LUK) / 5.1 + 20)',
  'EVA = floor(LUK / 3) + floor(DEX / 6) + 5',
  'Magic = floor(INT / 2)',
  'WDEF = floor(STR / 4)',
  'MDEF = floor(INT / 4)',
]);
const derivedCode = C(calcChunk, 's=1.2*r+2*a+.6*o;return[S("Beginner ACC",Math.floor(s/2.5+5),0)');
function derive({ level, str, dex, int, luk }) {
  const c = 1.2 * dex + 2 * level + 0.6 * luk;
  return {
    beginner_acc: Math.floor(c / 2.5 + 5), warrior_acc: Math.floor(c / 2.5 + 10), bowman_acc: Math.floor(c / 4.8 + 20), thief_acc: Math.floor(c / 4 + 15),
    magician_acc: Math.floor((1.2 * int + 2 * level + 0.6 * luk) / 5.1 + 20), eva: Math.floor(luk / 3) + Math.floor(dex / 6) + 5,
    magic: Math.floor(int / 2), wdef: Math.floor(str / 4), mdef: Math.floor(int / 4),
  };
}
{
  const d = derive({ level: 50, str: 50, dex: 100, int: 50, luk: 50 });
  check(d.beginner_acc === 105 && d.warrior_acc === 110 && d.bowman_acc === 72 && d.thief_acc === 77 && d.magician_acc === 57 && d.eva === 37 && d.magic === 25 && d.wdef === 12 && d.mdef === 12,
    'derived-stats calculator default (Lv50, 50/100/50/50) reproduces 105/110/72/77/57/37/25/12/12');
  const w = derive({ level: 30, str: 132, dex: 30, int: 4, luk: 4 });
  check(w.warrior_acc === 49 && w.eva === 11 && w.magic === 2 && w.wdef === 33 && w.mdef === 1, 'guide Lv30 Warrior example reproduces ACC 49 EVA 11 Magic 2 WDEF 33 MDEF 1');
}
const totalsNote = V('acc', 'Accuracy, avoid, magic and defense all come from total stats: base AP plus equipment and buffs.');
const floorNote = V('gdmg', 'Each floor is applied exactly where shown. Equipment and skill bonuses are added to the matching derived stat afterward.');

function statRoleTable(stat, nextStat) {
  // Rows of (Role, Used by, Formula) between the stat's header and the next stat's header in the guide.
  // Merge the role "Death EXP loss", which the page splits over three lines (EXP is a glossary link).
  const L = P.gdmg.lines.map((l, i, a) => (l === 'Death' && a[i + 1] === 'EXP' && a[i + 2] === 'loss' ? 'Death EXP loss' : l))
    .filter((l, i, a) => !((l === 'EXP' && a[i - 1] === 'Death EXP loss') || (l === 'loss' && a[i - 2] === 'Death EXP loss')));
  let start = -1;
  for (let i = 0; i + 3 < L.length; i++) if (L[i] === stat && L[i + 1] === 'Role' && L[i + 2] === 'Used by' && L[i + 3] === 'Formula') { start = i + 4; break; }
  check(start > 0, `stat role table ${stat}`);
  const out = [];
  for (let i = start; i < L.length && L[i] !== nextStat; i += 3) {
    if (['Total stats include assigned Ability Points, equipment, and active effects. Equipment requirements only decide whether you can equip an item.'].includes(L[i])) break;
    out.push({ role: L[i], used_by: L[i + 1], formula: L[i + 2] });
  }
  return out;
}
const statRoles = {
  str: statRoleTable('STR', 'One STR adds the same `STR / 100` amount in the Bow/Crossbow and Dagger/Claw formulas. Daggers and claws also add DEX. LUK is their main damage stat because LUK gets `W`.'),
  dex: statRoleTable('DEX', 'INT'),
  int: statRoleTable('INT', 'LUK'),
  luk: statRoleTable('LUK', 'Total stats include assigned Ability Points, equipment, and active effects. Equipment requirements only decide whether you can equip an item.'),
};
check(statRoles.str.length === 5 && statRoles.dex.length === 6 && statRoles.int.length === 6 && statRoles.luk.length === 6,
  `stat role tables parsed (STR ${statRoles.str.length}, DEX ${statRoles.dex.length}, INT ${statRoles.int.length}, LUK ${statRoles.luk.length})`);

const derivedStats = {
  id: 'derived_stats',
  name: 'Derived combat stats (Magic, WDEF, MDEF) and STR/DEX/INT/LUK roles',
  status: STATUS.plain,
  inputs_note: totalsNote,
  floor_rule: floorNote,
  formulas: {
    magic: { formula: V('acc', 'Magic = floor(INT / 2)'), guide_name: V('gdmg', 'Derived Magic = floor(INT / 2)'), stat: 'INT', divisor: 2, rounding: 'floor' },
    wdef: { formula: V('acc', 'WDEF = floor(STR / 4)'), guide_name: V('gdmg', 'Derived WDEF = floor(STR / 4)'), stat: 'STR', divisor: 4, rounding: 'floor' },
    mdef: { formula: V('acc', 'MDEF = floor(INT / 4)'), guide_name: V('gdmg', 'Derived MDEF = floor(INT / 4)'), stat: 'INT', divisor: 4, rounding: 'floor' },
  },
  accuracy_and_avoid: 'ACC and EVA are in accuracy.json (same /formulas card).',
  total_weapon_attack_rule: V('gdmg', 'Every equipped W.ATK line, including weapon, projectile, shield, glove, and future equipment sources, joins one Total Weapon Attack pool.'),
  attack_power_rule: V('gdmg', 'Attack Power is a separate stat supplied only by effects explicitly identified as Attack Power, such as skills, passives, and consumables.'),
  magic_total_rule: V('gdmg', 'MagicTotal = floor(TotalINT / 2) + EquipmentMATK + ScrollMATK + BuffMATK'),
  stat_roles: statRoles,
  stat_roles_note: [
    V('gdmg', 'These four base stats determine your damage, accuracy, defense, and avoidability; `W` is the weapon action multiplier used below.'),
    V('gdmg', 'A primary stat gets multiplied by `W`. A secondary stat is added directly. A larger `W` makes each point of the primary stat worth more damage.'),
    V('gdmg', 'Total stats include assigned Ability Points, equipment, and active effects. Equipment requirements only decide whether you can equip an item.'),
  ],
  parity_examples: [
    { input: { level: 50, str: 50, dex: 100, int: 50, luk: 50 }, output: derive({ level: 50, str: 50, dex: 100, int: 50, luk: 50 }), note: '/formulas Try-values defaults' },
    { input: { level: 30, str: 132, dex: 30, int: 4, luk: 4 }, output: { warrior_acc: 49, eva: 11, magic: 2, wdef: 33, mdef: 1 }, note: 'Damage formula guide, worked example: level 30 Warrior' },
  ],
  calculator_code: derivedCode,
  source: mainSource('acc'),
  field_sources: {
    floor_rule: src('gdmg'), total_weapon_attack_rule: src('gdmg'), attack_power_rule: src('gdmg'), magic_total_rule: src('gdmg'),
    stat_roles: src('gdmg'), stat_roles_note: src('gdmg'), 'parity_examples.1': src('gdmg'), calculator_code: chunkSrc(calcChunk, 'acc'),
  },
  gaps: ['Stat caps (maximum STR/DEX/INT/LUK, WDEF, MDEF, ACC, EVA) are not documented on MeowDB.'],
};

const outgoingLines = VV('acc', [
  'L = max(0, MobLevel - PlayerLevel)',
  'A = TotalACC × 100 / (10 × L + 255)',
  'D = A - MobEVA',
  'f = 0.15 + 0.20 / (1 + exp(D / 12))',
  'R = uniform(1 - f, 1 + f)',
  'Hit when A × R ≥ MobEVA',
  'q = MobEVA / A',
  'P(hit) = 1 when q ≤ 1 - f',
  'P(hit) = 0 when q ≥ 1 + f',
  'P(hit) = (1 + f - q) / (2 × f) otherwise',
]);
const incomingLines = VV('dtk', [
  'G = max(0, PlayerLevel - MobLevel)',
  'A = MobACC × 100 / (5 × (G + 51))',
  'E = PlayerEVA / (1 + PlayerEVA / 80) / (1 + G / 40)',
  'D = A - E',
  'f = 0.15 + 0.20 / (1 + exp(D / 12))',
  'R = uniform(1 - f, 1 + f)',
  'CandidateChance = P(A × R ≥ E)',
  'If E > A × (1 + f):',
  'CandidateChance = clamp(exp((A - E) / 18) × 0.03, 0.02, 0.03)',
  'FinalHitChance = CandidateChance + (1 - CandidateChance) × 0.08',
]);
const damageTakenLines = VV('dtk', [
  'EffectiveMobAttack = trunc(MobAttack × AttackRatio / 100)',
  'U = uniform(0, 1)',
  'Roll = 1.1 + 0.4 × U',
  'Raw = EffectiveMobAttack × Roll',
  'Taken = Raw × (1 - DEF / (DEF + 5 × (PlayerLevel + 40) + 1.2 × Raw))',
  'FinalTaken = trunc(clamp(Taken, 1, 50,000,000))',
]);
function takenRange(attack, def, level) {
  const t = (roll) => { const raw = attack * roll; return Math.trunc(Math.min(5e7, Math.max(1, raw * (1 - def / (def + 5 * (level + 40) + 1.2 * raw))))); };
  return [t(1.1), t(1.5)];
}
check(takenRange(300, 100, 50).join() === '295,408', '/formulas/damage-taken default 300 ATK / 100 DEF / Lv50 -> 295-408');
check(takenRange(3, 0, 1).join() === '3,4', 'Snail touch: base 3 at DEF 0 -> 3-4 (monster page shows "Touch DMG 3-4 Base 3")');
V('mon2', 'Touch DMG 3-4 Base 3');
function outgoingHit(acc, playerLevel, mobLevel, mobEva) {
  const L = Math.max(0, Math.max(1, mobLevel) - playerLevel), A = (acc * 100) / (10 * L + 255), D = A - mobEva, f = 0.15 + 0.2 / (1 + Math.exp(D / 12));
  if (mobEva <= 0) return { p: 1, A, f };
  if (acc <= 0) return { p: 0, A, f };
  if (D >= 25 + L * (0.5 * playerLevel + 15)) return { p: 1, A, f };
  const q = mobEva / A;
  return { p: q <= 1 - f ? 1 : q >= 1 + f ? 0 : (1 + f - q) / (2 * f), A, f };
}
{
  const o = outgoingHit(100, 50, 50, 20);
  check(o.p === 1 && (o.A * (1 - o.f)).toFixed(2) === '32.02' && (o.A * (1 + o.f)).toFixed(2) === '46.41', '/formulas outgoing-hit default -> 100%, roll 32.02-46.41');
}
function incomingHit(mobAcc, eva, playerLevel, mobLevel) {
  const G = Math.max(0, playerLevel - mobLevel), A = (mobAcc * 100) / (5 * (G + 51)), E = eva / (1 + eva / 80) / (1 + G / 40), D = A - E, f = 0.15 + 0.2 / (1 + Math.exp(D / 12));
  const q = E / A;
  let c = q <= 1 - f ? 1 : q >= 1 + f ? 0 : (1 + f - q) / (2 * f);
  if (E > A * (1 + f)) c = Math.min(0.03, Math.max(0.02, 0.03 * Math.exp(D / 18)));
  return { p: c + (1 - c) * 0.08, A, f };
}
{
  const i = incomingHit(100, 50, 50, 50);
  check((i.p * 100).toFixed(1) === '99.8' && (i.A * (1 - i.f)).toFixed(2) === '30.74' && (i.A * (1 + i.f)).toFixed(2) === '47.69', '/formulas/damage-taken incoming-hit default -> 99.8%, roll 30.74-47.69');
}
const accuracy = {
  id: 'accuracy',
  name: 'Accuracy, avoidability, hit chance, guards and incoming damage',
  status: STATUS.plain,
  inputs_note: totalsNote,
  floor_rule: floorNote,
  derived_accuracy: {
    common_term: derivedLines[0],
    by_job: {
      beginner: { formula: derivedLines[1], divisor: 2.5, constant: 5, uses_common_term: true },
      warrior: { formula: derivedLines[2], divisor: 2.5, constant: 10, uses_common_term: true },
      bowman: { formula: derivedLines[3], divisor: 4.8, constant: 20, uses_common_term: true },
      thief: { formula: derivedLines[4], divisor: 4, constant: 15, uses_common_term: true },
      magician: { formula: derivedLines[5], divisor: 5.1, constant: 20, uses_common_term: false, numerator: '1.2 × INT + 2 × Level + 0.6 × LUK' },
    },
    stat_coefficients: { dex: 1.2, level: 2, luk: 0.6, magician_int: 1.2 },
    rounding: 'floor of the whole expression (floor(Common / divisor + constant))',
  },
  avoidability: { formula: derivedLines[6], luk_divisor: 3, dex_divisor: 6, constant: 5, rounding: 'each term floored separately, then summed' },
  outgoing_hit: {
    status: STATUS.plain,
    applies_to: V('acc', 'Whether your attack connects. Physical attacks and spells use the same hit test.'),
    formulas: outgoingLines,
    constants: { acc_scale: 100, level_gap_coefficient: 10, base_divisor: 255, spread_base: 0.15, spread_extra: 0.2, spread_scale: 12 },
    automatic_hit: {
      formula: V('acc', 'Automatic hit: D ≥ 25 + L × (0.5 × PlayerLevel + 15)'),
      description: V('acc', 'The game compares your accuracy to the monster\'s avoid with a random spread. A big enough accuracy lead skips the roll.'),
      constants: { base: 25, player_level_coefficient: 0.5, per_gap_constant: 15 },
    },
    notes: [
      V('gdmg', 'Every offensive Magician spell can miss. Physical attacks and offensive spells use this shared target hit check. Some status actions disable the automatic-hit shortcut and still perform the same roll.'),
      V('dmg', 'Summons use your hit roll and the Darkness check. Against bosses they never get the automatic hit.'),
    ],
    calculator_edge_cases: {
      rules: [
        'MobEVA <= 0 -> hit chance 1 (always hits).',
        'TotalACC <= 0 (and MobEVA > 0) -> hit chance 0.',
        'The automatic-hit test is evaluated before the q-based probability.',
        'L uses max(1, MobLevel) - PlayerLevel, floored at 0.',
      ],
      code_excerpt: C(calcChunk, 't=Math.max(0,Math.max(1,M(e,"mobLevel"))-r),o=100*a/(10*t+255),s=o-l,n=.15+.2/(1+Math.exp(s/12)),i=l<=0?1:a<=0?0:s>=25+t*(.5*r+15)?1:T(o,l,n)'),
      probability_code: C(calcChunk, 'function T(e,a,l){if(e<=0)return+(a<=0);let r=a/e;return r<=1-l?1:r>=1+l?0:(1+l-r)/(2*l)}'),
    },
  },
  darkness: {
    status: STATUS.plain,
    formulas: VV('acc', ['d = clamp(Darkness / 100, 0, 1)', 'v = uniform(0, 1)', 'Lands = Hit and v > d', 'P(lands) = P(hit) × (1 - d)']),
    note: V('acc', 'Darkness is a separate miss check rolled after the attack hits. It does not lower your accuracy.'),
  },
  incoming_hit: {
    status: STATUS.plain,
    formulas: incomingLines,
    constants: { acc_scale: 100, level_base: 51, level_multiplier: 5, eva_soft_cap: 80, eva_level_divisor: 40, spread_base: 0.15, spread_extra: 0.2, spread_scale: 12, far_miss_scale: 18, far_miss_min: 0.02, far_miss_max: 0.03, minimum_hit_rescue: 0.08 },
    rescue_note: V('gdmg', 'After a candidate miss, apply the independent 8% minimum-hit rescue:'),
    magic_note: V('gdmg', 'Physical uses WDEF after physical evasion and guard. Magic uses MDEF and bypasses the physical evasion and guard path.'),
    monster_magic_note: V('gdmg', 'Monster magic attacks use their magic attack value and the MDEF curve without the physical miss roll.'),
    calculator_edge_cases: {
      rules: ['MobACC <= 0 -> monster hit chance 0%.', 'Player level and monster level are floored at 1.', 'The 8% rescue is applied after the candidate chance, including the far-miss clamp branch.'],
      code_excerpt: C(calcChunk, 'u=T(s,n,m);n>s*(1+m)&&(u=D(.03*Math.exp(i/18),.02,.03));let c=D((u+(1-u)*.08)*100,0,100)'),
    },
  },
  guards: {
    status: STATUS.plain,
    note: V('dtk', 'Guards only work against regular attacks. Monster skills always get through.'),
    formulas: VV('dtk', ['ShieldGuardChance = 0 when ShieldWDEF ≤ 0', 'ShieldGuardChance = max(0.05, ShieldWDEF / (ShieldWDEF + 500))', 'ClawGuardChance = 3% at Lv 1-6 · 4% at Lv 7-13 · 5% at Lv 14-20']),
    combine_rule: V('gdmg', 'When both are available, use the larger chance. A successful guard fully negates an eligible regular physical hit.'),
    beginner_relevance: 'Only Shield Guard can apply to a Beginner (needs an equipped shield with WDEF); Claw Guard is a Hermit skill.',
  },
  incoming_damage: {
    status: STATUS.plain,
    formulas: damageTakenLines,
    touch_attack_ratio: 100,
    touch_attack_ratio_note: V('dtk', 'touch hits: AttackRatio = 100'),
    roll: { distribution: 'uniform', min: 1.1, max: 1.5 },
    defense_curve: { def_level_offset: 40, def_level_multiplier: 5, raw_coefficient: 1.2 },
    clamp: { min: 1, max: 50000000, then: 'trunc' },
    def_stat: { physical: 'WDEF', magic: 'MDEF' },
    touch_zone_note: V('mon2', 'The touch zone deals contact damage when you walk into it. Attack power is a percent of the monster\'s own damage stat: physical attacks use P.DMG, magic attacks use M.DMG.'),
    midpoint_note: V('gdmg', 'The calculator\'s middle damage value uses `U = 0.5`, or a `1.3` attack roll.'),
    calculator_code: C(calcChunk, 't=e=>{let t=a*e;return Math.trunc(D(t*(1-l/(l+5*(r+40)+1.2*t)),1,5e7))};return[E("Damage taken",t(1.1),t(1.5),0)]'),
  },
  elemental_resistance: {
    status: STATUS.plain,
    formula: V('dtk', 'Taken = AfterDefense × (1 - Resist / 100)'),
    notes: VV('dtk', [
      'Applies to monster attacks with an element, magic and physical.',
      'Applied after defense, before the damage cap.',
      'Touching a monster deals damage with no element, so resistance never reduces it.',
    ]),
  },
  after_hit: {
    post_hit_invincibility_s: 1.5,
    statements: VV('dtk', ['Invincible after a hit: 1.5 s', 'A monster attack that misses you or that you block gives the same 1.5 s.']),
    knockback: 'See movement.json (knockback_airtime).',
  },
  defensive_skills_not_beginner: {
    status: STATUS.model,
    formulas: VV('dtk', [
      'Power Crash attack = trunc(EffectiveMobAttack × (1 - Reduction / 100))',
      'Invincible (Cleric line): TouchDamage × (1 - Reduction / 100)',
      'Meso Guard damage = DamageBeforeGuard × (1 - Reduction / 100)',
      'Meso cost = DamageBeforeGuard × Reduction / 100 × CostRate / 100',
      'Hyper Body HP = MaxHP × (1 + Bonus / 100)',
      'Magic Guard survival = min(HyperBodyHP + MaxMP, HyperBodyHP / (1 - Transfer))',
      'At 100% transfer: Magic Guard survival = HyperBodyHP + MaxMP',
    ]),
  },
  parity_examples: [
    { kind: 'outgoing_hit', input: { total_acc: 100, player_level: 50, mob_level: 50, mob_eva: 20 }, hit_chance: 1, accuracy_roll: [32.02, 46.41], note: '/formulas Try-values defaults' },
    { kind: 'incoming_hit', input: { mob_acc: 100, player_eva: 50, player_level: 50, mob_level: 50 }, hit_chance_pct: 99.8, accuracy_roll: [30.74, 47.69], note: '/formulas/damage-taken Try-values defaults' },
    { kind: 'incoming_damage', input: { mob_attack: 300, def: 100, player_level: 50 }, taken: [295, 408], note: '/formulas/damage-taken Try-values defaults' },
    { kind: 'incoming_damage', input: { mob_attack: 3, def: 0, player_level: 1 }, taken: [3, 4], note: 'Snail (monster 2): "Touch DMG 3-4, Base 3"' },
  ],
  source: mainSource('acc'),
  field_sources: {
    incoming_hit: src('dtk'), guards: src('dtk'), incoming_damage: src('dtk'), elemental_resistance: src('dtk'), after_hit: src('dtk'),
    defensive_skills_not_beginner: src('dtk'), floor_rule: src('gdmg'), 'outgoing_hit.notes': src('gdmg'),
    'incoming_hit.rescue_note': src('gdmg'), 'incoming_hit.magic_note': src('gdmg'), 'guards.combine_rule': src('gdmg'),
    'incoming_damage.touch_zone_note': src('mon2'), 'parity_examples.3': src('mon2'), calculator_code: chunkSrc(calcChunk, 'acc'),
  },
  gaps: [
    'Monster knockback on being hit (when a monster is pushed back / staggers) has only the glossary definition; no formula. See movement.json.',
    'Which monster "attack ratio" applies to non-touch monster attacks is per-skill monster data (monsters domain); only touch hits (100) are documented here.',
  ],
};

// ===============================================================================================================
// 4. Damage
// ===============================================================================================================
const physLines = VV('dmg', [
  'S = SkillDamage / 100',
  'M = (MasteryLevel / 10 + 0.1) × 0.8',
  'B = uniform(0.8, 1.0)',
  'Q = uniform(Primary × M, Primary)',
  'Raw = S × TotalWATK × (B + (Q × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)',
  'MIN = S × TotalWATK × (0.8 + (Primary × M × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)',
  'MAX = S × TotalWATK × (1.0 + (Primary × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)',
  'Average = S × TotalWATK × (0.9 + (Primary × (M + 1) / 2 × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)',
  'Ordinary attacks: StatDiv = 100 · APDiv = 50',
]);
V('gdmg', 'B and Q are independent random draws.');
const magicLines = VV('dmg', [
  'S = SkillPower / 100',
  'MagicTotal = floor(TotalINT / 2) + EquipmentMATK + ScrollMATK + BuffMATK',
  'MIN = S × MagicTotal × (1 + TotalINT × M / 100)',
  'MAX = S × MagicTotal × (1 + TotalINT / 100)',
  'Average = (MIN + MAX) / 2',
]);
// Weapon families (primary/secondary)
const famAt = afterHeader('dmg', ['Weapon or attack', 'Primary', 'Secondary']);
const famRows = rows('dmg', famAt, 3, 5);
{
  const g = rows('gdmg', afterHeader('gdmg', ['Weapon family', 'Primary', 'Secondary']), 3, 4);
  check(g.length === 4 && g.every((r, i) => r[1] === famRows[i][1] && r[2] === famRows[i][2]), 'weapon family primary/secondary agree between /formulas/damage and the guide');
}
const FAM_KEYS = ['sword_axe_blunt_spear_polearm', 'bow_crossbow', 'dagger_claw', 'wand_staff_physical', 'spell'];
const weaponFamilies = famRows.map((r, i) => ({ key: FAM_KEYS[i], label: r[0], primary: r[1], secondary: r[2] === '-' ? null : r[2] }));
// Weapon multipliers
const mulAt = afterHeader('dmg', ['Weapon', 'Swing', 'Stab', 'Shoot', 'Mixed']);
const mulRows = rows('dmg', mulAt, 5, 9);
const MUL_KEYS = ['one_handed_sword', 'two_handed_sword', 'one_handed_axe_or_blunt', 'two_handed_axe_or_blunt', 'spear', 'polearm', 'dagger', 'bow_crossbow_claw', 'wand_staff_physical'];
const weaponMultipliers = Object.fromEntries(mulRows.map((r, i) => [MUL_KEYS[i], { label: r[0], swing: dashNull(r[1]), stab: dashNull(r[2]), shoot: dashNull(r[3]), mixed: dashNull(r[4]) }]));
{
  const g = rows('gdmg', afterHeader('gdmg', ['Weapon', 'Swing', 'Stab', 'Shoot', 'Mixed']), 5, 9);
  check(g.every((r, i) => [1, 2, 3, 4].every((c) => dashNull(r[c]) === dashNull(mulRows[i][c]))), 'weapon multiplier table agrees between /formulas/damage and the guide ("-" == "Not used")');
}
// Swing / stab odds
const ssAt = afterHeader('dmg', ['Weapon', 'Swing', 'Stab', 'Average multiplier']);
const ssRows = rows('dmg', ssAt, 4, 12);
const SS_KEYS = ['one_handed_sword', 'two_handed_sword', 'one_handed_axe_or_blunt', 'two_handed_axe_or_blunt', 'spear', 'polearm', 'dagger', 'bow_close_range', 'crossbow_close_range', 'claw_close_range', 'wand_staff', 'barehanded'];
const actionOdds = Object.fromEntries(ssRows.map((r, i) => [SS_KEYS[i], { label: r[0], swing_pct: pct(r[1]), stab_pct: pct(r[2]), average_multiplier: dashNull(r[3]) }]));
check(actionOdds.barehanded.label === 'Barehanded' && actionOdds.barehanded.stab_pct === 100 && actionOdds.barehanded.swing_pct === null && actionOdds.barehanded.average_multiplier === null, 'barehanded row = - / 100% / -');
const specialLines = VV('dmg', [
  'Lucky Seven: WeaponMult = 3.0 · M = 0.5',
  'Drain: WeaponMult = 2.5',
  'Bow / Crossbow / Claw projectile: WeaponMult = 2.5 · StatDiv = 100 · APDiv = 50',
  'Close-range ranged swing: WeaponMult = 1.0 · StatDiv = 300 · APDiv = 150',
  'Close-range ranged stab: WeaponMult = 1.0 · StatDiv = 300 · APDiv = 50',
  'Crouched attack: WeaponMult = 1.0 · StatDiv = 300 · APDiv = 150 · B = uniform(0.2, 0.3)',
  'Magic skill: no WeaponMult',
]);
const defenseLines = VV('dmg', ['EffectiveDEF = max(0, FlatBonus + trunc((1 + PercentBonus / 100) × BaseDEF))', 'Defended = Raw × 100 / (EffectiveDEF + 100)']);
const elementLines = VV('dmg', [
  'Single element: immune 0 · resistant 0.75 · neutral 1.0 · weak 1.25',
  'Composition multiplier = 0.25 × (Code(Element1) + Code(Element2))',
  'Element codes: immune 0 · resistant 1 · neutral 2 · weak 3',
  'Any other element result counts as 1.0.',
]);
const elemAt = afterHeader('gdmg', ['Result', 'Multiplier']);
const elemRows = rows('gdmg', elemAt, 2, 7);
const levelGapLines = VV('dmg', [
  'Gap = MobLevel - PlayerLevel',
  'LevelScale = 1 when Gap ≤ 0',
  'LevelScale = 1 / (1 + Gap² × 0.005) when Gap is 1-9',
  'LevelScale = 1 / (1 + Gap × 0.05) when Gap ≥ 10',
]);
const critLines = VV('dmg', [
  'Critical hit = Normal × (1 + d)',
  'Expected with crit = Normal × (1 + c × d)',
  'Before gear and passives, the critical rate is 5% and critical damage is 20%.',
  'Power Knockback always lands as a critical hit.',
  'Damage over time and bleed can land as critical hits.',
]);
V('gdmg', 'Base values before gear and passives: `c = 0.05`, `d = 0.20`.');
const clampLine = V('dmg', 'Final = trunc(clamp(value, 1, 99,999))');
// Pipeline order table in the guide
const ordAt = afterHeader('gdmg', ['Order', 'Operation']);
const ordRows = rows('gdmg', ordAt, 2, 6);
// Raw damage helper for parity checks (uses only constants transcribed above)
function physRange({ S = 1, watk, primary, secondary, mult, mastery = 0, ap = 0, statDiv = 100, apDiv = 50 }) {
  const M = (Math.min(10, Math.max(0, mastery)) / 10 + 0.1) * 0.8;
  return {
    min: S * watk * (0.8 + (primary * M * mult + secondary) / statDiv + ap / apDiv),
    max: S * watk * (1.0 + (primary * mult + secondary) / statDiv + ap / apDiv),
    avg: S * watk * (0.9 + ((primary * (M + 1)) / 2 * mult + secondary) / statDiv + ap / apDiv),
  };
}
const fin = (x) => Math.trunc(Math.min(99999, Math.max(1, x)));
{
  const w = physRange({ watk: 47, primary: 132, secondary: 30, mult: 1.8 });
  check(fin(w.min) === 60 && fin(w.max) === 172, 'guide Lv30 Warrior Gladius window 60-172');
  const ps = physRange({ S: 2.6, watk: 47, primary: 132, secondary: 30, mult: 1.8 });
  check(fin(ps.min) === 157 && fin(ps.max) === 449, 'guide Lv30 Warrior Power Strike 157-449');
  const raw = physRange({ S: 1, mastery: 10, watk: 80, primary: 250, secondary: 50, mult: 2.5 });
  check(Math.round(raw.min) === 544 && Math.round(raw.max) === 620, '/formulas/damage physical calculator default -> 544-620');
}
// Beginner guide: Snail (HP 45, no DEF, Lv 1) with 13 STR / 4 DEX; split-action weapons use lowest MIN / highest MAX.
const SNAIL_HP = 45;
const hits = (dmg) => Math.ceil(SNAIL_HP / Math.max(1, Math.trunc(dmg)));
function beginnerWeaponCheck(watk, swing, stab) {
  const s = physRange({ watk, primary: 13, secondary: 4, mult: swing }), t = physRange({ watk, primary: 13, secondary: 4, mult: stab });
  const avg = 0.6 * s.avg + 0.4 * t.avg;
  return [hits(Math.min(s.min, t.min)), hits(avg), hits(Math.max(s.max, t.max))].join('/');
}
const snailTable = {
  sword: beginnerWeaponCheck(17, 1.8, 1.8),
  hand_axe: beginnerWeaponCheck(17, 2.4, 1.2),
  wooden_club: beginnerWeaponCheck(19, 2.4, 1.2),
};
check(snailTable.sword === '4/3/3' && snailTable.hand_axe === '4/3/3' && snailTable.wooden_club === '3/3/2',
  `Beginner guide Snail hit counts reproduce (got ${JSON.stringify(snailTable)})`);
V('mon2', 'HP 45');
VV('gbeg', ['Against a level 1 Snail with all 9 creation AP in STR (13 STR, 4', 'Sword', '4 hits', 'Wooden Club', '2 hits']);

const otherMechanics = (key, title, end, status) => ({ title, status, lines: block(key, title, end).filter((l) => !['Unconfirmed', "MeowDB's Model", 'Mechanic', 'Formula'].includes(l)) });
const damage = {
  id: 'damage',
  name: 'Outgoing damage formulas (physical, magic, defense, element, level gap, critical, clamp)',
  status: STATUS.plain,
  pipeline_order: {
    steps: ['hit_check', 'raw_roll', 'defense', 'element', 'level_gap', 'critical', 'final_clamp'],
    statement: VV('gdmg', ['After the raw roll', 'Hit check', 'Raw roll', 'Defense', 'Element', 'Level gap', 'Critical', 'Final clamp']).join(' / '),
    post_raw_operations: ordRows.map(([n, op]) => ({ order: num(n), operation: op })),
    skill_bonus_stage: V('dmg', 'Applied to the skill\'s power before the base roll.'),
    hit_effects_stage: V('dmg', 'Multipliers applied after defense.'),
    note: V('gdmg', 'These cover the common branches. Separate rules apply to Lucky Seven and prone attacks. Heal and damage over time also use the expandable reference.'),
  },
  physical: {
    formulas: physLines,
    independent_rolls: V('gdmg', 'B and Q are independent random draws.'),
    distribution_note: V('gdmg', 'MIN and MAX are the opposite corners of two independent rolls, so the distribution is concentrated toward the middle instead of being uniform across the displayed range. MasteryLevel is clamped to 0-10 for this base term.'),
    base_roll: { min: 0.8, max: 1.0 },
    ordinary_divisors: { stat_div: 100, ap_div: 50 },
    mastery: {
      formula: physLines[1],
      mastery_level_clamp: [0, 10],
      no_mastery_factor: 0.08,
      no_mastery_worked: V('gdmg', '= (0 / 10 + 0.1) × 0.8 = 0.08'),
      effect: V('gdmg', 'Weapon Attack multiplies the whole result. Mastery raises MIN only.'),
    },
    weapon_families: weaponFamilies,
    weapon_action_multipliers: weaponMultipliers,
    weapon_action_multipliers_note: V('gdmg', 'An explicit `Mixed` action uses the table\'s arithmetic midpoint.'),
    not_used_note: V('gdmg', '`Not used` means that action and weapon combination has no valid multiplier path. Ordinary play should never produce it.'),
    ordinary_action_odds: actionOdds,
    ordinary_action_odds_formula: V('dmg', 'Average multiplier = P(swing) × Swing + P(stab) × Stab'),
    ordinary_action_pool_note: V('gdmg', 'follows the current standing pool of three swing entries and two stab entries: 60% swing and 40% stab.'),
    ordinary_action_presentation_odds: 'Each of the five standing presentations is equally likely (20% each). MeowDB weapon item pages: "' + EQUAL_ODDS + '" See attack_styles.json ordinary_action_selection.',
    default_skill_action_note: V('dmg', 'A skill set to its weapon\'s default action stabs with swords, daggers, wands, staves and spears, swings with axes, blunt weapons and polearms, and shoots with bows, crossbows and claws.'),
    special_branches: {
      lines: specialLines,
      lucky_seven: { weapon_mult: 3.0, mastery_factor: 0.5 },
      drain: { weapon_mult: 2.5 },
      ranged_projectile: { applies_to: 'Bow / Crossbow / Claw projectile', weapon_mult: 2.5, stat_div: 100, ap_div: 50 },
      close_range_ranged_swing: { weapon_mult: 1.0, stat_div: 300, ap_div: 150 },
      close_range_ranged_stab: { weapon_mult: 1.0, stat_div: 300, ap_div: 50 },
      crouched_attack: { weapon_mult: 1.0, stat_div: 300, ap_div: 150, base_roll: { min: 0.2, max: 0.3 } },
      magic_skill: { weapon_mult: null },
      close_range_action_note: V('gdmg', 'A Bow always swings, a Crossbow swings or stabs at 50% each, and a Claw always stabs.'),
      wand_note: V('gdmg', 'Magic skills never use a weapon action multiplier. Wand and Staff `1.8` applies only to a physical whack.'),
    },
    stat_window_range: {
      description: V('gdmg', 'It predicts the lowest and highest damage from one ordinary basic physical attack.'),
      exclusions: V('gdmg', 'This range is calculated before the target\'s defenses and elements. It also excludes level-difference scaling, critical hits and a skill\'s damage value.'),
      split_action_rule: V('gdmg', 'MeowDB mirrors split-action weapons by using the lowest MIN and highest MAX across their possible ordinary actions.'),
    },
    attack_power_value_note: V('gdmg', 'For standard melee attacks and projectiles, 1 Attack Power adds the same raw damage as 2 points of secondary stat. Close-range Claw and Crossbow stabs are an exception: 1 Attack Power equals 6 secondary stat.'),
  },
  magic: {
    formulas: [magicLines[0], physLines[1], magicLines[1], magicLines[2], magicLines[3], magicLines[4]],
    guide_mastery_formula: V('gdmg', 'm = (SpellMastery / 10 + 0.1) × 0.8'),
    roll: V('gdmg', 'Ordinary magic uses one uniform roll between MIN and MAX. Total LUK and physical Weapon Attack do not enter this branch.'),
    note: V('gdmg', 'INT raises MagicTotal and the INT term. Mastery raises MIN only.'),
  },
  skill_bonuses: {
    lines: block('dmg', 'Combo, Panic and Charge', 'Try values').filter((l) => !['Mechanic', 'Formula'].includes(l)),
  },
  defense: {
    formulas: defenseLines,
    bypass_expected: V('gdmg', 'Raw × ((1 - g) × 100 / (EffectiveDEF + 100) + g)'),
    note: V('gdmg', 'Physical and magic defense use the same curve with different stats. A bypass proc produces either a defended hit or a full bypass; the last line is its expected value.'),
    def_stat: { physical: 'monster WDEF (P.DEF)', magic: 'monster MDEF (M.DEF)' },
    calculator_code: C(calcChunk, '100*M(e,"raw")/(Math.max(0,M(e,"defense"))+100)'),
  },
  elements: {
    formulas: elementLines,
    single_element_multiplier: { immune: 0, resistant: 0.75, neutral: 1.0, weak: 1.25 },
    composition_codes: { immune: 0, resistant: 1, neutral: 2, weak: 3 },
    composition_multiplier_coefficient: 0.25,
    result_table: elemRows.map(([r, m]) => ({ result: r, multiplier: num(m) })),
    other_result_multiplier: 1.0,
  },
  level_gap: {
    formulas: levelGapLines,
    branches: [
      { gap: '<= 0', scale: '1' },
      { gap: '1-9', scale: '1 / (1 + Gap^2 × 0.005)', coefficient: 0.005 },
      { gap: '>= 10', scale: '1 / (1 + Gap × 0.05)', coefficient: 0.05 },
    ],
    calculator_code: C(calcChunk, 'function I(e){return e<=0?1:e<10?1/(1+e**2*.005):1/(1+.05*e)}'),
    parity_example: {
      gap: 5, scale_pct: 88.9, raw: 1000, after: 889, after_exact: Math.round((1000 / (1 + 5 ** 2 * 0.005)) * 1000) / 1000,
      note: V('dmg', 'Damage after level gap') + ' (Try-values defaults: raw 1000, 5 levels above). The page displays the value rounded to an integer; the exact value is 1000 / 1.125 = 888.889. Do not truncate here: the final trunc happens only after the critical step.',
    },
  },
  critical: {
    formulas: critLines,
    base_rate_c: 0.05,
    base_damage_d: 0.2,
    expected_formula: V('gdmg', '= Normal × (1 + c × d)'),
  },
  final_clamp: { formula: clampLine, min: 1, max: 99999, rounding: 'trunc after clamp', calculator_code: C(calcChunk, 'let $=e=>Math.trunc(D(e,1,99999))') },
  other_mechanics: [
    otherMechanics('dmg', 'Element Amplification', 'Try values', STATUS.plain),
    otherMechanics('dmg', 'Shadow Partner and Iron Arrow', 'Try values', STATUS.plain),
    otherMechanics('dmg', 'Final Attack', 'Try values', STATUS.plain),
    otherMechanics('dmg', 'Heal', 'Party members hit, including you', STATUS.unconfirmed),
    otherMechanics('dmg', 'Damage Over Time', 'Try values', STATUS.plain),
    otherMechanics('dmg', 'Bleed (Axes and Coma)', 'Try values', STATUS.plain),
    otherMechanics('dmg', 'Meso Explosion', 'Try values', STATUS.unconfirmed),
    otherMechanics('dmg', 'Shadow Meso', 'Try values', STATUS.plain),
    otherMechanics('dmg', 'Linked Explosions', 'Arrow Bomb skill', STATUS.plain),
    otherMechanics('dmg', 'Summons', 'Try values', STATUS.plain),
    otherMechanics('dmg', 'Invincible Retaliation', 'Try values', STATUS.plain),
  ],
  bare_hands: {
    documented: false,
    weapon_attack: null,
    weapon_mult: null,
    note: 'MeowDB documents bare hands only as an attack presentation: hit boxes (Punch 1, Punch 2, Crouched attack; see attack_styles.json) and the ordinary-action row "Barehanded: Swing -, Stab 100%, Average multiplier -". It gives no Weapon Attack value, no weapon action multiplier and no damage example for an unarmed attack, and the Damage Simulator has no Beginner or unarmed option. Do not derive a value from the formula (TotalWATK would be 0); this is a gap.',
  },
  parity_examples: [
    { input: { skill_pct: 100, mastery_level: 0, total_watk: 47, primary_str: 132, secondary_dex: 30, weapon_mult: 1.8, attack_power: 0 }, window: [60, 172], note: V('gdmg', 'Character-window damage range: 60-172') },
    { input: { skill_pct: 260, mastery_level: 0, total_watk: 47, primary_str: 132, secondary_dex: 30, weapon_mult: 1.8, attack_power: 0 }, window: [157, 449], note: 'Max-level Power Strike on the same Warrior (guide)' },
    { input: { skill_pct: 100, mastery_level: 10, total_watk: 80, primary: 250, secondary: 50, weapon_mult: 2.5, attack_power: 0 }, raw_range_rounded: [544, 620], note: '/formulas/damage Try-values defaults (display rounds to integers)' },
    {
      input: { level: 1, str: 13, dex: 4, int: 4, luk: 4, target: 'Snail (monster 2): Lv 1, HP 45, no P.DEF' },
      hits_to_kill_min_avg_max: { sword_541: '4/3/3', hand_axe_576: '4/3/3', wooden_club_585: '3/3/2' },
      note: 'Beginner guide table; reproduced with the constants in this file, trunc after clamp, split-action weapons using lowest MIN / highest MAX and 60/40 average.',
    },
  ],
  source: mainSource('dmg'),
  field_sources: {
    'pipeline_order.statement': src('gdmg'), 'pipeline_order.post_raw_operations': src('gdmg'), 'pipeline_order.note': src('gdmg'),
    'physical.independent_rolls': src('gdmg'), 'physical.distribution_note': src('gdmg'), 'physical.mastery': src('gdmg'),
    'physical.weapon_action_multipliers_note': src('gdmg'), 'physical.not_used_note': src('gdmg'), 'physical.ordinary_action_pool_note': src('gdmg'),
    'physical.ordinary_action_presentation_odds': { urls: ['i541', 'i576', 'i585', 'i558'].map((k) => P[k].url), retrieved_at: P.i541.retrieved_at },
    'physical.special_branches.close_range_action_note': src('gdmg'), 'physical.special_branches.wand_note': src('gdmg'),
    'physical.stat_window_range': src('gdmg'), 'physical.attack_power_value_note': src('gdmg'), 'magic.guide_mastery_formula': src('gdmg'),
    'magic.roll': src('gdmg'), 'magic.note': src('gdmg'), 'defense.bypass_expected': src('gdmg'), 'defense.note': src('gdmg'),
    'elements.result_table': src('gdmg'), 'critical.expected_formula': src('gdmg'), 'parity_examples.0': src('gdmg'), 'parity_examples.1': src('gdmg'),
    'parity_examples.3': src('gbeg'), calculator_code: chunkSrc(calcChunk, 'acc'),
  },
  gaps: [
    'Bare-hand (no weapon) Weapon Attack, weapon action multiplier and attack speed are not documented on MeowDB.',
    'Whether Three Snails (fixed damage) is subject to the hit roll, level-gap scale or critical hits is not stated explicitly. Its page says character stats, weapon stats and target defense do not scale the fixed value, and lists "Target hit eligibility" (plus "Required shell item") as a conditional factor, which suggests the shared hit check applies; level gap and criticals are not mentioned.',
    'Critical rate/damage for a Beginner beyond the base c = 0.05, d = 0.20 is not documented (no Beginner passives exist).',
  ],
  discrepancies: [
    {
      topic: 'Displayed damage range vs roll distribution',
      values: [
        { url: P.ggloss.url, text: V('ggloss', 'The MIN-MAX damage window shown in your character stat window. Every hit rolls somewhere inside.') },
        { url: P.gdmg.url, text: 'MIN and MAX are the opposite corners of two independent rolls, so the distribution is concentrated toward the middle instead of being uniform across the displayed range.' },
      ],
      chosen: 'Two independent uniform rolls (B and Q), per the damage formula guide',
      reason: 'The guide is the dedicated methodology page; the glossary line is compatible (every hit is inside the window) but must not be read as one uniform roll.',
    },
    {
      topic: 'Heal undead damage formula',
      values: [
        { url: P.dmg.url, text: 't = PartyMembersHit + UndeadHit; Pool = ((TotalINT × r + TotalLUK) / 200 + 3) × MagicTotal × S × (1 + 0.1 × t); Undead damage per mob = trunc(trunc(Pool) / t × 0.5) (card labelled Unconfirmed)' },
        { url: P.gdmg.url, text: 't = max(2, every character and undead mob touched); Undead damage per mob = Pool × (1 + 0.1 × t) / t × 0.5' },
      ],
      chosen: 'Not used by a Beginner; both recorded (formulas tab text in other_mechanics, guide text in docs)',
      reason: 'Heal is a Cleric skill; resolve before implementing Clerics.',
    },
  ],
};

check(damage.level_gap.parity_example.after_exact === 888.889 && Math.round(damage.level_gap.parity_example.after_exact) === damage.level_gap.parity_example.after, 'level-gap default: 1000 / 1.125 = 888.889, displayed as 889');

// ===============================================================================================================
// 5. Attack speed
// ===============================================================================================================
const baseTimesAt = afterHeader('spd', ['Action', 'Base time (ms)']);
const baseTimeRows = rows('spd', baseTimesAt, 2, 7);
const BT_KEYS = ['swing', 'stab', 'spear_polearm_stab', 'bow_shot', 'crossbow_shot', 'crouched_attack', 'rush'];
const baseTimes = Object.fromEntries(baseTimeRows.map((r, i) => [BT_KEYS[i], { label: r[0], base_ms: num(r[1]) }]));
const speedAt = afterHeader('gspd', ['Speed', 'Label', 'Ordinary attack (ms)', 'Attacks per minute']);
const speedRows = rows('gspd', speedAt, 4, 13);
function parseLadder() {
  const L = P.gspd.lines;
  const at = afterHeader('gspd', ['Tier', 'Swing (ms)', 'Per min', 'Spear stab (ms)', 'Crossbow (ms)', 'Who gets here']);
  const out = [];
  let i = at;
  for (let tier = 0; tier <= 10; tier++) {
    check(L[i] === String(tier), `speed ladder tier ${tier} at line ${i}`);
    const r = { tier, swing_ms: num(L[i + 1]), per_min: num(L[i + 2]), spear_stab_ms: num(L[i + 3]), crossbow_ms: num(L[i + 4]) };
    const who = [];
    i += 5;
    while (i < L.length && !(L[i] === String(tier + 1) && isNum(L[i + 1]) && isNum(L[i + 4])) && L[i] !== 'Weapon speed by weapon type') who.push(L[i++]);
    r.who_gets_here = who.join(' ');
    out.push(r);
  }
  return out;
}
const ladder = parseLadder();
const timingLines = VV('spd', [
  'timingTier = clamp(resolvedTier, 0, 10)',
  'ScaledFrame = truncTowardZero(FrameDelay × (10 + timingTier) / 16)',
  'nativeMs = Σ ScaledFrame',
  'Player-facing Animation Time = 30 × ceil(nativeMs / 30)',
  'Effective cycle d = max(animation duration, skill-specific lockout)',
  'Completed casts in 60 s = floor(60,000 / d)',
  'One-minute damage = CompletedCasts × w',
  'F(t) = Σ pᵢ × (wᵢ + F(t - dᵢ)) for dᵢ ≤ t',
  'F(t) = 0 when no branch fits',
  'Exact one-minute expectation = F(60,000)',
  'Long-run DPS = Σ(pᵢ × wᵢ) / Σ(pᵢ × dᵢ / 1000)',
]);
// Whole-total scaling check against the published ladder (MeowDB publishes no per-frame lists).
const wholeTotal = (base, tier) => 30 * Math.ceil(Math.trunc((base * (10 + Math.min(10, Math.max(0, tier)))) / 16) / 30);
const scalingMismatches = [];
for (const r of ladder) {
  for (const [col, base] of [['swing_ms', 800], ['spear_stab_ms', 750], ['crossbow_ms', 820]]) {
    const w = wholeTotal(base, r.tier);
    if (w !== r[col]) scalingMismatches.push({ tier: r.tier, column: col, published_ms: r[col], whole_total_scaling_ms: w });
  }
}
for (const r of speedRows) check(num(r[2]) === wholeTotal(800, num(r[0])) || num(r[0]) > 10, `speed table tier ${r[0]} swing ${r[2]}`);
// Weapon type speed ranges (hand transcription, each value asserted)
const typeRanges = [
  ['Dagger', '3-4', 1, 'Bandit'], ['Claw', '3-5', 1, 'Assassin'], ['One-handed sword', '4-5', 2, 'Fighter, Page'], ['One-handed axe', '4-5', 2, 'Fighter'],
  ['One-handed mace', '4-5', 2, 'Page'], ['Two-handed sword', '5-6', 3, 'Fighter, Page'], ['Two-handed axe', '5-6', 3, 'Fighter'], ['Bow', '5-6', 3, 'Hunter'],
  ['Two-handed mace', '6-7', 4, 'Page'], ['Spear', '6-7', 4, 'Spearman'], ['Crossbow', '6-7', 4, 'Crossbowman'], ['Polearm', '7-8', 5, 'Spearman'],
].map(([w, sp, best, from]) => {
  const L = P.gspd.lines;
  const i = L.indexOf(w, afterHeader('gspd', ['Weapon', 'Speeds', 'Fastest weapons', 'Best with Booster', 'Booster from']));
  check(i > 0 && L[i + 1] === sp, `weapon speed range ${w} ${sp}`);
  return { weapon: w, speed_tiers: sp.split('-').map(Number), best_tier_with_booster: best, booster_from: from };
});
typeRanges.push({ weapon: 'Wand, staff', speed_tiers: [6, 7], best_tier_with_booster: 6, booster_from: null, note: V('gspd', 'Every wand and staff casts spells at Normal (6)') });
// Beginner weapons from their item pages
function itemWeapon(key, id) {
  const L = P[key].lines;
  const at = (lab) => L[L.indexOf(lab) + 1];
  const name = L[L.indexOf('Item Database') + 2];
  const speed = at('Attack Speed');
  const m = /^(\w+) \((\d+)\)$/.exec(speed);
  const cyc = L.indexOf('Attack cycle');
  const icon = /"iconKey":"(\d+)"/.exec(rsc(P[key].html))?.[1] ?? null;
  const mulAt = L.indexOf('Weapon Multipliers');
  return {
    item_id: id,
    name,
    subtype: L[L.indexOf('Item Database') + 6],
    watk: num(String(at('W.ATK')).replace('+', '')),
    level_req: L.includes('REQ LEV') ? num(at('REQ LEV')) : 0,
    attack_speed_label: m?.[1] ?? null,
    attack_speed_tier: m ? num(m[2]) : null,
    attack_cycle_ms: num(L[cyc + 1]),
    attack_cycle_with_booster_ms: num(L[cyc + 4]),
    swing_mult: num(String(L[mulAt + 2]).replace('×', '')),
    stab_mult: num(String(L[mulAt + 4]).replace('×', '')),
    icon_key: icon,
  };
}
const beginnerWeapons = [itemWeapon('i541', '541'), itemWeapon('i576', '576'), itemWeapon('i585', '585'), itemWeapon('i558', '558')];
// level_req 0 = the item page has no "REQ LEV" row; the Beginner shop list shows "-" in its Lv column for the starter trio.
VV('ieb', ['Wooden Club One-Handed Blunt Weapon - 19 - Fast (5) 50', 'Sword One-Handed Sword - 17 - Fast (4) 50', 'Hand Axe One-Handed Axe - 17 - Fast (4) 50', 'Razor Dagger 5 23']);
check(['i541', 'i576', 'i585'].every((k) => !P[k].lines.includes('REQ LEV')) && P.i558.lines.includes('REQ LEV'), 'starter trio pages have no REQ LEV row; Razor has one');
for (const w of beginnerWeapons) {
  check(w.attack_cycle_ms === wholeTotal(800, w.attack_speed_tier), `${w.name}: item page attack cycle ${w.attack_cycle_ms} = ladder swing at tier ${w.attack_speed_tier}`);
  check(w.attack_cycle_with_booster_ms === wholeTotal(800, w.attack_speed_tier - 2), `${w.name}: with-Booster cycle = tier - 2`);
}
check(beginnerWeapons.map((w) => `${w.name}:${w.watk}:${w.attack_speed_tier}`).join() === 'Sword:17:4,Hand Axe:17:4,Wooden Club:19:5,Razor:23:4', `beginner weapons parsed ${beginnerWeapons.map((w) => `${w.name}:${w.watk}:${w.attack_speed_tier}`).join()}`);

const attackSpeed = {
  id: 'attack_speed',
  name: 'Attack speed tiers and animation timing',
  status: STATUS.model,
  status_note: V('gspd', 'The frame durations and their attack-speed conversion are confirmed for ordinary COT2 characters, including Savage Blow. We still round displayed times up to 30 ms steps; that final rounding remains a model.'),
  timing_formula: timingLines.slice(0, 4),
  timing_tier_clamp: [0, 10],
  tier_scale: '(10 + timingTier) / 16',
  neutral_tier: 6,
  neutral_tier_note: V('spd', 'At speed tier 6 every frame keeps its base length.'),
  display_rounding_ms: 30,
  display_rounding_note: V('gdmg', 'Skill pages display the 30 ms player-facing Animation Time; current simulator throughput uses its resolved branch-completion durations before that display-only rounding, so the two values should not be substituted for one another.'),
  base_action_times_ms: baseTimes,
  base_action_times_note: V('spd', 'Base times add up the frames before attack speed scales each one.'),
  speed_tiers: speedRows.map(([t, label, ms, apm]) => {
    const l = ladder.find((x) => x.tier === num(t));
    return {
      tier: num(t), label, ordinary_attack_ms: num(ms), attacks_per_minute: num(apm),
      spear_stab_ms: l ? l.spear_stab_ms : ladder[10].spear_stab_ms, crossbow_ms: l ? l.crossbow_ms : ladder[10].crossbow_ms,
      who_gets_here: l ? l.who_gets_here : null,
    };
  }),
  speed_tiers_note: [
    V('gspd', 'Ordinary attack times use a sword, axe, mace, dagger, claw or bow swing. Attacks per minute counts completed attacks in 60 seconds.'),
    V('gspd', 'Tiers 11 and 12 take as long as tier 10, and no weapon in the game is slower than Slow (8).'),
    V('gspd', 'Two weapons with the same name can still attack at different speeds, which is why skill pages show the number beside the name: Fast (4) finishes an ordinary attack 30 ms before Fast (5).'),
  ],
  weapon_type_speed_ranges: typeRanges,
  boosters: {
    lines: VV('spd', ['Weapon Booster: Tier = WeaponTier - 2', 'Magician attacks: Tier = 6', 'Spell Booster: Tier = 6 - 1 at Lv 1-10 · 6 - 2 at Lv 11-20', 'Tier = clamp(Tier, 0, 12)']),
    notes: VV('spd', ['Weapon Booster only speeds up the weapon type it matches.', 'Spell Booster speeds up Fire/Poison and Ice/Lightning spells. A wand or staff\'s speed does not change a spell.']),
  },
  dps_model: { status: STATUS.model, formulas: timingLines.slice(4) },
  whole_total_scaling_check: {
    description: 'MeowDB publishes per-action base totals but not per-frame FrameDelay lists. Applying the timing formula to the base total (trunc(total × (10 + tier) / 16), then 30 × ceil(ms / 30)) reproduces every published ladder value except those listed here; per-frame truncation lowers them. Use the published ladder values (speed_tiers) as authoritative.',
    mismatches: scalingMismatches,
  },
  beginner_weapons: beginnerWeapons.map((w) => ({
    item_id: w.item_id, name: w.name, subtype: w.subtype, attack_speed_label: w.attack_speed_label, attack_speed_tier: w.attack_speed_tier,
    attack_cycle_ms: w.attack_cycle_ms, attack_cycle_with_booster_ms: w.attack_cycle_with_booster_ms,
  })),
  beginner_weapon_notes: VV('gbeg', ['Club attacks one tier slower than Sword or Hand Axe', 'Its 23 W.ATK and faster speed give every class path higher minimum and average damage than Wooden Club.']),
  three_snails: {
    skill_id: '0001000',
    base_action_ms: 800,
    animation_ms_at_normal_6: 810,
    weapon_speed_based: true,
    statements: VV('sk0001000', ['Weapon-speed based', 'Normal (6)', '810 ms']),
    class_page_anim: V('clsb', 'ANIM 800 MS'),
  },
  bare_hands: { attack_speed_tier: null, note: 'Not documented: no MeowDB page gives an attack speed or animation time for unarmed punches.' },
  source: mainSource('spd'),
  field_sources: {
    status_note: src('gspd'), display_rounding_note: src('gdmg'), speed_tiers: src('gspd'), speed_tiers_note: src('gspd'),
    weapon_type_speed_ranges: src('gspd'), beginner_weapons: { urls: ['i541', 'i576', 'i585', 'i558'].map((k) => P[k].url), retrieved_at: P.i541.retrieved_at },
    beginner_weapon_notes: src('gbeg'), three_snails: src('sk0001000'), 'three_snails.class_page_anim': src('clsb'),
  },
  gaps: [
    'Per-frame FrameDelay lists for each action are not published, so the per-frame truncation cannot be reproduced for arbitrary actions; use the published per-tier values.',
    'Unarmed (bare hands) attack speed / animation time is not documented.',
    'Animation time for Nimble Feet and Recovery casts: the skill pages say "Timing unavailable".',
  ],
};

// ===============================================================================================================
// 6. Attack styles / hit rectangles / targeting
// ===============================================================================================================
// Hit zone sets from MeowDB's client-derived JSON.
const SET_LABELS = {
  O: { swingO1: ['Swing 1', 'swing'], swingO2: ['Swing 2', 'swing'], swingO3: ['Swing 3', 'swing'], swingOF: ['Wide swing', 'swing'], stabO1: ['Thrust 1', 'thrust'], stabO2: ['Thrust 2', 'thrust'], stabOF: ['Deep thrust', 'thrust'], proneStab: ['Crouched attack', 'crouch'] },
  T: { swingT1: ['Swing 1', 'swing'], swingT2: ['Swing 2', 'swing'], swingT3: ['Swing 3', 'swing'], swingTF: ['Wide swing', 'swing'], stabO1: ['Thrust 1', 'thrust'], stabO2: ['Thrust 2', 'thrust'], stabOF: ['Deep thrust', 'thrust'], proneStab: ['Crouched attack', 'crouch'] },
  P: { swingP1: ['Overhead swing', 'swing'], swingT2: ['Side swing', 'swing'], swingP2: ['Short swing', 'swing'], swingPF: ['Full sweep', 'swing'], stabT1: ['Thrust 1', 'thrust'], stabT2: ['Thrust 2', 'thrust'], stabTF: ['Deep thrust', 'thrust'], proneStab: ['Crouched attack', 'crouch'] },
  crossBow: { swingT1: ['Overhead whack', 'swing'], stabT1: ['Thrust', 'thrust'], proneStab: ['Crouched attack', 'crouch'] },
  barehands: { stabO1: ['Punch 1', 'thrust'], stabO2: ['Punch 2', 'thrust'], proneStab: ['Crouched attack', 'crouch'] },
};
const SET_STYLE = { swordOL: 'O', swordOS: 'O', mace: 'O', swordTS: 'T', swordTL: 'T', axe: 'T', poleArm: 'P', spear: 'P', crossBow: 'crossBow', barehands: 'barehands' };
// MeowDB's own label lists (asserted in the chunk) for the standing basic presentations.
C(hitChunk, 'let l=[{action:"swingO3",label:"Swing 3",kind:"Swing"},{action:"swingO1",label:"Swing 1",kind:"Swing"},{action:"swingO2",label:"Swing 2",kind:"Swing"},{action:"stabO1",label:"Thrust 1",kind:"Thrust"},{action:"stabO2",label:"Thrust 2",kind:"Thrust"}]');
C(hitChunk, 'c=[{action:"swingT1",label:"Swing 1",kind:"Swing"},{action:"swingT3",label:"Swing 3",kind:"Swing"},{action:"swingT2",label:"Swing 2",kind:"Swing"},{action:"stabO2",label:"Thrust 2",kind:"Thrust"},{action:"stabO1",label:"Thrust 1",kind:"Thrust"}]');
C(hitChunk, '{weapon:"Spear or polearm",set:"poleArm",actions:[{action:"swingP1",label:"Overhead swing",kind:"Swing"},{action:"swingT2",label:"Side swing",kind:"Swing"},{action:"swingP2",label:"Short swing",kind:"Swing"},{action:"stabT1",label:"Thrust 1",kind:"Thrust"},{action:"stabT2",label:"Thrust 2",kind:"Thrust"}]}');
C(hitChunk, '{weapon:"Bare hands",set:"barehands",actions:[{action:"stabO1",label:"Punch 1",kind:"Thrust"},{action:"stabO2",label:"Punch 2",kind:"Thrust"}]}');
const bandSpec = C(hitChunk, 'let n={aimHeight:28,divisor:4,step:20,starts:{magic:50,ranged:65}}');
const snailSkillArea = C(hitChunk, '"0001000":{rc:300,rd:1,am:"magic"}');

function zoneSet(name) {
  const set = HZ.sets[name];
  const labels = SET_LABELS[SET_STYLE[name]];
  const band = (b) => Object.fromEntries(Object.keys(b).sort().map((a) => [a, {
    label: labels[a]?.[0] ?? null,
    kind: labels[a]?.[1] ?? null,
    box_px: b[a],
    far_px: Math.max(0, -b[a][0]),
    near_px: b[a][2] < 0 ? -b[a][2] : 0,
    up_px: Math.max(0, -b[a][1]),
    down_px: Math.max(0, b[a][3]),
    height_px: b[a][3] - b[a][1],
  }]));
  const out = { ordinary: band(set.ordinary) };
  if (set.level100) out.level100 = band(set.level100);
  return out;
}
const hzSets = Object.fromEntries(Object.keys(HZ.sets).sort().map((k) => [k, zoneSet(k)]));
// Weapon groups (rows of the /formulas/targeting reach table) mapped onto hit-zone sets.
const reachAt = afterHeader('tgt', ['Weapon', 'Horizontal reach', 'Vertical reach']);
const reachRows = rows('tgt', reachAt, 3, 14);
const GROUPS = [
  { set: 'poleArm', alt_set: 'spear', basic: ['swingP1', 'swingT2', 'swingP2', 'stabT1', 'stabT2', 'proneStab'], final_attack: ['swingPF', 'stabTF'], not_used: [], h: 'swingP1', v: 'swingT2' },
  { set: 'swordTL', basic: ['swingT1', 'swingT2', 'swingT3', 'stabO1', 'stabO2', 'proneStab'], final_attack: ['swingTF', 'stabOF'], not_used: [], h: 'stabO2', v: 'swingT1' },
  { set: 'swordTS', basic: ['swingT1', 'swingT2', 'swingT3', 'stabO1', 'stabO2', 'proneStab'], final_attack: ['swingTF', 'stabOF'], not_used: [], h: 'stabO1', v: 'swingT1' },
  { set: 'axe', basic: ['swingT1', 'swingT2', 'swingT3', 'stabO1', 'stabO2', 'proneStab'], final_attack: ['swingTF', 'stabOF'], not_used: [], h: 'swingT1', v: 'swingT1' },
  { set: 'swordOL', basic: ['swingO1', 'swingO2', 'swingO3', 'stabO1', 'stabO2', 'proneStab'], final_attack: ['swingOF', 'stabOF'], not_used: [], h: 'swingO3', v: 'swingO1' },
  { set: 'swordOS', basic: ['swingO1', 'swingO2', 'swingO3', 'stabO1', 'stabO2', 'proneStab'], final_attack: ['swingOF', 'stabOF'], not_used: [], h: 'swingO1', v: 'swingO1' },
  { set: 'swordOL', basic: ['swingO1', 'swingO2', 'swingO3', 'stabO1', 'stabO2', 'proneStab'], final_attack: ['swingOF', 'stabOF'], not_used: [], h: 'swingO3', v: 'swingO1' },
  { set: 'swordOL', basic: ['swingO1', 'swingO2', 'swingO3', 'stabO1', 'stabO2', 'proneStab'], final_attack: [], not_used: ['swingOF', 'stabOF'], h: 'swingO3', v: 'swingO1' },
  { set: 'swordOS', basic: ['swingO1', 'swingO2', 'swingO3', 'stabO1', 'stabO2', 'proneStab'], final_attack: [], not_used: ['swingOF', 'stabOF'], h: 'swingO1', v: 'swingO1' },
  { set: 'mace', basic: ['swingO1', 'swingO2', 'swingO3', 'stabO1', 'stabO2', 'proneStab'], final_attack: ['swingOF', 'stabOF'], not_used: [], h: 'swingO3', v: 'swingO1' },
  { set: 'mace', basic: ['swingO2', 'proneStab'], final_attack: [], not_used: ['swingO1', 'swingO3', 'stabO1', 'stabO2', 'swingOF', 'stabOF'], h: 'swingO2', v: 'swingO2' },
  { set: 'swordTS', basic: ['swingT1', 'swingT3', 'proneStab'], final_attack: [], not_used: [], h: 'proneStab', v: 'swingT1', labels: { swingT1: 'Overhead whack', swingT3: 'Uppercut whack' } },
  { set: 'crossBow', basic: ['swingT1', 'stabT1', 'proneStab'], final_attack: [], not_used: [], h: 'swingT1', v: 'swingT1' },
  { set: 'barehands', basic: ['stabO1', 'stabO2', 'proneStab'], final_attack: [], not_used: [], h: 'stabO1', v: 'stabO1' },
];
const weaponGroups = reachRows.map(([name, hz, vt], i) => {
  const g = GROUPS[i];
  const z = HZ.sets[g.set].ordinary;
  const hm = /^(\d+) px \((.+)\)$/.exec(hz), vm = /^(\d+) px \((.+)\)$/.exec(vt);
  check(hm && -z[g.h][0] === num(hm[1]), `reach table "${name}" horizontal ${hz} = -left of ${g.set}.${g.h} (${z[g.h]?.[0]})`);
  check(vm && -z[g.v][1] === num(vm[1]), `reach table "${name}" vertical ${vt} = -top of ${g.set}.${g.v} (${z[g.v]?.[1]})`);
  for (const a of [...g.basic, ...g.final_attack, ...g.not_used]) check(!!z[a], `${g.set} has ${a}`);
  return {
    group: name,
    hitzone_set: g.set,
    ...(g.alt_set ? { identical_set: g.alt_set } : {}),
    basic_actions: g.basic,
    final_attack_actions: g.final_attack,
    not_used_actions: g.not_used,
    unlabelled_actions: Object.keys(z).sort().filter((a) => ![...g.basic, ...g.final_attack, ...g.not_used].includes(a)),
    ...(g.labels ? { action_labels: g.labels } : {}),
    confirmed_basic_max_horizontal_px: num(hm?.[1]),
    horizontal_from: hm?.[2] ?? null,
    confirmed_basic_max_vertical_px: num(vm?.[1]),
    vertical_from: vm?.[2] ?? null,
  };
});
check(reachRows[13][0] === 'Barehanded', 'reach table last row is Barehanded');
check(JSON.stringify(HZ.sets.spear.ordinary) === JSON.stringify(HZ.sets.poleArm.ordinary), 'spear and poleArm hit zones identical');
// Cross-check: every SVG box on /guides/weapon-reach must exist in the JSON (diagram scale 2, origin x=470, feet y=280).
const svgCheck = (() => {
  const s = rsc(P.greach.html);
  const all = new Set();
  for (const set of Object.values(HZ.sets)) for (const band of Object.values(set)) for (const b of Object.values(band)) all.add(b.join());
  let checked = 0;
  const unmatched = [];
  const re = /\["\$","div","([^"]+)",\{"className":"rounded-lg border border-maple-border bg-maple-elevated\/50 p-2"/g;
  let m;
  while ((m = re.exec(s))) {
    const { value } = jsonAt(s, m.index);
    const flat = JSON.stringify(value);
    const r = /"rect",null,\{"x":(-?[\d.]+),"y":(-?[\d.]+),"width":([\d.]+),"height":([\d.]+)/.exec(flat);
    if (!r) continue;
    const [x, y, w, h] = r.slice(1).map(Number);
    const box = [(x - 470) / 2, (y - 280) / 2, (x + w - 470) / 2, (y + h - 280) / 2];
    checked++;
    if (!all.has(box.join())) unmatched.push({ card: m[1], box_px: box });
  }
  return { checked, unmatched };
})();
check(svgCheck.checked >= 50, `weapon-reach SVG boxes checked: ${svgCheck.checked}`);
// Beginner weapons -> hit-zone set via MeowDB iconKey (item page) -> hit-zone weapons map.
const beginnerWeaponStyles = beginnerWeapons.map((w) => {
  const set = HZ.weapons[w.icon_key] ?? null;
  check(!!set, `${w.name} iconKey ${w.icon_key} is in the hit-zone weapons map`);
  const fam = HZ.subtypeFamily[w.subtype] ?? null;
  return {
    item_id: w.item_id, name: w.name, subtype: w.subtype, icon_key: w.icon_key, hitzone_family: fam, hitzone_set: set,
    basic_actions: ['swingO1', 'swingO2', 'swingO3', 'stabO1', 'stabO2', 'proneStab'],
    swing_mult: w.swing_mult, stab_mult: w.stab_mult,
  };
});
check(beginnerWeaponStyles.map((w) => w.hitzone_set).join() === 'swordOL,swordOL,mace,swordOS', `beginner weapon sets ${beginnerWeaponStyles.map((w) => w.hitzone_set).join()}`);
V('greach', 'Pictured: Sword. Every 1H Axe, most 1H Swords, and the Zamadar daggers, Forked Dagger, Cass, and Shinkita use this set.');
V('greach', 'Pictured: Razor. Most daggers use this shorter set');
for (const k of ['i541', 'i576', 'i585', 'i558']) V(k, 'Basic attacks Swing 1 Swing 2 Swing 3 Thrust 1 Thrust 2 Crouched attack');
// Item pages list each basic attack's reach as "near-far px" + "up px"; they must equal the hit-zone boxes of the weapon's set.
const itemReachCheck = (() => {
  let checked = 0;
  const bad = [];
  const LABEL_TO_ACTION = { 'Swing 1': 'swingO1', 'Swing 2': 'swingO2', 'Swing 3': 'swingO3', 'Thrust 1': 'stabO1', 'Thrust 2': 'stabO2', 'Crouched attack': 'proneStab' };
  for (const w of beginnerWeaponStyles) {
    const L = P['i' + w.item_id].lines;
    const at = L.indexOf('Attack', L.indexOf('Attack distance'));
    const z = HZ.sets[w.hitzone_set].ordinary;
    for (let i = at + 3; i < L.length && LABEL_TO_ACTION[L[i]]; ) {
      const a = LABEL_TO_ACTION[L[i]];
      let near = 0, j = i + 1;
      if (/^\d+-$/.test(L[j])) { near = num(L[j].slice(0, -1)); j++; }
      const far = num(L[j]), up = num(L[j + 2]);
      const b = z[a];
      checked++;
      if (!(L[j + 1] === 'px' && L[j + 3] === 'px' && far === -b[0] && near === (b[2] < 0 ? -b[2] : 0) && up === -b[1])) bad.push(`${w.name} ${L[i]}: page ${near}-${far}/${up} vs box ${b}`);
      i = j + 4;
    }
  }
  return { checked, bad };
})();
check(itemReachCheck.checked === 24 && itemReachCheck.bad.length === 0, `item-page per-attack reach matches hit zones (${itemReachCheck.checked} checked): ${itemReachCheck.bad.join('; ')}`);

const attackStyles = {
  id: 'attack_styles',
  name: 'Attack hit rectangles, reach and target selection',
  status: STATUS.confirmed,
  status_note: V('greach', 'Close-range hit zones are the same in the first and second tests.'),
  coordinate_convention: 'box_px = [left, top, right, bottom] in MapleStory px relative to the attacker\'s origin (feet), character FACING LEFT, y down (negative y = above the feet). Mirror x (x -> -x, swap left/right) when facing right. Some boxes extend behind the character (right > 0) or below the feet (bottom > 0); keep them as is.',
  hitzone_data_source: {
    schema_version: HZ.schemaVersion,
    source_note: HZ.source,
    bands: HZ.bands,
    note: 'Bands: "ordinary" applies to character levels 1-99; "level100" replaces only the listed presentations from level 100. The White Knight "charge" band is omitted (MeowDB: never published).',
  },
  reach_definitions: VV('tgt', [
    'Horizontal reach is the distance from your character to the far edge of the hitbox.',
    'Vertical reach is how far above your feet the hitbox goes.',
    'Each value is the longest of that weapon\'s basic attacks, and the attack that reaches it is in brackets. Wands and staffs attack with Swing 2 only.',
    'Values are for levels 1 to 99. From level 100, 2H Axes and 2H Blunt Weapons reach 110 px and Crossbows 88 px. 1H Swords, 1H Axes and Daggers then reach 72 px high, or 58 px for the 85 px group.',
  ]),
  weapon_groups: weaponGroups,
  weapon_groups_note: 'basic_actions / final_attack_actions / not_used_actions follow the guide\'s card labels (Basic, Final Attack, Not used). unlabelled_actions are presentations present in the shared hit-zone set that MeowDB does not label for this weapon group (e.g. bows share the 2H-sword set but only the whacks and the crouched attack are listed as basic); do not treat them as usable basic attacks.',
  weapon_subtype_to_hitzone_family: HZ.subtypeFamily,
  hitzone_families: Object.fromEntries(Object.keys(HZ.families).sort().map((k) => [k, { primary_set: HZ.families[k].primarySet, weapon_count_by_set: HZ.families[k].sets }])),
  hitzone_family_naming_note: 'MeowDB\'s hit-zone family "wand" also covers One-Handed Blunt Weapon (they share the "mace" hit boxes). This is only a hit-box grouping: for damage, a One-Handed Blunt Weapon uses the 1H Axe / Blunt multipliers (swing 2.4, stab 1.2), not the wand physical 1.8 (Wooden Club item page confirms 2.4x / 1.2x).',
  hitzone_sets: hzSets,
  ordinary_action_selection: {
    rule: V('greach', 'A normal attack with a sword, axe, blunt weapon, spear, polearm, or dagger swings 60% of the time and stabs 40%. At close range, a bow always swings and a crossbow splits 50/50.'),
    presentation_odds_statement: EQUAL_ODDS,
    per_standing_presentation_pct: 20,
    per_standing_presentation_applies_to: 'Each of the five standing basic presentations (three swings + two thrusts) is picked with equal odds, 5 x 20% = 60% swing / 40% thrust; the crouched attack is not part of this pool. Stated verbatim on the MeowDB weapon item pages checked here (Sword 541, Hand Axe 576, Wooden Club 585, Razor 558). Other melee families with a three-swing/two-thrust standing set (2H swords, 2H axes/blunts, spears/polearms) follow the same 60/40 rule on the weapon-reach guide; their item pages were not opened by this extractor.',
    crouched_in_standing_pool: false,
    pool_note: 'Consistent with the damage guide: "follows the current standing pool of three swing entries and two stab entries: 60% swing and 40% stab." (damage.json).',
    bare_hands: 'Barehanded ordinary attacks are 100% stab (damage.json ordinary_action_odds). Bare hands have no item page, and the split between Punch 1 and Punch 2 is not documented.',
    crouched: 'Crouched attack (proneStab) is a separate basic attack used while lying down; its damage uses the crouched branch in damage.json.',
    skills_note: V('greach', 'Power Strike, Slash Blast, and the extra hit from Final Attack use the same 60/40 split as a normal attack.'),
  },
  overlap_rule: {
    lines: VV('tgt', [
      'Hit when max(AttackLeft, MonsterLeft) < min(AttackRight, MonsterRight)',
      'and max(AttackTop, MonsterTop) < min(AttackBottom, MonsterBottom)',
      'Both boxes must share width and height. Touching at an edge does not count.',
      'Weapon and monster artwork is ignored. Only the hitboxes count.',
    ]),
    strict_inequality: true,
  },
  target_selection_order: (() => {
    const at = afterHeader('tgt', ['Which Monsters Get Hit', 'Attack', 'Order']);
    return rows('tgt', at, 2, 5).map(([attack, order]) => ({ attack, order }));
  })(),
  target_selection_note: V('tgt', 'Several meso bags can pick the same monster.'),
  ranged_search_bands: {
    lines: VV('tgt', [
      'Widening bands: the first starts 65 px ahead, each band is 20 px long, its half-height is floor(d / 4), centered 28 px above your feet',
      'The same widening bands, starting 50 px ahead for spells and 65 px ahead for ranged skills',
      'd is the distance from you to the start of the band.',
    ]),
    aim_height_px: 28,
    band_length_px: 20,
    half_height_divisor: 4,
    start_px: { basic_bow_crossbow_claw: 65, ranged_skill: 65, spell: 50 },
    melee_attacks: V('tgt', 'The hitbox of the swing or stab being played'),
    area_skills: V('tgt', 'A fixed box in front of you or centered on you, mirrored when you face left'),
    calculator_code: bandSpec,
  },
  attack_ranges_px: {
    lines: VV('tgt', ['Spell: 300 px', 'Energy Bolt: 350 px', 'Bow / Crossbow: 300 + EyeOfAmazon px', 'Claw: 200 + KeenEyes px', 'Arrow Blow: 350 + EyeOfAmazon px', 'Three Snails: 300 px', 'EyeOfAmazon = 45 + 5 × Lv at Lv 1-15', 'KeenEyes = 40 + 10 × Lv at Lv 1-14 · 200 at Lv 15']),
    spell: 300, energy_bolt: 350, bow_crossbow_base: 300, claw_base: 200, arrow_blow_base: 350, three_snails: 300,
    three_snails_note: V('tgt', 'Three Snails reaches 300 px with any weapon. The Eye of Amazon and Keen Eyes do not extend it.'),
  },
  terrain_check: {
    lines: [V('tgt', 'Only basic ranged attacks and projectile skills check terrain. A blocked monster is dropped and its slot is not refilled.')].concat(
      rows('tgt', afterHeader('tgt', ['Terrain Check', 'Attack', 'Walls and platforms']), 2, 4).map(([a, b]) => `${a}: ${b}`),
    ),
    platform_rule: V('tgt', 'Shooting down through the platform you stand on is blocked. Shooting up through a platform is not.'),
  },
  cast_positions: rows('tgt', afterHeader('tgt', ['Where You Can Cast', 'Skill', 'Where you can cast']), 2, 7).map(([skill, where]) => ({ skill, where })),
  beginner_weapons: beginnerWeaponStyles,
  beginner_weapons_note: 'Join: item page iconKey (MeowDB RSC field) -> hit-zone JSON "weapons" map (keyed by the same icon key). The guide card images confirm the sets: item-anim/541-swingO3.gif (Sword) in the 1H Sword/Axe set and item-anim/558-*.gif (Razor) in the short dagger set; Wooden Club (585) is pictured for the 1H Blunt set.',
  bare_hands: {
    hitzone_set: 'barehands',
    basic_actions: ['stabO1', 'stabO2', 'proneStab'],
    labels: { stabO1: 'Punch 1', stabO2: 'Punch 2', proneStab: 'Crouched attack' },
    statement: V('greach', 'Bare hands: punches and crouched presentation'),
    reach_table_row: V('tgt', 'Barehanded 64 px (Punch) 33 px (Punch)'),
  },
  three_snails_targeting: {
    skill_id: '0001000',
    statements: VV('sk0001000', [
      'The target search begins 50 pixels ahead, checks 20 pixel bands, and widens by one pixel vertically for every four pixels horizontally.',
      'The search begins 28 px above your feet.',
      '100 px up / 44 px down',
    ]),
    band_start_px: 50,
    horizontal_reach_px: 300,
    vertical_reach_px: { up: 100, down: 44 },
    targets: 1,
    skill_area_code: snailSkillArea,
  },
  svg_cross_check: {
    description: 'Every hit box drawn on /guides/weapon-reach (SVG overlay, scale 2, attacker at x=470, feet at y=280) was converted back to px and looked up in the hit-zone JSON.',
    boxes_checked: svgCheck.checked,
    unmatched: svgCheck.unmatched,
  },
  item_page_reach_cross_check: {
    description: 'Each Beginner weapon item page lists every basic attack as "near- far px / up px" (Attack distance table). All values equal -left / -right (when right < 0) / -top of the matching hit-zone box.',
    attacks_checked: itemReachCheck.checked,
    mismatches: itemReachCheck.bad,
  },
  source: mainSource('greach'),
  field_sources: {
    hitzone_data_source: chunkSrc(hitChunk, 'cb'), hitzone_sets: chunkSrc(hitChunk, 'cb'), weapon_subtype_to_hitzone_family: chunkSrc(hitChunk, 'cb'),
    hitzone_families: chunkSrc(hitChunk, 'cb'), reach_definitions: src('tgt'), weapon_groups: src('tgt'), overlap_rule: src('tgt'),
    target_selection_order: src('tgt'), target_selection_note: src('tgt'), ranged_search_bands: src('tgt'), attack_ranges_px: src('tgt'),
    terrain_check: src('tgt'), cast_positions: src('tgt'), 'bare_hands.reach_table_row': src('tgt'),
    'ordinary_action_selection.presentation_odds_statement': { urls: ['i541', 'i576', 'i585', 'i558'].map((k) => P[k].url), retrieved_at: P.i541.retrieved_at },
    item_page_reach_cross_check: { urls: ['i541', 'i576', 'i585', 'i558'].map((k) => P[k].url), retrieved_at: P.i541.retrieved_at },
    beginner_weapons: { urls: ['i541', 'i576', 'i585', 'i558'].map((k) => P[k].url), retrieved_at: P.i541.retrieved_at },
    three_snails_targeting: src('sk0001000'), 'three_snails_targeting.skill_area_code': chunkSrc(hitChunk, 'cb'),
  },
  gaps: [
    'Which of Punch 1 / Punch 2 a bare-handed attack plays (probabilities) is not documented (bare hands have no item page carrying the "equal odds" sentence).',
    'Three Snails terrain interaction: its page says "Wall and platform interactions are not confirmed for this skill."',
  ],
  discrepancies: [
    {
      topic: 'Three Snails search band start',
      values: [
        { url: P.sk0001000.url, value_px: 50, text: 'The target search begins 50 pixels ahead (skill page); MeowDB skill-area data "0001000":{rc:300,rd:1,am:"magic"} uses the magic band (50 px).' },
        { url: P.tgt.url, value_px: 65, text: 'The same widening bands, starting 50 px ahead for spells and 65 px ahead for ranged skills (Three Snails is a projectile skill).' },
      ],
      chosen: 50,
      reason: 'The skill detail page (priority 1 in the brief) and MeowDB\'s per-skill data agree on 50 px; the targeting tab states a general rule.',
    },
  ],
};

// ===============================================================================================================
// 7. Spawn rate
// ===============================================================================================================
const spawnLines = VV('spn', [
  'Global respawn tick = 7.56 s',
  'Wave-point cooldown = 5 s',
  'Effective respawn = first 7.56 s tick at or after death + cooldown',
  'Wave ceiling per point = 3600 / 7.56 ≈ 476 spawns / hour',
  'Timed average per point = 3600 / (Timer + 3.78)',
]);
const capLines = VV('spn', ['PlayerScalar = min(1, 0.75 + 0.05 × (Players - 1))', 'Capacity = floor(SpawnPoints × PlayerScalar)']);
const capAt = afterHeader('spn', ['Players', 'Scalar']);
const capRows = rows('spn', capAt, 2, 6);
const killsLines = VV('spn', [
  'CyclesPerHour = 3600 / 7.56',
  'WaveSupply = WavePoints × CyclesPerHour × PlayerScalar',
  'TimedSupply = TimedPoints × 3600 / max(Timer + 3.78, 7.56)',
  'SupplyPerHour = WaveSupply + TimedSupply',
  'RequestedPerHour = KillsPerCycle × CyclesPerHour',
  'FractionOfCeiling = min(1, RequestedPerHour / SupplyPerHour) × Uptime',
  'KillsPerHour = round(PublishedKillsPerHour × FractionOfCeiling)',
  'EXPPerHour = round(PublishedEXPPerHour × FractionOfCeiling)',
  'MapEXPPerHour = Σ EXPPerHourᵢ',
]);
// Map page fields for a wave map (Snail Hunting Ground I)
const mapRsc = rsc(P.map40.html);
const mapMonsters = JSON.parse(/"monsters":(\[\{"id":"2","name":"Snail".*?\}\])/.exec(mapRsc)?.[1] ?? 'null');
const mapSpawnSample = /"spawns":\[(\{"mobId":"2","x":424,"y":342,"mobTime":0\})/.exec(mapRsc)?.[1] ?? null;
check(!!mapMonsters && mapMonsters[0].respawnMin === 0 && mapMonsters[0].waveSpawnCount === 40, 'map 000000040 monsters entry parsed (respawnMin 0, waveSpawnCount 40)');
check(!!mapSpawnSample, 'map 000000040 spawn sample with mobTime 0');
const spawnCalc = C(calcChunk, 'let a="timed"===P(e,"type")?Math.max(M(e,"timer")+3.78,7.56):7.56;return[S("Average respawn",`${A(a,2)} s`),S("Spawns per hour",3600/a,1)]');
const spawnRate = {
  id: 'spawn_rate',
  name: 'Monster respawn timing and map capacity',
  status: STATUS.model,
  status_note: V('gspawn', 'Our spawn model uses three rules: a global server tick, a per-spawn-point cooldown, and a map capacity that changes with player count. The exact player-count curve still needs direct confirmation in current live play.'),
  global_respawn_tick_s: 7.56,
  wave_point_cooldown_s: 5,
  timed_point_cooldown: 'the spawn point\'s own timer (map spawn "mobTime", in seconds) replaces the 5 s default',
  respawn_rules: spawnLines,
  effective_respawn_rule: V('gspawn', 'Effective respawn = the first 7.56s tick at or after (death + cooldown).'),
  effective_respawn_rule_note: 'Use this bracketed form from the spawn guide: the spawn point becomes ready at death + cooldown, and the mob appears on the first global tick at or after that moment. The formulas tab line "first 7.56 s tick at or after death + cooldown" has no brackets (see discrepancies).',
  respawn_explanation: VV('gspawn', [
    'The server runs one respawn check every 7.56 seconds, globally. That pass walks every loaded map and asks each empty spawn point whether it is ready to refill. The tick is a synchronization gate: a mob whose cooldown ended 1 second ago still has to wait for the next tick before it appears.',
    'When many mobs die in a short window (an AoE clear), they all respawn at the next tick together. The map looks empty for a few seconds, then refills in one wave.',
    'Each spawn point has its own post-death cooldown that runs in parallel with the global tick.',
    'Wave cooldowns are shorter than the tick, so a freshly-cleared wave point cycles roughly every 7.56s in active grinding.',
    'A timed boss on a 300s timer cycles in 300s plus up to 7.56s of tick slop, so closer to 304s on average.',
  ]),
  spawn_types: [
    { type: 'wave', map_mob_time: 0, cooldown_s: 5, description: V('gspawn', 'Wave-pool spawn (default) 5 seconds Default for every point') },
    { type: 'timed', map_mob_time: '> 0 (seconds)', cooldown_s: 'mobTime', description: V('gspawn', 'Timed spawn (the point has its own timer) That point\'s timer (60s, 180s, 300s, 1800s, etc.) Replaces the 5s default') },
  ],
  map_page_display: {
    explanation: 'MeowDB map pages list spawn points as {"mobId","x","y","mobTime"} and monsters as {"count","respawnMin","respawnMax","waveSpawnCount"}. mobTime 0 / respawnMin 0 / respawnMax 0 mean a wave-pool point (5 s cooldown), which the page labels "Wave (~7.5s)": in active grinding a wave point refills on the next 7.56 s server tick (the 5 s cooldown is shorter than the tick). "~7.5s" is a rounded display of the 7.56 s tick, not a separate constant.',
    example_map: { map_id: '000000040', monsters: mapMonsters, spawn_point_sample: JSON.parse(mapSpawnSample ?? 'null') },
    statements: [
      V('map40', 'Wave (~7.5s)'),
      V('map40', 'The server runs a global 7.56s respawn tick across every loaded map. After a mob dies its spawn point waits a cooldown (5s default, or usually the WZ mobTime value for timed spawns), then the mob reappears on the next tick. Field-boss schedules are server-owned, so unconfirmed live-timing windows are labelled when they differ from the raw map value.'),
    ],
  },
  derived_timing_note: 'Arithmetic implied by the rule (not stated by MeowDB): a wave-point mob reappears between 5 s and 12.56 s after it dies (death + 5 s cooldown, then wait for the next 7.56 s tick). When the mob is killed right as it spawns (on a tick), it reappears exactly one tick (7.56 s) later. MeowDB\'s calculator uses 7.56 s as the "Average respawn" for wave points and max(Timer + 3.78, 7.56) for timed points (3.78 s = half a tick of slop).',
  calculator_code: spawnCalc,
  capacity: {
    status: STATUS.model,
    formulas: capLines,
    player_scalar_table: capRows.map(([p, s]) => ({ players: p, scalar_pct: num(s.replace('%', '')) })),
    statements: VV('gspawn', [
      'The model sets maximum concurrent mobs to map spawn points multiplied by a player-count scalar: 75% for one player, then +5% per extra player, up to 100% at six. This curve powers the map calculators, but every live player-count step has not been measured yet.',
      'The player-count scalar does not apply to timed spawns.',
    ]),
    solo_scalar: 0.75,
    calculator_code: C(calcChunk, 'let a=Math.min(1,.75+.05*(Math.max(1,M(e,"players"))-1));return[S("Player scalar",`${A(100*a,0)}%`),S("Mob capacity",Math.floor(M(e,"points")*a),0)]'),
    example: { spawn_points: 40, solo_capacity: 30, full_party_capacity: 40, note: V('map40', 'This map has 40 spawn points, so capacity is ~30 concurrent mobs solo and 40 in a full party.') },
  },
  spawns_per_hour: {
    statements: VV('gspawn', [
      'For a wave-pool spawn point that always has someone clearing it, the upper ceiling is 3600 / 7.56 ≈ 476 spawns per hour. Apply the player-count scalar above: ~357/hr solo, ~476/hr in a full party.',
      'For a timed spawn on a 60-second timer, the per-point rate is 3600 / (60 + ~3.78) ≈ 56 spawns per hour; the tick adds an average half-tick (~3.78s) of slop on every cycle.',
    ]),
  },
  map_spawn_rate_multiplier: {
    applied_by_msc: false,
    statements: VV('gspawn', ['Each map\'s data carries a spawn-rate multiplier, typically between 0.8 and 2.0. Other MapleStory servers multiplied map capacity by it.', 'MSC does not.', 'The live game ignores it; capacity comes only from spawn-point count and the player scalar.']),
  },
  kills_and_exp_per_hour_model: { status: STATUS.model, formulas: killsLines },
  timed_boss_note: V('gspawn', 'Timed bosses ignore player count.'),
  unverified: V('gspawn', 'Still unverified in current live play: whether the player-count curve is exactly linear at every step, whether timed spawn points sit outside the wave-pool cap, and whether the 7.56-second tick can slip under load.'),
  source: mainSource('spn'),
  field_sources: {
    status_note: src('gspawn'), effective_respawn_rule: src('gspawn'), respawn_explanation: src('gspawn'), spawn_types: src('gspawn'), map_page_display: src('map40'),
    'capacity.statements': src('gspawn'), 'capacity.example': src('map40'), spawns_per_hour: src('gspawn'), map_spawn_rate_multiplier: src('gspawn'),
    timed_boss_note: src('gspawn'), unverified: src('gspawn'), calculator_code: chunkSrc(calcChunk, 'acc'),
  },
  gaps: [
    'Which spawn points are filled when capacity < spawn points (selection order or randomness) is not documented.',
    'Initial population when a map is first loaded is not documented.',
    'Whether the 7.56 s tick phase is shared across maps for a single player (global clock) is stated ("globally"), but the tick phase origin is not.',
  ],
  discrepancies: [
    {
      topic: 'Map mob-rate multiplier',
      values: [
        { url: P.map40.url, text: V('map40', 'Mob rate (1 x) multiplies that capacity: expect about 40 monsters up at a time. Not applied to the figures above yet; best reading from closed-beta play.') + ' / ' + V('map40', 'Mob rate multiplies how many monsters this map keeps alive at once. This map\'s mob rate is 1.0x, so its 40 spawn points are the whole story: about 40 monsters up at a time. The spawn figures above do not apply it yet. This is our best reading from closed-beta play, where a high-rate map held far more monsters than it has spawn points; an exact whole-map count has not been done.') },
        { url: P.gspawn.url, text: 'MSC does not. The live game ignores it; capacity comes only from spawn-point count and the player scalar.' },
        { url: P.ggloss.url, text: V('ggloss', 'There is no separate map-wide multiplier or fixed 40-mob cap.') },
      ],
      chosen: 'Capacity = floor(SpawnPoints × PlayerScalar); the map mob rate is not applied',
      reason: 'The dedicated spawn guide (updated 2026-08-24) and the glossary agree; the map pages themselves say their figures do not apply the mob rate and call it a "best reading from closed-beta play". Unresolved: mark for later verification. The map read here (000000040) shows mob rate 1.0x; check each map\'s mobRate in the maps domain before relying on either reading.',
    },
    {
      topic: 'Displayed respawn time',
      values: [
        { url: P.map40.url, text: 'Wave (~7.5s)' },
        { url: P.spn.url, text: 'Global respawn tick = 7.56 s' },
      ],
      chosen: 7.56,
      reason: 'The map label is a rounded display of the same model; the formulas tab gives the exact model constant.',
    },
    {
      topic: 'Effective respawn wording (operator grouping)',
      values: [
        { url: P.spn.url, text: spawnLines[2] },
        { url: P.gspawn.url, text: 'Effective respawn = the first 7.56s tick at or after (death + cooldown).' },
        { url: P.map40.url, text: V('map40', 'After a mob dies its spawn point waits a cooldown (5s default, or usually the WZ mobTime value for timed spawns), then the mob reappears on the next tick.') },
      ],
      chosen: 'first global tick at or after (death time + cooldown)',
      reason: 'The formulas-tab line can be misread as (first tick at or after death) + cooldown. The spawn guide brackets (death + cooldown), and the guide and map pages both describe the cooldown running first and the mob waiting for the next tick. Only this reading allows the stated 7.56 s cycle of a freshly-cleared wave point (the other reading would give 7.56 + 5 = 12.56 s and spawns off the tick).',
    },
  ],
};

// ===============================================================================================================
// 8. Movement (walk, climb, jump, pickup, knockback airtime, fall damage)
// ===============================================================================================================
const jumpAt = afterHeader('gmove', ['Jump', 'Height']);
const jumpRows = rows('gmove', jumpAt, 2, 5);
const movement = {
  id: 'movement',
  name: 'Movement speed, jump, pickup range, knockback airtime and fall damage',
  status: STATUS.confirmed,
  status_note: V('gmove', 'We measured COT2 video footage closely, frame by frame, and got these results.'),
  base_speed: 100,
  base_jump: 100,
  speed_cap: 140,
  jump_cap: 120,
  walk_speed: { formula: V('spd', 'Walk speed = 125 × (Speed + 20) / 100 px/s'), base_px_per_s: 150, cap_px_per_s: 200 },
  climb_speed: { formula: V('spd', 'Climb speed = Speed + 20 px/s'), base_px_per_s: 120, note: V('spd', 'Ropes and ladders use the climb speed. Haste raises both.') },
  caps_line: V('spd', 'Speed cap: 140 (200 px/s) · Jump cap: 120'),
  speed_notes: VV('gmove', [
    'Speed above 140 does nothing. Speed also has no effect on how fast you attack.',
    'MapleStory Classic World adds 20 Speed behind the scenes, so your 100 moves like the old 120.',
  ]),
  jump_height_px_by_jump: jumpRows.map(([j, h]) => ({ jump: num(j.replace(/ \(.*\)/, '')), height_px: num(h.replace(' px', '')) })),
  jump_note: V('gmove', 'At Jump 100 you rise 77 px. Each point of Jump adds launch speed, so height grows a little faster than Jump itself.'),
  nimble_feet_speed_bonus: 10,
  nimble_feet_note: V('gmove', 'Nimble Feet (every class) +10 - Beginner skill; lasts 10 to 30 sec; 3 min cooldown'),
  pickup_box_px: { left: 25, right: 25, above: 60, below: 30 },
  pickup_lines: VV('spd', ['Pickup box around your character:', 'x: 25 px left to 25 px right', 'y: 60 px above to 30 px below']),
  controls_statements: VV('q1013', [
    'Do you also know that if you press the down arrow key, you can crouch, and then jump while crouching, to leap down to a lower platform?',
    'If you press the up arrow key in front of a portal, you can enter it, and if you press the up arrow key in front of a ladder or rope, you can climb or hang from it.',
  ]),
  controls_note: 'Rain\'s Maple Quiz 1 (quest 1013) NPC dialogue: crouch (down) + jump drops through to a lower platform; up enters a portal or grabs a ladder/rope. Qualitative only; key bindings are configurable in game.',
  knockback_airtime: {
    status: STATUS.model,
    upward_speed_px_per_s: 270,
    gravity_px_per_s2: 2000,
    same_height_airtime_s: 0.27,
    time_to_peak_s: 0.135,
    rise_px: 18.225,
    lines: VV('dtk', [
      'UpwardSpeed = 270 px/s · Gravity = 2000 px/s²',
      'SameHeightAirtime = 2 × UpwardSpeed / Gravity = 0.270 s',
      'TimeToPeak = UpwardSpeed / Gravity = 0.135 s',
      'Rise = UpwardSpeed² / (2 × Gravity) = 18.225 px',
    ]),
    notes: VV('dtk', [
      'An ordinary knockback gives about 0.27 seconds of airtime when you start on the ground and land at the same height, with normal gravity and no further impacts or obstacles.',
      'This is a physics estimate. Existing movement, ledges and special attacks can change the flight. It does not measure how long you lose the ability to attack.',
    ]),
    gaps: ['Horizontal knockback speed/distance for the player is not documented.', 'Whether every hit knocks the player back (or only hits above some threshold) is not documented.'],
  },
  monster_knockback: {
    definition: V('ggloss', 'Being pushed backward when hit. Also the knockback resistance stat on mobs: a mob with 500 KB needs 500+ damage to stagger.'),
    gaps: ['Monster knockback distance/speed and stagger duration are not documented.'],
  },
  fall_damage: {
    status: STATUS.plain,
    lines: VV('dtk', [
      'N = consecutive movement updates with downward speed ≥ 500 px/s',
      'N ≤ 44: BaseFallDamage = 0',
      'N ≥ 45: BaseFallDamage = max(1, 36 - floor(336 / (N - 18)))',
      'N = 45: 24 · N = 60: 28 · N = 120: 33 · N ≥ 355: 36',
    ]),
    notes: VV('dtk', [
      'For a qualifying landing in COT2, base fall damage starts at 24 and caps at 36. The counter resets when downward speed falls below 500 px/s; N measures consecutive fast-falling updates. Taller drops generally increase it.',
      'Maps can disable fall damage.',
      'A flight-map setting multiplies it by 100, but none of the 426 checked COT2 maps enable that setting.',
      'DEF, avoidability, level and max HP do not enter this base formula. Final HP loss and mitigation from defensive skills remain unconfirmed.',
    ]),
    gaps: ['The length of one "movement update" (tick rate) is not documented.'],
  },
  source: mainSource('gmove'),
  field_sources: {
    walk_speed: src('spd'), climb_speed: src('spd'), caps_line: src('spd'), pickup_box_px: src('spd'), pickup_lines: src('spd'),
    knockback_airtime: src('dtk'), monster_knockback: src('ggloss'), fall_damage: src('dtk'),
    controls_statements: src('q1013'), controls_note: src('q1013'),
  },
  gaps: ['Walking acceleration/deceleration and air control are not documented.'],
};
check(jumpRows[0][0] === '100 (base)' && jumpRows[0][1] === '77 px' && jumpRows[4][1] === '111 px', 'jump table parsed');

// ===============================================================================================================
// 9. Death
// ===============================================================================================================
const deathLines = VV('lvl', ['Loss = floor(EXP to next level × (5 + 20 / LUK) / 100)', 'EXP after death = max(0, EXP - Loss)', 'LUK 4: 10% · LUK 10: 7% · LUK 20: 6% · LUK 50: 5.4% · LUK 100: 5.2%']);
const deathNotes = VV('lvl', ['LUK is base LUK: the points you put in, before gear.', 'EXP stops at 0, so a death never takes away a level.', 'A Safety Charm stops the loss.']);
const deathCode = C(calcChunk, 'l=D(Math.floor(M(e,"luk")),4,999),r=Math.round(a*D(M(e,"expPercent"),0,100)/100),t=Math.max(0,r-Math.floor(a*(5+20/l)/100))');
check(Math.floor((95700 * (5 + 20 / 4)) / 100) === 9570, 'death loss Lv30 LUK4 = 9,570');
const deathExpPenalty = {
  status: STATUS.model,
  formulas: deathLines,
  notes: deathNotes,
  luk_basis: 'The character\'s own base LUK: the starting 4 plus every AP placed in LUK, before equipment and buffs ("the points you put in, before gear"). Every character starts with 4 LUK, and MeowDB\'s calculator clamps the input to 4..999. Do not use only the allocated AP (that can be 0 and would divide by zero).',
  base_loss_pct: 5,
  luk_term_numerator: 20,
  calculator_luk_clamp: [4, 999],
  calculator_code: deathCode,
  parity_example: { level: 30, base_luk: 4, exp_before: 47850, loss: 9570, exp_after: 38280, note: V('lvl', 'EXP after death 38,280 (40%)') },
  town_exception: null,
  beginner_exception: null,
  exceptions_note: 'MeowDB documents NO exception for dying in town and NO Beginner exception. The only documented way to avoid the loss is a Safety Charm. Do not add exceptions from other sources without recording them as external.',
};
const death = {
  id: 'death',
  name: 'Death: EXP penalty and respawn',
  death_trigger: { dies_when_hp_reaches: 0, statement: V('npc3', 'You\'ll die when your HP reaches 0, so it\'s for your own good to consume a potion or food before it\'s too late.') },
  exp_penalty: deathExpPenalty,
  respawn_location: {
    rule: 'Each map has a "Respawn Map" ("Where you return after dying") on its MeowDB map page; use the maps domain value.',
    statement: V('map40', 'Where you return after dying'),
    example: { map_id: '000000040', respawn_map_name: 'Southperry', text: V('map40', 'Respawn Map Southperry Where you return after dying') },
  },
  general_statement: V('gwhat', 'Combat is slower. Monsters can take several hits, potions matter, maps are crossed on foot, and death costs EXP.'),
  source: mainSource('lvl'),
  field_sources: { death_trigger: src('npc3'), 'exp_penalty.calculator_code': chunkSrc(calcChunk, 'acc'), respawn_location: src('map40'), general_statement: src('gwhat') },
  gaps: [
    'HP/MP after respawning is not documented.',
    'Respawn delay / death screen timing is not documented.',
    'Whether items or mesos are lost on death is not documented (only EXP loss is).',
    'Town or Beginner exceptions to the EXP loss are not documented (none listed).',
  ],
};

// ===============================================================================================================
// 10. Recovery
// ===============================================================================================================
const recovery = {
  id: 'recovery',
  name: 'HP/MP recovery: natural regeneration, chairs, Recovery skill, consumables, level-up',
  natural_regeneration: {
    documented_values: false,
    hp_per_tick: null,
    mp_per_tick: null,
    tick_interval_s: null,
    statements: VV('q1016', [
      'When you\'re not in combat, just standing still will slowly restore your HP.',
      'Just press the sit key when you\'re near one, and you\'ll notice that your recovery speed is faster than when you\'re just standing.',
    ]),
    statement_source_note: 'Quest 1016 (Rain\'s Maple Quiz 4) NPC dialogue: qualitative only.',
  },
  chairs: [
    {
      item_id: '522', name: 'The Green Relaxer', additional_hp_per_tick: 30, tick_interval_s: 10, stacks_with_natural_regen: true, level_req: 0, tradeable: false,
      how_to_get: "Pio's quest, Maple Island",
      item_page_statement: V('i522', 'Catch your breath and relax by sitting on this chair to restore an additional 30 HP every 10 seconds.'),
    },
    {
      item_id: '525', name: 'Sky-blue Wooden Chair', additional_hp_per_tick: 30, tick_interval_s: 10, stacks_with_natural_regen: true, level_req: 5, tradeable: true,
      how_to_get: 'Mina, Lith Harbor, 1,000 mesos',
      item_page_statement: V('i525', 'A specially-made sky-blue wooden chair that\'s only available in Lith Harbor. Restores an additional 30 HP every 10 seconds.'),
    },
  ],
  chairs_note: 'Item detail pages (priority 1) say the chair restores an ADDITIONAL 30 HP every 10 seconds ("HP Recovery +30"; MeowDB item API stat "hpRecoverBonus": 30): a bonus on top of the character\'s own resting regeneration, whose amount is undocumented. The Beginner\'s guide table shortens this to "30 HP every 10 s" (see discrepancies).',
  chairs_statements: VV('gbeg', ['The Green Relaxer Pio\'s quest, Maple Island Free 30 HP every 10 s', 'Sky-blue Wooden Chair Mina, Lith Harbor 1,000 mesos 30 HP every 10 s']),
  recovery_skill: 'See beginner.json skills (Recovery, skill 0001001: fixed HP total over 30 s).',
  consumables: {
    rule: 'Potions and food restore the flat amount listed on each item page (items domain is authoritative).',
    beginners_guide_examples: [
      { item_id: '238', name: 'Meat', restores_hp: 160, price_mesos: 80 },
      { item_id: '270', name: 'Red Potion', restores_hp: 100, price_mesos: 50 },
      { item_id: '271', name: 'Orange Potion', restores_hp: 250, price_mesos: 150 },
      { item_id: '240', name: 'Lemon', restores_mp: 150, price_mesos: 150 },
      { item_id: '273', name: 'Blue Potion', restores_mp: 200, price_mesos: 220 },
    ],
    table_rows: VV('gbeg', ['Meat 160 HP 80 2.0 HP', 'Red Potion 100 HP 50 2.0 HP', 'Orange Potion 250 HP 150 1.67 HP', 'Lemon 150 MP 150 1.0 MP', 'Blue Potion 200 MP 220 0.91 MP']),
    statements: VV('gbeg', ['Potions are most of what you spend mesos on early. Mobs drop them rarely, so buy the ones that restore the most per meso:', 'Rest when you run low.', 'Switch to basic attacks when MP is low; they cost no MP.']),
    orange_potion_id_note: 'The guide does not link Orange Potion; id 271 is taken from its item page (/item-db/271).',
  },
  level_up_heal: {
    heals: true,
    amount: null,
    statement: V('ghpmp', 'Unlike leveling up, job advancing does not heal you.'),
    note: 'Implied only: MeowDB contrasts job advancement (no heal) with leveling up. The amount (full or partial) is not stated.',
  },
  source: mainSource('q1016'),
  field_sources: {
    chairs: { urls: [P.i522.url, P.i525.url], retrieved_at: P.i522.retrieved_at }, 'chairs.0': src('i522'), 'chairs.1': src('i525'), 'chairs.0.how_to_get': src('gbeg'), 'chairs.1.how_to_get': src('gbeg'),
    chairs_note: { urls: [P.i522.url, P.i525.url], retrieved_at: P.i522.retrieved_at },
    chairs_statements: src('gbeg'), consumables: src('gbeg'), 'consumables.beginners_guide_examples.2.item_id': src('i271'), level_up_heal: src('ghpmp'),
  },
  gaps: [
    'Natural HP and MP regeneration amounts and intervals (standing, sitting on the ground, and the base resting regen that a chair\'s "additional" 30 HP / 10 s is added to) are not documented; only "slowly restore" (standing) and "faster" (chairs) are stated.',
    'Whether natural regeneration also restores MP is not stated.',
    'What counts as "in combat" (timer after hitting / being hit) is not documented.',
    'Potion use cooldown / animation lock is not documented.',
    'Level-up heal amount is not documented.',
  ],
  discrepancies: [
    {
      topic: 'Chair HP recovery: total or bonus',
      values: [
        { url: P.gbeg.url, text: 'Table "Chair / Where / Cost / Restores": ' + V('gbeg', 'The Green Relaxer Pio\'s quest, Maple Island Free 30 HP every 10 s') + ' / ' + V('gbeg', 'Sky-blue Wooden Chair Mina, Lith Harbor 1,000 mesos 30 HP every 10 s') },
        { url: P.i522.url, text: V('i522', 'Catch your breath and relax by sitting on this chair to restore an additional 30 HP every 10 seconds.') + ' (HP Recovery +30)' },
        { url: P.i525.url, text: V('i525', 'Restores an additional 30 HP every 10 seconds.') + ' (HP Recovery +30, Required Level 5)' },
      ],
      chosen: 'additional_hp_per_tick 30 every 10 s, added on top of the (undocumented) natural resting regeneration',
      reason: 'Item detail pages are priority 1 and both say "additional"; MeowDB\'s item API names the stat hpRecoverBonus. The guide table is a shortened summary.',
    },
  ],
};

VV('i271', ['Orange Potion', 'HP Recovery +250']);
VV('i522', ['HP Recovery +30', 'Untradeable', 'Quest Reward Pio\'s Collecting Recycled Goods']);
VV('i525', ['HP Recovery +30 Required Level 5', 'Tradeable', 'Mina', '1,000 mesos']);
check(!P.i522.lines.includes('Required Level'), 'The Green Relaxer page has no Required Level row (level_req 0)');
check(!P.i525.lines.includes('Untradeable') && P.i525.lines.includes('Tradeable'), 'Sky-blue Wooden Chair page says Tradeable');
for (const c of recovery.chairs) {
  const r = await fetchUrl(`${ORIGIN}/msclassic/api/items/${c.item_id}?locale=en&preview=1`);
  const api = JSON.parse(r.text);
  check(api.stats.hpRecoverBonus === c.additional_hp_per_tick && api.levelReq === c.level_req, `${c.name}: item API hpRecoverBonus/levelReq ${api.stats.hpRecoverBonus}/${api.levelReq}`);
}

// ===============================================================================================================
// 11. Loot rules
// ===============================================================================================================
const lootRules = {
  id: 'loot_rules',
  name: 'Drops, pickup, mesos and inventory rules',
  drop_timing: { statement: V('mon2', 'loot drops as soon as the mob dies.'), note: 'Monster page (Snail). The death animation length is per-monster data (Snail: body fades over 1.26 s).' },
  player_pickup_box_px: { left: 25, right: 25, above: 60, below: 30 },
  pickup_lines: VV('spd', ['x: 25 px left to 25 px right', 'y: 60 px above to 30 px below']),
  pickup_key_note: V('npc3', 'Items you pick up will be automatically stored in the appropriate tab.'),
  inventory_full: V('npc3', 'When your Item Inventory is full, you won\'t be able to pick up new items.'),
  ownership: {
    documented: 'partially',
    statement: null, // filled from /formulas/pets below
    party_loot_definition: V('ggloss', 'Whether item drops go free-for-all or rotate by party member.'),
  },
  drop_tables: {
    documented_rates: false,
    statement: V('mon2', 'Classic World appears to draw from the pre-Big-Bang MapleSEA drop tables. This list is historical reference only and shows what this monster dropped in old MapleSEA.'),
    community: V('mon2', 'Items players have personally seen drop in-game. Upvote what you\'ve seen, downvote what you haven\'t.'),
    note: 'Per-monster drop lists (community-confirmed and MSEA reference) are monsters/drops domain data. MeowDB gives no drop chances.',
  },
  mesos: {
    documented_formula: false,
    note: 'Monster pages show "Mesos per kill" from player reports (/msclassic/api/mesos-reports?monsterId=...), monsters domain. No meso-drop formula is published.',
  },
  source: mainSource('spd'),
  field_sources: { drop_timing: src('mon2'), pickup_key_note: src('npc3'), inventory_full: src('npc3'), 'ownership.party_loot_definition': src('ggloss'), drop_tables: src('mon2') },
  gaps: [
    'Drop expiry time (how long an item/meso stays on the ground) is not documented.',
    'Drop ownership duration (how long a drop belongs to the killer before becoming free-for-all) is not documented.',
    'Meso drop amount formula and item drop chances are not documented.',
    'Drop scatter pattern (spacing between multiple drops) is not documented.',
  ],
};
lootRules.ownership.statement = 'Pets follow your ownership rules. They take free drops and drops that belong to you or your party.';
// That sentence lives on /formulas/pets, which is not otherwise needed; load and assert it there.
{
  const r = await fetchPage('/formulas/pets');
  const t = norm(pageText(r.html).split('\n').map((s) => s.trim()).filter(Boolean).join(' '));
  check(t.includes(lootRules.ownership.statement), 'pets tab ownership sentence');
  lootRules.field_sources['ownership.statement'] = { url: r.url, retrieved_at: r.retrieved_at };
}

// ===============================================================================================================
// 12. Beginner
// ===============================================================================================================
function skillLevels(key) {
  const at = afterHeader(key, ['Lv', 'Effect']);
  return rows(key, at, 2, 3).map(([lv, effect]) => ({ level: num(lv), effect }));
}
const snailLv = skillLevels('sk0001000');
const recLv = skillLevels('sk0001001');
const nimLv = skillLevels('sk0001002');
const parseSnail = (e) => { const m = /^(.+) -1, MP -(\d+); Damage (\d+)$/.exec(e); return m ? { item_cost_name: m[1], item_cost_qty: 1, mp_cost: num(m[2]), fixed_damage: num(m[3]) } : null; };
const parseRec = (e) => { const m = /^MP -(\d+); Recover HP (\d+) in (\d+) sec\. Cooldown: (\d+) min\.$/.exec(e); return m ? { mp_cost: num(m[1]), hp_total: num(m[2]), duration_s: num(m[3]), cooldown_s: num(m[4]) * 60 } : null; };
const parseNim = (e) => { const m = /^MP -(\d+); speed \+(\d+) for (\d+) sec\. Cooldown: (\d+) min\.$/.exec(e); return m ? { mp_cost: num(m[1]), speed_bonus: num(m[2]), duration_s: num(m[3]), cooldown_s: num(m[4]) * 60 } : null; };
const SHELL_IDS = { 'Snail Shell': '348', 'Blue Snail Shell': '349', 'Red Snail Shell': '351' };
const shellSources = {};
for (const [mon, nm] of [['2', 'Snail Shell'], ['3', 'Blue Snail Shell'], ['5', 'Red Snail Shell']]) {
  const r = await fetchUrl(`https://meowdb.com/msclassic/api/drops?monsterId=${mon}`);
  const drops = JSON.parse(r.text).drops;
  const d = drops.find((x) => x.itemName === nm);
  check(d && String(d.itemId) === SHELL_IDS[nm], `${nm} item id ${SHELL_IDS[nm]} (api/drops monster ${mon})`);
  shellSources[nm] = { url: r.url, retrieved_at: r.retrieved_at };
}
const skills = [
  {
    skill_id: '0001000', name: 'Three Snails', page: P.sk0001000.url, type: 'active', max_level: 3,
    description: V('sk0001000', 'Hurls snail shells to attack monsters from long distance.'),
    delivery: 'projectile', element: 'none', weapon_requirement: 'any', cast_position: 'ground only', targets: 1, range_px: 300,
    damage_formula: 'fixed damage',
    damage_note: V('sk0001000', 'Three Snails deals the fixed damage stored for the selected skill level. Character stats, weapon stats, and target defense do not scale this fixed value.'),
    affected_by: ['Skill level'],
    conditional_factors: ['Required shell item', 'Target hit eligibility'],
    factors_statement: V('sk0001000', 'Affected by Skill level Conditional factors Required shell item Target hit eligibility'),
    hit_check_note: 'The page lists "Target hit eligibility" as a conditional factor but does not say explicitly whether the shared accuracy roll, the level-gap scale or critical hits apply to this fixed damage (gap).',
    levels: snailLv.map((l) => ({ level: l.level, effect: l.effect, ...parseSnail(l.effect), item_cost_id: SHELL_IDS[parseSnail(l.effect)?.item_cost_name] ?? null })),
    animation: { base_action_ms: 800, ms_at_normal_6: 810, weapon_speed_based: true },
    terrain_note: V('sk0001000', 'Wall and platform interactions are not confirmed for this skill.'),
  },
  {
    skill_id: '0001001', name: 'Recovery', page: P.sk0001001.url, type: 'active', max_level: 3,
    description: V('sk0001001', 'Enables the user to recover HP constantly for 30 sec.'),
    target: 'self', cast_position: 'ground, air, or rope',
    output_formula: V('sk0001001', 'Timed HP recovery'),
    output_note: V('sk0001001', 'Recovery restores a fixed total amount of HP across its 30-second duration.'),
    affected_by: ['Skill level'],
    conditional_factors: ['30-second effect duration'],
    factors_statement: V('sk0001001', 'Affected by Skill level Conditional factors 30-second effect duration'),
    levels: recLv.map((l) => ({ level: l.level, effect: l.effect, ...parseRec(l.effect) })),
    animation: { timing: V('sk0001001', 'Timing unavailable') },
  },
  {
    skill_id: '0001002', name: 'Nimble Feet', page: P.sk0001002.url, type: 'active', max_level: 3,
    description: V('sk0001002', 'Enables the character to move around quickly for a short amount of time.'),
    target: 'self', cast_position: 'ground, air, or rope',
    levels: nimLv.map((l) => ({ level: l.level, effect: l.effect, ...parseNim(l.effect) })),
    animation: { timing: V('sk0001002', 'Timing unavailable') },
  },
];
for (const s of skills) for (const l of s.levels) check(Object.keys(l).length > 2, `${s.name} Lv ${l.level} effect parsed: ${l.effect}`);
VV('sk0001000', ['Cast: Ground only', 'PROJECTILE', 'Projectile', 'None', 'Any weapon', 'Fixed damage', 'One target; one hit.']);
VV('sk0001001', ['Cast: Ground, air, or rope', 'Self-only buff', 'The caster only.']);
VV('sk0001002', ['Cast: Ground, air, or rope', 'Self-only buff']);
VV('clsb', ['Three Snails', 'MAX LV 3', 'COOLDOWN 180 SEC', 'COOLDOWN 120 SEC']);
const maxLevelSkillNotes = VV('gbeg', [
  'Speed +10 for 30s (MP -10). 3 min cooldown.',
  '40 fixed damage, ranged. Consumes 1 Red Snail Shell + 5 MP per cast.',
  'Heals 72 HP over 30s (MP -15). 2 min cooldown.',
]);
const apLines = VV('lvl', ['Total AP = 25 + 5 × (Level - 1)', 'Free AP = Total AP - 16', 'Beginner SP = 9']);
const apCode = C(calcChunk, 'l=25+5*(a-1),r=[S("Total AP",l,0),S("Free AP",l-16,0)];return"beginner"===P(e,"class")?[...r,S("Beginner SP",9,0)]');
const builderEquipCode = C(builderChunk, 'h={beginner:[],warrior:["Warrior"],magician:["Mage"],bowman:["Bowman"],thief:["Thief"]};function f(e,t){return!e||h[t].some(t=>e.includes(t))}');
const beginnerHp = Array.from({ length: 10 }, (_, i) => ({ level: i + 1, ...beginnerHpMp(i + 1) }));

const beginner = {
  id: 'beginner',
  name: 'Beginner',
  class_slug: 'beginner',
  description: V('clsb', 'Every adventurer starts as a Beginner on Maple Island. Learn the basics of combat with simple skills before choosing your path at level 10.'),
  starting_level: 1,
  starting_level_note: V('gwhat', 'Classic World starts every character at level 1 in its own economy.'),
  starting_stats: { str: 4, dex: 4, int: 4, luk: 4 },
  starting_stats_note: V('lvl', 'Every character starts with 4 STR, 4 DEX, 4 INT and 4 LUK, and those 16 points count toward total AP.'),
  creation_ap: 9,
  creation_ap_note: VV('gbeg', ['You place your first 9 AP on the character creation screen, so pick your class before you make your character.', 'Every character starts with 4 in each stat. You place 9 more AP at character creation, then get 5 AP per level for STR, DEX, INT, and LUK.']),
  ap: {
    total_ap_formula: apLines[0],
    free_ap_formula: apLines[1],
    ap_per_level: 5,
    ap_per_level_note: V('q1018', 'You get 5 AP with each level, and you can use them on the stats you want in Character Info to make your character stronger.'),
    total_ap_at_level_1: 25,
    free_ap_at_level_1: 9,
    allocatable_stats: ['str', 'dex', 'int', 'luk'],
    unused_ap_retained: 'Not explicitly stated. AP is placed by hand and stays where it is put: "' + V('gwhat', 'You place every AP and SP by hand. A misplaced stat stays there until you use a cash-shop AP Reset.') + '"',
    ap_not_reset_on_job_advancement: V('gbeg', '1st job has no stat requirements (a 4-INT Beginner can advance to Warrior), but your AP does not reset on advancement.'),
    calculator_code: apCode,
  },
  sp: {
    beginner_total_sp: 9,
    formula: apLines[2],
    sp_per_level: 1,
    sp_levels: [2, 10],
    note: V('gbeg', 'You earn 9 SP by the time you hit level 10 (1 per level-up, 9 level-ups from 1 to 10). That\'s exactly enough to max all three Beginner skills (3 SP each, 9 total).'),
    after_level_10_as_beginner: 'Not documented. MeowDB\'s calculators return Beginner SP = 9 at every level (model, not confirmed).',
    calculator_caveat: 'The /formulas/leveling "AP and SP" calculator prints "Beginner SP = 9" for every level, including level 1. It is the level-10 total, not a starting grant: per the Beginner\'s guide a Beginner has 0 SP at level 1 and gains 1 SP at each level-up from 2 to 10.',
  },
  hp_mp: {
    base_hp: 50,
    base_mp: 5,
    hp_per_level: 16,
    mp_per_level: 12,
    random_range: null,
    random_range_note: 'Flat gains; MeowDB: "Sampled level-ups showed zero variance." (hp_mp_gain.json)',
    hp_formula: V('lvl', 'BeginnerHP = 50 + 16 × (Level - 1)'),
    mp_formula: V('lvl', 'BeginnerMP = 5 + 12 × (Level - 1)'),
    by_level_1_to_10: beginnerHp,
  },
  max_level: {
    game_level_cap: 100,
    beginner_specific_cap: null,
    note: 'MeowDB gives the game cap (Lv 100, see exp_table.json) but no Beginner-specific cap. A Beginner can stay a Beginner past level 10 (the HP/MP guide documents a level 11 Beginner advancing late); MeowDB\'s HP/MP calculator accepts Beginner levels 1-100.',
    evidence: V('ghpmp', 'A level 11 Beginner advanced to Warrior'),
  },
  stat_caps: null,
  stat_caps_note: 'Not documented on MeowDB (only Speed cap 140 and Jump cap 120, see movement.json).',
  job_advancement: {
    first_job_level: 10,
    statements: [
      V('q1017', 'To advance for not only Warriors, Bowmen, and Thieves, but also Magicians, you need to be at least level 10.'),
      V('gbeg', '1st job has no stat requirements (a 4-INT Beginner can advance to Warrior), but your AP does not reset on advancement.'),
    ],
    instructors: VV('gbeg', ['Perion: Warriors (Dances With Balrog)', 'Ellinia: Magicians (Grendel the Really Old)', 'Henesys: Bowmen (Athena Pierce)', 'Kerning City: Thieves (Dark Lord)']),
    leaving_maple_island: V('gbeg', 'Shanks at the dock sails you to Lith Harbor for 300 mesos once you reach level 7.'),
    one_way: V('gbeg', 'The boat is one-way.'),
  },
  equipment_restrictions: {
    rule: 'A Beginner can equip only items with no job requirement ("Any" class) that meet the level and stat requirements.',
    statements: [
      V('ieb', 'Every NPC-sold item with no class lock.'),
    ],
    character_builder_code: builderEquipCode,
    note: 'The rule is MeowDB tool logic (character builder: Beginner matches no job requirement) plus the Beginner shop category "no class lock"; it is not stated as a sentence on a mechanics page.',
  },
  starter_weapons: {
    statement: V('ieb', 'Every any-class weapon, from the 50-meso starter trio (Sword, Hand Axe, Wooden Club) up to Lv 27.'),
    creation_choice_note: V('gbeg', 'Choose the Wooden Club at character creation. It has 19 W.ATK; the Sword and Hand Axe have 17.'),
    items: beginnerWeapons.map((w) => ({ item_id: w.item_id, name: w.name, subtype: w.subtype, watk: w.watk, level_req: w.level_req, attack_speed_tier: w.attack_speed_tier })),
    level_req_note: 'level_req 0 = no level requirement: the item page has no "REQ LEV" row, the Beginner shop list shows "-" in its Lv column, and MeowDB\'s item API gives "levelReq": 0 (checked for 541/576/585; Razor 558 has 5 on all three).',
    guide_advice: VV('gbeg', ['Club attacks one tier slower than Sword or Hand Axe, but across levels 1 to 4, the Club reaches the useful damage breakpoints more often.', 'At level 5, switch to Razor. Its 23 W.ATK and faster speed give every class path higher minimum and average damage than Wooden Club.']),
  },
  starter_clothes: null,
  starter_clothes_note: 'Not documented on MeowDB.',
  skills,
  skills_max_level_summary: maxLevelSkillNotes,
  skill_order_advice: V('gbeg', 'Order matters for levels 1 to 9; by 10 they\'re all maxed anyway. Take Nimble Feet first, then Three Snails for ranged, Recovery last.'),
  basic_attack: {
    mp_cost: 0,
    mp_cost_note: V('gbeg', 'Switch to basic attacks when MP is low; they cost no MP.'),
    with_weapon: 'damage.json physical formula with the weapon\'s family, action multipliers and hit boxes (attack_styles.json beginner_weapons). No mastery (MasteryLevel 0 -> M = 0.08). Critical base c = 0.05, d = 0.20.',
    stat_advice: V('gbeg', 'STR gives a Beginner stronger basic attacks than INT does.'),
    bare_hands: {
      documented: 'hitboxes and action only',
      weapon_attack: null,
      weapon_mult: null,
      action: 'stab (100%)',
      presentations: ['Punch 1 (stabO1)', 'Punch 2 (stabO2)', 'Crouched attack (proneStab)'],
      hit_boxes_px: { stabO1: HZ.sets.barehands.ordinary.stabO1, stabO2: HZ.sets.barehands.ordinary.stabO2, proneStab: HZ.sets.barehands.ordinary.proneStab },
      attack_speed: null,
      note: 'MeowDB has NOTHING on unarmed damage: no Weapon Attack value, no multiplier ("Barehanded" row shows "-" for the average multiplier), no speed, and the Damage Simulator has no Beginner/unarmed option. Searched: /formulas/damage, /guides/explaining-the-damage-formula, /guides/weapon-reach, /dmg-simulator (page and JS), /character-builder JS, /classes, /classes/beginner.',
    },
  },
  death_exp_penalty: deathExpPenalty,
  beginner_perks: {
    taxi_discount: V('gbeg', 'Taxis are 90% off while you are still a Beginner.'),
    taxi_discount_pct: 90,
  },
  class_page_strengths: VV('clsb', ['Three Snails gives an early ranged attack (each throw uses a snail shell)', 'Nimble Feet gives a bit of mobility', 'No commitment: every job is still open']),
  class_page_weaknesses: VV('clsb', ['Very low damage and survivability', 'No job identity until Lv 10', 'Skills are minor next to job skills']),
  source: mainSource('clsb'),
  field_sources: {
    starting_level_note: src('gwhat'), starting_stats_note: src('lvl'), creation_ap_note: src('gbeg'), ap: src('lvl'), 'ap.ap_per_level_note': src('q1018'),
    'ap.unused_ap_retained': src('gwhat'), 'ap.ap_not_reset_on_job_advancement': src('gbeg'), 'ap.calculator_code': chunkSrc(calcChunk, 'acc'),
    sp: src('lvl'), 'sp.note': src('gbeg'), hp_mp: src('lvl'), max_level: src('ghpmp'),
    'job_advancement.statements.0': src('q1017'), job_advancement: src('gbeg'),
    'equipment_restrictions.statements.0': src('ieb'), 'equipment_restrictions.character_builder_code': chunkSrc(builderChunk, 'cb'),
    starter_weapons: src('ieb'), 'starter_weapons.items': { urls: ['i541', 'i576', 'i585', 'i558'].map((k) => P[k].url), retrieved_at: P.i541.retrieved_at },
    'starter_weapons.guide_advice': src('gbeg'), 'skills.0': src('sk0001000'), 'skills.1': src('sk0001001'), 'skills.2': src('sk0001002'),
    'skills.0.levels.item_cost_id': { urls: Object.values(shellSources).map((s) => s.url), retrieved_at: shellSources['Snail Shell'].retrieved_at },
    skills_max_level_summary: src('gbeg'), skill_order_advice: src('gbeg'), 'basic_attack.mp_cost_note': src('gbeg'), 'basic_attack.stat_advice': src('gbeg'),
    'basic_attack.bare_hands.hit_boxes_px': chunkSrc(hitChunk, 'cb'), death_exp_penalty: src('lvl'), 'death_exp_penalty.calculator_code': chunkSrc(calcChunk, 'acc'),
    beginner_perks: src('gbeg'),
  },
  gaps: [
    'Bare-hand (no weapon) Weapon Attack, multiplier and attack speed: not documented.',
    'Beginner-specific max level: not documented (game cap Lv 100).',
    'SP gained as a Beginner after level 10: not documented (calculator returns 9 total).',
    'Stat caps: not documented.',
    'Rule for putting AP into Max HP / Max MP: not documented.',
    'Starting clothes / starting inventory: not documented.',
    'Death EXP penalty exceptions in town or for Beginners: none documented.',
    'Whether Three Snails is subject to the hit roll, level-gap scale or critical hits: not stated explicitly (its page lists "Target hit eligibility" as a conditional factor).',
    'Animation time of Recovery and Nimble Feet casts: "Timing unavailable".',
    'How Recovery distributes its HP total over 30 s (tick interval): not documented.',
  ],
  discrepancies: [
    {
      topic: 'Which stats AP can raise',
      values: [
        { url: P.gbeg.url, text: V('gbeg', 'Every character starts with 4 in each stat. You place 9 more AP at character creation, then get 5 AP per level for STR, DEX, INT, and LUK.') },
        { url: P.lvl.url, text: 'Total AP = 25 + 5 × (Level - 1); Free AP = Total AP - 16 (STR/DEX/INT/LUK only; the HP/MP formulas have no AP term).' },
        { url: P.ggloss.url, text: 'AP: ' + V('ggloss', 'Earned at every level up. You get 5 per level. Used to raise STR / DEX / INT / LUK / HP / MP.') },
      ],
      chosen: 'allocatable_stats = STR, DEX, INT, LUK',
      reason: 'The Beginner\'s guide (updated 2026-10-02) and the leveling formulas agree on the four stats, and the HP/MP guide has no AP term ("HP washing is dead in MSCW"); the glossary is a one-line definition. Whether AP can be put into Max HP / Max MP remains a documented gap (hp_mp_gain.json ap_into_hp_mp = null).',
    },
  ],
};
// Starter-weapon level requirement cross-check against MeowDB's item API (cache-first).
for (const w of beginnerWeapons) {
  const r = await fetchUrl(`${ORIGIN}/msclassic/api/items/${w.item_id}?locale=en&preview=1`);
  const api = JSON.parse(r.text);
  check(api.levelReq === w.level_req && api.stats.watk === w.watk && api.stats.attackSpeed === w.attack_speed_tier, `${w.name}: item API levelReq/watk/attackSpeed ${api.levelReq}/${api.stats.watk}/${api.stats.attackSpeed} = page ${w.level_req}/${w.watk}/${w.attack_speed_tier}`);
  if (w.item_id === '541') beginner.field_sources['starter_weapons.level_req_note'] = { urls: beginnerWeapons.map((x) => `${ORIGIN}/msclassic/api/items/${x.item_id}?locale=en&preview=1`), retrieved_at: r.retrieved_at };
}
// Rain's Maple Quiz 2 (quest 1014) states the level/stat part of the rule; load and assert it.
{
  const r = await fetchPage('/quest-tracker/1014');
  const t = norm(pageText(r.html).split('\n').map((s) => s.trim()).filter(Boolean).join(' '));
  const q = 'If you can\'t wear something, check that your character meets the level and statistic requirements.';
  check(t.includes(q), 'quest 1014 equip-requirement sentence');
  beginner.equipment_restrictions.statements.push(q);
  beginner.field_sources['equipment_restrictions.statements.1'] = { url: r.url, retrieved_at: r.retrieved_at };
}

// ===============================================================================================================
// Write
// ===============================================================================================================
if (missing.length) {
  console.error(`extract_formulas: ${missing.length} verbatim/consistency check(s) failed:\n` + missing.map((m) => '  - ' + m).join('\n'));
  process.exit(1);
}
const outputs = [expTable, beginner, damage, accuracy, derivedStats, attackSpeed, attackStyles, spawnRate, hpMpGain, movement, recovery, lootRules, death];
for (const o of outputs) writeJson(path.join(OUT, `${o.id}.json`), o);
console.log(`extract_formulas: wrote ${outputs.length} files to ${path.relative(ROOT, OUT)}: ${outputs.map((o) => o.id).join(', ')}`);
