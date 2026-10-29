extends Node
## Boot scene (F01 placeholder). Logs the build identity so an exported build can be matched to its manifest.
## Real boot flow (profile load, Steam init, main menu) arrives with later tasks.

const MANIFEST_PATH: String = "res://build_manifest.json"


func _ready() -> void:
	print("Lights Back On boot | engine %s | build %s" % [Engine.get_version_info()["string"], _build_id()])


func _build_id() -> String:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return "unmanifested-dev"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if parsed is Dictionary and (parsed as Dictionary).has("build_id"):
		return str((parsed as Dictionary)["build_id"])
	return "manifest-unreadable"
