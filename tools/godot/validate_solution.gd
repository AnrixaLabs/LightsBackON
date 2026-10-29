extends SceneTree
## Replays a contract's solution trace through the host and checks the mission completes within max_ticks.
##   godot --headless --path . -s "$PWD/tools/godot/validate_solution.gd" -- --contract=res://content/contracts/c01_alder_street
## Exit 0 = solved, 1 = not solved (mismatches printed), 2 = content errors.

const Runner := preload("res://tests/support/solution_runner.gd")


func _initialize() -> void:
	var dir: String = "res://content/contracts/c01_alder_street"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--contract="):
			dir = a.trim_prefix("--contract=")
	var trace: Dictionary = Runner.json(dir.path_join("solution.json"))
	var ctx: Dictionary = Runner.build(dir, trace["players"], trace["tools"])
	if not (ctx["errors"] as Array).is_empty():
		print("CONTENT ERRORS: %s" % str(ctx["errors"]))
		quit(2)
		return
	var failures: Array[String] = Runner.run(ctx, trace["steps"], int(trace.get("pace_ticks_per_command", 0)))
	var done: bool = ctx["mission"].is_complete()
	if done and failures.is_empty() and int(ctx["now"]) <= int(trace["max_ticks"]):
		print("SOLVED %s in %d ticks (%d steps)" % [trace["contract_id"], int(ctx["now"]), (trace["steps"] as Array).size()])
		quit(0)
		return
	for f: String in failures:
		print("MISMATCH " + f)
	print("NOT SOLVED %s: complete=%s ticks=%d" % [trace["contract_id"], str(done), int(ctx["now"])])
	quit(1)
