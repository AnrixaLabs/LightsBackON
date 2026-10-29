extends Node
## Boot scene (F01 placeholder). Logs the build identity so an exported build can be matched to its manifest.
## Real boot flow (profile load, Steam init, main menu) arrives with later tasks.

const SaveSoak := preload("res://scripts/persistence/save_soak.gd")
const MANIFEST_PATH: String = "res://build_manifest.json"


func _ready() -> void:
	print("Lights Back On boot | engine %s | build %s" % [Engine.get_version_info()["string"], _build_id()])
	var mode: String = SaveSoak.requested_mode(OS.get_cmdline_user_args())
	if mode != "":
		_run_save_soak(mode)


## G06 kill test hooks (internal builds only; see save_soak.gd).
func _run_save_soak(mode: String) -> void:
	if not SaveSoak.allowed():
		print("save soak is not available in this build")
		return
	var soak: SaveSoak = SaveSoak.new()
	soak.name = "SaveSoak"
	soak.setup(_build_id())
	add_child(soak)
	if mode == SaveSoak.ARG_VERIFY:
		get_tree().quit(soak.verify())
	else:
		soak.start_soak()


func _build_id() -> String:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return "unmanifested-dev"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary and (parsed as Dictionary).has("build_id"):
		return str((parsed as Dictionary)["build_id"])
	return "manifest-unreadable"
