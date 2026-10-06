extends PlaytestScenario
## save_it2_continue: a real Iteration Two save in the real game (contract C3, docs/runtime/SAVES.md). Phase 0 puts
## the Iteration Two save game/tests/data/saves/it2/d_inventory.json (save_version 1, byte for byte) into the run's
## save folder, as a player who installs the new build has it, and quits. Phase 1, a new process: the title offers
## Continue for it, and Continue migrates it to save_version 2. The character resumes in the Southperry Armor Store at
## the saved point (or at the saved entry if that map's collision changed since), with the same character,
## inventory, equipment, quests and HUD; quickslot 1 is still the Egg, now a typed binding. The pause menu's Save
## writes save_version 2 and keeps the untouched v1 file as slot1.json.pre-v1, and Quit Game saves again. Phase 2,
## another process: Continue loads the v2 file with no migration and the same character, and the v1 copy is intact.

const FIXTURE := "res://tests/data/saves/it2/d_inventory.json"
const SLOT := "slot1"
const MAP := "000000061"
const KEY := "1"
const EGG := "237"
## Character fields that must come through the migration exactly as the Iteration Two file holds them.
const SAME_KEYS: Array[String] = ["name", "gender", "job", "level", "exp", "hp", "mp", "base_max_hp", "base_max_mp",
	"base_stats", "ap", "sp", "fame", "mesos", "skills", "inventory", "equipment", "flags"]


func description() -> String:
	return "a real Iteration Two save: Continue migrates it to v2 in the real game, Save keeps the v1 copy, " \
		+ "a new process loads v2 with no migration"


func max_seconds() -> float:
	return 120.0


func run(d: PlaytestDriver) -> void:
	match d.phase:
		0:
			await _phase0(d)
		1:
			await _phase1(d)
		_:
			await _phase2(d)


func _phase0(d: PlaytestDriver) -> void:
	var dst := d.save_dir.path_join(SLOT + ".json")
	var f := FileAccess.open(dst, FileAccess.WRITE)
	f.store_buffer(FileAccess.get_file_as_bytes(FIXTURE))
	f.close()
	d.check("the Iteration Two save is in the save folder, byte for byte",
		FileAccess.get_file_as_bytes(dst) == FileAccess.get_file_as_bytes(FIXTURE), dst)
	await d.reload_process()


func _phase1(d: PlaytestDriver) -> void:
	var listed := _entry(d)
	d.check("the slot list reads the Iteration Two file (save_version 1)", bool(listed.get("ok", false))
		and int(listed.get("save_version", -1)) == 1, str(listed))
	d.check("the title offers Continue for it", d.main.title.continue_button.visible
		and d.main.title.continue_slot == SLOT, "%s / %s" % [d.main.title.continue_button.visible, d.main.title.continue_slot])
	if not await _continue(d):
		return
	_check_location(d)
	_check_character(d, "after the migration")
	var hud := d.hud() as MisoHud
	d.check("the HUD shows quickslot %s bound to the Egg (none left: 0)" % KEY,
		MisoQuickslots.item_for(d.character(), KEY) == EGG and hud.status.quickslots.count_text(KEY) == "0",
		"'%s' -> '%s'" % [MisoQuickslots.item_for(d.character(), KEY), hud.status.quickslots.count_text(KEY)])
	var s: Dictionary = await d.save_game()
	d.check("the pause menu's Save", bool(s["ok"]) and s["via"] == "screen", "%s via %s %s" % [s["slot"], s["via"], s["status"]])
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(d.save_dir.path_join(SLOT + ".json")))
	d.check("the save is now save_version 2", raw is Dictionary and int((raw as Dictionary).get("save_version", 0)) == 2,
		str((raw as Dictionary).get("save_version", null)) if raw is Dictionary else "unreadable")
	_check_copy(d, "after the first save")
	await d.reload_process()


func _phase2(d: PlaytestDriver) -> void:
	var listed := _entry(d)
	d.check("the slot list reads save_version 2", bool(listed.get("ok", false))
		and int(listed.get("save_version", -1)) == 2, str(listed))
	var r := (d.saves() as SaveService).read_save(SLOT)
	d.check("no migration is needed any more", r.ok() and r.migrations_applied.is_empty(), str(r.migrations_applied))
	_check_copy(d, "after Quit Game saved again")
	if not await _continue(d):
		return
	d.check("in the Southperry Armor Store again", d.current_map() == MAP, d.current_map())
	_check_character(d, "after the v2 reload")


func _continue(d: PlaytestDriver) -> bool:
	var c: Dictionary = await d.continue_game()
	return d.check("Continue on the title", bool(c["ok"]) and c["via"] == "screen", str(c))


func _entry(d: PlaytestDriver) -> Dictionary:
	for e: Dictionary in (d.saves() as SaveService).list_saves():
		if String(e["slot"]) == SLOT:
			return e
	return {}


func _fixture() -> Dictionary:
	return SaveDocument.normalize_numbers(JSON.parse_string(FileAccess.get_file_as_string(FIXTURE)))


## The saved resume point when the map is unchanged (its collision hash equals the saved one), else the entry.
func _check_location(d: PlaytestDriver) -> void:
	d.check("in the Southperry Armor Store", d.current_map() == MAP, d.current_map())
	var resume: Dictionary = _fixture()["world"]["location"]["resume"]
	var def := (d.session().call("get_defs") as MapDefinitions).get_def(MAP)
	var rec: Variant = d.session().get("last_transition")
	var step := (rec as TransitionRecord).load_step if rec is TransitionRecord else ""
	if def.content_hash == String(resume["map_content_hash"]):
		var lp: Array = resume["local_pos"]
		var off := (d.state()["position"] as Vector3).distance_to(def.to_world(Vector3(lp[0], lp[1], lp[2])))
		d.check("the map is unchanged: resumed at the saved point", step == ArrivalResolver.STEP_RESUME and off < 1.0,
			"step %s, %.2f m from the saved point" % [step, off])
	else:
		d.check("the map changed since the save: arrived at the saved entry", step == ArrivalResolver.STEP_ENTRY,
			"step %s (saved hash %s, now %s)" % [step, resume["map_content_hash"], def.content_hash])


func _check_character(d: PlaytestDriver, when: String) -> void:
	var saved: Dictionary = _fixture()["character"]
	var now := d.character().to_dict()
	for k in SAME_KEYS:
		var df := PlaytestDriver.diff(saved.get(k), now.get(k), "$." + k)
		d.check("%s: %s is what the Iteration Two save held" % [when, k], df == "", df)
	d.check("%s: Sam's Suggestion (1006) is still completed" % when, d.character().quests.is_completed("1006")
		and d.character().quests.completions("1006") == 1, d.character().quests.status("1006"))
	d.check("%s: quickslot %s is a typed item binding" % [when, KEY],
		d.character().quickslots.get(KEY) == {"kind": "item", "id": EGG}, str(d.character().quickslots))


func _check_copy(d: PlaytestDriver, when: String) -> void:
	var copy := d.save_dir.path_join(SLOT + ".json.pre-v1")
	d.check("%s: the v1 file is kept, byte for byte, as %s.json.pre-v1" % [when, SLOT],
		FileAccess.file_exists(copy) and FileAccess.get_file_as_bytes(copy) == FileAccess.get_file_as_bytes(FIXTURE), copy)
