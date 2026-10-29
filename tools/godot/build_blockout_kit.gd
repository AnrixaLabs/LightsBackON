extends SceneTree
## Writes the F05 graybox kit scenes from content/world/kit_pieces.json. Rerun after editing the data; the F05 kit test
## fails while a committed scene and the data disagree.
##   godot --headless --path . -s "$PWD/tools/godot/build_blockout_kit.gd"
## Exit 0 = all written, 1 = a save failed.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const SceneWriter := preload("res://scripts/world/scene_writer.gd")


func _initialize() -> void:
	var kit: Dictionary = KitBuilder.load_kit()
	var failed: int = 0
	for def: Dictionary in kit["pieces"]:
		var path: String = def["scene"]
		var root: Node3D = KitBuilder.build(def, kit["materials"])
		var err: Error = SceneWriter.save(root, path, str(def["id"]))
		root.free()
		if err != OK:
			print("FAILED %s: %s" % [path, error_string(err)])
			failed += 1
		else:
			print("WROTE %s" % path)
	quit(1 if failed > 0 else 0)
