// node --test tools/icons/test/
// The fetch helper (lib.mjs fetchAnswer) and whole runs (fetch_pack.mjs run) against a stub: cache first, which
// answers are cached, --offline and --refresh, a body that breaks off, giving up without a network or after error
// after error, and pack.json left byte-for-byte as it was by a cache-hit run, an --offline run and a run without a
// network, but written by a run that got errors for one ID and by runs that stopped asking after errors that never
// clear. globalThis.fetch is a stub that counts its calls.
import { CACHE, tempDir, png, withFetch, dataDir, itemJson } from './fixtures.mjs';
import test, { afterEach } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fetchAnswer, hasCached, cacheFiles, network, CACHE_DIR, itemUrl, itemIconUrl, skillIconUrl } from '../lib.mjs';
import { run } from '../fetch_pack.mjs';

const MIN_GAP_MS = 1200; // lib.mjs's gap between requests
let n = 0;
// Every test starts with a run that has not given up yet.
const startOver = () => Object.assign(network, { failures: 0, errors: 0, stopped: false, down: false, reason: '' });
afterEach(startOver);
const fresh = () => `https://maplestory.io/api/MCW/CBT2/item/test-${++n}/icon`; // never cached

/** maplestory.io as the stub plays it: icons for the IDs in `art`, the metadata of each, a 404 for anything else. */
function site(art) {
  return (url) => {
    const m = /\/item\/(\d+)(?:\/(icon|iconRaw))?$/.exec(url) ?? /\/skill\/(\d+)\/(\w+)$/.exec(url);
    const id = m?.[1];
    if (!id || !(id in art)) return { status: 404, body: 'Item does not have an icon or a default effect', type: 'text/plain' };
    if (!m[2]) return { body: itemJson(id), type: 'application/json' };
    const a = art[id][m[2]];
    return a === undefined ? { status: 404, body: 'not found' } : Buffer.isBuffer(a) ? { body: a, type: 'image/png' } : a;
  };
}

test('the cache folder is the ICONS_CACHE_DIR override', () => {
  assert.equal(CACHE_DIR, path.resolve(CACHE));
});

test('an answer is fetched once with a User-Agent naming the project, cached byte for byte, then read from the cache', async () => {
  const url = fresh();
  const body = png(27, 30);
  let first;
  const calls = await withFetch(async () => { first = await fetchAnswer(url); }, () => ({ body, type: 'image/png' }));
  assert.deepEqual(calls.map((c) => c.url), [url]);
  assert.match(calls[0].headers['User-Agent'], /MisoStory/);
  assert.equal(first.fromCache, false);
  assert.ok(first.body.equals(body));
  assert.equal(hasCached(url), true);
  let second;
  const again = await withFetch(async () => { second = await fetchAnswer(url); }, () => { throw new Error('no request expected'); });
  assert.equal(again.length, 0, 'served from the cache');
  assert.equal(second.fromCache, true);
  assert.ok(second.body.equals(body), 'the same bytes');
  assert.equal(second.contentType, 'image/png');
  assert.equal(second.retrieved_at, first.retrieved_at, 'the cache keeps the time of the fetch');
});

test('a 404 is cached; a 500 is no answer and is not cached; requests are at least 1.2 s apart', async () => {
  const gone = fresh();
  const busy = fresh();
  let a404, a500;
  const calls = await withFetch(async () => {
    a404 = await fetchAnswer(gone);
    a500 = await fetchAnswer(busy, { attempts: 1 });
  }, (url) => ({ status: url === gone ? 404 : 500, body: 'x' }));
  assert.equal(calls.length, 2);
  assert.ok(calls[1].at - calls[0].at >= MIN_GAP_MS - 5, `gap ${calls[1].at - calls[0].at} ms`);
  assert.equal(a404.status, 404);
  assert.equal(hasCached(gone), true, 'maplestory.io said it does not exist');
  assert.deepEqual([a500.status, a500.reason], [null, 'maplestory.io answered http 500']);
  assert.equal(hasCached(busy), false, 'a transient failure is asked again next run');
});

/** A 200 whose body breaks off after the headers (a dropped connection; a stalled one times out the same way). */
const brokenBody = () => ({ body: new ReadableStream({ start(c) { c.error(new TypeError('terminated')); } }), type: 'image/png' });

