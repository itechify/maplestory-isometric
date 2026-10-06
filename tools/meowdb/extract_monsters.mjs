// Extract canonical MONSTER, DROP-TABLE and BREAKABLE data for the 25 Maple Island maps from MeowDB MS Classic.
//
//   node tools/meowdb/extract_monsters.mjs            (cache-first; re-running reproduces the JSON byte-for-byte)
//
// Outputs (one entity per file):
//   game/data/canonical/monsters/<monster_id>.json     e.g. monsters/2.json  (Snail)
//   game/data/canonical/drops/<owner_id>.json          monsters/<id> -> drops/<id>.json; breakable 0000001 -> drops/0000001.json
//                                                      schema 3 records (contract C1) built by tools/sources/drops_merge.mjs
//                                                      from the dated captures and the cache (this extractor is their
//                                                      single writer)
//   game/data/canonical/breakables/<breakable_id>.json e.g. breakables/0000001.json (Wooden Box)
//
// Dated hand-read captures (tools/*/captures, read through tools/sources/captures.mjs; decisions D3-1, D3-11, D3-12):
//   tools/meowdb/captures/monster_<id>.*    live monster pages: STAGGER (stagger_ms), meso report, community lists
//   tools/henesys/captures/item_rarity.json Henesys.gg rarity labels of the drop-list items
//   drop records: MeowDB community-list membership, Henesys.gg rarity, MeowDB meso reports (see drops_merge.mjs)
//
// Sources (MeowDB MS Classic cache; see docs/canonical/monsters.md):
//   /maps/<id>                              which monsters / breakables are on the 25 maps (the monster list is DERIVED here)
//   /monsters/<id>                          detail page (stats rendered into the RSC tree; spawn table as JSON props)
//   /msclassic/api/drops?monsterId=<id>     "Drops (MS Classic) - Community sourced" (client-side on the page)
//   /msclassic/api/mesos-reports?monsterId= "Mesos per kill" (client-side on the page)
//   /breakables, /breakables/<id>           breakable list + detail page
//   /msclassic/api/breakable-drops?breakableId=<id>   breakable community drops (client-side)
//   /_next/static/chunks/782-*.js           MeowDB's own raw monster stat table used by its simulators (only for fields
//                                           the detail page does not expose: kb, tags, nonAgg, hpRec/mpRec, revives, raw speed)
//   /guides/maplestory-classic-glossary     KB definition; "mob rate" definition (contradicts the map pages: see discrepancies)
//   /formulas/spawns, /formulas/damage-taken  cited in notes/gaps (respawn model; "Knockback Airtime" is the player's)
//   monster page client chunk (app/.../monsters/[id]/page-*.js, URL from the page's <script src>)  "Mob Rate" tooltip text
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as L from './lib.mjs';
import { loadCaptures } from '../sources/captures.mjs';
import { buildDropRecords } from '../sources/drops_merge.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const OUT = path.join(REPO, 'game', 'data', 'canonical');
const ORIGIN = 'https://meowdb.com';

const MAPLE_ISLAND_MAPS = [
  '000000001', '000000010', '000000020', '000000021', '000000030', '000000040', '000000041', '000000042', '000000050',
  '000000060', '000000061', '000001000', '000001001', '000001002', '000001003', '000001004', '000001005', '000001006',
  '000001010', '000001011', '000001012', '000001013', '000001014', '000001020', '000001021',
];
// MeowDB's simulator data chunk (loaded by /avoidability-sim, the "Calculate" link on every monster page). The hash is
// pinned so re-runs read the same cached file; if MeowDB redeploys, find the new chunk via the avoidability-sim page.
const RAW_TABLE_CHUNK = ORIGIN + '/_next/static/chunks/782-bb5a5ee666dc6188.js';
const GLOSSARY_PAGE = '/guides/maplestory-classic-glossary'; // defines KB (knockback resistance); cached by another extractor
const SPAWN_FORMULA_PAGE = '/formulas/spawns';
const DAMAGE_TAKEN_PAGE = '/formulas/damage-taken'; // cached by the formulas extractor; read only to word a knockback gap

const discrepancies = []; // collected across the run and printed at the end (also written into the entity files)
const warn = (msg) => console.warn('WARN', msg);

// ---------------------------------------------------------------------------------------------------------------------
// RSC tree helpers. rsc() yields rows "<hex>:<json>"; elements are ["$", type, key, props]; "$L<hex>" / "$<hex>" refs
// point at other rows. We parse every JSON row into a map and walk the tree resolving refs.
// ---------------------------------------------------------------------------------------------------------------------
function parseRows(r) {
  const rows = new Map();
  const re = /(?:^|\n)([0-9a-f]+):/g;
  let m;
  while ((m = re.exec(r))) {
    const start = m.index + m[0].length;
    const c = r[start];
    if (!c || /[A-Z]/.test(c)) continue; // I (module), T (text), H/D/E/W hints: not element JSON
    try {
      const { value, end } = L.jsonAt(r, start);
      if (!rows.has(m[1])) rows.set(m[1], value);
      re.lastIndex = end;
    } catch { /* not a JSON row */ }
  }
  return rows;
}
const refId = (s) => (typeof s === 'string' ? (/^\$L?([0-9a-f]+)$/.exec(s) || [])[1] : undefined);
const isEl = (n) => Array.isArray(n) && n.length === 4 && n[0] === '$' && typeof n[1] === 'string';

