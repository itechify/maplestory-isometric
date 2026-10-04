# MisoStory runtime architecture (Iteration Two)

This is the integration contract for the playable game. It says where everything lives, who owns it, and how the
pieces talk. The map/world model is specified separately in [`MAP_ARCHITECTURE.md`](MAP_ARCHITECTURE.md); the
Blender export in [`blender_export.md`](blender_export.md); canonical data in [`../canonical/`](../canonical/).

```
Blender (src/misostory, MapleIsland.blend)          environment source of truth
    │  scripts/export_runtime.py                     repeatable export: glTF chunks + gameplay sidecars
    ▼
game/assets/world/*.glb + *.json                     generated, never hand-edited
    │  scripts/world/*                               runtime world: chunks, collision, portals, regions
    ▼
MisoStory systems (game/scripts/*)                   player, camera, monsters, combat, items, quests, UI, saves
    │  ContentDB (Data autoload)
    ▼
game/data/canonical/**   MeowDB MS Classic facts      game/data/misostory/**   isometric adaptation data
```

## Engine and conventions

- **Godot 4.7.2**, GDScript, Forward+ renderer, Jolt physics, 60 physics ticks/s. Get the binary with
  `bash scripts/godot.sh --version` (downloads to `%LOCALAPPDATA%/MisoStory/godot/4.7.2/` on first use; override
  with `GODOT=...`).
- **Coordinates:** Godot is Y-up, meters. Blender Z-up meters convert exactly as the glTF exporter does:
  `godot = (x, z, -y)` of Blender. MapleStory pixel values from MeowDB (y down) are only ever converted through
  `WorldScale` (`game/data/misostory/world_scale.json`), never with ad-hoc constants.
- **Ids are strings**, exactly as MeowDB writes them: maps `"000000010"`, monsters `"2"`, items `"59"`, quests
  `"1002"`. Iteration One's GMS v8 ids survive only as `gms_v8_id` in `data/misostory/map_id_crosswalk.json` and in
  Blender collection names (`MushroomTown_10000`).
- Style: typed GDScript, tabs, `snake_case`, `class_name` for every reusable module, doc comments (`##`) on every
  public class. Pure rules live in `scripts/core/` and never touch the scene tree, so they are unit-testable.
- **No canonical number in code.** Gameplay values come from `Data.db` (canonical) or adaptation tables
  (`data/misostory`). Constants that are MisoStory feel decisions live in `data/misostory/*.json` with a `reason`.

## Directory layout and ownership

| Path | Contents |
|---|---|
| `game/project.godot` | project settings and autoload registration |
| `game/data/canonical/<domain>/<id>.json` | MeowDB facts, one entity per file, each with `source{authority,url,retrieved_at}` |
| `game/data/canonical/canonical_sources.json` | generated provenance index: every record → its MeowDB URL(s) |
| `game/data/misostory/**` | adaptation: crosswalk, world scale, movement/camera feel, spawn regions, dialogue scripts, placeholder rates |
| `game/assets/world/` | generated Blender export (glTF chunks + sidecar JSON); git-ignored, rebuilt by the pipeline |
| `game/scripts/autoload/` | autoload singletons (below) |
| `game/scripts/core/` | pure rules: formulas, stats, progression, inventory, equipment, quests, dialogue, shop, drops, saves |
| `game/scripts/world/` | world/chunk loading, map regions, portals, ladders, spawn manager |
| `game/scripts/actors/` | player controller, camera rig, monsters, NPCs, drops-on-ground, damage numbers |
| `game/scripts/ui/` + `game/scenes/ui/` | HUD and windows |
| `game/scripts/debug/` | debug console, overlays |
| `game/tests/` | `test_runner.tscn`, `test_case.gd`, `unit/test_*.gd` |
| `game/tools/` | headless tools: `validate_data.gd`, traversal bot, screenshot capture |
| `tools/meowdb/` | development-time MeowDB extractors (Node); cache in `tools/meowdb/.cache` (git-ignored) |

## Autoloads

| Name | Script | Role |
|---|---|---|
| `Events` | `scripts/autoload/events.gd` | global signal bus (see the file for the signal list) |
| `Data` | `scripts/autoload/data.gd` | `Data.db: ContentDB`, loaded at startup |
| `Controls` | `scripts/autoload/controls.gd` | input actions, registered in code (the key map lives there) |
| `Game` | `scripts/autoload/game_state.gd` | the live `CharacterState`, the pausable game clock, the gameplay RNG |
| `Saves` | `scripts/autoload/save_service.gd` | versioned save/load of logical state |
| `MapSession` | `scripts/autoload/map_session.gd` | `current_map` and `transition()` ([MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) §4.3) |
| `Debug` | `scripts/autoload/debug_tools.gd` | console command registry and overlays |

