// Offline join that builds the canonical schema v2 drop records (contract C1, docs/runtime/ITERATION_THREE_CONTRACTS.md;
// decisions D3-3 to D3-9 in docs/ITERATION_LOG.md). Called by tools/meowdb/extract_monsters.mjs, the single writer of
// game/data/canonical/drops/<owner id>.json; it reads only local files and never touches the network.
//
//   what can drop    monsters: Hidden Street's "Before Chaos" drop lists (tools/hiddenstreet/captures, D3-6)
//                    the Wooden Box: MeowDB's live breakable page (tools/meowdb/captures/breakable_0000001.txt, D3-7)
//   how often        KuroDB, only for members its page also lists (tools/kurodb/captures, D3-3): "<p>% base" = p / 100;
//                    a reactor's "Chance value N" = 1 / N, an interpretation (D3-7)
//   which item       the reviewed name crosswalk tools/sources/crosswalk/drop_items.json -> a local MeowDB item
//                    (game/data/canonical/items/<id>.json). Never joined by id across sites (D3-4).
//   meso amount      MeowDB's player report where there is one (Snail), else Hidden Street (D3-5)
//   meso chance      KuroDB's "Meso drop" row; no row = no mesos (Tutorial Jr. Sentinel, the Wooden Box)
//   quest gate       C1 gate rule (D3-9): the membership source or MeowDB's item subtype marks a quest item AND a Maple
//                    Island quest objective asks for it. KuroDB's "| Quest N" is corroboration only.
//
// Fails hard (throws DropMergeError) on anything the captures, the crosswalk and the local items do not support: a
// member without a crosswalk row or a row without a member, a KuroDB row claimed by two members, a "none" row whose
// KuroDB page does list the member, a resolved item that does not exist locally or whose name does not match, an
// unresolved item whose candidate is now local (review the row), an unparsable raw value, a quest item two quests ask
// for, a row without a reviewer_note. A KuroDB row no member claims becomes an excluded_kuro_only row (KuroDB never adds
// a member). A crosswalk "candidate" row (a KuroDB row that may be the member under another name, D3-8) is settled by
// its KuroDB item page capture (tools/kurodb/captures/item_<kuro id>.json, judgeKuroCandidate): confirmed, it is the
// member's chance (alias_with_evidence, the page cited in chance_source.match_evidence); rejected or not settled by the
// page, it is excluded_kuro_only with what the page showed; with no capture yet, it is a pending_kuro_candidates row and
// the member's chance a pending source read.
//
//   import { buildDropRecords } from '../sources/drops_merge.mjs';
//   const { records } = buildDropRecords({ meowdbCache });   // {"1": {...}, ..., "0000001": {...}}
import fs from 'node:fs';
import path from 'node:path';
import { loadCaptures, REPO_ROOT, AUTHORITIES } from './captures.mjs';
import { normalizeItemName, sameItemName, entryKey, parseMeowdbMesoReport } from './parse.mjs';

export const SCHEMA_VERSION = 2;
export const CROSSWALK_FILE = 'tools/sources/crosswalk/drop_items.json';
export const RESOLUTION_STATES = ['resolved', 'ambiguous', 'not_in_snapshot', 'not_in_classic'];
export const MATCH_METHODS = ['exact', 'normalized', 'alias_with_evidence', 'none'];

/** The owners the records cover, in file order (contract C1). */
export const OWNER_IDS = ['1', '2', '3', '4', '5', '9', '0000001'];

/**
 * MisoStory adaptation (verified: false): KuroDB's reactor rows ("Chance value N") carry no quantity, but a resolved C1
 * entry needs one. One item per successful roll, the same reading as the 1/N interpretation (D3-7: OdinMS-family
 * reactor drops have no quantity column). Written into each reactor entry's quantity with this reason.
 */
export const REACTOR_QUANTITY = Object.freeze({
  min: 1,
  max: 1,
  source: 'not published: KuroDB reactor rows ("Chance value N") carry no quantity',
  adaptation: {
    value: 'one item per successful roll',
    reason: 'A resolved drop needs a quantity and KuroDB gives none for reactor (breakable) drops. One per roll is the reading that goes with decision D3-7 (KuroDB reactor values follow the OdinMS-family reactor code, whose reactor drops have no quantity). MeowDB publishes no quantity either.',
    verified: false,
  },
});

/** The excluded_kuro_only reason of a KuroDB row no member claims (tools/parity/parity.mjs KURO_ONLY_REASON). */
export const KURO_ONLY_REASON = 'not on the membership list (KuroDB never adds members)';

/** Read as "<a>-<b> uniform integer" when a Hidden Street meso amount is a range (D3-5). */
const RANGE_INTERPRETATION = (a, b) => `Hidden Street range ${a}-${b} read as a uniform integer in [${a}, ${b}] (MisoStory interpretation, verified: false)`;
const REACTOR_INTERPRETATION = 'KuroDB reactor value "Chance value N" read as a 1-in-N chance (1 / N), as in the OdinMS-family reactor code; decision D3-7. KuroDB shows it as a value, not a percentage.';
const KURO_BASE_NOTE = 'KuroDB "<p>% base" is the chance before any server-wide drop-rate multiplier; MisoStory applies none (multiplier 1).';

export class DropMergeError extends Error {
  constructor(message) {
    super(message);
    this.name = 'DropMergeError';
  }
}

const fail = (msg) => { throw new DropMergeError(msg); };

// --- local data ----------------------------------------------------------------------------------------------

/** The reviewed crosswalk (tools/sources/crosswalk/drop_items.json). */
export function loadCrosswalk({ root = REPO_ROOT } = {}) {
  return JSON.parse(fs.readFileSync(path.join(root, CROSSWALK_FILE), 'utf8'));
}

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

// --- crosswalk checks ----------------------------------------------------------------------------------------

const GENDER_FIELD = { M: 'male', F: 'female' };

/**
 * Checks one crosswalk row's MeowDB side against the local items. Returns the C1 item_resolution and item_id.
 * `where` names the row in errors.
 */
