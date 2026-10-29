extends "res://tests/test_case.gd"
## Base for grid scenario tests: loads tests/data/c01_grid_cases.json and checks a case's step outcomes and end state.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const Cases := preload("res://tests/support/grid_cases.gd")

var _doc: Dictionary


func before_each() -> void:
	_doc = Cases.load_doc()


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
		if cmd["op"] == "tick":
			var want_trips: Array[String] = []
			want_trips.assign(cmd["expect_trips"])
			assert_eq(res["trips"], want_trips, "%s: trips for %s" % [case_name, str(cmd)])
			var want_counters: Dictionary = cmd.get("expect_overload_ticks", {})
			for pid: String in want_counters:
				assert_eq(res["overload_ticks"][pid], int(want_counters[pid]), "%s: counter %s after %s" % [case_name, pid, str(cmd)])
		elif cmd["expect"] == "ok":
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
	if exp.has("tripped"):
		var tripped: Array[String] = []
		for nid: String in st["nodes"]:
			if (st["nodes"][nid] as Dictionary).get("tripped", false):
				tripped.append(nid)
		tripped.sort()
		var want_tripped: Array[String] = []
		want_tripped.assign(exp["tripped"])
		assert_eq(tripped, want_tripped, "%s tripped" % case_name)
	if exp.has("tick"):
		assert_eq(st["tick"], int(exp["tick"]), "%s tick" % case_name)
	var flows: Dictionary = exp.get("flow", {})
	for eid: String in flows:
		assert_eq(st["edges"][eid]["flow"], int(flows[eid]), "%s flow %s" % [case_name, eid])
