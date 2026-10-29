extends PanelContainer
## S07 network tablet (blueprint p.23, reference p.43): full-screen panel on an opaque backdrop. Top: district, title, tabs
## Network / Objectives. Left: the directed map (tablet_map.gd). Right: evidence for the selected node and Ping. Bottom:
## legend, zoom, center and Close.
## The tablet may only inspect and ping (V07 acceptance): it holds an outbox gate that allows exactly those two intents.
## Selecting a node shows what is known; Accept on a node sends inspect for its meter panel (the host checks range and
## answers); Ping sends a ping on that node. Switches, breakers and repairs operate only in the world.
## Focus (blueprint p.22): opening moves focus into the tablet, closing restores the previous control; B / Esc / Tab close.

signal closed

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const StatusChip := preload("res://scripts/ui/status_chip.gd")
const TabletMap := preload("res://scripts/ui/tablet_map.gd")
const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")
const FocusScroll := preload("res://scripts/ui/focus_scroll.gd")

const MAP_INTENTS: Array[String] = ["inspect", "ping"]
const DETAIL_WIDTH_PX: int = 480
const SECTION_GAP_PX: int = 16
const TAB_NETWORK: String = "network"
const TAB_OBJECTIVES: String = "objectives"
const LEGEND: Array[Array] = [["supply", "restored"], ["supply", "temporary"], ["supply", "dark"], ["other", "unknown"]]

var tokens: Dictionary = {}
var ui_scale_percent: int = 100
var scale_percent: float = 100.0
var device: String = UiText.DEVICE_KBM
var gate: RefCounted = null  # intent_outbox.gd Gate limited to MAP_INTENTS
var map: Container
var selected: String = ""
var tab: String = TAB_NETWORK
var tab_buttons: Dictionary = {}
var ping_button: Button
var close_button: Button
var zoom_buttons: Array[Button] = []
var _view: Dictionary = {}
var _objectives: Array = []
var _context: Array[String] = ["district.alder_street", "contract.c01"]
var _status_text: String = ""
var _previous_focus: Control = null
var _detail: VBoxContainer
var detail_scroll: ScrollContainer
var _body_left: PanelContainer


func _init() -> void:
	tokens = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	theme_type_variation = "BackdropPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing behind the tablet is clickable while it is open
	resized.connect(_on_resized)


## outbox: intent_outbox.gd; the tablet keeps only a gate for inspect and ping.
func setup(outbox: RefCounted) -> void:
	gate = outbox.call("gate", MAP_INTENTS)
	if outbox.has_signal("replied"):
		outbox.connect("replied", on_reply)


## view: tablet_presenter.gd build(); objectives: mission_director objectives(); context: [district key, contract key].
func show_data(view: Dictionary, objectives: Array, context: Array[String] = []) -> void:
	_view = view
	_objectives = objectives
	if not context.is_empty():
		_context = context
	if selected == "" or not (view["nodes"] as Dictionary).has(selected):
		selected = str(view["order"][0])
	_rebuild()


func set_ui_scale(percent: int) -> void:
	ui_scale_percent = clampi(percent, int(tokens["ui_scale_percent"]["min"]), int(tokens["ui_scale_percent"]["max"]))
	_rebuild()


func set_device(input_device: String) -> void:
	device = input_device
	_rebuild()


func open() -> void:
	_previous_focus = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	visible = true
	_focus_default()


func close() -> void:
	visible = false
	if _previous_focus != null and is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	elif is_inside_tree() and get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_release_focus()
	closed.emit()


## Every control the player can focus in the tablet (tests walk the focus graph from these).
func focusables() -> Array[Control]:
	var out: Array[Control] = []
	_collect_focusables(self, out)
	return out


func select(nid: String) -> void:
	if nid == selected:
		return
	selected = nid
	_status_text = ""
	_fill_detail()


func inspect_selected() -> void:
	var v: Dictionary = _view["nodes"].get(selected, {})
	if v.is_empty() or str(v["panel"]) == "":
		return  # consumers and sources without a meter panel only show what is visible
	gate.call("send", "inspect", str(v["panel"]), {})


