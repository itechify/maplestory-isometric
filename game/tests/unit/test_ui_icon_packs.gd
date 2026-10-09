extends TestCase
## Item and skill icons resolve through layered icon packs over the procedural base (#49, docs/runtime/UI.md "Icon
## packs"). Every pack here is a fake one the test writes to a private folder (solid-colour PNGs made with
## Image.create). Those under user:// load through the raw-PNG path: a PNG made at runtime was never imported, so
## ResourceLoader cannot load it. The one res:// pack stands in for the bundled pack in an exported build, where only
## the imported copies are left: the test writes each imported texture and its .import remap itself. No network and
## no Nexon art. The shared resolver is swapped for the test's own and restored after every test.

const RED_POTION := "270"       # game_item_id 2000000, 27 x 30, origin (-3, 30)
const SNAIL_SHELL := "348"      # game_item_id 4000001, 26 x 27, origin (-4, 27)
const EGG := "237"              # game_item_id 2010002, in no fake pack
const SNAILS := "0001000"
const RECOVERY := "0001001"
const RED := Color(1, 0, 0)
const BLUE := Color(0, 0, 1)
const GREEN := Color(0, 1, 0)

## The private folders the fake packs live in (removed after each test). res_root is under res://.godot/, the import
## cache, which git and the editor's file scan both skip.
var root := ""
var res_root := ""
var nodes: Array = []


func before_each() -> void:
	var run := "icon_packs_%d_%d" % [Time.get_ticks_usec(), randi()]
	root = "user://_tests".path_join(run)
	res_root = "res://.godot/_tests".path_join(run)
	MisoIconResolver.set_shared(null)


func after_each() -> void:
	MisoIconResolver.set_shared(null)
	nodes.reverse()
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	_remove_tree(root)
	_remove_tree(res_root)


