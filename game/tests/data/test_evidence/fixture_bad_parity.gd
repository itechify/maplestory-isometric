extends TestCase
## Fixture for test_runner_evidence.gd: a parity_keys() that names a test this file does not have and a malformed key.


func parity_keys() -> Dictionary:
	return {
		"test_renamed_long_ago": ["quest:1002"],
		"test_ok": ["Quest 1002"],
	}


func test_ok() -> void:
	assert_true(true)
