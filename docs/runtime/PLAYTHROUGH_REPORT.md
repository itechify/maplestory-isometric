# Playthrough validation report (Iteration Two)

This report records how MisoStory's playable build was validated against the brief's Phase 23 tests (A–G) and its
Movement, Camera, Combat and World reviews, what was found, and what was fixed. Date: 2026-10-04.

## How the playthroughs were done

- **Real game, real input.** Every test runs `res://scenes/main.tscn` (title → creation → island) through the playtest
  harness ([PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md)). Moves, jumps, attacks, talking, menu clicks, double-clicks and
  drags are real `InputEvent`s, so the player controller, combat, UI and shell react exactly as to a keyboard.
- **Console use is setup only.** Each report counts `play`, `console` and `api` steps separately. Console steps were
  limited to setup: warps to a start point, money for shop tests, and a few HP lowerings for the death tests. The
  console has no HP setter, so those are logged `api` steps. Everything a test verifies happens through play.
- **Repeatable runs.** Every scenario ran headless at a fixed 60 fps on several seeds, and at least once windowed with
  screenshots. Run it yourself with `bash scripts/playtest.sh <scenario> [--windowed] [--seed n]`. Reports are written
  to `<out>/report.md` and `report.json`.
- **Expected values come from data.** Scenarios read canonical data (MeowDB) and compute expectations independently,
  for example damage ranges from `formulas/damage.json` and EXP from `exp_table.json`. They never hard-code results.