export function resolveMeowdbItem(member, side, items, where) {
  if (!side || typeof side !== 'object') fail(`${where}: meowdb side missing`);
  const { state, method } = side;
  const candidates = Array.isArray(side.candidates) ? side.candidates.map(String) : fail(`${where}: candidates must be a list`);
  if (!RESOLUTION_STATES.includes(state)) fail(`${where}: meowdb.state ${JSON.stringify(state)} is not one of ${RESOLUTION_STATES.join(', ')}`);
  if (!MATCH_METHODS.includes(method)) fail(`${where}: meowdb.method ${JSON.stringify(method)} is not one of ${MATCH_METHODS.join(', ')}`);
  if (typeof side.evidence !== 'string' || side.evidence.trim() === '') fail(`${where}: meowdb.evidence is required`);
  if (state === 'resolved') {
    const id = side.item_id == null ? fail(`${where}: resolved without an item_id`) : String(side.item_id);
    const item = items[id] ?? fail(`${where}: MeowDB item ${id} is not a local item (game/data/canonical/items/${id}.json)`);
    const n = normalizeItemName(member);
    if (method === 'exact' && item.name !== member) fail(`${where}: "exact" but MeowDB ${id} is named ${JSON.stringify(item.name)}`);
    if (method === 'normalized') {
      if (n.normalized !== normalizeItemName(item.name).normalized) fail(`${where}: "normalized" but MeowDB ${id} is ${JSON.stringify(item.name)}`);
      if (n.gender && item.gender !== GENDER_FIELD[n.gender]) fail(`${where}: the ${n.suffix} suffix needs gender ${GENDER_FIELD[n.gender]}, MeowDB ${id} has ${JSON.stringify(item.gender)}`);
      if (!n.gender && item.name === member) fail(`${where}: the names are identical; use "exact"`);
    }
    if (method === 'alias_with_evidence' && sameItemName(member, item.name)) fail(`${where}: the names match; use "exact" or "normalized", not an alias`);
    if (method === 'none') fail(`${where}: a resolved item needs a match method other than none`);
    return { item_id: id, item_resolution: { state, method, candidates, note: side.evidence } };
  }
  if (side.item_id != null) fail(`${where}: item_id must be null while meowdb.state is ${state}`);
  if (state === 'ambiguous' && candidates.length < 2) fail(`${where}: ambiguous needs at least two candidates`);
  const local = candidates.filter((c) => items[c]);
  if (state === 'not_in_snapshot' && local.length) fail(`${where}: candidate ${local.join(', ')} is now a local item; review the crosswalk row (resolve it)`);
  if (state === 'ambiguous' && local.length === candidates.length && candidates.length > 0) {
    // Every candidate is local: a gender suffix may now decide it.
    const n = normalizeItemName(member);
    const fit = local.filter((c) => normalizeItemName(items[c].name).normalized === n.normalized && (!n.gender || items[c].gender === GENDER_FIELD[n.gender]));
    if (fit.length === 1) fail(`${where}: only candidate ${fit[0]} fits now that all candidates are local; review the crosswalk row`);
  }
  return { item_id: null, item_resolution: { state, method, candidates, note: side.evidence } };
}

/** The KuroDB row a crosswalk row claims on `rows` ([{kuro_item_id, name, ...}]), checked; null for "none". */
export function matchKuroRow(member, side, rows, where) {
  if (!side || typeof side !== 'object') fail(`${where}: kurodb side missing`);
  if (typeof side.evidence !== 'string' || side.evidence.trim() === '') fail(`${where}: kurodb.evidence is required`);
  if (side.state === 'none') {
    const same = rows.filter((r) => sameItemName(member, r.name));
    if (same.length) fail(`${where}: kurodb.state is none but the KuroDB page lists ${same.map((r) => `${r.name} (${r.kuro_item_id})`).join(', ')}`);
    return null;
  }
  if (side.state !== 'matched') fail(`${where}: kurodb.state must be matched or none, got ${JSON.stringify(side.state)}`);
  if (!MATCH_METHODS.includes(side.method) || side.method === 'none') fail(`${where}: a matched KuroDB row needs method exact, normalized or alias_with_evidence`);
  const hits = rows.filter((r) => r.kuro_item_id === String(side.kuro_item_id) && r.name === side.kuro_name);
  if (hits.length !== 1) fail(`${where}: the KuroDB page has ${hits.length} rows "${side.kuro_name}" (${side.kuro_item_id}); expected exactly one`);
  if (side.method === 'exact' && side.kuro_name !== member) fail(`${where}: "exact" but KuroDB names it ${JSON.stringify(side.kuro_name)}`);
  if (side.method === 'normalized' && !sameItemName(member, side.kuro_name)) fail(`${where}: "normalized" but ${JSON.stringify(side.kuro_name)} differs`);
  return hits[0];
}

// --- quest gate (C1 rule, D3-9) ------------------------------------------------------------------------------

/**
 * The quest gate of a resolved member: {quest_id, basis, rule, decision, verified} or null. `marksQuest` is true when
 * the membership source itself labels the member a quest item (MeowDB's breakable list subtype "Quest Item").
 */
export function deriveQuestGate(itemId, marksQuest, items, quests, kuroQuest = null) {
  if (itemId == null) return null;
  const item = items[itemId];
  const subtypeQuest = item?.subtype === 'Quest Item';
  if (!marksQuest && !subtypeQuest) return null;
  const asking = Object.values(quests)
    .filter((q) => (q.region ?? 'Maple Island') === 'Maple Island')
    .map((q) => ({ q, need: (q.objectives?.item_collection ?? []).find((i) => String(i.item_id) === String(itemId)) }))
    .filter((x) => x.need)
    .sort((a, b) => Number(a.q.id) - Number(b.q.id));
  if (asking.length === 0) return null;
  if (asking.length > 1) fail(`item ${itemId}: quest item asked for by ${asking.map((x) => x.q.id).join(', ')}; the C1 gate rule needs exactly one quest`);
  const { q, need } = asking[0];
  const marks = [subtypeQuest ? `MeowDB item subtype "Quest Item" (items/${itemId}.json)` : null, marksQuest ? 'the membership source lists it as "Quest Item"' : null].filter(Boolean).join(' and ');
  return {
    quest_id: String(q.id),
    basis: `${marks}; quest ${q.id} (${q.name}) asks for ${need.count ?? '?'} in objectives.item_collection, so the entry rolls only while ${q.id} is in progress.`
      + (kuroQuest ? ` KuroDB's "Quest ${kuroQuest}" flag (its own quest id) corroborates.` : ''),
    rule: 'C1 quest-gate rule (docs/runtime/ITERATION_THREE_CONTRACTS.md): a MisoStory derivation',
    decision: 'D3-9',
    verified: false,
  };
}

