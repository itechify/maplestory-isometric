# Simulator parity oracles (MeowDB MS Classic)

MeowDB's simulators run entirely in the browser. Their calculation code ships in Next.js JS chunks. This domain
**executes that code unchanged** over a grid of Maple Island inputs. It records the results as golden vectors that the
Godot combat module must reproduce.

| Output | Path |
|---|---|
| Golden vectors (818) | `game/tests/data/parity_vectors.json` |
| Verbatim reference source, one file per tool | `docs/canonical/oracles/<tool>.js.txt` (`dmg-simulator`, `accuracy-sim`, `avoidability-sim`, `mob-hit-sim`, `exp-calculator`, `character-builder`, `dps-table`, `formulas`) |
| Generator | `tools/meowdb/oracle_vectors.mjs` |

Regenerate with `node tools/meowdb/oracle_vectors.mjs`. The script reads from the cache first. A re-run reproduces
every output byte for byte; this was checked with sha256 over the JSON and all `.js.txt` files. Add `--refresh` only if
you intend to re-pull MeowDB. See [Redeploys](#redeploys-and-refreshing).

No simulator logic is server-side. Every calculator below was recovered from client JS and executed. The only
server-supplied input is data: the dps-table's level-70 build list (page payload) and the Training Advisor's
`/_data/monster-locations.json`. Neither is used here.

**Scope.** All six monsters on the 25 Maple Island maps (1 Tutorial Jr. Sentinel, 2 Snail, 3 Blue Snail, 4 Shroom,
5 Red Snail, 9 Orange Mushroom; the same list as `docs/canonical/monsters.md`) and all four weapons sold by Sid, the
Maple Island weapon shop (Sword 541, Hand Axe 576, Wooden Club 585, Razor 558; see `shops/maple-road-sid.json`).

---

## 1. Pages and code that were read

Pages (all `https://meowdb.com/msclassic/...`): `/dmg-simulator`, `/accuracy-sim`, `/avoidability-sim`, `/mob-hit-sim`,
`/exp-calculator`, `/dps-table`, `/character-builder`, `/formulas`, `/guides/explaining-the-damage-formula`,
`/guides/exp-table-level-1-to-100` and `/guides/beginners-guide-first-steps-in-maple-world`. Fixture detail pages:
`/monsters/1`, `/monsters/2`, `/monsters/3`, `/monsters/4`, `/monsters/5`, `/monsters/9`, `/item-db/541` (Sword),
`/item-db/551` (Gladius), `/item-db/576` (Hand Axe), `/item-db/585` (Wooden Club) and `/item-db/558` (Razor). Also read:
`/msclassic/api/items?type=Equip&subtype=...`. This was only used to find the item ids. Stats come from the detail pages.

### How the code was located

1. Each simulator page's HTML lists `/_next/static/chunks/app/msclassic/[locale]/<tool>/page-*.js`.
2. These pages call `useCalculator({operation, input})`, from webpack module **47938**. Its dispatcher reads:
   `Promise.all([s.e(7135), s.e(6549), s.e(4790), s.e(4368)]).then(s.bind(s, 4790))`, then
   `switch (operation) { "damage": calculateDamage, "accuracy": calculateAccuracy, "avoidability": calculateAvoidability,
   "character-stats": calculateCharacterStats }`. `"mob-danger"` loads chunk 2150 (`computeMobDangerRows`).
3. The webpack runtime (`webpack-627aa0b35ae17090.js`) has a `.u` map that turns those chunk ids into hashed file names.

| Chunk (`https://meowdb.com/_next/static/chunks/...`) | Webpack modules used |
|---|---|
| `4790-688bba5b679fd1bc.js` (lazy) | **4790**: calculator engine. Exports `calculateDamage`, `calculateAccuracy`, `calculateAvoidability`, `calculateCharacterStats`, `incomingDamage`, `incomingHitRate`, `outgoingHitRate`, `guardChanceFor`, `statDerivedAccuracy` and **`FORMULA_PARITY_KERNELS_PRIVATE`** (`levelScale`, `mastery`, `physicalRaw`, `finalRoll`, ...). Also contains **58903** (accuracy), **63584** (attack timing) and **64007** (final attack) |
| `4368.e968ea2f15da4f52.js` (lazy) | **13805**: class tables, `jQ` total stat points, `lM` default AP plan, `H8` base HP/MP. Also **17033** (weapon requirement breakpoints), **36751**, **43239** and **68726** (scroll bonus totals) |
| `7135-240168d5571b96bf.js` (lazy) | **57135**: skill catalog `J3` (`basic_attack_warrior`, `basic_attack_thief`, `power_strike`, ...) and `XB`, the monster list filter (§2.4) |
| `6549-8ccdabf5b9357200.js` (lazy) | **96549**: scroll catalog, required by 68726 |
| `2150.42d12b8816737776.js` (lazy) | **42150**: `computeMobDangerRows` (mob-hit-sim) |
| `2700-281eba0f40bad0d4.js` (lazy) | **92700**: `monsterCombat` (touch boxes and attack ratios) |
| `782-bb5a5ee666dc6188.js` | **60782**: `IW`, the simulators' embedded monster table |
| `6459-e11456f2ce797f6c.js` | **17401**: EXP table (`jy`, `ML`, `Bq`). **27279**: cumulative EXP (`H1`, `Se`, `Mg`) |
| `5253-8d210be12f2a3111.js` | **51894**: the `/formulas` page "Try values" calculators. Also **70361** and **92560** (i18n) |
| `3997-838740702365190e.js`, `4068-26c6ed6efe1adbc7.js` | **61408**, required by 51894. **74920**, the i18n helper. 4068 also carries a second build of 13805 |
| page chunks for accuracy-sim, avoidability-sim, mob-hit-sim, exp-calculator and dps-table, plus `4916-85509b9cd591ff3d.js` (dmg-sim UI) and `4818-741685483b96d7a7.js` (builder UI) | input assembly and display code (reference text) |

The JSON header `oracles` lists, for each oracle, the page URL and two chunk lists. Each chunk entry has the URL,
`retrieved_at` from the cache metadata, the byte count and the sha256.

- `chunks`: the files the reference text (`<tool>.js.txt`) is sliced from.
- `executed_chunks`: every chunk file whose code actually ran to produce that oracle's vectors. The script traces this
  from the webpack loader (the dependency closure of the oracle's top-level module, plus any page chunk whose snippet is
  evaluated). Example: mob-hit-sim also executes 782 (monster table), 4368, 6549 and 7135. dps-table is not executed.

### Execution method (tools/meowdb/oracle_vectors.mjs)

- The cached chunk files are evaluated **verbatim** inside a `node:vm` context. The context has
  `self.webpackChunk_N_E = {push}` and a webpack `require` shim of about 20 lines (`d`, `r`, `o`, `n`, `e`). The exported
  functions are then called directly. No formula is re-typed.
- When a module id is registered twice, the first registration wins: 4368's 13805 is used, not 4068's. The two builds
  were compared for every class at levels 1-120 (`H8`, `lM`, `jQ`). Their outputs are identical.
- **The only source adaptation** is one token in module 51894. The page module keeps its calculator table `Y` local, so
  `l.d(a,{default:()=>ea})` becomes `l.d(a,{default:()=>ea,__calculators:()=>Y})` in the executed copy. The script
  asserts that the original text occurs exactly once.
- `react/jsx-runtime` (95155) and `react` (12115) are stubbed with empty objects. Only render code uses them.
- Some page-component code is not a module export. The script slices it verbatim, then evaluates it with its free
  variable bound:
  - the exp-calculator validation/remaining-EXP IIFE, with `d` = module 27279
  - the kills expression `Math.ceil(t/r)`, wrapped as `(()=>{let t,r;return <verbatim>})()`
  - the dmg-simulator table display helper `function E(e)`
- Before any execution, the script checks that the cached pages still reference these exact chunk files and that the
  webpack runtime still maps the lazy chunks. It fails loudly if not.
- Built-in assertions (the script throws if any fails):
  - For every Beginner build and starter weapon, `calculateDamage` with the Beginner input shape and no target returns
    exactly the character builder's `beginnerDamage`. This proves the input shape used for the monster vectors is
    MeowDB's own.
  - The explicit-roll extremes (both rolls 0, both rolls 1, over swing/stab) equal `per_hit.min` / `per_hit.max` of the
    matching `beginner_damage_vs_monster` vector.
  - The mob-hit-sim rows are exactly the Maple Island monsters that pass MeowDB's list filter `XB`.
  - `calculateDamage` returns exactly one row for the requested basic attack.
- Each block in `docs/canonical/oracles/*.js.txt` is sliced from the cached chunk by webpack module id plus a unique
  needle. The slicer is string- and template-literal-aware. Every block is checked twice: it must compile with
  `vm.Script` (no truncated slice), and it must be a byte-exact substring of the chunk that was executed.

---

## 2. The oracles: formulas, rounding and truncation

Notation follows the damage formula guide. "trunc" means truncate toward zero. "Display" means what the page shows,
which is not what the engine returns.

### 2.1 dmg-simulator: `calculateDamage` (module 4790, `eb` → `ex`)

Raw physical roll `J(input, skill, action, baseRoll, statRoll)`:

```
Raw = (0.8 + 0.2*baseRoll + (P * W * (m + statRoll*(1-m)) + Q) / StatDiv + AP / APDiv) * TotalWATK * (Coefficient/100)
m = E(MasteryLevel) = (clamp(MasteryLevel,0,10)/10 + 0.1) * 0.8      // mastery 0 -> 0.08
StatDiv = 300 for close-range hits with Bow/Crossbow/Claw (else 100); APDiv = 150 for close-range non-stab (else 50)
MIN = J(0,0), MAX = J(1,1), midpoint = (MIN+MAX)/2      (function F)
```

- **Actions (function K).** An `"inherit"` skill (every `basic_attack_*`) on a melee weapon takes the swing and stab
  ranges. MIN is the smaller of the two MINs. MAX is the larger of the two MAXes. The average is `0.6*swing.avg + 0.4*stab.avg`.
- **Weapon multipliers (table `f`).** 1H Sword swing/stab 1.8. 1H Axe and 1H Blunt 2.4/1.2. Dagger 1.0/2.0. The full
  table is in the extract.
- **Final roll `er(raw, input, skill, wdefIgnore, critDmgPct, ironArrowIndex, truncate=true, pct=100)`:**
  ```
  c = raw * ((100/(DEF+100))*(1-ignore) + ignore) * Element * LevelScale(playerLevel, targetLevel)
  x = clamp((pct/100) * (c [+ amp% * c for magic]) * (1 + critDmgPct/100) * max(0, 1 - 0.2*ironArrowIndex), 1, 99999)
  result = truncate ? trunc(x) : x
  ```
  DEF is `target.pdef`, or `target.mdef` for magic. Without a target, DEF = 0 and the level scale is 1. A crit
  multiplies the untruncated value, and the truncation comes after it. Example: raw 14.598 with a crit is
  trunc(17.52) = **17**. Truncating first would give trunc(14)·1.2 = 16.8 → 16. See `defense_curve_and_final_clamp`.
- **Level scale `Z(a, t)`.** With gap = t − a: gap ≤ 0 → 1; 1-9 → 1/(1+gap²·0.005); ≥10 → 1/(1+0.05·gap).
- **Per hit `en`.**
  - `min` and `max` are `er(...)` **truncated**. The 7th argument of `en`, which `ex` passes as `false` for
    `perHit`, only disables the Shadow Partner mirror. It does **not** disable truncation.
  - `avg = Math.round(10 * er(midpoint, …, truncate=false)) / 10`. This is the untruncated midpoint, clamped and rounded
    to 0.1.
- **Row fields.** `perHit` = `en`. `perCast` = `perHit × hitsPerCast`. Crit expectation:
  `perCastAvgCrit = (avg_noncrit*(1-c) + avg_crit*c) * hitsPerCast * procRate`, where `avg_crit` is `en` with
  `critDmgPct = critDamage`. Each avg is rounded to 0.1 before it is mixed.
- **Base crit (function `eg`).** `critRate = critRateOverride ?? 5 + gear + passives` and
  `critDamage = critDamageOverride ?? 20 + …`.
- **Display (4916, `function E`).** `Math.floor(x).toLocaleString("en-US")`, and `"0"` for 0 or non-finite values. The
  table shows MIN = floor(perHit.min), MAX = floor(perHit.max), AVG = floor(perCast.avg) and AVG+crit =
  floor(perCastAvgCrit).
- **Beginners.** The dmg-simulator has no Beginner class. Its class list maps every class to Warrior/Magician/Bowman/Thief
  (1st). MeowDB's own Beginner path is in the character builder (§2.5, `eI`). It picks the 1st-job basic attack by
  weapon family, always with masteryLvl 0 and no crit (`critRateOverride: 0`, `critDamageOverride: 0`):

  | Weapon | Skill | mainClass | primary | secondary |
  |---|---|---|---|---|
  | Sword, Axe, Blunt (and any other melee) | `basic_attack_warrior` | Warrior | STR | DEX |
  | Dagger, Claw (Razor) | `basic_attack_thief` | Thief | LUK | STR + DEX |
  | Bow, Crossbow | `basic_attack_bowman` | Bowman | DEX | STR |

  The `beginner_damage_vs_monster` and `physical_roll_explicit` vectors pass **that exact input shape** to
  `calculateDamage` and add `target` and `includeSkillKeys`. The script asserts that, with no target, the result equals
  `beginnerDamage` for every build and weapon.
- **Random rolls: MeowDB's sampler (`eh`, with `ed` and the RNG `eu`).** The simulators' Monte Carlo summaries
  (quartiles, kill distributions) draw hits this way, in this order:
  1. Once per cast, the action. For an `"inherit"` skill on a melee weapon: **swing if rng() < 0.6, otherwise stab**.
     Bow/Crossbow/Claw shoot. Other skills use their fixed action.
  2. Per hit, the raw roll `J(base = rng(), stat = rng())`: two independent U(0,1) draws, base first.
  3. Per hit, the crit draw: crit if rng() < critRate/100 (`alwaysCrit` skills always crit).
  4. `er` (defense, element, level scale, crit multiplier, clamp, trunc).

  `eu` is a xorshift32 generator with the fixed seed `0x6d2b79f5`. It only makes MeowDB's summaries repeatable; the game
  must not copy it. `eh` is not exported, so the 0.6 action split is documented from source
  (`docs/canonical/oracles/dmg-simulator.js.txt`, blocks `eu`, `ed`, `eh`) rather than vectorized. The 0.6/0.4 weights are
  the same ones `K` uses for the average. For 1H Sword (swing = stab = 1.8) the action does not change damage. For the
  Hand Axe and Wooden Club (2.4 / 1.2) and the Razor (Dagger, 1.0 / 2.0) it does.

### 2.2 accuracy-sim: `calculateAccuracy` (module 58903 `r`; `outgoingHitRate` = `i`)

```
if monAvoid <= 0 -> 100;  if acc <= 0 -> 0
L = max(0, monLevel - charLevel);  A = 100*acc/(10L + 255);  D = A - monAvoid;  f = 0.15 + 0.2/(1+exp(D/12))
auto-hit (100) when D >= 25 + L*(0.5*charLevel + 15)
else 100 * clamp(q <= 1-f ? 1 : q >= 1+f ? 0 : (1+f-q)/(2f), 0, 1)   with q = monAvoid/A
```

- The output `hitRate` is an **unrounded float percent**.
- `min`, `max` and `milestones` (25/50/75/90/95/100) are the ACC values that reach each hit rate. They come from a
  64-step bisection and are floats. When monAvoid ≤ 0 they are all 0.
- Page input: `acc` is the typed ACC plus the potion (Sniper +5, Supreme Sniper +7).
- Page display: the label is `"100%"` when hitRate ≥ 99.5, so 99.5-99.99 also shows "100%". Otherwise it is
  `hitRate.toFixed(1)+"%"`, and `"0%"` at 0. ACC targets are shown with `Math.ceil`.
- The `/formulas` "outgoing-hit" calculator (51894) is a second, independent implementation. It shows
  `toLocaleString(maxFrac 1)+"%"`. It agrees on all 160 grid cases.

### 2.3 avoidability-sim: `calculateAvoidability` (`eS`), `incomingHitRate` (`e_`), `incomingDamage` (`eP`), `guardChanceFor` (`eC`)

```
G = max(0, charLevel - monLevel);  A = monAcc*100/(5*(G+51));  E = avoid/(1+avoid/80)/(1+G/40);  D = A - E
f = 0.15 + 0.2/(1+exp(D/12));  cand = P(A*R >= E), R ~ U(1-f, 1+f)
if E > A*(1+f): cand = clamp(0.03*exp(D/18), 0.02, 0.03)
monster hit % = clamp((cand + (1-cand)*0.08) * 100, 0, 100)      (0 if monAcc <= 0);   dodgeRate = 100 - that
incomingDamage(atk, DEF, L): for roll in (1.1, 1.3, 1.5): x = atk*roll
   raw = trunc(x);  taken = trunc(clamp(x * (1 - DEF/(DEF + 5*(max(1,L)+40) + 1.2x)), 1, 5e7))
guard = max(shieldWdef>0 ? max(0.05, W/(W+500)) : 0, clawGuardLv: 1-6 -> .03, 7-13 -> .04, 14-20 -> .05)
expectedPhysicalDamagePerAttempt = takenAvg * (100-dodge)/100 * (1-guard)
```

- `taken` uses the **untruncated** `x`, not `raw`.
- Because of the 8% minimum-hit rescue, the dodge rate never reaches 100% (at most about 90.2%). `max` (AVOID for 100%
  dodge) is therefore `null`, and so is every unreachable milestone.
- Page display: the dodge label follows the same ≥99.5 / `toFixed(1)` rule as accuracy. Avoid targets use `Math.ceil`.
  Damage is shown as integers with `toLocaleString("en-US")`. Expected damage uses `toFixed(1)`.

### 2.4 mob-hit-sim: `computeMobDangerRows` (module 42150)

- The rows are `IW.filter(XB)`. `XB` (module 57135, `function W`) drops monsters with HP 0 or EXP 0, names starting with
  "Tutorial", invincible monsters and "(alt)" entries. **Tutorial Jr. Sentinel (1) therefore has no mob-hit-sim row.**
  The same filter builds the dmg-simulator target list and the exp-calculator monster list. The accuracy-sim and
  avoidability-sim lists drop only invincible monsters, so they do offer it.
- Each monster's contact attack is `pdmg`. If `monsterCombat[id].attacks` has a ratio of 100 or more, the attack is
  `trunc(pdmg*ratio/100)` instead. None of the six Maple Island monsters has attack entries.
- Damage comes from `incomingDamage`. Power Crash is applied as `trunc(t/100*a + a)`. If attack ≤ 0, the result is 0.
  **This guard differs from the raw kernel**; see the discrepancies.
- `hpFraction = damageAfterDef / HP`. Tiers by resource fraction: ≥0.5 `lethal`, ≥0.25 `danger`, ≥0.1 `caution`,
  otherwise `safe`.
- Display uses `Math.round` for damage and for `100*hpFraction`.

### 2.5 character-builder: `calculateCharacterStats` (`eI` → `eT`, `eA`)

- **Accuracy.** `Common = 1.2*DEX + 2*Level + 0.6*LUK`. Then:
  - Beginner: `floor(Common/2.5 + 5)`
  - Warrior: `floor(Common/2.5 + 10)`
  - Bowman: `floor(Common/4.8 + 20)`
  - Thief: `floor(0.25*Common + 15)`
  - Magician: `floor((1.2*INT + 2*Level + 0.6*LUK)/5.1 + 20)`
  - `Level = max(1, level)`
- **Other derived stats.** `EVA = floor(LUK/3) + floor(DEX/6) + 5`. `WDEF += floor(STR/4)`. `MDEF += floor(INT/4)`.
  `Magic += floor(INT/2)`. Each is added after the equipment totals.
- **HP/MP.** `trunc(base * (1 + maxHpPct/100))`, where base comes from `13805.H8`. For a Beginner that is
  `HP = 50 + 16*(L-1)` and `MP = 5 + 12*(L-1)`. Percent WDEF buffs are **not** truncated.
- **Default stats.** Crit is 5% / +20%. Speed is clamped to 0..140 and jump to 0..120.
- **Beginner damage window.** `beginnerDamage = en(...)` with no target and no crit. This is the character stat-window
  range. It is `null` without a weapon.
- **AP.** Total stat points are `jQ(L) = 25 + 5*(L-1)`: 4/4/4/4 plus 9 creation AP plus 5 per level.
  `lM("beginner", L)` puts every free point into STR, which matches the Beginner guide's "all of it in your primary
  until level 10". `lM` for other classes raises the secondary stat to the weapon-requirement breakpoint (module 17033).

### 2.6 exp-calculator (modules 17401, 27279 and the page IIFE)

```
jy[L] (EXP to next, L = 1..99):  L <= 5: (floor(L^2/2)+15)*L;  L <= 50: q = floor(L^2/3), (q+19)*q;  else trunc(1.0548*jy[L-1])
Bq(L)    = sum jy[1..L]          ("Total from Lv 1" = EXP from level 1 to reach L+1; the EXP guide's "Cumulative from lv 1")
H1(L, x) = sum jy[1..L-1] + floor(x)  (total EXP at level L with x EXP; level cap Mg = 100)
page: valid if 1 <= L < 100, L < target <= 100, 0 <= x < jy[L]; expRemaining = H1(target,0) - H1(L,x);
      confidence "current" if target <= 50 else "historical"; kills = Math.ceil(expRemaining / mobExp); time = Math.round(min)
```

- There are two cumulative conventions: `Bq(1) = 15` but `H1(1,0) = 0`. Each vector records both.
- The calculator applies no level-difference or party EXP modifiers.

### 2.7 /formulas page calculators (module 51894) — the second implementation

These calculators are used as cross-checks. They return display strings built with
`toLocaleString("en-US", {maximumFractionDigits: n})`. That is Intl's default **half-expand rounding, not truncation**:

| Calculator | Display precision |
|---|---|
| Raw damage | 0 decimals |
| Damage after defense | 0 decimals |
| Crit and expected crit | 0 decimals |
| Damage after level gap | 0 decimals |
| Percentages | 1 decimal |
| Accuracy rolls | 2 decimals |
| `clamp` | the only one that truncates |

### 2.8 dps-table

The dps-table page takes **server-supplied level-70 2nd-job builds** from its page payload. It re-runs them through the
same `calculateDamage`, against a custom target (`{level: 70, pdef, mdef, element}`). It scales by `vs8Crit/perCastAvgCrit`
and displays with `Math.round`. It has no Beginner content, so it produces no vectors. Its kernel is already covered by
the dmg-simulator vectors.

---

## 3. The vector file

The top-level keys are: `id`, `name`, `source`, `field_sources`, `generator`, `execution`, `units`, `oracles`,
`fixtures`, `vectors`, `discrepancies`, `notes` and `gaps`.

Each vector has these fields:

| Field | Meaning |
|---|---|
| `mechanic` | which mechanic the vector tests |
| `case_id` | unique within a mechanic |
| `inputs` | exactly what was passed to the oracle (positional kernels: descriptive keys in call order, see below). Extra bookkeeping keys: `plan`, `monster_id`, `monster_ids`, `weapon_item_id` |
| `outputs` | the oracle's return value, unmodified apart from JSON |
| `oracle_source` | `{oracle, function}`. `oracle` is a key into the top-level `oracles` |
| `cross_checks` | optional `[{oracle_source, inputs, outputs, agrees, note?}]` from a second MeowDB implementation (or the monster detail page). `agrees` is always a top-level boolean |
| `guide_expected`, `agrees_with_guide` | optional: the values the guide states, and whether the oracle matches them |
| `synthetic_inputs` | `true` when the inputs are test points, not MeowDB data: grid cases, explicit rolls, and every vector built from a `synthetic_str_dex_split` build |
| `notes` | optional |

Key naming: the wrapper keys are snake_case (`mechanic`, `case_id`, `oracle_source`, `cross_checks`, fixture fields).
Inside `inputs` and `outputs`, MeowDB's own camelCase field names are kept verbatim (`charLevel`, `monAvoid`, `hitRate`,
`takenMin`, `perHit`, `critRate`, …). This is deliberate: they are the literal call arguments and return shapes of the
executed functions, so a test can replay the exact call.

