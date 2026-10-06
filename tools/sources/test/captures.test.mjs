// node --test tools/sources/test/
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadCaptures, apiCaptureFor, textCapture, AUTHORITIES, CAPTURE_DIRS, REPO_ROOT, RARITY_LABELS } from '../captures.mjs';
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
    c.henesys.rarity, ...Object.values(c.meowdb.monsters), ...Object.values(c.meowdb.breakables), ...Object.values(c.meowdb.quests),
    c.meowdb.quest_tracker, ...Object.values(c.meowdb.items_api.items), ...Object.values(c.meowdb.item_pages),
  ];
  assert.ok(all.length >= 14);
  for (const x of all) assert.ok(isIsoTimestamp(x.read_at), `${x.file}: ${x.read_at}`);
  assert.equal(c.meowdb.quest_tracker.read_at, '2026-10-05T07:30Z', 'normalized from "07:3x" (header note)');
  assert.match(c.meowdb.quest_tracker.read_at_note, /07:3x/);
});

test('Henesys.gg rarity capture: one label per drop-list item, read by hand', () => {
  const r = c.henesys.rarity;
  assert.equal(r.file, 'tools/henesys/captures/item_rarity.json');
  assert.equal(r.authority, 'Henesys.gg');
  assert.equal(r.url, 'https://henesys.gg/loot');
  assert.equal(r.read_at, '2026-10-06T05:17:21.423Z');
  assert.match(r.site_notice, /Unauthorized reproduction or scraping/);
  assert.equal(Object.keys(r.items).length, 64);
  for (const it of Object.values(r.items)) assert.ok(RARITY_LABELS.includes(it.rarity), it.name);
  assert.deepEqual(Object.values(r.items).filter((it) => it.rarity !== 'Common').map((it) => [it.name, it.rarity]),
    [['Overall Armor DEF Scroll: Intermediate', 'Rare']]);
  assert.equal(r.items['Snail Shell'].row, 'Snail Shell | Monster Drop | A shell removed from a snail. | Common');
  // Every name on a MeowDB community list has a row.
  const names = new Set([...Object.values(c.meowdb.monsters), ...Object.values(c.meowdb.breakables)].flatMap((m) => m.community_drops.map((d) => d.name)));
  assert.deepEqual([...names].filter((n) => !r.items[n]), []);
});

test('a Henesys.gg rarity capture that does not read is an error', () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'captures-henesys-'));
  const f = path.join(root, 'tools/henesys/captures/item_rarity.json');
  let n = 0;
  const expectError = (mutate, re) => {
    const r = path.join(root, `r${++n}`);
    for (const dir of Object.values(CAPTURE_DIRS)) fs.cpSync(path.join(REPO_ROOT, dir), path.join(r, dir), { recursive: true });
    const p = path.join(r, 'tools/henesys/captures/item_rarity.json');
    const j = JSON.parse(fs.readFileSync(p, 'utf8'));
    mutate(j);
    fs.writeFileSync(p, JSON.stringify(j));
    assert.throws(() => loadCaptures({ root: r }), re);
  };
  expectError((j) => { j.items['Snail Shell'].rarity = 'Legendary'; }, /Snail Shell: rarity "Legendary" is not one of/);
  expectError((j) => { j.items['Snail Shell'].rarity = 'Rare'; }, /Snail Shell: a row reads "Common", the rarity is Rare/);
  expectError((j) => { j.items['Snail Shell'].row = 'Blue Snail Shell | Monster Drop | x | Common'; }, /does not start with the item's name/);
  expectError((j) => { j.url = 'https://henesys.gg/items'; }, /is not https:\/\/henesys\.gg\/loot/);
  expectError((j) => { j.read_at = '2026-10-06'; }, /not an ISO 8601/);
  expectError((j) => { delete j.site_notice; }, /site_notice/);
  assert.ok(!fs.existsSync(f));
  fs.rmSync(root, { recursive: true, force: true });
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
    assert.equal(c.meowdb.monsters[id].meso.report.state, 'none', `monster ${id} has no meso report (D3-12)`);
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
  fs.writeFileSync(path.join(root, 'tools/henesys/captures/stray.txt'), 'x');
  assert.throws(() => loadCaptures({ root }), /unrecognised capture file/);
  fs.rmSync(path.join(root, 'tools/henesys/captures/stray.txt'));
  const q = path.join(root, 'tools/meowdb/captures/quest_1008.txt');
  fs.writeFileSync(q, fs.readFileSync(q, 'utf8').replace(/READ_AT: \S+/, 'READ_AT: 2026-10-05T08:1x'));
  assert.throws(() => loadCaptures({ root }), /quest_1008\.txt.*not an ISO 8601/);
  fs.rmSync(root, { recursive: true, force: true });
});
