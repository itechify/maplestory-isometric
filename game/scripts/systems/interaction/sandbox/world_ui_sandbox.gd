extends Node3D
## Sandbox for the interaction system, NPC presentation, the dialogue and shop windows and ground loot, on the real
## island (scenes/world/world.tscn) with the real player and camera, wired exactly as the game shell wires them:
## a GameContext, the three subsystem scenes at their fixed paths, setup(ctx) on each.
##
## Run from an ISOLATE copy (never against game/ directly):
##   G="bash scripts/godot.sh --path _scratch/godot_runs/worldui/game"
##   $G --resolution 1600x900 --disable-vsync res://scripts/systems/interaction/sandbox/world_ui_sandbox.tscn -- \
##      --scenario roger --shot <dir> --quit
## Scenarios: roger (Mushroom Town: prompt, dialogue, accept), shop (Lucy in the Amherst Department Store), loot
## (drops tossed around the player in Snail Hunting Ground I, picked up, kept across a map round trip), kills (the
## monster system kills every monster of Snail Hunting Ground I; its loot_dropped must land on the ground), play (stay in Mushroom Town and play
## with the keyboard: WASD, F talk, Z pick up, L drop loot, Esc close). Without --quit the window stays open.
## Each scenario presses the real keys (Input.parse_input_event) and prints CHECK lines; with --quit the exit code is
## the number of failed checks (0 = pass), so it also runs headless as an integration check (collision only):
##    --headless res://scripts/systems/interaction/sandbox/world_ui_sandbox.tscn -- --scenario roger --quit

const MONSTER_SCENE := "res://scenes/systems/monster_system.tscn"
const SCENES := {
	"loot": "res://scenes/systems/loot_system.tscn",
	"interaction": "res://scenes/systems/interaction_system.tscn",
	"npc_ui": "res://scenes/ui/npc_ui.tscn",
}

var ctx: GameContext = null
var world: Node = null
var player: Node3D = null
var rig: Node3D = null
var loot: LootSystem = null
var interaction: InteractionSystem = null
var npc_ui: NpcUi = null
## The monster system (another engineer's scene), installed for the kills scenario only.
var monsters: Node = null
var notice_box: VBoxContainer = null
var _args: PackedStringArray = []
var _failures: int = 0


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	await _boot()
	var scenario := _arg("--scenario", "roger")
	match scenario:
		"roger":
			await _scenario_roger()
		"shop":
			await _scenario_shop()
		"loot":
			await _scenario_loot()
		"kills":
			await _scenario_kills()
		"play":
			await _warp("000000010")
			await _stand_before_npc("3")
	print("SANDBOX done: %s, %d failed checks" % [scenario, _failures])
	if _has("--quit"):
		get_tree().quit(0 if _failures == 0 else 1)


# --- boot (what the game shell does) ---------------------------------------------------------------------------

func _boot() -> void:
	var game := get_node("/root/Game")
	game.call("new_game", {"save": false})
	world = (load("res://scenes/world/world.tscn") as PackedScene).instantiate()
	if DisplayServer.get_name() == "headless" and "load_visuals" in world:
		world.set("load_visuals", false)
	add_child(world)
	await world.world_ready
	player = (load("res://scenes/actors/player.tscn") as PackedScene).instantiate()
	add_child(player)
	world.call("set_player", player)
	rig = (load("res://scenes/actors/camera_rig.tscn") as PackedScene).instantiate()
	add_child(rig)
	rig.call("set_target", player)
	rig.call("scan_occluders", world)
	var session := get_node("/root/MapSession")
	session.call("attach_camera", rig)
	ctx = GameContext.new()
	ctx.main = self
	ctx.world = world
	ctx.player = player
	ctx.camera = rig
	ctx.ui_root = CanvasLayer.new()
	ctx.ui_root.name = "UI"
	ctx.ui_root.layer = 10
	add_child(ctx.ui_root)
	ctx.systems = Node.new()
	ctx.systems.name = "Systems"
	add_child(ctx.systems)
	if _arg("--scenario", "roger") == "kills" and ResourceLoader.exists(MONSTER_SCENE):
		monsters = (load(MONSTER_SCENE) as PackedScene).instantiate()
		ctx.systems.add_child(monsters)
	loot = (load(SCENES["loot"]) as PackedScene).instantiate()
	ctx.systems.add_child(loot)
	interaction = (load(SCENES["interaction"]) as PackedScene).instantiate()
	ctx.systems.add_child(interaction)
	npc_ui = (load(SCENES["npc_ui"]) as PackedScene).instantiate()
	ctx.ui_root.add_child(npc_ui)
	for n: Node in [monsters, loot, interaction, npc_ui]:
		if n != null:
			n.call("setup", ctx)
	_make_notice_log()
	session.call("start_new_game")
	await _idle()