func ping_selected() -> void:
	var v: Dictionary = _view["nodes"].get(selected, {})
	if v.is_empty():
		return
	gate.call("send", "ping", selected, {"ping": "PING_FAULT" if TabletPresenter.shows_fault(v) else "PING_LOOK"})


func on_reply(envelope: Dictionary, reply: Dictionary) -> void:
	if envelope.get("type") != "inspect":
		return
	if reply.get("ok", false):
		_status_text = UiText.t("tablet.inspected")
	else:
		var key: String = str(reply.get("key", ""))
		_status_text = UiText.tf("tablet.inspect_refused", [UiText.t(key if UiText.has(key) else "network.refused.generic")])
	if _detail != null:
		_fill_detail()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("map_meter") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()  # Tab must not also move focus (ui_focus_next)
	elif event.is_action_pressed("ping") and tab == TAB_NETWORK:
		ping_selected()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion and event.is_action_pressed("tool_primary"):
		_zoom(1)
	elif event is InputEventJoypadMotion and event.is_action_pressed("tool_secondary"):
		_zoom(-1)


## The screen the tablet covers: its parent's rect, else the viewport. Never its own size, which grows with its content and
## would feed back into the scale (a rebuild loop).
func screen_size() -> Vector2:
	var parent: Control = get_parent() as Control
	if parent != null:
		return parent.size
	return get_viewport_rect().size if is_inside_tree() else ThemeTokens.DESIGN_SIZE


func _on_resized() -> void:
	if not is_equal_approx(ThemeTokens.effective_percent(ui_scale_percent, screen_size()), scale_percent) and not _view.is_empty():
		_rebuild()


# ---------- build ----------

func _rebuild() -> void:
	if _view.is_empty():
		return
	var had_focus: bool = is_inside_tree() and get_viewport().gui_get_focus_owner() != null \
		and is_ancestor_of(get_viewport().gui_get_focus_owner())
	scale_percent = ThemeTokens.effective_percent(ui_scale_percent, screen_size())
	theme = ThemeTokens.build(tokens, scale_percent)
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	tab_buttons.clear()
	zoom_buttons.clear()
	var s: float = scale_percent
	var margin: MarginContainer = MarginContainer.new()
	var safe: int = ThemeTokens.safe_area(tokens, screen_size())
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, safe)
	add_child(margin)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", ThemeTokens.px(SECTION_GAP_PX, s))
	margin.add_child(page)
	page.add_child(_header())
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", ThemeTokens.px(24, s))
	page.add_child(body)
	_body_left = PanelContainer.new()
	_body_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_body_left)
	map = TabletMap.new()
	map.name = "Map"
	map.setup(tokens, s, _view)
	map.node_activated.connect(func(nid: String) -> void:
		select(nid)
		inspect_selected())
	map.node_focused.connect(select)
	if tab == TAB_NETWORK:
		_body_left.add_child(map)
	else:
		_body_left.add_child(_objective_list())
	var detail_panel: PanelContainer = PanelContainer.new()
	detail_panel.name = "Detail"
	detail_panel.custom_minimum_size.x = ThemeTokens.px(DETAIL_WIDTH_PX, s)
	body.add_child(detail_panel)
	var detail_box: VBoxContainer = VBoxContainer.new()
	detail_panel.add_child(detail_box)
	# evidence scrolls; Ping stays below it, never under the fold (blueprint p.22 scroll panels)
	detail_scroll = FocusScroll.new()
	detail_scroll.name = "Evidence"
	detail_scroll.setup(tokens, s)
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_box.add_child(detail_scroll)
	detail_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", ThemeTokens.px(8, s))
	detail_scroll.add_child(_detail)
	ping_button = _button(detail_box, "", "PrimaryButton")
	ping_button.name = "Ping"
	ping_button.pressed.connect(ping_selected)
	page.add_child(_footer())
	_link_focus()
	_fill_detail()
	if had_focus:
		_focus_default()


