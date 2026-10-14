class_name PlayerVisual
extends Node3D
## Presentation of the player (child "Visual" of player.tscn): the model, a blob shadow, the X-ray fill and the
## see-through outline, facing, step smoothing, the rig's clips or the placeholder's procedural motions, invulnerability
## blink, and the chair. Reads the parent PlayerController (and its PlayerCombat / PlayerSkills signals) every frame
## and never changes gameplay state.
##
## Model, first found (feet at y = 0, front +Z, named "Model"):
##   1. the art pack's rigged Beginner preset for the character's gender (#63; PRESETS, looked up by ID through
##      ArtPack, already at the character scale on its rig node), wearing the character's saved hair, face and skin
##      (#67, CharacterLook; set_look() rebuilds when they change) and its equipment (#68, CharacterWardrobe: wearables
##      on the skeleton, the weapon in socket_weapon_r; set_equipment() rebuilds at once on every equip, unequip and
##      swap, which the live player hears as Events.equipment_changed). PlayerAnimator plays its clips from the gameplay
##      state (idle, walk, run, jump, climb, attack, hit, sit, death). Animation never moves the body: the clips'
##      root translation is held by the import (#62), and the procedural motions a clip covers (covers(): the walk bob
##      and lean, the death fall, the sit drop and lean, PlayerCombat's attack lunge) do not run. The only vertical
##      offsets the visual adds on the rig are ground_lift(): onto the chair's cushion while seated (SEAT_LIFT_M, the
##      sit clip keeps its root drop) and onto the ground while dead (DEATH_REST_LIFT_M);
##   2. Iteration One's Player_Proxy from the exported library (res://assets/world/_library.glb, "Player_Proxy_001");
##   3. a procedural chibi placeholder.
## Without the pack (a fresh clone, unit tests) 2 and 3 keep their procedural motions exactly as before.
##
## Sit pose (PlayerController.is_seated(), contract C5): on the rig, the sit clip onto the pack's model of the chair
## item. Without it the body settles SIT_DROP_M lower and leans back SIT_LEAN_DEG over SIT_EASE_S onto a procedural
## chair. Either way the chair is the "ChairProp" child of the player, turned with the facing. Presentation constants,
## not gameplay values.
##
## Readability through geometry (camera.json, docs/runtime/PLAYER_AND_CAMERA.md "X-ray fill and see-through outline"):
##   - every surface (the unshaded ink shell too) writes STENCIL_REF where it is visible;
##   - an X-ray fill (next pass: unshaded, no depth test, stencil != STENCIL_REF) paints the hidden parts of the body
##     in `xray_color`; an invisible mark pass after it writes STENCIL_REF over the whole silhouette (Godot keeps
##     stencil read and write exclusive in one pass);
##   - a see-through outline (a copy of the model with smoothed normals, grown `silhouette_width_px` on screen, no
##     depth test, stencil != STENCIL_REF, drawn last; on the rig each copy keeps its bones and weights and is posed by
##     the same skin and skeleton, so it follows the clips) rings the silhouette in `silhouette_color` on top of
##     everything. It shows while set_see_through(true) (CameraRig: something hides the player) and fades out
##     otherwise, so an unoccluded player has no extra line.
##
## Post-hit blink: while the player is invulnerable the body is hidden on every other BLINK_MS slice. In the open
## nothing is drawn then (the classic blink). While something hides the player (see-through on: a canopy, a building,
## terrain), the blink-off slices still draw the silhouette as a translucent ghost in the X-ray colour (#18: under the
## autumn canopies of 000001020 the player vanished at the moment a monster touched them). The outline meshes live
## under their own root (`OUTLINE_ROOT`, which follows the model's transform), so hiding the body leaves them.

const LIBRARY := "res://assets/world/_library.glb"
const PROXY_NODE := "Player_Proxy"
## Render layer of the player's meshes, excluded from the blob shadow decal so it never lands on the player.
const PLAYER_LAYER := 1 << 19
## Stencil value of the player's visible pixels (any value no other system uses).
const STENCIL_REF := 37
## Transparent-pass order: after faded occluders, FX and labels (0..100); the fill before the outline.
const FILL_PRIORITY := 120
const MARK_PRIORITY := 121
const OUTLINE_PRIORITY := 127
const OUTLINE_NAME := "SeeThroughOutline"
const OUTLINE_ROOT := "SeeThroughOutlines"
## Post-hit blink: the body shows and hides in slices of this many milliseconds (presentation).
const BLINK_MS := 70
## Sit pose: how far the body settles (m), how far it leans back (degrees) and how long the change takes (s).
const SIT_DROP_M := 0.2
const SIT_LEAN_DEG := 8.0
const SIT_EASE_S := 0.12
const CHAIR_NAME := "ChairProp"
const CHAIR_COLOR := Color("#5f9e4a")
## The chair's dark wooden frame around the green cushions (presentation: contrast against grass).
const CHAIR_FRAME_COLOR := Color("#4a2c17")
## The chair's ink outline (inverted hulls, as on the island's assets) and its thickness (m).
const CHAIR_INK_COLOR := Color(0.16, 0.09, 0.04)
const CHAIR_INK_M := 0.022

