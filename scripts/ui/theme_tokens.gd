extends RefCounted
## Builds a Godot Theme from content/ui/tokens.json (F05): colors, sizes and the owner-approved font (Noto Sans, ADR-004 addendum).
## Pure apart from creating the Theme and loading the imported font, so it is testable headless.

const TYPES_WITH_FONT_COLOR: Array[String] = ["Label", "Button", "LineEdit", "RichTextLabel"]
const TYPES_STRONG: Array[String] = ["Button", "HeaderLarge", "HeaderMedium"]


static func color(tokens: Dictionary, name: String) -> Color:
	return Color.html(str(tokens["colors"][name]))


static func build(tokens: Dictionary) -> Theme:
	var theme: Theme = Theme.new()
	var px: Dictionary = tokens["type_px"]
	theme.default_font_size = int(px["body"])
	var font: Dictionary = tokens["font"]
	var base: Font = load(str(font["path"])) as Font
	theme.default_font = weighted(base, int(font["weight_body"]))
	var strong: Font = weighted(base, int(font["weight_strong"]))
	for t: String in TYPES_STRONG:
		theme.set_font("font", t, strong)
	for t: String in TYPES_WITH_FONT_COLOR:
		theme.set_color("font_color", t, color(tokens, "text"))
	theme.set_font_size("font_size", "Button", int(px["button"]))
	theme.set_font_size("font_size", "HeaderLarge", int(px["heading_max"]))
	theme.set_font_size("font_size", "HeaderMedium", int(px["heading_min"]))
	theme.set_type_variation("HeaderLarge", "Label")
	theme.set_type_variation("HeaderMedium", "Label")
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


## The variable font at one weight (OpenType wght axis), so body and headings share one licensed file.
static func weighted(base: Font, weight: int) -> FontVariation:
	var v: FontVariation = FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return v
