# How to (Iterations Two and Three)

Every command runs from the repo root in **Git Bash** on Windows. Blender 5.2 must be installed (set `BLENDER=...` if
it is not at `C:\Program Files\Blender Foundation\Blender 5.2\`). Godot 4.7.2 is downloaded on first use to
`%LOCALAPPDATA%\MisoStory\godot\4.7.2\` (override with `GODOT=...`; `bash scripts/godot.sh --version` fetches it).
Node is needed for the source tools: the MeowDB extractors, the capture loader and drop record builder (`tools/sources/`), the
parity manifest (`tools/parity/`) and their tests.

On **Linux** the same commands run in bash: the scripts use `blender` from `PATH` (or `BLENDER=...`), and `godot` from
`PATH` when it is 4.7.2, else download Godot to `~/.local/share/MisoStory/godot/4.7.2/`. Use `B=blender` and
`PY=python3` in the snippets below.

## Build the Blender environment

```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"   # Linux: B=blender
"$B" -b --factory-startup --python scripts/build_island.py        # -> MapleIsland.blend (~1 min)
"$B" -b MapleIsland.blend --python scripts/validate.py            # -> docs/VALIDATION.md (expect 0 high, 0 medium)
"$B" -b --factory-startup --python scripts/build_map.py -- 50000  # one map alone (GMS v8 id), with MAP_TRAVERSAL_OK
```

The generator is `src/misostory/` (maps in `maps/m<id>_*.py`). Authoring rules: [`../AUTHORING.md`](../AUTHORING.md).
The integrated Iteration Three island validates with 0 high, 0 medium and 21 low findings. `validate.py` now also runs
`ring_band`, the Blender-side guard against the map-corner trap slots (see "Run the stuck-region scan").

## Export the environment and import it into the game

```bash
bash scripts/build_runtime.sh            # rebuilds the .blend if the source is newer, exports, imports, validates (~6 min)
bash scripts/build_runtime.sh --rebuild  # always rebuild the .blend first
```

The export goes to `game/assets/world/` (git-ignored): one `.glb`, one `.collision.glb` and one sidecar `.json` per
chunk ([`blender_export.md`](blender_export.md)). When you change the Blender source, export to a staging folder first
and gate it before replacing the game's copy, as the Blender rounds do:

```bash
"$B" -b MapleIsland.blend --python scripts/export_runtime.py -- --out _scratch/export_staging
PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"   # Linux: PY=python3
"$PY" src/misostory/sidecar_diff.py --old game/assets/world --new _scratch/export_staging   # SIDECAR_DIFF_OK True
MISOSTORY_EXPORT_DIR=_scratch/export_staging "$PY" src/misostory/test_sidecar_contract.py  # all OK
```

Then replace `game/assets/world/` with the staging folder. Never keep a backup of it under `game/assets/`: everything
there is git-ignored except `.gitignore`. After any change to a map module or `world.py`, also run the stuck-region
scan and its tests (below) before merging: a new trap fails the suite.

## Launch the game

```bash
bash scripts/play.sh              # windowed 1600x900
bash scripts/play.sh --fullscreen
bash scripts/play.sh --editor     # open the project in the Godot editor
```

## Play Maple Island to the end

| Keys | Action |
|---|---|
| W A S D | move (8 directions, relative to the camera) |
| Space / Alt | jump |
| J / Ctrl / left click | attack (also hits Wooden Boxes: 4 landed hits break one) |
| F | talk to the NPC in front of you |
| Up arrow | enter a portal, grab a ladder or rope (W/S or Up/Down to climb) |
| Z | pick up drops |
| X | sit on your first chair, or stand up |
| I / E / C / Q (or L) / K | inventory, equipment, character stats (spend AP), quest log, skills (spend SP) |
| 1 - 8 | quickslots: potions, food, a chair or a learned skill |
| M | fold the minimap to its title strip (the map name stays) |
| Esc | close the newest window, else the pause menu (save, load, controls, quit) |
| ` (backtick) / F3 | developer console / debug overlay (F3 also shows the canonical map id on the minimap) |

- **Quests.** The Quest Log (Q) lists Available, In Progress and Completed quests, a chain's steps ("Mai's Training
  2/3"), the start and turn-in NPCs with their maps, the canonical Missable tag and the random reward you received.
  A turn-in row reads "Return to X" once you have dealt with X through a quest, else "Talk to X". A shop refuses to
  buy a quest item an in-progress quest still needs, and Roger hands you another apple if yours is gone (quest 1002).
- **Skills.** Each level-up from 2 to 10 gives 1 SP, 9 in all (canonical; enough to max the three skills). A new
  character starts with 0 SP and a Beginner past level 10 gets none: adaptations, by the owner's ruling (#4), where
  MeowDB does not say. K opens the Skills window: "+" spends SP on
  Three Snails, Recovery or Nimble Feet. Drag a learned skill onto the HUD bar, or select it and press Set key and a
  key 1-8; that key casts it. Three Snails costs MP and one shell a cast (a Snail, Blue Snail or Red Snail Shell, by
  skill level).
- **Sitting and chairs.** Pio's quest (1012) gives The Green Relaxer. Double-click it in the inventory's Set-up tab
  (or select it and press Sit), bind it to a quickslot, or press X, which sits on the first chair you own (or says you
  have none). Any move, jump, attack or skill, a knockback, death or a warp stands you up. While you sit, the HUD
  shows what sitting recovers above the HP gauge.
- **Natural recovery.** 10 HP for every 10 s you stand still or sit, the project owner's rule. Walking, jumping,
  climbing and attacking (a Three Snails cast included) pause the clock; nothing resets it, and the clock is saved.
  Seated on The Green Relaxer you also get its canonical 30 HP every 10 s on a clock of its own. MP does not recover
  naturally, by the owner's ruling (#4): MeowDB documents none, and a future Magician skill will grant it.
- **Wooden Boxes.** 19 boxes stand on six maps around Amherst (000001000, 000001010-000001014). Each breaks after 4
  landed hits, basic attacks or Three Snails throws (one target per cast: the nearest monster or box in its band;
  whether skills may hit boxes is still an owner decision), and comes back after its canonical respawn time. Old
  Wooden Board and Rusty Screw drop only while Pio's quest is in progress; a gold marker shows over the boxes while
  the quest still wants them, and a warm rim while your swing can reach one.
- **The minimap** (top left) shows the map's ground by terrace height, the exits with their destination names (hover
  an exit when its name does not fit; that happens only on 000001000, whose eight names do not all fit: three go to
  the hover text in the suite's layout), NPCs with their quest markers and shop or boat icons, and your arrow. The
  hidden portal to Tomato Field is not shown.
- **Finishing Maple Island.** Talk to Shanks in Southperry (000000060) at level 7 or higher with 300 mesos (the
  canonical route to Lith Harbor). He lists any unfinished Maple Island quests, then asks whether to sail. Yes shows the
  "End of Maple Island" screen: Victoria Island is not in this build, so nobody travels, no mesos are taken, and you
  stay in Southperry. The boundary is recorded as `flags.maple_island_departure_ready_at`.

## Create a clean save

On the title screen choose **New Game**, then pick a name, gender, starter weapon (the canonical creation weapons 541,
576 and 585) and the 9 creation AP. A new game always goes into the first free slot, so it never overwrites a save.
Saves live in Godot's user folder for the project (`%APPDATA%\Godot\app_userdata\MisoStory\saves\`). To wipe a slot
from inside the game, open the console and run `reset_save [slot]` (alias `reset`), or `delete_save <slot>`.

Saves are `save_version` 2. An Iteration Two save (version 1) loads through the v1 to v2 migration. The first time this
build writes over an older save it keeps the old file once, byte for byte, as `<slot>.json.pre-v<N>` (`delete_save` and
`reset_save` remove it too). To check Iteration Two save compatibility in the real game:
`ISOLATE=<name> bash scripts/playtest.sh save_it2_continue` ([SAVES.md](SAVES.md)).

## Run automated tests

```bash
bash scripts/test.sh                                # every headless test file
bash scripts/test.sh combat parity                  # only files whose name contains a filter
ISOLATE=me INCLUDE_WORLD=1 bash scripts/test.sh     # in a private copy (parallel-safe), with the exported world
ISOLATE=me INCLUDE_WORLD=1 TEST_TIMEOUT_S=3000 TEST_EVIDENCE_OUT="$PWD/_scratch/ev/full.json" bash scripts/test.sh
```

- The full suite with the world is 1564 tests in 174 files (the final evidence run, 2026-10-06) and took 12 minutes
  beside two playtests; the stuck-region scan (`test_stuck_scan.gd`, about 80-110 s) and the former-trap probe
  (`test_playtest_traps.gd`, about 2 minutes) are the slowest files. World tests SKIP without `INCLUDE_WORLD=1` (or a
  `game/assets/world/` in the project you run).
- `TEST_TIMEOUT_S` (default 900) is the outer time limit of the Godot process. Raise it on a busy machine.
- `TEST_EVIDENCE_OUT=<file>` also writes the machine-readable test evidence (contract C6), format 2: `{format, run_at,
  commit, dirty, world_present, filters, totals, tests: [{file, name, ok, failures, parity, needs_world}]}`. A test
  file declares parity keys with an optional `func parity_keys() -> Dictionary`; a key that names a missing test, or
  is malformed, fails as `<file>::parity_keys`. `commit` is `git rev-parse HEAD`; `dirty` is true when `game/`,
  `tools/` or `scripts/` differ from it (untracked files included); `world_present` says whether the exported world
  was there, and `needs_world` marks a test whose file names `INCLUDE_WORLD` (the parity build refuses such a test's
  keys from evidence that ran without the world).
- **The Jolt body cap.** Godot 4.7.2's Jolt integration evidently does not reuse the body slots of freed collision
  objects within one process (inferred from the fix below; the engine side was not root-caused), so a test process
  that builds and frees the island more than about ten times aborted with exit code 3 and printed nothing (the suite
  seemed to stop after `test_traversal_routes`). `game/project.godot` sets
  `physics/jolt_physics_3d/limits/max_bodies=65536` (the default is 10240); with it 16 builds pass, and the full suite
  runs to its totals. The game itself builds the island once. If the suite ever stops without `TESTS_PASSED` or
  `TESTS_FAILED`, suspect this limit first.

Node tests for the source and parity tools (no Godot, a few seconds):

```bash
node --test tools/sources/test/     # capture loader, exact raw-value parsers, the drop record builder (31 tests)
node --test tools/parity/test/      # the parity state rule and the evidence provenance checks (18 tests)
```

## Run real-game playtests

The harness plays the real main scene with real input ([PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md)). Each run writes
`report.json` and `report.md`; the exit code is 0 only when the report passes.

```bash
bash scripts/playtest.sh --list                                   # the scenarios
bash scripts/playtest.sh test_e_quest                             # headless; report path printed
ISOLATE=<name> bash scripts/playtest.sh test_box --out "$PWD/_scratch/pt/box" --seed 2
bash scripts/playtest.sh test_a_traversal --windowed --out "$PWD/_scratch/tour"   # with screenshots
bash scripts/playtest.sh quest --quest 1012                       # one quest or chain of the every-quest set
bash scripts/playtest_quests.sh                                   # every Maple Island quest (7-10 min)
```

- **Headless and windowed.** A headless run lays the game out on the windowed 1600x900 screen (the GUI area and the
  camera's 16:9 view), and every click, double-click and drag first checks that a player could make it: a control off
  the screen, or covered by another, fails the run's check with the reason in both modes
  ([PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md) "Headless and windowed"). Only windowed runs load the visual chunks and
  take screenshots, so a check about what is drawn needs `--windowed` and a look at its `shots/`.
- `report.json` records the code it played in a `git` block (`commit`, `dirty`, `mixed` when a later phase ran
  another commit, `reused_copy` for a `PLAYTEST_REUSE_COPY=1` run), and `report.md` says it on its "Code" line.

- Use your own `ISOLATE` name when several agents run at once (default `playtest`); each name is a private mirrored
  copy of `game/` under `_scratch/godot_runs/`.
- Iteration Three scenarios: `quest` (the every-quest set), `test_box` (Pio's quest with Amherst's Wooden Boxes,
  a box broken by Three Snails, then every box of the other five maps: 17 of the 19 broken),
  `test_skills` (SP, the Skills window, all three Beginner skills), `regen` (the natural-recovery pause rule and
  seated recovery), `ui_minimap` (the minimap on all 25 maps and level-up feedback), `test_b_population` (all 15
  hunting maps' spawns), `save_it2_continue` (an Iteration Two save migrated in the real game), `npc_shanks` (the
  departure boundary and the fare refusal), `npc_bubbles` (the NPC speech bubbles), `pause_load` (a Load through the
  pause menu), `resume_gate` (a save just past a trail gate resumes where it was), `kit` (PlaytestKit's reference
  run), `playthrough` (the clean-character playthrough, creation to Shanks), `trap_probe` and `walk_probe` (single
  spots). Tests A-G are as in Iteration Two.
- **The every-quest set.** `scripts/playtest_quests.sh [--jobs N] [--seed N] [--out DIR] [--isolate PREFIX]
  [chains...]` runs the `quest` scenario once per chain (`--list` prints the 9 chains), `--jobs` at a time (default 3)
  in private copies named `<prefix>_<i>` (default prefix `quests`), then writes `<out>/quests.md` and `quests.json`: one
  row per quest (PASS, FAIL or NOT_PLAYED, checks, the random reward drawn) and one per chain. Exit 0 only when every
  quest passes. One chain alone: `bash scripts/playtest.sh quest --quest 1013-1019` (or `1002`, `1006,1009,1010`, or
  `QUEST=<spec>`). On the final Iteration Three build the whole set passes, 20 of 20 quests on each of seeds 1, 2 and 3
  with every chain strict ok, in about 7 minutes with `--jobs 3` (6.4-7.4 minutes with `--jobs 1` beside two other runs).
- **Strict mode.** A scenario that calls `d.begin_strict(reason)` may use no developer help after that step: a
  console command is refused, an api fallback, any developer command or any change to EXP, mesos, items or quests the
  event bus did not announce is a violation. `report.json` carries a `strict` block (`console_steps`, `api_steps`,
  `debug_commands`, `ledger`, `violations`, `ok`), and a report passes only when it is ok. The `quest` scenario is
  strict after its setup save (1000-1001 from character creation).
- **Parity keys.** A playtest check may carry keys (`d.check(name, cond, details, ["quest:1005"])`); `report.json`
  keeps them per check and sums them per key. Quests, objectives, rewards and chains become "verified" in the parity
  manifest only through tagged playtest checks.

## Run the stuck-region scan

The scan finds walkable places a player can get into but not out of, on all 25 maps, and verifies each finding with
the real player controller ([STUCK_SCAN.md](STUCK_SCAN.md)).

```bash
# every map, verified; writes docs/runtime/stuck_report.json (run on game/, not an ISOLATE copy); exit 1 on a new trap
bash scripts/godot.sh --headless --path game res://tools/stuck_scan_tool.tscn
# some maps, graph only, written elsewhere, with top-down pictures
bash scripts/godot.sh --headless --path game res://tools/stuck_scan_tool.tscn -- --map 000000041,000001010 \
    --no-verify --png "$PWD/_scratch/stuck_png" --out "$PWD/_scratch/stuck.json"
# inspect map-local points by hand (column surfaces, the forward path, the nearest escapable ground)
bash scripts/godot.sh --headless --path game res://tools/stuck_scan_tool.tscn -- --map 000001004 --no-verify \
    --inspect "35.44,0,-27.75;30.65,0,-26.4"
# the guards in the suite (with the world)
ISOLATE=stuck INCLUDE_WORLD=1 bash scripts/test.sh stuck_scan playtest_traps
# one spot in the real game, with real input
TRAP_MAP=000001010 TRAP_LOCAL="76.70,-2.50,-37.57" bash scripts/playtest.sh trap_probe
```

The tool exits 1 on a CONFIRMED trap the allowlist's `entries` do not list (`game/data/misostory/stuck_allowlist.json`;
empty: Maple Island has no intended dead end), on an UNENTERABLE component its `unenterable` list (13 components
reviewed by hand) does not list, and on escapable ground outside every map region. The
final Iteration Three scan reports 0 confirmed traps; every former trap (54 spots) is replayed by `trap_probe`.

## Run canonical-data validation

```bash
bash scripts/validate_data.sh              # exit 1 on a data error, 2 if the validator itself is broken
bash scripts/validate_data.sh --verbose    # also list the references skipped as out of scope
bash scripts/validate_data.sh --report     # also write docs/provenance_report.json and docs/PROVENANCE_REPORT.md
bash scripts/validate_data.sh --report-json _scratch/prov.json --report-md _scratch/prov.md   # the report elsewhere
ISOLATE=me bash scripts/validate_data.sh   # in a private copy
```

It runs the game's own loader over `game/data/canonical` and `game/data/misostory`
([DATA_VALIDATION.md](DATA_VALIDATION.md)): references, provenance per authority (MeowDB, Henesys.gg for rarity only,
Project owner) with capture files that must exist, the schema 3 drop records and the drop policy (membership against
the owner's own MeowDB page capture, rarity against the Henesys.gg capture, the owner's chance table and meso rule
complete), adaptations (`verified: true` needs `verified_against`), and the quest, NPC and dialogue validation. On the
final build it passes with 0 errors and 0 warnings (every drop member resolves), so `--strict` (warnings fail too)
passes as well when the Blender export is present. The provenance report is deterministic: regenerating it over
unchanged data gives the same files.

Two more source checks, both offline:

```bash
node tools/sources/check_spawn_captures.mjs   # the 51 canonical spawn rows against the dated MeowDB captures
bash scripts/check_canonical.sh               # every extractor re-run cache-only in a temp copy, diffed byte for byte
```

`check_canonical.sh` needs `tools/meowdb/.cache` (git-ignored: copy it from a checkout that has it). Exit 0 means every
extractor reproduces the committed files, 1 a difference (`--keep` keeps the copy to inspect), 2 a failed extractor or
a missing cache. It runs the extractors in their documented order (items and quests before monsters, which resolve
drop members against them) and passes on the final Iteration Three build: every canonical file is reproduced byte for
byte, Green Apple's record (242) from its two hand-read captures included. To regenerate canonical data, see
[`../canonical/README.md`](../canonical/README.md).

## Build the parity manifest

`docs/MAPLE_ISLAND_PARITY.md` and `docs/maple_island_parity.json` give every in-scope entry (maps, portals, monsters,
populations, drops, items, NPCs, shops, quests and their objectives and rewards, skills, breakables, chairs, mechanics)
a state: missing, partial, implemented or verified. The committed copy is the record of v0.3 at its evidence commit
and is not kept current: it was Iteration Three's exit proof, it is not a gate, and nothing needs it rebuilt (the tests
and the playtest scenarios guard against regressions; a rebuild costs a full evidence run). To make a fresh proof,
generate it from the data, the provenance report and test evidence:

