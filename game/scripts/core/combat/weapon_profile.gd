class_name WeaponProfile
extends RefCounted
## How one weapon (or bare hands) fights: stats it uses, action multipliers, ordinary-attack odds, speed and hit boxes.
##
## Every number comes from data:
##   damage.json        weapon_families (primary/secondary stat), weapon_action_multipliers, ordinary_action_odds
##   attack_styles.json hit-zone sets (boxes in px), per-weapon basic presentations, bare-hands presentations
##   attack_speed.json  speed tiers (via CombatFormula.attack_duration_ms)
##   items/<id>.json    W.ATK, attack speed tier, the weapon's own basic attacks
##   misostory/combat.json bare_hands (MeowDB documents no unarmed W.ATK, multiplier or speed)
## SUBTYPES below only joins MeowDB's item subtype names to the row keys of those tables; it holds no numbers.
##
## Boxes are px, [left, top, right, bottom] facing LEFT, y down, origin at the feet (attack_styles.json
## coordinate_convention); use CombatReach.mirror_box for a right-facing attacker and WorldScale.actor() for meters.

## item subtype -> damage.json row keys. "timing_stab" marks weapons whose stab uses the spear/polearm stab time.
const SUBTYPES: Dictionary = {
	"One-Handed Sword": {"multipliers": "one_handed_sword", "family": "sword_axe_blunt_spear_polearm", "odds": "one_handed_sword"},
	"Two-Handed Sword": {"multipliers": "two_handed_sword", "family": "sword_axe_blunt_spear_polearm", "odds": "two_handed_sword"},
	"One-Handed Axe": {"multipliers": "one_handed_axe_or_blunt", "family": "sword_axe_blunt_spear_polearm", "odds": "one_handed_axe_or_blunt"},
	"One-Handed Blunt Weapon": {"multipliers": "one_handed_axe_or_blunt", "family": "sword_axe_blunt_spear_polearm", "odds": "one_handed_axe_or_blunt"},
	"Two-Handed Axe": {"multipliers": "two_handed_axe_or_blunt", "family": "sword_axe_blunt_spear_polearm", "odds": "two_handed_axe_or_blunt"},
	"Two-Handed Blunt Weapon": {"multipliers": "two_handed_axe_or_blunt", "family": "sword_axe_blunt_spear_polearm", "odds": "two_handed_axe_or_blunt"},
	"Spear": {"multipliers": "spear", "family": "sword_axe_blunt_spear_polearm", "odds": "spear", "timing_stab": "spear_polearm_stab"},
	"Polearm": {"multipliers": "polearm", "family": "sword_axe_blunt_spear_polearm", "odds": "polearm", "timing_stab": "spear_polearm_stab"},
	"Dagger": {"multipliers": "dagger", "family": "dagger_claw", "odds": "dagger"},
	"Claw": {"multipliers": "bow_crossbow_claw", "family": "dagger_claw", "odds": "claw_close_range", "ranged": true, "timing_shoot": "swing"},
	"Bow": {"multipliers": "bow_crossbow_claw", "family": "bow_crossbow", "odds": "bow_close_range", "ranged": true, "timing_shoot": "bow_shot"},
	"Crossbow": {"multipliers": "bow_crossbow_claw", "family": "bow_crossbow", "odds": "crossbow_close_range", "ranged": true, "timing_shoot": "crossbow_shot"},
	"Wand": {"multipliers": "wand_staff_physical", "family": "wand_staff_physical", "odds": "wand_staff"},
	"Staff": {"multipliers": "wand_staff_physical", "family": "wand_staff_physical", "odds": "wand_staff"},
}
## attack_styles.json: the "level100" band replaces the listed presentations "from level 100".
const LEVEL100_BAND_MIN_LEVEL := 100

