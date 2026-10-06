// Offline loader for the dated, hand-read source captures (Iteration Three decisions D3-1..D3-8):
//
//   tools/meowdb/captures/       MeowDB MS Classic pages re-read in a normal browser (monster, breakable, quest and item
//                                pages, the quest tracker) and item API bodies (items_api.json)
//   tools/kurodb/captures/       KuroDB monster pages (<kuro monster id>.json), the reactor item pages
//                                (reactor_2001_items.json) and single item pages (item_<kuro item id>.json, read to settle
//                                which item a monster page's row is: decision D3-8); drop and meso probabilities only
//   tools/hiddenstreet/captures/ Hidden Street "Before Chaos" monster pages (drop membership and meso amounts only)
//
// Reads the files only; it never touches the network. Every file in those folders is loaded (README.md files are
// documentation and skipped); an unrecognised file is an error, so a new capture cannot be silently ignored. Every
// capture must carry an ISO 8601 read time (see isIsoTimestamp); items_api.json records only a session time in its
// "method" text, which is derived explicitly and flagged read_at_approximate.
//
//   import { loadCaptures } from '../sources/captures.mjs';
//   const c = loadCaptures();
//   c.kurodb.monsters['100100'].rows[0]   // {kuro_item_id: "4000019", name: "Snail Shell", raw: "100% base | Qty 1", ...}
//   c.hiddenstreet.monsters.snail.mesos   // {raw: "Mesos: 1", state: "resolved", min: 1, max: 1}
//   c.meowdb.monsters['2'].meso.report    // {raw: "Mesos: 2 per kill | 1 report", min: 2, max: 2, reports: 1, ...}
//   c.meowdb.item_pages['242'].rows['Max per Stack']   // {label: "Max per Stack", raw: "100", value: 100}
//   c.kurodb.item_pages['2040705']?.success_rate       // {pct: 10, raw: "...", source: "item stats" | "description"} | null
//
// Every capture object has {file (repo-relative, forward slashes), authority, url, read_at, method, sha256}.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
  parseKuroPercent, parseReactorChanceValue, parseHiddenStreetMonsterText, parseMeowdbMesoReport, isIsoTimestamp,
  SourceParseError,
} from './parse.mjs';

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Authority names; they must match game/scripts/core/validation/provenance_authorities.gd REGISTRY. */
export const AUTHORITIES = { meowdb: 'MeowDB MS Classic', kurodb: 'KuroDB', hiddenstreet: 'Hidden Street' };
export const CAPTURE_DIRS = { meowdb: 'tools/meowdb/captures', kurodb: 'tools/kurodb/captures', hiddenstreet: 'tools/hiddenstreet/captures' };

const DOC_FILES = new Set(['README.md']);

const memo = new Map();

/** Loads every capture under `root` (default: this repository). Cached per root. Throws on any unreadable capture. */
export function loadCaptures({ root = REPO_ROOT } = {}) {
  const key = path.resolve(root);
  if (!memo.has(key)) memo.set(key, load(key));
  return memo.get(key);
}

/**
 * The captured body for an exact API URL (items_api.json), or null. Used by tools/meowdb/lib.mjs as a fallback after a
 * cache miss. Only verbatim JSON API bodies are served; rendered-text page captures are never treated as pages.
 * Returns {url, text, read_at, read_at_approximate, read_at_note, capture: <repo-relative file>, pointer}.
 */
export function apiCaptureFor(url, { root = REPO_ROOT } = {}) {
  const c = loadCaptures({ root });
  for (const [id, it] of Object.entries(c.meowdb.items_api.items)) {
    if (it.url === url) {
      return {
        url: it.url, text: JSON.stringify(it.body), read_at: it.read_at, read_at_approximate: it.read_at_approximate,
        read_at_note: it.read_at_note, capture: c.meowdb.items_api.file, pointer: `/items/${id}/body`,
      };
    }
  }
  return null;
}

// ---------------------------------------------------------------------------------------------------------------

function load(root) {
  const out = {
    meowdb: { monsters: {}, breakables: {}, items_api: null, item_pages: {}, quests: {}, quest_tracker: null },
    kurodb: { monsters: {}, reactor_items: null, item_pages: {} },
    hiddenstreet: { monsters: {}, site: null, version_note: null },
    files: [],
  };
  for (const [site, dir] of Object.entries(CAPTURE_DIRS)) {
    const abs = path.join(root, dir);
    if (!fs.existsSync(abs)) throw new Error(`capture folder missing: ${dir}`);
    for (const name of fs.readdirSync(abs).sort()) {
      const full = path.join(abs, name);
      if (fs.statSync(full).isDirectory()) throw new Error(`${dir}/${name}: nested capture folders are not supported`);
      if (DOC_FILES.has(name)) continue;
      const file = `${dir}/${name}`;
      const text = fs.readFileSync(full, 'utf8');
      const meta = { file, authority: AUTHORITIES[site], sha256: crypto.createHash('sha256').update(text).digest('hex') };
      try {
        loadOne(out, site, name, text, meta);
      } catch (e) {
        if (!String(e.message).startsWith(file)) e.message = `${file}: ${e.message}`;
        throw e;
      }
      out.files.push({ file, authority: meta.authority, sha256: meta.sha256 });
    }
  }
  return out;
}

