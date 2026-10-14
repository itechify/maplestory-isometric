class_name PlayerAnimator
extends RefCounted
## Which clip of the rigged Beginner (Project art, #59/#63) the player's gameplay state plays. Presentation only: it
## reads the state PlayerVisual gathers from the controller and combat code and never changes it.
##
## select() is the pure rule, in priority order:
##   death   dead
##   sit     seated
##   hit     a hit reaction (a landed monster touch or a knockback, for the hit clip's length or the hit-stun)
##   climb   on a ladder, rope or vine
##   attack  a basic attack's or a skill cast's swing (it plays over a jump too)
##   jump    any airborne state (a jump, a fall)
##   run     grounded at or above run_speed (there is no run state: faster than Speed 100 walking, e.g. Nimble Feet)
##   walk    grounded and moving
##   idle    grounded, about still

const IDLE := ArtImport.CLIP_IDLE
const WALK := ArtImport.CLIP_WALK
const RUN := ArtImport.CLIP_RUN
const JUMP := ArtImport.CLIP_JUMP
const CLIMB := ArtImport.CLIP_CLIMB
const ATTACK := ArtImport.CLIP_ATTACK
const HIT := ArtImport.CLIP_HIT
const SIT := ArtImport.CLIP_SIT
const DEATH := ArtImport.CLIP_DEATH
const CLIPS: Array[StringName] = [IDLE, WALK, RUN, JUMP, CLIMB, ATTACK, HIT, SIT, DEATH]

## Horizontal speed (m/s) under which a grounded player reads as standing (presentation: the controller's own
## STILL_SPEED is "about zero"; this one keeps the walk cycle from twitching while ground_decel stops the body).
const IDLE_SPEED := 0.2


## The clip for one gameplay state: {dead, seated, hit, climbing, attacking, airborne: bool, speed: horizontal m/s,
## run_speed: m/s}.
static func select(s: Dictionary) -> StringName:
	if bool(s.get("dead", false)):
		return DEATH
	if bool(s.get("seated", false)):
		return SIT
	if bool(s.get("hit", false)):
		return HIT
	if bool(s.get("climbing", false)):
		return CLIMB
	if bool(s.get("attacking", false)):
		return ATTACK
	if bool(s.get("airborne", false)):
		return JUMP
	var speed := float(s.get("speed", 0.0))
	if speed < IDLE_SPEED:
		return IDLE
	return RUN if speed >= float(s.get("run_speed", INF)) else WALK


# =================================================================================================================
# Driving the rig's AnimationPlayer
# =================================================================================================================

## Crossfade into each clip (s). Reactions cut in fast so they read on the frame they happen; locomotion eases; the
## landing from a jump settles into idle or walk over the locomotion blend.
const BLEND_S := {IDLE: 0.2, WALK: 0.15, RUN: 0.15, JUMP: 0.08, CLIMB: 0.12, ATTACK: 0.05, HIT: 0.05, SIT: 0.15,
	DEATH: 0.1}
## The walk and run cycles play at the ground speed's share of their reference speed within these bounds, so the
## feet keep up with the body without a run cycle at a crawl.
const CYCLE_SCALE_MIN := 0.6
const CYCLE_SCALE_MAX := 1.8

## The imported AnimationPlayer (processed by hand from update(), so the pose, the blink and the outline stay in
## step with the visual and tests are deterministic).
var anim: AnimationPlayer = null
## The clip selected last (a finished one-shot holds its last frame while it stays selected).
var current: StringName = &""
var _hit_left: float = 0.0
var _attack_left: float = 0.0
var _attack_speed: float = 1.0
var _restart: bool = false
## Seconds since the current clip was (re)started.
var _since_play: float = 0.0


## The animator of an imported character model: null when it has no AnimationPlayer holding every clip of CLIPS.
static func from_model(model: Node) -> PlayerAnimator:
	for node in model.find_children("*", "AnimationPlayer", true, false):
		var ap := node as AnimationPlayer
		var complete := true
		for c in CLIPS:
			complete = complete and ap.has_animation(c)
		if complete:
			var a := PlayerAnimator.new()
			a.anim = ap
			ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			ap.autoplay = ""
			return a
	return null


## Where the rig is in its clips ({} with nothing playing): restore() on the animator of a rebuilt model (an equip or
## a look change) carries on from here instead of starting the clip over.
func snapshot() -> Dictionary:
	if current == &"" or anim == null:
		return {}
	return {"clip": current, "position": anim.current_animation_position, "speed": anim.speed_scale,
		"hit_left": _hit_left, "attack_left": _attack_left, "attack_speed": _attack_speed, "since_play": _since_play}


## Takes up a snapshot() of another animator: the same clip at the same point, with no blend.
func restore(s: Dictionary) -> void:
	if s.is_empty() or not has_clip(s.clip):
		return
	current = s.clip
	_hit_left = s.hit_left
	_attack_left = s.attack_left
	_attack_speed = s.attack_speed
	_since_play = s.since_play
	anim.play(current, 0.0)
	anim.seek(s.position, true)
	anim.speed_scale = s.speed


func has_clip(clip: StringName) -> bool:
	return anim != null and anim.has_animation(clip)


func clip_length(clip: StringName) -> float:
	return anim.get_animation(clip).length if has_clip(clip) else 0.0


## A basic attack or a skill cast started: the attack clip plays from its start, timed to fill the lockout.
func trigger_attack(lockout_s: float) -> void:
	_attack_left = maxf(lockout_s, 0.05)
	_attack_speed = clip_length(ATTACK) / _attack_left
	_restart = true


## A landed monster touch or a knockback: the hit clip plays from its start.
func trigger_hit() -> void:
	_hit_left = clip_length(HIT)
	_restart = true


## Advances the rig by `delta` seconds for the gameplay state `s` (select()'s keys, where `hitstun` also counts as a
## hit; plus `cycle_speed`: the walk/run reference speed, and `climb_rate`: the climbing speed's share of the climb
## speed). Returns the clip playing.
func update(s: Dictionary, delta: float) -> StringName:
	_hit_left = maxf(_hit_left - delta, 0.0)
	_attack_left = maxf(_attack_left - delta, 0.0)
	var st := s.duplicate()
	st["hit"] = bool(s.get("hitstun", false)) or _hit_left > 0.0
	st["attacking"] = _attack_left > 0.0
	var clip := select(st)
	if clip != current or (_restart and clip in [ATTACK, HIT]):
		anim.play(clip, float(BLEND_S.get(clip, 0.1)))
		anim.seek(0.0, true)
		current = clip
		_since_play = 0.0
	else:
		_since_play += delta
	_restart = false
	anim.speed_scale = _speed_for(clip, s)
	anim.advance(delta)
	return current


func _speed_for(clip: StringName, s: Dictionary) -> float:
	match clip:
		WALK, RUN:
			var ref := float(s.get("cycle_speed", 0.0))
			return clampf(float(s.get("speed", 0.0)) / ref, CYCLE_SCALE_MIN, CYCLE_SCALE_MAX) if ref > 0.0 else 1.0
		CLIMB:
			# Holding still on a rope holds the climbing pose, once the blend into it has run (the crossfade advances
			# with the playback speed, so a held clip at speed 0 could keep the previous clip's pose on the rope).
			if _since_play < float(BLEND_S[CLIMB]):
				return 1.0
			return clampf(float(s.get("climb_rate", 1.0)), 0.0, CYCLE_SCALE_MAX)
		ATTACK:
			return _attack_speed
	return 1.0
