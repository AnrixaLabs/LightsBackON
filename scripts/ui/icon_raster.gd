extends RefCounted
## UI02 status/tool/ping icons (blueprint p.40, ADR-004 point 2). Each icon in content/ui/status_states.json has an original SVG source in
## art_source/ui_icons/ (white ink on a 24 px canvas, tinted with its token color at runtime) and PNG exports at 24/32/48 px in
## assets/ui/icons/<px>/. tools/godot/export_icons.gd writes the exports; tests compare them with a fresh rasterization of the source.

const STATES_PATH: String = "res://content/ui/status_states.json"
const SOURCE_DIR: String = "res://art_source/ui_icons"
const EXPORT_DIR: String = "res://assets/ui/icons"
const BASE_PX: int = 24
const SIZES_PX: Array[int] = [24, 32, 48]


## Every icon id named in status_states.json, sorted, each once.
static func icon_ids() -> Array[String]:
	var states: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STATES_PATH))
	var ids: Array[String] = []
	for group: String in states:
		if group.begins_with("_"):
			continue
		for state: String in states[group]:
			var icon: String = states[group][state]["icon"]
			if not ids.has(icon):
				ids.append(icon)
	ids.sort()
	return ids


static func source_path(icon: String) -> String:
	return "%s/%s.svg" % [SOURCE_DIR, icon]


static func export_path(icon: String, px: int) -> String:
	return "%s/%d/%s.png" % [EXPORT_DIR, px, icon]


## Rasterizes an icon source to px x px RGBA8, or returns null if the SVG does not load at that size.
static func rasterize(svg: String, px: int) -> Image:
	var img := Image.new()
	if img.load_svg_from_string(svg, float(px) / float(BASE_PX)) != OK:
		return null
	if img.get_width() != px or img.get_height() != px:
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## The export to draw at a UI scale: the smallest one at least as large as the scaled 24 px icon (downscaling stays sharp),
## else the largest.
static func export_px_for_scale(ui_scale_percent: int) -> int:
	var want: int = ceili(BASE_PX * ui_scale_percent / 100.0)
	for px: int in SIZES_PX:
		if px >= want:
			return px
	return SIZES_PX[-1]
