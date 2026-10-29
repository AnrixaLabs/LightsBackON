extends RefCounted
## Base class for tests. Extend it by path (not class_name) so tests run on a fresh
## clone before Godot has built the global class cache:
##   extends "res://tests/test_case.gd"
## Assertions are soft: a failure is recorded and the test method keeps running.

var failures: Array[String] = []
var assertions: int = 0


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func assert_true(cond: bool, msg: String = "") -> void:
	assertions += 1
	if not cond:
		failures.append("assert_true failed. %s" % msg)


func assert_false(cond: bool, msg: String = "") -> void:
	assertions += 1
	if cond:
		failures.append("assert_false failed. %s" % msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	assertions += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("expected <%s> (%s) but got <%s> (%s). %s" % [
			str(expected), type_string(typeof(expected)),
			str(actual), type_string(typeof(actual)), msg])


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	assertions += 1
	if typeof(actual) == typeof(unexpected) and actual == unexpected:
		failures.append("did not expect <%s>. %s" % [str(unexpected), msg])