## Rigged Beginner (with the art pack): the walk and run clips play at ground speed above a Speed 100 walk times this.
const RUN_FACTOR := 1.15
## The procedural motions and the clip that replaces each one on the rig (covers()). Never both.
const COVERED_BY := {&"bob": PlayerAnimator.WALK, &"lean": PlayerAnimator.WALK, &"death_fall": PlayerAnimator.DEATH,
	&"sit_drop": PlayerAnimator.SIT, &"sit_lean": PlayerAnimator.SIT, &"lunge": PlayerAnimator.ATTACK}
## The rig's sit clip keeps its root drop (#59 decision 5): 0.28 m in rig units, about 0.21 m at the character scale.
const SIT_ROOT_DROP := 0.28
## How far the seated Beginner is lifted onto the chair (m). Measured on the pack's v1 rigs at the character scale:
## at the end of the sit clip the pelvis rests 0.127 m above the feet, and The Green Relaxer's seat cushion tops out
## at 0.46 m x 0.7566 = 0.348 m, so the dropped pose would sink 0.22 m into the seat. The lift follows the clip's
## own root drop (0 standing .. SEAT_LIFT_M fully seated), so the body settles onto the cushion instead of through
## it; the chair stays on the ground (sinking it instead buried its legs). test_player_rig pins the line-up.
const SEAT_LIFT_M := 0.221
## How far the dead Beginner is lifted so it lies on the ground (m). Measured on the pack's v1 rigs at the character
## scale: with its root held at rest (#62) the death clip lays the big chibi head 0.176 m under the feet (the clip's
## own stripped root lift, 0.12 m x 0.7566, was not enough either), and the X-ray fill painted the buried head and
## heels blue on a dead player nothing hides. The lift grows with the fall, over the first DEATH_FALL_SHARE of the
## clip (the sink grows about linearly until then and holds), and goes with the clip. test_player_rig pins it.
const DEATH_REST_LIFT_M := 0.176
const DEATH_FALL_SHARE := 0.5
## The art pack's Beginner preset per CharacterState.gender (#59: the default preset for the gender). Unknown ("")
## shows the male preset. The character's hair, face and skin (#67, CharacterState.appearance) go on it through
## CharacterLook.
const PRESETS := {"male": "Beginner_Male", "female": "Beginner_Female"}
const DEFAULT_PRESET := "Beginner_Male"

## Use the art pack's rigged Beginner, else the library proxy, when available (tests set false for the placeholder).
@export var use_library_model: bool = true
@export var blob_shadow: bool = true
## The X-ray fill and the see-through outline.
@export var xray: bool = true

var player: PlayerController = null
var model: Node3D = null
var shadow: Decal = null
## camera.json colours and timings (loaded in _ready; tests may set them before adding the node).
var xray_color: Color = Color(0.25, 0.55, 1.0, 0.55)
var silhouette_color: Color = Color(0.3, 0.62, 1.0, 1.0)
var silhouette_width_px: float = 3.0
var see_through_fade_s: float = 0.12
## Outline opacity factor (0 hidden .. 1 full), eased toward the requested state.
var see_through_amount: float = 0.0

var _see_through: bool = false
var _fill_mat: StandardMaterial3D = null
var _mark_mat: StandardMaterial3D = null
var _outline_mat: StandardMaterial3D = null
var _outlines: Array[MeshInstance3D] = []
## Parent of the outline meshes (a child of this node, following the model; see the class doc).
var _outline_root: Node3D = null
## True on a blink-off slice: the body is hidden (apply_blink).
var _blink_off: bool = false
var _config_loaded: bool = false
var _yaw: float = 0.0
var _bob_phase: float = 0.0
var _tilt: float = 0.0
var _death_t: float = 0.0
## Sit pose amount (0 standing .. 1 seated) and the chair under the player (built on the first sit).
var sit_amount: float = 0.0
var chair_prop: Node3D = null
## CharacterState.gender for the preset ("" = read Game.character when the player uses the autoloads). Set it before
## the node enters the tree.
var gender: String = ""
## CharacterState.appearance for the look (read from Game.character with the gender when `gender` is ""). Set it
## with `gender`, before the node enters the tree.
var appearance: Dictionary = {}
## The art pack preset shown ("" = no rig: the library proxy or the placeholder).
var preset: String = ""
## The look on the rig (a complete CharacterAppearance look; {} without a rig).
var look: Dictionary = {}
## Equipment.equipped() for what the character wears (slot -> item id; read from Game.character with the gender when
## `gender` is ""). Set it with `gender`, before the node enters the tree; set_equipment() changes it later.
var equipment: Dictionary = {}
## The equipment on the rig (its non-empty slots; {} without a rig) and what CharacterWardrobe.dress made of it
## ({worn: {slot: [meshes]}, held: {slot: node}, hidden, missing}).
var worn: Dictionary = {}
var wardrobe: Dictionary = {}
## Drives the rig's clips (null without a rig).
var animator: PlayerAnimator = null
## The art pack (injectable before the node enters the tree; else the installed one, loaded once).
var art: ArtPack = null

var _chair_id: String = ""
var _last_feet: Vector3 = Vector3.ZERO
var _hooked: bool = false
var _combat: Node = null
var _skills: Node = null
var _skeleton: Skeleton3D = null
var _root_bone: int = -1
## Outline hulls of the held items' static meshes, which a bone attachment moves: [source mesh, hull] pairs that
## step_see_through puts back on their source every frame the outline shows.
var _held_outlines: Array = []


