class_name WoodenBox
extends Node3D
## One Wooden Box in the world (MeowDB breakable 0000001, contract C8): a procedural proxy crate in the MisoStory
## style (warm planks, a dark frame and brace, an ink outline), placed by BreakableSystem at its BreakablePlacement.
## Presentation only: the box's state (hits, broken, respawn time) lives in MapInstanceState.breakables and the rules
## in BreakableSystem / BreakableRules; the system calls show_hit / show_break / show_respawn / sync.
##
## The box is not solid (classic reactors never block movement; breakables.json box). It joins the group
## &"miso_breakables" and answers placement_key(), is_broken() and hits_left() for the playtest kit and the console.
## receive_hit(res, attacker) (the Monster signature) hands a hit to its system, so any attack source that already
## calls receive_hit on its targets counts one hit on a box it reached.

signal hit_shown(hits_left: int)
signal broke()
signal came_back()

const GROUP := &"miso_breakables"
## Presentation constants: durations (s), colours and shapes. Not gameplay values.
const FLASH_S := 0.09
const WOBBLE_S := 0.28
const WOBBLE_DEG := 9.0
const BREAK_S := 0.75
const RESPAWN_S := 0.35
const GRAVITY := 9.8
const CHIPS_PER_HIT := 3
const PLANKS_ON_BREAK := 8
const PLANK_COLOR := Color(0.725, 0.51, 0.294)
const FRAME_COLOR := Color(0.424, 0.267, 0.141)
const OUTLINE_COLOR := Color(0.16, 0.09, 0.04)
const DUST_COLOR := Color(0.93, 0.85, 0.7, 0.6)
## Ink outline thickness (m) of the inverted hull, and how far the lid lifts when the box is nearly broken.
const OUTLINE_M := 0.025
const LID_LIFT_DEG := 7.0

var placement: BreakablePlacement = null
## BreakableSystem (duck-typed: land_hit(box, source) -> Dictionary); null = hits are not counted.
var system: Node = null
## Body size (m): width, height, depth (BreakableRules.size_m).
var size_m: Vector3 = Vector3(0.75, 0.75, 0.75)
var hits_to_break: int = 0

var model: Node3D = null
var lid: Node3D = null

var _hits_left: int = 0
var _broken: bool = false
var _meshes: Array[MeshInstance3D] = []
var _flash_mat: StandardMaterial3D = null
var _flash_t: float = 0.0
var _wobble_t: float = 0.0
var _respawn_t: float = -1.0
## Flying chips and planks: {"node", "v": Vector3, "spin": Vector3, "t", "life"}.
var _pieces: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(GROUP)
	if model == null:
		_build()


## Places the box and shows its current state (hits taken, broken) without any effect.
func setup(p: BreakablePlacement, p_size_m: Vector3, p_hits_to_break: int, hits_taken: int, is_broken_now: bool,
		p_system: Node = null) -> void:
	placement = p
	size_m = p_size_m
	hits_to_break = p_hits_to_break
	system = p_system
	name = "WoodenBox_%s_%d" % [p.map_id, p.index]
	transform = p.transform
	if model == null:
		_build()
	sync(hits_taken, is_broken_now)


# --- the playtest kit and console contract --------------------------------------------------------------------

## "<map_id>:<index>" (BreakableRules.placement_key).
func placement_key() -> String:
	return placement.key() if placement != null else ""


func map_id() -> String:
	return placement.map_id if placement != null else ""


## Index into the map's canonical reactors[] (MapInstanceState.breakables).
func index() -> int:
	return placement.index if placement != null else -1


func is_broken() -> bool:
	return _broken


## Landed hits still needed to break it (0 while broken).
func hits_left() -> int:
	return 0 if _broken else _hits_left


## Feet on the ground (world).
func feet() -> Vector3:
	return global_position


## The middle of the body (world), where FX and loot start.
func center() -> Vector3:
	return global_position + Vector3.UP * size_m.y * 0.5


## An attack reached this box: the system counts it (one landed hit). The arguments are the Monster.receive_hit
## signature and are not used (damage does not matter to a box). Returns true when the hit counted.
func receive_hit(_res: Variant = null, _attacker: Variant = null) -> bool:
	if system == null or not system.has_method("land_hit"):
		return false
	return bool((system.call("land_hit", self, "receive_hit") as Dictionary).get("counted", false))


# --- presentation (called by the system) ------------------------------------------------------------------------

## Shows a state at once (no effect): `hits_taken` of hits_to_break, standing or broken.
func sync(hits_taken: int, is_broken_now: bool) -> void:
	_broken = is_broken_now
	_hits_left = maxi(hits_to_break - hits_taken, 0)
	if model != null:
		model.visible = not _broken
		model.scale = Vector3.ONE
		model.rotation = Vector3.ZERO
	_set_lid()


## A landed hit that did not break it: a white flash, a wobble and a few chips.
func show_hit(left: int) -> void:
	_hits_left = left
	_flash_t = FLASH_S
	_wobble_t = WOBBLE_S
	_set_lid()
	for k in CHIPS_PER_HIT:
		_spawn_piece(Vector3(0.08, 0.04, 0.06), center() + Vector3.UP * size_m.y * 0.3, 1.6, 2.4, 0.45)
	hit_shown.emit(left)


## The breaking hit: the body vanishes into flying planks and a puff of dust.
func show_break() -> void:
	_broken = true
	_hits_left = 0
	_flash_t = 0.0
	_wobble_t = 0.0
	_apply_flash(false)
	if model != null:
		model.visible = false
	for k in PLANKS_ON_BREAK:
		var long := k % 2 == 0
		var dims := Vector3(size_m.x * (0.8 if long else 0.35), 0.06, 0.16)
		_spawn_piece(dims, center(), 2.2, 3.4, BREAK_S)
	_spawn_dust()
	broke.emit()


