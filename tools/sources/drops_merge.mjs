// Offline builder of the canonical schema 3 drop records (contract C1, docs/runtime/ITERATION_THREE_CONTRACTS.md;
// decisions D3-9, D3-11 and D3-12 in docs/ITERATION_LOG.md). Called by tools/meowdb/extract_monsters.mjs, the single
// writer of game/data/canonical/drops/<owner id>.json; it reads only local files and never touches the network.
//
//   what can drop    MeowDB's community list "Drops (MS Classic)" for the owner, ALL entries, in page order (D3-11).
//                    The newest dated source wins: the live page captures (tools/meowdb/captures/monster_<id>.*, the
//                    Wooden Box's breakable_0000001.txt; of two captures of one page the newer, captures.mjs) over the
//                    2026-10-04 cache. A cache read after the capture that names other members stops the build
//                    (re-capture the page). Votes are recorded, never used to exclude. MeowDB's "MSEA reference
//                    drops" list is kept in meowdb_reference, never a member.
//   which item       the member's name -> the one local item (game/data/canonical/items) with that name. Where several
//                    local items share the name, the item id MeowDB's own cached drop entry for this owner carries
//                    (/api/drops?monsterId=<id>, /api/breakable-drops?breakableId=<id>) decides, and the record says so.
//                    Every member the cached list also names must carry the same id there, or the build stops.
//   rarity           Henesys.gg's per-item label (tools/henesys/captures/item_rarity.json, read by hand; D3-11). A
//                    member Henesys.gg has no row for keeps rarity null: visible, unresolved, it never drops.
//   category         derived from the local MeowDB item's type and subtype plus the quest-gate rule (CHANCE_CATEGORIES
//                    below); the chance itself is the owner-approved table game/data/misostory/drop_rates.json
//                    (category x rarity), read at runtime. This record holds no probability.
//   quest gate       D3-9: MeowDB item subtype "Quest Item" AND exactly one Maple Island quest objective asks for it;
//                    the entry rolls only while that quest is in progress.
//   mesos            MeowDB's player reports where they exist (the newest dated of the live capture and the cached
//                    report API); otherwise null and the runtime's level formula applies (D3-12,
//                    game/data/misostory/meso_rules.json). A newer capture or cache with a report is used automatically.
//
// Fails hard (throws DropMergeError) on anything the captures and the local items do not support: an owner with no
// live capture or no cache, a cached drop entry whose item id differs from the member's local item, a member list
// category (ETC, USE, ...) that differs from the local item's type, a quest item two quests ask for.
//
//   import { buildDropRecords } from '../sources/drops_merge.mjs';
//   const { records } = buildDropRecords({ meowdbCache });   // {"1": {...}, ..., "0000001": {...}}
import fs from 'node:fs';
import path from 'node:path';
import { loadCaptures, REPO_ROOT, AUTHORITIES } from './captures.mjs';
import { entryKey, parseMeowdbMesoReport } from './parse.mjs';

export const SCHEMA_VERSION = 3;
export const RESOLUTION_STATES = ['resolved', 'ambiguous', 'not_in_snapshot'];
export const RESOLUTION_METHODS = ['exact_name', 'meowdb_drop_entry', 'none'];

/** The owners the records cover, in file order (contract C1). */
export const OWNER_IDS = ['1', '2', '3', '4', '5', '9', '0000001'];
/** Owner kind by id. */
export const OWNER_KINDS = { 1: 'monster', 2: 'monster', 3: 'monster', 4: 'monster', 5: 'monster', 9: 'monster', '0000001': 'breakable' };

/** The heading of the membership list on each kind of page. */
export const MEMBERSHIP_LIST = 'Drops (MS Classic)';

/**
 * The drop chance table's rows (decision D3-11; game/data/misostory/drop_rates.json holds a chance per row x rarity).
 * The rule, from the member's local MeowDB item (items/<id>.json type and subtype) and the D3-9 quest gate:
 *   etc_own_leftover  Etc, subtype "Monster Drop"
 *   etc_quest_gated   Etc, subtype "Quest Item", gated to a Maple Island quest (D3-9)
 *   etc_other         any other Etc (ores, gems, Monster Card, a quest item no Maple Island quest asks for)
 *   use_consumable    Use, any subtype but "Scroll" (potions, food, arrows)
 *   use_scroll        Use, subtype "Scroll"
 *   equip             any Equip
 *   setup             any Setup (chairs)
 * Any other type (Cash) has no category: the entry stays unresolved and never drops.
 */