## Stand-in for the HUD's notice log (the sandbox has no HUD): the last notices top-left.
func _make_notice_log() -> void:
	notice_box = VBoxContainer.new()
	notice_box.position = Vector2(16, 16)
	ctx.ui_root.add_child(notice_box)
	get_node("/root/Events").connect("notice", func(t: String) -> void:
		var l := NpcUiStyle.label(t, Color.WHITE, 15, true)
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		notice_box.add_child(l)
		while notice_box.get_child_count() > 6:
			notice_box.get_child(0).free())


func _unhandled_input(event: InputEvent) -> void:
	# The shell's Esc: close the newest window.
	if event.is_action_pressed(&"menu") and ctx != null:
		ctx.close_top_window()
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_L:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		loot.spawn_drops(DropRoller.roll("2", Data.db, rng) + [{"kind": "mesos", "amount": rng.randi_range(5, 1500)}],
			player.global_position + rig.get("ground_forward") * 1.2)


# --- scenarios -------------------------------------------------------------------------------------------------

func _scenario_roger() -> void:
	await _warp("000000010")
	await _stand_before_npc("3")
	await _wait(1.2)
	_check(interaction.prompt.text() == "[F] Talk to Roger", "prompt names Roger: '%s'" % interaction.prompt.text())
	var pres: NpcPresenter = interaction.presenters.get("3")
	_check(pres != null and pres.tag.visible and pres.marker.state == "available", "Roger's tag and '!' marker")
	await _shot("1_prompt_roger")
	await _press_key(KEY_F)
	await _wait(0.6)
	_check(npc_ui.dialogue.is_open() and npc_ui.dialogue.body_text().begins_with("Talk to Roger."),
		"F opened Roger's offer card: '%s'" % npc_ui.dialogue.body_text().left(40))
	_check(ctx.is_modal_active() and interaction.prompt.text() == "", "modal: no prompt")
	await _shot("2_dialogue_roger_offer")
	await _press_key(KEY_Y)
	await _wait(0.4)
	_check(Game.character.inventory.count("235") == 1, "Roger's Apple handed over")
	_check(npc_ui.dialogue.body_text().begins_with("Press the hotkey I"), "the instructions follow the accept")
	await _shot("2b_dialogue_roger_instructions")
	await _press_key(KEY_ENTER)
	await _wait(0.4)
	_check(not ctx.is_modal_active(), "modal released")
	# Talk again for the in-progress line with its item reference.
	await _press_key(KEY_F)
	await _wait(0.6)
	_check(npc_ui.dialogue.body_text().begins_with("Eat the Roger's Apple"), "in-progress line")
	await _shot("3_dialogue_roger_in_progress")
	await _press_key(KEY_ENTER)
	await _wait(0.3)
	_check(not npc_ui.dialogue.is_open(), "Enter closed the last line")
	ItemService.new(Game.character, Data.db, Events).use_item("235")
	await _press_key(KEY_F)
	await _wait(0.5)
	_check(Game.character.quests.status("1002") == QuestLog.COMPLETED, "1002 completed at Roger")
	_check(npc_ui.dialogue.shown_banner().begins_with("Quest complete: Roger's Apple"), "completion summary")
	await _press_key(KEY_ESCAPE)
	await _wait(0.3)
	_check(not npc_ui.dialogue.is_open(), "Esc (the shell's window stack) closed the chat")


