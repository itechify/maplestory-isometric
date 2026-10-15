extends PlaytestScenario
## wardrobe (#68): equipped items show on the player in the real game, through the real windows. A new Beginner holds
## the starter weapon -> level 15 and a set of wearables given (console level and give, setup only) -> each equipped
## by double-clicking it in the Item window (PlaytestKit.equip: ItemService, Events.equipment_changed), and the
## player wears it at once -> the hat taken off in the Equipment window and put back -> a weapon swap -> an attack and
## sitting on The Green Relaxer with everything on -> Save and Quit Game. Phase 1: Continue, and the player still
## wears all of it. Without the art pack (NO_ART_PACK=1) the placeholder shows nothing and only the equipment is
## checked. Run --windowed for the screenshots (each with a 3x close-up).
##
##   ISOLATE=wardrobe bash scripts/playtest.sh wardrobe --windowed              # a female character
##   QUEST=male ISOLATE=wardrobe bash scripts/playtest.sh wardrobe --windowed   # a male one

const STARTER := "541"
const SWAP := "585"
const CHAIR := "522"
## Per gender: what is given and worn (a level 15 Beginner can wear all of it).
const WEAR := {
	"female": ["708", "937", "1160", "1306", "900"],
	"male": ["708", "933", "1157", "1305", "900"],
}

var gender := "male" if OS.get_environment("QUEST") == "male" else "female"
var _pack := false


func description() -> String:
	return "equipped wearables and weapons show on the player at once, through equip, unequip, swap, attack, sit " \
		+ "and Save / Continue"


func max_seconds() -> float:
	return 420.0


func run(d: PlaytestDriver) -> void:
	_pack = ArtPack.shared().present()
	d.note("art pack installed: %s; %s character" % [_pack, gender])
	if d.phase == 0:
		await _dress(d)
		return
	var c: Dictionary = await d.continue_game()
	if not d.check("continued", bool(c["ok"]), str(c)):
		return
	await d.wait_idle()
	var want: Dictionary = d.carry.get("equipped", {})
	d.check("the loaded character keeps its equipment", PlayerVisual.shown_equipment(d.character().equipment.equipped()) == want,
		"%s, saved %s" % [d.character().equipment.equipped(), want])
	_check_worn(d, "after Continue", want)
	await d.wait(0.8)
	await _shot(d, "after_continue")


func _dress(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Wardrobe", gender, STARTER, {"str": 9})
	if not d.check("new game", bool(ng["ok"]), str(ng)):
		return
	await d.wait_idle()
	_check_worn(d, "the new Beginner holds the starter weapon", {"weapon": STARTER})
	await d.wait(0.6)
	await _shot(d, "starter")
	await d.console("level 15")
	for id: String in WEAR[gender] + [SWAP, CHAIR]:
		await d.console("give %s 1" % id)
	var kit := PlaytestKit.new(d)
	for id: String in WEAR[gender]:
		var eq: Dictionary = await kit.equip(id)
		if not d.check("equip %s" % id, bool(eq["ok"]), str(eq)):
			continue
		await d.wait(0.3)
		_check_worn(d, "%s shows once equipped" % id, PlayerVisual.shown_equipment(d.character().equipment.equipped()))
		await _shot(d, "equip_%s_%s" % [eq["slot"], id])
	var root := d.windows() as MisoWindowsRoot
	if d.check("the equipment window opens (E)", await d.open_window("equipment")):
		var r: Dictionary = root.equipment.unequip_slot("hat")
		await d.frames(2)
		await d.close_window("equipment")
		d.check("the hat comes off", bool(r.get("ok", false)), str(r))
		_check_worn(d, "the hat is gone at once", PlayerVisual.shown_equipment(d.character().equipment.equipped()))
		await d.wait(0.3)
		await _shot(d, "hat_off")
		await kit.equip("708")
	var sw: Dictionary = await kit.equip(SWAP)
	d.check("the weapon swap", bool(sw["ok"]) and sw["slot"] == "weapon", str(sw))
	_check_worn(d, "the swapped weapon is in hand", PlayerVisual.shown_equipment(d.character().equipment.equipped()))
	await d.wait(0.3)
	await _shot(d, "fully_equipped")
	await d.tap(&"attack")
	await d.wait(0.25)
	await _shot(d, "attack")
	await d.wait(1.0)
	var sit: Dictionary = await kit.use_chair(CHAIR)
	d.check("sits on The Green Relaxer", bool(sit["ok"]), str(sit))
	await d.wait(1.5)
	await _shot(d, "sit")
	await kit.stand()
	d.carry["equipped"] = PlayerVisual.shown_equipment(d.character().equipment.equipped())
	var saved: Dictionary = await d.save_game()
	d.check("saved", bool(saved["ok"]), str(saved))
	await d.reload_process()


## The player shows exactly `want` (slot -> item id) on the rig; without the art pack only the placeholder.
func _check_worn(d: PlaytestDriver, what: String, want: Dictionary) -> void:
	var vis := d.player().get_node(^"Visual") as PlayerVisual
	if not _pack:
		d.check(what + " (no art pack: the placeholder)", not vis.rigged() and vis.worn.is_empty(), str(vis.worn))
		return
	var on_model := {}
	for n in vis.model.find_children("*", "", true, false):
		if n.has_meta(&"item_id"):
			on_model[String(n.get_meta(&"item_id"))] = true
	var ids := want.values()
	ids.sort()
	var shown := on_model.keys()
	shown.sort()
	d.check(what, vis.rigged() and vis.worn == want and shown == ids and vis.wardrobe.get("missing", []).is_empty(),
		"worn %s, on the model %s, want %s" % [vis.worn, shown, want])


func _shot(d: PlaytestDriver, shot_name: String) -> void:
	var path: String = await d.screenshot(shot_name)
	if path == "":
		return
	var img := Image.load_from_file(path)
	var cam := d.get_viewport().get_camera_3d()
	if cam == null or img == null:
		return
	var at := Vector2i(cam.unproject_position(d.player().global_position + Vector3.UP * 0.8))
	var r := Rect2i(at - Vector2i(110, 100), Vector2i(220, 200)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var crop := img.get_region(r)
	crop.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_LANCZOS)
	crop.save_png(path.get_basename() + "_zoom.png")
