extends "res://tests/test_case.gd"
## G06 local: the kill-test hooks (save_soak.gd) behave in-process. The real-process result comes from tools/save_kill_test.py.

const SaveSoak := preload("res://scripts/persistence/save_soak.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")

var _dir: String
var _path: String


func before_each() -> void:
	_dir = "user://test_saves/soak_%d_%d" % [Time.get_ticks_usec(), randi()]
	_path = _dir.path_join("checkpoint.json")


func after_each() -> void:
	for suffix: String in ["", SaveService.TMP_SUFFIX, SaveService.BAK_SUFFIX]:
		DirAccess.remove_absolute(_path + suffix)
	DirAccess.remove_absolute(_dir)


func test_SAVE01_soak_writes_increasing_sequence_and_verify_reads_it() -> void:
	var soak: SaveSoak = _soak()
	assert_eq(soak.verify(), 1, "nothing saved yet")
	soak.start_soak()
	for i: int in 3:
		assert_true(soak.write_next()["ok"], "write %d" % i)
	assert_eq(soak.verify(), 0)
	var r: Dictionary = _reader().read_record(_path)
	assert_eq(int(r["payload"]["seq"]), 3)
	assert_eq(str(r["source"]), "current")
	soak.free()


func test_SAVE01_soak_continues_from_the_saved_sequence_after_a_crash() -> void:
	var first: SaveSoak = _soak()
	first.start_soak()
	first.write_next()
	first.write_next()
	first.free()
	# crash shape: half-written temp next to a valid current
	var f: FileAccess = FileAccess.open(_path + SaveService.TMP_SUFFIX, FileAccess.WRITE)
	f.store_string("{\"schema_version\":1,\"bu")
	f.close()
	var files: Dictionary = _reader().inspect_files(_path)
	assert_eq(files, {"current": "ok", "temp": "corrupt", "backup": "ok"})
	var second: SaveSoak = _soak()
	second.start_soak()
	assert_true(second.write_next()["ok"], "write after the crash replaces the stale temp")
	assert_eq(int(_reader().read_record(_path)["payload"]["seq"]), 3)
	assert_eq(_reader().inspect_files(_path)["temp"], "missing")
	second.free()


func test_SAVE01_soak_only_runs_on_request_and_in_internal_or_editor_builds() -> void:
	assert_eq(SaveSoak.requested_mode(PackedStringArray()), "")
	assert_eq(SaveSoak.requested_mode(PackedStringArray(["--other", "--save-soak"])), SaveSoak.ARG_SOAK)
	assert_eq(SaveSoak.requested_mode(PackedStringArray(["--save-verify"])), SaveSoak.ARG_VERIFY)
	assert_eq(SaveSoak.allowed(), OS.has_feature("internal") or OS.has_feature("editor"))
	var presets: String = FileAccess.get_file_as_string("res://export_presets.cfg")
	var release: String = presets.get_slice("[preset.1]", 0)
	assert_true(release.contains("name=\"Windows Desktop\"") and release.contains("custom_features=\"\""),
		"the release preset carries no internal feature")
	assert_true(presets.get_slice("[preset.1]", 1).contains("custom_features=\"internal\""), "the internal preset does")


func _soak() -> SaveSoak:
	var s: SaveSoak = SaveSoak.new()
	s.setup("test-build", _path)
	return s


func _reader() -> SaveService:
	var s: SaveService = SaveService.new()
	s.configure(1, "test-build", "soak")
	return s
