# The playtest harness: automated playthroughs of the real game

The playtest harness plays the **real** game: `res://scenes/main.tscn`, the title, the creation screen, the island, the
HUD and every subsystem the shell installs. It plays through **real input**: key, mouse and action events go through
Godot's `Input`, so the player controller, PlayerCombat, the dialogue and shop windows and the shell react exactly as
they do to a keyboard. A playthrough is a **scenario**, a small GDScript coroutine. Each run writes a report:
`report.json` for tools and `report.md` for people. The exit code is non-zero on any failed check or script error.

It is the one driver for the brief's Phase 23 playthroughs (Tests A-G) and for the movement, camera, combat and
world reviews. It replaces the throwaway drivers earlier reviews wrote: `_scratch/review-world/driver/drive.gd`,
`_scratch/review_combat/review_driver.gd`, `world_ui_main_checks.gd`, `shell_checks.gd` and the traversal bot's
`TraversalWalker`. See "Lineage" at the end.

## Quick start

```bash
bash scripts/playtest.sh smoke                      # headless; prints PLAYTEST lines and the report path
bash scripts/playtest.sh fight --windowed           # a 1600x900 window; screenshot() writes PNGs
ISOLATE=<your-name> bash scripts/playtest.sh <scenario> --out _scratch/playtest/mine --seed 3
bash scripts/playtest.sh --list                     # the scenarios
bash scripts/playtest.sh quest --quest 1013-1019    # one quest chain of the every-quest set (strict after setup)
bash scripts/playtest_quests.sh                     # every quest: one run per chain, 3 in parallel, one table
PLAYTEST_TIMEOUT_S=7500 bash scripts/playtest.sh playthrough --seed 1 --max-wall-s 7000 --out _scratch/pt/seed1
                                                    # the clean-character playthrough: creation to Shanks, strict
```

The script mirrors `game/` (with the exported world) into `_scratch/godot_runs/$ISOLATE/game`, the same way
`ISOLATE=... INCLUDE_WORLD=1 bash scripts/test.sh` does. `ISOLATE` defaults to `playtest`. When several agents run at
once, each uses its own name. The script imports the copy and runs `res://tools/playtest/playtest_runner.tscn` once
per phase. The output directory defaults to `_scratch/playtest/<scenario>-<time>` and holds:

| File | Content |
|---|---|
| `report.json` | the whole run (see "Report") |
| `report.md` | the same report as tables |
| `saves/` | the run's private save directory |
| `shots/NN_p<phase>_<name>.png` | the screenshots (windowed runs only) |

