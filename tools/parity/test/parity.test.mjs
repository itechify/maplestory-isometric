// node --test tools/parity/test/   (no dependencies)
// The parity generator's state rule on a small synthetic dataset: runtime declarations, evidence from unit tests and
// playtests (and which of them count), older and schema 3 drop records, source-data gaps, chains, out-of-scope keys.
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildParity, toMarkdown, runtimeState, matchFiles, collectEvidence, cleanRun, cleanRunProblems, DEPARTURE_BOUNDARY_CHECK } from '../parity.mjs';

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
      2: { id: '2', owner: { kind: 'monster', id: '2' }, schema_version: 3, entries: [
        { key: 'snail-shell', name: 'Snail Shell', item_id: '348', item_resolution: { state: 'resolved' }, chance_category: 'etc_own_leftover',
          membership_source: { authority: 'MeowDB MS Classic', list: 'Drops (MS Classic)', capture: 'tools/meowdb/captures/monster_2.txt', votes: { up: 9, down: 0, score: 9 } },
          rarity: { label: 'Common', source: { authority: 'Henesys.gg', capture: 'tools/henesys/captures/item_rarity.json' } } },
        { key: 'wooden-buckler', name: 'Wooden Buckler', item_id: null, item_resolution: { state: 'not_in_snapshot' }, rarity: null, chance_category: null },
      ], meso: { amount_state: 'reported', min: 2, max: 2, amount_source: { raw_value: 'Mesos: 2 per kill | 1 report' } } },
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

