class_name MonsterVisual
extends Node3D
## Presentation of one monster (child "Visual" of a Monster): its proxy model from _library.glb (or a named stone
## fallback body when the library lacks it), facing, a walk bob timed by the canonical move clip, a hit flinch over the canonical hit clip, an HP
## bar over the head once damaged, the spawn fade-in and the death fade over the canonical die time, and the
## see-through silhouette. Reads its Monster every frame and never changes gameplay state.
##
## See-through silhouette (docs/runtime/MONSTERS_AND_COMBAT_RUNTIME.md "See-through silhouette"): terrain never
## fades, so a monster near the player shows a flat tinted silhouette wherever something hides it.
##   - every surface of the model (the unshaded ink shell too) writes STENCIL_REF where it is visible, on copies of
##     the library's materials (the shared originals stay untouched);
##   - under each model mesh a "SeeThrough" child draws that mesh's triangles (every surface merged into one,
##     fill_mesh) with the shared fill shader: unshaded, no depth test, both faces, stencil read and write in one pass
##     with compare_greater STENCIL_REF. It draws where the
##     stored value is below STENCIL_REF, i.e. where no monster and not the player (PlayerVisual.STENCIL_REF 37) is
##     visible, and writes STENCIL_REF, so each pixel blends once and a silhouette never covers a visible monster or
##     the player;
##   - the fill skips fragments whose cover (the opaque surface in front, from the depth texture) is nearer than
##     def.see_through_min_cover_m along the view: no rim where a body dips into the ground;
##   - MonsterSystem.update_see_through() turns it on within the species' see_through_radius_m of the player
##     (see_through_wanted); it fades over see_through_fade_s, and a dying monster loses it at once.

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
## Stencil value of a monster's visible pixels. The fill passes where the stored value is below it
## (compare_greater), so it must stay below PlayerVisual.STENCIL_REF (37) to keep the player on top of silhouettes;
## any future stencil writer that a silhouette must not cover needs a value of at least this.
const STENCIL_REF := 36
## Transparent-pass order of the fill: before the default-priority labels (0), attack FX (8), damage numbers (10+) and
## the HP bar (20, 21), which stay on top of a silhouette; the player's X-ray fill and outline (120+) come later too.
const SEE_THROUGH_PRIORITY := -1
const SEE_THROUGH_NAME := "SeeThrough"
## The fill shader shared by every monster (a ShaderMaterial: BaseMaterial3D keeps stencil read and write exclusive).
## The tint (sRGB, alpha), the fade amount and the minimum cover are per-instance uniforms. A fragment draws only
## where the opaque surface in front of it is at least `see_through_min_cover` m nearer along the view, so the ground
## a body dips into (a slope under a snail) and a grass tuft at its feet never draw a rim; a cliff or a boulder does.
const SEE_THROUGH_SHADER := """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled;
stencil_mode read, write, compare_greater, %d;

uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
instance uniform vec4 see_through_tint : source_color = vec4(0.0);
instance uniform float see_through_amount = 0.0;
instance uniform float see_through_min_cover = 0.0;

void fragment() {
	float depth = texture(scene_depth, SCREEN_UV).r;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	// View space looks down -z: the cover is how much nearer the camera the opaque surface is than this fragment.
	if (scene.z / scene.w - VERTEX.z < see_through_min_cover) {
		discard;
	}
	ALBEDO = see_through_tint.rgb;
	ALPHA = see_through_tint.a * see_through_amount;
}
"""

static var _see_through_material: ShaderMaterial = null
## Stencil-writing copies of the library's shared materials (source material -> copy), shared by every monster.
static var _stencil_copies: Dictionary = {}
## One-surface copies of multi-surface model meshes (source mesh -> fill mesh), shared by every monster.
static var _fill_meshes: Dictionary = {}

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
## See-through silhouette: the eased amount (0 hidden .. 1 full), the requested state and the fill meshes.
var see_through_amount: float = 0.0
var _see_through: bool = false
var _see_through_fills: Array[MeshInstance3D] = []
var _see_through_applied: float = -1.0


## Builds the model for `d` from `library` (null or a missing asset = the labelled placeholder).
func build(d: MonsterDef, library: ProxyLibrary) -> void:
	def = d
	if model != null:
		model.queue_free()
	_geoms.clear()
	_see_through_fills.clear()
	# Decided afresh: _apply_see_through edits a placeholder's own materials in place, so a stale flag would edit the
	# library's shared materials.
	is_placeholder = false
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
	# After _collect_geoms: the fill meshes take no hit flash and no death transparency.
	_apply_see_through(model, is_placeholder)
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
	# Off at once: with transparency > 0 the body leaves the opaque pass, so its stencil would no longer be written
	# before the fill and the silhouette would cover the fading body.
	_see_through = false
	see_through_amount = 0.0
	_show_see_through()


func is_fading() -> bool:
	return _fade_t >= 0.0


# =================================================================================================================
# See-through silhouette
# =================================================================================================================

## Whether a monster `distance` m from the player (feet to feet) shows its see-through silhouette: alive and within
## `radius`; one already `showing` it keeps it until `radius + hysteresis`. Pure (MonsterSystem.update_see_through).
static func see_through_wanted(alive: bool, distance: float, radius: float, hysteresis: float, showing: bool) -> bool:
	if not alive or radius <= 0.0:
		return false
	return distance <= radius + (maxf(hysteresis, 0.0) if showing else 0.0)


