// node --test tools/sources/test/
// KuroDB item page captures (tools/kurodb/captures/item_<kuro id>.json, tools/sources/captures.mjs kuroItemPage) and how
// the drop merge settles a crosswalk candidate with one (decision D3-8, drops_merge.mjs judgeKuroCandidate): the
// Orange Mushroom's "Scroll for Shoes for Jump" row (KuroDB 2040705) against Hidden Street's "Scroll for Shoes for Jump
// 10%" (MeowDB 177: success rate 10%, Jump +3). Every page here is SYNTHETIC (tools/sources/test/fixtures/): nobody has
// read KuroDB item 2040705, and no test writes into the real capture folders; each case copies them to a temp root.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadCaptures, CAPTURE_DIRS, REPO_ROOT, statBonusesIn, successRateIn, statKey, SCROLL_STAT_KEYS } from '../captures.mjs';
import { buildDropRecords, loadCrosswalk, loadLocalItems, loadLocalQuests, judgeKuroCandidate, DropMergeError, OWNER_IDS, KURO_ONLY_REASON } from '../drops_merge.mjs';

const FIXTURE = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, 'tools/sources/test/fixtures/kurodb_item_page.synthetic.json'), 'utf8'));
const crosswalk = loadCrosswalk();
const items = loadLocalItems();
const quests = loadLocalQuests();
const CAPTURE = 'tools/kurodb/captures/item_2040705.json';
const MEMBER = 'scroll-for-shoes-for-jump-10';

/**
 * A temp copy of every capture folder plus extra files {name in tools/kurodb/captures: content}. The real KuroDB item
 * page captures (item_<id>.json) are left out of the copy, so each case holds exactly the item pages it names: once
 * the real page of 2040705 is read, "without the capture" still means without it.
 */
function rootWith(extra = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'kuro-item-'));
  for (const dir of Object.values(CAPTURE_DIRS)) {
    fs.cpSync(path.join(REPO_ROOT, dir), path.join(root, dir), { recursive: true, filter: (src) => !/^item_\d+\.json$/.test(path.basename(src)) || !src.replace(/\\/g, '/').includes('/kurodb/captures/') });
  }
  for (const [name, body] of Object.entries(extra)) fs.writeFileSync(path.join(root, 'tools/kurodb/captures', name), typeof body === 'string' ? body : JSON.stringify(body));
  return root;
}
const page = (patch = {}) => ({ ...FIXTURE, ...patch });
const withText = (from, to) => page({ text: FIXTURE.text.replace(from, to) });

function stubCache() {
  const out = {};
  for (const id of OWNER_IDS) {
    out[id] = { community: { url: `https://meowdb.com/msclassic/api/drops?monsterId=${id}`, retrieved_at: '2026-10-04T00:00:00Z', drops: [] }, msea: [], msea_page: null, mesos: { url: 'https://meowdb.com/x', retrieved_at: '2026-10-04T00:00:00Z', json: { reports: [] } } };
  }
  return out;
}

