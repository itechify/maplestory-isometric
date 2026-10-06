extends TestCase
## Fixture for test_runner_evidence.gd: a test file that needs the exported world (its SKIP line would say "run with
## INCLUDE_WORLD=1"), so its evidence entries are marked needs_world.


func parity_keys() -> Dictionary:
	return {"test_on_the_world": ["map:000000040"]}


func test_on_the_world() -> void:
	assert_true(true)