function requireReadAt(obj, where) {
  if (!isIsoTimestamp(obj.read_at)) throw new Error(`${where}: read_at ${JSON.stringify(obj.read_at)} is not an ISO 8601 timestamp with a zone`);
}

function loadOne(out, site, name, text, meta) {
  if (site === 'kurodb') {
    let m;
    if ((m = /^(\d+)\.json$/.exec(name))) {
      const j = JSON.parse(text);
      // A numeric name is a monster page (<kuro monster id>.json). Say so plainly when it is another kind of page.
      const head = String(j?.text ?? '').split('\n').map((s) => s.trim()).find(Boolean) ?? '';
      if (/^ITEM\s*·/.test(head)) throw new Error(`this is a KuroDB ITEM page ("${head}"): save it as item_<kuro item id>.json (a numeric name is a monster page)`);
      if (!/^MONSTER\s*·/.test(head) || j?.kuro_monster_id == null) {
        throw new Error(`a numeric KuroDB capture name is a monster page: expected kuro_monster_id and text starting "MONSTER · ${m[1]}", got ${JSON.stringify(head)}`);
      }
      if (String(j.kuro_monster_id) !== m[1]) throw new Error(`kuro_monster_id ${j.kuro_monster_id} differs from the file name ${m[1]}`);
      const mon = kuroMonster(j, meta);
      out.kurodb.monsters[mon.kuro_monster_id] = mon;
      return;
    }
    if ((m = /^item_(\d+)\.json$/.exec(name))) {
      out.kurodb.item_pages[m[1]] = kuroItemPage(m[1], JSON.parse(text), meta);
      return;
    }
    if (name === 'reactor_2001_items.json') {
      out.kurodb.reactor_items = kuroReactorItems(JSON.parse(text), meta);
      return;
    }
  } else if (site === 'hiddenstreet') {
    if (name === 'monsters.json') {
      const j = JSON.parse(text);
      out.hiddenstreet.site = j.site ?? null;
      out.hiddenstreet.version_note = j.version_note ?? null;
      for (const m of j.monsters || []) {
        const one = { ...meta, slug: m.slug, url: m.url, read_at: m.read_at, method: j.method ?? null, text: m.text, ...parseHiddenStreetMonsterText(m.text) };
        requireReadAt(one, `${meta.file} ${m.slug}`);
        out.hiddenstreet.monsters[m.slug] = one;
      }
      return;
    }
  } else if (site === 'meowdb') {
    let m;
    if ((m = /^monster_(\d+)\.(json|txt)$/.exec(name))) {
      out.meowdb.monsters[m[1]] = meowdbMonster(m[1], m[2] === 'json' ? JSON.parse(text) : textCapture(text), meta);
      return;
    }
    if ((m = /^breakable_(\d+)\.txt$/.exec(name))) {
      out.meowdb.breakables[m[1]] = meowdbBreakable(m[1], textCapture(text), meta);
      return;
    }
    if ((m = /^quest_(\d+)\.txt$/.exec(name))) {
      out.meowdb.quests[m[1]] = meowdbQuest(m[1], textCapture(text), meta);
      return;
    }
    if ((m = /^item_(\d+)\.txt$/.exec(name))) {
      out.meowdb.item_pages[m[1]] = meowdbItemPage(m[1], textCapture(text), meta);
      return;
    }
    if (name === 'quest_tracker_maple_island.txt') {
      out.meowdb.quest_tracker = meowdbQuestTracker(textCapture(text), meta);
      return;
    }
    if (name === 'items_api.json') {
      out.meowdb.items_api = meowdbItemsApi(JSON.parse(text), meta);
      return;
    }
  }
  throw new Error(`unrecognised capture file (add a reader to tools/sources/captures.mjs)`);
}

// --- text capture header ----------------------------------------------------------------------------------------

/**
 * A ".txt" capture: "KEY: value" header lines (continuation lines indented), a "---" line, then the rendered page
 * text. Returns {header: {url, read_at, method, purpose, ...}, body}.
 */
export function textCapture(text) {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  const sep = lines.indexOf('---');
  if (sep < 0) throw new Error('text capture has no "---" line after its header');
  const header = {};
  let last = null;
  for (const line of lines.slice(0, sep)) {
    const kv = /^([A-Z_]+):\s?(.*)$/.exec(line);
    if (kv) {
      last = kv[1].toLowerCase();
      header[last] = kv[2];
    } else if (last && /^\s+\S/.test(line)) {
      header[last] += ' ' + line.trim();
    } else if (line.trim() !== '') {
      throw new Error(`unreadable header line ${JSON.stringify(line)}`);
    }
  }
  return { header, body: lines.slice(sep + 1).join('\n') };
}

// --- KuroDB -----------------------------------------------------------------------------------------------------