export const CHANCE_CATEGORIES = Object.freeze(['etc_own_leftover', 'etc_quest_gated', 'etc_other', 'use_consumable', 'use_scroll', 'equip', 'setup']);

/** MeowDB's list group (the community list's category heading) -> the item record's type. */
const TYPE_BY_LIST_GROUP = { ETC: 'Etc', USE: 'Use', EQUIPMENT: 'Equip', SETUP: 'Setup', CASH: 'Cash' };

export const DROP_RATES_FILE = 'game/data/misostory/drop_rates.json';
export const MESO_RULES_FILE = 'game/data/misostory/meso_rules.json';

export class DropMergeError extends Error {
  constructor(message) {
    super(message);
    this.name = 'DropMergeError';
  }
}

const fail = (msg) => { throw new DropMergeError(msg); };
const byNumber = (a, b) => Number(a) - Number(b) || (a < b ? -1 : a > b ? 1 : 0);

// --- local data ----------------------------------------------------------------------------------------------

function readDomain(root, domain) {
  const dir = path.join(root, 'game', 'data', 'canonical', domain);
  const out = {};
  for (const f of fs.readdirSync(dir).filter((x) => x.endsWith('.json')).sort()) {
    const rec = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    out[String(rec.id ?? f.slice(0, -5))] = rec;
  }
  return out;
}

/** Local MeowDB items {id: record} (game/data/canonical/items). */
export function loadLocalItems({ root = REPO_ROOT } = {}) {
  return readDomain(root, 'items');
}

/** Local MeowDB quests {id: record} (game/data/canonical/quests: the Maple Island set). */
export function loadLocalQuests({ root = REPO_ROOT } = {}) {
  return readDomain(root, 'quests');
}

// --- rules ---------------------------------------------------------------------------------------------------

/**
 * The quest gate of a resolved member (D3-9): {quest_id, basis, rule, decision, verified} or null. Gated only when the
 * local MeowDB item's subtype is "Quest Item" AND exactly one Maple Island quest objective asks for it.
 */
export function deriveQuestGate(itemId, items, quests) {
  if (itemId == null) return null;
  const item = items[itemId];
  if (item?.subtype !== 'Quest Item') return null;
  const asking = Object.values(quests)
    .filter((q) => (q.region ?? 'Maple Island') === 'Maple Island')
    .map((q) => ({ q, need: (q.objectives?.item_collection ?? []).find((i) => String(i.item_id) === String(itemId)) }))
    .filter((x) => x.need)
    .sort((a, b) => Number(a.q.id) - Number(b.q.id));
  if (asking.length === 0) return null;
  if (asking.length > 1) fail(`item ${itemId}: quest item asked for by ${asking.map((x) => x.q.id).join(', ')}; the gate rule (D3-9) needs exactly one quest`);
  const { q, need } = asking[0];
  return {
    quest_id: String(q.id),
    basis: `MeowDB item subtype "Quest Item" (items/${itemId}.json); quest ${q.id} (${q.name}) asks for ${need.count ?? '?'} in objectives.item_collection, so the entry rolls only while ${q.id} is in progress.`,
    rule: 'quest-gate rule (contract C1, docs/runtime/ITERATION_THREE_CONTRACTS.md): a MisoStory derivation',
    decision: 'D3-9',
    verified: false,
  };
}

/** The table category of a local item under its quest gate (CHANCE_CATEGORIES), or null for a type the table lacks. */
export function deriveChanceCategory(item, gate) {
  if (!item) return null;
  switch (item.type) {
    case 'Etc':
      if (gate) return 'etc_quest_gated';
      return item.subtype === 'Monster Drop' ? 'etc_own_leftover' : 'etc_other';
    case 'Use':
      return item.subtype === 'Scroll' ? 'use_scroll' : 'use_consumable';
    case 'Equip':
      return 'equip';
    case 'Setup':
      return 'setup';
    default:
      return null;
  }
}

// --- MeowDB cache helpers ------------------------------------------------------------------------------------

/** MeowDB's own cached drop entries for an owner: name -> [{id, itemId, ...}]. */
function cachedEntriesByName(cache) {
  const out = new Map();
  for (const d of cache?.community?.drops ?? []) {
    if (!out.has(d.itemName)) out.set(d.itemName, []);
    out.get(d.itemName).push(d);
  }
  return out;
}

