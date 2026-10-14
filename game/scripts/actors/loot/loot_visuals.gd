class_name LootVisuals
extends RefCounted
## Looks for ground drops and item icons, from data/misostory/loot_visuals.json (an adaptation: MeowDB's item and meso
## art are Nexon sprites, which MisoStory never uses). With the art pack (Project art, ADR 0002) a drop shows the pack's
## model; without it, or for a model the pack lacks, a procedural shape.
##
##   var vis := LootVisuals.new(Data.db, ArtPack.shared())   # no pack argument: procedural only
##   vis.style_for_item("270")      # {"shape": "potion", "body": Color, "accent": Color, "name": "Red Potion"}
##   vis.style_for_mesos(7)         # {"shape": "meso", "body": Color, "coins": 1, "bag": false, "pack_extent_m", ...}
##   var mesh_root := vis.build_drop_model(record)    # Node3D: the pack model, or a bottle, a chest, a coin pile ...
##   LootVisuals.is_pack_model(mesh_root)             # true when it shows the pack's model
##   vis.motion("toss_duration_s")
##
## Pack models: the item's model by canonical id (monster drops such as the Snail Shell through the pack's monster
## manifest), the one meso model for every meso tier (tiers differ by size and tint). Each sits under a "Pack" child of
## the "Model" root, raised by the pack's ground offset (godot_validation.json), centred over the drop and scaled so its
## longest side is pack_models.item_extent_m (a meso tier's pack_extent_m). A skinned drop plays its Hover clip, which
## loops (ArtImport) and is its bob (hover_player()).
##
## Shapes: box (equipment), chair_box (setup), potion, food, scroll, bundle (arrows), gem (ores and gems), pouch (other
## Etc items), meso (coins or a bag). Type and subtype come from the canonical item record; colours from the table,
## tinted by the first name keyword that matches.

const TABLE := "loot_visuals"
const SHAPES: PackedStringArray = ["box", "chair_box", "potion", "food", "scroll", "bundle", "gem", "pouch", "meso"]
## The child of a drop model holding the pack's model (its ground offset, centring and scale).
const PACK_NODE := "Pack"
## The pack drops' looping clip.
const HOVER_CLIP := ArtImport.DROP_HOVER

var db: ContentDB = null
## The art pack drops are looked up in; null or absent: procedural drops only.
var art: ArtPack = null
var _table: Dictionary = {}
var _materials: Dictionary = {}


func _init(p_db: ContentDB = null, p_art: ArtPack = null) -> void:
	db = p_db
	art = p_art
	var t: Variant = db.miso_table(TABLE) if db != null else null
	_table = t if t is Dictionary else {}


## True when the adaptation table is present.
func has_table() -> bool:
	return not _table.is_empty()


## A motion/feel number from the "motion" section (0 when missing).
func motion(key: String) -> float:
	return num("motion", key)


## A number from any section of the table ("motion", "placement", "pickup", "sizes"); 0 when missing.
func num(section: String, key: String) -> float:
	var m: Variant = _table.get(section, {})
	return float((m as Dictionary).get(key, 0.0)) if m is Dictionary else 0.0


## A size from the "sizes" section in meters (0 when missing).
func size(key: String) -> float:
	return num("sizes", key)


## The shape name for a canonical item record (by "Type/Subtype", then "Type", then the default).
func shape_for_record(rec: Dictionary) -> String:
	var shapes: Dictionary = _dict(_table.get("shapes"))
	var t := _s(rec.get("type"))
	var st := _s(rec.get("subtype"))
	var by_sub := _dict(shapes.get("by_type_subtype"))
	if by_sub.has("%s/%s" % [t, st]):
		return String(by_sub["%s/%s" % [t, st]])
	var by_type := _dict(shapes.get("by_type"))
	if by_type.has(t):
		return String(by_type[t])
	return _s(shapes.get("default"), "pouch")