```bash
ISOLATE=ev INCLUDE_WORLD=1 TEST_TIMEOUT_S=3000 TEST_EVIDENCE_OUT="$PWD/_scratch/final3/unit_evidence.json" bash scripts/test.sh
bash scripts/validate_data.sh --report
ISOLATE=ev bash scripts/playtest.sh test_box --out "$PWD/_scratch/final3/pt/test_box"     # each scenario, its own --out
bash scripts/playtest_quests.sh --seed 1 --out "$PWD/_scratch/final3/pt/quests_s1"           # seeds 1, 2 and 3
PLAYTEST_TIMEOUT_S=7500 bash scripts/playtest.sh playthrough --seed 1 --max-wall-s 7000 --out "$PWD/_scratch/final3/pt/playthrough_s1"
bash scripts/playtest.sh test_skills --windowed --out "$PWD/_scratch/final3/pt/win_test_skills"  # windowed runs count too
node tools/parity/build_parity.mjs --tests _scratch/final3/unit_evidence.json --playtest _scratch/final3/pt
node tools/parity/build_parity.mjs --check --tests _scratch/final3/unit_evidence.json --playtest _scratch/final3/pt
```

`--playtest` takes a report.json or a folder searched for them; repeat `--tests` and `--playtest` as needed.
`--out-json` / `--out-md` write elsewhere. `--check` exits 1 when the committed files differ from a fresh build; it
needs the same inputs the committed build used (its "Evidence used" section lists them, with the exact command), which
live in git-ignored `_scratch/`. A key is "verified" only by a passing check tagged with it and no failing one. The
scenarios the rules consume are Tests A-G, `regen`, `test_skills`, `test_box`, `trap_probe`, `npcs`, `npc_shanks`,
`npc_bubbles`, `ui_minimap`, `save_it2_continue`, `pause_load`, `resume_gate` and `kit`, plus the every-quest set and
the clean-character playthrough (`--playtest` with its report or directory). The script also warns on the console (never
in the manifest) when an input records no commit, a dirty tree or a commit whose `game/`, `tools/` or `scripts/` differs
from HEAD, and when the inputs ran on different commits. In the final evidence run (commit `1f3120c`, 2026-10-06) every
one of them passed: seed 1 headless, the every-quest set and the playthrough on seeds 1, 2 and 3, and the playthrough,
`test_skills`, `test_box` and `kit` also windowed. The committed manifest, the v0.3 record built from that run, has
652 entries: 646 verified, 3 partial (all source-data gaps), 0 missing, 3 out of scope, 0 open. Built at a later HEAD,
it warns that `tools/` differs from the evidence commit: after the run only the wording of the drop rows in
`tools/parity` changed, which no Godot test or scenario runs, and the text of `tools/henesys/captures/README.md`,
which nothing loads. Later commits change the data and the code without rebuilding it.

