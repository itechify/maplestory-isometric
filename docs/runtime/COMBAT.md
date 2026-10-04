# Character rules and combat mathematics

This system owns the numbers behind fighting and growing: derived stats, AP, levels and EXP, HP/MP growth, the death
penalty, outgoing damage (player to monster), incoming damage (monster to player), attack timing and hit boxes. Every
rule is MeowDB MS Classic's published model. The values come from `game/data/canonical/formulas/*.json`; the values
MeowDB does not publish come from `game/data/misostory/combat.json`. Everything is pure GDScript in `scripts/core`:
no scene tree, no signals, and all randomness goes through a caller-supplied `RandomNumberGenerator`.

Primary source: [explaining the damage formula](https://meowdb.com/msclassic/guides/explaining-the-damage-formula),
plus `/formulas`, `/formulas/damage`, `/formulas/damage-taken`, `/formulas/attack-speed`, `/formulas/leveling` and
`/guides/weapon-reach` (transcribed in [`../canonical/formulas.md`](../canonical/formulas.md)). Parity oracles are
described in [`../canonical/oracles.md`](../canonical/oracles.md).

## Modules

| Class (file) | Role |
|---|---|
| `CombatFormula` (`scripts/core/combat/combat_formula.gd`) | every pipeline stage as a static function, the `resolve_*` orchestrators, incoming damage, attack timing, reactions |
| `CombatRules` (`combat/combat_rules.gd`) | typed snapshot of the canonical constants and the `combat.json` adaptations, cached per `ContentDB`; missing fields go to `errors` and `push_error`, never to a fallback number |
| `WeaponProfile` (`combat/weapon_profile.gd`) | one weapon (or bare hands): stat family, action multipliers, ordinary-attack odds, ranged flag, speed tier, hit boxes |
| `PhysicalAttack` (`combat/physical_attack.gd`) | every input of the physical raw roll for one action (after branch resolution) |
| `PlayerCombatStats` / `MonsterCombatStats` | the attacker and defender records the pipeline reads (`from_character`, `from_id`) |
| `DamageResult` / `IncomingResult` | outgoing and incoming records with the value after every stage (`to_dict()`, `stages()` for the debug overlay) |
| `CombatReach` (`combat/combat_reach.gd`) | box mirroring, strict overlap, monster touch box, target order, isometric depth |
| `StatCalculator` (`scripts/core/character/stat_calculator.gd`) | totals and derived stats, max HP/MP, the stat-window damage range, speed/jump, HP/MP limits |
| `Progression` (`scripts/core/character/progression.gd`) | EXP table, level-ups, AP/SP, HP/MP growth, level-up heal, AP allocation, death penalty, the EXP calculator |

## Data flow

```
CharacterState (base values) --+-- Equipment.total_bonuses(db) + effects[].bonuses
                               v
StatCalculator.snapshot / combat_stats --> PlayerCombatStats (+ WeaponProfile of the equipped weapon)
                                                    |
monsters/<id>.json --> MonsterCombatStats ----------+--> CombatFormula.resolve_physical_hit(...) --> DamageResult
                                                    +--> CombatFormula.resolve_monster_touch(...) --> IncomingResult
DamageResult.final -> monster HP; .knockback -> stagger      IncomingResult.final -> StatCalculator.change_hp
monster death -> Progression.gain_exp(c, monster.exp, db)    HP 0 -> Progression.is_dead / apply_death_penalty
```

Typical player attack (actor code, not in this module):

```gdscript
var stats := PlayerCombatStats.from_character(Game.character, Data.db)
var pick := CombatFormula.choose_ordinary_action(stats.weapon, Game.rng)       # {"action", "presentation"}
var ms := stats.weapon.attack_duration_ms(pick["action"], Data.db)             # attack lockout
var box := CombatReach.attack_box_px(stats.weapon, pick["presentation"], facing_right, stats.level)
# ...overlap box (WorldScale.actor) with CombatReach.monster_touch_box_px(m); CombatReach.pick_targets(..., 1)
var hit := CombatFormula.resolve_physical_hit(stats, target_stats, pick["action"], Game.rng, Data.db,
		{"presentation": pick["presentation"]})
```

Monster contact (skip it while the player is invincible):

```gdscript
var res := CombatFormula.resolve_monster_touch(monster_stats, PlayerCombatStats.from_character(c, Data.db), Game.rng, Data.db)
StatCalculator.change_hp(c, -res.final, Data.db)                                # 0 on a miss or guard
if res.knockback:
	player.apply_knockback_from_point(monster_pos, 1.0, res.invincibility_s)    # pass the duration explicitly
else:
	player.set_invulnerable(res.invincibility_s)                                 # a miss or guard: 1.5 s, no push
```

`invincibility_s` is the canonical 1.5 s (`accuracy.json after_hit`), also after a miss or a guard. Always pass it:
the player controller's own default (`movement.json default_invulnerability_s`, 2.0 s) is a fallback for a
`combat.json` key that this system deliberately does not define, because the duration is canonical. The horizontal
push speed belongs to the player controller (`data/misostory/movement.json knockback_horizontal_speed_mps`);
`CombatFormula.player_knockback(db)` reports it together with the canonical vertical model. For monsters use
`monster_staggers` (`DamageResult.knockback`), `monster_stagger_s` and `monster_knockback_distance_px`.

## Outgoing pipeline (MeowDB order)

| # | Stage | Function | Rule |
|---|---|---|---|
| 1 | hit check | `calculate_accuracy`, `roll_hit` (`draw_hit_spread` + `hit_succeeds`), `roll_darkness_lands` | `L = max(0, MobLv - PlayerLv)`, `A = ACC x 100 / (10L + 255)`, `D = A - EVA`, `f = 0.15 + 0.2 / (1 + exp(D/12))`, hit when `A x R >= EVA` with `R = uniform(1-f, 1+f)`; automatic hit when `D >= 25 + L(0.5 PlayerLv + 15)`; EVA 0 always hits, ACC 0 never. Darkness is a separate check after the hit. |
| 2 | raw roll | `physical_attack`, `raw_physical_roll`, `roll_physical_damage`, `calculate_physical_range` | `Raw = S x WATK x (B + (Q x WeaponMult + Secondary)/StatDiv + AP/APDiv)` with **two independent draws** `B = uniform(0.8, 1.0)` and `Q = uniform(Primary x M, Primary)`; MIN/MAX are the corners. Magic: `calculate_magic_range`, `roll_magic_damage` (one uniform draw). |
| 3 | defense | `effective_defense`, `apply_defense`, `apply_defense_expected` | `EffDEF = max(0, Flat + trunc((1 + Pct/100) x Base))`, `Raw x 100 / (EffDEF + 100)`; a bypass proc returns Raw; WDEF for physical, MDEF for magic. |
| 4 | element | `element_relation`, `element_multiplier`, `composition_multiplier`, `apply_element` | immune 0 / resistant 0.75 / neutral 1 / weak 1.25; composition `0.25 x (code1 + code2)` (the 7 results 0-1.5); other results 1.0. |
| 5 | level gap | `level_scale`, `apply_level_scaling` | gap <= 0: 1; 1-9: `1/(1 + gap^2 x 0.005)`; >= 10: `1/(1 + gap x 0.05)`. |
| 6 | critical | `roll_critical`, `apply_critical`, `expected_with_critical` | rate c and damage d are independent inputs; base c 0.05, d 0.20; `Normal x (1 + d)`. |
| 7 | skill modifiers | `apply_skill_modifiers` | a multiplier supplied by the skill system (1.0 for basic attacks). |
| 8 | final clamp | `finalize_damage` | `trunc(clamp(v, 1, 99999))`. Values stay fractional until here. |

`resolve_physical_hit`, `resolve_magic_hit` and `resolve_fixed_damage` (Three Snails) run the stages and fill a
`DamageResult`. The result holds `missed`/`miss_reason`, `hit_chance`, `hit_roll`, the two unit draws, `raw`,
`after_defense`, `after_element`, `after_level`, `critical`, `after_critical`, `after_skill`, `final` and
`knockback`. `damage_window` reproduces MeowDB's per-hit `{min, max, avg}` against a target, or the stat window with
no target. `expected_damage_with_crit` gives the simulator's crit expectation.

RNG draw order per hit: the hit spread R (only when the outcome isn't already decided), Darkness (only with
darkness), B, Q, the bypass draw (only with a bypass rate), then the crit draw (always one). This matches MeowDB's
sampler (action, then base, stat, crit) whenever no hit roll is needed. Every Maple Island monster has AVOID 0, so
none is needed there.

### Weapons

- **Families → stats** (`damage.json weapon_families`): Sword/Axe/Blunt/Spear/Polearm and a Wand/Staff whack use
  STR/DEX; Bow/Crossbow use DEX/STR; Dagger/Claw use LUK/(STR + DEX). `WeaponProfile.SUBTYPES` only joins MeowDB item
  subtypes to the table row keys.
- **Action multipliers** come from `weapon_action_multipliers` (swing/stab/shoot/mixed; `null` = "Not used"). They are
  cross-checked in tests against every weapon item page.
- **Ordinary attack** (`choose_ordinary_action`): the damage action comes from `ordinary_action_odds` (60% swing /
  40% stab for melee; bow swings, crossbow 50/50 and claw stabs at close range; wand/staff swing; bare hands stab).
  The presentation is then picked with equal odds among that action's basic presentations, which gives 20% each
  for the five standing presentations. Ranged weapons shoot unless `close_range`.
- **Special branches** come from `damage.json special_branches` and are picked by `default_branch`: crouched attack
  (`proneStab`, 1.0 / 300 / 150, B 0.2-0.3), ranged projectile (2.5 / 100 / 50), close-range ranged swing (1.0 / 300
  / 150) and stab (1.0 / 300 / 50). Lucky Seven and Drain are selected explicitly by key.
- **Mastery**: `M = (clamp(MasteryLevel, 0, 10)/10 + 0.1) x 0.8`. A Beginner has mastery 0, so M = 0.08 (the published
  `no_mastery_factor`). `StatCalculator.mastery_level` is the plug-in point for job mastery skills.
- **Stat window** (`StatCalculator` `damage_min/max/avg`): the lowest MIN and highest MAX over the ordinary actions
  (MeowDB's split-action rule). The average is 60/40-weighted and rounded to 0.1, as MeowDB does.

### Timing and reach

- `CombatFormula.attack_duration_ms(tier, base_action, db)` / `WeaponProfile.attack_duration_ms(action, db)` use
  MeowDB's published per-tier ladder (`attack_speed.json speed_tiers`: ordinary, spear/polearm stab, crossbow) where
  one exists. Otherwise (crouched attack, rush) they use the timing model `30 x ceil(trunc(base x (10 + tier)/16)/30)`.
  The whole-total model matches the ladder except the documented crossbow tier 7 mismatch, so the ladder is
  authoritative. Boosters: pass a `tier_offset`.
- Hit boxes are px, `[left, top, right, bottom]` facing left, y down, feet origin (`attack_styles.json`). The set is
  taken from `beginner_weapons`, else from the set whose boxes equal the item page's basic attacks, else from the
  subtype family's primary set. The level-100 band replaces some boxes from level 100. Overlap is strict
  (`CombatReach.boxes_overlap`). Basic attacks pick the nearest monster first; a tie goes to the monster that
  appeared first (`CombatReach.pick_targets`). Convert px with `WorldScale.actor()`.

## Incoming (monster → player)

`incoming_hit`: `G = max(0, PlayerLv - MobLv)`, `A = MobACC x 100 / (5(G + 51))`,
`E = EVA / (1 + EVA/80) / (1 + G/40)`, the spread test, the far-miss clamp `clamp(0.03 exp((A-E)/18), 0.02, 0.03)`
and the independent 8% minimum-hit rescue. A monster with ACC 0 never hits. Then come the guard (Shield
`max(0.05, W/(W + 500))`, or a larger guard supplied by skills; regular physical attacks only), the roll
`1.1 + 0.4U`, `Taken = Raw x (1 - DEF/(DEF + 5(PlayerLv + 40) + 1.2 Raw))`, elemental resistance (elemental attacks
only; touch has no element) and `trunc(clamp(Taken, 1, 5e7))`. Magic attacks skip evasion and guards and use MDEF.
A monster whose attack is 0 deals no damage (`no_attack`). This follows oracles.md discrepancy 2, which chose 0
over the kernel's clamp to 1. `incoming_damage_range` exposes MeowDB's kernel, clamp included, for parity.

## Character stats and progression

- Totals = base + `Equipment.total_bonuses(db)` + each effect's `"bonuses"` dictionary (`Equipment.BONUS_KEYS` plus
  `StatCalculator.EXTRA_BONUS_KEYS`: `attack_power`, `crit_rate_pct`, `crit_damage_pct`, `max_hp_pct`, `max_mp_pct`,
  `wdef_pct`, `mdef_pct`, `darkness_pct`, `shield_wdef`).
- ACC per job comes from `accuracy.json derived_accuracy.by_job`. A Beginner gets `floor(Common/2.5 + 5)` with
  `Common = 1.2 DEX + 2 Lv + 0.6 LUK`; the Magician row uses INT. EVA is `floor(LUK/3) + floor(DEX/6) + 5`, Magic
  `floor(INT/2)`, WDEF `floor(STR/4)` and MDEF `floor(INT/4)`; gear and effect lines are added afterward.
  `StatCalculator.JOBS` maps a job slug to its class row and advancement count: this is where jobs plug in.
- Max HP/MP: `trunc(base_max x (1 + pct/100)) + equipment`. Base max HP/MP grows by `hp_mp_gain.json per_class`
  (Beginner +16/+12, no variance); `Progression.base_max_hp_mp` / `class_base_max_hp_mp` give the published
  `JobHP`/`JobMP` totals. Speed and Jump are base 100 + bonuses, capped at 140 / 120.
- Level-ups (`Progression.gain_exp` / `apply_level_up`) grant +5 AP and, for a Beginner, +1 SP at levels 2-10, plus
  the class HP/MP growth, then a full heal (adaptation). One award can raise several levels. The cap is 100 (EXP
  stops there).
- `allocate_ap`: STR/DEX/INT/LUK only (`beginner.json ap.allocatable_stats`; AP into HP/MP is the documented
  discrepancy, decided "no").
- `apply_death_penalty`: `floor(EXP_to_next x (5 + 20/LUK)/100)` with **base** LUK clamped to 4..999. EXP never goes
  below 0 and a death never removes a level. The game creates characters through `CharacterFactory` (saves system),
  where the 9 creation AP are placed on the creation screen. `Progression.init_new_character` is a rules-level helper
  for tests and tools: the same level-1 Beginner (4/4/4/4, 50/5) with the 9 creation AP left unspent.
- `exp_remaining` / `total_exp_at` / `cumulative_exp_through` / `kills_needed` reproduce MeowDB's EXP calculator.

## Canonical sources used

`formulas/damage.json` (physical, magic, defense, elements, level_gap, critical, final_clamp, special branches,
odds), `formulas/accuracy.json` (derived ACC, EVA, outgoing/incoming hit, darkness, guards, incoming damage,
after_hit), `formulas/derived_stats.json`, `formulas/attack_speed.json`, `formulas/attack_styles.json`,
`formulas/movement.json` (caps, knockback airtime), `formulas/exp_table.json`, `formulas/beginner.json`,
`formulas/hp_mp_gain.json`, `formulas/death.json`, `monsters/*.json` (level, AVOID, P/M.DEF, ACC, P/M.DMG, KB,
element, touch zone, hit animation), and `items/*.json` (W.ATK, speed, multipliers and basic-attack boxes,
cross-checked).

**Formula constants in code.** Where MeowDB publishes a constant only inside a formula string, the function writes it
exactly as published. These are the mastery `/10 + 0.1` and `x 0.8`, the defense curve's `100`, Shield Guard's `0.05`
and `500`, the timing `(10 + tier)/16`, and the level-100 hit-zone band. `tests/unit/test_combat_formula_pins.gd`
fails if the published text changes. Every constant that exists as a data field is read from data.

## Adaptations (`game/data/misostory/combat.json`, all `verified: false`)

| Section | Value | Why |
|---|---|---|
| `bare_hands` | weapon W.ATK 0, multiplier 1.0, STR/DEX, tier 6, equal Punch 1/2 odds | MeowDB has no unarmed model. The documented formula with W.ATK 0 gives 1 damage after the final clamp. `weapon_watk` is the empty slot's line in the Total Weapon Attack pool (`StatCalculator.compute` adds it only when no weapon is equipped), so other W.ATK lines (gloves) still count. |
| `post_hit_invincibility` | `override_s: null` → canonical 1.5 s, also after a miss or guard | the canonical value is kept; this is the slot for an isometric adjustment |
| `player_knockback` | push on landed hits only (`on_landed_hit`, `on_miss_or_guard`) | only the vertical airtime is published; the horizontal speed has one owner, `movement.json knockback_horizontal_speed_mps` (player controller), and is deliberately not repeated here |
| `monster_knockback` | stagger when `damage >= KB`; stagger time = the monster's `hit1` clip (600 ms), fallback 0.6 s; 20 px push | the KB stat is canonical (all Maple Island monsters: KB 1); distance and duration are not |
| `fixed_damage_skills.0001000` | Three Snails: hit check yes, defense/level gap/crit no | MeowDB only says stats, weapon and defense don't scale it |
| `level_up` | full heal; excess EXP carries; several levels per award; EXP discarded at the cap | MeowDB implies a heal but not its amount; overflow is undocumented |
| `beginner_sp_after_level_10` | 0 | undocumented |
| `ap_allocation` | AP never goes into HP/MP | follows the canonical discrepancy decision |
| `isometric_reach` | attack boxes 60 px deep; touch zones as deep as they are wide | MeowDB is 2D |

## Parity with MeowDB

All 818 vectors in `game/tests/data/parity_vectors.json` are replayed (`test_parity_*.gd`), and
`test_parity_coverage.gd` fails if a mechanic in the file has no test. Integers (damage MIN/MAX, display strings,
derived stats, HP/MP, EXP, kills, incoming raw/taken) match exactly. Floats (hit and dodge rates, ACC/AVOID
milestones, untruncated damage, level scale, crit expectation) match to 1e-9 relative. Averages match through
MeowDB's own 0.1 rounding. To get there, the arithmetic order follows MeowDB's kernels (`J`, `er`, `eP`).

No vector disagrees with the code. Two oracle outputs are deliberately not game behaviour:

1. **No weapon.** MeowDB returns `beginnerDamage: null`; MisoStory shows and deals 1-1 (bare-hands adaptation). The
   test asserts the adaptation.
2. **Zero attack.** The `incomingDamage` kernel clamps a 0 attack to 1. The game deals 0, as chosen in oracles.md,
   and the mob-hit-sim does the same. Both are asserted.

The guide's worked example passes: the Lv30 Warrior with a Gladius has a 60-172 window (Power Strike 157-449), ACC 49,
EVA 11, Magic 2, WDEF 33, MDEF 1 and 1104/503 HP/MP. So do the Beginner's guide Snail hit counts (Sword 4/3/3, Club
3/3/2).

