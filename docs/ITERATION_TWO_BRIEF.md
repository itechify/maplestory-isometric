# MisoStory — Iteration Two

## Turn Maple Island Into a Playable Game

Iteration One successfully created all 25 classic Maple Island maps as a cohesive isometric 3D world in Blender.

Iteration Two must turn that environment into an **actual playable game**.

The goal is NOT yet to reproduce every Maple Island quest, NPC, item, shop, dialogue line, and piece of content.

The goal is to build the **complete gameplay foundation** that all of that content will run on, prove that foundation using authentic MapleStory Classic data and representative content, and make the entirety of Maple Island traversable and playable.

At the end of this iteration, I should be able to launch MisoStory and actually **play through Maple Island as a Beginner**.

The systems created here should be architected so that Iteration Three can add the complete Maple Island content catalog largely by adding data rather than rewriting game systems.

---

# Primary Goal

Create a playable isometric interpretation of classic MapleStory where the player can:

- control a character
- move naturally through the 3D isometric environment
- traverse all 25 Maple Island maps
- transition between maps correctly
- talk to NPCs
- fight monsters
- take damage
- knock monsters back
- die and respawn
- gain EXP
- level up
- receive AP
- manage HP and MP
- pick up monster drops
- gain mesos
- use consumables
- manage inventory
- equip equipment
- persist progress
- save and load
- complete at least one authentic Maple Island quest from beginning to end

This should feel like the beginning of an actual MapleStory game rather than a technical demo.

---

# Canonical Gameplay Source — MeowDB MS Classic

For gameplay data and mechanics, **MeowDB's MapleStory Classic database is the authoritative source of truth for MisoStory**:

https://meowdb.com/msclassic

Do not mix canonical values from:

- MapleLegends
- MapleRoyals
- modern MapleStory
- old private-server databases
- archived fan-site pages
- random wikis
- forum posts
- remembered pre-Big-Bang values
- assumptions

when MeowDB contains the corresponding MapleStory Classic information.

The objective is to reproduce the version of **MapleStory Classic represented by MeowDB**, translated into an isometric 3D game.

---

# Source Priority

When implementing any canonical MapleStory property, use this priority:

1. Relevant MeowDB MS Classic detail/database page
2. Relevant MeowDB MS Classic mechanics/formula guide
3. Other MeowDB MS Classic tools/calculators/supporting pages
4. External evidence ONLY when MeowDB contains no applicable information

If an external source must be used:

- document what MeowDB was missing
- document the external source
- mark the value as externally sourced/unverified
- isolate it so it can easily be replaced later

Never silently substitute another source for MeowDB.

---

# Do Not Guess Canonical Values

Do not invent, approximate, or rebalance canonical properties such as:

- monster HP
- monster MP
- monster level
- monster EXP
- physical attack
- magic attack
- physical defense
- magic defense
- accuracy
- avoidability
- contact damage
- movement speed
- item stats
- item requirements
- item effects
- item prices
- quest requirements
- quest rewards
- quest EXP
- quest mesos
- NPC shop inventories
- NPC shop prices
- EXP requirements
- weapon multipliers
- mastery
- attack speed
- damage formulas
- accuracy formulas
- avoidability formulas
- defense formulas
- HP/MP progression
- derived stats
- monster drops
- documented spawn behavior

If MeowDB provides the value, use it.

---

# Required MeowDB Research

Before implementing gameplay, inspect the relevant portions of:

https://meowdb.com/msclassic

including the available databases for:

- Monsters
- Items
- Maps
- NPCs
- Quests
- NPC Shops
- Classes
- Skills
- Formulas
- Breakables
- Crafting when relevant
- EXP/progression information
- mechanics guides
- calculators/simulators

Open the actual detail pages.

Do not rely on search-result snippets.

---

# Damage Formula Source

The damage system must be based on:

https://meowdb.com/msclassic/guides/explaining-the-damage-formula

This guide is the source of truth for the combat mathematics it documents.

Do NOT replace the MapleStory damage system with a generic RPG approximation.

Do NOT implement:

```text
damage = attack - defense
```

or:

```text
damage = random(min_damage, max_damage)
```

unless that exact behavior is supported by the documented formula.

Implement the underlying MapleStory calculation.

---

# Architectural Principle

## Content Must Be Data-Driven

Do not hard-code Maple Island content directly into gameplay systems.

Eventually MisoStory may contain hundreds or thousands of:

- maps
- monsters
- NPCs
- items
- equipment pieces
- quests
- shops
- drops
- portals
- skills

Create authoritative data definitions.

A structure such as the following would be appropriate:

