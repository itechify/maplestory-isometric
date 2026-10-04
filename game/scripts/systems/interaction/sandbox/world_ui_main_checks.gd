extends Node
## Drives the REAL game (res://scenes/main.tscn: the game shell, GameSession, SubsystemInstaller, the HUD, the monster
## system, the death controller) through the world-UI flows with real frames, physics, autoloads and key presses
## (Input.parse_input_event), printing one line per check. The engineer's sandbox wires its own GameContext; this one
## proves the subsystems work as the shell composes them.
##
##   godot --headless --fixed-fps 60 --path <copy> res://scripts/systems/interaction/sandbox/world_ui_main_checks.tscn -- --scenario main
##   godot --resolution 1600x900 --path <copy> res://scripts/systems/interaction/sandbox/world_ui_main_checks.tscn -- --scenario shots --out <dir>
##
## main   new game -> Roger's Apple (prompt, F, Esc through the shell, accept with Y, Space on the last line must not
##        make the player jump, the completion page and its summary) -> a portal and a ladder -> Lucy (greeting ->
##        shop, never both windows at once, mashing Enter/Space buys nothing, buy with Right + Enter, sell from the Use
##        tab, insufficient mesos, a full inventory, Esc, Esc = pause) -> Snail Hunting Ground I (real kills, Z pickups
##        with notices, the map round trip, holding Z with a full tab) -> Sam's Suggestion (Sam's offer, Backspace,
##        `kill all` until 10 Snails, every drop picked up with Z, Mai's "?" and the reward) -> robustness (WASD and
##        arrows in Rain's quiz menu, Up in a menu inside a portal, a warp with the chat or the shop open, a shop request
##        during a chat, a death in a chat) -> death with the shop open -> quit to title and continue
## shots  windowed screenshots: the prompt over Roger, the dialogue, the shop, drops with the pickup prompt, Rain's
##        quiz menu, the Sell tab, the insufficient-mesos line
##
## Output: "WORLDUI_CHECK PASS|FAIL <name>[: detail]", "WORLDUI_INFO ...", "WORLDUI_SHOT <path>", and finally
## "WORLDUI_CHECKS_DONE <passed> <failed>"; the exit code is 0 when nothing failed. Saves go to a private
## user://_tests/ directory, deleted at the end.

const MAIN_SCENE := "res://scenes/main.tscn"
const TIMEOUT_FRAMES := 2400

var scenario := "main"
var out_dir := ""
var main: MainShell = null
var save_dir := ""
var passed := 0
var failed := 0
var notices: PackedStringArray = []
var _shot_index := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	scenario = _arg(args, "--scenario", "main")
	out_dir = _arg(args, "--out", "user://worldui_shots")
	_run.call_deferred()


func _run() -> void:
	var saves := get_node("/root/Saves")
	save_dir = "user://_tests/worldui_%s_%d" % [scenario, Time.get_ticks_usec()]
	saves.set("save_dir", save_dir)
	get_node("/root/Events").connect("notice", func(t: String) -> void: notices.append(t))
	main = (load(MAIN_SCENE) as PackedScene).instantiate() as MainShell
	main.use_command_line = false
	add_child(main)
	await _frames(2)
	if await _new_game():
		match scenario:
			"main":
				await _roger()
				await _portal_and_ladder()
				await _lucy()
				await _loot()
				await _sam_suggestion()
				await _npc_window_robustness()
				await _death_with_shop_open()
				await _second_session()
			"shots":
				await _shots()
			_:
				_check("scenario", false, "unknown scenario '%s'" % scenario)
	_remove_tree(save_dir)
	print("WORLDUI_CHECKS_DONE %d %d" % [passed, failed])
	get_tree().paused = false
	get_tree().quit(0 if failed == 0 else 1)


# --- flows -------------------------------------------------------------------------------------------------------

func _new_game() -> bool:
	main.open_creation()
	var model := main.creation.model
	model.name = "Worldui"
	model.gender = "female"
	main.creation.refresh()
	main.creation.submit()
	var ok := await _until(func() -> bool: return not main.flow.is_in(ShellFlow.State.LOADING))
	_check("new game reaches PLAYING", ok and main.flow.is_in(ShellFlow.State.PLAYING), main.last_error_message)
	if not main.flow.is_in(ShellFlow.State.PLAYING):
		return false
	for n in ["LootSystem", "InteractionSystem", "NpcUI"]:
		var row := main.game_session.subsystem_row(n)
		_check("%s installed by the shell" % n, String(row.get("status", "")) == SubsystemInstaller.STATUS_INSTALLED,
			str(row.get("status", "")) + " " + str(row.get("error", "")))
	return true


