class_name GroundDrop
extends Node3D
## One drop lying on the ground (an item or a meso bag): a procedural model (LootVisuals) that is tossed out of the
## monster in a small arc, then hovers, bobs and turns, and blinks during its last seconds. The node is presentation
## only: the record it shows lives in the map instance (MapInstanceState.drops) and LootSystem owns both. LootSystem
## calls update(now, delta) every frame, so the node has no clock of its own and tests can drive it synchronously.

## The ground record's uid (LootPickupRules.UID_KEY).
var uid: String = ""
## A copy of the ground record (MapInstanceState.drops entry).
var record: Dictionary = {}
## Where the drop rests (its base on the ground), world space.
var landing: Vector3 = Vector3.ZERO
var model: Node3D = null
var shadow: MeshInstance3D = null

var _from: Vector3 = Vector3.ZERO
var _toss_t: float = 0.0
var _toss_len: float = 0.0
var _toss_h: float = 0.0
var _hover: float = 0.0
var _bob_amp: float = 0.0
var _bob_period: float = 1.0
var _spin: float = 0.0
var _blink_window: float = 0.0
var _blink_hz: float = 0.0
var _phase: float = 0.0
var _age: float = 0.0
var _last_delta: float = 0.0


## Builds the node. `from` is where the toss starts (the monster), `landing` where it rests. toss = false places it
## at rest at once (drops restored when re-entering a map).
func setup(p_record: Dictionary, visuals: LootVisuals, p_landing: Vector3, from: Vector3, toss: bool) -> void:
	record = p_record.duplicate(true)
	uid = String(record.get(LootPickupRules.UID_KEY, ""))
	name = ("Drop_%s" % uid).validate_node_name()
	landing = p_landing
	_from = from
	_toss_len = visuals.motion("toss_duration_s") if toss else 0.0
	_toss_h = visuals.motion("toss_height_m")
	_hover = visuals.motion("hover_m")
	_bob_amp = visuals.motion("bob_amplitude_m")
	_bob_period = maxf(visuals.motion("bob_period_s"), 0.05)
	_spin = deg_to_rad(visuals.motion("spin_deg_per_s"))
	_blink_window = visuals.motion("blink_before_expiry_s")
	_blink_hz = visuals.motion("blink_hz")
	_phase = float(absi(hash(uid)) % 1000) / 1000.0
	model = visuals.build_drop_model(record)
	add_child(model)
	model.rotation.y = _phase * TAU
	shadow = MeshInstance3D.new()
	shadow.name = "Shadow"
	var disc := CylinderMesh.new()
	var r := maxf(visuals.size("shadow_m"), 0.05) * 0.5
	disc.top_radius = r
	disc.bottom_radius = r
	disc.height = 0.01
	shadow.mesh = disc
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0, 0.32)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = m
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)
	position = landing
	_toss_t = 0.0
	_apply(0.0)


## True once the toss has landed (only landed drops can be picked up).
func is_landed() -> bool:
	return _toss_t >= _toss_len - 0.0001


## Advances the animation. `now` is the game clock (for the expiry blink), `delta` the frame time.
func update(now: float, delta: float) -> void:
	_age += delta
	_last_delta = delta
	if _toss_t < _toss_len:
		_toss_t = minf(_toss_t + delta, _toss_len)
	_apply(now)


## True while the blink pulse hides the model (exposed for tests).
func is_blinking_off() -> bool:
	return model != null and not model.visible


func _apply(now: float) -> void:
	if model == null:
		return
	var rest := Vector3(0, _hover, 0)
	if _toss_len > 0.0 and not is_landed():
		# Parabolic hop from the monster to the landing point: up by toss_height above the higher end, then down.
		var t := _toss_t / _toss_len
		var start := _from - landing
		var flat := start.lerp(rest, t)
		var top := maxf(start.y, rest.y) + _toss_h
		var y := lerpf(start.y, rest.y, t) + (top - maxf(start.y, rest.y)) * 4.0 * t * (1.0 - t)
		model.position = Vector3(flat.x, y, flat.z)
		model.rotation.y += _spin * 3.0 * _last_delta
		shadow.position = Vector3(flat.x, 0.005, flat.z)
	else:
		var bob := sin((_age / _bob_period + _phase) * TAU) * _bob_amp
		model.position = rest + Vector3(0, bob, 0)
		model.rotation.y = _phase * TAU + _age * _spin
		shadow.position = Vector3(0, 0.005, 0)
	var left := LootPickupRules.time_left(record, now)
	if _blink_window > 0.0 and _blink_hz > 0.0 and left < _blink_window:
		model.visible = fmod(left * _blink_hz, 1.0) >= 0.5
	else:
		model.visible = true
