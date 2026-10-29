extends SceneTree
## Writes the V01 graybox district scene from content/world/alder_street.json (kit pieces from F05). Rerun after editing
## the layout or the kit; the V01 test fails while the committed scene and the data disagree.
##   godot --headless --path . -s "$PWD/tools/godot/build_district.gd"
## Exit 0 = written, 1 = the save failed.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const SceneWriter := preload("res://scripts/world/scene_writer.gd")


func _initialize() -> void:
	var d: Dictionary = DistrictBuilder.load_district()
	var path: String = d["scene"]
	var root: Node3D = DistrictBuilder.build(d, KitBuilder.load_kit())
	var err: Error = SceneWriter.save(root, path, str(d["district_id"]))
	root.free()
	print(("WROTE %s" % path) if err == OK else "FAILED %s: %s" % [path, error_string(err)])
	quit(0 if err == OK else 1)