```text
data/
    canonical/
        maps/
        monsters/
        items/
        equipment/
        npcs/
        quests/
        shops/
        drops/
        formulas/

    misostory/
        maps/
        spawn_regions/
        camera/
        visuals/
        collision/
```

The exact format may vary.

The separation of concerns may not.

---

# Canonical Data vs MisoStory Adaptation

Keep MapleStory facts separate from isometric adaptations.

Example:

```text
monster:
    canonical:
        id
        name
        level
        hp
        exp
        accuracy
        avoidability
        defense
        drops

    misostory:
        model
        animation_set
        collision_radius
        model_scale
```

Likewise for maps:

```text
map:
    canonical:
        map_id
        monsters
        npcs
        portal_destinations

    misostory:
        blender_collection
        runtime_scene
        camera_bounds
        spawn_regions
        exact_3d_portal_positions
```

Changing the game from 2D to isometric 3D requires spatial adaptation.

It does NOT justify altering canonical MapleStory values.

---

# Local Canonical Data Cache

The game itself should NOT require a live connection to MeowDB.

MeowDB is the **development-time source of truth**.

Import/transcribe the relevant data into a local dataset that ships with MisoStory.

Preserve provenance where practical.

Example:

```text
source:
    authority: "MeowDB MS Classic"
    url: "https://meowdb.com/msclassic/..."
    retrieved_at: "..."
```

Maintain something like:

```text
canonical_sources.json
```

so that we can answer:

> Where did this gameplay value come from?

without searching commit history.

---

# Conflict Policy

If two MeowDB pages appear to disagree:

1. determine whether one represents newer or more explicitly verified Classic data
2. prefer the stronger/newer verified source
3. document the discrepancy
4. preserve the reasoning

Do not choose whichever value makes implementation easier.

If the discrepancy cannot be resolved, mark it for later verification.

---

# Runtime Engine

Blender remains the authoritative environment/art creation tool.

It should NOT become the game runtime unless the repository already has an extremely compelling reason for that.

If an established runtime engine already exists, continue using it.

Otherwise use **Godot 4.x** as the default runtime engine.

Maintain a clean pipeline:

```text
Blender
    ↓
environment export
    ↓
runtime engine
    ↓
MisoStory systems
    ↓
canonical MapleStory content data
```

---

# Phase 1 — Blender → Runtime Pipeline

Create a dependable, repeatable pipeline from:

```text
MapleIsland.blend
```

into the playable game.

Do not manually export and repair 25 areas every time the Blender world changes.

Preserve useful metadata including:

- map identity
- map ID
- terrain
- collision helpers
- portal markers
- spawn markers
- NPC markers
- traversal boundaries
- camera information where appropriate

Use existing Iteration One resources such as:

- `manifest.json`
- `MAPLE_ISLAND_MANIFEST.md`
- map collections
- portal markers
- scripts
- topology data

Avoid duplicating authoritative information unnecessarily.

A developer should be able to change Blender geometry, rebuild/export it, and regenerate the playable world without hand-editing every map afterward.

---

# Phase 2 — Runtime Map Architecture

All 25 Maple Island maps must exist in the playable runtime.

They may be:

- separate scenes
- streamed regions
- connected chunks
- portions of one larger world

depending on what works best.

Every canonical map still needs a stable MapleStory map ID.

The runtime map system should expose information such as:

```text
map_id
map_name
current_map
portals
destination_maps
monster_spawn_definitions
npc_definitions
player_spawn
respawn_location
environment_configuration
```

Use Iteration One's topology as the foundation.

Use MeowDB's map database for canonical map content.

---

# Map Data Authority

Use MeowDB map pages for canonical properties where provided, including:

- map ID
- map name
- monster species
- NPCs
- portals
- connections
- other relevant metadata

The Blender world decides exactly **where** something sits in 3D.

MeowDB decides **what canonically belongs there**.

For example:

```text
monster species on map = MeowDB
exact XYZ spawn location = MisoStory adaptation
```

and:

```text
portal destination = MeowDB
exact portal transform = MisoStory adaptation
```

---

# Phase 3 — Player Controller

Replace the debug/player proxy with a real gameplay controller.

A placeholder character model is acceptable.

Do not spend the entire iteration building final character art.

Prioritize game feel.

---

# Controls

Implement at least:

- WASD movement
- diagonal movement
- facing direction
- jump
- gravity
- attack
- interact
- pickup
- inventory
- quest panel
- character/stat panel

Controller support is desirable but optional for this iteration.

Keyboard support is mandatory.

---

# Isometric Movement

This is an isometric adaptation.

The character may move through approximately eight directions.

Movement should feel like MapleStory:

- immediate
- responsive
- fast to start
- fast to stop
- predictable
- arcade-like

Avoid realistic acceleration or momentum unless extremely subtle.

---

# Jumping

Jumping remains a core MapleStory mechanic.

Implement:

- jump impulse
- gravity
- airborne control
- landing
- terrain collision
- fall handling

The game must not become a walking-only isometric RPG.

Adapt platform distances and terrain where necessary to make jumps readable from the isometric camera.

Do not require unreasonable pixel-perfect jumps.

---

# Camera

Create a production-capable gameplay camera.

The camera should:

- retain the isometric visual identity from Iteration One
- follow the player smoothly
- maintain gameplay readability
- minimize obstruction
- avoid clipping through terrain
- avoid excessive motion
- keep enemies and important objects visible

Prefer a deliberate, mostly fixed orientation.

Do not add unrestricted player camera rotation unless there is a compelling reason.

Investigate orthographic or near-orthographic camera behavior.

---

# Phase 4 — Collision and Traversal

Every gameplay region must have functional collision.

Validate:

- terrain
- cliffs
- buildings
- fences
- trees
- water
- bridges
- ramps
- elevated terrain
- map boundaries
- portals

Small decorative objects should generally not block the player.

Avoid the player constantly catching on:

- grass
- flowers
- tiny stones
- roots
- mushrooms
- decorative clutter

Use simplified gameplay collision rather than raw visual meshes where appropriate.

---

# Full-Island Traversal Requirement

Before spending significant time on content, walk the entire island.

Every one of the 25 maps must be reachable.

Validate:

- primary route
- branch routes
- town interiors
- optional hunting maps
- Southperry
- Amherst
- Mushroom Town

No:

- collision traps
- unreachable portals
- impossible slopes
- impossible jumps
- falling through the world
- broken destination spawns
- inaccessible doorways

Build automated or semi-automated traversal validation where practical.

---

# Phase 5 — Portal System

Create one generic portal architecture.

Portal data should support:

```text
portal_id
source_map_id
destination_map_id
destination_portal_id
spawn_transform
portal_type
interaction_type
```

Support:

- normal map portals
- doors
- building interiors
- building exits

Use MeowDB for canonical map relationships.

Use MisoStory data for exact 3D transforms.

Do not create separate custom portal scripts for each map.

---

# Phase 6 — Character State

Implement persistent character state.

At minimum:

```text
name

level
exp

hp
max_hp

mp
max_mp

str
dex
int
luk

available_ap

mesos

inventory

equipment

quest_state

current_map

respawn_reference
```

Design this so future additions naturally support:

- job
- SP
- skills
- fame
- buffs
- debuffs
- status effects
- party state

---

# Leveling and EXP

Use MeowDB MS Classic as the source of truth for:

- EXP requirements
- level progression
- Maple Island monster EXP
- quest EXP
- other documented progression behavior

Do not substitute a remembered old Global MapleStory EXP table unless it has been verified against MeowDB.

Centralize progression logic.

Add tests.

---

# HP / MP Progression

Use MeowDB formula/data pages for documented HP and MP progression behavior.

Keep separate:

- base values
- level gains
- stat-derived contributions
- equipment
- skills
- buffs

Do not tune HP/MP purely by feel.

---

# AP

Implement Beginner AP behavior and stat allocation architecture.

The character should:

- gain AP at the proper times
- retain unused AP
- allocate STR / DEX / INT / LUK

Use the applicable MeowDB Classic rules.

---

# Derived Stats

Implement canonical derived stats according to MeowDB where documented.

Examples may include:

- accuracy
- avoidability
- magic
- physical defense
- magic defense

Do not assume all future jobs use the same formulas.

Create central stat-calculation systems.

---

# Phase 7 — Monster Framework

Build a generic monster system.

Monster definitions should be able to contain:

```text
id
name

level

hp
mp

physical_attack
magic_attack

physical_defense
magic_defense

accuracy
avoidability

exp

movement_speed

attributes

drop_table

respawn_rules

ai_type
```

Include additional MeowDB data that is relevant.

Do not invent monster stats.

---

# Initial Monster Set

Implement at least:

- Snail
- Blue Snail
- Red Snail
- Orange Mushroom

Use MeowDB monster pages for canonical gameplay properties.

Additional Maple Island monsters may be implemented if they are needed to exercise the architecture.

Placeholder stylized models are acceptable.

Gameplay correctness is more important than final art during this iteration.

---

# Monster Behavior

For now, monsters require:

- idle state
- wandering
- terrain awareness
- simple direction changes
- player contact
- receiving attacks
- knockback
- HP
- death
- EXP reward
- drops
- respawn