var item_id: String = ""
var name: String = ""
## MeowDB item subtype ("One-Handed Sword"), "" for bare hands.
var subtype: String = ""
var is_bare_hands: bool = false
## False when the item id was unknown or not a weapon (the profile then behaves as bare hands).
var valid: bool = true
## The weapon's own W.ATK line (Total Weapon Attack is the pool of every equipped line; see StatCalculator).
var watk: int = 0
var multiplier_row: String = ""
## action -> multiplier, or null when MeowDB marks the combination "Not used".
var multipliers: Dictionary = {}
var stat_family: String = ""
var primary_stats: PackedStringArray = []
var secondary_stats: PackedStringArray = []
## Ordinary close-range action odds {"swing": p, "stab": p} (damage.json ordinary_action_odds).
var odds: Dictionary = {}
## Bow, crossbow or claw: an ordinary attack at range is a projectile ("shoot").
var ranged: bool = false
var speed_tier: int = 0
var hitzone_set: String = ""
## presentation -> {"kind": "swing"|"stab"|"crouch", "label": String, "box": Rect2}
var presentations: Dictionary = {}
## presentation -> Rect2 for characters at LEVEL100_BAND_MIN_LEVEL and above (only where it differs).
var level100_boxes: Dictionary = {}
## kind -> PackedStringArray of the basic presentations of that kind ("swing", "stab", "crouch").
var basic_presentations: Dictionary = {}
var _timing_overrides: Dictionary = {}


## Profile of a canonical weapon item id; bare hands for "" (an unknown id logs an error and is bare hands).
## Cached per ContentDB: the returned profile is shared, so treat it as read-only (from_item builds a fresh one).
static func for_weapon_id(item_id: String, db: ContentDB) -> WeaponProfile:
	var cache := CombatRules.of(db).weapon_cache
	if cache.has(item_id):
		return cache[item_id]
	var p := bare_hands(db) if item_id == "" else from_item(item_id, db)
	cache[item_id] = p
	return p


static func from_item(item_id: String, db: ContentDB) -> WeaponProfile:
	var item := db.item(item_id)
	var weapon: Variant = item.get("weapon", null)
	if not weapon is Dictionary:
		push_error("[WeaponProfile] item %s is not a weapon" % item_id)
		var bare := bare_hands(db)
		bare.valid = false
		return bare
	var w: Dictionary = weapon
	var p := WeaponProfile.new()
	p.item_id = item_id
	p.name = String(item.get("name", ""))
	p.subtype = String(w.get("weapon_type", item.get("subtype", "")))
	var row: Dictionary = SUBTYPES.get(p.subtype, {})
	if row.is_empty():
		push_error("[WeaponProfile] no damage table row for weapon subtype '%s' (item %s)" % [p.subtype, item_id])
		p.valid = false
	var rules := CombatRules.of(db)
	p.multiplier_row = String(row.get("multipliers", ""))
	p.multipliers = (rules.action_multipliers.get(p.multiplier_row, {}) as Dictionary).duplicate()
	p.multipliers.erase("label")
	p._set_family(rules, String(row.get("family", "")))
	p.odds = (rules.action_odds.get(String(row.get("odds", "")), {}) as Dictionary).duplicate()
	p.ranged = bool(row.get("ranged", false))
	if row.has("timing_stab"):
		p._timing_overrides["stab"] = row["timing_stab"]
	if row.has("timing_shoot"):
		p._timing_overrides["shoot"] = row["timing_shoot"]
	p.speed_tier = int(w.get("attack_speed", 0))
	p.watk = int((item.get("stats", {}) as Dictionary).get("watk", 0))
	p._load_hitzones(db, w.get("basic_attacks", []))
	return p


