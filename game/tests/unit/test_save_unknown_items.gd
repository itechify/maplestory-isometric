extends TestCase
## Unknown (orphan) items in a save: an item id the current item data does not define is kept losslessly in its
## inventory slot, equipment slot or quickslot, counted in one load warning and told to the player, shown as
## "Unknown item <id>", and can never be used, equipped or sold (docs/runtime/SAVES.md, "Unknown items").
## The ids below are synthetic, so the proof does not depend on which items the item data defines;
## test_save_it2_fixtures.gd separately checks that every item a real Iteration Two save holds is still defined.

const IT2_FIXTURE := "res://tests/data/saves/it2/d_inventory.json"
const LOST_ETC := "999999"
const LOST_HAT := "999998"

var root := ""
var bus: Node
var notices: Array = []


func parity_keys() -> Dictionary:
	return {
		"test_unknown_items_are_kept_and_counted": ["persistence:orphan-item-ids", "persistence:inventory",
			"persistence:equipment"],
		"test_unknown_items_cannot_be_used_equipped_or_sold": ["persistence:orphan-item-ids"],
		"test_unknown_items_survive_a_save_and_a_reload": ["persistence:orphan-item-ids"],
		"test_unknown_item_icon_and_tooltip": ["persistence:orphan-item-ids"],
		"test_loading_unknown_items_tells_the_player": ["persistence:orphan-item-ids"],
	}


func before_each() -> void:
	root = "user://_tests/save_unknown_%d_%d" % [Time.get_ticks_usec(), randi()]
	bus = load("res://scripts/autoload/events.gd").new()
	notices = []
	bus.connect("notice", func(text: String) -> void: notices.append(text))


func after_each() -> void:
	bus.free()
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(root.path_join(f))
	DirAccess.remove_absolute(root)


## A real Iteration Two save (v1) holding 4 of an unknown Etc item, an unknown hat equipped and the unknown Etc item
## on quickslot 2 (a bare v1 id).
func _doc_with_unknown_items() -> Dictionary:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(IT2_FIXTURE))
	var c: Dictionary = doc["character"]
	(c["inventory"]["slots"]["etc"] as Array).append({"index": 10, "item_id": LOST_ETC, "qty": 4})
	c["equipment"]["slots"]["hat"] = {"item_id": LOST_HAT}
	c["quickslots"]["2"] = LOST_ETC
	return doc


func _pair() -> Array:
	var svc := SaveService.new()
	svc.save_dir = root
	svc.db = db()
	svc.event_bus = bus
	svc.log_failures = false
	svc.can_save_override = func() -> bool: return true
	svc.world_provider = func(ch: CharacterState) -> Dictionary: return SaveDocument.world_from_character(ch)
	var game := GameState.new()
	game.db = db()
	game.save_service = svc
	game.event_bus = bus
	game.log_warnings = false
	svc.game_node = game
	return [svc, game]


