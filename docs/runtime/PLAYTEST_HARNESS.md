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
| `game/tools/playtest/playtest_driver.gd` | `PlaytestDriver` | the API scenarios call: boots main.tscn, plays, logs steps and checks |
| `game/tools/playtest/playtest_input.gd` | `PlaytestInput` | real input: keys, actions (analog movement), mouse, typing; held state and focus re-assert |
| `game/tools/playtest/playtest_walker.gd` | `PlaytestWalker` | path planning and following with real input (RouteBot steering) |
| `game/tools/playtest/playtest_grid_nav.gd` | `PlaytestGridNav` | A* on the real collision, for targets the route network does not reach |
| `game/tools/playtest/playtest_report.gd` | `PlaytestReport` | steps, checks, screenshots, errors, phases; `report.json` / `report.md` |
| `game/tools/playtest/playtest_scenario.gd` | `PlaytestScenario` | base class of a scenario |
| `game/tools/playtest/playtest_runner.gd` + `.tscn` | | one process (phase) of a run: arguments, seeds, error guards, watchdog, report |
| `game/tools/playtest/playtest_engine_log.gd` | `PlaytestEngineLog` | records push_error and engine errors (reported, not fatal) |
| `game/tools/playtest/playtest_process.gd` | `PlaytestProcess` | runs a scenario's phases in child processes and reads the report (unit tests, tools) |
| `game/tools/playtest/scenarios/*.gd` | | the scenarios: `smoke`, `fight`, `reload`, `api`, `npcs`, `counter` |
| `scripts/playtest.sh` | | the command line: mirror, import, phases, exit code |
| `game/tests/unit/test_playtest_report.gd`, `test_playtest_smoke.gd` | | the tests (see "Tests") |

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
	if d.phase == 0:
		var ng: Dictionary = await d.new_game("Tester", "female", "541", {"str": 9})
		if not d.check("new game", ng.ok, ng.why):
			return
		await d.console("warp 000000040")                  # setup: logged as a console step
		var f: Dictionary = await d.fight_until(func() -> bool: return d.state().exp >= 10, 120.0)
		d.check("fought to 10 EXP", f.ok, "%d kills" % f.kills)
		await d.pickup_all_nearby()
		d.carry["inventory"] = d.character().inventory.to_dict()    # survives the reload, with its Godot types
		await d.reload_process()                             # Quit Game: the process ends here
		return
	# phase 1: a new process on the same saves
	await d.continue_game()
	var diff := PlaytestDriver.diff(d.carry["inventory"], d.character().inventory.to_dict())
	d.check("the inventory survives a real reload", diff == "", diff)
