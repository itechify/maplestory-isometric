# Character creation, game state and saves

This system creates new characters, owns the live game (`Game` autoload), and saves and loads it (`Saves`
autoload). It covers the character-state part of brief Phase 6, Phase 19 (save/load), "Save Versioning" and the
Phase 21 "Saves" tests. The persistent character itself is `CharacterState`
(`scripts/core/character/character_state.gd`, a shared contract this system does not own). Its position fields
follow [MAP_ARCHITECTURE.md](MAP_ARCHITECTURE.md) §4.8–4.9.

## Code map

| File | Role |
|---|---|
| `scripts/core/character/character_factory.gd` | `CharacterFactory`: validates the creation choices and builds a level-1 Beginner |
| `scripts/core/save/save_store.gd` | `SaveStore`: slot files, atomic writes, one `.bak`, error codes on read. No game knowledge |
| `scripts/core/save/save_document.gd` | `SaveDocument`: builds the envelope; decode = migrate + validate + sanitize the location + `CharacterState.from_dict` |
| `scripts/core/save/save_migrations.gd` | `SaveMigrations`: the v → v+1 registry and `CURRENT_VERSION` |
| `scripts/core/save/save_load_result.gd` | `SaveLoadResult`: what a read returns (error, character, world, meta, warnings) |
| `scripts/autoload/save_service.gd` | autoload `Saves` (`class_name SaveService`): wires the store to `Game` and `MapSession` |
| `scripts/autoload/game_state.gd` | autoload `Game` (`class_name GameState`): live character, clock, RNG, lifecycle, autosave |
| `data/misostory/new_character.json` | the creation values MeowDB does not publish (marked adaptations) |

Everything in `scripts/core` is pure. It does file IO but never touches the scene tree.

## Character creation

`CharacterFactory.create(params, db) -> CharacterFactory.Creation` returns `{ok, character, errors, warnings,
weapon_placement}` and never returns null. The params are:

```gdscript
{"name": "Maple", "ap": {"str": 5, "dex": 4}, "weapon_id": "585"}
```

| Rule | Source |
|---|---|
| Level 1 | canonical `formulas/beginner.json` `starting_level` |
| Base stats: 4/4/4/4 plus the creation AP | canonical `starting_stats` |
| Creation AP: exactly `creation_ap` (9) points over `ap.allocatable_stats` (STR/DEX/INT/LUK), each a whole number ≥ 0; unknown keys rejected | canonical `creation_ap`, `ap.allocatable_stats` |
| Free AP after creation = `free_ap_at_level_1 − creation_ap` (= 0) | canonical `ap` |
| Base max HP = `hp_mp.base_hp` (50), base max MP = `hp_mp.base_mp` (5). HP and MP start full at the derived maxima (`StatCalculator.max_hp/max_mp`), which are 50/5 because the starter weapon adds no HP or MP | canonical `hp_mp` (the level-1 row of `by_level_1_to_10` agrees) |
| Starter weapon: one of the items flagged `beginner_creation_weapon` (541 Sword, 576 Hand Axe, 585 Wooden Club). Razor 558, a level-5 starter weapon, is refused | canonical items, cross-checked against `starter_weapons.items` with `level_req` 0 |
| `respawn_reference` = the start map's `return_map_id` | canonical maps |
| Start map 000000001, player spawn 0. `validate()` refuses to create a character if the table names a map that is not canonical, or a spawn index outside that map's `player_spawns` | **adaptation** `start_location` |
| EXP 0, SP 0, mesos 0, fame 0, empty inventory apart from the weapon | **adaptation** `starting_*` (SP 0 is MeowDB prose, so it is marked `verified: true`) |
| Weapon equipped, not carried | **adaptation** `starter_weapon.placement` |
| Name: 4–12 ASCII letters and digits. The pattern must match the whole name, because a PCRE end anchor alone also accepts a trailing newline | **adaptation** `name_rules` |

The weapon is placed through the items system's own path. `Inventory.add(id, 1, db)` comes first, then
`Equipment.equip(character, id, db)`, which moves it to the weapon slot after the canonical requirement checks. If
equipping fails, the weapon stays in the bag, `weapon_placement` is `"inventory"` and a warning says why.

`CharacterFactory.default_params(db)` returns the `quick_start` parameters (name "Beginner", 9 STR, Wooden Club),
which follow the Beginner's guide advice. `Game.new_game()` uses them when called without a name, AP or weapon.

