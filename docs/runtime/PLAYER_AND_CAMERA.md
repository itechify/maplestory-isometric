# Player controller and gameplay camera (Iterations Two and Three)

This system covers the brief's Phase 3 (controls, isometric movement, jumping, camera) and the movement side of
Phase 4 (step-up, slopes, clutter). It also implements MAP_ARCHITECTURE §4.11 (camera bounds) and the §4.13 InputSource
the traversal bot drives. All feel numbers live in `game/data/misostory/movement.json` and `camera.json`, and every
key there has a reason. Canonical numbers are read from MeowDB data through `ContentDB` and converted only through
`WorldScale`.

## Files

| Path | Role |
|---|---|
| `scripts/actors/player/player_controller.gd` | `PlayerController` (CharacterBody3D): movement, jump, step-up, climbing, hit reactions, death, teleport, SafeGround, `activity()`, sitting |
| `scripts/actors/player/movement_model.gd` | `MovementModel` (pure): every number the controller moves by, in m and s |
| `scripts/actors/player/input_source.gd`, `keyboard_input.gd`, `bot_input.gd` | `InputSource` and its two implementations |
| `scripts/actors/player/climbable_def.gd` | `ClimbableDef`: one sidecar `climbables[]` entry |
| `scripts/actors/player/safe_ground.gd` | `SafeGround`: the last safe standing point (§4.6, §4.9) |
| `scripts/actors/player/route_bot.gd` | `RouteBot`: walks sidecar routes through a BotInput (the L2 bot seed) |
| `scripts/actors/player/player_visual.gd` | `PlayerVisual`: model (the exported Player_Proxy), blob shadow, X-ray fill and see-through outline, facing, bob, blink, poses including the sit pose and its chair prop (presentation only) |
| `scripts/core/items/chairs.gd` | `Chairs` (pure): what a chair is, its canonical bonus, using one (sit / stand) and the sit key; reaches the seated state through the player |
| `scripts/actors/player/player_test_world.gd` | `PlayerTestWorld`: synchronous physics worlds for tests and the sandbox |
| `scripts/actors/camera/camera_rig.gd` | `CameraRig`: the gameplay camera |
| `scripts/actors/camera/camera_math.gd` | `CameraMath` (pure): ground axes, view extents, bounds clamp, dead zone |
| `scripts/actors/camera/occlusion_fader.gd` | `OcclusionFader`: selects and dithers out the trees, buildings and tall props that hide the player or a nearby monster (M3) |
| `scripts/actors/camera/occlusion_math.gd` | `OcclusionMath` (pure): occluder rules, fading units, body and disc samples, view-frame boxes, dither holes |
| `scripts/actors/camera/occluder_dither.gd` | `OccluderDither`: dithered see-through stand-ins of the world's occluder materials (a generated spatial shader) |
| `scenes/actors/player.tscn`, `scenes/actors/camera_rig.tscn` | the two scenes wave 2 instances |
| `scenes/sandbox/player_sandbox.tscn` (+ `.gd`) | the sandbox: one map chunk, the player, the camera, a bot, screenshots, and a world smoke test |
| `data/misostory/movement.json`, `data/misostory/camera.json` | adaptation tables |

## Player controller

### Body model

The body is a "floating capsule". The collision capsule (radius 0.3 m) covers the body from `step_up_m` (0.45 m)
up to `body_height_m` (1.5 m). The feet are a disc of 9 downward rays: one at the centre and 8 on a 0.15 m circle
(`foot_radius_m`). The player stands on the highest walkable hit (normal within `floor_max_angle_deg`, 38°) under the
disc. The consequences:

- Stairs, ledges, roots and stones up to 0.45 m are mounted as soon as the front of the feet reaches them. The capsule
  never touches them, so nothing below step height can snag the player. Small clutter mostly has no collision anyway
  (the exporter drops foliage and props under 0.45 m).
- Anything that reaches the capsule while the player is grounded is a vertical wall. Steep contacts are flattened to
  horizontal normals before sliding, so the capsule never rides up a 0.6 m wall or a 45° slope.
- The player walks off an edge once the centre is 0.15 m past it, as in classic, where you drop when your feet leave
  the foothold. Drops of up to `snap_down_m` (0.45 m) are stepped down; anything deeper is a fall.
- Landing uses the same rays with the same 0.45 m band, so the highest ledge a jump reaches is apex + 0.45 m (1.35 m
  at Jump 100). MAP_ARCHITECTURE §4.4 already budgets `jump_apex_m_at_cap + step_up_m` for the one-way ledge.
  Measured (review probe): a standing jump against the face lands on ledges up to 1.35 m; a running jump does too
  from up to 1.2 m before the face.
- Only the feet land. A walkable contact on the capsule alone (its rounded bottom touching a ledge edge while no feet
  ray is over the ledge) is not a landing: the capsule slides off the edge, as classic drops you when your feet are
  past the foothold. (An earlier version counted that contact as ground, lifting the body ~0.5 m onto the ledge for
  one tick before it fell.)
- Wedged: a capsule that rests without falling and with no walkable ground under the feet (a V crevice between faces
  steeper than 38°) becomes ground after 6 ticks, in place. It stays latched while a short downward test move of the
  capsule still collides, so the player can jump out without the state flickering between ground and air (an earlier
  version emitted `landed` about 7 times a second there). `is_on_floor()` stays false while wedged, and a wedge is
  never recorded as SafeGround.
- A 1.5 m `Hurtbox` Area3D (in `player.tscn`, player layer) is the volume monsters touch.

The controller is kinematic and advances one tick at a time through `step(delta)`. It uses `move_and_collide` for the
capsule and `intersect_ray` for the feet. `_physics_process` calls `step()`, and tests and the bot call it directly.
`move_and_slide()` cannot be used: it reads the engine's frame delta, which is 0 inside a synchronous test.

`is_on_floor()` is a native method that other systems call (GateMonitor, MapSession ARRIVING, FallRecovery,
world_checks). It is kept truthful in-game: after each physics tick a 2 cm sphere placed over the supporting feet ray
replaces the capsule for one short straight-down `move_and_slide()`, then the shapes, position and velocity are
restored. Measured mismatch rate: 1 tick in 9,266 on Snail Hunting Ground I, and 1 in 689 in the full-world warp
smoke test. Both were a ray landing exactly on a 45° stair chamfer. Use `is_grounded()` in new code.