function kuroMonster(j, meta) {
  const m = {
    ...meta, kuro_monster_id: String(j.kuro_monster_id), url: j.url, read_at: j.read_at, method: j.method ?? null,
    site_updated_label: j.site_updated_label ?? null, name: j.text.split('\n').map((s) => s.trim()).filter(Boolean)[1] ?? null,
    rows: [], meso: null, text: j.text,
  };
  requireReadAt(m, meta.file);
  const count = /DROPS \((\d+)\)/.exec(j.text);
  if (!count || Number(count[1]) !== (j.rows || []).length) throw new Error(`"DROPS (N)" does not match the ${(j.rows || []).length} captured rows`);
  for (const r of j.rows || []) {
    if (!j.text.includes(`${r.name}\n${r.detail}`)) throw new Error(`row ${JSON.stringify(r.name)} / ${JSON.stringify(r.detail)} is not in the captured page text`);
    const p = parseKuroPercent(r.detail);
    if (p.kind === 'meso') {
      if (m.meso) throw new Error('two meso rows');
      if (r.link_id != null) throw new Error('the meso row links an item');
      m.meso = { name: r.name, raw: r.detail, pct: p.percent, probability: p.probability, parsed: p };
      continue;
    }
    if (r.link_section !== 'items' || !r.link_id) throw new Error(`row ${JSON.stringify(r.name)} has no item link`);
    m.rows.push({
      kuro_item_id: String(r.link_id), name: r.name, raw: r.detail, pct: p.percent, probability: p.probability,
      qty: p.qty, quest: p.quest, parsed: p,
    });
  }
  return m;
}

/** Splits a KuroDB item page's text into its MONSTER DROPS and REACTOR DROPS (N) pairs. */
function kuroItemSections(text) {
  const lines = text.split('\n').map((s) => s.trim()).filter(Boolean);
  const mi = lines.indexOf('MONSTER DROPS');
  const ri = lines.findIndex((l) => /^REACTOR DROPS \(\d+\)$/.test(l));
  if (mi < 0 || ri < 0 || ri < mi) throw new Error('item page text has no "MONSTER DROPS" / "REACTOR DROPS (N)" sections');
  const end = lines.findIndex((l, i) => i > ri && /^NPC SHOPS$/.test(l));
  const monsterLines = lines.slice(mi + 1, ri);
  const reactorLines = lines.slice(ri + 1, end < 0 ? lines.length : end);
  const reactorCount = Number(/\((\d+)\)/.exec(lines[ri])[1]);
  return { monsterLines, reactorLines, reactorCount };
}

function pairs(list, what) {
  if (list.length % 2 !== 0) throw new Error(`${what}: lines do not pair up (${list.length})`);
  const out = [];
  for (let i = 0; i < list.length; i += 2) out.push([list[i], list[i + 1]]);
  return out;
}

function kuroReactorItems(j, meta) {
  const out = {
    ...meta, url: null, read_at: null, method: j.note ?? null, site_updated_label: j.site_updated_label ?? null,
    reactor_identity_inference: j.reactor_identity_inference ?? null, egg_note: j.egg_note ?? null, items: {},
  };
  for (const it of j.items || []) {
    const one = { file: meta.file, authority: meta.authority, kuro_item_id: String(it.kuro_item_id), name: it.name, url: it.url, read_at: it.read_at, text: it.text, monster_drops: [], reactor_drops: [] };
    requireReadAt(one, `${meta.file} ${it.kuro_item_id}`);
    const s = kuroItemSections(it.text);
    const monsterLines = s.monsterLines.length === 1 && /^No monster drop is recorded\.$/.test(s.monsterLines[0]) ? [] : s.monsterLines;
    for (const [monster, raw] of pairs(monsterLines, `${it.name} monster drops`)) {
      const p = parseKuroPercent(raw);
      one.monster_drops.push({ monster_name: monster, raw, pct: p.percent, probability: p.probability, qty: p.qty, quest: p.quest, kuro_monster_id: p.source_id, parsed: p });
    }
    for (const [reactor, raw] of pairs(s.reactorLines, `${it.name} reactor drops`)) {
      const r = /^Reactor (\d+)$/.exec(reactor);
      if (!r) throw new Error(`${it.name}: expected "Reactor N", got ${JSON.stringify(reactor)}`);
      const p = parseReactorChanceValue(raw);
      one.reactor_drops.push({ reactor_id: r[1], raw, raw_n: p.raw_n, probability: p.probability, interpretation: p.interpretation, quest: p.quest, parsed: p });
    }
    if (one.reactor_drops.length !== s.reactorCount) throw new Error(`${it.name}: "REACTOR DROPS (${s.reactorCount})" but ${one.reactor_drops.length} rows`);
    out.items[one.kuro_item_id] = one;
  }
  return out;
}

/** Section headings of a KuroDB item page's rendered text (the reactor heading carries its count). */
const KURO_ITEM_HEADINGS = [/^CATEGORY$/, /^SOURCE$/, /^DROPPED BY$/, /^SOLD BY$/, /^DESCRIPTION$/, /^ITEM STATS$/, /^MONSTER DROPS$/,
  /^REACTOR DROPS \(\d+\)$/, /^NPC SHOPS$/];