The JSON is format 3 (contract C6). Besides the state, an entry may carry one of two labels: `source_data_gap` (the
sources were read and give no value: excused from the exit criterion) or `pending_source_read` (a source publishes the
value on a page nobody has read yet: not excused, the entry stays partial and open). `tools/parity/rules.json`
`pending_source_reads` declares each read; when the page is read and the data regenerated, remove the declaration
(the generator fails a stale one). None is declared. A drop row's chance is neither label: it is the project owner's
table (`drop_rates.json`, decision D3-11), an adaptation the row names, and a meso row's chance and formula amount the
owner's meso rule (D3-12); the manifest's "Adaptations" section counts the entries resting on each. The clean-character
playthrough rows (`playthrough:*`) count only checks of a clean run: a passing, strict report with no console or api
step whose final boundary check passed and that no `PLAYTHROUGH_STOP` ended early.

## Capture a source page by hand

Newer MeowDB facts and Henesys.gg rarity labels have come into the project as dated captures of pages read by a person
in a normal browser (decisions D3-1 and D3-11 in [`../ITERATION_LOG.md`](../ITERATION_LOG.md)). No tool fetches a
capture.

1. Open the page in a browser and read it. Copy the rendered text, trimmed to the record.
2. Save it under the authority's folder with a name the loader knows (`tools/meowdb/captures/README.md`,
   `tools/henesys/captures/README.md`). A MeowDB `.txt` capture starts with a
   header, then a `---` line, then the page text:

   ```
   URL: https://meowdb.com/msclassic/monsters/2
   READ_AT: 2026-10-05T07:47:01.065Z
   METHOD: manual page view in a normal browser; rendered page text, trimmed to the record
   PURPOSE: (optional) why the page was read
   ---
   <the page text>
   ```

   `READ_AT` must be an ISO 8601 time with a zone. A header value may continue on indented lines. JSON captures carry
   `url`, `read_at` and `method` fields instead. To update a value, read the page again and replace the capture with
   the new reading and its own read time; never edit a captured text by hand.