Old MapleStory monsters are intentionally simple.

Do not create complex modern enemy AI.

---

# Spawn System

Monster spawning must be data-driven.

Map data should define something equivalent to:

```text
monster_id
spawn_region
spawn_points
maximum_alive
respawn_delay
```

Use canonical monster presence from MeowDB.

Exact isometric spawn coordinates are MisoStory adaptation data.

Avoid permanently hand-placing runtime monsters unless those placements are generated from authoritative spawn definitions.

---

# Phase 8 — Combat Engine

Build the real MapleStory combat foundation now.

Support:

- normal Beginner attacks
- weapon attacks
- attack timing
- hit detection
- damage
- misses
- monster HP
- knockback
- death
- contact damage
- player post-hit invulnerability
- floating damage numbers

Favor responsive combat.

---

# Canonical Damage Mathematics

Use:

https://meowdb.com/msclassic/guides/explaining-the-damage-formula

The combat code must represent the documented formula rather than merely reproducing a displayed damage range.

Create a central combat module such as:

```text
CombatFormula

calculate_physical_range(...)
roll_physical_damage(...)

calculate_magic_range(...)
roll_magic_damage(...)

calculate_accuracy(...)
roll_hit(...)

apply_defense(...)
apply_element(...)
apply_level_scaling(...)
apply_critical(...)
finalize_damage(...)
```

Exact architecture is flexible.

Centralization is mandatory.

---

# Physical Damage

Implement the physical attack formula documented by MeowDB.

Preserve the role of:

- weapon attack
- skill damage
- primary stat
- secondary stat
- attack power
- mastery
- weapon family
- weapon action
- weapon multiplier
- independent random rolls

Do not simplify the result into one uniform random roll between displayed minimum and maximum if MeowDB documents a different roll process.

---

# Weapon Families and Actions

Design the combat engine to support weapon-specific behavior such as:

- swing
- stab
- shoot
- other action types

and weapon-family multipliers.

Even if Beginners only exercise a subset initially, do not create an architecture that assumes every weapon behaves identically.

---

# Mastery

Implement mastery as documented by MeowDB.

Mastery affects the damage distribution/range.

Do not represent it as a simple flat damage percentage if that is not how the Classic formula works.

Ensure the no-mastery Beginner case works correctly.

---

# Magic Damage

Build a distinct magic-damage calculation path according to MeowDB.

It must be capable of using documented relationships between things such as:

- INT
- Magic
- equipment Magic Attack
- buff Magic Attack
- skill power
- mastery

Maple Island may not heavily exercise magic yet.

Build the architecture now so Magician implementation later does not require replacing combat.

---

# Damage Processing Pipeline

Represent the damage pipeline explicitly.

Support the documented order for stages such as:

1. hit determination
2. raw damage roll
3. defense
4. elemental modifier
5. level-difference modifier
6. critical modifier
7. skill-specific modifiers
8. final truncation/clamping

Do not hide all of this inside an opaque giant function.

Each stage should be independently testable.

---

# Defense

Use MeowDB's documented physical and magical defense behavior.

Do not default to simple subtraction.

Support:

- physical defense
- magic defense
- flat adjustments where applicable
- percentage adjustments where applicable
- future defense bypass mechanics

---

# Elemental Modifiers

Prepare the combat system for MapleStory elemental interactions.

Support the documented concepts for:

- normal
- weakness
- resistance
- immunity

even if Maple Island does not yet exercise all of them.

---

# Level Difference Scaling

Implement the MeowDB Classic behavior for attacking higher-level targets.

Do not invent a generic level penalty.

Add unit tests covering:

- lower-level target
- same-level target
- slightly higher-level target
- significantly higher-level target

---

# Critical Hits

Keep:

```text
critical_chance
critical_damage
```

independent.

Implement MeowDB behavior where applicable.

Design for future skill/equipment modifiers.

---

# Accuracy and Misses

Do not implement arbitrary flat miss chances.

Use MeowDB's Classic accuracy/hit mechanics.

The result should derive from player and monster stats.

Add deterministic tests.

---

# Combat Formula Parity Tests

For each important formula:

1. obtain representative values from MeowDB documentation or tools
2. implement the formula
3. construct deterministic tests
4. compare results with MeowDB
5. treat unexplained differences as bugs

Include tests for:

- Beginner
- no mastery
- representative weapons
- swing/stab where applicable
- minimum damage
- maximum damage
- random damage rolls
- physical defense
- magic defense
- same-level targets
- higher-level targets
- miss behavior
- critical behavior
- final damage clamping