func _scenario_shop() -> void:
	await _warp("000001013")
	Game.character.mesos = 1234
	ItemService.new(Game.character, Data.db, Events).gain("348", 12)
	ItemService.new(Game.character, Data.db, Events).gain("270", 4)
	await _stand_before_npc("21")
	await _wait(1.0)
	_check(interaction.prompt.text() == "[F] Talk to Lucy", "prompt names Lucy: '%s'" % interaction.prompt.text())
	await _shot("4_prompt_lucy")
	await _press_key(KEY_F)
	await _wait(0.4)
	_check(npc_ui.dialogue.is_open(), "Lucy's greeting")
	await _press_key(KEY_ENTER)
	await _wait(0.4)
	_check(npc_ui.shop.is_open() and npc_ui.shop.shop_id == "maple-road-lucy", "the greeting opened Lucy's shop")
	npc_ui.shop.select(1)
	npc_ui.shop.set_quantity(3)
	var r := npc_ui.shop.confirm()
	_check(bool(r.get("ok", false)) and Game.character.mesos == 1234 - 3 * int(npc_ui.shop.buy_rows[1]["price"]),
		"bought 3 at the canonical price")
	npc_ui.shop.set_quantity(30)
	await _wait(0.4)
	await _shot("5_shop_buy")
	npc_ui.shop.set_sell_tab("etc")
	npc_ui.shop.select(0)
	npc_ui.shop.set_quantity(5)
	await _wait(0.3)
	await _shot("6_shop_sell")
	await _press_key(KEY_ESCAPE)
	await _wait(0.3)
	_check(not npc_ui.shop.is_open() and not ctx.is_modal_active(), "Esc left the shop")


func _scenario_loot() -> void:
	await _warp(_arg("--map", "000000040"))
	await _wait(0.5)
	var fwd: Vector3 = rig.get("ground_forward")
	var right: Vector3 = rig.get("ground_right")
	var at := player.global_position + fwd * 2.2
	# A spread of drop families: potion, etc pouch, equipment, mesos, food, gem, mesos; then scroll, coins, a top,
	# a meso bag, arrows, a chair.
	Events.loot_dropped.emit([{"kind": "item", "item_id": "270", "qty": 1}, {"kind": "item", "item_id": "348", "qty": 1},
		{"kind": "item", "item_id": "541", "qty": 1}, {"kind": "mesos", "amount": 7}, {"kind": "item", "item_id": "237", "qty": 2},
		{"kind": "item", "item_id": "321", "qty": 1}, {"kind": "mesos", "amount": 120}], at, MapSession.current_map)
	Events.loot_dropped.emit([{"kind": "item", "item_id": "143", "qty": 1}, {"kind": "mesos", "amount": 60},
		{"kind": "item", "item_id": "933", "qty": 1}, {"kind": "mesos", "amount": 2500}, {"kind": "item", "item_id": "209", "qty": 1},
		{"kind": "item", "item_id": "525", "qty": 1}], at - fwd * 1.2 + right * 0.2, MapSession.current_map)
	_check(loot.nodes().size() == 13, "13 drops on the ground (%d)" % loot.nodes().size())
	_check(MapSession.instance_state.drops.size() == 13, "13 records in the live map instance")
	await _wait(0.25)
	await _shot("7_loot_tossing")
	await _wait(1.0)
	# Step onto the first drop so the pickup prompt shows.
	var first: GroundDrop = loot.nodes().values()[0]
	world.call("place_player", Transform3D(Basis.IDENTITY, first.landing + right * 0.3))
	rig.call("snap")
	await _wait(0.6)
	_check(interaction.prompt.text().begins_with("[Z] Pick up"), "pickup prompt: '%s'" % interaction.prompt.text())
	await _shot("8_loot_prompt")
	var before := Game.character.inventory.count("270") + Game.character.inventory.count("348")
	for i in 2:
		await _press_key(KEY_Z)
		await _wait(0.3)
	_check(Game.character.inventory.count("270") + Game.character.inventory.count("348") > before, "Z picked up")
	await _shot("9_loot_after_pickup")
	# Leave and come back: the rest is still there.
	var left := MapSession.instance_state.drops.size()
	await _warp("000000010")
	_check(loot.nodes().is_empty(), "no drops in the other map")
	await _warp(_arg("--map", "000000040"))
	_check(loot.nodes().size() == left and MapSession.instance_state.drops.size() == left,
		"%d drops kept across the round trip (%d)" % [left, loot.nodes().size()])


