# MisoStory runtime architecture (Iterations Two and Three)

This is the integration contract for the playable game. It says where everything lives, who owns it, and how the
pieces talk. The map/world model is specified separately in [`MAP_ARCHITECTURE.md`](MAP_ARCHITECTURE.md); the
Blender export in [`blender_export.md`](blender_export.md); canonical data in [`../canonical/`](../canonical/). The
interfaces Iteration Three's parallel packages built against (drop records v2, the drop roll context, the save v2
fields, player activity, chairs, test evidence, provenance authorities, breakables) are in
[`ITERATION_THREE_CONTRACTS.md`](ITERATION_THREE_CONTRACTS.md).

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
game/data/canonical/**   sourced facts (MeowDB MS Classic;     game/data/misostory/**   isometric adaptation data
                         Henesys.gg rarity labels)                                  (and the owner's drop chance table and meso rule)
    ▲
tools/meowdb (cache-only extractors) + tools/*/captures (dated pages read by hand) + tools/sources (loader, drop records)
```

## Engine and conventions

- **Godot 4.7.2**, GDScript, Forward+ renderer, Jolt physics, 60 physics ticks/s. Get the binary with
  `bash scripts/godot.sh --version` (downloads to `%LOCALAPPDATA%/MisoStory/godot/4.7.2/` on first use, on Linux
  to `~/.local/share/MisoStory/godot/4.7.2/` unless a 4.7.2 `godot` is on `PATH`; override with `GODOT=...`).
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
| `game/data/canonical/<domain>/<id>.json` | sourced facts, one entity per file, each with `source{authority,url,retrieved_at}` (MeowDB) and, where a property comes from another authority, `provenance.<property>` (Henesys.gg rarity labels; schema 3 drop records cite MeowDB membership and Henesys.gg rarity per entry, and hold no probability) |
| `game/data/canonical/canonical_sources.json` | generated provenance index: every record → its URLs, capture files and per-property authorities |
| `game/data/misostory/**` | adaptation: crosswalk, world scale, movement/camera feel, spawn rules, dialogue scripts and rules, recovery, skills, breakables, drop interpretations (no rates), the stuck-scan allowlist |
| `game/assets/world/` | generated Blender export (glTF chunks + sidecar JSON); git-ignored, rebuilt by the pipeline |
| `game/scripts/autoload/` | autoload singletons (below) |
| `game/scripts/core/` | pure rules: formulas, stats, progression, inventory, equipment, chairs, quests, dialogue, shop, drops, skills, breakables, maps, saves, data validation |
| `game/scripts/world/` | world/chunk loading, map regions, portals, ladders, spawn manager |
| `game/scripts/actors/` | player controller (sitting, `activity()`), camera rig, combat (attacks, skills, effects, natural recovery), monsters, breakables, NPCs (speech bubbles), drops-on-ground, damage numbers |
| `game/scripts/ui/` + `game/scenes/ui/` | HUD, windows (inventory, equipment, stats, quests, skills), the minimap, screens (title, creation, death, departure) |
| `game/scripts/debug/` | debug console, overlays |
| `game/tests/` | `test_runner.tscn`, `test_case.gd`, `unit/test_*.gd`; `data/` fixtures (parity vectors, drop records, Iteration Two saves) |
| `game/tools/` | headless tools: `validate_data.gd`, the playtest harness (`playtest/`), the stuck-region scan (`stuck_scan*.gd`), traversal bot, screenshot capture |
| `tools/meowdb/` | development-time MeowDB extractors (Node, cache-only); cache in `tools/meowdb/.cache` (git-ignored); hand-read captures in `captures/` |
| `tools/henesys/captures/` | Henesys.gg item rarity labels read by hand (no extractor; see its README) |
| `tools/sources/` | the offline capture loader, exact raw-value parsers, the drop record builder (`drops_merge.mjs`), the spawn-capture check (`node --test tools/sources/test/`) |
| `tools/parity/` | the parity manifest generator (`build_parity.mjs`, `rules.json`) |

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
autoload list (Iteration Three added none). If a system truly needs a new signal, add it to `events.gd` with a comment
naming the emitter; Iteration Three added only additive ones (`player_sat_down` / `player_stood_up`,
`skill_leveled`, `skill_used`, `effects_changed`).

## Shared contracts

- `scripts/core/character/character_state.gd` (`CharacterState`) is the persistent character: base values only
  (level, EXP, HP/MP, `base_max_hp/mp`, `base_stats` {str, dex, int, luk}, AP, SP, fame, mesos, skills
  `{skill_id: level}`, effects and cooldowns in remaining seconds, the natural-recovery clock, location, respawn
  reference, typed quickslots `{key: {kind: item | skill, id}}`, flags). Derived totals (max HP with gear, total
  stats, ACC, EVA, W.ATK, damage range) are always computed, never stored. Saves are `save_version` 2 (contract C3,
  [SAVES.md](SAVES.md)); the seated state, breakables, monsters and ground drops are never saved.
- `PlayerController.activity()` (contract C4) says what the player is doing (`still`, `walking`, `jumping`,
  `climbing`, `attacking`, `seated`, ...); natural recovery and the playtests read it.
- `DropRoller.roll(owner_id, db, rng, ctx)` (contract C2) is the one way loot is rolled, for monsters and breakables
  alike, with `ctx = DropRoller.context_for(character)` (the quests in progress, for quest-gated drops).
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
  agents never share a `.godot/` import cache; `INCLUDE_WORLD=1` mirrors the exported world for the world tests.
- `TEST_EVIDENCE_OUT=<file>` writes the machine-readable test evidence (contract C6); a test file declares the parity
  rows it proves in `parity_keys()`.
- Tests extend `TestCase`, use `db()` for the real shipped content, and must be deterministic: every random roll
  goes through an injectable RNG (`RandomNumberGenerator` with a fixed seed in tests).
- One test process builds the island many times; `project.godot` raises Jolt's body cap
  (`physics/jolt_physics_3d/limits/max_bodies` 65536) because freed collision bodies' slots are evidently not reused
  within a process (inferred from the fix, not root-caused; HOWTO "Run automated tests").
- Real-game playthroughs: `bash scripts/playtest.sh <scenario>` and `bash scripts/playtest_quests.sh`
  ([PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md)).

## System documents

| System | Document |
|---|---|
| Map model, portals, transitions, spawns and spawn placement | [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md), [WORLD_RUNTIME.md](WORLD_RUNTIME.md) |
| Blender → runtime export | [blender_export.md](blender_export.md) |
| Combat mathematics, stats, progression, the Beginner skills | [COMBAT.md](COMBAT.md) |
| Items, inventory, equipment, consumables, chairs, shops, drops (schema 3 records, the owner's rule files, the roller) | [ITEMS.md](ITEMS.md) |
| Quests, dialogue, NPC definitions, the departure boundary | [QUESTS_AND_DIALOGUE.md](QUESTS_AND_DIALOGUE.md) |
| Character creation, game state, saves (v2) and migrations | [SAVES.md](SAVES.md) |
| Player controller (activity, sitting) and camera | [PLAYER_AND_CAMERA.md](PLAYER_AND_CAMERA.md) |
| Canonical data validation, provenance authorities, the provenance report | [DATA_VALIDATION.md](DATA_VALIDATION.md) (`bash scripts/validate_data.sh`) |
| Game shell: boot, title, creation, loading, pause, death and respawn, subsystem installer | [GAME_SHELL.md](GAME_SHELL.md) |
| Live monsters, the Wooden Box, player attacks, contact damage, natural recovery, damage numbers | [MONSTERS_AND_COMBAT_RUNTIME.md](MONSTERS_AND_COMBAT_RUNTIME.md) |
| Interaction prompts, NPC presentation and speech bubbles, dialogue and shop windows, ground loot | [INTERACTION_AND_NPC_UI.md](INTERACTION_AND_NPC_UI.md) |
| HUD, inventory, equipment, stats, quest and skills windows, the minimap, MisoTheme | [UI.md](UI.md) |
| Developer console, overlay, debug draw layers | [DEBUG_TOOLS.md](DEBUG_TOOLS.md) |
| How to build, export, launch, test, validate, playtest, scan and use the debug tools | [HOWTO.md](HOWTO.md) |
| Adding content (sources and captures, drops, quests, monsters, spawns, breakables, skills, chairs, NPCs, maps) | [CONTENT_AUTHORING.md](CONTENT_AUTHORING.md) |
| The Iteration Three contracts (C1-C8) | [ITERATION_THREE_CONTRACTS.md](ITERATION_THREE_CONTRACTS.md) |
| Playthrough validation report (Iteration Two's Tests A-G and the reviews) | [PLAYTHROUGH_REPORT.md](PLAYTHROUGH_REPORT.md) |
| Automated playthroughs of the real game, the every-quest set, strict mode | [PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md) |
| The stuck-region scan of every map | [STUCK_SCAN.md](STUCK_SCAN.md) |
| Canonical data, its sources and gaps; the parity manifest | [`../canonical/README.md`](../canonical/README.md), [`../MAPLE_ISLAND_PARITY.md`](../MAPLE_ISLAND_PARITY.md) |
