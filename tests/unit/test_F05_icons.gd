extends "res://tests/test_case.gd"
## F05 local part 2 / blueprint UI02: one original SVG icon per real state, tool and ping, one family (ADR-004 point 2),
## exported at 24/32/48 px, silhouettes that stay distinct without color.

const IconRaster := preload("res://scripts/ui/icon_raster.gd")
## Pixels whose coverage differs by more than half between two 24 px icons: a 4 x 4 block at least (closest pair measured 20).
const MIN_DISTINCT_PX: int = 16
## Ink coverage of a 24 px icon: below this it vanishes on the HUD, above it reads as a blob.
const INK_MIN: float = 0.06
const INK_MAX: float = 0.5
## Cross-platform anti-aliasing slack when comparing a committed export with a fresh rasterization (0-255 per channel).
const EXPORT_TOLERANCE: int = 2

var _ids: Array[String]


func before_each() -> void:
	_ids = IconRaster.icon_ids()


func test_F05_every_icon_has_one_svg_source_and_three_exports_and_nothing_else() -> void:
	assert_eq(_ids.size(), 39, "repair 9 + findings 11 + supply 3 + other 3 + pings 4 + tools 5 + equipment 1 + objectives 3 (V07)")
	assert_eq(_files(IconRaster.SOURCE_DIR, ".svg"), _ids, "art_source/ui_icons holds exactly the icons status_states.json names")
	for px: int in IconRaster.SIZES_PX:
		assert_eq(_files("%s/%d" % [IconRaster.EXPORT_DIR, px], ".png"), _ids, "assets/ui/icons/%d" % px)


func test_F05_tools_and_equipment_icons_match_what_contracts_use() -> void:
	var states: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(IconRaster.STATES_PATH))
	var tools: Array = []
	var kinds: Array = []
	for dir: String in DirAccess.get_directories_at("res://content/contracts"):
		var base: String = "res://content/contracts/%s" % dir
		if FileAccess.file_exists(base + "/repairs.json"):
			for r: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(base + "/repairs.json"))["repairs"]:
				for t: String in (r.get("tools", {}) as Dictionary).values():
					if not tools.has(t):
						tools.append(t)
		if FileAccess.file_exists(base + "/equipment.json"):
			for e: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(base + "/equipment.json"))["equipment"]:
				if not kinds.has(e["kind"]):
					kinds.append(e["kind"])
	tools.sort()
	kinds.sort()
	var have_tools: Array = (states["tools"] as Dictionary).keys()
	have_tools.sort()
	var have_kinds: Array = (states["equipment"] as Dictionary).keys()
	have_kinds.sort()
	assert_eq(have_tools, tools, "tool icons = tools named by contract repairs (nothing invented ahead of content)")
	assert_eq(have_kinds, kinds, "equipment icons = equipment kinds")


func test_F05_icon_sources_follow_the_family_rules() -> void:
	var colors := RegEx.create_from_string("#[0-9A-Fa-f]{3,8}\\b")
	var widths := RegEx.create_from_string("stroke-width=\"([0-9.]+)\"")
	var forbidden: Array[String] = ["<text", "<image", "<script", "<use", "<style", "style=", "href", "<foreignObject", "opacity"]
	for icon: String in _ids:
		var svg: String = FileAccess.get_file_as_string(IconRaster.source_path(icon))
		assert_true(svg.begins_with("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\">"),
			"%s: 24 px canvas" % icon)
		assert_true(svg.contains("stroke-linecap=\"round\" stroke-linejoin=\"round\""), "%s: rounded caps and joins" % icon)
		for m: RegExMatch in colors.search_all(svg):
			assert_eq(m.get_string(), "#FFFFFF", "%s: white ink only; the token color is applied at runtime" % icon)
		for m: RegExMatch in widths.search_all(svg):
			assert_eq(m.get_string(1), "2", "%s: one stroke weight" % icon)
		for f: String in forbidden:
			assert_false(svg.contains(f), "%s: no %s (no baked text, external refs or scripts)" % [icon, f])


func test_F05_committed_exports_match_their_svg_source() -> void:
	for icon: String in _ids:
		var svg: String = FileAccess.get_file_as_string(IconRaster.source_path(icon))
		for px: int in IconRaster.SIZES_PX:
			var want: Image = IconRaster.rasterize(svg, px)
			var have: Image = Image.load_from_file(ProjectSettings.globalize_path(IconRaster.export_path(icon, px)))
			if not (want != null and have != null):
				assert_true(false, "%s at %d px: source and export both load" % [icon, px])
				continue
			have.convert(Image.FORMAT_RGBA8)
			assert_eq(have.get_size(), Vector2i(px, px), "%s export is %d px" % [icon, px])
			assert_true(_max_channel_diff(want, have) <= EXPORT_TOLERANCE,
				"%s at %d px matches its source (rerun tools/godot/export_icons.gd)" % [icon, px])


func test_F05_icons_stay_on_the_canvas_with_legible_ink() -> void:
	for icon: String in _ids:
		var img: Image = IconRaster.rasterize(FileAccess.get_file_as_string(IconRaster.source_path(icon)), IconRaster.BASE_PX)
		var ink: float = 0.0
		var edge: float = 0.0
		for y: int in img.get_height():
			for x: int in img.get_width():
				var a: float = img.get_pixel(x, y).a
				ink += a
				if x == 0 or y == 0 or x == img.get_width() - 1 or y == img.get_height() - 1:
					edge = maxf(edge, a)
		ink /= float(img.get_width() * img.get_height())
		assert_true(ink >= INK_MIN and ink <= INK_MAX, "%s: ink coverage %.3f" % [icon, ink])
		assert_eq(edge, 0.0, "%s: 1 px clear margin so tinted icons never touch their frame" % icon)


func test_F05_icon_silhouettes_are_distinct_without_color() -> void:
	var masks: Dictionary = {}
	for icon: String in _ids:
		masks[icon] = IconRaster.rasterize(FileAccess.get_file_as_string(IconRaster.source_path(icon)), IconRaster.BASE_PX)
	var closest: int = IconRaster.BASE_PX * IconRaster.BASE_PX
	for i: int in _ids.size():
		for j: int in range(i + 1, _ids.size()):
			var differ: int = _differing_px(masks[_ids[i]], masks[_ids[j]])
			closest = mini(closest, differ)
			assert_true(differ >= MIN_DISTINCT_PX, "%s vs %s differ in %d px" % [_ids[i], _ids[j], differ])
	assert_true(closest >= MIN_DISTINCT_PX, "closest pair differs in %d px" % closest)


func test_F05_ui_scale_picks_an_export_at_least_as_large() -> void:
	assert_eq(IconRaster.export_px_for_scale(80), 24)
	assert_eq(IconRaster.export_px_for_scale(100), 24)
	assert_eq(IconRaster.export_px_for_scale(101), 32)
	assert_eq(IconRaster.export_px_for_scale(125), 32)
	assert_eq(IconRaster.export_px_for_scale(134), 48)
	assert_eq(IconRaster.export_px_for_scale(150), 48, "150 % = 36 px drawn from the 48 px export")


func _files(dir: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(f.trim_suffix(ext))
	out.sort()
	return out


func _max_channel_diff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return 255
	var da: PackedByteArray = a.get_data()
	var db: PackedByteArray = b.get_data()
	var worst: int = 0
	for k: int in da.size():
		worst = maxi(worst, absi(da[k] - db[k]))
	return worst


func _differing_px(a: Image, b: Image) -> int:
	var n: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if absf(a.get_pixel(x, y).a - b.get_pixel(x, y).a) > 0.5:
				n += 1
	return n