## Bare hands: canonical presentations and action odds, MisoStory W.ATK / multiplier / speed (misostory/combat.json).
static func bare_hands(db: ContentDB) -> WeaponProfile:
	var rules := CombatRules.of(db)
	var adapt := rules.adaptation("bare_hands")
	var p := WeaponProfile.new()
	p.is_bare_hands = true
	p.name = "Bare hands"
	p.watk = int(adapt.get("weapon_watk", 0))
	p.multiplier_row = "bare_hands"
	var wm: float = float(adapt.get("weapon_mult", 0.0))
	p.multipliers = {"swing": wm, "stab": wm, "shoot": null, "mixed": wm}
	p.primary_stats = PackedStringArray([String(adapt.get("primary", ""))])
	p.secondary_stats = PackedStringArray([String(adapt.get("secondary", ""))])
	p.stat_family = "bare_hands"
	p.odds = (rules.action_odds.get("barehanded", {}) as Dictionary).duplicate()
	p.speed_tier = int(adapt.get("attack_speed_tier", 0))
	var styles := db.formula("attack_styles")
	var bh: Dictionary = styles.get("bare_hands", {})
	p.hitzone_set = String(bh.get("hitzone_set", ""))
	p._load_set_boxes(styles)
	for action_name in bh.get("basic_actions", []):
		p._add_basic(String(action_name), String((p.presentations.get(action_name, {}) as Dictionary).get("kind", "")))
	return p


## Multiplier of a damage action, or -1.0 when MeowDB marks it "Not used" for this weapon.
func multiplier(action: String) -> float:
	var v: Variant = multipliers.get(action, null)
	return -1.0 if v == null else float(v)


## The ordinary attack's damage actions with their probabilities. Ranged weapons shoot unless at close range.
func ordinary_actions(close_range: bool = true) -> Dictionary:
	if ranged and not close_range:
		return {"shoot": 1.0}
	var out := {}
	for action in ["swing", "stab"]:
		var pr: float = float(odds.get(action, 0.0))
		if pr > 0.0:
			out[action] = pr
	return out


## The basic presentations (hit-box names) that play for a damage action ("swing", "stab", "crouch").
func presentations_for(action: String) -> PackedStringArray:
	var kind := "crouch" if action == "crouch" else action
	return basic_presentations.get(kind, PackedStringArray())


## Hit box (px, facing left) of a presentation; the level-100 band replaces some boxes from that level on.
func hit_box_px(presentation: String, level: int = 1) -> Rect2:
	if level >= LEVEL100_BAND_MIN_LEVEL and level100_boxes.has(presentation):
		return level100_boxes[presentation]
	var pres: Dictionary = presentations.get(presentation, {})
	if pres.is_empty():
		push_error("[WeaponProfile] %s has no presentation %s" % [name, presentation])
		return Rect2()
	return pres["box"]


## attack_speed.json base action key for a damage action of this weapon.
func timing_action(action: String) -> String:
	if action == "crouch":
		return "crouched_attack"
	if _timing_overrides.has(action):
		return String(_timing_overrides[action])
	return "stab" if action == "stab" else "swing"


## Player-facing duration (ms) of one attack with this weapon's speed tier (tier_offset: e.g. a booster's shift).
func attack_duration_ms(action: String, db: ContentDB, tier_offset: int = 0) -> int:
	return CombatFormula.attack_duration_ms(speed_tier + tier_offset, timing_action(action), db)


## Total of the stats in `keys` from a totals dictionary ({"str": .., "dex": ..}).
static func sum_stats(keys: PackedStringArray, totals: Dictionary) -> float:
	var s := 0.0
	for k in keys:
		s += float(totals.get(k, 0))
	return s


# --- internals -------------------------------------------------------------------------------------------------

func _set_family(rules: CombatRules, family_key: String) -> void:
	stat_family = family_key
	var fam: Dictionary = rules.weapon_families.get(family_key, {})
	if fam.is_empty():
		push_error("[WeaponProfile] unknown weapon family '%s'" % family_key)
		return
	primary_stats = fam["primary"]
	secondary_stats = fam["secondary"]


