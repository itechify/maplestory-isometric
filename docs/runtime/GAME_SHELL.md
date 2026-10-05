# The game shell: boot, screens, composition, death and respawn

The game shell is what runs when MisoStory launches. It boots to a title screen and owns the flow between the
screens (title, character creation, loading, the game, the pause menu). It composes every gameplay subsystem into
one running game, and it runs death and respawn (brief Phase 9). It also covers the brief's "Game launches
independently of Blender" and the gameplay acceptance flow: new game, play, save, quit, reload, continue.

The shell holds no gameplay rules of its own:

- Creation rules belong to `CharacterFactory`.
- Saving belongs to `Game` and `Saves`.
- Map changes belong to `MapSession`.
- The EXP penalty belongs to `Progression`.

The shell puts these together in the right order and gives them screens.

## Files

| Path | What |
|---|---|
| `game/scenes/main.tscn` | the project's `run/main_scene`: a `Node` with `scripts/game/main.gd` |
| `game/scripts/game/main.gd` | `MainShell`: screens, flow, pause menu, Esc, quitting, the root window's theme. Every button is a public method |
| `game/scripts/game/shell_flow.gd` | `ShellFlow` (pure): the screen state machine |
| `game/scripts/game/game_session.gd` | `GameSession`: one running game (world, player, camera, context, subsystems, death) |
| `game/scripts/game/subsystem_installer.gd` | `SubsystemInstaller`: the subsystem scene list (data) and `setup(ctx)` |
| `game/scripts/game/death_rules.gd` | `DeathRules` (pure): the ordered death penalties |
| `game/scripts/game/death_controller.gd` | `DeathController`: HP 0 → dead → loss taken and saved at once → notice → OK → respawn → save |
| `game/scripts/game/creation_model.gd` | `CreationModel` (pure): the creation screen's state, validation and stat preview |
| `game/scripts/game/save_slot_index.gd` | `SaveSlotIndex` (pure): which slot Continue loads, which slot a new game uses |
| `game/scripts/game/game_context.gd` | `GameContext`: the fixed contract handed to every subsystem (see "Changes to shared files") |
| `game/scripts/ui/screens/*.gd` | the screens, built in code: `TitleScreen`, `TitleBackdrop`, `CreationScreen`, `LoadingScreen`, `SlotList`, `PauseMenu`, `ControlsPanel`, `DeathNotice`, `ScreenKit` (shared builders) |
| `game/scripts/autoload/game_state.gd` | the `Game` autoload: the shell adds the quest wiring, HP/MP helpers, `gender`, `close_game()` and `save_as_is()` |
| `game/data/misostory/death.json` | the death adaptation: rule order and HP/MP after a respawn (its `respawn_player_spawn_index` belongs to the world runtime) |
| `game/scenes/ui/screens/shell_checks.tscn` + `game/scripts/game/checks/shell_checks.gd` | drives the real main scene for the flow tests and the screenshots |
| `game/scripts/game/checks/shell_check_runner.gd` | `ShellCheckRunner`: runs the checks scene in a child process for the unit tests |

## Screen flow

```
BOOT --boot--> TITLE --New Game--> CREATE --Start--> LOADING --ready--> PLAYING
               TITLE --Continue | Load | quick start--> LOADING          CREATE --Back/Esc--> TITLE
LOADING --failed--> TITLE (with the reason)
PLAYING --Esc (no window open)--> PAUSED --Resume/Esc | Load (in place)--> PLAYING
PLAYING | PAUSED --Quit to Title--> TITLE        PLAYING | PAUSED --HP 0--> DEAD --OK | a load--> PLAYING
any state --quit--> QUITTING
```

