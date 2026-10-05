// node --test tools/sources/test/
// The schema v2 drop records (game/data/canonical/drops/*.json, contract C1) against the dated captures and the
// reviewed crosswalk (tools/sources/crosswalk/drop_items.json), and the merge's fail-hard rules
// (tools/sources/drops_merge.mjs). Runs without the git-ignored MeowDB cache: the merge gets a minimal cache stand-in,
// so the parts of a record that come from the cache (meowdb_reference ids, the cached meso report) are not compared.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { loadCaptures, REPO_ROOT } from '../captures.mjs';
import { parseKuroPercent, parseReactorChanceValue, parseHiddenStreetMesos, parseMeowdbMesoReport, entryKey, sameItemName } from '../parse.mjs';
import {
  buildDropRecords, loadCrosswalk, loadLocalItems, loadLocalQuests, deriveQuestGate, resolveMeowdbItem, matchKuroRow,
  DropMergeError, OWNER_IDS, REACTOR_QUANTITY,
} from '../drops_merge.mjs';

const c = loadCaptures();
const crosswalk = loadCrosswalk();
const items = loadLocalItems();
const quests = loadLocalQuests();
const record = (id) => JSON.parse(fs.readFileSync(path.join(REPO_ROOT, 'game/data/canonical/drops', `${id}.json`), 'utf8'));
const records = Object.fromEntries(OWNER_IDS.map((id) => [id, record(id)]));
const monsters = OWNER_IDS.filter((id) => crosswalk.owners[id].kind === 'monster');

/** A stand-in for MeowDB's cached lists: empty lists, no cached meso reports. */
function stubCache() {
  const out = {};
  for (const id of OWNER_IDS) {
    out[id] = { community: { url: `https://meowdb.com/msclassic/api/drops?monsterId=${id}`, retrieved_at: '2026-10-04T00:00:00Z', drops: [] }, msea: [], msea_page: null, mesos: { url: 'https://meowdb.com/x', retrieved_at: '2026-10-04T00:00:00Z', json: { reports: [] } } };
  }
  return out;
}

const merge = (overrides = {}) => buildDropRecords({ captures: c, crosswalk, items, quests, meowdbCache: stubCache(), ...overrides });
const clone = (x) => structuredClone(x);
const throwsMerge = (fn, pattern) => assert.throws(fn, (e) => e instanceof DropMergeError && pattern.test(e.message), `expected DropMergeError ${pattern}`);

test('a fresh merge reproduces the committed entries, KuroDB-only rows, meso and provenance', () => {
  const { records: fresh } = merge();
  for (const id of OWNER_IDS) {
    const a = fresh[id];
    const b = records[id];
    assert.deepEqual(a.entries, b.entries, `drops/${id} entries`);
    assert.deepEqual(a.excluded_kuro_only, b.excluded_kuro_only, `drops/${id} excluded_kuro_only`);
    assert.deepEqual(a.provenance, b.provenance, `drops/${id} provenance`);
    assert.deepEqual(a.gaps, b.gaps, `drops/${id} gaps`);
    const strip = (m) => (m ? { ...m, discrepancies: (m.discrepancies ?? []).filter((d) => d.authority !== 'MeowDB MS Classic') } : m);
    assert.deepEqual(strip(a.meso), strip(b.meso), `drops/${id} meso (cached-report discrepancy aside)`);
    assert.equal(b.schema_version, 2);
  }
});

test('membership is authoritative: monster entries are exactly Hidden Street\'s lists, the box\'s exactly MeowDB\'s', () => {
  for (const id of monsters) {
    const hs = c.hiddenstreet.monsters[crosswalk.owners[id].hidden_street_slug];
    const r = records[id];
    assert.equal(r.membership_authority, 'Hidden Street');
    assert.deepEqual(r.entries.map((e) => e.name), hs.items.map((i) => i.name), `drops/${id}: every Hidden Street member, in page order`);
    for (const e of r.entries) {
      const m = hs.items.find((i) => i.name === e.name);
      assert.equal(e.key, entryKey(e.name));
      assert.equal(e.membership_source.raw_value, m.raw_lines.join('\n'), `${e.name}: verbatim Hidden Street lines`);
      assert.deepEqual([e.membership_source.url, e.membership_source.read_at, e.membership_source.capture], [hs.url, hs.read_at, hs.file]);
    }
  }
  const box = records['0000001'];
  assert.equal(box.membership_authority, 'MeowDB MS Classic');
  assert.deepEqual(box.entries.map((e) => e.name), c.meowdb.breakables['0000001'].community_drops.map((d) => d.name));
  assert.deepEqual(monsters.map((id) => records[id].entries.length), [1, 11, 12, 15, 15, 17], 'members per monster: 1/11/12/15/15/17');
});

