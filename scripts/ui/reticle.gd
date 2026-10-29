extends Control
## Small center reticle (S06). Two-tone so it reads over any scene pixel: a light cross on a dark outline (icons need 3:1, ADR-004).

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const STROKE_FRACTION: float = 0.09
const OUTLINE_FRACTION: float = 0.09

var ink: Color = Color.WHITE
var outline: Color = Color.BLACK


func setup(tokens: Dictionary, size_px: int) -> void:
	ink = ThemeTokens.color(tokens, "text")
	outline = ThemeTokens.color(tokens, "background")
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var half: float = size.x * 0.5
	var w: float = maxf(2.0, roundf(size.x * STROKE_FRACTION))
	var o: float = maxf(1.0, roundf(size.x * OUTLINE_FRACTION))
	for pass_color: Color in [outline, ink]:
		var grow: float = o if pass_color == outline else 0.0
		var r: float = half - o + grow
		var t: float = w * 0.5 + grow
		draw_rect(Rect2(c.x - r, c.y - t, r * 2.0, t * 2.0), pass_color)
		draw_rect(Rect2(c.x - t, c.y - r, t * 2.0, r * 2.0), pass_color)