/** MeowDB's MSEA list from the live capture, each name given MeowDB's own id from the cached page (null if none/not local). */
function meowdbReference(live, cache, items) {
  const ids = new Map();
  for (const m of cache?.msea ?? []) {
    if (!ids.has(m.item_name)) ids.set(m.item_name, new Set());
    ids.get(m.item_name).add(String(m.item_id));
  }
  const idOf = (name) => {
    const set = ids.get(name);
    if (!set || set.size !== 1) return null;
    const id = [...set][0];
    return items[id] ? id : null;
  };
  return {
    note: 'MeowDB\'s read-only "MSEA reference drops" list from the live page: reference only, never a member (decision D3-11). item_id is MeowDB\'s own id for the name on the cached page (null when it does not name it once or no local item exists).',
    source: { authority: AUTHORITIES.meowdb, url: live.url, read_at: live.read_at, capture: live.file },
    msea_reference: (live.msea_reference ?? []).map((d) => ({ name: d.name, category: d.category, detail: d.subtype, item_id: idOf(d.name) })),
  };
}

/** Record-level discrepancy when the cached MeowDB community list (2026-10-04) and the live page differ by name. */
function communityListDiscrepancy(live, cache) {
  const cached = new Set((cache?.community?.drops ?? []).map((d) => d.itemName));
  const now = new Set(live.community_drops.map((d) => d.name));
  const gone = [...cached].filter((n) => !now.has(n)).sort();
  const added = [...now].filter((n) => !cached.has(n)).sort();
  if (!gone.length && !added.length) return null;
  return {
    field: 'entries (membership)',
    values: [
      { value: { only_in_cache: gone }, source: `${cache.community.url} (cache, retrieved ${cache.community.retrieved_at})` },
      { value: { only_on_live_page: added }, source: `${live.url} (live page, read ${live.read_at}; ${live.file})` },
    ],
    chosen: 'the live page (newest dated source, decision D3-11)',
    reason: 'MeowDB\'s community list changed between the cache and the hand-read live page; the membership is the newest dated list.',
  };
}

/** The member's block "<name>\n<subtype>\n▲\n<up>\n▼\n<down>" as the capture shows it; it must be verbatim there. */
function memberRawValue(live, d, where) {
  const raw = [d.name, d.subtype, '▲', String(d.upvotes), '▼', String(d.downvotes)].join('\n');
  const body = String(live.text).replace(/\r\n/g, '\n').split('\n').map((l) => l.trim()).join('\n');
  if (!body.includes(raw)) fail(`${where}: the "${d.name}" block is not verbatim in ${live.file}`);
  return raw;
}

// --- item resolution -----------------------------------------------------------------------------------------

/**
 * The local item a member names: {item_id, item_resolution: {state, method, candidates, evidence}}. `cached` is MeowDB's
 * own cached drop entries for this owner with the member's name ([] when the cache does not list it).
 */
export function resolveMemberItem(name, items, cached, cacheRef, where) {
  const local = Object.values(items).filter((it) => it.name === name).map((it) => String(it.id)).sort(byNumber);
  const cachedIds = [...new Set(cached.map((d) => String(d.itemId)))].sort(byNumber);
  const cacheText = cached.length
    ? `MeowDB's own drop entry for this owner (${cacheRef.url}, retrieved ${cacheRef.retrieved_at}; entry ${cached.map((d) => d.id).join(', ')}) carries item ${cachedIds.join(', ')}`
    : null;
  if (local.length === 1) {
    if (cachedIds.length && !(cachedIds.length === 1 && cachedIds[0] === local[0])) {
      fail(`${where}: the one local item named "${name}" is ${local[0]}, but ${cacheText}`);
    }
    return {
      item_id: local[0],
      item_resolution: {
        state: 'resolved', method: 'exact_name', candidates: local,
        evidence: `game/data/canonical/items/${local[0]}.json is the only local item named "${name}"${cacheText ? `; ${cacheText}, the same id` : ''}`,
      },
    };
  }
  if (local.length > 1) {
    if (cachedIds.length === 1 && local.includes(cachedIds[0])) {
      return {
        item_id: cachedIds[0],
        item_resolution: {
          state: 'resolved', method: 'meowdb_drop_entry', candidates: local,
          evidence: `${local.length} local items are named "${name}" (${local.join(', ')}); ${cacheText}, so the member is ${cachedIds[0]}`,
        },
      };
    }
    return {
      item_id: null,
      item_resolution: {
        state: 'ambiguous', method: 'none', candidates: local,
        evidence: `${local.length} local items are named "${name}" (${local.join(', ')}) and ${cacheText ?? 'MeowDB\'s cached drop list for this owner does not name it'}; nothing decides between them`,
      },
    };
  }
  return {
    item_id: null,
    item_resolution: {
      state: 'not_in_snapshot', method: 'none', candidates: cachedIds,
      evidence: `no local item is named "${name}"${cacheText ? `; ${cacheText}, not extracted (add it to tools/meowdb/extract_items.mjs ITEM_IDS)` : ''}`,
    },
  };
}