## The box is back (its respawn time came): it grows back in place.
func show_respawn() -> void:
	sync(0, false)
	if model != null:
		model.scale = Vector3.ONE * 0.01
	_respawn_t = 0.0
	came_back.emit()


## Live chips and planks (tests).
func piece_count() -> int:
	return _pieces.size()


func _process(delta: float) -> void:
	advance(delta)


## Advances every effect (called by _process; tests call it directly).
func advance(delta: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= delta
		_apply_flash(_flash_t > 0.0)
	if model != null and _wobble_t > 0.0:
		_wobble_t = maxf(_wobble_t - delta, 0.0)
		var k := _wobble_t / WOBBLE_S
		model.rotation = Vector3(deg_to_rad(WOBBLE_DEG) * k * sin((1.0 - k) * TAU * 2.0), 0.0,
			deg_to_rad(WOBBLE_DEG * 0.6) * k * sin((1.0 - k) * TAU * 1.5))
	if model != null and _respawn_t >= 0.0:
		_respawn_t += delta
		var g := clampf(_respawn_t / RESPAWN_S, 0.0, 1.0)
		model.scale = Vector3.ONE * maxf(ease(g, 0.4), 0.01)
		if g >= 1.0:
			_respawn_t = -1.0
	var keep: Array[Dictionary] = []
	for p in _pieces:
		var n: Node3D = p.node
		if not is_instance_valid(n):
			continue
		p.t = float(p.t) + delta
		if float(p.t) >= float(p.life):
			n.queue_free()
			continue
		var v: Vector3 = p.v
		if bool(p.get("gravity", true)):
			v.y -= GRAVITY * delta
		p.v = v
		n.global_position += v * delta
		n.rotation += (p.spin as Vector3) * delta
		var fade := 1.0 - float(p.t) / float(p.life)
		n.scale = Vector3.ONE * maxf(fade, 0.05) if bool(p.get("shrink", true)) else Vector3.ONE * (1.0 + float(p.t) * 3.0)
		keep.append(p)
	_pieces = keep


# --- the model ------------------------------------------------------------------------------------------------

func _build() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var w := size_m.x
	var h := size_m.y
	var d := size_m.z
	var plank := _material(PLANK_COLOR)
	var frame := _material(FRAME_COLOR)
	# The body, inked by an inverted hull (front faces culled, unshaded), as the island's assets are.
	_box(model, Vector3(w, h, d), Vector3(0, h * 0.5, 0), plank)
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = OUTLINE_COLOR
	ink.cull_mode = BaseMaterial3D.CULL_FRONT
	var hull := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(w, h, d) + Vector3.ONE * OUTLINE_M * 2.0
	hull.mesh = hm
	hull.material_override = ink
	hull.position = Vector3(0, h * 0.5, 0)
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(hull)
	# Corner posts and a bottom rim in dark wood.
	var post := minf(w, d) * 0.12
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(model, Vector3(post, h * 1.01, post), Vector3(sx * (w - post) * 0.5, h * 0.5, sz * (d - post) * 0.5), frame)
	_box(model, Vector3(w * 1.02, h * 0.1, d * 1.02), Vector3(0, h * 0.05, 0), frame)
	# A diagonal brace on each side face.
	var diag := sqrt(w * w + h * h) * 0.86
	for side in 4:
		var yaw := side * PI * 0.5
		var face_d := (d if side % 2 == 0 else w) * 0.5 + 0.012
		var brace := _box(model, Vector3(diag, post * 0.8, 0.03), Vector3.ZERO, frame)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan2(h, w) * (1.0 if side < 2 else -1.0))
		brace.transform = Transform3D(basis, Basis(Vector3.UP, yaw) * Vector3(0, h * 0.5, face_d))
	# The lid: a dark rim that lifts a little as the box takes hits.
	lid = Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(-w * 0.5, h, 0)
	model.add_child(lid)
	_box(lid, Vector3(w * 1.04, h * 0.1, d * 1.04), Vector3(w * 0.5, 0, 0), frame)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 1, 1, 0.7)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


static func _material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _set_lid() -> void:
	if lid == null:
		return
	var taken := 0.0 if hits_to_break <= 0 else float(hits_to_break - _hits_left) / float(hits_to_break)
	lid.rotation = Vector3(0, 0, deg_to_rad(LID_LIFT_DEG) * clampf(taken, 0.0, 1.0))


func _apply_flash(on: bool) -> void:
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.material_overlay = _flash_mat if on else null


## A wood piece flying out of the box: `dims` (m), from `at`, outward speed in [v_lo, v_hi], for `life` s.
func _spawn_piece(dims: Vector3, at: Vector3, v_lo: float, v_hi: float, life: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = dims
	mi.mesh = bm
	mi.material_override = _material(PLANK_COLOR if randf() < 0.6 else FRAME_COLOR)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var v := dir * randf_range(v_lo, v_hi) * 0.5 + Vector3.UP * randf_range(v_lo, v_hi)
	_pieces.append({"node": mi, "v": v, "spin": Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)),
		"t": 0.0, "life": life})


func _spawn_dust() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size_m.x * 0.45
	sm.height = size_m.y * 0.4
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = DUST_COLOR
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = feet() + Vector3.UP * 0.1
	_pieces.append({"node": mi, "v": Vector3.ZERO, "spin": Vector3.ZERO, "t": 0.0, "life": BREAK_S * 0.6,
		"shrink": false, "gravity": false})
