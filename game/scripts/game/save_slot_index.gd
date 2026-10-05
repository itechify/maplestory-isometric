class_name SaveSlotIndex
extends RefCounted
## Pure helpers over Saves.list_saves() entries for the title screen and the shell: which slot Continue loads, and
## which slot a new game is written to (never an existing one, so New Game cannot overwrite a save).

## New games go to "<prefix><n>" with the smallest n >= 1 that has no save and no backup.
const NEW_SLOT_PREFIX := "slot"


## The most recently written loadable slot ("" when none): highest modified_unix, ties by slot name.
static func continue_slot(entries: Array) -> String:
	var best := ""
	var best_t := -1
	for e: Variant in entries:
		if not (e is Dictionary) or not bool((e as Dictionary).get("ok", false)):
			continue
		var t := int((e as Dictionary).get("modified_unix", 0))
		var s := String((e as Dictionary).get("slot", ""))
		if t > best_t or (t == best_t and s < best):
			best = s
			best_t = t
	return best


## The entry for `slot` ({} when absent).
static func entry(entries: Array, slot: String) -> Dictionary:
	for e: Variant in entries:
		if e is Dictionary and String((e as Dictionary).get("slot", "")) == slot:
			return e
	return {}


## The first free "slot<n>" (an unreadable save or a lone backup also occupies its slot).
static func next_free_slot(entries: Array) -> String:
	var taken := {}
	for e: Variant in entries:
		if e is Dictionary:
			taken[String((e as Dictionary).get("slot", ""))] = true
	var n := 1
	while taken.has("%s%d" % [NEW_SLOT_PREFIX, n]):
		n += 1
	return "%s%d" % [NEW_SLOT_PREFIX, n]


## True when `slot` is listed and loadable.
static func is_loadable(entries: Array, slot: String) -> bool:
	return bool(entry(entries, slot).get("ok", false))
