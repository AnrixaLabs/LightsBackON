extends RefCounted
## Versioned save files (G06; blueprint p.10 "Save and progression contract", CLAUDE.md section 5).
##
## Every record is one canonical-JSON envelope: schema_version, build_id, content_revision, saved_at_utc, kind,
## record_id, payload and a SHA-256 checksum over everything else. The checksum detects corruption; it is not anti-cheat.
##
## write_record(): refuse to replace a newer-schema file; move an unreadable current file aside instead of erasing it;
## write <name>.tmp in the same directory, flush and close, read it back and verify; keep the previous valid file as
## <name>.bak; then rename the temp file into place. A crash at any point leaves a valid current, temp or backup file.
## read_record(): current, then a complete temp, then backup; any fallback is reported in "issues", never silent.
##
## Engine file APIs only (no scene tree, no autoloads). Godot exposes flush but no fsync, so durability against
## power loss is up to the OS; process kills are covered by the temp/backup scheme.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const TMP_SUFFIX: String = ".tmp"
const BAK_SUFFIX: String = ".bak"
const UNREADABLE_SUFFIX: String = ".unreadable-"
const PROFILES_ROOT: String = "user://profiles"
const ENVELOPE_FIELDS: Array[String] = ["schema_version", "build_id", "content_revision", "saved_at_utc", "kind", "record_id", "payload"]
## Test-only crash points for write_record (SAVE01 fault injection).
const FAULT_PARTIAL_TMP: String = "partial_tmp"
const FAULT_AFTER_TMP: String = "after_tmp"
const FAULT_AFTER_BACKUP: String = "after_backup"

var _schema_version: int = 0
var _build_id: String = ""
var _content_revision: String = ""


## schema_version from content/versions.json; build_id and content_revision from build_manifest.json.
func configure(schema_version: int, build_id: String, content_revision: String) -> void:
	_schema_version = schema_version
	_build_id = build_id
	_content_revision = content_revision


## account_key is a random or hashed local key, never a raw Steam ID (CLAUDE.md section 9).
static func profile_dir(account_key: String) -> String:
	return PROFILES_ROOT.path_join(account_key)


static func checkpoint_path(account_key: String, campaign_id: String) -> String:
	return profile_dir(account_key).path_join("checkpoints").path_join(campaign_id + ".json")


static func is_valid_key(key: String) -> bool:
	if key.is_empty() or key.length() > 64:
		return false
	for i: int in key.length():
		var c: int = key.unicode_at(i)
		if not ((c >= 0x61 and c <= 0x7A) or (c >= 0x30 and c <= 0x39) or c == 0x5F or c == 0x2D or (c >= 0x41 and c <= 0x5A)):
			return false
	return true


## Returns {"ok": true, "issues": [...]} or {"ok": false, "code", "message"}. saved_at_utc is "YYYY-MM-DDTHH:MM:SSZ".
func write_record(path: String, kind: String, record_id: String, payload: Dictionary, saved_at_utc: String,
		fault: String = "") -> Dictionary:
	var envelope: Dictionary = {"schema_version": _schema_version, "build_id": _build_id, "content_revision": _content_revision,
		"saved_at_utc": saved_at_utc, "kind": kind, "record_id": record_id, "payload": payload}
	var body: String = PowerGrid.serialize(envelope)
	if body == "":
		return _fail("NOT_CANONICAL", "save payload must hold only ints, bools, ASCII strings, arrays and objects")
	envelope["checksum"] = body.sha256_text()
	var text: String = PowerGrid.serialize(envelope)
	var issues: Array[String] = []
	var dir: String = path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(dir) != OK:
		return _fail("WRITE_FAILED", "cannot create the save folder")
	var current: Dictionary = _inspect(path)
	if current["status"] == "newer_schema":
		return _fail("TARGET_NEWER_SCHEMA", "the existing save was written by a newer version; it was left untouched")
	if current["status"] == "corrupt":
		var aside: String = path + UNREADABLE_SUFFIX + saved_at_utc.replace(":", "")
		if DirAccess.rename_absolute(path, aside) != OK:
			return _fail("WRITE_FAILED", "cannot move the unreadable save aside")
		issues.append("CURRENT_UNREADABLE_KEPT_AS:" + aside.get_file())
	var tmp: String = path + TMP_SUFFIX
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return _fail("WRITE_FAILED", "cannot open the temp save file")
	if fault == FAULT_PARTIAL_TMP:
		f.store_string(text.substr(0, text.length() / 2))
		f.close()
		return _fail("SIMULATED_CRASH", fault)
	f.store_string(text)
	f.flush()
	f.close()
	if _inspect(tmp)["status"] != "ok":
		DirAccess.remove_absolute(tmp)
		return _fail("WRITE_FAILED", "temp file did not verify after writing")
	if fault == FAULT_AFTER_TMP:
		return _fail("SIMULATED_CRASH", fault)
	var bak: String = path + BAK_SUFFIX
	if FileAccess.file_exists(path):
		# only a valid current file reaches here; it becomes the one previous backup
		if FileAccess.file_exists(bak) and DirAccess.remove_absolute(bak) != OK:
			return _fail("WRITE_FAILED", "cannot replace the old backup")
		if DirAccess.rename_absolute(path, bak) != OK:
			return _fail("WRITE_FAILED", "cannot keep the previous save as backup")
	if fault == FAULT_AFTER_BACKUP:
		return _fail("SIMULATED_CRASH", fault)
	if DirAccess.rename_absolute(tmp, path) != OK:
		return _fail("WRITE_FAILED", "cannot move the new save into place")
	return {"ok": true, "issues": issues}


