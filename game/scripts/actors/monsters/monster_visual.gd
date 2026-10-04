class_name MonsterVisual
extends Node3D
## Presentation of one monster (child "Visual" of a Monster): the Iteration One proxy model (or a labelled
## placeholder), facing, a walk bob timed by the canonical move clip, a hit flinch over the canonical hit clip, an HP
## bar over the head once damaged, the spawn fade-in and the death fade over the canonical die time. Reads its
## Monster every frame and never changes gameplay state.

signal faded_out

## Presentation constants (not gameplay values).
const TURN_RATE_DEG := 720.0
const BOB_HEIGHT_FRACTION := 0.06
const SQUASH := 0.08
const FLINCH_TILT_DEG := 18.0
const FLASH_S := 0.09
const HP_BAR_WIDTH_FRACTION := 1.0
const HP_BAR_MIN_WIDTH_M := 0.8
const HP_BAR_HEIGHT_M := 0.13
const HP_BAR_GAP_M := 0.25
const HP_FILL := Color(0.95, 0.16, 0.12)
const HP_BACK := Color(0.08, 0.06, 0.06, 0.85)
const DEATH_SINK_FRACTION := 0.25

var monster: Node3D = null
var def: MonsterDef = null
var model: Node3D = null
var is_placeholder: bool = false
## Height of the model after fitting (m).
var height_m: float = 0.0
var hp_bar: Node3D = null
var _hp_fill: MeshInstance3D = null
var _hp_ratio: float = 1.0
var _yaw: float = 0.0
var _bob_phase: float = 0.0
var _flinch_t: float = 0.0
var _flash_t: float = 0.0
var _flash_mat: StandardMaterial3D = null
var _fade_t: float = -1.0
var _fade_s: float = 0.0
var _spawn_t: float = -1.0
var _spawn_s: float = 0.0
var _fit_scale: float = 1.0
var _geoms: Array[GeometryInstance3D] = []


## Builds the model for `d` from `library` (null or a missing asset = the labelled placeholder).
func build(d: MonsterDef, library: ProxyLibrary) -> void:
	def = d
	if model != null:
		model.queue_free()
	var inst: Node3D = null
	if d.has_model() and library != null:
		inst = library.instance(d.model)
	if inst != null:
		var h := library.height(d.model)
		_fit_scale = d.sprite_size_m.y / h if h > 0.0 and d.model_fit == "sprite_height" else 1.0
		height_m = h * _fit_scale if h > 0.0 else d.sprite_size_m.y
	else:
		inst = _placeholder(d)
		is_placeholder = true
		_fit_scale = 1.0
		height_m = d.sprite_size_m.y
	# The asset keeps its own root transform (an exported proxy may carry one); every procedural motion (fit,
	# squash, bob, flinch, sink) goes on this pivot above it.
	model = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * _fit_scale
	add_child(model)
	model.add_child(inst)
	_collect_geoms(model)
	_build_hp_bar()
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(1, 1, 1, 0.75)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD


## Faces `dir` at once (spawn).
func snap_facing(dir: Vector3) -> void:
	if dir.length_squared() > 1e-6:
		_yaw = atan2(dir.x, dir.z)
		rotation.y = _yaw


## Starts the spawn fade-in (scale from nothing over `seconds`).
func start_spawn(seconds: float) -> void:
	_spawn_s = seconds
	_spawn_t = 0.0 if seconds > 0.0 else -1.0
	if _spawn_t >= 0.0 and model != null:
		model.scale = Vector3.ONE * _fit_scale * 0.01


## A landed hit: flinch for the canonical hit clip, a white flash, and the HP bar.
func on_hit(hp_ratio: float) -> void:
	_flinch_t = def.hit_s if def != null and def.hit_s > 0.0 else 0.3
	_flash_t = FLASH_S
	set_hp_ratio(hp_ratio)


func set_hp_ratio(r: float) -> void:
	_hp_ratio = clampf(r, 0.0, 1.0)
	if hp_bar != null:
		hp_bar.visible = _hp_ratio < 1.0 and _fade_t < 0.0
		# Left-anchored in mesh space: a billboard turns each mesh about its own origin, so the fill is resized and
		# offset in the quad itself (a node offset would be a world-space shift that depends on the monster's yaw).
		var w := _bar_width()
		var q := _hp_fill.mesh as QuadMesh
		q.size = Vector2(maxf(w * _hp_ratio, 0.001), HP_BAR_HEIGHT_M)
		q.center_offset = Vector3(-w * 0.5 + q.size.x * 0.5, 0.0, 0.0)


## Starts the death fade over `seconds` (canonical die time); emits faded_out at the end.
func start_death_fade(seconds: float) -> void:
	_fade_t = 0.0
	_fade_s = maxf(seconds, 0.01)
	if hp_bar != null:
		hp_bar.visible = false



func is_fading() -> bool:
	return _fade_t >= 0.0


func _process(delta: float) -> void:
	advance(delta)