### Fixtures

- **`monsters`.** Tutorial Jr. Sentinel (1), Snail (2), Blue Snail (3), Shroom (4), Red Snail (5) and Orange Mushroom (9).
  Values come from the simulators' embedded table (module 60782). They were cross-checked field by field against each
  `/monsters/<id>` page: level, HP, EXP, touch base P.DMG, M.DMG, P.DEF, M.DEF, ACC and AVOID. All match. Every one of
  these monsters has AVOID 0 and P.DEF 0. Only Red Snail has M.DEF 30.
  `listed_by_dmg_sim_mob_hit_sim_exp_calc` is the result of MeowDB's list filter `XB` (§2.4). It is `false` only for
  Tutorial Jr. Sentinel.
- **`items`.** Sword 541 (W.ATK 17, speed 4), Hand Axe 576 (17, speed 4), Wooden Club 585 (19, speed 5), Razor 558
  (Dagger, 23, speed 4, REQ LEV 5) and Gladius 551 (47, speed 4, level 30). All values come from the item detail pages.
  `weapon_multipliers` is the page's "Weapon Multipliers" swing/stab. The script checks it against the engine's table
  (`weaponRollsForScripts`); all five match. The builds use clean items: no scrolls and no stat variance.
- **`beginner_builds`.** Levels 1, 5, 8 and 10 × two AP plans:
  - `meowdb_ap_plan` = `lM("beginner", L)`: STR 13/33/48/58, DEX 4.
  - `synthetic_str_dex_split`: STR gets `ceil(free/2)` and DEX gets `floor(free/2)`. This is **test input only**, not a
    MeowDB recommendation.

  Each build stores its `stats_with_sword`. The weapon changes only W.ATK. Every vector derived from a
  `synthetic_str_dex_split` build carries `synthetic_inputs: true`.