// --- KuroDB candidate rows (decision D3-8) --------------------------------------------------------------------

/** The rules a crosswalk candidate may name to be settled by its KuroDB item page (kurodb.candidate.confirm_with). */
export const CANDIDATE_RULES = ['meowdb_scroll'];

/**
 * What a KuroDB item page capture (tools/kurodb/captures/item_<id>.json, captures.mjs kuroItemPage) says about a
 * crosswalk candidate: a KuroDB monster-page row that may be a member under another name. Returns
 *   {outcome: "pending"}                       no capture of the item page yet: the member's chance stays a pending read
 *   {outcome: "confirmed", shows}              the page shows the member's item: the row becomes its chance source
 *                                              (match_method alias_with_evidence, the page cited)
 *   {outcome: "rejected" | "inconclusive", reasons}   the page shows another item, or does not show enough: the row
 *                                              is KuroDB-only (excluded_kuro_only) and the member's chance a real gap
 * Rule "meowdb_scroll": the member's local MeowDB item is a scroll; the page must show the same success rate
 * (scroll.success_rate_pct) and exactly the same "+N" stat bonuses (scroll.stat_bonus_on_success). A shown value that
 * differs rejects; a value the page does not show leaves it inconclusive. When the page lists this monster among its
 * MONSTER DROPS, that row must read as the monster page's row (else inconclusive: KuroDB disagrees with itself). Never
 * guesses: only what the page text shows is compared.
 */
export function judgeKuroCandidate({ cand, page, memberItem, monsterRow, monsterName, where }) {
  if (!page) return { outcome: 'pending' };
  if (!CANDIDATE_RULES.includes(cand.confirm_with)) fail(`${where}: candidate ${cand.kuro_item_id} needs confirm_with (one of ${CANDIDATE_RULES.join(', ')}) to be settled by its item page ${page.file}`);
  if (page.name !== cand.kuro_name) fail(`${where}: KuroDB item page ${page.file} is "${page.name}", the candidate row is "${cand.kuro_name}"`);
  if (!memberItem) return { outcome: 'inconclusive', reasons: ['the member has no local MeowDB item to compare the page with'] };
  const reasons = [];
  const differs = [];
  const scroll = memberItem.scroll;
  if (!scroll) fail(`${where}: confirm_with meowdb_scroll but the member's MeowDB item ${memberItem.id} has no scroll block`);
  const wantRate = scroll.success_rate_pct;
  const wantStats = Object.fromEntries(Object.entries(scroll.stat_bonus_on_success ?? {}).sort(([a], [b]) => (a < b ? -1 : 1)));
  if (page.success_rate == null) reasons.push('the page shows no success rate');
  else if (page.success_rate.pct !== wantRate) differs.push(`its success rate is ${page.success_rate.pct}% ("${page.success_rate.raw}"), MeowDB ${memberItem.id}'s is ${wantRate}%`);
  if (!Object.keys(page.stat_bonuses).length) reasons.push('the page shows no stat bonus');
  else if (JSON.stringify(page.stat_bonuses) !== JSON.stringify(wantStats)) differs.push(`its stat bonuses are ${JSON.stringify(page.stat_bonuses)}, MeowDB ${memberItem.id}'s are ${JSON.stringify(wantStats)}`);
  const own = page.monster_drops.filter((d) => d.monster_name === monsterName);
  if (own.length && !own.some((d) => d.raw === monsterRow.raw)) {
    reasons.push(`its MONSTER DROPS row for ${monsterName} reads ${own.map((d) => `"${d.raw}"`).join(', ')}, the monster page "${monsterRow.raw}"`);
  }
  if (differs.length) return { outcome: 'rejected', reasons: [...differs, ...reasons] };
  if (reasons.length) return { outcome: 'inconclusive', reasons };
  const shows = `${page.success_rate.raw} (${page.success_rate.source}), bonuses ${JSON.stringify(page.stat_bonuses)} (${page.stat_bonuses_source})`;
  return { outcome: 'confirmed', shows };
}

/** Where a pending candidate's item page goes once read. */
const itemPageCapture = (kuroId) => `tools/kurodb/captures/item_${kuroId}.json`;

// --- builders ------------------------------------------------------------------------------------------------

function kuroChanceSource(page, row, side) {
  return {
    authority: AUTHORITIES.kurodb, url: page.url, read_at: page.read_at, capture: page.file,
    kuro_item_id: row.kuro_item_id, kuro_name: row.name, match_method: side.method,
    raw_value: row.raw, format: row.parsed.format, normalized_probability: row.probability,
    conversion: row.parsed.conversion, interpretation: null, kuro_quest_condition: row.quest ?? null,
  };
}

function reactorChanceSource(item, drop, side, capture) {
  return {
    authority: AUTHORITIES.kurodb, url: item.url, read_at: item.read_at, capture,
    kuro_item_id: item.kuro_item_id, kuro_name: item.name, kuro_reactor_id: drop.reactor_id, match_method: side.method,
    raw_value: drop.raw, format: drop.parsed.format, normalized_probability: drop.probability,
    conversion: drop.parsed.conversion, interpretation: REACTOR_INTERPRETATION, kuro_quest_condition: drop.quest ?? null,
  };
}

