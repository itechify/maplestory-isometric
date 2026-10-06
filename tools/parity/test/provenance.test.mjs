// node --test tools/parity/test/
// Evidence provenance (contract C6): world-dependent unit test keys count only from a run that recorded the exported
// world present; the manifest's inputs carry each evidence file's commit, dirty flag and world flag; build_parity.mjs
// warns (console only) about missing commits, dirty trees, mixed commits and commits whose code trees differ from HEAD.
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildParity, toMarkdown, collectEvidence, gitOf, needsWorld, WORLD_MARKER } from '../parity.mjs';
import { provenanceWarnings, CODE_TREES } from '../build_parity.mjs';

const RULES = {
  categories: { maps: { runtime: { files: ['game/scripts/core/maps/map_definition.gd'] } } },
  mechanics: [], cross_reference: [], canonical_verification: [], out_of_scope: {},
};
const CANON = { maps: { '000000040': { id: '000000040', name: 'Snail Hunting Ground I', portals: [], monsters: [] } } };
const WORLD_TEST = 'game/tests/unit/test_world_walk.gd';
const LOGIC_TEST = 'game/tests/unit/test_logic.gd';
const runtime = {
  files: new Set(['game/scripts/core/maps/map_definition.gd', WORLD_TEST, LOGIC_TEST]),
  read: (p) => ({ [WORLD_TEST]: `print("SKIP x: run with ${WORLD_MARKER}=1")`, [LOGIC_TEST]: 'func test_a() -> void:\n\tpass' })[p] ?? '',
};
const find = (doc, key) => doc.categories.flatMap((c) => c.entries).find((e) => e.key === key);
const evidence = (extra, tests) => ({ file: 'ev.json', doc: { run_at: '2026-10-05T00:00:00Z', commit: 'abc', totals: {}, ...extra, tests } });
const build = (tests) => buildParity({ canonical: CANON, miso: {}, rules: RULES, runtime, tests, playtests: [] });

test('a world-dependent test counts only from a run that recorded the world present', () => {
  const entry = (extra = {}) => ({ file: 'test_world_walk.gd', name: 'test_walk', ok: true, parity: ['map:000000040'], ...extra });
  const without = build([evidence({ world_present: false }, [entry({ needs_world: true })])]);
  assert.equal(find(without, 'map:000000040').state, 'implemented', 'refused: the test printed SKIP and passed without the world');
  assert.deepEqual(without.inputs.tests[0].world_refused, { tests: 1, keys: ['map:000000040'] });
  assert.match(toMarkdown(without), /world absent, .*1 world-dependent test\(s\) refused/);
  const withWorld = build([evidence({ world_present: true }, [entry({ needs_world: true })])]);
  assert.equal(find(withWorld, 'map:000000040').state, 'verified');
  assert.deepEqual(withWorld.inputs.tests[0].world_refused, { tests: 0, keys: [] });
  // Older evidence records neither flag: the test file itself says whether it needs the world.
  const old = build([evidence({}, [entry()])]);
  assert.equal(find(old, 'map:000000040').state, 'implemented', 'old evidence of a world test: refused');
  assert.equal(old.inputs.tests[0].world_present, null, 'not recorded');
  const logic = build([evidence({}, [{ file: 'test_logic.gd', name: 'test_a', ok: true, parity: ['map:000000040'] }])]);
  assert.equal(find(logic, 'map:000000040').state, 'verified', 'a logic test counts from any run');
  const flagged = build([evidence({ world_present: false }, [entry({ needs_world: false })])]);
  assert.equal(find(flagged, 'map:000000040').state, 'verified', 'the entry\'s own needs_world wins over the file scan');
  assert.ok(needsWorld(`x ${WORLD_MARKER}=1`) && !needsWorld('x'));
  const refused = [];
  collectEvidence([evidence({ world_present: false }, [entry({ needs_world: true, parity: [] })])], [], [], null, { refused });
  assert.deepEqual(refused, [], 'an untagged test is not reported as refused');
});

test('the inputs carry commit, dirty flag and world flag; a playtest report its git block', () => {
  const doc = buildParity({ canonical: CANON, miso: {}, rules: RULES, runtime,
    tests: [evidence({ dirty: true, world_present: true }, [])],
    playtests: [{ file: 'pt/report.json', doc: { scenario: 's', result: 'PASS', seed: 1, checks: [], git: { commit: 'def', dirty: false, mixed: true, reused_copy: false } } },
      { file: 'old/report.json', doc: { scenario: 's', result: 'PASS', seed: 1, checks: [] } }] });
  assert.deepEqual([doc.inputs.tests[0].commit, doc.inputs.tests[0].dirty, doc.inputs.tests[0].world_present], ['abc', true, true]);
  assert.deepEqual([doc.inputs.playtests[0].commit, doc.inputs.playtests[0].dirty, doc.inputs.playtests[0].mixed], ['def', false, true]);
  assert.deepEqual(gitOf({}), { commit: null, dirty: null, mixed: false, reused_copy: false });
  const md = toMarkdown(doc);
  assert.match(md, /commit abc \(dirty tree\), world present/);
  assert.match(md, /`pt\/report\.json`: s seed 1, PASS, commit def \(clean tree, several commits\)/);
  assert.match(md, /`old\/report\.json`: s seed 1, PASS, commit not recorded/);
});

test('provenance warnings: no commit, dirty, mixed, several commits, code trees that differ from HEAD', () => {
  const trees = { HEAD: { game: 'g1', tools: 't1', scripts: 's1' }, aaa: { game: 'g1', tools: 't1', scripts: 's1' },
    bbb: { game: 'g0', tools: 't1', scripts: 's1' } };
  const gitFn = (args) => {
    const [rev, tree] = args[1].split(':');
    return trees[rev]?.[tree] ?? null;
  };
  const same = { tests: [{ file: 'ev.json', commit: 'aaa', dirty: false }], playtests: [{ file: 'p.json', commit: 'aaa', dirty: false, mixed: false }] };
  assert.deepEqual(provenanceWarnings(same, gitFn), [], 'one commit, clean, same code trees as HEAD (a docs-only difference is fine)');
  const w = provenanceWarnings({ tests: [{ file: 'ev.json', commit: 'aaa', dirty: true }],
    playtests: [{ file: 'p.json', commit: 'bbb', dirty: false, mixed: true }, { file: 'q.json', commit: null, dirty: null, mixed: false },
      { file: 'r.json', commit: 'ccc', dirty: false, mixed: false }] }, gitFn);
  assert.ok(w.some((x) => /1 evidence file\(s\) record no commit.*q\.json/.test(x)), w.join('\n'));
  assert.ok(w.some((x) => /unit evidence ev\.json ran on a dirty tree/.test(x)));
  assert.ok(w.some((x) => /playtest p\.json spans several commits/.test(x)));
  assert.ok(w.some((x) => /the evidence comes from 3 commits/.test(x)));
  assert.ok(w.some((x) => /evidence commit bbb differs from HEAD in game\/:/.test(x)), 'bbb changed game/');
  assert.ok(!w.some((x) => /evidence commit aaa differs/.test(x)), 'aaa has HEAD\'s trees');
  assert.ok(w.some((x) => /evidence commit ccc differs from HEAD in game\/ \(cannot compare/.test(x)), 'an unknown commit cannot be compared');
  assert.deepEqual(CODE_TREES, ['game', 'tools', 'scripts']);
});
