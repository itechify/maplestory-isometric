# Every-quest gameplay report (Iteration Three)

This report answers the brief's "Full Quest Playthrough Requirement": every canonical Maple Island quest (20, MeowDB
quests 1000-1019: 5 chains and 4 standalone quests) is exercised through the actual game with real input, and for
each quest the run checks availability, acceptance, objective progress, completion, rewards and follow-up behaviour,
with a save and a process restart in the middle. Date: 2026-10-05. The results below are the final evidence run, on
the final Iteration Three build (waves 1-3 merged and the final cleanup; game, harness and data at commit `c4e9ac5`).

The clean-character playthrough plays the same 20 quests again, in one strict run from character creation to
Shanks, on two more seeds: [PLAYTHROUGH_REPORT.md](PLAYTHROUGH_REPORT.md) (Iteration Three).

## Result

**20 of 20 quests PASS on each of seeds 1, 2 and 3** (60 quest runs, 520 / 523 / 523 quest checks, 0 failed, 0
warnings). Every chain is strict after its setup: 0 console commands, 0 api fallbacks, 0 developer commands and 0
ledger mismatches from the strict step on. 1000-1001 needs no setup at all and is strict from character creation.
Each seed took about 2,050-2,490 s of game time and 260-340 s of wall time in total (the chains one or two at a time,
beside other runs of the evidence run).

| Seed | Quests PASS | Quest checks | Game s (sum of chains) | Wall s (sum of chains) | 1008 random hat | 1011 random knife |
|---|---|---|---|---|---|---|
| 1 | 20 / 20 | 520 | 2253 | 310 | 712 Black Headband | 559 Fruit Knife |
| 2 | 20 / 20 | 523 | 2485 | 340 | 715 Blue Headband | 559 Fruit Knife |
| 3 | 20 / 20 | 523 | 2047 | 259 | 709 Green Skullcap | 559 Fruit Knife |

Seed 1's 1009 has 3 checks fewer: its 5 Red Snails were all killed during the Blue Snail and Shroom hunts, so the Red
Snail objective needed no hunt of its own (recorded in the evidence as "already 5 of 5").

Run it: `bash scripts/playtest_quests.sh --seed <n> --out <dir>` (about 6 minutes with 3 jobs), then
`godot --headless --path game --script res://tools/playtest/playtest_quest_summary.gd -- --combine "<dir1> <dir2>
<dir3>" --out <file.md>` for the tables below. On Windows (Git Bash) give the directories in Windows form
(`cygpath -m`): MSYS converts only the first `/c/...` path inside one argument, and the summary then reads one run
only. The evidence of this report is `_scratch/final/pt/quests_s{1,2,3}` (git-ignored; regenerate with the commands
above).

## How each quest is played

The `quest` scenario plays one chain per run through `PlaytestQuestRunner`
([PLAYTEST_HARNESS.md](PLAYTEST_HARNESS.md) "The quest runner"). Every quest fact (NPCs, maps, levels, prerequisites,
objectives, item sources and chances, quiz answers, rewards, hand-ins) comes from `PlaytestQuestPlan`, which reads
canonical data only; nothing about a quest is hard-coded.

- **Setup (phase 0, the only console use, each command a logged step):** a new game through the title and creation
  screens; a warp to the chain's start map; for a quest above level 1, first the check that it is refused below its
  canonical level (no offer marker, the engine says unavailable), then `level N`; the save through the pause menu and
  Quit Game. The chain's own quests are never forced; prerequisites inside the chain are played.
- **Play (strict from the Continue):**
  - **Availability:** the NPC's marker reads `available` (gold !) and the engine agrees; the Quest Log's Available
    tab lists the quest. For 1012 one Wooden Box is broken before the accept and must drop neither Rusty Screw nor
    Old Wooden Board (the C1/C2 quest gate).
  - **Acceptance:** the offer accepted with Y in the NPC's dialogue; the accept items in the bag; the HUD log line;
    the marker after the accept; the Quest Log's In Progress tab and its objective rows.
  - **Objective progress:** kills with the attack key in the hunt map, drops picked up with Z, Wooden Boxes broken,
    items used by a double-click in the Item window, and the Quest Log row after each kill objective. Quizzes: one
    wrong answer first (its canonical line, the quest still in progress), then the canonical answer.
  - **Completion:** the turn-in NPC's `completable` marker (green ?), the completion in the dialogue, the HUD log
    line and the Completed tab.
  - **Rewards:** total EXP rises by exactly `rewards.exp` in one `quest:<id>` EXP event, mesos by exactly
    `rewards.mesos`, the bag by exactly the fixed items, one item of each random group and minus the canonical
    `items_removed_on_completion`, nothing else; the quest log's C3 `rewards_received` record matches the random pick.
  - **Follow-ups:** each canonical follow-up is available at once (or level-gated) and its NPC's marker offers it.
  - **Mid-quest save and restart:** each quest with objectives saves through the pause menu and quits the process at
    half of its first kill or item objective; the run's first talk-only quest right after its accept; a chain of three
    or more once more between two quests, at the middle of the chain (after quest `floor(n / 2)`: after 1006 in
    1006,1009,1010 and after 1015 in 1013-1019). After Continue in a new process the quest log, level, EXP, mesos, bag
    and map must be the saved ones and the Quest Log must still list the quest.
  - **Quests without a restart of their own:** 1001, 1004, 1008 and 1014-1019 have nothing to hunt and are not the
    first talk-only quest of their run, so their "Mid-quest save and restart" row is "-". The between-quests restart
    of 1013-1019 (after 1015, with 1016-1019 not yet accepted) belongs to no quest and shows in no row; it is checked
    as `between: ...` in that chain's report. The clean-character playthrough also restarts the process with 1007,
    1008, 1009, 1010, 1011 and 1012 in progress ([PLAYTHROUGH_REPORT.md](PLAYTHROUGH_REPORT.md)).

Notes on reading the tables:

- **Objective progress** is counted from the last restart: a "5 -> 10 of 10" row means the first half was collected
  before the mid-quest save and restart (shown in the next row) and the second half after it.
- **Setup** lists the console commands each chain ran before strict mode; "none" means the chain was strict from
  character creation.
- **Random rewards are draws, not picks:** 1008 draws one of seven hats and 1011 one of two knives
  (`rewards.random`), seeded by `--seed`. The bag check accepts exactly one item of the group; the
  `rewards_received` record must name the same item.
- Runs of one seed can still differ in their physics (see PLAYTEST_HARNESS.md "Findings"), so each table is one
  sample per seed; the verdicts were the same on all three.

## History on this build

