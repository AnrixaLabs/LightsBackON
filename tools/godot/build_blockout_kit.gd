extends SceneTree
## Writes the F05 graybox kit scenes from content/world/kit_pieces.json. Rerun after editing the data; the F05 kit test
## fails while a committed scene and the data disagree.
##   godot --headless --path . -s "$PWD/tools/godot/build_blockout_kit.gd"
## Exit 0 = all written, 1 = a save failed.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")


func _initialize() -> void:
	var kit: Dictionary = KitBuilder.load_kit()
	var failed: int = 0
	for def: Dictionary in kit["pieces"]:
		var path: String = def["scene"]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		# keep the scene's UID across regenerations so references from other scenes survive
		var uid: int = _existing_uid(path)
		if uid == ResourceUID.INVALID_ID:
			uid = ResourceUID.create_id()
		var root: Node3D = KitBuilder.build(def, kit["materials"])
		var packed := PackedScene.new()
		var err: Error = packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, path)
		if err == OK:
			err = ResourceSaver.set_uid(path, uid)
		if err == OK:
			err = _stable_node_ids(path, str(def["id"]))
		root.free()
		if err != OK:
			print("FAILED %s: %s" % [path, error_string(err)])
			failed += 1
		else:
			print("WROTE %s" % path)
	quit(1 if failed > 0 else 0)


## Read from the file header: the editor's UID cache does not know about files this tool wrote in an earlier run.
func _existing_uid(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var m: RegExMatch = RegEx.create_from_string(r'uid="(uid://[a-z0-9]+)"').search(FileAccess.get_file_as_string(path).get_slice("\n", 0))
	return ResourceUID.text_to_id(m.get_string(1)) if m else ResourceUID.INVALID_ID


## Godot 4.7 writes a random unique_id per node on every save and has no setter for it. Derive it from the node path
## instead, so regenerating unchanged data leaves the committed files byte-identical.
func _stable_node_ids(path: String, piece_id: String) -> Error:
	var text: String = FileAccess.get_file_as_string(path)
	var re: RegEx = RegEx.create_from_string(r'\[node name="([^"]+)"([^\]]*?) unique_id=\d+\]')
	var out: String = text
	for m: RegExMatch in re.search_all(text):
		var stable: int = (piece_id + "/" + m.get_string(1)).hash() & 0x7FFFFFFF
		out = out.replace(m.get_string(0), "[node name=\"%s\"%s unique_id=%d]" % [m.get_string(1), m.get_string(2), maxi(stable, 1)])
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(out)
	f.close()
	return OK
