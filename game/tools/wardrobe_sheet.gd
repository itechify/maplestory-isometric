extends Node3D
## Contact sheets of the rigged Beginner wearing equipment (#68), built the way the player is (ArtPack preset,
## CharacterLook, CharacterWardrobe), for reviewing the wardrobe by eye. Needs the art pack and a real window.
##
##   bash scripts/godot.sh --path game --resolution 1600x900 --disable-vsync res://tools/wardrobe_sheet.tscn -- \
##       --sheet wearables|hats_male|hats_female|weapons --out <file.png> [--only <word,...>] [--px <pixels per m>]
##
##   wearables     all 40 pack wearables, each worn alone (tops and bottoms on their gender, the rest on both)
##   hats_<g>      every hair style (rows) under no hat and every hat (columns), on the <g> preset
##   weapons       the three starter weapons in idle, attack and sitting on The Green Relaxer, on both presets
## Prints SHEET_SAVED <file> (or SHEET_FAILED <why>) and quits.

const CELL_W := 1.0
const CELL_H := 1.75
const PX_PER_M := 190.0
const BACKGROUND := Color(0.86, 0.89, 0.93)
const CHAIR := "522"
const STARTER_WEAPONS := ["541", "576", "585"]

var art: ArtPack
var _viewport: SubViewport


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var sheet := _arg(args, "--sheet", "wearables")
	var out := _arg(args, "--out", "")
	art = ArtPack.shared()
	if not art.present() or out == "":
		print("SHEET_FAILED %s" % ("no art pack" if not art.present() else "no --out"))
		get_tree().quit(1)
		return
	var cells: Array = _only(_cells(sheet), _arg(args, "--only", ""))
	if cells.is_empty():
		print("SHEET_FAILED unknown sheet %s" % sheet)
		get_tree().quit(1)
		return
	var cols := 0
	for c: Dictionary in cells:
		cols = maxi(cols, int(c["col"]) + 1)
	var rows := int(cells[cells.size() - 1]["row"]) + 1
	_viewport = SubViewport.new()
	var px := float(_arg(args, "--px", str(PX_PER_M)))
	_viewport.size = Vector2i(ceili(cols * CELL_W * px), ceili(rows * CELL_H * px))
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var stage := Node3D.new()
	_viewport.add_child(stage)
	_light(stage)
	for c: Dictionary in cells:
		_place(stage, c)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = rows * CELL_H
	cam.position = Vector3(cols * CELL_W / 2.0, -rows * CELL_H / 2.0 + CELL_H, 10.0)
	stage.add_child(cam)
	cam.current = true
	for _i in 6:
		await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	img.save_png(out)
	print("SHEET_SAVED %s (%d cells, %dx%d)" % [out, cells.size(), img.get_width(), img.get_height()])
	get_tree().quit(0)


## Keeps the cells whose label contains one of the comma-separated `only` words, laid out again in rows of 6.
static func _only(cells: Array, only: String) -> Array:
	if only == "":
		return cells
	var out: Array = []
	for c: Dictionary in cells:
		for word in only.split(","):
			if String(c.get("label", "")).contains(word):
				var k := out.size()
				c["row"] = k / 6
				c["col"] = k % 6
				out.append(c)
				break
	return out


static func _arg(args: PackedStringArray, flag: String, fallback: String) -> String:
	var i := args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else fallback


## The sheet's cells: {row, col, gender, look, equipped, clip, at (share of the clip), chair, label}.
func _cells(sheet: String) -> Array:
	var cells: Array = []
	match sheet:
		"wearables":
			var i := 0
			for id in art.ids(ArtPack.WEARABLE):
				var item := _wearable(id)
				if item.is_empty() or String(item.get("id")) != id:
					continue  # the game_item_id alias of the same wearable
				var genders: Array = [item.gender] if item.gender in ["male", "female"] else ["male", "female"]
				for g in genders:
					cells.append({"row": i / 10, "col": i % 10, "gender": g, "equipped": {String(item.equip_slot): id},
						"label": "%s %s" % [id, item.name]})
					i += 1
		"hats_male", "hats_female":
			var g := sheet.trim_prefix("hats_")
			var hats: Array = [""]
			for id in art.ids(ArtPack.WEARABLE):
				var item := _wearable(id)
				if not item.is_empty() and String(item.get("id")) == id and item.equip_slot == "hat":
					hats.append(id)
			for hair in CharacterAppearance.choices(CharacterAppearance.HAIR_STYLE):
				for col in hats.size():
					var look := CharacterAppearance.default_for(g)
					look[CharacterAppearance.HAIR_STYLE] = hair
					cells.append({"row": int(hair), "col": col, "gender": g, "look": look,
						"equipped": {"hat": hats[col]} if hats[col] != "" else {},
						"label": "hair %d %s" % [hair, hats[col] if hats[col] != "" else "no hat"]})
		"weapons":
			var row := 0
			for g in ["male", "female"]:
				for w in STARTER_WEAPONS:
					var col := 0
					for pose: Array in [["idle", 0.0, false], ["attack", 0.3, false], ["attack", 0.55, false], ["sit", 1.0, true]]:
						cells.append({"row": row, "col": col, "gender": g, "equipped": {"weapon": w}, "clip": pose[0],
							"at": pose[1], "chair": pose[2], "label": "%s %s %s" % [w, pose[0], g]})
						col += 1
					row += 1
	cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [a.row, a.col] < [b.row, b.col])
	return cells


## The pack's wearables_manifest entry for a wearable id ({} when unknown).
func _wearable(id: String) -> Dictionary:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(art.root.path_join("characters/wearables_manifest.json")))
	if manifest is Dictionary:
		for a in manifest.get("assets", []):
			if String(a.get("id")) == id or String(a.get("game_item_id")) == id:
				return a
	return {}


func _place(stage: Node3D, c: Dictionary) -> void:
	var cell := Node3D.new()
	cell.position = Vector3((int(c.col) + 0.5) * CELL_W, -int(c.row) * CELL_H, 0.0)
	stage.add_child(cell)
	var preset := PlayerVisual.preset_for(String(c.gender))
	var model := art.instance(ArtPack.PRESET, preset)
	var look: Dictionary = c.get("look", CharacterAppearance.default_for(String(c.gender)))
	CharacterLook.apply(model, look, preset, art)
	var out := CharacterWardrobe.dress(model, c.get("equipped", {}), art)
	if not out["missing"].is_empty():
		print("SHEET missing models: %s" % [out["missing"]])
	cell.add_child(model)
	model.rotation_degrees.y = 25.0
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var clip := String(c.get("clip", "idle"))
	if ap != null and ap.has_animation(clip):
		ap.play(clip)
		ap.seek(ap.get_animation(clip).length * float(c.get("at", 0.0)), true)
		ap.pause()
	if bool(c.get("chair", false)):
		var chair := art.instance(ArtPack.ITEM, CHAIR)
		if chair != null:
			chair.scale = Vector3.ONE * ArtPack.character_scale()
			chair.rotation_degrees.y = 25.0
			cell.add_child(chair)
		model.position.y = PlayerVisual.SEAT_LIFT_M
	var label := Label3D.new()
	label.text = String(c.get("label", ""))
	label.font_size = 28
	label.pixel_size = 0.0035
	label.modulate = Color(0.1, 0.1, 0.15)
	label.outline_size = 0
	label.position = Vector3(0.0, -0.08, 0.6)
	cell.add_child(label)


func _light(stage: Node3D) -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = BACKGROUND
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.WHITE
	e.ambient_light_energy = 0.55
	env.environment = e
	stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	sun.light_energy = 1.1
	stage.add_child(sun)
