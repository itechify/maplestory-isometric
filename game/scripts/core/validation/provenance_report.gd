class_name ProvenanceReport
extends RefCounted
## The provenance validation report (brief Phase 17): for every canonical record and every property, which authority
## supplied it, from which URL, when it was read and from which dated capture; every unresolved value; every MisoStory
## adaptation with its verified flag and reason; and counts. Written by `bash scripts/validate_data.sh --report` to
## docs/provenance_report.json (build()) and docs/PROVENANCE_REPORT.md (to_markdown()).
##
##   var doc := ProvenanceReport.build(db, DataValidator.validate(db))
##
## Pure: it reads the ContentDB and the finished ValidationReport. It records no clock time (only the data's own
## read_at / retrieved_at), so regenerating it over unchanged data gives the same files.
##
## Property rows ("properties" of a record), in this order:
##   (record)      the record's own `source` (its MeowDB page): it covers every value no other row names
##   <field>       each `field_sources.<field>` (a value read from another MeowDB page or file); URLs off meowdb.com
##                 are declared in `external` and reported with that entry's authority "external"
##   <property>    each `provenance.<property>` block (contract C7: KuroDB, Hidden Street, Project owner, captures)
##   membership / probability / mesos.amount / mesos.probability   per entry and meso source of a schema v2 drop record
## Unresolved values: each record's `gaps` (what the source does not give: the value is null or absent) and, in drop
## records, each entry whose chance is unresolved (v2) or null (v1: the runtime still rolls the placeholder rates of
## misostory/drop_rates.json), each item that did not resolve and each unresolved meso amount or chance.

const FORMAT := 1
const COMMAND := "bash scripts/validate_data.sh --report"
const RECORD_PROPERTY := "(record)"
const EXTERNAL := "external"
## The adaptation keys that state what a value was checked against (AdaptationChecks.VERIFIED_AGAINST).
const VERIFIED_AGAINST := "verified_against"


## The report as a JSON-ready Dictionary (sorted, deterministic).
static func build(db: ContentDB, validation: ValidationReport) -> Dictionary:
	var findings_by_record := {}
	for f in validation.findings:
		var k := "%s/%s" % [f.domain, f.id]
		if not findings_by_record.has(k):
			findings_by_record[k] = []
		findings_by_record[k].append({"severity": f.severity, "check": f.check, "message": f.message})
	var records: Array = []
	var unresolved := {}
	var by_authority := {}
	var by_domain := {}
	var captures := {}
	var property_rows := 0
	for domain_name in ValidationUtil.canonical_domains(db):
		by_domain[domain_name] = 0
		for key in db.ids(domain_name):
			var rec: Dictionary = db.get_entity(domain_name, key)
			by_domain[domain_name] += 1
			var props := property_rows_of(domain_name, rec)
			var authorities := {}
			for p in props:
				property_rows += 1
				var authority: String = str(p.authority) if p.authority != null else "(none)"
				authorities[authority] = true
				by_authority[authority] = int(by_authority.get(authority, 0)) + 1
				if p.capture != null:
					captures[p.capture] = true
			for c in ProvenanceChecks._capture_files(rec):
				captures[c] = true
			var authority_list: Array = authorities.keys()
			authority_list.sort()
			var label := "%s/%s" % [domain_name, key]
			var open := unresolved_of(domain_name, key, rec)
			if not open.is_empty():
				if not unresolved.has(domain_name):
					unresolved[domain_name] = []
				unresolved[domain_name].append_array(open)
			records.append({
				"domain": domain_name, "id": key, "name": rec.get("name", null),
				"file": "game/data/canonical/%s/%s.json" % [domain_name, key],
				"authorities": authority_list, "properties": props, "unresolved_count": open.size(),
				"findings": findings_by_record.get(label, []),
			})
	var adaptations := adaptation_rows(db)
	var verified := 0
	for a in adaptations:
		if a.verified:
			verified += 1
	var unresolved_counts := {}
	var unresolved_total := 0
	for d in unresolved:
		unresolved_counts[d] = unresolved[d].size()
		unresolved_total += unresolved[d].size()
	var capture_list: Array = captures.keys()
	capture_list.sort()
	return {
		"format": FORMAT,
		"generated_by": COMMAND,
		"validation": {
			"errors": validation.error_count(), "warnings": validation.warning_count(),
			"findings": validation.findings.map(func(f: Dictionary) -> Dictionary: return {
				"severity": f.severity, "check": f.check, "domain": f.domain, "id": f.id, "message": f.message}),
			"out_of_scope_by_rule": validation.out_of_scope_by_rule.duplicate(),
		},
		"counts": {
			"records": records.size(), "records_by_domain": by_domain, "property_rows": property_rows,
			"property_rows_by_authority": by_authority, "capture_files": capture_list.size(),
			"unresolved": unresolved_total, "unresolved_by_domain": unresolved_counts,
			"adaptations": adaptations.size(), "adaptations_verified": verified,
			"adaptations_unverified": adaptations.size() - verified,
		},
		"capture_files": capture_list,
		"records": records,
		"unresolved": unresolved,
		"adaptations": adaptations,
	}


