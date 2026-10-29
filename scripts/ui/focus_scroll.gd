extends ScrollContainer
## Scroll panel that a controller can scroll (blueprint p.22: visible position indicator, controller scrolling, no primary
## action below the fold). It takes focus like a button; while focused, up/down (D-pad, left stick, arrows) scroll it until
## an end is reached, then move focus on as usual; the right stick scrolls it too. Shows the 3 px focus ring.

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const STEP_PX: int = 60
const STICK_SPEED_PX: float = 900.0

var _focus_box: StyleBoxFlat
var _scale_percent: float = 100.0


func setup(tokens: Dictionary, scale_percent: float) -> void:
	_scale_percent = scale_percent
	_focus_box = ThemeTokens.focus_box(tokens, scale_percent)
	focus_mode = Control.FOCUS_ALL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	follow_focus = false
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func can_scroll() -> bool:
	return get_v_scroll_bar().max_value - get_v_scroll_bar().page > 0.5


func _draw() -> void:
	if has_focus():
		draw_style_box(_focus_box, Rect2(Vector2.ZERO, size))


func _gui_input(event: InputEvent) -> void:
	var step: int = ThemeTokens.px(STEP_PX, _scale_percent)
	var bar: VScrollBar = get_v_scroll_bar()
	if event.is_action_pressed("ui_down", true) and scroll_vertical < bar.max_value - bar.page - 0.5:
		scroll_vertical += step
		accept_event()
	elif event.is_action_pressed("ui_up", true) and scroll_vertical > 0:
		scroll_vertical -= step
		accept_event()


func _process(delta: float) -> void:
	if not has_focus():
		return
	var stick: float = Input.get_axis("look_up", "look_down")
	if stick != 0.0:
		scroll_vertical += roundi(stick * STICK_SPEED_PX * _scale_percent / 100.0 * delta)