**At boot** `MainShell.apply_ui_theme(get_tree().root)` puts `MisoTheme.get_theme()` on the root window, so every
Control without a theme of its own shares the look, tooltips and popups included (they are windows of their own and
inherit the root's theme). MisoTheme is reached by path through `ScreenKit.theme()`; without the file the root keeps
Godot's default theme and the shell still runs.

`ShellFlow` is the table above. `fire(event)` refuses any event the current state does not list and changes
nothing. `MainShell` fires the event, then shows the screen that belongs to the new state.

- **Title.** It shows New Game, Continue, Load and Quit over a procedural backdrop: sky, clouds, an island with
  mushroom-cap houses, and falling leaf shapes. Continue appears only when a loadable save exists. It loads the
  most recently written loadable slot, chosen by `SaveSlotIndex.continue_slot`. Load opens the slot list, with one
  row per `Saves.list_saves()` entry. A row shows the name, level, map name, play time, slot and save time. An
  unreadable save is listed with its error, plus a "Restore backup" button when a backup exists.
- **Creation.** It has a name field, gender, the creation weapon (each with its canonical W.ATK and attack speed),
  and the creation AP with +/−, Clear and Recommended. A live preview shows HP/MP, W.ATK, Accuracy, Avoidability
  and Damage. Start is enabled only when `CreationModel.errors()` is empty. A new game is written to the first free
  slot (`slot1`, `slot2`, ...), so New Game never overwrites a save. The screen shows which slot it will use.
- **Loading.** A bar driven by `GameSession.progress`. The island load (`IslandWorld.load_progress`) fills the
  first 85%; composing and placing the character fill the rest. The screen stays up until MapSession is `IDLE`
  with the player standing in the world.
- **Pause menu** (Esc). Resume, Save, Load (the slot list; it loads in place), Controls, Quit to Title and Quit
  Game.
  - The Controls panel lists every action in `Controls.BINDINGS` that the game handles, with its `Controls.LABELS`
    label and all of its keys and mouse buttons. It is read-only.
  - It hides the actions in `ControlsPanel.NOT_AVAILABLE`, a key reserved in `Controls.BINDINGS` that nothing
    handles yet. The list is empty since Iteration Three: `sit` (X, sitting and chairs), `toggle_skills` (K, the
    skills window) and `toggle_minimap` (M, the minimap, UI.md "Minimap") are listed like every other key. An action
    goes on the list only while nothing handles it, and comes off when its feature lands. `test_shell_screens` fails
    while any script other than `controls.gd` and `controls_panel.gd` names a hidden action, so the panel cannot hide
    a key that works.
  - While the menu is open the tree is paused (`SceneTree.paused`, `Game.paused`). The menu and the shell keep
    processing (`PROCESS_MODE_ALWAYS`), and the menu is a modal, so player input stops.
- **Map name banner.** The HUD already shows one, so the shell does not add its own.

**Esc** (the `menu` action) is handled in one place, `MainShell.handle_menu_action()`:

| State | What Esc does |
|---|---|
| playing | `ctx.close_top_window()` first. With no window open, it opens the pause menu, but never while a modal (dialogue, shop, console, death notice) owns the keyboard or a map transition runs |
| paused | leaves the Load/Controls sub-panel, else resumes |
| creation | back to the title |
| title | closes the slot list |

Windows should register with `ctx.window_opened/window_closed` and leave Esc to the shell.

**Command line** (after `--`):

- `--quick-start` skips the title and starts a quick-start character (`new_character.json quick_start`) in a new
  slot.
- `--continue` skips the title and continues the latest save.

## Composition (GameSession.start)

The order follows WORLD_RUNTIME.md "Contracts with other systems" (and its "Game shell: what to call" table) and
ARCHITECTURE.md "Shared contracts":

0. MapSession must be in `BOOT`. A quit to title leaves it there (see "Teardown"); if it is found past `BOOT`
   anyway, `start()` calls `MapSession.reset()` first.
1. Instance `res://scenes/world/world.tscn` and wait for `world_ready`. Visual chunks are off when headless,
   because the threaded visual load crashes the dummy renderer. A world whose script did not load (a parse error)
   fails the start with "the island world could not be created", and the title shows it.
2. Add `res://scenes/actors/player.tscn` and call `world.set_player(player)`.
3. Add `res://scenes/actors/camera_rig.tscn`, then call `rig.set_target(player)`, `MapSession.attach_camera(rig)`
   and `rig.scan_occluders(world)`.
4. Build `GameContext`: `main` (the `MainShell`), `world`, `player`, `camera`, `ui_root` (CanvasLayer "UI",
   layer 10) and `systems` (Node "Systems"). Hand it to the world: `world.set_context(ctx)`. From then on the world
   asks this context whether a modal owns the keyboard: a portal key (Up, F) pressed under a modal is ignored, and
   the input hand-back at the end of a warp (`IslandWorld.set_player_input(true)`) is refused while a modal is
   open. Input comes back when the last modal closes (`GameContext.pop_modal`).
5. Create the `DeathController`. It installs itself as `MapSession.death_commit` (see "Death and respawn"), and its
   notice goes on CanvasLayer "Notices" (layer 90).
6. `SubsystemInstaller.install(ctx)` runs over this list, which is data, not code branches:

   | Name | Scene | Parent |
   |---|---|---|
   | MonsterSystem | `res://scenes/systems/monster_system.tscn` | systems |
   | LootSystem | `res://scenes/systems/loot_system.tscn` | systems |
   | InteractionSystem | `res://scenes/systems/interaction_system.tscn` | systems |
   | HUD | `res://scenes/ui/hud.tscn` | ui_root |
   | Minimap | `res://scenes/ui/minimap.tscn` | ui_root |
   | Windows | `res://scenes/ui/windows.tscn` | ui_root |
   | NpcUI | `res://scenes/ui/npc_ui.tscn` | ui_root |
   | DebugUI | `res://scenes/debug/debug_ui.tscn` | ui_root |

   - A scene file that does not exist is skipped with one log line (`missing`).
   - Every existing scene is instantiated and added first. Then `setup(ctx)` runs on each in list order, so a
     subsystem's setup can already find its siblings.
   - A root without `setup()` still runs (`no_setup`). A scene that cannot be loaded, or a context without the
     named parent, is `failed`.
   - The report is `GameSession.installer.report`, and `installer.summary()` prints one line.
7. Call `Game.new_game(params)` or `Game.load_game(slot)`, **only now** (see "Ordering" below).
8. Call `MapSession.start_new_game()` or `MapSession.load_character(Game.character)`, then wait until MapSession
   is `IDLE`: placed, grounded and faded in.
9. Sync the player's stats and arm the death watch.

**Stat sync.** `player.refresh_stats(Game.character, Data.db)` runs on `Events.stats_changed`, `equipment_changed`,
`leveled_up` and `Game.character_replaced`. The controller itself only listens to `stats_changed`.

**Ordering.** The world, player and camera must be in place before the game's character is created or loaded, and
the subsystems must be installed first so they hear the new character's refresh signals (`Game.character_replaced`,
`stats_changed`, `hp_changed`, ...). MapSession ignores `Game.character_replaced` while it is in `BOOT`, so the
shell places the character itself in step 8, with the world attached: a save's `resume` point is validated against
the real ground and kept. The title and creation screens only **read** (`Saves.list_saves()`,
`CharacterFactory.validate`); every `Game` call happens inside `GameSession.start` after step 6.