### Mechanics (counts)

| mechanic | n | oracle | what it pins down |
|---|---|---|---|
| `character_stats_and_damage_window` | 38 | character-builder | Beginner ACC/EVA/WDEF/MDEF/Magic/HP/MP and the stat-window range, for Sword, Hand Axe, Wooden Club, Razor (Lv ≥ 5) and no weapon (`beginnerDamage: null`) |
| `beginner_damage_vs_monster` | 228 | dmg-simulator | Basic attack vs the 6 monsters, `window` (no crit) and `default_crit` (5%/+20%); per_hit/per_cast/avg_with_crit + page display strings. Sword: all 8 builds. Hand Axe, Wooden Club, Razor: the MeowDB AP-plan builds (Razor from Lv 5) |
| `physical_roll_explicit` | 48 | dmg-simulator kernels `physicalRawRollForAction` (J) + `finalRoll` (er) | One hit at fixed rolls: 4 starter weapons × swing/stab × (base, stat) ∈ {(0,0), (1,1), (.5,.5), (0,1), (1,0), (.25,.75)}; raw, and final vs Snail (gap 0) and Orange Mushroom, with and without +20% crit. Lv 1 build (Razor: Lv 5) |
| `accuracy_hit_chance_vs_monster` | 48 | accuracy-sim | Beginner ACC vs the 6 monsters (all 100%: AVOID 0) |
| `accuracy_acc_milestones` | 32 | accuracy-sim | ACC needed for 0+/25/50/75/90/95/100% at player Lv 1/10, gaps 0/3/10/20, AVOID 0/5/10/20 |
| `accuracy_hit_chance_grid` | 160 | accuracy-sim × /formulas `outgoing-hit` | hit % for ACC 8/15/25/40/80 on that grid; both implementations agree |
| `avoid_and_incoming_damage_vs_monster` | 48 | avoidability-sim | dodge %, guard, physical/magic raw+taken min/avg/max, expected damage per attempt, avoid milestones; 6 monsters |
| `mob_hit_danger` | 8 | mob-hit-sim | per build: landed hit, HP fraction and tier for the 5 listed monsters (no row for Tutorial Jr. Sentinel, §2.4) |
| `monster_touch_damage_display` | 6 | incomingDamage × monster page | `trunc(P.DMG*1.1)-trunc(P.DMG*1.5)` equals each page's "Touch DMG" (1-1, 3-4, 5-7, 7-10, 9-13, 18-25) |
| `incoming_hit_chance_grid` | 50 | incomingHitRate × /formulas `incoming-hit` | monster hit % (ACC 33/62; AVOID 0-150; level gaps) |
| `incoming_damage_curve` | 60 | incomingDamage × /formulas `incoming-damage` | taken damage vs DEF and level |
| `shield_guard_chance` | 5 | guardChanceFor × /formulas `guards` | shield guard curve |
| `level_gap_scale` | 7 | kernel `levelScale` × /formulas `level-gap` | gaps −5, 0, 1, 5, 9, 10, 20 → 1, 1, 0.99502, 0.88889, 0.71174, 0.66667, 0.5 |
| `defense_curve_and_final_clamp` | 25 | kernel `finalRoll` × /formulas `monster-defense` | raw × P.DEF (0/10/30/100/500), truncated, untruncated and with +20% crit |
| `defense_ignore`, `magic_defense_curve` | 4, 2 | kernel `finalRoll` | ignore 0.2/1.0; M.DEF path |
| `final_clamp` | 5 | kernel `finalRoll` × /formulas `clamp` | 0 → 1, 0.4 → 1, 1.7 → 1, 99999.9 → 99999, 150000 → 99999 |
| `crit_expectation` | 5 | /formulas `critical` | Normal×(1+d) and Normal×(1+c·d) (display-rounded). `inputs` are the calculator's own fields: `normal`, `criticalDamage`, `criticalRate` (percent) |
| `guide_example_lv30_warrior_stats` | 1 | character-builder | AP plan 132/30/4/4 and 170 total AP (parsed from the guide; also equal to `lM("warrior", 30)` and `jQ(30)`), W.ATK 47, ACC 49, EVA 11, Magic 2, WDEF 33, MDEF 1 = guide |
| `guide_example_lv30_warrior_damage_window` | 1 | dmg-simulator (+ /formulas cross-checks) | Gladius 60-172 and Power Strike 157-449 = guide |
| `guide_example_beginner_starter_weapon_hits` | 3 | character-builder | 13/4/4/4 (parsed from the guide; equals `lM("beginner", 1)`) vs Snail (45 HP): Sword and Hand Axe need 4/3/3 hits, Wooden Club 3/3/2 = Beginner guide table |
| `exp_requirement` | 30 | exp-calculator × /formulas `exp-table` × EXP guide | Lv 1-30: EXP to next, H1, Bq, calculator result, kills per monster (Lv 1-10, 6 monsters) |
| `exp_calculator_validation` | 4 | exp-calculator | page defaults (10 → 30 = 545,290) and rejection cases |

