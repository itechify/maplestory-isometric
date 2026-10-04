class_name CreationModel
extends RefCounted
## The character-creation screen without the UI (docs/runtime/GAME_SHELL.md): name, gender, starter weapon and the
## creation AP spread, validated by CharacterFactory and previewed with StatCalculator.compute.
##
## Every number is read, never written here: the starting stats, the creation AP total, the allocatable stats and
## the base HP/MP from canonical formulas/beginner.json; the creation weapons (541 Sword, 576 Hand Axe, 585 Wooden
## Club) and their W.ATK and attack speed from their canonical item records; the name rules and the quick-start
## defaults from data/misostory/new_character.json. The preview works with a partial AP spread, which
## CharacterFactory.create() (exactly creation_ap points) does not.
##
##   var m := CreationModel.new(Data.db)
##   m.name = "Maple"; m.add_ap("dex"); m.weapon_id = "541"
##   m.preview()     # StatCalculator.compute(...) of the character this would create: acc, avoid, damage_min/max ...
##   m.errors()      # [] when Start may be pressed
##   Game.new_game(m.params())

const BEGINNER_FORMULA := "beginner"

var db: ContentDB = null
var name: String = ""
## One of GameState.GENDERS.
var gender: String = ""
var weapon_id: String = ""
## stat -> creation AP placed on top of the canonical starting stats.
var placed: Dictionary = {}


func _init(p_db: ContentDB = null) -> void:
	db = p_db
	gender = GameState.GENDERS[0] if not GameState.GENDERS.is_empty() else ""
	use_defaults()


## The quick-start AP spread and weapon of new_character.json (the Beginner's guide advice); the name is kept.
func use_defaults() -> void:
	var q := CharacterFactory.default_params(db) if db != null else {}
	placed = {}
	for k in stat_keys():
		placed[k] = int((q.get("ap", {}) as Dictionary).get(k, 0))
	weapon_id = String(q.get("weapon_id", ""))
	var ids := CharacterFactory.creation_weapon_ids(db) if db != null else PackedStringArray()
	if not (weapon_id in ids) and not ids.is_empty():
		weapon_id = ids[0]


# --- stats ----------------------------------------------------------------------------------------------------

func beginner() -> Dictionary:
	return db.formula(BEGINNER_FORMULA) if db != null else {}


## The stats creation AP may go into (canonical ap.allocatable_stats), in the canonical order.
func stat_keys() -> PackedStringArray:
	var out: PackedStringArray = []
	for k: Variant in (beginner().get("ap", {}) as Dictionary).get("allocatable_stats", []):
		out.append(str(k))
	return out


func starting_stat(stat: String) -> int:
	return int((beginner().get("starting_stats", {}) as Dictionary).get(stat, 0))


## Starting value + creation AP placed.
func stat_total(stat: String) -> int:
	return starting_stat(stat) + int(placed.get(stat, 0))


## The canonical creation AP (9).
func creation_ap() -> int:
	return int(beginner().get("creation_ap", 0))


func ap_placed() -> int:
	var n := 0
	for k in placed:
		n += int(placed[k])
	return n


func ap_remaining() -> int:
	return creation_ap() - ap_placed()


func can_add(stat: String) -> bool:
	return stat in stat_keys() and ap_remaining() > 0


func can_remove(stat: String) -> bool:
	return int(placed.get(stat, 0)) > 0


## Places `n` more creation AP into `stat` (refused past the creation AP total).
func add_ap(stat: String, n: int = 1) -> bool:
	if n <= 0 or not (stat in stat_keys()) or ap_remaining() < n:
		return false
	placed[stat] = int(placed.get(stat, 0)) + n
	return true


## Takes `n` creation AP back out of `stat` (never below the starting value).
func remove_ap(stat: String, n: int = 1) -> bool:
	if n <= 0 or int(placed.get(stat, 0)) < n:
		return false
	placed[stat] = int(placed[stat]) - n
	return true


## Takes every placed creation AP back.
func clear_ap() -> void:
	for k in stat_keys():
		placed[k] = 0


# --- weapons --------------------------------------------------------------------------------------------------

## The creation weapons with their canonical numbers: [{"id", "name", "subtype", "watk", "speed", "speed_name"}].
func weapons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if db == null:
		return out
	for id in CharacterFactory.creation_weapon_ids(db):
		var d := ItemDef.of(id, db)
		if d == null:
			continue
		out.append({"id": id, "name": d.name, "subtype": d.weapon_type if d.weapon_type != "" else d.subtype,
			"watk": int(d.bonuses.get("watk", 0)), "speed": d.attack_speed, "speed_name": d.attack_speed_name})
	return out


# --- preview and validation -----------------------------------------------------------------------------------

## The derived numbers of the character these choices would create (StatCalculator.compute): "max_hp", "max_mp",
## "acc", "avoid", "watk", "damage_min", "damage_max", the totals ... The weapon goes through the real equip path
## on a scratch character, so the preview equals the created character's StatCalculator.snapshot().
func preview() -> Dictionary:
	if db == null:
		return {}
	var b := beginner()
	var hp_mp: Dictionary = b.get("hp_mp", {})
	var base := {}
	for k in CharacterState.STAT_KEYS:
		base[k] = starting_stat(k) + int(placed.get(k, 0))
	var scratch := CharacterState.new()
	scratch.job = String(b.get("class_slug", scratch.job))
	scratch.level = int(b.get("starting_level", scratch.level))
	scratch.base_stats = base.duplicate()
	if weapon_id in CharacterFactory.creation_weapon_ids(db) and scratch.inventory.add(weapon_id, 1, db) == 1:
		scratch.equipment.equip(scratch, weapon_id, db)
	return StatCalculator.compute(scratch.job, scratch.level, base, int(hp_mp.get("base_hp", 0)),
		int(hp_mp.get("base_mp", 0)), StatCalculator.bonuses(scratch, db), scratch.equipment.weapon_id(), db)


## The parameters for Game.new_game() / CharacterFactory.create().
func params() -> Dictionary:
	var ap := {}
	for k in stat_keys():
		if int(placed.get(k, 0)) > 0:
			ap[k] = int(placed[k])
	return {"name": name, "gender": gender, "ap": ap, "weapon_id": weapon_id}


## Every reason Start is not allowed yet (empty when the character can be created).
func errors() -> PackedStringArray:
	if db == null:
		return PackedStringArray(["no content database"])
	var out := CharacterFactory.validate(params(), db)
	out.append_array(GameState.validate_gender(gender))
	return out


## Only the name problems (shown next to the name field).
func name_errors() -> PackedStringArray:
	return CharacterFactory.validate_name(name, db) if db != null else PackedStringArray()


func is_valid() -> bool:
	return errors().is_empty()
