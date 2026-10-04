class_name MonsterCombatStats
extends RefCounted
## The combat numbers of one monster, read from its canonical record (game/data/canonical/monsters/<id>.json).
##
## Field mapping: level, avoidability (EVA), physical_defense (P.DEF / WDEF), magic_defense (M.DEF), accuracy,
## physical_damage (P.DMG, the touch attack), magic_damage (M.DMG), knockback_threshold_damage (KB),
## element.raw, flags.boss, touch_zone_px [w, h]. Runtime modifiers (future debuffs) live in the *_bonus fields so
## the canonical values are never edited.

var id: String = ""
var name: String = ""
var level: int = 1
var hp: int = 0
var exp: int = 0
var avoid: int = 0
var pdef: int = 0
var mdef: int = 0
var acc: int = 0
var pdmg: int = 0
var mdmg: int = 0
## Damage needed to stagger (MeowDB glossary: "a mob with 500 KB needs 500+ damage to stagger").
var kb: int = 0
## MeowDB simulator element string ("" = no elemental affinity; tokens like "fire-strong" separated by "|").
var element_raw: String = ""
var boss: bool = false
## Touch zone in px [w, h], anchored at the bottom centre of the sprite.
var touch_zone_px: Vector2 = Vector2.ZERO
## Canonical hit animation length (ms), or 0 when the record has none.
var hit_animation_ms: int = 0
## EffectiveDEF = max(0, FlatBonus + trunc((1 + PercentBonus / 100) x BaseDEF)) inputs (0 = unmodified).
var pdef_flat_bonus: int = 0
var pdef_percent_bonus: float = 0.0
var mdef_flat_bonus: int = 0
var mdef_percent_bonus: float = 0.0


static func from_monster(m: Dictionary, hit_clip: String = "hit1") -> MonsterCombatStats:
	var s := MonsterCombatStats.new()
	s.id = String(m.get("id", ""))
	s.name = String(m.get("name", ""))
	s.level = _int(m, "level", 1)
	s.hp = _int(m, "hp", 0)
	s.exp = _int(m, "exp", 0)
	s.avoid = _int(m, "avoidability", 0)
	s.pdef = _int(m, "physical_defense", 0)
	s.mdef = _int(m, "magic_defense", 0)
	s.acc = _int(m, "accuracy", 0)
	s.pdmg = _int(m, "physical_damage", 0)
	s.mdmg = _int(m, "magic_damage", 0)
	s.kb = _int(m, "knockback_threshold_damage", 0)
	var el: Variant = m.get("element", {})
	if el is Dictionary:
		var raw: Variant = (el as Dictionary).get("raw", "")
		s.element_raw = String(raw) if raw is String else ""
	elif el is String:
		s.element_raw = String(el)
	var flags: Variant = m.get("flags", {})
	s.boss = bool((flags as Dictionary).get("boss", false)) if flags is Dictionary else false
	var tz: Variant = m.get("touch_zone_px", [])
	if tz is Array and (tz as Array).size() == 2:
		s.touch_zone_px = Vector2(float(tz[0]), float(tz[1]))
	var anims: Variant = m.get("animations", {})
	if anims is Dictionary and (anims as Dictionary).has(hit_clip):
		var clip: Variant = anims[hit_clip]
		if clip is Dictionary and (clip as Dictionary).get("duration_ms", null) != null:
			s.hit_animation_ms = int(clip["duration_ms"])
	return s


## A numeric field, or `fallback` when it is absent or null (canonical records keep unpublished values as null).
static func _int(m: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = m.get(key, null)
	return int(v) if v is int or v is float else fallback


## Combat stats of a canonical monster id ("2" = Snail). Empty stats (and an error) for an unknown id.
static func from_id(monster_id: String, db: ContentDB) -> MonsterCombatStats:
	var m := db.monster(monster_id)
	if m.is_empty():
		push_error("[MonsterCombatStats] unknown monster id %s" % monster_id)
	return from_monster(m, String(CombatRules.of(db).adaptation("monster_knockback").get("hit_animation_clip", "hit1")))
