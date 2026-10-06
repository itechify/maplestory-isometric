extends Node
## Autoload "Events": the global gameplay event bus.
##
## Systems announce facts here instead of calling each other, so quests, UI, the HUD, saves and debug tools stay
## decoupled. Payload ids are canonical MeowDB ids (strings). Emitters own the fact; listeners never mutate the
## emitter's state through the signal.

# --- world / maps -------------------------------------------------------------------------------------------
signal map_entered(map_id: String, previous_map_id: String)
signal map_left(map_id: String)
signal portal_used(map_id: String, portal_name: String, to_map_id: String)

# --- character ----------------------------------------------------------------------------------------------
## `amount` is negative for a loss: the death EXP penalty emits -lost with source "death" (listeners log gains only).
signal exp_gained(amount: int, source: String)
signal leveled_up(new_level: int)
signal stats_changed()
signal hp_changed(hp: int, max_hp: int)
signal mp_changed(mp: int, max_mp: int)
signal mesos_changed(mesos: int, delta: int)
signal player_damaged(amount: int, source_monster_id: String)
signal player_missed_by(source_monster_id: String)
signal player_died(map_id: String)
signal player_respawned(map_id: String)
## Sitting (contract C5), emitted by the PlayerController: the player sat down on chair item `chair_id`, or stood up
## (`reason`: move, jump, attack, sit_key, chair, knockback, death, climb, teleport, warp, chair_lost, character, ...).
signal player_sat_down(chair_id: String)
signal player_stood_up(reason: String)

# --- combat -------------------------------------------------------------------------------------------------
signal monster_hit(monster_id: String, damage: int, critical: bool)
signal monster_missed(monster_id: String)
signal monster_killed(monster_id: String, map_id: String)
## Emitted by the monster system when a kill (or a breakable) produces loot: `drops` is DropRoller.roll() output.
## The loot system listens and puts the drops on the ground at `world_position`.
signal loot_dropped(drops: Array, world_position: Vector3, map_id: String)

# --- items --------------------------------------------------------------------------------------------------
signal item_gained(item_id: String, quantity: int)
signal item_lost(item_id: String, quantity: int)
signal item_used(item_id: String)
signal inventory_changed()
signal equipment_changed(slot: String)
signal inventory_full(item_id: String)

# --- npcs / quests / shops ----------------------------------------------------------------------------------
signal npc_talked(npc_id: String)
signal dialogue_opened(npc_id: String)
signal dialogue_closed(npc_id: String)
signal quest_started(quest_id: String)
signal quest_progressed(quest_id: String)
signal quest_completed(quest_id: String)
signal quest_forfeited(quest_id: String)
## A request to open an NPC shop (any system may emit it; the NPC UI also listens to NpcInteraction.shop_requested).
signal shop_open_requested(shop_id: String, npc_id: String)
signal shop_opened(shop_id: String)
signal shop_closed(shop_id: String)

# --- skills and timed effects (Iteration Three) -------------------------------------------------------------
## One SP bought a skill level (SkillBook.learn; emitter: the skill window, MisoSkillsWindow).
signal skill_leveled(skill_id: String, level: int)
## A skill was cast: its costs were paid and its cooldown started (emitter: PlayerSkills).
signal skill_used(skill_id: String, level: int)
## A timed effect (Nimble Feet, Recovery) started or ended (emitters: PlayerSkills, EffectTicker).
signal effects_changed()

# --- persistence / ui ---------------------------------------------------------------------------------------
signal game_saved(slot: String)
signal game_loaded(slot: String)
signal notice(text: String)