/** An ITEM STATS label line ("PRICE", "SUCCESS RATE", "JUMP"): upper case, then its value on the next line. */
const KURO_STAT_LABEL = /^[A-Z][A-Z0-9 .%/&()'-]*$/;

/** Spelled-out stat names -> the keys MeowDB's scroll records use (items/<id>.json scroll.stat_bonus_on_success). */
const STAT_ALIASES = { weapondef: 'wdef', weapondefense: 'wdef', magicdef: 'mdef', magicdefense: 'mdef', weaponatt: 'watk',
  weaponattack: 'watk', magicatt: 'matk', magicattack: 'matk', accuracy: 'acc', avoidability: 'avoid', maxhp: 'hp', maxmp: 'mp' };

/** Item.wz property names a page may show for a scroll bonus ("incJump", "INC PAD") without their "inc" -> MeowDB keys. */
const WZ_STAT_CODES = { str: 'str', dex: 'dex', int: 'int', luk: 'luk', pad: 'watk', mad: 'matk', pdd: 'wdef', mdd: 'mdef',
  acc: 'acc', eva: 'avoid', speed: 'speed', jump: 'jump', mhp: 'hp', mmp: 'mp' };

/**
 * The stat keys MeowDB's scroll records use (tools/meowdb/extract_items.mjs STAT_KEYS, items/<id>.json
 * scroll.stat_bonus_on_success). A key a page gives outside this list is a name the reader does not understand.
 */
export const SCROLL_STAT_KEYS = Object.freeze(['str', 'dex', 'int', 'luk', 'watk', 'matk', 'wdef', 'mdef', 'acc', 'avoid',
  'speed', 'jump', 'hp', 'mp']);

/**
 * A stat name as written on a page ("Jump", "jump", "DEX", "Weapon Def.", "incJump") -> the key MeowDB's scroll records
 * use ("jump", "dex", "wdef"): lower case, letters only, spelled-out names (STAT_ALIASES) and Item.wz "inc" names
 * (WZ_STAT_CODES) mapped. An unknown name keeps its letters, so it can never equal a MeowDB key by accident (and is
 * not in SCROLL_STAT_KEYS: drops_merge.mjs refuses to judge a candidate on it).
 */
export const statKey = (name) => {
  const k = String(name).toLowerCase().replace(/[^a-z]/g, '');
  if (STAT_ALIASES[k]) return STAT_ALIASES[k];
  const inc = /^inc([a-z]+)$/.exec(k);
  return inc && WZ_STAT_CODES[inc[1]] ? WZ_STAT_CODES[inc[1]] : k;
};

/** "+3" bonuses named in free text: "Success rate: 10%, Jump +3" / "jump+2, DEX +1" -> {jump: 3} / {jump: 2, dex: 1}. */
export function statBonusesIn(text) {
  const out = {};
  // The name is the run of letters, spaces and dots right before the "+" ("Weapon Def. +4"); punctuation (": 10%, ")
  // and line ends separate it from the words before.
  for (const m of String(text ?? '').matchAll(/([A-Za-z][A-Za-z .]*?)\s*\+\s*(\d+)/g)) {
    const k = statKey(m[1].trim());
    if (!k) continue;
    if (out[k] != null && out[k] !== Number(m[2])) throw new Error(`stat ${k} is given twice with different values in ${JSON.stringify(text)}`);
    out[k] = Number(m[2]);
  }
  return out;
}

/** "Success rate: 10%" / "Success Rate 10%" / "success rate:10%" in free text -> 10, or null. */
export function successRateIn(text) {
  const m = /success\s*rate\s*:?\s*(\d+(?:\.\d+)?)\s*%/i.exec(String(text ?? ''));
  return m ? Number(m[1]) : null;
}

/**
 * A KuroDB item page read by hand: tools/kurodb/captures/item_<kuro item id>.json, the same shape as the monster
 * captures ({kuro_item_id, url, read_at, method, site_updated_label?, text}: the rendered page text, verbatim). Parsed:
 * the heading ("ITEM · <id>", which must be the file's id, as must kuro_item_id and the #items/<id> URL), the name,
 * the category, the description, the ITEM STATS label/value pairs, the MONSTER DROPS and REACTOR DROPS rows (when the
 * page has those sections), and what it says about a scroll: the success rate (an ITEM STATS row whose label names
 * SUCCESS, else "Success rate: N%" in the description) and the "+N" stat bonuses (ITEM STATS rows valued "+N", else
 * the description). Nothing the text does not show is filled in: an absent value is null / {}. Two sources on one page
 * that disagree are an error.
 */
function kuroItemPage(id, j, meta) {
  const p = {
    ...meta, kuro_item_id: String(j.kuro_item_id ?? ''), url: j.url, read_at: j.read_at, method: j.method ?? null,
    site_updated_label: j.site_updated_label ?? null, text: j.text,
  };
  requireReadAt(p, meta.file);
  if (p.kuro_item_id !== id) throw new Error(`kuro_item_id ${JSON.stringify(j.kuro_item_id)} differs from the file name item_${id}.json`);
  if (p.url !== `https://playkuro.com/database/#items/${id}`) throw new Error(`URL ${JSON.stringify(p.url)} is not KuroDB's page of item ${id}`);
  if (typeof j.text !== 'string') throw new Error('text (the rendered page) is missing');
  const lines = j.text.split('\n').map((s) => s.trim()).filter(Boolean);
  const hm = /^ITEM\s*·\s*(\d+)$/.exec(lines[0] ?? '');
  if (!hm) throw new Error(`the page text must start with "ITEM · ${id}", got ${JSON.stringify(lines[0] ?? '')}`);
  if (hm[1] !== id) throw new Error(`the page says ITEM · ${hm[1]}, the file is item ${id}`);
  p.name = lines[1] ?? null;
  if (!p.name || KURO_ITEM_HEADINGS.some((re) => re.test(p.name))) throw new Error('no item name after the "ITEM · <id>" line');
  const isHeading = (l) => KURO_ITEM_HEADINGS.some((re) => re.test(l));
  const sections = {};
  for (let i = 2; i < lines.length; i++) {
    if (!isHeading(lines[i])) continue;
    const key = /^REACTOR DROPS/.test(lines[i]) ? 'REACTOR DROPS' : lines[i];
    if (sections[key]) throw new Error(`section ${lines[i]} appears twice`);
    const j2 = lines.findIndex((l, k) => k > i && isHeading(l));
    sections[key] = { heading: lines[i], lines: lines.slice(i + 1, j2 < 0 ? lines.length : j2) };
  }
  p.sections = Object.keys(sections);
  p.category = sections.CATEGORY?.lines[0] ?? null;
  p.description = sections.DESCRIPTION ? sections.DESCRIPTION.lines.join('\n') : null;
  // ITEM STATS: "LABEL" then its value; a line that is not part of such a pair is kept as is.
  p.stats = [];
  p.stats_unpaired = [];
  const st = sections['ITEM STATS']?.lines ?? [];
  for (let i = 0; i < st.length; i++) {
    if (KURO_STAT_LABEL.test(st[i]) && i + 1 < st.length && !KURO_STAT_LABEL.test(st[i + 1])) {
      p.stats.push({ label: st[i], value: st[i + 1] });
      i++;
    } else {
      p.stats_unpaired.push(st[i]);
    }
  }
  // The scroll facts: success rate and "+N" bonuses, from the stats rows or else the description.
  const rateRow = p.stats.find((s) => /SUCCESS/.test(s.label));
  const rateFromStats = rateRow ? (/^(\d+(?:\.\d+)?)\s*%$/.exec(rateRow.value)?.[1] ?? null) : null;
  if (rateRow && rateFromStats == null) throw new Error(`ITEM STATS ${rateRow.label} is not a percentage: ${JSON.stringify(rateRow.value)}`);
  const rateFromText = successRateIn(p.description);
  if (rateFromStats != null && rateFromText != null && Number(rateFromStats) !== rateFromText) {
    throw new Error(`the success rate differs between ITEM STATS (${rateFromStats}%) and the description (${rateFromText}%)`);
  }
  p.success_rate = rateFromStats != null ? { pct: Number(rateFromStats), raw: `${rateRow.label}: ${rateRow.value}`, source: 'item stats' }
    : rateFromText != null ? { pct: rateFromText, raw: /success\s*rate[^,\n]*/i.exec(p.description)[0], source: 'description' } : null;
  const fromStats = {};
  for (const s of p.stats) {
    const b = /^\+\s*(\d+)$/.exec(s.value);
    if (b) fromStats[statKey(s.label)] = Number(b[1]);
  }
  const fromText = statBonusesIn(p.description);
  if (Object.keys(fromStats).length && Object.keys(fromText).length && JSON.stringify(sortKeys(fromStats)) !== JSON.stringify(sortKeys(fromText))) {
    throw new Error(`the stat bonuses differ between ITEM STATS ${JSON.stringify(fromStats)} and the description ${JSON.stringify(fromText)}`);
  }
  const bonuses = Object.keys(fromStats).length ? fromStats : fromText;
  p.stat_bonuses = sortKeys(bonuses);
  p.stat_bonuses_source = Object.keys(fromStats).length ? 'item stats' : Object.keys(fromText).length ? 'description' : null;
  // Drop rows, in the same forms as the reactor item pages.
  p.monster_drops = [];
  const md = sections['MONSTER DROPS']?.lines ?? [];
  const mdLines = md.length === 1 && /^No monster drop is recorded\.$/.test(md[0]) ? [] : md;
  for (const [monster, raw] of pairs(mdLines, `${p.name} monster drops`)) {
    const q = parseKuroPercent(raw);
    p.monster_drops.push({ monster_name: monster, raw, pct: q.percent, probability: q.probability, qty: q.qty, quest: q.quest, kuro_monster_id: q.source_id,
      maps: q.maps ?? null, excludes: q.excludes ?? [] });
  }
  p.reactor_drops = [];
  if (sections['REACTOR DROPS']) {
    for (const [reactor, raw] of pairs(sections['REACTOR DROPS'].lines, `${p.name} reactor drops`)) {
      const r = /^Reactor (\d+)$/.exec(reactor);
      if (!r) throw new Error(`${p.name}: expected "Reactor N", got ${JSON.stringify(reactor)}`);
      const q = parseReactorChanceValue(raw);
      p.reactor_drops.push({ reactor_id: r[1], raw, raw_n: q.raw_n, probability: q.probability, quest: q.quest });
    }
    const n = Number(/\((\d+)\)/.exec(sections['REACTOR DROPS'].heading)[1]);
    if (p.reactor_drops.length !== n) throw new Error(`${p.name}: "${sections['REACTOR DROPS'].heading}" but ${p.reactor_drops.length} rows`);
  }
  return p;
}

const sortKeys = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));