// --- builders ------------------------------------------------------------------------------------------------

function rarityOf(name, henesys) {
  const row = henesys.items[name];
  if (!row) return null;
  return {
    label: row.rarity,
    source: { authority: AUTHORITIES.henesys, url: henesys.url, read_at: henesys.read_at, capture: henesys.file, row: row.row },
  };
}

function buildEntry(ownerId, d, live, ctx, gaps) {
  const { items, quests, henesys, cachedByName, cacheRef } = ctx;
  const where = `drops/${ownerId} "${d.name}"`;
  const { item_id, item_resolution } = resolveMemberItem(d.name, items, cachedByName.get(d.name) ?? [], cacheRef, where);
  const item = item_id ? items[item_id] : null;
  const wantType = TYPE_BY_LIST_GROUP[d.category] ?? fail(`${where}: unknown list group ${d.category}`);
  if (item && item.type !== wantType) fail(`${where}: MeowDB lists it under ${d.category}, but local item ${item_id} is type ${item.type}`);
  const gate = deriveQuestGate(item_id, items, quests);
  const category = deriveChanceCategory(item, gate);
  const rarity = rarityOf(d.name, henesys);
  const entry = {
    key: entryKey(d.name),
    name: d.name,
    item_id,
    item_resolution,
    membership_source: {
      authority: AUTHORITIES.meowdb, url: live.url, read_at: live.read_at, capture: live.file,
      list: MEMBERSHIP_LIST, list_group: d.category, raw_value: memberRawValue(live, d, where),
      votes: { up: d.upvotes, down: d.downvotes, score: d.score },
    },
    rarity,
    category_inputs: item
      ? { item_type: item.type, item_subtype: item.subtype ?? null, quest_gated: gate != null, item: `game/data/canonical/items/${item_id}.json` }
      : { item_type: null, item_subtype: null, quest_gated: false, item: null },
    chance_category: category,
    quest_gate: gate,
    notes: [],
  };
  if (d.score <= 0) entry.notes.push(`MeowDB votes ${d.upvotes} up, ${d.downvotes} down (score ${d.score}); kept: the whole list is the membership, nothing is excluded for votes (D3-11)`);
  if (!item_id) gaps.push(`item unresolved: "${d.name}" (${item_resolution.state}): ${item_resolution.evidence}; it never drops`);
  if (!rarity) gaps.push(`rarity unresolved: Henesys.gg has no row for "${d.name}" (${henesys.file}); it never drops`);
  if (item && !category) gaps.push(`category unresolved: "${d.name}" is type ${item.type}, which the drop chance table has no row for; it never drops`);
  return entry;
}

/**
 * The meso block of a monster record: MeowDB's player reports from the newest dated source (the live capture or the
 * cached report API), or null amounts with the gaps when MeowDB has none. Never a chance (D3-12).
 */