`Progression.init_new_character()` (character rules system) is a different helper. It leaves the 9 creation AP
unspent, and only its own tests use it. New games go through `CharacterFactory`, which places the creation AP as
MeowDB describes ("You place your first 9 AP on the character creation screen").

## The Game autoload

The contract members are unchanged: `character`, `clock`, `paused`, `rng`.

| Member | Behaviour |
|---|---|
| `new_game(params := {}) -> Error` | Runs `CharacterFactory` with params plus optional `"slot"` (default `"slot1"`) and `"save"` (default true). It installs the character and writes the initial "clean save". That write bypasses `can_save()`, because the character stands at the canonical start and no world state exists yet. Bad params return `ERR_INVALID_PARAMETER` with the reasons in `last_creation_errors`, and the live game is untouched |
| `load_game(slot := "") -> Error` | Delegates to `Saves.load_game`. On success the character is **replaced wholesale** (new `CharacterState`, `Inventory`, `Equipment` and `QuestLog` objects). On error the live game is untouched |
| `save_game(slot := "") -> Error` | Delegates to `Saves.save_game` (blocked unless `can_save()`). `""` = `current_slot` |
| `reset_save(slot := "", params := {}) -> Error` | Debug. Deletes the slot and its backup, then starts a clean quick-start game in that slot |
| `start_or_continue(slot := "slot1") -> Error` | Boot helper. Loads the slot if it has a save **or only its backup** (see "Atomic write and backup"), otherwise starts a new game there. A save that exists but cannot be loaded is reported and **never overwritten** |
| `request_autosave(reason) -> bool` | Debounced autosave (below) |
| `connect_autosave_triggers(bus)` | Called from `_ready` with `Events`. `map_entered`, `leveled_up`, `quest_started`, `quest_completed` and `quest_forfeited` each request an autosave (`AUTOSAVE_TRIGGERS`), so progress persists even where no system calls `request_autosave` |
| `gain_exp(amount, source)`, `allocate_ap(stat, n)` | Call `Progression` and emit `exp_gained`, `leveled_up` (once per level), `hp/mp/stats_changed`. A level-up requests an autosave. `allocate_ap` passes the db, so the allowed stats are canonical `ap.allocatable_stats` |
| `refresh_ui()` | Emits every refresh signal for the current character |
| `has_active_game()`, `current_slot`, `session_play_time_s`, `format_play_time(s)` | State for the UI |

**Signals when the character is replaced** (new game, load, reset), in this order:

1. `Game.character_replaced(reason)`, where reason is `"new_game"`, `"load"` or `"reset"`. Listeners must drop
   their references to the old character and its composed objects.
2. `Events.stats_changed`, `hp_changed(hp, max_hp)`, `mp_changed(mp, max_mp)`, `mesos_changed(mesos, 0)`,
   `inventory_changed`, `equipment_changed("")`. Here `""` means every slot.
3. On a load only, `Events.game_loaded(slot)`. A load from the backup also emits `Events.notice`.

**Autosave.** A request saves after `autosave_debounce_s` (2 s) with no further request, but never later than
`autosave_max_delay_s` (15 s) after the first request of a burst. While `can_save()` is false it retries every
`autosave_retry_s` (1 s). It saves into `current_slot` and emits `Game.autosave_finished(slot, error)`. The timers run
on real frame time, so `Game.paused` does not delay persistence, and `can_save()` still gates the write. When the
window closes, the game saves if `can_save()` allows it. These timings are engineering choices, not gameplay values,
so they are documented members rather than data. Requests come from `AUTOSAVE_TRIGGERS`, from level-ups, and from
MapSession after every committed transition through `Saves.request_autosave()`.

**Play time.** `character.play_time_s` and `session_play_time_s` grow with unpaused frame time, and only while a game
is active. The total is saved with the character and shown in the slot meta.

**Debug console** (registered with `Debug.register_command`): `save [slot]`, `load [slot]`, `saves`,
`delete_save <slot>`, `reset_save [slot]`.

## The Saves autoload