test('KuroDB-only rows never enter a table; every KuroDB row is matched or excluded', () => {
  for (const id of monsters) {
    const kuro = c.kurodb.monsters[crosswalk.owners[id].kuro_monster_id];
    const r = records[id];
    const matched = r.entries.filter((e) => e.chance_source).map((e) => `${e.chance_source.kuro_item_id}|${e.chance_source.kuro_name}`);
    const excluded = r.excluded_kuro_only.map((x) => `${x.kuro_item_id}|${x.name}`);
    assert.deepEqual([...matched, ...excluded].sort(), kuro.rows.map((k) => `${k.kuro_item_id}|${k.name}`).sort(), `drops/${id}: each KuroDB row once`);
    for (const x of r.excluded_kuro_only) {
      assert.ok(!r.entries.some((e) => sameItemName(e.name, x.name)), `${x.name} is not a member of ${id}`);
      assert.equal(x.raw_value, kuro.rows.find((k) => k.kuro_item_id === x.kuro_item_id && k.name === x.name).raw);
    }
  }
  assert.deepEqual(monsters.map((id) => records[id].excluded_kuro_only.length), [0, 7, 13, 10, 18, 15]);
  for (const name of ['Snail Card', 'Bronze Ore', 'Garnet Ore', 'Sword']) {
    assert.ok(!records['2'].entries.some((e) => e.name === name), `Snail never drops the KuroDB-only ${name}`);
  }
});

test('chances re-parse from the KuroDB raw values (p% -> p/100, reactor N -> 1/N)', () => {
  for (const id of OWNER_IDS) {
    for (const e of records[id].entries) {
      if (e.chance_state !== 'resolved') {
        assert.equal(e.probability, null);
        assert.equal(e.chance_source, null);
        continue;
      }
      const cs = e.chance_source;
      const p = cs.format === 'percent_base' ? parseKuroPercent(cs.raw_value) : parseReactorChanceValue(cs.raw_value);
      assert.equal(cs.normalized_probability, p.probability, `${id}/${e.key}`);
      assert.equal(e.probability, p.probability);
      assert.ok(e.probability > 0 && e.probability <= 1);
      assert.equal(cs.kuro_quest_condition, p.quest ?? null);
      if (cs.format === 'percent_base') assert.deepEqual({ min: e.quantity.min, max: e.quantity.max }, p.qty);
      else assert.deepEqual(e.quantity, clone(REACTOR_QUANTITY), 'reactor quantity is the labelled adaptation');
    }
  }
  const om = Object.fromEntries(records['9'].entries.map((e) => [e.key, e]));
  assert.equal(om['brown-hard-leather-boots'].probability, 0.0008, '"0.0800% base" is 0.0008');
  assert.equal(om['red-potion'].probability, 0.02, '"2.00% base" is 0.02, not 2 or 0.0002');
  const box = Object.fromEntries(records['0000001'].entries.map((e) => [e.key, e]));
  assert.equal(box.apple.probability, 0.25, '"Chance value 4" is 1/4');
  assert.equal(box['old-wooden-board'].probability, 1);
});

test('never join by id across sites', () => {
  const om = records['9'].entries.find((e) => e.key === 'orange-mushroom-cap');
  assert.equal(om.chance_source.kuro_item_id, '4000001');
  assert.equal(om.item_id, '356', 'KuroDB 4000001 is Orange Mushroom Cap; MeowDB game_item_id 4000001 is Snail Shell (348)');
  assert.equal(items['348'].game_item_id, '4000001');
  const bs = records['3'].entries.find((e) => e.key === 'blue-snail-shell');
  assert.deepEqual([bs.chance_source.kuro_item_id, bs.item_id], ['4000000', '349']);
  assert.equal(items['347'].game_item_id, '4000000', 'MeowDB game_item_id 4000000 is the Jr. Sentinel Shellpiece');
  const apple = records['0000001'].entries.find((e) => e.key === 'apple');
  assert.deepEqual([apple.chance_source.kuro_item_id, apple.item_id], ['2010000', '236']);
  assert.equal(items['235'].game_item_id, '2010000', 'KuroDB Apple 2010000 is MeowDB Roger\'s Apple\'s game_item_id');
});