/**
 * MeowDB's own name -> item ids map from one of its cached lists (same site, so a join by name is safe). `list` is
 * [[name, id], ...].
 */
function meowdbIdsByName(list) {
  const byName = new Map();
  for (const [name, id] of list) {
    if (!byName.has(name)) byName.set(name, new Set());
    byName.get(name).add(String(id));
  }
  return byName;
}

const cachedCommunityIds = (cache) => meowdbIdsByName((cache?.community?.drops ?? []).map((d) => [d.itemName, d.itemId]));
const cachedMseaIds = (cache) => meowdbIdsByName((cache?.msea ?? []).map((m) => [m.item_name, m.item_id]));

/**
 * MeowDB's community and MSEA lists from the live capture, each name given the MeowDB item id the matching cached list
 * uses (the community list and the MSEA list may name different items alike: the Red Snail's "Red Cloth Pants" is 1168
 * on one, 1177 on the other). null when the cache does not name it once, or the item is not local.
 */
function meowdbReference(live, cache, items, note) {
  const idFrom = (ids) => (name) => {
    const set = ids.get(name);
    if (!set || set.size !== 1) return null;
    const id = [...set][0];
    return items[id] ? id : null;
  };
  const communityId = idFrom(cachedCommunityIds(cache));
  const mseaId = idFrom(cachedMseaIds(cache));
  const ref = {
    note,
    source: { authority: AUTHORITIES.meowdb, url: live.url, read_at: live.read_at, capture: live.file },
    community_drops: live.community_drops.map((d) => ({
      name: d.name, category: d.category, detail: d.subtype, upvotes: d.upvotes, downvotes: d.downvotes, score: d.score,
      disputed: d.score <= 0, item_id: communityId(d.name),
    })),
  };
  if (live.msea_reference) ref.msea_reference = live.msea_reference.map((d) => ({ name: d.name, category: d.category, detail: d.subtype, item_id: mseaId(d.name) }));
  return ref;
}

/** Record-level discrepancy when the cached MeowDB community list (2026-10-04) and the live page differ by name. */
function communityListDiscrepancy(live, cache) {
  const cached = new Set((cache?.community?.drops ?? []).map((d) => d.itemName));
  const now = new Set(live.community_drops.map((d) => d.name));
  const gone = [...cached].filter((n) => !now.has(n)).sort();
  const added = [...now].filter((n) => !cached.has(n)).sort();
  if (!gone.length && !added.length) return null;
  return {
    field: 'meowdb_reference.community_drops',
    values: [
      { value: { only_in_cache: gone }, source: `${cache.community.url} (cache, retrieved ${cache.community.retrieved_at})` },
      { value: { only_on_live_page: added }, source: `${live.url} (live page, read ${live.read_at}; ${live.file})` },
    ],
    chosen: 'the live page (newest dated source)',
    reason: 'MeowDB\'s community list changed between the cache and the hand-read live page. It is reference only: membership comes from Hidden Street (D3-6).',
  };
}

function hsMembershipSource(hs, member) {
  return {
    authority: AUTHORITIES.hiddenstreet, url: hs.url, read_at: hs.read_at, capture: hs.file,
    raw_value: member.raw_lines.join('\n'), categories: member.categories,
  };
}

/** The entry's notes: the row's reviewer note (required: every crosswalk row is reviewed) and any extra lines. */
function entryNotes(row, where, extra = []) {
  if (typeof row.reviewer_note !== 'string' || row.reviewer_note.trim() === '') fail(`${where}: reviewer_note is required (every crosswalk row records the reviewer's verdict)`);
  return [row.reviewer_note, ...extra];
}

