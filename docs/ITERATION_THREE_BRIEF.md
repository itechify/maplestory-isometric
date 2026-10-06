# MisoStory Iteration Three

> **Owner amendment (2026-10-06).** The project owner replaced this brief's drop and meso sources. The only sources of
> truth are **MeowDB MS Classic** and **Henesys.gg** (https://henesys.gg/loot, MapleStory Classic World):
>
> - **Drop membership** (monsters and the Wooden Box) is MeowDB's community list "Drops (MS Classic)" for that monster,
>   every entry; MeowDB's "MSEA reference drops" list is reference only.
> - **Rarity** is Henesys.gg's label for each item: Common, Rare, Very Rare or Extremely Rare.
> - **Drop chance** is the owner-approved MisoStory table by item category x rarity
>   (`game/data/misostory/drop_rates.json`): an adaptation (decision D3-11), not a MapleStory fact.
> - **Mesos**: MeowDB's player report where there is one; otherwise a uniform integer in [level, 2 x level] of the
>   monster's canonical level. Mesos drop with chance 60%. The Tutorial Jr. Sentinel and the Wooden Box drop none
>   (`game/data/misostory/meso_rules.json`: an adaptation, decision D3-12).
>
> Henesys.gg prohibits unauthorized reproduction or scraping of its content, so its labels are read by hand and kept
> for this private project only. The passages below that named other drop sources now state this rule. The rest of the
> brief is unchanged.

## Complete Canonical Maple Island

Iteration One built all 25 Maple Island maps as a cohesive isometric 3D world.

Iteration Two turned that world into a playable game with:

- character creation
- player movement
- jumping
- combat
- canonical MapleStory damage calculations
- EXP and leveling
- AP allocation
- monsters
- drops
- inventory
- equipment
- consumables
- mesos
- NPC interactions
- quests
- shops
- saving/loading
- death and respawning
- all 25 maps traversable
- developer tooling
- 1,145 automated tests
- 818 MeowDB formula parity checks

Iteration Three must turn that playable foundation into a **content-complete and mechanically complete Maple Island experience**.

The target is no longer:

> "Can the systems support MapleStory?"

The target is:

> "Can I start a brand-new character and play Maple Island from beginning to end with the quests, monsters, NPCs, shops, items, drops, progression, Beginner mechanics, and world behavior expected from MapleStory Classic?"

This iteration should focus on **canonical Maple Island completeness and fidelity**, not expansion to Victoria Island.

Do not build Victoria Island yet.

---

# Existing Project State

Continue from the current Iteration Two implementation.

Do not rewrite working systems unnecessarily.

Before making changes:

1. build the current project
2. run the current test suite
3. run Blender validation
4. establish the current clean-save playthrough baseline
5. inspect `DEFERRED.md`
6. inspect the existing canonical-data provenance
7. inspect the existing Maple Island quest implementation
8. identify which systems/content are complete, partial, placeholder, or missing

Preserve the current architecture unless a concrete problem justifies changing it.

---

# Source-of-Truth Policy

The source hierarchy from Iteration Two remains in effect, with the following clarification.

## Primary authority: MeowDB MS Classic

https://meowdb.com/msclassic

MeowDB remains authoritative for canonical MapleStory Classic data including, where available:

- monsters
- monster stats
- monster drop membership
- maps
- map IDs
- map monster populations
- spawn information
- items
- item properties
- equipment
- consumable effects
- NPCs
- quests
- quest requirements
- quest rewards
- shops
- shop inventories
- shop prices
- classes
- skills
- formulas
- breakables
- progression
- combat mechanics
- meso amounts
- other documented MapleStory Classic mechanics

Do not replace MeowDB values with values from another MapleStory version when MeowDB provides them.

---

# Narrow Secondary Authority: Henesys.gg Rarity (Owner amendment, 2026-10-06)

Use Henesys.gg:

https://henesys.gg/loot

(MapleStory Classic World) specifically for the **rarity label of each drop item**: Common, Rare, Very Rare or
Extremely Rare. Henesys.gg gives a rarity per item, not per monster, and no drop chance.

The use of Henesys.gg is intentionally narrow.

## Item drop rule

The set of items a monster is allowed to drop comes from **MeowDB**: its community list "Drops (MS Classic)" for that
monster (or breakable), every entry.

The probability of those drops comes from the **project owner's drop chance table**, by item category and Henesys.gg
rarity. The table is a MisoStory adaptation (decision D3-11), kept in one file the owner can tune
(`game/data/misostory/drop_rates.json`):

| Category | Common | Rare | Very Rare | Extremely Rare |
|---|---|---|---|---|
| Etc, the monster's own leftover (MeowDB subtype "Monster Drop") | 100% | 50% | 20% | 5% |
| Etc, quest-gated (MeowDB subtype "Quest Item" and required by a Maple Island quest; drops only while that quest is in progress) | 100% | 100% | 100% | 100% |
| Other Etc (ores, gems, Monster Card...) | 3% | 1% | 0.3% | 0.1% |
| Use: potions, food, arrows | 2% | 0.5% | 0.1% | 0.02% |
| Use: scrolls | 0.1% | 0.03% | 0.01% | 0.003% |
| Equip | 0.1% | 0.04% | 0.01% | 0.002% |
| Set-up (chairs) | 0.05% | 0.02% | 0.005% | 0.001% |

The same table applies to the Wooden Box. One item drops per successful roll.

In set terminology:

```text
implemented_drop_items =
    MeowDB_confirmed_drop_items
```

Then:

```text
drop_chance(item) =
    owner_table[category(item)][Henesys.gg rarity(item)]
```

### Critical rule

If an item is not on MeowDB's community list for that monster (for example an item only on MeowDB's "MSEA reference
drops" list):

**do not add it.**

Henesys.gg does not expand the canonical drop table.

It supplies the rarity label for the MeowDB entries.

---

# Drop Provenance

Represent the distinction explicitly.

For example:

```text
{
  "monster": "Snail",
  "item": "Snail Shell",

  "membership_source": {
    "authority": "MeowDB MS Classic",
    "url": "..."
  },

  "rarity_source": {
    "authority": "Henesys.gg",
    "url": "https://henesys.gg/loot",
    "raw_value": "Common"
  },

  "chance": {
    "authority": "Project owner",
    "decision": "D3-11",
    "verified": false,
    "normalized_probability": ...
  }
}
```

This distinction should be preserved throughout the entire project.

Do not collapse:

```text
what can drop
```

and:

```text
how often it drops
```

into one ambiguous source.

---

# Missing Henesys.gg Rarity

If:

- MeowDB confirms that an item drops
- but Henesys.gg contains no rarity for it

then:

1. keep the item in the canonical monster drop definition
2. mark its probability as unresolved
3. do not invent a chance
4. investigate whether another reliable source is necessary
5. document the discrepancy

Do not silently remove the MeowDB-confirmed item because its probability is unavailable.

Do not silently assign an arbitrary probability.

A missing probability must remain visible in validation.

If the unresolved drop is required for Maple Island progression, treat that as an Iteration Three blocker.

---

# Meso Drop Rules

Replace the Iteration Two placeholder meso implementation.

## Meso amount

Use **MeowDB MS Classic** for the canonical meso amount/count associated with the monster.

For example, the Snail MeowDB entry reports the appropriate canonical meso value for that monster.

Do not invent a custom meso range if MeowDB provides the value.

Where MeowDB has no meso report, use the project owner's level formula (an adaptation, decision D3-12): a uniform
integer in [level, 2 x level] of the monster's canonical level. When MeowDB gains a report for a monster, that report
replaces the formula for it.

The Tutorial Jr. Sentinel and the Wooden Box drop no mesos (the owner's choice).

## Meso probability

MeowDB publishes no meso drop chance. Use the **project owner's meso drop chance: 60%** for every monster that drops
mesos, also one with a MeowDB amount (an adaptation, decision D3-12).

Therefore:

```text
meso_amount = MeowDB (else the owner's level formula)
meso_drop_probability = project owner (60%)
```

Keep both source records in provenance.

Do not interpret "meso amount" and "meso drop chance" as the same concept.

---

# Probability Handling

Be extremely careful when importing probabilities.

For each probability (each cell of the owner's drop chance table, and the meso chance):

- preserve the raw source value
- store a normalized runtime probability
- document the conversion
- test the conversion

Do not accidentally confuse:

```text
1 / N
```

with:

```text
N%
```

or:

```text
0.01
```

with:

```text
1%
```

Add validation for impossible probabilities such as:

- negative chance
- chance > 100%
- incorrect percentage normalization
- accidental integer truncation

---

# Source Access Rules

> **Owner amendment, 2026-10-06 (after Iteration Three):** the restrictions in this section no longer apply. MeowDB
> and Henesys.gg data may be used, read automatically and published. The section is kept as the brief that Iteration
> Three ran under.

Do not repeat the prohibited automated MeowDB collection performed during Iteration Two.

Respect source terms and access restrictions.

Use:

- the existing local cache
- manually inspected pages
- normal browser access
- already-authorized/local data

Do not create another unauthorized scraper.

Apply the same caution to Henesys.gg. Its site prohibits unauthorized reproduction or scraping: read it by hand in a normal browser, keep its labels for this private project only, and ask Henesys.gg before publishing them. Do not assume automated collection is permitted merely because the site is publicly accessible.

The game must continue to use its own local canonical-data snapshot at runtime.

Neither MeowDB nor Henesys.gg should be required while actually playing MisoStory.

---

# Resolve Iteration Two Placeholder: Natural HP Regeneration

Remove the temporary MisoStory HP regeneration behavior.

For a Beginner, and for non-Warrior behavior where relevant later, implement:

```text
10 HP every 10 seconds
```

with the following condition:

Natural HP regeneration occurs only while the character is:

- standing completely still

or:

- sitting

Natural regeneration does NOT advance while the player is:

- walking
- jumping
- attacking

The natural regeneration timer **pauses**, rather than progressing, during those actions.

Do not award the tick while the player is actively moving or attacking.

Do not reset accumulated stationary time unless canonical behavior specifically requires a reset.

Example:

```text
stand still for 6 seconds
move for 5 seconds
stand still for 4 additional seconds
```

should allow the accumulated stationary regeneration timer to reach the 10-second requirement if the timer is modeled as paused.

HP recovery must never exceed Max HP.

---

# Sitting and Chairs

Iteration Two deferred sitting/chairs.

Implement them now because they interact directly with canonical regeneration and Maple Island rewards.

At minimum support:

- obtaining a chair
- storing chairs in the appropriate inventory category
- using/equipping a chair appropriately
- sitting down
- standing back up
- preventing incompatible movement while seated
- natural regeneration while seated
- saving/loading chair ownership

Pio's canonical Maple Island reward should work as an actual usable chair rather than merely an inventory record.

Use MeowDB item data for canonical chair/item properties where available.

---

# Iteration Three Core Objective

Every piece of canonical Maple Island content that is relevant to the player must now be inventoried.

Create a generated or maintained:

```text
MAPLE_ISLAND_PARITY.md
```

and machine-readable equivalent such as:

```text
maple_island_parity.json
```

The parity manifest should cover at least:

```text
maps
portals
monster species
monster populations
monster spawn rules
monster stats
monster drops
meso drops
items
equipment
consumables
NPCs
shops
quests
quest chains
quest objectives
quest rewards
Beginner skills
breakables
chairs
map mechanics
```

Each entry should have a state such as:

```text
missing
partial
implemented
verified
```

Iteration Three does not finish until all in-scope entries are `verified`, except explicitly documented source-data gaps.

---

# Do Not Trust Existing Content Merely Because It Exists

Iteration Two implemented representative content.

Iteration Three must audit it.

For every existing:

- monster
- NPC
- shop
- quest
- item
- portal
- map population
- reward

compare it against current canonical data.

Existing implementation is not proof of correctness.

---

# Phase 1: Complete Maple Island Quest Inventory

Use the MeowDB Quest Database filtered to Maple Island and build the authoritative quest inventory.

Do not assume the current implementation's quest count is correct.

Do not assume the set of 17 quests mentioned in previous testing is the complete set.

Derive the complete set from the current canonical source.

Account for:

- standalone quests
- quest chains
- zero-level quests
- level-gated quests
- missable quests
- tutorial quests
- quizzes
- prerequisite relationships
- follow-up relationships
- quests with random rewards

Produce:

```text
data/canonical/quests/maple_island/
```

or the equivalent project structure.

---

# Every Maple Island Quest Must Work

Implement every Maple Island quest that belongs to the canonical Maple Island experience.

Quest behavior must include the appropriate:

- availability
- level requirement
- prerequisite
- NPC
- map
- acceptance conditions
- objectives
- item requirements
- monster kill requirements
- NPC interaction requirements
- item-use requirements
- dialogue state
- completion conditions
- EXP
- mesos
- items
- equipment
- random rewards
- follow-up quest unlocking

Do not reduce unique quests to generic placeholders if they contain meaningful special behavior.

---

# Random Quest Rewards

Canonical random rewards must actually be random according to the documented reward set/probabilities.

Do not always grant the first option.

Do not choose a favorite reward.

Add deterministic seeded tests covering random reward selection.

---

# Quiz Quests

All Maple Island quiz content must actually function.

For each quiz:

- correct question
- available answers
- correct-answer detection
- incorrect-answer behavior
- progression
- reward
- quest-chain state

should match canonical information where available.

Do not represent quiz quests as automatic completion.

---

# Quest Dialogue

Reproduce canonical dialogue where a reliable source exists.

MeowDB remains the first source to inspect.

If exact dialogue text is not available from MeowDB:

1. document that limitation
2. use another reliable Classic source only where necessary
3. attach provenance
4. do not present invented dialogue as canonical

If temporary adapted dialogue is unavoidable, mark it explicitly in the parity manifest.

Do not block underlying quest mechanics merely because exact historical wording is unavailable.

---

# Quest Indicators

Add the expected world-state communication for quests.

NPCs should visually communicate states such as:

- quest available
- quest in progress
- quest ready to turn in

Use an original MisoStory implementation inspired by MapleStory's readability.

The player should not need the developer console to discover quest progression.

---

# Quest Log

Upgrade the quest UI enough to support the complete Maple Island quest set.

It should clearly display:

- quest name
- current objective
- quantities
- relevant NPC
- completion state
- chain progression where useful

Ensure quests survive save/load at every intermediate state.

---

# Phase 2: Complete NPC Pass

Audit all NPCs across all 25 maps against MeowDB.

Verify:

- canonical NPC identity
- correct map
- interaction availability
- quest associations
- shop associations
- quiz behavior
- appropriate dialogue
- canonical special behaviors

Every relevant Maple Island NPC should be interactable if the original one is interactable.

No NPC should exist merely as scenery when it should provide gameplay.

---

# Phase 3: Complete Shop Pass

Audit every Maple Island shop.

Verify:

- correct shop NPC
- complete inventory
- item prices
- buy behavior
- sell behavior
- quantity handling
- insufficient mesos behavior
- full inventory behavior

Use MeowDB shop data for canonical inventories/prices.

Do not assume the three Iteration Two shops are complete merely because purchasing works.

Test every Maple Island shop individually.

---

# Phase 4: Complete Item Pass

Create the complete set of items needed by the Maple Island experience.

Include anything required by:

- character creation
- starter weapons
- quests
- quest rewards
- monster drops
- shops
- consumables
- equipment
- chairs
- ETC objectives

For every item validate:

- canonical ID
- canonical name
- type
- inventory category
- stack behavior
- equip slot if relevant
- requirements
- stats
- consumable behavior
- sell/buy prices where relevant
- source relationships

Remove placeholder gameplay values.

---

# Phase 5: Complete Monster Pass

Audit every monster species appearing anywhere on the 25 Maple Island maps.

Do not rely on the Iteration Two six-monster assumption.

The authoritative set comes from the current MeowDB map data.

For every species validate:

- ID
- name
- level
- HP
- MP
- EXP
- physical damage
- magic damage if relevant
- physical defense
- magic defense
- accuracy
- avoidability
- speed
- movement type
- contact behavior
- knockback threshold
- stagger behavior
- elemental attributes
- animations/timing where gameplay-relevant
- canonical drops

Use MeowDB monster data.

---

# Monster Behavioral Fidelity

Preserve simple old MapleStory behavior.

Different monsters should support their actual documented movement style where available, such as:

- walking back and forth
- remaining on a floor
- jumping
- moving between appropriate elevations

Do not give every monster identical wandering AI.

The isometric interpretation may adapt navigation, but monster identity should remain recognizable.

---

# Monster Hitboxes

Iteration Two discovered enemy hitbox overlap issues.

Audit monster:

- body collision
- attackable hitbox
- touch-damage area
- visual bounds
- knockback behavior

against available MeowDB combat/sprite measurements where useful.

Make the isometric hit area fair and visually understandable.

Do not create invisible oversized contact-damage bubbles.

---

# Phase 6: Complete Monster Population Pass

For every one of the 25 maps, compare runtime monster composition against MeowDB map data.

Verify:

- monster species
- spawn-point counts
- relative composition
- map mob rate where documented
- respawn timing
- movement restrictions
- special spawn rules

Do not settle for "the right monsters appear somewhere."

Map populations should meaningfully reflect the canonical map.

---

# Isometric Spawn Adaptation

Classic MapleStory spawn positions cannot be copied literally into a 3D map.

Therefore separate:

```text
canonical:
    species
    count
    composition
    mob_rate
    respawn_behavior
```

from:

```text
misostory:
    x
    y
    z
    spawn_region
    navigation_floor
```

Place the canonical population intelligently throughout the isometric map.

Spawn locations should:

- avoid portals
- avoid NPC interaction spaces
- avoid unreachable terrain
- avoid walls
- avoid spawning directly inside the player
- respect map topology
- create enjoyable combat distribution

---

# Spawn Timing

Where MeowDB documents Classic spawn timing and mob-rate behavior, implement it accurately enough for the single-player MisoStory context.

Do not retain arbitrary Iteration Two spawn delays if canonical information is available.

Centralize spawn timing rules.

Add tests.

---

# Phase 7: Complete Drop Pass

Remove placeholder drop probabilities.

For every Maple Island monster:

## Step 1

Build the permitted drop table from MeowDB.

## Step 2

Look up each item's rarity on Henesys.gg.

## Step 3

For every item:

```text
item membership = MeowDB
rarity = Henesys.gg
drop probability = owner table[item category][rarity]
```

## Step 4

Record both sources.

## Step 5

Validate all item IDs resolve to real local item definitions.

---

# Meso Drops

For every Maple Island monster:

```text
meso amount = MeowDB (else the owner's level formula)
meso probability = project owner (60%)
```

Remove all Iteration Two placeholder meso values.

Ensure mesos:

- drop into the world correctly
- can be collected
- display the correct amount
- save correctly

---

# Drop Testing

Add tests proving that:

- items outside MeowDB's community list (for example MSEA reference drops) cannot enter canonical drop tables
- MeowDB membership is authoritative
- drop probabilities are parsed correctly
- probability normalization is correct
- meso amount comes from MeowDB
- meso probability comes from the owner's meso rule
- unknown probabilities remain visible
- all drop item IDs exist

Use seeded RNG for deterministic unit tests.

Also perform a large offline simulation as a statistical sanity check.

The simulation should not be treated as the source of the probability.

It merely confirms the implementation behaves approximately as configured.

---

# Phase 8: Beginner Mechanics

Complete every Beginner-specific mechanic that is relevant before leaving Maple Island.

Use MeowDB's current:

- class data
- skill data
- formulas
- progression information

Do not blindly assume old versions of MapleStory had the exact same Beginner mechanics.

Inventory what the current Classic dataset actually exposes.

---

# Beginner Skills

If the canonical MapleStory Classic Beginner has skills available during Maple Island progression, implement all of them.

For every skill reproduce the documented:

- skill ID
- level behavior
- SP behavior
- cost
- cooldown
- target behavior
- damage/effect
- prerequisites
- maximum level

Use the existing combat/stat systems rather than special-casing skills unnecessarily.

If a remembered legacy Beginner skill differs from current MeowDB Classic data, MeowDB wins.

---

# Skill UI

If Beginner skills exist:

- add a functional skill window
- show skill levels
- allow appropriate skill allocation/use
- allow keyboard binding or practical activation
- persist skill progression

Final UI artwork is not required yet.

Functional parity is.

---

# Natural HP Regeneration

Implement exactly:

```text
10 HP per 10 seconds of eligible regeneration time
```

Eligible:

```text
standing still
sitting
```

Ineligible:

```text
walking
jumping
attacking
```

The timer pauses during ineligible states.

Test:

```text
10 continuous eligible seconds
9.9 seconds
partial accumulation
movement pause
jump pause
attack pause
resume after pause
sitting
full HP
save/load
```

---

# Other Natural Recovery

Do not infer MP recovery rules from the HP rule above.

For MP or other recovery behavior:

- use MeowDB if documented
- otherwise research separately
- preserve provenance

Do not invent matching MP behavior merely for symmetry.

---

# Phase 9: Chairs and Sitting

Implement complete basic chair usage.

At minimum:

- obtain chair
- inventory representation
- select/use chair
- seated player state
- stand up
- regeneration while sitting
- cancel sitting when appropriate
- save/load
- map-transition safety

The Green Relaxer reward should be functionally usable.

---

# Phase 10: Breakables and Interactive Objects

Audit Maple Island quests and maps for breakables or interactive world objects.

Use MeowDB's Breakables data where applicable.

Implement any required:

- boxes
- crates
- destructible objects
- collectible environmental objects
- quest-specific interactables

They should use the same canonical data architecture as monsters/items.

Do not fake a breakable-dependent quest by simply granting its items.

---

# Phase 11: Minimap

Iteration Two deferred the minimap.

Implement it now.

Every playable map should provide a usable isometric minimap or simplified map representation.

Show at minimum:

- player position
- map shape/major traversal region
- portals/exits
- relevant NPCs

Quest markers may also be shown if useful.

The minimap should adapt the existing isometric map rather than attempting to literally reuse a 2D MapleStory minimap where that geometry no longer matches.

Display:

- canonical map name
- canonical map ID in debug mode

---

# Phase 12: World Interaction Polish

Add enough world feedback that a player can understand the game without debug tools.

Examples:

- interact indicator
- portal cue
- item pickup feedback
- meso pickup feedback
- quest availability/completion indicators
- shop indication
- damage feedback
- level-up feedback
- AP available notification
- inventory-full warning
- insufficient mesos warning

Do not make developer overlays necessary for normal play.

---

# Phase 13: Full Stuck-Region Scan

Iteration Two found two separate regions where a player could fall into an enclosed pocket.

Do not rely only on manually discovering more of these.

Build a systematic traversal/stuck-region validation for all 25 maps.

Use an appropriate technique such as:

- navigation connectivity analysis
- walkable-surface graph
- sampled flood fill
- automated traversal agents
- collision-space analysis

The goal is to identify walkable regions from which the player cannot return to:

- the main traversal graph
- a portal
- an intended path

Inspect all flagged regions manually.

Fix legitimate traps in Blender/source geometry.

Do not merely add teleport failsafes over bad terrain.

---

# Phase 14: Complete Save-State Audit

The save system must now account for all Maple Island systems.

Verify persistence of:

- character identity
- gender
- level
- EXP
- HP
- MP
- AP
- stats
- mesos
- inventory
- equipment
- chairs
- skills
- skill progression
- quest availability
- quest progress
- quest completion
- random quest rewards already received
- current map
- respawn information

Add schema migration rather than invalidating Iteration Two saves unnecessarily.

---

# Phase 15: Maple Island Start-to-Finish Playthrough

Create a true canonical playthrough scenario.

Start from:

```text
brand-new character
```

without using developer cheats after character creation.

The player should be able to naturally:

1. begin Maple Island
2. encounter the tutorial NPCs
3. accept quests
4. complete quest chains
5. fight appropriate monsters
6. receive drops
7. use consumables
8. earn mesos
9. level
10. spend AP
11. obtain/equip gear
12. use shops
13. complete quizzes
14. use a chair
15. explore optional maps
16. complete all available Maple Island content
17. arrive at Southperry ready to leave Maple Island

Do not implement Victoria Island itself.

The departure point is the boundary of this iteration.

---

# Full Quest Playthrough Requirement

Unit tests are not enough.

Every canonical Maple Island quest must be exercised through the actual game.

Use real gameplay input where possible.

For each quest test:

- availability
- acceptance
- objective progress
- completion
- rewards
- follow-up behavior

Also test save/load at representative points throughout quest chains.

The previous Iteration Two report explicitly noted that several quests were only unit tested.

That is no longer acceptable for Iteration Three completion.

---

# Clean-Character Progression Audit

During the full playthrough, record:

```text
level
EXP
mesos
major quest rewards
equipment
important ETC items
```

at meaningful progression checkpoints.

Review whether progression makes sense relative to canonical rewards and monster EXP.

Do NOT "fix" progression by changing canonical values.

If progression differs unexpectedly, find the incorrect implementation or missing content.

---

# Phase 16: Content Cross-Reference Validation

Create automated referential-integrity tests.

Every:

```text
quest reward item
quest objective item
quest monster
quest NPC
monster drop
shop item
map monster
map NPC
portal destination
skill reference
chair item
breakable drop
```

must resolve to a valid canonical definition.

No dangling IDs.

No duplicate canonical IDs.

No placeholder names.

No silent missing references.

---

# Phase 17: Provenance Audit

Every canonical gameplay record should be traceable.

Extend the provenance format so a record can contain multiple authorities for different properties.

Example:

```text
monster:snail:
    stats:
        authority: MeowDB

    drops.membership:
        authority: MeowDB

    drops.rarity:
        authority: Henesys.gg

    drops.probability:
        authority: Project owner (D3-11)

    mesos.amount:
        authority: MeowDB

    mesos.probability:
        authority: Project owner (D3-12)
```

This is preferable to claiming that the entire monster definition came from one source.

Generate a provenance validation report.

---

# Phase 18: Regression Pass

After all Maple Island content exists, rerun everything from Iteration Two.

The new content must not break:

- damage formula parity
- movement
- portals
- all-map traversal
- shops
- combat
- inventory
- saving
- death
- respawn
- Blender validation
- existing tests

Keep the current MeowDB parity coverage intact.

Any canonical-data change that invalidates an existing parity test must be understood before changing the test.

Do not rewrite expected values merely to make tests green.

---

# Autonomous Iteration Loop

After the complete content pass:

1. start a clean character
2. play Maple Island
3. note every mismatch, annoyance, blocker, or suspicious value
4. determine whether the problem is:
   - canonical data
   - game logic
   - map adaptation
   - collision
   - UI
   - content definition
5. fix the source problem
6. rerun affected tests
7. replay the affected sequence
8. repeat

Do not stop because the checklist technically passes.

Stop when the complete Maple Island experience holds together as a game.

---

# Priority Order

If time or complexity forces prioritization, use:

```text
1. canonical correctness
2. quest/content completeness
3. progression correctness
4. gameplay blockers
5. world traversal
6. combat fidelity
7. UI clarity
8. visual polish
```

Do not sacrifice canonical gameplay correctness to polish a menu.

---

# Explicitly Out of Scope

Do NOT expand into:

- Lith Harbor
- Victoria Island gameplay
- first job advancement
- Warrior content
- Magician content
- Bowman content
- Thief content
- Pirate content
- parties
- multiplayer
- guilds
- trading
- Cash Shop
- Free Market
- final production character art
- final production monster art
- final production audio
- final production UI skinning

The Southperry departure boundary is enough.

---

# Definition of Done

Iteration Three is complete only when all of the following are true.

## Placeholder Removal

- [ ] No placeholder monster item-drop chances remain: every chance is the owner's table cell for the item's category and Henesys.gg rarity
- [ ] Drop membership comes from MeowDB
- [ ] Drop rarity comes from Henesys.gg and drop probability from the owner's table
- [ ] Items outside MeowDB's community list are excluded
- [ ] Meso amount comes from MeowDB (else the owner's level formula)
- [ ] Meso chance comes from the owner's meso rule
- [ ] HP regeneration is 10 HP per 10 eligible seconds
- [ ] Movement pauses natural HP regeneration
- [ ] Jumping pauses natural HP regeneration
- [ ] Attacking pauses natural HP regeneration
- [ ] Sitting permits natural HP regeneration

## Maps

- [ ] All 25 Maple Island maps remain playable
- [ ] Every map's monster composition has been audited
- [ ] Spawn populations match canonical data/adaptation rules
- [ ] Portals remain correct
- [ ] All interiors remain accessible
- [ ] Automated stuck-region scan covers all maps
- [ ] No known unintended player trap remains

## Monsters

- [ ] Every Maple Island monster species is implemented
- [ ] All canonical stats match MeowDB
- [ ] Movement behavior is appropriately represented
- [ ] Contact damage works
- [ ] hitboxes are fair
- [ ] respawning works
- [ ] canonical drop membership is correct
- [ ] available drop probabilities are correct
- [ ] meso behavior is correct

## Items

- [ ] Every quest-required item exists
- [ ] Every Maple Island shop item exists
- [ ] Every implemented monster drop resolves
- [ ] Every Maple Island reward item exists
- [ ] equipment stats are correct
- [ ] consumable effects are correct
- [ ] chairs work

## NPCs

- [ ] Every canonical Maple Island NPC is present
- [ ] Correct maps
- [ ] Correct quest associations
- [ ] Correct shop associations
- [ ] Relevant NPCs are interactable

## Quests

- [ ] Complete Maple Island quest inventory derived from MeowDB
- [ ] Every in-scope quest implemented
- [ ] All level requirements correct
- [ ] All prerequisites correct
- [ ] All objectives correct
- [ ] All rewards correct
- [ ] All EXP rewards correct
- [ ] All meso rewards correct
- [ ] Random rewards work correctly
- [ ] Quiz quests work
- [ ] Quest chains work
- [ ] Quest progress persists
- [ ] Every quest has been tested through actual gameplay

## Shops

- [ ] Every Maple Island shop audited
- [ ] Inventories match MeowDB
- [ ] Prices match MeowDB
- [ ] Buying works
- [ ] Selling works

## Beginner Mechanics

- [ ] All Maple Island-relevant Beginner mechanics audited
- [ ] All applicable Beginner skills implemented
- [ ] Skill behavior uses canonical data
- [ ] Natural HP recovery works correctly
- [ ] Sitting works
- [ ] chairs work
- [ ] AP behavior remains correct

## UI

- [ ] Functional minimap exists for all playable maps
- [ ] quest states are understandable without debug mode
- [ ] portals/interactions are understandable
- [ ] inventory and quest UI support complete Maple Island content
- [ ] level-up/AP feedback works

## Persistence

- [ ] Complete quest state persists
- [ ] random reward state persists
- [ ] inventory persists
- [ ] equipment persists
- [ ] chairs persist
- [ ] skills persist
- [ ] mesos persist
- [ ] character progression persists
- [ ] save migration works

## Canonical Verification

- [ ] MeowDB parity tests still pass
- [ ] Henesys.gg rarity provenance exists
- [ ] probability conversions are tested
- [ ] drop membership/chance sources are separately recorded
- [ ] no canonical value is silently guessed
- [ ] unresolved canonical data is explicitly reported

## Gameplay

From a completely clean character:

- [ ] create character
- [ ] begin Maple Island
- [ ] complete the opening/tutorial content
- [ ] fight every Maple Island monster type
- [ ] obtain normal monster drops
- [ ] obtain mesos through actual monster drops
- [ ] level naturally
- [ ] allocate AP
- [ ] use consumables
- [ ] equip gear
- [ ] use every Maple Island shop
- [ ] complete every Maple Island quest
- [ ] complete every quiz
- [ ] obtain and use a chair
- [ ] visit all 25 maps
- [ ] die and respawn correctly
- [ ] save and reload during progression
- [ ] reach Southperry legitimately
- [ ] arrive ready to depart Maple Island
- [ ] no developer console is required during the canonical playthrough

---

# Final Deliverables

Leave behind:

1. Complete playable Maple Island build
2. `MAPLE_ISLAND_PARITY.md`
3. Machine-readable parity manifest
4. Complete canonical Maple Island quest dataset
5. Complete Maple Island monster dataset
6. Complete Maple Island item subset
7. Complete Maple Island NPC/shop dataset
8. Complete drop tables
9. MeowDB/Henesys.gg provenance data
10. Updated save schema/migrations
11. Full automated test suite
12. Full stuck-region validation
13. Every-quest gameplay test report
14. Clean-character end-to-end playthrough report
15. Updated `CONTENT_AUTHORING.md`
16. Updated `HOWTO.md`
17. Updated `DEFERRED.md`
18. Iteration Three change/decision log

The final report must explicitly list:

- complete quest count
- complete monster count
- complete NPC count
- complete shop count
- unresolved source-data fields
- any deliberate MisoStory adaptations

Do not describe something as canonical if its source is unknown.

---

# Final Acceptance Standard

Do not ask:

> "Have I added enough content?"

Ask:

> "If a player only had MisoStory and played from character creation until Southperry, would Maple Island now behave like a complete MapleStory Classic starting region rather than an early prototype?"

The answer should be yes.

A player should be able to start from nothing and naturally experience:

```text
character creation
→ tutorial progression
→ quests
→ combat
→ drops
→ mesos
→ equipment
→ consumables
→ leveling
→ AP
→ Beginner mechanics
→ shops
→ exploration
→ quest chains
→ quizzes
→ optional content
→ Southperry
```

with canonical numerical data traceable to its source.

Continue:

```text
audit
→ implement
→ play
→ compare
→ fix
→ replay
```

until there are no significant Maple Island content or gameplay gaps remaining.