// --- MeowDB -----------------------------------------------------------------------------------------------------

/** Value line after a label line ("HP" then "45"), or null. */
function after(lines, label) {
  const i = lines.indexOf(label);
  return i >= 0 && i + 1 < lines.length ? lines[i + 1] : null;
}

const toInt = (v) => (v != null && /^-?\d+$/.test(v) ? Number(v) : null);
const COMMUNITY_CATEGORIES = new Set(['ETC', 'USE', 'EQUIPMENT', 'SETUP', 'CASH']);

/**
 * Community-voted drop groups: "<CATEGORY>\n<n>\n" then n x (name, subtype, "▲", up, "▼", down).
 * `lines` start right after the section's intro text. Stops at the first line that is not a category header.
 */
function communityDrops(lines) {
  const out = [];
  let i = 0;
  while (i < lines.length && COMMUNITY_CATEGORIES.has(lines[i]) && /^\d+$/.test(lines[i + 1] ?? '')) {
    const category = lines[i];
    const n = Number(lines[i + 1]);
    i += 2;
    for (let k = 0; k < n; k++, i += 6) {
      const [name, subtype, up, upv, down, downv] = lines.slice(i, i + 6);
      if (up !== '▲' || down !== '▼' || toInt(upv) == null || toInt(downv) == null) throw new Error(`community drop ${JSON.stringify(name)} is not "name, subtype, ▲, n, ▼, n"`);
      out.push({ category, name, subtype, upvotes: Number(upv), downvotes: Number(downv), score: Number(upv) - Number(downv) });
    }
  }
  return { drops: out, next: i };
}

