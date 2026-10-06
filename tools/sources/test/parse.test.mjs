// node --test tools/sources/test/
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  parseKuroPercent, parseReactorChanceValue, parseHiddenStreetMesos, parseMeowdbMesoReport, normalizeItemName,
  sameItemName, entryKey, decimalShift, parseHiddenStreetMonsterText, isIsoTimestamp, SourceParseError,
} from '../parse.mjs';

const throwsParse = (fn) => assert.throws(fn, SourceParseError);

// --- KuroDB "<p>% base" --------------------------------------------------------------------------------------------

test('KuroDB percentages convert exactly (the brief\'s examples)', () => {
  const cases = [
    ['0.0700% base | Qty 1', 0.0007, '0.0007'],
    ['0.0800% base | Qty 1', 0.0008, '0.0008'],
    ['0.0300% base | Qty 1', 0.0003, '0.0003'],
    ['0.0500% base | Qty 1', 0.0005, '0.0005'],
    ['0.13% base | Qty 1', 0.0013, '0.0013'],
    ['0.10% base | Qty 1', 0.001, '0.001'],
    ['0.90% base | Qty 1', 0.009, '0.009'],
    ['0.70% base | Qty 1', 0.007, '0.007'],
    ['1.00% base | Qty 1', 0.01, '0.01'],
    ['2.00% base | Qty 1', 0.02, '0.02'],
    ['7.00% base | Qty 1 | Quest 28170', 0.07, '0.07'],
    ['12.50% base | Qty 1', 0.125, '0.125'],
    ['15% base | Qty 1 | Quest 21709', 0.15, '0.15'],
    ['26% base | Qty 1', 0.26, '0.26'],
    ['100% base | Qty 1', 1, '1'],
    ['100.00% base | Qty 1 | Quest 1035', 1, '1'],
  ];
  for (const [raw, p, text] of cases) {
    const r = parseKuroPercent(raw);
    assert.equal(r.probability, p, raw);
    assert.equal(r.probability_text, text, raw);
    assert.equal(r.raw, raw, 'raw kept verbatim');
    assert.equal(r.format, 'percent_base');
    assert.equal(r.kind, 'item');
  }
});

test('"0.0700% base | Qty 1" -> 0.0007, qty 1, no quest (task example)', () => {
  const r = parseKuroPercent('0.0700% base | Qty 1');
  assert.deepEqual({ probability: r.probability, qty: r.qty, quest: r.quest, raw: r.raw }, { probability: 0.0007, qty: { min: 1, max: 1 }, quest: null, raw: '0.0700% base | Qty 1' });
  assert.equal(r.percent_text, '0.0700', 'the percentage as written is kept');
  assert.equal(r.percent, 0.07);
  assert.equal(r.conversion, '0.0700 / 100');
});

test('"100.00% base | Qty 1 | Quest 1035" -> probability 1, quest "1035"', () => {
  const r = parseKuroPercent('100.00% base | Qty 1 | Quest 1035');
  assert.equal(r.probability, 1);
  assert.equal(r.quest, '1035');
  assert.equal(typeof r.quest, 'string', 'quest ids stay strings');
});

test('"40% base | Meso drop" is a meso chance', () => {
  const r = parseKuroPercent('40% base | Meso drop');
  assert.equal(r.kind, 'meso');
  assert.equal(r.probability, 0.4);
  assert.equal(r.qty, null);
});

test('an item page\'s global drop rule: "| Maps <from>-<to>" and "| Excludes ..." are read, not dropped', () => {
  const r = parseKuroPercent('0.0500% base | Qty 1 | Maps 211060100-211060900 | Excludes bosses | Excludes friendly mobs');
  assert.deepEqual([r.probability, r.qty, r.maps, r.excludes], [0.0005, { min: 1, max: 1 }, { from: '211060100', to: '211060900' }, ['bosses', 'friendly mobs']]);
  assert.deepEqual(parseKuroPercent('1% base | Qty 1 | Maps 100000000').maps, { from: '100000000', to: '100000000' }, 'one map');
  const plain = parseKuroPercent('0.0300% base | Qty 1');
  assert.ok(!('maps' in plain) && !('excludes' in plain), 'an ordinary row has neither key');
  for (const raw of ['1% base | Maps 5-3', '1% base | Maps 1-2 | Maps 3-4', '1% base | Maps abc', '1% base | Excludes everyone',
    '1% base | Excludes bosses | Excludes bosses']) {
    throwsParse(() => parseKuroPercent(raw));
  }
});