## Explicit focus exits between the regions (blueprint p.22: every control reachable by controller). Inside the map the
## stick follows the graph (tablet_map.gd); at its edges it leaves to the tabs (up), the evidence panel (right) and the footer.
func _link_focus() -> void:
	var footer: Array[Button] = []
	for b: Button in zoom_buttons:
		footer.append(b)
	footer.append(close_button)
	for i: int in footer.size():
		if i > 0:
			_neighbor(footer[i], SIDE_LEFT, footer[i - 1])
		if i < footer.size() - 1:
			_neighbor(footer[i], SIDE_RIGHT, footer[i + 1])
		_neighbor(footer[i], SIDE_TOP, ping_button if footer[i].visible and tab == TAB_NETWORK else detail_scroll)
	var tabs: Array = tab_buttons.values()
	var first: Control = map.nodes[_view["order"][0]] if tab == TAB_NETWORK else detail_scroll
	for b: Button in tabs:
		_neighbor(b, SIDE_BOTTOM, first)
	_neighbor(tabs[0], SIDE_RIGHT, tabs[1])
	_neighbor(tabs[1], SIDE_LEFT, tabs[0])
	_neighbor(tabs[1], SIDE_RIGHT, detail_scroll)
	_neighbor(detail_scroll, SIDE_TOP, tabs[1])
	_neighbor(detail_scroll, SIDE_BOTTOM, ping_button if tab == TAB_NETWORK else close_button)
	_neighbor(ping_button, SIDE_TOP, detail_scroll)
	_neighbor(ping_button, SIDE_BOTTOM, close_button)
	if tab == TAB_NETWORK:
		_neighbor(detail_scroll, SIDE_LEFT, map.nodes[selected] if map.nodes.has(selected) else first)
		_neighbor(ping_button, SIDE_LEFT, map.nodes[selected] if map.nodes.has(selected) else first)
		map.exits = {SIDE_TOP: tabs[0], SIDE_RIGHT: detail_scroll, SIDE_BOTTOM: footer[0]}
		map.queue_sort()
	else:
		_neighbor(detail_scroll, SIDE_LEFT, tabs[1])


func _neighbor(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))


func _header() -> Control:
	var s: float = scale_percent
	var row: HBoxContainer = HBoxContainer.new()
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", ThemeTokens.px(4, s))
	row.add_child(titles)
	var ctx: Label = _label(titles, "%s  /  %s" % [UiText.t(_context[0]), UiText.t(_context[1])], "StrongLabel", "restored")
	ctx.uppercase = true
	_label(titles, UiText.t("tablet.title"), "HeaderLarge")
	_label(titles, UiText.t("tablet.subtitle"), "MutedLabel")
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(tabs)
	var group: ButtonGroup = ButtonGroup.new()
	for t: String in [TAB_NETWORK, TAB_OBJECTIVES]:
		var b: Button = _button(tabs, UiText.t("tablet.tab." + t))
		b.name = "Tab_" + t
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = t == tab
		b.pressed.connect(_show_tab.bind(t))
		tab_buttons[t] = b
	return row


func _footer() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	var legend: HFlowContainer = HFlowContainer.new()
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	legend.add_theme_constant_override("h_separation", ThemeTokens.px(24, scale_percent))
	row.add_child(legend)
	for entry: Array in LEGEND:
		legend.add_child(StatusChip.make(tokens, scale_percent, entry[0], entry[1]))
	for z: Array in [["tablet.zoom_out", -1], ["tablet.zoom_in", 1]]:
		var b: Button = _button(row, UiText.t(z[0]))
		b.name = "Zoom_%s" % ("out" if int(z[1]) < 0 else "in")
		b.pressed.connect(_zoom.bind(int(z[1])))
		zoom_buttons.append(b)
	var center: Button = _button(row, UiText.t("tablet.center"))
	center.name = "Center"
	center.pressed.connect(func() -> void: map.center_view())
	zoom_buttons.append(center)
	for b: Button in zoom_buttons:
		b.visible = tab == TAB_NETWORK  # map tools leave with the map rather than sitting disabled without a reason
	close_button = _button(row, UiText.tf("prompt.binding", [UiText.binding("map_meter", device), UiText.t("tablet.close")]))
	close_button.name = "Close"
	close_button.pressed.connect(close)
	return row