Total: 818 vectors. There are 352 cross-checks; 350 agree. The two that disagree are listed below.

### How a Godot test should consume this

- **Exact match** for every integer the game will display or apply:
  - `per_hit.min/max`, `per_cast.min/max` and `display.*`
  - `final_truncated` and `final`
  - `physical.raw*/taken*`
  - derived stats, EXP values, kills and hits
- **Tolerance match** (about 1e-9 relative) for floats: hit/dodge percentages, ACC/AVOID milestones, `final_untruncated`,
  `raw` (explicit rolls), `level_scale` and expected damage per attempt. These go through `Math.exp` and bisection.
- **`avg` fields** are rounded to 0.1 by MeowDB. Compare them exactly against the same rounding:
  `round(10 * untruncated_midpoint) / 10`.
- **/formulas cross-check outputs** are display strings. Treat them as evidence, not as the game's numbers.
- **Expected values are not a roll sampler.** These vectors pin MIN, MAX and expectations. A real hit follows MeowDB's
  sampler order (§2.1): one action draw per cast (inherit melee: swing with probability 0.6, else stab), then per hit
  `baseRoll` and `statRoll` as two **independent** U(0,1) rolls (guide: "B and Q are independent random draws"), then a crit
  draw, then the `er` pipeline. Test the game's roll function **deterministically** against `physical_roll_explicit` (the
  same action and rolls must give the same `raw` and `final_*`). Test the sampler **statistically** against MIN/MAX/avg,
  never as a single uniform draw between MIN and MAX.
