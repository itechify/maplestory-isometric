// node --test tools/sources/test/
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadCaptures, apiCaptureFor, textCapture, AUTHORITIES, CAPTURE_DIRS, REPO_ROOT } from '../captures.mjs';
import { isIsoTimestamp } from '../parse.mjs';

const c = loadCaptures();

test('every capture file is loaded, each with an authority and a sha256', () => {
  const onDisk = [];
  for (const dir of Object.values(CAPTURE_DIRS)) {
    for (const f of fs.readdirSync(path.join(REPO_ROOT, dir))) if (f !== 'README.md') onDisk.push(`${dir}/${f}`);
  }
  assert.deepEqual(c.files.map((f) => f.file).sort(), onDisk.sort());
  for (const f of c.files) {
    assert.ok(Object.values(AUTHORITIES).includes(f.authority), f.file);
    assert.match(f.sha256, /^[0-9a-f]{64}$/);
  }
});

test('every capture value carries an ISO 8601 read_at', () => {
  const all = [
    ...Object.values(c.kurodb.monsters), ...Object.values(c.kurodb.reactor_items.items), ...Object.values(c.hiddenstreet.monsters),
    ...Object.values(c.meowdb.monsters), ...Object.values(c.meowdb.breakables), ...Object.values(c.meowdb.quests),
    c.meowdb.quest_tracker, ...Object.values(c.meowdb.items_api.items), ...Object.values(c.meowdb.item_pages),
  ];
  assert.ok(all.length >= 25);
  for (const x of all) assert.ok(isIsoTimestamp(x.read_at), `${x.file}: ${x.read_at}`);
  assert.equal(c.meowdb.quest_tracker.read_at, '2026-10-05T07:30Z', 'normalized from "07:3x" (header note)');
  assert.match(c.meowdb.quest_tracker.read_at_note, /07:3x/);
});

test('KuroDB monster rows: Snail', () => {
  const snail = c.kurodb.monsters['100100'];
  assert.equal(snail.name, 'Snail');
  assert.equal(snail.url, 'https://playkuro.com/database/#monsters/100100');
  assert.equal(snail.rows.length, 10, '11 drops on the page, one of them the meso row');
  assert.deepEqual(snail.rows[0], {
    kuro_item_id: '4000019', name: 'Snail Shell', raw: '100% base | Qty 1', pct: 100, probability: 1, qty: { min: 1, max: 1 },
    quest: null, parsed: snail.rows[0].parsed,
  });
  const white = snail.rows.find((r) => r.name === 'White Undershirt');
  assert.equal(white.probability, 0.0007);
  assert.equal(white.raw, '0.0700% base | Qty 1');
  assert.equal(snail.meso.raw, '40% base | Meso drop');
  assert.equal(snail.meso.probability, 0.4);
  assert.equal(snail.rows.find((r) => r.name === 'Green Apple').kuro_item_id, '2010009');
});

test('KuroDB: quest flags, the Tutorial Jr. Sentinel has no meso row', () => {
  const tut = c.kurodb.monsters['9300018'];
  assert.equal(tut.meso, null);
  assert.equal(tut.rows.length, 1);
  assert.equal(tut.rows[0].quest, '1035');
  assert.equal(tut.rows[0].probability, 1);
  const om = c.kurodb.monsters['1210102'];
  assert.equal(om.rows.find((r) => r.name === 'Omok Piece : Mushroom').probability, 0.01);
  assert.equal(om.rows.find((r) => r.name === 'Scroll for Shoes for Jump').probability, 0.0003);
  const rs = c.kurodb.monsters['130101'];
  assert.equal(rs.rows.filter((r) => r.name === 'Red Cloth Pants').length, 2, 'KuroDB lists two Red Cloth Pants rows');
  for (const m of Object.values(c.kurodb.monsters)) {
    for (const r of m.rows) assert.ok(r.probability > 0 && r.probability <= 1, `${m.name}/${r.name}`);
    if (m.meso) assert.equal(m.meso.probability, 0.4, `${m.name} meso`);
  }
});

test('KuroDB reactor 2001 values (Wooden Box, D3-7)', () => {
  const items = c.kurodb.reactor_items.items;
  const r2001 = (id) => items[id].reactor_drops.filter((d) => d.reactor_id === '2001');
  assert.deepEqual(r2001('4031162').map((d) => [d.raw, d.probability, d.quest]), [['Chance value 1 | Quest 1008', 1, '1008']]);
  assert.deepEqual(r2001('4031161').map((d) => [d.raw, d.probability, d.quest]), [['Chance value 1 | Quest 1008', 1, '1008']]);
  assert.deepEqual(r2001('2010000').map((d) => [d.raw, d.raw_n, d.probability, d.interpretation]), [['Chance value 4', 4, 0.25, '1/N']]);
  assert.deepEqual(r2001('2010002'), [], 'Egg: no reactor 2001 row (unresolved)');
  assert.equal(items['2010002'].monster_drops.length, 0);
  assert.equal(items['2010000'].monster_drops[1].probability, 0.02);
});