## Real kills through the monster system (when its scene exists): every death rolls DropRoller and announces
## Events.loot_dropped at the monster's feet; the loot system must put exactly those drops on the ground.
func _scenario_kills() -> void:
	if monsters == null:
		_check(false, "res://scenes/systems/monster_system.tscn is not installed")
		return
	await _warp(_arg("--map", "000000040"))
	await _wait(2.0)
	var announced := [0]
	Events.loot_dropped.connect(func(drops: Array, _at: Vector3, _map: String) -> void: announced[0] += drops.size())
	var killed := int(monsters.call("kill_all"))
	_check(killed > 0, "killed %d monsters" % killed)
	await _wait(1.5)
	_check(announced[0] > 0, "%d drops announced by the monster system" % announced[0])
	_check(loot.nodes().size() == announced[0] and MapSession.instance_state.drops.size() == announced[0],
		"every announced drop is on the ground and in the map instance (%d nodes, %d records)" % [loot.nodes().size(),
		MapSession.instance_state.drops.size()])
	var landed := 0
	for n: GroundDrop in loot.nodes().values():
		if n.is_landed():
			landed += 1
	_check(landed == loot.nodes().size(), "all landed")
	# Walk over to the kill with the most drops around it (the camera frames the player, drops spread by kill).
	var best: GroundDrop = null
	var best_n := -1
	for n: GroundDrop in loot.nodes().values():
		var near := 0
		for o: GroundDrop in loot.nodes().values():
			if o.landing.distance_to(n.landing) < 1.5:
				near += 1
		if near > best_n:
			best_n = near
			best = n
	if best != null:
		var right: Vector3 = rig.get("ground_right")
		var fwd: Vector3 = rig.get("ground_forward")
		world.call("place_player", Transform3D(Basis.IDENTITY, best.landing - fwd * 1.6 + right * 0.4))
		rig.call("snap")
		await _wait(0.8)
	await _shot("10_kills_loot")


# --- helpers ---------------------------------------------------------------------------------------------------

## Presses and releases a key through Input, exactly like the keyboard (the systems read Input / the player's source).
func _press_key(k: Key) -> void:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.pressed = down
		Input.parse_input_event(e)
		await get_tree().physics_frame
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["CHECK ok  " if ok else "CHECK FAIL", what])
	if not ok:
		_failures += 1


func _warp(map_id: String) -> void:
	var session := get_node("/root/MapSession")
	if String(session.get("current_map")) != map_id:
		session.call("debug_warp", map_id)
	await _idle()


func _idle() -> void:
	var session := get_node("/root/MapSession")
	var frames := 0
	while not bool(session.call("is_idle")) and frames < 900:
		await get_tree().physics_frame
		frames += 1
	await _wait(0.3)


## Puts the player about 1.1 m from an NPC, on the side the player arrived from (the NPC's model front when that is
## the same side), facing the NPC, and snaps the camera. Retries closer when the body was pushed out of talk range.
func _stand_before_npc(npc_id: String) -> void:
	var nodes: Dictionary = world.get("npc_nodes")
	var npc: Node3D = nodes.get(npc_id)
	if npc == null:
		push_error("[sandbox] no NPC %s" % npc_id)
		return
	var toward := player.global_position - npc.global_position
	toward.y = 0.0
	var front := npc.global_transform.basis.z
	front.y = 0.0
	var dir := toward.normalized() if toward.length_squared() > 0.01 else front.normalized()
	if front.length_squared() > 0.001 and front.normalized().dot(dir) > 0.0:
		dir = front.normalized()
	for dist: float in [1.1, 0.8, 0.6]:
		var pos := npc.global_position + dir * dist
		world.call("place_player", Transform3D(Basis.looking_at(dir, Vector3.UP), pos))
		rig.call("snap")
		await _wait(0.3)
		if player.global_position.distance_to(npc.global_position) < 1.5:
			return


func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame


func _shot(label: String) -> void:
	if not _has("--shot"):
		return
	await RenderingServer.frame_post_draw
	var dir := _arg("--shot", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(label + ".png")
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT %s" % path)
	if _has("--crop") and player != null:
		# A 2x close-up around the player (drops, tags and prompts are small at full frame).
		var cam: Camera3D = rig.get("camera")
		var c := cam.unproject_position(player.global_position)
		var r := Rect2i(Vector2i(c) - Vector2i(400, 260), Vector2i(800, 450))
		r.position = r.position.clamp(Vector2i.ZERO, img.get_size() - r.size)
		var crop := img.get_region(r)
		crop.resize(1600, 900, Image.INTERPOLATE_LANCZOS)
		crop.save_png(dir.path_join(label + "_crop.png"))


func _has(flag: String) -> bool:
	return flag in _args


func _arg(flag: String, fallback: String) -> String:
	var i := _args.find(flag)
	if i >= 0 and i + 1 < _args.size() and not _args[i + 1].begins_with("--"):
		return _args[i + 1]
	return fallback