## The property rows of one canonical record (see the class doc), each {property, authority, urls, read_at, capture,
## decision, raw_value, via}.
static func property_rows_of(domain_name: String, rec: Dictionary) -> Array:
	var out: Array = []
	var src: Dictionary = rec.get("source", {}) if rec.get("source", null) is Dictionary else {}
	out.append(_row(RECORD_PROPERTY, src, "source"))
	var external := {}
	for e in ValidationUtil.as_array(rec.get("external", null)):
		if e is Dictionary and e.get("source_url", null) is String:
			external[e.source_url] = e
	var fs: Variant = rec.get("field_sources", null)
	if fs is Dictionary:
		var fields: Array = fs.keys()
		fields.sort()
		for field in fields:
			var v: Variant = fs[field]
			if not (v is Dictionary):
				continue
			var row := _row(str(field), v, "field_sources")
			row.authority = ProvenanceAuthorities.MEOWDB
			for u in row.urls:
				if external.has(u):
					row.authority = EXTERNAL
					row["verified"] = external[u].get("verified", null)
			out.append(row)
	for pair in ProvenanceChecks.source_objects(domain_name, rec):
		var s: Variant = pair[1]
		if s is Dictionary:
			out.append(_row(str(pair[0]), s, "provenance"))
	return out


static func _row(property: String, src: Dictionary, via: String) -> Dictionary:
	var urls: Array = []
	for u in ProvenanceChecks._field_source_urls(src):
		if not (u in urls):
			urls.append(u)
	var read_at: Variant = src.get("read_at", src.get("retrieved_at", null))
	var row := {
		"property": property, "via": via,
		"authority": src.get("authority", null),
		"urls": urls, "read_at": read_at, "capture": src.get("capture", null), "decision": src.get("decision", null),
	}
	if src.get("raw_value", null) != null:
		row["raw_value"] = src.raw_value
	return row


## The unresolved values of one record: [{record, kind, ...}] (see the class doc).
static func unresolved_of(domain_name: String, key: String, rec: Dictionary) -> Array:
	var label := "%s/%s" % [domain_name, key]
	var out: Array = []
	for g in ValidationUtil.as_array(rec.get("gaps", null)):
		out.append({"record": label, "kind": "gap", "text": str(g)})
	if domain_name != "drops":
		return out
	var v2 := ValidationUtil.same(rec.get("schema_version", null), 2)
	for e in ValidationUtil.as_array(rec.get("entries", null)):
		if not (e is Dictionary):
			continue
		var entry := str(e.get("key", e.get("item_id", "?")))
		var item_name: Variant = e.get("name", e.get("item_name", null))
		if v2:
			var res: Variant = e.get("item_resolution", null)
			var state: Variant = res.get("state", null) if res is Dictionary else null
			if not ValidationUtil.same(state, "resolved"):
				out.append({"record": label, "kind": "item", "entry": entry, "name": item_name, "state": state,
					"candidates": res.get("candidates", []) if res is Dictionary else [],
					"note": res.get("note", "") if res is Dictionary else ""})
			if not ValidationUtil.same(e.get("chance_state", null), "resolved"):
				out.append({"record": label, "kind": "probability", "entry": entry, "name": item_name,
					"text": "no KuroDB chance for this member: it never drops"})
		elif e.get("chance", null) == null:
			out.append({"record": label, "kind": "probability", "entry": entry, "name": item_name,
				"text": "schema v1: chance null; the runtime rolls the placeholder rate of misostory/drop_rates.json"})
	var meso: Variant = rec.get("meso", null)
	if meso is Dictionary and v2:
		for part in [["amount_state", "meso amount"], ["chance_state", "meso probability"]]:
			if not ValidationUtil.same(meso.get(part[0], null), "resolved"):
				out.append({"record": label, "kind": part[1], "text": "unresolved: the meso bag never drops"})
	elif meso is Dictionary:
		for part in [["chance", "meso probability"], ["min", "meso amount"]]:
			if meso.get(part[0], null) == null:
				out.append({"record": label, "kind": part[1],
					"text": "schema v1: null; the runtime uses the placeholder of misostory/drop_rates.json"})
	return out


