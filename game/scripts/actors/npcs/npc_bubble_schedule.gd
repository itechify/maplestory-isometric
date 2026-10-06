class_name NpcBubbleSchedule
extends RefCounted
## When an NPC shows its next speech bubble and which canonical idle-chatter line it says. Pure and deterministic: a
## per-NPC RandomNumberGenerator seeded from the NPC id, timing from data/misostory/npcs/_speech_bubbles.json (an
## adaptation: MeowDB has the lines but no timing). NpcPresenter ticks it every frame.
##
##   var s := NpcBubbleSchedule.new("12", 3, config)
##   var line := s.tick(delta, eligible)   # >= 0: a new bubble starts now with idle_chatter[line]
##   s.is_showing()                        # the current bubble is still up
##
## A bubble that falls due while the NPC is not eligible (off the current map, off screen, in a conversation) is
## skipped and the next one is scheduled; a conversation hides the current bubble (hide_now).

const CONFIG_ID := "_speech_bubbles"
## Used when the adaptation file is absent.
const DEFAULTS := {"first_delay_min_s": 2.0, "first_delay_max_s": 10.0, "interval_min_s": 14.0,
	"interval_max_s": 26.0, "display_s": 5.0, "order": "sequential"}

var line_count: int = 0
var config: Dictionary = {}
var rng := RandomNumberGenerator.new()
## Seconds until the next bubble is due.
var until_next: float = 0.0
## Seconds the current bubble stays up (0 = none).
var showing_left: float = 0.0
## The line shown last (-1 = none yet).
var current_line: int = -1
var _next_line: int = 0


func _init(npc_id: String = "", p_line_count: int = 0, p_config: Dictionary = {}) -> void:
	line_count = maxi(0, p_line_count)
	config = DEFAULTS.duplicate()
	for k: Variant in p_config:
		if DEFAULTS.has(str(k)):
			config[str(k)] = p_config[k]
	rng.seed = hash("bubble:" + npc_id)
	_next_line = rng.randi_range(0, maxi(0, line_count - 1))
	until_next = _between("first_delay_min_s", "first_delay_max_s")


## The schedule for an NPC from content (its canonical idle_chatter count, the adaptation's timing).
static func for_npc(npc_id: String, db: ContentDB) -> NpcBubbleSchedule:
	var lines := 0
	var cfg := {}
	if db != null:
		lines = QuestJson.arr(db.npc(npc_id).get("idle_chatter")).size()
		cfg = db.miso_entity("npcs", CONFIG_ID)
	return NpcBubbleSchedule.new(npc_id, lines, cfg)


## Advances the clock. Returns the idle_chatter index of a bubble that starts now, or -1.
func tick(delta: float, eligible: bool) -> int:
	if line_count <= 0:
		return -1
	if showing_left > 0.0:
		showing_left = maxf(0.0, showing_left - delta)
	until_next -= delta
	if until_next > 0.0:
		return -1
	until_next = _between("interval_min_s", "interval_max_s")
	if not eligible:
		return -1
	current_line = _take_line()
	showing_left = float(config["display_s"])
	return current_line


func is_showing() -> bool:
	return showing_left > 0.0 and current_line >= 0


## Ends the current bubble at once (a conversation started).
func hide_now() -> void:
	showing_left = 0.0


func _take_line() -> int:
	if String(config["order"]) == "random":
		return rng.randi_range(0, line_count - 1)
	var l := _next_line % line_count
	_next_line = (l + 1) % line_count
	return l


func _between(lo_key: String, hi_key: String) -> float:
	var lo := float(config[lo_key])
	var hi := maxf(lo, float(config[hi_key]))
	return rng.randf_range(lo, hi)