func _ready() -> void:
	player = get_parent() as PlayerController
	if not _config_loaded:
		load_config(_read_config())
	_install_model()
	if blob_shadow and player != null:
		shadow = _build_shadow()
		player.add_child.call_deferred(shadow)
	if player != null:
		_yaw = atan2(player.facing.x, player.facing.z)
		_last_feet = player.global_position
	# The live player follows the live character: a new game or a load during play may change the gender.
	if player != null and player.use_autoloads and gender == "":
		var game := get_node_or_null(^"/root/Game")
		if game != null and game.has_signal(&"character_replaced"):
			game.connect(&"character_replaced", _on_character_replaced)
		# Every equip, unequip and swap (and the "" after a new game or a load) shows at once (#68).
		var events := get_node_or_null(^"/root/Events")
		if events != null and events.has_signal(&"equipment_changed"):
			events.connect(&"equipment_changed", _on_equipment_changed)


## Shows the preset for `character_gender` (CharacterState.gender) with the current appearance (set_look).
func set_gender(character_gender: String) -> void:
	set_look(character_gender, appearance)


## Shows the preset for `character_gender` wearing `character_appearance` (CharacterState.appearance; missing or bad
## values: the gender's default), rebuilding the rigged model and its silhouette when the preset or the look changes.
## Without a rig (no pack, the proxy or the placeholder) nothing changes.
func set_look(character_gender: String, character_appearance: Dictionary) -> void:
	show_character(character_gender, character_appearance, equipment)


## Shows `equipped` (Equipment.equipped(): slot -> item id) on the rig, rebuilding the model and its silhouette when
## the items shown change (#68). Without a rig nothing changes.
func set_equipment(equipped: Dictionary) -> void:
	show_character(gender, appearance, equipped)


## The preset, look and equipment together: one rebuild when any of them changes what the rig shows.
func show_character(character_gender: String, character_appearance: Dictionary, equipped: Dictionary) -> void:
	gender = character_gender
	appearance = character_appearance.duplicate()
	equipment = equipped.duplicate()
	if animator == null or (preset_for(character_gender) == preset
			and CharacterAppearance.resolve(character_appearance, character_gender) == look
			and shown_equipment(equipped) == worn):
		return
	remove_child(model)
	model.free()
	if _outline_root != null:
		remove_child(_outline_root)
		_outline_root.free()
	_outline_root = null
	_outlines.clear()
	_held_outlines.clear()
	animator = null
	preset = ""
	look = {}
	worn = {}
	wardrobe = {}
	_install_model()


## The slots of `equipped` that hold an item (what the rig shows).
static func shown_equipment(equipped: Dictionary) -> Dictionary:
	var out := {}
	for slot in equipped:
		if String(equipped[slot]) != "":
			out[String(slot)] = String(equipped[slot])
	return out


func _on_character_replaced(_reason: String = "") -> void:
	var c := _live_character()
	if c != null:
		show_character(c.gender, c.appearance, c.equipment.equipped())


func _on_equipment_changed(_slot: String = "") -> void:
	var c := _live_character()
	if c != null:
		show_character(c.gender, c.appearance, c.equipment.equipped())


func _live_character() -> CharacterState:
	var game := get_node_or_null(^"/root/Game")
	var c: Variant = game.get("character") if game != null else null
	return c as CharacterState if c is CharacterState else null


func _install_model() -> void:
	model = _build_model()
	add_child(model)
	if xray:
		_apply_silhouette(model)
	_tag_meshes(model)
	if _outline_root != null:
		_tag_meshes(_outline_root)


func _process(delta: float) -> void:
	advance(delta)


## One presentation frame of `delta` seconds (called from _process; tests call it directly): the see-through fade,
## the facing, the rig's clips or the placeholder's procedural motions, the sit pose, the blink and the shadow. A visual
## with no player (the creation screen's preview) only plays the rig's idle clip.
func advance(delta: float) -> void:
	step_see_through(delta)
	if player == null and animator != null:
		# No player to follow (the creation screen's preview): the rig stands in its idle clip.
		animator.update({}, delta)
	if player == null or player.model == null:
		return
	var m := player.model
	# Facing: turn toward the logical facing at the presentation turn rate.
	var want := atan2(player.facing.x, player.facing.z)
	var diff := wrapf(want - _yaw, -PI, PI)
	var step := m.facing_turn_rate * delta
	_yaw = want if absf(diff) <= step else _yaw + signf(diff) * step
	var speed := Vector3(player.actual_velocity.x, 0.0, player.actual_velocity.z).length()
	if animator != null:
		_step_rig(delta, speed)
	# Walk bob and a slight lean into the motion; nothing while airborne, climbing or dead. Retired on the rig, whose
	# walk clip moves the body (covers()).
	var moving := player.is_grounded() and speed > 0.2 and not player.is_dead()
	if moving:
		_bob_phase += delta * speed / maxf(m.walk_speed, 0.01) * TAU * 2.2
	else:
		_bob_phase = 0.0
	var bob := absf(sin(_bob_phase)) * 0.05 if moving and not covers(&"bob") else 0.0
	var lean := clampf(speed / maxf(m.walk_speed, 0.01), 0.0, 1.0) * 0.12 if moving and not covers(&"lean") else 0.0
	_tilt = lerpf(_tilt, lean, 1.0 - exp(-12.0 * delta))
	# Death: fall over backwards (the placeholder; the rig plays its death clip).
	_death_t = clampf(_death_t + (delta if player.is_dead() else -delta * 4.0) / 0.35, 0.0, 1.0)
	var fall := 0.0 if covers(&"death_fall") else _death_t * deg_to_rad(80.0)
	step_sit(delta)
	var drop := 0.0 if covers(&"sit_drop") else SIT_DROP_M * sit_amount
	var sit_lean := 0.0 if covers(&"sit_lean") else sit_amount * deg_to_rad(SIT_LEAN_DEG)
	position = player.presentation_offset + Vector3.UP * (bob + ground_lift()) + Vector3.DOWN * drop
	rotation = Vector3(_tilt - fall - sit_lean, _yaw, 0.0)
	# Classic post-hit blink while invulnerable.
	if model != null:
		apply_blink(player.is_invulnerable() and blink_off_at(Time.get_ticks_msec()))
	if shadow != null:
		shadow.visible = not player.is_climbing()