- **Final evidence run (`c4e9ac5`, the final build):** the result above. The tables below are generated from it.
- **Before this package's fixes (harness as merged in wave 1, integrated build):** seed 1 20/20, seed 3 20/20, seed 2
  17/20. On seed 2 the 1006,1009,1010 chain failed its trail hop from Snail Hunting Ground I to II: a Snail on a ledge
  1 m above the path touched the player, the survival guard stopped the walk to fight back, the fight back could not
  reach it without a chase, and the walk was stopped again at once, 24 times in 2 s of game time. A harness defect,
  not a game one: `PlaytestKit` now shuns a monster a fight back cannot reach for 4 s (`SHUN_S`). The same chain on
  seed 2 then passed, and so did the three seeds below.
- **1012 with real Wooden Boxes:** 1012 passes on every seed with the breakables runtime: the box broken before the
  accept drops none of the gated items, each box breaks after the canonical 4 landed hits, three boxes give the 3 Rusty
  Screws and 3 Old Wooden Boards, and the turn-in gives exactly 100 EXP, 150 mesos and The Green Relaxer.
- **First evidence run on this harness (`r1`, commit `ee0a209`):** 20/20 on seeds 1, 2 and 3. Between that run and the
  one reported here `PlaytestKit.break_box` changed (a tier-aware approach; see PLAYTHROUGH_REPORT.md), so every seed
  was run again.
- **Review re-run (the package's final harness, `5bf2687`):** 20/20 on seeds 1, 2 and 3, every chain strict ok, 0
  warnings; 523, 523 and 520 quest checks; 2,046 / 2,314 / 1,952 game s and 331 / 421 / 313 wall s summed over the
  chains (other runs in parallel on the machine); 1008 drew 713 Green / 712 Black / 713 Green Headband and 1011 the
  Fruit Knife each time; the drop tags are the schema-v2 slugs (`drop:3/blue-snail-shell`,
  `drop:9/orange-mushroom-cap`). Seed 3's 1009 has 3 checks fewer: its 5 Red Snails were all killed during the Blue
  Snail and Shroom hunts, so the Red Snail objective needed no hunt of its own (the walk, kill and Quest Log row
  checks of that objective did not run). The quest runner now records such an objective in the evidence as
  "already 5 of 5", as it does for an item already held.

## Per quest, per seed

Generated by `PlaytestQuestSummary --combine` from the three runs' `quests.json`: the verdict of each quest (with its
number of quest checks), each chain's run, then one table per quest with what each run showed.

| Quest | Name | Chain | seed 1 | seed 2 | seed 3 |
|---|---|---|---|---|---|
| 1000 | Borrowing Sera's Mirror | 1000-1001 | PASS (25) | PASS (25) | PASS (25) |
| 1001 | Bringing a Mirror to Heena | 1000-1001 | PASS (20) | PASS (20) | PASS (20) |
| 1002 | Roger's Apple | 1002 | PASS (25) | PASS (25) | PASS (25) |
| 1003 | What Sen wants to eat | 1003-1004 | PASS (25) | PASS (25) | PASS (25) |
| 1004 | Returning to Nina | 1003-1004 | PASS (19) | PASS (19) | PASS (19) |
| 1005 | Todd's How-to-Hunt | 1005 | PASS (27) | PASS (27) | PASS (27) |
| 1006 | Sam's Suggestion | 1006,1009,1010 | PASS (29) | PASS (29) | PASS (29) |
| 1009 | Mai's Training | 1006,1009,1010 | PASS (33) | PASS (36) | PASS (36) |
| 1010 | Mai's Final Training | 1006,1009,1010 | PASS (28) | PASS (28) | PASS (28) |
| 1007 | Letter for Lucas | 1007-1008 | PASS (27) | PASS (27) | PASS (27) |
| 1008 | Lucas's Reply | 1007-1008 | PASS (21) | PASS (21) | PASS (21) |
| 1011 | Biggs's Collection of Items | 1011 | PASS (30) | PASS (30) | PASS (30) |
| 1012 | Pio's Collecting Recycled Goods | 1012 | PASS (33) | PASS (33) | PASS (33) |
| 1013 | Rain's Maple Quiz 1 | 1013-1019 | PASS (30) | PASS (30) | PASS (30) |
| 1014 | Rain's Maple Quiz 2 | 1013-1019 | PASS (25) | PASS (25) | PASS (25) |
| 1015 | Rain's Maple Quiz 3 | 1013-1019 | PASS (25) | PASS (25) | PASS (25) |
| 1016 | Rain's Maple Quiz 4 | 1013-1019 | PASS (25) | PASS (25) | PASS (25) |
| 1017 | Rain's Maple Quiz 5 | 1013-1019 | PASS (25) | PASS (25) | PASS (25) |
| 1018 | Rain's Maple Quiz 6 | 1013-1019 | PASS (25) | PASS (25) | PASS (25) |
| 1019 | Rain's Maple Quiz 7 | 1013-1019 | PASS (23) | PASS (23) | PASS (23) |

| Chain | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| 1000-1001 | PASS, strict ok, 0 setup console, 3 phases, 90 game s / 12 wall s | PASS, strict ok, 0 setup console, 3 phases, 93 game s / 12 wall s | PASS, strict ok, 0 setup console, 3 phases, 98 game s / 12 wall s |
| 1002 | PASS, strict ok, 1 setup console, 3 phases, 65 game s / 10 wall s | PASS, strict ok, 1 setup console, 3 phases, 68 game s / 9 wall s | PASS, strict ok, 1 setup console, 3 phases, 62 game s / 10 wall s |
| 1003-1004 | PASS, strict ok, 1 setup console, 3 phases, 113 game s / 13 wall s | PASS, strict ok, 1 setup console, 3 phases, 119 game s / 13 wall s | PASS, strict ok, 1 setup console, 3 phases, 119 game s / 12 wall s |
| 1005 | PASS, strict ok, 1 setup console, 3 phases, 105 game s / 12 wall s | PASS, strict ok, 1 setup console, 3 phases, 119 game s / 13 wall s | PASS, strict ok, 1 setup console, 3 phases, 107 game s / 11 wall s |
| 1006,1009,1010 | PASS, strict ok, 1 setup console, 6 phases, 741 game s / 105 wall s | PASS, strict ok, 1 setup console, 6 phases, 705 game s / 98 wall s | PASS, strict ok, 1 setup console, 6 phases, 695 game s / 92 wall s |
| 1007-1008 | PASS, strict ok, 2 setup console, 3 phases, 391 game s / 53 wall s | PASS, strict ok, 2 setup console, 3 phases, 428 game s / 58 wall s | PASS, strict ok, 2 setup console, 3 phases, 344 game s / 46 wall s |
| 1011 | PASS, strict ok, 2 setup console, 3 phases, 541 game s / 73 wall s | PASS, strict ok, 2 setup console, 3 phases, 749 game s / 104 wall s | PASS, strict ok, 2 setup console, 3 phases, 402 game s / 46 wall s |
| 1012 | PASS, strict ok, 2 setup console, 3 phases, 107 game s / 12 wall s | PASS, strict ok, 2 setup console, 3 phases, 107 game s / 12 wall s | PASS, strict ok, 2 setup console, 3 phases, 112 game s / 12 wall s |
| 1013-1019 | PASS, strict ok, 2 setup console, 4 phases, 100 game s / 19 wall s | PASS, strict ok, 2 setup console, 4 phases, 97 game s / 19 wall s | PASS, strict ok, 2 setup console, 4 phases, 108 game s / 18 wall s |