## Picks the hit-zone set (attack_styles.json) and the weapon's basic presentations.
func _load_hitzones(db: ContentDB, item_basic: Array) -> void:
	var styles := db.formula("attack_styles")
	var sets: Dictionary = styles.get("hitzone_sets", {})
	# 1. attack_styles.json lists the starter weapons by item id.
	for bw in styles.get("beginner_weapons", []):
		if String((bw as Dictionary).get("item_id", "")) == item_id:
			hitzone_set = String(bw.get("hitzone_set", ""))
	# 2. Otherwise the set whose boxes equal the item page's basic attacks (MeowDB cross-checks these are equal),
	#    preferring the subtype family's primary set.
	var family_set := ""
	var fam_key := String((styles.get("weapon_subtype_to_hitzone_family", {}) as Dictionary).get(subtype, ""))
	if fam_key != "":
		family_set = String(((styles.get("hitzone_families", {}) as Dictionary).get(fam_key, {}) as Dictionary).get("primary_set", ""))
	if hitzone_set == "" and not item_basic.is_empty():
		var candidates: Array = [family_set] if family_set != "" else []
		for s in sets:
			if s != family_set:
				candidates.append(s)
		for s in candidates:
			if _set_matches(sets.get(s, {}), item_basic):
				hitzone_set = s
				break
	# 3. Otherwise the subtype family's primary set.
	if hitzone_set == "":
		hitzone_set = family_set
	_load_set_boxes(styles)
	if not item_basic.is_empty():
		for b in item_basic:
			var bd: Dictionary = b
			_add_basic(String(bd.get("action", "")), _kind(String(bd.get("kind", ""))))
	else:
		# No item page list: every presentation of the set except the Final Attack ones ("...F").
		for pres in presentations:
			if not String(pres).ends_with("F"):
				_add_basic(pres, String(presentations[pres]["kind"]))
	if presentations.is_empty():
		push_error("[WeaponProfile] no hit boxes for %s (%s)" % [name, subtype])


func _load_set_boxes(styles: Dictionary) -> void:
	var set_data: Dictionary = (styles.get("hitzone_sets", {}) as Dictionary).get(hitzone_set, {})
	var ordinary: Dictionary = set_data.get("ordinary", {})
	for pres in ordinary:
		var z: Dictionary = ordinary[pres]
		presentations[pres] = {"kind": _kind(String(z.get("kind", ""))), "label": String(z.get("label", "")), "box": _rect(z.get("box_px", []))}
	var lvl100: Dictionary = set_data.get("level100", {})
	for pres in lvl100:
		level100_boxes[pres] = _rect(lvl100[pres].get("box_px", []))


func _add_basic(pres: String, kind: String) -> void:
	if pres == "" or kind == "":
		return
	if not basic_presentations.has(kind):
		basic_presentations[kind] = PackedStringArray()
	var arr: PackedStringArray = basic_presentations[kind]
	if pres not in arr:
		arr.append(pres)
	basic_presentations[kind] = arr


static func _set_matches(set_data: Dictionary, item_basic: Array) -> bool:
	var ordinary: Dictionary = set_data.get("ordinary", {})
	if ordinary.is_empty():
		return false
	for b in item_basic:
		var bd: Dictionary = b
		var z: Dictionary = ordinary.get(String(bd.get("action", "")), {})
		if z.is_empty() or _rect(z.get("box_px", [])) != _rect(bd.get("box_px", [])):
			return false
	return true


## MeowDB kinds: hit-zone "thrust" and item-page "stab" are the stab action; "crouch" is the crouched attack.
static func _kind(k: String) -> String:
	return "stab" if k == "thrust" else k


## [left, top, right, bottom] -> Rect2(left, top, right - left, bottom - top).
static func _rect(box: Variant) -> Rect2:
	if not box is Array or (box as Array).size() != 4:
		return Rect2()
	var l := float(box[0])
	var t := float(box[1])
	return Rect2(l, t, float(box[2]) - l, float(box[3]) - t)
