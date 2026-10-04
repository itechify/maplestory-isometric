class_name NpcDef
extends RefCounted
## One NPC: canonical identity and relationships from MeowDB (data/canonical/npcs/<id>.json) plus optional MisoStory
## presentation hints (data/misostory/npcs/<id>.json). Built by NpcCatalog. The 3D placement is not here: the world
## system takes it from the Blender NPC markers (MAP_ARCHITECTURE.md §3.3, §4.7.5); `position_px` is the canonical
## MapleStory map position for reference and validation.
##
## Interaction behaviours are derived from the data (MeowDB has no "interaction type" field, docs/canonical/npcs.md):
##   "quest"     the NPC starts or completes quests
##   "shop"      the NPC has a shop block (opens data/canonical/shops/<shop_id>.json)
##   "transport" the NPC has transport routes (Shanks)
##   "talk"      always: default dialogue / idle chatter
## An adaptation file may disable behaviours ("disabled_behaviors") with a reason.

var id: String = ""
var name: String = ""
## MeowDB 9-digit map id of the (single) location.
var map_id: String = ""
var map_name: String = ""
## MapleStory map px, y down, same frame as the map's portals (convert only through WorldScale).
var position_px: Vector2 = Vector2.ZERO
## MeowDB role tags: "Quest Giver", "Townsfolk", "Transport", "Shopkeeper".
var roles: PackedStringArray = []
## Shopkeeper subtitle ("Armor Seller", ...), "" otherwise.
var function_title: String = ""
## Quest ids started / completed by this NPC (derived from the quest pages).
var quests_started: PackedStringArray = []
var quests_completed: PackedStringArray = []
## Canonical shop id (data/canonical/shops/<shop_id>.json), "" when not a shopkeeper.
var shop_id: String = ""
## Canonical transport block ({routes: [...]}) or {}.
var transport: Dictionary = {}
## "What <name> Says" lines and the speech-bubble pool, as canonical line dictionaries.
var dialogue_lines: Array = []
var idle_chatter: Array = []
## Behaviours in a fixed order (quest, shop, transport, talk), after adaptation overrides.
var behaviors: PackedStringArray = []
## UI portrait key: adaptation "portrait", else "npc_<id>". Portrait art is MisoStory's own (MeowDB art is not stored).
var portrait: String = ""
## Free-form visual hints for the actor/scene layer (model, scale, facing, ...), from the adaptation file.
var visual: Dictionary = {}
var record: Dictionary = {}
var adaptation: Dictionary = {}


static func from_records(rec: Dictionary, adapt: Dictionary = {}) -> NpcDef:
	var n := NpcDef.new()
	n.record = rec
	n.adaptation = adapt
	n.id = QuestJson.s(rec.get("id"))
	n.name = QuestJson.s(rec.get("name"))
	var locs := QuestJson.arr(rec.get("locations"))
	if not locs.is_empty():
		var loc := QuestJson.dict(locs[0])
		n.map_id = QuestJson.s(loc.get("map_id"))
		n.map_name = QuestJson.s(loc.get("map_name"))
		n.position_px = Vector2(QuestJson.f(loc.get("x_px")), QuestJson.f(loc.get("y_px")))
	n.roles = QuestJson.strings(rec.get("roles"))
	n.function_title = QuestJson.s(rec.get("function_title"))
	var q := QuestJson.dict(rec.get("quests"))
	n.quests_started = QuestJson.strings(q.get("started_here"))
	n.quests_completed = QuestJson.strings(q.get("completed_here"))
	n.shop_id = QuestJson.s(QuestJson.dict(rec.get("shop")).get("shop_id"))
	n.transport = QuestJson.dict(rec.get("transport"))
	n.dialogue_lines = QuestJson.arr(rec.get("dialogue"))
	n.idle_chatter = QuestJson.arr(rec.get("idle_chatter"))
	var disabled := QuestJson.strings(adapt.get("disabled_behaviors"))
	var all := PackedStringArray()
	if not n.quests_started.is_empty() or not n.quests_completed.is_empty():
		all.append("quest")
	if not n.shop_id.is_empty():
		all.append("shop")
	if not QuestJson.arr(n.transport.get("routes")).is_empty():
		all.append("transport")
	all.append("talk")
	for bh in all:
		if not (bh in disabled):
			n.behaviors.append(bh)
	n.portrait = QuestJson.s(adapt.get("portrait"), "npc_" + n.id)
	n.visual = QuestJson.dict(adapt.get("visual"))
	return n


func has_behavior(behavior: String) -> bool:
	return behavior in behaviors


## Idle-chatter line `index` as UI text ({"text", "segments", "source"}) for speech bubbles; MeowDB gives no
## interval or order, so the caller picks the line.
func idle_line(index: int) -> Dictionary:
	if index < 0 or index >= idle_chatter.size():
		return {"text": "", "segments": [], "source": ""}
	var out := DialogueText.normalize_line(idle_chatter[index])
	out["source"] = "canonical/npcs/%s.json#idle_chatter[%d]" % [id, index]
	return out


## Every quest this NPC is involved in (started or completed here), sorted and unique.
func all_quests() -> PackedStringArray:
	var out := PackedStringArray()
	for q in quests_started + quests_completed:
		if not (q in out):
			out.append(q)
	out.sort()
	return out