3. Check it loads: `tools/sources/captures.mjs` reads every file in the two folders (README.md is skipped) and stops
   on an unknown file name, a missing or non-ISO read time, or rows that are not in the captured text. A new kind of page
   needs a reader there first. Of two captures of one page the one with the later read time wins (a tie is an error),
   and the drop records always follow the newest dated capture of each owner's page.

   ```bash
   node -e "import('./tools/sources/captures.mjs').then(m => console.log(m.loadCaptures().files.length, 'capture files'))"
   node --test tools/sources/test/
   ```

4. Regenerate what reads it ([CONTENT_AUTHORING.md](CONTENT_AUTHORING.md) "Canonical data from dated captures"), then
   `bash scripts/validate_data.sh`. Every value taken from a capture cites the capture's path and the page URL, and the
   validator checks that the file exists.

## Run the combat and formula tests

```bash
bash scripts/test.sh combat parity stats progression skills
```

`test_parity_*` replays the 818 golden vectors computed by MeowDB's own calculators
(`game/tests/data/parity_vectors.json`). `test_combat_*` covers every stage of the damage pipeline and `test_skills_*`
the Beginner skills. The formulas are documented in [COMBAT.md](COMBAT.md).

## Teleport between maps

Open the console with the **backtick key** (`` ` ``):

```
warp 000000040            # a MeowDB map id, a GMS v8 id (40000) or a name fragment ("snail hunting ground i")
warp 000001010 in02       # arrive at a portal's arrival point
portals                   # the current map's portals and where they lead
where                     # map, region, position, session state
```

## Grant items

```
give 270 10               # 10 Red Potions (MeowDB item id)
give "Red Potion" 10      # by name
give 522                  # The Green Relaxer (a chair)
mesos 5000
clearinv use              # empty one tab (or all tabs)
```

## Grant EXP, quests and skills

```
exp 100                   # level-ups, AP, SP and HP/MP growth happen as in play
level 8                   # set the level consistently (AP/SP/HP/MP)
quest complete 1006       # quest accept|complete|forfeit|reset <id> [force], quests
skills                    # skill levels, SP, cooldowns and active effects
cast recovery             # cast a learned skill now (by id or name)
```

## Drops and Wooden Boxes

```
drops 2 1000              # simulate 1000 Snail kills: observed vs configured rates, each chance's table cell,
                          # and why a member never rolls (unresolved item, rarity or category); quest gates follow your quests
drops 0000001 500         # the same for the Wooden Box
loot 2 5                  # roll five Snail kills' loot at your feet (quest-gated drops follow your quests)
boxes                     # the current map's Wooden Boxes: placement, hits taken, respawn countdown
```

## Enable debug overlays

- **F3** toggles the overlay: FPS, map and street, session state, position (world and map-local), region, HP and
  states, monsters alive against capacity, and the next spawn tick. The minimap shows the canonical map id while it is
  on.
- Draw layers (console): `collision on`, `spawns on`, `portaldata on`, `npcs on`, `bounds on`, `mobregion on`,
  `rings on`, `safeground on`, or `draw all on`.
- `god on` makes you invulnerable, `heal` refills HP and MP, `spawn 2 5` spawns five Snails, and `kill all` kills them
  through the normal death path (EXP and drops).

Everything is listed by `help` in the console and documented in [DEBUG_TOOLS.md](DEBUG_TOOLS.md).