## {"shape", "body": Color, "accent": Color, "name"} for an item id ("pouch" in neutral colours for unknown ids).
func style_for_item(item_id: String) -> Dictionary:
	var rec: Dictionary = db.item(item_id) if db != null else {}
	var shape := shape_for_record(rec)
	var base := _dict(_dict(_table.get("colors")).get(shape))
	var body := _color(base.get("body"), Color(0.72, 0.58, 0.42))
	var accent := _color(base.get("accent"), Color(0.45, 0.33, 0.2))
	var item_name := _s(rec.get("name"))
	var tint: Variant = keyword_color(item_name)
	if tint is Color:
		body = tint
	return {"shape": shape, "body": body, "accent": accent, "name": item_name}


## The colour of the first keyword in name_keyword_colors found in `item_name`, or null.
func keyword_color(item_name: String) -> Variant:
	if item_name.is_empty():
		return null
	for e: Variant in _table.get("name_keyword_colors", []):
		var d := _dict(e)
		var kw := _s(d.get("keyword"))
		if not kw.is_empty() and item_name.contains(kw):
			return _color(d.get("color"), Color.WHITE)
	return null


## {"shape": "meso", "body": Color, "coins": int, "bag": bool} for a meso amount (first tier whose max_amount is
## at least the amount; -1 = no limit).
func style_for_mesos(amount: int) -> Dictionary:
	var tiers: Array = _table.get("meso_tiers", []) if _table.get("meso_tiers") is Array else []
	for t: Variant in tiers:
		var d := _dict(t)
		var cap := int(d.get("max_amount", -1))
		if cap < 0 or amount <= cap:
			var tint: Variant = d.get("pack_tint")
			return {"shape": "meso", "body": _color(d.get("coin"), Color(0.96, 0.77, 0.19)),
				"coins": int(d.get("coins", 1)), "bag": bool(d.get("bag", false)),
				"pack_extent_m": float(d.get("pack_extent_m", size("coin_m"))),
				"pack_tint": _color(tint, Color.WHITE) if tint is String else null}
	return {"shape": "meso", "body": Color(0.96, 0.77, 0.19), "coins": 1, "bag": false,
		"pack_extent_m": size("coin_m"), "pack_tint": null}


## The style of a ground record or rolled drop (items and meso bags alike).
func style_for_drop(drop: Dictionary) -> Dictionary:
	if ItemService.is_meso_drop(drop):
		return style_for_mesos(ItemService.quantity_of(drop.get("amount", drop.get("mesos", 0))))
	return style_for_item(ItemDef.id_of(drop.get("item_id", "")))


## A Node3D model for a drop, origin at its base: the pack's model when the pack has it, else a procedural shape about
## sizes.item_m tall (coins sizes.coin_m). Procedural meshes are primitives with shared materials, so hundreds of drops
## cost little.
func build_drop_model(drop: Dictionary) -> Node3D:
	var m := _pack_drop_model(drop)
	return m if m != null else build_model(style_for_drop(drop))


## True when a model from build_drop_model shows the pack's model.
static func is_pack_model(model: Node) -> bool:
	return model != null and model.get_node_or_null(PACK_NODE) != null


## A number from the "pack_models" section (0 when missing).
func pack_num(key: String) -> float:
	return num("pack_models", key)


## The pack's model for a drop, fitted onto the ground (see the header), or null when there is no pack or no model.
func _pack_drop_model(drop: Dictionary) -> Node3D:
	if art == null or not art.present():
		return null
	var kind := ArtPack.ITEM
	var id := ""
	var extent := pack_num("item_extent_m")
	var tint: Variant = null
	if ItemService.is_meso_drop(drop):
		kind = ArtPack.MESO
		var style := style_for_mesos(ItemService.quantity_of(drop.get("amount", drop.get("mesos", 0))))
		extent = float(style.pack_extent_m)
		tint = style.pack_tint
	else:
		id = ItemDef.id_of(drop.get("item_id", ""))
	var inst := art.instance(kind, id)
	if inst == null:
		return null
	var box := art.bounds(kind, id)
	var lift := art.ground_offset_y(kind, id)
	if not box.has_volume():
		box = ArtImport.visual_aabb(inst)
		lift = -box.position.y
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s := extent / longest if longest > 0.001 and extent > 0.0 else 1.0
	var root := Node3D.new()
	root.name = "Model"
	var fit := Node3D.new()
	fit.name = PACK_NODE
	fit.scale = Vector3.ONE * s
	var centre := box.get_center()
	fit.position = Vector3(-centre.x, lift, -centre.z) * s
	root.add_child(fit)
	fit.add_child(inst)
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if tint is Color and mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				if mat is BaseMaterial3D and mat.resource_name == _s(_dict(_table.get("pack_models")).get("tint_material")):
					mi.set_surface_override_material(i, _tinted(mat as BaseMaterial3D, tint))
	var player := hover_player(root)
	if player != null:
		# ArtImport makes Hover loop on import.
		player.autoplay = HOVER_CLIP
	return root