## Advances the presentation by `delta` (called by _process; tests call it directly).
func advance(delta: float) -> void:
	if monster == null or model == null:
		return
	var facing: Vector3 = monster.get("facing") if "facing" in monster else Vector3.BACK
	var want := atan2(facing.x, facing.z)
	var diff := wrapf(want - _yaw, -PI, PI)
	var step := deg_to_rad(TURN_RATE_DEG) * delta
	_yaw = want if absf(diff) <= step else _yaw + signf(diff) * step
	rotation.y = _yaw
	# Walk bob: one cycle per canonical move clip (snails squash, the rest bob).
	var moving := bool(monster.call("is_walking")) if monster.has_method("is_walking") else false
	if moving and def != null:
		var period := def.move_s if def.move_s > 0.0 else 0.6
		_bob_phase = fmod(_bob_phase + delta / period * TAU, TAU)
	else:
		_bob_phase = move_toward(_bob_phase, 0.0 if _bob_phase < PI else TAU, delta * 6.0)
	var wave := absf(sin(_bob_phase))
	var squash := 1.0
	var bob := 0.0
	if def != null and def.walk_style == MonsterDef.WALK_CRAWL:
		squash = 1.0 - SQUASH * wave
	else:
		bob = wave * height_m * BOB_HEIGHT_FRACTION
	# Hit flinch: tilt back, easing out over the canonical hit clip.
	var tilt := 0.0
	if _flinch_t > 0.0:
		_flinch_t -= delta
		var span := def.hit_s if def != null and def.hit_s > 0.0 else 0.3
		tilt = deg_to_rad(FLINCH_TILT_DEG) * clampf(_flinch_t / span, 0.0, 1.0)
	model.rotation = Vector3(-tilt, 0.0, 0.0)
	var s := _fit_scale
	if _spawn_t >= 0.0:
		_spawn_t += delta
		var k := clampf(_spawn_t / maxf(_spawn_s, 0.001), 0.0, 1.0)
		s *= maxf(k, 0.01)
		if k >= 1.0:
			_spawn_t = -1.0
	model.scale = Vector3(s / maxf(squash, 0.01) * 1.0, s * squash, s)
	model.position = Vector3.UP * bob
	# White flash on hit.
	if _flash_t > 0.0:
		_flash_t -= delta
		_set_overlay(_flash_mat if _flash_t > 0.0 else null)
	# Death fade over the canonical die time, sinking a little.
	if _fade_t >= 0.0:
		_fade_t += delta
		var f := clampf(_fade_t / _fade_s, 0.0, 1.0)
		for g in _geoms:
			if is_instance_valid(g):
				g.transparency = f
		model.position.y = bob - f * height_m * DEATH_SINK_FRACTION
		if f >= 1.0:
			_fade_t = INF
			faded_out.emit()


func _bar_width() -> float:
	var w := def.touch_size_m.x if def != null else 0.8
	return maxf(w * HP_BAR_WIDTH_FRACTION, HP_BAR_MIN_WIDTH_M)


func _build_hp_bar() -> void:
	hp_bar = Node3D.new()
	hp_bar.name = "HpBar"
	add_child(hp_bar)
	hp_bar.position = Vector3.UP * (height_m + HP_BAR_GAP_M)
	var w := _bar_width()
	var back := MeshInstance3D.new()
	back.mesh = _quad(Vector2(w + 0.07, HP_BAR_HEIGHT_M + 0.07))
	back.material_override = _bar_material(HP_BACK, 20)
	hp_bar.add_child(back)
	_hp_fill = MeshInstance3D.new()
	_hp_fill.mesh = _quad(Vector2(w, HP_BAR_HEIGHT_M))
	_hp_fill.material_override = _bar_material(HP_FILL, 21)
	hp_bar.add_child(_hp_fill)
	hp_bar.visible = false


static func _quad(size: Vector2) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	return q


static func _bar_material(c: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.no_depth_test = true
	m.render_priority = priority
	return m


## The Tutorial Jr. Sentinel (or any monster without a proxy): a stone body at the canonical sprite size, with a
## label that says it is a placeholder.
func _placeholder(d: MonsterDef) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = d.placeholder_color
	mat.roughness = 0.9
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(d.sprite_size_m.x * 0.8, d.sprite_size_m.y * 0.75, d.sprite_size_m.x * 0.6)
	body.mesh = box
	body.material_override = mat
	body.position = Vector3.UP * (box.size.y * 0.5)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = d.sprite_size_m.x * 0.32
	sphere.height = sphere.radius * 2.0
	head.mesh = sphere
	head.material_override = mat
	head.position = Vector3.UP * (box.size.y + sphere.radius * 0.8)
	root.add_child(head)
	var eye := MeshInstance3D.new()
	var em := SphereMesh.new()
	em.radius = sphere.radius * 0.3
	em.height = em.radius * 2.0
	eye.mesh = em
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.3, 0.85, 1.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.3, 0.85, 1.0)
	eye.material_override = eye_mat
	eye.position = head.position + Vector3(0, 0, sphere.radius * 0.85)
	root.add_child(eye)
	var tag := Label3D.new()
	tag.name = "PlaceholderTag"
	tag.text = "%s (placeholder)" % d.name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 48
	tag.outline_size = 14
	tag.pixel_size = 0.008
	tag.modulate = Color(1, 1, 1, 0.95)
	tag.position = Vector3.UP * (d.sprite_size_m.y + 0.45)
	root.add_child(tag)
	root.set_meta("placeholder", true)
	return root


func _collect_geoms(n: Node) -> void:
	if n is GeometryInstance3D:
		_geoms.append(n as GeometryInstance3D)
	for c in n.get_children():
		_collect_geoms(c)


func _set_overlay(mat: Material) -> void:
	for g in _geoms:
		if is_instance_valid(g) and not (g is Label3D):
			g.material_overlay = mat