test('a body that breaks off is no answer, not a crash, and is not cached', async () => {
  const url = fresh();
  let r;
  const calls = await withFetch(async () => { r = await fetchAnswer(url, { attempts: 2 }); }, brokenBody);
  assert.equal(calls.length, 2, 'tried again');
  assert.deepEqual([r.status, r.reason], [null, 'network error: TypeError']);
  assert.equal(hasCached(url), false);
});

test('a run whose download breaks off still records the rest and prints its line', async () => {
  const data = dataDir({ items: ['2000300'], skills: [] });
  const pack = tempDir('icons-pack-');
  const served = site({ 2000300: { icon: png(24, 26), iconRaw: png(24, 24) } });
  let r;
  await withFetch(async () => { r = await run({ packDir: pack, dataDir: data, attempts: 1 }); },
    (url) => (url === itemIconUrl('2000300', 'icon') ? brokenBody() : served(url)));
  assert.equal(r.line, 'icons: 0/1 items, 0/0 skills present (maplestory.io MCW/CBT2); 1 variant not reached (network error: TypeError)');
  assert.equal(r.wrote, true);
  assert.deepEqual(Object.keys(JSON.parse(fs.readFileSync(path.join(pack, 'pack.json'), 'utf8')).items['2000300']), ['iconRaw']);
});

test('--offline makes no request; --refresh re-fetches; both together are an error', async () => {
  const url = fresh();
  const calls = await withFetch(async () => {
    assert.deepEqual(await fetchAnswer(url, { offline: true }), { url, status: null, reason: 'not cached (--offline)', fromCache: false });
  }, () => ({ body: png(2, 2) }));
  assert.equal(calls.length, 0);
  await withFetch(async () => { await fetchAnswer(url); }, () => ({ body: png(2, 2) }));
  let r;
  const refreshed = await withFetch(async () => { r = await fetchAnswer(url, { refresh: true }); }, () => ({ body: png(3, 3) }));
  assert.equal(refreshed.length, 1);
  assert.equal(r.fromCache, false);
  assert.ok((await fetchAnswer(url)).body.equals(png(3, 3)), 'the cache holds the new body');
  await assert.rejects(fetchAnswer(url, { refresh: true, offline: true }), /--offline/);
});

test('after three URLs in a row that cannot reach maplestory.io the run stops asking', async () => {
  const urls = [fresh(), fresh(), fresh(), fresh()];
  const answers = [];
  const calls = await withFetch(async () => {
    for (const u of urls) answers.push(await fetchAnswer(u, { attempts: 1 }));
  }, () => { throw new TypeError('fetch failed'); });
  assert.equal(calls.length, 3, 'the fourth URL is not asked');
  assert.deepEqual([network.stopped, network.down], [true, true]);
  assert.deepEqual(answers.map((a) => a.status), [null, null, null, null]);
  assert.equal(answers[3].reason, 'network unavailable');
});

test('an error status means the network is up; the run stops asking after ten URLs in a row got one', async () => {
  const urls = Array.from({ length: 13 }, () => fresh());
  const answers = [];
  const calls = await withFetch(async () => {
    for (const u of urls) answers.push(await fetchAnswer(u, { attempts: 1 }));
  }, (url) => {
    if (urls.indexOf(url) < 2) throw new TypeError('fetch failed');
    return { status: 503, body: 'busy' };
  });
  assert.equal(calls.length, 12, 'two URLs that could not reach it and ten errors; the thirteenth is not asked');
  assert.equal(network.stopped, true);
  assert.equal(network.down, false, 'it answered');
  assert.equal(network.failures, 0, 'an error status resets the URLs that could not reach it');
  assert.equal(answers[2].reason, 'maplestory.io answered http 503');
  assert.equal(answers[12].reason, 'maplestory.io answered http 503', 'the summary says why, not "network unavailable"');
});

