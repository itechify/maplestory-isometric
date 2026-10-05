class_name ProvenanceAuthorities
extends RefCounted
## The provenance authority registry (Iteration Three contract C7; decisions D3-1 to D3-9 in docs/ITERATION_LOG.md):
## which sources may supply which property of the canonical data, and what each citation must carry. This table is
## the only place these rules live. ProvenanceChecks.check_source_object applies it to every source object:
##   - a record-level `provenance.<property>` block (any canonical domain, and game/data/misostory files)
##   - in a schema v2 drop record (contract C1): `entries[].membership_source` (property "membership"),
##     `entries[].chance_source` ("probability"), `meso.amount_source` ("mesos.amount") and `meso.chance_source`
##     ("mesos.probability"); see SOURCE_PROPERTIES
##
## To let an authority supply another property, add the property name to its `properties`. To add an authority, add a
## row (and, for a capture-backed one, its capture folder under tools/<site>/captures/). Property names are free-form
## strings; the C1 drop properties are listed in DROP_PROPERTIES.

const MEOWDB := "MeowDB MS Classic"
const KURODB := "KuroDB"
const HIDDEN_STREET := "Hidden Street"
const PROJECT_OWNER := "Project owner"

## A `properties` entry that matches every property.
const ANY_PROPERTY := "*"

## The properties of a drop record (contract C1).
const DROP_PROPERTIES := ["membership", "probability", "mesos.amount", "mesos.probability"]

## name -> rule
##   url_prefixes  every cited URL (`url`, or each of `urls`) starts with one of these on a path boundary; an empty list
##                 means no URL is needed
##   properties    the properties the authority may supply (ANY_PROPERTY = all)
##   read_at       an ISO 8601 `read_at` with a zone is required (MeowDB may give its cache stamp as `retrieved_at`)
##   capture       a `capture` path is required: the dated file under tools/<site>/captures/ the value was read from
##   decision      a `decision` is required: an owner decision id ("D3-5") or the Iteration Three brief
##   owner_kinds   (optional) drop-owner kinds the authority may describe; Hidden Street has no breakables
const REGISTRY := {
	MEOWDB: {
		"url_prefixes": ["https://meowdb.com/msclassic", "https://meowdb.com/_data/", "https://meowdb.com/api/"],
		"properties": [ANY_PROPERTY], "read_at": true, "capture": false, "decision": false,
	},
	KURODB: {
		"url_prefixes": ["https://playkuro.com/database/#"],
		"properties": ["probability", "mesos.probability"], "read_at": true, "capture": true, "decision": false,
	},
	HIDDEN_STREET: {
		"url_prefixes": ["https://bc.hidden-street.net/"],
		"properties": ["membership", "mesos.amount"], "read_at": true, "capture": true, "decision": false,
		"owner_kinds": ["monster"],
	},
	PROJECT_OWNER: {
		"url_prefixes": [],
		"properties": [ANY_PROPERTY], "read_at": false, "capture": false, "decision": true,
	},
}

## Schema v2 drop record source keys -> the property they supply (tools/meowdb/build_sources_index.mjs mirrors this).
const SOURCE_PROPERTIES := {
	"entries": {"membership_source": "membership", "chance_source": "probability"},
	"meso": {"amount_source": "mesos.amount", "chance_source": "mesos.probability"},
}

## A capture path: repo-relative, forward slashes, under tools/<site>/captures/.
const CAPTURE_PATH := "^tools/[A-Za-z0-9_-]+/captures/[^\\\\]+$"
## A decision reference: an ITERATION_LOG decision id ("D3-5") or the Iteration Three brief.
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


static func names_text() -> String:
	return ", ".join(PackedStringArray(REGISTRY.keys()))