## Returns {"ok": true, "envelope", "payload", "source": current|temp|backup, "issues"} or
## {"ok": false, "code": NOT_FOUND|NEWER_SCHEMA|CORRUPT, "message", "issues"}. Never modifies files.
func read_record(path: String) -> Dictionary:
	var issues: Array[String] = []
	var any_file: bool = false
	for pair: Array in [[path, "current"], [path + TMP_SUFFIX, "temp"], [path + BAK_SUFFIX, "backup"]]:
		var p: String = pair[0]
		var source: String = pair[1]
		var r: Dictionary = _inspect(p)
		match r["status"]:
			"missing":
				continue
			"ok":
				return {"ok": true, "envelope": r["envelope"], "payload": r["envelope"]["payload"], "source": source, "issues": issues}
			"newer_schema":
				# refuse instead of falling back to an older copy: the newer file is the player's real progress (SAVE03)
				var res: Dictionary = _fail("NEWER_SCHEMA", "%s save needs a newer version of the game" % source)
				res["issues"] = issues
				return res
			_:
				any_file = true
				issues.append(source.to_upper() + "_CORRUPT")
	var out: Dictionary = _fail("CORRUPT" if any_file else "NOT_FOUND", "no readable save at %s" % path.get_file())
	out["issues"] = issues
	return out


## status: missing | ok | corrupt | newer_schema; "envelope" when ok.
func _inspect(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing"}
	var json: JSON = JSON.new()  # instance parse reports errors without engine log noise for expected corruption
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"status": "corrupt"}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		return {"status": "corrupt"}
	var env: Dictionary = _ints(parsed)
	for field: String in ENVELOPE_FIELDS:
		if not env.has(field):
			return {"status": "corrupt"}
	if not (env["schema_version"] is int and env.get("checksum") is String):
		return {"status": "corrupt"}
	if int(env["schema_version"]) > _schema_version:
		return {"status": "newer_schema"}
	var unsigned: Dictionary = env.duplicate()
	unsigned.erase("checksum")
	var body: String = PowerGrid.serialize(unsigned)
	if body == "" or body.sha256_text() != env["checksum"]:
		return {"status": "corrupt"}
	return {"status": "ok", "envelope": env}


## JSON numbers arrive as float; canonical saves only contain ints, so integral floats become ints again.
static func _ints(v: Variant) -> Variant:
	if v is float:
		var as_int: Variant = PowerGrid.to_int(v)
		return as_int if as_int != null else v
	if v is Array:
		var out: Array = []
		for x: Variant in v:
			out.append(_ints(x))
		return out
	if v is Dictionary:
		var d: Dictionary = {}
		for k: Variant in v:
			d[k] = _ints(v[k])
		return d
	return v


static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "key": "save.error." + code.to_lower(), "message": message}