test('a run builds the pack; a second run makes no request and leaves pack.json as it was', async () => {
  const data = dataDir({ items: ['2000000'], keyed: ['4031000'], skills: ['0001000'] });
  const pack = tempDir('icons-pack-');
  const art = {
    2000000: { icon: png(27, 30), iconRaw: png(27, 27) },
    4031000: { icon: png(1, 1), iconRaw: png(25, 25) }, // a blank icon: a miss
    '0001000': { icon: png(32, 32, 1), iconMouseOver: png(32, 32, 2), iconDisabled: { body: '<html>oops</html>', type: 'text/html' } },
  };
  let first;
  const calls = await withFetch(async () => { first = await run({ packDir: pack, dataDir: data }); }, site(art));
  assert.equal(calls.length, 2 * 3 + 3, 'per item its metadata and two icons, per skill three icons');
  assert.ok(calls.some((c) => c.url === skillIconUrl('0001000', 'icon')));
  assert.equal(first.line, 'icons: 1/2 items, 0/1 skills present (maplestory.io MCW/CBT2); 2 variants missing at maplestory.io');
  assert.equal(first.wrote, true);
  const text = fs.readFileSync(path.join(pack, 'pack.json'), 'utf8');
  const doc = JSON.parse(text);
  assert.deepEqual(doc.items['2000000'].icon.origin, [-3, 30]);
  assert.equal(doc.items['2000000'].icon.url, itemIconUrl('2000000', 'icon'));
  assert.deepEqual(doc.missing, [
    { kind: 'item', id: '4031000', variant: 'icon', reason: 'blank 1x1 image' },
    { kind: 'skill', id: '0001000', variant: 'iconDisabled', reason: 'not a PNG (text/html)' },
  ]);
  assert.ok(fs.readFileSync(path.join(pack, 'items', '2000000', 'iconRaw.png')).equals(art[2000000].iconRaw), 'the PNG in the pack');
  assert.equal(fs.existsSync(path.join(pack, 'items', '4031000', 'icon.png')), false, 'a miss writes no PNG');
  const mtime = fs.statSync(path.join(pack, 'items', '2000000', 'icon.png')).mtimeMs;
  let second;
  const again = await withFetch(async () => { second = await run({ packDir: pack, dataDir: data }); }, () => { throw new Error('no request expected'); });
  assert.equal(again.length, 0, 'everything from the cache');
  assert.equal(second.wrote, false);
  assert.equal(fs.readFileSync(path.join(pack, 'pack.json'), 'utf8'), text, 'byte-for-byte');
  assert.equal(fs.statSync(path.join(pack, 'items', '2000000', 'icon.png')).mtimeMs, mtime, 'an unchanged PNG is not rewritten');
});

test('--offline with an empty cache reports nothing present and never writes pack.json', async () => {
  const data = dataDir({ items: ['2000100', '2000101'], skills: ['0001001'] });
  const pack = tempDir('icons-pack-');
  const committed = '{"format": 1, "kept": "byte for byte"}\n';
  fs.writeFileSync(path.join(pack, 'pack.json'), committed);
  let r;
  const calls = await withFetch(async () => { r = await run({ packDir: pack, dataDir: data, offline: true }); }, () => { throw new Error('no request expected'); });
  assert.equal(calls.length, 0);
  assert.equal(r.line, 'icons: 0/2 items, 0/1 skills present (maplestory.io MCW/CBT2); 7 variants not reached (--offline)');
  assert.equal(fs.readFileSync(path.join(pack, 'pack.json'), 'utf8'), committed);
  assert.equal(r.wrote, false);
});

test('a run without a network keeps the committed pack.json; the PNGs the cache holds still reach the pack', async () => {
  const built = tempDir('icons-pack-');
  await withFetch(async () => { await run({ packDir: built, dataDir: dataDir({ items: ['2000199', '2000200'], skills: [] }) }); },
    site({ 2000199: { icon: png(21, 21), iconRaw: png(21, 20) }, 2000200: { icon: png(20, 20), iconRaw: png(20, 19) } }));
  const committed = fs.readFileSync(path.join(built, 'pack.json'), 'utf8');
  // A fresh checkout whose game data has since dropped 2000199 and added 2000201: the committed pack.json, no PNGs, a
  // cache that lacks 2000200's metadata, then no network at all. A written pack would drop 2000199.
  fs.rmSync(cacheFiles(itemUrl('2000200')).metaFile);
  const clone = tempDir('icons-pack-');
  fs.writeFileSync(path.join(clone, 'pack.json'), committed);
  let r;
  await withFetch(async () => { r = await run({ packDir: clone, dataDir: dataDir({ items: ['2000200', '2000201'], skills: [] }), attempts: 1 }); },
    () => { throw new TypeError('fetch failed'); });
  assert.equal(network.down, true, 'three URLs in a row that could not reach maplestory.io');
  assert.equal(r.wrote, false);
  assert.equal(fs.readFileSync(path.join(clone, 'pack.json'), 'utf8'), committed, 'byte-for-byte, 2000199 and all');
  assert.equal(r.line, 'icons: 1/2 items, 0/0 skills present (maplestory.io MCW/CBT2); 2 variants not reached (network unavailable)');
  assert.ok(fs.readFileSync(path.join(clone, 'items', '2000200', 'icon.png')).equals(png(20, 20)), 'the cached PNG');
});