/** The Orange Mushroom record merged with the given extra capture files. */
function om(extra) {
  const root = rootWith(extra);
  try {
    return buildDropRecords({ captures: loadCaptures({ root }), crosswalk, items, quests, meowdbCache: stubCache() }).records['9'];
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
}
const rowKeys = (rows) => rows.map((x) => `${x.kuro_item_id}|${x.name}`);

function everyRowOnce(rec) {
  const kuro = loadCaptures().kurodb.monsters['1210102'];
  const matched = rec.entries.filter((e) => e.chance_source).map((e) => `${e.chance_source.kuro_item_id}|${e.chance_source.kuro_name}`);
  assert.deepEqual([...matched, ...rowKeys(rec.excluded_kuro_only), ...rowKeys(rec.pending_kuro_candidates)].sort(),
    kuro.rows.map((k) => `${k.kuro_item_id}|${k.name}`).sort(), 'matched, excluded or pending: each KuroDB row once');
}

test('the item page reader: name, category, description, stats, success rate, stat bonuses, drop rows', () => {
  const root = rootWith({ 'item_2040705.json': FIXTURE });
  const p = loadCaptures({ root }).kurodb.item_pages['2040705'];
  fs.rmSync(root, { recursive: true, force: true });
  assert.deepEqual([p.file, p.authority, p.kuro_item_id, p.url], [CAPTURE, 'KuroDB', '2040705', 'https://playkuro.com/database/#items/2040705']);
  assert.deepEqual([p.name, p.category], ['Scroll for Shoes for Jump', 'Use']);
  assert.equal(p.description, 'Improves Jump on shoes.\nSuccess rate: 10%, Jump +3');
  assert.deepEqual(p.stats, [{ label: 'PRICE', value: '1 mesos' }]);
  assert.deepEqual(p.success_rate, { pct: 10, raw: 'Success rate: 10%', source: 'description' });
  assert.deepEqual([p.stat_bonuses, p.stat_bonuses_source], [{ jump: 3 }, 'description']);
  assert.deepEqual(p.monster_drops.map((d) => [d.monster_name, d.raw, d.probability]), [['Orange Mushroom', '0.0300% base | Qty 1', 0.0003]]);
  assert.deepEqual(p.reactor_drops, []);
});

test('the reader takes the scroll facts from ITEM STATS rows too, and refuses a page that contradicts itself', () => {
  const stats = withText('PRICE\n1 mesos', 'PRICE\n1 mesos\nSUCCESS RATE\n10%\nJUMP\n+3');
  const root = rootWith({ 'item_2040705.json': stats });
  const p = loadCaptures({ root }).kurodb.item_pages['2040705'];
  fs.rmSync(root, { recursive: true, force: true });
  assert.deepEqual(p.success_rate, { pct: 10, raw: 'SUCCESS RATE: 10%', source: 'item stats' });
  assert.deepEqual([p.stat_bonuses, p.stat_bonuses_source], [{ jump: 3 }, 'item stats']);
  const bad = (body, re) => {
    const r = rootWith({ 'item_2040705.json': body });
    try {
      assert.throws(() => loadCaptures({ root: r }), re);
    } finally {
      fs.rmSync(r, { recursive: true, force: true });
    }
  };
  bad(withText('PRICE\n1 mesos', 'PRICE\n1 mesos\nSUCCESS RATE\n60%'), /success rate differs between ITEM STATS \(60%\) and the description \(10%\)/);
  bad(withText('PRICE\n1 mesos', 'PRICE\n1 mesos\nJUMP\n+2'), /stat bonuses differ/);
  bad(page({ kuro_item_id: '2040704' }), /kuro_item_id "2040704" differs from the file name item_2040705\.json/);
  bad(page({ url: 'https://playkuro.com/database/#items/2040704' }), /is not KuroDB's page of item 2040705/);
  bad(withText('ITEM · 2040705', 'ITEM · 2040704'), /the page says ITEM · 2040704, the file is item 2040705/);
  bad(page({ read_at: '2026-10-05 08:00' }), /not an ISO 8601 timestamp/);
  bad(withText('Orange Mushroom\n0.0300% base | Qty 1', 'Orange Mushroom\nabout 3 in 10000'), /not a KuroDB "<p>% base" value/);
});

test('a numeric file name is a monster page: an item page saved under one is refused with a clear message', () => {
  const root = rootWith({ '2040705.json': FIXTURE });
  try {
    assert.throws(() => loadCaptures({ root }), /2040705\.json: this is a KuroDB ITEM page \("ITEM · 2040705"\): save it as item_<kuro item id>\.json/);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
  const odd = rootWith({ '555.json': { kuro_monster_id: '555', text: 'something else' } });
  try {
    assert.throws(() => loadCaptures({ root: odd }), /a numeric KuroDB capture name is a monster page: expected kuro_monster_id and text starting "MONSTER · 555"/);
  } finally {
    fs.rmSync(odd, { recursive: true, force: true });
  }
});

test('stat names and rates in free text', () => {
  assert.deepEqual(statBonusesIn('Improves Jump on shoes.\nSuccess rate: 10%, Jump +3'), { jump: 3 });
  assert.deepEqual(statBonusesIn('Success rate: 60%, Weapon Def. +4, Magic Def. +2'), { wdef: 4, mdef: 2 });
  assert.deepEqual(statBonusesIn('success rate:10%, jump+2, DEX +1'), { jump: 2, dex: 1 });
  assert.deepEqual(statBonusesIn('no bonus here'), {});
  assert.equal(successRateIn('Success Rate 60%'), 60);
  assert.equal(successRateIn('Improves Jump on shoes.'), null);
  assert.equal(statKey('Weapon Def.'), 'wdef');
  assert.equal(statKey('Speed'), 'speed');
  // Item.wz property names, as a database page may print them.
  assert.deepEqual(['incJump', 'INC PAD', 'incPDD', 'incEVA', 'incMHP', 'incINT'].map(statKey), ['jump', 'watk', 'wdef', 'avoid', 'hp', 'int']);
  assert.equal(statKey('Improves jump on shoes'), 'improvesjumponshoes', 'an unknown name keeps its letters');
  assert.ok(!SCROLL_STAT_KEYS.includes(statKey('Improves jump on shoes')) && !SCROLL_STAT_KEYS.includes(statKey('incSlots')));
  // The shipped MeowDB scroll descriptions read back as their own stat blocks (the rule's other side).
  for (const id of ['139', '143', '177', '59', '61']) {
    assert.deepEqual(statBonusesIn(items[id].description), items[id].scroll.stat_bonus_on_success, `MeowDB ${id}`);
    assert.equal(successRateIn(items[id].description), items[id].scroll.success_rate_pct, `MeowDB ${id}`);
  }
});

test('without the capture the row is a pending candidate; the member never rolls', () => {
  const rec = om({});
  const e = rec.entries.find((x) => x.key === MEMBER);
  assert.deepEqual([e.item_id, e.chance_state, e.probability], ['177', 'unresolved', null]);
  assert.deepEqual(rec.pending_kuro_candidates.map((x) => [x.kuro_item_id, x.member, x.decision]), [['2040705', MEMBER, 'D3-8']]);
  assert.ok(!rowKeys(rec.excluded_kuro_only).includes('2040705|Scroll for Shoes for Jump'), 'not filed as KuroDB-only');
  assert.ok(rec.excluded_kuro_only.every((x) => x.reason === KURO_ONLY_REASON), 'excluded_kuro_only holds only rows with no member');
  everyRowOnce(rec);
});

test('a page that shows MeowDB 177\'s rate and stat confirms the row: the member rolls at the KuroDB chance, the page cited', () => {
  const rec = om({ 'item_2040705.json': FIXTURE });
  const e = rec.entries.find((x) => x.key === MEMBER);
  assert.deepEqual([e.chance_state, e.probability, e.quantity.min, e.quantity.max], ['resolved', 0.0003, 1, 1]);
  const cs = e.chance_source;
  assert.deepEqual([cs.authority, cs.kuro_item_id, cs.kuro_name, cs.match_method, cs.raw_value, cs.capture],
    ['KuroDB', '2040705', 'Scroll for Shoes for Jump', 'alias_with_evidence', '0.0300% base | Qty 1', 'tools/kurodb/captures/1210102.json']);
  assert.deepEqual([cs.match_evidence.capture, cs.match_evidence.url, cs.match_evidence.decision], [CAPTURE, FIXTURE.url, 'D3-8']);
  assert.match(cs.match_evidence.shows, /Success rate: 10%.*\{"jump":3\}/);
  assert.deepEqual(rec.pending_kuro_candidates, []);
  assert.ok(!rec.gaps.some((g) => g.includes('"Scroll for Shoes for Jump 10%"')), 'no chance gap left');
  assert.ok(e.notes.some((n) => n.includes('confirmed by its item page')));
  everyRowOnce(rec);
});

test('a page that shows another rate or stat rejects the row: KuroDB-only, the member a real gap', () => {
  for (const [variant, re] of [[withText('Success rate: 10%, Jump +3', 'Success rate: 60%, Jump +1'), /success rate is 60%.*MeowDB 177's is 10%/],
    [withText('Success rate: 10%, Jump +3', 'Success rate: 10%, Jump +2, DEX +1'), /stat bonuses are \{"dex":1,"jump":2\}/]]) {
    const rec = om({ 'item_2040705.json': variant });
    const e = rec.entries.find((x) => x.key === MEMBER);
    assert.equal(e.chance_state, 'unresolved');
    const x = rec.excluded_kuro_only.find((r) => r.kuro_item_id === '2040705');
    assert.ok(x, 'moved to excluded_kuro_only');
    assert.match(x.reason, re);
    assert.match(x.reason, /it shows another item/);
    assert.deepEqual(rec.pending_kuro_candidates, []);
    assert.ok(rec.gaps.some((g) => g.includes('"Scroll for Shoes for Jump 10%"') && g.includes(`whose item page (${CAPTURE}) it shows another item`)));
    everyRowOnce(rec);
  }
});

test('a page that shows no rate or stat does not settle it: excluded as not settled, never guessed', () => {
  const rec = om({ 'item_2040705.json': withText('Success rate: 10%, Jump +3', 'A scroll for shoes.') });
  const e = rec.entries.find((x) => x.key === MEMBER);
  assert.equal(e.chance_state, 'unresolved');
  const x = rec.excluded_kuro_only.find((r) => r.kuro_item_id === '2040705');
  assert.match(x.reason, /it does not settle it: the page shows no success rate; the page shows no stat bonus/);
  everyRowOnce(rec);
  // The page lists the Orange Mushroom at another chance than its monster page: KuroDB disagrees with itself.
  const off = om({ 'item_2040705.json': withText('Orange Mushroom\n0.0300% base | Qty 1', 'Orange Mushroom\n0.0500% base | Qty 1') });
  assert.match(off.excluded_kuro_only.find((r) => r.kuro_item_id === '2040705').reason, /MONSTER DROPS row for Orange Mushroom reads "0\.0500% base \| Qty 1", the monster page "0\.0300% base \| Qty 1"/);
});

test('a page whose bonus the reader cannot name stops the merge: never judged as "another item"', () => {
  // ITEM STATS in Item.wz names: understood, and the same scroll.
  const wz = om({ 'item_2040705.json': withText('PRICE\n1 mesos', 'PRICE\n1 mesos\nSUCCESS\n10%\nINCJUMP\n+3') });
  assert.equal(wz.entries.find((x) => x.key === MEMBER).chance_state, 'resolved');
  // A bonus name nothing maps ("Improves jump on shoes +3"): the merge fails instead of rejecting the row.
  assert.throws(() => om({ 'item_2040705.json': withText('Success rate: 10%, Jump +3', 'Success rate: 10%\nImproves jump on shoes +3') }),
    (err) => err instanceof DropMergeError && /stat bonus name\(s\) "improvesjumponshoes" that map to no MeowDB scroll stat/.test(err.message));
});

test('the copied capture folders hold only the item pages a case names', () => {
  const root = rootWith({});
  try {
    const names = fs.readdirSync(path.join(root, 'tools/kurodb/captures'));
    assert.deepEqual(names.filter((n) => /^item_\d+\.json$/.test(n)), [], 'no real item page leaks into a case');
    assert.ok(names.includes('1210102.json'), 'the monster pages are copied');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test('the merge refuses a capture that is not the candidate\'s page, and a candidate without a rule', () => {
  assert.throws(() => om({ 'item_2040705.json': withText('\nScroll for Shoes for Jump\n', '\nScroll for Shoes for Speed\n') }),
    (err) => err instanceof DropMergeError && /is "Scroll for Shoes for Speed", the candidate row is "Scroll for Shoes for Jump"/.test(err.message));
  const cand = { kuro_item_id: '2040705', kuro_name: 'Scroll for Shoes for Jump', reason: 'r' };
  assert.throws(() => judgeKuroCandidate({ cand, page: { file: CAPTURE, name: 'Scroll for Shoes for Jump' }, memberItem: items['177'], monsterRow: { raw: 'x' }, monsterName: 'Orange Mushroom', where: 't' }),
    /needs confirm_with/);
  assert.deepEqual(judgeKuroCandidate({ cand, page: null, where: 't' }), { outcome: 'pending' });
  assert.throws(() => judgeKuroCandidate({ cand: { ...cand, confirm_with: 'meowdb_scroll' }, page: { file: CAPTURE, name: 'Scroll for Shoes for Jump', monster_drops: [] }, memberItem: items['236'], monsterRow: { raw: 'x' }, monsterName: 'Orange Mushroom', where: 't' }),
    /has no scroll block/);
});
