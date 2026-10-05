class_name CharacterFactory
extends RefCounted
## Builds a brand-new level-1 Beginner from the creation screen's choices (pure rules, no scene tree).
##
## Input `params`: {"name": String, "ap": {"str"|"dex"|"int"|"luk": int}, "weapon_id": String}.
##   - "ap" is the creation AP placed on top of the canonical starting stats; it must total exactly the canonical
##     creation_ap (formulas/beginner.json) over the canonical allocatable stats, each part a whole number >= 0.
##   - "weapon_id" must be one of the canonical creation weapons (items flagged beginner_creation_weapon).
##   - "name" follows the adaptation name_rules (data/misostory/new_character.json).
## Every canonical number comes from ContentDB (formulas/beginner.json, the items domain, the start map's
## return_map_id); values MeowDB does not publish come from data/misostory/new_character.json. See docs/runtime/SAVES.md.

const RULES_TABLE := "new_character"
const BEGINNER_FORMULA := "beginner"

## Where the starter weapon ended up.
const PLACED_EQUIPPED := "equipped"
const PLACED_INVENTORY := "inventory"
const PLACED_NONE := "none"


## The outcome of create(): the character when ok, otherwise every validation error.
class Creation:
	extends RefCounted
	var ok: bool = false
	var character: CharacterState = null
	var errors: PackedStringArray = []
	## Non-fatal notes, e.g. "weapon placed in the inventory because Equipment cannot equip yet".
	var warnings: PackedStringArray = []
	## PLACED_EQUIPPED, PLACED_INVENTORY or PLACED_NONE.
	var weapon_placement: String = ""


## Validates `params` and builds the character. Never returns null; check `.ok` and `.errors`.
static func create(params: Dictionary, db: ContentDB) -> Creation:
	var out := Creation.new()
	out.errors = validate(params, db)
	if not out.errors.is_empty():
		return out
	var beginner := db.formula(BEGINNER_FORMULA)
	var rules := rules_table(db)
	var hp_mp: Dictionary = beginner.get("hp_mp", {})
	var ap_rules: Dictionary = beginner.get("ap", {})

	var c := CharacterState.new()
	c.name = String(params.get("name", ""))
	c.job = String(beginner.get("class_slug", c.job))
	c.level = int(beginner.get("starting_level", 1))
	c.exp = int(_rule_value(rules, "starting_exp"))
	c.base_max_hp = int(hp_mp.get("base_hp", c.base_max_hp))
	c.base_max_mp = int(hp_mp.get("base_mp", c.base_max_mp))
	var start_stats: Dictionary = beginner.get("starting_stats", {})
	var placed: Dictionary = params.get("ap", {})
	for key in CharacterState.STAT_KEYS:
		c.base_stats[key] = int(start_stats.get(key, 0)) + int(placed.get(key, 0))
	# Free AP after creation = the canonical free AP at level 1 minus the creation AP the player just placed.
	c.ap = maxi(0, int(ap_rules.get("free_ap_at_level_1", 0)) - int(beginner.get("creation_ap", 0)))
	c.sp = int(_rule_value(rules, "starting_sp"))
	c.fame = int(_rule_value(rules, "starting_fame"))
	c.mesos = int(_rule_value(rules, "starting_mesos"))
	c.location = start_location(db)
	c.respawn_reference = String(db.map(c.location.get("map_id", "")).get("return_map_id", ""))
	c.play_time_s = 0.0

	var starting_items: Array = (rules.get("starting_inventory", {}) as Dictionary).get("items", [])
	for entry in starting_items:
		if entry is Dictionary:
			var item_id := String(entry.get("item_id", ""))
			var qty := int(entry.get("qty", 1))
			if c.inventory.add(item_id, qty, db) < qty:
				out.warnings.append("starting item %s x%d did not fit in the inventory" % [item_id, qty])

	_place_starter_weapon(c, String(params.get("weapon_id", "")), db, rules, out)
	# Full vitals = the derived maxima (base + equipment + effects); the starter gear adds no HP/MP, so this is
	# base_hp / base_mp today, but stays right if the starting kit ever gains HP/MP gear.
	c.hp = StatCalculator.max_hp(c, db)
	c.mp = StatCalculator.max_mp(c, db)
	out.character = c
	out.ok = true
	return out


