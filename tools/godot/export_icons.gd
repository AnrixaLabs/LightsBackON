extends SceneTree
## Writes assets/ui/icons/<24|32|48>/<icon>.png from art_source/ui_icons/<icon>.svg for every icon in content/ui/status_states.json
## (blueprint UI02). A PNG is rewritten only when its pixels change, so a rerun leaves the tree untouched.
##   godot --headless --path . -s "$PWD/tools/godot/export_icons.gd"
## Exit 0 = every export written or unchanged; 1 = a source is missing or does not rasterize.

const IconRaster := preload("res://scripts/ui/icon_raster.gd")


func _initialize() -> void:
	var failed: int = 0
	var counts: Dictionary = {"WROTE": 0, "UNCHANGED": 0}
	for px: int in IconRaster.SIZES_PX:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("%s/%d" % [IconRaster.EXPORT_DIR, px]))
	for icon: String in IconRaster.icon_ids():
		var src: String = IconRaster.source_path(icon)
		if not FileAccess.file_exists(src):
			print("MISSING %s" % src)
			failed += 1
			continue
		var svg: String = FileAccess.get_file_as_string(src)
		for px: int in IconRaster.SIZES_PX:
			var img: Image = IconRaster.rasterize(svg, px)
			if img == null:
				print("FAILED %s at %d px" % [src, px])
				failed += 1
				continue
			var out: String = ProjectSettings.globalize_path(IconRaster.export_path(icon, px))
			var old: Image = Image.load_from_file(out) if FileAccess.file_exists(out) else null
			if old != null:
				old.convert(Image.FORMAT_RGBA8)
				if old.get_data() == img.get_data():
					counts["UNCHANGED"] += 1
					continue
			if img.save_png(out) != OK:
				print("FAILED to write %s" % out)
				failed += 1
				continue
			counts["WROTE"] += 1
	print("icons: %d wrote, %d unchanged, %d failed" % [counts["WROTE"], counts["UNCHANGED"], failed])
	quit(0 if failed == 0 else 1)
