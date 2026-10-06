# Iteration Two save fixtures

Real `save_version` 1 save files written by the Iteration Two game. They are the regression anchor for the save
migrations (`docs/runtime/SAVES.md`, contract C3 in `docs/runtime/ITERATION_THREE_CONTRACTS.md`): every later build
must still load each of them, with the values pinned in `game/tests/unit/test_save_it2_fixtures.gd`.

**Never edit these files.** They are evidence of what a player's Iteration Two save looks like. A change in what the
current code makes of them belongs in the test, with the reason.

## Provenance

- Game code: commit `62e36c9` (the Iteration Two game of `b85dec0`; the two commits differ in `game/` only by two
  `.uid` files).
- Produced on 2026-10-05 between 07:55Z and 08:14Z by the Iteration Three baseline run of the real-game playtests:
  `bash scripts/playtest.sh <scenario> --out _scratch/it3/baseline_playtests/<scenario>` (headless, `--fixed-fps 60`,
  seed 1). Each file is the scenario's `saves/slotN.json` at the end of the run, copied byte for byte.

| Fixture | Source | sha256 | What it covers |
|---|---|---|---|
| `e_quest_1008_done.json` | `test_e_quest/saves/slot1.json` | `b94c22a5e265c673e577761fa5f21bf988340b0b603239ae761639ec65d0ef5e` | Lv 3; quests 1002, 1006, 1007 and 1008 completed; the Green Headband (713) from 1008's random reward group in the Equip tab, with no record of the pick; Eggs (237) |
| `e_quest_1006_halfway.json` | `test_e_quest/saves/slot2.json` | `beca8c00b6077013eb0ed21cbc25847b466877c5e5f7239d78fa753edaf4ef48` | Lv 2; 1006 in progress with 10 Snail kills; an empty bag |
| `d_inventory.json` | `test_d_inventory/saves/slot1.json` | `79e134406a76a48376009bae3bef48b5f92f14773a64c5f352a3a7709f1278f8` | Lv 6, 56 mesos; quickslot `{"1": "237"}` (a bare v1 item id); top 933, bottom 1157 and weapon 585 equipped; a full Equip tab; Silver Ore (417) and Ice Jeans (1195) |
| `f_death.json` | `test_f_death/saves/slot1.json` | `9ea73c96b21bcbdaaa327d9c0f9cc85022f278a64608d25a82ca2e46e66907f1` | Lv 11 after two committed deaths; 1000 completed, 1006 in progress with 2 kills; a player-spawn entry in Amherst |
| `c_progression.json` | `test_c_progression/saves/slot1.json` | `344c6d982dba51a5b006a51b1c518549a6630f79dc41f6e483feee6cccb092fd` | Lv 8, 1042 mesos from kills only; the four ores 321, 413, 415 and 417 and the drop equips 651, 710, 934, 938, 939 and 1305 (Iteration Two drops from MeowDB's community lists; all are on the current lists) |
| `g_shop.json` | `test_g_shop/saves/slot1.json` | `cf3a1c889e6bc745d05f8972c2c6249154a7430847996f4d0fdbbaabdd312196` | Lv 1 after buying and selling in the Amherst Department Store; a full Equip tab of shop items |

Every fixture also has a `resume` point with the `map_content_hash` of its map's collision at that time. They
matched the exported world when these files were promoted, so a world rebuild that changes one of those maps makes
the load fall back to the map's entry instead (`ArrivalResolver.resolve_load`).
