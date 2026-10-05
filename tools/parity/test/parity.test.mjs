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
  assert.deepEqual(find(doc, 'drop:2/snail-shell').accepts, ['drop:2/348'], 'the item-id form a playtest check uses');
  const byId = build({ playtests: [play([{ i: 0, name: 'shells picked up', ok: true, parity: ['drop:2/348'] }])] });
  assert.equal(find(byId, 'drop:2/snail-shell').state, 'verified');
  assert.deepEqual(byId.inputs.unknown_evidence_keys, []);
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

test('v1 entries sharing a name get distinct keys; a duplicate key fails the build', () => {
  const c = canonical();
  // Red Snail's v1 table lists Red Cloth Pants twice (1168 male, 1177 female): one slug, two entries.
  c.drops['9'].entries.push({ item_id: '1168', item_name: 'Red Cloth Pants' }, { item_id: '1177', item_name: 'Red Cloth Pants' });
  const doc = build({ canonical: c });
  assert.equal(find(doc, 'drop:9/red-cloth-pants'), undefined, 'neither entry owns the bare slug');
  assert.equal(find(doc, 'drop:9/red-cloth-pants-1168').item_id, '1168');
  assert.equal(find(doc, 'drop:9/red-cloth-pants-1177').item_id, '1177');
  assert.ok(find(doc, 'drop:9/snail-shell'), 'an unshared slug keeps its plain key');
  const keys = doc.categories.flatMap((cat) => cat.entries).map((e) => e.key);
  assert.equal(new Set(keys).size, keys.length, 'every key names one entry');
  // Two entries with one explicit key cannot both be in the manifest.
  const d = canonical();
  d.drops['2'].entries.push({ ...d.drops['2'].entries[0] });
  assert.throws(() => build({ canonical: d }), /duplicate parity keys: drop:2\/snail-shell/);
});

test('rule rows: categories, aliases, real-game flags and source-data gaps', () => {
  const rules = { ...RULES, mechanics: [...RULES.mechanics,
    { key: 'persistence:mesos', category: 'persistence', name: 'mesos persist', accepts: ['mechanic:mesos-saved'] },
    { key: 'mechanic:natural-mp-regen', name: 'no MP regen', source_gaps: ['MeowDB documents none'] },
    { key: 'playthrough:reach-southperry', category: 'playthrough', name: 'reach Southperry' },
    { key: 'mechanic:strict-guard', category: 'playthrough', real_game: false, name: 'strict guard' },
  ] };
  const ev = [unit([{ file: 't.gd', name: 'test_a', ok: true, parity: ['mechanic:mesos-saved', 'mechanic:natural-mp-regen', 'playthrough:reach-southperry', 'mechanic:strict-guard'] }])];
  const doc = build({ rules, tests: ev });
  const mesos = find(doc, 'persistence:mesos');
  assert.equal(mesos.category, 'persistence');
  assert.equal(mesos.state, 'verified', 'evidence for the alias counts');
  assert.deepEqual(doc.inputs.unknown_evidence_keys, [], 'an alias is a known key');
  const mp = find(doc, 'mechanic:natural-mp-regen');
  assert.equal(mp.source_data_gap, true);
  assert.equal(mp.state, 'partial', 'a gap row is excused, never verified');
  assert.ok(doc.source_data_gaps.some((g) => g.key === 'mechanic:natural-mp-regen'));
  assert.equal(find(doc, 'playthrough:reach-southperry').state, 'implemented', 'the playthrough category needs the real game');
  assert.equal(find(doc, 'mechanic:strict-guard').state, 'verified', 'real_game false waives it for one row');
  const real = build({ rules, playtests: [play([{ i: 0, name: 'in Southperry', ok: true, parity: ['playthrough:reach-southperry'] }], 'playthrough')] });
  assert.equal(find(real, 'playthrough:reach-southperry').state, 'verified');
  assert.throws(() => build({ rules: { ...rules, mechanics: [...rules.mechanics, { key: 'mechanic:x', name: 'x', accepts: ['mechanic:mesos-saved'] }] } }),
    /mechanic:mesos-saved is accepted by both/);
  assert.throws(() => build({ rules: { ...rules, mechanics: [...rules.mechanics, { key: 'mechanic:y', name: 'y', accepts: ['quest:1006'] }] } }),
    /accepts quest:1006, which is the key of another entry/);
  assert.throws(() => build({ rules: { ...rules, mechanics: [{ key: 'mechanic:z', name: 'z', category: 'nowhere' }] } }), /unknown category nowhere/);
});