test('older drop records are partial; schema 3 unresolved members are source-data gaps; resolved ones can be verified', () => {
  const doc = build({ tests: [unit([{ file: 'test_drops.gd', name: 'test_shell', ok: true, parity: ['drop:2/snail-shell', 'drop:2/wooden-buckler'] }])] });
  assert.equal(find(doc, 'drop:9/snail-shell').state, 'partial', 'an older entry is keyed by the slug of its name');
  assert.match(find(doc, 'drop:9/snail-shell').issues[0], /not the drop record schema the runtime reads/);
  assert.equal(find(doc, 'meso:9').state, 'partial');
  assert.equal(find(doc, 'drop:2/snail-shell').state, 'verified');
  assert.deepEqual(find(doc, 'drop:2/snail-shell').accepts, ['drop:2/348'], 'the item-id form a playtest check uses');
  const byId = build({ playtests: [play([{ i: 0, name: 'shells picked up', ok: true, parity: ['drop:2/348'] }])] });
  assert.equal(find(byId, 'drop:2/snail-shell').state, 'verified');
  assert.deepEqual(byId.inputs.unknown_evidence_keys, []);
  const buckler = find(doc, 'drop:2/wooden-buckler');
  assert.equal(buckler.source_data_gap, true);
  assert.equal(buckler.state, 'partial', 'evidence cannot verify an unresolved member');
  assert.deepEqual(buckler.source_gaps, ['item not_in_snapshot: never drops', 'no Henesys.gg rarity for this member: never drops']);
  // The row says what is sourced and checked (membership, rarity) and that the chance is the owner's adaptation; a
  // verified row says plainly that its membership and rarity are what its checks verified, an unverified one does not.
  const shell = find(doc, 'drop:2/snail-shell');
  assert.deepEqual(shell.notes.slice(0, 2), ['membership: verified against MeowDB MS Classic "Drops (MS Classic)" (monster_2.txt)',
    'rarity: Common, verified against Henesys.gg (item_rarity.json)']);
  assert.deepEqual(find(build(), 'drop:2/snail-shell').notes.slice(0, 2), ['membership: MeowDB MS Classic "Drops (MS Classic)" (monster_2.txt)',
    'rarity: Henesys.gg Common (item_rarity.json)'], 'no evidence: implemented, nothing claimed verified');
  assert.equal(find(build(), 'drop:2/snail-shell').state, 'implemented');
  assert.equal(shell.notes[2], 'chance: no cell = drop_rates.json etc_own_leftover x Common, an owner-approved adaptation (D3-11, verified: false), not a source-data gap',
    'without the owner table the row says so instead of inventing a value');
  assert.equal(shell.source_data_gap, false, 'an adaptation is not a source-data gap');
  assert.ok(shell.adaptations.includes('game/data/misostory/drop_rates.json'));
  const table = { drop_rates: { chance_table: { etc_own_leftover: { Common: 1 }, equip: { Common: 0.001 } } },
    meso_rules: { chance: 0.6, amount_level_multiplier_min: 1, amount_level_multiplier_max: 2, no_mesos: {} } };
  const withTable = build({ miso: table, tests: [unit([{ file: 'test_drops.gd', name: 'test_shell', ok: true, parity: ['drop:2/snail-shell'] }])] });
  const tabled = find(withTable, 'drop:2/snail-shell');
  assert.equal(tabled.state, 'verified');
  assert.equal(tabled.notes[2], 'chance: 100% = drop_rates.json etc_own_leftover x Common, an owner-approved adaptation (D3-11, verified: false), not a source-data gap');
  assert.deepEqual(tabled.drop_sources.chance, { adaptation: 'game/data/misostory/drop_rates.json', decision: 'D3-11', verified: false,
    category: 'etc_own_leftover', rarity: 'Common', value: 1 });
  assert.equal(tabled.drop_sources.membership.capture, 'tools/meowdb/captures/monster_2.txt');
  assert.equal(tabled.drop_sources.rarity.capture, 'tools/henesys/captures/item_rarity.json');
  assert.equal(buckler.drop_sources.chance, null, 'no rarity: no chance');
  assert.ok(withTable.adaptations.some((x) => x.adaptation === 'game/data/misostory/drop_rates.json' && x.entries === 3),
    'two drop rows of drops/2 and the older drops/9 row list the table');
  assert.ok(toMarkdown(withTable).includes('\n## Adaptations\n'));
  assert.ok(toMarkdown(withTable).includes('- \x60drop_rates.json\x60: 3 entries'));
  assert.equal(find(doc, 'meso:2').state, 'implemented');
  assert.deepEqual(find(withTable, 'meso:2').notes, ['amount: 2 per kill, MeowDB MS Classic\'s player report "Mesos: 2 per kill | 1 report"',
    'chance: 60% (meso_rules.json), an owner-approved adaptation (D3-12, verified: false), not a source-data gap']);
  const formula = structuredClone(canonical());
  delete formula.drops['2'].meso.amount_source;
  formula.monsters['2'].level = 3;
  assert.equal(find(build({ canonical: formula, miso: table }), 'meso:2').notes[0],
    'amount: [3, 6] at level 3 by meso_rules.json\'s level formula (MeowDB has no player report)');
  assert.match(find(build({ canonical: formula, miso: table }), 'meso:2').notes[1], /^chance: 60% \(meso_rules\.json\); the formula and the chance are owner-approved adaptations \(D3-12, verified: false\), not a source-data gap$/);
  const noMesos = build({ miso: { meso_rules: { no_mesos: { 2: { reason: 'owner choice' } } } } });
  assert.deepEqual(find(noMesos, 'meso:2').notes, ['drops no mesos (meso_rules.json no_mesos: owner choice)']);
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

test('a canonical-verification row about the drop data stays partial while any drop record is not schema 3', () => {
  const rules = { ...RULES, canonical_verification: [
    { key: 'canon:membership-rarity-separate', name: 'separate sources', requires: { drops_schema_version: 3 } },
    { key: 'canon:adaptations-explained', name: 'adaptations explained' },
  ] };
  const evidence = [unit([{ file: 'test_v.gd', name: 'test_rule', ok: true, parity: ['canon:membership-rarity-separate', 'canon:adaptations-explained'] }])];
  const mixed = build({ rules, tests: evidence });
  const row = find(mixed, 'canon:membership-rarity-separate');
  assert.equal(row.state, 'partial', 'drop record 9 is an older schema');
  assert.match(row.issues.join(), /drop record\(s\) 9 are not schema 3/);
  assert.equal(find(mixed, 'canon:adaptations-explained').state, 'verified', 'a row without a data requirement');
  const c = canonical();
  delete c.drops['9'];
  assert.equal(find(build({ canonical: c, rules, tests: evidence }), 'canon:membership-rarity-separate').state, 'verified', 'every drop record schema 3');
});

test('a pending source read is its own label: never excused, never verified, listed apart from the gaps; stale declarations fail', () => {
  // A drop member and an item whose record gaps say a value is published on a page nobody has read yet.
  const withGaps = () => {
    const c = canonical();
    c.drops['2'].gaps = ['rarity unresolved: Henesys.gg has no row read for "Snail Shell" yet', 'quantity: no source gives one'];
    c.items['237'].gaps = ['max_stack: shown only on the item page, which was not captured', 'sources.breakables: not captured'];
    return c;
  };
  const evidence = [unit([{ file: 't.gd', name: 'test_all', ok: true, parity: ['drop:2/snail-shell', 'item:237', 'item:348'] }])];
  const undeclared = build({ canonical: withGaps(), tests: evidence });
  assert.equal(find(undeclared, 'item:237').state, 'verified', 'record gaps alone do not make an entry pending');
  assert.equal(find(undeclared, 'drop:2/snail-shell').state, 'verified');
  assert.deepEqual(undeclared.pending_source_reads, []);
  const rules = { ...RULES, pending_source_reads: {
    'drop:2/snail-shell': { read: 'Henesys.gg loot page, Snail Shell', resolves: 'its rarity', decision: 'D3-11', fields: ['rarity unresolved'] },
    'item:237': { read: 'MeowDB item page 237', resolves: 'its max stack', fields: ['max_stack'] },
  } };
  const declared = build({ canonical: withGaps(), rules, tests: evidence });
  const shell = find(declared, 'drop:2/snail-shell');
  assert.equal(shell.source_data_gap, false, 'a published but unread value is not a source-data gap');
  assert.equal(shell.pending_source_read, true);
  assert.equal(shell.state, 'partial', 'passing evidence cannot verify it');
  assert.equal(shell.pending_reads[0].read, 'Henesys.gg loot page, Snail Shell');
  const egg = find(declared, 'item:237');
  assert.equal(egg.pending_source_read, true);
  assert.equal(egg.state, 'partial', 'a passing item test cannot verify a value still to be read');
  assert.equal(find(declared, 'item:348').state, 'verified');
  assert.deepEqual(declared.pending_source_reads.map((p) => p.key), ['drop:2/snail-shell', 'item:237']);
  assert.ok(!declared.source_data_gaps.some((g) => g.key === 'drop:2/snail-shell'), 'not listed with the gaps');
  const open = declared.categories.flatMap((c) => c.entries).filter((e) => e.in_scope && e.state !== 'verified' && !e.source_data_gap).map((e) => e.key);
  assert.ok(open.includes('drop:2/snail-shell') && open.includes('item:237'), 'counted open for the exit criterion');
  assert.equal(declared.totals.open_for_exit, open.length);
  assert.equal(declared.totals.all.pending_source_read, 2);
  assert.equal(declared.totals.by_category['monster-drops'].pending_source_read, 1);
  const md = toMarkdown(declared);
  assert.ok(md.includes('\n## Pending source reads\n'));
  assert.match(md, /- `item:237` Egg \(Use\): read MeowDB item page 237 to settle its max stack\. max_stack: shown only on the item page/);
  assert.match(md, /\| `drop:2\/snail-shell` \| .* \| partial \(pending source read\) \|/);
  // An entry with a real gap stays excused; its pending part is listed beside the gap.
  const both = withGaps();
  both.drops['2'].gaps.push('rarity unresolved: Henesys.gg has no row for "Wooden Buckler"');
  const mixed = find(build({ canonical: both, rules: { ...RULES, pending_source_reads: { 'drop:2/wooden-buckler': { read: 'x', resolves: 'y', fields: ['rarity unresolved'] } } }, tests: evidence }), 'drop:2/wooden-buckler');
  assert.equal(mixed.source_data_gap, true);
  assert.equal(mixed.pending_source_read, false);
  assert.equal(mixed.pending_reads.length, 1);
  // Stale declarations fail: the read was done (the gap removed), or no entry, or no fields.
  const read = withGaps();
  read.drops['2'].gaps = [];
  assert.throws(() => build({ canonical: read, rules }), /drop:2\/snail-shell is stale: record drops\/2 has no gap for rarity unresolved/);
  const pageRead = withGaps();
  pageRead.items['237'].gaps = [];
  assert.throws(() => build({ canonical: pageRead, rules }), /item:237 is stale: record items\/237 has no gap for max_stack/);
  assert.throws(() => build({ canonical: withGaps(), rules: { ...RULES, pending_source_reads: { 'item:999': { read: 'x', resolves: 'y', fields: ['a'] } } } }),
    /item:999 names no entry/);
  assert.throws(() => build({ canonical: withGaps(), rules: { ...RULES, pending_source_reads: { 'item:237': { read: 'x', resolves: 'y' } } } }),
    /item:237 needs "fields"/);
});