## The AnimationPlayer playing a pack drop's Hover clip (its bob on the ground), or null (a procedural shape or a
## static pack model): GroundDrop leaves out its procedural bob where Hover plays (#59 decision 5).
static func hover_player(model: Node) -> AnimationPlayer:
	if model == null:
		return null
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		if (ap as AnimationPlayer).has_animation(HOVER_CLIP):
			return ap
	return null


## A shared copy of a pack material with its albedo replaced by `color` (a meso tier's tint).
func _tinted(base: BaseMaterial3D, color: Color) -> BaseMaterial3D:
	var key := "tint|%d|%s" % [base.get_instance_id(), color.to_html()]
	if not _materials.has(key):
		var m := base.duplicate() as BaseMaterial3D
		m.albedo_color = color
		_materials[key] = m
	return _materials[key]


## A Node3D model for a style from style_for_item / style_for_mesos.
func build_model(style: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var s := maxf(size("item_m"), 0.05)
	var body: Color = style.get("body", Color.WHITE)
	var accent: Color = style.get("accent", Color.WHITE)
	match String(style.get("shape", "pouch")):
		"box", "chair_box":
			_add(root, _box(Vector3(s * 0.9, s * 0.62, s * 0.66)), body, Vector3(0, s * 0.31, 0))
			_add(root, _box(Vector3(s * 0.94, s * 0.14, s * 0.7)), body.darkened(0.25), Vector3(0, s * 0.68, 0))
			_add(root, _box(Vector3(s * 0.16, s * 0.82, s * 0.72)), accent, Vector3(0, s * 0.39, 0))
			_add(root, _box(Vector3(s * 0.14, s * 0.16, s * 0.08)), accent.lightened(0.2), Vector3(0, s * 0.42, s * 0.36))
		"potion":
			_add(root, _sphere(s * 0.32), body, Vector3(0, s * 0.34, 0), 0.25)
			_add(root, _cylinder(s * 0.12, s * 0.12, s * 0.3), body.lightened(0.15), Vector3(0, s * 0.72, 0), 0.25)
			_add(root, _cylinder(s * 0.1, s * 0.11, s * 0.14), accent.darkened(0.35), Vector3(0, s * 0.92, 0))
			_add(root, _sphere(s * 0.08), Color(1, 1, 1, 1), Vector3(-s * 0.12, s * 0.46, s * 0.2), 0.6)
		"food":
			_add(root, _sphere(s * 0.38), body, Vector3(0, s * 0.38, 0), 0.1)
			_add(root, _cylinder(s * 0.03, s * 0.03, s * 0.2), Color(0.42, 0.28, 0.15), Vector3(0, s * 0.82, 0))
			var leaf := _add(root, _box(Vector3(s * 0.22, s * 0.03, s * 0.1)), accent, Vector3(s * 0.11, s * 0.84, 0))
			leaf.rotation_degrees = Vector3(0, 0, 25)
		"scroll":
			var roll := _add(root, _cylinder(s * 0.16, s * 0.16, s * 0.9), body, Vector3(0, s * 0.18, 0))
			roll.rotation_degrees = Vector3(0, 0, 90)
			var band := _add(root, _cylinder(s * 0.17, s * 0.17, s * 0.14), accent, Vector3(0, s * 0.18, 0))
			band.rotation_degrees = Vector3(0, 0, 90)
		"bundle":
			for i in 3:
				var shaft := _add(root, _cylinder(s * 0.035, s * 0.035, s * 0.95), body, Vector3((i - 1) * s * 0.09, s * 0.48, 0))
				shaft.rotation_degrees = Vector3(0, 0, (i - 1) * 6.0)
				_add(root, _cylinder(0.0, s * 0.07, s * 0.14), Color(0.62, 0.64, 0.68), shaft.position + Vector3(0, s * 0.52, 0))
			_add(root, _cylinder(s * 0.16, s * 0.16, s * 0.08), accent, Vector3(0, s * 0.4, 0))
		"gem":
			var g := _add(root, _sphere(s * 0.3, 6, 3), body, Vector3(0, s * 0.3, 0), 0.35)
			g.scale = Vector3(1.0, 1.3, 1.0)
			_add(root, _sphere(s * 0.08), accent, Vector3(-s * 0.1, s * 0.42, s * 0.18), 0.5)
		"meso":
			_build_meso(root, style)
		_:
			# pouch: a round sack with a tied neck.
			_add(root, _sphere(s * 0.34), body, Vector3(0, s * 0.32, 0))
			_add(root, _cylinder(s * 0.1, s * 0.16, s * 0.14), body.darkened(0.1), Vector3(0, s * 0.68, 0))
			_add(root, _cylinder(s * 0.12, s * 0.12, s * 0.05), accent, Vector3(0, s * 0.62, 0))
			_add(root, _cylinder(s * 0.15, s * 0.09, s * 0.1), body.lightened(0.1), Vector3(0, s * 0.8, 0))
	return root


func _build_meso(root: Node3D, style: Dictionary) -> void:
	var c := maxf(size("coin_m"), 0.05)
	var gold: Color = style.get("body", Color(0.96, 0.77, 0.19))
	if bool(style.get("bag", false)):
		var b := maxf(size("bag_m"), 0.05)
		_add(root, _sphere(b * 0.42), Color(0.55, 0.38, 0.22), Vector3(0, b * 0.4, 0))
		_add(root, _cylinder(b * 0.12, b * 0.2, b * 0.18), Color(0.5, 0.34, 0.2), Vector3(0, b * 0.86, 0))
		var badge := _add(root, _cylinder(b * 0.16, b * 0.16, b * 0.04), gold, Vector3(0, b * 0.42, b * 0.4), 0.3)
		badge.rotation_degrees = Vector3(90, 0, 0)
		return
	var coins := maxi(1, int(style.get("coins", 1)))
	for i in coins:
		# Coins lie flat; piles are stacked and offset.
		var coin := _add(root, _cylinder(c * 0.5, c * 0.5, c * 0.14), gold, Vector3.ZERO, 0.35)
		if coins == 1:
			# Flat: from the 40-degree camera a flat coin is a clear ellipse whatever the spin (on its edge it read as a
			# stick at most angles).
			coin.position = Vector3(0, c * 0.08, 0)
		else:
			coin.position = Vector3((i - 1) * c * 0.28, c * 0.08 + i * c * 0.15, (i % 2) * c * 0.12)
		var rim := _add(root, _cylinder(c * 0.36, c * 0.36, c * 0.16), gold.lightened(0.25), coin.position, 0.4)
		rim.rotation_degrees = coin.rotation_degrees


# --- mesh helpers ----------------------------------------------------------------------------------------------

func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, emission: float = 0.3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material(color, emission)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## A shared material per colour (emissive enough that drops still read in a cliff's shadow).
func material(color: Color, emission: float = 0.3) -> StandardMaterial3D:
	var key := "%s|%.2f" % [color.to_html(), emission]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.45
	m.emission_enabled = emission > 0.0
	m.emission = color
	m.emission_energy_multiplier = emission
	_materials[key] = m
	return m


static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


static func _sphere(r: float, segments: int = 16, rings: int = 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segments
	s.rings = rings
	return s


static func _cylinder(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 14
	return c


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _s(v: Variant, fallback: String = "") -> String:
	return String(v) if v is String and not String(v).is_empty() else fallback


static func _color(v: Variant, fallback: Color) -> Color:
	if v is String and Color.html_is_valid(String(v)):
		return Color.html(String(v))
	return fallback
