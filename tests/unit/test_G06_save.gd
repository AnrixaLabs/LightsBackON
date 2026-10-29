extends "res://tests/test_case.gd"
## G06: versioned save skeleton. SAVE01-SAVE03 at logic level (fault injection inside the writer, not a real process kill).

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const Codec := preload("res://scripts/persistence/checkpoint_codec.gd")
const Cases := preload("res://tests/support/grid_cases.gd")
const C01: String = "res://content/contracts/c01_alder_street/"
const NOW: String = "2026-10-29T08:00:00Z"
const LATER: String = "2026-10-29T08:01:00Z"

var _dir: String
var _path: String
var _svc: SaveService


func before_each() -> void:
	_dir = "user://test_saves/run_%d_%d" % [Time.get_ticks_usec(), randi()]
	_path = _dir.path_join("checkpoints").path_join("CAMPAIGN_TEST.json")
	_svc = _service(1)


func after_each() -> void:
	_rm_tree(_dir)


func test_SAVE01_kill_during_temp_write_keeps_current() -> void:
	_ok(_svc.write_record(_path, "checkpoint", "CP", {"v": 1}, NOW))
	assert_eq(_svc.write_record(_path, "checkpoint", "CP", {"v": 2}, LATER, SaveService.FAULT_PARTIAL_TMP)["code"], "SIMULATED_CRASH")
	var r: Dictionary = _svc.read_record(_path)
	assert_eq(r["source"], "current")
	assert_eq(r["payload"], {"v": 1})


func test_SAVE01_kill_after_temp_complete_keeps_current() -> void:
	_ok(_svc.write_record(_path, "checkpoint", "CP", {"v": 1}, NOW))
	_svc.write_record(_path, "checkpoint", "CP", {"v": 2}, LATER, SaveService.FAULT_AFTER_TMP)
	var r: Dictionary = _svc.read_record(_path)
	assert_eq(r["source"], "current", "progress loss bounded by one checkpoint")
	assert_eq(r["payload"], {"v": 1})
	_ok(_svc.write_record(_path, "checkpoint", "CP", {"v": 3}, LATER))
	assert_eq(_svc.read_record(_path)["payload"], {"v": 3}, "a later save replaces the stale temp file")


func test_SAVE01_kill_between_backup_and_rename_loads_complete_temp() -> void:
	_ok(_svc.write_record(_path, "checkpoint", "CP", {"v": 1}, NOW))
	_svc.write_record(_path, "checkpoint", "CP", {"v": 2}, LATER, SaveService.FAULT_AFTER_BACKUP)
	assert_false(FileAccess.file_exists(_path), "crash point leaves no current file")
	var r: Dictionary = _svc.read_record(_path)
	assert_eq(r["source"], "temp")
	assert_eq(r["payload"], {"v": 2})
	assert_true(FileAccess.file_exists(_path + SaveService.BAK_SUFFIX), "previous valid save kept as backup")


func test_SAVE02_truncated_current_recovers_backup_visibly() -> void:
	_ok(_svc.write_record(_path, "checkpoint", "CP", {"v": 1}, NOW))
	_ok(_svc.write_record(_path, "checkpoint", "CP", {"v": 2}, LATER))
	var text: String = FileAccess.get_file_as_string(_path)
	_write_raw(_path, text.substr(0, text.length() - 20))
	var r: Dictionary = _svc.read_record(_path)
	assert_eq(r["ok"], true)
	assert_eq(r["source"], "backup")
	assert_eq(r["payload"], {"v": 1})
	assert_eq(r["issues"], ["CURRENT_CORRUPT"] as Array[String], "recovery is reported, not silent")


func test_SAVE02_checksum_catches_edited_value() -> void:
	_ok(_svc.write_record(_path, "checkpoint", "CP", {"v": 1}, NOW))
	_ok(_svc.write_record(_path, "checkpoint", "CP", {"v": 2}, LATER))
	_write_raw(_path, FileAccess.get_file_as_string(_path).replace("\"v\":2", "\"v\":7"))
	var r: Dictionary = _svc.read_record(_path)
	assert_eq(r["source"], "backup")
	assert_eq(r["issues"], ["CURRENT_CORRUPT"] as Array[String])


