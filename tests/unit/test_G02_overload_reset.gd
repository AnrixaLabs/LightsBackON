extends "res://tests/support/grid_case_test.gd"
## G02: 10 Hz integer overload counters, trip at trip_ticks (15 = 1.5 s), recompute after trips, validated resets.
## Scenarios live in tests/data/c01_grid_cases.json and are cross-checked against reference/ (re-derived).


func test_SIM04_generator_overload_trips_TEMP_once_at_tick_15() -> void:
	_check("SIM04_generator_overload_trips_TEMP_at_15_ticks")


func test_SIM05_sustained_sign_overload_trips_JE_breaker() -> void:
	_check("SIM05_sign_overload_trips_JE_breaker")


func test_SIM08_equality_never_starts_overload_timer() -> void:
	_check("SIM08_edge_demand_equal_to_capacity")


func test_SIM09_overload_14_ticks_then_remove_load_resets_timer() -> void:
	_check("SIM09_overload_1_4s_then_remove_load_no_spurious_trip")


func test_SIM10_reset_refused_while_overloaded_and_no_trip_loop() -> void:
	_check("SIM10_reset_refused_while_overloaded_no_trip_loop")


func test_G02_unloaded_breaker_reset_is_accepted() -> void:
	_check("G02_reset_of_unloaded_breaker_accepted_while_component_failed")


func test_G02_trip_event_is_authoritative_and_emitted_once() -> void:
	var g: PowerGrid = _sim04_grid()
	var events: Array[Dictionary] = []
	for _i: int in 40:
		events.append_array(g.step())
	assert_eq(events.size(), 1, "sustained overload trips once")
	if events.size() == 1:
		assert_eq(events[0], {"type": "trip", "tick": 15, "protection": "BRK_TEMP", "element": "E_GEN_TEMP", "breaker": "TEMP"})
	var st: Dictionary = g.canonical_state()
	assert_eq(st["nodes"]["TEMP"]["tripped"], true)
	assert_eq(st["nodes"]["PUMP"]["supplied"], false, "recomputed after trip (step 7)")
	assert_eq(st["edges"]["E_GEN_TEMP"]["flow"], 0)


func test_G02_refused_reset_leaves_state_and_counter_untouched() -> void:
	var g: PowerGrid = _sim04_grid()
	for _i: int in 15:
		g.step()
	var before: String = g.canonical_string()
	var res: Dictionary = g.apply({"op": "set", "id": "TEMP", "field": "tripped", "value": false})
	assert_eq(res["ok"], false)
	assert_eq(res["code"], "RESET_OVERLOADED")
	assert_true(str(res["message"]).contains("8 PU"), "reason names the load: %s" % res["message"])
	assert_eq(g.canonical_string(), before)


func test_G02_trip_ticks_come_from_content() -> void:
	var def: Dictionary = Cases.definition_for(_doc, {}, false)
	def["trip_ticks"] = 3
	var g: PowerGrid = PowerGrid.new()
	assert_true(g.load_definition(def).is_empty())
	g.apply({"op": "set", "id": "E_TEMP_PUMP", "field": "enabled", "value": true})
	g.apply({"op": "set", "id": "E_TEMP_PUB", "field": "enabled", "value": true})
	g.apply({"op": "set", "id": "GEN", "field": "online", "value": true})
	assert_eq(g.step().size(), 0)
	assert_eq(g.step().size(), 0)
	assert_eq(g.step().size(), 1, "trips on the tick the counter reaches trip_ticks")


func _sim04_grid() -> PowerGrid:
	var g: PowerGrid = PowerGrid.new()
	g.load_definition(Cases.definition_for(_doc, {}, false))
	for cmd: Dictionary in [
		{"op": "set", "id": "E_TEMP_PUMP", "field": "enabled", "value": true},
		{"op": "set", "id": "E_TEMP_PUB", "field": "enabled", "value": true},
		{"op": "set", "id": "GEN", "field": "online", "value": true},
	]:
		g.apply(cmd)
	return g
