extends PlaytestScenario
## npc_rigs (#66): gameplay-scale screenshots of the 21 rigged NPCs in the real game (run --windowed; headless only
## runs the checks): every NPC idling with its name tag (the player stands beside it), each quest-marker state (Sam
## offers 1006, it is under way at Sam and at Mai, then ready to turn in at Mai), the player half hidden behind Shanks
## (the X-ray fill reads through the taller model), and every NPC's dialogue portrait (plus a 3x crop of it,
## <name>_portrait.png). Each stop checks that the NPC is its art pack model playing idle. Setup steps (teleports,
## the quest accept, the kills that complete it, opening each conversation) go through code, not input: the scenario
## is a camera, not a gameplay test (the npcs scenario walks to every NPC). Without the art pack (NO_ART_PACK=1) it
## shoots the library proxies the same way, for comparison.
##
##   ISOLATE=npc bash scripts/playtest.sh npc_rigs --windowed

## The marker states (test_interaction_system's chain): Sam (9) in Snail Hunting Ground I offers 1006, which sends the
## player to Mai (11) in Snail Hunting Ground II with ten Snails (2).
const SAM := "9"
const MAI := "11"
const QUEST := "1006"
const SNAIL := "2"
const KILLS := 10
const SHANKS := "15"
## How far beside the NPC the player stands for its shot (m, along the camera's right).
const BESIDE_M := 1.3


func description() -> String:
	return "the 21 rigged NPCs: each idling with its name tag, the three quest-marker states, the X-ray behind " + \
		"Shanks, every portrait"


func max_seconds() -> float:
	return 900.0


func run(d: PlaytestDriver) -> void:
	var ng: Dictionary = await d.new_game("Portraits", "female", "541")
	if not d.check("new game", bool(ng["ok"]), String(ng["why"])):
		return
	var w := d.world()
	var by_map := {}
	for npc_id: String in w.npc_nodes:
		var m := String((w.npc_nodes[npc_id] as WorldNpc).map_id())
		if not by_map.has(m):
			by_map[m] = []
		(by_map[m] as Array).append(npc_id)
	var maps := by_map.keys()
	maps.sort()
	for map_id: String in maps:
		await d.console("warp " + map_id)
		await d.wait_idle(10.0)
		var ids: Array = by_map[map_id]
		ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
		for npc_id: String in ids:
			await _npc_shot(d, npc_id)
			await _portrait_shot(d, npc_id)
	await _markers(d)
	await _behind_shanks(d)


## The NPC idling at gameplay scale with its name tag: the player beside it (along the camera's right).
func _npc_shot(d: PlaytestDriver, npc_id: String) -> void:
	var npc := d.world().npc_nodes[npc_id] as WorldNpc
	var label := "%s (%s)" % [npc.placement.npc_name, npc_id]
	if d.world().art != null and d.world().art.present():
		d.check("%s is its art pack model" % label, npc.model_source.begins_with("res://"), npc.model_source)
		var ap := npc.animation_player()
		d.check("%s idles" % label, ap != null and ap.is_playing() and String(ap.current_animation) == WorldNpc.CLIP_IDLE,
			String(ap.current_animation) if ap != null else "no AnimationPlayer")
	else:
		d.note("NO ART PACK: %s shows %s" % [label, npc.model_source if npc.model_source != "" else "the placeholder"])
	_stand_beside(d, npc)
	await d.wait(0.8)
	var p := _presenter(d, npc_id)
	d.check("%s shows its name tag" % label, p != null and p.tag.visible)
	if p != null:
		d.note("NPC %s height=%.2f marker='%s'" % [label, p.height, p.marker.state])
	await d.screenshot("npc_%s_%s" % [npc_id, npc.placement.npc_name])


