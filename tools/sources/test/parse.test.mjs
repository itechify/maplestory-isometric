// node --test tools/sources/test/
import test from 'node:test';
import assert from 'node:assert/strict';
import { parseMeowdbMesoReport, entryKey, isIsoTimestamp, SourceParseError } from '../parse.mjs';

const throwsParse = (fn) => assert.throws(fn, SourceParseError);

test('MeowDB player meso reports', () => {
  assert.deepEqual(parseMeowdbMesoReport('Mesos: 2 per kill | 1 report'), { raw: 'Mesos: 2 per kill | 1 report', state: 'resolved', min: 2, max: 2, reports: 1 });
  assert.deepEqual(parseMeowdbMesoReport('Mesos: 2-4 per kill | 3 reports').max, 4);
  assert.deepEqual(parseMeowdbMesoReport('  Mesos: 5 - 7 per kill | 2 reports ').min, 5);
  throwsParse(() => parseMeowdbMesoReport('No meso reports yet.'));
  throwsParse(() => parseMeowdbMesoReport('Mesos: 4-2 per kill | 1 report'));
  throwsParse(() => parseMeowdbMesoReport('Mesos: 4 per kill | 0 reports'));
  throwsParse(() => parseMeowdbMesoReport('Mesos: -4 per kill | 1 report'));
  throwsParse(() => parseMeowdbMesoReport(4));
});

test('entry keys are stable slugs', () => {
  assert.equal(entryKey('Snail Shell'), 'snail-shell');
  assert.equal(entryKey('Overall Armor DEF Scroll: Intermediate'), 'overall-armor-def-scroll-intermediate');
  assert.equal(entryKey('Jr. Sentinel Shellpiece'), 'jr-sentinel-shellpiece');
  assert.equal(entryKey('Blue One-lined T-Shirt'), 'blue-one-lined-t-shirt');
  assert.equal(entryKey("Black Magician's Token"), 'black-magicians-token');
  throwsParse(() => entryKey('()'));
});

test('isIsoTimestamp mirrors the validator', () => {
  for (const good of ['2026-10-04T09:56:36.674Z', '2026-10-05T07:30Z', '2024-02-29T23:59:60+09:00']) assert.ok(isIsoTimestamp(good), good);
  for (const bad of ['2026-10-05T07:3x', '2026-10-05', '2026-13-01T00:00Z', '2026-02-29T00:00Z', '2026-10-04T24:00Z', null]) assert.ok(!isIsoTimestamp(bad), String(bad));
});
