extends "res://tests/test_case.gd"
## G01: pure grid evaluation against the re-derived C01 scenarios (tests/data/c01_grid_cases.json).
## The same scenarios run in reference/tests; tools/cross_check_reference.py compares the canonical bytes.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const Cases := preload("res://tests/support/grid_cases.gd")
const POWER_GRID_PATH: String = "res://scripts/simulation/power_grid.gd"

var _doc: Dictionary


func before_each() -> void:
	_doc = Cases.load_doc()


func test_SIM01_initial_graph_supplies_nothing() -> void:
	_check("SIM01_initial_graph")


func test_SIM02_west_repair_supplies_9_pu() -> void:
	_check("SIM02_west_repaired")


func test_SIM03_pump_only_from_generator_static() -> void:
	_check("SIM03_pump_only_from_generator")


func test_SIM04_pump_and_pub_overload_generator_static() -> void:
	_check("SIM04_pump_and_pub_on_generator_static")


func test_SIM05_sign_overloads_east_edge_not_grid() -> void:
	_check("SIM05_sign_after_required_repairs")


func test_SIM06_second_energized_pub_route_refused_before_mutation() -> void:
	_check("SIM06_second_energized_pub_route_refused")
	_check("SIM06_east_repair_refused_while_pub_on_temp")


func test_SIM07_command_backfeed_cycle_and_invalid_ids_refused() -> void:
	_check("SIM07_command_backfeed_cycle_and_bad_ids_refused")


func test_SIM07_SIM06_invalid_definitions_rejected() -> void:
	for c: Dictionary in _doc["definition_cases"]:
		var g: PowerGrid = PowerGrid.new()
		var errs: Array[Dictionary] = g.load_definition(c["definition"])
		var codes: Array[String] = []
		for e: Dictionary in errs:
			codes.append(e["code"])
			assert_false(str(e["message"]).is_empty(), "%s: diagnostic needs a message" % c["name"])
		assert_true(codes.has(c["expect"]), "%s: expected %s, got %s" % [c["name"], c["expect"], str(codes)])


func test_SIM08_equality_is_not_overload() -> void:
	_check("SIM08_edge_demand_equal_to_capacity")
	_check("SIM08_source_demand_equal_to_capacity")


func test_SIM11_reversed_input_order_gives_identical_canonical_bytes() -> void:
	for c: Dictionary in _doc["cases"]:
		var fwd: PowerGrid = Cases.run_case(_doc, c, false)["grid"]
		var rev: PowerGrid = Cases.run_case(_doc, c, true)["grid"]
		assert_eq(rev.canonical_string(), fwd.canonical_string(), "SIM11 %s" % c["name"])


func test_C01_known_solution_final_grid() -> void:
	_check("C01_known_solution_final_grid")


func test_G01_canonical_serializer_golden_bytes() -> void:
	var v: Dictionary = {"b": [1, true, "x\"y\\"], "a": {"Z": false, "A": -3}, "_": 0}
	assert_eq(PowerGrid.serialize(v), "{\"_\":0,\"a\":{\"A\":-3,\"Z\":false},\"b\":[1,true,\"x\\\"y\\\\\"]}")
	for bad: Variant in [1.0, null, "é", "\n", {1: true}]:
		assert_eq(PowerGrid.serialize(bad), "", "not canonical: %s" % str(bad))


func test_G01_canonical_state_has_only_ints_bools_strings() -> void:
	var r: Dictionary = Cases.run_case(_doc, Cases.find_case(_doc, "SIM05_sign_after_required_repairs"), false)
	var g: PowerGrid = r["grid"]
	assert_ne(g.canonical_string(), "")
	assert_eq(g.canonical_hash().length(), 64)


func test_G01_power_grid_has_no_scene_tree_or_autoload_access() -> void:
	var code: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(POWER_GRID_PATH).split("\n"):
		var hash_at: int = line.find("#")
		code.append(line if hash_at < 0 else line.substr(0, hash_at))  # comments may name what is forbidden
	var src: String = "\n".join(code)
	for forbidden: String in ["get_node", "get_tree", "Engine.", "Steam", "extends Node", "OS.", "Time.", "randi", "randf"]:
		assert_false(src.contains(forbidden), "power_grid.gd must not use %s" % forbidden)
	var node_path_sugar := RegEx.create_from_string("\\$[A-Za-z%]")
	assert_true(node_path_sugar.search(src) == null, "power_grid.gd must not use $NodePath lookups")


func _check(case_name: String) -> void:
	var c: Dictionary = Cases.find_case(_doc, case_name)
	assert_false(c.is_empty(), "case %s missing" % case_name)
	if c.is_empty():
		return
	var r: Dictionary = Cases.run_case(_doc, c, false)
	assert_true((r["load_errors"] as Array).is_empty(), "%s load: %s" % [case_name, str(r["load_errors"])])
	for rec: Dictionary in r["log"]:
		var cmd: Dictionary = rec["cmd"]
		var res: Dictionary = rec["result"]
		if cmd["expect"] == "ok":
			assert_true(res["ok"], "%s: %s refused: %s" % [case_name, str(cmd), str(res)])
		else:
			assert_false(res["ok"], "%s: %s should be refused" % [case_name, str(cmd)])
			assert_eq(res.get("code", ""), cmd["expect"], "%s: %s" % [case_name, str(cmd)])
			var want_ids: Array[String] = []
			want_ids.assign(cmd.get("expect_ids", []))
			want_ids.sort()
			assert_eq(res.get("ids", []), want_ids, "%s: ids for %s" % [case_name, str(cmd)])
			assert_eq(rec["hash_after"], rec["hash_before"], "%s: refused command mutated state" % case_name)
	var g: PowerGrid = r["grid"]
	var st: Dictionary = g.canonical_state()
	var exp: Dictionary = c["expect"]
	var supplied: Array[String] = []
	for nid: String in st["nodes"]:
		if (st["nodes"][nid] as Dictionary).get("supplied", false):
			supplied.append(nid)
	supplied.sort()
	var want_supplied: Array[String] = []
	want_supplied.assign(exp["supplied"])
	assert_eq(supplied, want_supplied, "%s supplied" % case_name)
	var want_over: Array[String] = []
	want_over.assign(exp["overloaded"])
	assert_eq(g.overloads(), want_over, "%s overloaded" % case_name)
	var loads: Dictionary = exp.get("load", {})
	for nid: String in loads:
		assert_eq(st["nodes"][nid]["load"], int(loads[nid]), "%s load %s" % [case_name, nid])
	var flows: Dictionary = exp.get("flow", {})
	for eid: String in flows:
		assert_eq(st["edges"][eid]["flow"], int(flows[eid]), "%s flow %s" % [case_name, eid])
