// The maplestory_io icon pack (format 1, defined in #49): which IDs it holds, what an answer means for a variant, and
// the next pack.json. Pure apart from wantedIds (reads game/data); fetch_pack.mjs does the fetching and the writing.
//
//   game/assets/icon_packs/maplestory_io/pack.json                            tracked
//   game/assets/icon_packs/maplestory_io/items/<game_item_id>/<variant>.png   git-ignored   (icon, iconRaw)
//   game/assets/icon_packs/maplestory_io/skills/<skill_id>/<variant>.png      git-ignored   (icon, iconMouseOver, iconDisabled)
//
// pack.json records the last successful fetch of each variant (url, sha256, size [w, h], origin [x, y] when the source
// gives one, fetched date) and, in `missing`, each variant maplestory.io answered does not exist (a 404, a blank 1x1
// image, a body that is not a PNG). A variant this run got no answer for keeps what the previous pack.json says, so a
// run without a network leaves the file as it was. A variant's `fetched` date changes only when its bytes change.
//
// maplestory.io appends a short trailer after a PNG's IEND chunk (00 dd 01, then JSON: a notice, the serving
// container, its git hash, the URL and the time the image was generated). The pack keeps the PNG itself, through IEND:
// the trailer changes whenever the server regenerates the image, so its sha256 and fetched date follow the picture,
// not the server. The cache keeps the answer as it came.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { SOURCE } from './lib.mjs';

export const FORMAT = 1;
export const PACK_NAME = 'maplestory_io';
export const ITEM_VARIANTS = ['icon', 'iconRaw'];
export const SKILL_VARIANTS = ['icon', 'iconMouseOver', 'iconDisabled'];
/** Per kind: its section in pack.json (and folder in the pack) and its variants, in pack.json order. */
export const KINDS = {
  item: { section: 'items', variants: ITEM_VARIANTS },
  skill: { section: 'skills', variants: SKILL_VARIANTS },
};
const ICON_KEYS = new Set(['item_icon_key', 'icon_key']);
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/** Shorter IDs first, then by text: numeric order for the zero-padded IDs the game uses. */
export const byId = (a, b) => a.length - b.length || (a < b ? -1 : a > b ? 1 : 0);

function jsonFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true })
    .flatMap((e) => (e.isDirectory() ? jsonFiles(path.join(dir, e.name)) : e.name.endsWith('.json') ? [path.join(dir, e.name)] : []))
    .sort();
}

/**
 * The IDs the game data refers to, never the whole catalogue: {items, skills}, each sorted and unique.
 *   items   every game_item_id in <dataDir>/canonical/items/*.json, plus every value of a key named exactly
 *           item_icon_key or icon_key anywhere under <dataDir> (quests, shops, formulas/attack_styles.json)
 *   skills  every skills[].skill_id of a <dataDir>/canonical/formulas/*.json (beginner.json today)
 */
export function wantedIds(dataDir) {
  const items = new Set();
  const skills = new Set();
  const read = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
  const idOf = (v) => (typeof v === 'string' || typeof v === 'number') && String(v).trim() !== '' ? String(v).trim() : null;
  for (const f of jsonFiles(path.join(dataDir, 'canonical', 'items'))) {
    const id = idOf(read(f).game_item_id);
    if (id) items.add(id);
  }
  const walk = (node) => {
    if (Array.isArray(node)) node.forEach(walk);
    else if (node && typeof node === 'object') {
      for (const [k, v] of Object.entries(node)) {
        const id = ICON_KEYS.has(k) ? idOf(v) : null;
        if (id) items.add(id);
        walk(v);
      }
    }
  };
  for (const f of jsonFiles(dataDir)) walk(read(f));
  for (const f of jsonFiles(path.join(dataDir, 'canonical', 'formulas'))) {
    const list = read(f).skills;
    for (const s of Array.isArray(list) ? list : []) {
      const id = idOf(s?.skill_id);
      if (id) skills.add(id);
    }
  }
  return { items: [...items].sort(byId), skills: [...skills].sort(byId) };
}

/**
 * The PNG at the start of `buf`: {width, height, png} with `png` the bytes through the IEND chunk (anything after it,
 * such as maplestory.io's trailer, left out), or null unless its chunks run whole from the signature and IHDR to IEND.
 */