test('meso amount: MeowDB report for the Snail, Hidden Street otherwise; chance: KuroDB 40%; none for the Sentinel and the box', () => {
  const s = records['2'].meso;
  assert.equal(s.amount_source.authority, 'MeowDB MS Classic');
  assert.deepEqual([s.min, s.max], [parseMeowdbMesoReport(c.meowdb.monsters['2'].meso.report.raw).min, 2]);
  assert.ok(s.discrepancies.some((d) => d.authority === 'Hidden Street' && d.raw_value === 'Mesos: 1'), 'Hidden Street "Mesos: 1" recorded');
  for (const [id, slug] of [['3', 'blue-snail'], ['4', 'shroom'], ['5', 'red-snail'], ['9', 'orange-mushroom']]) {
    const m = records[id].meso;
    const hs = parseHiddenStreetMesos(c.hiddenstreet.monsters[slug].mesos.raw);
    assert.equal(m.amount_source.authority, 'Hidden Street');
    assert.deepEqual([m.min, m.max], [hs.min, hs.max], `drops/${id}`);
    assert.equal(m.amount_source.interpretation == null, hs.min === hs.max, 'a range is labelled as an interpretation');
  }
  for (const id of ['2', '3', '4', '5', '9']) {
    const m = records[id].meso;
    assert.equal(m.chance_source.authority, 'KuroDB');
    assert.equal(m.chance_source.raw_value, '40% base | Meso drop');
    assert.equal(m.probability, 0.4);
    assert.ok(!JSON.stringify(m.chance_source).includes('dropChancePct'), 'MeowDB\'s form constant is never a chance');
  }
  assert.deepEqual(['2', '3', '4', '5', '9'].map((id) => [records[id].meso.min, records[id].meso.max]), [[2, 2], [4, 4], [4, 6], [8, 12], [9, 13]]);
  assert.equal(records['1'].meso, null, 'Tutorial Jr. Sentinel: no KuroDB meso row (D3-5)');
  assert.equal(records['0000001'].meso, null);
});

test('quest gates follow the C1 rule: Board and Screw gated to 1012, the Shellpiece not', () => {
  const box = Object.fromEntries(records['0000001'].entries.map((e) => [e.key, e]));
  assert.equal(box['old-wooden-board'].quest_gate.quest_id, '1012');
  assert.equal(box['rusty-screw'].quest_gate.quest_id, '1012');
  assert.equal(box.apple.quest_gate, null);
  const shell = records['1'].entries[0];
  assert.equal(shell.quest_gate, null);
  assert.equal(shell.chance_source.kuro_quest_condition, '1035', 'KuroDB\'s flag recorded as corroboration only');
  for (const id of OWNER_IDS) for (const e of records[id].entries) if (e.quest_gate) assert.equal(e.quest_gate.verified, false);
  assert.equal(deriveQuestGate('441', false, items, quests).quest_id, '1012', 'MeowDB subtype Quest Item + quest 1012 objective');
  assert.equal(deriveQuestGate('347', false, items, quests), null, '347 is subtype Monster Drop');
  assert.equal(deriveQuestGate('236', false, items, quests), null);
  const twice = clone(quests);
  twice['1011'].objectives.item_collection.push({ item_id: '441', count: 1 });
  assert.throws(() => deriveQuestGate('441', false, items, twice), DropMergeError, 'two quests asking for one quest item');
});

test('unresolved members stay visible: in entries, item_id or probability null, listed in gaps', () => {
  for (const id of OWNER_IDS) {
    const r = records[id];
    for (const e of r.entries) {
      const rolls = e.chance_state === 'resolved' && e.item_id != null;
      if (!rolls) assert.ok(r.gaps.some((g) => g.includes(`"${e.name}"`)), `drops/${id}: "${e.name}" in gaps`);
    }
  }
  const om = Object.fromEntries(records['9'].entries.map((e) => [e.key, e]));
  assert.deepEqual([om['omok-piece-mushroom'].chance_state, om['omok-piece-mushroom'].item_id, om['omok-piece-mushroom'].item_resolution.state], ['resolved', null, 'ambiguous']);
  assert.deepEqual(om['omok-piece-mushroom'].item_resolution.candidates, ['486', '495', '498']);
  assert.deepEqual([om['scroll-for-shoes-for-jump-10'].item_id, om['scroll-for-shoes-for-jump-10'].chance_state], ['177', 'unresolved']);
  assert.ok(records['9'].excluded_kuro_only.some((x) => x.kuro_item_id === '2040705' && /D3-8/.test(x.reason)), 'the unconfirmed KuroDB scroll row is excluded with its reason');
  const egg = records['0000001'].entries.find((e) => e.key === 'egg');
  assert.deepEqual([egg.item_id, egg.chance_state, egg.probability], ['237', 'unresolved', null]);
});

