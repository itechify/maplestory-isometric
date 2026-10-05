// node --test tools/parity/test/   (no dependencies)
// The parity generator's state rule on a small synthetic dataset: runtime declarations, evidence from unit tests and
// playtests (and which of them count), v1 and v2 drop records, source-data gaps, chains, out-of-scope keys.
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildParity, toMarkdown, runtimeState, matchFiles, collectEvidence } from '../parity.mjs';

const RUNTIME_FILES = ['game/scripts/core/quests/quest_engine.gd', 'game/scripts/core/drops/drop_roller.gd', 'game/scripts/core/maps/map_definition.gd',
  'game/scripts/old_regen.gd'];

function runtime(files = RUNTIME_FILES, texts = {}) {
  return { files: new Set(files), read: (p) => texts[p] ?? '' };
}

const RULES = {
  categories: {
    quests: { runtime: { files: ['game/scripts/core/quests/quest_engine.gd'] } },
    'quest-chains': { runtime: { files: ['game/scripts/core/quests/quest_engine.gd'] } },
    'quest-objectives': { runtime: { files: ['game/scripts/core/quests/quest_engine.gd'] } },
    'quest-rewards': { runtime: { files: ['game/scripts/core/quests/quest_engine.gd'] } },
    'monster-drops': { runtime: { files: ['game/scripts/core/drops/drop_roller.gd'] } },
    'meso-drops': { runtime: { files: ['game/scripts/core/drops/drop_roller.gd'] } },
    maps: { runtime: { files: ['game/scripts/core/maps/map_definition.gd'] } },
    breakables: { runtime: { files: ['game/scripts/**/*breakable*.gd'] } },
  },
  mechanics: [
    { key: 'mechanic:natural-hp-regen', name: 'regen', runtime: { contains: [{ glob: 'game/scripts/**/*.gd', text: 'func activity(' }],
      partial: { files: ['game/scripts/old_regen.gd'], issue: 'placeholder' } } },
  ],
  cross_reference: [{ key: 'xref:shop-item', name: 'shop items resolve' }],
  canonical_verification: [],
  out_of_scope: { 'item:525': 'Lith Harbor' },
};

function canonical() {
  const quest = (id, name, line) => ({ id, name, start_npc: { npc_id: '1' }, objectives: { monster_kills: [{ mob_id: '2', name: 'Snail', count: 10 }] },
    rewards: { exp: 30, items: [{ item_id: '237', name: 'Egg', count: 3 }], random: [] }, quest_line: line, gaps: ['no max level'] });
  const line = { steps: [{ quest_id: '1006' }, { quest_id: '1009' }], position: 1, total: 2 };
  return {
    maps: { '000000040': { id: '000000040', name: 'Snail Hunting Ground I', portals: [{ name: 'east00', to_map_id: '000000040' }],
      monsters: [{ id: '2', name: 'Snail', count: 40 }], spawns: [{ mob_id: '2' }], mob_rate: 1, reactors: [{ id: '0000001', name: 'Wooden Box', respawn_s: 120 }] } },
    monsters: { 2: { id: '2', name: 'Snail', level: 1, hp: 8, exp: 3 } },
    items: { 237: { id: '237', name: 'Egg', type: 'Use' }, 348: { id: '348', name: 'Snail Shell', type: 'Etc' }, 525: { id: '525', name: 'Chair', type: 'Setup' } },
    quests: { 1006: quest('1006', "Sam's Suggestion", line), 1009: quest('1009', "Mai's Training", { ...line, position: 2 }) },
    drops: {
      2: { id: '2', owner: { kind: 'monster', id: '2' }, schema_version: 2, entries: [
        { key: 'snail-shell', name: 'Snail Shell', item_id: '348', item_resolution: { state: 'resolved' }, chance_state: 'resolved' },
        { key: 'wooden-buckler', name: 'Wooden Buckler', item_id: null, item_resolution: { state: 'not_in_snapshot' }, chance_state: 'unresolved' },
      ], meso: { amount_state: 'resolved', chance_state: 'resolved' } },
      9: { id: '9', owner: { kind: 'monster', id: '2' }, entries: [{ item_id: '348', item_name: 'Snail Shell' }], meso: { chance: null } },
    },
  };
}