- **`physical_roll_explicit` inputs.** `damage_input` is the Beginner `calculateDamage` input with no target. The kernel
  call is `J(ew(damage_input), skill, action, baseRoll, statRoll)`. `final_by_monster[id]` is `er(raw, ew(damage_input
  with target = monster), skill, 0, critDmg, 0, truncate)`, where the target is the fixture monster as in
  `beginner_damage_vs_monster`.
- **Positional kernels.** Where `oracle_source.function` is a positional kernel, `inputs` uses descriptive keys in call
  order: `incomingDamage(monster_attack, player_def, player_level)`, `incomingHitRate(monAcc, charAvoid, charLevel,
  monLevel)`, `levelScale(player_level, target_level)` and `guardChanceFor(shield_wdef, claw_guard_level)`.

---

## 4. What a game programmer must know

- **Pipeline order** (from `er`):
  1. hit check (`outgoingHitRate`)
  2. raw roll `J`
  3. × defense curve `100/(DEF+100)`, with the optional ignore blend
  4. × element
  5. × level scale (only when the target is higher level)
  6. (magic: + Element Amplification)
  7. × (1 + crit%/100)
  8. × Iron Arrow falloff
  9. clamp(1, 99,999)
  10. **trunc**

  Crits and the clamp apply to the untruncated value. This matches the guide's order table.