func _write(slot: String, doc: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join(slot + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()


func test_unknown_items_are_kept_and_counted() -> void:
	assert_false(db().has("items", LOST_ETC) or db().has("items", LOST_HAT), "the test ids are really unknown")
	var r := SaveDocument.decode(_doc_with_unknown_items(), SaveMigrations.new(), db())
	assert_eq(r.error, OK, "a save with unknown items still loads: %s" % r.message)
	if not r.ok():
		return
	assert_eq(r.unknown_item_ids, PackedStringArray([LOST_HAT, LOST_ETC]), "both ids reported, sorted")
	var counted := Array(r.warnings).filter(func(w: String) -> bool: return w.begins_with(
		"3 saved item place(s) hold 2 item id(s)"))
	assert_eq(counted.size(), 1, "one warning counts the stack, the equipped piece and the quickslot: %s" % str(r.warnings))
	var c := r.character
	assert_eq(c.inventory.count(LOST_ETC), 4, "the stack is kept")
	assert_eq(c.inventory.get_slot("etc", 10), {"item_id": LOST_ETC, "qty": 4, "data": {}}, "in its own slot")
	assert_eq(c.equipment.item_in("hat"), LOST_HAT, "the piece stays equipped")
	assert_eq(c.quickslots.get("2"), {"kind": "item", "id": LOST_ETC}, "the binding is kept (and typed)")
	assert_eq(c.inventory.count("348"), 5, "known items are untouched")
	# Equipment totals ignore the unknown piece instead of failing.
	var eq_only_known := Equipment.new()
	for slot: String in c.equipment.equipped():
		if slot != "hat":
			eq_only_known.force_equip(slot, c.equipment.item_in(slot), db())
	assert_eq(c.equipment.total_bonuses(db()), eq_only_known.total_bonuses(db()), "an unknown piece adds nothing")


func test_unknown_items_cannot_be_used_equipped_or_sold() -> void:
	var c := SaveDocument.decode(_doc_with_unknown_items(), SaveMigrations.new(), db()).character
	var items := ItemService.new(c, db(), bus)
	var used := items.use_item(LOST_ETC)
	assert_false(bool(used.get("ok", true)), "cannot be used")
	assert_eq(String(used.get("code", "")), ItemCodes.UNKNOWN_ITEM, "refused as unknown")
	assert_eq(c.inventory.count(LOST_ETC), 4, "nothing consumed")
	var worn := c.equipment.equip(c, LOST_ETC, db())
	assert_eq(String(worn.get("code", "")), ItemCodes.UNKNOWN_ITEM, "cannot be equipped")
	assert_false(c.equipment.can_equip(c, LOST_HAT, db()), "not even the piece already worn")
	var sold := ShopService.quote_sell(c, "maple-road-pan", LOST_ETC, 1, db())
	assert_eq(String(sold.get("code", "")), ItemCodes.UNKNOWN_ITEM, "cannot be sold")
	assert_false(c.inventory.can_add(LOST_ETC, 1, db()), "and no more can be added")
	assert_eq(c.inventory.count(LOST_ETC), 4, "still all there")


func test_unknown_items_survive_a_save_and_a_reload() -> void:
	_write("lost", _doc_with_unknown_items())
	var a := _pair()
	var game: GameState = a[1]
	assert_eq(game.load_game("lost"), OK, "loads")
	assert_eq(game.save_game("lost"), OK, "saves back")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root.path_join("lost.json")))
	var etc: Array = raw["character"]["inventory"]["slots"]["etc"]
	assert_true(etc.any(func(e: Dictionary) -> bool: return String(e["item_id"]) == LOST_ETC and int(e["qty"]) == 4),
		"the re-save writes the unknown stack unchanged")
	assert_eq(String(raw["character"]["equipment"]["slots"]["hat"]["item_id"]), LOST_HAT, "and the piece")
	var again := (a[0] as SaveService).read_save("lost")
	assert_eq(again.unknown_item_ids, PackedStringArray([LOST_HAT, LOST_ETC]), "still reported after the round trip")
	assert_eq(again.character.inventory.count(LOST_ETC), 4)
	for n in a:
		(n as Node).free()


func test_unknown_item_icon_and_tooltip() -> void:
	var rows := MisoItemTooltip.describe(LOST_ETC, CharacterState.new(), db(), {"qty": 4})
	assert_eq(rows[0], {"text": "Unknown item %s (x4)" % LOST_ETC, "tone": "title"}, "the title names the id")
	var texts: PackedStringArray = []
	for r: Dictionary in rows:
		texts.append(String(r["text"]))
	assert_true("Kept from your save. It cannot be used, equipped or sold." in texts, "says what it is: %s" % str(texts))
	var worn := MisoItemTooltip.describe(LOST_HAT, CharacterState.new(), db(), {"equipped": true})
	assert_eq(String(worn[0]["text"]), "Unknown item %s" % LOST_HAT)
	assert_true(worn.any(func(r: Dictionary) -> bool: return r["text"] == "Equipped"), "an equipped one says so")
	var icon := MisoItemIcon.new()
	icon.set_item(LOST_ETC, db())
	assert_eq(icon.shape, "unknown", "a '?' token")
	assert_eq(icon.color, MisoItemIcon.UNKNOWN_COLOR, "in neutral grey")
	icon.set_item("348", db())
	assert_ne(icon.shape, "unknown", "a known item draws its own shape")
	icon.free()


func test_loading_unknown_items_tells_the_player() -> void:
	_write("lost", _doc_with_unknown_items())
	var a := _pair()
	var game: GameState = a[1]
	assert_eq(game.load_game("lost"), OK)
	var told := notices.filter(func(t: String) -> bool: return t.contains("2 item(s) this version does not know"))
	assert_eq(told.size(), 1, "one notice: %s" % str(notices))
	notices.clear()
	_write("fine", JSON.parse_string(FileAccess.get_file_as_string(IT2_FIXTURE)))
	assert_eq(game.load_game("fine"), OK)
	assert_eq(notices.filter(func(t: String) -> bool: return t.contains("does not know")).size(), 0,
		"no notice when every item is known")
	for n in a:
		(n as Node).free()