## A fake pack `pack_name` in format 1, in `base` (default root). entries: [{kind, id, variant, size: Vector2i, color,
## origin (optional), png (default true: false lists the entry in pack.json without its PNG, as a fresh clone has it),
## imported (default false: true leaves only the imported copy of the PNG, as an exported build has it)}].
func _pack(pack_name: String, entries: Array, base: String = "") -> String:
	var dir := (base if base != "" else root).path_join(pack_name)
	var manifest := {"format": 1, "name": pack_name, "source": {"service": "test"}, "items": {}, "skills": {},
		"missing": []}
	for e: Dictionary in entries:
		var size: Vector2i = e["size"]
		var entry := {"size": [size.x, size.y], "sha256": "", "url": "", "fetched": "2026-10-09"}
		if e.has("origin"):
			entry["origin"] = e["origin"]
		var kind: Dictionary = manifest[e["kind"]]
		if not kind.has(e["id"]):
			kind[e["id"]] = {}
		kind[e["id"]][e.get("variant", "icon")] = entry
		if e.get("png", true):
			var folder := dir.path_join("%s/%s" % [e["kind"], e["id"]])
			DirAccess.make_dir_recursive_absolute(folder)
			var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
			img.fill(e.get("color", RED))
			var png := folder.path_join("%s.png" % e.get("variant", "icon"))
			if e.get("imported", false):
				_write_imported(png, img)
			else:
				assert_eq(img.save_png(png), OK, "PNG written")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join("pack.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	return dir


## What an exported build holds for the PNG `png` of a res:// pack: the imported texture and the .import remap that
## leads ResourceLoader to it, but not the .png. The editor imports to a .ctex; a saved ImageTexture stands in for it.
func _write_imported(png: String, img: Image) -> void:
	var tex := png.get_basename() + ".res"
	assert_eq(ResourceSaver.save(ImageTexture.create_from_image(img), tex), OK, "imported texture written")
	var f := FileAccess.open(png + ".import", FileAccess.WRITE)
	f.store_string('[remap]\n\nimporter="texture"\ntype="ImageTexture"\npath="%s"\n' % tex)
	f.close()


func _item(game_item_id: String, size: Vector2i, color: Color, origin: Variant = null,
		variant: String = "icon") -> Dictionary:
	var e := {"kind": "items", "id": game_item_id, "variant": variant, "size": size, "color": color}
	if origin != null:
		e["origin"] = origin
	return e


func _skill(skill_id: String, color: Color, variant: String = "icon") -> Dictionary:
	return {"kind": "skills", "id": skill_id, "variant": variant, "size": Vector2i(32, 32), "color": color}


## The resolver over `pack_roots`, made the one the UI draws from.
func _use(pack_roots: Array) -> MisoIconResolver:
	var r := MisoIconResolver.new(PackedStringArray(pack_roots))
	MisoIconResolver.set_shared(r)
	return r


func _keep(n: Node) -> Node:
	nodes.append(n)
	return n


func _item_icon(item_id: String, box: float = 32.0) -> MisoItemIcon:
	var icon: MisoItemIcon = _keep(MisoItemIcon.new())
	icon.set_item(item_id, db())
	icon.size = Vector2(box, box)
	return icon


func _colour_of(art: MisoIconResolver.Art) -> Color:
	return art.texture.get_image().get_pixel(0, 0)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for d in dir.get_directories():
		_remove_tree(path.path_join(d))
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


# --- layering ------------------------------------------------------------------------------------------------------

func test_a_pack_icon_replaces_the_procedural_one() -> void:
	_use([_pack("fake", [_item("2000000", Vector2i(27, 30), RED, [-3, 30]), _skill(SNAILS, GREEN)])])
	var potion := _item_icon(RED_POTION)
	assert_eq(potion.game_item_id, "2000000", "items are keyed by game_item_id, not the record id")
	assert_true(potion.art != null, "Red Potion draws the pack's icon")
	assert_eq(Vector2i(potion.art.texture.get_size()), Vector2i(27, 30), "the pack's PNG")
	assert_eq(_colour_of(potion.art), RED)
	assert_eq(potion.shape, "potion", "the procedural shape stays underneath (tests, the drag preview)")
	assert_eq(potion.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "pack art is drawn with nearest filtering")
	var skill: MisoSkillIcon = _keep(MisoSkillIcon.new())
	skill.skill_id = SNAILS
	assert_true(skill.art != null, "Three Snails draws the pack's icon")
	assert_eq(_colour_of(skill.art), GREEN)
	assert_eq(skill.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	skill.skill_id = RECOVERY
	assert_eq(skill.art, null, "Recovery is in no pack: the procedural badge")
	assert_eq(skill.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE, "and today's filtering")


func test_a_missing_id_or_variant_falls_through_to_the_next_pack_and_the_base() -> void:
	var first := _pack("first", [_item("2000000", Vector2i(27, 30), BLUE, [-3, 30]),
		_item("4000001", Vector2i(26, 27), BLUE, [-4, 27]).merged({"png": false})])
	var second := _pack("second", [_item("2000000", Vector2i(27, 30), RED, [-3, 30]),
		_item("2000000", Vector2i(25, 28), RED, [-4, 29], "iconRaw"), _item("4000001", Vector2i(26, 27), GREEN, [-4, 27])])
	var r := _use([first, root.path_join("not_there"), second])
	assert_eq(_colour_of(r.art("items", "2000000")), BLUE, "the first pack with the PNG wins")
	assert_eq(_colour_of(r.art("items", "2000000", "iconRaw")), RED, "a variant the first pack lacks comes from the next")
	assert_eq(_colour_of(r.art("items", "4000001")), GREEN, "an entry without its PNG falls through")
	assert_eq(r.art("items", "2010002"), null, "an id no pack has: no art")
	assert_eq(r.art("skills", SNAILS), null, "nor a skill no pack has")
	assert_eq(r.art("skills", "?"), null, "an id that is no file name never reaches the disk")
	assert_eq(r.art("items", "../first/items/2000000"), null, "nor a path")
	assert_true(is_same(r.art("items", "2000000"), r.art("items", "2000000")), "loaded once, then cached")
	var egg := _item_icon(EGG)
	assert_eq(egg.art, null, "the Egg is in no pack")
	assert_eq(egg.shape, "egg", "so its procedural icon draws")
	assert_eq(egg.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE, "with today's filtering")
	assert_eq(_item_icon(SNAIL_SHELL).art.offset, Vector2i(4, 5), "the second pack's Snail Shell, placed by its origin")


func test_with_no_pack_pngs_every_icon_is_drawn_procedurally() -> void:
	assert_eq(MisoIconResolver.listed_roots(), PackedStringArray(["res://assets/icon_packs/maplestory_io"]),
		"data/misostory/icon_packs.json lists the maplestory.io pack")
	# A fresh clone: the tracked pack.json lists every item and skill, and no PNG is there.
	var entries: Array = []
	for id in db().ids("items"):
		var e := _item(ItemDef.of(id, db()).game_item_id, Vector2i(32, 32), RED, [0, 32])
		e["png"] = false
		entries.append(e)
	for s: SkillDef in SkillDef.catalog("beginner", db()):
		entries.append(_skill(s.id, GREEN).merged({"png": false}))
	_use([_pack("clone", entries), root.path_join("missing_pack")])
	for id in db().ids("items"):
		var icon := _item_icon(id)
		assert_eq(icon.art, null, "item %s has no art" % id)
		assert_ne(icon.shape, "unknown", "item %s draws its procedural shape" % id)
		assert_eq(icon.texture_filter, CanvasItem.TEXTURE_FILTER_PARENT_NODE, "item %s keeps today's filtering" % id)
		icon.free()
	nodes.clear()
	for s: SkillDef in SkillDef.catalog("beginner", db()):
		var skill: MisoSkillIcon = _keep(MisoSkillIcon.new())
		skill.skill_id = s.id
		assert_eq(skill.art, null, "skill %s draws its badge" % s.id)
	assert_eq(MisoIconResolver.new(PackedStringArray([root.path_join("nothing")])).art("items", "2000000"), null,
		"a pack folder that is not there is no pack")


func test_a_res_pack_loads_only_imported_textures() -> void:
	# The bundled pack in an exported build: the Red Potion only as its imported copy, the Snail Shell as a raw PNG
	# that was never imported, the Egg listed without a PNG.
	var pack := _pack("bundled", [_item("2000000", Vector2i(27, 30), RED, [-3, 30]).merged({"imported": true}),
		_item("4000001", Vector2i(26, 27), BLUE, [-4, 27]),
		_item("2010002", Vector2i(32, 32), GREEN).merged({"png": false})], res_root)
	var r := MisoIconResolver.new(PackedStringArray([pack]))
	assert_false(FileAccess.file_exists(pack.path_join("items/2000000/icon.png")), "the Red Potion's .png is not there")
	var potion := r.art("items", "2000000")
	assert_true(potion != null, "but ResourceLoader finds and loads its imported copy")
	assert_eq(_colour_of(potion), RED)
	assert_eq(potion.offset, Vector2i(3, 2), "placed by its origin")
	assert_true(FileAccess.file_exists(pack.path_join("items/4000001/icon.png")), "the Snail Shell's .png is there")
	assert_eq(r.art("items", "4000001"), null, "but a res:// pack never loads a raw PNG")
	assert_eq(r.art("items", "2010002"), null, "an entry without its PNG falls through")


func test_the_pack_list_names_folders_in_order() -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var list := root.path_join("icon_packs.json")
	var f := FileAccess.open(list, FileAccess.WRITE)
	f.store_string(JSON.stringify({"packs": ["mine", "maplestory_io", "../elsewhere", 7]}))
	f.close()
	assert_eq(MisoIconResolver.listed_roots(list, "user://packs"),
		PackedStringArray(["user://packs/mine", "user://packs/maplestory_io"]), "names only, highest priority first")
	assert_eq(MisoIconResolver.listed_roots(root.path_join("none.json")), PackedStringArray(), "no list, no packs")
	var other := _pack("other", [_item("2000000", Vector2i(27, 30), RED)])
	var manifest := FileAccess.open(other.path_join("pack.json"), FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"format": 2, "items": {}}))
	manifest.close()
	assert_eq(MisoIconResolver.new(PackedStringArray([other])).art("items", "2000000"), null,
		"a pack of another format is skipped")


