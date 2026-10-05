class_name SkillBook
extends RefCounted
## Pure skill rules over a CharacterState (no scene tree, no events): learning with SP and whether a skill may be cast
## now. CharacterState.skills holds {skill_id: level} and CharacterState.sp the unspent points (contract C3).
##
## Learning (MeowDB's Beginner rules, formulas/beginner.json): one SP buys one level; a skill stops at its canonical
## max_level (3 for every Beginner skill); prerequisites come from the record (the Beginner skills have none). SP is
## never refunded: MeowDB documents no way to take a point back ("You place every AP and SP by hand").
## SP itself is granted by Progression (1 per level-up at levels 2-10, 9 in total).
##
## Casting: check_cast() tests what the character and the position decide (learned, cast position, cooldown, MP, the
## shell item). Whether the player can act at all (alive, no modal, not mid-attack) is the runtime's question
## (PlayerSkills). Every refusal names a code below, so the UI can say why.

const OK := "ok"
const UNKNOWN_SKILL := "unknown_skill"
const NO_SP := "no_sp"
const MAX_LEVEL := "max_level"
const PREREQUISITE := "prerequisite_missing"
const NOT_LEARNED := "not_learned"
const POSITION := "wrong_position"
const COOLDOWN := "cooldown"
const NO_MP := "not_enough_mp"
const NO_ITEM := "no_item"
## Runtime refusals (PlayerSkills): dead, input held (modal, warp, knockback), an attack or cast in progress.
const DEAD := "dead"
const BUSY := "busy"
const UNAVAILABLE := "unavailable"


## The level the character has in a skill (0 = not learned).
static func level_of(c: CharacterState, skill_id: String) -> int:
	if c == null:
		return 0
	var v: Variant = c.skills.get(skill_id, 0)
	return maxi(0, int(v)) if (v is int or v is float) else 0


## {ok, code, skill_id, level (current), next_level} for spending one SP on `skill_id`.
static func can_learn(c: CharacterState, skill_id: String, db: ContentDB) -> Dictionary:
	var def := SkillDef.of(skill_id, db)
	var level := level_of(c, skill_id)
	var out := {"ok": false, "code": OK, "skill_id": skill_id, "level": level, "next_level": level + 1}
	if c == null or def == null or not (def in SkillDef.catalog(c.job, db)):
		out["code"] = UNKNOWN_SKILL
		return out
	if level >= def.max_level:
		out["code"] = MAX_LEVEL
		return out
	if c.sp <= 0:
		out["code"] = NO_SP
		return out
	for p in def.prerequisites:
		if p is Dictionary:
			var need_id := ItemDef.id_of((p as Dictionary).get("skill_id", ""))
			var need_lv := int((p as Dictionary).get("level", 1))
			if level_of(c, need_id) < need_lv:
				out["code"] = PREREQUISITE
				out["requires"] = {"skill_id": need_id, "level": need_lv}
				return out
	out["ok"] = true
	return out


## Spends one SP on a skill. Returns can_learn()'s result; on success "level" is the new level and "sp" the SP left.
static func learn(c: CharacterState, skill_id: String, db: ContentDB) -> Dictionary:
	var res := can_learn(c, skill_id, db)
	if not res.ok:
		return res
	c.sp -= 1
	c.skills[skill_id] = int(res.next_level)
	res["level"] = int(res.next_level)
	res["sp"] = c.sp
	return res


## The costs of one cast at a level: {"mp", "item_id", "item_qty"} ("" / 0 when no item).
static func costs(def: SkillDef, level: int) -> Dictionary:
	var item := def.item_cost(level) if def != null else {}
	return {"mp": def.mp_cost(level) if def != null else 0, "item_id": String(item.get("item_id", "")),
		"item_qty": int(item.get("qty", 0))}


## Whether the character may cast a skill from `position` ("ground", "air", "rope"): {ok, code, skill_id, level,
## def, mp, item_id, item_qty, cooldown_left}. Checked in this order: known, learned, position, cooldown, MP, item.
static func check_cast(c: CharacterState, skill_id: String, db: ContentDB, position: String) -> Dictionary:
	var def := SkillDef.of(skill_id, db)
	var level := level_of(c, skill_id)
	var out := {"ok": false, "code": OK, "skill_id": skill_id, "level": level, "def": def, "mp": 0, "item_id": "",
		"item_qty": 0, "cooldown_left": 0.0}
	if c == null or def == null:
		out["code"] = UNKNOWN_SKILL
		return out
	if level <= 0:
		out["code"] = NOT_LEARNED
		return out
	level = mini(level, def.max_level)
	out["level"] = level
	out.merge(costs(def, level), true)
	if not def.can_cast_from(position):
		out["code"] = POSITION
		return out
	var left := EffectBook.cooldown_left(c, skill_id)
	out["cooldown_left"] = left
	if left > 0.0:
		out["code"] = COOLDOWN
		return out
	if c.mp < int(out.mp):
		out["code"] = NO_MP
		return out
	if String(out.item_id) != "" and c.inventory.count(String(out.item_id)) < int(out.item_qty):
		out["code"] = NO_ITEM
		return out
	out["ok"] = true
	return out


## True when the character could cast the skill from the ground right now as far as MP and items go (the HUD greys a
## quickslot otherwise). Cooldowns are drawn separately.
static func affordable(c: CharacterState, skill_id: String, db: ContentDB) -> bool:
	var def := SkillDef.of(skill_id, db)
	var level := mini(level_of(c, skill_id), def.max_level if def != null else 0)
	if c == null or def == null or level <= 0:
		return false
	var k := costs(def, level)
	if c.mp < int(k.mp):
		return false
	return String(k.item_id) == "" or c.inventory.count(String(k.item_id)) >= int(k.item_qty)
