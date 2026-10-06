// node --test tools/meowdb/test/
// The fetch helper (lib.mjs fetchUrl): cache first, one rate-limited request on a miss, --offline and --refresh. No test
// touches the network: globalThis.fetch is a stub that counts its calls, and MEOWDB_CACHE_DIR points the cache (and the
// cross-process rate gate) at a fresh temporary folder.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const CACHE = fs.mkdtempSync(path.join(os.tmpdir(), 'meowdb-cache-test-'));
process.env.MEOWDB_CACHE_DIR = CACHE;
const { fetchUrl, fetchPage, hasCached, CACHE_DIR, BASE_URL } = await import('../lib.mjs');
test.after(() => fs.rmSync(CACHE, { recursive: true, force: true }));

const MIN_GAP_MS = 1200; // lib.mjs's gap between requests

/** Replaces globalThis.fetch for the duration of `fn`; returns the calls [{url, at}]. Each call answers `body(url)`. */
async function withFetch(fn, body = (url) => `<html>${url}</html>`) {
  const calls = [];
  const real = globalThis.fetch;
  globalThis.fetch = async (url) => {
    calls.push({ url: String(url), at: Date.now() });
    return new Response(body(String(url)), { status: 200 });
  };
  try {
    await fn();
  } finally {
    globalThis.fetch = real;
  }
  return calls;
}

let n = 0;
const fresh = () => `${BASE_URL}/test-page-${++n}`; // never cached, never captured

test('the cache folder is the MEOWDB_CACHE_DIR override', () => {
  assert.equal(CACHE_DIR, path.resolve(CACHE));
});

test('a cache miss is fetched once and cached; the next read makes no request', async () => {
  const url = fresh();
  assert.equal(hasCached(url), false);
  let first;
  const calls = await withFetch(async () => { first = await fetchUrl(url); });
  assert.deepEqual(calls.map((c) => c.url), [url]);
  assert.equal(first.fromCache, false);
  assert.equal(first.html, `<html>${url}</html>`);
  assert.equal(hasCached(url), true, 'body and meta written');
  let second;
  const again = await withFetch(async () => { second = await fetchUrl(url); });
  assert.equal(again.length, 0, 'served from the cache');
  assert.equal(second.fromCache, true);
  assert.equal(second.html, first.html);
  assert.equal(second.retrieved_at, first.retrieved_at, 'the cache keeps the time of the fetch');
});

test('a run over a full cache makes no request', async () => {
  const urls = [fresh(), fresh()];
  await withFetch(async () => { for (const u of urls) await fetchUrl(u); });
  const calls = await withFetch(async () => {
    for (const u of urls) await fetchUrl(u);
    await fetchPage(urls[0].slice(BASE_URL.length));
  });
  assert.equal(calls.length, 0);
});

test('requests are at least 1.2 s apart', async () => {
  const calls = await withFetch(async () => {
    await fetchUrl(fresh());
    await fetchUrl(fresh());
  });
  assert.equal(calls.length, 2);
  assert.ok(calls[1].at - calls[0].at >= MIN_GAP_MS - 5, `gap ${calls[1].at - calls[0].at} ms`);
});

test('--offline: a miss throws "not cached" and makes no request; a cached page is still served', async () => {
  const cached = fresh();
  await withFetch(async () => { await fetchUrl(cached); });
  const missing = fresh();
  const calls = await withFetch(async () => {
    await assert.rejects(fetchUrl(missing, { offline: true }), /^Error: not cached: /);
    assert.equal((await fetchUrl(cached, { offline: true })).fromCache, true);
    process.argv.push('--offline');
    try {
      await assert.rejects(fetchUrl(missing), /not cached/, 'the command-line flag');
    } finally {
      process.argv.pop();
    }
  });
  assert.equal(calls.length, 0);
  assert.equal(hasCached(missing), false);
});

test('--refresh re-fetches a cached page; with --offline it is an error', async () => {
  const url = fresh();
  await withFetch(async () => { await fetchUrl(url); });
  let r;
  const calls = await withFetch(async () => { r = await fetchUrl(url, { refresh: true }); }, () => 'new body');
  assert.equal(calls.length, 1);
  assert.equal(r.fromCache, false);
  assert.equal((await fetchUrl(url)).html, 'new body', 'the cache holds the new body');
  await assert.rejects(fetchUrl(url, { refresh: true, offline: true }), /--offline/);
});

test('a hand-read API capture is served on a miss without a request', async () => {
  const url = BASE_URL + '/api/items/242?locale=en&preview=1'; // tools/meowdb/captures/items_api.json
  let r;
  const calls = await withFetch(async () => { r = await fetchUrl(url, { offline: true }); });
  assert.equal(calls.length, 0);
  assert.equal(r.fromCapture, true);
  assert.equal(hasCached(url), false, 'a capture is not written to the cache');
});
