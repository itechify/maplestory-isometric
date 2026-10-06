extends TestCase
## Fixture for test_runner_evidence.gd (not discovered by the runner: it lives outside tests/unit). One passing and one
## failing test, both tagged.


func parity_keys() -> Dictionary:
	return {
		"test_passes": ["quest:1005", "mechanic:natural-hp-regen"],
		"test_fails": ["drop:2/snail-shell"],
	}


func test_passes() -> void:
	assert_eq(1 + 1, 2, "arithmetic")


func test_fails() -> void:
	fail("deliberate fixture failure")


func test_untagged() -> void:
	assert_true(true)
