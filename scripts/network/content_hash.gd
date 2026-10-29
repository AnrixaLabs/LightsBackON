extends RefCounted
## Content revision hash for the join handshake (V04; blueprint p.10 "verify contract/content hashes").
## Same algorithm as tools/build_manifest.py content_revision: SHA-256 over every file under content/, in sorted
## relative-path order, each as "<path>\0<bytes>\0" with paths like "content/contracts/c01_alder_street/grid.json".
## Two peers with any differing content byte get different hashes and the join is refused before spawning.

const ROOT: String = "res://content"


static func content_revision(root: String = ROOT) -> String:
	var files: Array[String] = []
	_collect(root, files)
	files.sort()
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var prefix: String = root.trim_suffix("/").get_base_dir()  # "res://"
	for path: String in files:
		var rel: String = path.trim_prefix(prefix).trim_prefix("/")
		ctx.update(rel.to_utf8_buffer() + PackedByteArray([0]))
		ctx.update(FileAccess.get_file_as_bytes(path) + PackedByteArray([0]))
	return ctx.finish().hex_encode()


static func _collect(dir_path: String, out: Array[String]) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	for f: String in d.get_files():
		out.append(dir_path.path_join(f))
	for sub: String in d.get_directories():
		_collect(dir_path.path_join(sub), out)