export function buildMonsterMeso(live, cache) {
  const candidates = [];
  const rep = live.meso.report;
  candidates.push({
    at: live.read_at,
    source: { authority: AUTHORITIES.meowdb, url: live.url, read_at: live.read_at, capture: live.file, raw_value: rep.raw ?? live.meso.report_text },
    report: rep.state === 'resolved' ? { min: rep.min, max: rep.max, reports: rep.reports } : null,
  });
  if (cache?.mesos) {
    const s = cache.mesos.json?.summary ?? {};
    const count = Number(s.count ?? 0);
    candidates.push({
      at: cache.mesos.retrieved_at,
      source: {
        authority: AUTHORITIES.meowdb, url: cache.mesos.url, retrieved_at: cache.mesos.retrieved_at,
        raw_value: `summary: count ${count}, medianMin ${s.medianMin}, medianMax ${s.medianMax}`,
      },
      report: count > 0 ? { min: Number(s.medianMin), max: Number(s.medianMax), reports: count } : null,
    });
  }
  const newest = candidates.slice().sort((a, b) => Date.parse(b.at) - Date.parse(a.at))[0];
  const gaps = [];
  const meso = { amount_state: 'not_reported', min: null, max: null, amount_source: null, sources_compared: candidates.map((c) => c.source), gaps };
  if (newest.report) {
    const { min, max, reports } = newest.report;
    if (!(Number.isInteger(min) && Number.isInteger(max) && min >= 1 && max >= min)) fail(`meso report ${JSON.stringify(newest.source.raw_value)} is not an amount 1 <= min <= max`);
    meso.amount_state = 'reported';
    meso.min = min;
    meso.max = max;
    meso.amount_source = {
      ...newest.source, report_count: reports, decision: 'D3-12',
      interpretation: min === max ? null : `MeowDB's reported range ${min}-${max} read as a uniform integer in [${min}, ${max}] (MisoStory interpretation, verified: false)`,
    };
    const parsed = newest.source.capture ? parseMeowdbMesoReport(newest.source.raw_value) : null;
    if (parsed && (parsed.min !== min || parsed.max !== max)) fail(`meso report ${newest.source.raw_value} reads ${parsed.min}-${parsed.max}`);
  } else {
    gaps.push(`meso amount: MeowDB has no player meso report for this monster (newest source ${newest.source.url}, ${newest.at}: ${JSON.stringify(newest.source.raw_value)}); the runtime applies the meso rule of decision D3-12 (${MESO_RULES_FILE}: the level formula, or no mesos for an owner the rule exempts)`);
  }
  gaps.push(`meso chance: MeowDB publishes none (its report form's dropChancePct is a constant the form fills in, not an observed chance); the runtime uses ${MESO_RULES_FILE} (decision D3-12)`);
  return meso;
}

