class_name EffectMeshes
extends RefCounted
## The art pack's effect meshes (Project art, ADR 0002; ArtPack kind EFFECT, #71), shown on the game's existing skill
## and combat events. Presentation only: what plays, where and for how long is the caller's, and nothing here touches
## a gameplay value. Without the pack (a fresh clone, NO_ART_PACK=1 tests) every lookup is empty and the callers keep
## today's procedural effects.
##
##   ThreeSnails  the thrown shell (PlayerSkills._play_shell), on the same flight
##   Recovery     shown while the Recovery timed effect runs (PlayerFx)
##   NimbleFeet   shown while the Nimble Feet timed effect runs (PlayerFx)
##   HitSpark     the hit spark (AttackFx.spark)
##   JumpDust     dust at the feet on a ground jump and a landing (PlayerFx)
##
## Every effect model is one skinned mesh set on a two-bone rig whose Loop clip (2 s, looping as imported) spins and
## pulses it about its own vertical axis. The materials are opaque; a fade uses GeometryInstance3D.transparency.
##
##   var meshes := EffectMeshes.shared()            # the installed pack, loaded once
##   var spark := meshes.centered(EffectMeshes.HIT_SPARK, 0.7)   # null without the pack: keep the procedural effect

const THREE_SNAILS := "ThreeSnails"
const RECOVERY := "Recovery"
const NIMBLE_FEET := "NimbleFeet"
const HIT_SPARK := "HitSpark"
const JUMP_DUST := "JumpDust"
## The one clip every effect model carries.
const CLIP := "Loop"
## Skill id (canonical) -> the effect shown for as long as that skill's timed effect runs.
const SKILL_AURAS := {"0001001": RECOVERY, "0001002": NIMBLE_FEET}

static var _shared: EffectMeshes = null

## The pack the meshes come from (null: none).
var art: ArtPack = null
## Effect name -> its model's rest-pose bounds (cached per name).
var _bounds: Dictionary = {}


## The installed pack's effect meshes, loaded once per process (ArtPack.load_installed reads several manifests).
static func shared() -> EffectMeshes:
	if _shared == null:
		_shared = from_pack(ArtPack.load_installed())
	return _shared


static func from_pack(pack: ArtPack) -> EffectMeshes:
	var m := EffectMeshes.new()
	m.art = pack
	return m


## No pack: every lookup is empty (tests pin the procedural effects with it).
static func none() -> EffectMeshes:
	return EffectMeshes.new()


## True when the pack maps the effect and its model is imported.
func has(effect: String) -> bool:
	if art == null or not art.present():
		return false
	var path := art.model(ArtPack.EFFECT, effect)
	return path != "" and ResourceLoader.exists(path)


## A fresh instance of the effect's model with its Loop clip playing and shadows off, or null without it. The model
## keeps its authored origin (the effects stand on y = 0 and spin about that vertical axis).
func instance(effect: String) -> Node3D:
	if not has(effect):
		return null
	var n := art.instance(ArtPack.EFFECT, effect)
	if n == null:
		return null
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		var player := ap as AnimationPlayer
		if player.has_animation(CLIP):
			player.autoplay = CLIP
			player.play(CLIP)
	if not _bounds.has(effect):
		_bounds[effect] = ArtImport.visual_aabb(n)
	return n


## The effect's model under a pivot named after it, scaled so the model is `height_m` tall (0 = as authored) and
## lifted so its vertical centre sits on the pivot's origin (its spin axis stays on the pivot's). Null without it.
func centered(effect: String, height_m: float = 0.0) -> Node3D:
	var model := instance(effect)
	if model == null:
		return null
	var box: AABB = _bounds[effect]
	var s := height_m / box.size.y if height_m > 0.0 and box.size.y > 1e-4 else 1.0
	model.scale = Vector3.ONE * s
	model.position = Vector3.DOWN * box.get_center().y * s
	var pivot := Node3D.new()
	pivot.name = effect
	pivot.add_child(model)
	return pivot


## The effect's model scaled by `scale` about its authored origin (feet-based effects: auras, dust). Null without it.
func standing(effect: String, scale: float = 1.0) -> Node3D:
	var model := instance(effect)
	if model != null:
		model.scale = Vector3.ONE * scale
	return model


## Fades every mesh under `root`: 0 opaque, 1 gone (the effect materials are opaque, so the fade is per instance).
static func fade(root: Node, amount: float) -> void:
	var t := clampf(amount, 0.0, 1.0)
	if root is GeometryInstance3D:
		(root as GeometryInstance3D).transparency = t
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).transparency = t
