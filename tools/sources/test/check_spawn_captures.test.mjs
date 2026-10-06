// node --test tools/sources/test/
import test from 'node:test';
import assert from 'node:assert/strict';
import { checkSpawnCaptures, loadCanonicalMaps, parseMobRate, parseRespawn, parseShare } from '../check_spawn_captures.mjs';
import { loadCaptures } from '../captures.mjs';

test('the 51 canonical spawn rows equal the dated live captures', () => {
  const res = checkSpawnCaptures();
  assert.equal(res.checked, 51, 'one row per (map, species) on the 15 hunting maps');
  assert.equal(new Set(res.rows.map((r) => r.map_id)).size, 15);
  assert.deepEqual(res.missing_captures, []);
  assert.deepEqual(res.unmatched_capture_rows, []);
  assert.equal(res.mismatches, 0, JSON.stringify(res.rows.filter((r) => r.problems.length), null, 1));
  assert.equal(res.rows.reduce((s, r) => s + r.canonical.count, 0), 577, 'island spawn points');
  const a = res.rows.find((r) => r.map_id === '000000050' && r.mob_id === '3');
  assert.equal(a.capture.raw, 'A Split RoadMaple Road\t17\t17/42 40%\t3\t1.5x\t~7.5s');
  assert.ok(a.capture.read_at.startsWith('2026-10-05'), 'a dated capture');
});

test('a changed canonical count, mob rate or missing row is reported', () => {
  const maps = structuredClone(loadCanonicalMaps());
  const captures = loadCaptures();
  maps['000000040'].monsters[0].count = 39;
  maps['000000050'].mob_rate = 1.0;
  maps['000001021'].monsters = maps['000001021'].monsters.filter((m) => String(m.id) !== '9');
  const res = checkSpawnCaptures({ maps, captures });
  const problems = res.rows.flatMap((r) => r.problems.map((p) => `${r.map_id}/${r.mob_id}: ${p}`));
  assert.ok(problems.some((p) => p.startsWith('000000040/2: count 40 (capture) vs 39')), problems.join('\n'));
  assert.ok(problems.some((p) => p.startsWith('000000050/3: mob rate "1.5x" vs 1')), problems.join('\n'));
  assert.ok(problems.some((p) => p.startsWith('000001021/2: types 4 vs 3')), problems.join('\n'));
  assert.ok(res.unmatched_capture_rows.some((u) => u.mob_id === '9' && u.raw.startsWith('Tomato Field')), 'the capture row left over');
  assert.ok(res.mismatches > 3);
});

test('column parsers', () => {
  assert.deepEqual(parseShare('17/42 40%'), { count: 17, total: 42, pct: 40 });
  assert.equal(parseShare('17 of 42'), null);
  assert.equal(parseMobRate('1.5x'), 1.5);
  assert.equal(parseMobRate('0.6x'), 0.6);
  assert.equal(parseMobRate('fast'), null);
  assert.equal(parseRespawn('~7.5s'), 7.5);
  assert.equal(parseRespawn('about every 30 min'), null);
});