test('Hidden Street members and meso amounts', () => {
  const hs = c.hiddenstreet.monsters;
  assert.deepEqual(Object.keys(hs).sort(), ['blue-snail', 'orange-mushroom', 'red-snail', 'shroom', 'snail', 'tutorial-jr-sentinel']);
  assert.equal(hs.snail.items.length, 11);
  assert.deepEqual(hs.snail.mesos, { raw: 'Mesos: 1', state: 'resolved', min: 1, max: 1 });
  assert.deepEqual([hs['blue-snail'].mesos.min, hs['blue-snail'].mesos.max], [4, 4]);
  assert.deepEqual([hs.shroom.mesos.min, hs.shroom.mesos.max], [4, 6]);
  assert.deepEqual([hs['red-snail'].mesos.min, hs['red-snail'].mesos.max], [8, 12]);
  assert.deepEqual([hs['orange-mushroom'].mesos.min, hs['orange-mushroom'].mesos.max], [9, 13]);
  assert.equal(hs['tutorial-jr-sentinel'].mesos.state, 'unresolved');
  assert.deepEqual(hs['tutorial-jr-sentinel'].items.map((i) => i.name), ['Jr. Sentinel Shellpiece']);
  assert.ok(hs.snail.items.some((i) => i.name === 'Wooden Buckler'));
  assert.ok(!hs.snail.items.some((i) => i.name === 'Snail Card'), 'KuroDB-only rows are not members');
  assert.equal(hs['orange-mushroom'].items.find((i) => i.name === 'Black Cloth Pants (F)').gender, 'F');
});

test('MeowDB live monster captures: stats, meso report, community drops, map rows', () => {
  const snail = c.meowdb.monsters['2'];
  assert.deepEqual([snail.stats.level, snail.stats.hp, snail.stats.exp, snail.stats.accuracy, snail.stats.speed], [1, 45, 2, 33, -65]);
  assert.equal(snail.meso.report.raw, 'Mesos: 2 per kill | 1 report');
  assert.deepEqual([snail.meso.report.min, snail.meso.report.max, snail.meso.report.reports], [2, 2, 1]);
  assert.equal(snail.community_drops.length, 12);
  assert.ok(!snail.community_drops.some((d) => d.name === 'The Green Relaxer'), 'gone from the live list');
  assert.deepEqual(snail.community_drops.find((d) => d.name === 'Bronze Ore'), { category: 'ETC', name: 'Bronze Ore', subtype: 'Ore & Mineral', upvotes: 16, downvotes: 1, score: 15 });
  assert.equal(snail.msea_reference.length, 9);
  assert.equal(snail.map_rows.length, 13);
  assert.deepEqual(snail.map_rows[0].map_name, 'Snail Hunting Ground I');
  for (const id of ['1', '3', '4', '5', '9']) {
    assert.equal(c.meowdb.monsters[id].meso.report.state, 'none', `monster ${id} has no meso report (D3-5)`);
    assert.ok(c.meowdb.monsters[id].community_drops.length > 0);
  }
  assert.equal(c.meowdb.monsters['3'].community_drops.find((d) => d.name === 'Monster Card').downvotes, 1);
});

test('MeowDB breakable, quest and items_api captures', () => {
  const box = c.meowdb.breakables['0000001'];
  assert.equal(box.hits_to_break, 4);
  assert.deepEqual(box.community_drops.map((d) => d.name), ['Old Wooden Board', 'Rusty Screw', 'Apple', 'Egg']);
  assert.equal(box.spawns.reduce((a, s) => a + s.count, 0), 19);
  const q = c.meowdb.quests['1008'];
  assert.equal(q.name, "Lucas's Reply");
  assert.equal(q.reward_exp, 50);
  assert.equal(q.random_rewards.length, 7);
  const apple = c.meowdb.items_api.items['242'];
  assert.equal(apple.body.name, 'Green Apple');
  assert.equal(apple.read_at_approximate, true);
  assert.match(apple.read_at_note, /~08:17Z/);
});