| Member | Behaviour |
|---|---|
| `SAVE_VERSION: int` | `= SaveMigrations.CURRENT_VERSION` (1) |
| `save_game(slot) -> Error` | Saves `Game.character` with the world block. Needs an active game and `can_save()` |
| `save_character(slot, character, world := {}) -> Error` | Writes without the `can_save()` check (new game, tools, tests) |
| `load_game(slot) -> Error` | `read_for_load`, then `Game.apply_loaded_save(result)` |
| `read_save(slot, from_backup := false) -> SaveLoadResult` | Reads and decodes one file without touching the live game |
| `read_for_load(slot) -> SaveLoadResult` | `read_save(slot)`, or the backup when the save file is **missing** and a backup exists (`source = "backup"`). A save that is present but corrupt is never replaced by its backup here |
| `has_save(slot)`, `delete_save(slot)`, `restore_backup(slot)` | `has_save` is true when the save file exists. `delete_save` removes the save, the `.bak` and any `.tmp` |
| `list_saves() -> Array[Dictionary]` | Slot-picker entries, sorted by slot: `{slot, ok, error, error_text, has_backup, modified_unix, save_version, saved_at, meta, source}`. Each entry is read with `read_for_load`, so it describes what `load_game` would load. Unreadable saves are listed with `ok = false`. A slot with only a backup is listed as loadable with `source = "backup"` |
| `request_autosave(reason := "") -> bool` | Forwards to `Game.request_autosave` (MapSession calls it after each committed transition) |
| `can_save() -> bool` | `MapSession.can_save()`: state `IDLE`, a current map, and a valid SafeGround point when the world is attached. A MapSession without `can_save()` (a contract stub) allows saving |
| `last_error`, `last_error_message` | The last failure, for UI and the console |

The test seams are `save_dir`, `db`, `game_node`, `map_session_node`, `can_save_override`, `world_provider`,
`event_bus` and `log_failures`. `Game` has `save_service`, `db`, `event_bus` and `log_warnings`. Tests never use
`user://saves` or the real autoload state.

### Error codes

| Code | Meaning |
|---|---|
| `ERR_INVALID_PARAMETER` | The slot name is not `^[A-Za-z0-9_-]{1,32}$` (no paths, no dots), or it is a Windows device name (`CON`, `PRN`, `AUX`, `NUL`, `COM0`–`COM9`, `LPT0`–`LPT9`, in any letter case) |
| `ERR_UNAVAILABLE` | Saving is not allowed now (`can_save()` is false) |
| `ERR_UNCONFIGURED` | There is no active game to save |
| `ERR_FILE_NOT_FOUND` | No such save |
| `ERR_PARSE_ERROR` | Empty, truncated or non-JSON file |
| `ERR_FILE_CORRUPT` | Valid JSON that is not a MisoStory save: not an object, wrong `game`, no `character`, or a field of the wrong type (checked against a default `CharacterState`, so new fields are covered) |
| `ERR_INVALID_DATA` | `save_version` newer than this build, invalid, or with no migration path; on write, a value JSON cannot store (Vector3, Object, int dictionary key, INF), refused before any file is touched |
| other | File-system errors from the failing step |

A failed load never crashes and never changes the live game. The one known exception lives in a composed module:
`Inventory.from_dict` resizes a tab to whatever `capacity` or slot `index` the file states, so a hand-edited save
with a huge number there can exhaust memory (reported to the items system).

### File format

The save is written to `user://saves/<slot>.json` (on Windows, `%APPDATA%/Godot/app_userdata/MisoStory/saves/`).
It is tab-indented with sorted keys and full float precision.

```json
{
  "save_version": 1,
  "game": "MisoStory",
  "saved_at": "2026-10-04T12:00:00Z",
  "character": { "...": "CharacterState.to_dict(), verbatim (inventory/equipment/quests are their modules' to_dict())" },
  "world": {"location": {"map_id": "000001000", "entry": {"map_id": "000001000", "portal_id": "west00"}},
            "respawn_reference": "000001010"},
  "meta": {"name": "Maple", "level": 3, "job": "beginner", "map_id": "000001000",
           "map_name": "The Field West of Amherst", "play_time_s": 1234.5}
}
```