## Requests (true) or drops (false) the silhouette; it fades over def.see_through_fade_s. Ignored while dying.
func set_see_through(on: bool) -> void:
	_see_through = on and _fade_t < 0.0


## The requested state (the silhouette may still be fading).
func is_see_through() -> bool:
	return _see_through


## Advances the silhouette fade by `delta` seconds and applies it (called from advance(); tests call it directly).
func step_see_through(delta: float) -> void:
	var goal := 1.0 if _see_through else 0.0
	var fade := def.see_through_fade_s if def != null else 0.0
	see_through_amount = goal if fade <= 0.0 else move_toward(see_through_amount, goal, delta / fade)
	_show_see_through()


## The fill meshes (one "SeeThrough" child per model mesh).
func see_through_fills() -> Array[MeshInstance3D]:
	return _see_through_fills


## The fill material every monster shares: the see-through shader at SEE_THROUGH_PRIORITY.
static func see_through_material() -> ShaderMaterial:
	if _see_through_material == null:
		var sh := Shader.new()
		sh.code = SEE_THROUGH_SHADER % STENCIL_REF
		_see_through_material = ShaderMaterial.new()
		_see_through_material.resource_name = "MonsterSeeThrough"
		_see_through_material.shader = sh
		_see_through_material.render_priority = SEE_THROUGH_PRIORITY
	return _see_through_material


## `m` set to write STENCIL_REF wherever it draws (in place; returns it).
static func with_stencil(m: BaseMaterial3D) -> BaseMaterial3D:
	m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	m.stencil_reference = STENCIL_REF
	return m


## The stencil-writing version of `mat`: a copy of a shared (library) material, cached so every monster uses the same
## copy; `owned` materials (the placeholder's own) are changed in place. A surface without a material gets a default
## StandardMaterial3D (what Godot draws then). Materials that are not BaseMaterial3D are returned unchanged.
static func stencil_material(mat: Material, owned: bool) -> Material:
	if mat == null:
		return with_stencil(StandardMaterial3D.new())
	if not (mat is BaseMaterial3D):
		return mat
	if owned:
		return with_stencil(mat as BaseMaterial3D)
	if not _stencil_copies.has(mat):
		_stencil_copies[mat] = with_stencil(mat.duplicate() as BaseMaterial3D)
	return _stencil_copies[mat]


## The mesh the fill draws for `mesh`: the mesh itself when it has one surface, else one triangle surface holding
## every triangle surface of it (positions only; cached per source mesh), so a fill is one draw call per model mesh
## instead of one per material (a proxy mesh has 3-6 surfaces).
static func fill_mesh(mesh: Mesh) -> Mesh:
	if mesh == null or mesh.get_surface_count() <= 1:
		return mesh
	if _fill_meshes.has(mesh):
		return _fill_meshes[mesh]
	var verts := PackedVector3Array()
	var index := PackedInt32Array()
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var base := verts.size()
		verts.append_array(v)
		if ind.is_empty():
			for i in v.size():
				index.append(base + i)
		else:
			for i in ind:
				index.append(base + i)
	var out: Mesh = mesh
	if not index.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_INDEX] = index
		var merged := ArrayMesh.new()
		merged.resource_name = "%s_SeeThrough" % mesh.resource_name
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out = merged
	_fill_meshes[mesh] = out
	return out


## Gives every surface under `root` a stencil-writing material and every mesh a hidden fill copy.
func _apply_see_through(root: Node, owned: bool) -> void:
	var tint := def.see_through_color if def != null else Color(0, 0, 0, 0)
	var min_cover := def.see_through_min_cover_m if def != null else 0.0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or String(mi.name) == SEE_THROUGH_NAME:
			continue
		if mi.material_override != null:
			mi.material_override = stencil_material(mi.material_override, owned)
		else:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, stencil_material(mi.get_active_material(s), owned))
		# The whole mesh, ink shell included: the silhouette has the footprint of the visible monster.
		var fill := MeshInstance3D.new()
		fill.name = SEE_THROUGH_NAME
		fill.mesh = fill_mesh(mi.mesh)
		fill.material_override = see_through_material()
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fill.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# The fill exists to draw where terrain hides the monster: occlusion culling (off today) must never cull it.
		fill.ignore_occlusion_culling = true
		fill.layers = mi.layers
		fill.visible = false
		fill.set_instance_shader_parameter(&"see_through_tint", tint)
		fill.set_instance_shader_parameter(&"see_through_amount", 0.0)
		fill.set_instance_shader_parameter(&"see_through_min_cover", min_cover)
		mi.add_child(fill)
		_see_through_fills.append(fill)
	_see_through_applied = 0.0


func _show_see_through() -> void:
	if is_equal_approx(see_through_amount, _see_through_applied):
		return
	_see_through_applied = see_through_amount
	var on := see_through_amount > 0.001
	for f in _see_through_fills:
		if is_instance_valid(f):
			f.visible = on
			f.set_instance_shader_parameter(&"see_through_amount", see_through_amount)


func _process(delta: float) -> void:
	advance(delta)


## Advances the presentation by `delta` (called by _process; tests call it directly).
func advance(delta: float) -> void:
	if monster == null or model == null:
		return
	step_see_through(delta)
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


## Any monster whose proxy the library lacks (every Maple Island species has one since Iteration Three: the Tutorial
## Jr. Sentinel is Mob_TutorialJrSentinel): a stone body at the canonical sprite size with the monster's name over
## it. Its node keeps the "PlaceholderTag" name and the "placeholder" metadata for tools; nothing the player reads says
## "placeholder".
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
	tag.text = d.name
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
