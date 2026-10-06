// node --test tools/parity/test/   (no dependencies)
// The parity generator's state rule on a small synthetic dataset: runtime declarations, evidence from unit tests and
// playtests (and which of them count), v1 and v2 drop records, source-data gaps, chains, out-of-scope keys.
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildParity, toMarkdown, runtimeState, matchFiles, collectEvidence, cleanRun, cleanRunProblems, DEPARTURE_BOUNDARY_CHECK, KURO_ONLY_REASON } from '../parity.mjs';

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
  assert.equal(find(both, 'chain:1006').state, 'implemented', 'every member verified, but no check of a link of the chain');
  assert.ok(find(both, 'chain:1006').notes.some((n) => /needs a passing real-game check tagged with this key/.test(n)));
  const link = { i: 2, name: '1006: its follow-up 1009 (Mai\'s Training) is available at level 3', ok: true, parity: ['quest:1006', 'quest:1009'] };
  const tagRule = { scenario: 'quest_run', match: '^1006: its follow-up 1009 \\(.+\\) is available at level \\d+$', keys: ['chain:1006'], why: 't' };
  const linked = buildParity({ canonical: canonical(), miso: {}, rules: { ...RULES, playtest_tags: [tagRule] }, runtime: runtime(), tests: [],
    playtests: [play([{ i: 0, name: 'a', ok: true, parity: ['quest:1006'] }, { i: 1, name: 'b', ok: true, parity: ['quest:1009'] }, link])] });
  assert.equal(find(linked, 'chain:1006').state, 'verified', 'members verified and a passing real-game link check');
  assert.equal(find(linked, 'chain:1006').evidence.passed_count, 1);
  const unitLink = build({ tests: [unit([{ file: 't.gd', name: 'test_chain', ok: true, parity: ['chain:1006'] }])],
    playtests: [play([{ i: 0, name: 'a', ok: true, parity: ['quest:1006'] }, { i: 1, name: 'b', ok: true, parity: ['quest:1009'] }])] });
  assert.equal(find(unitLink, 'chain:1006').state, 'implemented', 'a unit test is not a real-game link check');
  const brokenLink = buildParity({ canonical: canonical(), miso: {}, rules: { ...RULES, playtest_tags: [tagRule] }, runtime: runtime(), tests: [],
    playtests: [play([{ i: 0, name: 'a', ok: true, parity: ['quest:1006'] }, { i: 1, name: 'b', ok: true, parity: ['quest:1009'] }, { ...link, ok: false }])] });
  assert.equal(find(brokenLink, 'chain:1006').state, 'partial', 'a failing link check');
  assert.match(find(brokenLink, 'chain:1006').issues.join(), /1 tagged check\(s\) failed/);
  assert.match(toMarkdown(linked), /\*\*chains\*\*: A quest chain/, 'the States section states the chain rule');
});