# =================================================================================================================
# Rigged Beginner
# =================================================================================================================

## True when the model is the art pack's rigged Beginner (its clips follow the gameplay state).
func rigged() -> bool:
	return animator != null


## The clip the rig plays now (&"" without a rig).
func current_clip() -> StringName:
	return animator.current if animator != null else &""


## True when a rig clip replaces the procedural `motion` (COVERED_BY: &"bob", &"lean", &"death_fall", &"sit_drop",
## &"sit_lean", &"lunge"), so the procedural one must not run. PlayerCombat asks before its attack lunge.
func covers(motion: StringName) -> bool:
	return animator != null and COVERED_BY.has(motion) and animator.has_clip(COVERED_BY[motion])


## The art pack preset for a CharacterState.gender.
static func preset_for(character_gender: String) -> String:
	return String(PRESETS.get(character_gender, DEFAULT_PRESET))


## How far the rig is lifted onto the chair now (m): SEAT_LIFT_M times the sit clip's current share of its root drop,
## so it rises and settles with the clip (and the blend out of it). 0 without a rig.
func seat_lift() -> float:
	if animator == null or model == null:
		return 0.0
	if _skeleton == null or not is_instance_valid(_skeleton) or not model.is_ancestor_of(_skeleton):
		_skeleton = model.find_child("Skeleton3D", true, false) as Skeleton3D
		_root_bone = _skeleton.find_bone(ArtImport.ROOT_BONE) if _skeleton != null else -1
	if _root_bone < 0:
		return 0.0
	var drop := _skeleton.get_bone_rest(_root_bone).origin.y - _skeleton.get_bone_pose_position(_root_bone).y
	return SEAT_LIFT_M * clampf(drop / SIT_ROOT_DROP, 0.0, 1.0)


## How far the dead rig is lifted onto the ground now (m): DEATH_REST_LIFT_M as the death clip falls. 0 otherwise.
func death_lift() -> float:
	if animator == null or animator.current != PlayerAnimator.DEATH:
		return 0.0
	var ap := animator.anim
	if not ap.is_playing() or ap.current_animation != String(PlayerAnimator.DEATH):
		return DEATH_REST_LIFT_M
	var fall := ap.current_animation_length * DEATH_FALL_SHARE
	return DEATH_REST_LIFT_M * clampf(ap.current_animation_position / fall, 0.0, 1.0) if fall > 0.0 else DEATH_REST_LIFT_M


## The rig's whole lift onto what it rests on (seat_lift() + death_lift()); the only vertical offset the visual
## adds to the body on the rig besides the controller's step smoothing.
func ground_lift() -> float:
	return seat_lift() + death_lift()


func _step_rig(delta: float, speed: float) -> void:
	_hook_sources()
	var m := player.model
	var feet := player.global_position
	var climb_rate := absf(feet.y - _last_feet.y) / delta / maxf(m.climb_speed, 0.01) if delta > 0.0 else 0.0
	_last_feet = feet
	var walk_ref := m.walk_speed * 100.0 / maxf(m.speed_stat, 1.0)
	animator.update({
		"dead": player.is_dead(), "seated": player.is_seated(), "hitstun": player.in_hitstun,
		"climbing": player.is_climbing(), "airborne": not player.is_grounded() and not player.is_climbing(),
		"speed": speed, "run_speed": walk_ref * RUN_FACTOR, "climb_rate": climb_rate,
		"cycle_speed": walk_ref * RUN_FACTOR if speed >= walk_ref * RUN_FACTOR else walk_ref,
	}, delta)


## Connects the gameplay signals the clips react to. PlayerCombat and PlayerSkills join the player after this visual
## (MonsterSystem.attach_player), so this runs every frame and connects whatever has appeared.
func _hook_sources() -> void:
	if not _hooked:
		_hooked = true
		player.knocked_back.connect(_on_knocked_back)
		# A landed touch without a knockback (ContactDamage) is announced only on the bus, by the live player.
		var events := get_node_or_null(^"/root/Events") if player.use_autoloads else null
		if events != null and events.has_signal(&"player_damaged"):
			events.connect(&"player_damaged", _on_player_damaged)
	var combat := player.get_node_or_null(^"PlayerCombat")
	if combat != _combat and combat != null and combat.has_signal(&"attack_started"):
		_combat = combat
		combat.connect(&"attack_started", _on_attack_started)
	var skills := player.get_node_or_null(^"PlayerSkills")
	if skills != _skills and skills != null and skills.has_signal(&"cast_started"):
		_skills = skills
		skills.connect(&"cast_started", _on_cast_started)