## Every problem with `params` (empty when they are valid).
static func validate(params: Dictionary, db: ContentDB) -> PackedStringArray:
	var errors: PackedStringArray = []
	if db == null or db.formula(BEGINNER_FORMULA).is_empty():
		errors.append("canonical formulas/beginner.json is not loaded")
		return errors
	if rules_table(db).is_empty():
		errors.append("data/misostory/new_character.json is not loaded")
		return errors
	errors.append_array(validate_start_location(db))
	errors.append_array(validate_name(params.get("name", null), db))
	errors.append_array(validate_creation_ap(params.get("ap", null), db))
	errors.append_array(validate_weapon(params.get("weapon_id", null), db))
	return errors


## Name rules (adaptation, new_character.json name_rules): length and character set.
static func validate_name(value: Variant, db: ContentDB) -> PackedStringArray:
	var errors: PackedStringArray = []
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		errors.append("name must be a string")
		return errors
	var text := String(value)
	var rules: Dictionary = rules_table(db).get("name_rules", {})
	var min_len := int(rules.get("min_length", 1))
	var max_len := int(rules.get("max_length", 64))
	if text.length() < min_len or text.length() > max_len:
		errors.append("name must be %d to %d characters (got %d)" % [min_len, max_len, text.length()])
	var pattern := String(rules.get("pattern", ""))
	if pattern != "":
		var re := RegEx.create_from_string(pattern)
		if re == null or not re.is_valid():
			errors.append("name_rules.pattern is not a valid regular expression")
		else:
			# PCRE's "$" also matches before a trailing newline, so the match must cover the whole name.
			var m := re.search(text)
			if m == null or m.get_string() != text:
				errors.append("name may only use letters A-Z, a-z and digits 0-9")
	return errors


## Creation AP: a Dictionary over the canonical allocatable stats, whole numbers >= 0, totalling exactly creation_ap.
static func validate_creation_ap(value: Variant, db: ContentDB) -> PackedStringArray:
	var errors: PackedStringArray = []
	var beginner := db.formula(BEGINNER_FORMULA)
	var required := int(beginner.get("creation_ap", 0))
	var allowed: Array = (beginner.get("ap", {}) as Dictionary).get("allocatable_stats", [])
	if not (value is Dictionary):
		errors.append("ap must be a dictionary of stat -> points (%d in total)" % required)
		return errors
	var placed: Dictionary = value
	var total := 0
	for key in placed:
		var points: Variant = placed[key]
		if not (str(key) in allowed):
			errors.append("ap: '%s' is not an allocatable stat (%s)" % [str(key), ", ".join(PackedStringArray(allowed))])
			continue
		if not _is_whole_number(points):
			errors.append("ap: %s must be a whole number" % str(key))
			continue
		if int(points) < 0:
			errors.append("ap: %s cannot be negative" % str(key))
			continue
		total += int(points)
	if errors.is_empty() and total != required:
		errors.append("ap: exactly %d creation AP must be placed (got %d)" % [required, total])
	return errors


## The starter weapon must be one of the canonical creation weapons.
static func validate_weapon(value: Variant, db: ContentDB) -> PackedStringArray:
	var errors: PackedStringArray = []
	var choices := creation_weapon_ids(db)
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		errors.append("weapon_id must be a string item id (one of %s)" % ", ".join(choices))
	elif not (String(value) in choices):
		errors.append("weapon_id %s is not a creation weapon (one of %s)" % [String(value), ", ".join(choices)])
	return errors