func _roger() -> void:
	var game := get_node("/root/Game") as GameState
	await _warp("000000010")
	await _stand_before_npc("3")
	await _seconds(0.6)
	var inter := _inter()
	var ui := _npc_ui()
	_check("prompt over Roger", inter.prompt.text() == "[F] Talk to Roger", inter.prompt.text())
	var pres: NpcPresenter = inter.presenters.get("3")
	_check("Roger's tag and available marker", pres != null and pres.tag.visible and pres.marker.state == "available"
		and pres.marker.visible)
	await _press(KEY_F)
	await _frames(3)
	_check("F opens Roger's dialogue", ui.dialogue.is_open() and main.ctx().is_modal_active(), ui.dialogue.body_text().left(60))
	_check("no prompt while the dialogue is open", inter.prompt.text() == "")
	var hud: Node = main.game_session.installer.node_of("HUD")
	var bar: Variant = hud.get("status") if hud != null else null
	if bar is Control:
		await _frames(2)
		var d := ui.dialogue.get_global_rect()
		_check("the dialogue sits above the HUD's status bar", d.end.y <= (bar as Control).get_global_rect().position.y + 0.5
			and d.position.y >= 0.0, "dialogue %s, bar top %.0f" % [d, (bar as Control).get_global_rect().position.y])
	await _press(KEY_ESCAPE)
	await _frames(3)
	_check("Esc ends the chat through the shell, no pause menu", not ui.dialogue.is_open()
		and main.flow.is_in(ShellFlow.State.PLAYING) and not main.ctx().is_modal_active())
	await _press(KEY_F)
	await _frames(3)
	_check("F again: the offer", ui.dialogue.is_open() and String(ui.dialogue.view.get("type", "")) == "yes_no",
		String(ui.dialogue.view.get("type", "")))
	var n0 := notices.size()
	await _press(KEY_Y)
	await _frames(3)
	_check("Y accepts Roger's Apple", game.character.quests.status("1002") == QuestLog.IN_PROGRESS
		and game.character.inventory.count("235") == 1)
	# 1002 has no canonical On accept text: Yes leads to the quest card with the canonical instructions (journal), which
	# carries the accept summary as its banner (a notice only if the chat had ended right after the accept).
	var accepted := ui.dialogue.shown_banner()
	if accepted == "":
		accepted = ", ".join(_notices_since(n0))
	_check("accept summary shown with the instructions", accepted.contains("Quest accepted: Roger's Apple")
		and ui.dialogue.is_open() and ui.dialogue.body_text().begins_with("Press the hotkey I"),
		"%s | %s" % [accepted, ui.dialogue.body_text().left(60)])
	await _press(KEY_ENTER)
	await _frames(3)
	_check("modal released after the instructions", not main.ctx().is_modal_active() and not ui.dialogue.is_open())
	# The in-progress line ends with OK: Space (also the jump key) closes it and must not make the player jump.
	await _settle()
	await _press(KEY_F)
	await _frames(3)
	_check("in-progress line", ui.dialogue.is_open(), ui.dialogue.body_text().left(60))
	var p := _player()
	await _settle()
	var y0 := p.global_position.y
	var max_vy := 0.0
	var max_dy := 0.0
	var e := _key_event(KEY_SPACE, true)
	Input.parse_input_event(e)
	for i in 12:
		await get_tree().physics_frame
		max_vy = maxf(max_vy, p.velocity.y)
		max_dy = maxf(max_dy, p.global_position.y - y0)
		if i == 1:
			Input.parse_input_event(_key_event(KEY_SPACE, false))
	_check("Space closed the last line", not ui.dialogue.is_open())
	_check("Space on the last line does not make the player jump", max_vy < 0.5 and max_dy < 0.05,
		"max vy %.2f, rise %.2f m" % [max_vy, max_dy])
	_check("the keyboard is back right after that physics step", not main.ctx().is_modal_active() and p.is_input_enabled())
	await _settle()
	ItemService.new(game.character, Data.db, get_node("/root/Events")).use_item("235")
	var exp0 := game.character.exp
	var n1 := notices.size()
	await _press(KEY_F)
	await _frames(3)
	var banner := ui.dialogue.shown_banner()
	var guard := 0
	while ui.dialogue.is_open() and guard < 6:
		if banner == "":
			banner = ui.dialogue.shown_banner()
		await _press(KEY_ENTER)
		await _frames(3)
		guard += 1
	_check("Roger's Apple completed at Roger", game.character.quests.status("1002") == QuestLog.COMPLETED)
	# The completion is shown on the next page, or announced if the chat ended right after it. Roger's Apple has no
	# canonical reward (exp 0), so the summary is the quest name alone; any EXP gained would be listed.
	var said := banner if banner != "" else ", ".join(_notices_since(n1))
	var gained := game.character.exp - exp0
	_check("the completion summary", said.begins_with("Quest complete: Roger's Apple")
		and (gained <= 0 or said.contains("+%d EXP" % gained)), said)
	_check("chat closed with Enter", not ui.dialogue.is_open() and not main.ctx().is_modal_active())