function buildRecord(ownerId, ctx) {
  const { captures, meowdbCache } = ctx;
  const kind = OWNER_KINDS[ownerId] ?? fail(`drops/${ownerId}: not a Maple Island drop owner (${OWNER_IDS.join(', ')})`);
  const where = `drops/${ownerId}`;
  const live = (kind === 'monster' ? captures.meowdb.monsters[ownerId] : captures.meowdb.breakables[ownerId])
    ?? fail(`${where}: no live MeowDB capture (tools/meowdb/captures/${kind === 'monster' ? `monster_${ownerId}.*` : `breakable_${ownerId}.txt`})`);
  const cache = meowdbCache?.[ownerId] ?? fail(`${where}: no MeowDB cache data passed in`);
  if (!live.community_drops.length) fail(`${where}: ${live.file} has no "${MEMBERSHIP_LIST}" list`);
  // The newest dated source wins (D3-11). The membership is read from the page capture; a cache read after it that
  // names other members is the newer list, which the build cannot quote verbatim: re-capture the page.
  const listDiff = communityListDiscrepancy(live, cache);
  if (listDiff && Date.parse(cache.community.retrieved_at) > Date.parse(live.read_at)) {
    fail(`${where}: MeowDB's cached community list (${cache.community.url}, retrieved ${cache.community.retrieved_at}) is newer than `
      + `the page capture ${live.file} (read ${live.read_at}) and names other members (${JSON.stringify(listDiff.values.map((v) => v.value))}): `
      + 're-capture the page (the newest dated source wins, decision D3-11)');
  }
  const henesys = captures.henesys.rarity ?? fail('no Henesys.gg rarity capture (tools/henesys/captures/item_rarity.json)');
  const gaps = [];
  const ectx = { ...ctx, henesys, cachedByName: cachedEntriesByName(cache), cacheRef: cache.community };
  const entries = [];
  const keys = new Set();
  const itemSeen = new Map();
  for (const d of live.community_drops) {
    const e = buildEntry(ownerId, d, live, ectx, gaps);
    if (keys.has(e.key)) fail(`${where}: two members with key ${e.key}`);
    keys.add(e.key);
    if (e.item_id && itemSeen.has(e.item_id)) fail(`${where}: item ${e.item_id} is both "${itemSeen.get(e.item_id)}" and "${e.name}"`);
    if (e.item_id) itemSeen.set(e.item_id, e.name);
    entries.push(e);
  }
  const meso = kind === 'monster' ? buildMonsterMeso(live, cache) : null;
  const provenance = {
    membership: { authority: AUTHORITIES.meowdb, url: live.url, read_at: live.read_at, capture: live.file, decision: 'D3-11' },
    rarity: { authority: AUTHORITIES.henesys, url: henesys.url, read_at: henesys.read_at, capture: henesys.file, decision: 'D3-11' },
  };
  if (meso?.amount_source) {
    const a = meso.amount_source;
    provenance['mesos.amount'] = { authority: a.authority, url: a.url, ...(a.read_at ? { read_at: a.read_at } : { retrieved_at: a.retrieved_at }), ...(a.capture ? { capture: a.capture } : {}), decision: 'D3-12' };
  }
  const name = live.name;
  return {
    id: ownerId,
    name: `${name} drop table`,
    schema_version: SCHEMA_VERSION,
    owner: { kind, id: ownerId, name },
    membership_authority: AUTHORITIES.meowdb,
    membership_list: MEMBERSHIP_LIST,
    entries,
    meowdb_reference: kind === 'monster' ? meowdbReference(live, cache, ctx.items) : null,
    meso,
    provenance,
    source: { authority: AUTHORITIES.meowdb, url: live.url, retrieved_at: live.read_at, capture: live.file },
    field_sources: {
      'entries[].item_id': { url: cache.community.url, retrieved_at: cache.community.retrieved_at, note: 'MeowDB\'s own cached drop entries for this owner: each member\'s item id is checked against them, and they decide between local items that share a name' },
    },
    gaps: [
      ...gaps,
      ...(kind === 'breakable' ? ['mesos: MeowDB has no meso reports for breakables; the Wooden Box drops no mesos (decision D3-12)'] : []),
      `drop chance: MeowDB and Henesys.gg publish none; the chance is the owner-approved table ${DROP_RATES_FILE} (category x rarity, decision D3-11), applied at runtime`,
      'quantity: no source gives one; one item per drop (decision D3-11)',
    ],
    discrepancies: [listDiff].filter(Boolean),
    notes: [
      `Membership: MeowDB's community list "${MEMBERSHIP_LIST}" on the live page (${live.url}, read ${live.read_at}), every entry with its votes; nothing is excluded for votes (decision D3-11).`,
      `Rarity: Henesys.gg's label per item (${henesys.url}, read ${henesys.read_at}; ${henesys.file}).`,
      `Chance: the drop chance table ${DROP_RATES_FILE} by chance_category x rarity.label (decision D3-11, verified: false). Quest-gated entries roll only while their quest is in progress (D3-9).`,
      kind === 'monster'
        ? `Mesos: MeowDB's player report when there is one (meso.amount_source); the rest of the rule (the level formula where MeowDB has no report, the chance, the owners without mesos) is ${MESO_RULES_FILE} (decision D3-12).`
        : `Mesos: none (decision D3-12, ${MESO_RULES_FILE}).`,
      'Runtime (contract C1): an entry rolls only when item_id, rarity and chance_category are all resolved and quest_gate is null or its quest is in progress.',
    ],
  };
}

/**
 * Builds every C1 record. `meowdbCache` gives, per owner id, MeowDB's cached data the extractor already read:
 * {community: {url, retrieved_at, drops: [{id, itemId, itemName, ...}]}, msea: [{item_id, item_name}], msea_page,
 *  mesos: {url, retrieved_at, json} | null}. Returns {records: {owner id: record}, summary: [...lines]}.
 */
export function buildDropRecords({ root = REPO_ROOT, captures = loadCaptures({ root }), items = loadLocalItems({ root }),
  quests = loadLocalQuests({ root }), meowdbCache } = {}) {
  const ctx = { root, captures, items, quests, meowdbCache };
  const records = {};
  const summary = [];
  for (const id of OWNER_IDS) {
    const rec = buildRecord(id, ctx);
    records[id] = rec;
    const resolved = rec.entries.filter((e) => e.item_id != null && e.rarity && e.chance_category);
    summary.push(`${id} ${rec.owner.name}: ${rec.entries.length} members, ${resolved.length} resolved (`
      + `${resolved.map((e) => `${e.item_id}:${e.chance_category}/${e.rarity.label}${e.quest_gate ? `[gate ${e.quest_gate.quest_id}]` : ''}`).join(' ')}), `
      + `${rec.entries.length - resolved.length} unresolved; meso ${rec.meso ? (rec.meso.amount_source ? `MeowDB report ${rec.meso.min}-${rec.meso.max}` : 'no MeowDB report') : 'none (breakable)'}`);
  }
  return { records, summary };
}