func test_SAVE03_newer_schema_refused_and_bytes_preserved() -> void:
	_ok(_service(2).write_record(_path, "checkpoint", "CP", {"v": 9}, NOW))
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_path)
	var r: Dictionary = _svc.read_record(_path)
	assert_eq(r["ok"], false)
	assert_eq(r["code"], "NEWER_SCHEMA")
	assert_eq(r["key"], "save.error.newer_schema")
	var w: Dictionary = _svc.write_record(_path, "checkpoint", "CP", {"v": 1}, LATER)
	assert_eq(w["code"], "TARGET_NEWER_SCHEMA")
	assert_eq(FileAccess.get_file_as_bytes(_path), bytes, "newer save never overwritten")


func test_G06_unreadable_current_is_moved_aside_not_erased() -> void:
	DirAccess.make_dir_recursive_absolute(_path.get_base_dir())
	_write_raw(_path, "{not json")
	var w: Dictionary = _svc.write_record(_path, "checkpoint", "CP", {"v": 1}, NOW)
	_ok(w)
	assert_eq((w["issues"] as Array).size(), 1)
	var aside: String = _path + SaveService.UNREADABLE_SUFFIX + NOW.replace(":", "")
	assert_eq(FileAccess.get_file_as_string(aside), "{not json", "original bytes kept")
	assert_eq(_svc.read_record(_path)["payload"], {"v": 1})


func test_G06_envelope_fields_and_canonical_payload_only() -> void:
	var svc: SaveService = SaveService.new()
	svc.configure(1, "20261029T075355Z-abc", "c0ffee")
	_ok(svc.write_record(_path, "checkpoint", "CP_1", {"v": 1}, NOW))
	var env: Dictionary = svc.read_record(_path)["envelope"]
	for field: String in ["schema_version", "build_id", "content_revision", "saved_at_utc", "kind", "record_id", "checksum"]:
		assert_true(env.has(field), "envelope has %s" % field)
	assert_eq(env["build_id"], "20261029T075355Z-abc")
	assert_eq(env["saved_at_utc"], NOW)
	assert_eq(svc.write_record(_path, "checkpoint", "CP", {"v": 1.5}, NOW)["code"], "NOT_CANONICAL")
	assert_eq(svc.read_record(_dir.path_join("none.json"))["code"], "NOT_FOUND")


func test_G06_checkpoint_round_trip_recomputes_derived_state() -> void:
	var a: Dictionary = _mission()
	var grid: PowerGrid = a["grid"]
	var inter: Interaction = a["interaction"]
	var eq: Equipment = a["equipment"]
	# west repaired through the repair state machine, generator running the pump, sign overloading east for 7 ticks
	_west_repair(a)
	_ok(eq.handle("P1", {"type": "pickup", "item": "GEN_PORTABLE", "in_range": true}))
	_ok(eq.handle("P1", {"type": "place", "item": "GEN_PORTABLE", "anchor": "PAD_PUMP", "in_range": true}))
	_ok(eq.handle("P1", {"type": "connect", "item": "GEN_PORTABLE", "route": "E_TEMP_PUMP", "in_range": true}))
	_ok(eq.handle("P1", {"type": "start", "item": "GEN_PORTABLE", "in_range": true}))
	for _i: int in 7:
		grid.step()
	var payload: Dictionary = Codec.encode("CAMPAIGN_TEST", "C01", grid, inter, eq)
	var text: String = PowerGrid.serialize(payload)
	for derived: String in ["\"supplied\"", "\"flow\"", "\"load\"", "\"energized\""]:
		assert_false(text.contains(derived), "checkpoint stores causes only, not %s" % derived)
	_ok(_svc.write_record(_path, Codec.KIND, "CAMPAIGN_TEST", payload, NOW))
	var b: Dictionary = _mission()
	var errs: Array[Dictionary] = Codec.restore(_svc.read_record(_path)["payload"], "C01", b["grid"], b["interaction"], b["equipment"])
	assert_true(errs.is_empty(), str(errs))
	assert_eq((b["grid"] as PowerGrid).canonical_string(), grid.canonical_string(), "derived power state identical after load")
	assert_eq((b["interaction"] as Interaction).repair_state("R_JW_FUSE"), "restored")
	assert_eq((b["interaction"] as Interaction).supply("FUSE_W"), 0, "no replacement handed back by a reload")
	assert_eq((b["equipment"] as Equipment).anchor_of("GEN_PORTABLE"), "PAD_PUMP")
	var meter: MeterModel = b["meter"]
	assert_eq(meter.readings("PANEL_JW", b["grid"])["load_pu"]["display"], "?", "meter starts unknown after a load")


