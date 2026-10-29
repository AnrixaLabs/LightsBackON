extends Container
## S06 field HUD (blueprint p.23, layout reference p.42, ADR-004 point 5): objective card top-left (at most three rows),
## crew top-right, small reticle at the screen center, interaction prompt below it, tools and carried equipment bottom-left,
## latest event plus Map/Ping hints bottom-right, all inside the 80 px safe area.
## Presentation only: apply() takes a view built by hud_presenter.gd from authoritative state. The HUD sends nothing.
## Reflow: cards have design-canvas widths x the effective UI scale and grow in height with their text; the prompt sits
## 140 px below the reticle when there is room and moves up toward it (never over it) when the bottom row is taller.

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const StatusChip := preload("res://scripts/ui/status_chip.gd")
const IconRaster := preload("res://scripts/ui/icon_raster.gd")
const Reticle := preload("res://scripts/ui/reticle.gd")

const OBJECTIVE_WIDTH_PX: int = 420
const CREW_WIDTH_PX: int = 390
const PROMPT_WIDTH_PX: int = 560
const PROMPT_BELOW_CENTER_PX: int = 140
const RETICLE_PX: int = 24
const EVENT_WIDTH_PX: int = 510
const EVENT_MIN_WIDTH_PX: int = 300
const SLOT_MIN_WIDTH_PX: int = 120
const SLOT_COMPACT_WIDTH_PX: int = 64
const MAX_TOOL_SLOTS: int = 4
const REGION_GAP_PX: int = 24
const CREW_NAME_PX: int = 110

var tokens: Dictionary = {}
var ui_scale_percent: int = 100
var device: String = UiText.DEVICE_KBM
var scale_percent: float = 100.0  # effective: slider x viewport fit
var max_objective_rows: int = 3
var compact_tools: bool = false
var _inner_bottom: float = 0.0

var objective_card: PanelContainer
var crew_card: PanelContainer
var prompt_card: PanelContainer
var tool_card: PanelContainer
var event_card: PanelContainer
var reticle: Control
var _view: Dictionary = {}


func _init() -> void:
	tokens = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	max_objective_rows = int(tokens["max_objective_rows"])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE  # the field HUD never takes focus; the player keeps control of movement
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_resized)


## The HUD regions in reading order (tests and the contrast capture walk these).
func regions() -> Array[Control]:
	var out: Array[Control] = [objective_card, crew_card, prompt_card, tool_card, event_card]
	return out


func set_ui_scale(percent: int) -> void:
	ui_scale_percent = clampi(percent, int(tokens["ui_scale_percent"]["min"]), int(tokens["ui_scale_percent"]["max"]))
	_rebuild()


func set_device(input_device: String) -> void:
	device = input_device
	_rebuild()


## view: see hud_presenter.gd build().
func apply(view: Dictionary) -> void:
	_view = view
	_rebuild()


func _on_resized() -> void:
	var s: float = ThemeTokens.effective_percent(ui_scale_percent, size)
	if not is_equal_approx(s, scale_percent) or objective_card == null:
		_rebuild()
	else:
		queue_sort()


