class_name ProvenanceAuthorities
extends RefCounted
## The provenance authority registry (Iteration Three contract C7; decisions D3-1, D3-11 and D3-12 in
## docs/ITERATION_LOG.md): which sources may supply which property of the canonical data, and what each citation must
## carry. This table is the only place these rules live. ProvenanceChecks.check_source_object applies it to every
## source object:
##   - a record-level `provenance.<property>` block (any canonical domain, and game/data/misostory files)
##   - in a schema 3 drop record (contract C1): `entries[].membership_source` (property "membership"),
##     `entries[].rarity.source` ("rarity") and `meso.amount_source` ("mesos.amount"); see SOURCE_PROPERTIES
##
## To let an authority supply another property, add the property name to its `properties`. To add an authority, add a
## row (and, for a capture-backed one, its capture folder under tools/<site>/captures/). Property names are free-form
## strings; the C1 drop properties are listed in DROP_PROPERTIES.

const MEOWDB := "MeowDB MS Classic"
const HENESYS := "Henesys.gg"
const PROJECT_OWNER := "Project owner"

## A `properties` entry that matches every property.
const ANY_PROPERTY := "*"

## The sourced properties of a drop record (contract C1). The drop and meso chances are not among them: they are the
## project owner's rules in game/data/misostory (decisions D3-11, D3-12), never canonical data.
const DROP_PROPERTIES := ["membership", "rarity", "mesos.amount"]

## name -> rule
##   url_prefixes  every cited URL (`url`, or each of `urls`) starts with one of these on a path boundary; an empty list
##                 means no URL is needed
##   properties    the properties the authority may supply (ANY_PROPERTY = all)
##   read_at       an ISO 8601 `read_at` with a zone is required (MeowDB may give its cache stamp as `retrieved_at`)
##   capture       a `capture` path is required: the dated file under tools/<site>/captures/ the value was read from
##   decision      a `decision` is required: an owner decision id ("D3-11") or the Iteration Three brief
##   owner_kinds   (optional) drop-owner kinds the authority may describe
const REGISTRY := {
	MEOWDB: {
		"url_prefixes": ["https://meowdb.com/msclassic", "https://meowdb.com/_data/", "https://meowdb.com/api/"],
		"properties": [ANY_PROPERTY], "read_at": true, "capture": false, "decision": false,
	},
	HENESYS: {
		"url_prefixes": ["https://henesys.gg/"],
		"properties": ["rarity"], "read_at": true, "capture": true, "decision": false,
	},
	PROJECT_OWNER: {
		"url_prefixes": [],
		"properties": [ANY_PROPERTY], "read_at": false, "capture": false, "decision": true,
	},
}

## Schema 3 drop record source paths (dotted, from the entry or the meso block) -> the property they supply
## (tools/meowdb/build_sources_index.mjs mirrors this).
const SOURCE_PROPERTIES := {
	"entries": {"membership_source": "membership", "rarity.source": "rarity"},
	"meso": {"amount_source": "mesos.amount"},
}

## A capture path: repo-relative, forward slashes, under tools/<site>/captures/.
const CAPTURE_PATH := "^tools/[A-Za-z0-9_-]+/captures/[^\\\\]+$"
## A decision reference: an ITERATION_LOG decision id ("D3-11") or the Iteration Three brief.
const DECISION_ID := "(^|[^A-Za-z0-9])D\\d+-\\d+($|[^0-9])"
const BRIEF := "ITERATION_THREE_BRIEF"


static func has(authority: Variant) -> bool:
	return authority is String and REGISTRY.has(authority)


static func rule(authority: String) -> Dictionary:
	return REGISTRY.get(authority, {})


## True when `authority` may supply `property`.
static func allows(authority: String, property: String) -> bool:
	var props: Array = rule(authority).get("properties", [])
	return ANY_PROPERTY in props or property in props


## The properties `authority` may supply, for messages.
static func allowed_text(authority: String) -> String:
	var props: Array = rule(authority).get("properties", [])
	return "any property" if ANY_PROPERTY in props else ", ".join(PackedStringArray(props))


## True when `url` starts with one of `authority`'s URL prefixes on a path boundary (so "meowdb.com.evil" or
## "/msclassicfake" do not pass). A prefix ending in "/" or "#" needs something after it.
static func url_allowed(authority: String, url: Variant) -> bool:
	if not (url is String):
		return false
	for prefix in rule(authority).get("url_prefixes", []):
		var p: String = prefix
		var u: String = url
		if p.ends_with("/") or p.ends_with("#"):
			if u.begins_with(p) and u.length() > p.length():
				return true
		elif u == p or u.begins_with(p + "/") or u.begins_with(p + "?") or u.begins_with(p + "#"):
			return true
	return false


## The value at a dotted `path` ("rarity.source") under `node`, or null when a step is missing.
static func at_path(node: Variant, path: String) -> Variant:
	var cur: Variant = node
	for step in path.split("."):
		if not (cur is Dictionary):
			return null
		cur = (cur as Dictionary).get(step, null)
	return cur


static func names_text() -> String:
	return ", ".join(PackedStringArray(REGISTRY.keys()))