# --- display rules -------------------------------------------------------------------------------------------------

func test_the_origin_places_item_art_in_the_cell() -> void:
	_use([_pack("fake", [_item("2000000", Vector2i(27, 30), RED, [-3, 30]),
		_item("4000001", Vector2i(26, 27), RED, [-4, 27]), _item("2010002", Vector2i(20, 24), RED),
		_skill(SNAILS, GREEN)])])
	var potion := _item_icon(RED_POTION)
	assert_eq(potion.art_rect(), Rect2(3, 2, 27, 30), "Red Potion (27 x 30, origin -3, 30) sits at (3, 2)")
	assert_eq(potion.art_rect().end.y, 32.0, "its bottom on the cell's bottom edge")
	var shell := _item_icon(SNAIL_SHELL)
	assert_eq(shell.art_rect(), Rect2(4, 5, 26, 27), "Snail Shell (26 x 27, origin -4, 27) sits at (4, 5)")
	assert_eq(shell.art_rect().end.y, 32.0, "the same baseline")
	assert_eq(_item_icon(EGG).art_rect(), Rect2(6, 4, 20, 24), "an entry without an origin is centred")
	assert_eq(MisoIconResolver.cell_offset(Vector2i(33, 35), [0, 35]), Vector2i(0, -3),
		"art taller than the cell pokes over its top, unclipped (The Spear)")
	assert_eq(MisoIconResolver.cell_offset(Vector2i(27, 30), [-3]), Vector2i(2, 1), "a malformed origin is no origin")
	var skill: MisoSkillIcon = _keep(MisoSkillIcon.new())
	skill.skill_id = SNAILS
	skill.size = Vector2(32, 32)
	assert_eq(skill.art_rect(), Rect2(0, 0, 32, 32), "a 32 x 32 skill fills the cell")


