extends "res://tests/test_case.gd"
## G03: meter and evidence model. Unknown readings are "?", never 0; inspected evidence explains the C01 faults.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Cases := preload("res://tests/support/grid_cases.gd")
const METER_PATH: String = "res://content/contracts/c01_alder_street/meter.json"
const METER_SCRIPT: String = "res://scripts/simulation/meter_model.gd"

var _doc: Dictionary
var _grid: PowerGrid
var _meter: MeterModel


func before_each() -> void:
	_doc = Cases.load_doc()
	_grid = PowerGrid.new()
	assert_true(_grid.load_definition(Cases.definition_for(_doc, {}, false)).is_empty(), "C01 grid loads")
	_meter = MeterModel.new()
	var errs: Array[Dictionary] = _meter.load_definition(JSON.parse_string(FileAccess.get_file_as_string(METER_PATH)), _grid)
	assert_true(errs.is_empty(), "C01 meter loads: %s" % str(errs))


func test_G03_uninspected_panel_never_reports_false_zero() -> void:
	# initial state, then states where real values are 0 (dead branches, offline generator) and non-zero
	_assert_all_unknown("initial")
	_run("@repair_west")
	_tick(5)
	_assert_all_unknown("after west repair")
	_run("@pump_on_generator")
	_assert_all_unknown("pump on generator")


func test_G03_measured_zero_is_explicit_and_distinct_from_unknown() -> void:
	assert_true(_meter.inspect("PANEL_JW", _grid)["ok"])
	var r: Dictionary = _meter.readings("PANEL_JW", _grid)
	assert_eq(r["load_pu"], {"known": true, "value": 0, "display": "0"}, "inspected dead branch reads a measured 0")
	var unknown: Dictionary = _meter.readings("PANEL_JE", _grid)["load_pu"]
	assert_eq(unknown, {"known": false, "display": "?"}, "uninspected JE stays unknown")


func test_G03_west_evidence_explains_component_fault() -> void:
	_meter.inspect("PANEL_JW", _grid)
	var r: Dictionary = _meter.readings("PANEL_JW", _grid)
	assert_eq(r["source_present"]["value"], true, "supply reaches the west junction")
	assert_eq(r["component"]["display"], "meter.value.open")
	assert_eq(r["breaker"]["value"], "tripped")
	assert_eq(r["breaker_reason"]["value"], "fault")
	assert_eq(r["demand_pu"]["value"], 9)
	assert_eq(r["capacity_pu"]["value"], 12)
	assert_eq(r["feed_E_GRID_JW"]["value"], "closed")
	assert_eq(_codes("PANEL_JW"), ["COMPONENT_OPEN", "TRIPPED_FAULT"])


func test_G03_east_evidence_explains_broken_trunk() -> void:
	_meter.inspect("PANEL_JE", _grid)
	_meter.inspect("PANEL_GRID", _grid)
	assert_eq(_codes("PANEL_JE"), ["FEED_OPEN", "NO_SOURCE"])
	assert_eq(_finding("PANEL_JE", "FEED_OPEN")["ids"], ["E_GRID_JE"], "evidence points at the open feed")
	assert_eq(_codes("PANEL_GRID"), [], "grid source itself is online and within capacity")
	assert_eq(_meter.readings("PANEL_GRID", _grid)["online"]["value"], true)


func test_G03_overload_trip_reason_explains_sign_load() -> void:
	_run("@repair_west")
	_run("@repair_east")
	_grid.apply({"op": "set", "id": "SIGN", "field": "enabled", "value": true})
	_meter.observe(_grid)
	_tick(15)
	_meter.inspect("PANEL_JE", _grid)
	var r: Dictionary = _meter.readings("PANEL_JE", _grid)
	assert_eq(r["breaker_reason"]["value"], "overload")
	assert_eq(r["trip_load_pu"]["value"], 14)
	assert_eq(r["trip_capacity_pu"]["value"], 12)
	assert_eq(r["demand_pu"]["value"], 14, "connected demand still shows what the branch would draw")
	assert_eq(r["load_pu"]["value"], 0, "tripped branch carries nothing now")
	assert_eq(_codes("PANEL_JE"), ["DEMAND_OVER_CAPACITY", "TRIPPED_OVERLOAD"])
	var trip: Dictionary = _finding("PANEL_JE", "TRIPPED_OVERLOAD")
	assert_eq(trip["ids"], ["E_GRID_JE", "JE"])
	assert_eq(trip["key"], "meter.finding.tripped_overload")


func test_G03_generator_panel_evidence_for_SIM04_overload() -> void:
	_run("@pump_on_generator")
	_grid.apply({"op": "set", "id": "E_TEMP_PUB", "field": "enabled", "value": true})
	_meter.inspect("PANEL_GEN", _grid)
	assert_eq(_codes("PANEL_GEN"), ["SOURCE_OVERLOADED"])
	assert_eq(_meter.readings("PANEL_GEN", _grid)["load_pu"]["value"], 8)


