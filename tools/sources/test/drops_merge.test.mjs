// node --test tools/sources/test/
// The schema 3 drop records (game/data/canonical/drops/*.json, contract C1; decisions D3-9, D3-11, D3-12) against the
// dated captures (tools/meowdb/captures, tools/henesys/captures) and the builder's rules (tools/sources/drops_merge.mjs).
// With the git-ignored MeowDB cache present (tools/meowdb/.cache) a fresh build must reproduce the committed records;
// without it the builder gets a stand-in made from the live captures, so the cache-only parts (item_resolution
// evidence, the MSEA ids, the cached meso report) are not compared.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { loadCaptures, REPO_ROOT, RARITY_LABELS } from '../captures.mjs';
import { entryKey } from '../parse.mjs';
import {
  buildDropRecords, buildMonsterMeso, loadLocalItems, loadLocalQuests, deriveQuestGate, deriveChanceCategory,
  resolveMemberItem, DropMergeError, OWNER_IDS, OWNER_KINDS, CHANCE_CATEGORIES, SCHEMA_VERSION,
} from '../drops_merge.mjs';
import * as L from '../../meowdb/lib.mjs';

const c = loadCaptures();
const items = loadLocalItems();
const quests = loadLocalQuests();
const record = (id) => JSON.parse(fs.readFileSync(path.join(REPO_ROOT, 'game/data/canonical/drops', `${id}.json`), 'utf8'));
const records = Object.fromEntries(OWNER_IDS.map((id) => [id, record(id)]));
const live = (id) => (OWNER_KINDS[id] === 'monster' ? c.meowdb.monsters[id] : c.meowdb.breakables[id]);
const clone = (x) => structuredClone(x);
const throwsMerge = (fn, pattern) => assert.throws(fn, (e) => e instanceof DropMergeError && pattern.test(e.message), `expected DropMergeError ${pattern}`);

/** The local item ids with a name. */
const idsNamed = (name) => Object.values(items).filter((it) => it.name === name).map((it) => String(it.id));

/**
 * A stand-in for MeowDB's cached lists made from the live captures: each member with its one local item's id (the
 * Red Snail's Red Cloth Pants with 1168, the id MeowDB's own entry carries), and no cached meso report, dated before
 * the captures.
 */
function stubCache() {
  const out = {};
  for (const id of OWNER_IDS) {
    let n = 0;
    const drops = live(id).community_drops.map((d) => ({ id: ++n, itemId: Number(d.name === 'Red Cloth Pants' ? '1168' : idsNamed(d.name)[0]), itemName: d.name }));
    out[id] = {
      community: { url: `https://meowdb.com/msclassic/api/drops?monsterId=${id}`, retrieved_at: '2026-10-04T00:00:00Z', drops },
      msea: [], msea_page: null,
      mesos: OWNER_KINDS[id] === 'monster' ? { url: `https://meowdb.com/msclassic/api/mesos-reports?monsterId=${id}`, retrieved_at: '2026-10-04T00:00:00Z', json: { reports: [], summary: { count: 0 } } } : null,
    };
  }
  return out;
}

/** MeowDB's cached lists as tools/meowdb/extract_monsters.mjs reads them (null when the cache is not here). */
async function realCache() {
  const urls = (id) => (OWNER_KINDS[id] === 'monster'
    ? [`${L.BASE_URL}/api/drops?monsterId=${id}`, `${L.BASE_URL}/api/mesos-reports?monsterId=${id}`]
    : [`${L.BASE_URL}/api/breakable-drops?breakableId=${id}`, null]);
  if (!OWNER_IDS.every((id) => urls(id).every((u) => u == null || L.hasCached(u)))) return null;
  const out = {};
  for (const id of OWNER_IDS) {
    const [du, mu] = urls(id);
    const d = await L.fetchUrl(du, { refresh: false, accept: 'application/json' });
    const m = mu ? await L.fetchUrl(mu, { refresh: false, accept: 'application/json' }) : null;
    out[id] = {
      community: { url: d.url, retrieved_at: d.retrieved_at, drops: JSON.parse(d.text).drops },
      msea: [], msea_page: null,
      mesos: m ? { url: m.url, retrieved_at: m.retrieved_at, json: JSON.parse(m.text) } : null,
    };
  }
  return out;
}

const build = (overrides = {}) => buildDropRecords({ captures: c, items, quests, meowdbCache: stubCache(), ...overrides });

