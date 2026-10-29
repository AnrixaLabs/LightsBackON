extends SceneTree
## Prints every C01 grid case as tab-separated records for tools/cross_check_reference.py.
##   godot --headless --path . -s "$PWD/tools/godot/dump_grid_cases.gd"
## STEP <case> <fwd|rev> <index> <ok|refusal code> <hash after>
## CASE <case> <fwd|rev> <final hash> <final canonical string>
## DEF  <case> <sorted diagnostic codes, comma separated>

const Cases := preload("res://tests/support/grid_cases.gd")
const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")


func _initialize() -> void:
	var doc: Dictionary = Cases.load_doc()
	for c: Dictionary in doc["cases"]:
		for reverse: bool in [false, true]:
			var direction: String = "rev" if reverse else "fwd"
			var r: Dictionary = Cases.run_case(doc, c, reverse)
			var i: int = 0
			for rec: Dictionary in r["log"]:
				var res: Dictionary = rec["result"]
				var outcome: String = "ok" if res["ok"] else str(res["code"])
				if res.has("trips"):
					outcome = "trips:" + ",".join(res["trips"])
				print("\t".join(["STEP", c["name"], direction, str(i), outcome, rec["hash_after"]]))
				i += 1
			var g: PowerGrid = r["grid"]
			print("\t".join(["CASE", c["name"], direction, g.canonical_hash(), g.canonical_string()]))
	for c: Dictionary in doc["definition_cases"]:
		var codes: Array[String] = []
		for e: Dictionary in PowerGrid.new().load_definition(c["definition"]):
			if not codes.has(e["code"]):
				codes.append(e["code"])
		codes.sort()
		print("\t".join(["DEF", c["name"], ",".join(codes)]))
	print("\t".join(["CONTENT", "content_revision", ContentHash.content_revision()]))
	quit(0)