/** Read-only MSEA reference groups: "<CATEGORY>\n<n>\n" then n x (name, subtype). */
function mseaDrops(lines) {
  const out = [];
  let i = 0;
  while (i < lines.length && COMMUNITY_CATEGORIES.has(lines[i]) && /^\d+$/.test(lines[i + 1] ?? '')) {
    const category = lines[i];
    const n = Number(lines[i + 1]);
    i += 2;
    for (let k = 0; k < n; k++, i += 2) out.push({ category, name: lines[i], subtype: lines[i + 1] });
  }
  return out;
}

function sectionAfter(lines, startPred, skipPred) {
  let i = lines.findIndex(startPred);
  if (i < 0) return null;
  i++;
  while (i < lines.length && skipPred(lines[i])) i++;
  return lines.slice(i);
}

function meowdbMonster(id, raw, meta) {
  const isText = raw.header != null;
  const url = isText ? raw.header.url : raw.url;
  const readAt = isText ? raw.header.read_at : raw.read_at;
  const fullText = isText ? raw.body : `${raw.head}\n${raw.drops}`;
  const lines = fullText.split('\n').map((s) => s.trim()).filter(Boolean);
  const m = { ...meta, monster_id: id, url, read_at: readAt, method: isText ? raw.header.method : raw.method ?? null };
  requireReadAt(m, meta.file);
  m.name = after(lines, '/');
  const speed = /\(speed (-?\d+)\)/.exec(after(lines, 'SPEED') ?? '');
  const mp = lines.map((l) => /^MP (\d+)$/.exec(l)).find(Boolean);
  m.stats = {
    level: toInt(after(lines, 'LEVEL')), hp: toInt(after(lines, 'HP')), exp: toInt(after(lines, 'EXP')),
    accuracy: toInt(after(lines, 'ACC')), touch_damage: after(lines, 'TOUCH DMG'), speed: speed ? Number(speed[1]) : null,
    speed_text: after(lines, 'SPEED'), movement: after(lines, 'MOVEMENT'), mp: mp ? Number(mp[1]) : null,
  };
  // Meso: the header block ("MESOS PER KILL" then "2" / "No meso reports yet.") and the report line further down.
  const header = after(lines, 'MESOS PER KILL');
  const reportLine = lines.find((l) => /^Mesos: .* per kill/.test(l)) ?? null;
  const none = lines.find((l) => /^No mesos? reports yet/.test(l)) ?? null;
  m.meso = {
    header_text: header, report_text: reportLine ?? none,
    report: reportLine ? parseMeowdbMesoReport(reportLine) : { raw: none, state: 'none', min: null, max: null, reports: 0 },
  };
  const drops = sectionAfter(lines, (l) => l === 'Drops (MS Classic)', (l) => /^(Community sourced|Items players have personally seen|Track a grind here)/.test(l));
  m.community_drops = drops ? communityDrops(drops).drops : [];
  const msea = sectionAfter(lines, (l) => l === 'MSEA reference drops', (l) => /^(Read-only|Classic World appears)/.test(l));
  m.msea_reference = msea ? mseaDrops(msea) : [];
  // Map rows: "<map><region>\t<count>\t<share>\t<types>\t<rate>\t<respawn>" (tabs kept in the raw lines).
  const rawRows = isText ? raw.body.split('\n') : raw.maple_island_map_rows || [];
  m.map_rows = rawRows.filter((l) => l.split('\t').length === 6 && /^\d+$/.test(l.split('\t')[1])).map((l) => {
    const [where, count, share, types, rate, respawn] = l.split('\t');
    const region = ['Maple Road', 'Rainbow Street'].find((r) => where.endsWith(r)) ?? null;
    return { raw: l, map_name: region ? where.slice(0, -region.length) : where, region, count: Number(count), share, types: toInt(types), mob_rate: rate, respawn };
  });
  m.text = fullText;
  return m;
}

