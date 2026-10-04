# Developer and debug tools (Iteration Two, brief Phase 20)

The debug tools are a console, an overlay and a set of 3D draw layers. Iteration Three uses them to verify content:
warp anywhere, look at what the world built, spawn and kill monsters, grant EXP, levels, mesos and items, and drive
quests. They have three parts:

- **The `Debug` autoload** (`scripts/autoload/debug_tools.gd`, `class_name DebugTools`) holds the command registry.
  Every command runs through `Debug.run(line)`: the console, the tests and the traversal bot use the same path. It
  works headless against the autoloads, with no UI and no world.
- **The built-in commands** (`scripts/debug/debug_commands.gd`) call the systems' own APIs: `MapSession`,
  `PortalGraph`, `Game`, `ItemService`, `Progression`, `DropRoller`, the `QuestService` and the world's
  `MapInstanceView`. They never reach around those APIs. Commands that another system already registers are reused,
  not registered a second time.
- **The UI** (`scenes/debug/debug_ui.tscn`) is the console (`` ` ``) and the overlay (F3). The game shell installs it
  and calls `setup(ctx)`. It also runs standalone.

No gameplay value lives in this system. Everything it prints or draws is read from the live objects: the session, the
instance state, `SpawnModel`, the camera rig, the character and the world's collision. It adds no adaptation data. The
few constants in its code are console limits (time scale 0.01 to 16, at most 50 debug spawns, 1000 simulated kills
by default) and presentation (colours, label sizes, the 1.5 m ring that debug spawns stand on).

## Files

| Path | What |
|---|---|
| `game/scripts/autoload/debug_tools.gd` | `DebugTools`, the `Debug` autoload: the registry (commands, aliases, composites, completion kinds, history), collaborator resolution, overlay and layer state, god mode, screenshots |
| `game/scripts/debug/debug_commands.gd` | `DebugCommands`: every built-in command, debug spawns, the quest dispatcher |
| `game/scripts/debug/debug_resolve.gd` | `DebugResolve` (pure): map, item, monster, quest and portal references to MeowDB ids |
| `game/scripts/debug/debug_completer.gd` | `DebugCompleter`: Tab completion |
| `game/scripts/debug/debug_report.gd` | `DebugReport`: the overlay text, `where`, `portals`, `maps`, `char`, `inv` |
| `game/scripts/debug/debug_draw.gd` | `DebugDraw` (Node3D): the 8 draw layers, created under the world |
| `game/scripts/debug/debug_ui.gd`, `debug_console.gd`, `debug_overlay.gd` | `DebugUI` (CanvasLayer root, `setup(ctx)`), `DebugConsole`, `DebugOverlay`, all built in code |
| `game/scripts/debug/debug_harness.gd` | `DebugHarness`: a private Debug + MapSession + Game + Saves + Events for tests and headless tools |
| `game/scripts/debug/debug_sandbox.gd` | the sandbox: the island, the player, the camera, a context and the debug UI, driven by a step list |
| `game/scenes/debug/debug_ui.tscn` | the subsystem scene (a `CanvasLayer`, layer 120: above the ScreenFader and the shell's screens) |
| `game/scenes/debug/debug_sandbox.tscn` | the sandbox scene |
| `game/tests/unit/test_debug_*.gd` | registry, resolve and completion, every command, the autoload, the UI, and the commands on the real world |

## Integration

- **Autoload.** `Debug` already exists in `project.godot` (last in the list). Its `_ready` installs the built-in
  commands synchronously. Other autoloads register their commands before (MapSession, in `_ready`) or after (Game,
  deferred), and the order does not matter: aliases resolve at run time, and composite commands keep the other
  system's registration as their fallback.
- **Scene.** The shell's `SubsystemInstaller` adds `res://scenes/debug/debug_ui.tscn` under `ctx.ui_root` as
  `DebugUI` and calls `setup(ctx)`. `setup` stores the context in `Debug.ctx` (duck-typed: `world`, `player`,
  `camera`, `push_modal` / `pop_modal`, `window_opened` / `window_closed`). The shell needs to do nothing else.
- **Collaborators.** Debug resolves each one on every call: an injected field first (`session`, `game`, `content`,
  `event_bus`, `world_node`, `player_node`, `camera_node`; tests use these), then the context (`world`, `player`,
  `camera`), then the autoloads (`MapSession`, `Game`, `Data.db`, `Events`, `MapSession.world`,
  `MapSession.camera`). A missing collaborator means "not available". The command then says so instead of failing.
- **Modal input.** Opening the console calls `ctx.push_modal(self)` and `ctx.window_opened(console)`. The shell's Esc
  handling can then close it as the newest window, and the console also closes on Esc itself. Closing it pops both.
  Without a context, the console switches the player's input off directly. `KeyboardInput` polls `Input`, so typing
  would otherwise walk the player. Two more guards apply while the console is open, with or without a context:
  - **The player's innermost `InputSource` is parked.** It is swapped for an idle `BotInput` and restored on close.
    `set_input_enabled(false)` gates only the controller. `PortalInteractor`, `PlayerCombat` and `LootSystem` read
    `player.input_source` themselves (PLAYER_AND_CAMERA.md, "Known issues"). MapSession also re-enables the
    controller at the end of every warp, even one typed into the open console. Without the swap, the history keys
    would press portals and ladders, and typed letters would walk the player after a warp. The swap walks decorators:
    `PlayerCombat` wraps the keyboard in an `AttackLockInput` (`inner`) and re-wraps whatever the player's source is
    on its next physics tick. So the idle source replaces the innermost source, and closing puts the keyboard back
    wherever the idle source sits by then. (The first version swapped the whole source. The lock then wrapped the
    idle source, and in the real game the player could not move again after the console closed.)
  - **Other UI's key handlers are fenced.** `_input` runs before GUI focus. An open NPC dialogue or shop
    (`DialogueWindow` / `ShopWindow.handle_key`) would otherwise take Enter, Space, Backspace, digits and WASD typed
    into the console: `mesos 25` arrived as `meo`, and Enter advanced the dialogue. While the console is open, every
    node under `ctx.ui_root` and `ctx.systems` whose own script defines `_input` (the debug UI excepted) has its
    input processing switched off, and it is switched back on when the console closes or the debug UI leaves the
    tree.
- **Keys.** `debug_console` (`` ` ``) and `debug_overlay` (F3) are caught in `_input` and marked handled, so the
  backtick is never typed into the input line.
- **Layer.** `DebugUI` is CanvasLayer 120, above the HUD (10), the death notice (90), the world's `ScreenFader` (100)
  and the shell's screens (110: loading, pause menu). The console stays readable during warp fades and when it is
  opened over the pause menu.

```
console line ──► Debug.run(line) ──► registry ──► DebugCommands handler ──► MapSession / Game / ItemService / ...
tests, bot  ──┘        │                                   │
                       └► command_ran(line, out) ──► console mirror (lines run by code show dimmed)
Debug.overlay_text() ◄── DebugReport ◄── session, instance state, SpawnModel, world, player, camera, character
Debug.set_layer() ──► DebugDraw (under IslandWorld) ◄── collision_root, containment_root, MapDefinition, view
```

## Public API (`Debug`)

| Member | Notes |
|---|---|
| `register_command(name, help, handler)` | Fixed contract. `handler(args: PackedStringArray) -> String`. Names are case-insensitive. By convention, `help` reads `"name <args>: what it does"` |
| `run(line) -> String` | Fixed contract. Double quotes group words (`give "Red Potion" 5`), and `\"` is a literal quote. Several commands are separated by `;`. An unknown command answers `unknown command: x` and suggests close names. A handler whose owner was freed, or one that returns null, gets a clear message |
| `register_alias(alias, target, prefix_args)` | The alias resolves when it runs, so its target may register later |
| `register_composite(name, help, handler)`, `shadowed_handler(name)` | A Debug-owned dispatcher. Another system's registration under the same name, earlier or later, becomes its fallback |
| `set_completion(name, kinds)`, `complete(line)` | Tab completion: `{line, candidates}` |
| `call_command(name, args)`, `has_command`, `command_names`, `command_owner(name)` | `command_owner` returns the object behind a command, for example the QuestService behind `quest_accept` |
| `history`, `add_history(line)` | Console history, shared by every console, with at most 200 entries |
| `overlay_text()`, `set_overlay(on)`, `overlay_enabled` | The overlay text is what the UI shows and what the tests read |
| `set_layer(name, on)`, `is_layer_on`, `LAYERS`, `ensure_draw()`, `draw` | The draw layers |
| `god_mode`, `set_god_mode(on)` | See "God mode" below |
| `screenshot(path) -> {ok, path, error}` | Captures the next frame without the console. Fails cleanly when headless |
| `attach_context(ctx)`, `get_session/get_game/get_db/get_bus/get_world/get_player/get_camera/get_defs/get_character/get_rng/get_clock/current_map()` | Collaborator resolution |
| signals `command_ran(line, out)`, `message(text)`, `overlay_toggled(on)`, `layer_toggled(layer, on)`, `clear_requested`, `capture_state(capturing)` | Used by the UI |

## Commands

The map argument accepts, in this order:

1. the MeowDB id (`000000040`);
2. the GMS v8 id (`40000`);
3. the MeowDB id without its leading zeros (`40`);
4. the Blender slug (`SnailHuntingGround1_40000`);
5. a name fragment.

Name fragments ignore case and punctuation and are matched against the MeowDB name, the street, the Iteration One
name and the slug, so `snail hunting ground 1` and `southperry` both work. An exact match beats a prefix match, and a
prefix match beats a "contains" match. When several maps tie, the command lists them and does nothing. `Mushroom Town`
is ambiguous between 000000010 and 000000020. Items, monsters and quests take a MeowDB id or a name in the same way:
`give red potion 5`, `spawn orange mushroom 3`, `quest accept sam's suggestion`. Tab completes command names, ids, and
names to ids.

| Command | Does | Drives |
|---|---|---|
| `help [cmd]` | Lists every registered command with its help (other systems' commands too), and the aliases | registry |
| `warp <map> [portal]` (alias `tp`) | Teleports to `player_spawns[0]`, or to a portal's arrival. With a world and a player the warp fades; the console prints `arrived: ...` (with the grounding frames) when it completes | `MapSession.debug_warp`. Refused while DEAD or mid-warp, with MapSession's reason |
| `portals [map]` | Each portal with its destination map and portal, the destination's name, kind, link mode and MeowDB type. Type 1 shows as `hidden`, the arrival gate as `walk-only` | `MapDefinition.portals` |
| `where` | Map, street, v8 id, slug, session state, respawn map, last arrival and transition, world and map-local position, region | `MapSession`, `RegionIndex` |
| `maps` | The 25 maps: ids, v8 ids, names, kinds, portal / spawn / NPC counts | `MapDefinitions` |
| `goto <x> <z>`, `goto slot <n>`, `goto npc <id or name>`, `goto portal <id>` | Moves the player inside the current map, grounded | `IslandWorld.place_player` (also resets fall recovery) |
| `showmap [on/off]`, `coords [on/off]`, `overlay [on/off]` | Toggle the overlay. `showmap` also prints the map and `coords` the position | overlay |
| `collision`, `spawns`, `portaldata`, `npcs`, `bounds`, `mobregion`, `rings`, `safeground` `[on/off]`; `draw [layer or all] [on/off]` | Draw layers (below). Each reports the lines and labels it built | `DebugDraw` |
| `spawn <monster> [n]` | n debug monsters (1 to 50) on a ring around the player | `MapInstanceView.monster_factory` with a synthetic `SpawnSlot` (`index -1`, `placement "debug"`) |
| `kill [nearest or all]` | Kills the nearest live monster (to the player), or every one, debug spawns included | See "Kill" below |
| `drops <monster> [kills] [seed]` | Simulates kills: mesos and every item with its kill rate (placeholder rates) | `DropRoller.simulate` with its own RNG (seed 1 by default), so `Game.rng` is untouched |
| `monsters [name]` (alias `mobs`), `items [name]` | Searches ids | `ContentDB` |
| `exp <n>` | Gains n EXP. Level-ups, AP, SP, HP/MP growth and events happen as in play | `Game.gain_exp(n, "debug")` |
| `level <n>` | Sets the level (see "Level" below) | `Game.gain_exp`, `Progression.level_up_gains` |
| `ap <stat> [n]` | Spends unspent AP | `Game.allocate_ap` (only the canonical `ap.allocatable_stats`) |
| `heal` | HP and MP to the derived maxima. Refused while dead | `StatCalculator.max_hp/max_mp`, `hp_changed` / `mp_changed` |
| `god [on/off]` | See "God mode" below | player, Debug |
| `char`, `inv` | Character summary; inventory tabs, equipment and mesos | `CharacterState` |
| `mesos <n>` | Adds n mesos (up to the cap), or spends them when n is negative (refused when short) | `ItemService.gain_mesos` / `spend_mesos` |
| `give <item> [qty]` | Puts items in the inventory and reports a full tab | `ItemService.gain` |
| `clearinv [tab]` | Empties one tab, or all of them. Equipment is untouched | `ItemService.clear_inventory` |
| `quest accept/complete/forfeit/reset <id>`, `quest complete <id> force`, `quest <id>`, `quest status <id>`, `quest list` | Quest actions and status | See "Quests" below |
| `quests` | Active and completed quests | the QuestService's own command |
| `reload` | A fresh instance of the current map. Removes debug spawns | `MapSession.reload_map` |
| `respawn` | Respawns a dead character at its return map | `MapSession.respawn` |
| `linkmode [warp or edge] [link or all]` | Shows or switches link modes. `edge` answers "unavailable until walk-through gates exist (M2)" | `PortalGraph.set_link_mode` |
| `timescale [x]` | Shows or sets `Engine.time_scale` (0.01 to 16). Physics, animation and `Game.clock` follow it | Engine |
| `seed [n]` | Shows or reseeds the gameplay RNG. The same seed replays the same rolls and new map instances | `Game.rng` |
| `screenshot [path]` | Saves the next frame, without the console, to `user://screenshots/` by default | `Debug.screenshot` |
| `clear` | Clears the console | UI |

These commands are reused from the systems that register them. Debug does not register them again:

| Command | Registered by | Debug's addition |
|---|---|---|
| `save [slot]`, `load [slot]`, `saves`, `delete_save <slot>`, `reset_save [slot]` | `Game` (deferred) | the alias `reset` → `reset_save` |
| `map_warp`, `map_info`, `map_link_mode`, `map_reload` | `MapSession` | completion kinds only |
| `quests`, `quest <id>`, `quest_accept`, `quest_complete <id> [force]`, `quest_reset` | `QuestService.register_debug_commands` (Game wires `Game.quests`) | the `quest` dispatcher and `quest forfeit` |

### Quests

`quest` is a Debug-owned composite command. Its subcommands map onto the QuestService's own commands:

- `accept`, `complete` (`force` first satisfies the kill, use, talk, visit and quiz objectives) and `reset` call
  `quest_accept`, `quest_complete` and `quest_reset`.
- `quest <id>` and `quest status <id>` call the QuestService's `quest <id>`, which stays registered as the
  dispatcher's fallback.
- `list` calls `quests`.
- `forfeit` is new. It calls `QuestService.forfeit()`, which takes back the accept items.

The service is found through the owner of the registered `quest_accept`, else through `Game.quests`. If the game has
neither, Debug creates an **unattached** fallback QuestService that follows `Game.character`, and its output says so.
It is not attached on purpose: an attached debug service would stand in for the game's wiring and double-count
progress once the game wires its own.

### Level

- **Up.** For each level, `level <n>` feeds `Game.gain_exp` exactly `exp_to_next(level) - exp`, so every level-up is
  Progression's own. The result: +AP, +SP, base max HP/MP from `hp_mp_gain.json`, the level-up heal, one
  `leveled_up` per level, and EXP 0 at the target. The base max HP equals MeowDB's job total
  (`Progression.base_max_hp_mp`); the tests check it.
- **Down.** Progression has no level-down. `level <n>` subtracts `Progression.level_up_gains(job, lv)` for each level
  above n: AP, SP, base max HP and base max MP. It then sets EXP to 0, clamps HP/MP to the new maxima, and emits
  `stats_changed`, `hp_changed` and `mp_changed`. If the AP or SP to take back has already been spent, the command
  refuses and changes nothing. Spent points stay where they were put; `reset_save` gives a clean character.

### Kill

`kill` prefers the monster's own death path. If the node has a zero-argument `debug_kill()`, `kill()` or `die()`
(checked by required-argument count), that method runs, and the monster system then grants EXP, rolls drops, emits
`monster_killed` and frees the slot. Otherwise, the slot is reported through `MapSession.report_monster_killed(node)`
(or the view's `notify_node_killed`), a debug spawn is freed, and Debug emits `Events.monster_killed(mob_id, map_id)`
itself, so quest kill objectives still count. That path gives no EXP and no drops, and the output says so. Without a
world (pure session), `kill` marks alive slots dead in `MapSession.instance_state` and emits `monster_killed`.

### Debug spawns

Debug spawns are non-canonical and never occupy a spawn slot:

- **Creation.** They are created by the view's `monster_factory`: the monster system's factory once it is installed,
  else the static proxy. Each gets a `SpawnSlot` with `index -1`, `placement "debug"`, grounded with the world's
  `GroundQuery`.
- **Metadata.** Each node carries `debug_spawn = true`, `non_canonical = true`, `spawn_slot = -1`, `mob_id` and
  `map_id`. The `default_proxy` meta is removed, so the view's proxy pool never adopts the node.
- **Ownership.** `MapInstanceView.nodes` and the instance state never see these nodes. Debug keeps its own list.
- **Removal.** They are removed on `Events.map_left`, on the session's `transition_started`, and on `reload`, through
  the view's `monster_releaser` when one is set, else `queue_free`.
- **Death.** With the monster system installed, they are real `Monster`s. The player can attack them (they are
  children of the view, which `MonsterSystem.live_monsters()` scans). Killed in play or by `kill`, they die like any
  monster: canonical EXP through `Game.gain_exp`, the drop roll and `loot_dropped`, and `monster_killed`. That is
  what makes them useful for checking those paths. Only the slot state is never touched.

### God mode

`god on` renews the player's invulnerability (`set_invulnerable(0.25)`) every physics tick. The player blinks
(`PlayerVisual`) for the whole time, which also shows that god mode is on. God mode also locks HP: any
`hp_changed` below the maximum refills HP, so damage paths that ignore invulnerability cannot kill the player either.
After `god off`, the last 0.25 s window runs out. A death announced before any `hp_changed` (HP set to 0 and
`player_died` emitted directly) is not undone.

## The overlay (F3)

Refreshed 4 times a second (`DebugOverlay.REFRESH_S`). Example from Snail Hunting Ground I:

```
FPS 1057  frame 0.9 ms  (process 47.8, physics 0.7)
MAP  000000040  Snail Hunting Ground I  [Maple Road]
     v8 40000  SnailHuntingGround1_40000  hunting
SESSION IDLE  respawn 000000060
     last 000000001 -> 000000040 via debug at t=1.6s, grounded in 1 frames
POS  world (56.02, 13.00, 245.31)  local (37.57, 2.00, -10.63)
     region map:000000040
PLAYER grounded yes  climbing no  invuln no  HP 50/50  MP 5/5  Lv 1
MOBS live 29 (capacity 30)  slots alive 29/40  next tick in 3.5s (every 7.56s)  debug spawns 2
CAMERA ortho 15.30 m  bounds set
DEBUG spawns mobregion
```

The overlay reads each line from these sources:

- **FPS and timing.** FPS from `Engine.get_frames_per_second()`. The frame time is smoothed real time. Process and
  physics times come from `Performance`.
- **MAP.** The map comes from `MapDefinition`.
- **SESSION.** The state comes from `MapSession`, with the last `TransitionRecord`, its frames-to-ground, and whether
  it was re-placed.
- **POS.** The position is `player.global_position`, shown as world coordinates and map-local through
  `MapDefinition.to_local`. The region is `RegionIndex.region_of`.
- **PLAYER.** Grounded, climbing and invulnerable come from the controller. HP/MP are the character's, against the
  derived maxima.
- **MOBS.** `live` is `MapInstanceView.live_count()`. `capacity` and the alive slots come from `MapInstanceState`.
  The next tick is `SpawnModel.boundary_time` of the next global boundary on `Game.clock`.
- **CAMERA.** The ortho size is the rig's.

## Draw layers

Lines are an unshaded vertex-colour mesh (`PRIMITIVE_LINES`). The collision wireframe is depth-tested and pulled 4 cm
toward the camera, so it sits on the surfaces it outlines. Every other layer, and every label, draws over the scene.
Static layers rebuild when the map changes. The `spawns`, `bounds` and `safeground` layers refresh every 0.25 s.
`DebugDraw` lives under the `IslandWorld` and is created the first time a layer is turned on while a world exists. A
layer turned on before that is drawn as soon as a world attaches.

| Layer (command) | Shows | Source |
|---|---|---|
| `collision` | Every collision shape whose bounds meet the map's box (footprint + 1.5 m, map height -3/+6 m). Concave triangles are kept when their centroid is inside the box, which matters because the island body is one shape. Walkable is green, blocking orange, scenery blue | `IslandWorld.collision_root`: concave faces, boxes, other shapes from their debug mesh (AABB fallback) |
| `spawns` | Spawn areas (cyan, with species); every `SpawnSlot`: alive green, dead red with the seconds until it may respawn, unfilled grey ("(unfilled)", above capacity); live monster nodes (yellow, with a line to their slot); debug spawns (magenta) | `MapDefinition.spawn_areas` and `monster_spawn_definitions`, `MapInstanceState`, `MapInstanceView.nodes` |
| `portals` (`portaldata`) | Trigger boxes; anchors; arrival points with their facing arrow; labels `name -> map.portal (name)` with kind, link mode and MeowDB type, `hidden` for type 1, `disarmed` when anti-ping-pong holds it. Doors are amber, hidden portals grey, the arrival gate violet | `PortalDef`, `WorldPortal.armed` |
| `npcs` | NPC anchors with talk radius and `name (npc id)`, marked `fallback` when the NPC had no Blender marker | `NpcPlacement`, `presentation.json npc.interaction_radius_m` |
| `camera` (`bounds`) | `MapDefinition.camera_bounds`; the rig's live view rectangle and its clamp rectangle | camera rig `focus_point`, `view_half_extents`, `bounds_rect`, ground axes |
| `mobregion` | The mob region | `SpawnSlotPlanner.mob_region` |
| `rings` | The current map's containment ring | `IslandWorld.containment_root/Ring_<id>` boxes |
| `safeground` | The SafeGround point in use, and the fall-recovery height (`kill_y`) as a rectangle | `IslandWorld.safe_point()`, `MapDefinition.kill_y` |

## Testing

```bash
ISOLATE=<name> bash scripts/test.sh test_debug                  # registry, resolve, commands, autoload, UI (world tests SKIP)
ISOLATE=<name> INCLUDE_WORLD=1 bash scripts/test.sh test_debug  # + the commands on the real island (56 tests)
```

| File | Covers |
|---|---|
| `test_debug_registry.gd` | The contract (PackedStringArray arguments, case-insensitive names, blank lines), quoting and `;` chains, suggestions, aliases resolved at run time, composites keeping earlier and later registrations as fallback, freed owners, history bounds, `help` listing every command (the brief's list included), the QuestService's own bare-instance pattern still working |
| `test_debug_resolve.gd` | All 25 maps by MeowDB id, v8 id and slug; short ids and names; "Mushroom Town" ambiguity; items, monsters and quests by id and name; portal ids; search; Tab completion of commands, map ids, names to ids, portals of a map, items, quest subcommands and ids |
| `test_debug_commands.gd` | On a `DebugHarness`, with no world: warp to every one of the 25 maps through the command, v8, name, portal and `tp`; warp failures (unknown, ambiguous, bad portal, dead); `portals`, `where`, `maps`, `reload`, `linkmode` (warp, edge, unknown, bad); `respawn`; kill without a world (slots and `monster_killed`); spawn input and its "needs the world" path; `drops`; `exp`; `level` up (AP, SP and HP/MP equal to Progression and MeowDB's job total) and down (reversal, refused when AP was spent); `ap`; `heal`; `god` (HP lock); `char` and `inv`; `give` by id, name and quotes, ambiguity, full tab; `mesos` add, spend and refuse; `clearinv`; quest accept, status, complete with and without `force`, the canonical rewards, `quests`, reset and forfeit through the fallback service and through `Game.quests`; `save`, `load` and `reset` reused from Game; `timescale`, `seed` replay, `screenshot` headless; the overlay text naming the map; every layer toggled without a world |
| `test_debug_autoload.gd` | The real autoload: built-ins installed in `_ready` next to MapSession's and the QuestService's commands; read-only and failing commands; `Debug.run("warp 000000040")` against the autoloads, then MapSession and the character restored |
| `test_debug_ui.gd` | `debug_ui.tscn` headless: a CanvasLayer with `setup(ctx)`; `` ` `` opens a modal console (push_modal, window_opened, backtick not typed) and Esc closes it; F3 and the `overlay` command; lines through `Debug.run`, echo, history Up/Down with the draft kept, Tab completion of names and command prefixes, commands run by code mirrored, `clear`; the layer above the ScreenFader and the shell's screens; the player's InputSource parked while the console is open and restored on close, also through PlayerCombat's `AttackLockInput` in both orders (decorator first, or re-wrapping the idle source); other UI's `_input` handlers under `ui_root` and `systems` fenced while the console is open and restored on close; the UI leaving the tree with the console open hands the modal, window, input source and fence back |
| `test_debug_world.gd` (INCLUDE_WORLD=1) | The real island (collision only) attached to the harness session: warp to all 25 maps with portals and instances swapped and the overlay following; every layer builds lines and labels in 000000040, follows a map change, and clips collision to the map; debug spawns are flagged, never in a slot, counted by the overlay, killed and removed by `reload` and by warps; `kill nearest` and `kill all` through the view with one `monster_killed` each; with the real `MonsterSystem` factory installed, `kill` runs `Monster.die()` (EXP through `Game.gain_exp`, exactly one `monster_killed`, the slot freed) and debug spawns are real, attackable Monsters that never occupy a slot; `reload` realizes a full instance; `goto` (slot, portal, npc, outside, bad slot) and `coords` with a player |

**Sandbox** (windowed; run it from an ISOLATE copy, never against `game/`). The sandbox starts a quick-start game in
slot `debug_sandbox` with autosave and save-on-quit off, so a run never writes a real save:

```bash
cd _scratch/godot_runs/<name>/game
bash ../../../../scripts/godot.sh --path . --resolution 1600x900 --disable-vsync res://scenes/debug/debug_sandbox.tscn -- \
  --map 000000040 --steps "@console open; help; @wait 0.6; @shot <dir>/console.png; @console close; overlay on; collision on; @wait 0.6; @shot <dir>/collision.png; @quit"
```

Steps are separated by `;`. A step is either a console command or one of these:

- `@wait <s>`
- `@shot <path>`
- `@console open|close`
- `@walk <x> <z> <s>`
- `@quit`

Commands are typed through the console, so they appear in its output.

### Visual check (2026-10-04, 1600x900)

- **Console** with `help`. A dark panel over the top 46% of the screen holds monospace output, the scroll bar, the
  hint line and the input. Every command's help is listed, including Game's `save`, `saves` and `reset_save`, and
  the aliases.
- **Overlay** (Snail Hunting Ground I). The panel sits top right, and every line above is legible over the scene.
- **Collision.** Green walkable outlines follow the terraces and paths. Orange blocking hulls show the stair rails,
  the signpost, the birch trunks and the cliff faces.
- **Spawns** (`goto slot 12`, `kill nearest`, `spawn 2 2`). Green labelled slots such as `#3 Snail` sit under live
  snails. The killed slot shows red `#12 Snail 11.2s`. Unfilled slots are `-` in that shot; they now show grey
  `(unfilled)`. The two debug snails are magenta, and the spawn-area outlines and mob region are visible.
- **Portals** (Snail Hunting Ground II, `warp 000000041 east00`). The cyan trigger box surrounds the swirl, labelled
  `east00 -> 000000042.west00 (Snail Hunting Ground III) [edge, link warp, type 2]`. The arrival circle and arrow sit
  under the player.

### In the real game (review, 2026-10-04, `res://scenes/main.tscn`)

The setup was a new game through `MainShell.start_new_game`, with all 7 subsystems installed. It was driven with real
key events (`Input.parse_input_event`) and `Debug.run`.

**Keys and input**

- `` ` `` opens the console as a modal (the backtick is not typed). `help` lists every command.
- Walk keys do nothing while the console is open, even after a `warp` typed into it.
- The player walks again after the console closes with Esc, with `` ` ``, after a warp typed into it, and after the
  pause menu.
- The console draws over the warp fade and over the pause menu.
- Over an open NPC dialogue, `mesos 25` runs, the dialogue keeps its line, and the dialogue takes Enter again once
  the console closes.
- Up recalls history. Tab turns `give red pot` into `give 270 `.

**Overlay and layers**

- The F3 overlay shows every line, with `MOBS live 30 (capacity 30)`.
- `collision`, `spawns` and `portaldata` draw in Snail Hunting Ground I (80,490 / 1,238 / 68 lines).

**Monsters and character**

- `spawn snail 3` makes real Monsters through the monster system's factory.
- `kill nearest` and `kill all` go through `Monster.die()`: EXP is awarded and Lv 1 becomes 3.
- `god on` makes the player invulnerable, and `god off` releases it within its 0.25 s window. The HP lock under real
  contact damage is unit-tested only.
- `give`, `mesos`, `level 5`, `level 3`, `exp`, `quest accept` and `quest complete ... force` all work.

**Maps, saves and tools**

- `reload`, `linkmode`, `timescale`, `seed`, `drops` and `screenshot <path>` work; the file was written.
- `warp` into an interior and `tp southperry` work.
- In a scratch slot, `save`, `load` (the inventory reverted), `reset` (a fresh character in 000000001) and
  `delete_save` work in place. The debug UI and overlay keep working after `load` and `reset`.

## Known limits and requests

- **`kill` without a monster death method.** A monster with no `debug_kill()`, `kill()` or `die()` gives no EXP or
  drops when killed from the console. The monster system should expose `debug_kill()` running its normal death.
- **Debug spawns and the monster system's factory.** These spawns go through the monster system's `monster_factory`
  with `slot.index == -1`. A factory or AI that assumes a real slot index should treat -1 as "no slot": do not report
  it to the view, and do not respawn it.
- **The context is duck-typed.** `Debug.ctx` and `DebugUI.setup()` take any `Object` with the `GameContext` fields
  and methods, so the debug tools never depend on the shell's script compiling. The sandbox uses the real
  `GameContext` and falls back to a stand-in only when that script does not load.
- **Other modals and the keyboard (requests).**
  - **GameContext.** It has no "top modal" query, so `DialogueWindow` and `ShopWindow` cannot tell that a newer modal
    owns the keys. The console fences their `_input` instead (see "Modal input"). A `GameContext.top_modal()` would
    let each window yield by itself.
  - **MapSession.** It re-enables the player's controller at the end of every transition
    (`IslandWorld.set_player_input(true)`) without checking `ctx.is_modal_active()`. The console's parked input
    source covers this for the console.
- **Collision layer cost.** The collision layer rebuilds on every map change while it is on: about 80,000 segments in
  Snail Hunting Ground I, roughly 0.1 to 0.3 s on the dev machine.
- **Tuning.** Label and line sizes were tuned at 1600x900 only.
- **Not built.** Console history is not saved between runs. There are no per-command permissions; the console is
  available in every build. The `edge` link mode waits for M2 gates.