export function pngImage(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 45 || !buf.subarray(0, 8).equals(PNG_SIGNATURE)) return null;
  if (buf.readUInt32BE(8) !== 13 || buf.toString('latin1', 12, 16) !== 'IHDR') return null;
  for (let p = 8; p + 12 <= buf.length;) {
    const end = p + 12 + buf.readUInt32BE(p);
    if (end > buf.length) return null;
    if (buf.toString('latin1', p + 4, p + 8) === 'IEND') return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20), png: buf.subarray(0, end) };
    p = end;
  }
  return null;
}

export const sha256 = (buf) => crypto.createHash('sha256').update(buf).digest('hex');

/**
 * What an answer (lib.mjs fetchAnswer) means for an icon variant:
 *   {state: 'ok', body, url, sha256, size, fetched}   a PNG larger than 1x1; `body` is the PNG through IEND and
 *                                                      `sha256` its hash; `fetched` is the UTC date it was fetched
 *   {state: 'gone', reason}                            maplestory.io says it does not exist: a 404, a blank 1x1 image,
 *                                                      a body that is not a PNG
 *   {state: 'none', reason}                            no answer this run
 */
export function judgeImage(answer) {
  if (answer.status === null) return { state: 'none', reason: answer.reason };
  if (answer.status !== 200) return { state: 'gone', reason: `http ${answer.status}` };
  const image = pngImage(answer.body);
  if (!image) return { state: 'gone', reason: `not a PNG (${answer.contentType || 'no content type'})` };
  if (image.width * image.height <= 1) return { state: 'gone', reason: `blank ${image.width}x${image.height} image` };
  return { state: 'ok', body: image.png, url: answer.url, sha256: sha256(image.png), size: [image.width, image.height],
    fetched: String(answer.retrieved_at).slice(0, 10) };
}

/**
 * The origins in an item's metadata answer: {icon: [x, y] | null, iconRaw: ...}, or null when the answer is missing.
 * maplestory.io answers 200 `null` for an unknown item; a body that is not an object, or an origin that is absent, not
 * numeric or marked isEmpty, gives no origin (#49: the icon is then centred).
 */
export function originsOf(answer) {
  if (answer.status === null) return null;
  let meta = null;
  if (answer.status === 200) {
    try {
      meta = JSON.parse(answer.body.toString('utf8'))?.metaInfo ?? null;
    } catch {
      meta = null;
    }
  }
  const pick = (o) => (o && typeof o === 'object' && !o.isEmpty && Number.isFinite(o.x) && Number.isFinite(o.y) ? [o.x, o.y] : null);
  return { icon: pick(meta?.iconOrigin), iconRaw: pick(meta?.iconRawOrigin) };
}

const variantKey = (kind, id, variant) => `${kind}/${id}/${variant}`;

/**
 * The next pack.json object: a pure function of the previous one (null for none), the wanted IDs ({items, skills})
 * and this run's outcomes (Map variantKey -> {state: 'ok', record} | {state: 'gone', reason} | {state: 'none'}; an
 * absent key is 'none'). An 'ok' record whose sha256 equals the previous one keeps the previous `fetched` date. IDs
 * the game data no longer names are dropped. A previous pack of another source or format counts as none.
 */
export function nextPack(prev, ids, outcomes) {
  const same = prev && prev.format === FORMAT && JSON.stringify(prev.source) === JSON.stringify(SOURCE);
  const before = same ? prev : { items: {}, skills: {}, missing: [] };
  const missingBefore = new Map((before.missing ?? []).map((m) => [variantKey(m.kind, m.id, m.variant), m]));
  const pack = { format: FORMAT, name: PACK_NAME, source: { ...SOURCE }, items: {}, skills: {}, missing: [] };
  for (const [kind, { section, variants }] of Object.entries(KINDS)) {
    for (const id of ids[section]) {
      for (const variant of variants) {
        const key = variantKey(kind, id, variant);
        const out = outcomes.get(key) ?? { state: 'none' };
        const old = before[section]?.[id]?.[variant];
        let record = null;
        if (out.state === 'ok') {
          record = { url: out.record.url, sha256: out.record.sha256, size: out.record.size };
          if (out.record.origin) record.origin = out.record.origin;
          record.fetched = old && old.sha256 === out.record.sha256 && old.fetched ? old.fetched : out.record.fetched;
        } else if (out.state === 'gone') {
          pack.missing.push({ kind, id, variant, reason: out.reason });
        } else if (old) {
          record = old;
        } else if (missingBefore.has(key)) {
          const m = missingBefore.get(key);
          pack.missing.push({ kind, id, variant, reason: m.reason });
        }
        if (record) (pack[section][id] ??= {})[variant] = record;
      }
    }
  }
  return pack;
}