function meowdbBreakable(id, raw, meta) {
  const lines = raw.body.split('\n').map((s) => s.trim()).filter(Boolean);
  const b = { ...meta, breakable_id: id, url: raw.header.url, read_at: raw.header.read_at, method: raw.header.method ?? null };
  requireReadAt(b, meta.file);
  b.name = after(lines, '/');
  const hits = lines.map((l) => /breaks in (\d+) hits/.exec(l)).find(Boolean);
  b.hits_to_break = hits ? Number(hits[1]) : null;
  const drops = sectionAfter(lines, (l) => l === 'DROPS (MS CLASSIC)', (l) => /^(Community sourced|Items players have personally seen)/.test(l));
  const cd = drops ? communityDrops(drops) : { drops: [], next: 0 };
  b.community_drops = cd.drops;
  const spawnAt = lines.indexOf('SPAWNS ON THESE MAPS');
  b.spawns = [];
  if (spawnAt >= 0) {
    for (let i = spawnAt + 1; i + 2 < lines.length; i += 3) {
      const [map, region, where] = lines.slice(i, i + 3);
      const s = /^×(\d+) · (\d+)s$/.exec(where ?? '');
      if (!s) break;
      b.spawns.push({ map_name: map, region, count: Number(s[1]), respawn_s: Number(s[2]), raw: `${map} | ${region} | ${where}` });
    }
  }
  b.text = raw.body;
  return b;
}

function meowdbQuest(id, raw, meta) {
  const lines = raw.body.split('\n').map((s) => s.trim()).filter(Boolean);
  const q = { ...meta, quest_id: id, url: raw.header.url, read_at: raw.header.read_at, method: raw.header.method ?? null, purpose: raw.header.purpose ?? null };
  requireReadAt(q, meta.file);
  q.name = lines[0] ?? null;
  q.summary = lines[1] ?? null;
  const exp = lines.map((l) => /^(\d+) EXP$/.exec(l)).find(Boolean);
  q.reward_exp = exp ? Number(exp[1]) : null;
  q.random_rewards = lines.map((l) => /^(.+) x(\d+) (\d+(?:\.\d+)?)%$/.exec(l)).filter(Boolean).map((r) => ({ name: r[1], qty: Number(r[2]), share_pct_text: r[3], raw: r[0] }));
  q.text = raw.body;
  return q;
}

/** Row labels of an item page's card (each followed by its value line), as tools/meowdb/extract_items.mjs knows them. */
export const ITEM_PAGE_ROWS = new Set(['HP Recovery', 'MP Recovery', 'NPC Sell-back', 'NPC Sell-back (per unit)', 'Max per Stack', 'Recharge Cost']);
/** Tags an item page's card shows as a line of their own. */
export const ITEM_PAGE_TAGS = new Set(['Tradeable', 'Untradeable', 'Male + Female', 'Male only', 'Female only']);
/** Section headings of an item page (the card ends at the first one). */
const ITEM_PAGE_SECTIONS = [/^Where to buy$/, /^Dropped By$/, /^MSEA Reference Drops$/, /^Quest Reward$/, /^Needed By$/,
  /^Found in Breakables$/, /^Craftable/, /^Change history$/];

/**
 * An item page's rendered text ("item_<id>.txt"), trimmed to the record by the person who read it. Only what the text
 * shows is parsed: the heading, the "<type> · <subtype> · No. <id>" line, the card's value rows (ITEM_PAGE_ROWS) and
 * tags, the one description line, and the sections present (Dropped By, MSEA Reference Drops, the Change history
 * label). A section the trimmed text leaves out is absent (`sections`), never read as empty. Every row value must be
 * a number ("+30", "3 mesos", "100"), the page number must be the file's id, the URL must be the item's page, and the
 * MSEA count line must match the monsters listed; anything else in the card is an error.
 */
