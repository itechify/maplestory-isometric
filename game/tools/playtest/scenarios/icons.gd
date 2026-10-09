extends PlaytestScenario
## icons: every UI place an item or skill icon is drawn, in the real game, for the icon packs (#49-#51, ADR 0001).
## A new game is set up through the console (level 10, one of every canonical item, setup only), spends its 9 SP with
## the Skills window's "+" buttons and puts the three Beginner skills on keys 1-3 and a Red Potion on key 4. Then:
## the Skills window, each Item window tab, an item tooltip, the Equipment window with four items worn, the HUD with
## Recovery and Nimble Feet running (effects bar), Recovery cooling down and Three Snails out of MP, a quest's reward
## icons, and Pan's shop (a row selected: the 64 px detail icon). With --windowed each step leaves a screenshot.
## The checks count how many drawn icons show pack art: with the maplestory_io pack built (scripts/build_runtime.sh)
## every one does; from a fresh clone (no pack PNGs) none does and the procedural icons are drawn instead, which the
## report states rather than fails, so the scenario also documents the fallback.

const PAN_STORE := "000000061"
const PAN := "16"
const RED_POTION := "270"
const SNAILS := "0001000"
const RECOVERY := "0001001"
const NIMBLE := "0001002"
const KEYS := {SNAILS: "1", RECOVERY: "2", NIMBLE: "3"}
## Worn for the Equipment window with the starting Sword (the character is female): Red Skullcap, White Tube Top, Red
## Miniskirt and Leather Sandals. Given first, so a full Equip tab never refuses them.
const WEAR: PackedStringArray = ["710", "937", "1160", "1305"]
## Quests whose reward lists hold items, tried in order on the Available tab.
const REWARD_QUESTS: PackedStringArray = ["1006", "1008", "1009", "1012", "1019"]

var k: PlaytestKit = null


func description() -> String:
	return "item and skill icons in every UI place (Skills, Item tabs, tooltip, Equipment, HUD, quest rewards, shop): pack art or the procedural base"


func max_seconds() -> float:
	return 600.0


