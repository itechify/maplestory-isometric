# Performance baseline before the Project art (#62)

Every #59 art ticket is gated against this baseline: **at least 60 fps at 1080p in the busiest map on the owner's
PC, with the island's load time no more than about 20% above the baseline** (#59 decision 9). It was measured on
2026-10-13, before any visual change: the game still draws Iteration One's proxies and placeholders, and the art pack
is installed but not used yet. The numbers are the medians of three runs; all three are in
[`perf_baseline.json`](perf_baseline.json).

## How it was measured

```bash
bash scripts/build_runtime.sh                      # the world export and the art pack
PLAYTEST_RESOLUTION=1920x1080 bash scripts/playtest.sh perf_baseline --windowed --realtime --out <dir>
```

The `perf_baseline` scenario (`game/tools/playtest/scenarios/perf_baseline.gd`) plays the **real game**: it starts a
new game through the title and creation screens, then warps to each map's player spawn, lets it settle for 5 s
(monsters spawned, the gameplay camera following the player) and samples 300 frames. It writes `<dir>/perf.json`.
Run it windowed, in real time and without vsync (`playtest.sh --windowed` passes `--disable-vsync`; without
`--realtime` the frame rate is fixed at 60), on a window in the foreground.

| Metric | Meaning |
|---|---|
| World load | `GameSession.world_load_ms`: from the start of the island load to `world_ready` (every chunk resident) |
| New game | wall time of the whole new-game step: title, creation screen clicks, island load, player placed |
| fps, frame | wall-clock frames per second and mean frame time over the 300 frames; worst = the longest frame |
| CPU, GPU | the viewport's measured render time (CPU adds the process time, as `tools/perf_probe.gd` does) and GPU time |
| Draws, primitives | `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` and `..._PRIMITIVES_IN_FRAME`, mean per frame (shadow passes included) |
| Static, video memory | `MEMORY_STATIC` and `RENDER_VIDEO_MEM_USED` at the end of the sample |
| Nodes | `OBJECT_NODE_COUNT` (the whole island stays resident) |

Machine: the owner's PC, NVIDIA GeForce RTX 4070 SUPER, Windows 11, Godot 4.7.2, a 1920 x 1080 window.

## Baseline

| What | Value |
|---|---|
| World load | **1,627 ms** (gate: at most about 1,950 ms) |
| New game, title to playing | 2,916 ms |

| Map | fps | Frame (ms) | Worst (ms) | CPU (ms) | GPU (ms) | Draws | Primitives | Static (MB) | Video (MB) | Nodes |
|---|---|---|---|---|---|---|---|---|---|---|
| 000001000 The Field West of Amherst | 357 | 2.80 | 4.96 | 5.11 | 1.06 | 2,144 | 1.15 M | 512 | 541 | 27,477 |
| 000000060 Southperry | 401 | 2.49 | 3.52 | 4.69 | 0.94 | 2,337 | 1.12 M | 509 | 541 | 26,789 |
| 000000050 A Split Road | 467 | 2.14 | 3.92 | 3.79 | 1.00 | 1,522 | 0.93 M | 513 | 541 | 27,161 |
| 000001010 Amherst | 483 | 2.07 | 3.25 | 3.97 | 0.92 | 1,857 | 0.92 M | 516 | 541 | 26,909 |
| 000000041 Snail Hunting Ground II | 575 | 1.74 | 3.15 | 2.96 | 1.03 | 935 | 0.84 M | 520 | 541 | 27,185 |

The busiest map is The Field West of Amherst (lowest fps, most primitives). Southperry draws the most calls. The maps
are the perf gate's gameplay views (MAP_ARCHITECTURE.md 4.12) plus Snail Hunting Ground II.

## After the art pack (2026-10-13)

The same command on the same PC, on the integrated #59 branch (every #62-#75 ticket plus the review fixes, among them
the NPC rigs of other maps no longer animating), with the pack installed and nothing else running. Medians of three
runs each, plain and with `PERF_EQUIP=1` (the player wears a hat, a top, a bottom, shoes and earrings and holds the
sword); every run is in `perf_baseline.json` `after_art_pack`.

**Gate: pass.** The busiest map runs at 283 fps (gate 60), and the world loads in 1,649 ms, 1.4% above the baseline's
1,627 ms (gate about 1,950 ms; the three plain runs 1,643-1,658 ms, the equipped ones 1,629-1,678 ms).

| What | Plain | Equipped |
|---|---|---|
| World load | 1,649 ms | 1,634 ms |
| New game, title to playing | 2,560 ms | 2,547 ms |

| Map | fps | Frame (ms) | Worst (ms) | CPU (ms) | GPU (ms) | Draws | Primitives | Static (MB) | Video (MB) | Nodes | fps equipped | Draws equipped |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 000001000 The Field West of Amherst | 284 | 3.52 | 5.91 | 5.76 | 1.21 | 1,991 | 1.56 M | 518 | 571 | 28,691 | 283 | 2,044 |
| 000000060 Southperry | 395 | 2.53 | 3.71 | 4.49 | 0.93 | 2,041 | 1.26 M | 511 | 559 | 27,350 | 382 | 2,055 |
| 000000050 A Split Road | 380 | 2.63 | 4.05 | 4.28 | 1.08 | 1,438 | 1.20 M | 518 | 567 | 28,178 | 356 | 1,463 |
| 000001010 Amherst | 473 | 2.12 | 3.55 | 3.76 | 0.96 | 1,379 | 1.08 M | 516 | 560 | 27,440 | 436 | 1,411 |
| 000000041 Snail Hunting Ground II | 427 | 2.34 | 3.82 | 3.46 | 1.12 | 1,024 | 1.12 M | 523 | 565 | 28,112 | 408 | 1,042 |

Against the baseline the busiest map lost 20% of its frame rate (357 to 284 fps): it draws 35% more primitives
(1.15 M to 1.56 M, shadow passes included) with fewer draw calls (2,144 to 1,991). Southperry, the NPC-densest map,
is about unchanged (401 to 395 fps). Full equipment costs 14-53 draw calls and up to 8% fps per map. Static memory
grew by about 6 MB and video memory by about 18-30 MB.

### art-pack-v1.1 (2026-10-14, #61)

The same command, plain, three runs on the same PC with nothing else running, after the bump to Jarvis's v1.1
correction (the island rebuilt with the smaller fitted tomato plants and garden beds). **Gate: pass.** World load
1,717 ms median (1,653-1,866 ms), 5.5% above the baseline. The busiest map runs at 286 fps (269-286). Southperry runs
at 390 fps, A Split Road 371, Amherst 459 and Snail Hunting Ground II 421. Draw calls and primitives match the
v1.0 numbers above to within 0.3%: 1,991 draws and 1.56 M primitives in the busiest map. The decimated garden beds keep
their 434 triangles, and the plants their 422. A v1.0 run in the same session gave 260 fps and a 1,793 ms load, so
the spread is run-to-run noise.

## Using it

A later ticket reruns the same command on the same PC and compares: every map at least 60 fps, the world load at most
about 20% above 1,627 ms. Draw calls, primitives and memory are recorded to explain a regression, not gated. Rerun the
baseline itself only when the measurement changes (then say so in the ticket).