test('playtest_tags give keys to matching hard checks of their scenario, and report rules that match nothing', () => {
  const rules = { ...RULES, playtest_tags: [
    { scenario: 'npcs', match: '^\\S+ \\((\\d+)\\) can be talked to on foot', keys: ['npc:$1', 'quest:1006'] },
    { scenario: ['npcs', 'other'], match: '^never matches$', keys: ['quest:1009'] },
  ] };
  const checks = [
    { i: 0, name: 'Sam (9) can be talked to on foot in 000000040', ok: true },
    { i: 1, name: 'Mai (11) can be talked to on foot in 000000050', ok: false },
    { i: 2, name: 'Roger (3) can be talked to on foot in 000000010', ok: true, soft: true },
    { i: 3, name: 'every NPC was talked to on foot', ok: true, parity: ['quest:1006'] },
  ];
  const doc = build({ rules, playtests: [play(checks, 'npcs'), play([{ i: 0, name: 'Sam (9) can be talked to on foot', ok: true }], 'elsewhere')] });
  const ev = collectEvidence([], [play(checks, 'npcs')], rules.playtest_tags);
  assert.deepEqual(ev.get('npc:9').passed.map((x) => x.id), ['npcs#0 Sam (9) can be talked to on foot in 000000040']);
  assert.equal(ev.get('npc:11').failed.length, 1, 'a failing matched check is failing evidence');
  assert.equal(ev.get('npc:3'), undefined, 'a soft check is never evidence');
  assert.equal(ev.get('quest:1006').passed.length, 2, 'one key once per check, rule keys and the check\'s own');
  assert.equal(find(doc, 'quest:1006').state, 'partial', 'the failing Mai check carries the rule\'s quest key too');
  assert.match(find(doc, 'quest:1006').issues.join(), /1 tagged check\(s\) failed/);
  assert.deepEqual(doc.inputs.playtest_tag_rules_unmatched.map((u) => u.rule), ['1: ^never matches$']);
  const p = doc.inputs.playtests.find((x) => x.scenario === 'npcs');
  assert.equal(p.rule_tagged_checks, 2);
  assert.deepEqual(p.failed_checks, ['#1 Mai (11) can be talked to on foot in 000000050']);
  assert.match(toMarkdown(doc), /node tools\/parity\/build_parity\.mjs \\\n {2}--playtest npcs\/report\.json/);
});

test('a placement accepts the map-wide breakable-placement key; every map has a minimap row', () => {
  const doc = build({ tests: [unit([{ file: 't.gd', name: 'test_b', ok: true, parity: ['breakable-placement:000000040', 'minimap:000000040'] }])] });
  assert.ok(find(doc, 'placement:000000040/0').accepts.includes('breakable-placement:000000040'));
  assert.equal(find(doc, 'minimap:000000040').category, 'ui');
  assert.deepEqual(doc.inputs.unknown_evidence_keys, []);
});

test('a canonical-verification row about the drop data stays partial while any drop record is schema v1', () => {
  const rules = { ...RULES, canonical_verification: [
    { key: 'canon:membership-chance-separate', name: 'separate sources', requires: { drops_schema_version: 2 } },
    { key: 'canon:adaptations-explained', name: 'adaptations explained' },
  ] };
  const evidence = [unit([{ file: 'test_v.gd', name: 'test_rule', ok: true, parity: ['canon:membership-chance-separate', 'canon:adaptations-explained'] }])];
  const mixed = build({ rules, tests: evidence });
  const row = find(mixed, 'canon:membership-chance-separate');
  assert.equal(row.state, 'partial', 'drop record 9 is still v1');
  assert.match(row.issues.join(), /drop record\(s\) 9 are not schema v2/);
  assert.equal(find(mixed, 'canon:adaptations-explained').state, 'verified', 'a row without a data requirement');
  const c = canonical();
  delete c.drops['9'];
  assert.equal(find(build({ canonical: c, rules, tests: evidence }), 'canon:membership-chance-separate').state, 'verified', 'every drop record v2');
});
