class_name InteractionResolver
extends RefCounted
## Pure: decides which one thing the player can interact with right now and the prompt that names its key, from a
## snapshot of the candidates (InteractionSystem gathers them from the world, the player and the loot system).
##
## The prompt must say what the key will really do, so the precedence mirrors the systems that act on the keys:
##   0. nothing while blocked (a modal is open, a warp is running, the player is dead or has no input) or climbing
##   1. a ladder/rope the player could grab: the controller grabs it on Up (or Down at the top) AND on interact,
##      before any other system sees the press, so it wins.                       "[Up] Climb" / "[Down] Climb down"
##   2. world.nearest_interactable(): an NPC in talk range or the portal the player stands in, whichever is nearer
##      (PortalInteractor uses the same call for interact).                         "[F] Talk to Roger"
##   3. the portal the player stands in (armed, pressable, visible): Up enters.  "[Up] Enter portal" (detail: the
##      destination's name). Hidden portals (type 1) work but show no prompt, as in classic.
##   4. the drop the pickup key would take (LootSystem.pickup_target).          "[Z] Pick up Snail Shell"
##
## Snapshot keys (all optional):
##   blocked: bool, climbing: bool
##   climbable: {} | {"at_top": bool}                         player.grabbable_climbable(); at_top = grabbed with Down
##   nearest:   {} | {"kind": "npc" | "portal", "id", "name", "distance", "shows_prompt", "detail"}
##   portal:    {} | {"id", "name", "detail", "shows_prompt"} portal_under_player()
##   drop:      {} | {"uid", "label"}                          LootSystem.pickup_target()
## Result: {} or {"kind": "climb"|"npc"|"portal"|"drop", "action": Controls action, "key": key label, "verb",
##          "target_id", "detail", "text": "[F] Talk to Roger"}.

const KIND_CLIMB := "climb"
const KIND_NPC := "npc"
const KIND_PORTAL := "portal"
const KIND_DROP := "drop"

const _CONTROLS := preload("res://scripts/autoload/controls.gd")


## The prompt for a snapshot (see the class comment). `key_label` maps an action to its key label (tests); empty =
## Controls.key_label.
static func resolve(snap: Dictionary, key_label: Callable = Callable()) -> Dictionary:
	if bool(snap.get("blocked", false)) or bool(snap.get("climbing", false)):
		return {}
	var climb := _dict(snap.get("climbable"))
	if not climb.is_empty():
		var at_top := bool(climb.get("at_top", false))
		return _make(KIND_CLIMB, &"climb_down" if at_top else &"portal_enter", "Climb down" if at_top else "Climb",
			String(climb.get("id", "")), "", key_label)
	var near := _dict(snap.get("nearest"))
	if String(near.get("kind", "")) == KIND_NPC:
		return _make(KIND_NPC, &"interact", "Talk to %s" % String(near.get("name", "")).strip_edges(),
			String(near.get("id", "")), String(near.get("detail", "")), key_label)
	var portal := _dict(snap.get("portal"))
	if portal.is_empty() and String(near.get("kind", "")) == KIND_PORTAL:
		portal = near
	if not portal.is_empty() and bool(portal.get("shows_prompt", true)):
		return _make(KIND_PORTAL, &"portal_enter", "Enter portal", String(portal.get("id", "")),
			String(portal.get("detail", portal.get("name", ""))), key_label)
	var drop := _dict(snap.get("drop"))
	if not drop.is_empty():
		return _make(KIND_DROP, &"pickup", "Pick up %s" % String(drop.get("label", "")).strip_edges(),
			String(drop.get("uid", "")), "", key_label)
	return {}


## True when the interact key (F) should start a conversation in this snapshot: exactly when the prompt is an NPC's.
## Every other use of interact (climb, portal) belongs to the controller and PortalInteractor.
static func interact_talks(snap: Dictionary) -> bool:
	return String(resolve(snap, func(_a: StringName) -> String: return "").get("kind", "")) == KIND_NPC


## The text shown in the prompt: "[F] Talk to Roger".
static func prompt_text(key: String, verb: String) -> String:
	return "[%s] %s" % [key, verb]


static func _make(kind: String, action: StringName, verb: String, target_id: String, detail: String,
		key_label: Callable) -> Dictionary:
	var key := String(key_label.call(action)) if key_label.is_valid() else _CONTROLS.key_label(String(action))
	return {"kind": kind, "action": String(action), "key": key, "verb": verb, "target_id": target_id,
		"detail": detail, "text": prompt_text(key, verb)}


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}