## The prompt must name what the key really does: inside a portal "[Up] Enter portal" + the destination, and Up warps
## there; at a ladder "[Up] Climb", and F (also the talk key) grabs the ladder instead of starting a chat.
func _portal_and_ladder() -> void:
	var session := get_node("/root/MapSession")
	var db: ContentDB = Data.db
	await _warp("000000010")
	var chosen: WorldPortal = null
	for wp: WorldPortal in _world().call("portals_of", "000000010"):
		if wp.def.accepts_press() and wp.shows_prompt() and wp.def.destination_map_id != "000000010":
			chosen = wp
			break
	_check("a pressable portal in 000000010", chosen != null)
	if chosen != null:
		var dest := chosen.def.destination_map_id
		_world().call("place_player", Transform3D(Basis.IDENTITY, chosen.def.anchor_ground + Vector3.UP * 0.2))
		await _settle()
		await _seconds(0.2)
		var p := _inter().prompt.current
		_check("portal prompt", _inter().prompt.text() == "[Up] Enter portal"
			and String(p.get("detail", "")) == String(db.map(dest).get("name", "")), "%s / %s" % [_inter().prompt.text(), p.get("detail", "")])
		await _press(KEY_UP)
		await _until(func() -> bool: return String(session.get("current_map")) == dest and bool(session.call("is_idle")))
		_check("Up entered the portal the prompt named", String(session.get("current_map")) == dest,
			String(session.get("current_map")))
	# A ladder: the first one that can be climbed from its foot.
	var pc := _player()
	if pc.climbables.is_empty():
		# Nothing in the shell or the world registers the sidecars' climbables with the player (only the player
		# sandbox does), so the real game has no ladders. Reported as a requested change; load them here so the
		# prompt / F arbitration is still checked against the real controller.
		_info("the game registered no climbables with the player; loading them from the sidecars for this check")
		var dir := DirAccess.open("res://assets/world")
		if dir != null:
			for f in dir.get_files():
				if f.ends_with(".json"):
					var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/" + f))
					if parsed is Dictionary and (parsed as Dictionary).get("climbables") is Array:
						pc.add_climbables_from_sidecar((parsed as Dictionary)["climbables"])
	var ladder: ClimbableDef = null
	for c: ClimbableDef in pc.climbables:
		if not c.descend_only and c.height() > 1.5:
			ladder = c
			break
	_check("the island has a ladder", ladder != null)
	if ladder == null:
		return
	var region: Dictionary = (_world().get("region_index") as RegionIndex).region_of(ladder.bottom)
	var map_id := String(region.get("id", ""))
	_check("the ladder lies in a map", map_id != "", str(ladder.bottom))
	if map_id == "":
		return
	await _warp(map_id)
	var foot := ladder.foot_ground if ladder.has_foot_ground else ladder.bottom
	_world().call("place_player", Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.1))
	await _settle()
	await _seconds(0.2)
	_check("ladder grabbable at its foot", pc.grabbable_climbable() != null, "%s in %s" % [ladder.name, map_id])
	_check("climb prompt", _inter().prompt.text() == "[Up] Climb", _inter().prompt.text())
	await _press(KEY_F)
	await _frames(2)
	_check("F grabbed the ladder, no chat", pc.is_climbing() and not _npc_ui().dialogue.is_open())
	_check("no prompt while climbing", _inter().prompt.text() == "")
	_world().call("place_player", Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.1))
	await _settle()


func _lucy() -> void:
	var game := get_node("/root/Game") as GameState
	await _warp("000001013")
	game.character.mesos = 1000
	await _stand_before_npc("21")
	await _seconds(0.6)
	var inter := _inter()
	var ui := _npc_ui()
	_check("prompt over Lucy", inter.prompt.text() == "[F] Talk to Lucy", inter.prompt.text())
	await _press(KEY_F)
	await _frames(3)
	_check("Lucy's greeting", ui.dialogue.is_open(), ui.dialogue.body_text().left(60))
	var both := [false]
	var watch := func(_id: String) -> void: both[0] = ui.dialogue.is_open()
	ui.shop.opened.connect(watch)
	await _press(KEY_ENTER)
	await _frames(3)
	ui.shop.opened.disconnect(watch)
	_check("Enter opens Lucy's shop", ui.shop.is_open() and ui.shop.shop_id == "maple-road-lucy", ui.shop.shop_id)
	_check("the greeting is closed when the shop is open", not ui.dialogue.is_open())
	# The open_shop action runs inside the greeting's last step, so the shop opens a moment before the greeting
	# closes (same key event); the window stack ends with the shop on top either way.
	_info("greeting still open when the shop opened: %s" % both[0])
	_check("the shop is the only window and modal owner", main.ctx().is_modal_active() and main.ctx().has_open_windows())
	var shop := ui.shop
	var price := int(shop.buy_rows[0]["price"])
	var item_id := String(shop.buy_rows[0]["item_id"])
	var have := game.character.inventory.count(item_id)
	# Mashing through the greeting: the presses right after the shop opened spend nothing.
	await _press(KEY_ENTER)
	await _press(KEY_SPACE)
	await _press(KEY_ENTER)
	_check("mashing Enter/Space through the greeting buys nothing", game.character.mesos == 1000
		and game.character.inventory.count(item_id) == have, "%d mesos, status '%s'" % [game.character.mesos, shop.status_text])
	await _seconds(shop.confirm_arm_s + 0.1)
	await _press(KEY_RIGHT)
	await _press(KEY_ENTER)
	await _frames(2)
	_check("Right + Enter buys 2 at the canonical price", game.character.mesos == 1000 - 2 * price
		and game.character.inventory.count(item_id) == have + 2, "%d mesos, status '%s'" % [game.character.mesos, shop.status_text])
	_check("the bought message", shop.status_text == "Bought %s x2 for %d mesos." % [String(Data.db.item(item_id).get("name", "")), 2 * price],
		shop.status_text)
	await _press(KEY_SPACE)
	_check("Space in the shop never buys", game.character.mesos == 1000 - 2 * price)
	# Sell two of them back from the Use tab (Tab, 2, Down to the row, Right, Enter).
	await _press(KEY_TAB)
	await _press(KEY_2)
	var row := -1
	for i in shop.sell_rows.size():
		if String(shop.sell_rows[i]["item_id"]) == item_id and int(shop.sell_rows[i]["qty"]) >= 2:
			row = i
			break
	_check("the Sell tab lists the Use slot", shop.mode == "sell" and shop.sell_tab == "use" and row >= 0, str(shop.sell_rows))
	for i in maxi(row, 0):
		await _press(KEY_DOWN)
	await _press(KEY_RIGHT)
	var unit := ShopService.sell_price(item_id, Data.db)
	var mesos1 := game.character.mesos
	var have1 := game.character.inventory.count(item_id)
	await _press(KEY_ENTER)
	await _frames(2)
	_check("selling 2 pays the canonical sell-back price", unit > 0 and game.character.mesos == mesos1 + 2 * unit
		and game.character.inventory.count(item_id) == have1 - 2, "%d -> %d mesos, '%s'" % [mesos1, game.character.mesos, shop.status_text])
	# Insufficient mesos: the Orange Potion with 10 mesos.
	await _press(KEY_TAB)
	game.character.mesos = 10
	await _press(KEY_DOWN)
	var dear := String(shop.buy_rows[shop.selected]["item_id"])
	var dear_price := int(shop.buy_rows[shop.selected]["price"])
	await _press(KEY_ENTER)
	await _frames(2)
	_check("insufficient mesos is refused with the numbers", game.character.mesos == 10 and game.character.inventory.count(dear) == 0
		and shop.status_text == "%s (costs %d, you have 10)" % [ItemCodes.message({"code": ItemCodes.INSUFFICIENT_MESOS}), dear_price]
		and shop.check_label.visible, "'%s' / '%s'" % [shop.status_text, shop.check_label.text])
	# A full Use tab.
	game.character.mesos = 5000
	var items := ItemService.new(game.character, Data.db, get_node("/root/Events"))
	var g := 0
	while game.character.inventory.can_add(item_id, 1, Data.db) and g < 400:
		items.gain(item_id, 100)
		g += 1
	await _press(KEY_UP)
	var held := game.character.inventory.count(item_id)
	await _press(KEY_ENTER)
	await _frames(2)
	_check("a full inventory is refused and costs nothing", game.character.mesos == 5000
		and game.character.inventory.count(item_id) == held and shop.status_text == ItemCodes.message({"code": ItemCodes.INVENTORY_FULL}),
		"'%s', %d mesos" % [shop.status_text, game.character.mesos])
	items.clear_inventory("use")
	game.character.mesos = 1000 - 2 * price
	await _press(KEY_ESCAPE)
	await _frames(3)
	_check("Esc leaves the shop, no pause menu", not ui.shop.is_open() and main.flow.is_in(ShellFlow.State.PLAYING)
		and not main.ctx().is_modal_active())
	await _press(KEY_ESCAPE)
	await _frames(3)
	_check("Esc with nothing open pauses", main.flow.is_in(ShellFlow.State.PAUSED))
	main.resume()
	await _frames(2)


