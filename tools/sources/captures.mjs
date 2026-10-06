// Offline loader for the dated, hand-read source captures (Iteration Three decisions D3-1, D3-2, D3-11):
//
//   tools/meowdb/captures/       MeowDB MS Classic pages re-read in a normal browser (monster, breakable, quest and item
//                                pages, the quest tracker) and item API bodies (items_api.json)
//   tools/henesys/captures/      Henesys.gg item rarity labels (item_rarity.json), read by hand: the rarity of each
//                                drop-list item, used only for the property "rarity" (decision D3-11)
//
// Reads the files only; it never touches the network. Every file in those folders is loaded (README.md files are
// documentation and skipped); an unrecognised file is an error, so a new capture cannot be silently ignored. Every
// capture must carry an ISO 8601 read time (see isIsoTimestamp); items_api.json records only a session time in its
// "method" text, which is derived explicitly and flagged read_at_approximate.
//
//   import { loadCaptures } from '../sources/captures.mjs';
//   const c = loadCaptures();
//   c.meowdb.monsters['2'].community_drops[0]   // {category: "ETC", name: "Bronze Ore", subtype: "Ore & Mineral", upvotes: 16, ...}
//   c.meowdb.monsters['2'].meso.report          // {raw: "Mesos: 2 per kill | 1 report", min: 2, max: 2, reports: 1, ...}
//   c.meowdb.item_pages['242'].rows['Max per Stack']   // {label: "Max per Stack", raw: "100", value: 100}
//   c.henesys.rarity.items['Snail Shell']       // {name: "Snail Shell", rarity: "Common", row: "Snail Shell | Monster Drop | ... | Common"}
//
// Every capture object has {file (repo-relative, forward slashes), authority, url, read_at, method, sha256}.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { parseMeowdbMesoReport, isIsoTimestamp } from './parse.mjs';

export const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

/** Authority names; they must match game/scripts/core/validation/provenance_authorities.gd REGISTRY. */
export const AUTHORITIES = { meowdb: 'MeowDB MS Classic', henesys: 'Henesys.gg' };
export const CAPTURE_DIRS = { meowdb: 'tools/meowdb/captures', henesys: 'tools/henesys/captures' };

/** Henesys.gg's rarity labels, lowest first (decision D3-11: the drop chance table's columns). */
export const RARITY_LABELS = Object.freeze(['Common', 'Rare', 'Very Rare', 'Extremely Rare']);
/** The page the rarity labels were read on. */
export const HENESYS_LOOT_URL = 'https://henesys.gg/loot';

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
    henesys: { rarity: null },
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

/**
 * Two captures of one page (monster_2.json and monster_2.txt): the newest dated one is the page (decision D3-11, "the
 * newest dated source wins"), never the one the file name sorts last. The same read time twice cannot be ordered and
 * is an error. The older capture stays a loaded file (`files`); `superseded` lists it.
 */
function keepNewest(map, id, cap) {
  const prev = map[id];
  if (!prev) {
    map[id] = cap;
    return;
  }
  const a = Date.parse(prev.read_at);
  const b = Date.parse(cap.read_at);
  if (a === b) throw new Error(`${cap.file}: a second capture of ${cap.url} with the same read_at as ${prev.file}; keep one`);
  const [newer, older] = b > a ? [cap, prev] : [prev, cap];
  map[id] = newer;
  newer.superseded = [...(newer.superseded ?? []), ...(older.superseded ?? []), older.file].sort();
}

function requireReadAt(obj, where) {
  if (!isIsoTimestamp(obj.read_at)) throw new Error(`${where}: read_at ${JSON.stringify(obj.read_at)} is not an ISO 8601 timestamp with a zone`);
}

function loadOne(out, site, name, text, meta) {
  if (site === 'henesys') {
    if (name === 'item_rarity.json') {
      out.henesys.rarity = henesysRarity(JSON.parse(text), meta);
      return;
    }
  } else if (site === 'meowdb') {
    let m;
    if ((m = /^monster_(\d+)\.(json|txt)$/.exec(name))) {
      keepNewest(out.meowdb.monsters, m[1], meowdbMonster(m[1], m[2] === 'json' ? JSON.parse(text) : textCapture(text), meta));
      return;
    }
    if ((m = /^breakable_(\d+)\.txt$/.exec(name))) {
      keepNewest(out.meowdb.breakables, m[1], meowdbBreakable(m[1], textCapture(text), meta));
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

// --- Henesys.gg -------------------------------------------------------------------------------------------------

/**
 * tools/henesys/captures/item_rarity.json: Henesys.gg's rarity label per item name, read by hand in a normal browser
 * (the page's own search box over the list it loads once; no scraping). {site, url, read_at, method, scope,
 * site_notice, rarity_labels_seen, items: {<name>: {row, rarity, note?}}}. Checked: the URL is the loot page, read_at
 * is an ISO time, every rarity is one of RARITY_LABELS, every row starts with the item's name and each of its
 * " | "-separated rows (several rows with one name are joined by "  /  ") ends with that label. Returns
 * {..meta, url, read_at, method, site_notice, items: {<name>: {name, rarity, row, note}}}.
 */
function henesysRarity(j, meta) {
  const r = { ...meta, url: j.url, read_at: j.read_at, method: j.method ?? null, scope: j.scope ?? null, site_notice: j.site_notice ?? null, items: {} };
  requireReadAt(r, meta.file);
  if (r.url !== HENESYS_LOOT_URL) throw new Error(`url ${JSON.stringify(r.url)} is not ${HENESYS_LOOT_URL}`);
  if (!r.site_notice) throw new Error('site_notice (the terms of the site: private use only) is missing');
  for (const [name, it] of Object.entries(j.items ?? {})) {
    if (!RARITY_LABELS.includes(it?.rarity)) throw new Error(`${name}: rarity ${JSON.stringify(it?.rarity)} is not one of ${RARITY_LABELS.join(', ')}`);
    const row = String(it.row ?? '');
    if (!row.startsWith(name + ' | ')) throw new Error(`${name}: row ${JSON.stringify(row)} does not start with the item's name`);
    for (const part of row.split('  /  ').filter((p) => p.includes(' | '))) {
      const label = part.split(' | ').pop().trim();
      if (label !== it.rarity) throw new Error(`${name}: a row reads ${JSON.stringify(label)}, the rarity is ${it.rarity}`);
    }
    r.items[name] = { name, rarity: it.rarity, row, note: it.note ?? null };
  }
  if (!Object.keys(r.items).length) throw new Error('no items');
  return r;
}

// --- MeowDB -----------------------------------------------------------------------------------------------------

function pairs(list, what) {
  if (list.length % 2 !== 0) throw new Error(`${what}: lines do not pair up (${list.length})`);
  const out = [];
  for (let i = 0; i < list.length; i += 2) out.push([list[i], list[i + 1]]);
  return out;
}

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