## Every adapted object carrying a verified flag in game/data/misostory: [{file, path, kind, verified,
## verified_against, reason}], sorted by file then path. `reason` is the object's own (`reason`, the `<key>_reason`
## of a `<key>_verified` flag, or "(per value: reasons map)") or else the nearest enclosing one.
static func adaptation_rows(db: ContentDB) -> Array:
	var out: Array = []
	var folders: Array = db.miso.keys()
	folders.sort()
	for folder in folders:
		var keys: Array = db.miso[folder].keys()
		keys.sort()
		for key in keys:
			var file := "game/data/misostory/%s.json" % (str(key) if str(folder) == "" else "%s/%s" % [folder, key])
			var data: Variant = db.miso[folder][key]
			var kind: Variant = data.get("kind", null) if data is Dictionary else null
			_collect_verified(data, "", null, file, kind, out)
	return out


static func _collect_verified(node: Variant, path: String, inherited_reason: Variant, file: String, kind: Variant, out: Array) -> void:
	if node is Dictionary:
		var reason: Variant = inherited_reason
		if ValidationUtil.non_empty(node.get("reason", null)):
			reason = node.reason
		elif node.get("reasons", null) is Dictionary:
			reason = "(per value: its reasons map)"
		elif node.keys().any(func(k: Variant) -> bool: return str(k).ends_with("_reason")):
			reason = "(per value: its <key>_reason entries)"
		if node.get("verified", null) is bool:
			out.append({"file": file, "path": path if path != "" else "(file)", "kind": kind, "verified": node.verified,
				"verified_against": node.get(VERIFIED_AGAINST, null), "reason": reason})
		var keys: Array = node.keys()
		keys.sort()
		for k in keys:
			var key := str(k)
			var child := key if path == "" else "%s.%s" % [path, key]
			if key.ends_with("_verified") and node[k] is bool:
				var base := key.trim_suffix("_verified")
				out.append({"file": file, "path": "%s%s" % [("" if path == "" else path + "."), base], "kind": kind,
					"verified": node[k], "verified_against": node.get(key + "_against", node.get(VERIFIED_AGAINST, null)),
					"reason": node.get(base + "_reason", reason)})
			elif not AdaptationChecks.is_meta_key(key):
				_collect_verified(node[k], child, reason, file, kind, out)
	elif node is Array:
		for e in node:
			_collect_verified(e, path + "[]", inherited_reason, file, kind, out)


# --- markdown -----------------------------------------------------------------------------------------------