test('a fresh build reproduces the committed records (the real MeowDB cache when present)', async () => {
  const cache = await realCache();
  const { records: fresh } = buildDropRecords({ captures: c, items, quests, meowdbCache: cache ?? stubCache() });
  for (const id of OWNER_IDS) {
    const a = fresh[id];
    const b = records[id];
    assert.equal(b.schema_version, SCHEMA_VERSION);
    const entries = (r) => r.entries.map((e) => (cache ? e : { ...e, item_resolution: { ...e.item_resolution, evidence: '' } }));
    assert.deepEqual(entries(a), entries(b), `drops/${id} entries`);
    assert.deepEqual(a.provenance, b.provenance, `drops/${id} provenance`);
    assert.deepEqual(a.gaps, b.gaps, `drops/${id} gaps`);
    assert.deepEqual(a.notes, b.notes, `drops/${id} notes`);
    if (cache) {
      assert.deepEqual(a.meso, b.meso, `drops/${id} meso`);
      assert.deepEqual(a.discrepancies, b.discrepancies, `drops/${id} discrepancies`);
      assert.deepEqual(a.field_sources, b.field_sources, `drops/${id} field_sources`);
    } else {
      assert.deepEqual([a.meso?.amount_state, a.meso?.min, a.meso?.max, a.meso?.amount_source], [b.meso?.amount_state, b.meso?.min, b.meso?.max, b.meso?.amount_source], `drops/${id} meso amount`);
    }
  }
});

test('membership is exactly MeowDB\'s community list "Drops (MS Classic)" for all seven owners', () => {
  for (const id of OWNER_IDS) {
    const r = records[id];
    const page = live(id);
    assert.equal(r.membership_authority, 'MeowDB MS Classic');
    assert.equal(r.membership_list, 'Drops (MS Classic)');
    assert.deepEqual(r.entries.map((e) => e.name), page.community_drops.map((d) => d.name), `drops/${id}: every entry, in page order`);
    for (const [i, e] of r.entries.entries()) {
      const d = page.community_drops[i];
      assert.equal(e.key, entryKey(d.name));
      assert.deepEqual(e.membership_source.votes, { up: d.upvotes, down: d.downvotes, score: d.score }, `${e.name} votes recorded`);
      assert.deepEqual([e.membership_source.url, e.membership_source.read_at, e.membership_source.capture, e.membership_source.list_group],
        [page.url, page.read_at, page.file, d.category]);
    }
  }
  // Nothing is excluded for votes: members voted at 0 or below stay.
  const low = OWNER_IDS.flatMap((id) => records[id].entries.filter((e) => e.membership_source.votes.score <= 0).map((e) => `${id}/${e.name}`));
  assert.deepEqual(low.sort(), ['3/Monster Card', '3/Opal Ore', '3/Silver Ore', '5/Amethyst Ore']);
});

test('no MSEA-only item is a member', () => {
  let mseaOnly = 0;
  for (const id of OWNER_IDS) {
    const page = live(id);
    const community = new Set(page.community_drops.map((d) => d.name));
    const names = new Set(records[id].entries.map((e) => e.name));
    for (const m of page.msea_reference ?? []) {
      if (community.has(m.name)) continue;
      mseaOnly += 1;
      assert.ok(!names.has(m.name), `drops/${id}: ${m.name} is MSEA reference only`);
    }
    if (OWNER_KINDS[id] === 'monster') assert.deepEqual(records[id].meowdb_reference.msea_reference.map((m) => m.name), page.msea_reference.map((m) => m.name));
  }
  assert.ok(mseaOnly >= 10, `${mseaOnly} MSEA-only names checked`);
});

test('every rarity is Henesys.gg\'s label from the capture', () => {
  const h = c.henesys.rarity;
  for (const id of OWNER_IDS) {
    for (const e of records[id].entries) {
      const row = h.items[e.name];
      assert.ok(row, `${e.name} has a Henesys.gg row`);
      assert.deepEqual(e.rarity, { label: row.rarity, source: { authority: 'Henesys.gg', url: h.url, read_at: h.read_at, capture: h.file, row: row.row } });
      assert.ok(RARITY_LABELS.includes(e.rarity.label));
    }
  }
});

test('an item Henesys.gg has no row for keeps rarity null: listed in gaps, never a guess', () => {
  const captures = clone(c);
  delete captures.henesys.rarity.items['Garnet Ore'];
  const { records: r } = build({ captures });
  const e = r['2'].entries.find((x) => x.name === 'Garnet Ore');
  assert.equal(e.rarity, null);
  assert.equal(e.chance_category, 'etc_other', 'its category is still derived');
  assert.ok(r['2'].gaps.some((g) => g.startsWith('rarity unresolved: Henesys.gg has no row for "Garnet Ore"')), r['2'].gaps.join('\n'));
});