- **Beginner with a Sword.** It is a Warrior basic attack:
  - inherited action (swing and stab are both 1.8 for a 1H Sword)
  - mastery 0 → m = 0.08
  - STR primary, DEX secondary, StatDiv 100, APDiv 50

  Level-1 window with 13 STR/4 DEX: **14-21** (avg 18.1).
- **The other Maple Island weapons** (MeowDB AP plan, no target):

  | Weapon | Skill (primary / secondary) | swing / stab | Lv 1 | Lv 5 | Lv 10 |
  |---|---|---|---|---|---|
  | Sword 541 | warrior (STR / DEX) | 1.8 / 1.8 | 14-21 (18.1) | 15-27 (21.4) | 15-35 (25.6) |
  | Hand Axe 576 | warrior (STR / DEX) | 2.4 / 1.2 | 14-22 (18.3) | 14-31 (21.8) | 15-41 (26.2) |
  | Wooden Club 585 | warrior (STR / DEX) | 2.4 / 1.2 | 16-25 (20.4) | 16-34 (24.4) | 17-46 (29.3) |
  | Razor 558 (REQ LEV 5) | thief (LUK / STR+DEX) | 1.0 / 2.0 | - | 26-33 (29.9) | 32-39 (35.7) |

  For split weapons MIN comes from the action with the lower multiplier and MAX from the higher one (Axe/Club: stab /
  swing; Razor: swing / stab), so a single hit's range depends on the action drawn (§2.1). The Razor's high floor comes from STR+DEX as its secondary stat. This agrees with the Beginner guide's
  advice to switch to the Razor at level 5 for higher minimum and average damage than the Wooden Club.