test('trap: integer truncation never turns a small percentage into 0', () => {
  for (const raw of ['0.0700% base | Qty 1', '0.0300% base | Qty 1', '0.05% base | Qty 1', '0.0001% base | Qty 1']) {
    const r = parseKuroPercent(raw);
    assert.ok(r.probability > 0, `${raw} is not 0`);
    assert.notEqual(r.probability, Math.trunc(r.percent) / 100, `${raw} is not truncated`);
  }
  assert.equal(parseKuroPercent('0.0001% base').probability, 0.000001);
});

test('trap: 0.01 vs 1% (percent is divided by 100 exactly once)', () => {
  assert.equal(parseKuroPercent('1.00% base | Qty 1').probability, 0.01, '1% is 0.01');
  assert.equal(parseKuroPercent('0.01% base | Qty 1').probability, 0.0001, '0.01% is 0.0001, not 0.01');
  assert.equal(parseKuroPercent('2.00% base | Qty 1').probability, 0.02, '2% is never 2 or 0.0002');
  assert.notEqual(parseKuroPercent('2.00% base | Qty 1').probability, 2);
  assert.notEqual(parseKuroPercent('2.00% base | Qty 1').probability, 0.0002);
});

test('trap: N% is never read as 1/N and 1/N never as N%', () => {
  throwsParse(() => parseKuroPercent('Chance value 4'));
  throwsParse(() => parseReactorChanceValue('4% base | Qty 1'));
  throwsParse(() => parseReactorChanceValue('25%'));
  assert.equal(parseKuroPercent('4.00% base | Qty 1').probability, 0.04, '4% is 0.04, not 1/4');
  assert.equal(parseReactorChanceValue('Chance value 4').probability, 0.25, 'Chance value 4 is 1/4, not 4%');
});

test('impossible or unreadable KuroDB percentages are rejected', () => {
  for (const raw of [
    '-1% base | Qty 1', '-0.5% base', '100.01% base | Qty 1', '150% base', 'NaN% base', 'abc% base', '% base', '',
    '1e2% base', '0x10% base', '1,5% base', '.5% base', '5.% base', '40%', '40% of base', '40% base | Qty 0',
    '40% base | Qty 3-1', '40% base | Qty -1', '40% base | Bonus 2', '40% base | Qty 1 | Qty 2', '40% base |',
    '40% base | Meso drop | Qty 1', '40% base | Quest abc', 'Infinity% base',
  ]) {
    throwsParse(() => parseKuroPercent(raw));
  }
  throwsParse(() => parseKuroPercent(null));
  throwsParse(() => parseKuroPercent(0.4));
});

test('KuroDB quantity ranges and item-page monster ids', () => {
  assert.deepEqual(parseKuroPercent('5% base | Qty 1-3').qty, { min: 1, max: 3 });
  assert.deepEqual(parseKuroPercent('5% base | Qty 2 ~ 2').qty, { min: 2, max: 2 });
  const r = parseKuroPercent('100% base | Qty 1 | Quest 1008 | ID 2000');
  assert.equal(r.source_id, '2000');
  assert.equal(r.quest, '1008');
  assert.equal(parseKuroPercent('0% base').probability, 0, 'an explicit 0% is a real (zero) chance');
});

// --- KuroDB "Chance value N" -------------------------------------------------------------------------------------