func test_art_scales_by_whole_multiples_with_nearest_filtering_except_the_effects_bar() -> void:
	_use([_pack("fake", [_item("2000000", Vector2i(27, 30), RED, [-3, 30]), _skill(SNAILS, GREEN)])])
	var potion := _item_icon(RED_POTION)
	# The boxes the UI draws items in: the quickslot's icon (32), a skill's (36), the inventory's (38), the tooltip's
	# (44), the shop detail (64), and boxes in between.
	for box in [32.0, 36.0, 38.0, 42.0, 44.0, 63.0, 64.0, 70.0, 100.0]:
		potion.size = Vector2(box, box)
		var k := maxi(1, floori(box / 32.0))
		var cell := floorf((box - 32.0 * k) / 2.0)
		assert_eq(potion.art_rect(), Rect2(Vector2(cell, cell) + Vector2(3, 2) * k, Vector2(27, 30) * k),
			"a %d px box draws the cell at %dx on whole pixels" % [box, k])
	potion.size = Vector2(26, 26)
	assert_eq(potion.art_rect().size, Vector2(27, 30), "never below 1x")
	assert_eq(potion.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "nearest filtering")
	var skill: MisoSkillIcon = _keep(MisoSkillIcon.new())
	skill.skill_id = SNAILS
	skill.size = Vector2(40, 40)
	assert_eq(skill.art_rect(), Rect2(4, 4, 32, 32), "a 40 px skill slot draws the cell at 1x")
	skill.size = Vector2(64, 64)
	assert_eq(skill.art_rect(), Rect2(0, 0, 64, 64), "2x")
	# The effects bar is the one exception: its 40 px icon box is filled.
	var bar: MisoEffectsBar = _keep(MisoEffectsBar.new())
	var cell_node: Control = _keep(bar._make_cell("skill:" + SNAILS))
	var effect: MisoSkillIcon = cell_node.get_node("Icon")
	assert_true(effect.fill, "the effects bar's icons fill their box")
	effect.skill_id = SNAILS
	effect.size = Vector2(MisoEffectsBar.ICON_SIZE, MisoEffectsBar.ICON_SIZE)
	assert_eq(effect.art_rect(), Rect2(0, 0, 40, 40), "stretched over the whole 40 px box")
	assert_eq(effect.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "still with nearest filtering")


