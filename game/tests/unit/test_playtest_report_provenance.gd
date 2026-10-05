extends TestCase
## Contract C6 evidence provenance: a playtest report.json records the commit it played and whether the tree was dirty
## (PlaytestReport.git, stamped from the PLAYTEST_GIT_* variables scripts/playtest.sh sets), across the phases of a
## multi-process run, so tools/parity/build_parity.mjs can compare the evidence with HEAD.


## Tooling, not a canonical or brief requirement: no parity keys.
func parity_keys() -> Dictionary:
	return {}


func test_the_first_phase_records_commit_and_dirty_flag() -> void:
	var r := PlaytestReport.new()
	r.stamp_git("", "1", false)
	assert_eq(r.git, {}, "no commit (not started through playtest.sh): nothing recorded")
	r.stamp_git("abc123", "0", false)
	assert_eq(r.git, {"commit": "abc123", "dirty": false, "reused_copy": false, "mixed": false})
	var d: Dictionary = JSON.parse_string(JSON.stringify(r.to_dict()))
	assert_eq(d.get("git", {}), {"commit": "abc123", "dirty": false, "reused_copy": false, "mixed": false}, "report.json carries it")
	assert_true(r.to_markdown().contains("- Code: commit abc123, clean tree"), "report.md says it")


func test_later_phases_keep_the_first_commit_and_flag_a_change() -> void:
	var r := PlaytestReport.new()
	r.stamp_git("abc123", "0", false)
	var next := PlaytestReport.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	assert_eq(next.git.get("commit", ""), "abc123", "the block survives the phase boundary")
	next.stamp_git("abc123", "0", false)
	assert_eq(next.git, {"commit": "abc123", "dirty": false, "reused_copy": false, "mixed": false}, "same commit, clean: unchanged")
	next.stamp_git("def456", "", true)
	assert_eq(next.git.get("commit", ""), "abc123", "the first phase's commit is kept")
	assert_eq(next.git.get("mixed", false), true, "a phase on another commit")
	assert_eq(next.git.get("dirty", false), null, "one phase of unknown tree state: unknown")
	assert_eq(next.git.get("reused_copy", false), true, "a reused copy is remembered")
	next.stamp_git("abc123", "1", false)
	assert_eq(next.git.get("dirty", null), true, "any dirty phase makes the run dirty")
	assert_true(next.to_markdown().contains("dirty tree, several commits across phases, a reused copy"), next.to_markdown())