- **Level gap matters on Maple Island.** A level-1 Beginner (14-21) hits an Orange Mushroom (Lv 8, gap 7, scale 0.803)
  for **11-17**. Against a Red Snail (Lv 4) the result is **13-20**. Tutorial Jr. Sentinel and Snail are level 1, so they
  take the unscaled window.
- **Contact damage.** A level-1 Beginner (WDEF 3, AVOID 6) takes 3-4 from a Snail and 18-25 from an Orange Mushroom.
  The Orange Mushroom result is half of the 50 HP, so mob-hit-sim rates it `lethal`. The Beginner never dodges these
  monsters: dodge 0%. AVOID 11.26 is needed before a Snail can miss at all. Tutorial Jr. Sentinel's touch damage is
  1-1 (P.DMG 1).
- **Tutorial Jr. Sentinel (1)** is a real Maple Island monster (map 000000030, quest 1005). MeowDB's dmg-simulator,
  mob-hit-sim and exp-calculator hide it from their lists (§2.4). Its vectors run the same engines on its
  simulator-table stats, so they are as canonical as the others, but no MeowDB page shows those exact results.
- **Hit chance vs these monsters is always 100%.** Their AVOID is 0. Keep the full accuracy formula anyway. The grid
  vectors pin it.
- **Crit.** MeowDB applies the base 5% / +20% crit to every class in `calculateDamage`; the character builder shows the
  same for a Beginner. The stat-window range (`beginnerDamage`) excludes crit.
- **Do not reuse the /formulas page's displayed ranges as damage.** They are rounded. Example: 61-173 instead of 60-172.

---

## 5. Discrepancies

Each item lists both values and which one was chosen.

1. **/formulas "Physical damage" calculator vs the guide (Gladius example).**
   - The guide (*explaining-the-damage-formula*) says `trunc(...)`: **60-172**, and Power Strike **157-449**.
     `calculateDamage` and `calculateCharacterStats` return the same.
   - The `/formulas` calculator shows **61-173** and **158-449**. It formats the untruncated raw roll with
     `toLocaleString(maximumFractionDigits 0)`.
   - **Chosen: truncation (60-172)**. That is the guide plus both simulators. The `/formulas` value is display rounding
     of a pre-truncation number. This was detected automatically and is listed in the JSON `discrepancies`.
2. **Zero-attack incoming damage.**
   - `incomingDamage(0, …)` clamps `taken` to **1**. `calculateAvoidability` therefore returns `magic.taken* = 1` for
     every monster with M.DMG 0. The avoidability page hides that block when M.DMG is 0.
   - `computeMobDangerRows` guards attack ≤ 0 → **0**.
   - **Chosen: 0** (no attack, no damage). The game must not deal 1 magic damage from a monster with no magic attack.
     The raw kernel output is still in the vectors.