func test_the_slots_draw_the_cell_at_1x() -> void:
	_use([_pack("fake", [_item("2000000", Vector2i(27, 30), RED, [-3, 30]), _skill(SNAILS, GREEN)])])
	var ui: Control = Control.new()
	ui.theme = MisoTheme.get_theme()
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(ui)
	_keep(ui)
	var bag := MisoItemSlot.new(MisoInventoryWindow.SLOT_SIZE)
	var quick_item := MisoQuickslotBar.QuickslotCell.new(MisoQuickslotBar.SLOT_SIZE)
	var quick_skill := MisoQuickslotBar.QuickslotCell.new(MisoQuickslotBar.SLOT_SIZE)
	var learned := MisoSkillsWindow.SkillIconCell.new(SNAILS)
	var tip := MisoItemTooltip.new()
	for c: Control in [bag, quick_item, quick_skill, learned, tip]:
		ui.add_child(c)
	bag.set_stack(RED_POTION, 1, db())
	quick_item.set_stack(RED_POTION, 1, db(), {}, true)
	quick_skill.set_skill(SNAILS, true, 0.0, 0.0)
	tip.show_item(RED_POTION, CharacterState.new(), db())
	for c: Control in [bag, quick_item, quick_skill, learned, tip]:
		c.size = c.get_combined_minimum_size()
		c.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	# The boxes UI.md "Icon packs" lists: each shows the 32 px cell at 1x, centred on whole pixels.
	for pair: Array in [["an inventory slot", bag.icon, Vector2(38, 38)],
			["an item quickslot", quick_item.icon, Vector2(32, 32)],
			["a skill quickslot", quick_skill.skill_icon, Vector2(36, 36)],
			["the Skills window", learned.icon, Vector2(36, 36)]]:
		var icon: Control = pair[1]
		assert_eq(icon.size, pair[2], "%s's icon box" % pair[0])
		var cell := floorf((pair[2].x - 32.0) / 2.0)
		var art_at: Vector2 = Vector2(3, 2) if icon is MisoItemIcon else Vector2.ZERO
		assert_eq(icon.call("art_rect").position, Vector2(cell, cell) + art_at, "%s draws the cell at 1x" % pair[0])
	assert_eq(tip._icon.size.x, 44.0, "the tooltip's icon box")
	assert_eq(tip._icon.art_rect().size, Vector2(27, 30), "the tooltip draws the cell at 1x")


func test_quest_reward_and_shop_icons_are_32_px_and_the_shop_detail_64() -> void:
	_use([_pack("fake", [_item("2000000", Vector2i(27, 30), RED, [-3, 30])])])
	var ql: MisoQuestWindow = _keep(MisoQuestWindow.new())
	var row: Control = _keep(ql._item_row(EGG, 5, db()))
	var reward: MisoItemIcon = row.get_child(0)
	assert_eq(reward.custom_minimum_size, Vector2(32, 32), "a quest reward's icon box is the 32 px cell")
	var shop := ShopWindow.new()
	shop.db = db()
	shop.bus = _keep(load("res://scripts/autoload/events.gd").new())
	shop.character_provider = func() -> CharacterState: return CharacterState.new()
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(shop)
	_keep(shop)
	assert_true(shop.open_shop("maple-road-lucy"))
	for r: Control in shop._rows:
		var icons := r.find_children("*", "MisoItemIcon", true, false)
		assert_eq(icons.size(), 1, "one icon per row")
		assert_eq((icons[0] as MisoItemIcon).custom_minimum_size, Vector2(32, 32), "a shop row's icon box is 32 px")
	assert_true(shop.select_buy_item(RED_POTION))
	assert_eq(shop.detail_icon.custom_minimum_size, Vector2(64, 64), "the detail's icon box is 64 px")
	assert_true(shop.detail_icon.art != null, "the detail shows the pack's Red Potion")
	shop.detail_icon.size = shop.detail_icon.custom_minimum_size
	assert_eq(shop.detail_icon.art_rect(), Rect2(6, 4, 54, 60), "at 2x")