func _on_knocked_back(_push_dir: Vector3) -> void:
	if animator != null:
		animator.trigger_hit()


func _on_player_damaged(_amount: Variant = null, _mob_id: Variant = null) -> void:
	if animator != null:
		animator.trigger_hit()


func _on_attack_started(_action: Variant, _presentation: Variant, lockout_s: float) -> void:
	if animator != null:
		animator.trigger_attack(lockout_s)


func _on_cast_started(_skill_id: Variant, _level: Variant, lockout_s: float) -> void:
	if animator != null:
		animator.trigger_attack(lockout_s)


# =================================================================================================================
# Sit pose
# =================================================================================================================

## Eases sit_amount toward the player's seated state and shows the chair under a seated player (called from _process;
## tests call it directly).
func step_sit(delta: float) -> void:
	var seated := player != null and player.is_seated()
	sit_amount = move_toward(sit_amount, 1.0 if seated else 0.0, delta / SIT_EASE_S)
	if seated and (chair_prop == null or player.seated_chair_id() != _chair_id):
		if chair_prop != null:
			chair_prop.free()
		_chair_id = player.seated_chair_id()
		chair_prop = _pack_chair(_chair_id)
		if chair_prop == null:
			chair_prop = _build_chair()
		player.add_child(chair_prop)
	if chair_prop != null:
		chair_prop.visible = seated
		chair_prop.rotation = Vector3(0.0, _yaw, 0.0)


## With the rig: the art pack's model of the chair item (The Green Relaxer is "522"), at the character scale like
## the body that sits on it (the seat line-up is SEAT_LIFT_M), front +Z, every surface writing the player's stencil
## like the procedural chair. Null without the rig or without a model for that item (the procedural chair then).
func _pack_chair(item_id: String) -> Node3D:
	if animator == null:
		return null
	_load_art()
	var inst := art.instance(ArtPack.ITEM, item_id) if art.present() else null
	if inst == null:
		return null
	var root := Node3D.new()
	root.name = CHAIR_NAME
	root.set_meta("item_id", item_id)
	inst.scale = Vector3.ONE * ArtPack.character_scale()
	root.add_child(inst)
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			var copy := mat.duplicate() as BaseMaterial3D
			_write_stencil(copy)
			mi.set_surface_override_material(s, copy)
	_tag_meshes(root)
	return root


static func _write_stencil(m: BaseMaterial3D) -> void:
	m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	m.stencil_reference = STENCIL_REF


## A four-legged armchair with a high back, in the model frame (front +Z, feet at y = 0): the seat sits under the
## settled body and the back behind it. #11: the first chair (0.64 m across) hid under the seated body (0.89 m across
## with its arms) on every facing, on grass and on Amherst's grey road alike. This one is wider than the body (the
## armrests and the back's side rails show on both sides of it), its back rises past the shoulders behind the head,
## its seat reaches out in front of the knees, and every part is inked like the island's assets, so the frame reads
## on grass, sand and the road.
func _build_chair() -> Node3D:
	var root := Node3D.new()
	root.name = CHAIR_NAME
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CHAIR_COLOR
	# Acceptance fixes (UI and play package): a dark wooden frame (legs, seat rim, back rails) around the green
	# cushions, so the chair reads on green grass (the acceptance review could not see it under the seated player).
	var frame := StandardMaterial3D.new()
	frame.albedo_color = CHAIR_FRAME_COLOR
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = CHAIR_INK_COLOR
	ink.cull_mode = BaseMaterial3D.CULL_FRONT
	# The chair counts as the player's own pixels (STENCIL_REF): the X-ray fill must not paint the body blue over a
	# back rail in front of it (facing away from the camera).
	for m: BaseMaterial3D in [mat, frame, ink]:
		m.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
		m.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
		m.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
		m.stencil_reference = STENCIL_REF
	var parts := [
		[Vector3(0.0, 0.3, 0.0), Vector3(0.84, 0.09, 0.72), mat],       # seat cushion
		[Vector3(0.0, 0.76, -0.38), Vector3(0.84, 0.82, 0.08), mat],    # back cushion
		[Vector3(0.0, 0.24, 0.0), Vector3(0.96, 0.06, 0.8), frame],     # seat rim, wider than the cushion
		[Vector3(0.0, 1.22, -0.39), Vector3(1.0, 0.08, 0.13), frame],   # back top rail, above the shoulders
	]
	for x in [-0.47, 0.47]:
		parts.append([Vector3(x, 0.74, -0.39), Vector3(0.07, 0.98, 0.11), frame])  # back side rails
		parts.append([Vector3(x, 0.56, -0.02), Vector3(0.09, 0.07, 0.76), frame])  # armrests
		parts.append([Vector3(x, 0.42, 0.3), Vector3(0.07, 0.24, 0.07), frame])    # armrest posts
	for x in [-0.42, 0.42]:
		for z in [-0.34, 0.32]:
			parts.append([Vector3(x, 0.11, z), Vector3(0.08, 0.23, 0.08), frame])  # legs
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = p[1]
		mi.mesh = box
		mi.material_override = p[2]
		mi.position = p[0]
		root.add_child(mi)
		# The ink: an inverted hull CHAIR_INK_M wider, as the island's assets and the Wooden Box are inked.
		var hull := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = (p[1] as Vector3) + Vector3.ONE * CHAIR_INK_M * 2.0
		hull.mesh = hm
		hull.material_override = ink
		hull.position = p[0]
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(hull)
	_tag_meshes(root)
	return root