function buildMonsterRecord(ownerId, cw, ctx) {
  const { captures, items, quests, meowdbCache } = ctx;
  const where = `drops/${ownerId}`;
  const hs = captures.hiddenstreet.monsters[cw.hidden_street_slug] ?? fail(`${where}: no Hidden Street capture "${cw.hidden_street_slug}"`);
  const kuro = captures.kurodb.monsters[cw.kuro_monster_id] ?? fail(`${where}: no KuroDB capture ${cw.kuro_monster_id}`);
  const live = captures.meowdb.monsters[ownerId] ?? fail(`${where}: no live MeowDB capture tools/meowdb/captures/monster_${ownerId}.*`);
  const cache = meowdbCache?.[ownerId] ?? fail(`${where}: no MeowDB cache data passed in`);
  for (const [site, name] of [['Hidden Street', hs.name], ['KuroDB', kuro.name], ['MeowDB (live)', live.name]]) {
    if (name !== cw.name) fail(`${where}: the ${site} page is "${name}", the crosswalk says "${cw.name}"`);
  }
  // Membership: Hidden Street's lists, deduplicated across categories, in page order.
  const members = hs.items;
  const rowsByName = new Map();
  for (const row of cw.rows) {
    if (rowsByName.has(row.name)) fail(`${where}: two crosswalk rows for "${row.name}"`);
    rowsByName.set(row.name, row);
  }
  for (const m of members) if (!rowsByName.has(m.name)) fail(`${where}: Hidden Street member "${m.name}" has no crosswalk row (tools/sources/crosswalk/drop_items.json)`);
  for (const name of rowsByName.keys()) if (!members.some((m) => m.name === name)) fail(`${where}: crosswalk row "${name}" is not on Hidden Street's ${cw.name} lists`);

  const claimed = new Map(); // "<kuro id>|<name>" -> member
  const candidates = new Map(); // same key -> the member whose candidate it is
  const pending = []; // pending_kuro_candidates rows
  const pendingKeys = new Set();
  const checked = new Map(); // key -> excluded_kuro_only reason of a candidate its item page did not confirm
  const entries = [];
  const gaps = [];
  const itemSeen = new Map();
  for (const m of members) {
    const row = rowsByName.get(m.name);
    const rw = `${where} "${m.name}"`;
    const { item_id, item_resolution } = resolveMeowdbItem(m.name, row.meowdb, items, rw);
    if (item_id && itemSeen.has(item_id)) fail(`${rw}: item ${item_id} is also "${itemSeen.get(item_id)}"`);
    if (item_id) itemSeen.set(item_id, m.name);
    let k = matchKuroRow(m.name, row.kurodb, kuro.rows, rw);
    let side = row.kurodb;
    let matchEvidence = null;
    const extraNotes = [];
    const cand = row.kurodb.candidate;
    if (cand) {
      if (k) fail(`${rw}: a matched KuroDB row and a candidate row on one member`);
      const hit = kuro.rows.filter((r) => r.kuro_item_id === String(cand.kuro_item_id) && r.name === cand.kuro_name);
      if (hit.length !== 1) fail(`${rw}: candidate KuroDB row ${cand.kuro_name} (${cand.kuro_item_id}) is not on the page`);
      if (!cand.reason) fail(`${rw}: a candidate KuroDB row needs a reason`);
      const ckey = `${cand.kuro_item_id}|${cand.kuro_name}`;
      candidates.set(ckey, m.name);
      const page = captures.kurodb.item_pages?.[String(cand.kuro_item_id)] ?? null;
      const judged = judgeKuroCandidate({ cand, page, memberItem: item_id ? items[item_id] : null, monsterRow: hit[0], monsterName: kuro.name, where: rw });
      const label = `KuroDB candidate row ${cand.kuro_name} (${cand.kuro_item_id}, "${hit[0].raw}")`;
      if (judged.outcome === 'confirmed') {
        k = hit[0];
        side = { method: 'alias_with_evidence' };
        matchEvidence = { capture: page.file, url: page.url, read_at: page.read_at, shows: judged.shows, decision: 'D3-8' };
        extraNotes.push(`${label} confirmed by its item page (${page.file}, read ${page.read_at}): it shows ${judged.shows}, as MeowDB ${item_id}'s scroll does (decision D3-8)`);
      } else if (judged.outcome === 'pending') {
        pending.push({
          kuro_item_id: String(cand.kuro_item_id), name: cand.kuro_name, raw_value: hit[0].raw, member: entryKey(m.name),
          read: `KuroDB item page ${cand.kuro_item_id} (https://playkuro.com/database/#items/${cand.kuro_item_id}), by hand in a browser; saved as ${itemPageCapture(cand.kuro_item_id)}`,
          reason: cand.reason, decision: 'D3-8',
        });
        pendingKeys.add(ckey);
        extraNotes.push(`${label}, pending a read of its item page (pending_kuro_candidates): ${cand.reason}`);
      } else {
        const why = `${judged.outcome === 'rejected' ? 'it shows another item' : 'it does not settle it'}: ${judged.reasons.join('; ')}`;
        checked.set(ckey, `possible match for the member '${m.name}', checked against its KuroDB item page (${page.file}, read ${page.read_at}): ${why}. Not accepted (decision D3-8); KuroDB never adds a member`);
        extraNotes.push(`${label} checked against its item page (${page.file}): ${why}; excluded`);
        gaps.push(`chance unresolved: "${m.name}" is on Hidden Street's list; KuroDB's ${cw.name} page (${kuro.file}) has a possible row ${cand.kuro_name} (${cand.kuro_item_id}, "${hit[0].raw}") whose item page (${page.file}) ${why}, so it never rolls (D3-8)`);
      }
    }
    if (k && !k.qty) fail(`${rw}: KuroDB row ${k.raw} has no quantity`);
    if (k) {
      const key = `${k.kuro_item_id}|${k.name}`;
      if (claimed.has(key)) fail(`${rw}: KuroDB row ${k.name} (${k.kuro_item_id}) is also claimed by "${claimed.get(key)}"`);
      claimed.set(key, m.name);
    }
    const notes = entryNotes(row, rw, extraNotes);
    const chanceSource = k ? kuroChanceSource(kuro, k, side) : null;
    if (chanceSource && matchEvidence) chanceSource.match_evidence = matchEvidence;
    const entry = {
      key: entryKey(m.name),
      name: m.name,
      item_id,
      item_resolution,
      membership_source: hsMembershipSource(hs, m),
      chance_source: chanceSource,
      chance_state: k ? 'resolved' : 'unresolved',
      probability: k ? k.probability : null,
      quantity: k ? { min: k.qty.min, max: k.qty.max, source: `KuroDB '${k.qty.min === k.qty.max ? `Qty ${k.qty.min}` : `Qty ${k.qty.min}-${k.qty.max}`}'` } : null,
      quest_gate: deriveQuestGate(item_id, false, items, quests, k?.quest ?? null),
      notes,
    };
    if (!k && cand && pendingKeys.has(`${cand.kuro_item_id}|${cand.kuro_name}`)) {
      gaps.push(`chance unresolved: "${m.name}" is on Hidden Street's list; KuroDB's ${cw.name} page (${kuro.file}) has a possible row ${cand.kuro_name} (${cand.kuro_item_id}, "${hit0(kuro, cand).raw}") whose item page has not been read (pending_kuro_candidates; a pending source read, not a source-data gap), so it never rolls`);
    } else if (!k && !cand) {
      gaps.push(`chance unresolved: "${m.name}" is on Hidden Street's list but KuroDB's ${cw.name} page (${kuro.file}) has no row for it, so it never rolls (D3-6)`);
    }
    if (!item_id) gaps.push(`item unresolved: "${m.name}" (${item_resolution.state}${item_resolution.candidates.length ? `, MeowDB candidates ${item_resolution.candidates.join(', ')}` : ''}), so it never rolls; see its item_resolution.note`);
    entries.push(entry);
  }
  for (const [key, member] of candidates) {
    if (claimed.has(key) && claimed.get(key) !== member) fail(`${where}: candidate KuroDB row ${key} of "${member}" is also claimed by "${claimed.get(key)}"`);
  }
  const excluded = kuro.rows
    .filter((r) => !claimed.has(`${r.kuro_item_id}|${r.name}`) && !pendingKeys.has(`${r.kuro_item_id}|${r.name}`))
    .map((r) => ({
      kuro_item_id: r.kuro_item_id, name: r.name, raw_value: r.raw,
      reason: checked.get(`${r.kuro_item_id}|${r.name}`) ?? KURO_ONLY_REASON,
    }));

  const meso = buildMonsterMeso(ownerId, cw, hs, kuro, live, cache, gaps);
  const provenance = {
    membership: { authority: AUTHORITIES.hiddenstreet, url: hs.url, read_at: hs.read_at, capture: hs.file, decision: 'D3-6', version_note: ctx.captures.hiddenstreet.version_note },
    probability: { authority: AUTHORITIES.kurodb, url: kuro.url, read_at: kuro.read_at, capture: kuro.file, decision: 'D3-3', site_updated_label: kuro.site_updated_label },
  };
  if (meso) {
    const a = meso.amount_source;
    provenance['mesos.amount'] = { authority: a.authority, url: a.url, read_at: a.read_at, capture: a.capture, decision: 'D3-5' };
    provenance['mesos.probability'] = { authority: AUTHORITIES.kurodb, url: kuro.url, read_at: kuro.read_at, capture: kuro.file, decision: 'D3-5' };
  }
  const discrepancies = [communityListDiscrepancy(live, cache)].filter(Boolean);
  return {
    id: ownerId,
    name: `${cw.name} drop table`,
    schema_version: SCHEMA_VERSION,
    owner: { kind: 'monster', id: ownerId, name: cw.name },
    membership_authority: AUTHORITIES.hiddenstreet,
    entries,
    excluded_kuro_only: excluded,
    pending_kuro_candidates: pending,
    meowdb_reference: meowdbReference(live, cache, items,
      'MeowDB\'s community-voted Classic drop list (with votes) and its read-only MSEA list, from the live page. Reference only: monster drop membership comes from Hidden Street (D3-6). item_id is MeowDB\'s own id for the name in its cached lists (null when the cache does not name it or no local item exists).'),
    meso,
    provenance,
    source: { authority: AUTHORITIES.meowdb, url: live.url, retrieved_at: live.read_at, capture: live.file },
    field_sources: {
      'meowdb_reference.item_ids': { url: cache.community.url, retrieved_at: cache.community.retrieved_at, note: 'MeowDB item ids for the reference lists, matched by name within MeowDB\'s own cached drop list' + (cache.msea_page ? ` and the cached page's MSEA list (${cache.msea_page.url})` : '') },
    },
    gaps,
    discrepancies,
    notes: [
      `Membership: Hidden Street's "Before Chaos" drop lists (${hs.url}, read ${hs.read_at}): post-Big-Bang GMS v0.96, a different game version from MapleStory Classic, used by the project owner's decision D3-6. Every member stays in entries; one without a KuroDB chance or a local item never rolls.`,
      `Chance: KuroDB (${kuro.url}, read ${kuro.read_at}, "${kuro.site_updated_label}"), only for members its page also lists, joined by name through ${CROSSWALK_FILE} (D3-4). ${KURO_BASE_NOTE}`,
      'excluded_kuro_only: KuroDB rows for this monster that no member matches. They never drop (KuroDB never adds a member, D3-6).',
      'pending_kuro_candidates: KuroDB rows that may be a member under another name, waiting for a hand read of their item page (decision D3-8; tools/kurodb/captures/item_<kuro id>.json). They never drop, and their member\'s chance is a pending source read, not a source-data gap. Once the page is read, the merge confirms the row as the member\'s chance (alias_with_evidence) or moves it to excluded_kuro_only with what the page showed.',
      'Runtime (contract C1): an entry rolls only when chance_state is resolved, item_id is not null and quest_gate is null or its quest is in progress. The meso bag rolls only when its amount and chance are both resolved; the amount is a uniform integer in [min, max].',
    ],
  };
}

