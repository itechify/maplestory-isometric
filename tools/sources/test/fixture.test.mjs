// node --test tools/sources/test/
// The Godot test fixture game/tests/data/drops_v2/fixture_2.json (a contract C1 Snail record) must be built from the
// real captures: every raw value, URL, read_at and capture path is checked here against tools/sources/captures.mjs,
// and every normalized value against tools/sources/parse.mjs.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { loadCaptures, REPO_ROOT } from '../captures.mjs';
import { parseKuroPercent, parseMeowdbMesoReport, entryKey } from '../parse.mjs';

const fixture = JSON.parse(fs.readFileSync(path.join(REPO_ROOT, 'game/tests/data/drops_v2/fixture_2.json'), 'utf8'));
const c = loadCaptures();
const hs = c.hiddenstreet.monsters.snail;
const kuro = c.kurodb.monsters['100100'];
const meow = c.meowdb.monsters['2'];

test('the fixture covers the task\'s cases', () => {
  const byKey = Object.fromEntries(fixture.entries.map((e) => [e.key, e]));
  assert.equal(byKey['snail-shell'].probability, 1);
  assert.equal(byKey['red-potion'].probability, 0.02);
  assert.equal(byKey['green-apple'].item_id, '242');
  assert.equal(byKey['wooden-buckler'].item_id, null);
  assert.equal(byKey['wooden-buckler'].chance_state, 'unresolved');
  assert.deepEqual(fixture.excluded_kuro_only.map((r) => r.name), ['Snail Card']);
  assert.deepEqual([fixture.meso.min, fixture.meso.max, fixture.meso.probability], [2, 2, 0.4]);
  assert.equal(fixture.meso.amount_source.authority, 'MeowDB MS Classic');
  assert.equal(fixture.meso.chance_source.authority, 'KuroDB');
});

test('membership sources quote the Hidden Street capture', () => {
  for (const e of fixture.entries) {
    const member = hs.items.find((i) => i.name === e.name);
    assert.ok(member, `${e.name} is a Hidden Street member`);
    assert.equal(e.key, entryKey(e.name));
    const ms = e.membership_source;
    assert.ok(member.raw_lines.includes(ms.raw_value), `${e.name}: raw_value is a captured line`);
    assert.deepEqual([ms.url, ms.read_at, ms.capture], [hs.url, hs.read_at, hs.file]);
  }
});

test('chance sources quote the KuroDB capture and normalize exactly', () => {
  for (const e of fixture.entries) {
    const row = kuro.rows.find((r) => r.name === e.name);
    if (e.chance_state === 'unresolved') {
      assert.equal(row, undefined, `${e.name}: no KuroDB row, so unresolved`);
      assert.equal(e.chance_source, null);
      continue;
    }
    const cs = e.chance_source;
    assert.deepEqual([cs.kuro_item_id, cs.raw_value, cs.url, cs.read_at, cs.capture], [row.kuro_item_id, row.raw, kuro.url, kuro.read_at, kuro.file]);
    const p = parseKuroPercent(cs.raw_value);
    assert.equal(cs.normalized_probability, p.probability);
    assert.equal(e.probability, p.probability);
    assert.equal(cs.conversion, p.conversion);
    assert.deepEqual({ min: e.quantity.min, max: e.quantity.max }, p.qty);
  }
  for (const x of fixture.excluded_kuro_only) {
    const row = kuro.rows.find((r) => r.kuro_item_id === x.kuro_item_id);
    assert.equal(row.raw, x.raw_value);
    assert.ok(!hs.items.some((i) => i.name === x.name), `${x.name} is KuroDB-only`);
  }
});

test('meso amount (MeowDB report) and chance (KuroDB) quote their captures', () => {
  const a = fixture.meso.amount_source;
  assert.deepEqual([a.raw_value, a.url, a.read_at, a.capture], [meow.meso.report.raw, meow.url, meow.read_at, meow.file]);
  const r = parseMeowdbMesoReport(a.raw_value);
  assert.deepEqual([fixture.meso.min, fixture.meso.max], [r.min, r.max]);
  const ch = fixture.meso.chance_source;
  assert.deepEqual([ch.raw_value, ch.url, ch.read_at, ch.capture], [kuro.meso.raw, kuro.url, kuro.read_at, kuro.file]);
  assert.equal(ch.normalized_probability, kuro.meso.probability);
  assert.equal(fixture.meso.discrepancies[0].raw_value, hs.mesos.raw, 'Hidden Street "Mesos: 1" kept as a discrepancy');
});