test('every member\'s chance category follows the rule from its MeowDB type and subtype', () => {
  const counts = Object.fromEntries(CHANCE_CATEGORIES.map((k) => [k, 0]));
  for (const id of OWNER_IDS) {
    for (const e of records[id].entries) {
      const it = items[e.item_id];
      const gate = deriveQuestGate(e.item_id, items, quests);
      assert.deepEqual(e.quest_gate, gate, `${id}/${e.key} gate`);
      assert.equal(e.chance_category, deriveChanceCategory(it, gate), `${id}/${e.key}`);
      assert.deepEqual([e.category_inputs.item_type, e.category_inputs.item_subtype, e.category_inputs.quest_gated], [it.type, it.subtype ?? null, gate != null]);
      counts[e.chance_category] += 1;
    }
  }
  assert.deepEqual(counts, { etc_own_leftover: 6, etc_quest_gated: 2, etc_other: 14, use_consumable: 17, use_scroll: 1, equip: 46, setup: 0 });
  // The rule itself, case by case.
  const it = (type, subtype) => ({ type, subtype });
  assert.equal(deriveChanceCategory(it('Etc', 'Monster Drop'), null), 'etc_own_leftover');
  assert.equal(deriveChanceCategory(it('Etc', 'Quest Item'), { quest_id: '1012' }), 'etc_quest_gated');
  assert.equal(deriveChanceCategory(it('Etc', 'Quest Item'), null), 'etc_other', 'a quest item no Maple Island quest asks for (Monster Card)');
  assert.equal(deriveChanceCategory(it('Etc', 'Ore & Mineral'), null), 'etc_other');
  assert.equal(deriveChanceCategory(it('Use', 'Potion'), null), 'use_consumable');
  assert.equal(deriveChanceCategory(it('Use', 'Arrow'), null), 'use_consumable');
  assert.equal(deriveChanceCategory(it('Use', 'Scroll'), null), 'use_scroll');
  assert.equal(deriveChanceCategory(it('Equip', 'Bottom'), null), 'equip');
  assert.equal(deriveChanceCategory(it('Setup', 'Chair'), null), 'setup');
  assert.equal(deriveChanceCategory(it('Cash', 'Pet'), null), null, 'no row: unresolved');
});

test('quest gate (D3-9): Board and Screw to Pio\'s 1012; Monster Card and Jr. Sentinel Shellpiece not gated', () => {
  for (const id of ['441', '442']) {
    const g = deriveQuestGate(id, items, quests);
    assert.deepEqual([g.quest_id, g.decision, g.verified], ['1012', 'D3-9', false]);
  }
  assert.equal(deriveQuestGate('483', items, quests), null, 'Monster Card: no Maple Island quest asks for it');
  assert.equal(deriveQuestGate('347', items, quests), null, 'Jr. Sentinel Shellpiece is a Monster Drop');
  assert.equal(deriveQuestGate(null, items, quests), null);
});

test('item ids: the one local item with the name; Red Cloth Pants by MeowDB\'s own drop entry', () => {
  const ref = { url: 'https://meowdb.com/msclassic/api/drops?monsterId=5', retrieved_at: '2026-10-04T10:07:08.887Z' };
  const pants = records['5'].entries.find((e) => e.name === 'Red Cloth Pants');
  assert.deepEqual([pants.item_id, pants.item_resolution.method, pants.item_resolution.candidates], ['1168', 'meowdb_drop_entry', ['1168', '1177']]);
  assert.deepEqual(resolveMemberItem('Red Cloth Pants', items, [{ id: 413, itemId: 1177 }], ref, 't').item_id, '1177', 'the entry decides');
  const none = resolveMemberItem('Red Cloth Pants', items, [], ref, 't');
  assert.deepEqual([none.item_id, none.item_resolution.state], [null, 'ambiguous'], 'two local items and no entry: unresolved, never guessed');
  const sole = resolveMemberItem('Snail Shell', items, [], ref, 't');
  assert.deepEqual([sole.item_id, sole.item_resolution.method, sole.item_resolution.candidates], ['348', 'exact_name', ['348']]);
  const missing = resolveMemberItem('Wooden Buckler', items, [{ id: 1, itemId: 916 }], ref, 't');
  assert.deepEqual([missing.item_id, missing.item_resolution.state, missing.item_resolution.candidates], [null, 'not_in_snapshot', ['916']]);
  throwsMerge(() => resolveMemberItem('Snail Shell', items, [{ id: 1, itemId: 349 }], ref, 't'), /the one local item named "Snail Shell" is 348/);
});

test('a cached drop entry with another item id, or a list group that is not the item\'s type, stops the build', () => {
  const cache = stubCache();
  cache['2'].community.drops.find((d) => d.itemName === 'Snail Shell').itemId = 349;
  throwsMerge(() => build({ meowdbCache: cache }), /the one local item named "Snail Shell" is 348/);
  const captures = clone(c);
  captures.meowdb.monsters['2'].community_drops.find((d) => d.name === 'Red Potion').category = 'ETC';
  throwsMerge(() => build({ captures }), /MeowDB lists it under ETC, but local item 270 is type Use/);
});