func _loot() -> void:
	var game := get_node("/root/Game") as GameState
	var session := get_node("/root/MapSession")
	await _warp("000000040")
	await _seconds(1.0)
	var loot := _loot_system()
	var monsters := main.game_session.installer.node_of("MonsterSystem")
	var announced := [0]
	var count := func(drops: Array, _at: Vector3, _map: String) -> void: announced[0] += drops.size()
	get_node("/root/Events").connect("loot_dropped", count)
	var killed := int(monsters.call("kill_all")) if monsters != null else 0
	await _seconds(1.2)
	get_node("/root/Events").disconnect("loot_dropped", count)
	_check("monster system kills in 000000040", killed > 0, "%d" % killed)
	_check("every announced drop is on the ground and in the map instance", announced[0] > 0
		and loot.nodes().size() == announced[0] and (session.get("instance_state") as MapInstanceState).drops.size() == announced[0],
		"%d announced, %d nodes" % [announced[0], loot.nodes().size()])
	# Walk onto one drop and press Z.
	var target: GroundDrop = null
	for n: GroundDrop in loot.nodes().values():
		target = n
		break
	if target == null:
		return
	_world().call("place_player", Transform3D(Basis.IDENTITY, target.landing + Vector3(0.1, 0.3, 0.0)))
	await _settle()
	var inter := _inter()
	_check("pickup prompt", inter.prompt.text().begins_with("[Z] Pick up"), inter.prompt.text())
	var before := loot.nodes().size()
	var mesos0 := game.character.mesos
	var inv0 := _inv_total(game.character)
	var n0 := notices.size()
	await _press(KEY_Z)
	await _frames(2)
	_check("Z picks up one drop", loot.nodes().size() == before - 1, "%d -> %d" % [before, loot.nodes().size()])
	_check("it went into the inventory or the mesos", game.character.mesos > mesos0 or _inv_total(game.character) > inv0)
	_check("pickup notice", _any_notice_since(n0, "You have gained"),
		", ".join(_notices_since(n0)))
	var left := loot.nodes().size()
	await _warp("000000010")
	_check("no drop nodes in the other map", loot.nodes().is_empty())
	await _warp("000000040")
	_check("drops kept across the round trip", loot.nodes().size() == left, "%d -> %d" % [left, loot.nodes().size()])
	await _full_inventory_hold()


