extends RefCounted
## Builds a Godot Theme from content/ui/tokens.json (F05): colors, sizes and the owner-approved font (Noto Sans, ADR-004 addendum).
## Pure apart from creating the Theme and loading the imported font, so it is testable headless.
## V07: every size is on the 1920x1080 design canvas and multiplied by the effective UI scale (slider x resolution, see
## effective_percent), so containers reflow at 80-150 % instead of the whole canvas being stretched. Component contracts from
## blueprint p.22: primary button amber with dark text, secondary button panel fill with a 2 px outline, both 56 px high;
## focus is a 3 px high-contrast border drawn 4 px outside the control.

const TYPES_WITH_FONT_COLOR: Array[String] = ["Label", "Button", "LineEdit", "RichTextLabel"]
const TYPES_STRONG: Array[String] = ["Button", "HeaderLarge", "HeaderMedium", "StrongLabel", "PrimaryButton"]
const DESIGN_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const BUTTON_HEIGHT_PX: int = 56
const BUTTON_PAD_PX: int = 16
const OUTLINE_PX: int = 2
const FOCUS_BORDER_PX: int = 3
const FOCUS_OFFSET_PX: int = 4
const RADIUS_PX: int = 10
const PANEL_PAD_PX: int = 22
const GAP_PX: int = 12


static func color(tokens: Dictionary, name: String) -> Color:
	return Color.html(str(tokens["colors"][name]))


## Design-canvas pixels at a UI scale in percent, never below 1.
static func px(design_px: float, scale_percent: float) -> int:
	return maxi(1, roundi(design_px * scale_percent / 100.0))


## UI scale slider x how much of the 1920x1080 canvas the viewport shows: 150 % on a 1280x720 window draws like 100 % on 1080p.
static func effective_percent(slider_percent: int, viewport: Vector2) -> float:
	var fit: float = minf(viewport.x / DESIGN_SIZE.x, viewport.y / DESIGN_SIZE.y)
	return float(slider_percent) * fit


## The 80 px safe area follows the screen, not the UI scale slider (it protects against overscan, not text size).
static func safe_area(tokens: Dictionary, viewport: Vector2) -> int:
	return px(float(tokens["safe_area_px"]), 100.0 * minf(viewport.x / DESIGN_SIZE.x, viewport.y / DESIGN_SIZE.y))


static func build(tokens: Dictionary, scale_percent: float = 100.0) -> Theme:
	var theme: Theme = Theme.new()
	var type_px: Dictionary = tokens["type_px"]
	var s: float = scale_percent
	theme.default_font_size = px(float(type_px["body"]), s)
	var font: Dictionary = tokens["font"]
	var base: Font = load(str(font["path"])) as Font
	theme.default_font = weighted(base, int(font["weight_body"]))
	var strong: Font = weighted(base, int(font["weight_strong"]))
	for t: String in TYPES_STRONG:
		theme.set_font("font", t, strong)
	for t: String in TYPES_WITH_FONT_COLOR:
		theme.set_color("font_color", t, color(tokens, "text"))
	theme.set_font_size("font_size", "Button", px(float(type_px["button"]), s))
	theme.set_font_size("font_size", "HeaderLarge", px(float(type_px["heading_max"]), s))
	theme.set_font_size("font_size", "HeaderMedium", px(float(type_px["heading_min"]), s))
	theme.set_font_size("font_size", "StrongLabel", px(float(type_px["body"]), s))
	for v: String in ["HeaderLarge", "HeaderMedium", "StrongLabel", "MutedLabel"]:
		theme.set_type_variation(v, "Label")
	theme.set_color("font_color", "MutedLabel", color(tokens, "text_muted"))
	for box: String in ["HBoxContainer", "VBoxContainer"]:
		theme.set_constant("separation", box, px(GAP_PX, s))
	var panel: StyleBoxFlat = _box(tokens, "panel", s)
	var bg: Color = color(tokens, "panel")
	bg.a = float(tokens["overlay"]["panel_alpha_percent"]) / 100.0
	panel.bg_color = bg
	_pad(panel, PANEL_PAD_PX, s)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_type_variation("ElevatedPanel", "PanelContainer")
	var elevated: StyleBoxFlat = _box(tokens, "elevated", s)
	_pad(elevated, GAP_PX, s)
	theme.set_stylebox("panel", "ElevatedPanel", elevated)
	theme.set_type_variation("BackdropPanel", "PanelContainer")
	var backdrop: StyleBoxFlat = StyleBoxFlat.new()
	backdrop.bg_color = color(tokens, "background")  # opaque: the tablet is a full-screen panel (S07)
	theme.set_stylebox("panel", "BackdropPanel", backdrop)
	_buttons(theme, tokens, "Button", "elevated", "text", s)
	theme.set_type_variation("PrimaryButton", "Button")
	_buttons(theme, tokens, "PrimaryButton", "action", "background", s)
	theme.set_font_size("font_size", "PrimaryButton", px(float(type_px["button"]), s))
	return theme


## Focus ring shared by buttons and custom focusable panels: 3 px amber border, 4 px outside the control.
static func focus_box(tokens: Dictionary, scale_percent: float) -> StyleBoxFlat:
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = color(tokens, "action")  # visible focus path for controller navigation
	focus.set_border_width_all(px(FOCUS_BORDER_PX, scale_percent))
	focus.set_expand_margin_all(px(FOCUS_OFFSET_PX + FOCUS_BORDER_PX, scale_percent))
	focus.set_corner_radius_all(px(RADIUS_PX + FOCUS_OFFSET_PX, scale_percent))
	return focus


## A rounded panel box with an outline in a token color (map nodes, tool slots).
static func outlined(tokens: Dictionary, fill: String, outline: String, scale_percent: float, outline_px: int = OUTLINE_PX) -> StyleBoxFlat:
	var box: StyleBoxFlat = _box(tokens, fill, scale_percent)
	box.border_color = color(tokens, outline)
	box.set_border_width_all(px(outline_px, scale_percent))
	_pad(box, GAP_PX, scale_percent)
	return box


## The variable font at one weight (OpenType wght axis), so body and headings share one licensed file.
static func weighted(base: Font, weight: int) -> FontVariation:
	var v: FontVariation = FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return v


static func _buttons(theme: Theme, tokens: Dictionary, type: String, fill: String, ink: String, s: float) -> void:
	var normal: StyleBoxFlat = outlined(tokens, fill, "text_muted" if fill == "elevated" else fill, s)
	normal.content_margin_left = px(BUTTON_PAD_PX, s)
	normal.content_margin_right = px(BUTTON_PAD_PX, s)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.border_color = color(tokens, "text")
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = color(tokens, "panel")
	disabled.border_color = color(tokens, "unknown")
	for state: String in ["normal", "pressed"]:
		theme.set_stylebox(state, type, normal)
	theme.set_stylebox("hover", type, hover)
	theme.set_stylebox("disabled", type, disabled)
	theme.set_stylebox("focus", type, focus_box(tokens, s))
	for c: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(c, type, color(tokens, ink))
	theme.set_color("font_disabled_color", type, color(tokens, "text_muted"))
	theme.set_constant("h_separation", type, px(GAP_PX, s))


static func _box(tokens: Dictionary, fill: String, s: float) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color(tokens, fill)
	box.set_corner_radius_all(px(RADIUS_PX, s))
	return box


static func _pad(box: StyleBoxFlat, design_px: int, s: float) -> void:
	box.set_content_margin_all(px(design_px, s))