function hit0(kuro, cand) {
  return kuro.rows.find((r) => r.kuro_item_id === String(cand.kuro_item_id) && r.name === cand.kuro_name);
}

function buildMonsterMeso(ownerId, cw, hs, kuro, live, cache, gaps) {
  const report = live.meso.report;
  if (!kuro.meso) {
    gaps.push(`mesos: KuroDB's ${cw.name} page (${kuro.file}) has no "Meso drop" row, so the monster drops no mesos (D3-5); MeowDB has ${report.state === 'resolved' ? `a report (${report.raw})` : 'no meso report'} and Hidden Street says ${JSON.stringify(hs.mesos.raw)}`);
    return null;
  }
  const meso = { amount_state: 'unresolved', min: null, max: null, amount_source: null };
  const discrepancies = [];
  if (report.state === 'resolved') {
    meso.amount_state = 'resolved';
    meso.min = report.min;
    meso.max = report.max;
    meso.amount_source = {
      authority: AUTHORITIES.meowdb, url: live.url, read_at: live.read_at, capture: live.file, raw_value: report.raw,
      interpretation: report.min === report.max ? null : `MeowDB report range ${report.min}-${report.max} read as a uniform integer in [${report.min}, ${report.max}] (MisoStory interpretation, verified: false)`,
      decision: 'D3-5',
    };
    // The cached report (2026-10-04) must agree with the live line; its form value dropChancePct is never a chance.
    const reps = cache.mesos?.json?.reports ?? [];
    for (const r of reps) {
      if (r.minMesos !== report.min || r.maxMesos !== report.max) fail(`drops/${ownerId}: cached meso report ${r.id} (${r.minMesos}-${r.maxMesos}) differs from the live "${report.raw}"`);
      discrepancies.push({
        authority: AUTHORITIES.meowdb, url: cache.mesos.url, retrieved_at: cache.mesos.retrieved_at,
        raw_value: `report ${r.id}: minMesos ${r.minMesos}, maxMesos ${r.maxMesos}, dropChancePct ${r.dropChancePct}`,
        note: 'dropChancePct is a constant MeowDB\'s report form fills in on submit (100), not an observed meso drop chance. It is never used as a chance: the chance comes from KuroDB (D3-5).',
      });
    }
    if (hs.mesos.state === 'resolved' && (hs.mesos.min !== report.min || hs.mesos.max !== report.max)) {
      discrepancies.push({
        authority: AUTHORITIES.hiddenstreet, url: hs.url, read_at: hs.read_at, capture: hs.file, raw_value: hs.mesos.raw,
        note: `MeowDB's player report (${report.raw}) is kept, following the brief's "do not replace MeowDB values when MeowDB provides them". This is the orchestrator's inference recorded with D3-5, not an owner decision: the owner's chosen option left the Snail as an open question.`,
      });
    }
  } else if (hs.mesos.state === 'resolved') {
    meso.amount_state = 'resolved';
    meso.min = hs.mesos.min;
    meso.max = hs.mesos.max;
    meso.amount_source = {
      authority: AUTHORITIES.hiddenstreet, url: hs.url, read_at: hs.read_at, capture: hs.file, raw_value: hs.mesos.raw,
      interpretation: hs.mesos.min === hs.mesos.max ? null : RANGE_INTERPRETATION(hs.mesos.min, hs.mesos.max),
      decision: 'D3-5',
      meowdb_note: `MeowDB (${live.url}, read ${live.read_at}): ${JSON.stringify(report.raw)}`,
    };
  } else {
    gaps.push(`meso amount unresolved: MeowDB ${JSON.stringify(report.raw)}, Hidden Street ${JSON.stringify(hs.mesos.raw)}; the meso bag never rolls`);
  }
  meso.chance_state = 'resolved';
  meso.probability = kuro.meso.probability;
  meso.chance_source = {
    authority: AUTHORITIES.kurodb, url: kuro.url, read_at: kuro.read_at, capture: kuro.file, raw_value: kuro.meso.raw,
    format: kuro.meso.parsed.format, normalized_probability: kuro.meso.probability, conversion: kuro.meso.parsed.conversion,
  };
  meso.discrepancies = discrepancies;
  return meso;
}