func _rebuild() -> void:
	scale_percent = ThemeTokens.effective_percent(ui_scale_percent, size if size.x > 0.0 else ThemeTokens.DESIGN_SIZE)
	theme = ThemeTokens.build(tokens, scale_percent)
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	compact_tools = false
	objective_card = _objectives()
	crew_card = _crew()
	prompt_card = _prompt()
	tool_card = _tools()
	event_card = _event()
	reticle = Reticle.new()
	reticle.setup(tokens, ThemeTokens.px(RETICLE_PX, scale_percent))
	for c: Control in [objective_card, crew_card, prompt_card, tool_card, event_card, reticle]:
		add_child(c)
	queue_sort()


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN or objective_card == null:
		return
	var s: float = scale_percent
	var safe: float = ThemeTokens.safe_area(tokens, size)
	var inner: Rect2 = Rect2(Vector2(safe, safe), size - Vector2(safe, safe) * 2.0)
	var gap: float = ThemeTokens.px(REGION_GAP_PX, s)
	_place(objective_card, inner.position, minf(ThemeTokens.px(OBJECTIVE_WIDTH_PX, s), inner.size.x))
	var crew_w: float = minf(ThemeTokens.px(CREW_WIDTH_PX, s), inner.size.x)
	_place(crew_card, Vector2(inner.end.x - crew_w, inner.position.y), crew_w)
	var center: Vector2 = size * 0.5
	var r: float = reticle.custom_minimum_size.x
	fit_child_in_rect(reticle, Rect2(center - Vector2(r, r) * 0.5, Vector2(r, r)))
	prompt_card.visible = not (_view.get("prompt", {}) as Dictionary).is_empty()
	# the prompt keeps the reference width on screen (560 px at 1080p) and wraps instead of growing with the UI scale,
	# so it stays a center column clear of the corner cards
	var fit_percent: float = 100.0 * minf(size.x / ThemeTokens.DESIGN_SIZE.x, size.y / ThemeTokens.DESIGN_SIZE.y)
	var prompt_w: float = minf(ThemeTokens.px(PROMPT_WIDTH_PX, minf(s, fit_percent)), inner.size.x)
	var prompt_h: float = _height_at(prompt_card, prompt_w)
	_place_bottom(inner, gap)
	_inner_bottom = inner.end.y
	var prompt: Rect2 = _prompt_rect(center, r, gap, prompt_w, prompt_h)
	if prompt_card.visible and prompt.grow(gap * 0.5).intersects(tool_card.get_rect()) and not compact_tools:
		_set_compact_tools(true)  # icons and numbers only; the selected tool's name moves above the slots
		_place_bottom(inner, gap)
		prompt = _prompt_rect(center, r, gap, prompt_w, prompt_h)
	if prompt_card.visible and prompt.grow(gap * 0.5).intersects(event_card.get_rect()):
		var event_w: float = maxf(ThemeTokens.px(EVENT_MIN_WIDTH_PX, s), inner.end.x - prompt.end.x - gap)
		var event_h: float = _height_at(event_card, event_w)
		_place(event_card, Vector2(inner.end.x - event_w, inner.end.y - event_h), event_w)
		prompt = _prompt_rect(center, r, gap, prompt_w, prompt_h)
	fit_child_in_rect(prompt_card, prompt)


func _place_bottom(inner: Rect2, gap: float) -> void:
	var s: float = scale_percent
	var tool_w: float = minf(tool_card.get_combined_minimum_size().x, inner.size.x)
	var tool_h: float = _height_at(tool_card, tool_w)
	_place(tool_card, Vector2(inner.position.x, inner.end.y - tool_h), tool_w)
	var event_w: float = clampf(inner.size.x - tool_w - gap, ThemeTokens.px(EVENT_MIN_WIDTH_PX, s), ThemeTokens.px(EVENT_WIDTH_PX, s))
	var event_h: float = _height_at(event_card, event_w)
	_place(event_card, Vector2(inner.end.x - event_w, inner.end.y - event_h), event_w)


## 140 px below the reticle when there is room; moves up toward it (never over it) when a bottom card under it is taller.
func _prompt_rect(center: Vector2, reticle_px: float, gap: float, w: float, h: float) -> Rect2:
	var x: float = center.x - w * 0.5
	var blocking_top: float = _inner_bottom + gap  # the safe area bounds the prompt like a card would
	for card: Control in [tool_card, event_card]:
		if card.position.x < x + w and card.get_rect().end.x > x:
			blocking_top = minf(blocking_top, card.position.y)
	var lowest_top: float = center.y + reticle_px * 0.5 + gap
	var y: float = minf(center.y + ThemeTokens.px(PROMPT_BELOW_CENTER_PX, scale_percent), blocking_top - gap - h)
	return Rect2(Vector2(x, maxf(y, lowest_top)), Vector2(w, h))