3. **Crit expectation: guide closed form vs simulator rounding.**
   - The guide writes `Normal × (1 + c·d)`.
   - The simulator mixes two separately 0.1-rounded averages: `avg*(1-c) + avgCrit*c`. Example, Lv 1 Sword vs Snail:
     **18.285**. The closed form gives 18.1 × 1.01 = 18.281 on the rounded average, or 18.128 × 1.01 = 18.309 on the
     unrounded midpoint.
   - The formula is the same and only the rounding path differs. The vectors carry the simulator's numbers.
4. **Heal vs undead (not tested; Cleric only).**
   - The simulator code (`q` in 4790) computes `trunc(Pool × (1 + 0.1t)) / t × 0.5`. `er` then truncates again at the
     end, so the result equals `trunc(trunc(Pool')/t × 0.5)` with `Pool' = Pool × (1 + 0.1t)`. That matches the
     `/formulas/damage` card the formulas domain recorded, which is labelled Unconfirmed there.
   - The guide (*explaining-the-damage-formula*) writes `Pool × (1 + 0.1t) / t × 0.5` with **no inner truncation**.
   - The simulator reading is recorded here, but it is out of Beginner scope and was not vector-tested. Resolve it before
     implementing Clerics.
5. **Minor, no numeric effect.**
   - The avoidability-sim i18n key `avoidability-sim.avg125x` suggests a 1.25× roll. The code and the guide use **1.3**.
     The visible label just says "Average".
   - The character builder passes `weaponAttackSpeed: 6` for the Beginner window whatever the weapon. Speed affects only
     timing, never damage.

No disagreement was found between:

- the simulators and the guide's formulas for ACC, EVA, WDEF/MDEF/Magic, outgoing hit, incoming hit/damage, level gap,
  mastery, the defense curve or the clamp;
- the EXP calculator, the EXP guide table (Lv 1-30) and the `/formulas` EXP table;
- the monster pages' "Touch DMG" and the incoming-damage kernel (all six monsters);
- the item pages' "Weapon Multipliers" (swing/stab) and the engine's table `f`, for all five weapons;
- the guides' stated AP plans (Lv 30 Warrior 132/30/4/4 of 170; Lv 1 Beginner 13/4/4/4) and MeowDB's AP-plan code
  (`lM`, `jQ`);
- the formulas domain (`game/data/canonical/formulas/accuracy.json`, `derived_stats.json`, `hp_mp_gain.json`,
  `beginner.json`, extracted separately from the `/formulas` cards) and the executed oracle: Beginner ACC
  `floor(Common/2.5 + 5)`, EVA, Magic/WDEF/MDEF floors, Beginner HP `50 + 16(L-1)` / MP `5 + 12(L-1)`, outgoing and
  incoming hit, and incoming damage. The formulas domain writes the incoming-damage clamp as `trunc(clamp(x, 1, 5e7))`;
  the kernel does `clamp(trunc(x), 1, 5e7)`. These are equal for every real x, because the bounds are integers.

---

## 6. Gaps

- **Bare hands.** No MeowDB simulator models unarmed damage. `calculateCharacterStats` returns `beginnerDamage: null`,
  and `calculateDamage` needs a weapon type. The formulas domain confirms that the guides give no unarmed W.ATK or
  multiplier. The no-weapon vectors record only that `null`.
- **No Beginner class in the dmg-simulator.** The Beginner vectors use MeowDB's own character-builder modeling: the
  Warrior basic attack for Sword/Axe/Club, the Thief basic attack for the Razor.
- **Monster accuracy cases are degenerate.** All six Maple Island monsters have AVOID 0, so every monster-specific accuracy
  vector is 100%. The curve is covered only by synthetic grid inputs.
- **Defense on Maple Island.** None of the six monsters has P.DEF, so the physical defense curve is covered by synthetic
  inputs. Red Snail's M.DEF 30 is only exercised by `magic_defense_curve`.
- **Armor.** No armor is modeled. Beginner WDEF/MDEF are the derived `floor(STR/4)` / `floor(INT/4)` only. The starter
  clothes' DEF is not included.
- **dps-table.** No vectors (level-70 builds only).
- **Random roll distribution.** The simulators expose only MIN/MAX/avg and seeded Monte Carlo summaries. The per-roll
  kernels `J` and `er` are vectorized at fixed rolls (`physical_roll_explicit`). The sampler `eh` itself is not
  exported, so its action draw (0.6 swing) and per-hit crit draw are documented from source (§2.1), not vectorized.
- **Tutorial Jr. Sentinel in MeowDB's tools.** It is hidden from the dmg-simulator, mob-hit-sim and exp-calculator lists
  (`XB`). `mob_hit_danger` has no row for it. Its contact damage is covered by `avoid_and_incoming_damage_vs_monster`
  and `monster_touch_damage_display`.
- **Razor at Lv 1-4.** The Razor requires level 5 (item page), so it is generated only for levels 5, 8 and 10. The
  character builder itself does not enforce REQ LEV.

## Redeploys and refreshing

The cache (`tools/meowdb/.cache`) is git-ignored, and the chunk file names are content hashes. After a MeowDB redeploy, a
fresh clone cannot refetch these exact files; they 404. The chunk fetches run before the reference check, so the first
symptom is usually `404 https://meowdb.com/_next/static/chunks/...`. Treat that the same as the script's "page … no
longer references …" error. To refresh:

1. Run with `--refresh`.
2. Read the new `<script src>` list from each page and the new `.u` map from the webpack runtime.
3. Update `CHUNKS` and `LAZY_IN_RUNTIME`. If module 51894's header changed, update `FORMULAS_PATCH`.
4. Re-run, then diff the vectors. Any change in an `outputs` value means MeowDB changed a formula. Review it before you
   update the game.