# =================================================================================================================
# See-through outline
# =================================================================================================================

## Shows (true) or hides (false) the see-through outline; it fades over see_through_fade_s. CameraRig calls this
## every update with "is anything hiding the player".
func set_see_through(on: bool) -> void:
	_see_through = on


## The requested state (the outline may still be fading).
func is_see_through() -> bool:
	return _see_through


## Advances the outline fade by `delta` seconds and applies it (called from _process; tests call it directly).
func step_see_through(delta: float) -> void:
	var goal := 1.0 if _see_through else 0.0
	see_through_amount = move_toward(see_through_amount, goal, delta / maxf(see_through_fade_s, 0.001))
	if _outline_mat == null:
		return
	if _outline_root != null and model != null:
		_outline_root.transform = model.transform
	var c := silhouette_color
	# A blink-off slice while hidden: the body is gone, so the outline hull draws the whole silhouette; at the X-ray
	# fill's opacity it reads as the hidden player, not as a solid blob.
	c.a = (xray_color.a if _blink_off else c.a) * see_through_amount
	_outline_mat.albedo_color = c
	var on := see_through_amount > 0.001
	for o in _outlines:
		if is_instance_valid(o):
			o.visible = on
	if on:
		_outline_mat.grow_amount = outline_grow()
		for pair: Array in _held_outlines:
			var src: MeshInstance3D = pair[0]
			var hull: MeshInstance3D = pair[1]
			if is_instance_valid(src) and is_instance_valid(hull) and src.is_inside_tree() and hull.is_inside_tree():
				hull.global_transform = src.global_transform


## True on the blink-off slices of the post-hit blink at `msec` (Time.get_ticks_msec()).
static func blink_off_at(msec: int) -> bool:
	return int(msec / BLINK_MS) % 2 == 1


## Shows the body (false) or hides it for a blink-off slice (true). The outline meshes are not under the body, so
## while the see-through outline is on they still draw the silhouette (step_see_through gives it the ghost opacity).
func apply_blink(off: bool) -> void:
	_blink_off = off
	if model != null:
		model.visible = not off


## True on a blink-off slice (apply_blink).
func is_blinked_off() -> bool:
	return _blink_off


## The outline meshes (one per model mesh with lit surfaces).
func outline_meshes() -> Array[MeshInstance3D]:
	return _outlines


## The X-ray fill, the silhouette mark and the outline materials ({fill, mark, outline}; null before _ready or
## without xray).
func silhouette_materials() -> Dictionary:
	return {"fill": _fill_mat, "mark": _mark_mat, "outline": _outline_mat}


## How far the outline hull grows, in meters: silhouette_width_px at the current orthographic camera's scale.
func outline_grow() -> float:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var h := get_viewport().get_visible_rect().size.y if is_inside_tree() else 0.0
	if cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL and h > 0.0:
		return silhouette_width_px * cam.size / h
	return silhouette_width_px * 15.0 / 900.0


## Reads the colours and timings from camera.json (a Dictionary as loaded).
func load_config(cfg: Dictionary) -> void:
	_config_loaded = true
	xray_color = _color(cfg.get("xray_color"), xray_color)
	silhouette_color = _color(cfg.get("silhouette_color"), silhouette_color)
	silhouette_width_px = float(cfg.get("silhouette_width_px", silhouette_width_px))
	see_through_fade_s = float(cfg.get("silhouette_fade_s", see_through_fade_s))