### Movement numbers

| Quantity | Value at base stats | Source |
|---|---|---|
| Walk speed | 150 px/s × `WorldScale.h` = **3.0 m/s** | canonical `formulas/movement.walk_speed` (base 150 at Speed 100, cap 200 at 140) |
| Speed stat | total from `StatCalculator.snapshot(...)["speed"]`, clamped to 140 | canonical caps; `refresh_stats()` on `Events.stats_changed` |
| Climb speed | 120 px/s × `WorldScale.v` = **1.40 m/s** | canonical `climb_speed` ("Speed + 20 px/s"). Climbing is vertical motion, so it uses the vertical scale |
| Jump apex | 77 px × `WorldScale.v` = **0.90 m** (Jump 120: 111 px = 1.30 m) | canonical `jump_height_px_by_jump`, interpolated |
| Gravity | 2000 px/s² × `WorldScale.v` = **23.4 m/s²** | canonical `knockback_airtime.gravity_px_per_s2` (reason in movement.json `reasons.gravity`) |
| Jump launch | √(2 g apex) = 6.49 m/s, airtime 0.555 s | derived |
| Knockback launch | 270 px/s × `WorldScale.v` = 3.16 m/s; rise 0.21 m; airtime 0.27 s | canonical `knockback_airtime` |
| Knockback push | 2.2 m/s horizontal | adaptation (MeowDB gap) |
| Post-hit invincibility | 1.5 s | `combat.json post_hit_invincibility.override_s` when set, else canonical `accuracy.after_hit.post_hit_invincibility_s` |

The walk formula's "+20" is not a published field. `MovementModel` takes the line through MeowDB's two published
points (Speed 100 → 150 px/s, Speed 140 → 200 px/s), which is the formula itself, and reuses its offset for the climb
speed. The base and cap stats (100, 140, 120) are read from the canonical record only; a missing key is reported and
reads as 0 rather than falling back to a number restated in code. MeowDB's jump table starts at Jump 100, so a total
Jump below 100 (possible in `StatCalculator`, not on Maple Island) uses the Jump 100 apex. The 2000 px/s² gravity and the canonical 77 px apex imply a 555 px/s launch. The same rule (launch speed
proportional to Jump) reproduces every row of MeowDB's jump table, so jumps and knockbacks share one arc. Vertical
motion is integrated exactly (the trapezoid rule for constant acceleration), so the apex is hit within a millimetre
at 60 Hz.

### Feel (adaptations, all in movement.json)

| Key | Value | Why |
|---|---|---|
| `ground_accel_mps2` / `ground_decel_mps2` | 60 / 90 | full speed in 3 ticks, stop in 2: immediate without a one-frame snap |
| `air_accel_mps2` | 6 | momentum is kept with no input. Steering can shorten a running jump but not turn it around (a full reversal takes 1 s); a standing jump drifts up to ~0.9 m |
| `coyote_time_s` | 0.08 | a jump pressed up to 5 ticks after walking off an edge still fires, because edges are hard to judge in isometric |
| `jump_buffer_s` | 0.12 | a jump pressed slightly before landing fires on landing |
| `hold_to_rejump` | true | classic behaviour: holding the jump key keeps hopping |
| `max_fall_speed_mps` | 12 | readable falls; stays above MeowDB's 500 px/s fall-damage threshold |
| `step_up_m`, `floor_max_angle_deg` | 0.45, 38 | Iteration One's traversal MAX_STEP and MAX_SLOPE_DEG, which every route was validated against |
| `foot_radius_m` | 0.15 | the feet disc (above) |
| `jump_apex_m_at_cap` | 1.2987 | derived (111 px × 0.0117) for MAP_ARCHITECTURE §4.4; a test pins it to the canonical table |
| `climb_*` | see file | grab radii, standoff, top-exit threshold, jump-off hop (half apex), re-grab cooldown |
| `knockback_*` | 2.2 m/s, 0.6 s | horizontal push (MeowDB gap); hit-stun lasts until landing, at most 0.6 s |
| `visual_step_smoothing_s`, `facing_turn_rate_deg_per_s` | 0.08, 1440 | presentation only |

Movement is 8-directional and relative to the camera: W walks along the camera's ground-projected forward axis
(Godot +X −Z), and D along its right axis (+X +Z). Diagonals are normalized. Speed on slopes is constant
horizontally. Logical `facing` is instant; the model turns at 1440°/s.

### Climbing

Climbables come from sidecar `climbables[]` (`ClimbableDef.from_sidecar`, or `player.add_climbables_from_sidecar(arr)`).
The climb line runs vertically through `bottom`/`top`, `facing_xz` points into the wall, and the climber hangs 0.3 m in
front of the line.

- **Grab:** Up (`portal_enter`) or `interact` within 0.8 m of the line; Down (`climb_down`) or `interact` within 0.9 m
  of `top_exit` at the top; or Up held while airborne (catching a rope mid-jump, as in classic). Descend-only ropes
  cannot be grabbed from the ground.
- **Climb:** W/S or the Up/Down arrows, at the canonical climb speed. Descend-only ropes ignore "up".
- **Exit:** at the top onto `top_exit`; at the bottom onto the foot ground, or a fall when `foot_ground` is null (ropes
  over a pit); or jump plus a direction that is not into the wall (a half-apex hop; jump alone does nothing, as in
  classic). Knockback and death also release the climbable.

### Activity (contract C4)

`activity()` says what the player is doing, for natural HP recovery (`NaturalRecovery`, see
[MONSTERS_AND_COMBAT_RUNTIME.md](MONSTERS_AND_COMBAT_RUNTIME.md)), skills, the HUD and playtests. One of, checked in
this order:

| Activity | When |
|---|---|
| `&"other"` | no movement model, not in the tree, or not processing (frozen for a warp, the tree paused) |
| `&"dead"` | after `die()` until `revive()` |
| `&"seated"` | sitting on a chair (below). On the one tick an attack or cast starts from the chair (before the player stands up), `&"attacking"` |
| `&"hitstun"` | a knockback in flight |
| `&"climbing"` | on a ladder, rope or vine |
| `&"attacking"` | `PlayerCombat.is_attacking()`: a basic attack's lockout, or a skill cast's (the skills package makes it true while casting). A planted ground attack has speed 0 but is not standing still |
| `&"jumping"` | any airborne state (a jump, a fall), and the landing ticks between the hops of a held jump (`hold_to_rejump`) |
| `&"walking"` | movement input this tick (also pushing into a wall), or horizontal speed above `STILL_SPEED` (0.05 m/s; the 2 deceleration ticks after a key is released) |
| `&"still"` | grounded, no movement input and about zero horizontal speed. Input is read after gating, so a player in a dialogue (input disabled) with a key held is standing still |

Natural HP recovery runs only while `still` or `seated` (`data/misostory/recovery.json` natural_hp, the project
owner's rule); every other activity pauses its clock.

### Sitting and chairs (contract C5)

A chair is a Setup item with canonical setup data (`ItemDef.is_chair()`: The Green Relaxer, 522, from Pio's quest
1012). Seated is a flag on GROUND (`seated_chair`, the chair's item id), not a fourth state, so `is_grounded()`,
SafeGround and the floor sync are unchanged.

- **Sitting down.** `sit(chair_id)` checks the body (`can_sit()`: alive, input enabled so no modal window or warp,
  not seated, `activity()` still); `Chairs` checks the item (a chair, owned, its level requirement, the character
  alive). The ways in:
  - double-click the chair in the inventory's Set-up tab, or select it and press Sit (`MisoInventoryWindow`, through
    `ItemService.use_item`, which hands chairs to `Chairs.use` on the shell's player);
  - a quickslot bound to the chair (`MisoQuickslots.use` → `ItemService.use_item`; `MisoQuickslots.can_bind`
    accepts chairs, so a chair is bound by a drag from the Set-up tab onto the HUD bar or with the inventory's Set
    key);
  - X (`sit`): `sit_key()` sits on the first chair in the Set-up tab, or announces "You do not have a chair to sit
    on." (`ItemCodes.NO_CHAIR`). An adaptation (`recovery.json` sitting): MeowDB documents no sitting without a chair
    and no map benches on Maple Island.
  Using the chair the player sits on stands it up; using another chair moves over.
- **While seated** the player cannot walk, jump or climb (ladder keys are ignored). Natural recovery is eligible and
  the chair's own bonus (canonical `setup.hp_recovery_bonus` every `setup.interval_s`, 30 HP every 10 s) runs on its
  own clock (`NaturalRecoveryRule`).
- **Standing up** (`stood_up(reason)`, also `Events.player_stood_up`): a move press (`move`) or a jump press (`jump`):
  that press does nothing else on that tick, and a held key walks from the next tick on (a held jump needs a new
  press); X again (`sit_key`); using the chair again (`chair`); PlayerCombat attacking (`attack`: the attack key
  swings and stands the player up; PlayerCombat filters the mouse, so a click on a window never counts; a skill cast
  stands up the same way); `apply_knockback` (`knockback`); `die` (`death`); `grab_climbable` (`climb`); `teleport`
  (`teleport`: warps, respawns, loads, fall recovery); `MapSession.transition_started` (`warp`, before the fade);
  `Game.character_replaced` (`character`); `Events.item_lost` when the last copy of the chair leaves the bag
  (`chair_lost`); and leaving the ground, e.g. the floor gone from under the chair (`fall`). Opening a dialogue or a
  window does not stand the player up.
- **Not saved.** The seated state is never written to the save (contract C3): a loaded game arrives standing, and the
  chair itself stays in the Set-up tab.
- **Pose.** `PlayerVisual` settles the body 0.2 m and leans it back 8° over 0.12 s onto a small procedural chair
  (`ChairProp`, turned with the facing); the proxy has no skeleton, so this is a simple pose.

`Chairs` finds the player through the `Chairs.SEAT_GROUP` group (the live player joins it when `use_autoloads`), and
only for `Game.character`, so a test fixture's `ItemService` never moves the real player. Callers may also pass the
player (`ItemService.seat`, the inventory window's `env.ctx.player`).

### InputSource

The controller reads intent only through `player.input_source`. Each tick it calls `begin_tick()`, then
`world_move(right, forward)`, `just_pressed(action)`, `is_held(action)` and `climb_axis()`. Action names are the
Controls actions.

- `KeyboardInput` reads `Input`.
- `BotInput` is scriptable: `world_dir` or `move`, `press(action)` (a one-tick tap), `hold(action)`, and `climb`. Two
  taps on consecutive ticks read as one held key. Held `move_*` actions add to `move`, and when `climb` is 0 the
  climb axis follows the keyboard rule (move up or a held `portal_enter` climbs, move down or a held `climb_down`
  descends), so a bot pressing the same keys as a player gets the same result.

Presses stay readable for the whole physics frame, so systems that run after the player (PortalInteractor, NPCs,
combat) should read `player.input_source` too. The bot can then press their keys.

### API for other systems

| Call | Who | Notes |
|---|---|---|
| `teleport(xform)` | world runtime (`IslandWorld.place_player`, MapSession) | origin = feet; facing = `xform.basis.z` (MODEL_FRONT, the sidecar convention). Zeroes velocity; clears jump buffer, coyote and hit-stun; leaves any ladder; resets SafeGround; settles onto ground within 0.6 m below or 0.45 m above; resets physics interpolation. Works while the body is frozen. Keeps the dead flag |
| `is_on_floor()` / `is_grounded()` | MapSession, GateMonitor, FallRecovery | see the body model above |
| `in_hitstun` | GateMonitor, FallRecovery | true from `apply_knockback` until landing (≤ 0.6 s) |
| `safe_ground: SafeGround` | FallRecovery, saves | recorded on every grounded (not wedged), alive, not-in-hit-stun tick that passes `safe_ground_filter` (`func(pos)` or `func(pos, collider)`); `safe_ground.transform()` for recovery |
| `kill_y`, signal `fell_out_of_world(at)` | optional | FallRecovery checks kill_y itself; the sandbox uses the signal |
| `apply_knockback(from_dir, strength = 1, invulnerability_s = -1)` | combat | `from_dir` points **from the damage source toward the player**; zero = pushed backwards. Negative invulnerability = the combat data's 1.5 s |
| `apply_knockback_from_point(source_pos, ...)` | combat | same, with the push direction taken from the source position |
| `set_invulnerable(s)`, `is_invulnerable()`, `invulnerable_time_left()` | combat | the model blinks while invulnerable |
| `die()`, `revive()`, `is_dead()`; signals `died`, `revived` | death flow | also driven by `Events.player_died` / `player_respawned`. Input is off while dead; gravity still applies |
| `set_input_enabled(bool)` | UI windows, transitions | physics keeps running |
| `set_input_source(src)`, `input_source` | bot, portals, combat | |
| `set_stats(speed, jump)`, `refresh_stats(character, db)` | character system | automatic on `Events.stats_changed` |
| `set_climbables(list)`, `add_climbables_from_sidecar(arr)`, `grab_climbable(c, at_top)`, `grabbable_climbable()` | world runtime, prompts | |
| `follow_anchor()` | CameraRig | feet x/z at the last ground height, so jumps never bob the camera |
| `activity()` | NaturalRecovery, skills, HUD, playtests | contract C4 (above) |
| `sit(chair_id)`, `stand_up(reason)`, `is_seated()`, `seated_chair_id()`, `can_sit()`, `sit_key()`; signals `sat_down(chair_id)`, `stood_up(reason)` | Chairs, skills, HUD | contract C5 (above); the live player also emits `Events.player_sat_down` / `player_stood_up`. `chair_owner` (tests) replaces `Game.character` for the sit key |
| `set_view_axes(right, forward)` | CameraRig | screen-relative input axes |
| signals `jumped`, `landed(fall_speed)`, `climb_started`, `climb_ended(c, how)`, `knocked_back(dir)`, `teleported(xform)` | animation, audio, UI | |

Collision layers follow the world runtime's table (`WorldLayers`, docs/runtime/WORLD_RUNTIME.md): the body and the
Hurtbox are on `PLAYER` (bit 4) with mask `PLAYER_MASK` (walkable, blocking, containment, scenery).

## Gameplay camera

`CameraRig` (`camera_rig.tscn`) is an orthographic Camera3D with KEEP_HEIGHT and Iteration One's fixed orientation:
pitched 40° down, looking toward Godot +X −Z.

- **Orientation and size.** `configure_from_sidecar(cameras.gameplay, map_scale)` takes the basis from the sidecar
  `xform` and sets the size to `godot_size_keep_height × camera.json ortho_size_scale (0.8) × map_scale`, clamped to
  12–19.5 m. MapSession passes `MapDefinition.ortho_size` to `set_bounds()`; that value is the sidecar frame width
  (KEEP_WIDTH). `view_size_for_frame_width()` divides it by the sidecar reference aspect (16:9) and applies the same
  scale and clamp, so both paths frame a map identically. The resulting sizes run from 12 m (interiors) to 19.5 m
  (Southperry and the wide fields): the character is 7.7–12.5% of the view height, about 70–110 px at 900 p.
- **Follow.** The rig follows `target.follow_anchor()`. A dead zone of 0.15 × the view (`dead_zone_fraction`) comes
  first, then an exponential approach at 7 Hz. The height follows the ground height at 4 Hz, never the jump height.
  The rig updates in `_physics_process` after the player (priority 100), or in `_process` when physics interpolation
  is on.
- **Bounds (§4.11).** `set_bounds(bounds, frame_width = -1, blend_s = 0)` accepts a world x/z `PackedVector2Array`, an
  Array of `[x, z]`, a `Rect2` or an `AABB`. The polygon is projected onto the camera's right and ground-forward axes.
  The view (size × aspect by size / sin(pitch) on the ground) stays inside that rectangle plus `overscan_m` (6 m), and
  is centred on any axis where the bounds are narrower than the view. `blend_s` (gate commits, 0.35 s) blends framing
  and size; warps call `snap()`.
- **No terrain clipping.** The camera sits 150 m behind its focus along the view axis, behind all terrain. Geometry
  between it and the player is dithered out or seen through (below), never cut by the near plane.
- **Per-map size.** `camera.json map_overrides["<MeowDB map id>"] = {ortho_size_m, reason}` replaces the scaled
  sidecar framing on that map (`map_view_size()`, clamped to min/max) when the rig is MapSession's camera
  (`session_map_id()`). It is empty: the camera review of the nine crowded maps (below) found no map whose size
  needed changing.
- **Readability extras.** A blob-shadow Decal under the feet marks the landing spot of every jump. The model has a
  small walk bob and lean, a post-hit blink, and a fall-over pose on death.

Wave 2 wiring: instance both scenes, then call `rig.set_target(player)`, `world.set_player(player)`,
`MapSession.attach_camera(rig)` and `rig.scan_occluders(world)`. The sandbox's `--world` mode does exactly this.

### Occlusion (M3): dithering out what hides the player and nearby monsters

The brief's camera review asks "Can I see the player? Can I see nearby enemies? Are trees/buildings obstructing play?
Are cliffs hiding monsters?". `CameraRig.update_occlusion()` runs after every camera update:

1. **Candidates** (`OcclusionFader.scan(root)`, once per added chunk). Every MeshInstance3D whose glTF extras pass
   `camera.json occluders` (`OcclusionMath.is_occluder`): category `Trees` or `Architecture` and group `Architecture`
   always; categories `Foliage` / `Props` and groups `Props` / `Vegetation` only when their Blender instance is at
   least 1.8 m tall (giant mushrooms, toadstool clusters, hedge tunnels, hanging vines, lamp posts, forges; never
   flowers, bushes or crates). The height is the instance's (the union of its parts' boxes), not the part's, so a giant
   red mushroom's 1.5 m cap fades with its 2 m stem. Never `Terrain`, `Plinth` (cliff skirts), `Rocks`, the island
   body or the sky, and never anything `walkable` (mushroom caps, roofs) or `climbable` (ropes, ladders); those rules
   apply per part. The whole island gives 3,472 candidate meshes in 2,303 **units**: the parts of one Blender instance
   (`<instance>__<part>` under one parent, such as a tree's trunk and canopy) fade together. Candidates sit in an 8 m
   ground grid, so a tick only looks at those within `occluder_radius_m` (22 m) of the player.
2. **Targets.** The player's whole body (5 heights x 3 columns across `occluder_player_half_width_m`, at the movement
   model's body height), a disc of 17 points in the screen plane around the chest out to `occluder_hole_radius_m`
   (2.4 m), and the body (3 x 3 points, `MonsterDef.sprite_size_m`) of every live monster within
   `occluder_monster_radius_m` (8 m), found by a physics shape query on `WorldLayers.MONSTERS`, nearest first, at most 7.
3. **Selection.** A unit is selected when one of its meshes lies between the camera and any target point: its
   view-frame box (`OcclusionMath.view_box`) must contain the point on screen and reach nearer the camera
   (`may_cover`), then the exact segment test runs against the mesh's triangles (a `TriangleMesh` BVH per mesh
   resource, shared by every instance). An Architecture mesh whose box holds a target's chest and whose ground
   footprint is at least `occluders.room_min_size_m` (8 m) on both axes is the room it stands in and never fades for
   it: the interior shells and the Amherst cutaway house (10-18 m). Smaller architecture the player walks through or
   under (the Amherst town gate, arches, trellises, the Southperry gazebo, signs, door frames: at most 7.1 m) fades like
   any building, and so does a tree or hedge tunnel the player stands in.
4. **Dithering.** A selected mesh gets `OccluderDither` stand-ins for its surface materials, and its
   `occlusion_fade` instance uniform eases to 1 over `occluder_fade_s` (0.2 s). The stand-in is a generated spatial
   shader that renders like the exported StandardMaterial3D (baked vertex-colour albedo, roughness, specular,
   emission; lit double-sided bodies and unshaded single-sided ink shells), plus a screen-door cut. Inside each hole
   (a circle in view space around the player's chest, radius 2.4 m, and around each nearby monster, half its size +
   0.5 m), fragments nearer than the target's depth + 0.8 m and higher than its feet + `occluder_hole_floor_margin_m`
   (0.1 m, `OcclusionMath.hole_floor`) are discarded against interleaved-gradient noise, up to
   `occluder_dither_strength` (90%) at the centre with a soft rim (`occluder_hole_edge`). Dithering is order
   independent: every layer of a double-sided canopy and its ink shell drops the same pixels, and the remaining dots
   still write depth. The cut is skipped in the sun's shadow pass (its view direction is compared with the gameplay
   camera's), so a faded tree's shadow does not change. The floor height keeps the deck or floor a target stands on
   solid when the mesh carrying it is dithered (the Southperry gazebo is one mesh with its deck and posts), and costs
   the body nothing: at the 40° pitch an occluder point d meters nearer the camera covers the body on screen only if
   it is at least 0.84 d above the feet. When a unit is clear its meshes fade back and get their own materials again.
   A mesh with a material the stand-in cannot reproduce (textures, transparency, a next pass) falls back to
   `GeometryInstance3D.transparency` = `occluder_transparency` (0.85); of the 3,472 exported candidates only the
   transparent `SouthperryArmorStore_60001_Light_Shaft` does.
5. **The player's see-through outline** is turned on (`PlayerVisual.set_see_through(true)`) while a selected unit
   covers a point of the player's body, or while a physics ray from the body toward the camera (knee, chest and head:
   `silhouette_terrain_heights_m`; walkable, blocking and scenery layers) hits terrain, a cliff or a wall, which never
   fade. `rig.player_occluded()` reports it.

Why the rewrite: the first version cast three rays (feet, chest, head) and alpha-faded hits to `transparency` 0.7.
The exported trees are double-sided with an inverted-hull ink shell, so a faded canopy still stacked three to six
blended layers (about 90% coverage), and blended meshes write no depth, so the stencil X-ray had nothing to show. In
Snail Hunting Ground I a player standing behind a sapling was 47% visible (only the feet read); it is now 97-100%.

Measured in the real game (Snail Hunting Ground I, `_scratch/camera-fix/driver`): the stand-ins at fade 0 differ
from the original materials in 0 pixels, and with the trees rendering only their shadows, fully cut stand-ins and the
originals differ in 0 pixels (the shadow-pass gate works). `update_occlusion()` costs about 0.13 ms per tick on Snail
Hunting Ground I and 0.31 ms in Dangerous Forest with four monsters near the player.

### X-ray fill and see-through outline (PlayerVisual)

`PlayerVisual` builds three passes on duplicated materials (the library's shared materials stay untouched):

- Every surface writes stencil `STENCIL_REF` (37) where it is visible (custom stencil: write, always), the unshaded
  ink shell (`M_Outline`, an inverted hull) too. The ink draws the contour lines in front of the body at creases (hair
  over the face, the ear, the feet); before the review it wrote no stencil, so the fill below painted those lines blue
  on a player nothing hid (360 px around the head and feet on Snail Hunting Ground I, now 90 px: a thin rim at the
  soles, where the feet sit slightly below the ground mesh).
- The next pass of every lit surface, the **X-ray fill** (unshaded, `xray_color` = the player's shirt blue #3B7AFF at 50%, no depth test,
  front faces only, stencil read != 37, render priority 120), paints the parts of the body hidden by terrain, props or the remaining
  dither dots. Then an invisible **mark** pass (priority 121, no depth test, stencil write 37) marks the whole
  silhouette, because Godot keeps stencil read and write exclusive within one pass.
- The **see-through outline** is a copy of each model mesh with position-averaged normals (the proxy is flat shaded,
  so growing the original normals would crack at every hard edge), grown by `silhouette_width_px` (3 px) at the
  current view size, unshaded in `silhouette_color` (the player's colour, #3B7AFF), no depth test, stencil read != 37,
  render priority 127: a ring around the silhouette drawn on top of everything. Its opacity eases over
  `silhouette_fade_s` (0.12 s) toward `set_see_through()`, so an unoccluded player has no extra line. The outline
  meshes are on the player render layer (no blob shadow on them) and cast no shadow.

The visual now shows the exported Player_Proxy. The export names asset roots with Blender's suffix
(`Player_Proxy_001`), and the old exact-name lookup had fallen back to the procedural chibi placeholder in the real
game. `PlayerVisual.find_proxy()` matches the name like `ProxyLibrary` does.

## Canonical sources used

- `data/canonical/formulas/movement.json` (MeowDB `guides/speed-jump-and-movement`, `formulas/attack-speed`,
  `formulas/damage-taken`): walk and climb speed, base and caps, the jump table, and the knockback airtime model.
- `data/canonical/formulas/accuracy.json` `after_hit.post_hit_invincibility_s` (`formulas/damage-taken`).
- `data/misostory/world_scale.json` through `WorldScale.h` / `.v` for every px → m conversion.

## Testing

```bash
ISOLATE=player bash scripts/test.sh player camera                  # the two real-world route tests SKIP without the world
ISOLATE=camera INCLUDE_WORLD=1 bash scripts/test.sh camera         # 46 tests: camera math, rig, occlusion, silhouette
ISOLATE=player INCLUDE_WORLD=1 bash scripts/test.sh player_route   # bot on real collision: SHG I + Mushroom Town routes, both ways
```

| File | Covers |
|---|---|
| `test_player_movement_model.gd` | canonical speed, climb, jump, gravity and knockback conversions; caps; `jump_apex_m_at_cap` = derivation; every adaptation key has a reason |
| `test_player_movement.gd` | 3.0 m/s per second; 3-tick start and 2-tick stop; W = camera forward; equal diagonal speed; facing; 0.90 m apex and 1.30 m at the cap; airtime; jump length; limited air control; coyote time and its expiry; jump buffer and its expiry; hold to re-jump; `landed` impact speed = √(2gh) and the terminal fall speed cap; total Speed from `StatCalculator` (a Speed effect walks faster) |
| `test_player_step.gd` | steps up 0.4 m, stops at a 0.6 m wall (and jumps onto it); the step boundary (exactly `step_up_m` mounts, 5 cm more does not); stairs with no airborne ticks; steps down 0.4 m; 30° and 36° walkable, 41° and 45° not; no creep on slopes; down-slopes stay grounded; clutter without speed loss; trimesh seams; wall sliding; feet over a ledge land on it, a capsule-only edge contact slides off (regression); wedged in a V crevice is steady ground and can jump out (regression) |
| `test_player_climb.gd` | sidecar parsing; a ladder end to end (Up grab, canonical climb time, exit to top_exit, Down grab from the top, climb down); interact and W/S; grab range; jump off sideways; descend-only; ropes without foot ground; mid-air catch; no re-grab after a jump-off with Up held (and Up held climbs, as on the keyboard); `grabbable_climbable()`/`grab_climbable()` and the exact top_exit |
| `test_player_hit.gd` | knockback rise and airtime per MeowDB's model, push, hit-stun gating input, direction conventions, invulnerability timer and source, knocked off ladders, death and revive, teleport reset, SafeGround rules and both filter forms, kill_y |
| `test_player_activity.gd` | `activity()`: still, walking (and pushing into a wall), still in a dialogue with a key held, jumping (and falling, and every tick of a held jump including the landings), climbing, hitstun, dead, attacking during a planted lockout (speed 0), seated, other when frozen or outside the tree |
| `test_player_sit.gd` | sitting only grounded, still, alive and free; a move press stands up without moving that tick and walks on the next; a jump press stands up without jumping; the attack key (a real PlayerCombat; its first tick is "attacking", not seated) and a cast stand up; knockback, death, teleport, a climb and leaving the ground stand up; ladder keys are ignored while seated; X toggles on the first chair owned and reports "no chair"; losing the chair stands up; the seated state is not in the save and a load arrives standing |
| `test_chairs_use.gd` | chairs are the Setup items with setup data (522, 525); the canonical bonus; the first chair in slot order; refusals (unknown, not a chair, not owned, level, dead, walking); use sits and stands without consuming or emitting item events; moving to another chair; a fixture ItemService never moves the live player; a quickslot-bound chair sits the live player; the inventory window's double-click and Sit / Stand button |
| `test_player_route_bot.gd` | the bot on real exported collision (INCLUDE_WORLD=1); route geometry helpers; on synthetic collision (no world needed): jumps a 0.8 m rise, climbs a ladder up and down, reports a stall at a wall |
| `test_player_scene.gd` | the authored `player.tscn` (player layer and mask, capsule over the step band, full-height Hurtbox, walks at the canonical speed) and every method/property the world runtime, MapSession, combat and the camera call; `camera_rig.tscn` (orthographic, KEEP_HEIGHT, camera.json near plane, MapSession duck type); bounds set before the first snap keep their size; a freed target does not crash the rig |
| `test_camera_math.gd` | iso axes and pitch from the sidecar basis, view extents, bounds forms, clamp with overscan, centring, a real footprint, dead zone, ortho size, frame-rate independence |
| `test_camera_rig.gd` | sidecar configuration and axes handed to the player, dead-zone follow, no bob on jumps, ground-height follow, bounds clamp and unbounded, MapSession's frame-width size with blend and clamp, the transparency fallback for a material that cannot be dithered, `map_overrides` (each has a reason, a MeowDB id and a size within min/max; clamping; only MapSession's camera reads a map id) |
| `test_camera_occlusion.gd` | the pure selection (`OcclusionMath`): every `occluders` rule (trees, architecture, tall foliage and props, never terrain, plinths, rocks, walkable or climbable), the tall rule reading the whole instance (a giant mushroom's short cap fades with its stem, a walkable cap never does), rooms only for room-sized Architecture (a town gate or gazebo is none), the hole floor (the deck in front stays, a canopy above the feet is cut), unit keys, body samples over the whole silhouette, the disc on the screen plane, view boxes in front / behind / aside, holes and the cut mirroring the shader, fade steps, the ellipsoid; `OccluderDither` stand-ins (parameters copied, lit and unshaded variants, cache, unconvertible materials, holes handed out); the fader on meshes through the rig: a tree in front dithers in and restores its own material, the fade time, an occluder beside the player inside the hole radius (dithered, not "covering") vs outside it and behind the player, an edge-of-body occluder the old three rays missed, trunk and canopy fading together, a tree hiding a nearby monster (physics query, a hole per monster), rooms and walkable roofs never fading, the transparency fallback and `clear()` |
| `test_camera_silhouette.gd` | `PlayerVisual`: lit surfaces write the stencil and chain the fill and mark passes, an unshaded ink shell writes the stencil with no fill and no hull (and, with the world export, every surface of the real proxy), fill / mark / outline flags and priorities, outline meshes hidden, shadowless and on the player layer, the smoothed hull (split normals averaged), the see-through toggle and its fade; the rig turning the outline on behind a tree and behind a terrain block (which never fades) and off in the open; the library proxy lookup (`Player_Proxy_001`) and, with the world export, the real proxy instead of the placeholder |

Sandbox, run from an ISOLATE copy (`_scratch/godot_runs/<name>/game`) so the shared `.godot` cache is untouched:

```bash
G="bash ../../../../scripts/godot.sh --path ."
$G --headless res://scenes/sandbox/player_sandbox.tscn -- --sweep all                     # every route of every map, both ways
$G --headless --fixed-fps 60 res://scenes/sandbox/player_sandbox.tscn -- --map <slug> --bot all --both --quit --verbose
$G --headless --fixed-fps 60 res://scenes/sandbox/player_sandbox.tscn -- --world --all --quit   # real island + MapSession
$G --disable-vsync --resolution 1600x900 res://scenes/sandbox/player_sandbox.tscn -- --map <slug> --context --showcase <dir> --quit
$G --disable-vsync --resolution 1600x900 res://scenes/sandbox/player_sandbox.tscn -- --map <slug> --context   # play: WASD, Space, Up/Down, F, R, F5, K, F3
```

Results on 2026-10-04:

- **Route sweep:** 25 maps, 360 route runs (every route in both directions), **360 pass** in 11 s with no falls
  (re-run 2026-10-04 after the Blender round-2 export). The four earlier failures (both interior `Rafters` reverse
  runs under eave hulls, TomatoField_1020001 `WestBed` both ways under tomato leaves) were fixed in the Blender
  source in round 2 (blender_export.md "In Godot"; ITERATION_LOG P2-7).
- **World smoke** (`--world --all`): all 25 maps through `MapSession.debug_warp`. The player is on the floor on the
  first frame after arrival (limit 10), and the camera receives bounds and its per-map size from MapSession.
- **Real-time bot** (SHG I, 16 runs): all pass, 1 `is_on_floor()` mismatch in 9,266 ticks.

### Feel check (windowed screenshots, `_scratch/player_shots/`)

- **Framing.** It matches Iteration One's isometric view. At 13.5 m (Mushroom Town, the start map) the character is
  about 90 px of 900; at 19.5 m (Southperry) about 70 px. 21 m read as too small, so the cap is 19.5 m.
- **Movement.** Moves are screen-aligned (D walks screen right, W screen up). A standing jump reaches 0.89 m with the
  camera perfectly still. Climbing a rope and the top exit read cleanly.
- **Occlusion.** Superseded by the camera review below (the exact triangle test from this check stays: an AABB-only
  test had faded a ship's thin masts and the box corners of trees that did not cover the player).
- **Blob shadow.** It is subtle under the strong sun shadow, but marks the landing spot during jumps.

### Camera review (2026-10-04, the real game)

The real main scene (`scenes/main.tscn`: title, a new character, the island, every subsystem) was driven windowed at
1600 x 900 from an ISOLATE copy by a scratch driver (`_scratch/camera-fix/driver/drive.gd`): `god on`, then
`warp <map>` to each crowded map, a capture at the arrival point and one deeper in (`goto slot` at 60% of the slot
list, or the first NPC on town maps). Each capture pauses the tree and renders the frame four times (player shown or
hidden, occluder candidates shown or hidden, with the player's and the monsters' shadows off) to measure the share of
the player's pixels, and of the monsters within 8 m, that are still visible with the occluders in place. The player
column counts every pixel the player changes, and the X-ray fill and the outline are part of the player, so it reads
"the player is visible or drawn through" rather than "the body is unobstructed"; the monster column (monsters have no
X-ray) is the plain visibility.

| Map | View | Arrival: player | Deeper: player | Deeper: monsters near | Notes |
|---|---|---|---|---|---|
| 000000010 Mushroom Town | 13.5 m | 1.00 | 1.00 | none | the sunflower patch in front of the arrival dithers inside the disc |
| 000000020 Mushroom Town (east) | 14.4 m | 1.00 | 1.00 | none | |
| 000000040 Snail Hunting Ground I | 15.3 m | 0.98 | 1.00 | 1.00 (2) | behind the sapling: 0.47 before, 1.00 now; the fight there (3 snails): monsters 0.98 |
| 000000041 Snail Hunting Ground II | 18.0 m | 0.92 | 0.99 | 0.98 (5) | |
| 000001000 The Field West of Amherst | 19.5 m | 1.00 | 1.00 | 0.91 (4) | the slot sits inside the 9 m stalk-mushroom cluster: outline on, the cluster dithered around the fight |
| 000001002 Dangerous Forest | 14.4 m | 1.00 | 1.00 | 0.95 (4) | behind a Tall Gloom tree with 3 snails: player 1.00, monsters 1.00 |
| 000001006 Hunting Ground Middle of the Forest II | 16.2 m | 1.00 | 1.00 | 1.00 (7) | arrival behind an orange tree: outline on |
| 000001010 Amherst | 19.5 m | 1.00 | 1.00 | none | |
| 000000060 Southperry | 19.5 m | 1.00 | 1.00 | none | |

The remaining monster gaps are the 10% of dither dots the strength leaves on purpose. The screenshots (viewed as
2 x 2 contact sheets) show no map whose framing needs a different view size, so `map_overrides` stays empty. What they
show instead:

- **Can I see the player?** Yes on every capture; behind trees and the stalk-mushroom cluster the blue outline rings
  the player and the dithered hole shows the body.
- **Can I see nearby enemies?** Yes: monsters inside a canopy's footprint get their own holes.
- **Are trees/buildings obstructing play?** Only beyond the 8 m monster radius: in Dangerous Forest the dense
  foreground canopies cover the lower part of the screen (the lower terrace) when the player stands on the upper
  path. Monsters there are seen once they come within 8 m. Town buildings never covered the player at the
  captures.
- **Are cliffs hiding monsters?** Not at the captures: terraces face the camera, and monsters on lower tiers stayed
  in view. A cliff that hides the player turns the outline on (physics ray); monsters have no X-ray yet (below).
  Checked on the one Snail Hunting Ground I slot (13 of 40) where terrain alone hides a standing player: the hidden
  body shows as the translucent blue fill inside the outline ring, not as a solid blob (the mark pass works).

## Known issues and follow-ups

- How often the outline is on (review sweep, 2,862 route, spawn and arrival points on all 25 maps): 363 points (13%),
  333 of them for a faded occluder over the body, the rest for terrain. Forest maps run highest (In a Small Forest
  29%, Hunting Ground Middle of the Forest II 33%), towns 0-4%, interiors 22-33%.
- The terrain rays use collision: next to a prop whose convex collision hull is larger than the visual (a log pile, a
  boulder, a giant tomato, a tomato plant) the outline can turn on while nothing visible covers the player (4 of the
  2,862 points).
- Architecture with a footprint of at least 8 m never fades for a player standing inside its box: intended for the
  interior shells and the Amherst cutaway house, but it also covers Southperry's `X60000_Ship_Victoria` (its deck,
  mast and crow's nest are walkable routes) and the Amherst lookout. There the mast and the nest rail cover part of the
  body, which shows only as the X-ray fill (no outline, no dither). An explicit exception would need a data rule; the
  review left it because the player stays readable (screenshots in `_scratch/review-camera/shots`).

- Monsters have their own see-through silhouette since Iteration Two's P4 round (`MonsterVisual`, stencil 36,
  MONSTERS_AND_COMBAT_RUNTIME.md "See-through silhouette"); it relies on the player's `STENCIL_REF` (37) staying above
  36, so another system that writes the stencil must not take 36 or 37.
- The dither leaves 10% of an occluder's pixels inside a hole (`occluder_dither_strength`), so the occluder still
  reads as present; the X-ray fill paints the player through those dots, and monsters behind them show through a
  sparse screen of dots.
- Holes are circles around the targets. A large mesh (a 15 m giant tree, the Amherst lookout) dithers only inside
  them, so the rest of it still covers the screen; dense forest maps (Dangerous Forest) keep a band of foreground
  canopies over the lower terrace beyond the 8 m monster radius.
- The disc around the player also dithers occluders that are only near the player (a sunflower patch in front of the
  Mushroom Town arrival); that is the radius rule working as intended, but it shows as a dotted patch.
- Terrain detection for the outline uses collision, not the visual mesh: a visual-only overhang with no collision
  does not turn the outline on (the per-pixel X-ray fill still shows the hidden body).
- Both Up (`portal_enter`) and `interact` also grab a climbable within 0.8 m. If a portal trigger or an NPC is in reach
  at the same time, both react. No map has that overlap today, but prompts should use `player.grabbable_climbable()`
  and the world's `nearest_interactable()` to pick one.
- `is_on_floor()` can be off for a single tick when a feet ray lands exactly on a chamfer edge (rate above).
  `is_grounded()` is exact.
- No skeletal animation: the Player_Proxy is a static model with procedural bob, lean, blink, death tilt and a simple
  sit pose (settle and lean onto a procedural chair). The fallback model (when `_library.glb` is missing) is
  procedural.
- Sitting needs a chair item: there is no ground sit and no map bench (MeowDB documents neither on Maple Island;
  Rain's quiz 1016 only mentions chairs and benches in general).
- Crouch and down-jump through platforms (the classic statement from Rain's quiz) and fall damage (MeowDB's formula
  exists; MAP_ARCHITECTURE §4.6 chose none) are not implemented.
- `IslandWorld` with `load_visuals = true` segfaults in headless runs (threaded visual load in the dummy renderer), so
  the sandbox's `--world` mode loads collision only when headless.
- `set_input_enabled(false)` (dialogue, transitions) gates only the controller. Systems that read
  `player.input_source` directly still see presses, so they must also check `player.is_input_enabled()`;
  PortalInteractor does (since Iteration Two's P3-1, through `IslandWorld.player_input_block()`).
- The bounds clamp works on the ground plane at the followed ground height. Terrain much higher or lower than the
  player near a map edge shifts what is visible there by about 1.2 × the height difference (cot 40°), which the 6 m
  overscan mostly absorbs.
- The route sweep never needs a jump (`jumps=0` on every exported route); jumping a rise is covered by the synthetic
  bot test only.

### Review of the occlusion rewrite (2026-10-04)

An adversarial review drove the real main scene from an ISOLATE copy (`_scratch/review-camera/driver/probe.gd`) and
swept every route, spawn and arrival point of the 25 maps against the fader, the terrain rays and the visual meshes.
It fixed four defects:

- **X-ray fill on an unoccluded player.** The proxy's ink shell wrote no stencil (above); every surface now does.
- **Instances split by the tall rule.** The rule read each part's own height, so 12 instances faded only in part: a
  giant red mushroom's cap (Field West of Amherst) stayed solid over the player while its stem dithered, as did lily of
  the valley bells and flag pennants. It now reads the instance's height (0 split instances; 48 more candidate
  meshes, mostly 1.9-2.2 m toadstool clusters).
- **The room rule caught small architecture.** Any Architecture box holding the chest counted, so a player walking
  through the Amherst town gate, the Mushroom Town stone arch, the Tomato Field gate and trellis arches, past a sign or
  a fence segment, or through an interior door frame was hidden by a pillar, arch or frame that never faded (14 hits
  in the sweep; the town gate's pillar covered the whole body, which showed only as the X-ray fill).
  `room_min_size_m` limits the rule to room-sized shells.
- **Holes in the floor.** A dithered mesh that also carries the floor (the gazebo: deck and posts in one mesh) was cut
  in front of the player down to the deck, which opened a dithered hole showing the sand below (4,816 px below the
  feet inside the hole; 509 with the floor, the post in front). Holes now stop at the target's feet.

### Review (2026-10-04)

An adversarial review re-ran everything above with identical results (at the time: sweep 356/360 with 4 geometry
failures since fixed in the Blender source, world smoke 25/25 grounded on arrival, 1 `is_on_floor()` mismatch in 688 ticks) after these fixes: the
capsule-only edge contact and wedge flicker described under "Body model"; `BotInput` climb/move parity with the
keyboard; no canonical stat fallbacks in `MovementModel` and no derived speed fallbacks in `RouteBot`; CameraRig keeps
the size of bounds set before its first snap and survives a freed target; `teleport()`/`snap()` reset physics
interpolation. Windowed screenshots of Snail Hunting Ground I (spawn, rope climb, a faded birch in front of the
player) matched the framing described above.