- **Final replay on the final build.** The playtest round ran before fix round F1, which changed world geometry
  (A Split Road, 000001005), attack timing, monster stagger and push, and added natural recovery. Every test A–G was
  then re-run on the final build (commit `2933fe7` plus docs, seed 1, headless). Those results are in
  [Final replay](#final-replay-final-build) below.
- **No human has played this build yet.** These are scripted playthroughs by agents, with screenshot review. A human
  pass (MAP_ARCHITECTURE L4) is the recommended next step: walk Test A by hand, fight, quest and shop, and judge feel.

## Results by brief test

| Test | Scenario | Result | Key evidence |
|---|---|---|---|
| A: entire island traversal | `test_a_traversal` | **PASS** (478 checks, 0 failed) | New game at 000000001. **25/25 maps** visited on foot and **47/47 canonical portals** used, each confirmed by its transition record (46 trail legs walked across gates, 8 door legs entered with Up). Doors ground in 1 frame. Headless runs were identical leg for leg. All 20 trails are walkable (`docs/runtime/traversal_report.json`: 366 route runs and 87 link runs with 0 failures; both Test A tours have 0 stalls and 0 fall recoveries). |
| B: combat | `test_b_combat` | **PASS** (3 seeds × 52 checks) | All 6 Maple Island species fought with real attacks. **652/652** targets matched the canonical hit-box oracle; 18/18 attacks behind the player and 18/18 beyond reach whiffed. Every hit value lay within `CombatFormula`'s range for the character's stats, with a centre-heavy distribution. EXP per kill is canonical, drops come from the canonical tables, and slots respawn on the 7.56 s tick. |
| C: progression | `test_c_progression` | **PASS on every rules check** | A clean Beginner levelled to 7+ **only by killing**. EXP per kill and the level thresholds match `exp_table.json`. Each level gives +5 AP and the canonical HP/MP. AP was spent through the real stats window, and every derived number (ACC, AVOID, damage range) matched the canonical formulas and MeowDB's character builder at levels 1, 5 and 8. The stats-window grid layout failure at 0 AP is fixed in F1. |
| D: inventory | `test_d_inventory` | **PASS** (4 seeds) | Mesos, a consumable (Sam's Eggs) and equipment (bought from Pan) were obtained by play and picked up with Z. The consumable was used by double-click and by quickslot, and the item equipped through both windows, with stats matching the canonical item. Save → title → Continue and a full process restart kept inventory, equipment, mesos, quickslots and stats exactly. Stacking, a full tab and unequipping into a full inventory were covered. The A Split Road trap it found is fixed in F1. |
| E: quest | `test_e_quest` | **PASS** (9 runs, 0 console steps) | Roger's Apple (1002) and Sam's Suggestion (1006) from clean saves, played fully: walk, talk, accept, kill or use, return, turn in. 1006 was also played with an interruption at 5/10: save, quit, reload, then a process restart, with the progress kept. **Reward exactly 30 EXP + 3 Eggs (item 237).** The chain 1007 → 1008 also passes. |
| F: death | `test_f_death` | **PASS** (200 checks) | 7 deaths in 4 maps plus a trail, each by real monster contact: input off, the notice, HUD HP 0. The **canonical EXP penalty** was applied **exactly once** across quit-while-dead and reload, with respawn at the canonical returnMap (Southperry or Amherst) and HP/MP per `death.json`. Inventory, equipment, mesos and quests were unchanged. Space no longer confirms the notice (fixed in F1). |
| G: shop | `test_g_shop` | **PASS** (184 checks) | All three shops (Pan, Sid, Lucy) reached on foot through their doors and talked to across the counter. 18 purchases and 15 sales at **canonical prices and sell-backs**. Insufficient funds and inventory-full refusals change nothing and say why. The quantity picker is capped by room, mesos and slot quantity. |
| NPC reach | `npcs` | **PASS** (hard checks) | **21/21 NPCs** talked to on foot, each with a player at least 0.6 m inside the talk zone. |
| Natural recovery | `regen` | **PASS** | No recovery while walking. +10 HP after 10 s standing still, one tick per 10 s, capped at max HP (an adaptation; MeowDB gives no numbers). |

## Final replay (final build)

Seed 1, headless, fixed 60 fps. Run with `ISOLATE=<name> bash scripts/playtest.sh <scenario> --seed 1`.

| Test | Result | Checks | Notes |
|---|---|---|---|
| A: traversal | **PASS** | 469 passed, 0 failed, 8 warnings | Re-run after the last world fix. 25/25 maps and 47/47 portals on foot. The warnings are the walker's known limits: it never fights, so it died on some hunting-map approaches and retried, plus prop replans. |
| B: combat | **PASS** | 50 passed, 0 failed, 2 warnings | The held attack now repeats at the canonical cadence (gaps of 43 ticks with a 44-tick gap every fifth swing, average 720 ms). Mid-hop hits now stagger; in 2 of 131 cases the push after landing was blocked by a ledge, which pushes respect by design. The bot could not reach some Sentinels on high tiers. |
| C: progression | **PASS** | 68 passed, 0 failed, 2 warnings | A clean Beginner reached level 7 by killing only, across two process restarts, with every EXP award, level-up, AP gain and stats-window number canonical. The first replay failed one check: phase 2 resumed the hunter inside a second walled pocket in 000001000 and it made 0 kills. That pocket was fixed in the source (F1-9) and this run is on the fixed world. The two warnings are deaths: the bot attacks Orange Mushrooms above its level and never retreats or rests. (Their soft check's label still says "there is no natural HP regeneration", which is out of date.) |
| D: inventory | **PASS** | 94 passed, 0 failed, 0 warnings | The A Split Road trap no longer happens (the earlier "never trapped" warning is gone). |
| E: quest | **PASS** | 102 passed, 0 failed, 0 warnings | Sam's Suggestion: exactly +30 EXP and 3 Eggs, across save, quit, reload and restart. |
| F: death | **PASS** | 200 passed, 0 failed, 0 warnings | Still passes with natural recovery in the game (200 of 200 checks). |
| G: shop | **PASS** | 184 passed, 0 failed, 0 warnings | Canonical prices at all three shops. |

The unit suite (1144 tests) also runs `smoke`, `npcs` (21/21 NPCs on foot), `reload`, `regen` and the traversal tools
(366 route runs, 87 link runs, both Test A tours) on every run.

## Review questions (measured)

### Movement review

| Question | Answer |
|---|---|
| Is movement responsive? | Yes. Full speed 0.050 s after the press, a stop in 0.033 s over 0.025 m, a reversal in 0.083 s. |
| Is movement speed pleasant? | 3.000 m/s, exactly MeowDB's 150 px/s at the world scale. Main-road maps cross in 1.04–1.20× the classic time. |
| Does diagonal movement feel correct? | Equal speed in the world; on screen diagonals run at about 33° because of the 40° camera pitch. |
| Does jumping feel useful? | The apex (0.90 m) and airtime (0.55 s) are canonical. Jumps are needed on 6 ledges; other rises use ladders, ropes or stairs. |
| Is air control understandable? | Yes. A running jump can be shortened by about half but not reversed, which is classic-like. |
| Does the player get snagged? | One 0.25 s catch on Southperry's rope-anchor posts. The A Split Road trap is fixed in F1. |
| Are terrain transitions smooth? | Step-ups up to 0.42 m have no airborne ticks, and slopes keep 99.7% of speed. A ladder-top exit jolts the camera 0.8 m in one tick (polish). |

### Camera review

| Question | Answer |
|---|---|
| Can I see the player? | Always in frame; unobstructed 88.9% of the time, otherwise shown through dither, X-ray and outline. |
| Can I see nearby enemies? | 98.6% of the time within 8 m. Monsters behind terrain show as silhouettes. |
| Are trees and buildings obstructing play? | Forests are handled by dither holes. Interiors cover the player about 37% of the time but stay readable. |
| Are cliffs hiding monsters? | Not confirmed by screenshot crops (the ray measure over-reports because collision rises above the visuals). |
| Does the camera expose unfinished geometry? | No holes or void found at map corners or on trails. Interiors float on a sky-blue background (by design). |
| Does the isometric angle make jumping understandable? | Partly: a 0.9 m rise reads as 32–46 px. On SHG III some jumps happen behind pillars and are seen only as the X-ray. |

### Combat review

| Question | Answer |
|---|---|
| Are attacks responsive? | Yes. A press resolves on the next physics tick (16.7 ms, 179/179 taps), and the swing, flash and number appear that tick. Held attack repeats every 733 ms against the canonical 720 ms (polish, open). |
| Do hitboxes match visuals? | Logic matches canonical boxes exactly. The proxy models are 1.1–1.5× wider than the canonical touch boxes, so a visible edge can be whiffed (open: proxy art). |
| Are monsters readable? | Snails read well by shell colour. Shroom caps resemble decorative mushrooms, and the Orange Mushroom reads as a dome (proxy art, deferred). |
| Is knockback clear? | Consistent but small. The player is pushed 0.62 m over 0.28 s, and the monster 20 px, both canonical or labelled adaptations. |
| Are misses understandable? | Misses never occur on Maple Island: every monster has AVOID 0, matching MeowDB's accuracy simulator (hit rate 100%). |
| Does contact damage feel predictable? | Yes. Every touch fell inside MeowDB's avoidability-sim range (Snail 3–4 … Orange Mushroom 18–24). |
| Are damage numbers readable? | Yes: large orange numbers, distinct criticals, violet for damage taken. |

### World review

| Question | Answer |
|---|---|
| Are spaces too large once walked? | Not horizontally (see above). Time is added by the trails, 32% of a full tour, with the longest 21.8 s each way, and by climbing mazes such as 000001000 to in04 (51 s for 78 m straight). |
| Are areas too empty? | Monster counts are canonical (slot counts equal MeowDB in all 15 monster maps), at about 1–2 monsters per 100 m². Towns have their canonical 1–4 NPCs. Flat untextured slopes dominate a few arrival frames (art, deferred). |
| Are routes obvious? | Between maps yes: swirls, the arrival banner, and the "-> destination" line on every trail. Inside maps, no exit is in view at first arrival and there is no minimap (deferred). |
| Are portals visible? | Yes, except the canonical hidden portal (000001020 in00, type 1), which is intentionally invisible. |
| Are combat areas large enough? | Hunting grounds 40–42 work well for levels 1–5. Raised tiers in 000000050 and 000001000 hold targets that are hard to reach. |
| Are town paths comfortable? | Yes. |

## What the playtests changed (fix round F1)

| Finding | Fix |
|---|---|
| BLOCKER: a walled ground pocket beside A Split Road's ramp trapped the player, and Continue resumed inside it | Blender source: `T4_UpperRoad_Low` now fills the pocket. `test_d_stuck` asserts the cap is at 2.2 m. |
| 000001005 out00: the arrival was inside the door block, and Up beside the portal grabbed a ladder | Blender source: the door block was set back and the ladder moved 1.55 m outside the trigger. `test_a_probe_1005` passes. |
| A second walled pocket in The Field West of Amherst (found by the Test C replay) | Blender source: the `P17_P25_Fill` terrace. `trap_probe` keeps both former traps escapable (`test_playtest_traps.gd`). |
| No natural HP regeneration (death spiral at low levels) | `NaturalRecovery`, a labelled adaptation. The `regen` scenario passes. |
| 5 NPCs unreachable on foot | Stairs in the Blender source plus an across-counter talk zone. `npcs` is 21/21. |
| Space (the jump key) confirmed the death notice | The notice ignores jump keys and key repeat. |
| The stats window grid reflowed at 0 AP; Quest Log "nearby" never matched; identical gain lines were dropped; the shop did not show gender requirements | Fixed in the UI with tests. |
| Held attacks repeated every 733 ms (canonical 720 ms); mid-hop hits never staggered; the monster push stopped one tick short; an attack pressed while dead fired after the respawn | Fixed, each with a regression test. Confirmed in the final Test B replay. |
| Nothing stopped a ladder from being grabbable inside a portal's press-Up trigger (the 000001005 class) | `sidecar_diff` now fails the export on it, with a mutation test; the shipped export passes. |

## Still open

- **Polish and feel:**
  - the proxy models are wider than their touch boxes
  - the 0.25 s snag in Southperry
  - the camera jolt at ladder tops
  - the canopy dither at the moment of contact
- **Prevention:** a flood-fill trap survey of every map, and an arrival-path sweep in the export gate. The playtests
  found two pockets, both fixed in the source and guarded by `trap_probe`, but there may be more. The climbable/trigger
  gate is built.
- **Deferred to later iterations** ([DEFERRED.md](../DEFERRED.md)):
  - minimap
  - sitting and chairs
  - shorter trails
  - final monster art and readability
  - environment texturing
  - a human (L4) playthrough