### 1000 Borrowing Sera's Mirror

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Heena's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Heena's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Heena's marker 'available' (engine 'available') at level 1; Quest Log Available yes |
| Acceptance | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Talk to Sera | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Talk to Sera | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Talk to Sera |
| Objectives | talk only | talk only | talk only |
| Completion | Sera's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Sera's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Sera's marker 'completable'; completed at level 1 (phase 2); Completed tab yes |
| Rewards | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 |
| Random reward | - | - | - |
| rewards_received | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1001 available at level 1 (min 1), marker 'available' | 1001 available at level 1 (min 1), marker 'available' | 1001 available at level 1 (min 1), marker 'available' |
| Mid-quest save and restart | after the accept in 000000001 (phase 1 -> 2): progress restored; Quest Log after: Talk to Sera | after the accept in 000000001 (phase 1 -> 2): progress restored; Quest Log after: Talk to Sera | after the accept in 000000001 (phase 1 -> 2): progress restored; Quest Log after: Talk to Sera |
| Setup | none: strict after character creation | none: strict after character creation | none: strict after character creation |

### 1001 Bringing a Mirror to Heena

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Sera's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Sera's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Sera's marker 'available' (engine 'available') at level 1; Quest Log Available yes |
| Acceptance | accepted at level 1 (phase 2); marker after 'in_progress'; Quest Log: Sera's Mirror 1/1 [x]; Return to Heena; accept items: 438 Sera's Mirror x1 (held 1, was 0) | accepted at level 1 (phase 2); marker after 'in_progress'; Quest Log: Sera's Mirror 1/1 [x]; Return to Heena; accept items: 438 Sera's Mirror x1 (held 1, was 0) | accepted at level 1 (phase 2); marker after 'in_progress'; Quest Log: Sera's Mirror 1/1 [x]; Return to Heena; accept items: 438 Sera's Mirror x1 (held 1, was 0) |
| Objectives | talk only | talk only | talk only |
| Completion | Heena's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Heena's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Heena's marker 'completable'; completed at level 1 (phase 2); Completed tab yes |
| Rewards | EXP +2 (canonical 2), mesos +0 (canonical 0), bag 438 Sera's Mirror -1; level 1 -> 1 | EXP +2 (canonical 2), mesos +0 (canonical 0), bag 438 Sera's Mirror -1; level 1 -> 1 | EXP +2 (canonical 2), mesos +0 (canonical 0), bag 438 Sera's Mirror -1; level 1 -> 1 |
| Random reward | - | - | - |
| rewards_received | { "exp": 2, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 2, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 2, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | - | - | - |
| Setup | none: strict after character creation | none: strict after character creation | none: strict after character creation |

### 1002 Roger's Apple

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Roger's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Roger's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Roger's marker 'available' (engine 'available') at level 1; Quest Log Available yes |
| Acceptance | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Use Roger's Apple 0/1; Return to Roger; accept items: 235 Roger's Apple x1 (held 1, was 0) (MisoStory adaptation) | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Use Roger's Apple 0/1; Return to Roger; accept items: 235 Roger's Apple x1 (held 1, was 0) (MisoStory adaptation) | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Use Roger's Apple 0/1; Return to Roger; accept items: 235 Roger's Apple x1 (held 1, was 0) (MisoStory adaptation) |
| Objectives | use Roger's Apple x1 in 000000010: 0 -> 1 of 1 | use Roger's Apple x1 in 000000010: 0 -> 1 of 1 | use Roger's Apple x1 in 000000010: 0 -> 1 of 1 |
| Completion | Roger's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Roger's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Roger's marker 'completable'; completed at level 1 (phase 2); Completed tab yes |
| Rewards | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 |
| Random reward | - | - | - |
| rewards_received | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | after the accept in 000000010 (phase 1 -> 2): progress restored; Quest Log after: Use Roger's Apple 0/1; Return to Roger | after the accept in 000000010 (phase 1 -> 2): progress restored; Quest Log after: Use Roger's Apple 0/1; Return to Roger | after the accept in 000000010 (phase 1 -> 2): progress restored; Quest Log after: Use Roger's Apple 0/1; Return to Roger |
| Setup | 1 console step(s) before strict mode (after the setup save): warp 000000010 | 1 console step(s) before strict mode (after the setup save): warp 000000010 | 1 console step(s) before strict mode (after the setup save): warp 000000010 |

### 1003 What Sen wants to eat

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Nina's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Nina's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Nina's marker 'available' (engine 'available') at level 1; Quest Log Available yes |
| Acceptance | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Talk to Sen | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Talk to Sen | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Talk to Sen |
| Objectives | talk only | talk only | talk only |
| Completion | Sen's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Sen's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Sen's marker 'completable'; completed at level 1 (phase 2); Completed tab yes |
| Rewards | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 | EXP +0 (canonical 0), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 |
| Random reward | - | - | - |
| rewards_received | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1004 available at level 1 (min 1), marker 'available' | 1004 available at level 1 (min 1), marker 'available' | 1004 available at level 1 (min 1), marker 'available' |
| Mid-quest save and restart | after the accept in 000000020 (phase 1 -> 2): progress restored; Quest Log after: Talk to Sen | after the accept in 000000020 (phase 1 -> 2): progress restored; Quest Log after: Talk to Sen | after the accept in 000000020 (phase 1 -> 2): progress restored; Quest Log after: Talk to Sen |
| Setup | 1 console step(s) before strict mode (after the setup save): warp 000000020 | 1 console step(s) before strict mode (after the setup save): warp 000000020 | 1 console step(s) before strict mode (after the setup save): warp 000000020 |

### 1004 Returning to Nina

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Sen's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Sen's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Sen's marker 'available' (engine 'available') at level 1; Quest Log Available yes |
| Acceptance | accepted at level 1 (phase 2); marker after 'in_progress'; Quest Log: Return to Nina | accepted at level 1 (phase 2); marker after 'in_progress'; Quest Log: Return to Nina | accepted at level 1 (phase 2); marker after 'in_progress'; Quest Log: Return to Nina |
| Objectives | talk only | talk only | talk only |
| Completion | Nina's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Nina's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Nina's marker 'completable'; completed at level 1 (phase 2); Completed tab yes |
| Rewards | EXP +3 (canonical 3), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 | EXP +3 (canonical 3), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 | EXP +3 (canonical 3), mesos +0 (canonical 0), bag unchanged; level 1 -> 1 |
| Random reward | - | - | - |
| rewards_received | { "exp": 3, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 3, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 3, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | - | - | - |
| Setup | 1 console step(s) before strict mode (after the setup save): warp 000000020 | 1 console step(s) before strict mode (after the setup save): warp 000000020 | 1 console step(s) before strict mode (after the setup save): warp 000000020 |

### 1005 Todd's How-to-Hunt

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Todd's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Todd's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Todd's marker 'available' (engine 'available') at level 1; Quest Log Available yes |
| Acceptance | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Tutorial Jr. Sentinel 0/3; Jr. Sentinel Shellpiece 0/3; Talk to Peter | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Tutorial Jr. Sentinel 0/3; Jr. Sentinel Shellpiece 0/3; Talk to Peter | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Tutorial Jr. Sentinel 0/3; Jr. Sentinel Shellpiece 0/3; Talk to Peter |
| Objectives | kill Tutorial Jr. Sentinel x3 in 000000030: 1 -> 3 of 3; item Jr. Sentinel Shellpiece x3 in 000000030: already held 3 | kill Tutorial Jr. Sentinel x3 in 000000030: 1 -> 3 of 3; item Jr. Sentinel Shellpiece x3 in 000000030: already held 3 | kill Tutorial Jr. Sentinel x3 in 000000030: 1 -> 3 of 3; item Jr. Sentinel Shellpiece x3 in 000000030: already held 3 |
| Completion | Peter's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Peter's marker 'completable'; completed at level 1 (phase 2); Completed tab yes | Peter's marker 'completable'; completed at level 1 (phase 2); Completed tab yes |
| Rewards | EXP +10 (canonical 10), mesos +0 (canonical 0), bag 347 Jr. Sentinel Shellpiece -3; level 1 -> 1 | EXP +10 (canonical 10), mesos +0 (canonical 0), bag 347 Jr. Sentinel Shellpiece -3; level 1 -> 1 | EXP +10 (canonical 10), mesos +0 (canonical 0), bag 347 Jr. Sentinel Shellpiece -3; level 1 -> 1 |
| Random reward | - | - | - |
| rewards_received | { "exp": 10, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 10, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 10, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | at 1/3 Tutorial Jr. Sentinel in 000000030 (phase 1 -> 2): progress restored; Quest Log after: Tutorial Jr. Sentinel 1/3; Jr. Sentinel Shellpiece 1/3; Talk to Peter | at 1/3 Tutorial Jr. Sentinel in 000000030 (phase 1 -> 2): progress restored; Quest Log after: Tutorial Jr. Sentinel 1/3; Jr. Sentinel Shellpiece 1/3; Talk to Peter | at 1/3 Tutorial Jr. Sentinel in 000000030 (phase 1 -> 2): progress restored; Quest Log after: Tutorial Jr. Sentinel 1/3; Jr. Sentinel Shellpiece 1/3; Talk to Peter |
| Setup | 1 console step(s) before strict mode (after the setup save): warp 000000030 | 1 console step(s) before strict mode (after the setup save): warp 000000030 | 1 console step(s) before strict mode (after the setup save): warp 000000030 |

### 1006 Sam's Suggestion

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Sam's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Sam's marker 'available' (engine 'available') at level 1; Quest Log Available yes | Sam's marker 'available' (engine 'available') at level 1; Quest Log Available yes |
| Acceptance | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Snail 0/10; Talk to Mai | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Snail 0/10; Talk to Mai | accepted at level 1 (phase 1); marker after 'in_progress'; Quest Log: Snail 0/10; Talk to Mai |
| Objectives | kill Snail x10 in 000000040: 5 -> 10 of 10 | kill Snail x10 in 000000040: 5 -> 10 of 10 | kill Snail x10 in 000000040: 5 -> 10 of 10 |
| Completion | Mai's marker 'completable'; completed at level 3 (phase 2); Completed tab yes | Mai's marker 'completable'; completed at level 3 (phase 2); Completed tab yes | Mai's marker 'completable'; completed at level 3 (phase 2); Completed tab yes |
| Rewards | EXP +30 (canonical 30), mesos +0 (canonical 0), bag 237 Egg +3; level 2 -> 3 | EXP +30 (canonical 30), mesos +0 (canonical 0), bag 237 Egg +3; level 2 -> 3 | EXP +30 (canonical 30), mesos +0 (canonical 0), bag 237 Egg +3; level 3 -> 3 |
| Random reward | - | - | - |
| rewards_received | { "exp": 30, "mesos": 0, "items": [{ "item_id": "237", "qty": 3 }], "random_picks": [] } | { "exp": 30, "mesos": 0, "items": [{ "item_id": "237", "qty": 3 }], "random_picks": [] } | { "exp": 30, "mesos": 0, "items": [{ "item_id": "237", "qty": 3 }], "random_picks": [] } |
| Follow-ups | 1009 available at level 3 (min 3), marker 'available' | 1009 available at level 3 (min 3), marker 'available' | 1009 available at level 3 (min 3), marker 'available' |
| Mid-quest save and restart | at 5/10 Snail in 000000040 (phase 1 -> 2): progress restored; Quest Log after: Snail 5/10; Talk to Mai | at 5/10 Snail in 000000040 (phase 1 -> 2): progress restored; Quest Log after: Snail 5/10; Talk to Mai | at 5/10 Snail in 000000040 (phase 1 -> 2): progress restored; Quest Log after: Snail 5/10; Talk to Mai |
| Setup | 1 console step(s) before strict mode (after the setup save): warp 000000040 | 1 console step(s) before strict mode (after the setup save): warp 000000040 | 1 console step(s) before strict mode (after the setup save): warp 000000040 |

### 1009 Mai's Training

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Mai's marker 'available' (engine 'available') at level 3; Quest Log Available yes | Mai's marker 'available' (engine 'available') at level 3; Quest Log Available yes | Mai's marker 'available' (engine 'available') at level 3; Quest Log Available yes |
| Acceptance | accepted at level 3 (phase 3); marker after 'in_progress'; Quest Log: Blue Snail 0/10; Shroom 0/10; Red Snail 0/5; Return to Mai | accepted at level 3 (phase 3); marker after 'in_progress'; Quest Log: Blue Snail 0/10; Shroom 0/10; Red Snail 0/5; Return to Mai | accepted at level 3 (phase 3); marker after 'in_progress'; Quest Log: Blue Snail 0/10; Shroom 0/10; Red Snail 0/5; Return to Mai |
| Objectives | kill Blue Snail x10 in 000000050: 5 -> 10 of 10; kill Shroom x10 in 000000050: 0 -> 10 of 10; kill Red Snail x5 in 000000050: already 5 of 5 (killed in the earlier hunts) | kill Blue Snail x10 in 000000050: 5 -> 10 of 10; kill Shroom x10 in 000000050: 0 -> 10 of 10; kill Red Snail x5 in 000000050: 3 -> 5 of 5 | kill Blue Snail x10 in 000000050: 5 -> 10 of 10; kill Shroom x10 in 000000050: 0 -> 10 of 10; kill Red Snail x5 in 000000050: 4 -> 5 of 5 |
| Completion | Mai's marker 'completable'; completed at level 5 (phase 4); Completed tab yes | Mai's marker 'completable'; completed at level 5 (phase 4); Completed tab yes | Mai's marker 'completable'; completed at level 5 (phase 4); Completed tab yes |
| Rewards | EXP +70 (canonical 70), mesos +0 (canonical 0), bag 237 Egg +5; level 5 -> 5 | EXP +70 (canonical 70), mesos +0 (canonical 0), bag 237 Egg +5; level 5 -> 5 | EXP +70 (canonical 70), mesos +0 (canonical 0), bag 237 Egg +5; level 5 -> 5 |
| Random reward | - | - | - |
| rewards_received | { "exp": 70, "mesos": 0, "items": [{ "item_id": "237", "qty": 5 }], "random_picks": [] } | { "exp": 70, "mesos": 0, "items": [{ "item_id": "237", "qty": 5 }], "random_picks": [] } | { "exp": 70, "mesos": 0, "items": [{ "item_id": "237", "qty": 5 }], "random_picks": [] } |
| Follow-ups | 1010 available at level 5 (min 1), marker 'available' | 1010 available at level 5 (min 1), marker 'available' | 1010 available at level 5 (min 1), marker 'available' |
| Mid-quest save and restart | at 5/10 Blue Snail in 000000050 (phase 3 -> 4): progress restored; Quest Log after: Blue Snail 5/10; Shroom 0/10; Red Snail 2/5; Return to Mai | at 5/10 Blue Snail in 000000050 (phase 3 -> 4): progress restored; Quest Log after: Blue Snail 5/10; Shroom 0/10; Red Snail 0/5; Return to Mai | at 5/10 Blue Snail in 000000050 (phase 3 -> 4): progress restored; Quest Log after: Blue Snail 5/10; Shroom 0/10; Red Snail 2/5; Return to Mai |
| Setup | 1 console step(s) before strict mode (after the setup save): warp 000000040 | 1 console step(s) before strict mode (after the setup save): warp 000000040 | 1 console step(s) before strict mode (after the setup save): warp 000000040 |

### 1010 Mai's Final Training

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Mai's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Mai's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Mai's marker 'available' (engine 'available') at level 5; Quest Log Available yes |
| Acceptance | accepted at level 5 (phase 4); marker after 'in_progress'; Quest Log: Orange Mushroom 0/1; Return to Mai | accepted at level 5 (phase 4); marker after 'in_progress'; Quest Log: Orange Mushroom 0/1; Return to Mai | accepted at level 5 (phase 4); marker after 'in_progress'; Quest Log: Orange Mushroom 0/1; Return to Mai |
| Objectives | kill Orange Mushroom x1 in 000001000: 0 -> 1 of 1 | kill Orange Mushroom x1 in 000001000: 0 -> 1 of 1 | kill Orange Mushroom x1 in 000001000: 0 -> 1 of 1 |
| Completion | Mai's marker 'completable'; completed at level 6 (phase 5); Completed tab yes | Mai's marker 'completable'; completed at level 6 (phase 5); Completed tab yes | Mai's marker 'completable'; completed at level 6 (phase 5); Completed tab yes |
| Rewards | EXP +100 (canonical 100), mesos +150 (canonical 150), bag 237 Egg +10; level 6 -> 6 | EXP +100 (canonical 100), mesos +150 (canonical 150), bag 237 Egg +10; level 5 -> 6 | EXP +100 (canonical 100), mesos +150 (canonical 150), bag 237 Egg +10; level 6 -> 6 |
| Random reward | - | - | - |
| rewards_received | { "exp": 100, "mesos": 150, "items": [{ "item_id": "237", "qty": 10 }], "random_picks": [] } | { "exp": 100, "mesos": 150, "items": [{ "item_id": "237", "qty": 10 }], "random_picks": [] } | { "exp": 100, "mesos": 150, "items": [{ "item_id": "237", "qty": 10 }], "random_picks": [] } |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | at 0/1 Orange Mushroom in 000001000 (phase 4 -> 5): progress restored; Quest Log after: Orange Mushroom 0/1; Return to Mai | at 0/1 Orange Mushroom in 000001000 (phase 4 -> 5): progress restored; Quest Log after: Orange Mushroom 0/1; Return to Mai | at 0/1 Orange Mushroom in 000001000 (phase 4 -> 5): progress restored; Quest Log after: Orange Mushroom 0/1; Return to Mai |
| Setup | 1 console step(s) before strict mode (after the setup save): warp 000000040 | 1 console step(s) before strict mode (after the setup save): warp 000000040 | 1 console step(s) before strict mode (after the setup save): warp 000000040 |

### 1007 Letter for Lucas

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | refused at level 1; Maria's marker 'available' (engine 'available') at level 2; Quest Log Available yes | refused at level 1; Maria's marker 'available' (engine 'available') at level 2; Quest Log Available yes | refused at level 1; Maria's marker 'available' (engine 'available') at level 2; Quest Log Available yes |
| Acceptance | accepted at level 2 (phase 1); marker after 'in_progress'; Quest Log: Maria's Letter 1/1 [x]; Talk to Lucas; accept items: 439 Maria's Letter x1 (held 1, was 0) | accepted at level 2 (phase 1); marker after 'in_progress'; Quest Log: Maria's Letter 1/1 [x]; Talk to Lucas; accept items: 439 Maria's Letter x1 (held 1, was 0) | accepted at level 2 (phase 1); marker after 'in_progress'; Quest Log: Maria's Letter 1/1 [x]; Talk to Lucas; accept items: 439 Maria's Letter x1 (held 1, was 0) |
| Objectives | talk only | talk only | talk only |
| Completion | Lucas's marker 'completable'; completed at level 3 (phase 2); Completed tab yes | Lucas's marker 'completable'; completed at level 3 (phase 2); Completed tab yes | Lucas's marker 'completable'; completed at level 3 (phase 2); Completed tab yes |
| Rewards | EXP +0 (canonical 0), mesos +0 (canonical 0), bag 439 Maria's Letter -1; level 3 -> 3 | EXP +0 (canonical 0), mesos +0 (canonical 0), bag 439 Maria's Letter -1; level 3 -> 3 | EXP +0 (canonical 0), mesos +0 (canonical 0), bag 439 Maria's Letter -1; level 3 -> 3 |
| Random reward | - | - | - |
| rewards_received | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 0, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1008 available at level 3 (min 1), marker 'available' | 1008 available at level 3 (min 1), marker 'available' | 1008 available at level 3 (min 1), marker 'available' |
| Mid-quest save and restart | after the accept in 000000050 (phase 1 -> 2): progress restored; Quest Log after: Maria's Letter 1/1 [x]; Talk to Lucas | after the accept in 000000050 (phase 1 -> 2): progress restored; Quest Log after: Maria's Letter 1/1 [x]; Talk to Lucas | after the accept in 000000050 (phase 1 -> 2): progress restored; Quest Log after: Maria's Letter 1/1 [x]; Talk to Lucas |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000000050; level 2 | 2 console step(s) before strict mode (after the setup save): warp 000000050; level 2 | 2 console step(s) before strict mode (after the setup save): warp 000000050; level 2 |

### 1008 Lucas's Reply

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Lucas's marker 'available' (engine 'available') at level 3; Quest Log Available yes | Lucas's marker 'available' (engine 'available') at level 3; Quest Log Available yes | Lucas's marker 'available' (engine 'available') at level 3; Quest Log Available yes |
| Acceptance | accepted at level 3 (phase 2); marker after 'in_progress'; Quest Log: Lucas's Letter 1/1 [x]; Return to Maria; accept items: 440 Lucas's Letter x1 (held 1, was 0) | accepted at level 3 (phase 2); marker after 'in_progress'; Quest Log: Lucas's Letter 1/1 [x]; Return to Maria; accept items: 440 Lucas's Letter x1 (held 1, was 0) | accepted at level 3 (phase 2); marker after 'in_progress'; Quest Log: Lucas's Letter 1/1 [x]; Return to Maria; accept items: 440 Lucas's Letter x1 (held 1, was 0) |
| Objectives | talk only | talk only | talk only |
| Completion | Maria's marker 'completable'; completed at level 4 (phase 2); Completed tab yes | Maria's marker 'completable'; completed at level 4 (phase 2); Completed tab yes | Maria's marker 'completable'; completed at level 4 (phase 2); Completed tab yes |
| Rewards | EXP +50 (canonical 50), mesos +0 (canonical 0), bag 440 Lucas's Letter -1, 712 Black Headband +1; level 3 -> 4 | EXP +50 (canonical 50), mesos +0 (canonical 0), bag 440 Lucas's Letter -1, 715 Blue Headband +1; level 3 -> 4 | EXP +50 (canonical 50), mesos +0 (canonical 0), bag 440 Lucas's Letter -1, 709 Green Skullcap +1; level 3 -> 4 |
| Random reward | 712 Black Headband | 715 Blue Headband | 709 Green Skullcap |
| rewards_received | { "exp": 50, "mesos": 0, "items": [{ "item_id": "712", "qty": 1 }], "random_picks": [{ "group": 0, "item_id": "712", "qty": 1 }] } (matches the pick) | { "exp": 50, "mesos": 0, "items": [{ "item_id": "715", "qty": 1 }], "random_picks": [{ "group": 0, "item_id": "715", "qty": 1 }] } (matches the pick) | { "exp": 50, "mesos": 0, "items": [{ "item_id": "709", "qty": 1 }], "random_picks": [{ "group": 0, "item_id": "709", "qty": 1 }] } (matches the pick) |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | - | - | - |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000000050; level 2 | 2 console step(s) before strict mode (after the setup save): warp 000000050; level 2 | 2 console step(s) before strict mode (after the setup save): warp 000000050; level 2 |

### 1011 Biggs's Collection of Items

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | refused at level 1; Biggs's marker 'available' (engine 'available') at level 3; Quest Log Available yes | refused at level 1; Biggs's marker 'available' (engine 'available') at level 3; Quest Log Available yes | refused at level 1; Biggs's marker 'available' (engine 'available') at level 3; Quest Log Available yes |
| Acceptance | accepted at level 3 (phase 1); marker after 'in_progress'; Quest Log: Blue Snail Shell 0/10; Orange Mushroom Cap 0/1; Return to Biggs | accepted at level 3 (phase 1); marker after 'in_progress'; Quest Log: Blue Snail Shell 0/10; Orange Mushroom Cap 0/1; Return to Biggs | accepted at level 3 (phase 1); marker after 'in_progress'; Quest Log: Blue Snail Shell 0/10; Orange Mushroom Cap 0/1; Return to Biggs |
| Objectives | item Blue Snail Shell x10 in 000000050: 6 -> 10 of 10 from monster Blue Snail (chance 1.0); item Orange Mushroom Cap x1 in 000001000: 0 -> 1 of 1 from monster Orange Mushroom (chance 1.0) | item Blue Snail Shell x10 in 000000050: 5 -> 10 of 10 from monster Blue Snail (chance 1.0); item Orange Mushroom Cap x1 in 000001000: 0 -> 1 of 1 from monster Orange Mushroom (chance 1.0) | item Blue Snail Shell x10 in 000000050: 5 -> 10 of 10 from monster Blue Snail (chance 1.0); item Orange Mushroom Cap x1 in 000001000: 0 -> 1 of 1 from monster Orange Mushroom (chance 1.0) |
| Completion | Biggs's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Biggs's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Biggs's marker 'completable'; completed at level 5 (phase 2); Completed tab yes |
| Rewards | EXP +70 (canonical 70), mesos +0 (canonical 0), bag 349 Blue Snail Shell -10, 356 Orange Mushroom Cap -1, 559 Fruit Knife +1; level 4 -> 5 | EXP +70 (canonical 70), mesos +0 (canonical 0), bag 349 Blue Snail Shell -10, 356 Orange Mushroom Cap -1, 559 Fruit Knife +1; level 4 -> 5 | EXP +70 (canonical 70), mesos +0 (canonical 0), bag 349 Blue Snail Shell -10, 356 Orange Mushroom Cap -1, 559 Fruit Knife +1; level 4 -> 5 |
| Random reward | 559 Fruit Knife | 559 Fruit Knife | 559 Fruit Knife |
| rewards_received | { "exp": 70, "mesos": 0, "items": [{ "item_id": "559", "qty": 1 }], "random_picks": [{ "group": 0, "item_id": "559", "qty": 1 }] } (matches the pick) | { "exp": 70, "mesos": 0, "items": [{ "item_id": "559", "qty": 1 }], "random_picks": [{ "group": 0, "item_id": "559", "qty": 1 }] } (matches the pick) | { "exp": 70, "mesos": 0, "items": [{ "item_id": "559", "qty": 1 }], "random_picks": [{ "group": 0, "item_id": "559", "qty": 1 }] } (matches the pick) |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | at 6/10 Blue Snail Shell in 000000050 (phase 1 -> 2): progress restored; Quest Log after: Blue Snail Shell 6/10; Orange Mushroom Cap 0/1; Return to Biggs | at 5/10 Blue Snail Shell in 000000050 (phase 1 -> 2): progress restored; Quest Log after: Blue Snail Shell 5/10; Orange Mushroom Cap 0/1; Return to Biggs | at 5/10 Blue Snail Shell in 000000050 (phase 1 -> 2): progress restored; Quest Log after: Blue Snail Shell 5/10; Orange Mushroom Cap 0/1; Return to Biggs |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000000060; level 3 | 2 console step(s) before strict mode (after the setup save): warp 000000060; level 3 | 2 console step(s) before strict mode (after the setup save): warp 000000060; level 3 |

### 1012 Pio's Collecting Recycled Goods

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | refused at level 1; Pio's marker 'available' (engine 'available') at level 5; Quest Log Available yes; box 000001010:1 broken before the accept, gained '' | refused at level 1; Pio's marker 'available' (engine 'available') at level 5; Quest Log Available yes; box 000001010:1 broken before the accept, gained '' | refused at level 1; Pio's marker 'available' (engine 'available') at level 5; Quest Log Available yes; box 000001010:1 broken before the accept, gained '' |
| Acceptance | accepted at level 5 (phase 1); marker after 'in_progress'; Quest Log: Rusty Screw 0/3; Old Wooden Board 0/3; Return to Pio | accepted at level 5 (phase 1); marker after 'in_progress'; Quest Log: Rusty Screw 0/3; Old Wooden Board 0/3; Return to Pio | accepted at level 5 (phase 1); marker after 'in_progress'; Quest Log: Rusty Screw 0/3; Old Wooden Board 0/3; Return to Pio |
| Objectives | item Rusty Screw x3 in 000001010: 1 -> 3 of 3 from breakable Wooden Box (chance 1.0); item Old Wooden Board x3 in 000001010: already held 3; 3 Wooden Boxes broken | item Rusty Screw x3 in 000001010: 1 -> 3 of 3 from breakable Wooden Box (chance 1.0); item Old Wooden Board x3 in 000001010: already held 3; 3 Wooden Boxes broken | item Rusty Screw x3 in 000001010: 1 -> 3 of 3 from breakable Wooden Box (chance 1.0); item Old Wooden Board x3 in 000001010: already held 3; 3 Wooden Boxes broken |
| Completion | Pio's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Pio's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Pio's marker 'completable'; completed at level 5 (phase 2); Completed tab yes |
| Rewards | EXP +100 (canonical 100), mesos +150 (canonical 150), bag 442 Old Wooden Board -3, 441 Rusty Screw -3, 522 The Green Relaxer +1; level 5 -> 5 | EXP +100 (canonical 100), mesos +150 (canonical 150), bag 442 Old Wooden Board -3, 441 Rusty Screw -3, 522 The Green Relaxer +1; level 5 -> 5 | EXP +100 (canonical 100), mesos +150 (canonical 150), bag 442 Old Wooden Board -3, 441 Rusty Screw -3, 522 The Green Relaxer +1; level 5 -> 5 |
| Random reward | - | - | - |
| rewards_received | { "exp": 100, "mesos": 150, "items": [{ "item_id": "522", "qty": 1 }], "random_picks": [] } | { "exp": 100, "mesos": 150, "items": [{ "item_id": "522", "qty": 1 }], "random_picks": [] } | { "exp": 100, "mesos": 150, "items": [{ "item_id": "522", "qty": 1 }], "random_picks": [] } |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | at 1/3 Rusty Screw in 000001010 (phase 1 -> 2): progress restored; Quest Log after: Rusty Screw 1/3; Old Wooden Board 1/3; Return to Pio | at 1/3 Rusty Screw in 000001010 (phase 1 -> 2): progress restored; Quest Log after: Rusty Screw 1/3; Old Wooden Board 1/3; Return to Pio | at 1/3 Rusty Screw in 000001010 (phase 1 -> 2): progress restored; Quest Log after: Rusty Screw 1/3; Old Wooden Board 1/3; Return to Pio |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 |

### 1013 Rain's Maple Quiz 1

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | refused at level 1; Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | refused at level 1; Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | refused at level 1; Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes |
| Acceptance | accepted at level 5 (phase 1); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 1); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 1); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz |
| Objectives | quiz 'What key should you press in front of a ladder or rope to ha': wrong 'left arrow key' kept it in progress, then 'up arrow key' (meowdb_marker) completed it | quiz 'What key should you press in front of a ladder or rope to ha': wrong 'left arrow key' kept it in progress, then 'up arrow key' (meowdb_marker) completed it | quiz 'What key should you press in front of a ladder or rope to ha': wrong 'left arrow key' kept it in progress, then 'up arrow key' (meowdb_marker) completed it |
| Completion | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes |
| Rewards | EXP +20 (canonical 20), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 | EXP +20 (canonical 20), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 | EXP +20 (canonical 20), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 |
| Random reward | - | - | - |
| rewards_received | { "exp": 20, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 20, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 20, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1014 available at level 5 (min 5), marker 'available' | 1014 available at level 5 (min 5), marker 'available' | 1014 available at level 5 (min 5), marker 'available' |
| Mid-quest save and restart | after the accept in 000001010 (phase 1 -> 2): progress restored; Quest Log after: Return to Rain; Answer the quiz | after the accept in 000001010 (phase 1 -> 2): progress restored; Quest Log after: Return to Rain; Answer the quiz | after the accept in 000001010 (phase 1 -> 2): progress restored; Quest Log after: Return to Rain; Answer the quiz |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 |

### 1014 Rain's Maple Quiz 2

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes |
| Acceptance | accepted at level 5 (phase 2); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 2); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 2); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz |
| Objectives | quiz 'Can you wear an item just by double-clicking it with your mo': wrong 'No way.' kept it in progress, then 'Oh yes' (meowdb_marker) completed it | quiz 'Can you wear an item just by double-clicking it with your mo': wrong 'No way.' kept it in progress, then 'Oh yes' (meowdb_marker) completed it | quiz 'Can you wear an item just by double-clicking it with your mo': wrong 'No way.' kept it in progress, then 'Oh yes' (meowdb_marker) completed it |
| Completion | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes |
| Rewards | EXP +25 (canonical 25), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 | EXP +25 (canonical 25), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 | EXP +25 (canonical 25), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 |
| Random reward | - | - | - |
| rewards_received | { "exp": 25, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 25, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 25, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1015 available at level 5 (min 5), marker 'available' | 1015 available at level 5 (min 5), marker 'available' | 1015 available at level 5 (min 5), marker 'available' |
| Mid-quest save and restart | - | - | - |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 |

### 1015 Rain's Maple Quiz 3

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes |
| Acceptance | accepted at level 5 (phase 2); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 2); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 2); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz |
| Objectives | quiz 'What window can you use to check the items you're wearing?': wrong 'Character Stat' kept it in progress, then 'Equipment Inventory' (meowdb_marker) completed it | quiz 'What window can you use to check the items you're wearing?': wrong 'Character Stat' kept it in progress, then 'Equipment Inventory' (meowdb_marker) completed it | quiz 'What window can you use to check the items you're wearing?': wrong 'Character Stat' kept it in progress, then 'Equipment Inventory' (meowdb_marker) completed it |
| Completion | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes | Rain's marker 'completable'; completed at level 5 (phase 2); Completed tab yes |
| Rewards | EXP +30 (canonical 30), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 | EXP +30 (canonical 30), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 | EXP +30 (canonical 30), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 |
| Random reward | - | - | - |
| rewards_received | { "exp": 30, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 30, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 30, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1016 available at level 5 (min 5), marker 'available' | 1016 available at level 5 (min 5), marker 'available' | 1016 available at level 5 (min 5), marker 'available' |
| Mid-quest save and restart | - | - | - |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 |

### 1016 Rain's Maple Quiz 4

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes |
| Acceptance | accepted at level 5 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz |
| Objectives | quiz 'Which of the following is not a correct way to recover healt': wrong 'Sit on a chair' kept it in progress, then 'Sleep' (meowdb_marker) completed it | quiz 'Which of the following is not a correct way to recover healt': wrong 'Sit on a chair' kept it in progress, then 'Sleep' (meowdb_marker) completed it | quiz 'Which of the following is not a correct way to recover healt': wrong 'Sit on a chair' kept it in progress, then 'Sleep' (meowdb_marker) completed it |
| Completion | Rain's marker 'completable'; completed at level 5 (phase 3); Completed tab yes | Rain's marker 'completable'; completed at level 5 (phase 3); Completed tab yes | Rain's marker 'completable'; completed at level 5 (phase 3); Completed tab yes |
| Rewards | EXP +35 (canonical 35), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 | EXP +35 (canonical 35), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 | EXP +35 (canonical 35), mesos +0 (canonical 0), bag unchanged; level 5 -> 5 |
| Random reward | - | - | - |
| rewards_received | { "exp": 35, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 35, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 35, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1017 available at level 5 (min 5), marker 'available' | 1017 available at level 5 (min 5), marker 'available' | 1017 available at level 5 (min 5), marker 'available' |
| Mid-quest save and restart | - | - | - |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 |

### 1017 Rain's Maple Quiz 5

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 5; Quest Log Available yes |
| Acceptance | accepted at level 5 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 5 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz |
| Objectives | quiz 'In order to make the job advancement as a Warrior, Bowman, o': wrong 'Level 8' kept it in progress, then 'Level 10' (meowdb_marker) completed it | quiz 'In order to make the job advancement as a Warrior, Bowman, o': wrong 'Level 8' kept it in progress, then 'Level 10' (meowdb_marker) completed it | quiz 'In order to make the job advancement as a Warrior, Bowman, o': wrong 'Level 8' kept it in progress, then 'Level 10' (meowdb_marker) completed it |
| Completion | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes |
| Rewards | EXP +40 (canonical 40), mesos +0 (canonical 0), bag unchanged; level 5 -> 6 | EXP +40 (canonical 40), mesos +0 (canonical 0), bag unchanged; level 5 -> 6 | EXP +40 (canonical 40), mesos +0 (canonical 0), bag unchanged; level 5 -> 6 |
| Random reward | - | - | - |
| rewards_received | { "exp": 40, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 40, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 40, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1018 available at level 6 (min 5), marker 'available' | 1018 available at level 6 (min 5), marker 'available' | 1018 available at level 6 (min 5), marker 'available' |
| Mid-quest save and restart | - | - | - |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 |

### 1018 Rain's Maple Quiz 6

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Rain's marker 'available' (engine 'available') at level 6; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 6; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 6; Quest Log Available yes |
| Acceptance | accepted at level 6 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 6 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 6 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz |
| Objectives | quiz 'If you keep up with your adventures, you can level up and ea': wrong '1 point' kept it in progress, then '5 points' (inferred_from_meowdb_responses) completed it | quiz 'If you keep up with your adventures, you can level up and ea': wrong '1 point' kept it in progress, then '5 points' (inferred_from_meowdb_responses) completed it | quiz 'If you keep up with your adventures, you can level up and ea': wrong '1 point' kept it in progress, then '5 points' (inferred_from_meowdb_responses) completed it |
| Completion | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes |
| Rewards | EXP +45 (canonical 45), mesos +0 (canonical 0), bag unchanged; level 6 -> 6 | EXP +45 (canonical 45), mesos +0 (canonical 0), bag unchanged; level 6 -> 6 | EXP +45 (canonical 45), mesos +0 (canonical 0), bag unchanged; level 6 -> 6 |
| Random reward | - | - | - |
| rewards_received | { "exp": 45, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 45, "mesos": 0, "items": [], "random_picks": [] } | { "exp": 45, "mesos": 0, "items": [], "random_picks": [] } |
| Follow-ups | 1019 available at level 6 (min 5), marker 'available' | 1019 available at level 6 (min 5), marker 'available' | 1019 available at level 6 (min 5), marker 'available' |
| Mid-quest save and restart | - | - | - |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 |

### 1019 Rain's Maple Quiz 7

| | seed 1 | seed 2 | seed 3 |
|---|---|---|---|
| Availability | Rain's marker 'available' (engine 'available') at level 6; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 6; Quest Log Available yes | Rain's marker 'available' (engine 'available') at level 6; Quest Log Available yes |
| Acceptance | accepted at level 6 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 6 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz | accepted at level 6 (phase 3); marker after 'completable'; Quest Log: Return to Rain; Answer the quiz |
| Objectives | quiz 'This is important! You can only make the job advancement at ': wrong 'Amherst' kept it in progress, then 'Southperry' (meowdb_marker) completed it | quiz 'This is important! You can only make the job advancement at ': wrong 'Amherst' kept it in progress, then 'Southperry' (meowdb_marker) completed it | quiz 'This is important! You can only make the job advancement at ': wrong 'Amherst' kept it in progress, then 'Southperry' (meowdb_marker) completed it |
| Completion | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes | Rain's marker 'completable'; completed at level 6 (phase 3); Completed tab yes |
| Rewards | EXP +50 (canonical 50), mesos +0 (canonical 0), bag 239 Orange +10; level 6 -> 6 | EXP +50 (canonical 50), mesos +0 (canonical 0), bag 239 Orange +10; level 6 -> 6 | EXP +50 (canonical 50), mesos +0 (canonical 0), bag 239 Orange +10; level 6 -> 6 |
| Random reward | - | - | - |
| rewards_received | { "exp": 50, "mesos": 0, "items": [{ "item_id": "239", "qty": 10 }], "random_picks": [] } | { "exp": 50, "mesos": 0, "items": [{ "item_id": "239", "qty": 10 }], "random_picks": [] } | { "exp": 50, "mesos": 0, "items": [{ "item_id": "239", "qty": 10 }], "random_picks": [] } |
| Follow-ups | none (canonical) | none (canonical) | none (canonical) |
| Mid-quest save and restart | - | - | - |
| Setup | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 | 2 console step(s) before strict mode (after the setup save): warp 000001010; level 5 |
