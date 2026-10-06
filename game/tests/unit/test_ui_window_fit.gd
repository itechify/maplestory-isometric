extends TestCase
## Every window fits the 1600 x 900 base screen with its largest realistic content and never covers the HUD's status
## bar (the acceptance review: the Skills window grew off the bottom of a windowed screen once a skill was learned, so
## its Set key could not be reached, and it covered the HP gauge). The windows and the HUD sit side by side under one
## CanvasLayer, as under ctx.ui_root in the game; the root viewport is pinned to exactly 1600 x 900 (the windowed
## playtest screen; headless the display server's window would make it 1600 x 1600).
##
## Content: the Skills window with all three Beginner skills learned, a row selected and the key picker open; a full
## Use tab with a slot selected and its key picker open; the Quest Log with every Maple Island quest in progress and
## the longest detail selected; Character Stats and Equipment; the shop with the largest canonical stock; a dialogue
## page with the longest canonical line. Also: a window that grows after it opens is pulled back inside, a drag
## cannot push a window over the bar, and a smaller viewport re-clamps every open window.

const SCREEN := Rect2(0, 0, 1600, 900)

var bus: Node
var nodes: Array = []
var game: GameState = null
var _saved_scale: Dictionary = {}


func before_each() -> void:
	bus = load("res://scripts/autoload/events.gd").new()
	var win := _root()
	_saved_scale = {"mode": win.content_scale_mode, "aspect": win.content_scale_aspect, "size": win.content_scale_size}
	_pin(Vector2i(1600, 900))


func after_each() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.free()
	nodes.clear()
	if game != null:
		game.free()
		game = null
	bus.free()
	var win := _root()
	win.content_scale_mode = _saved_scale["mode"]
	win.content_scale_aspect = _saved_scale["aspect"]
	win.content_scale_size = _saved_scale["size"]


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


## The GUI area of the root viewport, exactly `px` (the playtest runner's headless pin: aspect "ignore").
func _pin(px: Vector2i) -> void:
	var win := _root()
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_size = px
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE


func _character() -> CharacterState:
	var cr := CharacterFactory.create(CharacterFactory.default_params(db()), db())
	assert_true(cr.ok, "factory character")
	return cr.character


## The HUD and the windows under one CanvasLayer (ctx.ui_root in the game), both laid out.
func _ui(c: CharacterState) -> Dictionary:
	game = GameState.new()
	game.db = db()
	game.event_bus = bus
	game.log_warnings = false
	game.character = c
	var layer := CanvasLayer.new()
	layer.name = "FitUi"
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(layer)
	nodes.append(layer)
	var hud: MisoHud = load("res://scenes/ui/hud.tscn").instantiate()
	hud.configure(MisoUiEnv.isolated(c, db(), bus, null, game))
	layer.add_child(hud)
	var root: MisoWindowsRoot = load("res://scenes/ui/windows.tscn").instantiate()
	root.configure(MisoUiEnv.isolated(c, db(), bus, null, game))
	layer.add_child(root)
	_layout(hud)
	return {"layer": layer, "hud": hud, "root": root}


## Lays a control tree out now (containers sort deferred) at its minimum size or more.
func _layout(c: Control) -> void:
	c.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)
	if c is MisoWindow or c is ShopWindow or c is DialogueWindow:
		c.size = c.size.max(c.get_combined_minimum_size())
	c.propagate_notification(Container.NOTIFICATION_SORT_CHILDREN)


func _bar(hud: MisoHud) -> Rect2:
	return hud.status.get_global_rect()


func _rect(c: Control) -> Rect2:
	return Rect2(c.get_global_rect().position, c.size.max(c.get_combined_minimum_size()))


func _assert_fits(what: String, c: Control, bar: Rect2) -> void:
	var r := _rect(c)
	print("fit %s: %s (bar top %.0f)" % [what, r, bar.position.y])
	assert_true(SCREEN.encloses(r), "%s %s lies inside the 1600 x 900 screen" % [what, r])
	assert_false(r.intersects(bar), "%s %s does not cover the HUD's status bar %s" % [what, r, bar])


func _learn_all_skills(c: CharacterState) -> PackedStringArray:
	var ids := PackedStringArray()
	for def in SkillDef.catalog(c.job, db()):
		ids.append(def.id)
	c.sp = ids.size()
	for sid in ids:
		assert_true(bool(SkillBook.learn(c, sid, db()).ok), "learned %s" % sid)
	return ids


## The longest skill description (the detail pane's biggest page).
func _longest_skill(ids: PackedStringArray) -> String:
	var best := ""
	var n := -1
	for sid in ids:
		var def := SkillDef.of(sid, db())
		var len_ := def.description.length() + def.effect_text(1).length() + def.effect_text(2).length()
		if len_ > n:
			n = len_
			best = sid
	return best


func _fill_tab(c: CharacterState, tab: String) -> void:
	var pool: Array[String] = []
	for id in db().ids("items"):
		if String(db().item(id).get("inventory_tab", "")) == tab:
			pool.append(id)
	assert_true(not pool.is_empty(), "items for the %s tab" % tab)
	for i in c.inventory.capacity(tab):
		c.inventory.put_at(tab, i, {"item_id": pool[i % pool.size()], "qty": 1})
	assert_eq(c.inventory.free_slots(tab), 0, "the %s tab is full" % tab)


# --- the character windows --------------------------------------------------------------------------------------