func run(d: PlaytestDriver) -> void:
	k = PlaytestKit.new(d)
	var ng: Dictionary = await d.new_game("Iconic", "female", "541", {})
	if not d.check("new game", bool(ng["ok"]), String(ng.get("why", ""))):
		return
	var c := d.character()
	var db := d.db()
	var packed := MisoIconResolver.shared().art(MisoIconResolver.ITEMS, String(db.item(RED_POTION)["game_item_id"])) != null
	d.note("the maplestory_io pack is %s" % ("built: icons should show pack art" if packed else "absent: icons are procedural"))

	# --- setup: level 10, one of every canonical item --------------------------------------------------------------
	await d.console("level 10")
	var given := 0
	for id: String in WEAR:
		await d.console("give %s 1" % id)
	for id: String in db.ids("items"):
		if id in WEAR:
			given += 1
			continue
		var out := await d.console("give %s 1" % id)
		if out.begins_with("gave"):
			given += 1
	d.note("%d of %d items given (a full tab refuses the rest)" % [given, db.ids("items").size()])
	await d.console("mesos 5000")

	# --- Skills window: 9 SP spent with "+", keys 1-3 --------------------------------------------------------------
	if not d.check("K opens the Skills window", await d.open_window("skills")):
		return
	var w: Node = d.windows().call("window_by_name", "skills")
	for sid: String in [SNAILS, RECOVERY, NIMBLE]:
		for i in 3:
			await d.click(w.get("plus_buttons")[sid])
	d.check("9 SP spent", c.sp == 0, "SP %d" % c.sp)
	for sid: String in [SNAILS, RECOVERY, NIMBLE]:
		await d.click(w.get("rows")[sid]["panel"])
		await d.click(w.get("key_button"))
		await d.click(w.get("key_buttons")[KEYS[sid]])
	await d.frames(2)
	_count_art(d, "the Skills window", w, packed)
	await d.screenshot("icons_skills_window")
	await d.close_window("skills")
	await k.bind_quickslot(RED_POTION, "4")

	# --- Item window: every tab, then a tooltip -------------------------------------------------------------------
	await d.open_window("inventory")
	var inv := k.inventory_window()
	for tab: String in Inventory.TABS:
		await d.click(inv.tab_buttons[tab])
		await d.frames(2)
		_count_art(d, "the Item window's %s tab" % tab, inv, packed)
		await d.screenshot("icons_inventory_%s" % tab)
	await d.click(inv.tab_buttons["use"])
	await d.frames(2)
	var idx := k.slot_index("use", RED_POTION)
	if idx >= 0:
		var rows: Array = await k.tooltip_rows(inv.slots[idx])
		d.check("hovering Red Potion shows its tooltip", not rows.is_empty(), str(rows.size()))
		await d.screenshot("icons_tooltip_red_potion")
	await d.close_window("inventory")

	# --- Equipment window ----------------------------------------------------------------------------------------
	for id: String in WEAR:
		await k.equip(id)
	if await d.open_window("equipment"):
		var eq: Node = d.windows().call("window_by_name", "equipment")
		await d.frames(2)
		_count_art(d, "the Equipment window", eq, packed)
		await d.screenshot("icons_equipment")
		await d.close_window("equipment")

	# --- HUD: effects bar, a cooldown, a skill out of MP -----------------------------------------------------------
	await d.console("mp max")
	await d.tap(&"quickslot_2")
	await d.tap(&"quickslot_3")
	await d.wait(0.5)
	await d.console("mp 0")
	await d.frames(4)
	_count_art(d, "the HUD (quickslots, effects bar)", d.hud(), packed)
	await d.screenshot("icons_hud_effects_cooldown_no_mp")

	# --- Quest log: a quest's reward icons --------------------------------------------------------------------------
	for qid: String in REWARD_QUESTS:
		var qw: Dictionary = await k.quest_window(qid, MisoQuestWindow.TAB_AVAILABLE)
		if bool(qw.get("ok", false)):
			d.note("quest %s shown on the Available tab" % qid)
			break
	await d.frames(2)
	# The rewards end the quest's detail: scrolled into view for the screenshot.
	var quests: Node = d.windows().call("window_by_name", "quests")
	for sc in quests.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).scroll_vertical = 100000
	await d.frames(2)
	_count_art(d, "the Quest Log", quests, packed)
	await d.screenshot("icons_quest_rewards")
	await d.close_window("quests")

	# --- Pan's shop: rows and the 64 px detail ---------------------------------------------------------------------
	await d.console("warp " + PAN_STORE)
	await d.wait(1.0)
	if d.check("Pan's shop opens", await k.open_shop(PAN)):
		var sw: Node = d.shop()
		# The first row selected (setup: the window's own select), so the detail shows its 64 px icon.
		sw.call("select", 0)
		await d.frames(2)
		_count_art(d, "Pan's shop", sw, packed)
		await d.screenshot("icons_shop_buy")
		await k.close_shop()


## Notes how many visible item and skill icons under `root` draw pack art, and checks the pack's effect: every one
## with the pack built, none without it.
func _count_art(d: PlaytestDriver, where: String, root: Node, packed: bool) -> void:
	if root == null:
		d.note("%s: not found" % where)
		return
	var shown := 0
	var with_art := 0
	for n in root.find_children("*", "", true, false):
		if not (n is MisoItemIcon or n is MisoSkillIcon) or not (n as Control).is_visible_in_tree():
			continue
		if n is MisoItemIcon and String((n as MisoItemIcon).game_item_id) == "":
			continue
		shown += 1
		if n.get("art") != null:
			with_art += 1
	if shown == 0:
		d.note("%s: no icon shown" % where)
	elif packed:
		d.check("%s: every icon shows pack art" % where, with_art == shown, "%d of %d" % [with_art, shown])
	else:
		d.check("%s: no pack, every icon is procedural" % where, with_art == 0, "%d of %d with art" % [with_art, shown])
