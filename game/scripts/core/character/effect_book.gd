class_name EffectBook
extends RefCounted
## Timed effects and skill cooldowns on a CharacterState, as pure rules (no scene tree, no events). Both are kept as
## REMAINING seconds of game time, never absolute clock times, so they survive a save and a restart exactly
## (contract C3; Game.clock restarts at 0 every process):
##
##   CharacterState.effects    [{"id", "source", "remaining_s", "data": {...}}]
##   CharacterState.cooldowns  {skill_id: remaining_s}
##
## An effect's "data" may carry:
##   "bonuses": {stat key: number}            read by StatCalculator.effect_bonuses (Nimble Feet: {"speed": 10})
##   "hp_total", "duration_s", "tick_s",      a heal over time (Recovery): `hp_total` spread over equal ticks every
##   "ticks_done"                             `tick_s` (heal_for_tick); ticks_done is saved, so a reload never heals a
##                                            tick twice. tick_s 0 = one heal when the effect ends.
##   "skill_id", "level"                      what made it (display)
## tick() advances everything and reports what happened; the runtime (EffectTicker) applies the heals through
## Game.change_hp and announces stat changes, so this stays testable. Anything the save hands back in another shape
## (a non-Dictionary, a missing or non-numeric remaining_s, an old "until" entry) is dropped on the next tick.
## One entry per effect id: adding an id that is active replaces it (a re-cast restarts it).


## The effect with this id, or {} when none is active.
static func find(c: CharacterState, effect_id: String) -> Dictionary:
	if c == null:
		return {}
	for e in c.effects:
		if e is Dictionary and String((e as Dictionary).get("id", "")) == effect_id:
			return e
	return {}


static func has(c: CharacterState, effect_id: String) -> bool:
	return not find(c, effect_id).is_empty()


## Seconds left on an effect (0 when it is not active).
static func remaining(c: CharacterState, effect_id: String) -> float:
	return remaining_of(find(c, effect_id))


## Adds an effect (replacing any active one with the same id). `remaining_s` > 0. Returns the stored entry.
static func add(c: CharacterState, effect_id: String, source: String, remaining_s: float, data: Dictionary = {}) -> Dictionary:
	remove(c, effect_id)
	var e := {"id": effect_id, "source": source, "remaining_s": maxf(0.0, remaining_s), "data": data.duplicate(true)}
	c.effects.append(e)
	return e


## Removes the effect with this id. Returns true when one was active.
static func remove(c: CharacterState, effect_id: String) -> bool:
	if c == null:
		return false
	for i in range(c.effects.size() - 1, -1, -1):
		var e: Variant = c.effects[i]
		if e is Dictionary and String((e as Dictionary).get("id", "")) == effect_id:
			c.effects.remove_at(i)
			return true
	return false


## Ends every effect whose source starts with `source_prefix` ("" = all). Returns the removed entries.
static func clear(c: CharacterState, source_prefix: String = "") -> Array:
	var removed: Array = []
	if c == null:
		return removed
	var keep: Array = []
	for e in c.effects:
		if e is Dictionary and String((e as Dictionary).get("source", "")).begins_with(source_prefix):
			removed.append(e)
		else:
			keep.append(e)
	c.effects = keep
	return removed


## Seconds left on a skill's cooldown (0 = ready).
static func cooldown_left(c: CharacterState, skill_id: String) -> float:
	if c == null:
		return 0.0
	var v: Variant = c.cooldowns.get(skill_id, 0.0)
	return maxf(0.0, float(v)) if (v is int or v is float) else 0.0


## Starts (or restarts) a cooldown of `seconds`; 0 or less clears it.
static func start_cooldown(c: CharacterState, skill_id: String, seconds: float) -> void:
	if seconds > 0.0:
		c.cooldowns[skill_id] = seconds
	else:
		c.cooldowns.erase(skill_id)