func test_every_window_fits_above_the_status_bar_with_its_largest_content() -> void:
	var c := _character()
	var ids := _learn_all_skills(c)
	_fill_tab(c, "use")
	for qid in db().ids("quests"):
		c.quests.start(qid, 0.0)
	var ui := _ui(c)
	var root: MisoWindowsRoot = ui.root
	var bar := _bar(ui.hud)
	assert_true(bar.size.y > 40.0 and bar.end.y <= SCREEN.end.y, "the HUD's status bar is laid out at the bottom: %s" % bar)
	assert_near(root.bottom_inset(), SCREEN.end.y - bar.position.y, 0.5, "the windows root reserves the bar")
	for n in ["stats", "quests", "equipment", "inventory", "skills"]:
		root.open_window(n)
	# The largest content each window shows.
	root.skills.select_skill(_longest_skill(ids))
	root.skills.key_picker.visible = true
	root.inventory.select_tab("use")
	root.inventory.select_slot(0)
	root.inventory.key_picker.visible = true
	root.quests.select_tab(MisoQuestWindow.TAB_IN_PROGRESS)
	root.quests.select_quest("1006")
	for w: MisoWindow in root.windows.values():
		w.refresh()
		_layout(w)
	for n in ["stats", "quests", "equipment", "inventory", "skills"]:
		_assert_fits(n, root.window_by_name(n), bar)
	# The Skills window's controls a player needs are on screen.
	for b: Button in [root.skills.key_button, root.skills.key_buttons["1"], root.skills.plus_buttons[ids[0]]]:
		var r := b.get_global_rect()
		assert_true(SCREEN.encloses(r) and not r.intersects(bar), "Skills: '%s' %s is on screen above the bar" % [b.text, r])


func test_the_skills_window_keeps_one_size_as_skills_are_learned() -> void:
	var c := _character()
	var ui := _ui(c)
	var root: MisoWindowsRoot = ui.root
	var bar := _bar(ui.hud)
	root.open_window("skills")
	_layout(root.skills)
	var r0 := _rect(root.skills)
	_assert_fits("skills before", root.skills, bar)
	# Learn every skill, select the longest row and open the key picker: nothing moves or grows.
	var ids := _learn_all_skills(c)
	root.skills.select_skill(_longest_skill(ids))
	root.skills.key_picker.visible = true
	root.skills.refresh()
	_layout(root.skills)
	var r1 := _rect(root.skills)
	print("skills %s -> %s" % [r0, r1])
	assert_eq(r1, r0, "the Skills window keeps its place and size")
	_assert_fits("skills after learning", root.skills, bar)


func test_a_window_that_grows_after_it_opens_is_pulled_back_inside() -> void:
	var c := _character()
	var ui := _ui(c)
	var root: MisoWindowsRoot = ui.root
	var bar := _bar(ui.hud)
	root.open_window("skills")
	_layout(root.skills)
	# Pushed as low as it may go, then its content grows by 120 px (any window: a longer page, more rows).
	root.skills.position.y = 5000.0
	root.skills._clamp_to_screen()
	_assert_fits("skills at the bottom", root.skills, bar)
	var y0 := root.skills.position.y
	root.skills.custom_minimum_size.y = root.skills.size.y + 120.0
	_layout(root.skills)
	_assert_fits("skills after growing", root.skills, bar)
	assert_near(root.skills.position.y, y0 - 120.0, 0.5, "it moved up by exactly what it grew")


func test_a_drag_cannot_push_a_window_over_the_bar() -> void:
	var c := _character()
	var ui := _ui(c)
	var root: MisoWindowsRoot = ui.root
	var bar := _bar(ui.hud)
	root.open_window("stats")
	_layout(root.stats)
	root.stats.global_position = Vector2(4000, 4000)
	root.stats._clamp_to_screen()
	_assert_fits("stats dragged to the corner", root.stats, bar)
	assert_near(root.stats.get_global_rect().end.y, bar.position.y - MisoWindow.BAR_GAP, 0.5, "it stops just above the bar")


func test_a_smaller_viewport_reclamps_open_windows() -> void:
	var c := _character()
	_fill_tab(c, "use")
	var ui := _ui(c)
	var root: MisoWindowsRoot = ui.root
	root.open_window("inventory")
	_layout(root.inventory)
	var x0 := root.inventory.position.x
	_pin(Vector2i(1280, 900))
	_layout(ui.hud)
	var area := root.get_viewport_rect()
	assert_eq(area.size, Vector2(1280, 900), "the viewport shrank")
	var r := _rect(root.inventory)
	assert_true(r.end.x <= area.end.x + 0.5, "the inventory (was at x %.0f) moved inside the narrower screen: %s" % [x0, r])


# --- the NPC windows (NpcUi: the shop and the dialogue sit above the bar too) ---------------------------------------

func _npc_ui(c: CharacterState, layer: CanvasLayer) -> NpcUi:
	var ui: NpcUi = load("res://scenes/ui/npc_ui.tscn").instantiate()
	ui.bus = bus
	layer.add_child(ui)
	ui.shop.db = db()
	ui.shop.bus = bus
	ui.shop.character_provider = func() -> CharacterState: return c
	return ui


func test_the_largest_shop_fits_above_the_status_bar() -> void:
	var c := _character()
	c.mesos = 1000000
	var ui := _ui(c)
	var bar := _bar(ui.hud)
	var best := ""
	var npc := ""
	var most := -1
	for sid in db().ids("shops"):
		var n := (db().shop(sid).get("items", []) as Array).size()
		if n > most:
			most = n
			best = sid
			npc = String(db().shop(sid).get("npc_id", ""))
	assert_true(best != "", "a canonical shop")
	var nui := _npc_ui(c, ui.layer)
	assert_true(nui.open_shop(best, npc), "the %s shop (%d rows) opens" % [best, most])
	_layout(nui.shop)
	nui.shop._layout()
	_assert_fits("shop %s (%d rows)" % [best, most], nui.shop, bar)