/** One value on one line, with a space after each colon and comma. */
function inline(v) {
  if (Array.isArray(v)) return `[${v.map(inline).join(', ')}]`;
  if (v && typeof v === 'object') return `{${Object.entries(v).map(([k, x]) => `${JSON.stringify(k)}: ${inline(x)}`).join(', ')}}`;
  return JSON.stringify(v);
}

/**
 * pack.json text: fixed key order, IDs sorted, one line per variant and per missing entry, so a change to one variant
 * is a one-line diff. The same pack always gives the same bytes.
 */
export function stringifyPack(pack) {
  const L = ['{', `  "format": ${pack.format},`, `  "name": ${JSON.stringify(pack.name)},`, `  "source": ${inline(pack.source)},`];
  for (const { section, variants } of Object.values(KINDS)) {
    const ids = Object.keys(pack[section]).sort(byId);
    if (!ids.length) {
      L.push(`  "${section}": {},`);
      continue;
    }
    L.push(`  "${section}": {`);
    ids.forEach((id, i) => {
      const entry = pack[section][id];
      const names = variants.filter((v) => entry[v]);
      L.push(`    ${JSON.stringify(id)}: {`);
      names.forEach((v, j) => {
        const r = entry[v];
        const ordered = { url: r.url, sha256: r.sha256, size: r.size, ...(r.origin ? { origin: r.origin } : {}), fetched: r.fetched };
        L.push(`      ${JSON.stringify(v)}: ${inline(ordered)}${j < names.length - 1 ? ',' : ''}`);
      });
      L.push(`    }${i < ids.length - 1 ? ',' : ''}`);
    });
    L.push('  },');
  }
  const kindOrder = Object.keys(KINDS);
  const missing = [...pack.missing].sort((a, b) => kindOrder.indexOf(a.kind) - kindOrder.indexOf(b.kind) || byId(a.id, b.id)
    || KINDS[a.kind].variants.indexOf(a.variant) - KINDS[b.kind].variants.indexOf(b.variant));
  if (!missing.length) L.push('  "missing": []');
  else {
    L.push('  "missing": [');
    missing.forEach((m, i) => L.push(`    ${inline({ kind: m.kind, id: m.id, variant: m.variant, reason: m.reason })}${i < missing.length - 1 ? ',' : ''}`));
    L.push('  ]');
  }
  L.push('}');
  return L.join('\n') + '\n';
}

/** The PNG of a variant in a pack folder. */
export const pngPath = (packDir, kind, id, variant) => path.join(packDir, KINDS[kind].section, id, `${variant}.png`);

/** How many wanted IDs have every variant's PNG in the pack folder: {items, skills}. */
export function presentCounts(packDir, ids) {
  const count = (kind) => ids[KINDS[kind].section].filter((id) => KINDS[kind].variants.every((v) => fs.existsSync(pngPath(packDir, kind, id, v)))).length;
  return { items: count('item'), skills: count('skill') };
}

/**
 * The one line a run prints, e.g. "icons: 94/94 items, 3/3 skills present (maplestory.io MCW/CBT2)". An ID is present
 * when every variant's PNG is in the pack folder. Variants maplestory.io answered do not exist this run, and those
 * that got no answer, are added when there are any.
 */
export function summaryLine(present, ids, { gone = 0, none = 0, why = '' } = {}) {
  let line = `icons: ${present.items}/${ids.items.length} items, ${present.skills}/${ids.skills.length} skills present ` +
    `(${SOURCE.service} ${SOURCE.region}/${SOURCE.version})`;
  if (gone) line += `; ${gone} variant${gone === 1 ? '' : 's'} missing at ${SOURCE.service}`;
  if (none) line += `; ${none} variant${none === 1 ? '' : 's'} not reached${why ? ` (${why})` : ''}`;
  return line;
}
