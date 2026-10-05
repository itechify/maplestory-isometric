// Extract the 21 Maple Island NPCs (+ their dialogue) from MeowDB MS Classic into game/data/canonical/npcs/<id>.json.
//
//   node tools/meowdb/extract_npcs.mjs            # runs from tools/meowdb/.cache (cache-first, deterministic)
//
// Pages read (all cache-first through lib.mjs):
//   /maps/<id>                 x 25  NPC ids + px positions on each Maple Island map; speech-bubble preview lines
//   /npcs/<id>                 x 21  name, role tags, function title, location, "What X Says" dialogue + idle chatter,
//                                    quests given / turned in, shop link + shop item ids, "What They Do"
//   /npcs/all                        category the NPC index files each NPC under (cross-check of role)
//   /npc-shops                       shop slug <-> npcId / mapId / item ids (cross-check of the NPC page shop block)
//   /quest-tracker/<id>        x 20  quest start/complete NPC + the "NPC Dialogue" states (accept / completion / quiz)
//   /guides/beginners-guide-first-steps-in-maple-world   Shanks' boat (destination, fare, level, one-way)
//   /world-map                       map id of Lith Harbor (Shanks' destination)
//
// The structured data lives in the Next.js flight payload as a React element tree split across lazily referenced rows
// ("$L4a"). This script resolves those references into one tree and walks it. No images are fetched or stored.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchPage as libFetchPage, rsc, valuesForKey, firstValue, pageText, source, writeJson } from './lib.mjs';

// Every page goes through lib.mjs (cache-first, globally rate-limited). Count real network fetches so a re-run can be
// confirmed to have worked purely from tools/meowdb/.cache.
let networkFetches = 0;
async function fetchPage(p) {
  const res = await libFetchPage(p);
  if (!res.fromCache) networkFetches++;
  return res;
}

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const OUT_DIR = path.join(ROOT, 'game', 'data', 'canonical', 'npcs');

// The 25 classic Maple Island maps (Iteration One island), MeowDB 9-digit map ids.
const MAP_IDS = [
  '000000001', '000000010', '000000020', '000000021', '000000030', '000000040', '000000041', '000000042', '000000050',
  '000000060', '000000061', '000001000', '000001001', '000001002', '000001003', '000001004', '000001005', '000001006',
  '000001010', '000001011', '000001012', '000001013', '000001014', '000001020', '000001021',
];
const GUIDE_PATH = '/guides/beginners-guide-first-steps-in-maple-world';

// ---------------------------------------------------------------------------------------------------------------
// Flight payload -> resolved React element tree
// ---------------------------------------------------------------------------------------------------------------

/** Split a decoded flight payload into rows: id -> {raw} (one-line JSON / import) or {text} (T-rows, length-prefixed). */
function parseRows(r) {
  const rows = new Map();
  let i = 0;
  while (i < r.length) {
    const m = /^([0-9a-f]+):/.exec(r.slice(i, i + 12));
    if (!m) {
      const nl = r.indexOf('\n', i);
      if (nl < 0) break;
      i = nl + 1;
      continue;
    }
    const id = m[1];
    const j = i + m[0].length;
    if (r[j] === 'T') {
      const comma = r.indexOf(',', j);
      const len = parseInt(r.slice(j + 1, comma), 16);
      const text = Buffer.from(r.slice(comma + 1), 'utf8').subarray(0, len).toString('utf8');
      rows.set(id, { text });
      i = comma + 1 + text.length;
      continue;
    }
    const nl = r.indexOf('\n', j);
    rows.set(id, { raw: r.slice(j, nl < 0 ? r.length : nl) });
    i = nl < 0 ? r.length : nl + 1;
  }
  return rows;
}