function build(extra = {}) {
  return buildParity({ canonical: canonical(), miso: {}, rules: RULES, runtime: runtime(), provenance: null, tests: [], playtests: [], ...extra });
}

const find = (doc, key) => doc.categories.flatMap((c) => c.entries).find((e) => e.key === key);
const unit = (tests) => ({ file: 'ev.json', doc: { run_at: '2026-10-05T00:00:00Z', commit: 'abc', totals: {}, tests } });
const play = (checks, scenario = 'quest_run') => ({ file: `${scenario}/report.json`, doc: { scenario, result: 'PASS', seed: 1, checks } });

test('glob matching and runtime declarations', () => {
  const files = new Set(['game/scripts/a/breakable_box.gd', 'game/scripts/b.gd', 'game/tools/stuck_scan.gd']);
  assert.deepEqual(matchFiles('game/scripts/**/*breakable*.gd', files), ['game/scripts/a/breakable_box.gd']);
  assert.deepEqual(matchFiles('game/scripts/**/*.gd', files), ['game/scripts/a/breakable_box.gd', 'game/scripts/b.gd']);
  assert.deepEqual(matchFiles('game/tools/stuck_scan*.gd', files), ['game/tools/stuck_scan.gd']);
  assert.deepEqual(matchFiles('game/scripts/b.gd', files), ['game/scripts/b.gd']);
  const rt = runtime(['game/scripts/x.gd', 'game/scripts/old_regen.gd'], { 'game/scripts/x.gd': 'func activity() -> StringName:' });
  assert.equal(runtimeState(RULES.mechanics[0].runtime, rt).state, 'present');
  assert.equal(runtimeState(RULES.mechanics[0].runtime, runtime()).state, 'partial');
  assert.equal(runtimeState(RULES.mechanics[0].runtime, runtime([])).state, 'absent');
  assert.equal(runtimeState(undefined, runtime([])).state, 'present', 'no declaration: nothing of its own to check');
});

test('without evidence entries are implemented, missing or partial', () => {
  const doc = build();
  assert.equal(find(doc, 'quest:1006').state, 'implemented');
  assert.equal(find(doc, 'objective:1006/monster_kills/2').state, 'implemented');
  assert.equal(find(doc, 'reward:1006/exp').state, 'implemented');
  assert.equal(find(doc, 'reward:1006/item/237').state, 'implemented');
  assert.equal(find(doc, 'breakable:0000001'), undefined, 'breakables come from canonical/breakables');
  assert.equal(find(doc, 'placement:000000040/0').state, 'missing', 'no breakable runtime');
  assert.equal(find(doc, 'mechanic:natural-hp-regen').state, 'partial', 'the placeholder runtime');
  assert.match(find(doc, 'mechanic:natural-hp-regen').issues.join(), /placeholder/);
  assert.equal(find(doc, 'map:000000040').state, 'implemented');
  assert.deepEqual(find(doc, 'quest:1006').source_gaps, ['no max level'], 'record gaps travel with the entry');
});

test('v1 drop records are partial; v2 unresolved members are source-data gaps; resolved ones can be verified', () => {
  const doc = build({ tests: [unit([{ file: 'test_drops.gd', name: 'test_shell', ok: true, parity: ['drop:2/snail-shell', 'drop:2/wooden-buckler'] }])] });
  assert.equal(find(doc, 'drop:9/snail-shell').state, 'partial', 'v1 entry keyed by the slug of its name');
  assert.match(find(doc, 'drop:9/snail-shell').issues[0], /placeholder/);
  assert.equal(find(doc, 'meso:9').state, 'partial');
  assert.equal(find(doc, 'drop:2/snail-shell').state, 'verified');
  const buckler = find(doc, 'drop:2/wooden-buckler');
  assert.equal(buckler.source_data_gap, true);
  assert.equal(buckler.state, 'partial', 'evidence cannot verify an unresolved probability');
  assert.equal(find(doc, 'meso:2').state, 'implemented');
  assert.ok(doc.source_data_gaps.some((g) => g.key === 'drop:2/wooden-buckler'));
  const open = doc.categories.flatMap((c) => c.entries).filter((e) => e.in_scope && e.state !== 'verified' && !e.source_data_gap);
  assert.ok(!open.some((e) => e.key === 'drop:2/wooden-buckler'), 'a source-data gap is excused from the exit count');
});