test('reactor "Chance value N" is 1/N, labelled an interpretation (D3-7)', () => {
  const r = parseReactorChanceValue('Chance value 4');
  assert.equal(r.raw_n, 4);
  assert.equal(r.probability, 0.25);
  assert.equal(r.interpretation, '1/N');
  assert.equal(r.decision, 'D3-7');
  assert.equal(r.format, 'reactor_chance_value');
  assert.match(r.conversion, /^1 \/ 4 \(interpretation, decision D3-7\)$/);
  assert.equal(r.raw, 'Chance value 4');
  const q = parseReactorChanceValue('Chance value 1 | Quest 1008');
  assert.equal(q.probability, 1);
  assert.equal(q.quest, '1008');
  assert.equal(parseReactorChanceValue('Chance value 30').probability, 1 / 30);
  assert.equal(parseReactorChanceValue('Chance value 2').probability, 0.5);
});

test('impossible reactor values are rejected', () => {
  for (const raw of ['Chance value 0', 'Chance value -1', 'Chance value 2.5', 'Chance value', 'Chance value x',
    'Chance value 4 | Qty 1', 'chance 4', '4', '1/4', 'Chance value 4 | Quest 1 | Quest 2']) {
    throwsParse(() => parseReactorChanceValue(raw));
  }
});

// --- Hidden Street and MeowDB meso amounts ------------------------------------------------------------------------

test('Hidden Street meso amounts', () => {
  assert.deepEqual(parseHiddenStreetMesos('Mesos: 4-6'), { raw: 'Mesos: 4-6', state: 'resolved', min: 4, max: 6 });
  assert.deepEqual(parseHiddenStreetMesos('Mesos: 1'), { raw: 'Mesos: 1', state: 'resolved', min: 1, max: 1 });
  assert.deepEqual(parseHiddenStreetMesos('Mesos: ?'), { raw: 'Mesos: ?', state: 'unresolved', min: null, max: null });
  assert.deepEqual(parseHiddenStreetMesos('Mesos: 8 - 12'), { raw: 'Mesos: 8 - 12', state: 'resolved', min: 8, max: 12 });
  assert.equal(parseHiddenStreetMesos('9-13').max, 13, 'the "Mesos:" label is optional');
  for (const raw of ['Mesos: 6-4', 'Mesos: -1', 'Mesos: 4.5', 'Mesos: ', 'Mesos: a', 'Mesos: 1-', 'Mesos: ??', 'Mesos: 0x4']) {
    throwsParse(() => parseHiddenStreetMesos(raw));
  }
});

test('MeowDB player meso reports', () => {
  assert.deepEqual(parseMeowdbMesoReport('Mesos: 2 per kill | 1 report'), { raw: 'Mesos: 2 per kill | 1 report', state: 'resolved', min: 2, max: 2, reports: 1 });
  assert.deepEqual(parseMeowdbMesoReport('Mesos: 2-4 per kill | 3 reports').max, 4);
  throwsParse(() => parseMeowdbMesoReport('No meso reports yet.'));
  throwsParse(() => parseMeowdbMesoReport('Mesos: 4-2 per kill | 1 report'));
});

// --- names ------------------------------------------------------------------------------------------------------

test('normalizeItemName joins spelling variants', () => {
  const same = [
    ['Red-Striped T-Shirt', 'Red Striped T-Shirt'],
    ['AquaMarine Ore', 'Aquamarine Ore'],
    ['Omok Piece : Mushroom', 'Omok Piece: Mushroom'],
    ['Grey / Brown Training Shirt', 'Grey/Brown Training Shirt'],
    ['Black Magician’s Token', "Black Magician's Token"],
    ['  Snail   Shell ', 'Snail Shell'],
    ['Double Axe ', 'double axe'],
  ];
  for (const [a, b] of same) assert.equal(normalizeItemName(a).normalized, normalizeItemName(b).normalized, `${a} ~ ${b}`);
  assert.notEqual(normalizeItemName('Arrow for Bow').normalized, normalizeItemName('Arrows for Bows').normalized, 'plurals need an alias, not normalization');
  assert.notEqual(normalizeItemName('Red Striped Top').normalized, normalizeItemName('Red-Striped T-Shirt').normalized);
});