## A full Etc tab: holding Z next to an Etc drop leaves it on the ground and says so, without flooding the HUD log
## (the pickup key repeats every pickup.hold_repeat_s while held).
func _full_inventory_hold() -> void:
	var game := get_node("/root/Game") as GameState
	var loot := _loot_system()
	var items := ItemService.new(game.character, Data.db, get_node("/root/Events"))
	var guard := 0
	while game.character.inventory.can_add("348", 1, Data.db) and guard < 400:
		items.gain("348", 50)
		guard += 1
	while game.character.inventory.can_add("348", 1, Data.db) and guard < 2000:
		items.gain("348", 1)
		guard += 1
	_check("Etc tab full", not game.character.inventory.can_add("348", 1, Data.db))
	for n: GroundDrop in loot.nodes().values():
		loot.remove_record(n.uid)
	var feet := _player().global_position
	loot.spawn_drops([{"kind": "item", "item_id": "348", "qty": 1}], feet + Vector3(0.3, 0.0, 0.0))
	await _seconds(0.8)
	var hud: Node = main.game_session.installer.node_of("HUD")
	var log_panel: Variant = hud.get("log_panel") if hud != null else null
	var hist0 := ((log_panel as Object).get("history") as Array).size() if log_panel is Object else -1
	var n0 := notices.size()
	Input.parse_input_event(_key_event(KEY_Z, true))
	await _seconds(1.5)
	Input.parse_input_event(_key_event(KEY_Z, false))
	await _frames(3)
	_check("the refused drop stays on the ground", loot.nodes().size() == 1)
	_check("the refusal is announced", _any_notice_since(n0, "Your inventory is full"), ", ".join(_notices_since(n0)))
	var added := ((log_panel as Object).get("history") as Array).size() - hist0 if log_panel is Object else 0
	_check("holding Z does not flood the log", added <= 2 and notices.size() - n0 <= 1,
		"%d HUD lines, %d notices in 1.5 s" % [added, notices.size() - n0])
	_info("refusal lines: %s" % ", ".join(_notices_since(n0)))
	# Make room again for the rest of the flow.
	items.clear_inventory("etc")


func _death_with_shop_open() -> void:
	var game := get_node("/root/Game") as GameState
	var session := get_node("/root/MapSession")
	var ui := _npc_ui()
	get_node("/root/Events").emit_signal("shop_open_requested", "maple-road-lucy", "21")
	await _frames(2)
	_check("Events.shop_open_requested opens the shop", ui.shop.is_open() and main.ctx().is_modal_active())
	game.change_hp(-game.character.hp)
	await _frames(4)
	var dc := main.game_session.death
	_check("death closes the shop", dc.is_dead() and not ui.shop.is_open() and dc.notice.visible)
	dc.notice.confirm()
	var ok := await _until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle")))
	_check("respawned with no modal left", ok and not main.ctx().is_modal_active() and _player().is_input_enabled())


func _second_session() -> void:
	var session := get_node("/root/MapSession")
	await _warp("000000040")
	var loot := _loot_system()
	var dbg := get_node("/root/Debug")
	var out := String(dbg.call("run", "drop_item 270 2"))
	_check("drop_item in the first session", loot.nodes().size() >= 1 and out.begins_with("1 drop"), out)
	var before_quit := "%d in %s" % [loot.nodes().size(), String(session.get("current_map"))]
	main.quit_to_title()
	await _frames(3)
	_check("quit to title", main.flow.is_in(ShellFlow.State.TITLE))
	main.continue_game()
	var ok := await _until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle")))
	_check("continue", ok)
	if not ok:
		return
	await _seconds(0.5)
	loot = _loot_system()
	var st := session.get("instance_state") as MapInstanceState
	_check("the new loot system shows exactly the live instance's drops", loot.nodes().size() == st.drops.size(),
		"%d nodes, %d records in %s" % [loot.nodes().size(), st.drops.size(), st.map_id])
	_info("after continue: %d drop records in %s (%s before the quit)" % [st.drops.size(), st.map_id, before_quit])
	var before := loot.nodes().size()
	out = String(dbg.call("run", "drop_mesos 30"))
	_check("drop_mesos in the second session drops into the new loot system", loot.nodes().size() == before + 1, out)
	_check("the prompt still works", _inter().update_prompt() is Dictionary)


func _shots() -> void:
	if DisplayServer.get_name() == "headless":
		_check("shots need a window", false, "run without --headless")
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _warp("000000010")
	await _stand_before_npc("3")
	await _seconds(1.0)
	await _shot("roger_prompt")
	await _press(KEY_F)
	await _seconds(0.5)
	await _shot("roger_dialogue")
	await _press(KEY_ESCAPE)
	await _warp("000001013")
	(get_node("/root/Game") as GameState).character.mesos = 900
	await _stand_before_npc("21")
	await _press(KEY_F)
	await _seconds(0.3)
	await _press(KEY_ENTER)
	await _seconds(0.5)
	await _shot("lucy_shop")
	await _press(KEY_ESCAPE)
	await _warp("000000040")
	await _seconds(1.0)
	var monsters := main.game_session.installer.node_of("MonsterSystem")
	if monsters != null:
		monsters.call("kill_all")
	await _seconds(1.5)
	var loot := _loot_system()
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
		# Stand just in front of the cluster (toward the camera) so the drops are in view, within reach of the nearest.
		var rig := main.game_session.camera
		var fwd: Vector3 = rig.get("ground_forward") if "ground_forward" in rig else Vector3.FORWARD
		_world().call("place_player", Transform3D(Basis.IDENTITY, best.landing - fwd * 0.45 + Vector3.UP * 0.3))
		if rig.has_method("snap"):
			rig.call("snap")
		await _seconds(1.0)
		await _press(KEY_Z)
		await _seconds(0.4)
	await _shot("loot_pickup")
	# Rain's quiz menu with the second answer highlighted.
	var game := get_node("/root/Game") as GameState
	game.character.level = maxi(game.character.level, 5)
	await _warp("000001010")
	await _stand_before_npc("19")
	await _seconds(0.5)
	await _press(KEY_F)
	await _seconds(0.2)
	await _press(KEY_Y)
	await _seconds(0.2)
	while _npc_ui().dialogue.is_open():
		await _press(KEY_ENTER)
		await _seconds(0.1)
	await _settle()
	await _press(KEY_F)
	await _seconds(0.2)
	await _press(KEY_DOWN)
	await _seconds(0.4)
	await _shot("quiz_menu")
	await _press(KEY_ESCAPE)
	# Lucy's Sell tab, then an unaffordable purchase.
	ItemService.new(game.character, Data.db, get_node("/root/Events")).gain("237", 3)
	await _warp("000001013")
	await _stand_before_npc("21")
	await _press(KEY_F)
	await _seconds(0.3)
	await _press(KEY_ENTER)
	await _seconds(0.5)
	await _press(KEY_TAB)
	await _press(KEY_2)
	await _seconds(0.4)
	await _shot("shop_sell")
	await _press(KEY_TAB)
	game.character.mesos = 10
	await _press(KEY_DOWN)
	await _press(KEY_ENTER)
	await _seconds(0.4)
	await _shot("shop_insufficient")
	await _press(KEY_ESCAPE)


