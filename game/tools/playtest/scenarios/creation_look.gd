extends PlaytestScenario
## creation_look (#67): the look chosen at creation, through the real screens, kept through Quit Game and Continue.
## Phase 0: New Game, the name typed, the gender, then every hair style, every face and every skin clicked on the creation
## screen with a screenshot of each (the live preview), a non-default look (hair 5, face 3, skin 2) clicked and Start.
## In the game the player wears it; then every hair, face and skin on the player in the world (setting the visual's
## look in code: the scenario is a camera here, not a gameplay test), each with a screenshot and a 3x close-up.
## Quit Game ends the process. Phase 1: Continue, and the character and the player still wear the chosen look.
## Run --windowed for the screenshots (headless only checks).
##
##   ISOLATE=look bash scripts/playtest.sh creation_look --windowed              # a female character
##   QUEST=male ISOLATE=look bash scripts/playtest.sh creation_look --windowed   # a male one

const NAME := "Stylist"
## The character's gender: female, or male with QUEST=male (as player_rig takes QUEST=female).
var gender := "male" if OS.get_environment("QUEST") == "male" else "female"
## The look picked at creation (indices; each differs from both defaults, female 2 / 0 / 3 and male 3 / 0 / 0).
const CHOSEN := {"hair_style": 4, "face": 2, "skin": 1}


func description() -> String:
	return "every hair, face and skin on the creation screen and in the game; a chosen look kept through Quit and Continue"


func max_seconds() -> float:
	return 600.0


func run(d: PlaytestDriver) -> void:
	if d.phase == 0:
		await _create(d)
		return
	var c: Dictionary = await d.continue_game()
	if not d.check("continued", bool(c["ok"]), str(c)):
		return
	var ch := d.character()
	d.check("the loaded character keeps its look", ch.appearance == CHOSEN, "%s, chose %s" % [ch.appearance, CHOSEN])
	var vis := d.player().get_node(^"Visual") as PlayerVisual
	d.check("the player wears it after the load", not vis.rigged() or vis.look == CHOSEN, "%s" % vis.look)
	await d.wait(0.8)
	await _shot(d, "after_continue")


func _create(d: PlaytestDriver) -> void:
	var main := d.main
	if not bool((await d.click(main.title.new_button))["ok"]):
		return
	if not d.check("the creation screen opens", await d.wait_until(func() -> bool:
			return main.creation != null and is_instance_valid(main.creation), 10.0)):
		return
	var cs: CreationScreen = main.creation
	await d.click(cs.name_edit)
	await d.input.type_text(NAME)
	await d.click(String(CreationScreen.GENDER_LABELS[gender]))
	d.check("name and gender", cs.model.name == NAME and cs.model.gender == gender, "%s %s" % [cs.model.name, cs.model.gender])
	var preview := cs.preview_visual()
	d.check("the creation screen previews the rigged Beginner", preview != null and preview.rigged(),
		"preset %s" % (preview.preset if preview != null else "(none)"))
	var base := CharacterAppearance.default_for(gender)
	for key in CharacterAppearance.KEYS:
		for i in CharacterAppearance.choices(key):
			if not bool((await d.click(cs.find_child("Look_%s_%d" % [key, i], true, false)))["ok"]):
				continue
			var want := base.duplicate()
			want[key] = i
			d.check("creation %s %d: the model and the preview" % [key, i], cs.model.look() == want
				and (preview == null or not preview.rigged() or preview.look == want), "%s / %s" % [cs.model.look(),
				preview.look if preview != null else {}])
			await d.wait(0.3)
			await d.screenshot("creation_%s_%d" % [key, i])
		await d.click(cs.find_child("Look_%s_%d" % [key, int(base[key])], true, false))
	for key: String in CHOSEN:
		await d.click(cs.find_child("Look_%s_%d" % [key, int(CHOSEN[key])], true, false))
	d.check("the chosen look is on the screen", cs.model.look() == CHOSEN, str(cs.model.look()))
	await d.screenshot("creation_chosen")
	await d.click(cs.start_button)
	if not d.check("the game starts", await d.wait_until(func() -> bool: return main.flow.is_in(ShellFlow.State.PLAYING), 60.0)):
		return
	await d.wait_idle()
	var ch := d.character()
	d.check("the new character has the chosen look", ch.appearance == CHOSEN, str(ch.appearance))
	var vis := d.player().get_node(^"Visual") as PlayerVisual
	d.check("the player wears it", vis.rigged() and vis.look == CHOSEN, "%s %s" % [vis.preset, vis.look])
	await d.wait(1.0)
	await _shot(d, "game_chosen")
	for key in CharacterAppearance.KEYS:
		for i in CharacterAppearance.choices(key):
			var want := base.duplicate()
			want[key] = i
			vis.set_look(gender, want)
			await d.wait(0.4)
			d.check("in game %s %d" % [key, i], not vis.rigged() or vis.look == want, str(vis.look))
			await _shot(d, "game_%s_%d" % [key, i])
	vis.set_look(gender, ch.appearance)
	d.carry["look"] = CHOSEN
	await d.reload_process()


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
