# save_version 2 fixtures

Real `save_version` 2 save files written by the game before character appearance existed (#67). They are the
regression anchor of the v2 -> v3 migration (`docs/runtime/SAVES.md`): every later build must still load each of
them, and each must come back with its gender's default Beginner look. The tests that pin them are in
`game/tests/unit/test_save_v2_fixtures.gd`.

**Never edit these files.** They are evidence of what a player's save looked like before appearance was saved. A
change in what the current code makes of them belongs in the test, with the reason.

## Provenance

- Game code: commit `d11fc35` (the art-pack integration branch `t3code/art-pack-59` after #63 merged; save_version 2).
- Produced on 2026-10-13 at 21:39Z by a one-off real-game playtest scenario run headless (`--fixed-fps 60`, seed 1)
  on that commit with the world export and the art pack installed:
  `ISOLATE=67-capture bash scripts/playtest.sh capture_v2_saves`. The scenario was not kept: it played a female
  new game through the title and creation screens, walked route Main of 000000001 and saved through the pause menu
  (slot1); quit to title, played a male new game the same way and saved (slot2); then ran the debug console's
  `reset_save slot3`, the quick-start path that creates a character with no gender, and saved (slot3). Each file is
  the run's `saves/slotN.json`, copied byte for byte.

| Fixture | Source | sha256 | What it covers |
|---|---|---|---|
| `female.json` | `slot1.json` | `1698f43f97471fceabaae3ac39458fb45d6f18aec6e86ba8ce2f6ec86f13bf20` | "Mira", female, Lv 1, Sword (541) equipped, STR 9 DEX 8, after a walk through 000000001 |
| `male.json` | `slot2.json` | `7e2fdc1735a723aaa2c1c93871458997efae076665a0d30c15e957e76738321b` | "Tomas", male, Lv 1, Hand Axe (576) equipped, STR 13 |
| `no_gender.json` | `slot3.json` | `72675e93ec9296e28be4006e9fd788fd1ad572e50014468d465a204f0483f580` | "Beginner", gender `""` (the quick start of `new_character.json`), Wooden Club (585), STR 13 |
