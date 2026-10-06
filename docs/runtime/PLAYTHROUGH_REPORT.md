# Playthrough validation report

Iteration Three's clean-character playthrough and every-quest set come first; the Iteration Two report (Tests A-G
and the movement, camera, combat and world reviews) follows unchanged.

# Iteration Three: the clean-character playthrough (2026-10-05)

One run of the real game from a brand-new character to Shanks' departure boundary in Southperry, strict from the step
after character creation. The results below are the final evidence run on the final Iteration Three build (waves 1-4
merged and the KuroDB 2040705 read applied; the game, harness and data at commit `9ddf137`, a clean tree, recorded in
each report's `git` block; scenario `playthrough`). It answers the brief's Phase 15, the "Clean-Character Progression
Audit" and the Definition of Done "Gameplay". The method is in
[PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md) ("The clean-character playthrough"); every quest of it is played by the
same `PlaytestQuestRunner` as the every-quest set, whose own report is
[QUEST_PLAYTHROUGH_REPORT.md](QUEST_PLAYTHROUGH_REPORT.md).

```bash
PLAYTEST_TIMEOUT_S=7500 ISOLATE=pt bash scripts/playtest.sh playthrough --seed 1 --max-wall-s 7000 --out _scratch/pt/s1
PLAYTEST_TIMEOUT_S=7500 ISOLATE=pt bash scripts/playtest.sh playthrough --seed 1 --max-wall-s 7000 --windowed --out _scratch/pt/w1
```

## Result

**PASS on seeds 1, 2 and 3 headless, and on seed 1 in a window** (the final evidence run), at a fixed 60 fps, 8
processes each (7 restarts through Quit Game and Continue), 0 failed checks, 0 warnings, strict mode intact from
character creation to the end. The headless runs lay the game out on the windowed 1600x900 screen, and every click,
double-click and drag first checks that a player could make it (PLAYTEST_HARNESS.md "Headless and windowed"): the
Skills window's Set key, the stats window's "+", the shop rows and the inventory slots were all on screen and
uncovered when the runs pressed them. Each report is a clean run for the parity manifest: it passes, it is strict with
0 console and 0 api steps, and its final boundary check ("ready to depart: the End of Maple Island screen reached in
Southperry") passed with no `PLAYTHROUGH_STOP` flag (`tools/parity/parity.mjs` `cleanRun`).

| Seed | Mode | Checks | Game time | Wall time | Level at the end | Mesos at the end | Quest hat (1008) | Quest knife (1011) | Deaths |
|---|---|---|---|---|---|---|---|---|---|
| 1 | headless | 625 | 2,590 s (43 min) | 411 s | 8 (the Fruit Knife needs 8) | 497 | 715 Blue Headband | 559 Fruit Knife | 1 |
| 2 | headless | 623 | 2,329 s (39 min) | 312 s | 7 | 428 | 712 Black Headband | 558 Razor | 1 |
| 3 | headless | 623 | 2,298 s (38 min) | 308 s | 7 | 383 | 715 Blue Headband | 558 Razor | 1 |
| 1 | windowed | 695 | 2,573 s (43 min) | 696 s | 8 | 497 | 715 Blue Headband | 559 Fruit Knife | 1 |

The windowed run has 70 more checks: in a window the quest runner also checks that each quest marker over an NPC is
drawn on screen (the "marker is drawn" rows; the visual chunks load only windowed). Its route, draws and checkpoints
follow the headless seed-1 run's closely (one more Shroom kill: 1,309 EXP at the boundary against 1,303). It recorded
0 input re-asserts (the window kept its focus) and 0 engine errors. The wall times were taken with up to two other
Godot runs of the evidence run beside each. No run logged the G1 resume-point warning (fixed in wave 3; see
"Findings").

**Earlier runs.** The previous final run (`c4e9ac5`, before wave 4) passed seeds 1, 2 and 3 headless with 620, 617
and 617 checks, but on the old 1600x1600 headless GUI area and without the click gate; the acceptance review's windowed
re-run of it failed 8 checks on the Skills window's Set key, which had grown off the bottom of the 900 px screen
(fixed in wave 4: every window stays above the HUD's status bar, and the summary checks now need real casts). At the
playthrough package's commits the scenario passed seeds 1, 2 and 3 with 619, 616 and 615 checks (`6ccc699`), and the
review re-run at `5bf2687` with 616, 616 and 617. The first evidence run (`ee0a209`) failed 1 check on seed 1 and 3 on
seed 2: harness defects in the Wooden Box approach and the Three Snails throw (findings H2 and H3 below), both fixed.
Check counts differ by a few between runs because the draws and the physics differ (for example whether the Egg step
finds HP low enough for an Egg's whole restore, or whether Pan's first visit can afford the sandals).

## Strict mode: the proof of a console-free run

| | Seed 1 | Seed 2 | Seed 3 | Seed 1 windowed |
|---|---|---|---|---|
| Strict since | phase 0, step 1 (right after `new_game`) | the same | the same | the same |
| Console steps / api fallbacks / developer commands | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| Ledger: reconciliations, events heard, mismatches | 9, 423, 0 | 9, 336, 0 | 9, 314, 0 | 9, 425, 0 |
| Violations | 0 | 0 | 0 | 0 |
| Play steps (top level) | 1,001 | 914 | 890 | 1,002 |

- The character was created through the real title and creation screens: New Game, the name typed, the creation
  screen's **Recommended** button (STR 13, DEX 4, INT 4, LUK 4 and the Wooden Club, the guide's recommendation) and
  Start. No step of the run used the console or a shell call; the creation itself went "via screen".
- Every change to EXP, mesos, items and quest states was announced on the event bus (`PlaytestLedger`, reconciled at
  every phase end, Quit to Title and new game). `test_playtest_strict.gd` scans `playthrough.gd`, `PlaytestKit`,
  `PlaytestQuestRunner` and the driver, walker, grid planner, input and runner for teleports, direct writes and
  service calls (they pass).
- The only reloads are the pause menu's Save then Quit Game (a new process: Continue on the title) and one Save, Quit
  to Title and Continue in the same process. After each, the character was compared with what was saved: level,
  EXP, mesos, AP, SP, skills, bag, equipment, quests, map and the play-time clock.

## The route and its phases (seed 1; the others are the same steps)

| Phase | Ends with | Game s | Wall s | Steps |
|---|---|---|---|---|
| 0 | Quit Game | 274 | 39 | character creation; Heena and Sera (1000, 1001); Roger (1002); Nina and Sen (1003, 1004); Todd and Peter (1005); Save, Quit to Title, Continue |
| 1 | Quit Game | 534 | 85 | Robin; Sam (1006, 10 Snails); the first SP: Three Snails learned, bound to key 1, thrown at a Snail; Snail Hunting Grounds II and III to A Split Road; Mai (1006 done), Maria (1007), Mai (1009); Southperry: Yoona, Bari, Biggs (1011), Shanks refusing level 4; Pan's shop |
| 2 | Quit Game in 1009 | 83 | 12 | Mai's training to 5/10 Blue Snails (the mid-quest restart) |
| 3 | Quit Game in 1012 | 324 | 78 | 1009 done, 1010 accepted; Recovery and Nimble Feet learned and cast; The Field West of Amherst: 1010's Orange Mushroom and 1011's cap; Amherst: Lucas (1007 done, 1008 accepted); Pio (1012): a box broken before the accept, then Wooden Boxes to 1/3 Rusty Screw (the mid-quest restart) |
| 4 | Quit Game | 345 | 51 | 1012 done (The Green Relaxer); the death in The Field West of Amherst and the respawn in Amherst; The Green Relaxer sat on; Rain (1013-1019); Sid; Lucy; Townstreet, Snail Field of Flowers, The Field East of Amherst, Tomato Field |
| 5 | Quit Game | 897 | 130 | the six forest maps; A Split Road (1010, 1008 done); Southperry (1011 done); the hat, the knife refused below level 8; Pan again; the level-8 hunt at A Split Road; the knife equipped |
| 6 | Quit Game | 115 | 11 | Shanks: the offer, Yes, the End of Maple Island screen; Save |
| 7 | done | 18 | 4 | Continue: the departure flag survives; the summary checks |

## Checkpoints (the progression audit)

Seed 1 headless, from `d.carry["checkpoints"]`. Play time is game time since the title (all phases). ETC items: 348
Snail Shell, 349 Blue Snail Shell, 350 Mushroom Spore, 351 Red Snail Shell, 356 Orange Mushroom Cap, 439 Maria's
Letter, 440 Lucas's Letter. Skills: Three Snails / Recovery / Nimble Feet levels.

| Checkpoint | Play s | Map | Level | EXP (total) | Mesos | Equipment | Important ETC | Skills | Quests done |
|---|---|---|---|---|---|---|---|---|---|
| a new character | 18 | 000000001 | 1 | 0 (0) | 0 | Wooden Club | | | 0 |
| Mushroom Town's tutorial quests (1000-1005) | 259 | 000000030 | 2 | 3 (18) | 0 | Wooden Club | | | 6 |
| Sam's Suggestion (1006) done | 598 | 000000050 | 3 | 51 (100) | 16 | Wooden Club | 348x14 349x3 | 1/1/0 | 7 |
| Southperry, first visit | 781 | 000000060 | 4 | 38 (144) | 37 | Wooden Club | 348x14 349x5 350x2 351x3 439 | 1/1/0 | 7 |
| Pan's shop, first visit (sandals refused at 37 mesos; loot sold) | 807 | 000000061 | 4 | 38 (144) | 55 | Wooden Club | 348x14 349x5 439 | 1/1/0 | 7 |
| Mai's Training (1009) done | 1,047 | 000000050 | 6 | 25 (358) | 101 | Wooden Club | 348x14 349x16 350x10 351x5 439 | 2/2/1 | 8 |
| 1010's Orange Mushroom and 1011's items | 1,098 | 000001000 | 6 | 40 (373) | 101 | Wooden Club | ... 349x16 356x1 439 | 2/2/1 | 8 |
| Pio (1012) done: The Green Relaxer | 1,252 | 000001010 | 6 | 172 (505) | 270 | Wooden Club | ... 349x16 351x9 356x1 440 | 2/2/1 | 10 |
| after the death (respawned in Amherst) | 1,283 | 000001010 | 6 | 135 (468) | 270 | Wooden Club | (unchanged) | 2/2/1 | 10 |
| Rain's seven quizzes (1013-1019) done | 1,322 | 000001010 | 7 | 8 (713) | 270 | Wooden Club | (unchanged) | 2/2/2 | 17 |
| Sid's shop (Sword bought) | 1,346 | 000001011 | 7 | 8 (713) | 255 | Sword | 348x14 349x16 350x5 351x4 356x1 440 | 2/2/2 | 17 |
| Lucy's shop (2 Red Potions) | 1,375 | 000001013 | 7 | 8 (713) | 186 | Sword | 348x14 349x16 356x1 440 | 2/2/2 | 17 |
| Amherst and its neighbours explored | 1,560 | 000001010 | 7 | 16 (721) | 198 | Sword | 348x14 349x16 351x1 356x1 440 | 2/2/2 | 17 |
| 1010 and 1008 done (A Split Road) | 2,083 | 000000050 | 7 | 248 (953) | 398 | Sword | 348x15 349x25 350x2 351x5 356x1 | 2/2/2 | 19 |
| Biggs (1011) done | 2,166 | 000000060 | 7 | 346 (1,051) | 429 | Sword | 348x15 349x15 350x4 351x7 | 2/2/2 | 20 |
| the quest hat equipped (knife refused: level 8) | 2,166 | 000000060 | 7 | 346 (1,051) | 429 | Blue Headband, Sword | (unchanged) | 2/2/2 | 20 |
| Pan's shop, last visit (Leather Sandals) | 2,188 | 000000061 | 7 | 346 (1,051) | 379 | Blue Headband, Leather Sandals, Sword | (unchanged) | 2/2/2 | 20 |
| after the level-8 hunt | 2,415 | 000000050 | 8 | 0 (1,265) | 493 | Blue Headband, Leather Sandals, Sword | 348x15 349x32 350x11 351x20 | 3/2/2 | 20 |
| at the departure boundary | 2,572 | 000000060 | 8 | 38 (1,303) | 497 | Blue Headband, Leather Sandals, Fruit Knife | 348x15 349x33 350x14 351x22 | 3/2/2 | 20 |

Seeds 2 and 3 at the same checkpoints:

| Checkpoint | Seed 2: play s, level, total EXP, mesos | Seed 3: play s, level, total EXP, mesos |
|---|---|---|
| Mushroom Town's tutorial quests | 271, 2, 18, 0 | 236, 2, 18, 0 |
| 1006 done | 614, 3, 104, 24 | 596, 4, 120, 31 |
| Southperry, first visit | 785, 4, 132, 37 | 762, 4, 142, 48 |
| 1009 done | 1,084, 6, 370, 143 | 1,074, 6, 362, 146 |
| Pio (1012) done | 1,297, 6, 505, 314 | 1,304, 6, 497, 304 |
| after the death | 1,333, 6, 468, 314 | 1,336, 6, 460, 304 |
| Rain's quizzes done | 1,371, 7, 713, 314 | 1,375, 7, 705, 304 |
| Biggs (1011) done | 2,242, 7, 1,100, 478 | 2,208, 7, 1,043, 433 |
| at the departure boundary | 2,308, 7, 1,100, 428 | 2,278, 7, 1,043, 383 |

Level-ups (play s): seed 1: 2 at 258, 3 at 446, 4 at 605, 5 at 953, 6 at 1,045, 7 at 1,321, 8 at 2,413; seed 2: 2 at
270, 3 at 457, 4 at 632, 5 at 964, 6 at 1,081, 7 at 1,370; seed 3: 2 at 235, 3 at 405, 4 at 593, 5 at 949, 6 at
1,072, 7 at 1,374.

Major quest rewards received (all three seeds, each checked exact against canonical data at the turn-in): 1006: 30
EXP and 3 Eggs; 1009: 70 EXP and 5 Eggs; 1010: 100 EXP, 150 mesos and 10 Eggs; 1008: 50 EXP and one random hat;
1011: 70 EXP and one random knife; 1012: 100 EXP, 150 mesos and The Green Relaxer; 1013-1019: 245 EXP in all and 10
Oranges (1019).

## Definition of Done "Gameplay", item by item

Every item below is a check of the run (or a group of checks) that passed on all three headless seeds and in the
windowed run.

| Item | Evidence in the run |
|---|---|
| create character | `new_game` through the title and creation screens (`via` "screen"), then "a new Beginner: level 1, 0 EXP, 0 mesos, no quest, in Maple Island's first map 000000001" |
| begin Maple Island | strict mode from the next step; Heena's 1000 offered by her marker in 000000001 |
| complete the opening/tutorial content | 1000-1005 played and completed (Heena, Sera, Roger, Nina, Sen, Todd, Peter), Robin talked to; every quest check of the runner passed |
| fight every Maple Island monster type | "X fought and killed" for all 6 species (seed 1: 3 Tutorial Jr. Sentinels, 18 Snails, 43 Blue Snails, 27 Shrooms, 34 Red Snails, 1 Orange Mushroom) and "N kills gave the canonical EXP each" per species |
| obtain normal monster drops | "monster drops picked up with Z": 134 / 99 / 91 items (the count is every item picked up with Z, so it also holds the few items of 1012's Wooden Boxes); the monster-only loot in the checkpoints (Snail Shell, Blue Snail Shell, Mushroom Spore, Red Snail Shell, Orange Mushroom Cap); quest drops (Jr. Sentinel Shellpiece, Blue Snail Shell, Orange Mushroom Cap) collected for 1005 and 1011 |
| obtain mesos through actual monster drops | "mesos from monster meso bags picked up": 313 mesos in 55 bags / 249 in 43 / 202 in 34 (the Wooden Box drops no mesos, so every bag was a monster's) |
| level naturally | "level 8 / 7 / 7 reached naturally: EXP only from kills, quest rewards and the death penalty"; every kill's EXP and every quest's EXP equal to canonical data (see the progression review) |
| allocate AP | "every AP spent through the stats window (35 / 30 / 30 points over 7 / 6 / 6 levels)": each point a mouse click on the stats window's "+" |
| use consumables | Roger's Apple used for 1002; an Egg (+60 HP) eaten with a double-click in Southperry on seeds 2 and 3 (the step waits for HP low enough for an Egg's whole restore, which seed 1's HP there was not); an Orange for MP in Amherst (+7 on every seed: its canonical 50 capped at Max MP 77); Eggs and Red Potions drunk by the survival policy whenever HP fell below 40% (7 / 4 / 6 per run) |
| equip gear | the Sword bought from Sid, the Leather Sandals bought from Pan, the 1008 hat at level 7 (it needs 5), the 1011 knife: the Razor at once (seeds 2 and 3), or the Fruit Knife refused at level 7 with "You need to be level 8 to equip that." and equipped after the level-8 hunt (seed 1) |
| use every Maple Island shop | Pan, Sid and Lucy each "bought and sold" at canonical prices and sell prices; on every seed Pan's first visit was short of mesos and the refusal ("You do not have enough mesos. (costs 50, you have 37)" on seeds 1 and 2, 48 on seed 3) was checked, the sandals bought on the last visit |
| complete every Maple Island quest | "every Maple Island quest completed through play (20 of 20)"; per quest the full runner checks (availability, accept, objectives, turn-in, exact rewards, follow-ups) |
| complete every quiz | 1013-1019: one wrong answer each (its canonical line, the quest still in progress), then the canonical answer, all seven completed |
| obtain and use a chair | The Green Relaxer from 1012; double-click in the Set-up tab seats the player, X seats again, a step stands up; seated at 50 of 130 HP right after the respawn, HP rose in 11 s by 50 on seeds 1 and 3 (the chair's 30 plus two natural ticks of 10) and by 40 on seed 2 (one tick), exactly the canonical amounts; the HUD's seated cue shows while seated |
| visit all 25 maps | "map ... visited on foot" for each of the 25 canonical maps (`visited_maps`, from `Events.map_entered`) |
| die and respawn correctly | a death to Orange Mushroom contact in The Field West of Amherst; the notice; the canonical EXP penalty (37 at level 6, LUK 4: floor(372 x 10 / 100)); the notice's OK respawns at the map's canonical return map, Amherst |
| save and reload during progression | 7 process restarts (5 planned, 2 in the middle of 1009 and 1012) and one Quit to Title, each compared with the saved character |
| reach Southperry legitimately | on foot from Amherst over The Field West of Amherst and A Split Road (portal hops, no warp) |
| arrive ready to depart | at level 7+ with at least 300 mesos, Shanks offers the voyage; Yes shows "End of Maple Island" ("Maple Island quests completed: 20 of 20", "Every Maple Island quest is done."), the fare is not taken, the departure flag is set and survives the last restart |
| no developer console during the canonical playthrough | the strict block above: 0 console, 0 api, 0 developer commands, 0 ledger mismatches, from the step after creation |

Also exercised: all 21 NPCs talked to on foot (each check tagged `npc:<id>`); the three Beginner skills learned with
the Skills window's "+" and bound with Set key and a key 1-3 (Three Snails hit a Snail three times for the canonical
fixed 15 and killed it; Recovery and Nimble Feet started their effects and cost their canonical MP; the end-of-run
summary counts only real casts); no NPC speech bubble over an open shop; quest markers and the Quest Log at every quest
step. Each run's checks carry 103-105 distinct parity keys (all 25 maps, 21 NPCs, 20 quests, 6 monsters, 3 shops, 3
skills, the chair, the Wooden Box, quest items and `mechanic:*` keys; 107 distinct keys over the three seeds, 13 of them
`mechanic:*`), and none of them failed.

## Deaths

One death per seed, deliberate because no natural death happened first: after Pio, the player walks into the Orange
Mushrooms of The Field West of Amherst without attacking or drinking (`let_monsters_win`) and dies to their contact
damage (8-11 touches, 89-118 damage, 19-24 s). The death notice shows, the EXP penalty is the canonical floor(EXP to
next level x (5 + 20 / LUK) / 100) = 37 at level 6 with base LUK 4 (EXP 172 -> 135 on seeds 1 and 2, 164 -> 127 on
seed 3), and the OK respawns the player at the field's canonical return map, Amherst, with 50 HP. In an earlier
evidence run the death came before Pio, right after a level-up, and the penalty was capped at the EXP held (16 and
26): "EXP stops at 0, so a death never takes away a level" (formulas/death.json).

## Progression review

**Canonical expectations.** The 20 quests give 680 EXP and 300 mesos in all (`rewards.exp`, `rewards.mesos`). The
kills the quest objectives require are 3 Tutorial Jr. Sentinels (1 EXP each), 10 Snails (2), 10 Blue Snails (4), 10
Shrooms (6), 5 Red Snails (8) and 1 Orange Mushroom (15): 178 EXP. 1011's 10 Blue Snail Shells and Orange Mushroom
Cap drop at probability 1.0 from those species, so they need no extra kill when 1009's Blue Snail Shells are kept.
The minimum, 680 + 178 = 858 EXP, passes level 7 (705 EXP from level 1) and leaves 153 of the 560 to level 8. So a
player who does every quest with no extra hunting reaches exactly Shanks' canonical level 7: the canonical numbers
fit together.

**What the runs did.**

| | Seed 1 | Seed 2 | Seed 3 |
|---|---|---|---|
| EXP from quests | 680 | 680 | 680 |
| EXP from kills (kills) | 660 (126) | 457 (88) | 400 (81) |
| of which the level-8 hunt for the Fruit Knife | 214 | - | - |
| Death penalty | -37 | -37 | -37 |
| Total EXP, level | 1,303, 8 | 1,100, 7 | 1,043, 7 |
| Level 7 reached at | 1,321 s | 1,370 s | 1,374 s |
| Mesos in: quests / meso bags / sales | 300 / 313 / 84 | 300 / 249 / 79 | 300 / 202 / 81 |
| Mesos out: Sandals, Sword, 2 Red Potions | 200 | 200 | 200 |
| Mesos at the end | 497 | 428 | 383 |

- **EXP per kill and per quest are exact.** The end-of-run checks compare the event bus's EXP per source with
  canonical data: every kill of every species gave its monster's canonical EXP, and the 20 quests gave exactly 680.
  Nothing scales, rounds or double-counts EXP.
- **Kills.** The runs killed 2.2-2.6 times the EXP the objectives require (400-457 EXP of kills before the Fruit Knife
  hunt), because the hunts take what attacks the player and travel through hunting maps fights back. The quests are
  52-65% of all EXP earned, so they, not grinding, carry the island.
- **Time.** Level 7 came after 22-23 minutes of game time (at Rain's quizzes) and Shanks after 38-43 minutes (with a
  4-minute level-8 hunt when the Fruit Knife is drawn). For comparison, Test C, which levels by killing only, reached
  level 9 in about 1.3 hours of play in this evidence run (and needed about 2.2 hours to reach level 8 in the Phase B3
  baseline, before the drop and spawn changes; [ITERATION_LOG.md](../ITERATION_LOG.md)). Nothing here points to an
  implementation fault; the pace is the canonical rewards' pace.
- **Mesos.** Expected meso-bag income per kill from the canonical drop tables is 0.8 (Snail), 1.6 (Blue Snail), 2.0
  (Shroom), 4.0 (Red Snail) and 4.4 (Orange Mushroom); the runs' kills predict about 278, 188 and 163 mesos against
  313, 249 and 202 picked up. In bags: 55, 43 and 34 against about 49, 34 and 31 expected from the 123, 85 and 78 kills
  that can drop mesos at 40%: seeds 1 and 3 within one standard deviation, seed 2 about two above, and the three
  together about two above. The roller itself draws one meso roll per kill (`MonsterSystem` calls `DropRoller.roll`
  once per death) and its rates are checked by the unit suite's drop simulations; the meso totals reconcile exactly
  with the ledger. The quests' 300 mesos equal Shanks' fare, which the boundary checks but does not take; after 200
  mesos of shopping the runs ended with 383-497. A player who spends more has to hunt for the fare (the playthrough's
  `ready_to_sail` step would have; it was not needed).
- **Level gates never stopped the route.** Each quest's canonical level (1007: 2, 1009 and 1011: 3, 1012 and the
  quizzes: 5) was already reached when the player met the NPC: the runner's level check and hunt were never needed.
- **The Fruit Knife (1011's random reward, level 8) is above Shanks' level 7.** Seed 1 drew it (headless and
  windowed); the player could only equip it after hunting one more level. That is canonical data (MeowDB item 559,
  requirements.level 8), not a defect.
- **Equipment.** The Wooden Club the guide recommends at creation, then the Sword (Sid, 50 mesos), the quest hat
  (level 5, equipped at 7), Leather Sandals (Pan, 50 mesos) and the quest knife. Shops sold every listed item at its
  canonical price; sales paid the canonical sell price (Red Snail Shell 4, Mushroom Spore 3, Blue Snail Shell 2, Snail
  Shell 1, Orange Mushroom Cap 8).

## Findings

No game defect blocked the player in any run, and none was fixed in game code by this package. What the runs found:

**Game:**

- **G1 (low; world/saves): a Continue right after a walkable trail logged a resume-point warning. Fixed in wave 3**
  (W3-6, `1e349d5`): `IslandWorld.validate_resume` now accepts a point inside the trigger of the save's own entry
  portal, which the load disarms as on a real arrival (the `resume_gate` scenario, 23 checks); the final runs above
  logged no resume warning on any seed. What the runs had found: on every run the
  save made after "explore_amherst" (arrived in Amherst over the trail from The Field East of Amherst) and, on seed 1,
  the one before boarding (arrived in Southperry over the trail from A Split Road) were refused on Continue:
  MapSession printed "saved resume point (257.85, 6.00, 634.78) in 000001010 failed validation; using the entry"
  (and (74.65, 4.30, 531.09) in 000000060). A probe placed both points: Amherst map-local (74.2, 0.0, -12.0), inside
  the trigger box of the edge portal east00 and 0.71 m from that portal's own arrival spawn (73.5, 0.0, -12.0);
  Southperry (4.5, 3.3, -44.2), inside west00's trigger, 0.70 m from its arrival spawn. The walk across a trail gate
  stops inside the gate's own trigger, and `IslandWorld.validate_resume` refuses any point inside a non-arrival
  portal's trigger. The fallback is the entry, 0.7 m away, so the player sees nothing wrong. Expected: a spot the
  game itself delivered the player to should resume without a warning (accept the entry portal's own trigger, or
  move edge arrivals out of their trigger). This warning is the only engine message of the runs. It depends on where
  the walk happens to stop after the gate: in the review re-runs at `5bf2687` seed 2 logged the Amherst warning
  again and so did seed 3, while seed 1 resumed silently.
- **G2 (note, canonical): the Fruit Knife needs level 8**, one more than Shanks asks; see the progression review.

**Harness (fixed in this package):**

- **H1: the survival guard spun on a monster it could not reach.** Seed 2 of the every-quest 1006 chain: a Snail on
  a ledge 1 m above the trail touched the player; the guard stopped the walk to fight back, the fight back could not
  reach it without a chase, and the next walk was stopped at once, 24 times in 2 s of game time; the trail hop to
  Snail Hunting Ground II failed. `PlaytestKit` now shuns such a monster for 4 s.
- **H2: the Wooden Box walk-up did not know about tiers.** Amherst's box 000001010:0 (map-local (45.6, 0.0, -3.2))
  stands at the foot of a 1.6 m terrace; walking up from Lucas on the plaza ended on the terrace edge 1.3 m above it,
  and 40 attacks whiffed (both seeds of the first evidence run failed 1012's gate probe there). `break_box` now uses
  test_box's approach (spots on the box's own ground at 0.6 of the weapon's reach, the routes first, no attack from
  another tier) and passes over a box it cannot stand beside. The box is reachable: from the plaza the routes lead
  down to it.
- **H3: Three Snails was thrown at a Snail on another tier.** Seed 2 of the first evidence run: the target stood on a
  ledge, so the walk stopped at once (its stop condition ignored height) and the throw never happened, 0 casts in 40 s.
  `throw_at` now only walks until it is level with the target and gives up after three walks without progress; the
  playthrough picks targets on the player's own tier.
- **H4: walking into monsters never touched them.** The first `let_monsters_win` walked to each monster with the
  planner, whose arrival stops 0.75 m short: 1 touch in 400 s. It now takes the last step straight at the monster.
- **H5: a run continued from a copy of its `--out` wrote its report into the original directory** (the report kept
  the first phase's `out_dir`). The runner now writes where it is told.
- **H6: three playtest parity tags named no manifest entry** (`mechanic:quest-random-rewards` and
  `mechanic:quest-persistence` in the every-quest scenario, and drop tags built from the item id, `drop:9/356`); they
  are now `mechanic:random-quest-rewards`, `mechanic:save-load` and the drop entry's schema-v2 slug
  (`drop:9/orange-mushroom-cap`, `drop:3/blue-snail-shell`). Every evidence run since (the review re-runs at
  `5bf2687` and both final runs) carries only the slugs, and `build_parity.mjs` over them lists no tagged key that
  names no manifest entry. No check or verdict depends on a tag.

**Harness (fixed in the final evidence run of 2026-10-06; PLAYTEST_HARNESS.md "Findings"):**

- **H7: a trail hop whose retry stalled mid-trail was never unstuck.** The first run on the new drop sources failed
  seed 2 of the every-quest set's 1006,1009,1010: the hop out of Snail Hunting Ground I stalled at a ledge corner 10 m
  along, the retry stalled there at once, and `travel_to` measured the retry from the hop's start. The retry's own
  start counts now (`PlaytestKit.retry_stalled`); the spot is escapable ground (`trap_probe`).
- **H8: a rest on a ladder heals nothing.** In the same run Test C rested 2,250 s on an A Split Road ladder without a
  natural-recovery tick: climbing pauses recovery (contract C4), so the game was right. `PlaytestKit.rest()` climbs off
  first (`leave_climb`), checked by the `regen` scenario.

## The every-quest set and the other real-game scenarios of this package

- **Every quest:** 20 of 20 PASS on seeds 1, 2 and 3 (520 / 523 / 523 quest checks in the final evidence run, headless
  on the pinned screen), strict after each chain's logged setup; per-quest evidence in
  [QUEST_PLAYTHROUGH_REPORT.md](QUEST_PLAYTHROUGH_REPORT.md).
  1012 now passes with the real Wooden Box: the box broken before the accept drops none of the gated items.
- **`npc_shanks`** (the quests package's scratch check, adopted): PASS, 26 checks. Shanks refuses level 1 with the
  canonical level 7 and level 7 without the 300-meso fare; with the fare he gives the guide's sentence, lists the
  unfinished Maple Island quests and offers the voyage; Yes opens the End of Maple Island screen (no fare taken, still
  in Southperry, the flag set); Space does not close it, Enter and Esc do; the flag survives Save, Quit to Title and
  Continue. Setup: a warp, `level 7`, `mesos 300`.
- **`npc_bubbles`** (adopted): PASS, 7 checks. Strict after a setup warp to Amherst; in 30 s Pio and Rain showed four
  speech bubbles, every text one of the NPC's canonical idle lines; none shows over Rain while her chat is open.
- **`kit`** now learns Recovery with the Skills window's "+", binds it with Set key and casts it (previously a WARN):
  21 checks headless and windowed in the final evidence run. `test_skills` (51 checks) and `test_box` (40 checks, 17 of
  the 19 boxes broken) also pass in both modes there.

# Iteration Two: Tests A-G and the reviews (2026-10-04)

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
