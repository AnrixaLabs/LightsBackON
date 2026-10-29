extends SceneTree
## Renders every UI02 icon for the owner's review: a 72 px view of the source, then the committed 48/32/24 px exports, all tinted with the
## state's token color on the opaque HUD panel, plus the 24 px export in plain text color (reads without color). Labels show the
## localization key and icon id in the token theme's font (Noto Sans). Needs a real GPU window, not headless.
##   godot --path . --import --headless; godot --path . --resolution 1920x1080 -s "$PWD/tools/godot/capture_icon_sheet.gd" -- --out=build/icon_sheet.png
## Exit 0 = PNG written.

const IconRaster := preload("res://scripts/ui/icon_raster.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const COLUMNS: int = 6
const PREVIEW_PX: int = 72
const LABEL_PX: int = 15
const SETTLE_FRAMES: int = 6


func _initialize() -> void:
	var out: String = "build/icon_sheet.png"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	var states: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(IconRaster.STATES_PATH))
	var colors: Dictionary = tokens["colors"]
	var bg := ColorRect.new()
	bg.color = Color(str(colors["background"]))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.theme = ThemeTokens.build(tokens)
	root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	bg.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(grid)
	for group: String in states:
		if group.begins_with("_"):
			continue
		for state: String in states[group]:
			var e: Dictionary = states[group][state]
			grid.add_child(_cell(e, Color(str(colors[e["color"]])), colors))
	for i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var err: Error = img.save_png(out)
	print(("WROTE %s (%dx%d, %s)" % [out, img.get_width(), img.get_height(), RenderingServer.get_video_adapter_name()])
		if err == OK else "FAILED %s: %s" % [out, error_string(err)])
	quit(0 if err == OK else 1)


func _cell(e: Dictionary, tint: Color, colors: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(str(colors["panel"]))
	box.set_corner_radius_all(6)
	box.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", box)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	panel.add_child(v)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var icon: String = e["icon"]
	var big: Image = IconRaster.rasterize(FileAccess.get_file_as_string(IconRaster.source_path(icon)), PREVIEW_PX)
	row.add_child(_icon(ImageTexture.create_from_image(big), tint))
	for px: int in [48, 32, 24]:
		row.add_child(_icon(load(IconRaster.export_path(icon, px)) as Texture2D, tint))
	row.add_child(_icon(load(IconRaster.export_path(icon, 24)) as Texture2D, Color(str(colors["text"]))))
	v.add_child(_label(str(e["text_key"]), Color(str(colors["text"]))))
	v.add_child(_label(icon, Color(str(colors["text_muted"]))))
	return panel


func _icon(tex: Texture2D, tint: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.self_modulate = tint
	return r


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", LABEL_PX)
	l.add_theme_color_override("font_color", color)
	return l