Whenever MeowDB exposes a simulator relevant to a mechanic, use it as a parity oracle.

---

# Phase 9 — Player Damage and Death

The player must be able to receive monster contact damage.

Implement:

- player defense calculation
- damage taken
- hit reaction
- knockback if appropriate
- temporary invulnerability
- HP reduction
- zero-HP state
- death
- respawn

Use canonical MapleStory rules where MeowDB documents them.

Structure the system so later death penalties can be added cleanly.

---

# Phase 10 — Drops

Monsters must support canonical drops.

Use MeowDB item/monster pages as the authority for:

- which items can drop
- relevant documented values
- mesos behavior where available

Drops should:

- appear visibly
- exist in the world
- be collectible
- disappear after an appropriate period
- enter inventory
- add mesos

The exact 3D placement and physics behavior may be adapted for isometric gameplay.

---

# Drop Architecture

Use reusable drop-table data.

For example:

```text
drop_table:
    entries:
        item_id
        chance
        min_quantity
        max_quantity
```

Do not embed drop logic directly inside monster scripts.

---

# Phase 11 — Inventory

Create a classic MapleStory-style inventory architecture.

Support the categories:

- Equip
- Use
- Setup
- Etc.
- Cash

Not every category needs substantial content yet.

Implement the underlying model correctly.

The player should be able to:

- obtain an item
- see it in inventory
- stack stackable items
- use consumables
- equip equipment
- remove equipment
- inspect basic item information

---

# Item Data

Use MeowDB's item database and item detail pages for canonical properties such as:

- ID
- name
- category
- equip slot
- requirements
- stats
- Weapon Attack
- Magic Attack
- defense
- STR / DEX / INT / LUK bonuses
- consumable effects
- shop sources
- quest sources
- monster sources

Do not approximate classic item values.

---

# Equipment

Support at least the equipment types necessary for early Maple Island gameplay.

Architect broadly enough to support future slots such as:

- weapon
- hat
- top
- bottom
- overall
- shoes
- gloves
- cape
- shield
- earrings

Only the subset needed in Iteration Two needs actual content.

Equipped items must alter character stats.

Visual equipment overlays can remain limited.

---

# Phase 12 — Consumables

Implement representative HP and MP recovery consumables based on MeowDB data.

Using a consumable must:

- decrement quantity
- restore the documented resource amount
- respect Max HP / Max MP
- persist correctly

---

# Phase 13 — Mesos

Implement persistent mesos.

Support:

- monster meso drops
- pickup
- HUD display
- persistence

Design it so NPC shops can use the same currency system.

---

# Phase 14 — NPC Framework

Create a reusable NPC architecture.

NPC definitions should support:

```text
npc_id
name
map_id
position
visual
dialogue
quests
shop_id
interaction_behavior
```

Use MeowDB for canonical identity and relationships.

Use MisoStory data for exact 3D position and visual adaptation.

---

# NPC Interaction

The player should:

1. approach an NPC
2. see an interaction cue
3. press interact
4. open dialogue
5. advance dialogue
6. make choices where necessary
7. trigger quest/shop behavior
8. close dialogue

Dialogue must support branching and conditions.

---

# Dialogue UI

Create a temporary but polished-enough MapleStory-inspired dialogue UI.

Support:

- NPC name
- NPC portrait/icon
- dialogue
- Next
- Back when appropriate
- Yes / No
- multiple-choice options

Do not obsess over pixel-perfect reproduction of MapleStory's original interface yet.

Robustness matters more.

---

# Phase 15 — NPC Shops

Build the shop framework now even if only a small representative shop is populated.

Use MeowDB's NPC Shop database for:

- NPC/shop relationships
- inventories
- purchase prices
- other relevant data

Shop architecture must support:

- buying
- selling
- meso validation
- inventory-full handling
- quantities
- item metadata

Shop contents should be data, not hard-coded UI entries.

---

# Phase 16 — Quest Framework

Build the real quest system.

Do not yet implement every Maple Island quest.

Quest definitions should be capable of expressing:

```text
quest_id
name

starting_npc
ending_npc

minimum_level
prerequisites

dialogue_states

objectives

monster_kills
item_collection
npc_interaction
map_visitation
item_usage
other_conditions

rewards

exp
mesos
items
equipment

followup_quests
```

Quest progress must save.

---

# Quest Data Authority

Use MeowDB's Quest database and quest detail information for canonical properties.

Do not alter:

- required quantities
- required monsters
- EXP
- mesos
- rewards
- prerequisite relationships
- required levels

without an explicit MisoStory adaptation reason.

---

# One Authentic Maple Island Quest