# --- the seams -----------------------------------------------------------------------------------------------------

func test_the_drag_preview_the_npc_ui_and_the_skill_icons_go_through_the_resolver() -> void:
	_use([_pack("fake", [_item("2000000", Vector2i(27, 30), RED, [-3, 30]), _skill(SNAILS, GREEN)])])
	var slot: MisoItemSlot = _keep(MisoItemSlot.new(46.0))
	slot.set_stack(RED_POTION, 3, db())
	var holder: Control = _keep(slot.drag_preview())
	var preview: MisoItemIcon = holder.get_child(0)
	assert_true(preview.art != null and is_same(preview.art.texture, slot.icon.art.texture),
		"the drag preview shows the slot's pack art")
	assert_eq(preview.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	slot.set_stack(SNAIL_SHELL, 2, db())
	var plain: MisoItemIcon = _keep(slot.drag_preview()).get_child(0)
	assert_eq(plain.art, null, "a Snail Shell is in no pack")
	assert_eq([plain.shape, plain.color], [slot.icon.shape, slot.icon.color], "so the preview draws its procedural icon")
	var npc_icon: MisoItemIcon = _keep(NpcUiStyle.item_icon(RED_POTION, db(), 32.0))
	assert_true(npc_icon.art != null, "the NPC UI's item icon is a MisoItemIcon with the pack art")
	NpcUiStyle.set_icon_item(npc_icon, SNAIL_SHELL, db())
	assert_eq([npc_icon.art, npc_icon.shape], [null, "shell"], "set_icon_item resolves again")
	var cell: MisoQuickslotBar.QuickslotCell = _keep(MisoQuickslotBar.QuickslotCell.new(40.0))
	cell.set_skill(SNAILS, false, 0.5, 3.0)
	assert_true(cell.skill_icon.art != null, "a quickslot's skill draws the pack art")
	assert_true(cell.skill_icon.dim and cell.skill_icon.cooldown == 0.5, "with the procedural dim and cooldown over it")
	var learned: MisoSkillsWindow.SkillIconCell = _keep(MisoSkillsWindow.SkillIconCell.new(SNAILS))
	assert_true(learned.icon.art != null, "the skills window draws the pack art")


func test_the_thrown_shell_keeps_its_colour() -> void:
	_use([_pack("fake", [_item("4000001", Vector2i(26, 27), GREEN, [-4, 27])])])
	assert_eq(PlayerSkills.shell_color("348"), Color(0.80, 0.56, 0.30), "Snail Shell: brown")
	assert_eq(PlayerSkills.shell_color("349"), Color(0.25, 0.52, 0.95), "Blue Snail Shell: blue")
	assert_eq(PlayerSkills.shell_color("351"), Color(0.90, 0.20, 0.18), "Red Snail Shell: red")
	assert_eq(PlayerSkills.shell_color(EGG), PlayerSkills.SHELL_FALLBACK_COLOR, "any other item: the fallback")
	var snails := SkillDef.of(SNAILS, db())
	for level in range(1, snails.max_level + 1):
		var item_id := String(snails.item_cost(level).get("item_id", ""))
		assert_has(PlayerSkills.SHELL_COLORS, item_id, "level %d's shell %s has its pinned colour" % [level, item_id])