## Sam's Suggestion (quest 1006) through the real UI: Sam's offer with Enter (Yes is highlighted), Backspace on the
## page with Back, the console's `kill all` (the monster system's own deaths) until 10 Snails, every drop picked up with
## Z, then Mai in A Split Road: her "?" marker, the completion page with its summary, the reward.
func _sam_suggestion() -> void:
	var game := get_node("/root/Game") as GameState
	var dbg := get_node("/root/Debug")
	var ui := _npc_ui()
	var out := String(dbg.call("run", "warp 000000040"))
	await _warp("000000040")
	_check("console warp to Snail Hunting Ground I", String(get_node("/root/MapSession").get("current_map")) == "000000040", out)
	await _stand_before_npc("9")
	await _seconds(0.4)
	_check("prompt over Sam", _inter().prompt.text() == "[F] Talk to Sam", _inter().prompt.text())
	await _press(KEY_F)
	await _frames(3)
	_check("Sam's offer with its rewards", String(ui.dialogue.view.get("node_id", "")) == "q1006.offer.0"
		and ui.dialogue.reward_label.visible and ui.dialogue.offer_reward_text().contains("30 EXP"), _vs())
	await _press(KEY_ENTER)
	await _frames(3)
	_check("Enter on the highlighted Yes accepts, with the summary", game.character.quests.status("1006") == QuestLog.IN_PROGRESS
		and ui.dialogue.shown_banner().begins_with("Quest accepted: Sam's Suggestion"), _vs())
	await _press(KEY_ENTER)
	await _frames(3)
	var second := String(ui.dialogue.view.get("node_id", ""))
	await _press(KEY_BACKSPACE)
	await _frames(3)
	_check("Backspace goes back a page", second == "q1006.accepted.1"
		and String(ui.dialogue.view.get("node_id", "")) == "q1006.accepted.0", "%s -> %s" % [second, _vs()])
	var guard := 0
	while ui.dialogue.is_open() and guard < 6:
		await _press(KEY_ENTER)
		await _frames(3)
		guard += 1
	_check("Sam's chat ends with Enter", not ui.dialogue.is_open() and not main.ctx().is_modal_active())
	# Ten Snails through the monster system.
	var rounds := 0
	while game.character.quests.kills("1006", "2") < 10 and rounds < 12:
		var said := String(dbg.call("run", "kill all"))
		rounds += 1
		await _seconds(1.2)
		if said.contains("no live"):
			await _seconds(5.0)
	_check("10 Snails counted through real kills", game.character.quests.kills("1006", "2") >= 10,
		"%d kills after %d rounds" % [game.character.quests.kills("1006", "2"), rounds])
	# Every drop picked up with Z.
	var loot := _loot_system()
	var total := loot.nodes().size()
	var picked := 0
	var misses := PackedStringArray()
	var n0 := notices.size()
	guard = 0
	while not loot.nodes().is_empty() and guard < 80:
		guard += 1
		var n: GroundDrop = loot.nodes().values()[0]
		_world().call("place_player", Transform3D(Basis.IDENTITY, n.landing + Vector3(0.05, 0.3, 0.0)))
		await _settle()
		var before := loot.nodes().size()
		var prompt := _inter().prompt.text()
		await _press(KEY_Z)
		await _frames(2)
		if loot.nodes().size() < before:
			picked += 1
		else:
			misses.append("%s (prompt '%s')" % [n.uid, prompt])
			loot.remove_record(n.uid)
	var gained := 0
	for t in _notices_since(n0):
		if t.begins_with("You have gained"):
			gained += 1
	_check("every drop of the kills picked up with Z", total > 0 and picked == total and misses.is_empty(),
		"%d of %d; missed %s" % [picked, total, ", ".join(misses)])
	_check("one pickup notice per drop", gained == picked, "%d notices, %d pickups" % [gained, picked])
	# Mai.
	await _warp("000000050")
	await _stand_before_npc("11")
	await _seconds(0.4)
	var mai: NpcPresenter = _inter().presenters.get("11")
	_check("Mai shows the ready marker", mai != null and mai.marker.state == "completable" and mai.marker.visible)
	var exp0 := game.character.exp
	var lv0 := game.character.level
	var eggs0 := game.character.inventory.count("237")
	await _press(KEY_F)
	await _frames(3)
	var banner := ""
	guard = 0
	while ui.dialogue.is_open() and guard < 8:
		if banner == "":
			banner = ui.dialogue.shown_banner()
		await _press(KEY_ENTER)
		await _frames(3)
		guard += 1
	_check("Sam's Suggestion completed at Mai", game.character.quests.status("1006") == QuestLog.COMPLETED)
	_check("the reward: 30 EXP and 3 Eggs", (game.character.level > lv0 or game.character.exp == exp0 + 30)
		and game.character.inventory.count("237") == eggs0 + 3, "exp %d -> %d (lv %d -> %d), eggs %d -> %d" % [exp0,
		game.character.exp, lv0, game.character.level, eggs0, game.character.inventory.count("237")])
	_check("the completion summary", banner == "Quest complete: Sam's Suggestion   ·   +30 EXP, +Egg x3", banner)
	_check("Mai's chat ended", not ui.dialogue.is_open() and not main.ctx().is_modal_active())