All autoloads are registered up front; systems fill in their owned scripts and never edit `project.godot`'s
autoload list. `Events` is complete (MAP_ARCHITECTURE §4.3 needs no new signals); if a system truly needs a new
signal, add it to `events.gd` with a comment naming the emitter.

## Shared contracts

- `scripts/core/character/character_state.gd` (`CharacterState`) is the persistent character: base values only
  (level, EXP, HP/MP, `base_max_hp/mp`, `base_stats` {str, dex, int, luk}, AP, SP, fame, mesos, skills, effects,
  location, respawn reference, quickslots, flags). Derived totals (max HP with gear, total stats, ACC, EVA, W.ATK,
  damage range) are always computed, never stored.
- `Inventory` (`scripts/core/items/inventory.gd`), `Equipment` (`scripts/core/items/equipment.gd`) and `QuestLog`
  (`scripts/core/quests/quest_log.gd`) each own `to_dict()` / `static from_dict()`; `CharacterState` composes them.
- `data/misostory/world_scale.json`: `horizontal_px_to_m` 0.02 (ground distances and speeds), `vertical_px_to_m`
  0.0117 (heights, jumps), `actor_px_to_m` 0.025 (hit boxes, touch zones, pickup box, reach).
- Input action names: `Controls.BINDINGS` (`move_*`, `jump`, `attack`, `interact`, `portal_enter`, `climb_down`,
  `pickup`, `sit`, `toggle_*`, `quickslot_1..8`, `menu`, `debug_console`, `debug_overlay`).

- `scripts/game/game_context.gd` (`GameContext`): what the main scene hands every gameplay subsystem
  (`setup(ctx)`): `world`, `player`, `camera`, `ui_root`, `systems`, plus the modal-input stack (`push_modal` /
  `pop_modal`: dialogue, shop, console and menus take the keyboard; inventory-style windows do not) and the window
  stack (`window_opened` / `window_closed` / `close_top_window`, so Esc closes the newest window first).
- `Events.loot_dropped(drops, world_position, map_id)`: the monster system announces loot; the loot system puts it
  on the ground.

## Testing

- `bash scripts/test.sh [filters...]`: headless import, then every `game/tests/unit/test_*.gd`. Prints
  `TESTS_PASSED`/`TESTS_FAILED`, exits non-zero on failure.
- `bash scripts/validate_data.sh`: canonical-data validation through the game's own loader (exit 1 on broken
  references, 2 if the validator itself is broken).
- `ISOLATE=<name> bash scripts/test.sh` runs in a private mirror under `_scratch/godot_runs/<name>/` so concurrent
  agents never share a `.godot/` import cache.
- Tests extend `TestCase`, use `db()` for the real shipped content, and must be deterministic: every random roll
  goes through an injectable RNG (`RandomNumberGenerator` with a fixed seed in tests).
## System documents

| System | Document |
|---|---|
| Map model, portals, transitions, spawns | [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md), [WORLD_RUNTIME.md](WORLD_RUNTIME.md) |
| Blender → runtime export | [blender_export.md](blender_export.md) |
| Combat mathematics, stats, progression | [COMBAT.md](COMBAT.md) |
| Items, inventory, equipment, consumables, shops, drops | [ITEMS.md](ITEMS.md) |
| Quests, dialogue, NPC definitions | [QUESTS_AND_DIALOGUE.md](QUESTS_AND_DIALOGUE.md) |
| Character creation, game state, saves | [SAVES.md](SAVES.md) |
| Player controller and camera | [PLAYER_AND_CAMERA.md](PLAYER_AND_CAMERA.md) |
| Canonical data validation | [DATA_VALIDATION.md](DATA_VALIDATION.md) (`bash scripts/validate_data.sh`) |
| Game shell: boot, title, creation, loading, pause, death and respawn, subsystem installer | [GAME_SHELL.md](GAME_SHELL.md) |
| Live monsters, player attacks, contact damage, damage numbers | [MONSTERS_AND_COMBAT_RUNTIME.md](MONSTERS_AND_COMBAT_RUNTIME.md) |
| Interaction prompts, NPC presentation, dialogue and shop windows, ground loot | [INTERACTION_AND_NPC_UI.md](INTERACTION_AND_NPC_UI.md) |
| HUD, inventory, equipment, stats and quest windows, MisoTheme | [UI.md](UI.md) |
| Developer console, overlay, debug draw layers | [DEBUG_TOOLS.md](DEBUG_TOOLS.md) |
| Automated playthroughs of the real game (`bash scripts/playtest.sh <scenario>`) | [PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md) |