**Teardown** (quit to title):

1. The shell saves.
2. `Game.close_game()`: no game is active, a pending autosave is dropped, and play time stops.
3. The death controller detaches (it removes its `death_commit` hook), the stat hooks detach,
   `MapSession.attach_camera(null)` runs, and the session subtree is removed.
4. `IslandWorld._exit_tree` calls `MapSession.detach_world`, which settles a warp in flight and calls
   `MapSession.reset()`: `BOOT`, no `current_map`, an empty instance cache and transition log, nothing pending.
   `GameSession.teardown` then resets MapSession itself if it is still past `BOOT` (a world that failed before it
   attached, a failed start).

So Continue, Load and New Game after a quit to title enter exactly like the first game of the process: from `BOOT`,
through step 8. The continued session's first transition names no old map, and none of the last session's
monsters or drops survive in the cache.

## The Game autoload additions

These are additions to `game_state.gd`. The existing API is unchanged.

| Member | Behaviour |
|---|---|
| `quests: QuestService`, `npc_talk: NpcInteraction` | Wired in `_ready` exactly as QUESTS_AND_DIALOGUE.md describes: `QuestService.create(Events, Data.db, character, rng, clock)`, `character_provider` follows new game and load, `attach()`, and the console commands through `register_debug_commands(Debug)` (deferred with the other `Game` commands). `wire_quests(bus)` is the seam, and calling it twice is harmless |
| `change_hp(delta) -> int`, `change_mp(delta) -> int` | `StatCalculator.change_hp/mp`, then `Events.hp_changed/mp_changed` (always emitted, even for 0). Every system that changes the player's HP should come through here, because the death watch reads `hp_changed` |
| `damage_player(amount, source_monster_id) -> int` | Emits `Events.player_damaged(amount, source)` when amount > 0, then calls `change_hp(-amount)`. Returns the HP lost |
| `is_character_dead()` | `Progression.is_dead` (canonical trigger: HP 0), **or MapSession in `DEAD`**. The loss is taken at the moment of death, so while the notice is up the character already holds its respawn HP (death.json, 50); `hp <= 0` alone would say "alive". Any system asking "is the player dead?" asks this (or MapSession), never the raw HP. `map_session` is the test seam (null = the autoload) |
| `new_game(params)` with `"gender"` | One of `GENDERS` (`male`, `female`), or `""` for unknown (quick start, tools). It is validated, and a bad value is refused like any creation error. It is stored in `CharacterState.gender`, which saves already carry |
| `close_game()` | Ends the live game without saving: `has_active_game()` becomes false, autosave is dropped, play time stops, the clock is unpaused, and `current_slot` is kept |
| `validate_gender(value)` (static) | The gender check used by `new_game` and `CreationModel` |
| `save_as_is(slot := "") -> Error` | Writes the live character exactly as it is, with its own location: no MapSession world block and no `can_save()` check. Only for a state MapSession refuses to save but the caller has made consistent. The one user is `DeathController.commit_death_for_quit()`, for a death that happened during a warp and is not committed yet when the game closes (every other death is saved with `save_game()`) |

