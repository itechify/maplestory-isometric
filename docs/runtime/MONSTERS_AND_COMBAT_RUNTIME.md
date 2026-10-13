# Live monsters, breakables and the player's combat (Iterations Two and Three)

This system puts the monsters and the fighting into the real scene: brief Phase 7 (monster framework, the Maple Island
monster set, monster behaviour, spawn-system integration) and the in-world half of Phase 8 (attacks, hit detection,
damage numbers, knockback, death, contact damage, post-hit invulnerability, the EXP award). The mathematics are wave
1's: [`COMBAT.md`](COMBAT.md) (`CombatFormula`, `CombatReach`, `WeaponProfile`, `StatCalculator`, `Progression`). The
spawn model and slots are [`WORLD_RUNTIME.md`](WORLD_RUNTIME.md) (`MapInstanceView`, `MapInstanceState`). Drops are
[`ITEMS.md`](ITEMS.md) (`DropRoller`). Nothing here restates a canonical number: every gameplay value is read from
`game/data/canonical/` through `ContentDB`, and every value MeowDB does not publish lives in
`game/data/misostory/monsters/_shared.json` (what every species shares), `monsters/<id>.json` (per species) or
`combat.json` (wave 1's file; this system owns its `player_attack` section), each with a reason and `verified: false`.

## Files

| Path | Class | Role |
|---|---|---|
| `scripts/actors/monsters/monster_system.gd` | `MonsterSystem` | root of `scenes/systems/monster_system.tscn`: `setup(ctx)`, the monster factory/releaser, kill and touch handling, the FX layer, who shows a see-through silhouette (`update_see_through`) |
| `scripts/actors/monsters/monster.gd` | `Monster` | one live monster (`scenes/actors/monster.tscn`, a `CharacterBody3D` on `WorldLayers.MONSTERS` with `MONSTER_MASK`) |
| `scripts/actors/monsters/monster_def.gd` | `MonsterDef` | pure: the canonical record joined with its adaptation file; the speed, hop and size conversions |
| `scripts/actors/monsters/monster_brain.gd` | `MonsterBrain` | pure: stand / pace back and forth / turn / stagger / chase |
| `scripts/actors/monsters/mob_region.gd` | `MobRegion` | pure XZ geometry: the map's mob region minus the portal-arrival discs |
| `scripts/actors/monsters/monster_visual.gd` | `MonsterVisual` | the art pack's rigged model and its state-driven clips (else the proxy model, else a named stone fallback body), bob, facing, flinch, HP bar, spawn and death fades, the see-through silhouette (stencil 36) |
| `scripts/actors/monsters/monster_test_rig.gd` | `MonsterTestRig` | synchronous combat lab for tests (private bus, private `GameState`, seeded RNG) |
| `scripts/actors/monsters/monster_game_checks.gd` | | the real-game checks (`scenes/actors/monster_game_checks.tscn`): `main.tscn`, the console's `spawn`/`kill`, real mouse and key events |
| `scripts/actors/combat/player_combat.gd` | `PlayerCombat` | the player's basic attack (a child of the player, added by `setup`) |
| `scripts/actors/combat/mouse_attack_gate.gd` | `MouseAttackGate` (+ `MouseAttackGate.Observer`) | the mouse's share of the `attack` action: only world clicks count, never a click the UI took; the observer is PlayerCombat's internal child that feeds it every mouse event, even while the tree is paused |
| `scripts/actors/combat/attack_lock_input.gd` | `AttackLockInput` | `InputSource` decorator: no walking or jumping during a ground attack |
| `scripts/actors/combat/melee_query.gd` | `MeleeQuery` | pure: canonical hit boxes and touch zones placed in 3D, target selection, touch overlap |
| `scripts/actors/combat/contact_damage.gd` | `ContactDamage` | pure statics: touch gate, resolve, apply (HP, events, knockback), death announcement |
| `scripts/actors/combat/damage_numbers.gd` | `DamageNumbers` | floating numbers (`scenes/fx/damage_numbers.tscn`) |
| `scripts/actors/combat/attack_fx.gd` | `AttackFx` | swing arc, thrust, punch, hit spark (the art pack's `HitSpark` when installed), and the attack box's footprint on the ground (`scenes/fx/attack_fx.tscn`) |
| `scripts/actors/combat/effect_meshes.gd` | `EffectMeshes` | the art pack's effect meshes by name (`ArtPack` kind `EFFECT`), loaded once; empty without the pack (#71) |
| `data/misostory/monsters/_shared.json` | | the adaptation every species shares (model fit, terrain probes, floor band, pacing rhythm, chase time, hop landing reach, fall landing tolerance, the see-through silhouette's radius, hysteresis, colour and fade); a species file overrides any key |
| `data/misostory/monsters/{1,2,3,4,5,9}.json` | | per-species adaptation (model, capsule, walk style, speed model, stand and walk times, touch rule, hop and its floors) |
| `data/misostory/combat.json` `player_attack` | | the player-attack feel: ground root, input buffer, target count, model lunge |
| `scenes/sandbox/monster_sandbox.tscn` (+ `.gd`) | | the real island, player, camera, MapSession and this system, with a fighting bot and screenshots |

## Integration (for the game shell)

Instance `res://scenes/systems/monster_system.tscn` under `ctx.systems` and call `setup(ctx)` once `ctx.world` (the
`IslandWorld`) and `ctx.player` exist. Nothing else is needed. `setup`:

1. **World.** Installs `make_monster` / `release_monster` as `world.instance_view.monster_factory` /
   `monster_releaser` (immediately, or on `world_ready` if the world is still building), takes the world's
   `ProxyLibrary`, `WorldTuning` and `PhysicsGroundQuery`, and connects `world.body_fell` (a monster that reaches
   the sea returns to its spawn point). If a map is already live, it calls `view.realize(state, def, player_pos)`
   again at once, so the static proxies the default factory made become real monsters (survivor HP is kept).
2. **Player.** Adds a `PlayerCombat` child named `PlayerCombat` to `ctx.player` (reused if present; calling `setup`
   twice is safe). It reads the `attack` action from `player.input_source`, so the traversal bot can attack too.
3. **FX.** `DamageNumbers` and `AttackFx` are children of the system node (a `Node3D` at the origin). The numbers
   size themselves from the gameplay camera (`ctx.camera`'s `Camera3D`, else the viewport camera).

Every collaborator is optional: without a world the system only serves free spawns; without a player there is no
contact damage and no attack. `db`, `game`, `events` and `session` default to the `Data`, `Game`, `Events` and
`MapSession` autoloads; tests inject private ones. On `_exit_tree` the view gets its default factory back.

The debug console (`scripts/debug/debug_commands.gd`, not ours) uses this seam: `spawn` calls the installed
`monster_factory` with a slot index of -1, and `kill` calls `Monster.debug_kill()`. See "Debug console support"
below.

## Data flow

```
MapSession.transition → IslandWorld.activate_map → MapInstanceView.realize(state, def, arrival)
    → make_monster(mob_id, slot)  [MonsterDef.from_id: canonical record + misostory/monsters/_shared.json + <id>.json]
        Monster.setup(def, system, slot.transform, seed, MobRegion(def), ground query, library, slot HP)
        Monster.slot_index = slot.index (-1 = no slot: a debug spawn)
Monster.step (each physics tick, priority 20, after the player):
    MonsterBrain.tick → move dir → probe(dir): region / wall rays / ledge ray → advance onto the ground (or hop, or turn)
    → MonsterSystem.monster_touch(monster)
        ContactDamage.can_be_touched (alive, not invulnerable, not warping) + MeleeQuery.touch_overlaps
        → CombatFormula.resolve_monster_touch → ContactDamage.apply: StatCalculator.change_hp, Events.player_damaged /
          hp_changed (or player_missed_by), player.apply_knockback_from_point(pos, 1, res.invincibility_s) or
          player.set_invulnerable(res.invincibility_s); a number over the player; HP 0 → announce_death
PlayerCombat.step (priority 10): attack action (keys from the input source; the mouse only through world clicks,
    MouseAttackGate) → choose_ordinary_action → lockout = attack_duration_ms
    → CombatReach.attack_box_px → MeleeQuery.pick(nearest, cap 1) → CombatFormula.resolve_physical_hit
    → MonsterSystem.apply_player_hit: number (MISS / damage / critical), spark, Events.monster_hit / monster_missed
    → Monster.receive_hit: HP, stagger (DamageResult.knockback = damage >= KB), provoked, die at 0
Monster.die (a killing blow, or the console's Monster.debug_kill) → MonsterSystem.on_monster_died:
    Game.gain_exp(canonical EXP, "monster:<id>"), Events.monster_killed(id, map),
    DropRoller.roll(id, db, Game.rng) → Events.loot_dropped(drops, feet, map) when anything dropped
    → Monster.died → MapInstanceView.notify_killed(slot) → MapInstanceState.kill(slot, Game.clock)   (slot monsters only)
    → respawn on the first spawn_rate.json tick (7.56 s) at or after death + 5 s; the body fades over die_fade_ms
```

## Monsters

### Species data (`MonsterDef`)

Canonical, from `data/canonical/monsters/<id>.json`: level, HP, EXP, P.DMG, ACC, AVOID, defences, KB, the speed
modifier, the movement label, the Peace flag, `touch_zone_px`, `sprite_size_px`, the clip lengths (`stand`, `move`,
`hit1`) and `die_fade_ms`. `MonsterCombatStats.from_id` feeds `CombatFormula`. Conversions:

| Value | Rule | Snail / Orange Mushroom |
|---|---|---|
| Walk speed | `slope x (base_speed + modifier)` px/s → `WorldScale.h`. `slope` is the px/s per Speed point of MeowDB's published walk line (`walk_speed.base_px_per_s` at `base_speed`, `cap_px_per_s` at `speed_cap`: 1.25). The character-only "+20 Speed behind the scenes" is not applied | 43.75 px/s = 0.875 m/s; 125 px/s = 2.5 m/s (player 3.0) |
| Touch zone | `touch_zone_px` x `WorldScale.actor`, depth = width (`combat.json isometric_reach`) | 0.93 x 0.65 m; 1.58 x 1.45 m |
| Model size | proxy scaled so its height = `sprite_size_px[1]` x `WorldScale.actor` (`model_fit: sprite_height`) | 0.65 m; 1.45 m |
| Stagger | the canonical record's own stagger time when it carries one (MeowDB's live pages, 2026-10-05: "STAGGER 0.6 seconds" for all six; fields `stagger_s`, `stagger_ms`, `stagger_duration_s/_ms` or `stagger` {seconds, ms}; `combat.json monster_knockback.stagger_from_canonical_record`), else `CombatFormula.monster_stagger_s` (the canonical `hit1` clip, 600 ms). `MonsterDef.stagger_source` says which | 0.6 s |
| Push | `CombatFormula.monster_knockback_distance_px` (20 px) x `WorldScale.h` | 0.4 m |
| Hop | apex = the character's canonical base jump (`jump_height_px_by_jump` at `base_jump`, 77 px x `WorldScale.v` = 0.90 m); gravity = canonical `knockback_airtime.gravity_px_per_s2` x `WorldScale.v` | Orange Mushroom only |

### Adaptation layers (`_shared.json` + `<id>.json`)

`MonsterDef.build` reads `data/misostory/monsters/_shared.json` (`MonsterDef.SHARED_TABLE`) and lays the species file
over it (`MonsterDef.merged_adaptation`): any key the species file names wins, and its `reasons` entry wins with it.
`MonsterDef.adaptation` holds the merged view. The shared table holds what all six species repeated: `model_fit`, the
three MAP_ARCHITECTURE §4.7.4 probes (`probe_ahead_m` 0.6, `ledge_tolerance_m` 0.45, `wall_probe_height_m` 0.3),
the floor band (`floor_band_m` 0.5), the pacing rhythm (`pace_reverse_chance` 0.35, `pace_min_run_m` 1.0,
`turn_jitter_deg` 50), `provoked_chase_s`, and the two values that used to be code constants,
`hop_max_rise_apex_fraction` (0.9, jumpers) and `fall_landing_tolerance_m` (0.05). `speed_model` stays in each
species file, because its reason carries that species' own conversion (Snail: 1.25 x 35 = 43.75 px/s). A missing
shared table, or a value missing from both layers, is a `MonsterDef.errors` entry. The data validator treats a file
whose name starts with `_` in a canonical-domain folder as a shared table, not as a monster id
(`AdaptationChecks.SHARED_TABLE_PREFIX`); the reason/verified convention and the reference sweep still apply to it.

### Behaviour (`MonsterBrain` + `Monster`)

The classic simple loop. MeowDB's movement labels say how: 'Stays on its floor' ("Walks back and forth on the floor it
spawns on": species 1-5) and 'Jumps between floors' ("Can hop to a floor above or below its spawn point": the Orange
Mushroom). A monster stands (`idle_s`) and walks (`walk_s`) **back and forth on one line**, its pacing axis (the facing
its spawn slot gave it): it turns around exactly when blocked, and after a stand it turns around on the line with
`pace_reverse_chance` (0.35), else carries on. When it is blocked twice in a row after less than `pace_min_run_m` (1 m)
each (a corner, a narrow strip of floor), its line itself turns by 90° ± `turn_jitter_deg`. A chase faces the attacker;
when it ends the monster goes back to its line. Iteration Two re-rolled a random 3D heading after 60% of stands, which
read as wandering, not pacing. Before every step it probes, as MAP_ARCHITECTURE §4.7.4 specifies:

- **Region.** `MobRegion.allows_step(pos, pos + dir x probe_ahead_m)`. The region is the map's mob region
  (`SpawnSlotPlanner.mob_region`: the footprint inset by `spawns.mob_region_inset_m`, 2 m) minus a disc of
  `spawns.slot_portal_clearance_m` (4 m) around every portal arrival and arrival gate (the clearance spawn slots
  keep). Trails lie outside every footprint, so monsters never enter trails or reach a portal. A monster already
  outside (a forced slot or a knockback) may only move back toward the inside.
- **Wall.** Three rays at `wall_probe_height_m` (0.3 m), from the centre and both sides of the capsule, reaching
  `probe_ahead_m` (0.6 m) ahead, against walkable and blocking. A hit steeper than the ledge slope
  (`atan(ledge_tolerance / probe_ahead)` = 37°) is a wall; a ramp is not.
- **Ledge.** `PhysicsGroundQuery.ground_at(ahead, ±ledge_tolerance_m)`: the first surface within ±0.45 m must be
  walkable (a blocking slab within the world's coplanar tolerance counts, as for the player).
- **Floor.** That ground must stay on the monster's floor (`Monster.floor_range`, probe reason "floor"). A monster's
  spawn floor is its spawn height ± `floor_band_m` (0.5 m), widened to its spawn region's authored height band
  (sidecar `spawn_regions` `y_band`, found through the slot's region: `MonsterSystem.region_band`) when the slot lies
  on that tier (`MonsterDef.floor_range`). Connected by the probes and limited by the mob region, that is "the walkable
  surface it can walk to from its spawn point, at its spawn height", so a walker never climbs or descends a ramp to
  another terrace (Iteration Two let any ramp-connected terrace of the mob region count). A monster already off its
  floor (fallen) may only move back toward it. Chases and stagger pushes obey it too.

Then it moves `speed x dt` and sits on the ground found under its new position. There are no physics sweeps:
monsters never collide with each other or with the player (classic bodies overlap), and their capsule exists for the
sea kill plane and debug overlays. A monster with no ground under it (spawned in the air) falls with the canonical
gravity and lands on ground within `fall_landing_tolerance_m` (5 cm) of its feet; below the map's `kill_y` or on the
sea plane it returns to its spawn point.

- **Jumpers** (Orange Mushroom, "Jumps between floors"): every `hop_interval_s` while walking, and instead of turning
  at a ledge, a wall or its floor's edge, it tries a ballistic hop one walk-speed airtime ahead. The landing must be
  walkable ground from `hop_max_rise_apex_fraction` (0.9) of the apex above to `hop_max_drop_m` (2 m) below, inside
  the region, with a clear path (two rays over the arc), **and on a floor it may use** (`monsters/9.json
  hop_floor_rule` "spawn_floor_one_hop", `MonsterDef.hop_floor`): from its spawn floor (floor 0) it may hop onto a
  floor above or below it (floor +1 / -1, walking within `floor_band_m` of the landing height there); from floor +1 or
  -1 it may only hop along that floor or back to the spawn floor. So it never ends up two floors from its spawn point
  (Iteration Two measured each hop from where it stood, so repeated hops could cross a hillside of terraces).
  Otherwise it turns. It really changes floors: the world test counts 56 hops in 60 s of simulated time on five maps.
- **Hit.** When `DamageResult.knockback` (damage >= KB; every Maple Island monster has KB 1) it staggers for its
  stagger time (the canonical STAGGER, 0.6 s) and slides 20 px away from the attacker, stopping at a ledge, wall,
  region edge or the edge of its floor (never knocked off a cliff). A knockback hit **in mid-hop** cancels the rest
  of the hop (`combat.json monster_knockback.airborne_hit` "cancel_hop_then_push"): it keeps its vertical speed,
  falls straight down from where it was hit, and the push runs during the fall (over ground on a floor it may use) and
  after the landing, so it ends about 0.4 m away from the attacker like a monster hit on the ground (Iteration Two let
  the hop carry it on, up to 1.4 m, often toward the attacker: test_b WARN #43). Any hit provokes it: it turns to the
  attacker and, after the stagger, walks toward the attacker for `provoked_chase_s` (a chase stops at an edge instead
  of turning away), then paces its line again.
- **Death.** No more touches or hits; the owner announces it at once (MeowDB: "Loot drops as soon as the mob dies");
  the body fades over the canonical `die_fade_ms` (Snail 1.26 s), sinks a little (a rig plays `Death` instead) and
  frees itself.

### Presentation (`MonsterVisual`)

**Rigged models (Project art, #64).** With the art pack installed (ADR 0002), each species is Jarvis's rigged model,
looked up by canonical id: `MonsterVisual.build(def, library, art)` takes `art.instance(ArtPack.MONSTER, def.id)`
(`MonsterSystem.art`: `setup(ctx)` loads `ArtPack.load_installed()` unless one was injected; passed through `Monster.setup`). `model_fit` still sizes it:
the top of its meshes at rest goes to the canonical sprite height, on the model's own origin (feet at y = 0, front +Z).
`model_source` says where the model came from. The rig plays the clip the monster's state selects, and never drives
it:

| State | Clip | How it plays |
|---|---|---|
| standing (`is_walking()` false) | `Idle` | loops |
| moving or hopping (`is_walking()`) | `Walk` | loops |
| a resolved touch (`MonsterSystem.monster_touch` returned true; monsters have no other attack) | `Attack` | once; never cuts a `Hit` short |
| a landed hit (`on_hit`) | `Hit` | once, over the canonical `hit1` time |
| death (`start_death_fade`) | `Death` | once, over the first half (`DEATH_CLIP_SHARE`) of the canonical die time at full opacity; the body fades over the rest, so `faded_out` still fires at the die time; nothing interrupts it |

Changes cross-fade over `CLIP_BLEND_S` (0.15 s). The import holds every clip's root bone at rest and sets the loops
(`ArtImport`), so animation never moves the monster: AI and physics own its position. Where a clip covers it, the
procedural motion below is skipped (walk bob and squash under `Walk`, flinch under `Hit`, death sink under `Death`);
facing, the spawn scale-in, the flash, the HP bar and the fades stay. Without the pack (or for a species it lacks) the
proxy or the fallback body is built and moves procedurally, as before. Fitted to the sprite height, the pack's
Tutorial Jr. Sentinel is a 1.7 m dome about 1.7 m across (its touch zone is 0.53 m wide: the sprite is tall, the model
squat), and the snails are 1.25-1.4x their touch width along their facing; the Shroom and the Orange Mushroom match.
`bash scripts/godot.sh --path game --resolution 1600x900 --disable-vsync res://scenes/sandbox/monster_sandbox.tscn --
--map 000001010 --showcase <dir>` shoots every species' states.

**Proxies.** The proxies from `_library.glb` (Snail, Blue Snail, Red Snail, Shroom, Orange Mushroom, and since Iteration Three the
Tutorial Jr. Sentinel: `Mob_TutorialJrSentinel`, a small stone sentinel with one glowing eye, `src/misostory/kit/
creatures.py`). Every proxy stands on its feet (its lowest vertex at y = 0: the Orange Mushroom floated 0.18 m and the
Snail 5 cm) and, fitted to its canonical sprite height, its footprint along its facing is 1.0-1.2x its canonical
touch-zone width (the Blue and Red Snails were 1.3x). If an export lacks a proxy, a stone fallback body at the
canonical sprite size carries the monster's name. All procedural motion goes on a pivot above the asset: a walk cycle with
one period per canonical `move` clip ("crawl" squash and stretch for snails, "bounce" for the rest), facing (720°/s),
a backward flinch over the canonical `hit1` clip with a white flash, a scale-in over `spawns.fade_in_s` (0.3 s), and
the death fade (`GeometryInstance3D.transparency`). A red HP bar (billboard, drawn over terrain, left-anchored in mesh
space so it reads the same at every facing) appears over the head once the monster is damaged. A spawned monster
settles onto the ground within `grounding.probe_up_m` / `probe_down_m` (presentation.json).

### See-through silhouette (`MonsterVisual` + `MonsterSystem.update_see_through`)

The camera dithers out trees, buildings and tall props, but terrain, cliffs and rocks never fade (PLAYER_AND_CAMERA.md
"Occlusion"). So a monster near the player shows a flat tinted silhouette wherever something hides it, the monster
counterpart of the player's X-ray fill. It is per pixel and needs no occlusion test: the stencil decides where the
monster is hidden.

- **Stencil write.** Every surface of the model writes `MonsterVisual.STENCIL_REF` (36) where it is visible (custom
  stencil: write, always), the unshaded ink shell (`M_Outline`) too, so the silhouette never paints over the contour
  lines drawn in front of the body. The library's materials are shared by every proxy (`M_Outline`, the eye
  materials), so each gets one stencil-writing copy (`MonsterVisual.stencil_material`, cached per source material and
  shared by every monster); the placeholder's own materials are changed in place.
- **The fill.** Under each model mesh, a `SeeThrough` MeshInstance3D draws that mesh's triangles, every surface merged
  into one (`MonsterVisual.fill_mesh`, built once per library mesh: one draw call instead of one per material; the ink
  shell is included, so the silhouette has the footprint of the visible monster) with one `ShaderMaterial` all
  monsters share (`MonsterVisual.see_through_material()`): unshaded, no depth test, both faces, no depth write, no shadow, render
  priority -1, and `stencil_mode read, write, compare_greater, 36`. A ShaderMaterial, because BaseMaterial3D keeps
  stencil read and write exclusive (its setter drops one flag); reading and writing in one pass is what makes each
  pixel blend once, so a hidden snail is one flat shape, not darker where its shell overlaps its body. Godot compares
  `reference op stored` (probed: compare_greater with reference 3 passes over 0 and fails over 5), so the fill draws
  where the stored value is below 36: where neither a monster nor the player is visible. The player writes 37
  (`PlayerVisual.STENCIL_REF`), so **36 must stay below the player's reference** (a test pins it): a monster hidden
  only by the player gets no silhouette over the player, and a monster in front of another hides it as usual. Any
  future stencil writer that a silhouette must not cover needs a value of at least 36. The tint, the fade amount and
  the minimum cover are instance uniforms (`see_through_tint`, `see_through_amount`, `see_through_min_cover`).
- **Minimum cover.** The fill reads the depth texture (the opaque pass) and discards a fragment unless the surface in
  front of it is at least `see_through_min_cover_m` (0.25 m) nearer the camera along the view. Without it every
  monster on a slope wore a tinted line along its underside, where the body dips a few centimetres into the ground
  (seen in the real game; 27 sampled px under one Snail on Snail Hunting Ground I, 0 with the threshold), and grass at
  its feet would tint too. Cliffs, terrace edges and boulders are half a metre to metres in front and still show it.
- **Skinned rigs.** Under a rig's skinned mesh the fill shares the mesh's `Skin` and points at the same `Skeleton3D`,
  and a merged fill mesh keeps every vertex's bones and weights, so the silhouette follows the animation instead of
  freezing in the rest pose.
- **Draw order.** Priority -1 puts the fill before every default-priority transparent (the placeholder's name tag,
  occluders the camera fades by alpha, the hit flash, ground-drop shadows), the attack FX (8), the damage numbers (10+)
  and the HP bar (20, 21), which all stay on top of a silhouette; the player's X-ray fill and outline (120-127) come
  after it and win where the two overlap. NPC name tags and quest markers are 2D controls, always on top.
- **Never culled by occlusion.** The fills set `ignore_occlusion_culling`: occlusion culling is off today, but a fill
  exists to draw exactly where terrain hides the monster, so an occluder must never cull it.
- **Placeholder vs library.** `build()` decides `is_placeholder` afresh each time: the placeholder's own materials are
  made stencil-writing in place, so a stale flag on a rebuild would have edited the library's shared materials (a
  test pins it).
- **Who gets it.** `MonsterSystem._process` calls `update_see_through()` every frame: each live monster within its
  species' `see_through_radius_m` (12 m) of the player's feet turns it on; one that shows it keeps it up to
  `see_through_radius_m + see_through_hysteresis_m` (13 m); without a player none does. The rule is the pure
  `MonsterVisual.see_through_wanted(alive, distance, radius, hysteresis, showing)`. The fill fades over
  `see_through_fade_s` (0.2 s, `step_see_through`, run by the visual's own `advance`), and a hidden fill is invisible,
  so a monster outside the radius costs no draw call.
- **Death, flash.** `start_death_fade` drops the silhouette at once: with `transparency` above 0 the body leaves the
  opaque pass, its stencil is no longer written before the fill, and the fill would cover the fading body. The fill
  meshes are added after `_collect_geoms`, so the hit flash overlay and the death transparency never touch them.

## The player's attack (`PlayerCombat`)

| Step | Rule | Source |
|---|---|---|
| Input | `attack` pressed or held on `player.input_source` (keys J and Ctrl, pads, the bot); the left mouse button only through world clicks (see "Mouse clicks and the UI"); not while dead, input-disabled (modal windows, warps), climbing or in knockback hit-stun | Controls, PlayerController |
| Action | `CombatFormula.choose_ordinary_action(weapon, Game.rng)`: swing/stab by the weapon's odds, then a presentation with equal odds | `damage.json`, item pages |
| Lockout | `weapon.attack_duration_ms(action)`: the per-tier ladder (Sword/Hand Axe/Razor 720 ms, Wooden Club 750 ms, bare hands 810 ms at the adaptation tier 6). Holding attack repeats exactly at that rate; a press fires on the first tick the lockout allows, and a press up to `input_buffer_s` (0.15 s) before the lockout ends is kept until then | `attack_speed.json`, `combat.json bare_hands`, `player_attack.input_buffer_s` |
| Root | with `root_on_ground` (true), a ground attack plants the player until the lockout ends (`AttackLockInput`: no walking, no jumping); in the air the jump carries on | `combat.json player_attack` (classic behaviour) |
| Reach | `CombatReach.attack_box_px(weapon, presentation, facing right, level)` placed along `player.facing`, px → m by `WorldScale.actor`, `attack_box_depth_px` (60 px) deep across the facing; the monster's body is its canonical touch box, as deep as it is wide. Strict overlap on all three axes | `attack_styles.json`, `combat.json isometric_reach` |
| Target | the nearest overlapping monster (horizontal distance), ties to the one that appeared first; `basic_attack_targets` of them, 1 (each target gets its own roll when data raises it) | `attack_styles.json target_selection_order` (the order); `combat.json player_attack.basic_attack_targets` (the count, unpublished) |
| Damage | `CombatFormula.resolve_physical_hit(stats, monster.def.stats, action, Game.rng, db, {presentation})` | COMBAT.md pipeline |

A whiff still takes the attack's time. If the PlayerCombat node leaves the player mid-attack, it unlocks and hands
the wrapped input source back, so the player is never left planted. Bare hands are combat.json's adaptation: W.ATK 0,
so a landed punch deals the final-clamp minimum of 1. The swing arc, thrust spike or punch burst is built from the
presentation's own box (its near and far reach and height). With it, AttackFx lays **the hit area itself** on the
ground at the player's feet (`AttackFx.last_reach`): the canonical box from its near edge to its far edge along the
facing (swingO2's starts 5 px behind the feet) and `attack_box_depth_px` (60 px, 1.5 m) across it, the isometric
depth the hit test uses (MonsterSystem passes it to AttackFx). A pale fill with a brighter rim, it fades with the
slash. A monster is hit when its touch zone overlaps that box, so a slash that reaches a Snail a metre beside the
facing line is now seen to reach it (the Iteration Three audit: the band reached ±1.21 m for a Snail, ±1.54 m for an
Orange Mushroom, and the FX drew only a line along the facing). The reach numbers are unchanged. The footprint is a
flat box 3 cm above the feet, drawn with the depth test off (#13): before, a slope rising ahead, a step, a ledge, a
bush or the grass hid the part of it that lay below them. It reads the player's stencil (`PlayerVisual.STENCIL_REF`)
and skips the player's visible pixels, so it shows around the body and never over it; on a monster it lies as a faint
tint. On a slope it keeps the attacker's height, which is where the hit box is. The player's model
(PlayerVisual's `Model` child,
which PlayerVisual never moves) lunges `lunge_m` (0.14 m) forward and back over `lunge_s` (0.16 s). The body itself
never moves.

**The feel values** (`combat.json player_attack`: `root_on_ground`, `input_buffer_s`, `basic_attack_targets`,
`lunge_m`, `lunge_s`; each has its `<key>_reason`, except that `lunge_m` and `lunge_s` share `lunge_reason`) are read by `PlayerCombat.load_feel()` in `_ready` (MonsterSystem
wires the node to its ContentDB before adding it). There is no fallback number in code: a missing section or a
malformed value goes to `PlayerCombat.errors` and `push_error`, and that feature stays off (no root, no buffer, one
target, no lunge). "No buffer" means a press made during the lockout is not kept; a press when the attack is free
still fires at once, including a tap whose key is already up at the tick (a sub-tick J tap or world click). Before the
wave-3 review a zero buffer dropped those taps: the press only fed the buffer. The swing/thrust/punch FX and the damage-number styles stay presentation constants in their
scripts, as before.

### Mouse clicks and the UI

The left mouse button is an `attack` binding (Controls), and Godot's `Input` marks the action pressed for every press,
including one a HUD button or a window consumes. So `PlayerCombat` takes the mouse's share of the action from the
viewport's routing instead (`MouseAttackGate`):

- `MouseAttackGate.Observer`, an internal child of PlayerCombat with `PROCESS_MODE_ALWAYS`, sees every attack-button
  press and release in `_input` (never consumed), even while the scene tree is paused; PlayerCombat's own
  `_unhandled_input` sees only presses no GUI control took. Only those **world presses** can attack, and not while
  `Viewport.gui_is_dragging()` (an item dragged to a quickslot). A world press held down repeats at the lockout rate,
  like a held key.
- When the mouse took no part in a tick, the input source's own reading is used unchanged, so J, Ctrl, pads, the
  bot and `Input.action_press` behave exactly as before. When it did, the keys count through their own bindings
  (polled: `Input` cannot say which binding pressed an action), so J still attacks while the left button holds a
  window by its title.
- A press and release that both fall between two physics ticks are still seen: a quick click on a window never
  swings, a quick click on the world swings once. `Input` reports an action press on the first physics frame that
  starts after the event, which is the next frame when the event arrives during a physics frame (agile input
  flushing, or events injected from a `physics_frame` callback); a mouse event therefore keeps the mouse involved
  through the following frame (`MouseAttackGate.mouse_until_frame`). The real-game check found this.
- The pause menu's Resume button is clicked while the tree, and with it PlayerCombat, is paused, and its release
  unpauses. Before the wave-3 review the gate lived in PlayerCombat's own `_input`, so it never saw that click, and a
  click on Resume shorter than a frame (a touchpad tap) swung once on the first tick after the unpause (found in the
  real game). The always-processing observer fixes it.
- Only the keyboard player takes mouse input (the innermost source under any `AttackLockInput` is a `KeyboardInput`);
  a bot or the console's parked idle source ignores the mouse.

This replaces the earlier polling guard (`Input.is_mouse_button_pressed` plus the hovered control on the physics
tick), which swung on clicks shorter than a tick and while a UI drag crossed the world. The UI's workaround,
`MisoUiEnv.release_attack_action()` on drag start, is no longer needed (requested to the UI owner).

**The input decorator.** PlayerCombat wraps `player.input_source` in an `AttackLockInput` and re-wraps on its next tick
whenever another system swaps the source. A re-wrap always builds a new decorator (carrying the lock while a lockout
runs) and never changes the `inner` of one somebody may have saved, so the usual
`before := player.input_source; set_input_source(bot); ...; set_input_source(before)` gives the caller its own source
back (the debug sandbox, the checks scenes and the bots all do this). DebugUI's console mute walks the decorator's
`inner` and works with either order.

**Behind the player.** Basic boxes reach forward, but the Sword/Axe `swingO2` box is `[-73, -50, 5, 17]` px: it
extends 5 px behind the feet, so a monster whose body overlaps the player's back can be hit by that one swing, as in
2D. A monster whose touch box lies wholly behind that line is never selected. The tests check a monster 1 m behind
against every Sword presentation and both punches, and in a live fight.

**Misses.** Every Maple Island monster has AVOID 0, so a basic attack never misses there (`calculate_accuracy`'s EVA 0
rule). The MISS path is tested with a monster given a high avoidability.

## Contact damage

Each tick, after it moves, every live monster asks `MonsterSystem.monster_touch`. A touch is resolved when:

- the monster's touch rule allows it (`touch_rule`: `always`, or `when_provoked` for the Peace monster),
- the player is alive, not invulnerable, and MapSession is not in `WARP_OUT`, `SWAP`, `WARP_IN`, `ARRIVING` or `DEAD`,
- the touch zone (width x height x depth, at the feet, along the monster's facing) strictly overlaps the player's
  body (the `Hurtbox` capsule of `player.tscn`, radius 0.3 m, height 1.5 m).

Then `CombatFormula.resolve_monster_touch` (hit roll with the 8% rescue, guard, `1.1 + 0.4U` roll, WDEF curve, clamp)
and `ContactDamage.apply`: HP down through `StatCalculator.change_hp`, `Events.player_damaged` and `hp_changed`, and
`player.apply_knockback_from_point(monster, 1, res.invincibility_s)`. A miss or guard deals nothing, emits
`Events.player_missed_by`, shows MISS or GUARD, and still grants the canonical 1.5 s
(`player.set_invulnerable(res.invincibility_s)`, no push: `combat.json player_knockback`). The invulnerability gates
the next touch, so one touch resolves per 1.5 s however many monsters overlap.

**Death.** When HP reaches 0, `ContactDamage.announce_death`: `MapSession.enter_dead()` when the session is IDLE
(it sets DEAD, turns input off and emits `Events.player_died`, which the controller and the death UI hear);
otherwise `Events.player_died(map)` directly (MapSession enters DEAD at once or after the warp). The player node is
put into its death state too. The EXP penalty and the respawn screen are not this system's: the penalty belongs in
`MapSession.death_rules` (Phase 9 owner), the screen to the shell.

**Peace monster (Tutorial Jr. Sentinel).** MeowDB calls it "Peace" ("won't attack unless provoked", "Safe to walk
past") yet shows a 21 x 36 touch zone with Touch DMG 1-1. MisoStory reads both literally: walking into it is harmless
until the player hits it; from then on (for the rest of its life) its touch deals the normal formula damage (P.DMG 1).
Recorded in `data/misostory/monsters/1.json` `touch_rule` with `verified: false`.

## Debug console support

The console's `kill` and `spawn` ([DEBUG_TOOLS.md](DEBUG_TOOLS.md)) run through this system's own paths:

- **`Monster.debug_kill()`** (zero arguments; the console's first choice) runs the normal death path, exactly as a
  killing blow does: the canonical EXP through `Game.gain_exp`, the drop roll and `Events.loot_dropped`,
  `Events.monster_killed`, then `died`, which reports a slot monster to `MapInstanceView` (its slot respawns on the
  tick). It returns false and does nothing for a monster that is already dying (or was never set up).
- **Debug spawns** come from `make_monster` with a `SpawnSlot` of index -1 (placement "debug"; the console adds the
  metadata `debug_spawn = true`). They get full HP and `Monster.slot_index = NO_SLOT` (`has_slot()` false,
  `is_debug_spawn()` true). Nothing reports them to the view: only `MapInstanceView._spawn` links a node's `died` to
  a slot, and it never sees these nodes. So their death never frees a slot, they never respawn, and the view never
  writes their HP into the instance. They are children of the view, so `live_monsters()` includes them: the player
  can fight them, and they die like any monster (EXP, drops, `monster_killed`).

Checked end to end in the real game (`monster_game_checks.tscn`, run by `test_monster_game.gd`): `Debug.run("warp
000000040")`, `Debug.run("spawn 2 3")`, `Debug.run("kill all")` gives 33 kills (30 slot monsters + 3 debug Snails),
exactly 66 EXP (the canonical 2 per Snail; Lv 1 → 3), only items from the killed monsters' canonical tables, every drop
on the ground through the LootSystem, every slot dead, only slot monsters released by the view, and on the respawn
tick 30 monsters again with no debug spawn among them.

## Natural HP recovery (`NaturalRecovery`)

MeowDB documents natural regeneration only qualitatively ("When you're not in combat, just standing still will slowly
restore your HP"; `formulas/recovery.json` natural_regeneration, documented_values false). The rule is the project
owner's (docs/ITERATION_THREE_BRIEF.md "Natural HP Regeneration", contract C4), recorded in
`data/misostory/recovery.json` `natural_hp` with `provenance.natural_hp` authority "Project owner" and
`verified: true` against the brief:

- **10 HP per 10 s of eligible time.** Eligible activities (`natural_hp.eligible_activities`, read against
  `PlayerController.activity()`): `still` (grounded, no movement input, about zero speed) and `seated`.
- **Pause, never reset.** Every other activity (walking, jumping, attacking or casting, climbing, hit-stun, dead, a
  warp) leaves the clock where it is, so 6 s still + 5 s walking + 4 s still reach the tick. There is no
  out-of-combat delay: a monster touch only matters through what it does to the activity (a knockback is hit-stun).
- **Max HP.** HP never goes above Max HP, and while HP is full (or 0) the clock holds.
- **Saved.** The clock is `CharacterState.natural_recovery.hp_rest_s` (contract C3): the node reads it from the live
  character before each step and writes it back after, so a save keeps the paused time, Continue restores it, and a
  new or replaced character uses its own.
- **Chairs.** While seated on a chair, the chair's canonical bonus (`items/<id>.json` `setup.hp_recovery_bonus` every
  `setup.interval_s`; The Green Relaxer: 30 HP every 10 s) runs on its own clock on top (contract C5): 10 s on The
  Green Relaxer give 10 + 30 HP. When that clock starts and whether it holds at full HP are adaptations
  (`recovery.json` `chair_bonus`, verified false): it starts again at 0 at each sit and holds while HP is full.
- **MP.** No natural MP recovery, by the owner's ruling (#4, 2026-10-06; a future Magician skill will grant it). It is
  an adaptation over a source-data gap: MeowDB documents none (`recovery.json` `natural_mp`, values null, status
  `unresolved_source_gap`, `decision` #4). The brief forbids inferring one from the HP rule.

This replaces Iteration Two's adaptation (`combat.json` `natural_recovery`: a 5 s out-of-combat delay and a rest that
started over on every movement, attack or monster touch), which is gone.

- `scripts/core/character/natural_recovery_rule.gd` (`NaturalRecoveryRule`): the pure rule (`step(dt, activity, hp,
  max_hp, chair_hp, chair_interval_s)`, `rest_s`, `chair_rest_s`). A missing config key is a data error (no invented
  default). Ticks are counted with a 1 µs tolerance, so 600 physics ticks of 1/60 s are exactly 10 s.
- `scripts/actors/combat/natural_recovery.gd` (`NaturalRecovery`): added to the player by `MonsterSystem.attach_player`.
  It runs after the player and PlayerCombat (`process_physics_priority` 20), reads `player.activity()` (`dead` while
  `Game.is_character_dead()`, `other` while MapSession is not idle), adds the seated chair's bonus (`Chairs.bonus`)
  and heals through `Game.change_hp`, so the HUD sees every tick.
- Tests: `test_natural_recovery.gd` covers the brief's list: 10 continuous eligible seconds, 9.9 s, partial
  accumulation (6 + 5 + 4), movement, jump and attack pauses, resume after a pause, sitting, full HP, save/load
  (through a JSON round trip of `CharacterState` and a character swap). It also covers the chair clock, the MP gap,
  and the node on a real `PlayerController` (walking, held jump, a stub PlayerCombat attacking, a dialogue, a warp).
  `test_playtest_regen.gd` runs the `regen` scenario in the real game with real input; see
  [PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md) for the harness. Run on 2026-10-05: 29 checks PASS over 2 processes. The
  checks: 6 s still bank 6.00 s; 5 s walking leave them at 6.00 s; 4.00 s more give one tick; 5 s of held jump move
  the clock 2.25 → 2.27 s; 7 held swings move it 2.40 → 2.42 s; the clock then resumes to the next tick; X without a
  chair says so; a double-click on The Green Relaxer in the Set-up tab sits; 10 s seated give 5 → 45 HP (+10 +30);
  a move key and a warp stand up; Quit Game with 4.40 s banked; after Continue the player stands, 4.40 s are restored
  and complete the next tick, and X sits again. Since then phase 0 also sits down in the trigger of Mushroom Town's
  door and presses Up: the player stands up (`warp`) and arrives in 000000001.

## Breakables: the Wooden Box (Iteration Three, contract C8)

The Wooden Box (MeowDB breakable `0000001`) stands on its 19 canonical placements on six maps (000001000: 5,
000001010: 6, 000001011: 2, 000001012: 2, 000001013: 1, 000001014: 3). It is hit like a monster, but it is not one.

| Path | Class | Role |
|---|---|---|
| `scripts/core/breakables/breakable_rules.gd` | `BreakableRules` | pure: the canonical record (`hits_to_break` 4), the map's `reactors[]` placements (index, id, `respawn_s`), the adaptation table, the drop roll |
| `scripts/core/breakables/breakable_placement_planner.gd` | `BreakablePlacementPlanner` | pure: places each placement on walkable ground, seeded per map, the way `SpawnSlotPlanner` places spawn slots |
| `scripts/core/breakables/breakable_placement.gd` | `BreakablePlacement` | one planned placement: key `<map_id>:<index>`, breakable id, position, respawn time |
| `scripts/core/maps/map_instance_state.gd` | `MapInstanceState.breakables` | the live state: `{id, hits, respawn_at (-1 intact), respawn_s}` per placement; `hit_breakable`, `tick_breakables`; in the map's snapshot |
| `scripts/actors/breakables/breakable_system.gd` | `BreakableSystem` | the current map's boxes in the scene (`scenes/systems/breakable_system.tscn`, installed after the loot system): realizes them from the live state, lands hits, rolls drops, brings boxes back; the `boxes` console command |
| `scripts/actors/breakables/wooden_box.gd` | `WoodenBox` | presentation only: the art pack's rigged WoodenBox (`Idle`, `Hit`, `Break`; #65), or without the pack a procedural crate (lighter, faintly glowing planks); hit flash, break and respawn; group `&"miso_breakables"` with `placement_key()`, `is_broken()`, `hits_left()` |
| `data/misostory/breakables.json` | | the box's body (`box.touch_px` 30 x 30), the hit rule, the respawn clock and the placement rules (all `verified: false`) |

- **Placement.** MeowDB's `x_px` / `y_px` are 2D and not used (as for spawns). Candidates come from the map's spawn
  areas clipped to its mob region, else (towns and interiors, which have no species-tagged regions) from its floor and
  region extensions. A box keeps a clear capsule, stays out of portal triggers and keep-outs, 3.5 m from portals and
  arrivals, 1.2 m from spawn slots, 2.5 m from other boxes and outside NPC talk zones, needs 5 of 8 standing points
  around it, and must be in the gameplay camera's sight (checked against collision: a colliderless canopy can still
  hang over one). A map always gets the same boxes.
- **Hits.** `PlayerCombat.attack_started` hands the swing's canonical hit box to `MeleeQuery` over the intact boxes:
  one landed basic attack is one hit on the nearest box it overlaps, whatever monster the swing also hits. There is no
  MISS, and damage does not matter (MeowDB: "how many basic attacks it takes to break open"). Skills do not count
  (`breakables.json hit_rule`, `verified: false`, the owner's ruling in #5): Three Snails searches the live monsters
  only, so a box in its band neither takes a hit nor shields a monster behind it, and a cast with only a box in its
  band is a cast with no target.
- **Break and drops.** At `hits_to_break` the box breaks and rolls `DropRoller.roll(<breakable id>, db, rng, ctx)`
  with the character's quests in progress (contract C2): Old Wooden Board and Rusty Screw (every break, only while Pio's
  quest 1012 is in progress), Apple and Egg (2% each, the owner's table, decision D3-11); the box drops no mesos. The loot goes
  out through `Events.loot_dropped` at the box.
- **Respawn.** Exactly the placement's canonical `respawn_s` after the break, on `Game.clock` (not aligned to the
  monster spawn tick; the map pages' per-placement values, such as 90 and 180 s on 000001000, are kept over the
  breakable page's single 120 s). The box is not solid (classic reactors never block movement).
- **Model (#65).** `BreakableSystem.setup(ctx)` loads the installed art pack (`ArtPack.load_installed()`) into its
  `art` seam, and every box it realizes looks up the pack's WoodenBox by canonical breakable id (`ArtPack.BREAKABLE`,
  `0000001`), fitted by one uniform scale so its wider footprint side matches the body (`box.touch_px`) and its base
  sits on the feet. `Idle` loops while the box stands; each hit that does not break it plays `Hit` from its start
  (instead of the crate's wobble and lid), then `Idle` again; the flash and chips stay. On the breaking hit everything
  gameplay sees changes at that moment, as without the pack (broken, no attack target, the drops, the respawn clock,
  the hidden `Model` and cues); the standing model is detached from `Model` as a presentation-only node
  (`WoodenBox.breaking_rigs()`) that plays `Break` once, its flying pieces replacing the crate's plank burst (the dust
  stays), and frees itself; nothing gameplay-visible waits on the clip. A fresh model waits in the hidden `Model` and
  grows back with it at the respawn. The clips are stepped by `WoodenBox.advance()`. Without the pack, or a system
  built without `setup` (the unit tests), the procedural crate stays (`test_wooden_box_art.gd`).
- **Not saved.** Box state lives in the map instance (parked with the map in `MapStateCache`) and never in a save; a
  reload rebuilds every box intact (`test_breakables_persistence.gd`).
- **Tests:** `test_breakables_state.gd`, `test_breakables_placement.gd` (with the world: every box on real collision,
  standing room, camera sight), `test_breakables_system.gd` (hits, the nearest-box cap, breaks, gated drops through
  the real roller, respawn, the reach rim and quest marker as drawn: `WoodenBox.cues_drawn`), `test_breakables_drop_fixture.gd`, `test_breakables_persistence.gd`, `test_wooden_box_art.gd` (the pack model's
  clips across four hits and a respawn; the procedural crate without the pack); in the real game
  `bash scripts/playtest.sh test_box` (Pio's quest with real swings on Amherst's boxes, the box state across a
  real reload, Three Snails thrown at a box that keeps all its hits, then every box of the other five maps: 16 of
  the 19 broken,
  since the quest needs three of Amherst's six) and the every-quest set's 1012 chain.

## Damage numbers (`DamageNumbers`)

Billboarded `Label3D`s drawn over everything (`no_depth_test`) with a thick dark outline, sized in screen pixels from
the gameplay camera's orthographic size (glyph heights authored for a 900 px tall view, so a 12 m interior and a
19.5 m field show the same size). Dealt damage: orange-yellow, 56 px. Critical: pink-red, 70 px, over a gold
starburst. Damage taken: violet, 50 px. MISS (pale blue) and GUARD (pale gold): 40 px. Each pops in (x1.45 over
0.09 s), rises 1.6 glyphs with an ease-out and fades over the last 0.3 s of its 1.05 s life. Numbers on the same
target within 0.45 s stack a line up, and a new number never covers one still on screen (compared in the camera's
screen axes), so a monster's damage and the player's damage taken stay apart when they overlap. These are
presentation constants in the script, not gameplay values.

## Adaptations

| Where | Value | Why |
|---|---|---|
| `monsters/<id>.json speed_model` | `walk_line_no_character_bonus` | MeowDB publishes the modifier, not a monster speed formula (checked: monster pages, glossary, /formulas, the speed guide) |
| `monsters/<id>.json model`, `model_fit`, `placeholder_color`, `walk_style` | proxies fitted to the canonical sprite height (the Tutorial Jr. Sentinel's since Iteration Three); the fallback body's grey | MeowDB publishes stats, not art |
| `monsters/<id>.json capsule_*` | inside the touch zone | physics body only (kill plane) |
| `monsters/<id>.json idle_s`, `walk_s` | 0.8-3.0 s stands, 1.0-4.0 s walks | unpublished AI timings, per species |
| `monsters/_shared.json floor_band_m` | 0.5 m around the spawn height (and the spawn region's tier) | 'Stays on its floor' in 3D: no ramp to another terrace |
| `monsters/_shared.json pace_reverse_chance`, `pace_min_run_m`, `turn_jitter_deg`, `provoked_chase_s` | 0.35, 1 m, 50°, chase 4 s | 'Walks back and forth': unpublished pacing rhythm and chase, the same for every species |
| `monsters/9.json hop_floor_rule` | `spawn_floor_one_hop` | 'Can hop to a floor above or below its spawn point', counted from the spawn floor |
| `combat.json monster_knockback` (ours) | canonical stagger first, then the hit clip; 20 px push; `airborne_hit` cancel the hop | MeowDB publishes the STAGGER time, not the push or a mid-air rule |
| `monsters/_shared.json probe_ahead_m`, `ledge_tolerance_m`, `wall_probe_height_m` | 0.6 / 0.45 / 0.3 m | MAP_ARCHITECTURE §4.7.4 |
| `monsters/_shared.json model_fit` | `sprite_height` | the body you see is the body you hit |
| `monsters/_shared.json hop_max_rise_apex_fraction` | 0.9 | a hop needs clearance under the top of its arc |
| `monsters/_shared.json see_through_radius_m`, `see_through_hysteresis_m` | 12 m, kept to 13 m | presentation: past the camera's 8 m nearby radius, ~4 s of walking; farther hidden monsters stay hidden (no screen of silhouettes) |
| `monsters/_shared.json see_through_color`, `see_through_fade_s` | warm red-orange (1.0, 0.42, 0.3) at 50%, 0.2 s | presentation: the opposite of the player's blue X-ray, subtle; no popping at the radius |
| `monsters/_shared.json see_through_min_cover_m` | 0.25 m | presentation: no tinted rim where a body dips into the ground or stands in grass |
| `monsters/_shared.json fall_landing_tolerance_m` | 0.05 m | absorbs the float error between the ground query and the per-tick fall step |
| `monsters/9.json hop_*` | every 1.2-2.8 s, character base jump, 2 m max drop | MeowDB: "Can hop to a floor above or below", no rule |
| `monsters/1.json touch_rule` | `when_provoked` | the Peace gap (above) |
| `combat.json` (wave 1) | stagger, push, invincibility, bare hands, isometric depth | read through `CombatFormula` / `CombatReach` |
| `combat.json player_attack` (ours) | `root_on_ground` true, `input_buffer_s` 0.15, `basic_attack_targets` 1, `lunge_m` 0.14, `lunge_s` 0.16 | classic ground root; input forgiveness; MeowDB orders basic-attack targets but publishes no count (a classic basic attack hits one monster); the lunge is presentation of the attack's weight |

Every species file and `_shared.json` have `verified: false` and a reason for every key (`reasons` map), and the
merged view of every species explains every value it reads; `test_monster_def.gd` checks it, and
`bash scripts/validate_data.sh` validates them (0 errors).

## Testing

```bash
ISOLATE=<name> bash scripts/test.sh test_monster test_player_combat                    # 100 tests (3 world tests, the proxy-fit and the library see-through checks SKIP)
ISOLATE=<name> INCLUDE_WORLD=1 bash scripts/test.sh test_monster test_player_combat    # + real collision, the console on the island, the real game
ISOLATE=<name> bash scripts/validate_data.sh                                            # the adaptation files, _shared.json included
```

The real-game checks also run on their own, from an ISOLATE copy (windowed with `--out`, one screenshot after
`kill all`):

```bash
bash scripts/godot.sh --headless --fixed-fps 60 --path _scratch/godot_runs/<name>/game res://scenes/actors/monster_game_checks.tscn
bash scripts/godot.sh --resolution 1600x900 --disable-vsync --path _scratch/godot_runs/<name>/game \
    res://scenes/actors/monster_game_checks.tscn -- --out <abs dir>
```

| File | Covers |
|---|---|
| `test_monster_def.gd` | all 6 species build; every map species has an adaptation; stats are the canonical JSON; movement kind = canonical label; speed = the walk-line derivation (read from data) plus the documented pins; hop apex and gravity; stagger and push from the combat rules; the Peace rule; models, placeholder and capsules; every adaptation key (species files and `_shared.json`) has a reason and every reason a key, and each species' merged view explains every value; the shared values (the see-through ones too) reach every species and no species file repeats them; a species override wins with its own reason while the others keep the shared value; a missing shared table is an error, naming every value it held (`model_fit` and the see-through values included: no silent default) |
| `test_monster_shared_data.gd` | the validator's shared-table exception: the shipped `_shared.json` has no finding and `misostory/monsters` no error; an injected `_zz_test_shared` in `monsters/` and `quests/` is not matched against canonical ids but still fails the reason convention, and is still swept for references; any other basename in a domain folder must still be a canonical id |
| `test_monster_debug.gd` | `debug_kill()` takes no arguments and is the console's first choice; it runs the death path once (canonical EXP "monster:9", one `monster_killed(id, map)`, `loot_dropped` = `DropRoller.roll` with the same seed, `died` once), a second call does nothing, a bare monster is harmless; 40 debug kills drop only canonical Snail items; a slot index of -1 is no slot; INCLUDE_WORLD: on the real island with the real factory, `spawn 2 3` makes three slotless real Monsters and `kill all` gives EXP = the canonical sum of the kills, the seeded drops, every slot dead, only slot monsters released, and on the respawn tick exactly the slots come back |
| `test_monster_game.gd` | INCLUDE_WORLD: runs `monster_game_checks.tscn` (36 checks) in a child process: `main.tscn`, the console's warp/spawn/kill end to end, the see-through silhouette as the shell's own frames run it (a Snail spawned next to the player gets it, fades in and its fills draw; every live monster inside 12 m has it and every one beyond 13 m draws none; `kill nearest` drops it in the same frame and it stays off), and real mouse and key events (HUD button click and sub-frame click never swing, a world click swings once, J swings; then, injected between frames as real input arrives: a sub-frame click on the pause menu's Resume never swings, a sub-frame world click swings once) |
| `test_monster_ai.gd` | brain stand/walk timings, turning around exactly on its line (and a new line after two short runs), pacing one line and returning to it after a chase, stagger → chase → wander, sub-KB hits; region steps, discs and strays; region from a MapDefinition; on synthetic collision: turns at a ledge and never falls, turns at a wall, walks up a 0.2 m step, six monsters stay inside a region for 30 s, the Orange Mushroom hops onto a 0.6 m terrace and never off a 5 m cliff, ambient hops land, falling and landing, the push stops at a ledge |
| `test_monster_floor.gd` | the spawn floor band (flat tier, hillside region, a slot off its region's tier), a jumper's floors (one above or below its spawn floor, never two), a slot monster takes its region's tier; on synthetic collision: a walker never climbs a ramp off its floor, a walker paces back and forth on its line, the Orange Mushroom on 0.7 m terraces reaches the floor above and below and never the second, a hit mid-hop is pushed the knockback distance away from the attacker |
| `test_monster_hit_area.gd` | the swing/stab/punch footprint is the canonical box (near and far edge, swingO2 5 px behind) with the 60 px isometric depth, at the feet, for three facings; drawn with no depth test and a stencil read that skips the player (#13), at the same size; it is exactly what MeleeQuery hits; MonsterSystem gives AttackFx the depth; contact is the canonical touch zone and nothing more; INCLUDE_WORLD: every proxy (the Sentinel's included) stands on its feet, covers its touch zone along its facing and is within 1.25x of it |
| `test_player_combat_attack.gd` | lockout = the weapon's ladder time (Wooden Club, Sword, bare hands), presses during it ignored; held attack repeats at the lockout rate; the input buffer; no attack while input-disabled, in hit-stun or dead; the ground root and the air attack; nearest-in-front, never 1 m behind, one target; selection rules in isolation (every Sword presentation and both punches, depth, height, ties); the depth tolerance; bare hands deal 1 and a weapon matches CombatFormula with the same seed; whiffs; monster_hit / monster_missed and their numbers; `setup(ctx)` wiring; the scenes; removing PlayerCombat mid-attack releases the lock; a source swapped and put back by its owner is the owner's again (the decorator it saved is never re-pointed), and a re-wrap mid-attack keeps the player planted; the target count comes from `combat.json player_attack` (1) and a raised count rolls each target |
| `test_player_combat_mouse.gd` | real `Input` events routed through the viewport (a Button over the world, the keyboard player): a press on the button (held, then released) never swings; a click shorter than a tick on it neither (the old polling guard swung); a world click swings, holding repeats, a sub-tick world click swings once; J attacks with the pointer over the button and while the left button holds it; Ctrl attacks; no swing during a GUI drag; a bot-driven player ignores the mouse; `MouseAttackGate` alone: pass-through without the mouse, world presses only, drags, release ends the hold, other buttons ignored, and the frame-N+1 report of a press that arrives during a physics frame; a sub-frame click on a Resume button that unpauses the tree never swings |
| `test_player_combat_feel.gd` | `combat.json player_attack` holds every feel value with its own reason and `verified: false`; PlayerCombat reads them; edited data changes the attack (no root: walks during it); with `input_buffer_s` 0 a tap whose key is already up at the tick still attacks at once and a press during the lockout is not kept, while the shipped buffer keeps one; a missing section or malformed values are errors and leave the features off |
| `test_monster_combat.gd` | every species (Sentinel, Snail, Blue Snail, Shroom, Red Snail, Orange Mushroom) dies to Sword hits with a stagger and its HP bar, awarding exactly its own canonical EXP, one `monster_killed(id, map)` and items only from its own drop table; a seeded Sword kill of a Snail in 3-6 hits grants exactly the canonical 2 EXP (`exp_gained` "monster:2"), one `monster_killed("2", map)`; `loot_dropped` = `DropRoller.roll` with the same seed, at the feet, items from the canonical table, none for an empty roll; the kill is recorded and the slot respawns exactly at the 7.56 s tick, not before; survivor HP through release/realize; an already-live map is re-realized as monsters; contact damage = `resolve_monster_touch(...).final` with the same seed, events, the canonical 1.5 s gate, a second touch only after it; a miss (no damage, no push, MISS); a guard; the Peace rule; HP 0 → `player_died` and a dead player; no touch during a warp; touch geometry edges |
| `test_monster_see_through.gd` | the rule (inside, at and past the radius, the hysteresis, dead, zero radius); the values reach every species from `_shared.json` (radius at least the camera's nearby radius; a malformed colour is an error); the fill: one shared ShaderMaterial, `stencil_mode read, write, compare_greater, 36`, no depth test, both faces, priority below labels, numbers and the HP bar, and `STENCIL_REF` below `PlayerVisual.STENCIL_REF`; lit and ink surfaces write the stencil on copies shared between monsters while the originals stay untouched; the fill mesh is one surface holding every surface's triangles (merged once per source mesh, a one-surface mesh used as it is) and is never occlusion-culled; with the world export, every surface of the real Snail proxy (ink shells included) writes the stencil, each fill is one surface over the whole mesh, and the library stays untouched; the placeholder in place (no fill under its tag); a visual rebuilt from the placeholder to a library model never edits the library's shared material; the fade in and out (alpha follows, hidden when off) through `step_see_through` and `advance`; death drops it at once and ignores requests, and the flash and death fade never touch the fill; `MonsterSystem.update_see_through` by distance (near, edge, past, far), the player walking in and back (hysteresis), a killed monster, no player |
| `test_monster_rigs.gd` | on a stand-in pack written to `user://` (runs with or without the real pack): a species in the pack is built from its model at the canonical sprite height; Idle, Walk, Attack (from a real touch through `MonsterSystem`), Hit (over the canonical hit time, never cut short by a touch) and Death (final) follow the state; the fills share the skin and skeleton and keep bones and weights; flash, HP bar, spawn scale-in and the death fade (opaque during the clip, `faded_out` at the die time) on the skinned meshes; no bob, squash, flinch or sink under a rig while the fallback keeps them; a species the pack lacks keeps the old path. With the real pack (SKIP without): all six species map to their models at the sprite height, every state selects its clip (Idle and Walk loop, the rest once), every surface writes the stencil and every fill is skinned to the rig |
| `test_monster_fx.gd` | number styles, stacking, rise and expiry; nearby targets do not overlap; FX reach the canonical box edges; the proxy fit (the Tutorial Jr. Sentinel's too) and the named fallback body without a library (never called a placeholder); the HP bar and the death fade over the canonical time |
| `test_monster_world.gd` | INCLUDE_WORLD: the island built synchronously, the factory installed on the world's view, maps 030/040/050/1002/1020 realized to capacity with real monsters (all six species), 12 s of stepping each: no falls, no recoveries, inside the mob region and the footprint, on walkable ground, every species wanders, Orange Mushrooms hop; no portal trigger of those maps reaches into the mob region and no monster ever stands in a trigger |
| `test_spawn_placement.gd` | slots keep `slot_npc_clearance_m` from NPCs; a 16 m² region keeps 8 m² per slot and spills the rest, one species' overflow never displaces another species from its own region, a species shares its regions by weight; authored exclusions are no room and no slot lands in them; INCLUDE_WORLD: on the island every slot is clear of every NPC and exclusion, no region crowded past the map's own density; a respawn is held back while the player stands on its slot and appears once the player leaves (`respawn_waited` inside `monster_spawned`) |
| `test_spawn_model.gd` | (spawns) the tick, cooldown and capacity rules; the mob rate is ignored by the shipped switch, and turned on (`presentation.json map_mob_rate.apply`) it multiplies capacity, capped at the spawn points, in `MapInstanceState` too |
| `tools/sources/test/check_spawn_captures.test.mjs` | `node --test tools/sources/test/`: the 51 canonical spawn rows equal the dated captures; a changed count, mob rate or missing row is reported |

### Sandbox

Run from an ISOLATE copy (refresh it with a `test.sh` run first):

```bash
cd _scratch/godot_runs/<name>/game
bash ../../../../scripts/godot.sh --path . --resolution 1600x900 --disable-vsync res://scenes/sandbox/monster_sandbox.tscn -- --bot --quit --seconds 30 --shots <dir>
bash ../../../../scripts/godot.sh --path . --resolution 1600x900 --disable-vsync res://scenes/sandbox/monster_sandbox.tscn -- --map 000001020 --bot --heal
bash ../../../../scripts/godot.sh --headless --fixed-fps 60 --path . res://scenes/sandbox/monster_sandbox.tscn -- --bot --quit --seconds 25
```

Options: `--map <id>`, `--weapon <id|none>`, `--bot`, `--standoff <m>`, `--heal` (a labelled sandbox cheat),
`--shots <dir>`, `--seconds <s>`, `--quit`. Keyboard play otherwise (WASD, Space, J/Ctrl, F3, K kills all).

Results (2026-10-04, Sword, STR 13):

- Headless, Snail Hunting Ground I, 25 s: 18 attacks, 18 hits, 2 criticals, 6 kills, 12 EXP, the map back to 30
  live monsters through respawns.
- Windowed, Field East of Amherst (Snail, Blue Snail, Red Snail, Orange Mushroom), 40 s: 43 attacks, 40 hits,
  6 kills, 44 EXP and a level-up to 2; 10 Orange Mushroom touches for 222 damage (about 22 each, MeowDB's estimate
  is 18-25).

Screenshots (`_scratch/monster_shots/`): the numbers read clearly at the 19.5 m field zoom; a critical shows pink
digits over the starburst; damage taken stacks above damage dealt when an Orange Mushroom overlaps the player; the
swing crescent is visible around the player; the HP bar shows over a damaged monster, filled from the left; a killed
Snail fades out; the Tutorial Jr. Sentinel placeholder of that time carried a "(placeholder)" tag (Iteration Three
replaced it with its stone proxy and dropped the word). A Snail's shell is a flat
disc, so a snail facing the camera reads as a thin vertical stripe (proxy art). On 000000030 one Tutorial Jr. Sentinel
slot sits against the mushroom house, its 1.7 m body partly inside the roof: the slot planner's clearance capsule is
0.8 m tall (WORLD_RUNTIME, presentation.json spawns.clearance_height_m). The sandbox bot walks in straight lines and
cannot path around buildings, so it made no attack on that map.

## Verified in the real game (Iteration Three)

`test_b_combat` (headless, seeds 1, 2 and 3 on the rebuilt export: 53 checks, 0 failed each) and the new
`test_b_population` (79 checks, 0 failed):

- **Reach probes.** Each probe is classified by the identity of what the attack hit, and every tap waits for a front
  with no other monster in reach of any Sword presentation. The probe Snail 0.75-1.4 m behind and the one 3.2-3.9 m in
  front were never hit (6 + 6 whiffs per seed). The Iteration Three baseline failure ("2 behind hits") was a bystander
  Snail 2.1 m in front of the player, counted because the probe recorded "something was hit".
- **Stagger** 0.600 s on every staggered monster (137-140 tracks per seed), the oracle reading the canonical STAGGER
  field before the hit clip. **Mid-hop hits:** 1-6 per seed landed on an airborne Orange Mushroom; every one staggered
  and was pushed away from the attacker, never toward it (now a check, was WARN #43).
- **Visuals:** all six species show their proxy (the Tutorial Jr. Sentinel's included) on their feet, within 1.35x of
  their touch zone in the model's own frame (now a check).
- **Respawns** stay on the 7.56 s tick (49-56 refills per seed, none off-tick); a respawn the view held back because the
  bot stood on its slot is listed apart (`MapInstanceView.respawn_waited`).
- **Population, all 15 hunting maps:** one slot per MeowDB spawn point with the canonical species counts (577 in all),
  the solo capacity live after the first fill (426 in all) and again after `kill all` on the respawn ticks; every
  slot placed (strict, relaxed or pinned) clear of every arrival (4 m) and NPC (2.5 m; Sam is now 4.3 m from the
  nearest 000000040 slot); after 8 s of wandering every grounded monster stands on its floor inside its mob region; no
  respawn realized within 2 m of the player; and on 000000040 a respawn of the slot the player stood on waited
  (`MapInstanceView.deferred_respawns` counts each held-back respawn once) and appeared once the player left.
- Known in the harness: in seed 2 the bot, standing still among Orange Mushrooms for the scenario's final 14 s, dies at
  the very end (pacing monsters keep walking over a player who stands on their line); its open knockback track now
  counts as interrupted instead of lost.
- **The bot after floor-bound walkers** (review). A monster on a terrace above or below the player no longer walks
  down to it, so `test_b_combat` picks fight, touch-probe and reach-probe targets on the player's own tier (within
  1.5 / 0.8 / 0.3 m of its feet) and walks to another tier over the routes only when none is left on its own; a reach
  probe taps only on level ground and the check fails on one that does not (a seed-2 run had probed all 18 from 9 m
  below a terrace and passed on height whiffs); an attack call or a walk that leaves the player where it was hops out
  with move + jump (`wedges` in the samples) and replans over the grid. Before that, two runs failed on a wedge: the
  bot stood still for 200-250 s at 000000040 local (8.0, 9.2, -37.4) (seed 2) and at the foot of a 0.83 m lip on
  000000050 (54.2, 2.2, -17.3) (seed 3: walking into it moves 0.01 m, a jump clears it), and one seed-2 run left the
  bot on the low ground under every live Snail. Seeds 1, 2 and 3 then passed (53 checks, 0 failed each; no wedge).

## Verified in the real game (wave-2 review)

The real main scene (`scenes/main.tscn`: title, creation, loading, the shell's `SubsystemInstaller`) was driven
windowed with a scripted bot and the debug console's `warp` (39 checks, no script errors):

- the installer installs `MonsterSystem` first; the factory sits on the world's view; the player gets one
  `PlayerCombat` and an `AttackLockInput`; the numbers use the rig's `Camera3D`
- 000000040 and 000001020 fill to capacity with real `Monster`s (30 and 28); the bot's kills award exactly the
  canonical EXP sum; every kill announces loot and the loot system puts nodes on the ground; the maps refill after the
  7.56 s tick; the Orange Mushrooms hop (76 in 25 s) and nothing leaves its region or falls
- standing in a Snail: touches at 0.03, 1.55, 3.07, 4.58 s (the canonical 1.5 s gate) for 3-4 damage (MeowDB's
  estimate at 0 WDEF: 3-4); at 1 HP a touch kills: `Events.player_died` exactly once, MapSession `DEAD`, the shell's
  notice; no touches and no attacks while dead; OK respawns
- the unprovoked Tutorial Jr. Sentinel is harmless; one hit provokes it and its touch then hurts
- a modal blocks attacks; a left click on the world attacks, on a HUD button it does not; J attacks
- a bot swap put back by its owner returns the keyboard (this failed before the review: the re-wrap re-pointed the
  saved decorator at the bot)

**Wave-3 fixes, checked again in the real game** (`monster_game_checks.tscn`, 26 checks, headless in
`test_monster_game.gd` and windowed at 1600x900, no script errors): the console's `spawn 2 3` and `kill all` end to end
(see "Debug console support"); a click on the HUD's Item button opens the inventory and never swings, a click shorter
than a frame on it closes it and never swings, a click on the world swings once, J swings. The first run of these
checks found the frame-N+1 report of a press that arrives during a physics frame (a sub-frame click on the button
swung once); `MouseAttackGate.mouse_until_frame` fixed it. The windowed screenshot after `kill all` shows Level 3, the
"+2" EXP lines in the log and the drops on the ground where the debug Snails died.

**Wave-3 review** (a separate driver on `main.tscn`, headless and windowed at 1600x900 with `--disable-vsync`, events
injected on process frames, the normal input path; 29 checks, no script errors after the fixes): dragging the inventory
by its title over the world, a click on its body, an item dragged from a slot and released over the world (a real GUI
drag), a sub-frame click on its close button, a click while the console is open: none swings. A sub-frame world click
swings once; a world press held 1.5 s swings 3 times with the Sword (720 ms) and releasing it over a HUD button adds
nothing; J attacks on the first tick after the console closes. The review found that a sub-frame click on the pause
menu's Resume swung once (see "Mouse clicks and the UI"); fixed, and now one of the checks scene's checks (36 today). Debug
side: `spawn 9 2` and `spawn 2 2` on 000000040 (the Orange Mushrooms hop there too), a debug Snail fought to death
with J (EXP = the canonical sum of what died, the slot state and `view.nodes` untouched), three `kill nearest` in one
frame kill three distinct monsters (never a fading one twice), debug spawns are gone after a warp away and back and
after `reload`, and a second `kill all` reports no live monsters.

### See-through silhouette in the real game (2026-10-04)

A scratch driver (`_scratch/monsters-xray/driver/xray.gd`, run by `_scratch/monsters-xray/run.sh` from the ISOLATE
copy, windowed at 1600 x 900 with `--disable-vsync`) starts `main.tscn` with a new character, turns `god on`, warps to
each map and looks for a live monster that terrain hides: physics rays from 30, 60 and 90% of its height toward the
camera (walkable, blocking, scenery), going on through prop and tree hulls (`*_hull*`), which the camera can dither.
It then stands the player on a spawn slot 2.5-10 m from it that terrain does not hide (`goto slot`), waits 0.9 s,
pauses the tree and renders the frame as the game left it, then with every silhouette off, without the monster,
without the player, and with only this monster's silhouette. Pixel counts sample every other pixel on both axes.

| Map | Monster, cover | Monster visible without it | Its silhouette adds | Changed on visible player pixels |
|---|---|---|---|---|
| 000000041 Snail Hunting Ground II | Blue Snail behind a raised terrace (`Walls`), 4.8 m away | 0 px | 430 px | 0 |
| 000000041 Snail Hunting Ground II | Blue Snail half behind a terrace edge (`Ground`), 6.2 m | 165 px | 353 px | 0 |
| 000000042 Snail Hunting Ground III | Blue Snail behind the corner of a cliff wall (`Walls`), 5.7 m | 121 px | 282 px | 0 |
| 000001002 Dangerous Forest | Orange Mushroom behind a boulder (`Walls`, `Ground`), 3.6 m | 18 px | 2,209 px | 0 |

These are the shipped shader (with the minimum cover); the runs before it found the same kind of cases (a Blue Snail
wholly behind a Snail Hunting Ground III cliff wall: 0 px visible, 455 px added). In every capture the real system had
turned the monster's silhouette on by itself (`is_see_through()` true, amount 1), and 2-11 of the map's 25-33 live
monsters had it (the 12 m radius). The screenshots (`_scratch/monsters-xray/shots7/` and `shots8/`, viewed as sheets
of off/on crops) show a flat red-orange snail or mushroom shape over the terrace, the cliff face and the boulder,
completing a half-hidden body at the terrace edge and the cliff corner, with nothing in the frames without it, and no
tint under the visible snails standing on the slopes around. Terrain hides monsters rarely: in the first 10 s after
arrival (20 samples of every live monster per run) 0-4.4% of the samples on Snail Hunting Ground II, 0-0.5% on III
and 1.6-2.6% in Dangerous Forest; the captures are monsters that wandered behind the terraces' walls later.

- **Behind the player** (Snail Hunting Ground I, a Snail moved 0.7 m behind the player on a slope by the arrival): of
  its 400 px silhouette 341 are hidden by the player, and the silhouette changes no pixel at all in the 400 x 300 box
  around the player. A negative control swaps in a naive fill (`compare_not_equal 36`, which only skips the monster's
  own pixels): it paints 356 px over the player. Before the minimum cover the real fill drew a 27 px line along the
  snail's underside on that slope (the body dipping into the ground; seen in a zoomed crop); with it, 0.
- **Cost** (Snail Hunting Ground II, 33 live monsters, the tree paused, 120 frames each): `update_see_through()` takes
  34 µs per frame. With the 7 monsters of the radius on, 880 draw calls instead of 868 and 0.790 ms instead of
  0.740 ms of GPU time (the depth read included; without the minimum cover the difference was 0.02 ms); with all 33
  on, the same 880 calls and 0.791 ms, because fills off screen are culled. So all live monsters would be cheap too;
  the radius is a readability choice (no screen of silhouettes on lower terraces). Before the fill meshes were merged
  into one surface, 8 monsters cost 65 extra draw calls (one per material).

**Review (2026-10-04, `_scratch/review-monsters-xray/driver/rv.gd`, same setup).** To see exactly which pixels a
silhouette draws, the measurement turns one monster's tint opaque magenta and counts magenta pixels in its screen
box (two identical frames differ by 0 px, so nothing else moves).

- *Who hides what.* Of 237 samples of monsters within 13 m (000000040/41/42/50, 000001000/02/03/20, the player at
  4-8 spawn slots per map) that no collision ray finds hidden, 59 still get silhouette pixels, and every one looked at
  is really covered by geometry without collision: Dangerous Forest's boulders (a Red Snail, 2,483 px, almost wholly
  hidden), A Split Road's sunflowers (a Shroom, 804 px over the flower heads), and the dots a camera-dithered canopy
  keeps over a monster in its hole. So collision rays undercount what the silhouette is for; the behaviour is the
  designed one.
- *Feet.* No rim seen: in 11 of 152 samples the silhouette pixels sit only in the bottom fifth of a visible body
  (1-186 px), and the three largest (186, 84, 42 px on Snail Hunting Ground III, The Field West of Amherst, Mushroom
  Garden) are flower patches standing in front of the feet, not the ground the body dips into.
- *Dithered trees.* An Orange Mushroom 2.3 m from the player behind an autumn canopy in In a Small Forest (inside the
  camera's hole): the canopy's remaining dots over the cap take the tint (870 px), which reads as the same monster,
  slightly warmer; nothing outside the body changes.
- *NPCs.* A Snail placed 0.8 m behind Robin (Snail Hunting Ground I) paints 1,265 px of silhouette over him. In normal
  play it is rare: with the player standing beside each NPC of 000000030 (Todd, Peter: Tutorial Jr. Sentinels),
  000000040 (Robin, Sam) and 000000050 (Maria, Mai) for 240 s of game time each, monsters came within 0.4-1.6 m of
  Todd, Sam and Mai, but a silhouetted monster stood behind an NPC on screen in 1 of 1,800 samples (Maria).
- *Hit flash and death* with the silhouette on behind a terrace (a Blue Snail, 1,814 px): during the flash the
  silhouette is still there (1,884 px, the body tilted by its flinch), and `die()` hides every fill in the same frame.
- *All 25 maps*: warp, `spawn 2 3`, `kill all`, `reload` on every monster map, then save and load: no error.

## Known limits and follow-ups

- **Requested (UI):** `MisoUiEnv.release_attack_action()` (called when an item or a window drag starts) is no longer
  needed: PlayerCombat ignores mouse presses a GUI control consumed and presses during a GUI drag. It also releases a
  held J or Ctrl, so removing it is better for the keys too.
- Ranged weapons always use their close-range branch (no projectiles, no ranged search bands); no crouched attack.
  No Maple Island creation weapon is ranged.
- The death EXP penalty (`Progression.apply_death_penalty`) is not applied here: the game shell applies it at the
  moment of death through `MapSession.death_commit` (GAME_SHELL.md "Death and respawn (Phase 9)").
- Monsters keep moving while a modal dialogue is open (as in classic); they stop only with the scene tree's pause.
- Trees between the camera and a fight fade (OcclusionFader) but can still hide the player (camera system).
- **See-through silhouette.** It is a flat tint: the hidden monster's shape, not its colours or its species. A cover
  nearer than 0.25 m along the view (`see_through_min_cover_m`) never shows it, so the bottom of a body right behind
  a low ledge it touches stays hidden, like its own contact with the ground; taller foliage (a flower patch, a bush)
  further in front does tint (flower patches at a visible monster's feet, measured in the review above). It covers
  NPCs, loot and anything else that writes no stencil: rare in play (1 of 1,800 samples beside the NPCs of
  000000030/40/50), but a monster behind Todd, Sam, Maria or Mai paints over them. Its stencil value (36) must stay
  below the player's (37); a new system that writes the stencil needs a value of at least 36, or monster silhouettes
  will paint over it. Monsters beyond 13 m that terrain hides stay hidden (a readability choice, not a cost one: see
  the review).
- **Requested (NPCs):** if an NPC should never show a monster silhouette over it, the NPC's model surfaces write a
  stencil value of at least 36 and other than 37 (say 38), as `MonsterVisual.with_stencil` does with 36: the
  monster fill (`compare_greater 36`) then skips the NPC, and the player's X-ray (`!= 37`) is unchanged.
- `MonsterVisual`'s stencil copies and merged fill meshes are cached in static dictionaries keyed by the library's
  material and mesh resources, which they keep alive: each fresh load of `_library.glb` (a new world) adds a set and
  the old one is never released (a few proxy meshes and materials per load).
- **Requested (camera, PLAYER_AND_CAMERA.md):** `PlayerVisual.STENCIL_REF`'s comment ("any value no other system
  uses") and the known issue "Monsters have no X-ray or outline of their own" are stale: monsters write 36, and
  their silhouette relies on the player's reference staying above it.
- The mouse split polls the attack action's key bindings while the mouse is involved, so a key tap shorter than a
  physics tick in the same tick as a UI click is lost (both land between the same two ticks). Keys alone are read
  exactly as before.
- **Resolved:** the Tutorial Jr. Sentinel slot under the 000000030 mushroom house's cap (Iteration Two's request to
  the world runtime). `maps/000000030.json spawn_keepouts` keeps slots out of the cap's disc and the planner's
  clearance capsule is as tall as the species (`SpawnSlotPlanner.clearance_height`); `test_spawn_slots.gd`
  `test_no_sentinel_under_the_mushroom_house_cap` pins it.
- The same probe found 22 of 426 monsters briefly overlapping blocking geometry in 20 s of wandering on the 15 maps
  (mostly Orange Mushroom hops and wide bodies brushing walls; the wall rays sit at the capsule radius, the proxies
  are wider), one Orange Mushroom spawned overlapping on 000001002 and one ended inside on 000001021. Small and
  transient; a wider ray fan or a body-overlap check before a step would remove it.
- The player blinks while invulnerable (PlayerVisual), so right after a touch the violet number can float over a
  frame where the player model is hidden. That is the classic look, not a lost player.
- No audio.