/** The live breakable page's member block "<name>\n<subtype>\n▲\n<up>\n▼\n<down>", verbatim from the capture. */
function breakableRawValue(b, d) {
  const raw = [d.name, d.subtype, '▲', String(d.upvotes), '▼', String(d.downvotes)].join('\n');
  const body = b.text.replace(/\r\n/g, '\n');
  if (!body.includes(raw)) fail(`drops/${b.breakable_id}: "${d.name}" block is not verbatim in ${b.file}`);
  return raw;
}

function buildBreakableRecord(ownerId, cw, ctx) {
  const { captures, items, quests, meowdbCache } = ctx;
  const where = `drops/${ownerId}`;
  const live = captures.meowdb.breakables[ownerId] ?? fail(`${where}: no live MeowDB capture tools/meowdb/captures/breakable_${ownerId}.txt`);
  const reactor = captures.kurodb.reactor_items ?? fail(`${where}: no KuroDB reactor item capture`);
  const cache = meowdbCache?.[ownerId] ?? fail(`${where}: no MeowDB cache data passed in`);
  if (live.name !== cw.name) fail(`${where}: the live MeowDB page is "${live.name}", the crosswalk says "${cw.name}"`);
  const members = live.community_drops;
  const rowsByName = new Map(cw.rows.map((r) => [r.name, r]));
  if (rowsByName.size !== cw.rows.length) fail(`${where}: duplicate crosswalk rows`);
  for (const m of members) if (!rowsByName.has(m.name)) fail(`${where}: MeowDB member "${m.name}" has no crosswalk row`);
  for (const name of rowsByName.keys()) if (!members.some((m) => m.name === name)) fail(`${where}: crosswalk row "${name}" is not on MeowDB's live ${cw.name} list`);
  const meowdbIds = cachedCommunityIds(cache);
  const kuroItems = Object.values(reactor.items);
  const entries = [];
  const gaps = [];
  for (const m of members) {
    const row = rowsByName.get(m.name);
    const rw = `${where} "${m.name}"`;
    const { item_id, item_resolution } = resolveMeowdbItem(m.name, row.meowdb, items, rw);
    const own = meowdbIds.get(m.name);
    if (item_id && own && !(own.size === 1 && own.has(item_id))) fail(`${rw}: MeowDB's own breakable list names item ${[...own].join('/')}, the crosswalk ${item_id}`);
    // KuroDB: the member's item page (same-site lookup by the crosswalk's KuroDB id), and its row for this reactor.
    const page = kuroItems.filter((it) => sameItemName(m.name, it.name));
    let drop = null;
    if (row.kurodb.state === 'matched') {
      matchKuroRow(m.name, row.kurodb, kuroItems.map((x) => ({ kuro_item_id: x.kuro_item_id, name: x.name })), rw);
      const it = reactor.items[String(row.kurodb.kuro_item_id)];
      const rows = it.reactor_drops.filter((d) => d.reactor_id === cw.kuro_reactor_id);
      if (rows.length !== 1) fail(`${rw}: KuroDB item ${it.kuro_item_id} has ${rows.length} rows for reactor ${cw.kuro_reactor_id}`);
      drop = { item: it, row: rows[0] };
    } else if (row.kurodb.state === 'none') {
      if (typeof row.kurodb.evidence !== 'string' || !row.kurodb.evidence.trim()) fail(`${rw}: kurodb.evidence is required`);
      for (const it of page) if (it.reactor_drops.some((d) => d.reactor_id === cw.kuro_reactor_id)) fail(`${rw}: kurodb.state is none but KuroDB item ${it.kuro_item_id} lists reactor ${cw.kuro_reactor_id}`);
    } else {
      fail(`${rw}: kurodb.state must be matched or none`);
    }
    const marksQuest = m.subtype === 'Quest Item';
    const entry = {
      key: entryKey(m.name),
      name: m.name,
      item_id,
      item_resolution,
      membership_source: {
        authority: AUTHORITIES.meowdb, url: live.url, read_at: live.read_at, capture: live.file,
        raw_value: breakableRawValue(live, m), categories: [m.category],
      },
      chance_source: drop ? reactorChanceSource(drop.item, drop.row, row.kurodb, reactor.file) : null,
      chance_state: drop ? 'resolved' : 'unresolved',
      probability: drop ? drop.row.probability : null,
      quantity: drop ? structuredClone(REACTOR_QUANTITY) : null,
      quest_gate: deriveQuestGate(item_id, marksQuest, items, quests, drop?.row.quest ?? null),
      notes: entryNotes(row, rw),
    };
    if (!drop) gaps.push(`chance unresolved: "${m.name}" is on MeowDB's ${cw.name} list but no read KuroDB page gives reactor ${cw.kuro_reactor_id} a value for it, so it never drops (D3-7)`);
    if (!item_id) gaps.push(`item unresolved: "${m.name}" (${item_resolution.state})`);
    entries.push(entry);
  }
  gaps.push(`quantity per roll: KuroDB reactor rows give none; 1 per roll is a MisoStory adaptation (each entry's quantity.adaptation, verified: false)`);
  gaps.push('KuroDB-only drops: KuroDB has no page listing every drop of reactor 2001; only the item pages of MeowDB\'s members were read, so no KuroDB-only row is known (excluded_kuro_only is empty for that reason)');
  const pageUrls = kuroItems.map((it) => it.url).sort();
  const readTimes = kuroItems.map((it) => it.read_at).sort();
  const discrepancies = [communityListDiscrepancy({ ...live, community_drops: live.community_drops }, cache)].filter(Boolean);
  return {
    id: ownerId,
    name: `${cw.name} drop table`,
    schema_version: SCHEMA_VERSION,
    owner: { kind: 'breakable', id: ownerId, name: cw.name },
    membership_authority: AUTHORITIES.meowdb,
    entries,
    excluded_kuro_only: [],
    pending_kuro_candidates: [],
    meowdb_reference: meowdbReference(live, cache, items,
      'MeowDB\'s community-voted Classic drop list for this breakable (with votes), from the live page. For the Wooden Box this list IS the membership: Hidden Street has no breakables (D3-7).'),
    meso: null,
    provenance: {
      membership: { authority: AUTHORITIES.meowdb, url: live.url, read_at: live.read_at, capture: live.file, decision: 'D3-7' },
      probability: {
        authority: AUTHORITIES.kurodb, urls: pageUrls, read_at: readTimes[0], read_at_last: readTimes[readTimes.length - 1],
        capture: reactor.file, decision: 'D3-7', site_updated_label: reactor.site_updated_label,
        reactor_identity: cw.kuro_reactor_identity,
      },
    },
    source: { authority: AUTHORITIES.meowdb, url: live.url, retrieved_at: live.read_at, capture: live.file },
    field_sources: {
      'meowdb_reference.item_ids': { url: cache.community.url, retrieved_at: cache.community.retrieved_at, note: 'MeowDB item ids for the breakable\'s list, matched by name within MeowDB\'s own cached breakable drop list' },
    },
    gaps: [...gaps, 'mesos: none. MeowDB has no meso reports for breakables and KuroDB lists no meso drop for reactors; meso is null (the box never drops mesos)'],
    discrepancies,
    notes: [
      `Membership: MeowDB's live ${cw.name} page (${live.url}, read ${live.read_at}); Hidden Street has no breakables (D3-7).`,
      `Chance: KuroDB reactor ${cw.kuro_reactor_id} rows on the members' item pages (${reactor.file}). ${cw.kuro_reactor_identity}`,
      `"Chance value N" is read as 1 / N, an interpretation (decision D3-7).`,
      'Runtime (contract C1): an entry rolls only when chance_state is resolved, item_id is not null and quest_gate is null or its quest is in progress.',
    ],
  };
}

