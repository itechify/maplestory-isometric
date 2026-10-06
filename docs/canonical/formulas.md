# Canonical data: formulas, progression and the Beginner class

Authority: **MeowDB MS Classic** (https://meowdb.com/msclassic), the "MapleStory Classic World" (COT2) database. No value here comes from GMS v8/v62, private servers or other wikis. Where MeowDB is silent, the field is `null` and the gap is listed; no `external` values were needed.

- Extractor: `tools/meowdb/extract_formulas.mjs` (run `node tools/meowdb/extract_formulas.mjs`; cache-first; re-running reproduces the JSON byte-for-byte; verified).
- Output: `game/data/canonical/formulas/*.json`, one entity per file (13 files, listed below).
- The extractor asserts every formula string against the page text (whitespace-normalised) and cross-checks every table against the second MeowDB page that publishes it. If a `--refresh` brings different wording or numbers, the run fails and lists each mismatch instead of writing stale data.
- The simulator golden vectors (`tools/meowdb/oracle_vectors.mjs`) live in `game/tests/data/parity_vectors.json`, outside the shipped content, because only tests read them.

## 1. Pages read

| URL | retrieved_at | Used for |
|---|---|---|
| https://meowdb.com/msclassic/formulas | 2026-10-04T09:57:48.010Z | Accuracy tab: derived stats, hit roll, darkness |
| https://meowdb.com/msclassic/formulas/targeting | 2026-10-04T10:04:38.766Z | attack shapes, ranges, weapon reach table, overlap, target order, terrain, cast position |
| https://meowdb.com/msclassic/formulas/damage | 2026-10-04T10:04:41.289Z | physical/magic damage, multipliers, swing/stab odds, special branches, defense, element, level gap, crit, clamp, other damage |
| https://meowdb.com/msclassic/formulas/damage-taken | 2026-10-04T10:04:42.496Z | monster hit chance, guards, damage taken, resist, invincibility, knockback, fall damage |
| https://meowdb.com/msclassic/formulas/attack-speed | 2026-10-04T10:04:43.693Z | base animation times, boosters, timing model, movement speed, pickup box |
| https://meowdb.com/msclassic/formulas/leveling | 2026-10-04T10:04:44.928Z | EXP formula + table 1-99, party EXP, death EXP loss, HP/MP, AP/SP, citizenship, crafting |
| https://meowdb.com/msclassic/formulas/spawns | 2026-10-04T10:04:46.189Z | respawn tick, capacity, kills/EXP per hour model |
| https://meowdb.com/msclassic/formulas/pets | 2026-10-04T10:04:47.357Z | drop-ownership sentence only (pets are out of scope) |
| https://meowdb.com/msclassic/guides/explaining-the-damage-formula | 2026-10-04T10:04:40.014Z | "Damage Formula" tab: methodology, pipeline order, worked example, stat roles |
| https://meowdb.com/msclassic/guides/attack-speed-and-animation-times | 2026-10-04T10:05:46.916Z | "Atk Speed" tab: speed tiers and ladder |
| https://meowdb.com/msclassic/guides/weapon-reach | 2026-10-04T10:06:08.439Z | "Attack Styles" tab: hit boxes per weapon and presentation |
| https://meowdb.com/msclassic/guides/hp-mp-gain-explained | 2026-10-04T10:06:12.068Z | "HP/MP Gain" tab |
| https://meowdb.com/msclassic/guides/exp-table-level-1-to-100 | 2026-10-04T10:06:26.526Z | "EXP Table" tab (cross-check of the EXP table) |
| https://meowdb.com/msclassic/guides/spawn-engine-respawn-and-map-capacity | 2026-10-04T10:06:30.200Z | "Spawn Rate" tab |
| https://meowdb.com/msclassic/npc-shops/item-efficiency | 2026-10-04T10:05:33.306Z | "Shop Item Efficiency" tab (only HP/MP per meso; no formula beyond restore / price) |
| https://meowdb.com/msclassic/npc-shops/item-efficiency/beginner | 2026-10-04T10:08:28.797Z | "no class lock" Beginner category, starter weapon trio |
| https://meowdb.com/msclassic/guides | 2026-10-04T09:57:51.040Z | index of mechanics guides |
| https://meowdb.com/msclassic/guides/beginners-guide-first-steps-in-maple-world | 2026-10-04T10:06:38.610Z | creation AP, SP, skills, starter weapons, Snail hit table, chairs, potions, taxi discount |
| https://meowdb.com/msclassic/guides/speed-jump-and-movement | 2026-10-04T10:09:32.829Z | Speed/Jump, walk/climb speed, jump heights |
| https://meowdb.com/msclassic/guides/maplestory-classic-glossary | 2026-10-04T10:09:34.025Z | KB, mob rate, party loot, level-up definitions (discrepancy evidence) |
| https://meowdb.com/msclassic/guides/what-is-maplestory-classic-worlds | 2026-10-04T10:09:38.993Z | level cap 100, start at level 1, AP placed by hand |
| https://meowdb.com/msclassic/guides/controls-and-settings | 2026-10-04T10:09:35.574Z | read; nothing gameplay-numeric |
| https://meowdb.com/msclassic/guides/attacks-you-can-use-mid-jump | 2026-10-04T10:09:37.466Z | read; no Beginner content |
| https://meowdb.com/msclassic/classes | 2026-10-04T09:57:46.530Z | class tree, job levels |
| https://meowdb.com/msclassic/classes/beginner | 2026-10-04T10:06:42.205Z | Beginner class page (main source of beginner.json) |
| https://meowdb.com/msclassic/skills | 2026-10-04T09:57:49.521Z | skill book index (Beginner: 3 skills) |
| https://meowdb.com/msclassic/skills/beginner/three-snails | 2026-10-04T10:08:40.464Z | skill 0001000 |
| https://meowdb.com/msclassic/skills/beginner/recovery | 2026-10-04T10:08:44.073Z | skill 0001001 |
| https://meowdb.com/msclassic/skills/beginner/nimble-feet | 2026-10-04T10:08:41.660Z | skill 0001002 |
| https://meowdb.com/msclassic/exp-calculator | 2026-10-04T09:57:52.584Z | EXP coverage statement, parity values |
| https://meowdb.com/msclassic/dmg-simulator | 2026-10-04T09:57:54.049Z | searched for unarmed/Beginner handling (none) |
| https://meowdb.com/msclassic/accuracy-sim, /avoidability-sim, /mob-hit-sim | 2026-10-04 | read; same formulas as the tabs |
| https://meowdb.com/msclassic/character-builder | 2026-10-04T10:04:36.433Z | loads the hit-zone JSON chunk and the stat/equip module |
| https://meowdb.com/msclassic/quest-tracker/1013, /1014, /1016, /1017, /1018 | 2026-10-04 | Rain's Maple Quiz dialogue (crouch + jump to drop down / up to climb, equip rule, regen, job level, 5 AP per level) |
| https://meowdb.com/msclassic/npcs/3 | 2026-10-04T10:04:50.974Z | Roger idle chatter (inventory full; "You'll die when your HP reaches 0") |
| https://meowdb.com/msclassic/maps/000000040 | 2026-10-04T09:56:43.779Z | spawn display (mobTime 0, "Wave (~7.5s)"), mob-rate text, Respawn Map |
| https://meowdb.com/msclassic/monsters/2 | 2026-10-04T09:57:41.529Z | Snail: HP 45, Touch DMG 3-4 / Base 3, "loot drops as soon as the mob dies" |
| https://meowdb.com/msclassic/item-db/541, /576, /585, /558, /271 | 2026-10-04 | Sword, Hand Axe, Wooden Club, Razor (speed, cycle, multipliers, iconKey, per-attack reach, "each with equal odds" sentence); Orange Potion id |
| https://meowdb.com/msclassic/item-db/522, /525 | 2026-10-04T10:17:31.306Z / 10:47:05.333Z | chairs: "restore an additional 30 HP every 10 seconds", HP Recovery +30, Sky-blue Wooden Chair Required Level 5 (pages cached by the items domain; read from cache) |
| https://meowdb.com/msclassic/api/items/{541,576,585,558,522,525}?locale=en&preview=1 | 2026-10-04 | cross-check of levelReq / watk / attackSpeed (weapons) and hpRecoverBonus / levelReq (chairs); read from cache |
| https://meowdb.com/msclassic/api/drops?monsterId=2, 3, 5 | 2026-10-04 | Snail Shell 348, Blue Snail Shell 349, Red Snail Shell 351 (Three Snails costs) |
| https://meowdb.com/_next/static/chunks/2347-d8fa2c57e839440e.js | 2026-10-04T10:04:59.330Z | hit-zone JSON (schemaVersion 1), ranged band spec, Three Snails skill area |
| https://meowdb.com/_next/static/chunks/5253-8d210be12f2a3111.js | 2026-10-04T10:05:18.698Z | the /formulas calculators' code (used as the rounding oracle) |
| https://meowdb.com/_next/static/chunks/4068-26c6ed6efe1adbc7.js | 2026-10-04T10:05:15.057Z | character-builder stat module (HP/MP constants, Beginner equip rule) |

Exact `retrieved_at` per field is in each JSON file's `source` / `field_sources`.

## 2. Output files and fields

All files: `id`, `name`, `source {authority, url, retrieved_at}`, `field_sources` (dotted field path -> `{url, retrieved_at}`; JS chunks also carry `loaded_by`), and where relevant `status`, `gaps`, `discrepancies`, `parity_examples`, `calculator_code` (a short verbatim excerpt of MeowDB's own calculator code, asserted to exist in the chunk).

**Status labels.** MeowDB tags cards. `status` reproduces the tag: `Current`, `Historical`, `MeowDB's Model` (MeowDB's own model, not a confirmed game constant), `Unconfirmed`, `Confirmed` (MeowDB says COT2-measured), or `Published formula` (no tag). Spawn timing, death EXP loss, knockback airtime, the DPS/30 ms timing rule and defensive skills are **MeowDB's Model**.

| File | Contents (key fields; units) |
|---|---|
| `exp_table.json` | `levels[]` 1-99: `exp_to_next` (EXP from level L at 0 EXP to L+1, **not cumulative**), `total_from_lv1` (cumulative EXP to reach L+1), `status` current (1-49) / historical (50-99); `formula_segments`; `level_cap` 100; `party_bonus.bonus_exp_pct_by_party_size`; `party_inactivity_cutoff_s` 15 |
| `beginner.json` | starting level 1; `starting_stats` 4/4/4/4; `creation_ap` 9; `ap` (25 + 5 x (L-1) total, 5 per level); `sp` (9 total, 1 per level 2-10); `hp_mp` (50/5 base, +16/+12 per level, no variance, table L1-10); `max_level`; `job_advancement` (Lv 10, no stat requirement); `equipment_restrictions`; `starter_weapons` (MeowDB item ids); `skills[]` (ids 0001000/0001001/0001002, per-level parsed effects); `basic_attack` incl. `bare_hands`; `death_exp_penalty`; `beginner_perks` (taxi 90% off) |
| `damage.json` | `pipeline_order`; `physical` (formulas, `base_roll` 0.8-1.0, `ordinary_divisors` StatDiv 100 / APDiv 50, `mastery` incl. no-mastery 0.08, `weapon_families` primary/secondary, `weapon_action_multipliers` swing/stab/shoot/mixed with `null` = "-"/"Not used", `ordinary_action_odds` swing_pct/stab_pct, `special_branches`, `stat_window_range`); `magic`; `skill_bonuses`; `defense`; `elements`; `level_gap`; `critical` (c 0.05, d 0.20); `final_clamp` 1..99999 then trunc; `other_mechanics` (verbatim lines); `bare_hands` (all null) |
| `accuracy.json` | `derived_accuracy.by_job` (divisor, constant); `avoidability`; `outgoing_hit` (+ `automatic_hit`, calculator edge cases); `darkness`; `incoming_hit` (+8% rescue); `guards`; `incoming_damage` (roll 1.1-1.5, clamp 1..50,000,000 then trunc, `touch_attack_ratio` 100); `elemental_resistance`; `after_hit.post_hit_invincibility_s` 1.5 |
| `derived_stats.json` | Magic = floor(INT/2), WDEF = floor(STR/4), MDEF = floor(INT/4); Total Weapon Attack pool rule; Attack Power rule; MagicTotal; `stat_roles` (STR/DEX/INT/LUK role tables) |
| `attack_speed.json` | `timing_formula`; `timing_tier_clamp` [0,10]; `display_rounding_ms` 30; `base_action_times_ms` (swing 800, stab 800, spear/polearm stab 750, bow 800, crossbow 820, crouched 700, rush 400); `speed_tiers[]` 0-12 (label, ordinary_attack_ms, attacks_per_minute, spear_stab_ms, crossbow_ms); `weapon_type_speed_ranges`; `boosters`; `whole_total_scaling_check`; `beginner_weapons` (tier, cycle ms); `three_snails` |
| `attack_styles.json` | `hitzone_sets` (box_px [left, top, right, bottom], px, facing left, y down; far/near/up/down/height); `weapon_groups` (14 rows of the targeting reach table mapped to sets, basic / Final Attack / not-used actions); `weapon_subtype_to_hitzone_family`; `ordinary_action_selection` (60/40 rule, `per_standing_presentation_pct` 20 from the item pages' "each with equal odds", crouched attack not in the pool); `overlap_rule` (strict); `target_selection_order`; `ranged_search_bands`; `attack_ranges_px`; `terrain_check`; `cast_positions`; `beginner_weapons` (item id -> set); `bare_hands`; `three_snails_targeting`; `svg_cross_check`; `item_page_reach_cross_check` (24 per-attack reach values on the four weapon pages = hit-zone boxes) |
| `spawn_rate.json` | `global_respawn_tick_s` 7.56; `wave_point_cooldown_s` 5; timed cooldown = mobTime; `respawn_rules`; `map_page_display` (what mobTime 0 / "Wave (~7.5s)" means); `capacity` (player scalar 75%..100%); `spawns_per_hour`; `map_spawn_rate_multiplier` (not applied) |
| `hp_mp_gain.json` | `per_class` (+HP/+MP per level and per advancement), formulas, base 50/5, `random_range` null (zero variance), `ap_into_hp_mp` null (gap; glossary disagrees, see Discrepancies), job advancement does not heal; `late_advancement_caveat` (only a level-11 Warrior catch-up is measured; later levels and other classes are untested) |
| `movement.json` | walk = 125 x (Speed + 20) / 100 px/s; climb = Speed + 20 px/s; caps Speed 140 / Jump 120; base 100/100; `jump_height_px_by_jump`; `pickup_box_px`; `controls_statements` (crouch + jump drops to a lower platform; up grabs a ladder/rope or enters a portal); `knockback_airtime` (270 px/s up, gravity 2000 px/s^2); `monster_knockback` (definition only); `fall_damage` (incl. counter-reset rule) |
| `recovery.json` | natural regen (qualitative only, values null); chairs: `additional_hp_per_tick` 30 every 10 s **on top of** the undocumented base resting regen (`stacks_with_natural_regen`), `level_req` 0 (Green Relaxer) / 5 (Sky-blue Wooden Chair); consumable examples with item ids; level-up heal implied |
| `loot_rules.json` | loot drops on death; player pickup box; inventory-full rule; ownership (exists, duration unknown); drop rates / meso amounts / expiry: not documented |
| `death.json` | `death_trigger` (dies when HP reaches 0); `exp_penalty` (MeowDB's Model formula; `luk_basis` = own base LUK incl. the starting 4, never only the placed AP; no town/Beginner exception documented); `respawn_location` = map's "Respawn Map" |

Unit conversions (the raw page string is always kept next to the number): skill cooldowns "2 min" / "3 min" are stored as `cooldown_s` 120 / 180; percentages are stored as `*_pct` numbers (60 for "60%"); "1.5 s" is `post_hit_invincibility_s` 1.5. In `attack_styles.json` `weapon_groups`, `unlabelled_actions` lists presentations that exist in the shared hit-zone set but that MeowDB does not label for that weapon (only the bow has some); they are not usable basic attacks.

Ids are MeowDB's: skills `0001000` Three Snails, `0001001` Recovery, `0001002` Nimble Feet; items `541` Sword, `576` Hand Axe, `585` Wooden Club, `558` Razor, `348/349/351` snail shells, `522` The Green Relaxer, `525` Sky-blue Wooden Chair, `238` Meat, `270` Red Potion, `271` Orange Potion, `240` Lemon, `273` Blue Potion; monster `2` Snail; map `000000040` Snail Hunting Ground I. The hit-zone JSON's `weapons` map is keyed by MeowDB's `iconKey` (the client code, e.g. `1302000` for item 541); those keys are **not** MeowDB item ids and are not exported.

## 3. Verbatim transcription

Blocks below are generated from the cached page text (interactive "Try values" widgets and link rows removed). Section names are MeowDB's. Tables are flattened one cell per line, and sentences that contain an inline link appear split at the link (for example "branch" / "." / "Booster" in 3.9); the words are verbatim, only the line breaks are artefacts.

### 3.1 /formulas (tab "Accuracy") - https://meowdb.com/msclassic/formulas

Step 1 "Your stats":
```text
Accuracy, avoid, magic and defense all come from total stats: base AP plus equipment and buffs.
Stats from STR, DEX, INT, and LUK
Common = 1.2 × DEX + 2 × Level + 0.6 × LUK
Beginner ACC = floor(Common / 2.5 + 5)
Warrior ACC = floor(Common / 2.5 + 10)
Bowman ACC = floor(Common / 4.8 + 20)
Thief ACC = floor(Common / 4 + 15)
Magician ACC = floor((1.2 × INT + 2 × Level + 0.6 × LUK) / 5.1 + 20)
EVA = floor(LUK / 3) + floor(DEX / 6) + 5
Magic = floor(INT / 2)
WDEF = floor(STR / 4)
MDEF = floor(INT / 4)
```

Step 2 "The hit roll" (card "Chance to Hit") and card "Darkness":
```text
L = max(0, MobLevel - PlayerLevel)
A = TotalACC × 100 / (10 × L + 255)
D = A - MobEVA
f = 0.15 + 0.20 / (1 + exp(D / 12))
R = uniform(1 - f, 1 + f)
Hit when A × R ≥ MobEVA
q = MobEVA / A
P(hit) = 1 when q ≤ 1 - f
P(hit) = 0 when q ≥ 1 + f
P(hit) = (1 + f - q) / (2 × f) otherwise
Automatic hit: D ≥ 25 + L × (0.5 × PlayerLevel + 15)
Darkness
d = clamp(Darkness / 100, 0, 1)
v = uniform(0, 1)
Lands = Hit and v > d
P(lands) = P(hit) × (1 - d)
Darkness is a separate miss check rolled after the attack hits. It does not lower your accuracy.
```

### 3.2 /formulas/targeting - https://meowdb.com/msclassic/formulas/targeting

Card "Attack Shapes" and "Attack Range":
```text
Attack
Hitbox
Melee attacks
The hitbox of the swing or stab being played
Basic bow, crossbow and claw shots
Widening bands: the first starts 65 px ahead, each band is 20 px long, its half-height is floor(d / 4), centered 28 px above your feet
Ranged skills and spells with no area of their own
The same widening bands, starting 50 px ahead for spells and 65 px ahead for ranged skills
Area skills
A fixed box in front of you or centered on you, mirrored when you face left
d is the distance from you to the start of the band.
Attack Range
Spell: 300 px
Energy Bolt: 350 px
Bow / Crossbow: 300 + EyeOfAmazon px
Claw: 200 + KeenEyes px
Arrow Blow: 350 + EyeOfAmazon px
Three Snails: 300 px
EyeOfAmazon = 45 + 5 × Lv at Lv 1-15
KeenEyes = 40 + 10 × Lv at Lv 1-14 · 200 at Lv 15
Three Snails reaches 300 px with any weapon. The Eye of Amazon and Keen Eyes do not extend it.
```

Card "Weapon Reach" (table, horizontal reach = distance to the far edge of the box; vertical reach = how far above the feet the box goes):

| Weapon | Horizontal reach | Vertical reach |
|---|---|---|
| Spear / Polearm | 133 px (Overhead swing) | 125 px (Side swing) |
| 2H Sword: Scimitar, Lion's Fang, Sparta, Doombringer | 127 px (Thrust) | 95 px (Swing) |
| Other 2H Swords | 98 px (Thrust) | 81 px (Swing) |
| 2H Axe / 2H Blunt | 99 px (Swing) | 90 px (Swing) |
| 1H Axe | 102 px (Swing) | 62 px (Swing) |
| 1H Sword: Long Sword, Beginner's Long Sword, Gladius, Old Gladius, Hero's Gladius, Traus, Jeweled Katar, Sky Blue Umbrella, Yellow Umbrella | 85 px (Swing) | 51 px (Swing) |
| Other 1H Swords | 102 px (Swing) | 62 px (Swing) |
| Dagger: Triangular Zamadar, Beginner's Triangular Zamadar, Triple-Tipped Zamadar, Halfmoon Zamadar, Forked Dagger, Cass, Shinkita | 102 px (Swing) | 62 px (Swing) |
| Other Daggers | 85 px (Swing) | 51 px (Swing) |
| 1H Blunt | 94 px (Swing) | 61 px (Swing) |
| Wand / Staff | 69 px (Swing 2) | 55 px (Swing 2) |
| Bow | 92 px (Crouched attack) | 81 px (Overhead whack) |
| Crossbow | 86 px (Overhead whack) | 81 px (Overhead whack) |
| Barehanded | 64 px (Punch) | 33 px (Punch) |

```text
Horizontal reach is the distance from your character to the far edge of the hitbox.
Vertical reach is how far above your feet the hitbox goes.
Each value is the longest of that weapon's basic attacks, and the attack that reaches it is in brackets. Wands and staffs attack with Swing 2 only.
Values are for levels 1 to 99. From level 100, 2H Axes and 2H Blunt Weapons reach 110 px and Crossbows 88 px. 1H Swords, 1H Axes and Daggers then reach 72 px high, or 58 px for the 85 px group.
Slash Blast Reach
Slash Blast needs a monster inside your weapon's normal reach first.
When it finds one, its reach extends forward to 130 px (Lv 1) up to 150 px (Lv 20), and it hits up to its mob count of monsters inside that longer area.
With no monster in weapon reach, the extension never happens.
Power Strike always uses the weapon's normal reach.
```

Step 2 "Overlap", Step 3 "Which monsters get hit", Step 4 "Walls and platforms" / "Where You Can Cast" (tables flattened one cell per line):
```text
Hit when max(AttackLeft, MonsterLeft) < min(AttackRight, MonsterRight)
and max(AttackTop, MonsterTop) < min(AttackBottom, MonsterBottom)
Both boxes must share width and height. Touching at an edge does not count.
Weapon and monster artwork is ignored. Only the hitboxes count.
Step 3
Which monsters get hit
When more monsters are in range than the skill can hit, the game picks them in this order.
Which Monsters Get Hit
Attack
Order
Basic attacks and melee skills without their own hitbox (Power Strike, Double Stab)
Nearest monsters first. A tie goes to the monster that appeared first.
Melee skills with their own hitbox (Rush, Steal, Savage Blow)
The first monsters to appear on the map
Projectile skills
Nearest monsters first
Spells that hit several monsters
Nearest monsters picked, then their order shuffled
Meso Explosion
Each meso bag takes its nearest monster, one monster per bag
Several meso bags can pick the same monster.
Step 4
Walls and platforms
Only basic ranged attacks and projectile skills check terrain. A blocked monster is dropped and its slot is not refilled.
Terrain Check
Attack
Walls and platforms
Basic bow, crossbow and claw shots
Checked
Energy Bolt, Fire Arrow, Holy Arrow, Element Composition
Checked
Magic Claw, Slow, Cold Beam, Thunder Bolt, Ice Strike, Thunder Spear, Shining Ray, Doom
Ignored
Band of Thieves, Meso Explosion
Ignored
Shooting down through the platform you stand on is blocked. Shooting up through a platform is not.
Poison Breath's explosion ignores walls.
Where You Can Cast
Skill
Where you can cast
Self buffs, toggles and party support skills
Ground, air or rope
Heal
Ground or air
28 attack skills, including Power Strike, Slash Blast, Explosion and Assaulter
Ground or air
31 attack skills, including Energy Bolt, Magic Claw, Ice Strike and Arrow Rain
Ground only
Summons, Mystic Door and Teleport
Ground only
Wind Step and Evasion Step
Ground only
Flash Jump
Air only
Each skill page lists where that skill can be cast.
```

### 3.3 /formulas/damage (tab "Dealing Damage") - https://meowdb.com/msclassic/formulas/damage

Step 1 "Base damage", card "Weapon Damage":
```text
S = SkillDamage / 100
M = (MasteryLevel / 10 + 0.1) × 0.8
B = uniform(0.8, 1.0)
Q = uniform(Primary × M, Primary)
Raw = S × TotalWATK × (B + (Q × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
MIN = S × TotalWATK × (0.8 + (Primary × M × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
MAX = S × TotalWATK × (1.0 + (Primary × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
Average = S × TotalWATK × (0.9 + (Primary × (M + 1) / 2 × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
Ordinary attacks: StatDiv = 100 · APDiv = 50
```

Card "Which Stats Each Weapon Uses":

| Weapon or attack | Primary | Secondary |
|---|---|---|
| Sword / Axe / Blunt / Spear / Polearm | STR | DEX |
| Bow / Crossbow | DEX | STR |
| Dagger / Claw | LUK | STR + DEX |
| Wand / Staff physical hit | STR | DEX |
| Spell | INT | - |

Card "Weapon Damage Multipliers" ("-" on this tab = "Not used" in the guide):

| Weapon | Swing | Stab | Shoot | Mixed |
|---|---|---|---|---|
| 1H Sword | 1.8 | 1.8 | 1.8 | 1.8 |
| 2H Sword | 2.5 | 2.5 | 2.5 | 2.5 |
| 1H Axe / Blunt | 2.4 | 1.2 | - | 1.8 |
| 2H Axe / Blunt | 3.0 | 2.0 | - | 2.5 |
| Spear | 1.5 | 3.5 | - | 2.5 |
| Polearm | 3.5 | 1.5 | - | 2.5 |
| Dagger | 1.0 | 2.0 | - | 1.5 |
| Bow / Crossbow / Claw | 1.0 | 1.0 | 2.5 | 1.0 |
| Wand / Staff physical hit | 1.8 | 1.8 | 1.8 | 1.8 |

Card "Swing and Stab Ratio" (`Average multiplier = P(swing) × Swing + P(stab) × Stab`):

| Weapon | Swing | Stab | Average multiplier |
|---|---|---|---|
| 1H Sword | 60% | 40% | 1.8 |
| 2H Sword | 60% | 40% | 2.5 |
| 1H Axe / Blunt | 60% | 40% | 1.92 |
| 2H Axe / Blunt | 60% | 40% | 2.6 |
| Spear | 60% | 40% | 2.3 |
| Polearm | 60% | 40% | 2.7 |
| Dagger | 60% | 40% | 1.4 |
| Bow, close range | 100% | - | 1.0 |
| Crossbow, close range | 50% | 50% | 1.0 |
| Claw, close range | - | 100% | 1.0 |
| Wand / Staff | 100% | - | 1.8 |
| Barehanded | - | 100% | - |

Cards "Skills With a Fixed Action", "Special Attack Rules", "Spell Damage":
```text
Action
Skills
Stab
Double Stab, Savage Blow
Swing
Steal
Shoot
Avenger, Arrow Rain, Arrow Eruption, and the explosions of Arrow Bomb, Inferno and Blizzard
Mixed
Rush, Shout, Dragon Fury, Dragon Roar, Piercing Crusher, Assaulter, Shadow Web
Close-range weapon action
Power Knockback: a bow swings, a crossbow swings or stabs
Weapon's normal odds
Every other attack skill, the same as a basic attack
A skill set to its weapon's default action stabs with swords, daggers, wands, staves and spears, swings with axes, blunt weapons and polearms, and shoots with bows, crossbows and claws.
Special Attack Rules
Lucky Seven: WeaponMult = 3.0 · M = 0.5
Drain: WeaponMult = 2.5
Bow / Crossbow / Claw projectile: WeaponMult = 2.5 · StatDiv = 100 · APDiv = 50
Close-range ranged swing: WeaponMult = 1.0 · StatDiv = 300 · APDiv = 150
Close-range ranged stab: WeaponMult = 1.0 · StatDiv = 300 · APDiv = 50
Crouched attack: WeaponMult = 1.0 · StatDiv = 300 · APDiv = 150 · B = uniform(0.2, 0.3)
Magic skill: no WeaponMult
Spell Damage
S = SkillPower / 100
M = (MasteryLevel / 10 + 0.1) × 0.8
MagicTotal = floor(TotalINT / 2) + EquipmentMATK + ScrollMATK + BuffMATK
MIN = S × MagicTotal × (1 + TotalINT × M / 100)
MAX = S × MagicTotal × (1 + TotalINT / 100)
Average = (MIN + MAX) / 2
```

Step 2 "Skill bonuses":
```text
Applied to the skill's power before the base roll.
Combo, Panic and Charge
Mechanic
Formula
Combo Attack
1 + (5 + floor(ComboLevel / 2)) / 100
Panic / Coma
1 + 5 × Orbs × (Orbs - 1) / 100
Charge bonus
Damage multiplier = 1 + bonus / 100
Lv 1-8: bonus = Lv + 1 · Lv 9: 9 · Lv 10-30: 5 + floor(Lv / 2)
```

Step 3 "Defense and elements" (cards "Monster Defense", "Element Weakness", "Higher-Level Monsters"):
```text
Monster Defense
EffectiveDEF = max(0, FlatBonus + trunc((1 + PercentBonus / 100) × BaseDEF))
Defended = Raw × 100 / (EffectiveDEF + 100)
Element Weakness
Single element: immune 0 · resistant 0.75 · neutral 1.0 · weak 1.25
Composition multiplier = 0.25 × (Code(Element1) + Code(Element2))
Element codes: immune 0 · resistant 1 · neutral 2 · weak 3
Any other element result counts as 1.0.
Higher-Level Monsters
Gap = MobLevel - PlayerLevel
LevelScale = 1 when Gap ≤ 0
LevelScale = 1 / (1 + Gap² × 0.005) when Gap is 1-9
LevelScale = 1 / (1 + Gap × 0.05) when Gap ≥ 10
```

Step 4 "Hit effects" (Element Amplification, Critical Hits, Shadow Partner and Iron Arrow, Final Attack, Mortal Blow):
```text
Multipliers applied after defense.
Element Amplification
Mechanic
Formula
Element Amplification
Lv 1-29: (104 + Lv)% · Lv 30: 135%
MP cost
BaseMP + trunc(BaseMP × x / 100)
x = 19 + Lv at Lv 1-29 · 50 at Lv 30
The extra MP applies to Energy Bolt, Magic Claw, Fire Arrow, Explosion, Element Composition, Cold Beam, Thunder Bolt, Ice Strike and Thunder Spear. Slow, Seal, Poison Breath and Poison Mist keep their normal MP cost.
Critical Hits
Critical hit = Normal × (1 + d)
Expected with crit = Normal × (1 + c × d)
Before gear and passives, the critical rate is 5% and critical damage is 20%.
Power Knockback always lands as a critical hit.
Damage over time and bleed can land as critical hits.
Shadow Partner and Iron Arrow
Mechanic
Formula
Shadow Partner
Lv 1-29: (109 + Lv)% · Lv 30: 140%
Iron Arrow target i
max(0, 1 - 0.2 × i)
Final Attack
Proc chance = 20% at Lv 1 to 50% at Lv 30
Starts after your attack animation ends, then plays its own attack
Follow-up time = Σ trunc(FrameDelay × (10 + tier) / 16), rounded up to 30 ms
You can't attack again until it ends
Costs no MP
Final Attack
Damage at Lv 30
Hits
Follow-up at speed 4
Fighter: Sword, Axe
140%
Up to 3 mobs within 150 px
630 ms
Page: Sword, Blunt Weapon
270%
1 mob
630 ms
Spearman: Spear, Polearm
260%, absorbs 10% as HP
1 mob
630 ms
Hunter: Bow
90% × 3 arrows
Split like Holy Arrow
630 ms
Crossbowman: Crossbow
250%
1 mob
720 ms
It fires the way you face when it starts. With no mob in front, it doesn't fire.
Mortal Blow
MeowDB's Model
Mechanic
Formula
Mortal Blow
activation rate × direct-hit damage
```

Step 5 "Final number" and "Other damage" (Heal [Unconfirmed], Damage Over Time, Bleed, Meso Explosion [Unconfirmed], Shadow Meso, Linked Explosions, Summons, Invincible Retaliation):
```text
Damage Cap
Final = trunc(clamp(value, 1, 99,999))
Other damage
Damage that does not use the weapon formula.
Heal
Unconfirmed
r = uniform(0.8, 1.0)
S = RecoveryRate / 100
t = PartyMembersHit + UndeadHit
Pool = ((TotalINT × r + TotalLUK) / 200 + 3) × MagicTotal × S × (1 + 0.1 × t)
Undead damage per mob = trunc(trunc(Pool) / t × 0.5)
Party members hit, including you
Undead slots
1
5
2
4
3
3
4
2
5
1
6
0
Heal has six shared slots. You and nearby party members fill them before undead monsters.
This card covers damage to undead monsters, not the HP restored.
Damage Over Time
DoT core total = (ConfiguredDoT / 100) × MagicTotal × (TotalINT / 125 + 1)
Higher-level DoT scale = 1 / (1 + LevelGap × 0.05)
Bleed (Axes and Coma)
Total = (dot / 100) × (1 + (2 × STR + DEX) / 100 + AttackPower / 50) × TotalWATK
Coma: dot × (1 + 5 × Orbs × (Orbs - 1) / 100)
Higher-level scale = 1 / (1 + LevelGap × 0.05)
Axe Mastery per tick = Total / 3
Axe Mastery dot = 40 at Lv 1 · 100 at Lv 20
Coma dot = 40 at Lv 1 · 100 at Lv 30
Axe Mastery can apply bleed on a successful axe hit: 5% chance at Lv 1, 25% at Lv 20. The total lands over three 1-second ticks.
Bleed does not stack. A new bleed refreshes the timer, and a stronger bleed replaces a weaker one.
Slash Blast and Shout roll bleed for every monster they hit.
Bleed ignores mastery, the damage roll and monster defense. It can land as a critical hit.
Meso Explosion
Unconfirmed
x = 900 at Lv 1 · 1,500 at Lv 30
HIGH = x × 0.5 × (1 + Mesos / (Mesos + 10))
LOW = HIGH × 0.5
Damage per drop = uniform(LOW, HIGH)
Shadow Meso
MesoCost = 200 + 10 × (Lv - 1) at Lv 1-29 · 500 at Lv 30
Base = MesoCost × 8
Base = 1,600 at Lv 1 · 4,000 at Lv 30
Damage = Base × LevelScale
Critical hit = Damage × (1 + d)
Final = trunc(clamp(value, 1, 99,999))
Shadow Meso uses the normal hit roll and the Darkness check.
Monster defense and elements do not apply.
Linked Explosions
ExplosionTargets ≤ 4
Arrow Bomb / Inferno / Blizzard explosion: WeaponMult = 2.5 · StatDiv = 100 · APDiv = 50
Arrow Bomb, Inferno, Blizzard and Poison Breath hit one monster first, then set off an explosion.
The explosion hits up to 4 monsters, counting the first one.
The Arrow Bomb, Inferno and Blizzard explosions always count as a shoot action.
Summons
U = uniform(0, 1)
Q = uniform(DEX × 0.48, DEX)
Hawk / Eagle Raw = SkillDamage × (0.8 + 0.2 × U + 2 × Q / 100 + STR / 100 + AttackPower / 50)
M = (ceil(Lv / 3) / 10 + 0.1) × 0.8
QI = uniform(TotalINT × M, TotalINT)
Dragon Raw = MagicTotal × (SkillMagic / 100) × (QI / 100 + 1)
Defended = Raw × 100 / (DEF + 100)
DEF = monster WDEF for Hawk / Eagle · MDEF for Dragon
Silver Hawk and Golden Eagle use DEX and STR with a bow or crossbow equipped. Summon Dragon uses INT.
Summon damage does not use your weapon's attack or multiplier.
Element, higher-level scale, critical hits and the damage cap then apply as usual.
Summons use your hit roll and the Darkness check. Against bosses they never get the automatic hit.
Invincible Retaliation
Retaliation = (dot / 100) × MagicTotal × (TotalINT / 125 + 1)
dot = 9 + Lv at Lv 1-19 · 30 at Lv 20
Higher-level scale = 1 / (1 + LevelGap × 0.05)
Critical hit = Retaliation × (1 + d)
Final = trunc(clamp(value, 1, 99,999))
Hits a monster that touches you while Invincible is active.
Monster defense does not apply. Monsters that ignore reflected damage take none.
```

### 3.4 /formulas/damage-taken - https://meowdb.com/msclassic/formulas/damage-taken

```text
Chance a Monster Hits You
G = max(0, PlayerLevel - MobLevel)
A = MobACC × 100 / (5 × (G + 51))
E = PlayerEVA / (1 + PlayerEVA / 80) / (1 + G / 40)
D = A - E
f = 0.15 + 0.20 / (1 + exp(D / 12))
R = uniform(1 - f, 1 + f)
CandidateChance = P(A × R ≥ E)
If E > A × (1 + f):
CandidateChance = clamp(exp((A - E) / 18) × 0.03, 0.02, 0.03)
FinalHitChance = CandidateChance + (1 - CandidateChance) × 0.08
Step 2
Guards
Guards only work against regular attacks. Monster skills always get through.
Shield and Claw Guard
ShieldGuardChance = 0 when ShieldWDEF ≤ 0
ShieldGuardChance = max(0.05, ShieldWDEF / (ShieldWDEF + 500))
ClawGuardChance = 3% at Lv 1-6 · 4% at Lv 7-13 · 5% at Lv 14-20
Claw Guard is a Hermit skill
Step 3
Damage
Damage Taken
EffectiveMobAttack = trunc(MobAttack × AttackRatio / 100) touch hits: AttackRatio = 100
U = uniform(0, 1)
Roll = 1.1 + 0.4 × U
Raw = EffectiveMobAttack × Roll
Taken = Raw × (1 - DEF / (DEF + 5 × (PlayerLevel + 40) + 1.2 × Raw))
FinalTaken = trunc(clamp(Taken, 1, 50,000,000))
Elemental Resistance
Taken = AfterDefense × (1 - Resist / 100)
Applies to monster attacks with an element, magic and physical.
Applied after defense, before the damage cap.
Touching a monster deals damage with no element, so resistance never reduces it.
Step 4
Defensive skills
Defensive Skills
MeowDB's Model
Power Crash attack = trunc(EffectiveMobAttack × (1 - Reduction / 100))
Invincible (Cleric line): TouchDamage × (1 - Reduction / 100)
Meso Guard damage = DamageBeforeGuard × (1 - Reduction / 100)
Meso cost = DamageBeforeGuard × Reduction / 100 × CostRate / 100
Hyper Body HP = MaxHP × (1 + Bonus / 100)
Magic Guard survival = min(HyperBodyHP + MaxMP, HyperBodyHP / (1 - Transfer))
At 100% transfer: Magic Guard survival = HyperBodyHP + MaxMP
Invincible reduces monster touch damage only. It does not reduce a monster's attacks or magic.
After You Get Hit
Invincible after a hit: 1.5 s
A monster attack that misses you or that you block gives the same 1.5 s.
Knockback Airtime
MeowDB's Model
UpwardSpeed = 270 px/s · Gravity = 2000 px/s²
SameHeightAirtime = 2 × UpwardSpeed / Gravity = 0.270 s
TimeToPeak = UpwardSpeed / Gravity = 0.135 s
Rise = UpwardSpeed² / (2 × Gravity) = 18.225 px
An ordinary knockback gives about 0.27 seconds of airtime when you start on the ground and land at the same height, with normal gravity and no further impacts or obstacles.
This is a physics estimate. Existing movement, ledges and special attacks can change the flight. It does not measure how long you lose the ability to attack.
Fall damage
Fall Damage
N = consecutive movement updates with downward speed ≥ 500 px/s
N ≤ 44: BaseFallDamage = 0
N ≥ 45: BaseFallDamage = max(1, 36 - floor(336 / (N - 18)))
N = 45: 24 · N = 60: 28 · N = 120: 33 · N ≥ 355: 36
For a qualifying landing in COT2, base fall damage starts at 24 and caps at 36. The counter resets when downward speed falls below 500 px/s; N measures consecutive fast-falling updates. Taller drops generally increase it.
Maps can disable fall damage. A flight-map setting multiplies it by 100, but none of the 426 checked COT2 maps enable that setting. The quick check assumes fall damage is enabled on an ordinary map.
DEF, avoidability, level and max HP do not enter this base formula. Final HP loss and mitigation from defensive skills remain unconfirmed.
```

### 3.5 /formulas/attack-speed (tab "Speed & DPS") - https://meowdb.com/msclassic/formulas/attack-speed

```text
Base Animation Times
Action
Base time (ms)
Swing
800
Stab
800
Spear and polearm stab
750
Bow shot
800
Crossbow shot
820
Crouched attack
700
Rush
400
Base times add up the frames before attack speed scales each one.
At speed tier 6 every frame keeps its base length.
Boosters
Weapon Booster: Tier = WeaponTier - 2
Magician attacks: Tier = 6
Spell Booster: Tier = 6 - 1 at Lv 1-10 · 6 - 2 at Lv 11-20
Tier = clamp(Tier, 0, 12)
Weapon Booster only speeds up the weapon type it matches.
Spell Booster speeds up Fire/Poison and Ice/Lightning spells. A wand or staff's speed does not change a spell.
Attack Speed and DPS
MeowDB's Model
timingTier = clamp(resolvedTier, 0, 10)
ScaledFrame = truncTowardZero(FrameDelay × (10 + timingTier) / 16)
nativeMs = Σ ScaledFrame
Player-facing Animation Time = 30 × ceil(nativeMs / 30)
Effective cycle d = max(animation duration, skill-specific lockout)
Completed casts in 60 s = floor(60,000 / d)
One-minute damage = CompletedCasts × w
F(t) = Σ pᵢ × (wᵢ + F(t - dᵢ)) for dᵢ ≤ t
F(t) = 0 when no branch fits
Exact one-minute expectation = F(60,000)
Long-run DPS = Σ(pᵢ × wᵢ) / Σ(pᵢ × dᵢ / 1000)
Skill Lockouts
Dragon Roar cycle = max(animation time, self-stun)
Self-stun = 4 s at Lv 1-9 · 3 s at Lv 10-20 · 2 s at Lv 21-30
Uses per minute ≤ floor(60 / self-stun)
Weapon Booster cannot shorten Dragon Roar's self-stun.
Step 2
Movement and pickup
Movement Speed
Walk speed = 125 × (Speed + 20) / 100 px/s
Climb speed = Speed + 20 px/s
Speed cap: 140 (200 px/s) · Jump cap: 120
Ropes and ladders use the climb speed. Haste raises both.
Pickup Range
Pickup box around your character:
x: 25 px left to 25 px right
y: 60 px above to 30 px below
```

### 3.6 /formulas/leveling (tab "Leveling & Tables") - https://meowdb.com/msclassic/formulas/leveling

Card "EXP to Next Level":

| Levels | Formula | Status |
|---|---|---|
| 1-5 | (floor(level² / 2) + 15) × level | Current |
| 6-50 | q = floor(level² / 3); (q + 19) × q | Current through Lv 49 |
| 51-99 | trunc(previous level's EXP × 1.0548) | Historical |

Card "EXP Table": 99 rows (Level, EXP to next level, Total from Lv 1), transcribed in full in `exp_table.json`. Notes on the card: "Total from Lv 1 is all the EXP needed to reach the next level, starting from level 1." / "Values through level 49 match current play. Level 50 and up follow the historical table." First rows: 1: 15 (15), 2: 34 (49), 3: 57 (106), 4: 92 (198), 5: 135 (333), 6: 372 (705), 7: 560 (1,265), 8: 840 (2,105), 9: 1,242 (3,347), 10: 1,716 (5,063); last: 99: 9,692,044 (180,455,178).

Card "Party EXP": party size 2: 10%, 3: 20%, 4: 30%, 5: 30%, 6: 30%.

Cards "EXP Lost on Death" [MeowDB's Model], "Total HP and MP", "AP and SP":
```text
MeowDB's Model
Loss = floor(EXP to next level × (5 + 20 / LUK) / 100)
EXP after death = max(0, EXP - Loss)
LUK 4: 10% · LUK 10: 7% · LUK 20: 6% · LUK 50: 5.4% · LUK 100: 5.2%
LUK is base LUK: the points you put in, before gear.
EXP stops at 0, so a death never takes away a level.
A Safety Charm stops the loss.
Step 2
Character growth
Total HP and MP
B = min(Level, 10) - 1
C = max(0, Level - 10)
A = 1 + [2nd job at Lv 30+] + [3rd job at Lv 70+]
BeginnerHP = 50 + 16 × (Level - 1)
BeginnerMP = 5 + 12 × (Level - 1)
JobHP = 50 + 16 × B + HPAdv × A + HPPerLevel × C
JobMP = 5 + 12 × B + MPAdv × A + MPPerLevel × C
TotalHP = trunc(JobHP × (1 + MaxHP% / 100)) + EquipmentHP
TotalMP = trunc(JobMP × (1 + MaxMP% / 100)) + EquipmentMP
```

| Class | HP / level | MP / level | HP / advancement | MP / advancement |
|---|---|---|---|---|
| Beginner | +16 | +12 | - | - |
| Warrior | +28 | +12 | +350 | +150 |
| Bowman | +22 | +17 | +250 | +250 |
| Thief | +22 | +17 | +250 | +250 |
| Magician | +16 | +22 | +150 | +350 |

```text
Total AP = 25 + 5 × (Level - 1)
Free AP = Total AP - 16
1st job SP = 1 + 3 × (min(Level, 30) - 10) from Lv 10
2nd job SP = 1 + 3 × (min(Level, 70) - 30) from Lv 30
3rd job SP = 1 + 3 × (Level - 70) from Lv 70
Beginner SP = 9
Every character starts with 4 STR, 4 DEX, 4 INT and 4 LUK, and those 16 points count toward total AP.
Each job advancement adds 1 SP to that job's skill book, then every level adds 3 more.
```

Step 3 "Citizenship and crafting" (not used by a Maple Island Beginner; Citizenship opens at Lv 12, crafting at Lv 10):
```text
Shop discount = (2 × Grade + 3)% at Grade 1-9 · 25% at Grade 10
Storage discount = (5 × Grade)%
Price = round(Base × (100 - Discount) / 100)
Daily quest contribution = 100 + (Grade - 1) × 50
Weekly donation contribution = 250 × (Grade + 1) at Grade 1-9
```

Crafting: "Crafting currently caps at level 10." / "Crafting level 1 unlocks at character level 10. From crafting level 2, the character level needed is 5 × the crafting level." (crafting EXP table on the page; not exported).

### 3.7 /formulas/spawns - https://meowdb.com/msclassic/formulas/spawns

```text
Respawn Times
MeowDB's Model
Global respawn tick = 7.56 s
Wave-point cooldown = 5 s
Effective respawn = first 7.56 s tick at or after death + cooldown
Wave ceiling per point = 3600 / 7.56 ≈ 476 spawns / hour
Timed average per point = 3600 / (Timer + 3.78)
Mobs per Map
MeowDB's Model
PlayerScalar = min(1, 0.75 + 0.05 × (Players - 1))
Capacity = floor(SpawnPoints × PlayerScalar)
```

Player scalar table: 1: 75%, 2: 80%, 3: 85%, 4: 90%, 5: 95%, 6+: 100%.

```text
MeowDB's Model
CyclesPerHour = 3600 / 7.56
WaveSupply = WavePoints × CyclesPerHour × PlayerScalar
TimedSupply = TimedPoints × 3600 / max(Timer + 3.78, 7.56)
SupplyPerHour = WaveSupply + TimedSupply
RequestedPerHour = KillsPerCycle × CyclesPerHour
FractionOfCeiling = min(1, RequestedPerHour / SupplyPerHour) × Uptime
KillsPerHour = round(PublishedKillsPerHour × FractionOfCeiling)
EXPPerHour = round(PublishedEXPPerHour × FractionOfCeiling)
MapEXPPerHour = Σ EXPPerHourᵢ
```

### 3.8 /formulas/pets - https://meowdb.com/msclassic/formulas/pets

Out of scope for a Maple Island Beginner (pets are Cash Shop items); not exported. The only sentence used: "Pets follow your ownership rules. They take free drops and drops that belong to you or your party." (loot_rules.json). The tab also publishes pet levels/closeness, commands, lifespan/hunger, pet pickup box (x: 25 px each side; y: 50 px above to 10 px below), Auto Move search box, Auto HP/MP rule, pet movement/teleport/talk (several cards labelled Unconfirmed).

### 3.9 /guides/explaining-the-damage-formula (tab "Damage Formula") - https://meowdb.com/msclassic/guides/explaining-the-damage-formula

Cheat sheet (Physical / Magic) and "After the raw roll" pipeline:
```text
Damage formula cheat sheet
Use the physical card for weapon attacks and the magic card for spells. Full exceptions and supporting formulas can be found below.
Physical
Weapon attacks
K = SkillDamage / 100
m = (MasteryLevel / 10 + 0.1) × 0.8
MIN = K × TotalWATK ×
(0.8 + (P × m × W + Q + 2A) / 100)
MAX = K × TotalWATK ×
(1.0 + (P × W + Q + 2A) / 100)
K
skill damage / 100
m
mastery factor
P
primary stat
Q
secondary stat
W
weapon action multiplier
A
Attack Power
TotalWATK
all equipped Weapon Attack
Weapon Attack multiplies the whole result. Mastery raises MIN only.
Magic
Spells
K = SkillPower / 100
m = (SpellMastery / 10 + 0.1) × 0.8
MagicTotal = floor(TotalINT / 2)
+ EquipmentMATK + ScrollMATK + BuffMATK
MIN = K × MagicTotal × (1 + TotalINT × m / 100)
MAX = K × MagicTotal × (1 + TotalINT / 100)
K
skill power / 100
m
mastery factor
TotalINT
INT after gear and effects
MagicTotal
derived INT plus all Magic Attack
INT raises MagicTotal and the INT term. Mastery raises MIN only.
After the raw roll
1
Hit check
2
Raw roll
3
Defense
4
Element
5
Level gap
6
Critical
7
Final clamp
These cover the common branches. Separate rules apply to Lucky Seven and prone attacks. Heal and damage over time also use the expandable reference.
```

Worked example "level 30 Warrior" (132 STR, 30 DEX, 4 INT, 4 LUK, clean Gladius 47 W.ATK, no skills/buffs): ACC 49, EVA 11, Magic 2, WDEF 33, MDEF 1; "Mastery at Lv 0 = (0 / 10 + 0.1) × 0.8 = 0.08"; "Basic attack MIN = trunc(47 × (0.8 + (132 × 0.08 × 1.8 + 30) / 100)) = 60"; "Basic attack MAX = trunc(47 × (1.0 + (132 × 1.8 + 30) / 100)) = 172"; "Character-window damage range: 60-172"; max-level Power Strike `S = 2.60` -> 157-449. "MeowDB mirrors split-action weapons by using the lowest MIN and highest MAX across their possible ordinary actions."

"Physical damage":
```text
This calculates weapon-based attack damage before defense and other target modifiers.
S = SkillDamage / 100
M = (MasteryLevel / 10 + 0.1) × 0.8
B = uniform(0.8, 1.0)
Q = uniform(Primary × M, Primary)
B and Q are independent random draws.
Raw = S × TotalWATK × (B + (Q × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
MIN = S × TotalWATK × (0.8 + (Primary × M × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
MAX = S × TotalWATK × (1.0 + (Primary × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
Exact pre-truncation average = S × TotalWATK × (0.9 + (Primary × (M + 1) / 2 × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)
For ordinary melee and fired attacks, `StatDiv = 100` and `APDiv = 50`. MIN and MAX are the opposite corners of two independent rolls, so the distribution is concentrated toward the middle instead of being uniform across the displayed range. MasteryLevel is clamped to 0-10 for this base term.
```

"Weapon actions and multipliers" (same table as 3.3, "Not used" in place of "-") and "Special physical branches":
```text
- Lucky Seven forces `WeaponMult = 3.0` and `M = 0.5`.
- Drain uses the claw's ordinary projectile multiplier of `2.5`.
- A Bow, Crossbow, or Claw projectile uses `WeaponMult = 2.5`, `StatDiv = 100`, and `APDiv = 50`.
- A close-range hit with those ranged weapons uses `WeaponMult = 1.0` and `StatDiv = 300`. A close-range swing uses `APDiv = 150`, and a close-range stab keeps `APDiv = 50`. A Bow always swings, a Crossbow swings or stabs at 50% each, and a Claw always stabs.
- Crouched attack also uses `WeaponMult = 1.0`, `StatDiv = 300`, `APDiv = 150`, and replaces the base `0.8-1.0` roll with `0.2-0.3`.
- Magic skills never use a weapon action multiplier. Wand and Staff `1.8` applies only to a physical whack.
```

"Magic damage":
```text
This calculates ordinary spell damage from skill power, Magic, INT, and mastery.
S = SkillPower / 100
M = (SpellMastery / 10 + 0.1) × 0.8
MIN = S × MagicTotal × (1 + TotalINT × M / 100)
MAX = S × MagicTotal × (1 + TotalINT / 100)
Average = (MIN + MAX) / 2
MagicTotal = floor(TotalINT / 2) + EquipmentMATK + ScrollMATK + BuffMATK
Ordinary magic uses one uniform roll between MIN and MAX. Total LUK and physical Weapon Attack do not enter this
branch
. A wand, staff, sword, or umbrella's displayed weapon speed also does not change a magic action; magician actions resolve from the fixed magic timing category, with eligible Spell
Booster
applied separately.
```

"Defense, elements, levels, and criticals" - order table: 1 `Raw × 100 / (EffectiveDEF + 100)`; 2 Multiply by elemental result; 3 Multiply by higher-level target scale; 4 Multiply by critical result; 5 Apply Iron Arrow target falloff when relevant; 6 `trunc(clamp(value, 1, 99,999))`. Element result table: Immune 0.00, Quarter 0.25, Half 0.50, Resistant 0.75, Neutral 1.00, Weak 1.25, Enhanced weak 1.50.
```text
EffectiveDEF = max(0, FlatBonus + trunc((1 + PercentBonus / 100) × BaseDEF))
Normal defended hit = Raw × 100 / (EffectiveDEF + 100)
For a full-defense-bypass proc with rate `g`:
Expected defended hit = Raw × ((1 - g) × 100 / (EffectiveDEF + 100) + g)
Physical and magic defense use the same curve with different stats. A bypass proc produces either a defended hit or a full bypass; the last line is its expected value.
```
```text
Gap = MobLevel - PlayerLevel
Gap ≤ 0: `LevelScale = 1`
Gap 1-9: `LevelScale = 1 / (1 + Gap² × 0.005)`
Gap ≥ 10: `LevelScale = 1 / (1 + Gap × 0.05)`
Let `c` be critical rate as a decimal and `d` be critical damage as a decimal:
Critical hit = Normal × (1 + d)
Expected hit with
crit = Normal × (1 - c) + Critical × c = Normal × (1 + c × d)
Base values before gear and passives: `c = 0.05`, `d = 0.20`.
```

"Derived combat stats" and "STR, DEX, INT, and LUK effects": same formulas as 3.1; role tables exported in `derived_stats.json` `stat_roles`.

"Outgoing hit chance":
```text
L = max(0, MobLevel - PlayerLevel)
A = TotalACC × 100 / (10 × L + 255)
D = A - MobEVA
f = 0.15 + 0.20 / (1 + exp(D / 12))
R = uniform(1 - f, 1 + f)
Hit
when A × R ≥ MobEVA
Let q = MobEVA / A:
- P(hit) = 1 when q ≤ 1 - f
- P(hit) = 0 when q ≥ 1 + f
- P(hit) = (1 + f - q) / (2 × f) otherwise
Automatic hit threshold : D ≥ 25 + L × (0.5 × PlayerLevel + 15)
Every offensive Magician spell can miss. Physical attacks and offensive spells use this shared target hit check. Some status actions disable the automatic-hit shortcut and still perform the same roll.
```

"Heal and damage over time" (Heal: note the differences from the 3.3 Heal card, see Discrepancies):
```text
Heal
r = uniform(0.8, 1.0)
S = RecoveryRate / 100
Pool = ((TotalINT × r + TotalLUK) / 200 + 3) × MagicTotal × S
t = max(2, every character and undead mob touched)
Undead damage per mob = Pool × (1 + 0.1 × t) / t × 0.5
```

"Animation timing and one-minute damage":
```text
timingTier = clamp(resolvedTier, 0, 10)
ScaledFrame = truncTowardZero(FrameDelay × (10 + timingTier) / 16)
nativeMs = sum(ScaledFrame for every resolved frame)
Player-facing Animation Time (best-supported model) = 30 × ceil(nativeMs / 30)
Weapon Booster shifts a matching weapon by 2 speed stages. Spell Booster shifts eligible F/P and I/L magic actions by 1 stage at Lv 1-10 and 2 stages at Lv 11-20.
The frame durations and their attack-speed conversion are confirmed for ordinary COT2 characters, including Savage Blow. Explosion includes both its preparation and release. We still round displayed times up to 30
ms
steps; that final rounding remains a model.
```

"Incoming hits, guards, and damage":
```text
G = max(0, PlayerLevel - MobLevel)
A = MobACC × 100 / (5 × (G + 51))
E = PlayerEVA / (1 + PlayerEVA / 80) / (1 + G / 40)
D = A - E
f = 0.15 + 0.20 / (1 + exp(D / 12))
R = uniform(1 - f, 1 + f)
CandidateChance = P(A × R ≥ E)
If E > A × (1 + f), replace CandidateChance with:
`clamp(exp((A - E) / 18) × 0.03, 0.02, 0.03)`
After a candidate miss, apply the independent 8% minimum-hit rescue:
FinalHitChance = CandidateChance + (1 - CandidateChance) × 0.08
ShieldGuardChance = 0 when ShieldWDEF ≤ 0
Otherwise: max(0.05, ShieldWDEF / (ShieldWDEF + 500))
ClawGuardChance = 3% at Lv 1-6, 4% at Lv 7-13, 5% at Lv 14-20, for a Hermit who has learned Claw Guard
When both are available, use the larger chance. A successful guard fully negates an eligible regular physical hit.
U = uniform(0, 1)
Roll = 1.1 + 0.4 × U
Raw = EffectiveMobAttack × Roll
Taken = Raw × (1 - DEF / (DEF + 5 × (PlayerLevel + 40) + 1.2 × Raw))
FinalTaken = trunc(clamp(Taken, 1, 50,000,000))
Physical uses WDEF after physical evasion and guard. Magic uses MDEF and bypasses the physical evasion and guard path.
The calculator's middle damage value uses `U = 0.5`, or a `1.3` attack roll. Its per-attempt figure is therefore a
midpoint estimate : `MidpointTaken × PhysicalHitChance × (1 - GuardChance)`. Monster magic attacks use their magic attack value and the MDEF curve without the physical miss roll.
```

### 3.10 Other tabs and guides

**Atk Speed** (https://meowdb.com/msclassic/guides/attack-speed-and-animation-times). Speed tier table (ordinary attack = sword/axe/mace/dagger/claw/bow swing):

| Speed | Label | Ordinary attack (ms) | Attacks/min | Spear stab (ms) | Crossbow (ms) |
|---|---|---|---|---|---|
| 0 | Fastest | 510 | 117 | 480 | 540 |
| 1 | Fastest | 570 | 105 | 540 | 570 |
| 2 | Faster | 600 | 100 | 570 | 630 |
| 3 | Faster | 660 | 90 | 630 | 690 |
| 4 | Fast | 720 | 83 | 660 | 720 |
| 5 | Fast | 750 | 80 | 720 | 780 |
| 6 | Normal | 810 | 74 | 750 | 840 |
| 7 | Slow | 870 | 68 | 810 | 870 |
| 8 | Slow | 900 | 66 | 870 | 930 |
| 9 | Slower | 960 | 62 | 900 | 990 |
| 10 | Slowest | 1020 | 58 | 960 | 1050 |
| 11 | Slowest | 1020 | 58 | (= tier 10) | (= tier 10) |
| 12 | Slowest | 1020 | 58 | (= tier 10) | (= tier 10) |

"Tiers 11 and 12 take as long as tier 10, and no weapon in the game is slower than Slow (8)." Weapon type ranges: Dagger 3-4, Claw 3-5, 1H sword/axe/mace 4-5, 2H sword/axe and Bow 5-6, 2H mace / Spear / Crossbow 6-7, Polearm 7-8, wands/staves cast at Normal (6). "A matching weapon Booster moves your weapon two tiers at every skill level". Every timed Magician spell uses Normal (6): 810 ms.

**Attack Styles** (https://meowdb.com/msclassic/guides/weapon-reach): one card per presentation, "hits A-B px out" and box height, labelled Basic / Final Attack / Not used. All 64 drawn boxes match MeowDB's hit-zone JSON exactly (`attack_styles.json` `svg_cross_check`). Bare hands: "Punch 1 (Basic) 64 px, 15 px tall, hits 27-64 px out", "Punch 2 (Basic) 60 px, 16 px tall, hits 27-60 px out", "Crouched attack (Basic) 56 px, 12 px tall, hits 12-56 px out". Key sentences: "A normal attack with a sword, axe, blunt weapon, spear, polearm, or dagger swings 60% of the time and stabs 40%. At close range, a bow always swings and a crossbow splits 50/50." / "Close-range hit zones are the same in the first and second tests."

**Weapon item pages** (/item-db/541, /576, /585, /558), "Weapon Details": "A normal attack picks one of the attacks, each with equal odds (60% swing, 40% thrust), and the averages use those attacks. Crouched attack is left out of average calculations." Each page also lists every basic attack's reach ("Swing 3: 22- 102 px, 50 px", ...); all 24 values equal the hit-zone boxes (`attack_styles.json` `item_page_reach_cross_check`).

**HP/MP Gain** (https://meowdb.com/msclassic/guides/hp-mp-gain-explained): per-level table identical to 3.6; advancement table Warrior +350/+150, Bowman +250/+250, Thief +250/+250, Magician +150/+350 (500 per advancement); "All five classes are confirmed. Sampled level-ups showed zero variance."; "HP washing is dead in MSCW. INT does not give additional MP here."; "A character starts with 50 base HP and 5 base MP. A Beginner at level 10 has 194 HP and 113 MP."; "Unlike leveling up, job advancing does not heal you. It only raises your max HP and MP."; "The percentage skill applies after the flat bonus, then the result rounds down."

**EXP Table** (https://meowdb.com/msclassic/guides/exp-table-level-1-to-100): same 99 rows (checked row by row); "Levels 1 to 49 are confirmed in the current game. Levels 50 to 99 reproduce a historical reference table and remain planning estimates until they are verified in current play."; "Nexon has never announced a level cap for Classic." (superseded, see Discrepancies); party bonus 10/20/30/30/30%, "The bonus caps at four members."

**Spawn Rate** (https://meowdb.com/msclassic/guides/spawn-engine-respawn-and-map-capacity): "The server runs one respawn check every 7.56 seconds, globally. [...] The tick is a synchronization gate: a mob whose cooldown ended 1 second ago still has to wait for the next tick before it appears." Wave-pool spawn (default): 5 seconds; timed spawn: "That point's timer (60s, 180s, 300s, 1800s, etc.) Replaces the 5s default". "Effective respawn = the first 7.56s tick at or after (death + cooldown). Wave cooldowns are shorter than the tick, so a freshly-cleared wave point cycles roughly every 7.56s in active grinding." Capacity 75% solo +5% per extra player to 100% at six. "Each map's data carries a spawn-rate multiplier, typically between 0.8 and 2.0. Other MapleStory servers multiplied map capacity by it. MSC does not." "Still unverified in current live play: whether the player-count curve is exactly linear at every step, whether timed spawn points sit outside the wave-pool cap, and whether the 7.56-second tick can slip under load."

**Shop Item Efficiency** (https://meowdb.com/msclassic/npc-shops/item-efficiency): ranks items by HP (or MP) restored / price ("HP / meso"); e.g. Meat 160 HP for 80 = 2.000, Red Potion 100 HP for 50 = 2.000, Lemon 150 MP for 150 = 1.000. No other formula.

**Speed, Jump and Movement** (https://meowdb.com/msclassic/guides/speed-jump-and-movement): "At the base Speed of 100, your character walks 150 pixels per second [...] Every point of Speed adds 1.25 px/s, up to the cap of 140 (200 px/s). Jump caps at 120." Jump heights: 100 (base) 77 px, 105: 85 px, 110: 93 px, 115: 102 px, 120 (cap): 111 px. Nimble Feet: +10 Speed, "lasts 10 to 30 sec; 3 min cooldown".

**Beginner's Guide** (https://meowdb.com/msclassic/guides/beginners-guide-first-steps-in-maple-world): "You place your first 9 AP on the character creation screen"; "Every character starts with 4 in each stat. You place 9 more AP at character creation, then get 5 AP per level for STR, DEX, INT, and LUK."; "You earn 9 SP by the time you hit level 10 (1 per level-up, 9 level-ups from 1 to 10)."; Snail hit table (13 STR, 4 DEX/INT/LUK vs level 1 Snail): Sword 4/3/3, Hand Axe 4/3/3, Wooden Club 3/3/2 hits (min/avg/max damage); chairs "30 HP every 10 s" (the chair item pages say "an additional 30 HP every 10 seconds", see Discrepancies); "Taxis are 90% off while you are still a Beginner."; "Switch to basic attacks when MP is low; they cost no MP."

**Chair item pages** (/item-db/522 The Green Relaxer: "Catch your breath and relax by sitting on this chair to restore an additional 30 HP every 10 seconds.", HP Recovery +30, Untradeable, quest reward of Pio's Collecting Recycled Goods; /item-db/525 Sky-blue Wooden Chair: "Restores an additional 30 HP every 10 seconds.", HP Recovery +30, Required Level 5, Mina, 1,000 mesos). The item API names the stat `hpRecoverBonus`.

### 3.11 Beginner skills (skill pages)

| Skill (id) | Lv 1 | Lv 2 | Lv 3 (max) | Other |
|---|---|---|---|---|
| Three Snails (0001000) | Snail Shell -1, MP -3; Damage 15 | Blue Snail Shell -1, MP -4; Damage 25 | Red Snail Shell -1, MP -5; Damage 40 | projectile, 1 target, range 300 px, ground only, any weapon, no element, fixed damage ("Character stats, weapon stats, and target defense do not scale this fixed value."); "Affected by: Skill level"; "Conditional factors: Required shell item, Target hit eligibility"; search begins 50 px ahead, 20 px bands, 1 px vertical per 4 px, 28 px above feet, 100 px up / 44 px down; animation 800 ms base, 810 ms at Normal (6), weapon-speed based |
| Recovery (0001001) | MP -5; Recover HP 24 in 30 sec. Cooldown: 2 min. | MP -10; Recover HP 48 in 30 sec. Cooldown: 2 min. | MP -15; Recover HP 72 in 30 sec. Cooldown: 2 min. | self buff; ground, air or rope; "Output formula: Timed HP recovery"; "Affected by: Skill level"; "Conditional factors: 30-second effect duration"; timing unavailable |
| Nimble Feet (0001002) | MP -4; speed +10 for 10 sec. Cooldown: 3 min. | MP -7; speed +10 for 20 sec. Cooldown: 3 min. | MP -10; speed +10 for 30 sec. Cooldown: 3 min. | self buff; ground, air or rope; timing unavailable |

## 4. What a game programmer must know

1. **Damage is two independent rolls, not one uniform roll.** `B = uniform(0.8, 1.0)` and `Q = uniform(Primary × M, Primary)`, then `Raw = S × TotalWATK × (B + (Q × WeaponMult + Secondary) / StatDiv + AttackPower / APDiv)`. A Beginner has no mastery: `MasteryLevel = 0 -> M = 0.08`. Weapon Attack multiplies everything.
2. **Pipeline** (outgoing): hit check (outgoing hit roll, then Darkness if any) -> raw roll -> `Raw × 100 / (EffectiveDEF + 100)` -> element multiplier -> level-gap scale -> critical (`× (1 + d)` with probability c; base c = 0.05, d = 0.20) -> skill falloff (Iron Arrow) -> `trunc(clamp(value, 1, 99999))`. Skill bonuses (Combo etc.) multiply the skill power before the roll. Each stage is a pure function and can be unit tested against `parity_examples`.
3. **Weapon action**: an ordinary basic attack with a sword, axe, blunt weapon or dagger is a swing 60% / stab 40%; the multiplier depends on the action (1H Axe/Blunt: swing 2.4, stab 1.2; Dagger: swing 1.0, stab 2.0; 1H Sword: 1.8 both). The hit box also depends on the presentation played (`attack_styles.json` `hitzone_sets`, five standing presentations: three swings, two stabs). MeowDB's weapon item pages state that each standing presentation is picked "with equal odds" (20% each, which is where 60/40 comes from); the crouched attack is not in that pool.
4. **Crouched (prone) attack** is its own branch: `WeaponMult = 1.0, StatDiv = 300, APDiv = 150, B = uniform(0.2, 0.3)` and uses the `proneStab` box.
5. **Bare hands**: MeowDB documents the boxes (Punch 1, Punch 2, Crouched attack) and that the action is 100% stab, and nothing else. No WATK, multiplier or speed. Treat as an open design question, not canonical data.
6. **Hit boxes** are in MapleStory px relative to the feet, facing left, y down: mirror x when facing right. Overlap is strict (`<`): touching edges do not hit. Basic attacks pick the nearest monsters first (ties: the monster that appeared first).
7. **Incoming damage**: monster hit chance uses the `incoming_hit` formulas plus an 8% minimum-hit rescue; then (physical only) Shield Guard; then `Roll = 1.1 + 0.4 × U`, `Taken = Raw × (1 - DEF / (DEF + 5 × (PlayerLevel + 40) + 1.2 × Raw))`, `trunc(clamp(Taken, 1, 50,000,000))`. Touch damage uses `AttackRatio = 100` and has no element. After a hit (or a miss/guard) the player is invincible for 1.5 s.
8. **Respawn**: wave points (map `mobTime` 0) wait 5 s, then appear on the next global 7.56 s tick (map pages show "Wave (~7.5s)"); timed points wait `mobTime` seconds instead. Solo capacity is `floor(spawn points × 0.75)`. The per-map mob-rate multiplier is not applied (see Discrepancies).
9. **EXP table** values are "EXP to next level", not cumulative. Levels 50-99 are historical. Level cap 100.
10. **Beginner progression**: level 1, 4/4/4/4 + 9 creation AP (25 total), +5 AP per level, +1 SP per level up to 9 SP at level 10, HP 50 + 16 × (L - 1), MP 5 + 12 × (L - 1) (flat, no randomness), first job at level 10 with no stat requirement, AP never resets on advancement.
11. **Death**: the character dies when HP reaches 0 (Roger, npc 3). Lose `floor(EXP to next level × (5 + 20 / baseLUK) / 100)` EXP, floored at 0 EXP (never de-levels). `baseLUK` is the character's own LUK including the starting 4 (before gear), not just the AP placed in LUK; a value of 0 would divide by zero. No town or Beginner exception is documented. Respawn at the map's Respawn Map (maps domain).
12. **Chairs** add a bonus: "an additional 30 HP every 10 seconds" on top of the resting regeneration, whose base amount is undocumented. The Sky-blue Wooden Chair needs level 5. Do not treat 30 HP / 10 s as the whole sitting regen.
13. **Beginner SP**: the calculator's "Beginner SP = 9" is the level-10 total. The Beginner's guide gives only "9 SP by the time you hit level 10 (1 per level-up)"; 1 SP per level-up from level 2 to 10, and so 0 SP at level 1, is arithmetic from that sentence, not a value any page states (MisoStory starts at 0: `new_character.json` `starting_sp`, an adaptation).

## 5. Ambiguities (rounding order, truncation, floor placement)

Resolved by MeowDB's own calculator code (chunk `5253-8d210be12f2a3111.js`, excerpts in `calculator_code` fields) unless stated otherwise:

1. **Physical/magic raw damage**: MeowDB keeps the raw value fractional through defense, element, level gap and critical, and truncates once at the end (`trunc(clamp(x, 1, 99999))`). The worked examples truncate MIN and MAX only at the end (`trunc(47 × (0.8 + ...))`). Do not round B or Q, and do not truncate between stages.
2. **Clamp before trunc**: `Final = trunc(clamp(value, 1, 99,999))`. A positive raw below 1 becomes 1.
3. **Mastery**: `MasteryLevel` is clamped to 0-10 before `(Lv / 10 + 0.1) × 0.8` (guide text; calculator `W=e=>(D(e,0,10)/10+.1)*.8`).
4. **EffectiveDEF** truncates only the percent-scaled base: `max(0, FlatBonus + trunc((1 + PercentBonus / 100) × BaseDEF))`.
5. **Level gap**: integer `Gap = MobLevel - PlayerLevel`; branch at Gap <= 0, 1-9, >= 10 (`e<=0?1:e<10?...:...`).
6. **Derived stats**: `floor` wraps the whole ACC expression; EVA floors `LUK/3` and `DEX/6` separately then adds 5. "Each floor is applied exactly where shown. Equipment and skill bonuses are added to the matching derived stat afterward." Inputs are total stats (base AP + equipment + buffs).
7. **Outgoing hit**: calculator order is MobEVA <= 0 -> always hit; else ACC <= 0 -> never; else automatic-hit test; else the q-probability. `L` uses `max(1, MobLevel) - PlayerLevel`, floored at 0. `D` is computed with the unrounded `A`.
8. **Incoming hit**: if MobACC <= 0 the hit chance is 0. The far-miss clamp branch replaces the candidate chance; the 8% rescue is applied after it in every case. Player and mob levels are floored at 1.
9. **Damage taken**: `trunc(clamp(Taken, 1, 5e7))` is applied per roll; the min/max shown are the U = 0 and U = 1 rolls (1.1 and 1.5). `EffectiveMobAttack` is truncated before the roll. `Raw` appears inside the defense denominator, so the reduction depends on the rolled value.
10. **Death EXP loss**: `floor` of the whole loss; LUK is base LUK, and the calculator clamps it to 4..999. `EXP after death = max(0, EXP - Loss)`.
11. **EXP table**: levels 51+ chain `trunc(previous × 1.0548)` from the level-50 value (709,716). The published table matches this exactly.
12. **HP/MP**: flat integers; percent bonuses (Max HP %) apply after the flat total, then truncate, then equipment HP is added.
13. **Attack timing**: MeowDB truncates **each frame** (`truncTowardZero(FrameDelay × (10 + tier) / 16)`) and sums, then rounds the sum **up** to a multiple of 30 ms for display. Per-frame lists are not published. Scaling the base total instead reproduces every published ladder value except crossbow at tier 7 (published 870 ms vs 900 ms), so use the published per-tier table. The simulator uses pre-rounding durations for throughput, and the skill pages show the 30 ms display time; MeowDB warns these "should not be substituted for one another". The 30 ms rounding itself "remains a model".
14. **Spawn timing**: "Effective respawn = first 7.56 s tick at or after death + cooldown". Read this as tick at or after (death + cooldown), as the guide writes it with brackets (`spawn_rate.json` `effective_respawn_rule`, and a discrepancy entry). The "average respawn" of 7.56 s for wave points assumes active grinding; for timed points the calculator uses `max(Timer + 3.78, 7.56)`. Capacity uses `floor`.
15. **Swing/stab selection**: the 60/40 split comes from "a pool of three swing entries and two stab entries", and MeowDB's weapon item pages state that each entry is picked "with equal odds" (20% each; crouched attack excluded). The split between Punch 1 and Punch 2 (bare hands, no item page) is not documented.
16. **Element composition**: `0.25 × (code1 + code2)` with codes 0..3; a single element uses 0 / 0.75 / 1.0 / 1.25; "Any other element result counts as 1.0."
17. **Level-gap example**: the /formulas/damage calculator shows "Damage after level gap 889" for raw 1000 at gap 5; that is a display rounding of 888.889. Keep the fractional value until the final `trunc`.

## 6. Discrepancies

| Topic | Page A | Page B | Chosen | Why |
|---|---|---|---|---|
| Level cap | what-is-maplestory-classic-worlds (updated 2026-10-03): "Level 100. Nexon set the maximum character level at Lv. 100 in its Founder's Access release notes." | exp-table guide (updated 2026-09-18): "Nexon has never announced a level cap for Classic." | 100 | Newer page, cites Nexon's release notes |
| Level 50 status | /formulas/leveling: formula row "6-50" labelled "Current through Lv 49" | guide: "Levels 1 to 49 are confirmed" | Level 50 value 709,716 kept, marked historical | Same value; boundary is 49 on both |
| Map mob-rate multiplier | map pages: "Mob rate (1x) multiplies that capacity [...] best reading from closed-beta play" | spawn guide: "MSC does not. The live game ignores it"; glossary: "There is no separate map-wide multiplier" | Not applied | Dedicated guide + glossary agree; the map page itself says its figures do not apply it. **Unresolved**; 000000040 shows 1.0x, check each map's mobRate |
| Respawn display | map pages "Wave (~7.5s)" | /formulas/spawns "Global respawn tick = 7.56 s" | 7.56 s | Display rounding of the same model |
| Damage window vs distribution | glossary: "Every hit rolls somewhere inside." | damage guide: two independent rolls, concentrated toward the middle | Two rolls | Methodology page; the glossary is not wrong, only imprecise |
| Heal undead damage | /formulas/damage (Unconfirmed): `t = PartyMembersHit + UndeadHit`, `Pool = (...) × S × (1 + 0.1 × t)`, `trunc(trunc(Pool) / t × 0.5)` | guide: `t = max(2, every character and undead mob touched)`, `Pool × (1 + 0.1 × t) / t × 0.5` | Both recorded, not used | Cleric skill, not Beginner; resolve before implementing Clerics |
| AP contribution to HP/MP / which stats AP raises | glossary: "Max HP/MP goes up with level, plus a small AP contribution." and AP: "Used to raise STR / DEX / INT / LUK / HP / MP." | HP/MP guide: no AP term, "HP washing is dead in MSCW"; Beginner's guide: "5 AP per level for STR, DEX, INT, and LUK"; leveling formulas: no AP term | No AP term; `allocatable_stats` STR/DEX/INT/LUK; AP-into-HP/MP stays a gap | Measured mechanics page and the newer Beginner's guide outrank one-line glossary definitions (recorded in `hp_mp_gain.json` and `beginner.json`) |
| Chair recovery: total or bonus | Beginner's guide table: "30 HP every 10 s" | chair item pages 522/525: "restore an additional 30 HP every 10 seconds" (API stat `hpRecoverBonus`) | Bonus on top of the base resting regen (`additional_hp_per_tick`) | Item detail pages are priority 1 |
| Effective respawn grouping | /formulas/spawns: "first 7.56 s tick at or after death + cooldown" | spawn guide: "first 7.56s tick at or after (death + cooldown)"; map pages: cooldown, then the next tick | Tick at or after (death + cooldown) | Only this reading gives the stated ~7.56 s cycle of a cleared wave point |
| Three Snails search start | skill page: begins 50 px ahead; skill-area data `"0001000":{rc:300,rd:1,am:"magic"}` (magic band, 50 px) | /formulas/targeting: ranged skills start 65 px ahead | 50 px | Skill detail page (priority 1) and per-skill data agree |
| Final Attack / Shadow Partner wording | /formulas/damage tables | guide "Skill-specific modifiers" | Same numbers; not used by a Beginner | No numeric conflict |

## 7. Gaps (MeowDB does not document these)

- Bare-hand (no weapon) Weapon Attack, weapon multiplier and attack speed/animation time.
- Beginner-specific max level; SP gained as a Beginner after level 10 (calculator returns 9 total).
- Stat caps (STR/DEX/INT/LUK, ACC, EVA, DEF); only Speed 140 / Jump 120 are documented.
- Whether AP can go into Max HP / Max MP and how much it gives.
- Level-up heal amount (only implied that levelling up heals).
- Natural HP/MP regeneration amounts, interval, and what "not in combat" means; sitting on the ground; the base resting regen that a chair's "additional" 30 HP / 10 s is added to. (MisoStory uses the project owner's rule for HP, 10 HP per 10 s still or seated, in `game/data/misostory/recovery.json`; MP stays without natural recovery.)
- Which of Punch 1 / Punch 2 a bare-handed attack plays (the "equal odds" sentence exists only on weapon item pages).
- Potion use cooldown / lock.
- Drop expiry time, drop ownership duration, drop scatter, item drop chances, meso drop amount formula. (Iteration
  Three: MeowDB's community lists give the drop members and its player reports the meso amount where one exists,
  Henesys.gg gives each item's rarity, and the drop chance table and the meso rule are the project owner's adaptations,
  `game/data/misostory/drop_rates.json` and `meso_rules.json`, decisions D3-11 and D3-12: [monsters.md](monsters.md).)
- HP/MP after respawn, respawn delay, any item/meso loss on death; town or Beginner exceptions to the EXP loss (none listed).
- Player knockback horizontal speed/distance and when it triggers; monster knockback distance (only "a mob with 500 KB needs 500+ damage to stagger"). The monster stagger time was a gap here too; the live monster pages publish it since ("STAGGER 0.6 seconds", read 2026-10-05: `stagger_ms` in the monster records), though `formulas/movement.json` `monster_knockback.gaps` still lists it until the formulas extractor reads the captures.
- Whether Three Snails uses the hit roll, level-gap scale and criticals: not stated explicitly (its page lists "Target hit eligibility" as a conditional factor, which suggests the shared hit check applies); its terrain interaction ("not confirmed").
- Recovery's HP tick interval; Recovery / Nimble Feet cast animation ("Timing unavailable").
- Party EXP split between members.
- Which spawn points fill when capacity < spawn points; initial population on map load.
- Per-frame FrameDelay lists; the movement-update tick length used by fall damage.
- Starting clothes / starting inventory.

## 8. Tooling notes

- `tools/meowdb/lib.mjs` worked as documented; no bugs found. Environment gotcha: Git Bash rewrites a leading-slash argument such as `/formulas` into a Windows path (`C:/Program Files/Git/formulas`) before Node sees it, which produced two 404 requests early on. Pass paths without the leading slash, or set `MSYS_NO_PATHCONV=1`.
- The extractor locates JS chunks by content, not by hash (it scans the chunk list of `/character-builder` and `/formulas`), so a MeowDB redeploy only needs `--refresh`.
