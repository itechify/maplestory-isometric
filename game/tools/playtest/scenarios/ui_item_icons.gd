extends PlaytestScenario
## ui_item_icons: item icons in the real game (#69). Every item icon is the art pack's rendered icon when the pack is
## installed, else the procedural shape. A new Beginner, set to level 5, is given equipment, potions, food and
## monster drops (console level and give, setup only) -> the inventory window on its Equip, Use and Etc tabs, with a
## Red Potion on quickslot 1 -> the equipment window after equipping a hat, a top, a bottom and shoes -> an item
## tooltip (hovering an inventory slot)
## -> the quest window on Lucas's Reply (1008), whose random rewards are items -> Lucy's shop (Events.
## shop_open_requested), its rows and the detail of one item. On each surface every visible MisoItemIcon with an item
## draws the pack's icon (MisoItemIcon.art) with the pack, and none does without it. Screenshots need --windowed.

const WEAPON := "541"
const GIVE := ["933", "1157", "1305", "708", "1002", "1440", "270", "271", "236", "237", "239", "348", "349", "351",
	"356", "350", "441"]
const WEAR := ["708", "933", "1157", "1305"]
const QUEST := "1008"
const LUCY_STORE := "000001013"
const LUCY_SHOP := "maple-road-lucy"
const LUCY := "21"

var _pack := false


func description() -> String:
	return "item icons: the pack's rendered icons (or the procedural shapes without the pack) in the inventory, " \
		+ "quickslots, equipment, a tooltip, the quest rewards and a shop"


func max_seconds() -> float:
	return 300.0


func run(d: PlaytestDriver) -> void:
	_pack = ArtPack.load_installed().present()
	d.note("art pack installed: %s" % _pack)
	var ng: Dictionary = await d.new_game("Icons", "male", WEAPON, {"str": 9})
	if not d.check("new game through the title and creation screens", bool(ng["ok"]), str(ng)):
		return
	await d.console("level 5")  # so the hat can be worn
	for id: String in GIVE:
		await d.console("give %s 3" % id)
	var kit := PlaytestKit.new(d)
	var root := d.windows() as MisoWindowsRoot

	# The inventory, tab by tab, with a Red Potion on quickslot 1 (the HUD's quickslot bar).
	if d.check("the inventory window opens (I)", await d.open_window("inventory")):
		var inv := root.inventory
		inv.select_tab("use")
		inv.select_slot(inv.visible_item_ids().find("270"))
		inv.assign_quickslot("1")
		for tab: String in ["equip", "use", "etc"]:
			inv.select_tab(tab)
			await d.frames(3)
			_check_icons(d, "the inventory's %s tab" % tab, inv)
			await d.screenshot("inventory_" + tab)
		_check_icons(d, "the quickslot bar", d.hud())
		# A tooltip: hovering the first Equip slot.
		inv.select_tab("equip")
		await d.frames(2)
		inv.slots[0].hover_changed.emit(inv.slots[0], true)
		await d.frames(3)
		d.check("hovering a slot shows the tooltip", root.tooltip.visible)
		_check_icons(d, "the tooltip", root.tooltip)
		await d.screenshot("tooltip")
		inv.slots[0].hover_changed.emit(inv.slots[0], false)
		await d.close_window("inventory")

	# The equipment window.
	for id: String in WEAR:
		var eq: Dictionary = await kit.equip(id)
		d.soft_check("equip %s" % id, bool(eq["ok"]), str(eq))
	if d.check("the equipment window opens (E)", await d.open_window("equipment")):
		await d.frames(3)
		_check_icons(d, "the equipment window", root.equipment)
		await d.screenshot("equipment")
		await d.close_window("equipment")

	# The quest window on a quest with item rewards, scrolled down to them.
	if d.check("the quest window opens (Q)", await d.open_window("quests")):
		root.quests.select_tab(MisoQuestWindow.TAB_AVAILABLE)
		root.quests.select_quest(QUEST)
		await d.frames(3)
		(root.quests.detail_box.get_parent() as ScrollContainer).scroll_vertical = 100000
		await d.frames(3)
		_check_icons(d, "the quest rewards", root.quests)
		await d.screenshot("quest_rewards")
		await d.close_window("quests")

	# A shop: Lucy's, opened as her conversation would.
	await d.console("warp " + LUCY_STORE)
	d.get_tree().root.get_node("Events").emit_signal("shop_open_requested", LUCY_SHOP, LUCY)
	await d.frames(5)
	var shop := d.shop()
	if d.check("Lucy's shop opens", shop != null and bool(shop.call("is_open"))):
		shop.call("select_buy_item", "270")
		await d.frames(3)
		_check_icons(d, "the shop", shop)
		await d.screenshot("shop")
		await d.close_shop()


## Every visible item icon under `root` draws the pack's icon with the pack, and the procedural shape without it.
func _check_icons(d: PlaytestDriver, where: String, root: Node) -> void:
	if root == null:
		d.check("%s is there" % where, false)
		return
	var with_art := 0
	var shapes: PackedStringArray = []
	for n in root.find_children("*", "MisoItemIcon", true, false):
		var icon := n as MisoItemIcon
		if icon.item_id == "" or not icon.is_visible_in_tree():
			continue
		if icon.art != null:
			with_art += 1
		else:
			shapes.append("%s:%s" % [icon.item_id, icon.shape])
	var total := with_art + shapes.size()
	if _pack:
		d.check("%s: all %d item icons are the pack's" % [where, total], total > 0 and shapes.is_empty(), ", ".join(shapes))
	else:
		d.check("%s: all %d item icons are procedural (no pack)" % [where, total], total > 0 and with_art == 0,
			"%d with art" % with_art)
