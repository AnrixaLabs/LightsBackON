extends RefCounted
## Builds a Godot Theme from content/ui/tokens.json (F05). Colors and sizes only; the font is added once one is
## approved and licensed (ADR-004 point 6). Pure apart from creating the Theme resource, so it is testable headless.

const TYPES_WITH_FONT_COLOR: Array[String] = ["Label", "Button", "LineEdit", "RichTextLabel"]


static func color(tokens: Dictionary, name: String) -> Color:
	return Color.html(str(tokens["colors"][name]))


static func build(tokens: Dictionary) -> Theme:
	var theme: Theme = Theme.new()
	var px: Dictionary = tokens["type_px"]
	theme.default_font_size = int(px["body"])
	for t: String in TYPES_WITH_FONT_COLOR:
		theme.set_color("font_color", t, color(tokens, "text"))
	theme.set_font_size("font_size", "Button", int(px["button"]))
	theme.set_font_size("font_size", "HeaderLarge", int(px["heading_max"]))
	theme.set_font_size("font_size", "HeaderMedium", int(px["heading_min"]))
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	var bg: Color = color(tokens, "panel")
	bg.a = float(tokens["overlay"]["panel_alpha_percent"]) / 100.0
	panel.bg_color = bg
	theme.set_stylebox("panel", "PanelContainer", panel)
	var button: StyleBoxFlat = StyleBoxFlat.new()
	button.bg_color = color(tokens, "elevated")
	button.content_margin_top = 8
	button.content_margin_bottom = 8
	theme.set_stylebox("normal", "Button", button)
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = color(tokens, "action")  # visible focus path for controller navigation
	focus.set_border_width_all(3)
	theme.set_stylebox("focus", "Button", focus)
	return theme