test('spawn-rule rows list the mob-rate switch and say whether the rate is applied; adaptation sections must exist', () => {
  const miso = { presentation: { map_mob_rate: { apply: false, reason: 'r', verified: false }, fall_recovery: { reason: 'r', verified: false } } };
  const doc = buildParity({ canonical: canonical(), miso, rules: RULES, runtime: runtime(), tests: [], playtests: [] });
  const sr = find(doc, 'spawn-rule:000000040');
  assert.deepEqual(sr.adaptations, ['game/data/misostory/presentation.json#map_mob_rate']);
  assert.match(sr.name, /MeowDB mob rate 1 \(not applied: presentation\.json map_mob_rate\)/);
  assert.ok(sr.notes.some((n) => /deliberately not applied/.test(n)));
  const on = buildParity({ canonical: canonical(), miso: { presentation: { map_mob_rate: { apply: true, verified: false } } }, rules: RULES, runtime: runtime(), tests: [], playtests: [] });
  assert.match(find(on, 'spawn-rule:000000040').name, /\(applied: /);
  const bare = build();
  assert.deepEqual(find(bare, 'spawn-rule:000000040').adaptations, [], 'no presentation.json: nothing listed');
  const withRow = (adaptations) => ({ ...RULES, mechanics: [...RULES.mechanics, { key: 'mechanic:fall-damage', name: 'f', source_gaps: ['g'], adaptations }] });
  const ok = buildParity({ canonical: canonical(), miso, rules: withRow(['game/data/misostory/presentation.json#fall_recovery', 'game/data/misostory/none.json']), runtime: runtime() });
  assert.deepEqual(find(ok, 'mechanic:fall-damage').adaptations, ['game/data/misostory/presentation.json#fall_recovery'], 'a missing file is not listed');
  assert.equal(find(ok, 'mechanic:fall-damage').source_data_gap, true);
  assert.match(toMarkdown(ok), /adaptation: presentation\.json#fall_recovery/);
  assert.throws(() => buildParity({ canonical: canonical(), miso, rules: withRow(['game/data/misostory/presentation.json#no_such_section']), runtime: runtime() }),
    /has no section "no_such_section"/, 'a stale section fails the build');
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
  const check = [{ i: 0, name: 'in Southperry', ok: true, parity: ['playthrough:reach-southperry'] }];
  const setup = build({ rules, playtests: [play(check, 'playthrough')] });
  assert.equal(find(setup, 'playthrough:reach-southperry').state, 'implemented', 'a run that is not strict is not a clean-character run');
  const clean = (doc, steps) => ({ ...doc, doc: { ...doc.doc, strict: { enabled: true, ok: true }, counts: { steps } } });
  const withConsole = build({ rules, playtests: [clean(play(check, 'playthrough'), { play: 9, console: 1, api: 0 })] });
  assert.equal(find(withConsole, 'playthrough:reach-southperry').state, 'implemented', 'one console step (even setup) is not clean');
  const boundary = { i: 9, name: DEPARTURE_BOUNDARY_CHECK, ok: true };
  const real = build({ rules, playtests: [clean(play([...check, boundary], 'playthrough'), { play: 9, console: 0, api: 0 })] });
  assert.equal(find(real, 'playthrough:reach-southperry').state, 'verified');
  // A strict run stopped by a failed step: its earlier passing checks (one quest of six, one quiz of seven) do not
  // show the clean-character playthrough was done.
  const stopped = clean(play([...check, { i: 1, name: "step 'quiz' completed", ok: false }], 'playthrough'), { play: 9, console: 0, api: 0 });
  stopped.doc.result = 'FAIL';
  assert.equal(find(build({ rules, playtests: [stopped] }), 'playthrough:reach-southperry').state, 'implemented',
    'a failed run is not a clean-character playthrough');
  assert.throws(() => build({ rules: { ...rules, mechanics: [...rules.mechanics, { key: 'mechanic:x', name: 'x', accepts: ['mechanic:mesos-saved'] }] } }),
    /mechanic:mesos-saved is accepted by both/);
  assert.throws(() => build({ rules: { ...rules, mechanics: [...rules.mechanics, { key: 'mechanic:y', name: 'y', accepts: ['quest:1006'] }] } }),
    /accepts quest:1006, which is the key of another entry/);
  assert.throws(() => build({ rules: { ...rules, mechanics: [{ key: 'mechanic:z', name: 'z', category: 'nowhere' }] } }), /unknown category nowhere/);
});

test('a playthrough stopped before the departure boundary is not a clean run, so it verifies no playthrough row', () => {
  const rules = { ...RULES, mechanics: [...RULES.mechanics,
    { key: 'playthrough:create-character', category: 'playthrough', name: 'create the character' },
    { key: 'playthrough:ready-to-depart', category: 'playthrough', name: 'arrive ready to depart' },
  ] };
  // A strict, passing report with no console or api step whose early checks carry playthrough keys.
  const report = (checks, extra = {}) => ({ file: 'playthrough/report.json', doc: { scenario: 'playthrough', result: 'PASS', seed: 1,
    strict: { enabled: true, ok: true }, counts: { steps: { play: 40, console: 0, api: 0 } }, notes: [], carry: {}, checks, ...extra } });
  const early = [{ i: 0, name: 'a brand-new character through the title and creation screens', ok: true, parity: ['playthrough:create-character'] }];
  const boundary = { i: 1, name: DEPARTURE_BOUNDARY_CHECK, ok: true, parity: ['playthrough:ready-to-depart'] };
  const state = (doc, key) => find(doc, key).state;

  // (a) Stopped with PLAYTHROUGH_STOP=pio: the scenario's carry flag and note, and no boundary check.
  const stopped = report(early, { carry: { stopped_after: 'pio' }, notes: ['[phase 3, 812.0 s] PLAYTHROUGH_STOP=pio: stopping after this step'] });
  assert.equal(cleanRun(stopped.doc), false);
  assert.deepEqual(cleanRunProblems(stopped.doc), [
    "stopped early (PLAYTHROUGH_STOP after step 'pio')",
    `the departure boundary was not reached (no passing check "${DEPARTURE_BOUNDARY_CHECK}")`,
  ]);
  const a = build({ rules, playtests: [stopped] });
  assert.equal(state(a, 'playthrough:create-character'), 'implemented', 'a check of a run stopped early does not verify a playthrough row');
  assert.match(find(a, 'playthrough:create-character').notes.join(' '), /departure boundary reached, not stopped early/);
  const listed = a.inputs.playtests[0];
  assert.equal(listed.clean_run, false);
  assert.match(toMarkdown(a), /not a clean run: stopped early \(PLAYTHROUGH_STOP after step 'pio'\)/);

  // (b) No stop flag, but the boundary check is missing (the run ended before _finish(true)).
  assert.equal(state(build({ rules, playtests: [report(early)] }), 'playthrough:create-character'), 'implemented');
  // ... or present and failing, or only soft.
  assert.equal(state(build({ rules, playtests: [report([...early, { ...boundary, ok: false }])] }), 'playthrough:create-character'), 'implemented');
  assert.equal(state(build({ rules, playtests: [report([...early, { ...boundary, soft: true }])] }), 'playthrough:create-character'), 'implemented');

  // (c) The stop flag alone (the note without the carry key, or the carry key without the note) disqualifies a run
  //     even with a passing boundary check.
  const noteOnly = report([...early, boundary], { notes: ['[phase 6, 2400.0 s] PLAYTHROUGH_STOP=after_departure: stopping after this step'] });
  assert.equal(cleanRun(noteOnly.doc), false);
  assert.equal(state(build({ rules, playtests: [noteOnly] }), 'playthrough:create-character'), 'implemented');
  const carryOnly = report([...early, boundary], { carry: { stopped_after: 'shanks' } });
  assert.equal(cleanRun(carryOnly.doc), false);

  // (d) The full run: boundary passed, no stop flag: every tagged playthrough row is verified.
  const full = report([...early, boundary]);
  assert.equal(cleanRun(full.doc), true);
  assert.deepEqual(cleanRunProblems(full.doc), []);
  const d = build({ rules, playtests: [full] });
  assert.equal(state(d, 'playthrough:create-character'), 'verified');
  assert.equal(state(d, 'playthrough:ready-to-depart'), 'verified');
  assert.equal(d.inputs.playtests[0].clean_run, true);
  assert.match(toMarkdown(d), /a clean run \(counts for the playthrough rows\)/);
  // Other scenarios' reports carry no clean-run verdict.
  assert.equal(build({ rules, playtests: [play(early, 'quest')] }).inputs.playtests[0].clean_run, undefined);
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

test('a pending source read is its own label: never excused, never verified, listed apart from the gaps; stale declarations fail', () => {
  // A drop member whose chance is unresolved while the record holds a KuroDB row that may be it, waiting for a read of
  // its item page (pending_kuro_candidates, decision D3-8), next to a member KuroDB truly has no row for (a gap).
  const withCandidate = () => {
    const c = canonical();
    c.drops['2'].entries.push({ key: 'jump-scroll', name: 'Scroll for Shoes for Jump 10%', item_id: '348', item_resolution: { state: 'resolved' },
      chance_state: 'unresolved', notes: ['KuroDB candidate row Scroll for Shoes for Jump (2040705, "0.0300% base | Qty 1"), pending a read of its item page'] });
    c.drops['2'].excluded_kuro_only = [
      { kuro_item_id: '2380000', name: 'Snail Card', raw_value: '26% base | Qty 1', reason: KURO_ONLY_REASON },
      // A candidate its item page did not confirm is excluded with what the page showed: KuroDB-only, never pending.
      { kuro_item_id: '2040799', name: 'Scroll for Shoes for Speed', raw_value: '0.0300% base | Qty 1', reason: 'checked against its item page: another item' },
    ];
    c.drops['2'].pending_kuro_candidates = [
      { kuro_item_id: '2040705', name: 'Scroll for Shoes for Jump', raw_value: '0.0300% base | Qty 1', member: 'jump-scroll', read: 'KuroDB item page 2040705', reason: 'possible match, page not read', decision: 'D3-8' },
    ];
    c.items['237'].gaps = ['max_stack: shown only on the item page, which was not captured', 'sources.breakables: not captured'];
    return c;
  };
  const evidence = [unit([{ file: 't.gd', name: 'test_all', ok: true, parity: ['drop:2/jump-scroll', 'item:237', 'item:348'] }])];
  const undeclared = build({ canonical: withCandidate(), tests: evidence });
  const scroll = find(undeclared, 'drop:2/jump-scroll');
  assert.equal(scroll.source_data_gap, false, 'a published but unread chance is not a source-data gap');
  assert.equal(scroll.pending_source_read, true, 'the record alone marks it, even undeclared');
  assert.equal(scroll.state, 'partial', 'passing evidence cannot verify it');
  assert.deepEqual(scroll.source_gaps, [], 'no gap text claims KuroDB has no chance');
  assert.match(scroll.pending_reads[0].read, /KuroDB item 2040705/);
  assert.deepEqual(undeclared.inputs.undeclared_pending_reads, ['drop:2/jump-scroll']);
  assert.ok(!undeclared.source_data_gaps.some((g) => g.key === 'drop:2/jump-scroll'), 'not listed with the gaps');
  assert.deepEqual(undeclared.pending_source_reads.map((p) => p.key), ['drop:2/jump-scroll']);
  assert.equal(find(undeclared, 'drop:2/wooden-buckler').source_data_gap, true, 'a member KuroDB has no row for stays a gap');
  const open = undeclared.categories.flatMap((c) => c.entries).filter((e) => e.in_scope && e.state !== 'verified' && !e.source_data_gap).map((e) => e.key);
  assert.ok(open.includes('drop:2/jump-scroll'), 'counted open for the exit criterion');
  assert.equal(undeclared.totals.open_for_exit, open.length);
  assert.equal(undeclared.totals.all.pending_source_read, 1);
  assert.equal(undeclared.totals.by_category['monster-drops'].pending_source_read, 1);
  assert.equal(find(undeclared, 'item:237').state, 'verified', 'record gaps alone do not make an item pending');
  // Declared: the drop keeps its pending label with the declared read; a record entry needs the fields its gaps name.
  const rules = { ...RULES, pending_source_reads: {
    'drop:2/jump-scroll': { read: 'KuroDB item page 2040705', resolves: 'the chance', decision: 'D3-8' },
    'item:237': { read: 'MeowDB item page 237', resolves: 'its max stack', fields: ['max_stack'] },
  } };
  const declared = build({ canonical: withCandidate(), rules, tests: evidence });
  assert.deepEqual(declared.inputs.undeclared_pending_reads, []);
  assert.equal(find(declared, 'drop:2/jump-scroll').pending_reads[0].read, 'KuroDB item page 2040705');
  const egg = find(declared, 'item:237');
  assert.equal(egg.pending_source_read, true);
  assert.equal(egg.state, 'partial', 'a passing item test cannot verify a value still to be read');
  assert.equal(find(declared, 'item:348').state, 'verified');
  assert.deepEqual(declared.pending_source_reads.map((p) => p.key), ['drop:2/jump-scroll', 'item:237']);
  const md = toMarkdown(declared);
  assert.ok(md.includes('\n## Pending source reads\n'));
  assert.match(md, /- `item:237` Egg \(Use\): read MeowDB item page 237 to settle its max stack\. max_stack: shown only on the item page/);
  assert.match(md, /\| `drop:2\/jump-scroll` \| .* \| partial \(pending source read\) \|/);
  assert.match(md, /partial: pending source read \(KuroDB item page 2040705\): `drop:2\/jump-scroll`/);
  // An entry with a real gap stays excused; its pending part is listed beside the gap.
  const both = withCandidate();
  both.drops['2'].entries.find((e) => e.key === 'jump-scroll').item_resolution = { state: 'ambiguous', candidates: ['1', '2'] };
  both.drops['2'].entries.find((e) => e.key === 'jump-scroll').item_id = null;
  const mixed = find(build({ canonical: both, rules, tests: evidence }), 'drop:2/jump-scroll');
  assert.equal(mixed.source_data_gap, true);
  assert.equal(mixed.pending_source_read, false);
  assert.equal(mixed.pending_reads.length, 1);
  // Stale declarations fail: the read was done (the chance resolved, the candidate gone; the gap removed), or no entry.
  const read = withCandidate();
  read.drops['2'].pending_kuro_candidates = [];
  read.drops['2'].entries.find((e) => e.key === 'jump-scroll').chance_state = 'resolved';
  assert.throws(() => build({ canonical: read, rules }), /drop:2\/jump-scroll is stale: its drop record has no pending_kuro_candidates row/);
  // The page was read and did not confirm the row: it is excluded with what the page showed, the member is a gap.
  const rejected = withCandidate();
  const row = rejected.drops['2'].pending_kuro_candidates.pop();
  rejected.drops['2'].excluded_kuro_only.push({ kuro_item_id: row.kuro_item_id, name: row.name, raw_value: row.raw_value, reason: 'checked: 60%' });
  const gap = find(build({ canonical: rejected }), 'drop:2/jump-scroll');
  assert.deepEqual([gap.source_data_gap, gap.pending_source_read], [true, false], 'an excluded row is never pending, whatever its reason');
  assert.throws(() => build({ canonical: rejected, rules }), /drop:2\/jump-scroll is stale/);
  const pageRead = withCandidate();
  pageRead.items['237'].gaps = [];
  assert.throws(() => build({ canonical: pageRead, rules }), /item:237 is stale: record items\/237 has no gap for max_stack/);
  assert.throws(() => build({ canonical: withCandidate(), rules: { ...RULES, pending_source_reads: { 'item:999': { read: 'x', resolves: 'y', fields: ['a'] } } } }),
    /item:999 names no entry/);
  assert.throws(() => build({ canonical: withCandidate(), rules: { ...RULES, pending_source_reads: { 'item:237': { read: 'x', resolves: 'y' } } } }),
    /item:237 needs "fields"/);
  // A candidate row whose member cannot be found is reported.
  const lost = withCandidate();
  lost.drops['2'].pending_kuro_candidates[0].member = 'no-such-member';
  assert.deepEqual(build({ canonical: lost }).inputs.unmatched_kuro_candidates, ['drops/2: KuroDB 2040705 Scroll for Shoes for Jump (member no-such-member)']);
  assert.equal(find(build({ canonical: lost }), 'drop:2/jump-scroll').pending_source_read, false);
});
