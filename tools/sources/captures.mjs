// Offline loader for the dated, hand-read source captures (Iteration Three decisions D3-1..D3-8):
//
//   tools/meowdb/captures/       MeowDB MS Classic pages re-read in a normal browser (monster, breakable and quest pages,
//                                the quest tracker) and item API bodies (items_api.json)
//   tools/kurodb/captures/       KuroDB monster pages and reactor item pages (drop and meso probabilities only)
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
    meowdb: { monsters: {}, breakables: {}, items_api: null, quests: {}, quest_tracker: null },
    kurodb: { monsters: {}, reactor_items: null },
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
    if (/^\d+\.json$/.test(name)) {
      const m = kuroMonster(JSON.parse(text), meta);
      out.kurodb.monsters[m.kuro_monster_id] = m;
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
