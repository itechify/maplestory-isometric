// node --test tools/sources/test/
// The authority registry lives in game/scripts/core/validation/provenance_authorities.gd (the validator). The Node side
// only names authorities (captures.mjs AUTHORITIES); this keeps the two in step and checks that every captured URL is
// one the registry accepts for its authority.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { loadCaptures, AUTHORITIES, REPO_ROOT } from '../captures.mjs';

const gd = fs.readFileSync(path.join(REPO_ROOT, 'game/scripts/core/validation/provenance_authorities.gd'), 'utf8');

/** {authority name: {prefixes: [url prefixes], properties: [..]}} read from the GDScript REGISTRY. */
function registry() {
  const names = Object.fromEntries([...gd.matchAll(/^const (\w+) := "([^"]+)"$/gm)].map((m) => [m[1], m[2]]));
  const out = {};
  for (const m of gd.matchAll(/^\t(\w+): \{\n\t\t"url_prefixes": \[([^\]]*)\],\n\t\t"properties": \[([^\]]*)\]/gm)) {
    out[names[m[1]]] = {
      prefixes: [...m[2].matchAll(/"([^"]+)"/g)].map((x) => x[1]),
      properties: [...m[3].matchAll(/"([^"]+)"|(ANY_PROPERTY)/g)].map((x) => x[1] ?? '*'),
    };
  }
  return out;
}

const urlAllowed = (prefixes, url) => prefixes.some((p) => (p.endsWith('/') || p.endsWith('#') ? url.startsWith(p) && url.length > p.length : url === p || ['/', '?', '#'].some((s) => url.startsWith(p + s))));

test('the validator registers exactly MeowDB MS Classic, Henesys.gg and the project owner', () => {
  const reg = registry();
  assert.deepEqual(Object.keys(reg).sort(), ['Henesys.gg', 'MeowDB MS Classic', 'Project owner']);
  for (const name of Object.values(AUTHORITIES)) assert.ok(name in reg, `${name} is in provenance_authorities.gd`);
  assert.deepEqual(reg['Henesys.gg'].properties, ['rarity'], 'Henesys.gg supplies the rarity only');
  assert.deepEqual(reg['Henesys.gg'].prefixes, ['https://henesys.gg/']);
});

test('every captured page URL is accepted for its authority', () => {
  const reg = registry();
  const c = loadCaptures();
  const all = [
    c.henesys.rarity, ...Object.values(c.meowdb.monsters), ...Object.values(c.meowdb.breakables), ...Object.values(c.meowdb.quests),
    c.meowdb.quest_tracker, ...Object.values(c.meowdb.items_api.items),
  ];
  for (const x of all) assert.ok(urlAllowed(reg[x.authority].prefixes, x.url), `${x.file}: ${x.url} for ${x.authority}`);
  assert.ok(!urlAllowed(reg['Henesys.gg'].prefixes, 'https://henesys.gg.evil/loot'));
  assert.ok(!urlAllowed(reg['Henesys.gg'].prefixes, 'https://henesys.gg/'));
});
