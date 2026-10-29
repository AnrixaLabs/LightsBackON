extends "res://tests/test_case.gd"
## Proves the headless runner works. Delete once real tests exist (G01 onwards).


func test_runner_executes() -> void:
	assert_eq(1 + 1, 2)
	assert_true(true)


func test_typed_assertions_distinguish_int_and_float() -> void:
	# integer PU are the design choice (see CLAUDE.md section 3); the runner must not hide int/float drift
	assert_ne(12, 12.0)
