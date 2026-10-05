# How to (Iteration Two)

Every command runs from the repo root in **Git Bash** on Windows. Blender 5.2 must be installed (set `BLENDER=...` if
it is not at `C:\Program Files\Blender Foundation\Blender 5.2\`). Godot 4.7.2 is downloaded on first use to
`%LOCALAPPDATA%\MisoStory\godot\4.7.2\` (override with `GODOT=...`). Node is only needed to re-run the MeowDB
extractors.

## Build the Blender environment

```bash
B="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
"$B" -b --factory-startup --python scripts/build_island.py        # -> MapleIsland.blend (~1 min)
"$B" -b MapleIsland.blend --python scripts/validate.py            # -> docs/VALIDATION.md (expect 0 high, 0 medium)
"$B" -b --factory-startup --python scripts/build_map.py -- 50000  # one map alone (GMS v8 id), with MAP_TRAVERSAL_OK
```

The generator is `src/misostory/` (maps in `maps/m<id>_*.py`). Authoring rules: [`../AUTHORING.md`](../AUTHORING.md).

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
PY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
"$PY" src/misostory/sidecar_diff.py --old game/assets/world --new _scratch/export_staging   # SIDECAR_DIFF_OK True
MISOSTORY_EXPORT_DIR=_scratch/export_staging "$PY" src/misostory/test_sidecar_contract.py  # all OK
```

Then replace `game/assets/world/` with the staging folder. Never keep a backup of it under `game/assets/`: everything
there is git-ignored except `.gitignore`.

## Launch the game

```bash
bash scripts/play.sh              # windowed 1600x900
bash scripts/play.sh --fullscreen
bash scripts/play.sh --editor     # open the project in the Godot editor
```

## Create a clean save

On the title screen choose **New Game**, then pick a name, gender, starter weapon (the canonical creation weapons 541,
576 and 585) and the 9 creation AP. A new game always goes into the first free slot, so it never overwrites a save.
Saves live in Godot's user folder for the project (`%APPDATA%\Godot\app_userdata\MisoStory\saves\`). To wipe a slot
from inside the game, open the console and run `reset_save [slot]` (alias `reset`), or `delete_save <slot>`.

## Run automated tests

```bash
bash scripts/test.sh                       # every headless test (~3 min; 1140 tests)
bash scripts/test.sh combat parity         # only files whose name contains a filter
ISOLATE=me INCLUDE_WORLD=1 bash scripts/test.sh   # in a private copy (parallel-safe), with the exported world
```

Real-game playthroughs (the brief's Tests A–G; see [PLAYTHROUGH_REPORT.md](PLAYTHROUGH_REPORT.md)):

```bash
bash scripts/playtest.sh test_e_quest            # headless; report in _scratch/... (path printed)
bash scripts/playtest.sh test_a_traversal --windowed --out "$PWD/_scratch/tour"
```

The scenarios are in `game/tools/playtest/scenarios/` and the harness is documented in
[PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md).

## Run canonical-data validation

```bash
bash scripts/validate_data.sh              # exit 1 on a broken reference, 2 if the validator itself is broken
bash scripts/validate_data.sh --strict     # warnings fail too
```

It runs the game's own loader over `game/data/canonical` and `game/data/misostory`
([DATA_VALIDATION.md](DATA_VALIDATION.md)). To regenerate the canonical data from the local MeowDB cache, see
[`../canonical/README.md`](../canonical/README.md).

## Run the combat and formula tests

```bash
bash scripts/test.sh combat parity stats progression
```

`test_parity_*` replays the 818 golden vectors computed by MeowDB's own calculators
(`game/tests/data/parity_vectors.json`). `test_combat_*` covers every stage of the damage pipeline. The formulas are
documented in [COMBAT.md](COMBAT.md).

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
mesos 5000
clearinv use              # empty one tab (or all tabs)
```

## Grant EXP

```
exp 100                   # level-ups, AP, SP and HP/MP growth happen as in play
level 8                   # set the level consistently (AP/SP/HP/MP)
quest complete 1006       # quest commands: quest accept|complete|forfeit|reset <id>, quests
```

## Enable debug overlays

- **F3** toggles the overlay: FPS, map and street, session state, position (world and map-local), region, HP and
  states, monsters alive against capacity, and the next spawn tick.
- Draw layers (console): `collision on`, `spawns on`, `portaldata on`, `npcs on`, `bounds on`, `mobregion on`,
  `rings on`, `safeground on`, or `draw all on`.
- `god on` makes you invulnerable, `heal` refills HP and MP, `spawn 2 5` spawns five Snails, and `kill all` kills them
  through the normal death path (EXP and drops).

Everything is listed by `help` in the console and documented in [DEBUG_TOOLS.md](DEBUG_TOOLS.md).