test('gender suffixes are reported, not silently stripped', () => {
  const m = normalizeItemName('Blue Training Shirt (M)');
  assert.equal(m.gender, 'M');
  assert.equal(m.suffix, '(M)');
  assert.equal(m.base, 'Blue Training Shirt');
  assert.equal(m.raw, 'Blue Training Shirt (M)');
  assert.equal(normalizeItemName('Orange Lolica Armor (F)').gender, 'F');
  assert.equal(normalizeItemName('Snail Shell').gender, null);
  assert.equal(sameItemName('Red Cloth Pants (M)', 'Red Cloth Pants (F)'), false, 'male and female versions differ');
  assert.equal(sameItemName('Red Cloth Pants (M)', 'Red Cloth Pants'), false, 'a suffix vs none is not a silent match');
  assert.equal(sameItemName('Red Cloth Pants (M)', 'red cloth pants (m)'), true);
  throwsParse(() => normalizeItemName(''));
  throwsParse(() => normalizeItemName(null));
});

test('entry keys are stable slugs', () => {
  assert.equal(entryKey('Snail Shell'), 'snail-shell');
  assert.equal(entryKey('Blue Training Shirt (M)'), 'blue-training-shirt-m');
  assert.equal(entryKey('Omok Piece : Mushroom'), 'omok-piece-mushroom');
  assert.equal(entryKey("Black Magician's Token"), 'black-magicians-token');
  throwsParse(() => entryKey('()'));
});

test('decimalShift is exact', () => {
  assert.equal(decimalShift('0.0700', 2), '0.0007');
  assert.equal(decimalShift('100.00', 2), '1');
  assert.equal(decimalShift('2', 2), '0.02');
  assert.equal(decimalShift('12.50', 2), '0.125');
  assert.equal(decimalShift('0', 2), '0');
  assert.equal(decimalShift('5', 0), '5');
  throwsParse(() => decimalShift('-1', 2));
  throwsParse(() => decimalShift('1e-3', 2));
});

test('Hidden Street page text: categories, members and (M)/(F)', () => {
  const text = 'Snail\nLevel: 1\nHP: 15\tMP: 0\nEXP: 3\tMesos: 1\tKB: 5\nEtc. drop: Snail Shell\t\nCommon equipment: Blue Training Shirt (M), Wooden Buckler\nWarrior equipment: Wooden Mallet\nMagician equipment: Blue Training Shirt (M), Brown Apprentice Hat\nBowman equipment: Wooden Mallet\nThief equipment: Wooden Mallet, Red Cloth Pants (M)\nPirate equipment: -\n\nOre drop: -\nMaker item: -\nUseable drop: Red Potion, Blue Potion, Green Apple, Arrow for Bow, Arrow for Crossbow\n';
  const p = parseHiddenStreetMonsterText(text);
  assert.equal(p.name, 'Snail');
  assert.equal(p.items.length, 11);
  assert.deepEqual(p.mesos, { raw: 'Mesos: 1', state: 'resolved', min: 1, max: 1 });
  assert.deepEqual(p.lists['Pirate equipment'], []);
  const mallet = p.items.find((i) => i.name === 'Wooden Mallet');
  assert.deepEqual(mallet.categories, ['Warrior equipment', 'Bowman equipment', 'Thief equipment']);
  assert.equal(p.items.find((i) => i.name === 'Snail Shell').raw_lines[0], 'Etc. drop: Snail Shell');
  assert.equal(p.items.find((i) => i.name === 'Red Cloth Pants (M)').gender, 'M');
  throwsParse(() => parseHiddenStreetMonsterText(text.replace('Maker item: -\n', '')));
  throwsParse(() => parseHiddenStreetMonsterText(text.replace('Mesos: 1', 'Mesos: 1-0')));
});

test('isIsoTimestamp mirrors the validator', () => {
  for (const good of ['2026-10-04T09:56:36.674Z', '2026-10-05T07:30Z', '2024-02-29T23:59:60+09:00']) assert.ok(isIsoTimestamp(good), good);
  for (const bad of ['2026-10-05T07:3x', '2026-10-05', '2026-13-01T00:00Z', '2026-02-29T00:00Z', '2026-10-04T24:00Z', null]) assert.ok(!isIsoTimestamp(bad), String(bad));
});