- **`world`** is the map/session block. `world` is authoritative: on save the character's copy is set to it, and
  on load it is copied back into `character.location` and `character.respawn_reference`. Monster, drop and spawn
  state is never saved (§4.7.3). It comes from `MapSession.save_world() -> Dictionary`, which the world runtime
  implements (`location` from SafeGround via `capture_location()`). Without `save_world()`, it is the character's
  `location`, checked against MapSession:
  - While `current_map` is `""` (no world yet), the location is kept as it is.
  - When the location is for another map, or its `entry` is not `MapSession.last_arrival` (§4.9 says the entry
    is `last_arrival`, an `ArrivalRef` or a Dictionary), the location is stale. It becomes
    `{map_id: current_map, entry: last_arrival}`, or player spawn 0 when there is no `last_arrival`. It gets no
    `resume`, because only MapSession knows SafeGround.
  - `MapSession.respawn_reference` is used when set.
- **On load**, `SaveDocument.sanitize_location` makes sure MapSession never receives a malformed location:
  - `entry` must be `{map_id: <the location's map>, portal_id: non-empty String}` or `{map_id, spawn_index: int ≥ 0}`
    within that map's `player_spawns`. Anything else becomes `{map_id, spawn_index: 0}`.
  - `resume`, when present, needs `local_pos` (3 finite numbers) and, if present, a finite `facing_deg`. Both are
    re-floated, because JSON turned `135.0` into `135`. A malformed `resume` is dropped, so the entry is used.
  - Other keys are kept, because MapSession owns the format. Every correction is a warning in
    `SaveLoadResult.warnings`.
  - An unknown or empty `location.map_id` falls back to the start location (§4.9 step 4), and
    `respawn_reference` is recomputed from the canonical `return_map_id` (canonical wins; a mismatch is a warning).
- **`meta`** is recomputed on load, so it always matches the character.
- **Numbers.** JSON has one number type. On load, every integral number (|x| ≤ 2^53) becomes an `int`, so ids,
  counts and `spawn_index` come back as ints. A float that happened to be integral (for example `135.0`) comes back
  as the int `135`. GDScript's `==` treats those as equal, but `Dictionary ==` does not, so compare saves with a
  numeric-tolerant deep compare (see `_diff` in `test_save_roundtrip.gd`). Fields typed `float` in
  `CharacterState` are re-floated by `from_dict`, and the `location.resume` numbers by the load sanitizer.

### Atomic write and backup

1. The new text is written to `<slot>.json.tmp`, then read back and compared.
2. If the current `<slot>.json` still parses, it is copied to `<slot>.json.bak`. A corrupt save never replaces a
   good backup.
3. `.tmp` is renamed over `<slot>.json`. If the rename fails after the old file is gone, the save is restored from
   `.bak`.

Any failure leaves the previous save byte-identical. A corrupt save is not silently replaced by its backup when
loading. Instead `list_saves()` reports `has_backup`, and the UI can call `restore_backup(slot)`.

On Windows, `DirAccess.rename_absolute` removes the old file before it moves the new one in. A crash in that window
leaves only `.bak` (and `.tmp`). So a slot whose save file is **missing** loads its backup (`read_for_load`,
`start_or_continue`). Otherwise booting would start a new game in the slot, and the next save would copy that fresh
game over the only remaining progress. The first save after such a load writes the save file and leaves the backup
alone, because there is no current save to rotate into it.

## Versioning and migrations

`SaveMigrations` maps each `from_version` to a step `Callable(doc) -> doc`. `migrate()` applies the steps in order up
to `CURRENT_VERSION` and stamps `save_version` after each one. A save that is newer than this build, carries an
invalid version, or has a missing step is refused with `ERR_INVALID_DATA`. Nothing is guessed.

**v0 → v1** (`v0_flat_character_to_v1_envelope`) is the built-in example. Version 0 is the pre-envelope prototype
save: one flat object with no `save_version`, using the brief's Phase 6 field names (`max_hp`, `max_mp`, flat
`str/dex/int/luk`, `available_ap`, `quest_state`, `current_map`, `play_time`). It becomes the v1 envelope, with
`current_map` turned into `location {map_id, entry: {map_id, spawn_index: 0}}`. The inventory, equipment and quest
blobs pass through unchanged. An object with no version that does not look like v0 is `ERR_FILE_CORRUPT`.

**Adding a schema change:**

1. Bump `CURRENT_VERSION`.
2. Write `_vN_to_vN1()` and register it in `_init()`.
3. Add a fixture test to `test_save_migrations.gd`.