## Compact tool bar: numbers and icons only, the selected tool's name above the slots. Chosen only when the full bar would
## run under the prompt; apply() and a scale change start from the full bar again.
func _set_compact_tools(compact: bool) -> void:
	compact_tools = compact
	for n: Node in tool_card.find_children("ToolName", "Label", true, false):
		(n as Label).visible = not compact
	for n: Node in tool_card.find_children("Slot_*", "PanelContainer", true, false):
		(n as Control).custom_minimum_size.x = ThemeTokens.px(SLOT_COMPACT_WIDTH_PX if compact else SLOT_MIN_WIDTH_PX, scale_percent)
	var title: Label = tool_card.find_child("SelectedTool", true, false) as Label
	if title != null:
		title.visible = compact
	_refresh_min(tool_card)


## Minimum sizes are cached and refreshed a frame later; a mode change needs them now.
static func _refresh_min(n: Node) -> void:
	for c: Node in n.get_children():
		_refresh_min(c)
	if n is Control:
		(n as Control).update_minimum_size()


func _place(card: Control, pos: Vector2, width: float) -> void:
	fit_child_in_rect(card, Rect2(pos, Vector2(width, _height_at(card, width))))


## Minimum height of a card once its wrapping labels have this width (the card is resized first, so labels re-measure).
func _height_at(card: Control, width: float) -> float:
	if not is_equal_approx(card.size.x, width):
		card.size = Vector2(width, card.size.y)
	return card.get_combined_minimum_size().y


# ---------- regions ----------

func _card() -> PanelContainer:
	var card: PanelContainer = PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return card


func _vbox(parent: Control, gap_px: int = ThemeTokens.GAP_PX) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", ThemeTokens.px(gap_px, scale_percent))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box


func _label(parent: Control, text: String, variation: String = "", color_token: String = "", wrap: bool = true) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	if color_token != "":
		l.add_theme_color_override("font_color", ThemeTokens.color(tokens, color_token))
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _objectives() -> PanelContainer:
	var card: PanelContainer = _card()
	card.name = "Objectives"
	var box: VBoxContainer = _vbox(card)
	var context: String = "%s  /  %s" % [UiText.t(str(_view.get("district_key", "district.alder_street"))),
		UiText.t(str(_view.get("contract_key", "contract.c01")))]
	var head: Label = _label(box, context, "StrongLabel", "restored")
	head.uppercase = true
	var rows: Array = _view.get("objectives", [])
	for i: int in mini(rows.size(), max_objective_rows):
		var o: Dictionary = rows[i]
		var chip: HBoxContainer = StatusChip.make(tokens, scale_percent, "objectives", str(o["status"]), UiText.t(str(o["text_key"])), true,
			"StrongLabel" if o["status"] == "active" else "")
		chip.name = "Objective_%s" % o.get("id", str(i))
		box.add_child(chip)
	return card