func _objective_list() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "ObjectiveList"
	for o: Dictionary in _objectives:
		box.add_child(StatusChip.make(tokens, scale_percent, "objectives", str(o["status"]), UiText.t(str(o["text_key"])), true))
	return box


func _fill_detail() -> void:
	if _detail == null:
		return
	for c: Node in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	var v: Dictionary = _view["nodes"].get(selected, {})
	if v.is_empty():
		return
	var name_text: String = UiText.t(str(v["name_key"]))
	var head: Label = _label(_detail, UiText.tf("tablet.selected", [name_text]), "StrongLabel", "action")
	head.uppercase = true
	_detail.add_child(StatusChip.make(tokens, scale_percent, v["status_group"], v["status_state"], "", true, "HeaderMedium"))
	if v.has("source_text"):
		_section(UiText.t("tablet.section.source"), [v["source_text"]])
	var evidence: Array = []
	for f: Dictionary in v["findings"]:
		evidence.append(f)
	if evidence.is_empty():
		_section(UiText.t("tablet.section.evidence"), v["lines"])
	else:
		_section(UiText.t("tablet.section.evidence"), v["lines"])
		for f: Dictionary in evidence:
			_detail.add_child(StatusChip.make(tokens, scale_percent, "findings", str(f["code"]), "", true))
	if v.has("access_key"):
		_section(UiText.t("tablet.section.access"), [UiText.t(str(v["access_key"]))])
	if str(v["panel"]) != "":
		_section(UiText.t("tablet.section.worker"), [v.get("worker_text", UiText.t("tablet.no_worker"))])
		_label(_detail, UiText.tf("tablet.inspect_hint", ["[%s]" % UiText.binding("ui_accept", device)]), "MutedLabel")
	if _status_text != "":
		_label(_detail, _status_text, "StrongLabel", "action")
	_label(_detail, UiText.t("tablet.footnote"), "MutedLabel")
	ping_button.text = UiText.tf("prompt.binding", [UiText.binding("ping", device), UiText.tf("tablet.ping_branch", [name_text])])
	ping_button.visible = tab == TAB_NETWORK


func _section(title: String, lines: Array) -> void:
	var t: Label = _label(_detail, title, "StrongLabel", "text_muted")
	t.uppercase = true
	for line: Variant in lines:
		_label(_detail, str(line))


func _show_tab(t: String) -> void:
	if t == tab:
		return
	tab = t
	_rebuild()
	(tab_buttons[t] as Button).grab_focus()


func _zoom(step: int) -> void:
	map.set_zoom_index(map.zoom_index + step)
	map.ensure_visible(selected)


func _focus_default() -> void:
	if tab == TAB_NETWORK and map != null and map.nodes.has(selected):
		(map.nodes[selected] as Control).grab_focus()
	elif tab_buttons.has(tab):
		(tab_buttons[tab] as Button).grab_focus()


func _collect_focusables(n: Node, out: Array[Control]) -> void:
	for c: Node in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			var ctl: Control = c
			if ctl.focus_mode == Control.FOCUS_ALL and not (ctl is BaseButton and (ctl as BaseButton).disabled):
				out.append(ctl)
			_collect_focusables(c, out)


func _label(parent: Control, text: String, variation: String = "", color_token: String = "") -> Label:
	var l: Label = Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if color_token != "":
		l.add_theme_color_override("font_color", ThemeTokens.color(tokens, color_token))
	parent.add_child(l)
	return l


func _button(parent: Control, text: String, variation: String = "") -> Button:
	var b: Button = Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.custom_minimum_size.y = ThemeTokens.px(ThemeTokens.BUTTON_HEIGHT_PX, scale_percent)
	b.focus_mode = Control.FOCUS_ALL
	parent.add_child(b)
	return b
