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

## Using it

A later ticket reruns the same command on the same PC and compares: every map at least 60 fps, the world load at most
about 20% above 1,627 ms. Draw calls, primitives and memory are recorded to explain a regression, not gated. Rerun the
baseline itself only when the measurement changes (then say so in the ticket).