function meowdbItemPage(id, raw, meta) {
  const lines = raw.body.split('\n').map((s) => s.trim()).filter(Boolean);
  const p = { ...meta, item_id: id, url: raw.header.url, read_at: raw.header.read_at, method: raw.header.method ?? null, purpose: raw.header.purpose ?? null };
  requireReadAt(p, meta.file);
  if (p.url !== `https://meowdb.com/msclassic/item-db/${id}`) throw new Error(`URL ${JSON.stringify(p.url)} is not the page of item ${id}`);
  p.name = after(lines, '/');
  const hi = lines.findIndex((l) => /^.+ · No\. \d+$/.test(l));
  if (hi < 0) throw new Error('no "<type> · <subtype> · No. <id>" line');
  const hm = /^(.+?)(?: · (.+?))? · No\. (\d+)$/.exec(lines[hi]);
  p.type = hm[1];
  p.subtype = hm[2] ?? null;
  p.number = hm[3];
  if (Number(p.number) !== Number(id)) throw new Error(`the page says No. ${p.number}, the file is item ${id}`);
  const isSection = (l) => ITEM_PAGE_SECTIONS.some((re) => re.test(l));
  let end = lines.findIndex((l, i) => i > hi && isSection(l));
  if (end < 0) end = lines.length;
  p.rows = {};
  p.tags = [];
  const description = [];
  for (let i = hi + 1; i < end; i++) {
    const l = lines[i];
    if (ITEM_PAGE_ROWS.has(l)) {
      const v = lines[i + 1];
      const n = /^[+-]?([\d,]+)(?: mesos)?$/.exec(v ?? '');
      if (i + 1 >= end || !n) throw new Error(`row ${JSON.stringify(l)} has no numeric value (got ${JSON.stringify(v)})`);
      if (p.rows[l]) throw new Error(`row ${JSON.stringify(l)} appears twice`);
      p.rows[l] = { label: l, raw: v, value: Number(v.replace(/[^\d-]/g, '')) };
      i++;
    } else if (ITEM_PAGE_TAGS.has(l)) p.tags.push(l);
    else description.push(l);
  }
  if (description.length > 1) throw new Error(`the card has lines no reader knows: ${JSON.stringify(description)}`);
  p.description = description[0] ?? null;
  // Sections: each heading's lines up to the next heading.
  p.sections = [];
  const body = {};
  for (let i = end; i < lines.length; i++) {
    if (!isSection(lines[i])) continue;
    const j = lines.findIndex((l, k) => k > i && isSection(l));
    body[lines[i]] = lines.slice(i + 1, j < 0 ? lines.length : j);
    p.sections.push(lines[i]);
  }
  const dropped = body['Dropped By'];
  p.community_drops_none = dropped ? dropped.includes('No drops reported yet.') : null;
  p.msea_reference = null;
  const msea = body['MSEA Reference Drops'];
  if (msea) {
    const cm = /^Read-only · (\d+) monsters?$/.exec(msea[0] ?? '');
    if (!cm) throw new Error(`MSEA Reference Drops: expected "Read-only · N monster(s)", got ${JSON.stringify(msea[0])}`);
    p.msea_reference = pairs(msea.slice(1), 'MSEA Reference Drops').map(([monster, lv]) => {
      const m = /^Lv (\d+)$/.exec(lv);
      if (!m) throw new Error(`MSEA Reference Drops: ${JSON.stringify(monster)} has no "Lv N" line (got ${JSON.stringify(lv)})`);
      return { monster_name: monster, monster_level: Number(m[1]), raw: `${monster} | ${lv}` };
    });
    if (p.msea_reference.length !== Number(cm[1])) throw new Error(`MSEA Reference Drops: "${msea[0]}" but ${p.msea_reference.length} monsters listed`);
  }
  const ch = body['Change history'];
  p.change_history_label = ch ? ch[0] ?? null : null;
  p.text = raw.body;
  return p;
}

function meowdbQuestTracker(raw, meta) {
  const t = { ...meta, url: raw.header.url, read_at: raw.header.read_at, read_at_note: raw.header.read_at_note ?? null, method: raw.header.method ?? null, purpose: raw.header.purpose ?? null };
  requireReadAt(t, meta.file);
  const lines = raw.body.split('\n');
  t.quests = lines.map((l) => /^\s*(.+?)\s{2,}(?:Level \d+ · )?\S.* · Maple Island · /.exec(l)).filter(Boolean).map((m) => m[1].trim());
  const result = lines.find((l) => l.startsWith('RESULT:'));
  t.result = result ? lines.slice(lines.indexOf(result)).join(' ').replace(/\s+/g, ' ').trim() : null;
  t.text = raw.body;
  return t;
}

/** "2026-10-05 ~08:17Z" in the capture's method text -> "2026-10-05T08:17Z" (approximate: a session time). */
function sessionReadAt(method) {
  const m = /(\d{4}-\d{2}-\d{2})\s+~?(\d{2}:\d{2})Z/.exec(method || '');
  return m ? { read_at: `${m[1]}T${m[2]}Z`, basis: m[0] } : null;
}

function meowdbItemsApi(j, meta) {
  const session = sessionReadAt(j.method);
  const out = { ...meta, url: null, read_at: null, method: j.method ?? null, search_results: j.search_results ?? {}, conclusions: j.conclusions ?? {}, items: {} };
  for (const [id, it] of Object.entries(j.items || {})) {
    const own = it.read_at ?? null;
    const one = {
      file: meta.file, authority: meta.authority, item_id: String(id), url: it.url, body: it.body,
      read_at: own ?? session?.read_at ?? null, read_at_approximate: own == null,
      read_at_note: own == null && session ? `approximate: the capture records only the reading session, "${session.basis}" (method text), not a per-item time` : null,
    };
    requireReadAt(one, `${meta.file} item ${id}`);
    if (!one.body || String(one.body.id) !== String(id)) throw new Error(`item ${id}: body id ${one.body?.id} differs`);
    out.items[id] = one;
  }
  return out;
}