## The conversation's first view with the speaker's portrait, plus a 3x crop of the portrait.
func _portrait_shot(d: PlaytestDriver, npc_id: String) -> void:
	var npc := d.world().npc_nodes[npc_id] as WorldNpc
	var label := "%s (%s)" % [npc.placement.npc_name, npc_id]
	var v: Dictionary = d.interaction().call("talk_to", npc_id)
	await d.wait_until(d.dialogue_open, 3.0)
	await d.wait(0.4)
	var portrait := d.dialogue().get("portrait") as NpcPortrait
	d.check("%s: a conversation opens" % label, not v.is_empty() and d.dialogue_open())
	d.check("%s: the portrait renders the model" % label, portrait != null and portrait.mode == "model",
		portrait.mode if portrait != null else "no portrait")
	var path: String = await d.screenshot("portrait_%s_%s" % [npc_id, npc.placement.npc_name])
	if path != "" and portrait != null:
		var img := Image.load_from_file(path)
		var r := Rect2i(portrait.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x > 0 and r.size.y > 0:
			var crop := img.get_region(r)
			crop.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_LANCZOS)
			crop.save_png(path.get_basename() + "_portrait.png")
	await d.close_dialogue()


## Sam offers 1006 (available), the player accepts it (in progress at Sam and at Mai), ten Snails later Mai has it
## ready to turn in (completable).
func _markers(d: PlaytestDriver) -> void:
	var sam := d.world().npc_nodes[SAM] as WorldNpc
	await d.console("warp " + sam.map_id())
	await d.wait_idle(10.0)
	_stand_beside(d, sam)
	await d.wait(0.8)
	await _marker_shot(d, SAM, "available")
	await d.console("quest accept " + QUEST)
	await d.wait(0.5)
	await _marker_shot(d, SAM, "in_progress")
	var mai := d.world().npc_nodes[MAI] as WorldNpc
	await d.console("warp " + mai.map_id())
	await d.wait_idle(10.0)
	_stand_beside(d, mai)
	await d.wait(0.8)
	await _marker_shot(d, MAI, "in_progress")
	for i in KILLS:
		d.events().emit_signal(&"monster_killed", SNAIL, sam.map_id())
	await d.wait(0.5)
	await _marker_shot(d, MAI, "completable")


func _marker_shot(d: PlaytestDriver, npc_id: String, want: String) -> void:
	var p := _presenter(d, npc_id)
	if p != null:
		p.refresh_marker()
	await d.frames(2)
	var state := p.marker.state if p != null else "(no presenter)"
	d.check("npc %s shows the '%s' marker" % [npc_id, want], state == want and p.marker.visible, "marker '%s'" % state)
	await d.screenshot("marker_%s_%s" % [npc_id, want])


## The player just behind Shanks as the camera sees him: the taller model hides the body, and the X-ray fill paints
## the hidden part.
func _behind_shanks(d: PlaytestDriver) -> void:
	var shanks := d.world().npc_nodes[SHANKS] as WorldNpc
	await d.console("warp " + shanks.map_id())
	await d.wait_idle(10.0)
	var cam := d.get_viewport().get_camera_3d()
	var away := -cam.global_transform.basis.z
	away = Vector3(away.x, 0.0, away.z).normalized()
	d.player().teleport(Transform3D(Basis.IDENTITY, shanks.global_position + away * 0.55 + Vector3.UP * 0.3))
	await d.wait(1.0)
	await d.screenshot("xray_behind_shanks")


func _stand_beside(d: PlaytestDriver, npc: WorldNpc) -> void:
	var cam := d.get_viewport().get_camera_3d()
	var right := cam.global_transform.basis.x if cam != null else Vector3.RIGHT
	right = Vector3(right.x, 0.0, right.z).normalized()
	d.player().teleport(Transform3D(Basis.IDENTITY, npc.global_position + right * BESIDE_M + Vector3.UP * 0.3))


func _presenter(d: PlaytestDriver, npc_id: String) -> NpcPresenter:
	var ps: Variant = d.interaction().get("presenters")
	return (ps as Dictionary).get(npc_id) as NpcPresenter if ps is Dictionary else null