test('a run in which maplestory.io answers errors for one ID writes pack.json and asks for the IDs after it', async () => {
  // An item it serves, then a skill whose three URLs it answers 500 (as it does for the /job/... paths), then a skill
  // it serves. One ID's errors must not stop the run nor keep the item and the second skill out of pack.json.
  const data = dataDir({ items: ['2000400'], skills: ['0001400', '0001401'] });
  const pack = tempDir('icons-pack-');
  const served = site({
    2000400: { icon: png(22, 22), iconRaw: png(22, 21) },
    '0001401': { icon: png(32, 32), iconMouseOver: png(32, 32, 1), iconDisabled: png(32, 32, 2) },
  });
  let r;
  const calls = await withFetch(async () => { r = await run({ packDir: pack, dataDir: data, attempts: 1 }); },
    (url) => (url.includes('/skill/0001400/') ? { status: 500, body: 'Internal Server Error' } : served(url)));
  assert.equal(calls.length, 3 + 3 + 3, 'every URL asked');
  assert.equal(network.stopped, false);
  assert.equal(r.line, 'icons: 1/1 items, 1/2 skills present (maplestory.io MCW/CBT2); 3 variants not reached (maplestory.io answered http 500)');
  assert.equal(r.wrote, true);
  const doc = JSON.parse(fs.readFileSync(path.join(pack, 'pack.json'), 'utf8'));
  assert.deepEqual([Object.keys(doc.items), Object.keys(doc.skills), doc.missing], [['2000400'], ['0001401'], []], 'an error is not a miss');
});

test('a run in which maplestory.io keeps answering errors stops asking but writes pack.json, from an empty cache or not', async () => {
  // An item and a skill it serves, then four skills of a job whose .img it lacks: it answers 500 to all twelve of their
  // URLs (as it does for 500.img). An error is not cached, so a later run asks those URLs again, and only those: ten of
  // them are ten in a row on every run.
  const data = dataDir({ items: ['2000500'], skills: ['0001500', '5001001', '5001002', '5001003', '5001005'] });
  const served = site({
    2000500: { icon: png(23, 23), iconRaw: png(23, 22) },
    '0001500': { icon: png(32, 32), iconMouseOver: png(32, 32, 1), iconDisabled: png(32, 32, 2) },
  });
  const answer = (url) => (url.includes('/500.img/') ? { status: 500, body: 'Internal Server Error' } : served(url));
  const line = 'icons: 1/1 items, 1/5 skills present (maplestory.io MCW/CBT2); 12 variants not reached (maplestory.io answered http 500)';
  const recorded = (pack) => {
    const doc = JSON.parse(fs.readFileSync(path.join(pack, 'pack.json'), 'utf8'));
    return [Object.keys(doc.items), Object.keys(doc.skills), doc.missing];
  };
  const first = tempDir('icons-pack-');
  let r;
  const calls = await withFetch(async () => { r = await run({ packDir: first, dataDir: data, attempts: 1 }); }, answer);
  assert.equal(calls.length, 3 + 3 + 10, 'the IDs it serves, then ten errors in a row');
  assert.deepEqual([network.stopped, network.down], [true, false], 'it stopped asking; the network is up');
  assert.equal(r.line, line);
  assert.equal(r.wrote, true);
  assert.deepEqual(recorded(first), [['2000500'], ['0001500'], []]);
  // A fresh checkout sharing the cache: everything it serves is a cache hit.
  startOver();
  const second = tempDir('icons-pack-');
  const again = await withFetch(async () => { r = await run({ packDir: second, dataDir: data, attempts: 1 }); }, answer);
  assert.equal(again.length, 10, 'only URLs that got an error');
  assert.ok(again.every((c) => c.url.includes('/500.img/')));
  assert.deepEqual([network.stopped, network.down], [true, false]);
  assert.equal(r.line, line);
  assert.equal(r.wrote, true);
  assert.deepEqual(recorded(second), [['2000500'], ['0001500'], []]);
});
