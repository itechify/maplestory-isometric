class_name ValidationReport
extends RefCounted
## The result of one DataValidator run: a flat list of findings plus a few counters.
##
## Every finding is a Dictionary {severity, domain, id, message, check}:
##   severity  "error" (broken data: treated like a compile error, the tool exits non-zero) or "warning"
##   domain    canonical domain ("maps", "quests", ...), "misostory/<sub>" for adaptation files, "canonical_sources",
##             "crosswalk" or "load"
##   id        the record id inside that domain (or the file basename / path)
##   message   one human-readable sentence
##   check     a short slug naming the rule that fired ("reference", "portal", "provenance", ...); tests key on it
##
## References that point outside the shipped dataset on purpose (Victoria Island quests listed on a Maple Island map,
## a monster's off-island spawn maps, Shanks' boat to Lith Harbor, a canonical dialogue link naming an off-island NPC)
## are not findings; they are counted in out_of_scope so the report can say how many were skipped and why.

const ERROR := "error"
const WARNING := "warning"

var findings: Array[Dictionary] = []
## "<domain>/<id>: <field> -> <target>/<ref> (<why>)" for every reference skipped as deliberately out of scope.
var out_of_scope: PackedStringArray = []
## Free-form counters filled by the validator (records checked, references resolved, ...).
var stats: Dictionary = {}


## Records an error finding.
func error(check: String, domain: String, id: String, message: String) -> void:
	add(ERROR, check, domain, id, message)


## Records a warning finding.
func warning(check: String, domain: String, id: String, message: String) -> void:
	add(WARNING, check, domain, id, message)


## Records a finding with an explicit severity ("error" or "warning").
func add(severity: String, check: String, domain: String, id: String, message: String) -> void:
	findings.append({"severity": severity, "domain": domain, "id": id, "message": message, "check": check})


## Adds one to a named counter in stats.
func count(stat: String, by: int = 1) -> void:
	stats[stat] = int(stats.get(stat, 0)) + by


func errors() -> Array[Dictionary]:
	return _with_severity(ERROR)


func warnings() -> Array[Dictionary]:
	return _with_severity(WARNING)


func error_count() -> int:
	return errors().size()


func warning_count() -> int:
	return warnings().size()


func has_errors() -> bool:
	for f in findings:
		if f.severity == ERROR:
			return true
	return false


## Findings matching every non-empty filter (check slug, domain, id, severity). Handy in tests.
func matching(check: String = "", domain: String = "", id: String = "", severity: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in findings:
		if check != "" and f.check != check:
			continue
		if domain != "" and f.domain != domain:
			continue
		if id != "" and f.id != id:
			continue
		if severity != "" and f.severity != severity:
			continue
		out.append(f)
	return out


## One line per finding, errors first, then a summary line.
func format_text(include_out_of_scope: bool = false) -> String:
	var lines: PackedStringArray = []
	for f in errors():
		lines.append(_format_finding(f))
	for f in warnings():
		lines.append(_format_finding(f))
	if include_out_of_scope:
		for s in out_of_scope:
			lines.append("SKIPPED (out of scope) " + s)
	lines.append(summary())
	return "\n".join(lines)


## "<n> errors, <m> warnings, <k> out-of-scope references skipped" plus the stats counters.
func summary() -> String:
	var keys: Array = stats.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%s" % [k, stats[k]])
	return "%d errors, %d warnings, %d out-of-scope references skipped (%s)" % [
		error_count(), warning_count(), out_of_scope.size(), ", ".join(parts)]


## A JSON-ready snapshot of the whole report.
func to_dict() -> Dictionary:
	return {
		"errors": error_count(),
		"warnings": warning_count(),
		"findings": findings.duplicate(true),
		"out_of_scope": Array(out_of_scope),
		"stats": stats.duplicate(),
	}


func _with_severity(severity: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in findings:
		if f.severity == severity:
			out.append(f)
	return out


static func _format_finding(f: Dictionary) -> String:
	var label := "VALIDATION ERROR" if f.severity == ERROR else "VALIDATION WARNING"
	return "%s [%s] %s/%s: %s" % [label, f.check, f.domain, f.id, f.message]