class Tree {
  constructor(html) {
    this.r = L.rsc(html);
    this.rows = parseRows(this.r);
    // roots = rows no parsed row points at (the page's row "0" is not in the push payload, so its children are roots)
    const referenced = new Set();
    const collect = (v) => {
      const id = refId(v);
      if (id !== undefined) referenced.add(id);
      else if (Array.isArray(v)) v.forEach(collect);
      else if (v && typeof v === 'object') Object.values(v).forEach(collect);
    };
    for (const v of this.rows.values()) collect(v);
    this.roots = [...this.rows.keys()].filter((k) => !referenced.has(k)).map((k) => this.rows.get(k));
  }
  resolve(n, seen) {
    const id = refId(n);
    if (id !== undefined && this.rows.has(id) && !seen.has(id)) return { node: this.rows.get(id), id };
    return null;
  }
  /** Every element in the tree (with its ancestor chain), refs resolved. */
  elements() {
    if (this._els) return this._els;
    const out = [];
    const seen = new Set();
    const done = new Set(); // element identity: a row reached twice is listed once
    const walk = (n, anc) => {
      const ref = this.resolve(n, seen);
      if (ref) { seen.add(ref.id); walk(ref.node, anc); seen.delete(ref.id); return; }
      if (isEl(n)) {
        if (done.has(n)) return;
        done.add(n);
        out.push({ el: n, anc });
        const props = n[3] || {};
        const inner = [...anc, n];
        walk(props.children, inner);
        for (const [k, v] of Object.entries(props)) if (k !== 'children' && v && typeof v === 'object') walk(v, inner);
        for (const [k, v] of Object.entries(props)) if (k !== 'children' && typeof v === 'string') walk(v, inner);
        return;
      }
      if (Array.isArray(n)) { for (const c of n) walk(c, anc); return; }
      if (n && typeof n === 'object') for (const v of Object.values(n)) walk(v, anc);
    };
    for (const root of this.roots) walk(root, []);
    return (this._els = out);
  }
  /** Text tokens under a node (refs resolved; "$undefined"/booleans dropped; each token trimmed). */
  texts(n, seen = new Set()) {
    const out = [];
    const walk = (x) => {
      const ref = this.resolve(x, seen);
      if (ref) { seen.add(ref.id); walk(ref.node); seen.delete(ref.id); return; }
      if (typeof x === 'string') { if (!x.startsWith('$') && x.trim()) out.push(x.trim()); return; }
      if (typeof x === 'number') { out.push(String(x)); return; }
      if (isEl(x)) { walk((x[3] || {}).children); return; }
      if (Array.isArray(x)) for (const c of x) walk(c);
    };
    walk(n);
    return out;
  }
  text(n) { return this.texts(n).join(' '); }
  /** Prose text under a node: string tokens concatenated untrimmed (RSC keeps the inter-token spaces), whitespace collapsed. */
  rawText(n) {
    let out = '';
    const seen = new Set();
    const walk = (x) => {
      const ref = this.resolve(x, seen);
      if (ref) { seen.add(ref.id); walk(ref.node); seen.delete(ref.id); return; }
      if (typeof x === 'string') { if (!x.startsWith('$')) out += x; return; }
      if (typeof x === 'number') { out += String(x); return; }
      if (isEl(x)) { walk((x[3] || {}).children); return; }
      if (Array.isArray(x)) for (const c of x) walk(c);
    };
    walk(n);
    return out.replace(/\s+/g, ' ').trim();
  }
  /** Direct children of an element as a flat list (refs resolved, arrays flattened). */
  children(el) {
    const out = [];
    const walk = (x, seen) => {
      const ref = this.resolve(x, seen);
      if (ref) { const s2 = new Set(seen); s2.add(ref.id); walk(ref.node, s2); return; }
      if (Array.isArray(x) && !isEl(x)) { for (const c of x) walk(c, seen); return; }
      if (x !== null && x !== undefined && x !== false && x !== '' && x !== '$undefined') out.push(x);
    };
    walk((el[3] || {}).children, new Set());
    return out;
  }
  find(pred) { return this.elements().filter(({ el, anc }) => pred(el, anc)); }
  /** Label/value cards: the element whose first child has text === label; returns the remaining children's texts. */
  card(label, { cls } = {}) {
    const hits = this.find((el) => {
      if (cls && !String(el[3]?.className || '').includes(cls)) return false;
      const kids = this.children(el);
      return kids.length >= 2 && isEl(kids[0]) && this.text(kids[0]) === label;
    });
    if (!hits.length) return null;
    const kids = this.children(hits[0].el);
    return { el: hits[0].el, values: kids.slice(1).map((k) => this.texts(k)) };
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// small parsers
// ---------------------------------------------------------------------------------------------------------------------
const num = (s) => {
  if (s === null || s === undefined) return null;
  const t = String(s).replace(/,/g, '').trim();
  return /^-?\d+(\.\d+)?$/.test(t) ? Number(t) : null;
};
const dash = (s) => s === '—' || s === '-' || s === '';
const px2 = (s) => {
  const m = /^(\d+)\s*x\s*(\d+)\s*px$/.exec(s || '');
  return m ? [Number(m[1]), Number(m[2])] : null;
};
/** "900ms" -> 900, "1.26s" -> 1260, "held pose" -> null */
const durMs = (s) => {
  let m = /^(\d+(?:\.\d+)?)\s*ms$/.exec(s || '');
  if (m) return Math.round(Number(m[1]));
  m = /^(\d+(?:\.\d+)?)\s*s$/.exec(s || '');
  if (m) return Math.round(Number(m[1]) * 1000);
  return null;
};
async function page(p) {
  const r = await L.fetchPage(p);
  return { html: r.html, url: r.url, retrieved_at: r.retrieved_at };
}
async function api(p) {
  const r = await L.fetchUrl(ORIGIN + p, { accept: 'application/json' });
  return { json: JSON.parse(r.text), url: r.url, retrieved_at: r.retrieved_at };
}

// ---------------------------------------------------------------------------------------------------------------------
// 1. Maple Island map pages -> monster ids, breakable ids, per-map counts (for cross-checks)
// ---------------------------------------------------------------------------------------------------------------------
async function readMaps() {
  const maps = {};
  for (const id of MAPLE_ISLAND_MAPS) {
    const pg = await page('/maps/' + id);
    const r = L.rsc(pg.html);
    const mapObj = L.valuesForKey(r, 'map').find((v) => v && typeof v === 'object' && v.reactors !== undefined);
    if (!mapObj) throw new Error('map object not found on /maps/' + id);
    const labels = L.firstValue(r, 'breakableLabels', (v) => v && typeof v === 'object') || {};
    // "About mob rate." paragraph (server-rendered prose under the map's monster table); cited in the mob_rate discrepancy
    let aboutMobRate = null;
    if ((mapObj.monsters || []).length) {
      const t = new Tree(pg.html);
      const para = t.find((el) => el[1] === 'p' && (() => { const k = t.children(el); return isEl(k[0]) && t.text(k[0]) === 'About mob rate.'; })())[0];
      aboutMobRate = para ? t.rawText(para.el) : null;
    }
    maps[id] = {
      id,
      name: mapObj.name,
      street_name: mapObj.streetName,
      url: pg.url,
      retrieved_at: pg.retrieved_at,
      mob_rate: mapObj.mobRate,
      total_mob_count: mapObj.totalMobCount,
      monsters: (mapObj.monsters || []).map((m) => ({ id: String(m.id), name: m.name, count: m.count, wave: m.waveSpawnCount, respawnMin: m.respawnMin, respawnMax: m.respawnMax })),
      spawns: mapObj.spawns || [],
      reactors: (mapObj.reactors || []).map((x) => ({ ...x, label: labels[x.id] ?? null })),
      about_mob_rate: aboutMobRate,
    };
  }
  return maps;
}

// ---------------------------------------------------------------------------------------------------------------------
// 1b. What MeowDB says "mob rate" means (its pages disagree; see buildMonster's mob_rate discrepancy)
// ---------------------------------------------------------------------------------------------------------------------
/** Glossary definition: the <tr> whose first <td> reads `term`; returns the second cell's prose. */
function glossaryDef(html, term) {
  const t = new Tree(html);
  for (const { el } of t.find((e) => e[1] === 'tr')) {
    const tds = t.children(el).filter((c) => isEl(c) && c[1] === 'td');
    if (tds.length >= 2 && t.text(tds[0]) === term) return t.rawText(tds[1]);
  }
  return null;
}
/** The monster page's "Mob Rate" column tooltip. It is an i18n string in the page's client chunk (URL taken from the
 *  cached page's <script src>, so no chunk hash is pinned here). */
async function monsterPageMobRateTip(html) {
  const m = /<script src="(\/_next\/static\/chunks\/app\/msclassic\/%5Blocale%5D\/monsters\/%5Bid%5D\/page-[0-9a-f]+\.js)"/.exec(html);
  if (!m) return null;
  const r = await L.fetchUrl(ORIGIN + m[1]);
  const key = '"monster.locations.mobRateTip":';
  const at = r.text.indexOf(key);
  if (at < 0) return null;
  const { value } = L.jsonAt(r.text, at + key.length);
  return value && typeof value.en === 'string' ? { text: value.en, url: r.url, retrieved_at: r.retrieved_at } : null;
}

// ---------------------------------------------------------------------------------------------------------------------
// 2. MeowDB raw stat table (JS chunk) -> { [id]: {...} } and speed map
// ---------------------------------------------------------------------------------------------------------------------
async function readRawTable(ids) {
  const r = await L.fetchUrl(RAW_TABLE_CHUNK);
  const src = r.text;
  const rows = {};
  for (const id of ids) {
    const at = src.indexOf(`{id:${id},name:`);
    if (at < 0) throw new Error('raw table: monster ' + id + ' not found');
    let depth = 0, end = -1, inStr = false;
    for (let j = at; j < src.length; j++) {
      const c = src[j];
      if (inStr) { if (c === '\\') j++; else if (c === '"') inStr = false; continue; }
      if (c === '"') inStr = true;
      else if (c === '{' || c === '[') depth++;
      else if (c === '}' || c === ']') { depth--; if (depth === 0) { end = j + 1; break; } }
    }
    // JS object literal -> JSON (keys unquoted, !0/!1 booleans). Only applied to this one small object.
    const json = src.slice(at, end)
      .replace(/([{,])([A-Za-z_][A-Za-z0-9_]*):/g, '$1"$2":')
      .replace(/:!0\b/g, ':true').replace(/:!1\b/g, ':false');
    rows[id] = JSON.parse(json);
  }
  const g = /\],g=\{([^}]*)\}/.exec(src);
  const speed = {};
  if (g) for (const m of g[1].matchAll(/(\d+(?:e\d+)?):(-?\d+)/g)) speed[String(Number(m[1]))] = Number(m[2]);
  return { rows, speed, url: r.url, retrieved_at: r.retrieved_at };
}

// ---------------------------------------------------------------------------------------------------------------------
// 3. Monster detail page
// ---------------------------------------------------------------------------------------------------------------------
function parseMonsterPage(html, id) {
  const t = new Tree(html);
  const r = t.r;
  const out = {};

  out.name = t.text(t.find((el) => el[1] === 'h1')[0].el);
  const noEl = t.find((el) => el[1] === 'span' && /^No\. \d+$/.test(t.text(el)))[0];
  out.bestiary_no = noEl ? t.text(noEl.el).replace('No. ', '') : null;
  const catEl = t.find((el) => el[1] === 'span' && /· Bestiary$/.test(t.text(el)))[0];
  out.category_label = catEl ? t.texts(catEl.el)[0] : null;

  // header: Level + badges (e.g. "Peace")
  const lvl = t.find((el) => el[1] === 'span' && t.texts(el).length === 2 && t.texts(el)[0] === 'Level')[0];
  out.level = lvl ? num(t.texts(lvl.el)[1]) : null;
  const headerRow = lvl ? lvl.anc[lvl.anc.length - 1] : null;
  out.header_badges = headerRow ? t.children(headerRow).filter((c) => isEl(c) && c !== lvl.el).map((c) => t.text(c)).filter(Boolean) : [];

  // element affinity line (diamond icon + text)
  const diamond = t.find((el) => String(el[3]?.className || '').includes('rotate-45'))[0];
  out.element_text = diamond ? t.text(diamond.anc[diamond.anc.length - 1]) : null;

  const desc = t.find((el) => el[1] === 'p' && el[3]?.className === 'text-sm leading-relaxed text-maple-muted')[0];
  out.description = desc ? t.text(desc.el) : null;

  // HP / EXP cards
  const hp = t.card('HP'); out.hp = hp ? num(hp.values[0][0]) : null;
  const exp = t.card('EXP'); out.exp = exp ? num(exp.values[0][0]) : null;

  // keyed stat cards
  const stat = (key) => {
    const hit = t.find((el) => el[1] === 'div' && el[2] === key)[0];
    if (!hit) return null;
    const kids = t.children(hit.el).filter(isEl);
    return { value: kids[1] ? t.text(kids[1]) : null, extra: kids.slice(2).map((k) => t.texts(k)), title: hit.el[3]?.title };
  };
  const touch = stat('Touch DMG');
  const tm = /^(\d+)-(\d+)$/.exec(touch?.value || '');
  out.touch_damage_estimate = tm ? [Number(tm[1]), Number(tm[2])] : null;
  const base = (touch?.extra.flat() || []).map((s) => /^Base (\d+)$/.exec(s)).find(Boolean);
  out.touch_base = base ? Number(base[1]) : null;
  out.touch_title = touch?.title || null;
  for (const [k, key] of [['mdmg', 'M.DMG'], ['pdef', 'P.DEF'], ['mdef', 'M.DEF'], ['acc', 'ACC'], ['avoid', 'AVOID']]) {
    const s = stat(key);
    out[k + '_display'] = s ? s.value : null;
    out[k] = s && !dash(s.value) ? num(s.value) : null;
  }

  // speed / movement (dt/dd)
  const sp = t.card('Speed');
  out.speed_label = sp ? sp.values[0][0] : null;
  const spRaw = sp ? sp.values[0].map((s) => /^\(speed (-?\d+)\)$/.exec(s)).find(Boolean) : null;
  out.speed_display_raw = spRaw ? Number(spRaw[1]) : null;
  const mv = t.card('Movement');
  out.movement_label = mv ? mv.values[0][0] : null;
  out.movement_description = mv ? mv.values[0].slice(1).join(' ') : null;

  // Other Attributes list
  const attrs = t.find((el) => el[3] && el[3]['data-monster-attributes'])[0];
  out.other_attributes = attrs
    ? t.find((el, anc) => el[1] === 'li' && anc.includes(attrs.el)).map(({ el }) => ({ label: t.text(el), title: el[3]?.title && el[3].title !== '$undefined' ? el[3].title : null }))
    : [];

  // Combat Details
  const sprite = t.card('Sprite size'); out.sprite_size_px = sprite ? px2(sprite.values[0].join(' ')) : null;
  const zone = t.card('Touch zone'); out.touch_zone_px = zone ? px2(zone.values[0].join(' ')) : null;
  const zoneTitle = t.find((el) => typeof el[3]?.title === 'string' && el[3].title.startsWith('The dashed rectangle is the touch damage zone'))[0];
  out.touch_zone_title = zoneTitle ? zoneTitle.el[3].title : null;
  const zoneText = t.find((el) => el[1] === 'p' && /^The touch zone deals contact damage/.test(t.rawText(el)))[0];
  out.touch_zone_text = zoneText ? t.rawText(zoneText.el) : null; // Combat Details prose under the sprite/zone sizes

  // animation clips + timings
  out.clips = L.firstValue(r, 'clips', Array.isArray) || [];
  out.animations = {};
  for (const clip of out.clips) {
    const hit = t.find((el) => el[1] === 'div' && el[2] === clip && String(el[3]?.className || '').includes('bg-maple-bg'))[0];
    if (!hit) { out.animations[clip] = null; continue; }
    const kids = t.children(hit.el).filter(isEl);
    const label = kids[1] ? t.text(kids[1]) : null;
    const value = kids[2] ? t.text(kids[2]) : null;
    out.animations[clip] = { label, display: value, ms: durMs(value), held_pose: value === 'held pose' };
  }
  const dieLi = t.find((el) => el[1] === 'li' && /body fades over/.test(t.text(el)))[0];
  out.die_fade_text = dieLi ? t.text(dieLi.el).replace(/ : /g, ': ').replace(/ ;/g, ';') : null;
  const fade = dieLi ? t.texts(dieLi.el).map(durMs).find((v) => v !== null) : null;
  out.die_fade_ms = fade ?? null;

  // Analysis text (MeowDB commentary)
  const an = t.find((el) => el[3]?.id === 'monster-analysis')[0];
  out.analysis = an ? t.find((el, anc) => el[1] === 'p' && anc.includes(an.el)).map(({ el }) => t.text(el)) : [];

  // MSEA reference drops
  const mseaH = t.find((el) => el[1] === 'h2' && t.text(el) === 'MSEA reference drops')[0];
  out.msea = null;
  if (mseaH) {
    const section = [...mseaH.anc].reverse().find((a) => String(a[3]?.className || '').includes('rounded-xl'));
    const countText = t.find((el, anc) => anc.includes(section) && el[1] === 'span' && /items?$/.test(t.text(el)))[0];
    const items = [];
    for (const g of t.find((el, anc) => anc.includes(section) && el[1] === 'div' && typeof el[2] === 'string' && el[2] && !el[3]?.className)) {
      const group = g.el[2];
      for (const { el } of t.find((e2, anc) => anc.includes(g.el) && typeof e2[3]?.href === 'string' && e2[3].href.startsWith('/msclassic/item-db/'))) {
        const tx = t.texts(el);
        const img = t.find((e3, anc) => anc.includes(el) && e3[1] === 'img')[0];
        items.push({
          item_id: el[3].href.split('/').pop(),
          item_name: tx[0],
          group,
          detail_text: tx.slice(1).join(' ') || null,
          icon_key: img ? String(img.el[3].src).split('/').pop() : null,
        });
      }
    }
    out.msea = { header_text: countText ? t.text(countText.el) : null, items };
  }

  // Associated quests
  const qs = t.find((el) => el[3] && el[3]['data-monster-associated-quests'])[0];
  out.quests = [];
  if (qs) {
    for (const { el } of t.find((e2, anc) => anc.includes(qs.el) && typeof e2[3]?.href === 'string' && e2[3].href.startsWith('/msclassic/quest-tracker/'))) {
      const spans = t.find((e3, anc) => anc.includes(el) && e3[1] === 'span' && String(e3[3]?.className || '').includes('block')).map((x) => x.el);
      const name = spans[0] ? t.text(spans[0]) : null;
      const objective = spans[1] ? t.texts(spans[1]).join('') : null; // ["Defeat Snail"," x",10] -> "Defeat Snailx10"
      const om = /^(.*?)x(\d+)$/.exec(objective || '');
      const metaSpan = t.find((e3, anc) => anc.includes(el) && e3[1] === 'span' && String(e3[3]?.className || '').startsWith('mt-1 flex'))[0];
      const metaTokens = metaSpan ? t.texts(metaSpan.el).filter((s) => s !== '·') : [];
      const lvlTok = metaTokens.find((s) => /^Lv \d+\+$/.test(s));
      out.quests.push({
        quest_id: el[3].href.split('/').pop(),
        name,
        objective_text: om ? `${om[1].trim()} x${om[2]}` : objective,
        objective_kill_count: om ? Number(om[2]) : null,
        region: metaTokens.filter((s) => s !== lvlTok).join(' ') || null,
        min_level: lvlTok ? Number(/\d+/.exec(lvlTok)[0]) : null,
      });
    }
  }

  // Map locations (JSON props) + header count
  out.locations = L.valuesForKey(r, 'locations').find((v) => Array.isArray(v) && v.every((x) => x && x.mapId)) || [];
  const locH = t.find((el) => el[1] === 'h2' && t.texts(el)[0] === 'Map Locations')[0];
  out.locations_header_count = locH ? num(t.texts(locH.el).find((s) => /^\d+$/.test(s))) : null;

  // Change history table
  const chH = t.find((el) => el[1] === 'h2' && t.text(el) === 'Change history')[0];
  out.change_history = [];
  if (chH) {
    const det = [...chH.anc].reverse().find((a) => a[1] === 'details');
    const head = t.find((el, anc) => anc.includes(det) && el[1] === 'thead')[0];
    const cols = head ? t.find((el, anc) => anc.includes(head.el) && el[1] === 'th').map(({ el }) => t.text(el)) : [];
    const upd = t.find((el, anc) => anc.includes(det) && el[1] === 'span' && /^updated in /.test(t.text(el)))[0];
    out.change_history_label = upd ? t.text(upd.el) : null;
    for (const { el } of t.find((e2, anc) => anc.includes(det) && e2[1] === 'tr' && e2[2])) {
      const cells = t.find((e3, anc) => anc.includes(el) && (e3[1] === 'th' || e3[1] === 'td')).map((x) => t.text(x.el));
      const row = {};
      cols.forEach((c, i) => {
        const k = c.toLowerCase().replace(/[^a-z0-9]+/g, '_');
        row[k] = k === 'stat' ? cells[i] : (num(String(cells[i]).replace(/^\+/, '')) ?? cells[i]);
      });
      out.change_history.push(row);
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------
// 4. Breakable detail page
// ---------------------------------------------------------------------------------------------------------------------
function parseBreakablePage(html) {
  const t = new Tree(html);
  const out = {};
  out.name = t.text(t.find((el) => el[1] === 'h1')[0].el);
  const hitsEl = t.find((el) => el[1] === 'span' && /^\d+ hits? to break$/.test(t.text(el)))[0];
  out.hits_to_break = hitsEl ? Number(/^\d+/.exec(t.text(hitsEl.el))[0]) : null;
  const h = t.find((el) => el[1] === 'h2' && t.text(el) === 'Spawns on these maps')[0];
  const section = h ? h.anc[h.anc.length - 1] : null;
  out.maps = section
    ? t.find((el, anc) => anc.includes(section) && typeof el[3]?.href === 'string' && el[3].href.startsWith('/msclassic/maps/')).map(({ el }) => {
      const tx = t.texts(el); // [name, street, "×", count, "·", "120s"]
      const ci = tx.indexOf('×');
      const resp = tx.find((s) => /^\d+s$/.test(s));
      return { map_id: el[3].href.split('/').pop(), map_name: tx[0], street_name: ci > 1 ? tx[1] : null, count: ci >= 0 ? num(tx[ci + 1]) : null, respawn_s: resp ? Number(resp.slice(0, -1)) : null };
    })
    : [];
  return out;
}
function parseBreakablesList(html) {
  const t = new Tree(html);
  const rows = {};
  for (const { el } of t.find((e) => e[1] === 'tr' && typeof e[2] === 'string' && /^\d{7}$/.test(e[2]))) {
    const cells = t.find((e2, anc) => anc.includes(el) && e2[1] === 'td').map((x) => t.text(x.el));
    // columns: Sprite, Name, ID, Hits, Maps, Placements, Drops
    rows[el[2]] = { name: cells[1], id: cells[2], hits: num(cells[3]), maps: num(cells[4]), placements: num(cells[5]), drops: dash(cells[6]) ? null : num(cells[6]) };
  }
  return rows;
}

// ---------------------------------------------------------------------------------------------------------------------
// builders
// ---------------------------------------------------------------------------------------------------------------------
const ELEMENT_NOTE = 'raw = MeowDB simulator element string; "" matches the page label "No elemental affinity". The meaning of non-empty tokens (e.g. "fire-strong") is not documented on the pages read; none occur on Maple Island monsters';

/**
 * The live page's "STAGGER" block ("STAGGER\n0.6 seconds\nHow long the mob is staggered for when knocked back."), read
 * from the dated capture (tools/meowdb/captures/monster_<id>.*): {ms, value, explanation} or null when the capture has
 * none. Seconds become whole milliseconds with exact decimal arithmetic (up to 3 decimals; more is an error).
 */
function liveStagger(live) {
  if (!live) return null;
  const lines = live.text.split('\n').map((s) => s.trim()).filter(Boolean);
  const at = lines.indexOf('STAGGER');
  if (at < 0) return null;
  const m = /^(\d+)(?:\.(\d{1,3}))?\s+seconds?$/.exec(lines[at + 1] ?? '');
  if (!m) throw new Error(`${live.file}: unreadable STAGGER value ${JSON.stringify(lines[at + 1])}`);
  return { ms: Number(m[1]) * 1000 + Number((m[2] ?? '').padEnd(3, '0')), value: lines[at + 1], explanation: lines[at + 2] ?? null };
}

function buildMonster(id, pg, P, raw, rawMeta, mesos, maps, glossary, spawnFormula, mobRate, damageTaken, live) {
  const R = raw.rows[id];
  const rawSpeed = raw.speed[id];
  const dis = [];
  const gaps = [];
  const notes = [];
  const cmp = (field, pageVal, rawVal, chosen, why) => {
    if (pageVal !== rawVal) {
      const d = { field, values: [{ value: pageVal, source: pg.url }, { value: rawVal, source: rawMeta.url }], chosen, reason: why };
      dis.push(d);
      discrepancies.push({ monster_id: id, ...d });
    }
  };
  // detail page is canonical for everything it shows; raw table must agree
  cmp('name', P.name, R.name, P.name, 'detail page is canonical');
  cmp('level', P.level, R.level, P.level, 'detail page is canonical');
  cmp('hp', P.hp, R.hp, P.hp, 'detail page is canonical');
  cmp('exp', P.exp, R.exp, P.exp, 'detail page is canonical');
  cmp('physical_damage', P.touch_base, R.pdmg, P.touch_base, 'detail page is canonical');
  cmp('accuracy', P.acc, R.acc, P.acc, 'detail page is canonical');
  const mpAttr = P.other_attributes.map((a) => /^MP (\d+)$/.exec(a.label)).find(Boolean);
  const pageMp = mpAttr ? Number(mpAttr[1]) : null;
  cmp('mp', pageMp, R.mp, pageMp ?? R.mp, 'detail page is canonical');
  // "—" on the page must mean 0 in the raw table
  const dashField = (key, rawKey, field) => {
    if (P[key] !== null) { cmp(field, P[key], R[rawKey], P[key], 'detail page is canonical'); return P[key]; }
    if (R[rawKey] !== 0) {
      const d = { field, values: [{ value: P[key + '_display'], source: pg.url }, { value: R[rawKey], source: rawMeta.url }], chosen: null, reason: 'page shows a dash but the raw table is non-zero; left null' };
      dis.push(d); discrepancies.push({ monster_id: id, ...d });
      return null;
    }
    return 0;
  };
  const mdmg = dashField('mdmg', 'mdmg', 'magic_damage');
  const pdef = dashField('pdef', 'pdef', 'physical_defense');
  const mdef = dashField('mdef', 'mdef', 'magic_defense');
  const avoid = dashField('avoid', 'avoid', 'avoidability');
  if (P.speed_display_raw !== null) cmp('speed', P.speed_display_raw, rawSpeed, P.speed_display_raw, 'detail page is canonical');
  const speed = P.speed_display_raw ?? (rawSpeed ?? null);
  const pagePeace = P.other_attributes.some((a) => a.label === 'Peace') || P.header_badges.includes('Peace');
  cmp('non_aggressive', pagePeace, R.nonAgg, pagePeace, 'detail page is canonical ("Peace" attribute)');
  if (P.element_text !== 'No elemental affinity' || R.element !== '') {
    gaps.push(`element affinity: page shows "${P.element_text}", raw table "${R.element}" - parse the page text before use`);
  }
  if (P.locations_header_count !== P.locations.length) {
    const d = { field: 'spawns.length', values: [{ value: P.locations_header_count, source: pg.url + ' (Map Locations header)' }, { value: P.locations.length, source: pg.url + ' (locations props)' }], chosen: P.locations.length, reason: 'structured list used' };
    dis.push(d); discrepancies.push({ monster_id: id, ...d });
  }

  // spawn table, cross-checked against the 25 Maple Island map pages
  const spawns = P.locations.map((l) => {
    const timed = l.count - l.waveSpawnCount;
    const isle = Object.prototype.hasOwnProperty.call(maps, l.mapId);
    const row = {
      map_id: l.mapId,
      map_name: l.mapName,
      street_name: l.streetName,
      maple_island: isle,
      count: l.count,
      map_total_spawns: l.mapTotal,
      share_pct: l.mapTotal > 0 ? Math.round((100 * l.count) / l.mapTotal) : null,
      map_mob_type_count: l.mapTypes,
      mob_rate: l.mobRate,
      wave_spawn_count: l.waveSpawnCount,
      timed_spawn_count: timed,
      respawn_kind: timed === 0 ? 'wave' : l.waveSpawnCount === 0 ? 'timed' : 'mixed',
      respawn_min_s: l.respawnMin,
      respawn_max_s: l.respawnMax,
    };
    if (isle) {
      const mp = maps[l.mapId];
      const mm = mp.monsters.find((m) => m.id === id);
      const spawnPts = mp.spawns.filter((s) => String(s.mobId) === id).length;
      const check = (field, a, b) => {
        if (a !== b) {
          const d = { field: `spawns[${l.mapId}].${field}`, values: [{ value: a, source: pg.url }, { value: b, source: mp.url }], chosen: a, reason: 'monster page value kept; map page differs' };
          dis.push(d); discrepancies.push({ monster_id: id, ...d });
        }
      };
      check('count', l.count, mm ? mm.count : null);
      check('count_vs_map_spawn_points', l.count, spawnPts);
      check('wave_spawn_count', l.waveSpawnCount, mm ? mm.wave : null);
      check('mob_rate', l.mobRate, mp.mob_rate);
      check('map_total_spawns', l.mapTotal, mp.total_mob_count);
    }
    return row;
  });
  // every Maple Island map that lists this monster must be in the monster page's list
  for (const mp of Object.values(maps)) {
    if (mp.monsters.some((m) => m.id === id) && !P.locations.some((l) => l.mapId === mp.id)) {
      const d = { field: 'spawns', values: [{ value: `missing ${mp.id}`, source: pg.url }, { value: `listed on ${mp.id}`, source: mp.url }], chosen: null, reason: 'map page lists the monster but the monster page does not' };
      dis.push(d); discrepancies.push({ monster_id: id, ...d });
    }
  }

  // mob_rate MEANING: MeowDB's pages disagree. The number is kept verbatim; all texts are recorded. Emitted only while
  // both positions are actually present in the cached pages, so a future MeowDB reconciliation does not leave a stale entry.
  const rateMap = MAPLE_ISLAND_MAPS.map((m) => maps[m]).find((mp) => mp.about_mob_rate && P.locations.some((l) => l.mapId === mp.id));
  const rateVals = [];
  if (mobRate.tip) rateVals.push({ value: mobRate.tip.text, source: `${pg.url} (Map Locations "Mob Rate" column tooltip; i18n string in ${mobRate.tip.url})` });
  if (rateMap) rateVals.push({ value: rateMap.about_mob_rate, source: `${rateMap.url} ("About mob rate." paragraph)` });
  if (mobRate.glossary) rateVals.push({ value: mobRate.glossary.text, source: `${mobRate.glossary.url} (glossary entry "mob rate")` });
  const NO_MULT = /no separate map-wide multiplier/i;
  const rateIsMultiplier = rateVals.some((v) => /\bmultipl/i.test(v.value) && !NO_MULT.test(v.value));
  const rateIsNotMultiplier = rateVals.some((v) => NO_MULT.test(v.value));
  if (rateIsMultiplier && rateIsNotMultiplier) {
    const d = {
      field: 'spawns[].mob_rate (meaning)',
      values: rateVals,
      chosen: 'mob_rate is kept verbatim as MeowDB publishes it; the extractor applies no multiplier and derives no capacity',
      reason: 'MeowDB disagrees with itself: the monster-page tooltip and the map pages call mob rate a multiplier on how many monsters a map keeps alive (the map page calls it "our best reading from closed-beta play" and does not apply it to its own figures), while the glossary says live capacity is the spawn-point count scaled by party size with no separate map-wide multiplier'
        + (mobRate.spawnCapacityHasNoRate ? `; the ${mobRate.spawnUrl} capacity model ("Capacity = floor(SpawnPoints × PlayerScalar)") has no mob-rate term` : '')
        + '. Whether the game applies mob_rate is a MisoStory design decision, not canonical data',
    };
    dis.push(d); discrepancies.push({ monster_id: id, ...d });
  } else if (rateVals.length < 3) {
    warn(`monster ${id}: could not read all mob-rate texts (tooltip ${!!mobRate.tip}, map paragraph ${!!rateMap}, glossary ${!!mobRate.glossary})`);
  }

  const anim = {};
  for (const [clip, a] of Object.entries(P.animations)) anim[clip] = a ? { duration_ms: a.ms, held_pose: a.held_pose, display: a.display } : null;

  const mesosSummary = mesos.json.summary;
  if (!P.touch_damage_estimate) gaps.push('touch damage estimate not shown on the page');
  gaps.push('mesos per kill: ' + (mesosSummary.count === 0 ? 'no player reports on MeowDB (see drops/' + id + '.json)' : `${mesosSummary.count} player report(s) only`) + '; MeowDB publishes no meso formula or meso drop chance (the runtime applies the meso rule of decision D3-12)');
  gaps.push('drop chances and quantities: MeowDB gives none; drops/' + id + '.json records membership and rarity, and the runtime applies the owner-approved chance table (decision D3-11)');
  gaps.push('kb (knockback threshold), boss/undead tags, hp/mp recovery and revive data are not shown on the detail page; taken from MeowDB\'s simulator data chunk (field_sources)');
  gaps.push('attacks: the page lists no attack entries (skills, ranged or magic attacks) for this monster, only the touch zone; touch-damage rules live in the formulas domain (/formulas/damage-taken)');
  const stagger = liveStagger(live);
  gaps.push((stagger
    ? 'monster knockback: MeowDB publishes the KB threshold (knockback_threshold_damage) and, on the live page, how long the monster is staggered (stagger_ms). How far or how high a monster is pushed when hit is not published'
    : 'monster knockback: MeowDB publishes only the KB threshold (knockback_threshold_damage). How far, how high or how long a monster is pushed or staggered when hit is not published')
    + (damageTaken.playerKnockbackSection ? `; the "Knockback Airtime" model on ${damageTaken.url} sits under "After You Get Hit" and describes the PLAYER being knocked back, not monsters` : ''));
  if (pagePeace && P.touch_zone_px) {
    const peaceTitle = P.other_attributes.find((a) => a.label === 'Peace')?.title;
    const peaceAnalysis = P.analysis.filter((a) => /PEACE|walk past/i.test(a));
    const est = P.touch_damage_estimate ? `, Touch DMG ${P.touch_damage_estimate[0]}-${P.touch_damage_estimate[1]} (Base ${P.touch_base})` : '';
    gaps.push(`Peace vs touch damage: this page marks the monster "Peace"${peaceTitle ? ` ("${peaceTitle}")` : ''}${peaceAnalysis.length ? ` and its analysis says "${peaceAnalysis.join(' ')}"` : ''}, yet the same page shows a ${P.touch_zone_px[0]} x ${P.touch_zone_px[1]} px touch zone${est} and the generic Combat Details text "${P.touch_zone_text}". MeowDB does not say whether walking into a Peace monster's touch zone damages the player`);
  }
  for (const q of P.quests) {
    if (q.min_level === null) gaps.push(`quests[${q.quest_id}].min_level: the monster page shows no "Lv N+" for ${q.name}; read quest requirements from the quests domain (quests/${q.quest_id}.json, built from ${L.BASE_URL}/quest-tracker/${q.quest_id}), not from this file`);
  }

  if (P.touch_title) notes.push('MeowDB (Touch DMG tooltip): ' + P.touch_title);
  if (P.touch_zone_title) notes.push('MeowDB (touch zone tooltip): ' + P.touch_zone_title);
  if (P.touch_zone_text) notes.push('MeowDB (Combat Details): ' + P.touch_zone_text);
  if (P.die_fade_text) notes.push('MeowDB (animation): ' + P.die_fade_text);
  for (const a of P.analysis) notes.push('MeowDB analysis: ' + a);
  notes.push('Respawn: "wave" spawn points respawn on MeowDB\'s modelled global 7.56 s server tick plus a 5 s per-point cooldown (the page shows "~7.5s"); "timed" points use respawn_min_s..respawn_max_s. See ' + L.BASE_URL + SPAWN_FORMULA_PAGE + ' (retrieved ' + spawnFormula.retrieved_at + ').');

  const fsrc = (url, retrieved_at, extra) => ({ url, retrieved_at, ...(extra ? { note: extra } : {}) });
  const rawSrc = (note) => fsrc(rawMeta.url, rawMeta.retrieved_at, note);
  // a value the page shows is sourced to the page; a page "—" is resolved to 0 by the raw table
  const dashSrc = (key) => (P[key] !== null ? fsrc(pg.url, pg.retrieved_at, 'page value; raw table agrees') : rawSrc('page shows "—"; raw table value 0'));
  return {
    id,
    name: P.name,
    bestiary_no: P.bestiary_no,
    category_label: P.category_label,
    description: P.description,
    level: P.level,
    hp: P.hp,
    mp: pageMp,
    exp: P.exp,
    physical_damage: P.touch_base,
    touch_damage_estimate_at_0_wdef: P.touch_damage_estimate ? { min: P.touch_damage_estimate[0], max: P.touch_damage_estimate[1] } : null,
    magic_damage: mdmg,
    physical_defense: pdef,
    magic_defense: mdef,
    accuracy: P.acc,
    avoidability: avoid,
    knockback_threshold_damage: R.kb,
    stagger_ms: stagger ? stagger.ms : null,
    speed,
    speed_label: P.speed_label,
    movement: { label: P.movement_label, description: P.movement_description },
    element: { label: P.element_text, raw: R.element, note: ELEMENT_NOTE },
    flags: {
      non_aggressive: pagePeace,
      boss: R.tags.includes('boss'),
      undead: R.tags.includes('undead'),
      auto_aggressive: R.tags.includes('auto-agg'),
      tags: R.tags,
    },
    hp_recovery: R.hpRec,
    mp_recovery: R.mpRec,
    revives_into: R.revives === '' ? [] : R.revives.split(',').map((s) => s.trim()),
    other_attributes: P.other_attributes,
    touch_zone_px: P.touch_zone_px,
    sprite_size_px: P.sprite_size_px,
    animation_clips: P.clips,
    animations: anim,
    die_fade_ms: P.die_fade_ms,
    mesos_per_kill: {
      report_count: mesosSummary.count,
      trusted_report_count: mesosSummary.trustedCount,
      median_min: mesosSummary.count > 0 ? mesosSummary.medianMin : null,
      median_max: mesosSummary.count > 0 ? mesosSummary.medianMax : null,
      canonical: false,
      see: `drops/${id}.json`,
    },
    drop_table: `drops/${id}.json`,
    spawns,
    quests: P.quests,
    change_history: { label: P.change_history_label, rows: P.change_history, note: 'headline stats on this page are the latest test (COT2) values' },
    source: L.source(pg.url, pg.retrieved_at),
    field_sources: {
      mp: fsrc(pg.url, pg.retrieved_at, 'from "Other Attributes" ("MP n")'),
      mesos_per_kill: fsrc(mesos.url, mesos.retrieved_at, 'client-side API behind the page\'s "Mesos per kill" line'),
      magic_damage: dashSrc('mdmg'),
      physical_defense: dashSrc('pdef'),
      magic_defense: dashSrc('mdef'),
      avoidability: dashSrc('avoid'),
      speed: P.speed_display_raw !== null ? fsrc(pg.url, pg.retrieved_at, 'page "(speed n)"; raw table agrees') : rawSrc(`page shows only the label "${P.speed_label}"; raw value from the simulator speed map`),
      knockback_threshold_damage: rawSrc(`raw "kb"; meaning per MeowDB glossary (${glossary.url}, retrieved ${glossary.retrieved_at}): "knockback resistance stat on mobs: a mob with 500 KB needs 500+ damage to stagger"`),
      ...(stagger ? {
        stagger_ms: {
          url: live.url, retrieved_at: live.read_at, capture: live.file,
          note: `live page "STAGGER ${stagger.value}"${stagger.explanation ? ` ("${stagger.explanation}")` : ''}, read by hand in a normal browser (decision D3-1); seconds converted to whole milliseconds. The 2026-10-04 cache predates the field`,
        },
      } : {}),
      flags: rawSrc('boss/undead/auto_aggressive/tags from raw "tags"; non_aggressive from the page "Peace" attribute (raw "nonAgg" agrees)'),
      element: rawSrc('label from the page; raw from the simulator table'),
      hp_recovery: rawSrc('raw "hpRec"'),
      mp_recovery: rawSrc('raw "mpRec"'),
      revives_into: rawSrc('raw "revives"'),
      ...(rateIsMultiplier && rateIsNotMultiplier ? {
        'spawns[].mob_rate': fsrc(pg.url, pg.retrieved_at, 'value from the page\'s locations props (Maple Island rows equal the map pages). Its MEANING is disputed between MeowDB pages; see discrepancies. Texts read from: '
          + [mobRate.tip && `${mobRate.tip.url} (retrieved ${mobRate.tip.retrieved_at})`, rateMap && `${rateMap.url} (retrieved ${rateMap.retrieved_at})`, mobRate.glossary && `${mobRate.glossary.url} (retrieved ${mobRate.glossary.retrieved_at})`].filter(Boolean).join('; ')),
      } : {}),
    },
    gaps,
    discrepancies: dis,
    notes,
  };
}

/**
 * MeowDB's cached data for one drop owner, as tools/sources/drops_merge.mjs reads it: the community drop list API (ids
 * by name for the reference lists), the cached page's MSEA list and the meso-report API (monsters only).
 */
function meowdbDropCache(community, msea, mesos, pageUrl) {
  return {
    community: { url: community.url, retrieved_at: community.retrieved_at, drops: community.json.drops },
    msea: (msea?.items || []).map((m) => ({ item_id: m.item_id, item_name: m.item_name })),
    msea_page: msea ? { url: pageUrl } : null,
    mesos: mesos ? { url: mesos.url, retrieved_at: mesos.retrieved_at, json: mesos.json } : null,
  };
}

// ---------------------------------------------------------------------------------------------------------------------
async function main() {
  const maps = await readMaps();
  const monsterIds = [...new Set(Object.values(maps).flatMap((m) => m.monsters.map((x) => x.id)))].sort((a, b) => Number(a) - Number(b));
  const breakableIds = [...new Set(Object.values(maps).flatMap((m) => m.reactors.map((x) => x.id)))].sort();
  console.log('monsters on the 25 maps:', monsterIds.join(', '), '| breakables:', breakableIds.join(', '));

  const raw = await readRawTable(monsterIds);
  const rawMeta = { url: raw.url, retrieved_at: raw.retrieved_at };
  const glossaryPg = await page(GLOSSARY_PAGE);
  const spawnPg = await page(SPAWN_FORMULA_PAGE);
  const glossary = { url: glossaryPg.url, retrieved_at: glossaryPg.retrieved_at };
  const spawnFormula = { url: spawnPg.url, retrieved_at: spawnPg.retrieved_at };
  // what MeowDB says mob rate means (glossary vs map/monster pages) and whether /formulas/spawns' capacity model uses it
  const mobRateGloss = glossaryDef(glossaryPg.html, 'mob rate');
  const spawnText = L.pageText(spawnPg.html).replace(/\s+/g, ' ');
  const mobRateBase = {
    glossary: mobRateGloss ? { text: mobRateGloss, ...glossary } : null,
    spawnUrl: spawnPg.url,
    spawnCapacityHasNoRate: spawnText.includes('Capacity = floor(SpawnPoints × PlayerScalar)') && !/mob ?rate/i.test(spawnText),
  };
  // /formulas/damage-taken: its "Knockback Airtime" section belongs to "After You Get Hit" (the player), cited in a gap
  const dmgPg = await page(DAMAGE_TAKEN_PAGE);
  const dmgText = L.pageText(dmgPg.html).replace(/\s+/g, ' ');
  const damageTaken = { url: dmgPg.url, playerKnockbackSection: /After You Get Hit .*?Knockback Airtime/.test(dmgText) };

  const captures = loadCaptures(); // dated hand-read pages: live monster pages (STAGGER) and the drop-record inputs
  const meowdbCache = {}; // per drop owner: MeowDB's cached lists, read here and handed to the drop merge
  for (const id of monsterIds) {
    const pg = await page('/monsters/' + id);
    const P = parseMonsterPage(pg.html, id);
    const community = await api('/msclassic/api/drops?monsterId=' + id);
    const mesos = await api('/msclassic/api/mesos-reports?monsterId=' + id);
    const mobRate = { ...mobRateBase, tip: await monsterPageMobRateTip(pg.html) };
    const monster = buildMonster(id, pg, P, raw, rawMeta, mesos, maps, glossary, spawnFormula, mobRate, damageTaken, captures.meowdb.monsters[id] ?? null);
    L.writeJson(path.join(OUT, 'monsters', id + '.json'), monster);

    if (P.msea) {
      const declared = num((/(\d+) items?$/.exec(P.msea.header_text || '') || [])[1]);
      if (declared !== P.msea.items.length) warn(`monster ${id}: MSEA header says ${declared}, parsed ${P.msea.items.length}`);
    }
    meowdbCache[id] = meowdbDropCache(community, P.msea, mesos, pg.url);
    if (monster.stagger_ms == null) warn(`monster ${id}: no live capture with a STAGGER value; stagger_ms is null`);
    console.log(`monster ${id} ${P.name}: lv${P.level} hp${P.hp} exp${P.exp} stagger ${monster.stagger_ms} ms; ${P.locations.length} spawn maps; ${P.quests.length} quests`);
  }

  // breakables
  const listPg = await page('/breakables');
  const list = parseBreakablesList(listPg.html);
  for (const bid of breakableIds) {
    const pg = await page('/breakables/' + bid);
    const B = parseBreakablePage(pg.html);
    const drops = await api('/msclassic/api/breakable-drops?breakableId=' + bid);
    const dis = [];
    const placements = [];
    for (const mp of Object.values(maps)) {
      for (const x of mp.reactors.filter((rx) => rx.id === bid)) placements.push({ map_id: mp.id, map_name: mp.name, x_px: x.x, y_px: x.y, respawn_s: x.respawn });
      if (mp.reactors.some((rx) => rx.label && rx.id === bid && rx.label !== B.name)) {
        dis.push({ field: 'name', values: [{ value: B.name, source: pg.url }, { value: mp.reactors.find((rx) => rx.id === bid).label, source: mp.url }], chosen: B.name, reason: 'breakable page is canonical' });
      }
    }
    const maps_ = B.maps.map((m) => {
      const pl = placements.filter((p) => p.map_id === m.map_id);
      const row = { map_id: m.map_id, map_name: m.map_name, street_name: m.street_name, maple_island: Object.prototype.hasOwnProperty.call(maps, m.map_id), count: m.count, respawn_s_listed: m.respawn_s };
      if (row.maple_island) {
        if (pl.length !== m.count) dis.push({ field: `maps[${m.map_id}].count`, values: [{ value: m.count, source: pg.url }, { value: pl.length, source: maps[m.map_id].url }], chosen: pl.length, reason: 'map page lists each placement' });
        const resp = [...new Set(pl.map((p) => p.respawn_s))].sort((a, b) => a - b);
        if (resp.length !== 1 || resp[0] !== m.respawn_s) {
          dis.push({ field: `maps[${m.map_id}].respawn_s`, values: [{ value: m.respawn_s, source: pg.url + ' (one value per map)' }, { value: resp, source: maps[m.map_id].url + ' (per placement)' }], chosen: 'per-placement respawn_s from the map page', reason: 'the map page gives a value per placement; the breakable page shows a single per-map value' });
        }
      }
      return row;
    });
    const L0 = list[bid];
    if (L0) {
      if (L0.hits !== B.hits_to_break) dis.push({ field: 'hits_to_break', values: [{ value: B.hits_to_break, source: pg.url }, { value: L0.hits, source: listPg.url }], chosen: B.hits_to_break, reason: 'detail page' });
      if (L0.placements !== B.maps.reduce((s, m) => s + (m.count || 0), 0)) dis.push({ field: 'placements', values: [{ value: B.maps.reduce((s, m) => s + (m.count || 0), 0), source: pg.url }, { value: L0.placements, source: listPg.url }], chosen: null, reason: 'totals differ' });
      if (L0.drops !== null && L0.drops !== drops.json.drops.length) dis.push({ field: 'drops.length', values: [{ value: drops.json.drops.length, source: drops.url }, { value: L0.drops, source: listPg.url }], chosen: drops.json.drops.length, reason: 'API is the live list' });
    }
    for (const d of dis) discrepancies.push({ breakable_id: bid, ...d });
    const entity = {
      id: bid,
      name: B.name,
      kind: 'breakable',
      hits_to_break: B.hits_to_break,
      hits_to_break_note: '"Hits" is how many basic attacks it takes to break open (MeowDB /breakables)',
      maps: maps_,
      placements: placements.sort((a, b) => a.map_id.localeCompare(b.map_id) || a.x_px - b.x_px || a.y_px - b.y_px),
      drop_table: `drops/${bid}.json`,
      breakables_list_row: L0 ? { hits: L0.hits, maps: L0.maps, placements: L0.placements, drops: L0.drops } : null,
      source: L.source(pg.url, pg.retrieved_at),
      field_sources: {
        breakables_list_row: { url: listPg.url, retrieved_at: listPg.retrieved_at },
        ...Object.fromEntries([...new Set(placements.map((p) => p.map_id))].sort().map((mid) => [
          `placements[${mid}]`,
          { url: maps[mid].url, retrieved_at: maps[mid].retrieved_at, note: 'map page "reactors" list: x/y in MapleStory px (y down), respawn in seconds' },
        ])),
      },
      gaps: [
        'HP / hit rules beyond "N basic attacks": not published (MeowDB counts basic attacks only)',
        'drop chances / quantities: not published',
        'whether skills or damage amount affect hits: not published',
      ],
      discrepancies: dis,
      notes: ['MeowDB calls breakables "reactors" in map data (map page key "reactors", label from "breakableLabels").'],
    };
    L.writeJson(path.join(OUT, 'breakables', bid + '.json'), entity);
    meowdbCache[bid] = meowdbDropCache(drops, null, null, pg.url);
    console.log(`breakable ${bid} ${B.name}: ${B.hits_to_break} hits; ${placements.length} Maple Island placements`);
  }

  // Drop records (contract C1): MeowDB community-list membership and Henesys.gg rarity. The build must cover exactly the
  // drop owners found on the 25 maps.
  const { records, summary } = buildDropRecords({ captures, meowdbCache });
  const owners = [...monsterIds, ...breakableIds];
  if (owners.slice().sort().join() !== Object.keys(records).sort().join()) {
    throw new Error(`drop owners on the maps (${owners.join(', ')}) differ from the merged records (${Object.keys(records).join(', ')})`);
  }
  const itemIds = new Set();
  for (const id of owners) {
    L.writeJson(path.join(OUT, 'drops', id + '.json'), records[id]);
    for (const e of records[id].entries) if (e.item_id != null) itemIds.add(e.item_id);
  }
  for (const line of summary) console.log('drops', line);
  console.log('resolved drop member item ids:', [...itemIds].sort((a, b) => Number(a) - Number(b)).join(','));
  console.log('discrepancies:', discrepancies.length);
  for (const d of discrepancies) console.log('  ', JSON.stringify(d));
}

main().catch((e) => { console.error(e); process.exit(1); });