## True when any effect carries stat bonuses (a change to such an effect changes derived stats).
static func has_bonuses(e: Variant) -> bool:
	if not (e is Dictionary):
		return false
	var data: Variant = (e as Dictionary).get("data", {})
	if data is Dictionary and (data as Dictionary).get("bonuses", null) is Dictionary:
		return not ((data as Dictionary)["bonuses"] as Dictionary).is_empty()
	return (e as Dictionary).get("bonuses", null) is Dictionary


## An entry's remaining seconds (0 for a malformed entry).
static func remaining_of(e: Variant) -> float:
	if not (e is Dictionary):
		return 0.0
	var v: Variant = (e as Dictionary).get("remaining_s", null)
	return maxf(0.0, float(v)) if (v is int or v is float) else 0.0


## HP healed by tick `k` (1-based) of `n` equal ticks of a `total`: floor(total k / n) - floor(total (k - 1) / n), so
## the n ticks sum to exactly `total` (24 over 6 ticks: 4 each).
static func heal_for_tick(total: int, n: int, k: int) -> int:
	if n <= 0 or k < 1 or k > n:
		return 0
	@warning_ignore("integer_division")
	return (total * k) / n - (total * (k - 1)) / n


## The number of heal ticks an effect of `duration_s` with ticks every `tick_s` makes (the last one as it ends);
## 1 when tick_s is 0 (one heal at the end).
static func tick_count(duration_s: float, tick_s: float) -> int:
	if tick_s <= 0.0 or duration_s <= 0.0:
		return 1
	return maxi(1, int(floor(duration_s / tick_s + 1e-6)))


## Advances every effect and cooldown by `dt` seconds of game time. Heal ticks that fall due are counted (data
## ticks_done advances) and their HP is summed in "heal"; expired effects are removed. Returns
## {"heal": int, "expired": [entries], "bonuses_changed": bool, "dropped": int (malformed entries removed)}.
static func tick(c: CharacterState, dt: float) -> Dictionary:
	var out := {"heal": 0, "expired": [], "bonuses_changed": false, "dropped": 0}
	if c == null or dt < 0.0:
		return out
	var keep: Array = []
	for e in c.effects:
		if not (e is Dictionary) or not (((e as Dictionary).get("remaining_s", null) is int) or ((e as Dictionary).get("remaining_s", null) is float)):
			out["dropped"] = int(out["dropped"]) + 1
			if has_bonuses(e):
				out["bonuses_changed"] = true
			continue
		var entry: Dictionary = e
		var left := maxf(0.0, float(entry["remaining_s"]) - dt)
		entry["remaining_s"] = left
		out["heal"] = int(out["heal"]) + _due_heal(entry)
		if left <= 0.0:
			(out["expired"] as Array).append(entry)
			if has_bonuses(entry):
				out["bonuses_changed"] = true
		else:
			keep.append(entry)
	c.effects = keep
	for sid in c.cooldowns.keys():
		var left := cooldown_left(c, String(sid)) - dt
		if left <= 0.0:
			c.cooldowns.erase(sid)
		else:
			c.cooldowns[sid] = left
	return out


## The HP of the heal ticks that are due on a heal-over-time entry (after its remaining_s was lowered), marking them
## done. 0 for an effect without a heal.
static func _due_heal(entry: Dictionary) -> int:
	var data: Variant = entry.get("data", null)
	if not (data is Dictionary) or not (data as Dictionary).has("hp_total"):
		return 0
	var d: Dictionary = data
	var total := int(d.get("hp_total", 0))
	var duration := float(d.get("duration_s", 0.0))
	var tick_s := float(d.get("tick_s", 0.0))
	var n := tick_count(duration, tick_s)
	var elapsed := duration - remaining_of(entry)
	var due := n
	if remaining_of(entry) > 0.0:
		due = 0 if tick_s <= 0.0 else mini(n, int(floor(elapsed / tick_s + 1e-6)))
	var done := clampi(int(d.get("ticks_done", 0)), 0, n)
	var heal := 0
	for k in range(done + 1, due + 1):
		heal += heal_for_tick(total, n, k)
	d["ticks_done"] = maxi(done, due)
	return heal