Implement at least one actual early Maple Island quest end-to-end.

Prefer one that exercises several systems such as:

- NPC interaction
- quest acceptance
- item acquisition/use
- objective tracking
- quest turn-in
- reward
- save/load

Do NOT create a fake development-only quest instead.

The purpose is to prove that additional Maple Island quests can later be created mostly by adding quest data.

---

# Phase 17 — Quest UI

Create basic interfaces for:

- available quest indicators
- active quests
- quest objectives
- objective progress
- completion

For example:

```text
Quest Name

☑ Talk to NPC
☐ Obtain 3 items
☐ Return to NPC
```

Exact visual polish can wait.

---

# Phase 18 — HUD

Create a usable gameplay HUD showing at least:

- HP
- MP
- Level
- EXP
- Mesos

Provide access to:

- inventory
- equipment
- character stats
- quests

Use a MapleStory-inspired visual language without requiring exact copying of original assets.

---

# Phase 19 — Save / Load

Create persistent saves.

Persist at minimum:

- player stats
- level
- EXP
- HP
- MP
- AP
- mesos
- inventory
- equipped items
- quest states
- current map
- respawn location

Save **logical game state**.

Do not serialize the entire runtime scene as the save system.

---

# Save Versioning

Every save file must contain a schema version.

Plan for migration.

Example:

```text
save_version: 1
```

Future changes should be able to migrate older saves rather than immediately invalidating them.

---

# Phase 20 — Developer Tools

Create strong developer/debug tooling.

At minimum make it easy to:

- teleport to map
- teleport to portal
- show current map ID
- show coordinates
- show collision
- show spawn regions
- show portal data
- spawn monster
- kill monster
- grant EXP
- set level
- grant mesos
- grant item
- clear inventory
- accept quest
- complete quest
- reload map
- reset save

These tools are required because Iteration Three will involve a large amount of content verification.

---

# Phase 21 — Automated Testing

Create automated tests for core logic.

At minimum:

## Character

- EXP thresholds
- level up
- AP gain
- stat allocation
- HP/MP limits
- derived stats

## Combat

- attack range/formula
- random rolls
- hit/miss
- defense
- level difference
- crit
- monster death
- EXP award

## Inventory

- add item
- remove item
- stacking
- inventory full
- use consumable
- equip
- unequip

## Drops

- valid drop definitions
- item pickup
- mesos

## Portals

- source map
- destination map
- destination portal
- correct player spawn

## Quest

- accept
- objective updates
- complete
- rewards
- persistence

## Shops

- purchase
- insufficient mesos
- full inventory
- selling

## Saves

- save
- load
- round-trip state equality
- schema version

---

# Phase 22 — Canonical Data Validation

Add validation scripts for local canonical data.

Validate things such as:

- every referenced item exists
- every referenced monster exists
- every map ID exists
- every portal destination exists
- every NPC exists
- every quest NPC exists
- every quest reward item exists
- every monster drop item exists
- every shop item exists
- no duplicate canonical IDs
- source provenance exists

Treat broken data references similarly to compile errors.

---

# Phase 23 — Gameplay Validation

Automated tests are not enough.

Perform real playthroughs.

---

# Test A — Entire Island Traversal

Start at the beginning of Maple Island.

Visit all 25 maps.

Travel:

- through Mushroom Town
- through the Snail Hunting Grounds
- through branches
- through Amherst
- through optional forest/hunting areas
- to Southperry

Verify every portal and route.

---

# Test B — Combat

Fight every implemented monster.

Verify:

- hit detection
- misses
- damage
- damage taken
- knockback
- monster death
- EXP
- drops
- respawning

---

# Test C — Progression

Starting with a clean character:

- kill monsters
- gain EXP
- level naturally
- receive AP
- allocate AP
- observe stat changes

Compare representative calculations against MeowDB.

---

# Test D — Inventory

Obtain:

- mesos
- consumable
- equipment

Then:

- pick them up
- use the consumable
- equip the equipment
- verify resulting stats
- save
- reload
- confirm everything persists

---

# Test E — Quest

Complete the authentic Maple Island quest from a clean save.

Repeat while:

1. accepting quest
2. progressing halfway
3. saving
4. quitting
5. reloading
6. completing quest

Verify the exact canonical reward.

---

# Test F — Death

Die intentionally in multiple areas.

Confirm:

- death state works
- respawn works
- save data remains valid
- inventory does not corrupt
- quest state does not corrupt

---

# Test G — Shop

Buy and sell representative items.

Verify:

- MeowDB prices
- meso changes
- inventory changes
- insufficient-funds handling
- inventory-full behavior

---

# Autonomous Iteration Loop