Never edit an existing step. A `CharacterState` field added with a default needs no migration, because `from_dict`
fills it in. A field that changes meaning does.

## Integration notes for other systems

- **World runtime (MapSession).** It implements `can_save()`, `save_world()` and `capture_location()`, and calls
  `Saves.request_autosave()` after each committed transition. What it does not do yet: react to
  `Game.character_replaced`. After `Game.new_game`, `load_game`, `reset_save` or `start_or_continue`, something
  must call `MapSession.load_character(Game.character)` (or `start_new_game()`). This is the `transition(via = load)`
  of §4.9. Until then, a load changes the character but leaves the player where they stand, and the next
  `capture_location()` writes that position into the loaded character.
- **Boot / title screen.** Call `Game.start_or_continue()` or `Game.new_game(params)` before gameplay. Saving
  needs an active game.
- **UI.**
  - Read `Saves.list_saves()` for the slot picker. `source == "backup"` means the save file is missing and its
    backup will load.
  - Read `Game.last_creation_errors` for the creation screen.
  - Read `CharacterFactory.creation_weapon_ids(db)` and the `creation_ap` / `allocatable_stats` of
    `formulas/beginner.json` for the choices.
- **Composed modules** (Inventory, Equipment, QuestLog). Their `to_dict()` must contain only JSON values with
  String keys, or the save is refused (`ERR_INVALID_DATA`). Their `from_dict()` receives normalized numbers and
  must not trust sizes or indices from the file.

## Tests

```bash
ISOLATE=<name> bash scripts/test.sh save_ new_character game_state
```

| File | What it covers |
|---|---|
| `test_new_character_factory.gd` | Exact new-character values, read from canonical data or the adaptation table; a golden test that pins MeowDB's published numbers literally (Lv 1, HP 50 / MP 5, 4/4/4/4 + 9 AP, weapons 541/576/585); creation AP split, totals and bad entries; name rules, including a trailing newline; the creation weapon trio, cross-checked against two canonical sources; Razor and unknown ids refused; every creation weapon equipped through `Equipment.equip` for every all-in-one-stat build; a broken start location refused; every adaptation entry has a reason and a verified flag |
| `test_save_store.gd` | Write/read; one-generation backup; a failed write (a real file-system failure: the `.tmp` path is a non-empty directory) leaves the old save and backup byte-identical; unserializable values refused; error codes for missing, garbage, empty, truncated, non-object and binary files; slot-name safety (paths, newlines, Windows device names); list and delete; restore from backup; a corrupt save never replaces a good backup |
| `test_save_migrations.gd` | `save_version` written and equal to `SAVE_VERSION`; a v0 fixture migrated and loaded (renames, location, meta, inventory pass-through); a migrated save is rewritten as current; steps run in order; newer or invalid versions and missing steps refused |
| `test_save_roundtrip.gd` | save → load deep equality of `CharacterState.to_dict()` with the real inventory, equipment, quest log, location (entry and resume), flags, effects, skills and quickslots; the envelope; `can_save` blocking and the no-`can_save` fallback; corrupt and missing loads keep the live game; wrong-type fields are `ERR_FILE_CORRUPT`; unknown map fallback; respawn recomputed; `list_saves`; delete; a failed save keeps the previous save loadable |
| `test_save_location.gd` | Load sanitizing of the §4.9 location: string, foreign and out-of-range entries; malformed or non-finite `resume`; re-floated numbers; extra keys kept. `capture_world` without `save_world()`: no world yet, map changed, no `last_arrival`, a stale entry in the same map, a Dictionary `last_arrival`. `save_game` writes MapSession's location, and `save_world()` is used verbatim. MapSession is a private stand-in with only the contract's data members |
| `test_game_state_lifecycle.gd` | New game and its clean save; rejected params change nothing; load replaces the character wholesale with signals; autosave debounce, max delay and `can_save` gating; autosave on `Events` milestones and through `Saves.request_autosave()`; play time (paused time excluded, persisted); `reset_save`; `start_or_continue` (never overwrites a corrupt save); a missing save with a backup continues from the backup and keeps it; a corrupt save is not silently replaced; `allocate_ap` with canonical stats; the debug console commands; `gain_exp` signals (skipped while `Progression` is a stub) |

All tests use a private `user://_tests/...` directory, which is deleted afterwards, and a private `Events` instance,
so they never touch real saves or autoload state.
