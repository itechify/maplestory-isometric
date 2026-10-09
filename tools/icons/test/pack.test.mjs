// node --test tools/icons/test/
// The pack rules (pack.mjs), without the network: the IDs taken from the game data, what an answer means for a
// variant (the 1x1 rejection among them), how a miss is recorded, and the shape and stability of pack.json.
import { tempDir, png, dataDir, itemJson } from './fixtures.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { SOURCE } from '../lib.mjs';
import { wantedIds, pngSize, judgeImage, originsOf, nextPack, stringifyPack, presentCounts, summaryLine } from '../pack.mjs';

const GAME_DATA = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..', 'game', 'data');
const answer = (body, extra = {}) => ({ url: 'https://maplestory.io/x', status: 200, contentType: 'image/png', body, retrieved_at: '2026-10-09T17:00:00.000Z', ...extra });
const ok = (url, body, origin, fetched = '2026-10-09') => {
  const j = judgeImage(answer(body, { url, retrieved_at: `${fetched}T12:00:00.000Z` }));
  return { state: 'ok', record: { url, sha256: j.sha256, size: j.size, origin, fetched: j.fetched } };
};

test('the IDs are every game_item_id plus every item_icon_key / icon_key, and the formulas skills', () => {
  const ids = wantedIds(GAME_DATA);
  assert.equal(ids.items.length, 94, 'the 94 items the game data refers to');
  assert.deepEqual(ids.skills, ['0001000', '0001001', '0001002'], 'the Beginner skills');
  for (const id of ['2000000', '4000001', '4031000', '1302000', '1432000', '3010000']) assert.ok(ids.items.includes(id), id);
  assert.deepEqual(ids.items, [...ids.items].sort((a, b) => Number(a) - Number(b)), 'sorted');
  assert.equal(new Set(ids.items).size, ids.items.length, 'unique');
});

test('an icon key outside the item records counts; a key that only contains the name does not', () => {
  const root = dataDir({ items: ['2000000'], keyed: ['4031000', '2000000'], skills: ['0001000'] });
  fs.writeFileSync(path.join(root, 'canonical', 'quests', '2.json'), JSON.stringify({
    styles: [{ icon_key: 1302000 }, { icon_key: null }, { icon_key: { nested: '9999998' } }],
    provenance: { 'objectives.item_usage[0].item_icon_key': { raw_value: '9999999' } },
  }));
  assert.deepEqual(wantedIds(root), { items: ['1302000', '2000000', '4031000'], skills: ['0001000'] });
});

test('a whole PNG larger than 1x1 is an icon; a blank 1x1 image, another body or a 404 is a miss with its reason', () => {
  const icon = judgeImage(answer(png(27, 30)));
  assert.equal(icon.state, 'ok');
  assert.deepEqual(icon.size, [27, 30]);
  assert.equal(icon.fetched, '2026-10-09');
  assert.match(icon.sha256, /^[0-9a-f]{64}$/);
  assert.deepEqual(pngSize(png(32, 32)), { width: 32, height: 32 });
  assert.deepEqual(judgeImage(answer(png(1, 1))), { state: 'gone', reason: 'blank 1x1 image' });
  assert.deepEqual(judgeImage(answer(Buffer.from('<html>busy</html>'), { contentType: 'text/html' })), { state: 'gone', reason: 'not a PNG (text/html)' });
  assert.deepEqual(judgeImage(answer(png(27, 30).subarray(0, 40))), { state: 'gone', reason: 'not a PNG (image/png)' }, 'a truncated PNG');
  assert.deepEqual(judgeImage(answer(Buffer.from('Item does not have an icon'), { status: 404 })), { state: 'gone', reason: 'http 404' });
  assert.deepEqual(judgeImage({ url: 'x', status: null, reason: 'not cached (--offline)' }), { state: 'none', reason: 'not cached (--offline)' });
});

