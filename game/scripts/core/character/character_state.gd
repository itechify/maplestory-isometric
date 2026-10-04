class_name CharacterState
extends RefCounted
## The player character's logical, persistent state: everything a save file holds about the character.
##
## Holds BASE values only (what the player earned or placed). Totals that include equipment and buffs (max HP,
## total STR, ACC, W.ATK ...) are derived on demand by the stat calculator, never stored, so a save can never
## contain a stale derived number. Composed modules (inventory, equipment, quest log) own their own serialization.
##
## Every field here is serialized by to_dict(); add new fields with a default so older saves still load, and bump
## SaveService's schema version with a migration when a field changes meaning.

const STAT_KEYS: PackedStringArray = ["str", "dex", "int", "luk"]

var name: String = ""
## "male" / "female" (chosen at creation; gendered equipment checks it), or "" when unknown.
var gender: String = ""
## Canonical class slug (MeowDB /classes): "beginner" for all of Iteration Two.
var job: String = "beginner"
var level: int = 1
## EXP toward the next level (MeowDB's table is "EXP to next level").
var exp: int = 0
var hp: int = 50
var mp: int = 5
## Max HP/MP from level-ups and job gains, before equipment and buffs (MeowDB: BeginnerHP = 50 + 16 × (Level - 1)).
var base_max_hp: int = 50
var base_max_mp: int = 5
## Base primary stats: the starting 4/4/4/4 plus every AP placed (never equipment).
var base_stats: Dictionary = {"str": 4, "dex": 4, "int": 4, "luk": 4}
## Unspent ability points and skill points.
var ap: int = 0
var sp: int = 0
var fame: int = 0
var mesos: int = 0
## skill_id -> level (Beginner skills; future jobs).
var skills: Dictionary = {}
## Active timed effects (future: buffs, debuffs, status). Each entry is a Dictionary owned by the effect system.
var effects: Array = []

var inventory: Inventory = Inventory.new()
var equipment: Equipment = Equipment.new()
var quests: QuestLog = QuestLog.new()

## Logical location (MAP_ARCHITECTURE.md §4.9): {"map_id", "entry": {...}, "resume": {...}?}. Owned by MapSession.
var location: Dictionary = {}
## Canonical returnMap of the current map (recomputed on load; saved because the brief requires it).
var respawn_reference: String = ""
## Quickslot bindings: slot index (String) -> item id. Presentation preference, but saved.
var quickslots: Dictionary = {}
## Free-form progression flags for scripted content (e.g. "tutorial_seen").
var flags: Dictionary = {}
var play_time_s: float = 0.0


func get_base_stat(key: String) -> int:
	return int(base_stats.get(key, 0))


func to_dict() -> Dictionary:
	return {
		"name": name,
		"gender": gender,
		"job": job,
		"level": level,
		"exp": exp,
		"hp": hp,
		"mp": mp,
		"base_max_hp": base_max_hp,
		"base_max_mp": base_max_mp,
		"base_stats": base_stats.duplicate(),
		"ap": ap,
		"sp": sp,
		"fame": fame,
		"mesos": mesos,
		"skills": skills.duplicate(true),
		"effects": effects.duplicate(true),
		"inventory": inventory.to_dict(),
		"equipment": equipment.to_dict(),
		"quests": quests.to_dict(),
		"location": location.duplicate(true),
		"respawn_reference": respawn_reference,
		"quickslots": quickslots.duplicate(),
		"flags": flags.duplicate(true),
		"play_time_s": play_time_s,
	}


static func from_dict(d: Dictionary) -> CharacterState:
	var c := CharacterState.new()
	c.name = String(d.get("name", ""))
	c.gender = String(d.get("gender", ""))
	c.job = String(d.get("job", "beginner"))
	c.level = int(d.get("level", 1))
	c.exp = int(d.get("exp", 0))
	c.hp = int(d.get("hp", 50))
	c.mp = int(d.get("mp", 5))
	c.base_max_hp = int(d.get("base_max_hp", 50))
	c.base_max_mp = int(d.get("base_max_mp", 5))
	var bs: Dictionary = d.get("base_stats", {})
	for k in STAT_KEYS:
		c.base_stats[k] = int(bs.get(k, 4))
	c.ap = int(d.get("ap", 0))
	c.sp = int(d.get("sp", 0))
	c.fame = int(d.get("fame", 0))
	c.mesos = int(d.get("mesos", 0))
	c.skills = (d.get("skills", {}) as Dictionary).duplicate(true)
	c.effects = (d.get("effects", []) as Array).duplicate(true)
	c.inventory = Inventory.from_dict(d.get("inventory", {}))
	c.equipment = Equipment.from_dict(d.get("equipment", {}))
	c.quests = QuestLog.from_dict(d.get("quests", {}))
	c.location = (d.get("location", {}) as Dictionary).duplicate(true)
	c.respawn_reference = String(d.get("respawn_reference", ""))
	c.quickslots = (d.get("quickslots", {}) as Dictionary).duplicate()
	c.flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	c.play_time_s = float(d.get("play_time_s", 0.0))
	return c