func _crew() -> PanelContainer:
	var card: PanelContainer = _card()
	card.name = "Crew"
	var box: VBoxContainer = _vbox(card)
	var title: Label = _label(box, UiText.t("hud.crew"), "StrongLabel", "text_muted")
	title.uppercase = true
	for m: Dictionary in _view.get("crew", []):
		var row: HBoxContainer = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.name = "Crew_%s" % m["player"]
		box.add_child(row)
		var name_text: String = str(m["name"])
		if m.get("local", false):
			name_text = "%s (%s)" % [name_text, UiText.t("hud.you")]
		var who: Label = _label(row, name_text, "StrongLabel", "restored" if m.get("local", false) else "text", false)
		who.custom_minimum_size.x = ThemeTokens.px(CREW_NAME_PX, scale_percent)
		who.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if m.has("task_group"):
			var chip: HBoxContainer = StatusChip.make(tokens, scale_percent, str(m["task_group"]), str(m["task_state"]),
				str(m["task_text"]), true)
			chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(chip)
		else:
			_label(row, UiText.t("hud.crew_task.free"), "MutedLabel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return card


func _prompt() -> PanelContainer:
	var card: PanelContainer = _card()
	card.name = "Prompt"
	var p: Dictionary = _view.get("prompt", {})
	var box: VBoxContainer = _vbox(card, 6)
	if p.is_empty():
		return card
	var obj: Label = _label(box, UiText.t(str(p["object_key"])), "StrongLabel", "text_muted")
	obj.uppercase = true
	var action: Label = _label(box, UiText.tf("prompt.binding", [UiText.binding(str(p["action"]), device), UiText.t(str(p["verb_key"]))]),
		"StrongLabel")
	action.add_theme_font_size_override("font_size", ThemeTokens.px(float(tokens["type_px"]["button"]), scale_percent))
	if p.has("detail_group"):
		box.add_child(StatusChip.make(tokens, scale_percent, str(p["detail_group"]), str(p["detail_state"]), str(p["detail_text"]), true))
	elif p.has("detail_text"):
		_label(box, str(p["detail_text"]), "", "restored")
	return card


func _tools() -> PanelContainer:
	var card: PanelContainer = _card()
	card.name = "Tools"
	var box: VBoxContainer = _vbox(card)
	var carrying: String = str(_view.get("carrying", ""))
	if carrying != "":
		box.add_child(StatusChip.make(tokens, scale_percent, "equipment", carrying,
			UiText.tf("hud.carrying", [UiText.t(str(StatusChip.entry("equipment", carrying)["text_key"]))]), true))
	var tools: Array = _view.get("tools", [])
	var selected: int = int(_view.get("selected_slot", 1))
	if selected >= 1 and selected <= tools.size():
		var title: Label = _label(box, UiText.t(str(StatusChip.entry("tools", str(tools[selected - 1]))["text_key"])), "StrongLabel",
			"", false)
		title.name = "SelectedTool"
		title.uppercase = true
		title.visible = false  # shown only in the compact tool bar
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	for i: int in mini(tools.size(), MAX_TOOL_SLOTS):
		row.add_child(_slot(i + 1, str(tools[i]), i + 1 == selected))
	if tools.size() > MAX_TOOL_SLOTS:  # the rest are on the tool radial; the note sits under the slots so the bar stays narrow
		_label(box, UiText.tf("hud.tools_more", [tools.size() - MAX_TOOL_SLOTS]), "MutedLabel")
	return card


func _slot(number: int, tool: String, selected: bool) -> PanelContainer:
	var slot: PanelContainer = PanelContainer.new()
	slot.name = "Slot_%d" % number
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size.x = ThemeTokens.px(SLOT_MIN_WIDTH_PX, scale_percent)
	var style: StyleBoxFlat = ThemeTokens.outlined(tokens, "elevated", "action" if selected else "elevated", scale_percent,
		ThemeTokens.FOCUS_BORDER_PX)
	slot.add_theme_stylebox_override("panel", style)
	slot.set_meta("selected", selected)
	var box: VBoxContainer = _vbox(slot, 4)
	var top: HBoxContainer = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(top)
	_label(top, str(number), "StrongLabel", "action", false)
	var e: Dictionary = StatusChip.entry("tools", tool)
	var icon: TextureRect = TextureRect.new()
	icon.texture = StatusChip.icon_texture(str(e["icon"]), scale_percent)
	icon.self_modulate = ThemeTokens.color(tokens, str(e["color"]))
	var icon_px: int = ThemeTokens.px(IconRaster.BASE_PX, scale_percent)
	icon.custom_minimum_size = Vector2(icon_px, icon_px)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_meta("icon", str(e["icon"]))
	icon.set_meta("color_token", str(e["color"]))
	top.add_child(icon)
	var name_label: Label = _label(box, UiText.t(str(e["text_key"])), "", "", false)
	name_label.name = "ToolName"
	return slot


func _event() -> PanelContainer:
	var card: PanelContainer = _card()
	card.name = "Event"
	var box: VBoxContainer = _vbox(card, 8)
	var ev: Dictionary = _view.get("event", {})
	if not ev.is_empty():
		box.add_child(StatusChip.make(tokens, scale_percent, str(ev["group"]), str(ev["state"]), str(ev["text"]), true, "StrongLabel"))
	var hints: HFlowContainer = HFlowContainer.new()
	hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hints.add_theme_constant_override("h_separation", ThemeTokens.px(REGION_GAP_PX, scale_percent))
	box.add_child(hints)
	for h: Dictionary in [{"action": "map_meter", "key": "hud.hint.tablet"}, {"action": "ping", "key": "hud.hint.ping"}]:
		_label(hints, UiText.tf("prompt.binding", [UiText.binding(h["action"], device), UiText.t(h["key"])]), "MutedLabel", "", false)
	return card