Do not stop after the systems technically function.

Repeatedly:

1. launch the game
2. play it
3. identify the largest gameplay or fidelity problem
4. fix it
5. replay the affected sequence
6. run automated tests
7. compare formulas/data against MeowDB
8. repeat

Continue until the first playable foundation is genuinely coherent.

---

# Movement Review

During every major playthrough evaluate:

- Is movement responsive?
- Is movement speed pleasant?
- Does diagonal movement feel correct?
- Does jumping feel useful?
- Is air control understandable?
- Does the player get snagged?
- Are terrain transitions smooth?

---

# Camera Review

Evaluate:

- Can I see the player?
- Can I see nearby enemies?
- Are trees/buildings obstructing play?
- Are cliffs hiding monsters?
- Does the camera expose unfinished geometry?
- Does the isometric angle make jumping understandable?

Fix environment or camera issues instead of accepting poor readability.

---

# Combat Review

Evaluate:

- Are attacks responsive?
- Do hitboxes match visuals?
- Are monsters readable?
- Is knockback clear?
- Are misses understandable?
- Does contact damage feel predictable?
- Are damage numbers readable?

If values feel surprising, verify the calculations against MeowDB before changing canonical data.

---

# World Review

Evaluate:

- Are some Iteration One spaces far too large once walking through them?
- Are areas too empty?
- Are routes obvious?
- Are portals visible?
- Are monster combat areas large enough?
- Are town paths comfortable?

Iteration One optimized for renders.

Iteration Two must optimize for **actual gameplay**.

---

# Critical Rule — Modify Blender When Gameplay Exposes World Problems

Iteration One's environment is not sacred.

Gameplay may reveal:

- path too narrow
- bridge too steep
- tree blocking camera
- portal awkwardly positioned
- collision trap
- arena too small
- impossible jump
- hidden pathway
- building entrance too cramped

When this occurs, fix the source world.

Update:

- Blender
- build scripts
- map adaptation data
- collision data
- validation

Do not pile runtime hacks on top of problematic Blender geometry.

---

# No Silent Rebalancing

Do not change canonical values because they "feel better."

Examples:

```text
monster HP
monster damage
monster EXP
drop values
weapon stats
potion effects
quest rewards
shop prices
level requirements
formulas
```

must remain MeowDB values unless there is an explicit documented reason to adapt them.

If isometric gameplay requires adaptation, keep that adaptation separate.

For example:

```text
canonical_contact_damage = MeowDB value
```

while something like:

```text
isometric_contact_invulnerability_duration
```

may legitimately be a MisoStory-specific property.

---

# Scope Restrictions

Do NOT yet attempt to implement:

- every Maple Island quest
- every Maple Island NPC
- every Maple Island dialogue
- every Maple Island item
- every Maple Island shop
- every Maple Island monster if not needed to prove systems
- Victoria Island
- job advancement
- Warrior
- Magician
- Bowman
- Thief
- Pirate
- advanced skills
- parties
- multiplayer
- trading
- guilds
- Cash Shop
- final character art
- final animation quality
- final UI art

Those belong in later iterations.

Iteration Two is the **gameplay engine and foundation**.

---

# Definition of Done

Iteration Two is complete only when all of the following are true.

## Runtime

- [ ] Game launches independently of Blender
- [ ] Blender remains the environment source
- [ ] Blender → runtime pipeline is repeatable
- [ ] All 25 Maple Island maps exist in runtime

## Canonical Data

- [ ] MeowDB MS Classic is explicitly the gameplay-data authority
- [ ] Local canonical data cache exists
- [ ] Source/provenance URLs are retained
- [ ] Monster values implemented so far match MeowDB
- [ ] Item values implemented so far match MeowDB
- [ ] Quest values implemented so far match MeowDB
- [ ] NPC/shop values implemented so far match MeowDB
- [ ] No unexplained canonical-data discrepancies remain

## Player

- [ ] Movement works
- [ ] Diagonal movement works
- [ ] Jumping works
- [ ] Collision works
- [ ] Camera works
- [ ] Player can traverse all 25 maps

## Portals

- [ ] All required map transitions work
- [ ] Portal definitions are data-driven
- [ ] Building entrances and exits work
- [ ] Destinations match canonical topology

## Character

- [ ] HP works
- [ ] MP works
- [ ] EXP works
- [ ] Levels work
- [ ] AP works
- [ ] stat allocation works
- [ ] Beginner derived stats are calculated correctly

## Combat