func test_G06_restore_from_other_content_is_refused_without_change() -> void:
	var a: Dictionary = _mission()
	var payload: Dictionary = Codec.encode("CAMPAIGN_TEST", "C01", a["grid"], a["interaction"], a["equipment"])
	(payload["grid"]["nodes"] as Dictionary)["GHOST"] = {"online": true}
	var b: Dictionary = _mission()
	var before: String = (b["grid"] as PowerGrid).canonical_string()
	var errs: Array[Dictionary] = Codec.restore(payload, "C01", b["grid"], b["interaction"], b["equipment"])
	assert_eq(errs[0]["code"], "UNKNOWN_ID")
	assert_eq((b["grid"] as PowerGrid).canonical_string(), before)
	assert_eq(Codec.restore(payload, "C02", b["grid"], b["interaction"], b["equipment"])[0]["code"], "BAD_SAVE")


func test_G06_profile_paths_follow_the_contract() -> void:
	assert_eq(SaveService.checkpoint_path("k3y_01", "CAMP_A"), "user://profiles/k3y_01/checkpoints/CAMP_A.json")
	assert_true(SaveService.is_valid_key("a1b2-c3"))
	assert_false(SaveService.is_valid_key("../evil"))
	assert_false(SaveService.is_valid_key(""))


# ---------- helpers ----------

func _service(schema: int) -> SaveService:
	var s: SaveService = SaveService.new()
	s.configure(schema, "test-build", "test-content")
	return s


func _ok(res: Dictionary) -> void:
	assert_true(res["ok"], str(res))


func _write_raw(path: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _mission() -> Dictionary:
	var grid: PowerGrid = PowerGrid.new()
	grid.load_definition(Cases.definition_for(Cases.load_doc(), {}, false))
	var meter: MeterModel = MeterModel.new()
	meter.load_definition(_json(C01 + "meter.json"), grid)
	var inter: Interaction = Interaction.new()
	inter.load_definition(_json("res://content/interaction.json"), _json(C01 + "repairs.json"), grid, meter)
	inter.join("P1", ["screwdriver", "puller", "cutter", "crimper", "meter"] as Array[String])
	var eq: Equipment = Equipment.new()
	eq.load_definition(_json(C01 + "equipment.json"), grid, meter)
	return {"grid": grid, "meter": meter, "interaction": inter, "equipment": eq}


func _west_repair(m: Dictionary) -> void:
	var inter: Interaction = m["interaction"]
	_ok(inter.handle("P1", {"type": "request_lock", "repair": "R_JW_FUSE", "in_range": true}))
	(m["meter"] as MeterModel).inspect("PANEL_JW", m["grid"])
	var tools: Dictionary = {"open": "screwdriver", "remove": "puller", "install": "puller", "test": "meter"}
	for step: String in Interaction.STEPS:
		_ok(inter.handle("P1", {"type": "equip", "tool": tools.get(step, "")}))
		_ok(inter.handle("P1", {"type": "repair_step", "repair": "R_JW_FUSE", "step": step, "in_range": true}))


func _rm_tree(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	for f: String in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub: String in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