test('the origins come from the item metadata; an unknown item (200 null) or a malformed body gives none', () => {
  const meta = (text, status = 200) => ({ status, body: Buffer.from(text) });
  assert.deepEqual(originsOf(meta(itemJson('2000000', { x: -3, y: 30 }, { x: -3, y: 29 }))), { icon: [-3, 30], iconRaw: [-3, 29] });
  assert.deepEqual(originsOf(meta('null')), { icon: null, iconRaw: null });
  assert.deepEqual(originsOf(meta('{"metaInfo": {"iconOrigin": {"x": 0, "y": 0, "isEmpty": true}}}')), { icon: null, iconRaw: null });
  assert.deepEqual(originsOf(meta('{not json')), { icon: null, iconRaw: null });
  assert.deepEqual(originsOf(meta('Not found', 404)), { icon: null, iconRaw: null });
  assert.equal(originsOf({ status: null, reason: 'network error' }), null, 'no answer: the origin is unknown');
});

test('a miss is recorded with its reason, and an icon obtained later replaces it', () => {
  const ids = { items: ['2000000'], skills: ['0001000'] };
  const url = 'https://maplestory.io/api/MCW/CBT2/item/2000000/icon';
  const outcomes = new Map([
    ['item/2000000/icon', ok(url, png(27, 30), [-3, 30])],
    ['item/2000000/iconRaw', { state: 'gone', reason: 'http 404' }],
    ['skill/0001000/icon', { state: 'gone', reason: 'blank 1x1 image' }],
  ]);
  const pack = nextPack(null, ids, outcomes);
  assert.deepEqual(Object.keys(pack.items['2000000']), ['icon']);
  assert.deepEqual(pack.missing, [
    { kind: 'item', id: '2000000', variant: 'iconRaw', reason: 'http 404' },
    { kind: 'skill', id: '0001000', variant: 'icon', reason: 'blank 1x1 image' },
  ]);
  assert.deepEqual(pack.skills, {}, 'a skill with no variant has no entry');
  outcomes.set('item/2000000/iconRaw', ok(url + 'Raw', png(27, 27), [-3, 30]));
  const later = nextPack(pack, ids, outcomes);
  assert.deepEqual(Object.keys(later.items['2000000']), ['icon', 'iconRaw']);
  assert.equal(later.missing.length, 1, 'only the skill is still missing');
});

test('a variant without an answer keeps its record or its miss; an ID the data no longer names is dropped', () => {
  const ids = { items: ['2000000', '4000001'], skills: [] };
  const first = nextPack(null, ids, new Map([
    ['item/2000000/icon', ok('u1', png(27, 30), [-3, 30], '2026-10-01')],
    ['item/4000001/icon', { state: 'gone', reason: 'http 404' }],
  ]));
  const again = nextPack(first, ids, new Map());
  assert.equal(stringifyPack(again), stringifyPack(first), 'no answers: the same pack');
  const fewer = nextPack(first, { items: ['4000001'], skills: [] }, new Map());
  assert.deepEqual(fewer.items, {});
  assert.deepEqual(fewer.missing, [{ kind: 'item', id: '4000001', variant: 'icon', reason: 'http 404' }]);
  const otherVersion = nextPack({ ...first, source: { ...SOURCE, version: 'CBT1' } }, ids, new Map());
  assert.deepEqual([otherVersion.items, otherVersion.missing], [{}, []], 'a pack of another version is not carried over');
});

test('the fetched date changes only when the bytes change', () => {
  const ids = { items: ['2000000'], skills: [] };
  const first = nextPack(null, ids, new Map([['item/2000000/icon', ok('u', png(27, 30), [-3, 30], '2026-10-01')]]));
  const same = nextPack(first, ids, new Map([['item/2000000/icon', ok('u', png(27, 30), [-4, 30], '2026-10-09')]]));
  assert.equal(same.items['2000000'].icon.fetched, '2026-10-01', 'same bytes: the first date stays');
  assert.deepEqual(same.items['2000000'].icon.origin, [-4, 30], 'a corrected origin is still taken');
  const changed = nextPack(first, ids, new Map([['item/2000000/icon', ok('u', png(27, 30, 7), [-3, 30], '2026-10-09')]]));
  assert.equal(changed.items['2000000'].icon.fetched, '2026-10-09', 'new bytes: the date of their fetch');
  assert.notEqual(changed.items['2000000'].icon.sha256, first.items['2000000'].icon.sha256);
});