test('membership: a cache read after the page capture that names other members stops the build (newest wins)', () => {
  const later = '2026-11-01T00:00:00Z';
  const cache = stubCache();
  cache['3'].community.retrieved_at = later;
  const { records: same } = build({ meowdbCache: cache });
  assert.deepEqual(same['3'].entries.map((e) => e.name), live('3').community_drops.map((d) => d.name), 'a newer cache with the same names: the page list stands');
  cache['3'].community.drops.push({ id: 999, itemId: 270, itemName: 'Blue Potion' });
  throwsMerge(() => build({ meowdbCache: cache }), /drops\/3: MeowDB's cached community list .* is newer than the page capture tools\/meowdb\/captures\/monster_3\.json .*re-capture the page/);
  // An older cache that differs is only a discrepancy row (the page is the newest list).
  const older = stubCache();
  older['3'].community.drops.push({ id: 999, itemId: 270, itemName: 'Blue Potion' });
  const { records: r } = build({ meowdbCache: older });
  assert.deepEqual(r['3'].discrepancies[0].values[0].value, { only_in_cache: ['Blue Potion'] });
});

test('meso: MeowDB\'s report from the newest dated source; none means null; a newer report replaces the formula', () => {
  const s = records['2'].meso;
  assert.deepEqual([s.amount_state, s.min, s.max, s.amount_source.raw_value, s.amount_source.capture], ['reported', 2, 2, 'Mesos: 2 per kill | 1 report', 'tools/meowdb/captures/monster_2.txt']);
  for (const id of ['1', '3', '4', '5', '9']) {
    const m = records[id].meso;
    assert.deepEqual([m.amount_state, m.min, m.max, m.amount_source], ['not_reported', null, null, null], `drops/${id}`);
    assert.ok(m.gaps.some((g) => g.startsWith('meso amount: MeowDB has no player meso report')));
  }
  assert.equal(records['0000001'].meso, null, 'a breakable has no meso block');
  // A newer cache (after the 2026-10-05 page read) with a report for the Blue Snail: used automatically.
  const blue = c.meowdb.monsters['3'];
  const newerCache = { mesos: { url: 'https://meowdb.com/msclassic/api/mesos-reports?monsterId=3', retrieved_at: '2026-11-01T00:00:00Z',
    json: { reports: [{ id: 9, minMesos: 3, maxMesos: 5 }], summary: { count: 2, medianMin: 3, medianMax: 5 } } } };
  const m1 = buildMonsterMeso(blue, newerCache);
  assert.deepEqual([m1.amount_state, m1.min, m1.max, m1.amount_source.url, m1.amount_source.report_count], ['reported', 3, 5, newerCache.mesos.url, 2]);
  assert.match(m1.amount_source.interpretation, /uniform integer in \[3, 5\]/);
  // A newer live page capture with a report line: used too.
  const newerPage = { ...clone(blue), read_at: '2026-11-02T00:00:00Z' };
  newerPage.meso = { report_text: 'Mesos: 4 per kill | 1 report', report: { raw: 'Mesos: 4 per kill | 1 report', state: 'resolved', min: 4, max: 4, reports: 1 } };
  const m2 = buildMonsterMeso(newerPage, newerCache);
  assert.deepEqual([m2.amount_state, m2.min, m2.max, m2.amount_source.read_at], ['reported', 4, 4, '2026-11-02T00:00:00Z']);
  // An older cache report does not override a newer page that has none.
  const olderCache = { mesos: { ...newerCache.mesos, retrieved_at: '2026-10-01T00:00:00Z' } };
  assert.equal(buildMonsterMeso(blue, olderCache).amount_state, 'not_reported');
});

test('no probability, chance or quantity in a canonical drop record', () => {
  const bad = new Set(['probability', 'chance', 'chance_source', 'chance_state', 'normalized_probability', 'quantity', 'rate', 'drop_chance']);
  const walk = (node, where) => {
    if (Array.isArray(node)) node.forEach((x, i) => walk(x, `${where}[${i}]`));
    else if (node && typeof node === 'object') {
      for (const [k, v] of Object.entries(node)) {
        if (['notes', 'gaps', 'discrepancies'].includes(k)) continue;
        assert.ok(!bad.has(k), `${where}.${k}`);
        walk(v, `${where}.${k}`);
      }
    }
  };
  for (const id of OWNER_IDS) walk(records[id], `drops/${id}`);
});