/**
 * Builds every C1 record. `meowdbCache` gives, per owner id, MeowDB's cached data the extractor already read:
 * {community: {url, retrieved_at, drops: [{itemId, itemName, ...}]}, msea: [{item_id, item_name}], msea_page,
 *  mesos: {url, retrieved_at, json} | null}. Returns {records: {owner id: record}, summary: [...lines]}.
 */
export function buildDropRecords({ root = REPO_ROOT, captures = loadCaptures({ root }), crosswalk = loadCrosswalk({ root }),
  items = loadLocalItems({ root }), quests = loadLocalQuests({ root }), meowdbCache } = {}) {
  const ctx = { root, captures, crosswalk, items, quests, meowdbCache };
  const owners = crosswalk.owners ?? fail(`${CROSSWALK_FILE}: no owners`);
  const ids = Object.keys(owners);
  if (ids.slice().sort().join() !== OWNER_IDS.slice().sort().join()) fail(`${CROSSWALK_FILE}: owners ${ids.join(', ')}; expected ${OWNER_IDS.join(', ')}`);
  const records = {};
  const summary = [];
  for (const id of OWNER_IDS) {
    const cw = owners[id];
    const rec = cw.kind === 'monster' ? buildMonsterRecord(id, cw, ctx) : cw.kind === 'breakable' ? buildBreakableRecord(id, cw, ctx) : fail(`${CROSSWALK_FILE} ${id}: kind must be monster or breakable`);
    records[id] = rec;
    const rolls = rec.entries.filter((e) => e.chance_state === 'resolved' && e.item_id != null);
    summary.push(`${id} ${cw.name}: ${rec.entries.length} members, ${rolls.length} roll (${rolls.map((e) => `${e.item_id}@${e.probability}${e.quest_gate ? `[gate ${e.quest_gate.quest_id}]` : ''}`).join(' ')}), `
      + `${rec.entries.length - rolls.length} unresolved, ${rec.excluded_kuro_only.length} KuroDB-only excluded, ${rec.pending_kuro_candidates.length} pending item-page read(s); `
      + `meso ${rec.meso ? `${rec.meso.min}-${rec.meso.max} @${rec.meso.probability}` : 'none'}`);
  }
  return { records, summary };
}