## The creation weapon item ids (canonical items flagged beginner_creation_weapon), sorted.
static func creation_weapon_ids(db: ContentDB) -> PackedStringArray:
	var out: PackedStringArray = []
	var items := db.domain("items")
	for id in items:
		var rec: Dictionary = items[id]
		if bool(rec.get("beginner_creation_weapon", false)):
			out.append(String(id))
	out.sort()
	return out


## The adaptation table data/misostory/new_character.json ({} when missing).
static func rules_table(db: ContentDB) -> Dictionary:
	var t: Variant = db.miso_table(RULES_TABLE)
	return t if t is Dictionary else {}


## The adaptation start location must name a canonical map and one of its player spawns (empty when it does).
static func validate_start_location(db: ContentDB) -> PackedStringArray:
	var errors: PackedStringArray = []
	var start := start_location(db)
	var map_id := String(start["map_id"])
	if map_id == "" or not db.has("maps", map_id):
		errors.append("new_character.json start_location.map_id '%s' is not a canonical map" % map_id)
		return errors
	var spawns: Array = db.map(map_id).get("player_spawns", [])
	var index := int((start["entry"] as Dictionary)["spawn_index"])
	if index < 0 or index >= spawns.size():
		errors.append("new_character.json start_location.spawn_index %d is not one of map %s's %d player spawns"
			% [index, map_id, spawns.size()])
	return errors


## A new character's logical location (MAP_ARCHITECTURE.md §4.9): {"map_id", "entry": {"map_id", "spawn_index"}}.
static func start_location(db: ContentDB) -> Dictionary:
	var start: Dictionary = rules_table(db).get("start_location", {})
	var map_id := String(start.get("map_id", ""))
	return {"map_id": map_id, "entry": {"map_id": map_id, "spawn_index": int(start.get("spawn_index", 0))}}


## Valid parameters for a quick start (debug, boot without a creation screen); see new_character.json quick_start.
static func default_params(db: ContentDB) -> Dictionary:
	var q: Dictionary = rules_table(db).get("quick_start", {})
	return {
		"name": String(q.get("name", "")),
		"ap": (q.get("ap", {}) as Dictionary).duplicate(),
		"weapon_id": String(q.get("weapon_id", "")),
	}


# --- internals ------------------------------------------------------------------------------------------------

## The weapon goes into the inventory (Inventory.add), then, when the placement rule says "equipped", through the
## items system's own equip path, Equipment.equip(character, item_id, db), which moves it from the bag to the weapon
## slot after the canonical requirement checks. If equipping fails the weapon stays in the bag (with a warning).
static func _place_starter_weapon(c: CharacterState, weapon_id: String, db: ContentDB, rules: Dictionary,
		out: Creation) -> void:
	if c.inventory.add(weapon_id, 1, db) != 1:
		out.weapon_placement = PLACED_NONE
		out.warnings.append("starter weapon %s could not be placed (Inventory.add accepted nothing)" % weapon_id)
		return
	out.weapon_placement = PLACED_INVENTORY
	var placement := String((rules.get("starter_weapon", {}) as Dictionary).get("placement", PLACED_EQUIPPED))
	if placement != PLACED_EQUIPPED:
		return
	var result: Dictionary = c.equipment.equip(c, weapon_id, db)
	if bool(result.get("ok", false)) and c.equipment.weapon_id() == weapon_id:
		out.weapon_placement = PLACED_EQUIPPED
	else:
		out.warnings.append("starter weapon %s could not be equipped (%s); it stays in the inventory"
			% [weapon_id, String(result.get("code", "unknown"))])


static func _rule_value(rules: Dictionary, key: String) -> Variant:
	return (rules.get(key, {}) as Dictionary).get("value", 0)


static func _is_whole_number(v: Variant) -> bool:
	if typeof(v) == TYPE_INT:
		return true
	if typeof(v) == TYPE_FLOAT:
		var f: float = v
		return is_finite(f) and f == floorf(f)
	return false