## Testing

```bash
ISOLATE=<name> bash scripts/test.sh test_combat test_stats test_progression test_parity   # this system (118 tests)
ISOLATE=<name> bash scripts/test.sh                                                        # everything
```

| File | Covers |
|---|---|
| `test_combat_formula.gd` | each outgoing stage; Beginner/no mastery; representative weapons and swing/stab; special branches; seeded rolls; a statistical check that the two-draw distribution is centre-heavy (it fails for a single shared draw); defense; magic; elements; lower/same/higher level; misses and Darkness; criticals; clamp; bare hands; Three Snails; full pipeline |
| `test_combat_incoming.gd` | published examples, the 8% rescue and far-miss branch, observed hit rate, roll and curve, guards, magic path, resistance, invincibility and knockback, determinism |
| `test_combat_weapons.gd` | every weapon item vs its page (multipliers, boxes, cycle times), families, 60/40 and 20% presentation odds, other weapon rules, geometry, target order, the timing ladder |
| `test_combat_adaptations.gd` | every `combat.json` section has a reason and `verified: false`; the stagger, invincibility and knockback rules |
| `test_combat_formula_pins.gd` | published formula strings for every constant written in code |
| `test_stats_calculator.gd` | totals with gear and effects (via a fake `Equipment`), derived stats per job, HP/MP with gear and %, limits, caps, stat window, the bare-hands W.ATK line in the pool (patched private `ContentDB`), Shield Guard WDEF from a scrolled shield's own stats |
| `test_combat_kill_and_exp.gd` | end to end on canonical data: seeded basic attacks kill a Snail in the Beginner guide's 3-4 hits, bare hands need one punch per HP, 8 Snails level a Beginner at the published 15 EXP, Orange Mushroom contact kills a level-1 Beginner in 2-3 touches, then the death EXP penalty |
| `test_progression_exp.gd` | thresholds, single/multiple level-ups, the cap, AP/SP, HP/MP growth to level 11, allocation, death penalty |
| `test_parity_*.gd` | the MeowDB oracle vectors (`test_parity_base.gd` holds the shared loader) |

## Known limits

- Job SP after an advancement (1 + 3 per level), 2nd/3rd job slugs, job mastery skills, boosters and Element
  Amplification are not in the canonical JSON or not needed by a Beginner. The hooks are `StatCalculator.JOBS`,
  `StatCalculator.mastery_level`, `tier_offset` and `skill_multiplier`.
- When a flat WDEF effect and a percent WDEF effect are both active, they are summed before the percent is applied.
  MeowDB's builder adds buff flat WDEF after the percent. No Beginner effect does either.
- The danger tiers of the mob-hit-sim are UI and are not implemented; only its damage numbers are tested.
- `WeaponProfile` takes a weapon's basic presentations from its item page (`weapon.basic_attacks`); every weapon in
  the data has them. For a future item without that list it falls back to every non-Final-Attack presentation of the
  hit-zone set, which is too wide for a bow or crossbow (`attack_styles.json weapon_groups` lists the real basics).
- A shield's Shield Guard WDEF uses the piece's own per-instance `stats` when it has them (a scroll result), the same
  rule as `Equipment.total_bonuses`. No Maple Island shield exists in the canonical data yet.
