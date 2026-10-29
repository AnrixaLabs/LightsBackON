extends RefCounted
## Loads tests/data/c01_grid_cases.json and replays a case against power_grid.gd.
## Mirrors reference/cases.py; used by the G01 tests and tools/godot/dump_grid_cases.gd.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const CASES_PATH: String = "res://tests/data/c01_grid_cases.json"


static func load_doc() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CASES_PATH))


static func find_case(doc: Dictionary, case_name: String) -> Dictionary:
	for c: Dictionary in doc["cases"]:
		if c["name"] == case_name:
			return c
	return {}


static func expand(steps: Array, macros: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Variant in steps:
		if s is String:
			out.append_array(expand(macros[(s as String).substr(1)], macros))
		else:
			out.append(s)
	return out


static func definition_for(doc: Dictionary, case: Dictionary, reverse: bool) -> Dictionary:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(doc["definition"]))
	var patch: Dictionary = case.get("patch", {})
	for group: String in ["nodes", "edges"]:
		for rec: Dictionary in d[group]:
			if patch.has(rec["id"]):
				rec.merge(patch[rec["id"]], true)
		if reverse:
			(d[group] as Array).reverse()
	return d


## Returns {"grid": PowerGrid, "load_errors": Array, "log": Array of {cmd, result, hash_before, hash_after}}.
static func run_case(doc: Dictionary, case: Dictionary, reverse: bool) -> Dictionary:
	var g: PowerGrid = PowerGrid.new()
	var errs: Array[Dictionary] = g.load_definition(definition_for(doc, case, reverse))
	var log: Array[Dictionary] = []
	if errs.is_empty():
		for cmd: Dictionary in expand(case["steps"], doc["macros"]):
			var clean: Dictionary = {}
			for k: String in cmd:
				if not k.begins_with("expect"):
					clean[k] = cmd[k]
			var before: String = g.canonical_hash()
			var res: Dictionary = g.apply(clean)
			log.append({"cmd": cmd, "result": res, "hash_before": before, "hash_after": g.canonical_hash()})
	return {"grid": g, "load_errors": errs, "log": log}
