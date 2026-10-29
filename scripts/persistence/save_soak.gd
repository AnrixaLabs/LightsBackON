extends Node
## G06 real-process kill test (SAVE01), internal builds only. The driver (tools/save_kill_test.py) starts the exported game
## with `-- --save-soak`, hard-kills it at a random moment, then runs `-- --save-verify` and checks a save still loads.
##
## --save-soak    keep rewriting one checkpoint through SaveService, one write per frame, sequence number increasing,
##                continuing from whatever the last run left (so post-crash recovery inside write_record is exercised too).
## --save-verify  read the checkpoint once, print one VERIFY line (source, seq, issues, state of each file) and quit.
##
## Boot only adds this node when the build has the "internal" feature (or runs from the editor binary): release exports
## never contain a path that writes test saves (CLAUDE.md section 9, debug tools only in internal exports).

const SaveService := preload("res://scripts/persistence/save_service.gd")

const ARG_SOAK: String = "--save-soak"
const ARG_VERIFY: String = "--save-verify"
const ACCOUNT_KEY: String = "soak-test"
const CAMPAIGN_ID: String = "c01_soak"
const KIND: String = "checkpoint_soak"
## Small enough for many writes per second (canonical serialization in GDScript dominates a write), large enough that the temp
## file takes several OS write calls, so random kills land in every phase of write_record, not only between writes.
const BLOB_BYTES: int = 1 << 16

var _save: SaveService = SaveService.new()
var _path: String = ""
var _seq: int = 0
var _blob: String = ""


static func allowed() -> bool:
	return OS.has_feature("internal") or OS.has_feature("editor")


static func requested_mode(args: PackedStringArray) -> String:
	for a: String in args:
		if a == ARG_SOAK or a == ARG_VERIFY:
			return a
	return ""


## path_override is for unit tests, which share user:// with the exported build.
func setup(build_id: String, path_override: String = "") -> void:
	var versions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/versions.json"))
	_save.configure(int(versions["save_schema_version"]), build_id, "soak")
	_path = path_override if path_override != "" else SaveService.checkpoint_path(ACCOUNT_KEY, CAMPAIGN_ID)


func path() -> String:
	return _path


## One-shot read for the driver. Returns the process exit code: 0 = a valid save loaded, 1 = none did.
func verify() -> int:
	var r: Dictionary = _save.read_record(_path)
	var files: Dictionary = _save.inspect_files(_path)
	var states: String = "current:%s,temp:%s,backup:%s" % [files["current"], files["temp"], files["backup"]]
	if r["ok"]:
		print("VERIFY ok=true source=%s seq=%d issues=%s files=%s" % [r["source"], int(r["payload"]["seq"]),
			",".join(r["issues"]), states])
		return 0
	print("VERIFY ok=false code=%s issues=%s files=%s" % [r["code"], ",".join(r.get("issues", [])), states])
	return 1


func start_soak() -> void:
	var r: Dictionary = _save.read_record(_path)
	_seq = int(r["payload"]["seq"]) if r["ok"] else 0
	_blob = "x".repeat(BLOB_BYTES)
	print("SOAK start seq=%d path=%s" % [_seq, ProjectSettings.globalize_path(_path)])
	set_process(true)


## One write. Public so the unit test can drive it without a frame loop.
func write_next() -> Dictionary:
	var next: int = _seq + 1
	var res: Dictionary = _save.write_record(_path, KIND, CAMPAIGN_ID, {"seq": next, "blob": _blob},
		Time.get_datetime_string_from_system(true) + "Z")
	if res["ok"]:
		_seq = next
	else:
		push_error("SOAK write failed: %s" % str(res))
	return res


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	write_next()