- [ ] Physical damage follows MeowDB
- [ ] Mastery behavior follows MeowDB
- [ ] weapon action/multiplier structure exists
- [ ] defense follows MeowDB
- [ ] accuracy/miss behavior follows MeowDB
- [ ] level-gap behavior follows MeowDB
- [ ] critical architecture exists
- [ ] magic damage architecture exists
- [ ] representative formula parity tests pass

## Monsters

- [ ] Generic monster framework exists
- [ ] Snail works
- [ ] Blue Snail works
- [ ] Red Snail works
- [ ] Orange Mushroom works
- [ ] spawning works
- [ ] respawning works
- [ ] wandering works
- [ ] contact damage works
- [ ] knockback works
- [ ] death works
- [ ] EXP works

## Items

- [ ] drops work
- [ ] mesos work
- [ ] inventory works
- [ ] item stacking works
- [ ] consumables work
- [ ] equipment works
- [ ] equipment modifies stats

## NPCs

- [ ] generic NPC framework exists
- [ ] interactions work
- [ ] dialogue works
- [ ] branching dialogue is supported

## Shops

- [ ] generic shop system exists
- [ ] buying works
- [ ] selling works
- [ ] prices come from canonical data

## Quests

- [ ] generic quest framework exists
- [ ] quest progress persists
- [ ] at least one authentic Maple Island quest is implemented fully
- [ ] rewards exactly match canonical data

## Persistence

- [ ] saving works
- [ ] loading works
- [ ] inventory persists
- [ ] equipment persists
- [ ] mesos persist
- [ ] stats persist
- [ ] quest state persists
- [ ] map/progression persists
- [ ] save schema is versioned

## Engineering

- [ ] gameplay is data-driven
- [ ] map-specific behavior is not unnecessarily hard-coded
- [ ] canonical and MisoStory adaptation data are separated
- [ ] automated tests pass
- [ ] canonical reference validation passes
- [ ] debug tools exist
- [ ] no architectural blocker prevents adding the remainder of Maple Island content

## Gameplay Acceptance

Starting from a clean save:

- [ ] I can move around naturally
- [ ] I can visit all 25 maps
- [ ] I can fight monsters
- [ ] I can miss attacks according to the real system
- [ ] I can take damage
- [ ] I can die
- [ ] I can respawn
- [ ] I can collect drops
- [ ] I can collect mesos
- [ ] I can use consumables
- [ ] I can equip equipment
- [ ] I can gain EXP
- [ ] I can level up
- [ ] I can spend AP
- [ ] I can talk to NPCs
- [ ] I can complete an authentic quest
- [ ] I can use a shop
- [ ] I can save halfway through progression
- [ ] I can quit
- [ ] I can reload
- [ ] I can continue without corrupted state
- [ ] no significant traversal blocker remains
- [ ] no significant gameplay blocker remains
- [ ] representative numerical behavior agrees with MeowDB

---

# Final Deliverables

Leave behind:

1. Playable MisoStory runtime project.
2. Updated Blender environment and generation scripts.
3. Repeatable Blender → runtime import/export pipeline.
4. Local canonical MeowDB-derived gameplay dataset.
5. Canonical-data provenance manifest.
6. Gameplay architecture documentation.
7. Content/schema documentation.
8. Damage/combat formula documentation.
9. Automated tests.
10. MeowDB parity tests.
11. Debug tooling documentation.
12. Playthrough validation report.
13. Iteration log describing major problems discovered and fixed.
14. Updated deferred backlog.

Document exactly how to:

```text
build the Blender environment

export/import the environment

launch the game

create a clean save

run automated tests

run canonical-data validation

run combat/formula tests

teleport between maps

grant items

grant EXP

enable debug overlays
```

---

# Final Acceptance Standard

Do not evaluate Iteration Two by asking:

> "Did I implement all of the requested systems?"

Evaluate it by asking:

> "Can somebody actually sit down and play Maple Island now, and are the underlying MapleStory mechanics faithful enough that I can confidently build the rest of the game on top of them?"

The player should be able to:

- enter the world
- move naturally
- jump
- traverse Maple Island
- fight monsters
- miss attacks appropriately
- deal damage using the real Classic combat model
- take damage
- gain EXP
- level up
- spend AP
- acquire items
- equip gear
- use consumables
- earn mesos
- interact with NPCs
- use a shop
- complete a real quest
- save
- quit
- reload
- continue playing

Most importantly:

**The systems created during this iteration must be strong enough that implementing the remaining Maple Island content becomes primarily a content-authoring and verification task, rather than another major gameplay-engine rewrite.**

After the first complete implementation, continue:

**play → inspect → compare with MeowDB → identify problems → fix → retest**

until the foundation genuinely feels ready for a full canonical Maple Island content pass.