## The human-readable report (docs/PROVENANCE_REPORT.md) of a build() Dictionary.
static func to_markdown(doc: Dictionary) -> String:
	var c: Dictionary = doc.counts
	var v: Dictionary = doc.validation
	var L: PackedStringArray = []
	L.append("# Provenance validation report")
	L.append("")
	L.append("Generated by `%s` from `game/data/canonical` and `game/data/misostory` (brief Phase 17)." % COMMAND)
	L.append("Do not edit: change the data or the validator and regenerate. The machine-readable copy is")
	L.append("[`provenance_report.json`](provenance_report.json); the rules are in")
	L.append("[`runtime/DATA_VALIDATION.md`](runtime/DATA_VALIDATION.md) and the authorities in")
	L.append("[`canonical/README.md`](canonical/README.md).")
	L.append("")
	L.append("## Summary")
	L.append("")
	L.append("| What | Count |")
	L.append("|---|---|")
	L.append("| Validation errors / warnings | %d / %d |" % [int(v.errors), int(v.warnings)])
	L.append("| Canonical records | %d (%s) |" % [int(c.records), _pairs(c.records_by_domain)])
	L.append("| Property rows (record source, field sources, per-property sources) | %d |" % int(c.property_rows))
	L.append("| Property rows by authority | %s |" % _pairs(c.property_rows_by_authority))
	L.append("| Dated capture files cited | %d |" % int(c.capture_files))
	L.append("| Unresolved values | %d (%s) |" % [int(c.unresolved), _pairs(c.unresolved_by_domain)])
	L.append("| Adaptations (objects with a verified flag) | %d: %d verified, %d not verified |" % [
		int(c.adaptations), int(c.adaptations_verified), int(c.adaptations_unverified)])
	L.append("")
	if not v.findings.is_empty():
		L.append("Findings of the validation run:")
		L.append("")
		for f in v.findings:
			L.append("- %s [%s] %s/%s: %s" % [f.severity, f.check, f.domain, f.id, _esc(f.message)])
		L.append("")
	var rules: Dictionary = v.out_of_scope_by_rule
	if not rules.is_empty():
		L.append("References skipped as out of scope (not findings):")
		L.append("")
		var keys: Array = rules.keys()
		keys.sort()
		for k in keys:
			L.append("- %d x %s" % [int(rules[k]), k])
		L.append("")
	L.append("Captures cited: %s." % ", ".join(PackedStringArray(doc.capture_files.map(func(x: String) -> String: return "`%s`" % x))))
	L.append("")
	L.append("## Records")
	L.append("")
	L.append("One row per canonical record: its own source page (it covers every value no property row names), the other")
	L.append("authorities its properties cite, the number of property rows and of unresolved values.")
	L.append("")
	L.append("| Record | Name | Source | Read at | Authorities | Properties | Unresolved |")
	L.append("|---|---|---|---|---|---|---|")
	for r in doc.records:
		var own: Dictionary = r.properties[0]
		L.append("| %s/%s | %s | %s | %s | %s | %d | %d |" % [r.domain, r.id, _esc(r.name), _urls(own.urls), _s(own.read_at),
			_esc(", ".join(PackedStringArray(r.authorities))), r.properties.size(), int(r.unresolved_count)])
	L.append("")
	L.append("## Properties")
	L.append("")
	L.append("Every property row: `(record)` is the record's own source, other names are `field_sources` entries (a value read")
	L.append("from another page) or per-property `provenance` sources (contract C7).")
	var by_domain := {}
	for r in doc.records:
		if not by_domain.has(r.domain):
			by_domain[r.domain] = []
		by_domain[r.domain].append(r)
	var domains: Array = by_domain.keys()
	domains.sort()
	for d in domains:
		L.append("")
		L.append("### %s" % d)
		L.append("")
		L.append("| Record | Property | Authority | URL | Read at | Capture | Decision |")
		L.append("|---|---|---|---|---|---|---|")
		for r in by_domain[d]:
			for p in r.properties:
				L.append("| %s | %s | %s | %s | %s | %s | %s |" % [r.id, _esc(p.property), _esc(p.authority), _urls(p.urls),
					_s(p.read_at), _code(p.capture), _esc(p.decision)])
	L.append("")
	L.append("## Unresolved values")
	L.append("")
	L.append("What the sources do not give, by domain: each record's `gaps` (the value is null or absent and never guessed)")
	L.append("and, in drop records, every member without a chance, every unresolved item and meso value.")
	var udomains: Array = doc.unresolved.keys()
	udomains.sort()
	for d in udomains:
		L.append("")
		L.append("### %s (%d)" % [d, doc.unresolved[d].size()])
		L.append("")
		for u in doc.unresolved[d]:
			var what: String = u.kind
			if u.has("entry"):
				what += " `%s`%s" % [u.entry, (" (%s)" % u.name) if u.get("name", null) != null else ""]
			var text := str(u.get("text", ""))
			if u.has("state"):
				text = "item %s%s" % [str(u.state), (": candidates %s" % ", ".join(PackedStringArray(u.candidates))) if not u.candidates.is_empty() else ""]
			L.append("- %s, %s: %s" % [u.record, what, _esc(text)])
	L.append("")
	L.append("## Adaptations")
	L.append("")
	L.append("Every MisoStory adaptation in `game/data/misostory` that carries a verified flag, with what it was verified against")
	L.append("and its reason (the nearest one when the object inherits it).")
	L.append("")
	L.append("| File | Path | Verified | Verified against | Reason |")
	L.append("|---|---|---|---|---|")
	for a in doc.adaptations:
		L.append("| %s | %s | %s | %s | %s |" % [a.file.trim_prefix("game/data/misostory/"), _esc(a.path),
			"yes" if a.verified else "no", _esc(a.verified_against), _esc(a.reason)])
	L.append("")
	return "\n".join(L)


static func _pairs(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s %s" % [k, str(d[k])])
	return ", ".join(parts)


static func _urls(urls: Array) -> String:
	return "<br>".join(PackedStringArray(urls.map(func(u: Variant) -> String: return _esc(u))))


static func _code(v: Variant) -> String:
	return "" if v == null else "`%s`" % str(v)


static func _s(v: Variant) -> String:
	return "" if v == null else str(v)


## Markdown-table-safe text: pipes escaped, newlines flattened; null is empty; a list is joined.
static func _esc(v: Variant) -> String:
	if v == null:
		return ""
	if v is Array:
		return "; ".join(PackedStringArray(v.map(func(x: Variant) -> String: return str(x)))).replace("|", "\\|").replace("\n", " ")
	return str(v).replace("|", "\\|").replace("\n", " ")