test('pack.json has the format 1 shape, in a fixed order, one line per variant', () => {
  const ids = { items: ['4000001', '2000000'], skills: ['0001000'] };
  const outcomes = new Map([
    ['item/4000001/icon', ok('https://maplestory.io/api/MCW/CBT2/item/4000001/icon', png(26, 27), [-4, 27])],
    ['item/2000000/icon', ok('https://maplestory.io/api/MCW/CBT2/item/2000000/icon', png(27, 30), [-3, 30])],
    ['item/2000000/iconRaw', ok('https://maplestory.io/api/MCW/CBT2/item/2000000/iconRaw', png(27, 27), [-3, 30])],
    ['skill/0001000/iconDisabled', ok('s3', png(32, 32, 3), null)],
    ['skill/0001000/icon', ok('s1', png(32, 32, 1), null)],
    ['skill/0001000/iconMouseOver', ok('s2', png(32, 32, 2), null)],
    ['item/4000001/iconRaw', { state: 'gone', reason: 'http 404' }],
  ]);
  const text = stringifyPack(nextPack(null, { items: [...ids.items].sort(), skills: ids.skills }, outcomes));
  const doc = JSON.parse(text);
  assert.deepEqual(Object.keys(doc), ['format', 'name', 'source', 'items', 'skills', 'missing']);
  assert.equal(doc.format, 1);
  assert.equal(doc.name, 'maplestory_io');
  assert.deepEqual(doc.source, { service: 'maplestory.io', region: 'MCW', version: 'CBT2' });
  assert.deepEqual(Object.keys(doc.items), ['2000000', '4000001']);
  assert.deepEqual(Object.keys(doc.items['2000000']), ['icon', 'iconRaw']);
  assert.deepEqual(Object.keys(doc.skills['0001000']), ['icon', 'iconMouseOver', 'iconDisabled'], 'the variants in their order');
  const red = doc.items['2000000'].icon;
  assert.deepEqual(Object.keys(red), ['url', 'sha256', 'size', 'origin', 'fetched']);
  assert.deepEqual([red.size, red.origin, red.fetched], [[27, 30], [-3, 30], '2026-10-09']);
  assert.deepEqual(Object.keys(doc.skills['0001000'].icon), ['url', 'sha256', 'size', 'fetched'], 'no origin: no key');
  assert.deepEqual(doc.missing, [{ kind: 'item', id: '4000001', variant: 'iconRaw', reason: 'http 404' }]);
  const lines = text.split('\n');
  assert.ok(lines.includes(`      "icon": {"url": "https://maplestory.io/api/MCW/CBT2/item/2000000/icon", "sha256": "${red.sha256}", "size": [27, 30], "origin": [-3, 30], "fetched": "2026-10-09"},`), 'one line per variant');
  assert.ok(text.endsWith('}\n'));
  assert.equal(stringifyPack(JSON.parse(text)), text, 'the text of the parsed pack is the same text');
  assert.equal(stringifyPack(nextPack(null, { items: [], skills: [] }, new Map())),
    '{\n  "format": 1,\n  "name": "maplestory_io",\n  "source": {"service": "maplestory.io", "region": "MCW", "version": "CBT2"},\n' +
    '  "items": {},\n  "skills": {},\n  "missing": []\n}\n', 'an empty pack');
});

test('the summary line counts the IDs whose every variant is in the pack folder', () => {
  const dir = tempDir();
  const ids = { items: ['2000000', '4000001'], skills: ['0001000'] };
  for (const v of ['icon', 'iconRaw']) {
    fs.mkdirSync(path.join(dir, 'items', '2000000'), { recursive: true });
    fs.writeFileSync(path.join(dir, 'items', '2000000', `${v}.png`), png(2, 2));
  }
  fs.mkdirSync(path.join(dir, 'items', '4000001'), { recursive: true });
  fs.writeFileSync(path.join(dir, 'items', '4000001', 'icon.png'), png(2, 2));
  const present = presentCounts(dir, ids);
  assert.deepEqual(present, { items: 1, skills: 0 });
  assert.equal(summaryLine(present, ids), 'icons: 1/2 items, 0/1 skills present (maplestory.io MCW/CBT2)');
  assert.equal(summaryLine(present, ids, { gone: 1, none: 4, why: '--offline' }),
    'icons: 1/2 items, 0/1 skills present (maplestory.io MCW/CBT2); 1 variant missing at maplestory.io; 4 variants not reached (--offline)');
});