## Keys and windows under stress: WASD and the arrows in a quiz menu never walk the player; Up in a menu while standing
## in a portal never warps (and the portal works again after the chat); a warp closes an open chat and an open shop;
## a shop request during a chat replaces the chat; a death closes the chat.
func _npc_window_robustness() -> void:
	var game := get_node("/root/Game") as GameState
	var session := get_node("/root/MapSession")
	var dbg := get_node("/root/Debug")
	var ui := _npc_ui()
	game.character.level = maxi(game.character.level, 5)
	await _warp("000001010")
	await _stand_before_npc("19")
	await _seconds(0.4)
	await _press(KEY_F)
	await _frames(3)
	_check("Rain's offer", String(ui.dialogue.view.get("type", "")) == "yes_no", _vs())
	await _press(KEY_Y)
	await _frames(3)
	var guard := 0
	while ui.dialogue.is_open() and guard < 6:
		await _press(KEY_ENTER)
		await _frames(3)
		guard += 1
	await _settle()
	await _press(KEY_F)
	await _frames(3)
	_check("Rain's quiz menu", String(ui.dialogue.view.get("type", "")) == "menu" and ui.dialogue.choice_texts().size() == 4, _vs())
	var p0 := _player().global_position
	var seen := PackedInt32Array()
	for k: Key in [KEY_S, KEY_S, KEY_W, KEY_D, KEY_A, KEY_DOWN, KEY_UP]:
		Input.parse_input_event(_key_event(k, true))
		await _seconds(0.3)
		Input.parse_input_event(_key_event(k, false))
		await _frames(2)
		seen.append(ui.dialogue.selected)
	_check("W/S and the arrows move the highlight", seen == PackedInt32Array([1, 2, 1, 1, 1, 2, 1]), str(seen))
	_check("held WASD and arrows never walk the player in a menu", _player().global_position.distance_to(p0) < 0.02,
		"moved %.3f m" % _player().global_position.distance_to(p0))
	await _press(KEY_BACKSPACE)
	await _frames(2)
	_check("Backspace in a menu without Back does nothing", ui.dialogue.is_open()
		and String(ui.dialogue.view.get("node_id", "")) == "q1013.quiz")
	await _press(KEY_ESCAPE)
	await _frames(3)
	_check("Esc ends the quiz", not ui.dialogue.is_open() and game.character.quests.status("1013") == QuestLog.IN_PROGRESS)
	# Up in a menu while standing in a portal.
	var chosen: WorldPortal = null
	for wp: WorldPortal in _world().call("portals_of", "000001010"):
		if wp.def.accepts_press() and wp.shows_prompt() and wp.def.destination_map_id != "000001010":
			chosen = wp
			break
	_check("a pressable portal in Amherst", chosen != null)
	if chosen != null:
		_world().call("place_player", Transform3D(Basis.IDENTITY, chosen.def.anchor_ground + Vector3.UP * 0.2))
		await _settle()
		await _seconds(0.2)
		_check("standing in the portal", _inter().prompt.text() == "[Up] Enter portal", _inter().prompt.text())
		_inter().talk_to("19")
		await _frames(3)
		for i in 3:
			await _press(KEY_UP)
			await _frames(2)
		await _frames(10)
		_check("Up in a menu inside a portal moves the highlight and never warps", ui.dialogue.selected == 1
			and String(session.get("current_map")) == "000001010" and bool(session.call("is_idle")),
			"selected %d, map %s" % [ui.dialogue.selected, session.get("current_map")])
		await _press(KEY_ESCAPE)
		await _frames(3)
		await _press(KEY_UP)
		await _until(func() -> bool: return String(session.get("current_map")) != "000001010" and bool(session.call("is_idle")), 600)
		_check("after the chat, Up enters that portal again", String(session.get("current_map")) == chosen.def.destination_map_id,
			String(session.get("current_map")))
	# A warp with a chat open, then with the shop open.
	await _warp("000001010")
	await _stand_before_npc("19")
	await _press(KEY_F)
	await _frames(3)
	var was_open := ui.dialogue.is_open()
	var said := String(dbg.call("run", "warp 000000010"))
	await _warp("000000010")
	_check("a warp closes an open chat", was_open and not ui.dialogue.is_open() and not main.ctx().is_modal_active()
		and _player().is_input_enabled(), "%s; %s" % [said, _vs()])
	get_node("/root/Events").emit_signal("shop_open_requested", "maple-road-lucy", "21")
	await _frames(2)
	was_open = ui.shop.is_open()
	dbg.call("run", "warp 000001010")
	await _warp("000001010")
	_check("a warp closes an open shop", was_open and not ui.shop.is_open() and not main.ctx().is_modal_active()
		and not main.ctx().has_open_windows())
	# A shop request during a chat: the shop replaces the chat.
	await _stand_before_npc("19")
	await _press(KEY_F)
	await _frames(3)
	get_node("/root/Events").emit_signal("shop_open_requested", "maple-road-lucy", "21")
	await _frames(3)
	_check("a shop request during a chat replaces the chat", ui.shop.is_open() and not ui.dialogue.is_open())
	await _press(KEY_ESCAPE)
	await _frames(3)
	_check("one Esc leaves the shop and nothing is left under it", not ui.shop.is_open() and not main.ctx().has_open_windows()
		and not main.ctx().is_modal_active() and main.flow.is_in(ShellFlow.State.PLAYING))
	# A death with a chat open.
	await _press(KEY_F)
	await _frames(3)
	was_open = ui.dialogue.is_open()
	game.change_hp(-game.character.hp)
	await _frames(4)
	var dc := main.game_session.death
	_check("death closes the chat", was_open and dc.is_dead() and not ui.dialogue.is_open())
	dc.notice.confirm()
	var ok := await _until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING) and bool(session.call("is_idle")))
	_check("respawned after a death in a chat with the keyboard back", ok and not main.ctx().is_modal_active()
		and _player().is_input_enabled())


