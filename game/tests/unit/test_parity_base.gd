class_name ParityTestCase
extends TestCase
## Shared base for the MeowDB parity tests (test_parity_*.gd). Holds no tests itself.
##
## Loads game/tests/data/parity_vectors.json once (818 golden vectors computed by MeowDB's own calculators, see
## docs/canonical/oracles.md) and offers the comparisons oracles.md prescribes: exact for every integer the game
## displays or applies, ~1e-9 relative for floats (hit rates, milestones, untruncated damage, level scale), and
## averages through MeowDB's own 0.1 rounding.

const VECTORS_PATH := "res://tests/data/parity_vectors.json"
const REL_TOL := 1e-9

static var _vectors_doc: Dictionary = {}


## The whole parity document (keys: vectors, fixtures, discrepancies, ...).
func parity_doc() -> Dictionary:
	if _vectors_doc.is_empty():
		var text := FileAccess.get_file_as_string(VECTORS_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_vectors_doc = parsed
		else:
			fail("cannot read %s" % VECTORS_PATH)
	return _vectors_doc


## Every vector of a mechanic, in file order (fails the test when there are none).
func vectors(mechanic: String) -> Array:
	var out: Array = []
	for v in parity_doc().get("vectors", []):
		if String((v as Dictionary).get("mechanic", "")) == mechanic:
			out.append(v)
	if out.is_empty():
		fail("no parity vectors for mechanic %s" % mechanic)
	return out


## A fixture monster (parity_vectors.json fixtures.monsters) as combat stats.
func fixture_monster(monster_id: String) -> MonsterCombatStats:
	var m: Dictionary = (parity_doc().get("fixtures", {}) as Dictionary).get("monsters", {}).get(monster_id, {})
	var s := MonsterCombatStats.new()
	s.id = monster_id
	s.level = int(m.get("level", 1))
	s.hp = int(m.get("hp", 0))
	s.avoid = int(m.get("avoid", 0))
	s.pdef = int(m.get("pdef", 0))
	s.mdef = int(m.get("mdef", 0))
	s.acc = int(m.get("acc", 0))
	s.pdmg = int(m.get("pdmg", 0))
	s.mdmg = int(m.get("mdmg", 0))
	s.element_raw = String(m.get("element", ""))
	s.boss = bool(m.get("boss", false))
	return s


## A target built from a dmg-simulator input "target" block ({level, pdef, mdef, element, avoid, boss}).
func sim_target(t: Variant) -> MonsterCombatStats:
	if not t is Dictionary:
		return null
	var s := MonsterCombatStats.new()
	s.level = int(t.get("level", 1))
	s.hp = int(t.get("hp", 0))
	s.pdef = int(t.get("pdef", 0))
	s.mdef = int(t.get("mdef", 0))
	s.avoid = int(t.get("avoid", 0))
	s.element_raw = String(t.get("element", ""))
	s.boss = bool(t.get("boss", false))
	return s


## A PlayerCombatStats from a dmg-simulator damage input (primary/secondary given directly by MeowDB's oracle).
## The weapon comes from the vector's weapon_item_id; primary and secondary are pinned to the oracle's values.
func sim_attacker(inp: Dictionary, weapon_item_id: String) -> PlayerCombatStats:
	var s := PlayerCombatStats.new()
	s.level = int(inp.get("level", 1))
	s.weapon = WeaponProfile.for_weapon_id(weapon_item_id, db())
	# Pin primary/secondary exactly: put the oracle's numbers on the weapon's first stat keys.
	s.totals = {"str": 0, "dex": 0, "int": 0, "luk": 0}
	var pk: String = s.weapon.primary_stats[0]
	s.totals[pk] = int(inp.get("primary", 0))
	if s.weapon.secondary_stats.size() > 0:
		var sk: String = s.weapon.secondary_stats[0]
		s.totals[sk] = int(s.totals.get(sk, 0)) + int(inp.get("secondary", 0))
	s.total_watk = int(inp.get("baseWatk", 0)) + int(inp.get("extraWatk", 0))
	s.attack_power = int(inp.get("bonusAp", 0))
	s.mastery_level = int(inp.get("masteryLvl", 0))
	var cr: Variant = inp.get("critRateOverride", null)
	var cd: Variant = inp.get("critDamageOverride", null)
	s.crit_rate = (float(cr) if cr != null else CombatFormula.base_crit_rate(db()) * 100.0) / 100.0
	s.crit_damage = (float(cd) if cd != null else CombatFormula.base_crit_damage(db()) * 100.0) / 100.0
	return s


## |actual - expected| within REL_TOL relative (absolute near 0).
func assert_rel(actual: float, expected: float, msg: String = "") -> void:
	var tol := REL_TOL * maxf(1.0, absf(expected))
	if is_inf(expected) or is_inf(actual):
		if not (is_inf(expected) and is_inf(actual)):
			fail("%s expected %s got %s" % [msg, expected, actual])
		return
	if absf(actual - expected) > tol:
		fail("%s expected %s got %s (diff %s)" % [msg, expected, actual, actual - expected])


## Recursive equality where JSON floats and GDScript ints compare by value (dictionaries need the same keys).
func assert_same_data(actual: Variant, expected: Variant, msg: String = "") -> void:
	if not _same_data(actual, expected):
		fail("%s expected %s got %s" % [msg, JSON.stringify(expected), JSON.stringify(actual)])


func _same_data(a: Variant, e: Variant) -> bool:
	if _is_num(a) and _is_num(e):
		return float(a) == float(e)
	if a is Dictionary and e is Dictionary:
		if (a as Dictionary).size() != (e as Dictionary).size():
			return false
		for k in e:
			if not (a as Dictionary).has(k) or not _same_data(a[k], e[k]):
				return false
		return true
	if a is Array and e is Array:
		if (a as Array).size() != (e as Array).size():
			return false
		for i in (e as Array).size():
			if not _same_data(a[i], e[i]):
				return false
		return true
	return typeof(a) == typeof(e) and a == e


## MeowDB display rounding for /formulas calculator strings (toLocaleString, half away from zero, 0 decimals).
func display_round(x: float) -> String:
	var n := int(roundf(x))
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out