test('every resolved item id is a local MeowDB item', () => {
  for (const id of OWNER_IDS) for (const e of records[id].entries) if (e.item_id != null) assert.ok(items[e.item_id], `drops/${id} ${e.item_id}`);
});

// --- the merge refuses what the sources do not support -------------------------------------------------------

const mutate = (fn) => { const cw = clone(crosswalk); fn(cw); return cw; };
const rowOf = (cw, owner, name) => cw.owners[owner].rows.find((r) => r.name === name);

test('a Hidden Street member without a crosswalk row, or a row without a member, fails', () => {
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { cw.owners['2'].rows = cw.owners['2'].rows.filter((r) => r.name !== 'Blue Potion'); }) }), /"Blue Potion" has no crosswalk row/);
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { cw.owners['2'].rows.push({ ...clone(rowOf(cw, '2', 'Blue Potion')), name: 'Bronze Ore' }); }) }), /"Bronze Ore" is not on Hidden Street/);
});

test('a KuroDB claim must name a row on the page, by its own id and name; "none" must be true', () => {
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { rowOf(cw, '2', 'Snail Shell').kurodb.kuro_item_id = '4000001'; }) }), /expected exactly one/);
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { rowOf(cw, '2', 'Red Potion').kurodb = { state: 'none', evidence: 'x' }; }) }), /none but the KuroDB page lists Red Potion/);
  throwsMerge(() => merge({ crosswalk: mutate((cw) => {
    rowOf(cw, '2', 'Blue Potion').kurodb = { state: 'matched', kuro_item_id: '2000000', kuro_name: 'Red Potion', method: 'alias_with_evidence', evidence: 'x' };
  }) }), /also claimed/);
});

test('a resolved item must exist locally and match by name; an unresolved one whose candidate became local fails', () => {
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { rowOf(cw, '2', 'Wooden Buckler').meowdb = { state: 'resolved', item_id: '916', method: 'exact', candidates: [], evidence: 'x' }; }) }), /not a local item/);
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { rowOf(cw, '2', 'Blue Potion').meowdb.item_id = '271'; }) }), /"exact" but MeowDB 271/);
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { rowOf(cw, '2', 'Red Cloth Pants (M)').meowdb.item_id = '1177'; }) }), /needs gender male/);
  const withBuckler = { ...items, 916: { id: '916', name: 'Wooden Buckler', gender: 'any' } };
  throwsMerge(() => merge({ items: withBuckler }), /candidate 916 is now a local item/);
});

test('every crosswalk row carries a reviewer note, and the record entry keeps it', () => {
  for (const id of OWNER_IDS) {
    for (const row of crosswalk.owners[id].rows) {
      assert.ok(typeof row.reviewer_note === 'string' && row.reviewer_note.trim() !== '', `${id} "${row.name}": reviewer_note`);
      const e = records[id].entries.find((x) => x.name === row.name);
      assert.equal(e.notes[0], row.reviewer_note, `drops/${id} "${row.name}": notes[0] is the reviewer note`);
    }
  }
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { rowOf(cw, '2', 'Blue Potion').reviewer_note = ''; }) }), /"Blue Potion": reviewer_note is required/);
  throwsMerge(() => merge({ crosswalk: mutate((cw) => { delete rowOf(cw, '0000001', 'Egg').reviewer_note; }) }), /"Egg": reviewer_note is required/);
  // A member whose possible KuroDB row was not accepted says so in its gap (not "no row").
  const gap = records['9'].gaps.find((g) => g.includes('"Scroll for Shoes for Jump 10%"') && g.startsWith('chance unresolved'));
  assert.match(gap, /possible row Scroll for Shoes for Jump \(2040705, "0\.0300% base \| Qty 1"\) that is not accepted/);
});

test('crosswalk helpers', () => {
  assert.throws(() => resolveMeowdbItem('Pan Lid', { state: 'resolved', item_id: null, method: 'none', candidates: [], evidence: 'x' }, items, 't'), DropMergeError);
  assert.equal(matchKuroRow('Egg', { state: 'none', evidence: 'x' }, [{ kuro_item_id: '1', name: 'Apple' }], 't'), null);
});
