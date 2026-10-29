extends RefCounted
## Saves generated graybox scenes (F05 kit, V01 districts) so that regenerating unchanged data leaves the committed
## .tscn byte-identical: the scene UID survives, and the ids Godot would otherwise randomize on every save are derived
## from stable names instead. Used only by the generator tools under tools/godot/.


## Packs root (all nodes owned by it) and writes path. seed namespaces the derived node ids.
static func save(root: Node, path: String, seed: String) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	# keep the scene's UID across regenerations so references from other scenes survive
	var uid: int = _existing_uid(path)
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var packed := PackedScene.new()
	var err: Error = packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	if err == OK:
		err = ResourceSaver.set_uid(path, uid)
	if err == OK:
		err = _stable_ids(path, seed)
	return err


## Read from the file header: the editor's UID cache does not know about files a tool wrote in an earlier run.
static func _existing_uid(path: String) -> int:
	if not FileAccess.file_exists(path):
		return ResourceUID.INVALID_ID
	var m: RegExMatch = RegEx.create_from_string(r'uid="(uid://[a-z0-9]+)"').search(FileAccess.get_file_as_string(path).get_slice("\n", 0))
	return ResourceUID.text_to_id(m.get_string(1)) if m else ResourceUID.INVALID_ID


## Godot 4.7 writes a random unique_id per node and a random suffix per ext_resource id on every save, with no setter
## for either. Rewrite them: ext_resource ids from their order and file name, node ids from the node's name and parent.
static func _stable_ids(path: String, seed: String) -> Error:
	var text: String = FileAccess.get_file_as_string(path)
	var ext: RegEx = RegEx.create_from_string(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]')
	var n: int = 0
	for m: RegExMatch in ext.search_all(text):
		n += 1
		var stable: String = "%d_%s" % [n, m.get_string(1).get_file().get_basename()]
		text = text.replace('id="%s"]' % m.get_string(2), 'id="%s"]' % stable)
		text = text.replace('ExtResource("%s")' % m.get_string(2), 'ExtResource("%s")' % stable)
	var node: RegEx = RegEx.create_from_string(r'\[node name="([^"]+)"([^\]]*?) unique_id=\d+([^\]]*)\]')
	var out: String = text
	for m: RegExMatch in node.search_all(text):
		var key: String = seed + "/" + m.get_string(1)
		var parent: RegExMatch = RegEx.create_from_string(r'parent="([^"]*)"').search(m.get_string(2))
		if parent and parent.get_string(1) != ".":  # root's children keep the F05 key, so the kit files stay unchanged
			key = seed + "/" + parent.get_string(1) + "/" + m.get_string(1)
		var stable_id: int = maxi(key.hash() & 0x7FFFFFFF, 1)
		out = out.replace(m.get_string(0), "[node name=\"%s\"%s unique_id=%d%s]" % [m.get_string(1), m.get_string(2), stable_id, m.get_string(3)])
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(out)
	f.close()
	return OK
