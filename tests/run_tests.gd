extends SceneTree
## Minimal headless test runner with no third-party addons.
##
##   godot --headless --path . -s res://tests/run_tests.gd -- [--filter=text] [--dir=res://tests]
##
## Finds every res://tests/**/test_*.gd, instantiates it, and runs each method whose
## name starts with "test_". Exit code 0 = all passed, 1 = failures, 2 = runner error.
## Name test methods after the acceptance-matrix ID where one exists, e.g. test_SIM08_equality_is_not_overload.

const TEST_CASE_PATH := "res://tests/test_case.gd"


func _initialize() -> void:
	var filter := ""
	var root_dir := "res://tests"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
		elif a.begins_with("--dir="):
			root_dir = a.trim_prefix("--dir=")
	# the root window joins the tree after _initialize starts; scene tests (V01) need its World3D for physics queries
	await process_frame
	quit(_run(root_dir, filter))


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	var names: Array[String] = []
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if n != "." and n != "..":
			names.append(n)
		n = d.get_next()
	d.list_dir_end()
	names.sort()  # deterministic order
	for name in names:
		var p := dir_path.path_join(name)
		if DirAccess.dir_exists_absolute(p):
			_collect(p, out)
		elif name.begins_with("test_") and name.ends_with(".gd") and p != TEST_CASE_PATH:
			out.append(p)


func _run(root_dir: String, filter: String) -> int:
	var files: Array[String] = []
	_collect(root_dir, files)
	var n_pass := 0
	var n_fail := 0
	var n_assert := 0
	var report: Array[String] = []
	for path in files:
		var script := load(path) as GDScript
		if script == null:
			print("RUNNER ERROR: cannot load %s" % path)
			return 2
		var method_names: Array[String] = []
		for m in script.get_script_method_list():
			var mn: String = m["name"]
			if mn.begins_with("test_"):
				method_names.append(mn)
		method_names.sort()
		for mn in method_names:
			if filter != "" and not (path.contains(filter) or mn.contains(filter)):
				continue
			var t = script.new()
			t.before_each()
			t.call(mn)
			t.after_each()
			n_assert += t.assertions
			if t.failures.is_empty() and t.assertions > 0:
				n_pass += 1
				print("  PASS  %s::%s" % [path.get_file(), mn])
			else:
				n_fail += 1
				if t.assertions == 0:
					t.failures.append("test made no assertions")
				print("  FAIL  %s::%s" % [path.get_file(), mn])
				for f in t.failures:
					print("        - %s" % f)
	print("tests: %d passed, %d failed, %d assertions" % [n_pass, n_fail, n_assert])
	if n_pass + n_fail == 0:
		print("no tests ran (filter='%s')" % filter)
		return 2 if filter != "" else 0
	return 0 if n_fail == 0 else 1