## Character creation (CreationModel)

Every number is read from data, never written in the shell:

| Value | Source |
|---|---|
| Starting stats 4/4/4/4, 9 creation AP, STR/DEX/INT/LUK | canonical `formulas/beginner.json` (`starting_stats`, `creation_ap`, `ap.allocatable_stats`) |
| Creation weapons and their numbers: 541 Sword (W.ATK 17, Fast 4), 576 Hand Axe (W.ATK 17, Fast 4), 585 Wooden Club (W.ATK 19, Fast 5) | items flagged `beginner_creation_weapon`, read through `ItemDef` |
| Name rules | `new_character.json name_rules`, checked by `CharacterFactory.validate_name`, which matches the whole name, so a trailing newline is refused |
| Default spread and weapon ("Recommended") | `new_character.json quick_start` (the Beginner's guide advice: 9 STR, Wooden Club) |

The preview equips the chosen weapon on a scratch character through the real `Equipment.equip` path. It then calls
`StatCalculator.compute(job, level, base stats, base HP/MP, StatCalculator.bonuses(scratch), weapon, db)`, so the
preview equals the created character's `StatCalculator.snapshot()`, and a test checks that. It also works with a
partial spread, which `CharacterFactory.create` does not accept.

## Death and respawn (Phase 9)

Classic MapleStory takes a death's loss when the character dies, not when the player answers the prompt. The shell
does the same through the world runtime's death commit (WORLD_RUNTIME.md "Death commit"), and saves at once:

```
HP 0 (Events.hp_changed, Progression.is_dead)        or another system emits Events.player_died
   │ one idle step later, if nobody announced it: DeathController.kill(): player.die(); MapSession.enter_dead()
   ▼
MapSession enters DEAD (input off) and calls its death_commit hook = DeathController.commit_rules(character),
   │   once per death: DeathRules.apply in death.json's order
   │     1. exp_penalty     Progression.apply_death_penalty (canonical formulas/death.json)
   │     2. respawn_vitals  death.json HP/MP (adaptation), set now so the save already holds them
   │ MapSession: character.location = respawn_location() (returnMap player_spawns[death.json
   │   respawn_player_spawn_index], no resume point), respawn_reference = the town's; death_committed(map, report)
   ▼ death_committed → DeathController: Game.save_game() right away (allowed: can_save() is true in a committed
   │   DEAD) → the slot holds the post-death character in town; committed(map, report)
Events.player_died (enter_dead emits it after the commit; another system's announcement reaches MapSession first)
   → MainShell (connected at boot, before the controller): the pause menu, if open, closes and the tree unpauses
   → DeathController: open modal windows (dialogue, shop, console) are closed, then the modal
   │                  DeathNotice "You have died. Return to the nearest town?" [OK]
   │                  (the line under it names the town: the map's canonical returnMap)
   │ once the death is both committed and announced (either order): Events.exp_gained(-exp_lost, "death"), so the
   │   HUD's EXP bar drops at the death; its HP gauge keeps the killing blow's 0
   ▼ OK → confirm()   (waits for DEAD when the death happened during a warp)
MapSession.respawn() → only the transition via respawn to the same returnMap spawn (nothing is applied again)
                      → stats/hp/mp refresh; the notice hides as the screen fades out (the modal stays)
   ▼ transition_finished
player.revive(); modal popped (input back); Game.save_game() (now with the town's resume point); respawned(map, report)
```

- **Watch.** The HP watch acts only while `armed`, which is set once the session is playing. Loading emits
  `hp_changed` through `Game.refresh_ui()`, and that must not count as a death.
- **One announcement.** `kill()` calls `MapSession.enter_dead()`, which emits `Events.player_died`, and the
  controller reacts to that signal; a death announced directly by another system takes the same path. In the game
  the watch kills one idle step after the `hp_changed` (deferred), and only if HP is still 0 and nobody announced
  the death meanwhile. The reason is MonsterSystem: its touch path (`ContactDamage.apply` then
  `ContactDamage.announce_death`) emits `hp_changed` and then announces the death itself. A synchronous kill made
  MapSession `DEAD` first, so `announce_death` emitted `player_died` a second time and the HUD logged "You have
  died." twice. Without a tree (unit tests) the kill stays synchronous.
- **At the death.** A modal window still open (an NPC conversation, a shop, the console) is closed from the top of
  the window stack until no modal is left. Otherwise it kept the keyboard over the notice, and after the respawn it
  was still open in town as a registered modal while MapSession had turned the player's input back on.
  Non-modal windows (inventory, stats) stay open.
- **Once per death.** `commit_rules` applies the rules only on the first call of a death (`is_committed()`), and
  returns the first report on any later call. The flag clears when the death ends: the respawn finished, a load
  out of `DEAD`, or `detach()`. Every path goes through it: MapSession's hook, the quit fallback below, and a
  last-resort commit in `confirm()` if MapSession entered `DEAD` without the hook. `attach()` during an uncommitted
  `DEAD` calls `MapSession.commit_death()`.
- **While dead.**
  - The loss is already taken and saved. `MapSession.can_save()` is true, and any save (the autosave MapSession
    requests at the commit, Game's save when the window closes) writes the same post-death character in town.
  - **The character already holds its respawn HP** (death.json's 50) while it is dead. "Is the player dead?" is
    `Game.is_character_dead()` (true while MapSession is `DEAD`) or MapSession's state, never `hp <= 0`.
  - The HUD shows the death as classic does: the EXP bar drops at the death (`Events.exp_gained(-exp_lost,
    "death")`, sent once per death; the HUD redraws its EXP bar for any amount and logs positive gains only), and
    the HP gauge keeps the killing blow's 0. The full refresh (`stats_changed`, `hp_changed`, `mp_changed`) is sent
    as the respawn starts, not at the commit, because it would show the respawn HP under the notice (see "Known
    limits").
  - Esc neither closes the notice nor opens the pause menu.
  - **Dying while paused.** `ShellFlow` allows `PAUSED --died--> DEAD`. No gameplay path does it today (the world
    is paused), but a death announced then closes the pause menu and unpauses the tree before the controller opens
    the notice (`MainShell._on_player_died`, connected to `Events.player_died` at boot, so it runs first). Otherwise
    the tree stayed paused under the menu, with Resume and Quit to Title refused in `DEAD`.
- **OK only travels.**
  - A mouse click or Enter (keypad Enter too) confirms. The jump keys (Space, Alt) and key repeat do not. OK holds
    the keyboard focus, so Enter reaches it and no other control gets the keys. Space is also Godot's default
    `ui_accept`, and players hold the jump key (`movement.json` `hold_to_rejump`) and mash it as they die. So the
    OK button's own `gui_input` swallows any key that matches the `jump` action (or `Controls.BINDINGS["jump"]`
    when the action is not registered), and any echo, before `Button` reads it (`DeathNotice.ignores_key`). The
    global `ui_accept` is unchanged: Space still presses the pause menu's Resume. The filter sits on the button
    rather than in the notice's `_input`, so a debug console that has the focus while dead still types spaces
    (`load slot1`).
  - With MapSession `DEAD`, it calls `respawn()` at once; EXP, HP and MP do not change. The notice hides as the
    warp starts. The screen fader draws above the notice layer, so a notice left up would sit over the town during
    the fade-in.
  - During a warp (the death was announced, but MapSession enters `DEAD`, and commits, only when the warp
    completes), OK is queued. It runs on the `state_changed` to `DEAD`, deferred one idle step so it never
    re-enters MapSession's completion.
  - If MapSession refuses, the notice reopens so OK can be pressed again.
  - The respawn's input hand-back is refused while the notice's modal is held (the world asks the context); the
    controller pops the modal in `_finish()` and `GameContext.pop_modal` turns the input back on.
- **A load out of DEAD** (the console's `load` or `reset_save`; the death notice has no load button), or the
  console's `respawn` (`MapSession.respawn()` without OK). MapSession emits `player_respawned` for it. The
  controller clears the death, revives the player, sends the stats/HP/MP refresh (the HUD still showed the killing
  blow) and emits `death_cleared`, and the shell leaves its `DEAD` state. Loading the current slot finds the save
  written at the death: the character in the return town with the penalty taken once.
- **Quitting while dead.** Nothing is needed for a committed death: the save at the death holds it, and `Game` (an
  autoload, notified of the window close first) saves it again. `MainShell` still calls
  `DeathController.commit_death_for_quit()`, which saves once more for a committed death. Its real job is the one
  death that is not committed yet: a death during a warp, before the warp ends (MapSession refuses saves until
  then). It applies the rules through `commit_rules`, so never twice, sets the location to
  `MapSession.respawn_location()` (with the town's respawn reference) and writes it with `Game.save_as_is()`. If
  that warp then completes after all, MapSession's commit finds the death already committed and applies nothing.
- **Reload.** The next Continue enters from `BOOT` at the save's `entry` (the respawn spawn, no `resume`), with the
  EXP penalty taken exactly once and the HP/MP of death.json. Nothing about the death is pending any more.
- **DeathRules** is the slot for later penalties. A rule is `Callable(character, report)`. `register_rule(name, rule)`
  adds one, and its name goes into `death.json rules.order`. An unknown name in the order is reported and skipped,
  never fatal. Nothing in the shell touches the inventory, equipment, mesos or the quest log, and the tests check
  that.
- **Report.** `DeathController.last_report` is DeathRules' report (`applied`, `exp_before`, `level_before`,
  `hp_before`, `mp_before`, `exp_lost`, `hp`, `mp`) plus `map_id` (died in) and `death_save_error` (the save at the
  death), and after the respawn `returned_to` and `save_error`. `committed(map_id, report)` fires after the save at
  the death; `respawned(map_id, report)` after the one at the end of the respawn.

## Adaptations

| File:key | Value | Why |
|---|---|---|
| `death.json:rules.order` | `exp_penalty`, `respawn_vitals` | MeowDB documents only the EXP loss (`formulas/death.json`); no item, meso or buff loss |
| `death.json:respawn_vitals` | HP: `fixed` 50 (capped at Max HP); MP: `keep` | MeowDB gap ("HP/MP after respawning is not documented"). A classic-feel choice: the player returns with 50 HP and MP as it was. `verified: false`. HP is always at least 1 after a respawn. Set when the death is committed, so the save made while dead already holds it |
| `death.json:respawn_player_spawn_index` (the world runtime's key) | 0 | which return-map spawn a respawn uses (open question 1). Moved here from `presentation.json` by the world runtime; read through `WorldTuning.respawn_spawn_index()` / `MapSession.respawn_location()`. The shell only reads it |
| New games use the first free `slot<n>` | engineering | New Game must never overwrite an existing save |
| HP/MP shown in the death notice? No; it names the return town | UI | the classic prompt asks to return to "the nearest town" |
| The loss is taken, and saved, at the moment of death | classic behaviour; the brief's "quitting cannot dodge it" | `MapSession.death_commit` → `DeathController.commit_rules`, then `Game.save_game()` on `death_committed`. OK only travels |

UI text, colours and layout are presentation, not canonical data, so they live in the screen scripts. The look comes
from `MisoTheme` (the HUD system's theme, `res://scripts/ui/theme/miso_theme.gd`), which the shell also puts on the
root window at boot ("Screen flow"). It is loaded by path, so the shell still runs, with Godot's default theme, if
that file is absent.

## Tests

```bash
ISOLATE=shell bash scripts/test.sh test_shell_ test_death_                   # pure tests (the three main-scene tests SKIP)
ISOLATE=shell INCLUDE_WORLD=1 bash scripts/test.sh test_shell_ test_death_   # + the real main scene in child processes
```

| File | Covers |
|---|---|
| `test_shell_flow_states.gd` | every `ShellFlow` transition and refusal; quit from any state once; `changed` and history; the table is closed; `SaveSlotIndex`: Continue = newest loadable save (an unreadable save is skipped, ties broken by name), a new game never reuses a slot (an unreadable save or a lone backup occupies its slot) |
| `test_shell_installer.gd` | real `.tscn` files written to `user://_tests`: missing scenes skipped, systems under `ctx.systems` and UI under `ctx.ui_root`, `setup(ctx)` receives the context, every node is in the tree before any setup, a root without `setup()` still runs, bad entries and missing parents fail cleanly, `summary()`, the default list's shape and order |
| `test_shell_creation.gd` | the canonical creation numbers (9 AP, 4/4/4/4, 541/576/585 W.ATK and speed, pinned once and cross-checked against the item records); the quick-start defaults; AP rules (never below 4, never above 9, only allocatable stats); name rules (short, long, spaces, non-ASCII, a trailing newline); gender; Razor and unknown ids refused; the preview equals `StatCalculator.compute` and the created character's snapshot for 3 spreads × 3 weapons; `Game.new_game` with gender, slot and save |
| `test_shell_game_state.gd` | `change_hp/mp` clamp and announce; `damage_player` signals; `is_character_dead()` stays true through a committed death that already holds the respawn HP (a private MapSession in `DEAD`) and turns false after the respawn; `close_game` (no autosave afterwards, the save is byte-identical, play time stops, a load reactivates); the quest wiring follows a new character; `npc_talk` opens a conversation; the quest console commands |
| `test_shell_screens.gd` | the title's Continue and Load from save entries, slot row text (name, level, map, play time), creation Start gating and the +/− and weapon buttons, the controls list covers every binding except `NOT_AVAILABLE` (empty since Iteration Three: Sit on X, Skills on K and Minimap on M are rows and drawn labels), no other script names a hidden action and the minimap handles `toggle_minimap`, the pause menu's sub-panels and Esc, the death notice confirms once per death; **the death notice's keys** through real GUI dispatch (`Viewport.push_input` on the focused OK): Space, Alt, a held Space with repeat and a repeating Enter do not confirm, Enter and keypad Enter do, and Space still presses the pause menu's Resume (the global `ui_accept` is untouched); the jump keys still come from `Controls.BINDINGS` without the InputMap action; `MainShell.apply_ui_theme` puts `MisoTheme.get_theme()` on a window |
| `test_death_rules.gd` | death.json valid and ordered, with reasons; the EXP penalty equals `Progression.death_exp_loss` across levels and LUK, never takes a level, and passes MeowDB's parity example (Lv 30, 47,850 → 38,280); HP/MP per death.json; vital modes; inventory, equipment, quests, mesos, AP/SP and stats untouched; a new rule slots in by name; unknown rules reported, not fatal; missing table |
| `test_death_controller.gd` | a private MapSession without a world: `death_commit` = `commit_rules` installed and removed (no `death_rules`), with the save hook; **Test F in 000000040 and 000001014**: at the death the rules run once, the canonical EXP loss and death.json HP/MP are on the character, the location is the canonical returnMap's respawn spawn, the save on disk already holds all of it (no resume point), saving while dead works; OK only travels (EXP/HP/MP unchanged, rules still applied once), the save after the respawn, inventory and quest state intact in memory and in the file; **death → quit → reload in 000000040 and 000001014** (the saves on close, `close_game`, `MapSession.reset()`, a fresh controller, `load_game`, `load_character` from `BOOT`): in the return town at the respawn spawn through `entry`, the penalty exactly once, HP above 0, no death and no rule on the way, inventory and quest intact; a death announced by another system (committed before the controller hears it); **the EXP loss announced once per death** (`exp_gained(-exp_lost, "death")` after the commit and the announcement, for an HP-0 death, an announced death and a death during a warp; nothing at OK); a disarmed watch; OK runs once; `committed` fires with the save on disk; a death during a warp (committed when the warp ends, OK queued until `DEAD`); **a quit during that warp** (the fallback writes the penalty and the town with `save_as_is`; the warp then ending does not apply it again); a load out of `DEAD` clears the death and emits `death_cleared` once; the console's respawn without OK clears it too and the HUD hears the live HP; **a load from the death screen** finds the save of the death (town, penalty once, alive); a modal window open at the death is closed and a non-modal one stays; quitting while dead keeps the committed death and never takes EXP twice; attached after the death, the controller commits it; a quit commit needs a death |
| `test_shell_acceptance.gd` | the real main scene (child process, `--scenario flow`, 56 checks):<br>- title with no Continue, the root window wearing MisoTheme, MapSession in `BOOT`; creation; loading<br>- `PLAYING` with the context complete, every subsystem installed or skipped and none failed, the quest system wired and the death commit hooked<br>- the player at 000000001 `player_spawns[0]` on the floor; the chosen character<br>- the world asks the context it was given (with `GameSession.ctx` hidden), a warp ending under a modal leaves the input off, closing the modal gives it back<br>- walk 2 m, save, pause/resume (tree paused, input off), Esc closes a window first, then opens and closes the pause menu<br>- quit to title (session gone, game inactive, **MapSession reset**: `BOOT`, no map, empty cache and log, no world, no death hook), the slot list's name, level, map and play time<br>- continue: same map, same position (within 0.1 m of the saved SafeGround point, entered through the `resume` step), the first transition names no old map, same stats, inventory, equipment and quests; the player's speed synced<br>- quit to title again (reset again), then **New Game** from `BOOT`: the second character goes to a new slot at 000000001 `player_spawns[0]` (load step `entry`), and the first slot's save is untouched |
| `test_death_flow.gd` | the real main scene (`--scenario death`, 108 checks): deaths in 000000040 and 000001014 through `Game.change_hp` and one in 000000001 through `Events.player_died`: one `death_committed` at the death, the EXP penalty and death.json HP/MP at the death, the save on disk holding them in the return town at the respawn spawn, saving while dead allowed, the UI notice and Esc, **Space and Alt pressed for real** (`Input.parse_input_event`, OK focused) leave the notice up and MapSession `DEAD`, **the HUD under the notice** (the EXP bar already dropped; HP 0 for the HP-0 deaths), `Game.is_character_dead()` while the respawn HP is held, then OK only travels, plus the checks above; a death in the middle of a warp to 000000041 (OK queued until `DEAD`, then the deferred respawn to its returnMap, the penalty applied once); a **monster-touch death** reproduced call for call (`StatCalculator.change_hp`, `hp_changed`, `ContactDamage.announce_death`): `Events.player_died` fires once, and the notice hides as the respawn starts; a death with an NPC conversation open (closed at the death, no modal left after the respawn, Esc pauses); **a death announced while paused** (the menu closes and the tree unpauses before the notice; OK respawns, input back); then quit to title and continue from the post-death save; a console `load` while dead (the save of the death: town, penalty once, alive; the shell leaves `DEAD`, Esc pauses); and **closing the window while dead** (`NOTIFICATION_WM_CLOSE_REQUEST` through the whole tree): the save at the death and the saves on close hold the penalty once at the returnMap |
| `test_death_quit_reload.gd` | brief Test F as a **real quit**: three child processes share one save directory (`--scenario death_quit` / `death_reload`, `--save-dir`, `--keep-saves`). 1: new game, die in 000000040 (loss taken and saved at the death), close the window, exit. 2: Continue: in 40's return town at the respawn spawn (`entry`, no resume, a clean session), the EXP penalty exactly once, death.json HP/MP, inventory, equipment and quest 1000 intact, alive, input on, still once after 30 armed frames; then die in 000001014, close, exit. 3: Continue and the same checks for 1014 |

**Visual check.** In an ISOLATE copy:

```bash
bash ../../../../scripts/godot.sh --path . --resolution 1600x900 --disable-vsync \
  res://scenes/ui/screens/shell_checks.tscn -- --scenario shots --out <dir>
```

This writes the title, creation, a tooltip on the creation screen (the root window's MisoTheme reaches popups),
the game after spawning, the death notice, the pause menu, its Controls panel, and the
title's slot list.

## Changes to shared files

- **`game_context.gd`** (the fixed contract, under `scripts/game/`). `_apply_player_input()` did not compile: it
  inferred a type from `... if ... else null` and read `MainLoop.root`. Nothing had used `GameContext` until the
  shell did. The body now reads `SceneTree.root` with an explicit `Node` type. No field or signature changed.

## Known limits

- **No rebinding.** The Controls panel is read-only.
- **Gender is not shown.** It is stored and saved, and gendered equipment checks it, but the player model does not
  change with it.
- **The world is rebuilt on every Continue after a quit to title** (about 1–1.5 s with visuals on the dev machine).
  The world could be kept resident instead, at the cost of pausing it on the title screen.
- **The respawn fade-in shows the player in the death pose.** `player.revive()` runs when MapSession reaches `IDLE`
  (grounded), so the character lies down for the 0.2 s fade-in and then stands up. This is cosmetic. Reviving at
  the swap would need a "respawn swap" hook from MapSession.
- **The HUD's HP gauge reads 0 under the notice only because nothing refreshes it.** The EXP bar drops at the death
  (`exp_gained(-exp_lost, "death")`), but the full refresh waits for the respawn: the character already holds the
  HP it will wake up with (death.json's 50), and any `stats_changed` while dead (the shell's or another system's)
  would show it under the notice. A HUD that keeps its HP gauge at 0 between `Events.player_died` and
  `player_respawned` (requested) would make this independent of who refreshes.
- **A death during a warp names the town of the map being left.** The notice's line reads the map
  `Events.player_died` names, which during the fade-out is the map the player is leaving; MapSession commits the
  death when the warp ends, at the destination's returnMap. They differ only across 000000030 → 000000040 (East
  Entrance → Southperry) and 000000050 ↔ 000001000 (Southperry ↔ Amherst), and only for an HP-0 source that warp
  states do not gate (contact damage is gated; Maple Island has no other).
- **The quit fallback for a death during a warp writes the respawn point of MapSession's current map.** If the
  death came before that warp's swap, that is the map being left; MapSession's own commit, when the warp ends,
  would have used the destination's. Both are canonical return towns, and the window is about 0.2 s.
