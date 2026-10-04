class_name DialogueRichText
extends RefCounted
## Turns DialogueText UI segments ({"text", "bold", "color", "ref"?, "icon"?}) into RichTextLabel BBCode, so canonical
## MeowDB text renders with its emphasis: bold stays bold, red stays red, and references are highlighted by kind
## (items blue, monsters dark red, NPCs green, maps amber, quests violet), bold, as MapleStory's chat window did.
## Text is escaped, so a "[" in canonical text can never become markup.

const RED := "#d0252b"
const REF_COLORS := {
	"item": "#2457b8",
	"monster": "#b0321e",
	"npc": "#2a7a35",
	"map": "#a35a00",
	"quest": "#7b3fb5",
}


## BBCode for a segment list. Empty segments fall back to `fallback_text` (escaped).
static func to_bbcode(segments: Array, fallback_text: String = "") -> String:
	if segments.is_empty():
		return escape(fallback_text)
	var out := PackedStringArray()
	for s: Variant in segments:
		if s is Dictionary:
			out.append(segment_bbcode(s))
		elif s is String:
			out.append(escape(s))
	return "".join(out)


## BBCode for one segment.
static func segment_bbcode(seg: Dictionary) -> String:
	var text := escape(String(seg.get("text", "")))
	if text.is_empty():
		return ""
	var bold := bool(seg.get("bold", false))
	var color := ""
	if String(seg.get("color", "")) == "red":
		color = RED
	elif String(seg.get("color", "")).begins_with("#") and Color.html_is_valid(String(seg.get("color"))):
		# Only a real "#rrggbb": anything else would be pasted into [color=...] as markup.
		color = String(seg.get("color"))
	var ref: Variant = seg.get("ref")
	if ref is Dictionary:
		var kind := String((ref as Dictionary).get("kind", ""))
		if REF_COLORS.has(kind):
			bold = true
			if color.is_empty():
				color = REF_COLORS[kind]
	if bold:
		text = "[b]%s[/b]" % text
	if not color.is_empty():
		text = "[color=%s]%s[/color]" % [color, text]
	return text


## Escapes BBCode: "[" -> "[lb]", "]" -> "[rb]" (in one pass, so the escapes are not escaped again).
static func escape(s: String) -> String:
	if not (s.contains("[") or s.contains("]")):
		return s
	var out := PackedStringArray()
	for ch in s:
		match ch:
			"[":
				out.append("[lb]")
			"]":
				out.append("[rb]")
			_:
				out.append(ch)
	return "".join(out)


## The plain text of a segment list (what a screen reader or a test reads).
static func plain(segments: Array, fallback_text: String = "") -> String:
	if segments.is_empty():
		return fallback_text
	var parts := PackedStringArray()
	for s: Variant in segments:
		parts.append(String((s as Dictionary).get("text", "")) if s is Dictionary else str(s))
	return "".join(parts)