| Option | Effect |
|---|---|
| (default) | `--headless --fixed-fps 60`: deterministic game time. The runner lays the game out on the windowed 1600x900 screen (see "Headless and windowed"). Screenshots are skipped (logged, never a failure) |
| `--windowed` | `--resolution 1600x900 --disable-vsync`, still `--fixed-fps 60`, with pictures. The GUI area and the click rules are the same as headless, but the two are not the same run: the visual chunks are loaded only windowed, and OS focus and timing can differ. A UI check is evidence for a windowed player only from a windowed run or from a headless run on the pinned screen (see "Headless and windowed") |
| `--realtime` | with `--windowed`, drops `--fixed-fps`: game time follows the wall clock (for feel checks only; results may vary) |
| `--seed <n>` | seeds `Game.rng` (combat rolls, drops, quest rewards) and MapSession's instance RNG. The default is 1. Since `Game.clock` stands still on the title and during the load (wave 2), three seed-1 runs of `test_skills` matched step for step; longer runs have not been shown to repeat exactly (see "Findings"), so treat a long run as one sample |
| `--trace` | records `PlaytestDriver.trace_digest()` on every step (`trace0` when it begins, `trace` when it ends): `Game.clock`, both RNG states, map and session state, position, vitals and a hash of the live monsters. Two runs of one seed diverge at the first step whose digest differs |
| `--max-s <s>` | the game-time budget of one phase (default: the scenario's `max_seconds()`) |
| `--max-wall-s <s>` | the wall-time budget of one phase (default: three times the game budget, at least 900 and at most 3300, so it fires before the outer 3600 s timeout) |
| `--quest <spec>` | for the `quest` scenario: `1002`, `1013-1019` or `1006,1009,1010` (the `QUEST` environment variable does the same) |
| `--resume` | continue a run in `--out` that stopped between phases (below): its report and saves are kept and the next phase starts with `--continue-run`. Development only: the report then mixes the code of two runs |

`PLAYTEST_STOP_PHASE=<n>` stops the run before phase `n` starts and leaves the report `RELOADING` (exit 1). With a
copy of that `--out` directory and `--resume`, a long scenario's later phase can be replayed after a code change
without playing the earlier phases again (the playthrough was developed this way). `PLAYTHROUGH_STOP=<step>` ends the
`playthrough` scenario after one of its steps: the report can still pass, but it records the stop (`carry.stopped_after`
and a `PLAYTHROUGH_STOP=` note) and never reaches the final boundary check ("ready to depart: the End of Maple Island
screen reached in Southperry"), so the parity generator does not count it as a clean-character run: no `playthrough:*`
row is verified by it (`tools/parity/parity.mjs` `cleanRun`; a `RELOADING` report is not one either).

**Exit code:**

- 0: the report passes.
- 1: a check failed, or a fatal error happened (a script error, a timeout, a scenario that does not compile).
- 2: a bad command line, a missing world export, or no report was written. The script removes any report left in
  `--out` before the first phase, so an old result is never read back, and a later phase that writes no report (a
  crash) also ends the run with 2 instead of being started again.

`PLAYTEST_TIMEOUT_S` (default 3600) is the outer `timeout` of each process. It is a last resort: the runner's own
watchdog normally stops the run first.

## Files

| Path | Class | Role |
|---|---|---|
| `game/tools/playtest/playtest_driver.gd` | `PlaytestDriver` | the API scenarios call: boots main.tscn, plays, logs steps and checks, strict mode |
| `game/tools/playtest/playtest_kit.gd` | `PlaytestKit` | the composite play every scenario shares: travel, talk, conversations and quizzes, markers, the Quest Log, item use, AP, shops, precise pickup, hunting with a survival policy, deaths, and the contract helpers for sitting, chairs, skills and Wooden Boxes (see "PlaytestKit") |
| `game/tools/playtest/playtest_ledger.gd` | `PlaytestLedger` | strict mode's bookkeeping: every change to EXP, mesos, items, quests, the level, AP, SP, base stats, skills, HP and MP must be explained by the event bus (see "Strict mode") |
| `game/tools/playtest/playtest_quest_plan.gd` | `PlaytestQuestPlan` | how to play a quest, derived from canonical data only (see "Quest plans") |
| `game/tools/playtest/playtest_quest_runner.gd` | `PlaytestQuestRunner` | plays one quest step by step with real input (offer, objectives, turn-in, rewards, follow-ups) and records its evidence; `quest` and `playthrough` both use it (see "The quest runner") |
| `game/tools/playtest/playtest_quest_summary.gd` | `PlaytestQuestSummary` | the every-quest table: reads every chain's report, writes `quests.md` / `quests.json`; `--combine` merges several runs (seeds) into the per-quest evidence report |
| `game/tools/playtest/playtest_bubble_watch.gd` | `PlaytestBubbleWatch` | NPC speech bubbles around an open window, by waiting only: reads each NPC's bubble schedule to wait until a bubble shows (`wait_shown`) or, while a window is open, until one falls due for an NPC that could show it, checking none does (`watch_quiet`) |
| `game/tools/playtest/playtest_input.gd` | `PlaytestInput` | real input: keys, actions (analog movement), mouse, typing; held state and focus re-assert |
| `game/tools/playtest/playtest_walker.gd` | `PlaytestWalker` | path planning and following with real input (RouteBot steering) |
| `game/tools/playtest/playtest_grid_nav.gd` | `PlaytestGridNav` | A* on the real collision, for targets the route network does not reach |
| `game/tools/playtest/playtest_report.gd` | `PlaytestReport` | steps, checks (with parity keys), screenshots, errors, phases, the strict block; `report.json` / `report.md` |
| `game/tools/playtest/playtest_scenario.gd` | `PlaytestScenario` | base class of a scenario |
| `game/tools/playtest/playtest_runner.gd` + `.tscn` | | one process (phase) of a run: arguments, seeds, error guards, watchdog, strict reconciliation, report |
| `game/tools/playtest/playtest_engine_log.gd` | `PlaytestEngineLog` | records push_error and engine errors (reported, not fatal) |
| `game/tools/playtest/playtest_process.gd` | `PlaytestProcess` | runs a scenario's phases in child processes and reads the report (unit tests, tools) |
| `game/tools/playtest/scenarios/*.gd` | | the scenarios (see "Scenarios") |
| `scripts/playtest.sh` | | the command line: mirror, import, phases, exit code |
| `scripts/playtest_quests.sh` | | the every-quest set: the `quest` scenario once per chain in parallel copies, then the table |
| `game/tests/unit/test_playtest_*.gd` | | the tests (see "Tests") |

## Writing a scenario

Create `game/tools/playtest/scenarios/<name>.gd`:

```gdscript
extends PlaytestScenario
## <name>: one paragraph on what this playthrough proves (it is the report's first note).

func description() -> String:
	return "Test D: pick up, use, equip, save, reload"

func max_seconds() -> float:      # game-time budget of one phase (the watchdog)
	return 600.0

func run(d: PlaytestDriver) -> void:
	var k := PlaytestKit.new(d)                          # the shared composite play
	if d.phase == 0:
		var ng: Dictionary = await d.new_game("Tester", "female", "541", {"str": 9})
		if not d.check("new game", ng.ok, ng.why):
			return
		await _setup_warp(d)                             # setup: logged as a console step
		d.begin_strict("after the setup warp")           # optional: no cheat from here on (see "Strict mode")
		k.connect_bus()
		var h: Dictionary = await k.hunt(["2"], func() -> bool: return d.state().exp >= 10, {"max_s": 120.0})
		d.check("fought to 10 EXP", h.ok, "%d kills" % h.kills, ["monster:2"])   # the parity key it proves
		d.carry["inventory"] = d.character().inventory.to_dict()    # survives the reload, with its Godot types
		await d.reload_process()                             # Quit Game: the process ends here
		return
	# phase 1: a new process on the same saves
	await d.continue_game()
	var diff := PlaytestDriver.diff(d.carry["inventory"], d.character().inventory.to_dict())
	d.check("the inventory survives a real reload", diff == "", diff)

func _setup_warp(d: PlaytestDriver) -> void:         # console calls of a strict scenario live in _setup* functions
	await d.console("warp 000000040")
```

Rules:

- **`run()` is a coroutine.** Await every driver call documented "Await it". A call that is not awaited runs in the
  background and the scenario races it.
- **Play first, console for setup only.** `console()` steps are counted apart from play steps in the report, so a
  reader can tell legitimate play from setup. A shell call the UI could not make is an `api` step and carries the
  reason. A scenario that must prove a console-free run calls `d.begin_strict(reason)` after its setup (see "Strict
  mode"); its console calls then live only in functions named `_setup*` (a unit test enforces it).
- **Use the kit for composite play.** `var k := PlaytestKit.new(d)`: travel between maps, talking, conversations,
  quizzes, markers, item use, AP, shops, hunting and deaths are written once there. Do not copy them into a scenario.
- **`check()` fails the run; `soft_check()` only warns.** Use `soft_check` for a known issue the scenario must surface
  without blocking the rest of the flow (a feature another package has not built yet, say).
- **Tag what a check proves.** `d.check(name, cond, details, ["quest:1005", "monster:1"])`: the parity keys of
  contract C6 (`<category>:<id>`). `report.json` keeps them per check and sums them per key.
- **Do not hard-code canonical numbers.** Read them from `d.db()` (`ContentDB`), `ShopService`, `MonsterDef`,
  `StatCalculator` and the like. The sample `fight` compares the EXP it gains against `MonsterDef.exp_reward`; the
  `quest` scenario reads every quest fact through `PlaytestQuestPlan`.
- **Phases.** `reload_process()` ends the process the way a player does: the pause menu's Quit Game, then the shell
  saves and quits. The runner then starts a new process with `phase + 1` on the same save directory and calls
  `run()` again. Branch on `d.phase`. Values travel in `d.carry`, which is written with `var_to_str`, so ints stay
  ints and vectors stay vectors. A run has at most 12 phases (8 before the clean-character playthrough, which
  restarts the process seven times).

## The driver API

Every call that plays logs one **step** with its kind, its game and wall durations and its result, and returns a
Dictionary. A call made inside another one is a nested step (for example, the walks of a `talk_to`). It is listed with
its depth, but only top-level steps are counted.

Step kinds:

| Kind | Meaning |
|---|---|
| `play` | real input, or waiting on the game |
| `console` | `console()`, setup only |
| `api` | the UI could not be driven, so the shell was called; the reason is in `fallback` |
| `observe` | `screenshot`, `window_text` |

### Shell

| Call | Does | Returns |
|---|---|---|
| `new_game(name, gender, weapon_id := "", ap := {})` | Through the **real screens**: New Game is clicked, the name is typed into the name field, then Clear and "+" are clicked for each point of `ap` (or Recommended when `ap` is empty), the gender and `Weapon_<id>` buttons are clicked, and Start is clicked. If a control does not respond, the call falls back to `MainShell.start_new_game` (an `api` step with the reason). All five sample scenarios drive the screen without a fallback headless; smoke and fight were also run windowed | `{ok, via ("screen" \| "api"), slot, map, why}` |
| `continue_game()` | the title's Continue button | `{ok, via, slot, map}` |
| `quit_to_title()` | Esc until the pause menu is open (open windows close first), then Quit to Title. The shell saves first | `{ok, via}` |
| `save_game()` | Esc, Save, Esc. It is OK when `Events.game_saved` fired | `{ok, via, slot, status}` |
| `load_from_pause_menu(slot)` | Esc (windows close first), the pause menu's Load, then the Load button of `slot`'s row (`MainShell.load_in_game`); waits until the game plays again. The strict ledger is checked before and re-baselined after, as for Quit to Title and Continue | `{ok, via, slot, map}` |
| `reload_process()` | Quit Game (the shell saves), and the next process continues (see "Phases"). Never returns | |

### Input (real events)

| Call | Does |
|---|---|
| `press(action, seconds)` / `tap(action)` | holds or taps an action through its first keyboard key in the InputMap (`Controls.BINDINGS`), for example `jump` is Space and `attack` is J |
| `press_key(key, seconds)` / `tap_key(key)` | raw keys the windows read that are not actions: Enter, Y, N, Tab, digits, Esc |
| `type_text(text)` | types into the focused control (one key event with its unicode per character) |
| `click(target)` | moves the mouse onto the control, presses and releases. `target` is a `Control`, a path (`"/root/..."` or `"./..."` from the main scene), or a text: the topmost visible control whose text is exactly it, else one that contains it, buttons first (`find_control`, and a text search, skip a control off the screen unless it sits in a list whose centre is on the screen: `reach_reason`, since a player scrolls a long list). Only what a player can click is pressed: a row a list (ScrollContainer) clips is first scrolled into view with mouse-wheel notches (`scroll_into_view`); a control whose centre then lies outside `get_viewport().get_visible_rect()` or outside the list it sits in (`seen_reason`), or that another control covers once the pointer is on it (`covered_reason`: the GUI's hovered control is not it or inside it), is refused before any press. A refused click fails its step and adds a failed check "a player can click ..." with the control's rect and the screen, or the covering control. Returns `{ok, control, why}`; for a button, ok means its `pressed` signal fired. The step's result names the control's rect |
| `pointer_onto(control, at)` | the same refusal rules without a click: moves the pointer onto the control and returns "" or why a player could not click it there (the kit's `double_click` and `drag` use it; `drag` reads both ends' positions after any scrolling and looks at the drop target again once the source is scrolled into view). `last_click_why` holds the reason of the last refused click |

### World

| Call | Does | Returns |
|---|---|---|
| `walk_to(target, opts)` | walks in the current map. Targets: a world `Vector3`; `{"local": Vector3}` or `"local:x,y,z"` (the map frame); `"world:x,y,z"`; `"portal:<id>"`; `"npc:<id>"` (1 m in front); `"spawn:<n>"`; `"slot:<n>"`; `"route:<name>[:end]"`. opts: `max_s`, `within_m`, `stop_when` (Callable), `retries` (1), `clearance_m`, `planner` (`auto`, `grid`, `routes`) | `{ok, result (DONE, STALLED, FELL, TIMEOUT, ABORTED, STOPPED), how, props, time_s, distance_m, issues, recoveries, violations, gate_errors, attempts}` |
| `walk_route(map, route, opts)` | to the start of an exported route, then along it (opts `reverse`, refused for a one_way route) | `{ok, legs, time_s, distance_m, issues}` |
| `walk_trail(from_map, to_map)` | edge mode (M2): to the portal, along the trail's centreline, across the far gate, to the destination's arrival. A link that is not an edge trail (a door, or a warp-only trail) is entered with Up instead, and the step says so | `{ok, how ("walk" \| "press_up"), via, map, time_s, distance_m, issues}` |
| `enter_portal(name)` | walks into a portal of the current map (by id, or by destination map id or name), nudges into its trigger and presses Up. A walk-only portal is walked with `walk_trail` | `{ok, from, to, via, portal, issues}` |
| `wait_idle(max_s)` | until MapSession is IDLE with the player on the floor | bool |
| `find_portal(name)`, `resolve_target(target)`, `route_points(map, route)`, `route_is_one_way(map, route)` | lookups | |

### Combat and loot

| Call | Does | Returns |
|---|---|---|
| `nearest_monster(opts)` | the nearest live monster (opts `mob_id`, `max_dist_m` (30), `exclude`) | `Node3D` or null |
| `face_and_attack_nearest(max_s, opts)` | approaches the monster: over the routes when it is far or on another tier, straight at it when close. Turns to face it with a slow step and taps the attack key until it dies. The reach comes from the weapon's canonical hit boxes and the monster's touch box (`attack_reach()`: `CombatReach`, `WorldScale.actor`) | `{ok (killed), target, attacks, hits, misses (rolled MISS), whiffs (nothing in reach), damage, time_s, why}` |
| `fight_until(cond, max_s, opts)` | repeats `face_and_attack_nearest` until `cond()` is true. A monster it cannot reach is excluded | `{ok, kills, attacks, hits, time_s, fights}` |
| `pickup_all_nearby(radius_m := 6, max_s := 30)` | walks to each landed drop and presses Z (the pickup key). A drop the game refuses (a full tab) stays where it is | `{ok, picked, records, refused, left}` |

### NPCs, windows, shop

| Call | Does | Returns |
|---|---|---|
| `talk_to(npc_id)` | walks to approach points around the NPC until the prompt offers "[F] Talk to ...", then presses F. The points lie on rings 1.0 to 2.5 m out (the front first) where the body can stand within 0.7 m of the NPC's talk zone (`talk_gap`). When a walk ends short of the zone (a counter in between), the player leans in: up to 1.5 s of walking straight at the NPC, as a player presses into a counter. NPCs are not solid, so neither a walk nor the lean brings the feet closer than `talk_min_gap()` to the NPC's (the player's body radius, `NPC_BODY_RADIUS_M` 0.35 and 0.15 m of air: 0.8 m; the acceptance review saw the player's body inside Rain's). At most 4 points are walked and 12 planned. A point with no path from where the player stands (no route, no grid path, on another tier) is skipped, and so is every later point at its ground height (the same perch, terrace or pocket) | `read_dialogue()` plus `reached_over_props`, `leaned` and `npc_distance_m`; on failure `{open: false, talk_gap, why}`, where `talk_gap` is the closest the body came to the talk zone (m) |
| `talk_gap(npc, feet)` | the game's talk rule (`WorldNpc.in_range`) as a distance: how far the body standing at `feet` is from the NPC's talk zone, `<= 0` inside it. The zone is the NPC's talk Area3D, a sphere of `interaction_radius_m` (1.6 m) centred 0.8 m above the NPC's feet, and it must overlap the body capsule (0.3 m radius, 0.45 to 1.5 m above the feet). Feet within 1.6 m of the NPC's feet also count, as the fallback | m |
| `read_dialogue()` | the conversation on screen | `{open, type, npc_id, text, buttons, choices, selected, banner, view}` |
| `choose(choice)` | answers with the window's keys. A menu choice (its position, or text it contains) uses digit 1-9, else Up/Down + Enter. On a Yes/No, `"yes"` / `"no"` use Y / N. The buttons: `"next"` / `"ok"` (Enter), `"back"` (Backspace), `"end"` (the End Chat button) | `read_dialogue()` after |
| `next()` | Enter on a line. It is refused on a Yes/No or a menu, where Enter would answer; use `choose()` there | |
| `close_dialogue()` | Esc, through the shell's window stack | bool |
| `open_window(name)` / `close_window(name)` / `window_text(name)` | `inventory`, `equipment`, `stats`, `quests`, opened and closed by their toggle keys. `window_text` returns the window's visible text | bool / String |
| `shop_buy(item_id, qty)` / `shop_sell(item_id, qty)` | in the open shop, with its keys: Tab, the inventory tab's digit, Up/Down to the row, Right/Left to the quantity, then Enter once the shop's confirm key is armed | `{ok, message, mesos_delta, count_delta, quantity, result}` |
| `shop_open()` / `close_shop()` | | |

### Setup, recording, time

| Call | Does |
|---|---|
| `console(cmd)` | `Debug.run(cmd)`, the console's own path, and waits for a warp it started. A `console` step. In strict mode the command is refused (it never runs) and a failed check records it |
| `begin_strict(reason)` / `is_strict()` | strict mode from this step on, for the rest of the run (see "Strict mode") |
| `screenshot(name)` | `<out>/shots/NN_p<phase>_<name>.png` when windowed; headless it is logged as skipped |
| `state()` | flow, map and name, MapSession state and last transition, position (world, local and region), floor, climbing, dead, input, facing, level, EXP, HP/MP and their maxima, AP/SP, mesos, base stats, the inventory summary, equipment, quests (in progress and completed), modal, open windows, dialogue and shop |
| `check(name, cond, details, parity)` / `soft_check(...)` / `note(text)` | PASS/FAIL lines, WARN lines, free notes; `parity` is an optional array of contract C6 keys the check proves |
| `PlaytestDriver.diff(a, b)` | `""` when the values are equal (numbers with tolerance, an int equals the same float), else where they first differ |
| `frames(n)`, `wait(s)`, `wait_until(cond, max_s)`, `game_s()` | game time: physics frames / 60 |
| accessors | `main`, `ctx()`, `world()`, `player()`, `session()`, `game()`, `character()`, `db()`, `events()`, `debug()`, `system(name)`, `monsters()`, `loot()`, `interaction()`, `npc_ui()`, `dialogue()`, `shop()`, `windows()`, `hud()`, `combat()`, `walker`, `input`, `notices` (the `Events.notice` lines heard) |

## How input works

The player keeps its `KeyboardInput`; the harness never swaps the input source. Everything goes through
`Input.parse_input_event` plus `Input.flush_buffered_events()`, sent from a process frame:

- **Keys** are `InputEventKey` with `keycode` and `physical_keycode`. Actions are pressed through their first keyboard
  binding.
- **Movement while walking a path** uses `InputEventAction` `move_*` with a **strength**, on device 7.
  `KeyboardInput.move_vector` reads `Input.get_action_strength`, so any direction is possible.
  `PlaytestInput.screen_move_for` inverts `world_move` (`right * x + forward * y`) with the player's `view_right` and
  `view_forward`. Probe, 2026-10-04: a world direction comes out at exactly `walk_speed` (3.000 m/s).
- **The mouse** sends `InputEventMouseMotion` and `InputEventMouseButton` at `viewport.get_final_transform() *` the
  control's centre (`get_global_transform_with_canvas`). Headless runs dispatch GUI clicks too, at any coordinate:
  a press at y 948 of a 900 px screen still reaches a button there. So every click, double-click and drag first checks
  that a player could make it (on the screen, not covered; see `click`) and fails with the reason when not.
- **Mouse wheel**: `PlaytestInput.wheel(at, down)` sends one notch (a press and a release of the wheel button);
  `scroll_into_view` uses it on a list that clips the control a click wants.
- **Timing.** An action press is reported to the physics tick that starts after the event. A tap is down, one physics
  tick, up. `wait()` and the walker count physics frames, not wall time.

## Headless and windowed

The headless display server reports a 64 x 64 window, which the project's `canvas_items` / `expand` stretch turned
into a 1600 x 1600 GUI area and a square camera view. A window that grew off the bottom of a windowed 1600 x 900
screen therefore still fitted headless, and the harness, which then did not check the screen, clicked its button: the
acceptance review's windowed runs failed `test_skills` (22 checks), `test_box` (1), `kit` (2) and the clean-character
playthrough (8) on the Skills window's Set key at y 948, while all 50 headless evidence reports had passed. Two
changes make the modes agree on what a player can click:

- `pin_headless_screen` (`playtest_runner.gd`): headless, the root window's content scale is the project's 1600 x 900 with
  the aspect "ignore", so the GUI area and the camera's 16:9 view are the windowed ones. Every run prints `PLAYTEST
  VIEWPORT visible rect ...` at boot.
- The click rules of `click`, `pointer_onto`, the kit's `double_click` and `drag` (above): a control off the visible
  rect or covered by another control is refused, with a failed check, in both modes.

With the code before the Skills window fix, a headless `test_skills` on the pinned screen fails on the same button as the
review's windowed run did ("Button 'Set key' (338, 948 342x30) lies outside the visible screen (0, 0 1600x900)"; 19
failed checks before it stopped, against the windowed run's 22); after it, it passes in both modes (51 checks headless
and windowed in the final evidence run). What still differs: windowed runs load the visual chunks (headless, collision only), so a
check about what is drawn (a canopy hiding a box, a colour) needs `--windowed` and a look at its screenshots.

## Walking

`PlaytestWalker.plan(to)` tries these in order:

1. **routes**: the map's exported routes through `TraversalNav`, the traversal bot's planner. Ladders and ropes are
   on these, and they are the walkways the route sweep validated.
2. **grid**: `PlaytestGridNav`, A* over 0.35 m cells on the real collision with the player's own reach from its
   `MovementModel`. It can walk up or down steps within `step_up`, jump onto ledges up to `jump_apex + step_up - 0.2`,
   and drop up to 3 m. It needs the planning capsule clear.

   The ground is what the controller's feet stand on: the first surface of the walkable, blocking and scenery layers
   whose normal is within `floor_max_angle`. That includes **flat prop tops** (a rock, a counter). They cost more, and
   a path's `props` counts them, so a scenario can flag a path that only works by jumping onto scenery.
3. **routes+grid** and **grid+routes**: the routes to the route point nearest the goal, then the grid; or the
   reverse.
4. **straight**: a straight line. The walk then reports where it stalled.

`TraversalPaths.resample` and `with_clearance` refine the path (props on the way are stepped around). RouteBot
steers it: pure pursuit, jumps at rises, ladders on climb segments, stall after 2 s without progress, and a time
budget. Each tick, its intent becomes real input:

| RouteBot intent | Real input |
|---|---|
| direction | the `move_*` strengths |
| jump | Space for one tick |
| climbing | Up or Down held |
| ladder grabs | Up / Down taps |

On a stall the walker re-plans once from where the player stands, trying the grid first if the routes stalled. A map
change aborts an in-map walk (trail walks allow it), and so do a death and the `max_s` budget. A modal window, a warp
or knockback stops the player exactly as it stops a keyboard player. While MapSession is not IDLE the walker holds
still, and that time is not counted as a stall.

## Report

`report.json`, format 2 (format 1 plus `strict`, `strict_raw`, `parity`, `counts.parity_keys` and the checks'
`parity`):

| Key | Content |
|---|---|
| `scenario`, `result`, `seed`, `windowed`, `args`, `finished`, `reload_requested` | `result` is `PASS` (finished, at least one check, no failed check, no fatal error, and in strict mode no violation), `FAIL`, or `RELOADING` between phases |
| `totals` | `{game_s, wall_s}` over all phases |
| `phases` | `[{phase, started_at, game_s, wall_s, end}]`; `end` is `done`, `reload`, `timeout` or `error` |
| `counts` | `steps` `{play, console, api, observe}` (top level), `checks`, `checks_failed`, `warnings`, `errors`, `engine_errors`, `screenshots`, `input_reasserts`, `parity_keys` |
| `strict` | `{"enabled": false}`, or `{enabled, reason, since {phase, step, game_s}, console_steps, api_steps, debug_commands, ledger {reconciled, heard, mismatches, vital_steps}, violations [{phase, kind, detail}], ok}`: the proof of a no-cheat run (see "Strict mode"). `strict_raw` is the same block without the counted steps (what the next phase reads back) |
| `parity` | per parity key: `{checks, passed, failed, warned}` |
| `checks` | `[{i, phase, name, ok, details, at_game_s, step, soft, parity?}]` |
| `steps` | `[{i, phase, depth, kind, name, detail, ok, result, at_game_s, game_s, wall_s, fallback?}]` |
| `screenshots` | `[{name, phase, path \| skipped + reason}]` |
| `errors` | fatal: `[{phase, kind (script, scenario, timeout, harness), message}]` |
| `engine_errors` | not fatal: push_error, engine errors and warnings while the scenario ran |
| `notes`, `carry` (readable), `carry_var` | `carry_var` holds the typed copy |
| `git` | `{commit, dirty, mixed, reused_copy}`: the commit `scripts/playtest.sh` found at HEAD for the first phase, whether `game/`, `tools/` or `scripts/` differed from it in any phase, whether a later phase ran another commit, and whether the run reused a mirrored copy (`PLAYTEST_REUSE_COPY=1`). `report.md` prints it on its "Code" line, and the parity build warns about missing, dirty or mixed commits |

`report.md` holds the same report as a header (with the strict verdict) and tables: Strict violations, Errors, Checks
(PASS, **FAIL**, WARN, with their parity keys), Parity keys, Steps (nested steps indented with `·`), Screenshots,
Engine errors, Notes and Phases. Console lines while a run plays: `PLAYTEST STEP`, `PLAYTEST CHECK PASS|FAIL|WARN`,
`PLAYTEST FALLBACK`, `PLAYTEST NOTE`, and at the end `PLAYTEST_RESULT` (with `strict ok|VIOLATED|off`),
`PLAYTEST_FAILED_CHECK`, `PLAYTEST_ERROR` and `PLAYTEST_REPORT <path>`.

**Errors and the watchdog:**

- A `ScriptErrorGuard` is attached before main.tscn loads. Every GDScript runtime error is a fatal `script` error,
  whether it comes from the game or from the scenario. In Godot 4.7 such an error only aborts the current function,
  which returns null, so without the guard a broken step could pass silently. The guard caught the harness's own bug
  during development.
- A scenario that does not compile is a fatal `scenario` error.
- `PlaytestEngineLog` records push_error and engine errors as `engine_errors`. They are not fatal.
- The runner's `_process` (`PROCESS_MODE_ALWAYS`) checks the game-time and wall-time budgets. Past either, it writes
  the report with a `timeout` error and quits, even if the scenario is stuck awaiting something forever.
  `--quit-after` would kill the process without a report.
- `PlaytestProcess` also scans the child's output for `SCRIPT ERROR` and `Parse Error` lines (parse errors happen
  before the guard exists). It gives each child a hard `--quit-after` cap far above the budget: twice opts
  `max_s` plus 300 s, or 4 hours of game time. The cap only matters if the runner itself stops processing. Like
  `playtest.sh`, it removes an old report from `out` first, and a phase that writes no report ends the run with a
  `process_errors` line (`passed()` is then false).

## Pitfalls

- **Fixed fps vs real time.** Under `--fixed-fps 60` each frame is 1/60 s of game time however long it takes, so game
  time is deterministic and runs faster than real time headless (smoke: about 55 s of game in 12 s). Timers,
  `wait()` and RouteBot all count game time. Measure in `game_s` (reported per step), never `Time.get_ticks_msec`.
  The wall time is reported alongside. `--realtime` windowed runs follow the clock instead: physics may take 0 or 2
  steps in a frame, which the walker handles by counting physics frames, but results are no longer repeatable.
- **Focus.** A window that loses OS focus makes Godot release every pressed key and action. The harness re-sends what
  it holds every frame (`PlaytestInput.reassert`, counted as `input_reasserts`). A re-sent press is a new press, so
  watch that count in windowed runs, and do not use the mouse over the game window while it runs.
- **Vsync throttling.** With vsync, a windowed run is capped at the monitor's refresh rate and Windows throttles a
  covered or minimized window further. `--disable-vsync` (always set by `--windowed`) runs as fast as the GPU allows.
  Screenshots wait for `RenderingServer.frame_post_draw`.
- **Headless has no frames.** `screenshot()` is a logged skip, and visual chunks are not loaded (`GameSession` turns
  them off headless; collision is loaded). Anything visual needs `--windowed`.
- **Saves are private** (`<out>/saves`). The project's `user://` is shared by every copy of the project, the user's
  real game included. A phase 0 run deletes the previous run's `saves/`, `shots/` and report in its `--out`
  directory.
- **Await in conditions.** Write `var ok := await d.x()` and then `if ok:`. Do not put `await` inside `and` / `or`
  expressions.
- **A freed control compares equal to null.** A button that frees its own screen (Start, Continue) is gone after the
  click. The driver decides "is it a button" before clicking; do the same in custom code.
- **Ints become floats in JSON.** Use `d.carry` (typed through `var_to_str`) and `PlaytestDriver.diff` (an int equals
  the same float) when comparing across a reload.
- **The console teleports.** `goto` and `warp` are setup. A `goto` can put the player where no walk leads (the pocket
  behind Lucy's counter). Warp back to the map's spawn before walking on.
- **Monsters push.** Contact damage knocks the player back, and a walk in a hunting ground can stall on it. The
  walker re-plans once. Walk with the kit (`travel_to`, `walk_safely`, `approach`): a monster that keeps hitting the
  player is fought and low HP is healed or rested (see "PlaytestKit"). A scenario that is not about survival can still
  `console("god on")`, which is logged as setup.
- **New `class_name` scripts need an import.** Godot learns a new class from the import (`--import`). `playtest.sh`
  and `test.sh` import their private copies; when you check a new script by hand in `game/`, import it first.

## PlaytestKit

`var k := PlaytestKit.new(d)` (`game/tools/playtest/playtest_kit.gd`) holds the composite play that every scenario used
to copy (`test_a_traversal`, Tests B to G, `quest`, `playthrough`, `kit`, `npc_bubbles`, `npc_shanks`, `pause_load`,
`test_box` (its Three Snails throw) and `walk_probe` use it). Where a scenario still drives the UI its own way, it does
so on purpose and a comment says why: Test G presses the shop's keys one at a time to read the picker between them,
Test D holds the Stats and Equipment windows open around its equips, Test B's Peace probe stands in a Sentinel for a
fixed 4 s. Everything the kit does goes through the driver's real input and reads the live game; nothing writes game
state, so every kit call is legal in strict mode.

| Area | Calls |
|---|---|
| bus | `connect_bus()` (EXP awards, quest events, touches), `exp_since(t0)`, `damage_taken`, `touches`, `touched_recently()` |
| travel | `travel_to(map, opts)`: map by map over the canonical portals (`portal_path(db, from, to)`, a breadth-first search that knows 000000030 -> 000000040 is one-way), each hop a `walk_trail` with one retry, deaths answered with OK. opts `fallback_warp` (non-strict scenarios only: a failed hop becomes a WARN and a logged console warp; otherwise a failed check), `safe` (default true: the survival policy on the trails). `travel_rows`, `travel_text()`, `fallbacks` |
| survival | `walk_safely(target, opts)`, `survive(opts)`, `rest(until)`, `threat()`, `best_heal_item()`, `hp_frac()`, counters in `survival`. The policy: a walk is interrupted only when HP falls below `hp_floor` (0.4 of Max HP), or, above 55% HP (`FIGHT_BACK_HP`), when a monster the player can beat (at most 3 levels above it) hit the player in the last 1.5 s and is still next to it (`on_threat` "fight"; "ignore" keeps walking); `interrupt_when()` is that guard for scenarios that walk with the driver (Test A does). A fight back takes that monster (never a namesake on another tier) and does not chase it over the routes. Below the floor the player drinks the best HP consumable it holds (Item window, Use button), else rests (`rest()`): first off any ladder, rope or vine it hangs on (`leave_climb()`: Down to the foot, else Up over the top, at most 12 s each way; natural recovery pauses while climbing, contract C4), then to the arrival point farthest from the monsters (at most 25 m away; a new touch on the way ends that walk) and stands still until `hp_resume` (0.8); a monster that comes close is walked away from, and only a cornered player that keeps being hit fights back. Monsters that merely pass by never stop a walk. A monster a fight back cannot reach without a chase (a ledge just above or below) is shunned for `SHUN_S` (4 s): it stops counting as a threat and the walk goes on (`shun()`, `shunned()`; without it seed 2 of the 1006 chain spun 24 interrupts in 2 s of game time at the foot of a Snail Hunting Ground I ledge and failed its trail hop). `unstick()`: off a spot where every planned walk stalls at once (a ledge corner whose way off neither planner takes, though a player steps off or jumps), real-input pushes in 8 directions, then with a jump, until the feet are 2.5 m away (a logged `kit.unstick` step); `walk_safely` opts `unstick` uses it after a walk that stalled where it began, and so do the talk retry's walk to the arrival, the hunt's slot tour and a trail hop whose retry stalled where it began (`retry_stalled()`: measured from where the retry started, not where the hop did, because the first walk may carry the player along the trail to the corner). Test A with it (2026-10-05, seed 1): 54 legs, 472 checks, no death (the baseline walker died on legs 22 and 32 in 000001000; they now pass with 2 and 0 survival stops). `unstick(opts)`: `toward` (a world point: the pushes go toward it first, then its sides, away and along the diagonals, `unstick_dirs()`), `jump` ("always": every push hops at once), `push_s`, `min_m`; Test B's wedge after a knockback is `{"toward": monster, "jump": "always", "push_s": 0.6, "min_m": 0.3}` |
| NPCs | `approach(npc)` (to 3.5 m, so the marker is on screen), `talk(npc)` (talk_to; a death on the way is a WARN and a retry; an NPC that cannot be planned to from where the player stands is tried again from the map's arrival; the result carries `pre`, the reward baseline taken right before the chat opened, and stays in `last_talk`, so a scenario can read the talk that `open_shop` made; opts go to the walks back after a death: `fallback_warp` and the survival opts), `marker(npc)` (the presenter's state and the engine's), `quest_window(qid, tab)`, `row_has`, `rows_text` |
| conversations | `converse(goals, opts)`: goals `quest id -> "accept" \| "decline" \| "complete" \| "quiz_wrong[:rank]"`. A menu picks the entry of a goal not met yet (else End Chat), a Yes/No answers Y only for an "accept" of a quest not started, lines are paged with Enter, and a quiz menu (node `q<id>.quiz`) is answered with the canonical correct choice or the requested wrong one. Returns the pages, the banners and the quiz answers with the line shown after each |
| quizzes | `PlaytestKit.quiz_answer(db, qid)` (static): the correct choice by the canonical `correct_choice_index` (1018's is inferred and says so in `basis`), the question, the choices, and each wrong choice with the wrong-answer line MeowDB lists for it (in choice order, as the game pairs them) |
| items | `use_item(id, via, opts)` (`double_click`, `button` or `quickslot`; HP and count read right around the input; the result names the item's `slot`; opts `keep_open` leaves the Item window open on its tab, for a scenario that reads the slot afterwards), `tooltip_rows(c)` (hovers a slot, from 400 px above, and returns the item tooltip's rows: the windows' or the HUD's), `row_texts(rows)` and `row_contains(rows, needle)` (static), `slot_index(tab, id)`, `drink(id)` (the canonical restore it should give, as `want_hp`), `equip(id)`, `bind_quickslot(id, key)` (a mouse drag onto the HUD slot), `double_click(control)`, `drag(a, b)` (both refuse, with `why` and a failed check, a control a player cannot point at: `PlaytestDriver.pointer_onto`; `test_d_inventory` and `regen` use the same rule), `hp_restore(id)` |
| AP | `stats_window()`, `click_plus(stat)`, `allocate_ap(["str", "dex"])` (the stats window's "+" with the mouse) |
| shops | `open_shop(npc)` (talk, page the greeting), `buy(id, qty)`, `sell(id, qty)`, `close_shop()` |
| loot | `pickup(radius, max_s)`: like `pickup_all_nearby`, but RouteBot stops about 0.75 m short of a drop, outside the canonical pickup box (25 px = 0.625 m), so the kit then steps straight onto the landing point at half speed until the drop is inside the box (`step_onto`) and presses Z. A logged `kit.pickup` step whose result names the map-local spot it started and ended at (a walk onto a drop below a ledge can end in a pocket) |
| hunting | `hunt(mob_ids, cond, opts)`: the survival policy first, whatever is hitting the player, then the nearest wanted monster with the attack key, the drops picked up after every kill, unspent AP spent through the stats window (`ap_plan`), deaths answered and the walk back to `map`, a tour of the spawn slots when nothing is in sight. The survival opts hold for the hunt's own walks; `hp_floor` 0 turns its HP stops off (Test D: the Eggs are the test's own). opts `pickup_radius_m` (5) and `pickup_s` (10); `after_kill` (a Callable awaited after each kill; with `pickup` false it does the pickup itself, as Test D does after its drops screenshot); `fallback_warp` (non-strict only): three fights in a row that reach nothing, then a walk to the arrival that cannot leave the spot, make a trap: a WARN "the hunting player is never trapped", a row in `traps` and a logged console warp. `nearest_of(mob_ids)` |
| deaths | `is_dead()`, `death_notice()`, `respawn(opts)` (the notice's OK; the row goes to `deaths`; opts `click` false only waits, for a respawn another key started: Test F's jump-key probe) |
| contracts | `activity()` (C4), `sit()` (X, C5), `stand()`, `use_chair(id)` (a double-click in the Set-up tab, C5), `skill_key(id)` / `cast_skill(id)` (the skill's quickslot key, C3 `{"kind": "skill"}`; a cast shows as a cooldown, an effect from `skill:<id>` or the attacking activity), `breakables()` / `break_box(box)` (nodes in group `&"miso_breakables"` with `placement_key()`, `is_broken()`, `hits_left()`, C8; test_box's approach: spots beside the box on its own ground at 0.6 of the weapon's canonical reach (`box_reach_m()`, `box_spots()`), walked to with the routes, then the grid, up to 6 spots; no attack from another tier; closer after 3 whiffs; `break_box(null)` passes over a box it cannot stand beside for the next nearest, at most 3. Amherst's box 000001010:0 stands at the foot of a 1.6 m terrace: from Lucas (on the plaza above) the old walk-up ended on the terrace edge 1.3 m above it and 40 attacks whiffed, which failed both playthrough seeds' 1012 gate probe). Every feature behind them is built (wave 1); on a build without one, its helper answers `{"ok": false, "why": "... is not built"}` |
| skills | `learn_skill(id)` (K, then the skill's "+" with the mouse; one SP), `bind_skill(id, key)` (the skill's row, Set key, the key), `throw_at(target, opts)` (Three Snails from inside its canonical band: walks to about 150 px, faces, taps the skill's key; every hit heard on `PlayerSkills.cast_resolved`; the target is a monster, or a Wooden Box to aim at, which is never hit: the cast searches monsters only, #5), `skills_window()` |
| death | `let_monsters_win(mob_ids, opts)`: the player stops defending and walks into the nearest monster again and again (real input, no attack, no potion) until it dies; every hit is the monster's own contact damage. opts `until` (a Callable: stop alive once it holds; Test B's touch probes count touches), `between` (awaited before each approach: Test B's console heal), `hop` (hold the jump key from 3 m out, so a touch can land mid-air: Test F), `climb_s` (the walk budget to a monster on another tier). The target is `same_tier_monster(mob_ids, skip, opts)`, whose choice is the static `pick_index()`: the nearest on the player's tier (`max_dy_m`, 1.0) within `max_dist_m` (40), `debug_spawns` false leaves out the console's spawns, `other_tiers` true takes, when none stands on the tier, the nearest on another one with its height weighing three times its distance (Test F's rule; Test B's fights and probes use it too) |
| record | `snapshot()`, `bag_delta(a, b, skip)`, `total_exp()`, `checkpoint(tag)` (level, EXP, mesos, AP, SP, HP, MP, stats, equipment, ETC and Use items, skills, deaths, quest states, `play_s` (the run's game time over every phase) and `play_time_s` (the character's own saved clock) into `d.carry["checkpoints"]` and a note: the brief's progression audit), `track()` (from the event bus into `d.carry`, across phases: `visited_maps`, `kills_by_mob`, `exp_by_source`, `level_at`, `deaths`, `respawns`, `mesos_flow`, `items_gained`/`lost`/`used`, `skills_used`, `sat`), `carry_totals()` (this process's pickup and survival counters, per phase and summed: `picked_mesos` and `picked_bags` count the meso bags picked up with Z), `play_s()`, `local_pos()`, `map_local(at, map, step)` (a world point in a map's frame, rounded), `flat_m(a, b)` (static), `log_clock()`, `log_since(t)`, `log_history()` (the HUD log's live history array: an entry kept from before a trade is found again by identity, as Test G does), `log_on_screen()`, `hud_mesos()` (the status bar's meso text), `shot(name)` |

## Strict mode

`d.begin_strict(reason)` proves a run used no developer help after a point ("after the setup save" in the `quest`
scenario; "after character creation" for a clean playthrough). From that step on, for every later phase too:

- `console()` refuses the command (it never runs), records a violation and fails a check.
- An api fallback (a shell call because the UI did not respond) records a violation and fails a check.
- `DebugTools.commands_run` counts every command the Debug autoload dispatches, whoever calls it (the console, `run`,
  `call_command`, a test). The driver takes it at boot and at `begin_strict`; any increase in a strict phase is a
  violation, so a command run behind the driver's back is caught too.
- `PlaytestLedger` reconciles the character against the event bus at every phase end, before a new game, at Quit to
  Title and before a pause-menu Load. Against a baseline taken when strict mode starts and again after every Continue,
  new game and Load:

  | Value | Reconciled against |
  |---|---|
  | EXP | total EXP (every level below plus the bar) against the sum of `exp_gained` (kills, quest rewards, the death penalty's negative award) |
  | mesos | the `mesos_changed` deltas |
  | items | every item's count in the inventory plus the equipment against `item_gained - item_lost` |
  | quests | every status change against its `quest_started` / `quest_completed` / `quest_forfeited` |
  | level | one `leveled_up` per level gained, the last one announcing the live level |
  | AP and base stats | AP plus the base stats grew by exactly the AP the announced level-ups grant (`Progression.level_up_gains`); no base stat fell, only `beginner.json`'s allocatable stats rose; AP and the stats are what they were at the last `stats_changed` (an AP spend through the stats window announces one) |
  | SP and skills | SP changed by the level-ups' SP minus one per `skill_leveled`; each skill's level is the last one its `skill_leveled` announced, one event per level |
  | base Max HP / MP | the level-ups' canonical gains |
  | HP and MP | step by step: each `hp_changed` / `mp_changed` against the last one, explained by what was heard in between: `player_damaged` (down by the damage, never below 0), `item_used` (up by the item's canonical restore, never above the max), `leveled_up` (combat.json's level-up heal), `player_died` (death.json's respawn vitals, which the death sets silently until the respawn announces them), `equipment_changed` (down to a smaller max), or, for MP, the `skill_used` heard right after it (PlayerSkills pays the MP first) whose canonical MP cost it is. An HP rise with no cause must be one recovery tick: recovery.json's natural tick, the bonus of the chair a `player_sat_down` named (alone or with the natural tick: one NaturalRecovery step heals both), or a tick of a heal-over-time effect such as Recovery (`EffectBook.heal_for_tick`; the last tick comes after the effect has ended); a smaller one only when it fills HP. The live HP and MP must be the last announced (the respawn vitals while a death is pending) |

  A change nobody announced (a scenario writing `c.mesos` or `c.ap`, adding to the inventory, completing a quest,
  healing) is a mismatch, and so is an announced HP or MP step nothing explains. The `strict.ledger` block counts the
  explained HP and MP steps by cause (`vital_steps`). The ledger does not follow the player's position: teleports are
  the scan's.
- The runner adds one check per strict phase and writes the `strict` block; `report.passed()` requires it to be ok.
- `test_playtest_strict.gd` reads every scenario that calls `begin_strict` and every harness file
  (`game/tools/playtest/*.gd`, listed from the directory, so a new file is scanned without being named): the driver,
  the kit, the quest runner and plan, the walker, the grid planner, the input, the ledger, the report, the quest
  summary, the runner, the process runner, the engine log, the scenario base class and the bubble watch. It fails on
  teleports (`place_player`, `global_position =`, `debug_warp`, `request_portal`), `Debug.run`, console calls outside
  `_setup*` functions, direct writes to the character (EXP, level, mesos, HP, MP, AP, SP, base stats, skills,
  cooldowns, effects, quickslots, inventory, equipment, the quest log), calls into the game's services that change it
  (`d.game().items.gain/lose/pickup/use_item/equip/spend_mesos...`, `quests.accept/complete/forfeit`, the quest engine,
  `allocate_ap`, `change_hp`, `damage_player`), hits or kills no attack made (`receive_hit`, `land_hit`,
  `report_monster_killed`) and file writes and saves (`FileAccess.WRITE`, `save_now`, `SaveService.`). Each exception
  is named by file, function and call, and an entry that matches nothing any more fails:

  | File | Function | Call | Why |
  |---|---|---|---|
  | `playtest_driver.gd` | `new_game` | `start_new_game(` | the api fallback when the creation screen does not respond, after its counted `api` step |
  | `playtest_driver.gd` | `save_game` | `save_now(` | the api fallback when the pause menu's Save cannot be used, after its counted `api` step |
  | `playtest_driver.gd` | `console` | `call("run"` | the console itself, after its counted `console` step (refused in strict mode) |
  | `playtest_report.gd` | `_write_text` | `FileAccess.WRITE` | writes `report.json` and `report.md` into the run's `--out` |
  | `playtest_quest_summary.gd` | `_write` | `FileAccess.WRITE` | writes `quests.md` and `quests.json` into its `--out` |

  Synthetic sources in the same test prove the scan flags each kind.

What it does not prove: that a scenario never reads state the UI does not show (reading is allowed), and that the
setup before the strict step was minimal (the console steps before it are listed in the report and the every-quest
table). The player's position rests on the static scan alone. Because the game's services announce what they change,
the ledger cannot tell a service call from play: those calls are caught only by the scan, which reads source lines, so
an indirection it cannot see (a method name built at run time, `call("gain", ...)`) would get through. And a write
that follows the game's own rules and is then announced by an unrelated event (AP moved into a stat behind the bus,
followed by a `stats_changed` from equipping) looks like play to the ledger; the scan refuses the write.

## Quest plans

`PlaytestQuestPlan.plan(qid, db)` derives how to play a quest from canonical data only, so no scenario hard-codes quest
knowledge: the start and end NPCs and maps (`start_npc`, `start_maps`, `end_npc`, `end_maps`), `min_level`,
prerequisites, the chain (`quest_line`), follow-ups, the accept items (canonical `items_given_on_accept` plus MisoStory
`accept_items` adaptations, flagged), the kill objectives with the maps whose canonical spawns hold the monster and
the hunt map (fewest portal hops from the start map to the hunt and on to the turn-in, then the most spawns), the item
objectives with every source (monster and breakable drop tables: each entry with the chance
`DropRates.effective_entries` gives it, the owner's table cell, whether it resolves, and its `quest_gate`) and the best one to
farm, the item-use objectives, the quiz answer key, the rewards and the hand-ins (`hand_ins`: canonical
`items_removed_on_completion`, the list the quest engine removes). `source_why(row, quest)` is the obtainability rule:
an unresolved chance, a chance of 0, a gate to another quest (C1/C2) or no map holding the owner rules a source out.
An objective that only an unresolved drop could supply is listed in `blocked` as a source-data gap, never faked.
`setup_for(ids)` says what a chain needs first (the first quest's level and start map, the prerequisites outside
the chain, prerequisites first), `chains(db)` is the every-quest set (one chain per canonical quest line, each
standalone quest alone), `parse_ids` and `chain_spec` name chains, and `item_sources`, `best_source`,
`spawn_maps`, `hunt_map` and `hops` are public.

## The quest runner

`PlaytestQuestRunner` (`game/tools/playtest/playtest_quest_runner.gd`) plays one quest at a time, step by step, with
the kit's real input and the plan's canonical facts. The `quest` scenario and the clean-character `playthrough` both
play their quests through it, so a quest is checked the same way in both.

| Call | Does |
|---|---|
| `offer(qid)` | below the quest's `min_level`: checks the refusal, then hunts to the level; walks to the start NPC's map; for a quest whose items come from a breakable gated to it, breaks one box first (it must drop none of them); the NPC's marker, the engine and the Quest Log's Available tab; the accept in the dialogue (Yes); the accept items in the bag; the HUD log; the marker after the accept; the In Progress tab |
| `objectives(qid)` | from the live progress: kills with the attack key in the hunt map, items from their best source (monster drops picked up with Z, Wooden Boxes broken), items used by a double-click; the Quest Log row after each kill objective |
| `turn_in(qid)` | the turn-in NPC's completable marker; a quiz with one wrong answer first (its canonical line, the quest still in progress), then the canonical answer; the completion; `check_rewards()`: total EXP + `rewards.exp` in one `quest:<id>` EXP event, mesos + `rewards.mesos`, the fixed items, one item of each random group, the canonical hand-ins taken, nothing else in the bag, and the C3 `rewards_received` record; the HUD log and the Completed tab |
| `after(qid)` | each canonical follow-up is available (or level-gated) and its NPC's marker offers it when the NPC is in this map |
| `play(qid)` | all four from the quest's live status |
| `mid_reload(tag, when)` / `verify_mid()` | the save through the pause menu and Quit Game; after the next Continue, the quest log, level, EXP, mesos, bag and map are the saved ones and the Quest Log still lists the quest |
| `results(ids)` | the per-quest verdicts into `d.carry["quest_results"]` |

`mid_reload_policy` decides where a run restarts in the middle of a quest: `"auto"` (the `quest` scenario: each quest
with objectives once, at half of its first kill or item objective, and the run's first talk-only quest right after
its accept), `"listed"` (only the quests in `mid_reload_quests`; the playthrough lists 1009 and 1012) or `"off"`.

What each quest showed is kept in `d.carry["quest_evidence"][qid]` (it survives the restarts): the offer (marker,
engine, Quest Log, level), the gate probe, the accept (pages, items, Quest Log row), each objective's progress and
source, the quiz answers, the completion, the rewards (EXP and mesos against canonical, the bag change, the random
pick, the `rewards_received` record), the follow-ups and the mid-quest restart. `PlaytestQuestSummary` renders it.

## The every-quest set

`scenarios/quest.gd` plays one quest or one chain (`--quest 1013-1019`, or `QUEST=...`):

- **Phase 0, setup** (the only console use, every command a logged console step): a new game through the title and
  creation screens; a warp to the first quest's start map; for a level-gated first quest, a check that it is refused
  below its level (no offer marker, the engine says unavailable); `level N`; `quest accept` + `quest complete <id>
  force` for prerequisites outside the chain; a save through the pause menu; Quit Game. A chain that needs none of
  that (its first quest starts in the creation map at level 1 with no prerequisite: 1000-1001) turns strict mode on
  right after character creation, so its report proves a console-free run from the very start.
- **Phase 1 on, play** (strict from the Continue): for each quest of the chain, by its live status so a restart
  resumes anywhere: for a quest whose items come from a breakable gated to it (1012 under contract C1), one Wooden Box
  broken before the accept, which must drop none of them; the NPC's offer marker and the Quest Log's Available tab;
  the offer accepted in the dialogue; the
  accept items in the bag; the HUD log; the marker after the accept; the Quest Log's In Progress tab; then the
  objectives (kills with the attack key in the hunt map, drops picked up with Z, Wooden Boxes broken, items used by
  double-click, levels reached by hunting when a later quest needs them); the turn-in NPC's completable marker; for a
  quiz, one wrong answer first (its canonical line, the quest still in progress), then the canonical answer; the exact
  reward (total EXP + `rewards.exp` with one `quest:<id>` EXP event, mesos, fixed items, one item of each random
  group, the canonical `items_removed_on_completion` taken, nothing else in the bag; the C3 `rewards_received` record
  when the quest log has it); the HUD log and the Completed tab; and each follow-up's availability and marker.
- **Save and restart in the middle:** a save through the pause menu and Quit Game at the half of the first kill or
  item objective of each quest (a monster drop or a Wooden Box item alike), after the accept of the first quest with
  nothing to hunt, and once between two quests at the middle of a chain of three or more (after quest
  `floor(n / 2)`: after 1006 in 1006,1009,1010, after 1015 in 1013-1019). The next phase checks the quest log,
  level, EXP, mesos, bag and map against the saved ones and the Quest Log's In Progress row.
- Every quest check carries `quest:<id>`; `d.carry["quest_results"]` holds the per-quest verdict. The table
  (`PlaytestQuestSummary`) fails every quest of a chain whose strict block was violated, or whose report has a fatal
  error or a failed check that names no quest; a failure tagged to one quest fails only that quest.

`scripts/playtest_quests.sh` runs every chain (`--list` prints them; `test_playtest_quest_plan.gd` keeps the list equal
to `PlaytestQuestPlan.chains`), `--jobs` at a time in private copies that are mirrored and imported once, then
`PlaytestQuestSummary` writes `<out>/quests.md` and `<out>/quests.json`: one row per quest (PASS, FAIL or NOT_PLAYED,
its checks, the failed ones, the random reward drawn) and one per chain (strict verdict, setup console steps, phases,
game and wall time).

### Results (2026-10-06, the final Iteration Three build, seeds 1, 2 and 3)

**20 of 20 quests PASS on each seed** (520 / 523 / 523 quest checks, 0 failed, 0 warnings), every chain strict after its
setup (0 console steps, 0 api fallbacks, 0 developer commands, 0 ledger mismatches); 1000-1001 strict from character
creation. These are the final evidence run's reports (commit `1f3120c`, headless on the pinned 1600x900 screen with
the click gate, `--jobs 1` beside two other runs). 1012 passes with the real Wooden Box (contract C8) and the
1012-gated drops (C1/C2), and the C3 `rewards_received` record of 1008 and 1011 is a hard check that matches the
random pick. Per quest and per seed, with what each run showed:
[QUEST_PLAYTHROUGH_REPORT.md](QUEST_PLAYTHROUGH_REPORT.md).

| Chain | Quests | Checks | Setup console steps | Phases | Game s (seed 1 / 2 / 3) | Wall s (1 / 2 / 3) | Random reward (1 / 2 / 3) |
|---|---|---|---|---|---|---|---|
| 1000-1001 | Sera's Mirror | 45 | 0 | 3 | 99 / 108 / 103 | 12 / 11 / 12 | |
| 1002 | Roger's Apple | 25 | 1 | 3 | 69 / 74 / 68 | 10 / 9 / 10 | |
| 1003-1004 | Nina and Sen's dinner | 44 | 1 | 3 | 114 / 122 / 113 | 14 / 12 / 14 | |
| 1005 | Todd's How-to-Hunt | 27 | 1 | 3 | 102 / 124 / 102 | 13 / 12 / 12 | |
| 1006, 1009, 1010 | Mai's Training | 90 / 93 / 93 | 1 | 6 | 721 / 697 / 712 | 102 / 88 / 100 | |
| 1007-1008 | the letters | 48 | 2 | 3 | 317 / 375 / 416 | 43 / 47 / 60 | 708 Brown Skullcap / 709 Green Skullcap / 711 Red Headband |
| 1011 | Biggs's collection | 30 | 2 | 3 | 490 / 952 / 432 | 62 / 127 / 54 | 558 Razor / 559 Fruit Knife / 559 Fruit Knife |
| 1012 | Pio's recycled goods | 33 | 2 | 3 | 113 / 115 / 108 | 12 / 12 / 13 | |
| 1013-1019 | Rain's seven quizzes, one wrong answer each | 178 | 2 | 4 | 110 / 108 / 100 | 18 / 18 / 20 | |

Seed 1's 1009 has 3 checks fewer: its 5 Red Snails were all killed during the other hunts, so that objective needed
no hunt of its own. Seed 2's 1006 chain stepped off the ledge corner of the trail-hop finding below with one unstick,
and its 1011 needed 2 deaths and 6 rests before the Orange Mushroom Cap. The final run before the drop-source switch
(`9ddf137`) and the one before wave 4 (`c4e9ac5`: the 1600x1600 headless GUI area, no click gate) had also passed 20
of 20 on each seed; the first run on the owner's drop sources (`0fc524a`) failed seed 2's 1006 chain at that trail
hop ("Findings").

**Before the shun fix (the wave-1 harness on this build).** Seeds 1 and 3 passed 20/20; seed 2 failed 1006, 1009 and
1010 at the trail hop from Snail Hunting Ground I to II (the survival guard spin, "Findings"). On the base build
before wave 2, 1012 failed at "Wooden Boxes stand in 000001010" (no breakables runtime), and 1008 and 1011 had a
`rewards_received` WARN (the quest log did not keep it yet).

## The clean-character playthrough

`scenarios/playthrough.gd` is ONE run from a brand-new character to Shanks' departure boundary (brief Phase 15 and
the Definition of Done "Gameplay"). Results: [PLAYTHROUGH_REPORT.md](PLAYTHROUGH_REPORT.md) (Iteration Three).

- **Strict from character creation.** `new_game` drives the title and creation screens (the name typed, the
  Recommended stats and weapon, Start); `begin_strict("after character creation")` follows at once. From there on no
  console command, no api fallback, no developer command and no change the event bus did not announce, in every
  phase; the only reloads are the pause menu's Save and Quit Game (or Quit to Title) and the title's Continue.
- **A route of named steps** (`STEPS`), in the island's order: Heena and Sera, Roger, Nina and Sen, Todd and Peter,
  Robin, Sam (the first SP: Three Snails learned with "+", put on key 1 and thrown at a Snail), the Snail Hunting
  Grounds to A Split Road (Mai, Maria), Southperry (Yoona, Bari, Biggs, Shanks refusing a low level, Pan), Mai's
  training, Recovery and Nimble Feet, The Field West of Amherst (1010's Orange Mushroom, 1011's drops), Amherst
  (Lucas, Pio's boxes), a death back in The Field West of Amherst, The Green Relaxer sat on at low HP where the
  respawn left the player, Rain's quizzes, Sid, Lucy (an Orange after a Nimble Feet cast), the maps around Amherst and
  the six forest maps, the last turn-ins, the quest hat and knife, Pan again, the boarding level and fare, and
  Shanks. Each step is checked done in `d.carry["steps_done"]`, so a phase resumes at the first step not done; every
  step reads the live game state (quest status, inventory), so a restart in the middle of a step resumes it.
- **Quests** are played by `PlaytestQuestRunner` with the canonical checks of the every-quest set
  (`mid_reload_policy` "listed": the process restarts in the middle of 1009 and of 1012).
- **Restarts:** after Mushroom Town (plus an in-process Save, Quit to Title and Continue), after Southperry, in the
  middle of 1009 and of 1012, after Amherst, before boarding and after the departure screen. After each Continue the
  character is compared with what was saved (level, EXP, mesos, AP, SP, skills, bag, equipment, quests, map, play
  time).
- **What the scenario decides, and nothing else:** the route; the AP split (`AP_PLAN`, STR and DEX); the SP order
  (one point in each Beginner skill, then round the three); what it buys (Pan: Leather Sandals, Sid: a Sword, Lucy:
  two Red Potions; a buy it cannot afford is tried, refused and retried on a later visit) and sells (loot no open quest
  needs, keeping 6 Snail Shells for Three Snails); the death. Prices, rewards, levels, the route's fare and level, the
  death penalty and the return maps are read from canonical data.
- **The death:** when no death has happened by then (after Pio), `let_monsters_win` walks into the Orange
  Mushrooms, Red Snails and Shrooms of The Field West of Amherst without attacking or drinking until they win; the
  notice's OK respawns the player at the map's canonical return map (Amherst), and the EXP lost is checked against
  `formulas/death.json`. The respawn leaves the player at low HP, so the chair that follows shows its own bonus on
  top of natural recovery (one interval seated: the bonus plus one or two natural ticks).
- **Speech bubbles at the shops** (Pan, Sid, Lucy; `PlaytestBubbleWatch`): the run may only wait, never force a
  bubble, so it reads each NPC's bubble schedule (`NpcBubbleSchedule.until_next`) and waits at most until the next
  bubble is due, plus 1 s. Near the shopkeeper a bubble must show before the shop opens; while the shop is open, a
  bubble must fall due for an NPC that could show it (its name tag on screen, not in a conversation: the shop's
  greeting has ended) and no bubble may show on any frame of that wait; after the shop closes a bubble must show
  again. A bubble showing before the shop opens cannot carry the proof, because the greeting dialogue (a modal window
  too) hides it before the shop is open; the schedule skips a bubble that falls due while hidden, so the frame its
  `until_next` jumps is the frame it would have shown. The earlier check read the bubbles once, 0.2 s after the shop
  opened, and passed whether or not they were hidden (#40). `test_playtest_bubble_watch.gd` shows the watch fails when
  the presenter ignores the open window.
- **The audit** (`k.track()` plus checkpoints) is in `d.carry`: `checkpoints`, `exp_by_source`, `kills_by_mob`,
  `visited_maps`, `talked_to`, `level_at`, `deaths`, `respawns`, `mesos_flow`, `items_used`, `skills_cast`, `shops`,
  `equipped`, `chair`, `departure`, `quest_evidence`, `findings` and `totals`. The end of the run checks every
  Definition of Done "Gameplay" item from them (every quest, map, NPC and monster type, monster drops and meso bags,
  natural levelling, every AP spent, the skills, the three shops bought from and sold to, consumables, gear, the
  chair, the death, the departure, the restarts). A skill counts only when it went off: `skills_cast` records the
  real casts (a try that never threw or was refused records 0), and the end check needs at least one cast, and for
  Recovery and Nimble Feet their effect started or their MP spent (the acceptance review saw "learned and cast" pass
  with 0 casts). A first Three Snails throw that found no target is tried again after Mai's training.
- **Findings:** a step that cannot be completed stops the run with a failed check and a row in `d.carry["findings"]`
  (the step, map, map-local position, level, what happened and what was expected).

```bash
PLAYTEST_TIMEOUT_S=7500 ISOLATE=pt bash scripts/playtest.sh playthrough --seed 2 --max-wall-s 7000 --out _scratch/pt/s2
```

## Cost

Headless runs are faster than game time, plus about 20-30 s to mirror and import a fresh copy (`PLAYTEST_REUSE_COPY=1`
skips it; `playtest_quests.sh` does that for every chain after a worker's first).

| Run | Game time | Wall time | Ratio |
|---|---|---|---|
| `smoke` | 54 s | 8 s | 7x |
| `test_e_quest` | 1040 s (2 phases) | 137 s | 7.6x |
| `test_c_progression` (to level 7, Iteration Two baseline) | 8032 s | 1074 s | 7.5x |
| `quest --quest 1002` | 45-60 s (3 phases) | 9-13 s | 5x |
| `quest --quest 1006,1009,1010` | 610 s (6 phases) | 94-147 s | 4-6.5x |
| `quest --quest 1011` | 1020-1035 s (3 phases) | 175-230 s | 4.5-6x |
| `playtest_quests.sh --jobs 3` (all 9 chains) | 2040-2230 s summed | about 6 min (5-6 min with two playthroughs running beside it) | |
| `playtest_quests.sh --jobs 1` (all 9 chains, final evidence run) | 2130-2670 s summed | 6.3-7.2 min beside two other runs | 7-8x |
| `playthrough` (creation to Shanks, 8 phases) | 2200-2590 s | 299-411 s (beside two other runs) | 6-7.6x |
| `playthrough --windowed` (seed 1, final evidence run) | 2581 s | 636 s (beside two headless runs) | 4.1x |

Wall times grow with the machine's load (the ranges are two runs, the slower one beside other agents' Godot runs).

## Scenarios

| Scenario | Proves | Owner |
|---|---|---|
| `smoke` | new game through the screens, route Main of 000000001, the trail to 000000010 across the gate, Roger, F, Esc, save, quit to title, Continue: the same map, place and character | harness |
| `fight` | in 000000040: the attack key against Snails until a kill drops loot, canonical EXP per kill, the drop picked up with Z | harness |
| `reload` | phase 0: new game, a walk, Quit Game; phase 1: Continue, the same map, place and character | harness |
| `api` | every remaining driver call (keys, windows, the grid planner, Lucy's shop, a door, End Chat, a declined offer, a mouse click) | harness |
| `npcs` | talk to every NPC of the 25 maps on foot from its map's arrival, then press on until well inside its talk zone (21/21 since V1-1) | harness |
| `counter` | Pan across his counter: the walk, the lean, `talk_gap` against the game's prompt | harness |
| `kit` | PlaytestKit's reference run: AP through the stats window, Lucy's shop opened by talking (the talk in `last_talk`), buy and sell at canonical prices (the purchase in `log_history()`, the status bar's `hud_mesos()`), a quickslot bound by a drag and used, a use by double-click with `keep_open` and the slot's `tooltip_rows`, a potion drunk, `map_local` against the driver's state, sandals equipped, a checkpoint; the contract helpers: The Green Relaxer (given in the setup) from the Set-up tab and with X, Recovery learned with the Skills window's "+" (`learn_skill`), put on key 2 with Set key (`bind_skill`) and cast with it (`cast_skill`), the Wooden Box in the store (all hard checks since wave 1 merged them) | harness |
| `quest` | the every-quest set (see above) | harness |
| `quest_forfeit` | forfeit from the Quest Log (owner ruling #10), strict from character creation: Heena's 1000 accepted on foot, the Forfeit button only on the in-progress quest, Cancel (clicked) and Delete then Esc change nothing, the question's Forfeit (clicked) forfeits (`quest_forfeited`, the HUD line, the log back to Available), Heena offers 1000 again and it is accepted | harness |
| `test_a_traversal`, `test_a_routes`, `test_a_detours`, `test_a_ladders` | Test A: the island on foot, every route, the routes planner against the grid, every ladder foot against every press-Up trigger | harness |
| `test_a_probe_1005`, `test_a_probe_trap`, `test_d_probe`, `test_d_stuck` | one-off diagnostics of single spots (000001005 out00, a 000001000 trap, kill and drop rates, the A Split Road pocket) | harness |
| `walk_probe` | can the walker get from a map-local spot to a target (`WALK_MAP`, `WALK_FROM`, `WALK_TO`)? The plan and the walk, for walks a scenario saw fail from an odd spot; `WALK_TO=talk:<npc>` plays `PlaytestKit.talk` instead (approach points, the walk back to the arrival, `unstick`) | harness |
| `test_b_combat` | Test B: every species, hit detection, damage windows, touch damage, knockback, death, EXP (uses the kit) | monsters |
| `test_c_progression` | Test C: a clean Beginner levels only by killing, AP through the stats window, every number against canonical data and MeowDB vectors (uses the kit) | harness |
| `test_d_inventory` | Test D: pickups, use by double-click and quickslot, equipment, persistence across a process restart (uses the kit) | drops |
| `test_e_quest` | Test E: 1002, 1006 twice (one with a save, Quit to Title, Continue and a process restart at 5/10), 1007 -> 1008 (uses the kit) | harness |
| `test_f_death` | Test F: real monster deaths, the death notice, the EXP penalty, quit while dead and reload; death.json's respawn HP plus exactly the natural ticks the banked clock allows (C4: the clock holds while dead, is never reset and survives the quit) (uses the kit) | harness |
| `test_g_shop` | Test G: Pan, Sid and Lucy on foot; canonical prices, buying, selling; The Green Relaxer (given in the setup) refused by Lucy as a protected item, its message on screen (uses the kit) | harness |
| `test_feel_*` | the movement, camera, ledge, gate and route feel reviews (`test_feel_common` is their library) | harness |
| `playthrough` | the clean-character playthrough: creation to Shanks' departure boundary, strict from the step after character creation (see "The clean-character playthrough") | harness |
| `npc_shanks` | Shanks' departure boundary: refused below level 7 and without the fare, the guide's sentence and the unfinished quests, Yes -> End of Maple Island (no voyage, no fare taken, the flag set), Space ignored, Enter and Esc close it, the flag survives a reload (setup: warp, level, mesos) | harness (from quests) |
| `npc_bubbles` | NPC speech bubbles in Amherst: every text one of the NPC's canonical idle lines, none while talking (strict after the setup warp) | harness (from quests) |
| `regen` | natural HP recovery in the real game; sitting, and Up at a real portal while seated (the player stands up and uses it); last, on a ladder: climbing pauses the clock, and `PlaytestKit.rest()` climbs off before it rests | mechanics |
| `trap_probe` | escape attempts from known former trap spots | world |
| `test_skills`, `test_box` | the Beginner skills; the Wooden Boxes: 1012 with real boxes, box state not saved, every box of the other five box maps, and Three Snails thrown hits_to_break + 1 times at an Amherst box that keeps all its hits (skills never hit a box, #5) (Iteration Three packages) | skills, breakables |
| `pause_load` | the pause menu's Load inside a running session (contract C3): after a save, a box broken and drops on the ground; Esc, Load, the slot's Load: the same map, a new instance, both boxes whole, no ground drop, nothing parked, the saved character (adopted from the wave-2 integration review) | harness |
| `resume_gate` | G1: a save just past a trail gate (inside the trigger of the portal the player arrived through: Amherst east00, Southperry west00) resumes there after Quit Game and Continue (load step `resume`, the portal disarmed as after an arrival, re-armed on leaving it) | harness |
| `test_b_population` | the monster population of all 15 hunting maps | monsters |
| `save_it2_continue` | an Iteration Two save continued in the real game: the migration, Save writing v2, a v2 reload | saves |
| `perf_baseline` | the performance baseline (#62): island load time, then fps, frame time, draw calls, primitives and memory in the five busiest maps; windowed, real time, `PLAYTEST_RESOLUTION=1920x1080` (docs/runtime/PERF_BASELINE.md) | art (#59) |
| `ui_minimap` | the minimap on all 25 maps and the Phase 12 feedback, by real kills to level 2; the status bar's Map [M] button, and the fold kept across Quit Game and Continue (two phases) | UI |

## Findings (2026-10-05)

- **Acceptance review: headless passed what a windowed player could not do.** See "Headless and windowed": the
  Skills window's Set key was off the bottom of the windowed screen and the harness clicked it anyway headless (a
  1600 x 1600 GUI area, no screen check). Fixed in the harness (the pinned screen, the click rules) and in the game
  (every window stays above the HUD's status bar; the Skills window keeps one size: UI.md). The same review saw the
  playthrough's skill summary pass with 0 casts and the player's body inside Rain's while they talked; both fixed
  (above and `talk_to`).

- **Iteration Three playthrough package (the harness defects its runs found, all fixed):** the survival guard spun
  on a monster it could not reach (seed 2 of 1006: 24 interrupts in 2 s; `shun()`); `break_box` walked up to a box
  at the foot of a terrace from the terrace above and whiffed 40 times (Amherst 000001010:0; test_box's tier-aware
  approach and the next-box fallback); Three Snails walked toward a Snail on a ledge and never threw (`throw_at` stops
  only when level with the target, `same_tier_monster()`); `let_monsters_win` stopped 0.75 m short of every monster
  (now the last step is straight at it); a run continued with `--resume` from a copy wrote its report into the
  original `--out` (the runner now writes where it is told). Details and the one open game observation (G1: a
  Continue just past a trail gate logged a resume-point warning, fixed in wave 3, below):
  [PLAYTHROUGH_REPORT.md](PLAYTHROUGH_REPORT.md) "Findings".
- **Wave 3 (the polish package).** `test_f_death`'s "[D6.1] after OK: HP 50" read HP 60 on the reviews' runs: natural
  recovery's clock (contract C4) holds through a death and is never reset, so a clock banked near 10 s ticks within the
  0.5 s the scenario stood in town after the respawn (the integrated build's run banked 9.450 s at that death and read
  9.950 s at the check). The game follows the owner's rule; the scenario now expects death.json's HP plus exactly the
  ticks the clock allows, and checks the clock holds while dead and survives the quit. `ui_minimap` expected the old
  "SP to distribute" line; the HUD says "SP to spend". G1: the resume point just past a gate lies inside the trigger
  of the portal the player arrived through, which `IslandWorld.validate_resume` refused; the save's entry portal is now
  accepted (the load disarms it as an arrival does), and `resume_gate` checks both gates the playthrough saw (on the
  old code it fails 6 checks with the playthrough's own warnings). `test_skills` on seed 1: three `--trace` runs gave
  identical checks and identical step digests.
- **A trap in The Field West of Amherst (000001000), confirmed.** Test C's hunter (seed 1, final harness) ended phase
  1 at map-local (62.5, 0.0, -37.5), world (196.9, 5.0, 541.9), below terraces 4-9 m up; the Continue of phase 2
  resumed it there, and in the whole phase it reached none of 393 targets ("phase 2: every kill gave its canonical
  monster EXP" fails with 0 kills; the scenario now also fails "the hunter is not stranded" and names the cell).
  `trap_probe` FAILs the spot (best escape 1.92 m, rise 0.00 m) and `walk_probe` finds no plan to the arrival. Same
  conditions as F1-9 (walled pocket, autosave and Continue resume inside it). For the world package. How the hunter
  got there: in phase 1, right after an Orange Mushroom kill (step 453; every later target is 4-9 m up). No rest walk
  came before it, so either that fight's knockback or the precise pickup that follows a kill (its walker plans drops
  of up to 3 m) took it down; that pickup walk was not a logged step then, and `kit.pickup` steps now name where they
  end. Seed 2 at the same commit passes (73 checks).
- **A possible pocket in The Field West of Amherst (000001000).** Twice in Test A (leg 24, in01 to Dangerous Forest),
  a Snail's knockback dropped the walker off the in01 terrace to map-local (29.0, 0.0, -40.6), world (173.4, 5.0,
  520.2). `walk_probe` finds no plan from there to in01 or to the map's arrival (routes, the grid and the linked plans
  all fail; the walk stalls at once). `trap_probe` calls the spot "not a trap" because one try moved 7.2 m flat,
  although no try rose at all: the flat-distance rule the audit flagged. Test A now reports such a spot as a WARN with
  its coordinates and warps back to retry the leg; the spot belongs to the world package's stuck-region scan.
- **A ledge corner at A Split Road (000000050), a harness gap (review, 2026-10-05).** A seed-1 run of 1006,1009,1010
  ended a Red Snail fight on the 3.8 m ledge at map-local (48.7, 3.8, -15.3). From there the routes and the grid both
  plan a way that stalls at once (a wall 1.9 m on), so the approach to Mai, all four talk points and the walk back to
  the arrival stalled, and 1009 failed at "Mai can be talked to for the turn-in". `trap_probe` calls the spot no trap
  (a 3.8 m drop or a jump gets out): the planners do not take the way off. `PlaytestKit.unstick()` now steps off such
  a spot; `WALK_TO=talk:11` from it opens Mai's chat after one unstick.
- **A trail hop that stalled mid-way, a harness defect (final evidence run, 2026-10-06).** On seed 2 the every-quest
  set's 1006,1009,1010 chain walked 10 m of Snail Hunting Ground I toward its east exit, stalled at map-local
  (27.0, 1.0, -13.1), and the retry stalled there at once. `travel_to` measured the retry's progress from where the
  hop began (9.3 m back), so it never ran `unstick()`, and the chain failed. `trap_probe` calls the spot no trap
  (escapable ground, one try). Now the retry's own start counts (`retry_stalled()`, `test_playtest_kit.gd`); the
  same chain on seed 2 then steps off with one unstick and passes.
- **Resting on a ladder, a harness defect (final evidence run, 2026-10-06).** Test C's hunter chased a Shroom up a
  ladder on A Split Road, gave up ("could not reach the monster"), and then rested on the ladder: 15 rests of the
  150 s budget, 2,250 s of game time, without one natural-recovery tick, because natural recovery pauses while
  climbing (contract C4: only still and seated time counts; the game was right). A logged diagnostic showed
  `activity()` "climbing" in all 226 samples. `rest()` now gets off the climbable first (`leave_climb()`); the
  `regen` scenario checks both sides at the end of its phase 1 (HP 40% on 000000001's ladder near its top: 3 s on
  the ladder leave the clock and HP as they were, then the rest climbs down and heals 20 -> 40 of 50; without the
  fix the player stays on the ladder and heals nothing). The check lives in `regen`, not in `kit`, because its
  setup needs an api step (no console command grabs a ladder) and `kit` is the api-free reference run
  (`test_playtest_smoke.gd`).
- **Runs of one seed: repeatable since the clock fix, as far as measured.** Before wave 2's integration fix, two
  headless seed-1 runs of the same chain (the engineer's and the review's) diverged in phase 2: the same trail walk
  took 10.6 s / 31.7 m and 8.7 s / 25.9 m. The cause was `Game.clock` running through the threaded island load, a
  wall-clock-dependent number of frames, which put the global spawn ticks at a different phase of play in every run;
  the clock now stands still on the title and during the load. Three seed-1 runs of `test_skills` on the integrated
  build (wave 3) gave the same 50 checks with the same details and the same `--trace` digest at every step (the
  `frame` field the digest then carried differed only by the load frames, which is why it now records `Game.clock`).
  `test_skills` had failed one seed-1 rerun before the fix (its walks stalled). Longer runs have not been compared
  this way, and the wave-2 reviews still saw quest 1011's random pick and check counts differ between seed-1 runs
  made before the fix, so a long result remains one sample; the every-quest table and the playthrough were taken on
  three seeds.
- **Heena's perch** (000000001): its stairs start on the arrival side, so from Sera's hill no approach to Heena can be
  planned; `PlaytestKit.talk` walks back to the arrival and tries again (1000-1001 pass).
- **Knockback and the survival guard:** a touch that stops a walk is often followed by a knockback that carries the
  monster out of reach before the walk returns; the guard therefore records that it fired. A fight back takes the
  monster that hit (`nearest_monster` opts `target`), never a namesake on another tier, and does not chase it
  (`face_and_attack_nearest` opts `chase` false): chasing one 8 m below had walked the player off its trail.

## The talk rule

`WorldNpc.in_range`: the NPC's talk Area3D (a sphere of `interaction_radius_m`, 1.6 m, centred 0.8 m above the NPC's
feet) overlaps the player's body (a capsule of radius 0.3 m from 0.45 to 1.5 m above the feet); the fallback is feet
within 1.6 m of the NPC's feet. `talk_gap` measures it. The 2026-10-04 survey found 5 of 21 NPCs unreachable on foot
(Heena, Roger and Nina on perches, Sid and Lucy behind counters); round V1-1 gave them walkable stairs and an
`across_counter` talk-zone profile, and the `npcs` scenario now passes 21/21 with every margin at least 0.6 m
(PLAYTHROUGH_REPORT.md). Heena's stairs start on the arrival side of her perch, so from Sera's hill there is no planned
way up; `PlaytestKit.talk` then walks back to the arrival and tries again.

## Tests

```bash
ISOLATE=harness INCLUDE_WORLD=1 bash scripts/test.sh test_playtest_     # the scenario runs SKIP without the world
```

| File | Covers |
|---|---|
| `test_playtest_report.gd` | the PASS rules: an unfinished report or one without checks never passes, a soft check only warns, a fatal error fails; top-level step counts by kind and step durations; the JSON round trip keeps `carry`'s ints and vectors and the reload request; `report.md` (WARN rows, escaped pipes); parity keys per check (kept once, summed per key, through report.json and report.md); `screen_move_for` maps back onto every direction for three camera bases and keeps a slow step's strength; actions press their first `Controls.BINDINGS` key; `diff` |
| `test_playtest_strict.gd` | `DebugTools.commands_run` counts every dispatched command; a strict report fails on a console or api step after the strict step, a violation, a developer command or a ledger mismatch, and the verdict survives the phase round trip; `PlaytestLedger` explains pickups, spending and unequipping and flags direct writes to mesos, items, quests and EXP; it explains two level-ups, AP and SP spent, damage, a Red Potion, a natural tick, a chair's bonus, Recovery's MP and every one of its heal ticks, a death and its respawn, and flags a write to AP, a base stat (raised, lowered, or AP moved into it behind the bus), SP, a skill level, the level, base Max HP, HP and MP, an announced HP loss or gain nothing explains and an MP drop no skill paid; the strict scenarios (quest, playthrough, npc_bubbles) and every harness file (`game/tools/playtest/*.gd`) make no cheat call outside their counted logged steps and named exceptions, and the scan flags a synthetic scenario's (and a synthetic driver's) service calls, teleport, AP write, console call outside `_setup*` and unnamed file write |
| `test_playtest_bubble_watch.gd` | `PlaytestBubbleWatch` on real `NpcPresenter`s with an injected modal check: with the window rule a bubble falls due within the schedule's bound and none shows; with the rule disabled the same watch fails; a bubble skipped during a conversation proves nothing; `wait_shown`'s bound finds the next bubble |
| `test_playtest_kit.gd` | the quiz answer key of 1013-1019 from canonical data (index, text, basis, the wrong-answer pairing); travel over canonical portals and the one-way link; the node parser and the bag bookkeeping; a hop whose retry stalled where it began; both quickslot shapes; the row readers (`row_texts`, `row_contains`); `unstick_dirs` (toward the target first, then its sides, away, the diagonals); `pick_index` (the player's tier first, the species, `skip`, `max_dist_m`, `max_dy_m`, debug spawns, other tiers by flat distance plus three times the height) |
| `test_playtest_quest_plan.gd` | 1005 (Tutorial Jr. Sentinels and their Shellpiece in 000000030), 1009 (three species at A Split Road; the setup completes 1006), 1012 (the Wooden Box), schema v2 (C1) source rows and the gate rule on a synthetic Wooden Box table, 1002 (the apple adaptation), 1011 (Blue Snails and Orange Mushrooms, its hand-ins), the quiz plan and 1016's setup; the chain list equals `playtest_quests.sh`'s; `PlaytestQuestSummary` over synthetic reports (a script error or an unattributed failure fails the chain's quests, a tagged failure only its quest); `combined_markdown` over two synthetic runs (verdicts and chains side by side, the per-quest evidence table); `PlaytestQuestRunner`'s mid-quest restart policy (`auto`, `listed`, `off`, never twice) |
| `test_playtest_smoke.gd` | `smoke` headless through `PlaytestProcess`, as `playtest.sh` runs it: PASS, finished, no fatal or script error, at least 15 checks, one process, the screens driven without an `api` fallback, at most one console step, the key checks present, `report.md` and the private `saves/` written; `reload`: PASS across two processes (`reload` then `done`); `counter`: PASS, with `talk_to(16)` a successful play step (the regression test for the talk rule); `quest --quest 1002`: PASS in strict mode with every quest check tagged; `kit`: PASS without an api fallback |

## Lineage

| Earlier driver | What the harness keeps |
|---|---|
| `shell_checks.gd` / `ShellCheckRunner` | main.tscn as a child with a private `Saves.save_dir`; `_until`/frames helpers; the window close through `propagate_notification`; the child process and output parsing |
| `world_ui_main_checks.gd` | real key presses through `Input.parse_input_event`; prompts, dialogue, shop and loot assertions |
| `review_combat/review_driver.gd` | mouse events through the viewport's final transform with `flush_buffered_events`; injecting outside physics frames; PlayerCombat counters |
| `review-world/driver/drive.gd` | console setup through `Debug.run`; the trail walk with RouteBot and the event sequence |
| `TraversalWalker` / `TraversalNav` / `TraversalPaths` / `TraversalTour` | path planning on routes, clearance replanning, RouteBot steering, `portal_between`. The harness drives the real `KeyboardInput` through input events instead of a `BotInput` swap |