test('quests need real-game evidence; objectives and rewards accept their quest key; chains follow their members', () => {
  const unitOnly = build({ tests: [unit([{ file: 'test_quest_engine.gd', name: 'test_1006', ok: true, parity: ['quest:1006'] }])] });
  assert.equal(find(unitOnly, 'quest:1006').state, 'implemented');
  assert.ok(find(unitOnly, 'quest:1006').notes.some((n) => /playtest/.test(n)));
  const one = build({ playtests: [play([{ i: 0, name: 'quest 1006 done', ok: true, parity: ['quest:1006'] }])] });
  assert.equal(find(one, 'quest:1006').state, 'verified');
  assert.equal(find(one, 'objective:1006/monster_kills/2').state, 'verified', 'accepts quest:1006');
  assert.equal(find(one, 'reward:1006/exp').state, 'verified');
  assert.equal(find(one, 'chain:1006').state, 'implemented', 'one member still implemented');
  const both = build({ playtests: [play([{ i: 0, name: 'a', ok: true, parity: ['quest:1006'] }, { i: 1, name: 'b', ok: true, parity: ['quest:1009'] }])] });
  assert.equal(find(both, 'chain:1006').state, 'verified');
});

test('a failing tagged check, a soft check and a validation error', () => {
  const failing = build({ playtests: [play([{ i: 0, name: 'ok', ok: true, parity: ['quest:1006'] }, { i: 1, name: 'bad', ok: false, parity: ['quest:1006'] }])] });
  assert.equal(find(failing, 'quest:1006').state, 'partial');
  assert.match(find(failing, 'quest:1006').issues.join(), /1 tagged check\(s\) failed/);
  const soft = build({ playtests: [play([{ i: 0, name: 'warn', ok: true, soft: true, parity: ['quest:1006'] }])] });
  assert.equal(find(soft, 'quest:1006').state, 'implemented', 'a soft check is never evidence');
  const provenance = { validation: { errors: 1, warnings: 0, findings: [{ severity: 'error', check: 'reference', domain: 'quests', id: '1006', message: 'broken' }] }, counts: { records: 1 } };
  const broken = build({ provenance, playtests: [play([{ i: 0, name: 'ok', ok: true, parity: ['quest:1006'] }])] });
  assert.equal(find(broken, 'quest:1006').state, 'partial');
  assert.match(find(broken, 'quest:1006').issues.join(), /validation: \[reference\] broken/);
});

test('out-of-scope keys, unknown evidence keys, totals and the exit count', () => {
  const doc = build({ tests: [unit([{ file: 't.gd', name: 'test_x', ok: true, parity: ['xref:shop-item', 'quest:9999'] }])] });
  const chair = find(doc, 'item:525');
  assert.equal(chair.in_scope, false);
  assert.equal(doc.totals.all.out_of_scope, 1);
  assert.equal(find(doc, 'xref:shop-item').state, 'verified', 'no runtime declaration: evidence alone decides');
  assert.deepEqual(doc.inputs.unknown_evidence_keys, ['quest:9999']);
  const all = doc.categories.flatMap((c) => c.entries);
  const open = all.filter((e) => e.in_scope && e.state !== 'verified' && !e.source_data_gap).length;
  assert.equal(doc.totals.open_for_exit, open);
  assert.equal(doc.totals.all.entries, all.length);
});

test('evidence collection and markdown are deterministic', () => {
  const ev = collectEvidence([unit([{ file: 'a.gd', name: 'test_a', ok: true, parity: ['quest:1006'] }, { file: 'a.gd', name: 'test_b', ok: false, parity: ['quest:1006'] }])], []);
  assert.deepEqual(ev.get('quest:1006').passed.map((x) => x.id), ['a::test_a']);
  assert.deepEqual(ev.get('quest:1006').failed.map((x) => x.id), ['a::test_b']);
  const a = toMarkdown(build());
  assert.equal(a, toMarkdown(build()));
  for (const h of ['# Maple Island parity manifest', '## States', '## Totals', '## Source-data gaps', '## Quests', '## Monster drops']) assert.ok(a.includes(`\n${h}\n`) || a.startsWith(`${h}\n`), h);
  assert.equal(JSON.stringify(build()), JSON.stringify(build()));
});