test('MeowDB item page capture: Green Apple (242), only what the trimmed text shows', () => {
  const p = c.meowdb.item_pages['242'];
  assert.equal(p.url, 'https://meowdb.com/msclassic/item-db/242');
  assert.equal(p.read_at, '2026-10-05T22:11:30.520Z');
  assert.deepEqual([p.name, p.type, p.subtype, p.number], ['Green Apple', 'Use', 'Food', '0242']);
  assert.deepEqual(Object.fromEntries(Object.entries(p.rows).map(([k, r]) => [k, r.value])),
    { 'MP Recovery': 30, 'NPC Sell-back (per unit)': 3, 'Max per Stack': 100 });
  assert.deepEqual(p.tags, ['Tradeable']);
  assert.equal(p.description, 'A sour and crunchy green apple. Restores 30 MP.');
  assert.deepEqual(p.sections, ['Dropped By', 'MSEA Reference Drops', 'Change history']);
  assert.equal(p.community_drops_none, true);
  assert.deepEqual(p.msea_reference.map((m) => [m.monster_name, m.monster_level]), [['Mano', 20]]);
  assert.equal(p.change_history_label, 'updated in COT2');
});

test('an item page capture that does not parse is an error', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'captures-item-'));
  for (const dir of Object.values(CAPTURE_DIRS)) fs.cpSync(path.join(REPO_ROOT, dir), path.join(root, dir), { recursive: true });
  const f = path.join(root, 'tools/meowdb/captures/item_242.txt');
  const good = fs.readFileSync(f, 'utf8');
  // Each mutation is loaded from a fresh copy (loadCaptures caches per root).
  let n = 0;
  const expectError = (mutate, re) => {
    fs.writeFileSync(f, mutate(good));
    const r = path.join(root, `r${++n}`);
    for (const dir of Object.values(CAPTURE_DIRS)) fs.cpSync(path.join(root, dir), path.join(r, dir), { recursive: true });
    fs.writeFileSync(f, good);
    assert.throws(() => loadCaptures({ root: r }), re);
  };
  expectError((t) => t.replace('No. 0242', 'No. 0243'), /No\. 0243, the file is item 242/);
  expectError((t) => t.replace('item-db/242', 'item-db/243'), /is not the page of item 242/);
  expectError((t) => t.replace('Max per Stack\n100', 'Max per Stack\nmany'), /"Max per Stack" has no numeric value/);
  expectError((t) => t.replace('Tradeable\n', 'Tradeable\nRequired Level\n'), /lines no reader knows/);
  expectError((t) => t.replace('Read-only · 1 monster', 'Read-only · 2 monsters'), /but 1 monsters listed/);
  expectError((t) => t.replace('Lv 20', 'Level 20'), /has no "Lv N" line/);
  fs.rmSync(root, { recursive: true, force: true });
});

test('apiCaptureFor serves exact API URLs only', () => {
  const hit = apiCaptureFor('https://meowdb.com/msclassic/api/items/242?locale=en&preview=1');
  assert.equal(JSON.parse(hit.text).stats.mpRecover, 30);
  assert.equal(hit.capture, 'tools/meowdb/captures/items_api.json');
  assert.equal(hit.pointer, '/items/242/body');
  assert.equal(apiCaptureFor('https://meowdb.com/msclassic/api/items/242'), null, 'no partial matches');
  assert.equal(apiCaptureFor('https://meowdb.com/msclassic/item-db/242'), null, 'item pages are never served from the API capture');
  assert.equal(apiCaptureFor('https://meowdb.com/msclassic/monsters/2'), null, 'rendered-text captures are never served');
});

test('text capture headers; a bad read_at or an unknown file is an error', () => {
  const t = textCapture('URL: https://x\nREAD_AT: 2026-10-05T07:30Z\nPURPOSE: a\n   b\n---\nbody\n---\nmore');
  assert.deepEqual(t.header, { url: 'https://x', read_at: '2026-10-05T07:30Z', purpose: 'a b' });
  assert.equal(t.body, 'body\n---\nmore');
  assert.throws(() => textCapture('URL: x\nbody'));
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'captures-'));
  for (const dir of Object.values(CAPTURE_DIRS)) fs.cpSync(path.join(REPO_ROOT, dir), path.join(root, dir), { recursive: true });
  fs.writeFileSync(path.join(root, 'tools/kurodb/captures/stray.txt'), 'x');
  assert.throws(() => loadCaptures({ root }), /unrecognised capture file/);
  fs.rmSync(path.join(root, 'tools/kurodb/captures/stray.txt'));
  const q = path.join(root, 'tools/meowdb/captures/quest_1008.txt');
  fs.writeFileSync(q, fs.readFileSync(q, 'utf8').replace(/READ_AT: \S+/, 'READ_AT: 2026-10-05T08:1x'));
  assert.throws(() => loadCaptures({ root }), /quest_1008\.txt.*not an ISO 8601/);
  fs.rmSync(root, { recursive: true, force: true });
});