/** Build a resolver over a page: get(rowId) returns the row value with every "$L.."/"$.." row reference inlined. */
function flight(html) {
  const rows = parseRows(rsc(html));
  const cache = new Map();
  const get = (id) => {
    if (cache.has(id)) return cache.get(id);
    const row = rows.get(id);
    if (!row) return undefined;
    let v;
    if ('text' in row) v = row.text;
    else if (/^[[{"0-9tfn-]/.test(row.raw)) {
      try { v = JSON.parse(row.raw); } catch { v = row.raw; }
    } else v = { $import: row.raw };
    cache.set(id, v); // break cycles
    v = resolve(v, 0);
    cache.set(id, v);
    return v;
  };
  const resolve = (v, d) => {
    if (d > 80) return v;
    if (typeof v === 'string') {
      const m = /^\$L?([0-9a-f]+)$/.exec(v);
      return m && rows.has(m[1]) ? get(m[1]) : v;
    }
    if (Array.isArray(v)) {
      // Element tuples ["$", type, key, props]: keep the type (a component reference like "$L29") unresolved.
      if (v[0] === '$' && typeof v[1] === 'string') return v.map((x, k) => (k === 1 ? x : resolve(x, d + 1)));
      return v.map((x) => resolve(x, d + 1));
    }
    if (v && typeof v === 'object') {
      const o = {};
      for (const k of Object.keys(v)) o[k] = resolve(v[k], d + 1);
      return o;
    }
    return v;
  };
  /** Resolved value of the first row whose raw text satisfies pred. */
  const findRow = (pred) => {
    for (const [id, row] of rows) if (row.raw && pred(row.raw)) return get(id);
    return undefined;
  };
  return { rows, get, findRow };
}

const isEl = (n) => Array.isArray(n) && n[0] === '$' && typeof n[1] === 'string';
const cls = (el) => (isEl(el) && typeof el[3]?.className === 'string' ? el[3].className : '');
const kids = (el) => (isEl(el) ? el[3]?.children : undefined);

/** Depth-first walk over elements (children and object-valued props). fn(el) returning false stops descent. */
function walk(n, fn) {
  if (isEl(n)) {
    if (fn(n) === false) return;
    const props = n[3] || {};
    if (props.children !== undefined) walk(props.children, fn);
  } else if (Array.isArray(n)) for (const x of n) walk(x, fn);
}
function findAll(n, pred) {
  const out = [];
  walk(n, (el) => { if (pred(el)) out.push(el); });
  return out;
}
function text(n) {
  if (n == null || n === false || n === true) return '';
  if (typeof n === 'string') return /^\$[A-Za-z]/.test(n) ? '' : n;
  if (typeof n === 'number') return String(n);
  if (isEl(n)) return n[1] === 'br' ? '\n' : text(kids(n));
  if (Array.isArray(n)) return n.map(text).join('');
  return '';
}

/** A "section card": the element whose children start with an h2 (or a header div holding an h2). */
function sections(root) {
  const out = [];
  walk(root, (el) => {
    const ch = kids(el);
    if (!Array.isArray(ch) || !ch.length) return;
    const first = ch[0];
    if (isEl(first) && first[1] === 'h2') out.push({ title: text(first), el, body: ch.slice(1) });
    else if (isEl(first) && first[1] === 'div' && Array.isArray(kids(first)) && isEl(kids(first)[0]) && kids(first)[0][1] === 'h2')
      out.push({ title: text(kids(first)[0]), header: first, el, body: ch.slice(1) });
  });
  return out;
}

// ---------------------------------------------------------------------------------------------------------------
// Rich text (dialogue lines) -> {text, segments}
// ---------------------------------------------------------------------------------------------------------------

function parseHref(href) {
  const m = /^\/msclassic\/(npcs|maps|item-db|monsters|quest-tracker)\/([0-9]+)$/.exec(href);
  if (!m) return { kind: 'link', href };
  const kind = { npcs: 'npc', maps: 'map', 'item-db': 'item', monsters: 'monster', 'quest-tracker': 'quest' }[m[1]];
  return { kind, id: m[2] };
}

/**
 * Convert a rendered dialogue node into a line. MeowDB renders MapleStory script markup as: bold spans
 * ("font-semibold"), red spans ("text-rose-400"), links to NPC/map/item/monster pages, inline item icons and <br>.
 * opts.skip(el) excludes sub-trees (quiz options nested inside other options).
 */
function richLine(node, { itemRefs = {}, skip = () => false } = {}) {
  const segs = [];
  const push = (t, style) => {
    if (!t) return;
    const last = segs[segs.length - 1];
    const same = last && !last.ref && !style.ref && !!last.bold === !!style.bold && (last.color || null) === (style.color || null);
    if (same) last.text += t;
    else segs.push({ text: t, ...style });
  };
  const go = (n, style) => {
    if (n == null || n === false || n === true) return;
    if (typeof n === 'string') return push(/^\$[A-Za-z]/.test(n) ? '' : n, style);
    if (typeof n === 'number') return push(String(n), style);
    if (Array.isArray(n) && !isEl(n)) return n.forEach((x) => go(x, style));
    if (!isEl(n) || skip(n)) return;
    const [, type, , props = {}] = n;
    if (type === 'br') return push('\n', style);
    if (type === 'img') return; // icons are proprietary art; never stored
    // A link keeps the emphasis of the span it sits in: MeowDB wraps linked names in the same bold
    // ("font-semibold") / red ("text-rose-400") spans as plain words (e.g. quest 1000 "Sera", quest 1009 "Blue Snail").
    if (props.href) return push(text(props.children), { ...style, ref: parseHref(props.href) });
    const c = cls(n);
    if (c.startsWith('inline-flex items-baseline')) {
      // inline item icon + name (MapleStory #i/#t); MeowDB item id comes from the page's itemRefs table
      const name = text(n);
      const ref = itemRefs[name] ? { kind: 'item', id: String(itemRefs[name].id) } : { kind: 'item', id: null };
      return push(name, { ...style, ref });
    }
    const next = { ...style };
    if (/\bfont-semibold\b/.test(c)) next.bold = true;
    if (/\btext-rose-400\b/.test(c)) next.color = 'red';
    go(props.children, next);
  };
  go(node, {});
  // trim the line ends (leading/trailing whitespace only)
  while (segs.length && !segs[0].ref && !segs[0].text.trimStart()) segs.shift();
  while (segs.length && !segs[segs.length - 1].ref && !segs[segs.length - 1].text.trimEnd()) segs.pop();
  if (segs.length && !segs[0].ref) segs[0].text = segs[0].text.trimStart();
  if (segs.length && !segs[segs.length - 1].ref) segs[segs.length - 1].text = segs[segs.length - 1].text.trimEnd();
  const line = { text: segs.map((s) => s.text).join('') };
  if (segs.some((s) => s.bold || s.color || s.ref)) {
    line.segments = segs.map((s) => {
      const o = { text: s.text };
      if (s.bold) o.bold = true;
      if (s.color) o.color = s.color;
      if (s.ref) o.ref = s.ref;
      return o;
    });
  }
  return line;
}

// ---------------------------------------------------------------------------------------------------------------
// Page parsers
// ---------------------------------------------------------------------------------------------------------------

async function loadMaps() {
  const maps = [];
  for (const id of MAP_IDS) {
    const p = await fetchPage('/maps/' + id);
    const r = rsc(p.html);
    const map = firstValue(r, 'map', (v) => v && v.id === id);
    const npcs = valuesForKey(r, 'npcs').find((v) => Array.isArray(v)) || [];
    const talkers = valuesForKey(r, 'talkers')[0] || [];
    maps.push({ id, name: map?.name ?? null, url: p.url, retrieved_at: p.retrieved_at, npcs, talkers });
  }
  return maps;
}

async function loadIndexCategories() {
  const p = await fetchPage('/npcs/all');
  const { rows, get } = flight(p.html);
  const out = {}; // npcId -> category (the <section key="..."> the index lists the NPC under)
  for (const id of rows.keys()) {
    const v = get(id);
    if (typeof v !== 'object' || v === null) continue;
    walk(v, (el) => {
      if (el[1] !== 'section' || !el[2]) return;
      walk(kids(el), (x) => {
        const mm = /^\/msclassic\/npcs\/(\d+)$/.exec(x[3]?.href || '');
        if (mm && !(mm[1] in out)) out[mm[1]] = el[2];
      });
      return false;
    });
  }
  return { url: p.url, retrieved_at: p.retrieved_at, categories: out };
}

async function loadShops() {
  const p = await fetchPage('/npc-shops');
  const r = rsc(p.html);
  // shop objects are {"slug": ..., "npcId": ..., "items": [...]}; collect those carrying an npcId
  const out = [];
  const needle = '{"slug":"';
  let i = 0;
  while ((i = r.indexOf(needle, i)) >= 0) {
    try {
      const v = JSON.parse(extractObject(r, i));
      if (v && typeof v.npcId === 'number') out.push(v);
    } catch { /* not a plain object */ }
    i += needle.length;
  }
  return { url: p.url, retrieved_at: p.retrieved_at, shops: out };
}

/** Balanced-brace slice of the JSON object starting at s[i]. */
function extractObject(s, i) {
  let depth = 0, inStr = false;
  for (let j = i; j < s.length; j++) {
    const c = s[j];
    if (inStr) { if (c === '\\') j++; else if (c === '"') inStr = false; continue; }
    if (c === '"') inStr = true;
    else if (c === '{' || c === '[') depth++;
    else if (c === '}' || c === ']') { depth--; if (depth === 0) return s.slice(i, j + 1); }
  }
  throw new Error('unterminated object');
}

async function loadNpcPage(id) {
  const p = await fetchPage('/npcs/' + id);
  const { findRow } = flight(p.html);
  const root = findRow((raw) => raw.startsWith('["$","div"') && raw.includes('"children":"NPC Database"'));
  if (!root) throw new Error('npc page root not found: ' + id);
  const h1 = findAll(root, (el) => el[1] === 'h1')[0];
  const name = text(h1);
  // header block: h1, optional italic subtitle (function title), role tag spans
  const header = findAll(root, (el) => el[1] === 'div' && Array.isArray(kids(el)) && kids(el)[0] === h1)[0];
  const subtitle = findAll(header, (el) => el[1] === 'p' && /\bitalic\b/.test(cls(el)))[0];
  const roles = findAll(header, (el) => el[1] === 'span' && el[2] && /inline-flex items-center whitespace-nowrap/.test(cls(el))).map((el) => text(el));
  const bubble = findAll(root, (el) => Array.isArray(el[3]?.lines))[0]?.[3].lines ?? [];

  const secs = sections(root);
  const sec = (re) => secs.find((s) => re.test(s.title));

  // Location(s)
  const locations = [];
  const loc = sec(/^Location$/);
  if (loc) {
    walk(loc.body, (el) => {
      if (el[1] === 'div' && /^\d{9}$/.test(el[2] || '')) {
        const link = findAll(el, (x) => x[3]?.href === '/msclassic/maps/' + el[2])[0];
        const street = findAll(el, (x) => x[1] === 'span' && /text-maple-faint ml-2/.test(cls(x)))[0];
        locations.push({ map_id: el[2], map_name: text(link), street_name: street ? text(street) : null });
        return false;
      }
    });
  }

  // "What X Says": blockquotes (d0, d1, ...) = dialogue; <li key="c#"> = idle chatter
  const says = sec(/^What .+ Says$/);
  const dialogue = says ? findAll(says.body, (el) => el[1] === 'blockquote').map((el) => richLine(kids(el))) : [];
  const chatter = says ? findAll(says.body, (el) => el[1] === 'li' && /^c\d+$/.test(el[2] || '')).map((el) => richLine(kids(el))) : [];
  const hasIdleHeading = says ? findAll(says.body, (el) => el[1] === 'h3' && text(el) === 'Idle chatter').length > 0 : false;

  const questLinks = (s) => (s ? findAll(s.body, (el) => /^\/msclassic\/quest-tracker\/\d+$/.test(el[3]?.href || '')).map((el) => ({
    id: el[3].href.split('/').pop(),
    name: text(findAll(el, (x) => x[1] === 'div' && /\btext-sm\b/.test(cls(x)))[0]),
  })) : []);
  const given = questLinks(sec(/^Quests Given/));
  const turnedIn = questLinks(sec(/^Quests Turned In/));

  // Shop block (rendered as <section> with an h2 "Shop inventory (N items)")
  let shop = null;
  const shopSec = findAll(root, (el) => el[1] === 'section' && /^Shop inventory/.test(text(findAll(el, (x) => x[1] === 'h2')[0])))[0];
  if (shopSec) {
    const heading = text(findAll(shopSec, (x) => x[1] === 'h2')[0]);
    const link = findAll(shopSec, (x) => /^\/msclassic\/npc-shops#/.test(x[3]?.href || ''))[0];
    const items = findAll(shopSec, (x) => x[1] === 'tr' && /^\d+-\d+$/.test(x[2] || '')).map((tr) => {
      const a = findAll(tr, (x) => /^\/msclassic\/item-db\/\d+$/.test(x[3]?.href || ''))[0];
      return { item_id: a[3].href.split('/').pop(), name: text(a) };
    });
    const soldAt = findAll(shopSec, (x) => /^\/msclassic\/maps\/\d{9}$/.test(x[3]?.href || ''))[0];
    shop = {
      shop_id: link[3].href.split('#')[1],
      heading,
      sold_at_map_id: soldAt ? soldAt[3].href.split('/').pop() : null,
      items,
    };
  }

  const what = sec(/^What They Do$/);
  const whatTheyDo = what ? findAll(what.body, (el) => el[1] === 'li').map((el) => text(el)) : [];

  return { id, url: p.url, retrieved_at: p.retrieved_at, html: p.html, name, function_title: subtitle ? text(subtitle) : null, roles, bubble, locations, dialogue, chatter, hasIdleHeading, given, turnedIn, shop, whatTheyDo };
}

/** Parse one quest page: quest object + its "NPC Dialogue" sections. */
async function loadQuest(qid) {
  const p = await fetchPage('/quest-tracker/' + qid);
  const r = rsc(p.html);
  const quest = firstValue(r, 'quest', (v) => v && v.id === qid);
  if (!quest) throw new Error('quest object not found ' + qid);
  const itemRefs = firstValue(r, 'itemRefs') || {};
  const placements = firstValue(r, 'npcPlacements') || {};
  const { findRow } = flight(p.html);
  const dlgRoot = findRow((raw) => raw.includes('"children":"NPC Dialogue"'));
  const blocks = [];
  if (dlgRoot) {
    const isOption = (el) => el[1] === 'span' && /^block ml-/.test(cls(el));
    const cards = findAll(dlgRoot, (el) => el[1] === 'div' && /^bg-maple-surface border border-maple-border rounded-xl p-4/.test(cls(el)));
    for (const card of cards) {
      const ch = kids(card);
      const headerDiv = ch[0];
      const section = text(findAll(headerDiv, (x) => x[1] === 'h2')[0]);
      const badge = findAll(headerDiv, (x) => x[1] === 'span' && x[3]?.title)[0];
      const rest = ch.slice(1);
      // branch boxes: "mt-3/mt-4 rounded-lg border ..." with a label div + lines
      const branchEls = findAll(rest, (el) => el[1] === 'div' && /^mt-[34] rounded-lg border/.test(cls(el)));
      const inBranch = new Set();
      for (const b of branchEls) walk(b, (x) => { inBranch.add(x); });
      // quiz question container
      const quizEl = findAll(rest, (el) => el[1] === 'div' && cls(el) === 'text-sm text-maple-text leading-relaxed' && findAll(el, isOption).length > 0)[0]
        || findAll(rest, (el) => el[1] === 'div' && cls(el) === 'text-sm text-maple-text leading-relaxed')[0];
      const inQuiz = new Set();
      if (quizEl) walk(quizEl, (x) => { inQuiz.add(x); });
      const mainLines = findAll(rest, (el) => el[1] === 'p' && !inBranch.has(el) && !inQuiz.has(el)).map((el) => richLine(kids(el), { itemRefs }));
      const branches = branchEls.map((b) => {
        const bch = kids(b);
        const label = text(bch[0]);
        const lineEls = findAll(bch.slice(1), (x) => x[1] === 'p' || x[1] === 'li');
        return { key: b[2] ?? null, label, lines: lineEls.map((x) => richLine(kids(x), { itemRefs })) };
      });
      let quiz = null;
      if (quizEl) {
        const qch = kids(quizEl);
        const firstOpt = qch.findIndex((x) => isEl(x) && isOption(x));
        const question = richLine(firstOpt >= 0 ? qch.slice(0, firstOpt) : qch, { itemRefs });
        const options = [];
        const notes = [];
        for (const opt of findAll(quizEl, isOption)) {
          const [labelSpan, content, marker] = kids(opt);
          void labelSpan;
          const line = richLine(content, { itemRefs, skip: (x) => x !== opt && isOption(x) });
          const correct = !!marker && text(marker).includes('Correct answer');
          // MeowDB occasionally leaves a raw selection marker ("#L2 # 5 points") inside the previous option's text.
          const raw = /#L(\d+)\s*#/.exec(line.text);
          if (raw) {
            const before = line.text.slice(0, raw.index).trim();
            const after = line.text.slice(raw.index + raw[0].length).trim();
            options.push({ text: before, correct });
            options.push({ text: after, correct: false, malformed_markup: raw[0] });
            notes.push(`MeowDB renders the option "${after}" with an unparsed selection marker "${raw[0]}" inside the previous option; split here.`);
          } else options.push({ ...line, correct });
        }
        const marked = options.filter((o) => o.correct).length;
        if (marked === 0) {
          for (const o of options) o.correct = null;
          notes.push('MeowDB marks no option as the correct answer for this question.');
        }
        quiz = { question, options, correct_option_index: marked === 1 ? options.findIndex((o) => o.correct) : null };
        if (notes.length) quiz.notes = notes;
      }
      blocks.push({ section, badge: badge ? text(badge) : null, lines: mainLines, branches, quiz });
    }
  }
  return { id: qid, url: p.url, retrieved_at: p.retrieved_at, html: p.html, quest, itemRefs, placements, blocks };
}

/** Item page header (cache-first): MeowDB name + icon key, read from the page's header icon alt/src text. */
const itemPages = new Map();
async function itemPage(id) {
  if (!itemPages.has(id)) {
    const p = await fetchPage('/item-db/' + id);
    const m = /"src":"\/msclassic\/api\/assets\/icons\/([^"]+)","alt":"((?:[^"\\]|\\.)*) icon - MapleStory Classic"/.exec(rsc(p.html));
    if (!m) throw new Error('item page header not found for ' + id);
    itemPages.set(id, { url: p.url, retrieved_at: p.retrieved_at, icon_key: m[1], name: JSON.parse('"' + m[2] + '"') });
  }
  return itemPages.get(id);
}

/**
 * Quest-dialogue item links are sometimes resolved by name to a different item-db entry than the quest's own item
 * (same name, different icon key). When the quest page's itemRefs table names an item with the same (singular) name
 * and that item's icon key matches itemRefs, use the itemRefs id and record both values as a discrepancy.
 */
async function reconcileItemLinks(entry, q, discrepancies) {
  const refIds = new Set(Object.values(q.itemRefs).map((v) => String(v.id)));
  // same name, allowing the dialogue's plural ("Shellpieces" for "Shellpiece")
  const sameName = (n, t) => [n, n + 's', n + 'es'].map((x) => x.toLowerCase()).includes(t.trim().toLowerCase());
  const segs = [];
  walk2(entry, (v) => { if (v && v.ref && v.ref.kind === 'item' && v.ref.id && !refIds.has(v.ref.id)) segs.push(v); });
  const done = new Set();
  for (const seg of segs) {
    const twinName = Object.keys(q.itemRefs).find((n) => sameName(n, seg.text));
    if (!twinName) continue;
    const twin = q.itemRefs[twinName];
    const twinId = String(twin.id);
    const linked = await itemPage(seg.ref.id);
    const own = await itemPage(twinId);
    if (own.icon_key !== String(twin.iconKey) || linked.name !== own.name || linked.icon_key === own.icon_key) continue;
    const linkId = seg.ref.id;
    seg.ref = { kind: 'item', id: twinId, meowdb_link_id: linkId };
    if (done.has(linkId)) continue;
    done.add(linkId);
    discrepancies.push({
      field: `quest_dialogue/${entry.quest_id}/${entry.npc_role} item reference "${seg.text}"`,
      values: [
        { url: q.url, where: 'quest page itemRefs (quest item data)', value: twinId },
        { url: q.url, where: `NPC dialogue link "${seg.text}"`, value: linkId },
      ],
      chosen: twinId,
      reason: `item-db ${twinId} ("${own.name}", icon key ${own.icon_key}) is the item the quest page's itemRefs table uses (icon key ${twin.iconKey}); item-db ${linkId} is a different entry with the same name (icon key ${linked.icon_key}), so the dialogue link appears to be resolved by name. segments[].ref.meowdb_link_id keeps the linked id.`,
      sources: [{ url: own.url, retrieved_at: own.retrieved_at }, { url: linked.url, retrieved_at: linked.retrieved_at }],
    });
  }
}

async function loadShanksRoute() {
  const g = await fetchPage(GUIDE_PATH);
  const { rows, get } = flight(g.html);
  let sentence = null;
  for (const [id, row] of rows) {
    if (!row.raw || !row.raw.includes('Shanks at the dock')) continue;
    walk(get(id), (el) => {
      if (!sentence && el[1] === 'li' && text(el).includes('Shanks at the dock')) sentence = text(el);
    });
  }
  if (!sentence) throw new Error('Shanks sentence not found in guide');
  const m = /Shanks at the dock sails you to ([A-Z][A-Za-z ]+?) for ([\d,]+) mesos once you reach level (\d+)\. (The boat is one-way\.)/.exec(sentence);
  if (!m) throw new Error('Shanks sentence changed: ' + sentence);
  const quote = sentence.slice(sentence.indexOf('Shanks at the dock'));
  const w = await fetchPage('/world-map');
  const spot = valuesForKey(rsc(w.html), 'spots').flat().find((s) => s && s.title === m[1]);
  return {
    guide: { url: g.url, retrieved_at: g.retrieved_at },
    world: { url: w.url, retrieved_at: w.retrieved_at },
    quote,
    destination_name: m[1],
    destination_map_id: spot ? spot.mapId : null,
    fare_mesos: Number(m[2].replace(/,/g, '')),
    min_level: Number(m[3]),
    one_way: true,
  };
}

// ---------------------------------------------------------------------------------------------------------------
// Assemble
// ---------------------------------------------------------------------------------------------------------------

const norm = (s) => s.replace(/\s+/g, ' ').trim();
const squash = (s) => s.replace(/\s+/g, ''); // page-text cross-check ignores whitespace (pageText splits at every tag)

async function main() {
  const maps = await loadMaps();
  // NPC ids present on the 25 maps, in numeric order
  const placements = new Map(); // npcId -> [{map, x, y, name}]
  for (const m of maps) for (const n of m.npcs) {
    if (!placements.has(n.id)) placements.set(n.id, []);
    placements.get(n.id).push({ map: m, x: n.x, y: n.y, name: n.name });
  }
  const npcIds = [...placements.keys()].sort((a, b) => Number(a) - Number(b));

  const index = await loadIndexCategories();
  const shopsPage = await loadShops();
  const shanks = await loadShanksRoute();

  const npcPages = new Map();
  for (const id of npcIds) npcPages.set(id, await loadNpcPage(id));

  // every quest any of these NPCs gives or takes
  const questIds = new Set();
  for (const p of npcPages.values()) for (const q of [...p.given, ...p.turnedIn]) questIds.add(q.id);
  const quests = new Map();
  for (const q of [...questIds].sort((a, b) => Number(a) - Number(b))) quests.set(q, await loadQuest(q));

  const report = { discrepancies: [], checks: [], referenced: { quests: new Set(), shops: new Set(), items: new Set(), npcs: new Set(), maps: new Set(), monsters: new Set() } };
  const collectRefs = (obj) => walk2(obj, (v) => {
    if (v && typeof v === 'object' && v.kind && v.id) {
      const bucket = { npc: 'npcs', map: 'maps', item: 'items', monster: 'monsters', quest: 'quests' }[v.kind];
      if (bucket) report.referenced[bucket].add(v.id);
    }
  });

  fs.mkdirSync(OUT_DIR, { recursive: true });
  for (const f of fs.readdirSync(OUT_DIR)) if (f.endsWith('.json') && !npcIds.includes(f.replace(/\.json$/, ''))) fs.rmSync(path.join(OUT_DIR, f));

  for (const id of npcIds) {
    const p = npcPages.get(id);
    const fieldSources = {};
    const gaps = [];
    const notes = [];
    const discrepancies = [];
    const text_ = pageText(p.html);

    // --- locations: map/street from the NPC page, px position from the map page
    const locations = p.locations.map((l) => {
      const pl = placements.get(id).find((x) => x.map.id === l.map_id);
      if (!pl) discrepancies.push(`NPC page lists map ${l.map_id} but that map page has no placement for NPC ${id}.`);
      else {
        fieldSources[`locations/${l.map_id}`] = { url: pl.map.url, retrieved_at: pl.map.retrieved_at, fields: ['x_px', 'y_px'] };
        if (pl.map.name !== l.map_name) discrepancies.push(`Map name differs: NPC page "${l.map_name}" vs map page "${pl.map.name}" (${l.map_id}); kept the NPC page value.`);
        if (pl.name !== p.name) discrepancies.push(`Name differs: NPC page "${p.name}" vs map page "${pl.name}"; kept the NPC page value.`);
      }
      return { map_id: l.map_id, map_name: l.map_name, street_name: l.street_name, x_px: pl ? pl.x : null, y_px: pl ? pl.y : null };
    });
    for (const pl of placements.get(id)) {
      if (!p.locations.some((l) => l.map_id === pl.map.id)) discrepancies.push(`Map page ${pl.map.id} places NPC ${id} but the NPC page does not list that map.`);
      // map-page speech-bubble preview must be a prefix of the NPC page's idle chatter
      const t = pl.map.talkers.find((x) => x.name === p.name);
      if (t) {
        const chatter = p.chatter.map((c) => c.text);
        const prefix = t.lines.every((l, k) => norm(l) === norm(chatter[k] || ''));
        report.checks.push(`map ${pl.map.id} talker preview for ${p.name}: ${t.lines.length} line(s), prefix of NPC page chatter: ${prefix}`);
        if (!prefix) discrepancies.push(`Map page ${pl.map.id} speech-bubble lines are not a prefix of the NPC page idle chatter.`);
      }
    }

    // --- role cross-check against the NPC index
    const category = index.categories[id] ?? null;
    if (!category || !p.roles.includes(category)) discrepancies.push(`NPC index files ${p.name} under "${category}" but the NPC page role tags are ${JSON.stringify(p.roles)}.`);
    report.checks.push(`index category for ${id} ${p.name}: ${category}; page roles ${p.roles.join('/')}`);

    // --- quests
    const startedHere = [];
    const completedHere = [];
    for (const q of quests.values()) {
      const start = q.quest.npc;
      const complete = q.quest.completeNpc ?? q.quest.npc;
      if (start === p.name) startedHere.push(q.id);
      if (complete === p.name) completedHere.push(q.id);
    }
    for (const g of p.given) {
      const q = quests.get(g.id);
      if (q.quest.name !== g.name) discrepancies.push(`Quest ${g.id} is "${g.name}" on the NPC page but "${q.quest.name}" on its quest page; kept the quest page name in quest_dialogue.`);
      if (q.quest.npc !== p.name) discrepancies.push(`NPC page lists quest ${g.id} as given, but the quest page's NPC is "${q.quest.npc}".`);
    }
    for (const t of p.turnedIn) {
      const q = quests.get(t.id);
      if (q.quest.name !== t.name) discrepancies.push(`Quest ${t.id} is "${t.name}" on the NPC page but "${q.quest.name}" on its quest page.`);
      if ((q.quest.completeNpc ?? q.quest.npc) !== p.name) discrepancies.push(`NPC page lists quest ${t.id} as turned in here, but the quest page's completion NPC is "${q.quest.completeNpc ?? q.quest.npc}".`);
    }
    for (const qid of startedHere) if (!p.given.some((g) => g.id === qid)) discrepancies.push(`Quest page ${qid} names ${p.name} as its NPC but the NPC page does not list it under Quests Given.`);
    for (const q of [...p.given, ...p.turnedIn]) report.referenced.quests.add(q.id);

    // --- quest dialogue: "On accept" goes to the start NPC, "On completion" to the completion NPC
    const questDialogue = [];
    for (const qid of [...new Set([...startedHere, ...completedHere])].sort((a, b) => Number(a) - Number(b))) {
      const q = quests.get(qid);
      const start = q.quest.npc;
      const complete = q.quest.completeNpc ?? q.quest.npc;
      for (const b of q.blocks) {
        const role = b.section === 'On accept' ? 'start' : b.section === 'On completion' ? 'complete' : null;
        if (role === null) { discrepancies.push(`Unknown dialogue section "${b.section}" on quest ${qid}.`); continue; }
        if ((role === 'start' ? start : complete) !== p.name) continue;
        const npcIdOf = (name) => (q.placements[name] ? String(q.placements[name].npcId) : null);
        const entry = {
          quest_id: qid,
          quest_name: q.quest.name,
          npc_role: role,
          start_npc_id: npcIdOf(start),
          complete_npc_id: npcIdOf(complete),
          section: b.section,
          lines: b.lines,
          branches: b.branches,
          quiz: b.quiz,
        };
        if (start !== complete && role === 'complete' && b.branches.some((x) => x.key === 'stopNpc' || x.key === 'lost')) {
          entry.notes = [`MeowDB files every branch of this quest's completion dialogue under "On completion" without naming a speaker. Start NPC (${start}, id ${npcIdOf(start)}) and completion NPC (${complete}, id ${npcIdOf(complete)}) differ; the stopNpc / lost branch texts read as if spoken by the start NPC. Unverified: MeowDB does not say.`];
        }
        questDialogue.push(entry);
        fieldSources[`quest_dialogue/${qid}/${role}`] = { url: q.url, retrieved_at: q.retrieved_at };
        await reconcileItemLinks(entry, q, discrepancies);
        collectRefs(entry);
      }
      for (const sectionName of ['On accept', 'On completion']) {
        const who = sectionName === 'On accept' ? start : complete;
        if (who === p.name && !q.blocks.some((b) => b.section === sectionName))
          gaps.push(`Quest ${qid} (${q.quest.name}): MeowDB shows no "${sectionName}" dialogue.`);
      }
      for (const b of q.blocks) {
        const who = b.section === 'On accept' ? start : complete;
        if (who === p.name && b.lines.length === 0 && !b.quiz)
          gaps.push(`Quest ${qid} (${q.quest.name}) "${b.section}": MeowDB shows no main lines, only conditional branches (${b.branches.map((x) => x.label).join('; ') || 'none'}).`);
        if (who === p.name && b.quiz && b.quiz.correct_option_index === null)
          gaps.push(`Quest ${qid} (${q.quest.name}) quiz: MeowDB does not mark the correct option (see quest_dialogue quiz.notes).`);
      }
    }

    // --- shop
    let shop = null;
    if (p.shop) {
      const s = shopsPage.shops.find((x) => x.slug === p.shop.shop_id);
      if (!s) discrepancies.push(`Shop slug ${p.shop.shop_id} not found on /npc-shops.`);
      else {
        if (String(s.npcId) !== id) discrepancies.push(`/npc-shops lists shop ${s.slug} under npcId ${s.npcId}, not ${id}.`);
        if (s.mapId !== p.shop.sold_at_map_id) discrepancies.push(`Shop ${s.slug}: /npc-shops mapId ${s.mapId} vs NPC page "Sold at" ${p.shop.sold_at_map_id}.`);
        const a = p.shop.items.map((x) => x.item_id).join(',');
        const b = (s.items || []).map((x) => String(x.itemId)).join(',');
        if (a !== b) discrepancies.push(`Shop ${s.slug}: item ids on the NPC page (${a}) differ from /npc-shops (${b}).`);
        if (s.npcFunction !== p.function_title) discrepancies.push(`Shop ${s.slug}: /npc-shops npcFunction "${s.npcFunction}" vs NPC page subtitle "${p.function_title}".`);
        fieldSources['shop'] = { url: shopsPage.url, retrieved_at: shopsPage.retrieved_at, note: 'cross-check only: shop_id, item_ids and sold_at_map_id are read from the NPC page and matched against this page (slug, npcId, mapId, items[].itemId)' };
      }
      shop = { shop_id: p.shop.shop_id, sold_at_map_id: p.shop.sold_at_map_id, item_ids: p.shop.items.map((x) => x.item_id), item_names: p.shop.items.map((x) => x.name) };
      report.referenced.shops.add(p.shop.shop_id);
      for (const it of p.shop.items) report.referenced.items.add(it.item_id);
      gaps.push('No distinct shop-open greeting is shown by MeowDB; the only lines are the ones in idle_chatter.');
    } else if (shopsPage.shops.some((x) => String(x.npcId) === id)) {
      discrepancies.push(`/npc-shops has a shop for NPC ${id} but the NPC page shows none.`);
    }

    // --- transport (Shanks)
    let transport = null;
    if (p.roles.includes('Transport')) {
      if (p.name === 'Shanks') {
        transport = {
          routes: [{
            from_map_id: locations[0]?.map_id ?? null,
            to_map_name: shanks.destination_name,
            to_map_id: shanks.destination_map_id,
            fare_mesos: shanks.fare_mesos,
            min_level: shanks.min_level,
            one_way: shanks.one_way,
            source_quote: shanks.quote,
          }],
        };
        fieldSources['transport'] = { url: shanks.guide.url, retrieved_at: shanks.guide.retrieved_at, fields: ['to_map_name', 'fare_mesos', 'min_level', 'one_way', 'source_quote'] };
        fieldSources['transport/to_map_id'] = { url: shanks.world.url, retrieved_at: shanks.world.retrieved_at };
        report.referenced.maps.add(shanks.destination_map_id);
        notes.push('Out of scope for Iteration Two gameplay: the boat leaves Maple Island (destination Lith Harbor, Victoria Island). Record only.');
        gaps.push('MeowDB has no structured transport data for Shanks: no boarding dialogue / Yes-No prompt text, no arrival map or spawn point, no travel time. Route facts come from the editorial beginner guide (prose), the map id from the world-map spot "Lith Harbor".');
      } else gaps.push('Transport NPC without route data.');
    }

    // --- dialogue notes / gaps
    if (p.dialogue.length === 0) gaps.push(`MeowDB shows no quoted dialogue for ${p.name}; "What ${p.name} Says" lists only the idle/speech-bubble lines.`);
    const bubble = JSON.stringify(p.bubble.map(norm));
    const chatterTexts = JSON.stringify(p.chatter.map((c) => norm(c.text)));
    if (bubble !== chatterTexts) discrepancies.push(`Speech-bubble "lines" prop differs from the idle chatter list on the NPC page.`);

    // --- verify every extracted text is visible on its page
    const pageSq = squash(text_);
    for (const l of [...p.dialogue, ...p.chatter]) if (!pageSq.includes(squash(l.text))) report.discrepancies.push(`self-check: text not found on page ${p.url}: ${l.text.slice(0, 60)}`);
    for (const e of questDialogue) {
      const qn = squash(pageText(quests.get(e.quest_id).html));
      const all = [...e.lines, ...e.branches.flatMap((b) => b.lines), ...(e.quiz ? [e.quiz.question, ...e.quiz.options] : [])];
      for (const l of all) if (!qn.includes(squash(l.text))) report.discrepancies.push(`self-check: text not found on quest page ${e.quest_id}: ${l.text.slice(0, 60)}`);
    }

    for (const l of [...p.dialogue, ...p.chatter]) collectRefs(l);
    report.referenced.npcs.add(id);

    const out = {
      id,
      name: p.name,
      roles: p.roles,
      function_title: p.function_title,
      locations,
      dialogue: p.dialogue,
      idle_chatter: p.chatter,
      quests: {
        given: p.given,
        turned_in: p.turnedIn,
        started_here: startedHere,
        completed_here: completedHere,
      },
      quest_dialogue: questDialogue,
      shop,
      transport,
      what_they_do: p.whatTheyDo,
      source: source(p.url, p.retrieved_at),
      field_sources: fieldSources,
    };
    if (notes.length) out.notes = notes;
    if (gaps.length) out.gaps = gaps;
    if (discrepancies.length) out.discrepancies = discrepancies.map((d) => (typeof d === 'string' ? { field: 'cross-check', detail: d } : d));
    report.discrepancies.push(...discrepancies.map((d) => `${id} ${p.name}: ${typeof d === 'string' ? d : d.field + ' -> chose ' + d.chosen}`));
    writeJson(path.join(OUT_DIR, id + '.json'), out);
  }

  // quest ids referenced inside dialogue but not given/taken by these NPCs are reported too (via collectRefs)
  for (const [k, v] of Object.entries(report.referenced)) report.referenced[k] = [...v].sort((a, b) => (Number(a) - Number(b)) || a.localeCompare(b));
  // npc ids referenced from dialogue that are not part of this domain
  const outside = report.referenced.npcs.filter((x) => !npcIds.includes(x));
  console.log(JSON.stringify({ network_fetches: networkFetches, npc_ids: npcIds, quest_ids: [...quests.keys()], referenced: report.referenced, npc_refs_outside_domain: outside, discrepancies: report.discrepancies, checks: report.checks.length }, null, 1));
  if (process.argv.includes('--checks')) console.log(report.checks.join('\n'));
  if (report.discrepancies.some((d) => d.startsWith('self-check'))) {
    console.error('self-check failed: some extracted text is not visible on its source page');
    process.exitCode = 1;
  }
}

/** Generic deep walk over plain JSON values. */
function walk2(v, fn) {
  fn(v);
  if (Array.isArray(v)) v.forEach((x) => walk2(x, fn));
  else if (v && typeof v === 'object') Object.values(v).forEach((x) => walk2(x, fn));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
