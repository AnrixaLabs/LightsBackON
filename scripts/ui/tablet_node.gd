extends PanelContainer
## One focusable node on the network tablet map: name, status chip (icon + text + token color) and its measured lines.
## Accept (A / Enter / click) emits activated; the tablet turns that into an inspect intent. It never toggles anything.

signal activated(node_id: String)

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const StatusChip := preload("res://scripts/ui/status_chip.gd")

var node_id: String = ""
var view: Dictionary = {}
var chip: HBoxContainer
var _focus_box: StyleBoxFlat


func setup(tokens: Dictionary, scale_percent: float, node_view: Dictionary) -> void:
	node_id = node_view["id"]
	view = node_view
	name = "Node_%s" % node_id
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var color_token: String = str(StatusChip.entry(node_view["status_group"], node_view["status_state"])["color"])
	add_theme_stylebox_override("panel", ThemeTokens.outlined(tokens, "panel", color_token, scale_percent))
	_focus_box = ThemeTokens.focus_box(tokens, scale_percent)
	var box: VBoxContainer = VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", ThemeTokens.px(4, scale_percent))
	add_child(box)
	var title: Label = Label.new()
	title.text = UiText.t(str(node_view["name_key"]))
	title.theme_type_variation = "StrongLabel"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	chip = StatusChip.make(tokens, scale_percent, node_view["status_group"], node_view["status_state"], "", true)
	box.add_child(chip)
	for line: String in node_view["lines"]:
		var l: Label = Label.new()
		l.text = line
		l.theme_type_variation = "MutedLabel"
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	var target: int = ThemeTokens.px(48, scale_percent)
	custom_minimum_size = Vector2(target, target)  # blueprint p.11: 48 x 48 px minimum target
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _draw() -> void:
	if has_focus():
		draw_style_box(_focus_box, Rect2(Vector2.ZERO, size))


func _gui_input(event: InputEvent) -> void:
	var click: bool = event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
		and event.is_pressed()
	if click:
		grab_focus()
	if click or event.is_action_pressed("ui_accept"):
		activated.emit(node_id)
		accept_event()
