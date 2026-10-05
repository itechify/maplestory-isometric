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
| (default) | `--headless --fixed-fps 60`: deterministic game time. Screenshots are skipped (logged, never a failure) |
| `--windowed` | `--resolution 1600x900 --disable-vsync`, still `--fixed-fps 60`, so it gives the same results as headless, with pictures |
| `--realtime` | with `--windowed`, drops `--fixed-fps`: game time follows the wall clock (for feel checks only; results may vary) |
| `--seed <n>` | seeds `Game.rng` (combat rolls, drops, quest rewards) and MapSession's instance RNG. The default is 1, so a run is repeatable |
| `--max-s <s>` | the game-time budget of one phase (default: the scenario's `max_seconds()`) |
| `--max-wall-s <s>` | the wall-time budget of one phase (default: three times the game budget, at least 900 and at most 3300, so it fires before the outer 3600 s timeout) |
| `--quest <spec>` | for the `quest` scenario: `1002`, `1013-1019` or `1006,1009,1010` (the `QUEST` environment variable does the same) |

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
| `game/tools/playtest/playtest_ledger.gd` | `PlaytestLedger` | strict mode's bookkeeping: every change to EXP, mesos, items and quests must be announced by the event bus |
| `game/tools/playtest/playtest_quest_plan.gd` | `PlaytestQuestPlan` | how to play a quest, derived from canonical data only (see "Quest plans") |
| `game/tools/playtest/playtest_quest_summary.gd` | `PlaytestQuestSummary` | the every-quest table: reads every chain's report, writes `quests.md` / `quests.json` |
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
  ints and vectors stay vectors. A run has at most 8 phases.

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
| `reload_process()` | Quit Game (the shell saves), and the next process continues (see "Phases"). Never returns | |

### Input (real events)

| Call | Does |
|---|---|
| `press(action, seconds)` / `tap(action)` | holds or taps an action through its first keyboard key in the InputMap (`Controls.BINDINGS`), for example `jump` is Space and `attack` is J |
| `press_key(key, seconds)` / `tap_key(key)` | raw keys the windows read that are not actions: Enter, Y, N, Tab, digits, Esc |
| `type_text(text)` | types into the focused control (one key event with its unicode per character) |
| `click(target)` | moves the mouse onto the control, presses and releases. `target` is a `Control`, a path (`"/root/..."` or `"./..."` from the main scene), or a text: the topmost visible control whose text is exactly it, else one that contains it, buttons first. Returns `{ok, control}`; for a button, ok means its `pressed` signal fired |

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
| `talk_to(npc_id)` | walks to approach points around the NPC until the prompt offers "[F] Talk to ...", then presses F. The points lie on rings 0.75 to 2.5 m out (the front first) where the body can stand within 0.7 m of the NPC's talk zone (`talk_gap`). When a walk ends short of the zone (a counter in between), the player leans in: up to 1.5 s of walking straight at the NPC, as a player presses into a counter. At most 4 points are walked and 12 planned. A point with no path from where the player stands (no route, no grid path, on another tier) is skipped, and so is every later point at its ground height (the same perch, terrace or pocket) | `read_dialogue()` plus `reached_over_props` and `leaned`; on failure `{open: false, talk_gap, why}`, where `talk_gap` is the closest the body came to the talk zone (m) |
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
  control's centre (`get_global_transform_with_canvas`). Headless runs dispatch GUI clicks too.
- **Timing.** An action press is reported to the physics tick that starts after the event. A tap is down, one physics
  tick, up. `wait()` and the walker count physics frames, not wall time.

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
| `strict` | `{"enabled": false}`, or `{enabled, reason, since {phase, step, game_s}, console_steps, api_steps, debug_commands, ledger {reconciled, heard, mismatches}, violations [{phase, kind, detail}], ok}`: the proof of a no-cheat run (see "Strict mode"). `strict_raw` is the same block without the counted steps (what the next phase reads back) |
| `parity` | per parity key: `{checks, passed, failed, warned}` |
| `checks` | `[{i, phase, name, ok, details, at_game_s, step, soft, parity?}]` |
| `steps` | `[{i, phase, depth, kind, name, detail, ok, result, at_game_s, game_s, wall_s, fallback?}]` |
| `screenshots` | `[{name, phase, path \| skipped + reason}]` |
| `errors` | fatal: `[{phase, kind (script, scenario, timeout, harness), message}]` |
| `engine_errors` | not fatal: push_error, engine errors and warnings while the scenario ran |
| `notes`, `carry` (readable), `carry_var` | `carry_var` holds the typed copy |

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
to copy (Test C and Test E use it; Test D and the others still carry their own copies). Everything it does goes through
the driver's real input and reads the live game; nothing writes game state, so every kit call is legal in strict mode.

| Area | Calls |
|---|---|
| bus | `connect_bus()` (EXP awards, quest events, touches), `exp_since(t0)`, `damage_taken`, `touches`, `touched_recently()` |
| travel | `travel_to(map, opts)`: map by map over the canonical portals (`portal_path(db, from, to)`, a breadth-first search that knows 000000030 -> 000000040 is one-way), each hop a `walk_trail` with one retry, deaths answered with OK. opts `fallback_warp` (non-strict scenarios only: a failed hop becomes a WARN and a logged console warp; otherwise a failed check), `safe` (default true: the survival policy on the trails). `travel_rows`, `travel_text()`, `fallbacks` |
| survival | `walk_safely(target, opts)`, `survive(opts)`, `rest(until)`, `threat()`, `best_heal_item()`, `hp_frac()`, counters in `survival`. The policy: a walk is interrupted only when HP falls below `hp_floor` (0.4 of Max HP), or, above 55% HP (`FIGHT_BACK_HP`), when a monster the player can beat (at most 3 levels above it) hit the player in the last 1.5 s and is still next to it (`on_threat` "fight"; "ignore" keeps walking); `interrupt_when()` is that guard for scenarios that walk with the driver (Test A does). A fight back takes that monster (never a namesake on another tier) and does not chase it over the routes. Below the floor the player drinks the best HP consumable it holds (Item window, Use button), else walks to the arrival point farthest from the monsters (at most 25 m away; a new touch on the way ends that walk) and stands still until `hp_resume` (0.8); a monster that comes close is walked away from, and only a cornered player that keeps being hit fights back. Monsters that merely pass by never stop a walk. Test A with it (2026-10-05, seed 1): 54 legs, 472 checks, no death (the baseline walker died on legs 22 and 32 in 000001000; they now pass with 2 and 0 survival stops) |
| NPCs | `approach(npc)` (to 3.5 m, so the marker is on screen), `talk(npc)` (talk_to; a death on the way is a WARN and a retry; an NPC that cannot be planned to from where the player stands is tried again from the map's arrival; the result carries `pre`, the reward baseline taken right before the chat opened), `marker(npc)` (the presenter's state and the engine's), `quest_window(qid, tab)`, `row_has`, `rows_text` |
| conversations | `converse(goals, opts)`: goals `quest id -> "accept" \| "decline" \| "complete" \| "quiz_wrong[:rank]"`. A menu picks the entry of a goal not met yet (else End Chat), a Yes/No answers Y only for an "accept" of a quest not started, lines are paged with Enter, and a quiz menu (node `q<id>.quiz`) is answered with the canonical correct choice or the requested wrong one. Returns the pages, the banners and the quiz answers with the line shown after each |
| quizzes | `PlaytestKit.quiz_answer(db, qid)` (static): the correct choice by the canonical `correct_choice_index` (1018's is inferred and says so in `basis`), the question, the choices, and each wrong choice with the wrong-answer line MeowDB lists for it (in choice order, as the game pairs them) |
| items | `use_item(id, via)` (`double_click`, `button` or `quickslot`), `drink(id)` (the canonical restore it should give, as `want_hp`), `equip(id)`, `bind_quickslot(id, key)` (a mouse drag onto the HUD slot), `double_click(control)`, `drag(a, b)`, `hp_restore(id)` |
| AP | `stats_window()`, `click_plus(stat)`, `allocate_ap(["str", "dex"])` (the stats window's "+" with the mouse) |
| shops | `open_shop(npc)` (talk, page the greeting), `buy(id, qty)`, `sell(id, qty)`, `close_shop()` |
| loot | `pickup(radius, max_s)`: like `pickup_all_nearby`, but RouteBot stops about 0.75 m short of a drop, outside the canonical pickup box (25 px = 0.625 m), so the kit then steps straight onto the landing point at half speed until the drop is inside the box (`step_onto`) and presses Z |
| hunting | `hunt(mob_ids, cond, opts)`: the survival policy first, whatever is hitting the player, then the nearest wanted monster with the attack key, the drops picked up after every kill, unspent AP spent through the stats window (`ap_plan`), deaths answered and the walk back to `map`, a tour of the spawn slots when nothing is in sight. `nearest_of(mob_ids)` |
| deaths | `is_dead()`, `death_notice()`, `respawn(opts)` (the notice's OK; the row goes to `deaths`) |
| contracts | `activity()` (C4), `sit()` (X, C5), `stand()`, `use_chair(id)` (a double-click in the Set-up tab, C5), `skill_key(id)` / `cast_skill(id)` (the skill's quickslot key, C3 `{"kind": "skill"}`; a cast shows as a cooldown, an effect from `skill:<id>` or the attacking activity), `breakables()` / `break_box(box)` (nodes in group `&"miso_breakables"` with `placement_key()`, `is_broken()`, `hits_left()`, C8: walk up, face, attack until broken, pick up). Until the packages that build these land, each returns `{"ok": false, "why": "... is not built"}` |
| record | `snapshot()`, `bag_delta(a, b, skip)`, `total_exp()`, `checkpoint(tag)` (level, EXP, mesos, equipment, ETC items and quest states into `d.carry["checkpoints"]` and a note: the brief's progression audit), `log_clock()`, `log_since(t)`, `log_on_screen()`, `shot(name)` |

## Strict mode

`d.begin_strict(reason)` proves a run used no developer help after a point ("after the setup save" in the `quest`
scenario; "after character creation" for a clean playthrough). From that step on, for every later phase too:

- `console()` refuses the command (it never runs), records a violation and fails a check.
- An api fallback (a shell call because the UI did not respond) records a violation and fails a check.
- `DebugTools.commands_run` counts every command the Debug autoload dispatches, whoever calls it (the console, `run`,
  `call_command`, a test). The driver takes it at boot and at `begin_strict`; any increase in a strict phase is a
  violation, so a command run behind the driver's back is caught too.
- `PlaytestLedger` reconciles the character against the event bus at every phase end, before a new game and at Quit to
  Title: total EXP against the sum of `exp_gained`, mesos against the `mesos_changed` deltas, every item's count in the
  inventory plus the equipment against `item_gained - item_lost`, and every quest status change against its
  `quest_started` / `quest_completed` / `quest_forfeited`. A change nobody announced (a scenario writing `c.mesos`,
  adding to the inventory, completing a quest) is a mismatch.
- The runner adds one check per strict phase and writes the `strict` block; `report.passed()` requires it to be ok.
- `test_playtest_strict.gd` reads every scenario that calls `begin_strict` (and the kit) and fails on teleports,
  `Debug.run`, direct writes to the character or its services, and console calls outside `_setup*` functions.

What it does not prove: that a scenario never reads state the UI does not show (reading is allowed), and that the
setup before the strict step was minimal (the console steps before it are listed in the report and the every-quest
table).

## Quest plans

`PlaytestQuestPlan.plan(qid, db)` derives how to play a quest from canonical data only, so no scenario hard-codes quest
knowledge: the start and end NPCs and maps (`start_npc`, `start_maps`, `end_npc`, `end_maps`), `min_level`,
prerequisites, the chain (`quest_line`), follow-ups, the accept items (canonical `items_given_on_accept` plus MisoStory
`accept_items` adaptations, flagged), the kill objectives with the maps whose canonical spawns hold the monster and
the hunt map (fewest portal hops from the start map to the hunt and on to the turn-in, then the most spawns), the item
objectives with every source (monster and breakable drop tables: schema v2 entries by `chance_state`, `probability`
and `quest_gate`; Iteration Two tables by membership and the placeholder rate DropRates resolves) and the best one to
farm, the item-use objectives, the quiz answer key and the rewards. An objective that only an unresolved drop could
supply is listed in `blocked` as a source-data gap, never faked. `setup_for(ids)` says what a chain needs first (the
first quest's level and start map, the prerequisites outside the chain, prerequisites first), `chains(db)` is the
every-quest set (one chain per canonical quest line, each standalone quest alone), `parse_ids` and `chain_spec` name
chains, and `item_sources`, `best_source`, `spawn_maps`, `hunt_map` and `hops` are public.

## The every-quest set

`scenarios/quest.gd` plays one quest or one chain (`--quest 1013-1019`, or `QUEST=...`):

- **Phase 0, setup** (the only console use, every command a logged console step): a new game through the title and
  creation screens; a warp to the first quest's start map; for a level-gated first quest, a check that it is refused
  below its level (no offer marker, the engine says unavailable); `level N`; `quest accept` + `quest complete <id>
  force` for prerequisites outside the chain; a save through the pause menu; Quit Game.
- **Phase 1 on, play** (strict from the Continue): for each quest of the chain, by its live status so a restart
  resumes anywhere: for a quest whose items come from a breakable gated to it (1012 under contract C1), one Wooden Box
  broken before the accept, which must drop none of them; the NPC's offer marker and the Quest Log's Available tab;
  the offer accepted in the dialogue; the
  accept items in the bag; the HUD log; the marker after the accept; the Quest Log's In Progress tab; then the
  objectives (kills with the attack key in the hunt map, drops picked up with Z, Wooden Boxes broken, items used by
  double-click, levels reached by hunting when a later quest needs them); the turn-in NPC's completable marker; for a
  quiz, one wrong answer first (its canonical line, the quest still in progress), then the canonical answer; the exact
  reward (total EXP + `rewards.exp` with one `quest:<id>` EXP event, mesos, fixed items, one item of each random
  group, the hand-ins taken, nothing else in the bag; the C3 `rewards_received` record when the quest log has it); the
  HUD log and the Completed tab; and each follow-up's availability and marker.
- **Save and restart in the middle:** a save through the pause menu and Quit Game at the half of the first kill or
  item objective of each quest, after the accept of the first quest with nothing to hunt, and after the middle quest
  of a chain of three or more. The next phase checks the quest log, level, EXP, mesos, bag and map against the saved
  ones and the Quest Log's In Progress row.
- Every quest check carries `quest:<id>`; `d.carry["quest_results"]` holds the per-quest verdict.

`scripts/playtest_quests.sh` runs every chain (`--list` prints them; `test_playtest_quest_plan.gd` keeps the list equal
to `PlaytestQuestPlan.chains`), `--jobs` at a time in private copies that are mirrored and imported once, then
`PlaytestQuestSummary` writes `<out>/quests.md` and `<out>/quests.json`: one row per quest (PASS, FAIL or NOT_PLAYED,
its checks, the failed ones, the random reward drawn) and one per chain (strict verdict, setup console steps, phases,
game and wall time).

### Results (2026-10-05, the Iteration Three base build with this harness, seeds 1, 2 and 3)

On each seed 19 of 20 quests pass in the real game with real input, every chain strict after its setup (0 console
steps, 0 api fallbacks, 0 developer commands, 0 ledger mismatches). 1012 (Pio) is blocked by design: Rusty Screw and
Old Wooden Board come only from the Wooden Box, and the base build has no breakables runtime (contract C8), so its run
fails at "Wooden Boxes stand in 000001010" right after the accept. The WARNs are the C3 `rewards_received` record of
1008 and 1011, which the quest log does not keep yet. Checks per quest are the same on every seed; the random rewards
and the times differ.

| Chain | Quests | Result (checks) | Setup console steps | Phases | Game s (seed 1 / 2 / 3) | Wall s (1 / 2 / 3) | Random reward (1 / 2 / 3) |
|---|---|---|---|---|---|---|---|
| 1000-1001 | Sera's Mirror | PASS (45) | 0 | 3 | 74 / 79 / 76 | 14 / 13 / 14 | |
| 1002 | Roger's Apple | PASS (25) | 1 | 3 | 54 / 57 / 48 | 11 / 10 / 11 | |
| 1003-1004 | Nina and Sen's dinner | PASS (44) | 1 | 3 | 96 / 100 / 101 | 15 / 15 / 16 | |
| 1005 | Todd's How-to-Hunt | PASS (27) | 1 | 3 | 104 / 94 / 77 | 15 / 13 / 16 | |
| 1006, 1009, 1010 | Mai's Training | PASS (93) | 1 | 6 | 757 / 612 / 574 | 148 / 94 / 121 | |
| 1007-1008 | the letters | PASS (48, 1 WARN) | 2 | 3 | 420 / 407 / 313 | 71 / 66 / 68 | 712 Black / 714 Yellow / 713 Green Headband |
| 1011 | Biggs's collection | PASS (30, 1 WARN) | 2 | 3 | 533 / 1144 / 1112 | 93 / 155 / 186 | 559 Fruit Knife on all three |
| 1012 | Pio's recycled goods | FAIL: no Wooden Box runtime yet | 2 | 2 | 19 / 39 / 33 | 9 / 6 / 6 | |
| 1013-1019 | Rain's seven quizzes, one wrong answer each | PASS (178) | 2 | 4 | 58 / 81 / 59 | 26 / 20 / 24 | |

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
| `playtest_quests.sh --jobs 3` (all 9 chains) | about 2400 s summed | 8-10 min | |

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
| `kit` | PlaytestKit's reference run: AP through the stats window, Lucy's shop opened by talking, buy and sell at canonical prices, a quickslot bound by a drag and used, a potion drunk, sandals equipped, a checkpoint; the contract helpers WARN until their packages land | harness |
| `quest` | the every-quest set (see above) | harness |
| `test_a_traversal`, `test_a_routes`, `test_a_detours`, `test_a_ladders` | Test A: the island on foot, every route, the routes planner against the grid, every ladder foot against every press-Up trigger | harness |
| `test_a_probe_1005`, `test_a_probe_trap`, `test_d_probe`, `test_d_stuck` | one-off diagnostics of single spots (000001005 out00, a 000001000 trap, kill and drop rates, the A Split Road pocket) | harness |
| `walk_probe` | can the walker get from a map-local spot to a target (`WALK_MAP`, `WALK_FROM`, `WALK_TO`)? The plan and the walk, for walks a scenario saw fail from an odd spot | harness |
| `test_b_combat` | Test B: every species, hit detection, damage windows, touch damage, knockback, death, EXP | monsters |
| `test_c_progression` | Test C: a clean Beginner levels only by killing, AP through the stats window, every number against canonical data and MeowDB vectors (uses the kit) | harness |
| `test_d_inventory` | Test D: pickups, use by double-click and quickslot, equipment, persistence across a process restart | drops |
| `test_e_quest` | Test E: 1002, 1006 twice (one with a save, Quit to Title, Continue and a process restart at 5/10), 1007 -> 1008 (uses the kit) | harness |
| `test_f_death` | Test F: real monster deaths, the death notice, the EXP penalty, quit while dead and reload | harness |
| `test_g_shop` | Test G: Pan, Sid and Lucy on foot; canonical prices, buying, selling | harness |
| `test_feel_*` | the movement, camera, ledge, gate and route feel reviews (`test_feel_common` is their library) | harness |
| `regen` | natural HP recovery in the real game | mechanics |
| `trap_probe` | escape attempts from known former trap spots | world |
| `test_skills`, `test_box` | the Beginner skills and the Wooden Boxes (Iteration Three packages) | skills, breakables |

## Findings (2026-10-05)

- **A trap in The Field West of Amherst (000001000), confirmed.** Test C's hunter (seed 1, final harness) ended phase
  1 at map-local (62.5, 0.0, -37.5), world (196.9, 5.0, 541.9), below terraces 4-9 m up; the Continue of phase 2
  resumed it there, and in the whole phase it reached none of 393 targets ("phase 2: every kill gave its canonical
  monster EXP" fails with 0 kills; the scenario now also fails "the hunter is not stranded" and names the cell).
  `trap_probe` FAILs the spot (best escape 1.92 m, rise 0.00 m) and `walk_probe` finds no plan to the arrival. Same
  conditions as F1-9 (walled pocket, autosave and Continue resume inside it). For the world package.
- **A possible pocket in The Field West of Amherst (000001000).** Twice in Test A (leg 24, in01 to Dangerous Forest),
  a Snail's knockback dropped the walker off the in01 terrace to map-local (29.0, 0.0, -40.6), world (173.4, 5.0,
  520.2). `walk_probe` finds no plan from there to in01 or to the map's arrival (routes, the grid and the linked plans
  all fail; the walk stalls at once). `trap_probe` calls the spot "not a trap" because one try moved 7.2 m flat,
  although no try rose at all: the flat-distance rule the audit flagged. Test A now reports such a spot as a WARN with
  its coordinates and warps back to retry the leg; the spot belongs to the world package's stuck-region scan.
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
| `test_playtest_strict.gd` | `DebugTools.commands_run` counts every dispatched command; a strict report fails on a console or api step after the strict step, a violation, a developer command or a ledger mismatch, and the verdict survives the phase round trip; `PlaytestLedger` explains pickups, spending and unequipping and flags direct writes to mesos, items, quests and EXP; the strict scenarios and the kit make no cheat call |
| `test_playtest_kit.gd` | the quiz answer key of 1013-1019 from canonical data (index, text, basis, the wrong-answer pairing); travel over canonical portals and the one-way link; the node parser and the bag bookkeeping |
| `test_playtest_quest_plan.gd` | 1005 (Tutorial Jr. Sentinels and their Shellpiece in 000000030), 1009 (three species at A Split Road; the setup completes 1006), 1012 (the Wooden Box), 1002 (the apple adaptation), 1011 (Blue Snails and Orange Mushrooms), the quiz plan and 1016's setup; the chain list equals `playtest_quests.sh`'s; `PlaytestQuestSummary` over synthetic reports |
| `test_playtest_smoke.gd` | `smoke` headless through `PlaytestProcess`, as `playtest.sh` runs it: PASS, finished, no fatal or script error, at least 15 checks, one process, the screens driven without an `api` fallback, at most one console step, the key checks present, `report.md` and the private `saves/` written; `reload`: PASS across two processes (`reload` then `done`); `counter`: PASS, with `talk_to(16)` a successful play step (the regression test for the talk rule); `quest --quest 1002`: PASS in strict mode with every quest check tagged; `kit`: PASS without an api fallback |

## Lineage

| Earlier driver | What the harness keeps |
|---|---|
| `shell_checks.gd` / `ShellCheckRunner` | main.tscn as a child with a private `Saves.save_dir`; `_until`/frames helpers; the window close through `propagate_notification`; the child process and output parsing |
| `world_ui_main_checks.gd` | real key presses through `Input.parse_input_event`; prompts, dialogue, shop and loot assertions |
| `review_combat/review_driver.gd` | mouse events through the viewport's final transform with `flush_buffered_events`; injecting outside physics frames; PlayerCombat counters |
| `review-world/driver/drive.gd` | console setup through `Debug.run`; the trail walk with RouteBot and the event sequence |
| `TraversalWalker` / `TraversalNav` / `TraversalPaths` / `TraversalTour` | path planning on routes, clearance replanning, RouteBot steering, `portal_between`. The harness drives the real `KeyboardInput` through input events instead of a `BotInput` swap |
