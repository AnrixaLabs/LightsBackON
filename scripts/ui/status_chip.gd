extends HBoxContainer
## Status chip (blueprint p.22): icon + label, both in the state's token color from content/ui/status_states.json.
## Status never depends on color alone: every chip has its own icon silhouette (F05) and text.

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const IconRaster := preload("res://scripts/ui/icon_raster.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const SELF_PATH: String = "res://scripts/ui/status_chip.gd"

static var _states: Dictionary = {}

var group: String = ""
var state: String = ""
var icon_rect: TextureRect
var label: Label


## A chip for status_states.json[group][state]. text overrides the state's own text (e.g. an objective's wording);
## the icon and color always come from the state.
static func make(tokens: Dictionary, scale_percent: float, chip_group: String, chip_state: String, text: String = "",
		wrap: bool = false, variation: String = "") -> HBoxContainer:
	var chip: Variant = (load(SELF_PATH) as GDScript).new()  # a script cannot preload itself
	chip.setup(tokens, scale_percent, wrap)
	chip.set_state(tokens, chip_group, chip_state, text)
	chip.label.theme_type_variation = variation
	return chip


static func entry(chip_group: String, chip_state: String) -> Dictionary:
	if _states.is_empty():
		_states = JSON.parse_string(FileAccess.get_file_as_string(IconRaster.STATES_PATH))
	return _states.get(chip_group, {}).get(chip_state, {})


static func icon_texture(icon: String, scale_percent: float) -> Texture2D:
	return load(IconRaster.export_path(icon, IconRaster.export_px_for_scale(ceili(scale_percent)))) as Texture2D


func setup(_tokens: Dictionary, scale_percent: float, wrap: bool) -> void:
	icon_rect = TextureRect.new()
	label = Label.new()
	var icon_px: int = ThemeTokens.px(IconRaster.BASE_PX, scale_percent)
	icon_rect.custom_minimum_size = Vector2(icon_px, icon_px)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if wrap else Control.SIZE_SHRINK_CENTER
	icon_rect.set_meta("scale_percent", scale_percent)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_theme_constant_override("separation", ThemeTokens.px(ThemeTokens.GAP_PX * 0.75, scale_percent))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon_rect)
	add_child(label)


func set_state(tokens: Dictionary, chip_group: String, chip_state: String, text: String = "") -> void:
	group = chip_group
	state = chip_state
	var e: Dictionary = entry(chip_group, chip_state)
	assert(not e.is_empty(), "no status %s.%s in status_states.json" % [chip_group, chip_state])
	var tint: Color = ThemeTokens.color(tokens, str(e["color"]))
	icon_rect.texture = icon_texture(str(e["icon"]), float(icon_rect.get_meta("scale_percent", 100.0)))
	icon_rect.self_modulate = tint
	label.text = text if text != "" else UiText.t(str(e["text_key"]))
	label.add_theme_color_override("font_color", tint)
	set_meta("icon", str(e["icon"]))
	set_meta("color_token", str(e["color"]))
	set_meta("text_key", str(e["text_key"]))