func test_G03_change_after_inspection_reverts_whole_panel_to_unknown() -> void:
	_meter.inspect("PANEL_JW", _grid)
	_grid.apply({"op": "set", "id": "JW", "field": "isolated", "value": true})
	_meter.observe(_grid)
	var r: Dictionary = _meter.readings("PANEL_JW", _grid)
	for field: String in r:
		if field != "_panel":
			assert_eq(r[field]["display"], "?", "%s must not show a stale value" % field)
	assert_eq(r["_panel"], {"inspected": true, "needs_reinspect": true})
	assert_eq(_meter.findings("PANEL_JW", _grid), [] as Array[Dictionary])
	_meter.inspect("PANEL_JW", _grid)
	assert_eq(_meter.readings("PANEL_JW", _grid)["isolator"]["value"], "open")


func test_G03_unexplained_trip_reason_reads_unknown_not_a_guess() -> void:
	_grid.apply({"op": "set", "id": "TEMP", "field": "tripped", "value": true})
	_meter.observe(_grid)
	_meter.inspect("PANEL_TEMP", _grid)
	var r: Dictionary = _meter.readings("PANEL_TEMP", _grid)
	assert_eq(r["breaker"]["value"], "tripped")
	assert_eq(r["breaker_reason"], {"known": false, "display": "?"})
	assert_true(_codes("PANEL_TEMP").has("TRIPPED_UNKNOWN"))


func test_G03_reset_clears_trip_reason() -> void:
	_run("@repair_west")
	_meter.inspect("PANEL_JW", _grid)
	var r: Dictionary = _meter.readings("PANEL_JW", _grid)
	assert_eq(r["breaker"]["value"], "closed")
	assert_eq(r["breaker_reason"]["known"], false, "a closed breaker has no reason")
	assert_eq(_codes("PANEL_JW"), [])
	assert_eq(_meter.canonical_state()["trip_reasons"], {})


func test_G03_inspect_unknown_panel_refused() -> void:
	var res: Dictionary = _meter.inspect("PANEL_NOWHERE", _grid)
	assert_eq(res["ok"], false)
	assert_eq(res["code"], "UNKNOWN_PANEL")
	assert_eq(_meter.readings("PANEL_NOWHERE", _grid), {"_panel": {"inspected": false, "needs_reinspect": false}})


func test_G03_bad_meter_definitions_rejected() -> void:
	var bad: Array[Dictionary] = [
		{"panels": [{"id": "panel jw", "target": "JW"}]},
		{"panels": [{"id": "PANEL_X", "target": "NOWHERE"}]},
		{"panels": [{"id": "PANEL_X", "target": "PUB"}]},
		{"panels": [{"id": "JW", "target": "JW"}]},
		{"panels": [], "initial_breaker_reasons": {"JE": "fault"}},
		{"panels": [], "initial_breaker_reasons": {"JW": "gremlins"}},
	]
	var want: Array[String] = ["INVALID_ID", "UNKNOWN_TARGET", "BAD_TARGET_KIND", "DUPLICATE_ID", "BAD_REASON", "BAD_REASON"]
	for i: int in bad.size():
		var errs: Array[Dictionary] = MeterModel.new().load_definition(bad[i], _grid)
		assert_eq(errs.size(), 1, "definition %d" % i)
		if errs.size() == 1:
			assert_eq(errs[0]["code"], want[i], "definition %d" % i)


func test_G03_meter_state_is_canonical_and_pure() -> void:
	_meter.inspect("PANEL_JW", _grid)
	assert_ne(PowerGrid.serialize(_meter.canonical_state()), "")
	var src: String = FileAccess.get_file_as_string(METER_SCRIPT)
	for forbidden: String in ["get_node", "get_tree", "Engine.", "extends Node", "OS.", "Time."]:
		assert_false(src.contains(forbidden), "meter_model.gd must not use %s" % forbidden)


# ---------- helpers ----------

func _assert_all_unknown(label: String) -> void:
	var nodes: Dictionary = _grid.canonical_state()["nodes"]
	for pid: String in ["PANEL_GRID", "PANEL_GEN", "PANEL_JW", "PANEL_JE", "PANEL_TEMP"]:
		var r: Dictionary = _meter.readings(pid, _grid)
		assert_true(r.size() > 1, "%s %s has fields" % [label, pid])
		for field: String in r:
			if field == "_panel":
				continue
			assert_eq(r[field]["known"], false, "%s %s.%s known before inspection" % [label, pid, field])
			assert_eq(r[field]["display"], "?", "%s %s.%s" % [label, pid, field])
			assert_false(r[field].has("value"), "%s %s.%s leaks a value" % [label, pid, field])
		assert_eq(_meter.findings(pid, _grid), [] as Array[Dictionary], "%s %s has no evidence yet" % [label, pid])
	assert_true(nodes.size() > 0)


func _run(macro: String) -> void:
	for cmd: Dictionary in Cases.expand([macro], _doc["macros"]):
		var clean: Dictionary = cmd.duplicate()
		clean.erase("expect")
		assert_true(_grid.apply(clean)["ok"], "%s %s" % [macro, str(cmd)])
		_meter.observe(_grid)


func _tick(n: int) -> void:
	for _i: int in n:
		_meter.record_events(_grid.step(), _grid)


func _finding(panel_id: String, code: String) -> Dictionary:
	for f: Dictionary in _meter.findings(panel_id, _grid):
		if f["code"] == code:
			return f
	return {}


func _codes(panel_id: String) -> Array[String]:
	var out: Array[String] = []
	for f: Dictionary in _meter.findings(panel_id, _grid):
		out.append(f["code"])
	out.sort()
	return out