## One line describing the dialogue window (failure details).
func _vs() -> String:
	var d := _npc_ui().dialogue
	if not d.is_open():
		return "<closed> modal=%s" % main.ctx().is_modal_active()
	var v := d.view
	return "%s node=%s buttons=%s choices=%s banner='%s' text='%s'" % [v.get("type", ""), v.get("node_id", ""),
		",".join(d.visible_buttons()), " | ".join(d.choice_texts()), d.shown_banner(), d.body_text().left(90).replace("\n", " ")]


# --- helpers -----------------------------------------------------------------------------------------------------

func _inter() -> InteractionSystem:
	return main.game_session.installer.node_of("InteractionSystem") as InteractionSystem


func _npc_ui() -> NpcUi:
	return main.game_session.installer.node_of("NpcUI") as NpcUi


func _loot_system() -> LootSystem:
	return main.game_session.installer.node_of("LootSystem") as LootSystem


func _world() -> Node:
	return main.game_session.world


func _player() -> PlayerController:
	return main.game_session.player as PlayerController


func _inv_total(c: CharacterState) -> int:
	var n := 0
	for tab: String in Inventory.TABS:
		for i in c.inventory.capacity(tab):
			var s := c.inventory.get_slot(tab, i)
			if not s.is_empty():
				n += int(s.qty)
	return n


func _notices_since(n: int) -> PackedStringArray:
	return notices.slice(n)


func _any_notice_since(n: int, prefix: String) -> bool:
	for t in _notices_since(n):
		if t.begins_with(prefix):
			return true
	return false


func _key_event(k: Key, down: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	return e


## Presses and releases a key through Input, like the keyboard.
func _press(k: Key) -> void:
	Input.parse_input_event(_key_event(k, true))
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.parse_input_event(_key_event(k, false))
	await get_tree().physics_frame
	await get_tree().process_frame


func _warp(map_id: String) -> void:
	var session := get_node("/root/MapSession")
	if String(session.get("current_map")) != map_id:
		session.call("debug_warp", map_id)
	await _until(func() -> bool: return bool(session.call("is_idle")))
	await _seconds(0.3)


## Waits until the player stands still on the floor.
func _settle() -> void:
	var p := _player()
	await _until(func() -> bool: return p.is_on_floor() and p.velocity.length() < 0.05, 180)
	await _physics(4)


## Puts the player about 1 m in front of an NPC and snaps the camera (the same placement the sandbox uses).
func _stand_before_npc(npc_id: String) -> void:
	var nodes: Dictionary = _world().get("npc_nodes")
	var npc: Node3D = nodes.get(npc_id)
	if npc == null:
		_check("NPC %s exists" % npc_id, false)
		return
	var front := npc.global_transform.basis.z
	front.y = 0.0
	var dir := front.normalized() if front.length_squared() > 0.001 else Vector3.FORWARD
	var rig := main.game_session.camera
	for dist: float in [1.1, 0.8, 0.6]:
		_world().call("place_player", Transform3D(Basis.looking_at(-dir, Vector3.UP), npc.global_position + dir * dist))
		if rig.has_method("snap"):
			rig.call("snap")
		await _settle()
		if _player().global_position.distance_to(npc.global_position) < 1.5:
			return


func _info(text: String) -> void:
	print("WORLDUI_INFO %s" % text)


func _check(check_name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("WORLDUI_CHECK PASS %s" % check_name)
	else:
		failed += 1
		print("WORLDUI_CHECK FAIL %s%s" % [check_name, (": " + detail) if detail != "" else ""])


func _until(cond: Callable, max_frames: int = TIMEOUT_FRAMES) -> bool:
	var n := 0
	while not bool(cond.call()) and n < max_frames:
		await get_tree().process_frame
		n += 1
	return bool(cond.call())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true).timeout


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_index += 1
	var path := out_dir.path_join("%02d_%s.png" % [_shot_index, label])
	var err := img.save_png(path)
	print("WORLDUI_SHOT %s %s" % [ProjectSettings.globalize_path(path), error_string(err)])


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	if i >= 0 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
		return args[i + 1]
	return fallback


static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
