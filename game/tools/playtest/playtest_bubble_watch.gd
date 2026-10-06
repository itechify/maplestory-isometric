class_name PlaytestBubbleWatch
extends RefCounted
## NPC speech bubbles around an open window, by waiting only (#40; docs/runtime/PLAYTEST_HARNESS.md "The
## clean-character playthrough"). A bubble cannot be forced in a strict run, so the watch reads each NPC's bubble
## schedule (NpcPresenter.bubbles, NpcBubbleSchedule.until_next) to know how long to wait, and waits at most that long:
##
##   wait_shown(d)    a bubble shows on some NPC, at most until the next one falls due (before a shop opens, after it
##                    closes: the NPCs chatter at all)
##   watch_quiet(d)   while a window stays open, until a bubble falls due for an NPC that could show it (on the current
##                    map and on screen: its name tag shows, which a window does not change; not in a conversation,
##                    whose own rule hides it), checking every frame that no bubble shows. NpcBubbleSchedule skips a
##                    bubble that falls due while the NPC may not show it and schedules the next one, so the jump of
##                    until_next is the moment a bubble would have shown: without the window rule it shows that frame
##
## A dialogue hides every bubble too (any modal window does), so a bubble showing before the shop opens is gone before
## the shop is: only a bubble that falls due while the shop is open proves the shop hides it. The watch only reads
## presenters; it never calls into them.

## Seconds past the next due a wait allows (frames and rounding).
const MARGIN_S := 1.0
## A jump of until_next larger than this is a bubble falling due (the schedule's intervals are 14-26 s).
const ROLLOVER_S := 1.0

## npc id -> sample row (see sample()) of the last feed().
var _last: Dictionary = {}
## The NPCs whose bubble fell due while they could show one, with the game time.
var due: Array = []
## The bubbles seen while watching: [{"npc", "at_s", "text"}].
var shown: Array = []


## The live NPC presenters (npc id -> NpcPresenter) of the interaction system, {} without one.
static func presenters(d: PlaytestDriver) -> Dictionary:
	var sys := d.interaction()
	var p: Variant = sys.get("presenters") if sys != null else null
	return p if p is Dictionary else {}


## One look at every presenter with a bubble schedule: npc id -> {"visible" (its bubble shows), "on_screen" (its name
## tag shows), "talking" (in a conversation with the player), "until_next" (seconds until its next bubble falls due),
## "text" (the bubble's line)}.
static func sample(ps: Dictionary) -> Dictionary:
	var out := {}
	for id: Variant in ps:
		var p: Variant = ps[id]
		if not (p is NpcPresenter) or not is_instance_valid(p):
			continue
		var np := p as NpcPresenter
		if np.bubble == null or not is_instance_valid(np.bubble) or np.bubbles == null:
			continue
		out[String(id)] = {"visible": np.bubble.visible, "on_screen": np.tag != null and is_instance_valid(np.tag)
			and np.tag.visible, "talking": np.is_talking(), "until_next": np.bubbles.until_next, "text": np.bubble.text}
	return out


## Seconds until the next bubble falls due for an NPC that could show it (on screen, not talking); -1 when none can.
static func next_due(s: Dictionary) -> float:
	var best := -1.0
	for id: String in s:
		var r: Dictionary = s[id]
		if bool(r["on_screen"]) and not bool(r["talking"]) and (best < 0.0 or float(r["until_next"]) < best):
			best = maxf(0.0, float(r["until_next"]))
	return best


## The NPCs whose bubble shows in a sample.
static func visible_in(s: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in s:
		if bool(s[id]["visible"]):
			out.append(id)
	return out


## Takes one sample at game time `at_s`: records every bubble that shows and every bubble that fell due (until_next
## jumped up) for an NPC that was on screen and not talking in this sample and the one before.
func feed(s: Dictionary, at_s: float) -> void:
	for id: String in s:
		var r: Dictionary = s[id]
		if bool(r["visible"]):
			shown.append({"npc": id, "at_s": snappedf(at_s, 0.01), "text": String(r["text"])})
		var l: Dictionary = _last.get(id, {})
		if l.is_empty() or float(r["until_next"]) <= float(l["until_next"]) + ROLLOVER_S:
			continue
		if bool(r["on_screen"]) and bool(l["on_screen"]) and not bool(r["talking"]) and not bool(l["talking"]):
			due.append({"npc": id, "at_s": snappedf(at_s, 0.01)})
	_last = s


## A bubble fell due for an NPC that could show it.
func proven() -> bool:
	return not due.is_empty()


## The verdict of watch_quiet: proven, and no bubble showed.
func quiet() -> bool:
	return proven() and shown.is_empty()


## Waits until a bubble shows on some NPC, at most until the next bubble falls due for an NPC that could show it
## (plus MARGIN_S). Returns {"ok", "npc", "text", "waited_s", "bound_s", "why"}. Await it.
static func wait_shown(d: PlaytestDriver) -> Dictionary:
	var s := sample(presenters(d))
	var bound := next_due(s)
	var out := {"ok": false, "npc": "", "text": "", "waited_s": 0.0, "bound_s": bound, "why": ""}
	if s.is_empty() or (bound < 0.0 and visible_in(s).is_empty()):
		out["why"] = "no NPC on screen could show a bubble (%d with a schedule)" % s.size()
		return out
	bound += MARGIN_S
	out["bound_s"] = snappedf(bound, 0.01)
	var t0 := d.game_s()
	while visible_in(s).is_empty() and d.game_s() - t0 <= bound:
		await d.frames(1)
		s = sample(presenters(d))
	var v := visible_in(s)
	out["waited_s"] = snappedf(d.game_s() - t0, 0.01)
	out["ok"] = not v.is_empty()
	if out["ok"]:
		out["npc"] = v[0]
		out["text"] = String(s[v[0]]["text"])
	else:
		out["why"] = "no bubble within %.1f s (the next one was due by then)" % bound
	return out


## While a window stays open: watches every frame until a bubble falls due for an NPC that could show it (at most that
## due plus MARGIN_S), recording any bubble that shows. Returns {"ok" (a bubble fell due and none showed), "proven",
## "due", "shown", "waited_s", "bound_s", "why"}. Await it.
static func watch_quiet(d: PlaytestDriver) -> Dictionary:
	var w := PlaytestBubbleWatch.new()
	var s := sample(presenters(d))
	var bound := next_due(s)
	var t0 := d.game_s()
	w.feed(s, 0.0)
	if bound >= 0.0:
		bound += MARGIN_S
		while not w.proven() and d.game_s() - t0 <= bound:
			await d.frames(1)
			w.feed(sample(presenters(d)), d.game_s() - t0)
	var out := {"ok": w.quiet(), "proven": w.proven(), "due": w.due.duplicate(), "shown": w.shown.duplicate(),
		"waited_s": snappedf(d.game_s() - t0, 0.01), "bound_s": snappedf(bound, 0.01), "why": ""}
	if bound < 0.0:
		out["why"] = "no NPC on screen could show a bubble (%d with a schedule)" % s.size()
	elif not w.proven():
		out["why"] = "no bubble fell due within %.1f s" % bound
	elif not w.shown.is_empty():
		out["why"] = "a bubble showed while the window was open: %s" % [w.shown[0]]
	return out