```

Rules:

- **`run()` is a coroutine.** Await every driver call documented "Await it". A call that is not awaited runs in the
  background and the scenario races it.
- **Play first, console for setup only.** `console()` steps are counted apart from play steps in the report, so a
  reader can tell legitimate play from setup. A shell call the UI could not make is an `api` step and carries the
  reason.
- **`check()` fails the run; `soft_check()` only warns.** Use `soft_check` for a known issue the scenario must surface
  without blocking the rest of the flow. An example is an NPC a player cannot reach; see "Findings".
- **Do not hard-code canonical numbers.** Read them from `d.db()` (`ContentDB`), `ShopService`, `MonsterDef`,
  `StatCalculator` and the like. The sample `fight` compares the EXP it gains against `MonsterDef.exp_reward`.
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
| `console(cmd)` | `Debug.run(cmd)`, the console's own path, and waits for a warp it started. A `console` step |
| `screenshot(name)` | `<out>/shots/NN_p<phase>_<name>.png` when windowed; headless it is logged as skipped |
| `state()` | flow, map and name, MapSession state and last transition, position (world, local and region), floor, climbing, dead, input, facing, level, EXP, HP/MP and their maxima, AP/SP, mesos, base stats, the inventory summary, equipment, quests (in progress and completed), modal, open windows, dialogue and shop |
| `check(name, cond, details)` / `soft_check(...)` / `note(text)` | PASS/FAIL lines, WARN lines, free notes |
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

`report.json`, format 1:

| Key | Content |
|---|---|
| `scenario`, `result`, `seed`, `windowed`, `args`, `finished`, `reload_requested` | `result` is `PASS` (finished, at least one check, no failed check, no fatal error), `FAIL`, or `RELOADING` between phases |
| `totals` | `{game_s, wall_s}` over all phases |
| `phases` | `[{phase, started_at, game_s, wall_s, end}]`; `end` is `done`, `reload`, `timeout` or `error` |
| `counts` | `steps` `{play, console, api, observe}` (top level), `checks`, `checks_failed`, `warnings`, `errors`, `engine_errors`, `screenshots`, `input_reasserts` |
| `checks` | `[{i, phase, name, ok, details, at_game_s, step, soft}]` |
| `steps` | `[{i, phase, depth, kind, name, detail, ok, result, at_game_s, game_s, wall_s, fallback?}]` |
| `screenshots` | `[{name, phase, path \| skipped + reason}]` |
| `errors` | fatal: `[{phase, kind (script, scenario, timeout, harness), message}]` |
| `engine_errors` | not fatal: push_error, engine errors and warnings while the scenario ran |
| `notes`, `carry` (readable), `carry_var` | `carry_var` holds the typed copy |

`report.md` holds the same report as a header and tables: Errors, Checks (PASS, **FAIL**, WARN), Steps (nested steps
indented with `·`), Screenshots, Engine errors, Notes and Phases. Console lines while a run plays: `PLAYTEST STEP`,
`PLAYTEST CHECK PASS|FAIL|WARN`, `PLAYTEST FALLBACK`, `PLAYTEST NOTE`, and at the end `PLAYTEST_RESULT`,
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
  walker re-plans once. A scenario that only needs to walk past can `console("god on")`, which is logged as setup.

## Sample scenarios

| Scenario | Proves | Headless (2026-10-04, fixed fps) |
|---|---|---|
| `smoke` | new game through the title and creation screens, route Main of 000000001, the trail to 000000010 across the gate, Roger (WARN when unreachable, then a logged `goto npc 3`), F, Esc, save, quit to title, Continue: the same map, place and character | 16 checks, 1 WARN, about 55 s game, 12 s wall |
| `fight` | in 000000040, after a console warp: the attack key against Snails until a kill drops loot (bounded), canonical EXP for every kill, the drop picked up with Z | 9 checks. Seed 1 gives 2 kills, 6 attacks, 4 hits, a 2-meso drop |
| `reload` | phase 0: new game, a walk, Quit Game; phase 1 (a new process): Continue, the same map, place and character (`carry`, `diff`) | 16 checks, 2 processes, about 7 s wall |
| `api` | every remaining call: `press`/`tap`, windows by key and `window_text`, the grid planner, Lucy's shop (the window's price checked against `ShopService.row_for`, the canonical data; buy 2 at 50, sell 1 back at 5), a door with Up, End Chat on Rain, Sam's pages with `next()` and his offer declined with `choose("no")`, a mouse `click` on Resume, `state()` | 28 checks, 2 WARN |
| `npcs` | a survey: `talk_to` every NPC of the 25 maps on foot from its map's arrival; the unreachable ones are WARN, with how close the body came to the talk zone | 21 NPCs, 16 reached, 5 WARN, about 25 s wall |
| `counter` | talk to Pan (16) across his counter in 000000061 on foot, after a console warp: the walk ends at the counter, the lean brings the body into the talk zone at 1.94 m feet to feet, and `talk_gap` agrees with the game's prompt | 7 checks |

## Findings (2026-10-04)

The `npcs` survey found that **5 of 21 NPCs cannot be talked to by a walking player**.

The talk rule is `WorldNpc.in_range`: the NPC's talk Area3D overlaps the player's body. The Area3D is a sphere of
`interaction_radius_m` (1.6 m, `presentation.json`) centred 0.8 m above the NPC's feet; the body is a capsule of radius
0.3 m from 0.45 to 1.5 m above the player's feet. The fallback is feet within 1.6 m of the NPC's feet. On level
ground, a player whose feet are about 1.9 m from the NPC can therefore still talk. `talk_gap` measures the rule, and
the gap below is the closest the body came to the zone on foot (walks from the map's arrival over the routes and the
grid, then the lean):

| NPC | Map | Gap | Where they stand |
|---|---|---|---|
| Heena (1) | 000000001 | 0.52 m | on a perch 1.6 m above the ground around it (more than the 1.35 m jump reach). The perch top is wide enough that the ground below never comes within reach of the zone |
| Roger (3) | 000000010 | no path | on a terrace 3 to 4 m above every ground around it, with no stairs or climbable (Roger's Apple, Test E) |
| Nina (4) | 000000020 | no path | there is standing room in talk range, but no route or grid path connects it to the map's ground |
| Sid (20) | 000001011 | 0.18 m | behind his counter, 0.45 m above the shop floor: a player pressed against it is 2.08 m from him horizontally; a shopkeeper (Test G) |
| Lucy (21) | 000001013 | 0.01 m | in a pocket behind her counter, 0.8 m above the shop floor: a player pressed against the counter is 1.87 m from her horizontally, 1 cm out of the zone; a shopkeeper (Test G) |

Pan (16, 000000061), the third shopkeeper, **can** be talked to: a player pressed against his counter is 1.89 m from
him horizontally (1.94 m feet to feet) and 0.008 m inside the zone (the `counter` scenario and its test). That margin
is under a centimetre, so the world-side fix below should cover him too.

The earlier main-scene checks placed the player in front of the NPC with `place_player`, so they never walked there.
The fix belongs to the world runtime (NPC placement, or a larger talk zone for NPCs behind counters). Until then,
scenarios that need these NPCs use `soft_check` plus a `console("goto npc <id>")`, as `smoke` and `api` do.

An earlier version of `talk_to` (2026-10-04) treated the rule as feet to feet in 3D, within 1.45 m, and sampled
approach points only out to 1.3 m. Under that model it also reported Pan as unreachable.

## Tests

```bash
ISOLATE=harness INCLUDE_WORLD=1 bash scripts/test.sh test_playtest_     # 9 tests; the three runs SKIP without the world
```

| File | Covers |
|---|---|
| `test_playtest_report.gd` | the PASS rules: an unfinished report or one without checks never passes, a soft check only warns, a fatal error fails; top-level step counts by kind and step durations; the JSON round trip keeps `carry`'s ints and vectors and the reload request; `report.md` (WARN rows, escaped pipes); `screen_move_for` maps back onto every direction for three camera bases and keeps a slow step's strength; actions press their first `Controls.BINDINGS` key; `diff` |
| `test_playtest_smoke.gd` | `smoke` headless through `PlaytestProcess`, as `playtest.sh` runs it: PASS, finished, no fatal or script error, at least 15 checks, one process, the screens driven without an `api` fallback, at most one console step (the documented `goto npc`), the key checks present, `report.md` and the private `saves/` written; `reload`: PASS across two processes (`reload` then `done`); `counter`: PASS, with `talk_to(16)` a successful play step (the regression test for the talk rule) |

## Lineage

| Earlier driver | What the harness keeps |
|---|---|
| `shell_checks.gd` / `ShellCheckRunner` | main.tscn as a child with a private `Saves.save_dir`; `_until`/frames helpers; the window close through `propagate_notification`; the child process and output parsing |
| `world_ui_main_checks.gd` | real key presses through `Input.parse_input_event`; prompts, dialogue, shop and loot assertions |
| `review_combat/review_driver.gd` | mouse events through the viewport's final transform with `flush_buffered_events`; injecting outside physics frames; PlayerCombat counters |
| `review-world/driver/drive.gd` | console setup through `Debug.run`; the trail walk with RouteBot and the event sequence |
| `TraversalWalker` / `TraversalNav` / `TraversalPaths` / `TraversalTour` | path planning on routes, clearance replanning, RouteBot steering, `portal_between`. The harness drives the real `KeyboardInput` through input events instead of a `BotInput` swap |