static func _color(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 4:
		return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return fallback


static func _read_config() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/misostory/camera.json")
	var cfg: Variant = JSON.parse_string(text) if text != "" else null
	return cfg if cfg is Dictionary else {}


## Gives every surface a stencil write and every lit surface the shared X-ray fill as its next pass (on duplicated
## materials, so the shared library materials stay untouched), and adds an outline mesh under every mesh that has lit
## surfaces.
func _apply_silhouette(root: Node) -> void:
	_fill_mat = StandardMaterial3D.new()
	_fill_mat.resource_name = "PlayerXrayFill"
	_fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fill_mat.albedo_color = xray_color
	_fill_mat.no_depth_test = true
	# Front faces only (like Godot's own X-ray pass): a hidden part blends once, not front and back.
	_fill_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_fill_mat.render_priority = FILL_PRIORITY
	_fill_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	_fill_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
	_fill_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
	_fill_mat.stencil_reference = STENCIL_REF
	# Godot keeps stencil read and write exclusive, so an invisible pass after the fill marks the whole silhouette
	# (visible and hidden parts) for the outline.
	_mark_mat = StandardMaterial3D.new()
	_mark_mat.resource_name = "PlayerSilhouetteMark"
	_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mark_mat.albedo_color = Color(0, 0, 0, 0)
	_mark_mat.no_depth_test = true
	_mark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mark_mat.render_priority = MARK_PRIORITY
	_mark_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	_mark_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
	_mark_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
	_mark_mat.stencil_reference = STENCIL_REF
	_fill_mat.next_pass = _mark_mat
	_outline_mat = StandardMaterial3D.new()
	_outline_mat.resource_name = "PlayerSeeThroughOutline"
	_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_outline_mat.albedo_color = Color(silhouette_color, 0.0)
	_outline_mat.no_depth_test = true
	_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_outline_mat.grow = true
	_outline_mat.grow_amount = outline_grow()
	_outline_mat.render_priority = OUTLINE_PRIORITY
	_outline_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
	_outline_mat.stencil_flags = BaseMaterial3D.STENCIL_FLAG_READ
	_outline_mat.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_NOT_EQUAL
	_outline_mat.stencil_reference = STENCIL_REF
	_outline_root = Node3D.new()
	_outline_root.name = OUTLINE_ROOT
	add_child(_outline_root)
	var meshes: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes.append(n)
	for mi in meshes:
		var lit: Array[int] = []
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			# Every visible surface of the player writes the stencil, the unshaded ink shell (Player_Proxy M_Outline)
			# too: its inverted hull draws the contour lines in front of the body at creases (hair over the face, the
			# ear, the feet), and if it did not count as "the player was drawn here" the fill would paint those lines
			# blue on a player nothing hides. Only lit surfaces carry the fill and get an outline hull (the ink is
			# already an expanded shell).
			var copy := mat.duplicate() as BaseMaterial3D
			copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
			copy.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
			copy.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
			copy.stencil_reference = STENCIL_REF
			if mat.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
				copy.next_pass = _fill_mat
				lit.append(s)
			if mi.material_override != null:
				mi.material_override = copy
				break
			mi.set_surface_override_material(s, copy)
		if lit.is_empty():
			continue
		# A material_override covers every surface, so the hull does too.
		var surfaces: Array = Array(lit) if mi.material_override == null else range(mi.mesh.get_surface_count())
		var hull := smoothed_hull(mi.mesh, surfaces)
		if hull == null:
			continue
		var o := MeshInstance3D.new()
		o.name = OUTLINE_NAME
		o.mesh = hull
		o.material_override = _outline_mat
		o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		o.visible = false
		# Under the outline root, at the mesh's place in the model: hiding the body for the blink leaves it.
		var rel := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			if n is Node3D:
				rel = (n as Node3D).transform * rel
			n = n.get_parent()
		o.transform = rel
		_outline_root.add_child(o)
		# A skinned mesh (the rig): the hull keeps its bones and weights (smoothed_hull) and is posed by the same skin
		# and skeleton, so the outline follows every clip instead of standing in the bind pose.
		if mi.skin != null:
			o.skin = mi.skin
			o.skeleton = o.get_path_to(mi.get_node(mi.skeleton))
		elif _on_bone(mi, root):
			# A held item (#68): a bone attachment moves it, so its hull is put back on it every frame it shows.
			_held_outlines.append([mi, o])
		_outlines.append(o)


## True when `n` hangs under a BoneAttachment3D inside `root` (a held weapon or shield).
static func _on_bone(n: Node, root: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != root:
		if p is BoneAttachment3D:
			return true
		p = p.get_parent()
	return false


## The see-through outline hull of a held item's mesh (null when it has none).
func held_outline(mi: MeshInstance3D) -> MeshInstance3D:
	for pair: Array in _held_outlines:
		if pair[0] == mi:
			return pair[1]
	return null


## One triangle surface of `surfaces` of `mesh` with every vertex normal averaged over the vertices at the same
## position, so growing it along the normals never cracks at hard edges (the proxy is flat shaded). Null when the
## surfaces hold no triangles. Skinned surfaces keep their bones and weights (when every surface has the same number
## per vertex), so the hull can be posed by the source's skin.
static func smoothed_hull(mesh: Mesh, surfaces: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var index := PackedInt32Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var per_vertex := -1
	var acc: Dictionary = {}
	for s in surfaces:
		# PrimitiveMeshes are always triangles; an ArrayMesh says.
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(int(s)) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(int(s))
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var base := verts.size()
		if arr[Mesh.ARRAY_BONES] != null and arr[Mesh.ARRAY_WEIGHTS] != null and v.size() > 0 and per_vertex != 0:
			var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var n_per := b.size() / v.size()
			if per_vertex < 0 or per_vertex == n_per:
				per_vertex = n_per
				bones.append_array(b)
				weights.append_array(arr[Mesh.ARRAY_WEIGHTS])
			else:
				per_vertex = 0
		else:
			per_vertex = 0
		verts.append_array(v)
		for i in v.size():
			var key := v[i].snappedf(0.0001)
			acc[key] = (acc.get(key, Vector3.ZERO) as Vector3) + (nrm[i] if i < nrm.size() else Vector3.ZERO)
		if ind.is_empty():
			for i in v.size():
				index.append(base + i)
		else:
			for i in ind:
				index.append(base + i)
	if index.is_empty():
		return null
	normals.resize(verts.size())
	for i in verts.size():
		var n: Vector3 = acc[verts[i].snappedf(0.0001)]
		normals[i] = n.normalized() if n.length_squared() > 1e-12 else Vector3.UP
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = index
	var flags := 0
	if per_vertex > 0 and bones.size() == verts.size() * per_vertex:
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		if per_vertex == 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return out


# =================================================================================================================
# Model
# =================================================================================================================

func _build_model() -> Node3D:
	if use_library_model:
		var rig := _rig_model()
		if rig != null:
			return rig
	if use_library_model and ResourceLoader.exists(LIBRARY):
		var lib: PackedScene = load(LIBRARY)
		if lib != null:
			var inst := lib.instantiate()
			var proxy := find_proxy(inst)
			if proxy != null:
				var copy := proxy.duplicate() as Node3D
				inst.free()
				copy.transform = Transform3D.IDENTITY
				copy.name = "Model"
				return copy
			inst.free()
	return _placeholder()


## The art pack's Beginner preset for the character's gender (looked up by ID, #62; already at the character scale
## on its rig node), named "Model", with its animator; null without the pack.
func _rig_model() -> Node3D:
	_load_art()
	if not art.present():
		return null
	var g := _gender()
	var wanted := preset_for(g)
	var inst := art.instance(ArtPack.PRESET, wanted)
	if inst == null:
		return null
	var anims := PlayerAnimator.from_model(inst)
	if anims == null:
		inst.free()
		return null
	inst.name = "Model"
	inst.transform = Transform3D.IDENTITY
	# The saved hair, face and skin (#67), before the silhouette copies the meshes.
	var shown := CharacterAppearance.resolve(_appearance(), g)
	CharacterLook.apply(inst, shown, wanted, art)
	# What the character wears and holds (#68), on the look and before the silhouette copies the meshes.
	var equipped := shown_equipment(_equipment())
	wardrobe = CharacterWardrobe.dress(inst, equipped, art)
	preset = wanted
	look = shown
	worn = equipped
	animator = anims
	return inst


func _load_art() -> void:
	if art == null:
		art = ArtPack.load_installed()


func _gender() -> String:
	if gender != "" or player == null or not player.use_autoloads:
		return gender
	var game := get_node_or_null(^"/root/Game")
	var c: Variant = game.get("character") if game != null else null
	return String(c.gender) if c is CharacterState else ""


## The appearance to show: `appearance` when the gender was given (tests, set_look), else the live character's.
func _appearance() -> Dictionary:
	if gender != "" or not appearance.is_empty() or player == null or not player.use_autoloads:
		return appearance
	var game := get_node_or_null(^"/root/Game")
	var c: Variant = game.get("character") if game != null else null
	return (c as CharacterState).appearance if c is CharacterState else {}


## The equipment to show: `equipment` when the gender was given (tests, show_character), else the live character's.
func _equipment() -> Dictionary:
	if gender != "" or not equipment.is_empty() or player == null or not player.use_autoloads:
		return equipment
	var c := _live_character()
	return c.equipment.equipped() if c != null else {}


## The Player_Proxy root of an instantiated library: the export names asset roots with Blender's numeric suffix
## ("Player_Proxy_001"), matched like ProxyLibrary does.
static func find_proxy(library_root: Node) -> Node3D:
	for c in library_root.get_children():
		if c is Node3D and ProxyLibrary.asset_name(String(c.name)) == PROXY_NODE:
			return c
	return library_root.find_child(PROXY_NODE, true, false) as Node3D


## A chibi placeholder: big head, short body, a nose for facing (front = +Z).
func _placeholder() -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("#ffd9b8")
	var shirt := StandardMaterial3D.new()
	shirt.albedo_color = Color("#3b7dd8")
	var hair := StandardMaterial3D.new()
	hair.albedo_color = Color("#6b3b1f")
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.24
	cap.height = 0.75
	body.mesh = cap
	body.material_override = shirt
	body.position = Vector3(0, 0.38, 0)
	root.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.36
	sphere.height = 0.7
	head.mesh = sphere
	head.material_override = skin
	head.position = Vector3(0, 1.08, 0)
	root.add_child(head)
	var hair_mi := MeshInstance3D.new()
	var hs := SphereMesh.new()
	hs.radius = 0.38
	hs.height = 0.5
	hair_mi.mesh = hs
	hair_mi.material_override = hair
	hair_mi.position = Vector3(0, 1.22, -0.05)
	root.add_child(hair_mi)
	var nose := MeshInstance3D.new()
	var nm := SphereMesh.new()
	nm.radius = 0.06
	nm.height = 0.12
	nose.mesh = nm
	nose.material_override = skin
	nose.position = Vector3(0, 1.02, 0.35)
	root.add_child(nose)
	return root


func _tag_meshes(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = PLAYER_LAYER
	for c in n.get_children():
		_tag_meshes(c)


## A soft round shadow projected straight down under the feet: reads the landing spot of every jump.
func _build_shadow() -> Decal:
	var d := Decal.new()
	d.name = "BlobShadow"
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	d.texture_albedo = tex
	# The box spans from just above the feet to 5.7 m below them: it paints the ground under a jump or a drop,
	# never a canopy or ceiling above the player.
	d.size = Vector3(0.9, 6.0, 0.9)
	d.position = Vector3(0.0, -2.7, 0.0)
	d.upper_fade = 0.05
	d.lower_fade = 0.3
	d.cull_mask = 0xFFFFF & ~PLAYER_LAYER
	return d
