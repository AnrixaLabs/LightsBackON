extends "res://tests/test_case.gd"
## V07: field HUD and network tablet (S06/S07, blueprint p.23; references p.42-43; ADR-004 point 5).
## Acceptance: "Map inspects and pings only; controller focus complete; 150% scale usable." Automated here: the tablet sends
## nothing but inspect and ping whatever the player presses, and the grid is unchanged by it; the directional focus graph
## reaches every control from every control; nothing overflows its container or the safe area at 1280x720 / 1920x1080 /
## 1920x1200 x 80/100/150 % x English / 35 % pseudo-locale (UX02/UX03 layout part); every status is icon + text in its token
## color. A person pressing a real controller (UX01) and judging readability stays pending local.

const Fixture := preload("res://tests/support/ui_fixture.gd")
const Runner := preload("res://tests/support/solution_runner.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const IntentOutbox := preload("res://scripts/ui/intent_outbox.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const StatusChip := preload("res://scripts/ui/status_chip.gd")
const IconRaster := preload("res://scripts/ui/icon_raster.gd")
const TabletMap := preload("res://scripts/ui/tablet_map.gd")
const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const SIZES: Array[Vector2] = [Vector2(1280, 720), Vector2(1920, 1080), Vector2(1920, 1200)]
const SCALES: Array[int] = [80, 100, 150]
const LOCALES: Array[String] = [UiText.LOCALE_EN, UiText.LOCALE_PSEUDO]
const SIDES: Array[Side] = [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]
const TABLET_PLAYER: String = "P4"  # sends nothing in the fixture, so the outbox owns its sequence numbers

var _ctx: Dictionary
var _tokens: Dictionary
var _sent: Array[Dictionary] = []
var _owned: Array[Node] = []


func before_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	UiText.clear_missing()
	_ctx = Fixture.mid_shift()
	assert_true((_ctx["errors"] as Array).is_empty(), str(_ctx["errors"]))
	assert_eq(_ctx["failures"], [] as Array[String], "fixture replays the first part of the C01 solution")
	_tokens = Runner.json("res://content/ui/tokens.json")
	_sent.clear()


func after_each() -> void:
	UiText.set_locale(UiText.LOCALE_EN)
	for n: Node in _owned:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()
	_owned.clear()
	_ctx = {}


# ---------- acceptance: map inspects and pings only ----------

func test_V07_map_sends_only_inspect_and_ping_and_never_changes_the_network() -> void:
	var before: Dictionary = (_ctx["host"].authoritative_state() as Dictionary).duplicate(true)
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100, true)
	tablet.open()
	for nid: String in tablet.map.nodes:
		var node: Control = tablet.map.nodes[nid]
		node.grab_focus()
		node._gui_input(_action("ui_accept"))
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		node._gui_input(click)
		tablet.ping_button.pressed.emit()
	for action: StringName in InputMap.get_actions():
		if not tablet.visible:
			tablet.open()
		tablet._input(_action(action))
	for b: Control in Fixture.controls(tablet):
		if b is BaseButton and b != tablet.close_button and b.is_visible_in_tree():
			(b as BaseButton).pressed.emit()
	var kinds: Dictionary = {}
	for env: Dictionary in _sent:
		kinds[env["type"]] = true
	assert_eq(kinds.keys().filter(func(k: String) -> bool: return not NetworkTablet.MAP_INTENTS.has(k)), [],
		"the tablet sent only %s" % str(NetworkTablet.MAP_INTENTS))
	assert_true(kinds.has("inspect") and kinds.has("ping"), "pressing nodes inspects; Ping pings (%d intents)" % _sent.size())
	var after: Dictionary = _ctx["host"].authoritative_state()
	for part: String in ["grid", "repairs", "equipment", "mission", "crew"]:
		assert_eq(PowerGrid.serialize(after[part]), PowerGrid.serialize(before[part]), "%s unchanged by the tablet" % part)
	var refused: Dictionary = tablet.gate.send("toggle_switch", "SW_SIGN", {"value": true})
	assert_eq(refused.get("code"), "UI_INTENT_NOT_ALLOWED", "the gate refuses a switch before anything is sent")
	assert_false(_sent.any(func(e: Dictionary) -> bool: return e["type"] == "toggle_switch"))


func test_V07_inspect_goes_through_the_host_and_its_answer_is_shown() -> void:
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100, true)
	tablet.open()
	tablet.select("TEMP")
	tablet.inspect_selected()
	assert_eq(_sent[-1]["type"], "inspect")
	assert_eq(_sent[-1]["entity"], "PANEL_TEMP", "a node inspects its own meter panel")
	assert_eq(_ctx["host"].revision > 0, true)
	tablet.select("APT_W")
	var count: int = _sent.size()
	tablet.inspect_selected()
	assert_eq(_sent.size(), count, "a building without a meter panel sends nothing")


# ---------- acceptance: controller focus complete ----------

func test_V07_directional_focus_reaches_every_control_from_every_control() -> void:
	for size: Vector2 in [Vector2(1920, 1080), Vector2(1280, 720)]:
		for scale: int in [100, 150]:
			for tab: String in [NetworkTablet.TAB_NETWORK, NetworkTablet.TAB_OBJECTIVES]:
				var tablet: PanelContainer = _tablet(size, scale)
				if tab != tablet.tab:
					tablet._show_tab(tab)
					Fixture.settle(tablet)
				var where: String = "%dx%d @%d%% %s" % [size.x, size.y, scale, tab]
				var all: Array[Control] = tablet.focusables()
				assert_true(all.size() >= (18 if tab == NetworkTablet.TAB_NETWORK else 3), "%s: %d focusable controls" % [where, all.size()])
				var graph: Dictionary = {}
				for c: Control in all:
					var next: Array[Control] = []
					for side: Side in SIDES:
						var n: Control = c.find_valid_focus_neighbor(side)
						if n != null and n != c and all.has(n):
							next.append(n)
					assert_false(next.is_empty(), "%s: %s has a way out" % [where, c.name])
					graph[c] = next
				for start: Control in all:
					var seen: Dictionary = _reach(graph, start)
					var missing: Array = all.filter(func(c: Control) -> bool: return not seen.has(c)).map(func(c: Control) -> String:
						return str(c.name))
					if not missing.is_empty():
						assert_eq(missing, [], "%s: from %s the stick/D-pad cannot reach" % [where, start.name])
						break
				for c: Control in all:
					var target: float = ThemeTokens.px(float(_tokens["min_target_px"]), tablet.scale_percent) - 0.5
					assert_true(c.size.x >= target and c.size.y >= target, "%s: %s is at least the 48 px target" % [where, c.name])
				_free(tablet)


func test_V07_opening_moves_focus_in_and_closing_restores_it() -> void:
	var host: Button = Button.new()
	_root().add_child(host)
	_owned.append(host)
	host.grab_focus()
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 100)
	tablet.visible = false
	tablet.open()
	var owner: Control = _root().gui_get_focus_owner()
	assert_true(owner != null and tablet.is_ancestor_of(owner), "focus moved into the tablet")
	assert_eq(owner, tablet.map.nodes[tablet.selected], "first focus is the selected node")
	tablet._input(_action("ui_cancel"))
	assert_false(tablet.visible, "B / Esc closes")
	assert_eq(_root().gui_get_focus_owner(), host, "closing restores the previous control")
	tablet.open()
	tablet._input(_action("map_meter"))
	assert_false(tablet.visible, "the tablet key closes it again")


func test_V07_controller_bindings_show_the_device_and_follow_remapping() -> void:
	assert_eq(UiText.binding("interact", UiText.DEVICE_KBM), "E")
	assert_eq(UiText.binding("interact", UiText.DEVICE_PAD), "A")
	assert_eq(UiText.binding("ping", UiText.DEVICE_KBM), "MMB")
	assert_eq(UiText.binding("ping", UiText.DEVICE_PAD), "LB")
	assert_eq(UiText.binding("ui_accept", UiText.DEVICE_PAD), "A", "controller Accept is A on the tablet")
	assert_eq(UiText.binding("ui_cancel", UiText.DEVICE_PAD), "B", "controller Back is B")
	var original: Array[InputEvent] = InputMap.action_get_events("interact")
	InputMap.action_erase_events("interact")
	var f: InputEventKey = InputEventKey.new()
	f.physical_keycode = KEY_F
	InputMap.action_add_event("interact", f)
	assert_eq(UiText.binding("interact", UiText.DEVICE_KBM), "F", "a remapped action shows its new key")
	InputMap.action_erase_events("interact")
	for e: InputEvent in original:
		InputMap.action_add_event("interact", e)


# ---------- acceptance: 150 % usable; reflow under longer text ----------

func test_V07_hud_fits_the_safe_area_at_every_size_scale_and_locale() -> void:
	for locale: String in LOCALES:
		UiText.set_locale(locale)
		var view: Dictionary = Fixture.worst_hud_view()
		for size: Vector2 in SIZES:
			for scale: int in SCALES:
				var hud: Container = _hud(size, scale, view)
				var where: String = "HUD %dx%d @%d%% %s" % [size.x, size.y, scale, locale]
				var safe: float = ThemeTokens.safe_area(_tokens, size)
				var inner: Rect2 = Rect2(Vector2(safe, safe), size - Vector2(safe, safe) * 2.0)
				var regions: Array[Control] = hud.regions()
				for r: Control in regions:
					assert_true(Fixture.rect_inside(r.get_rect(), inner), "%s: %s inside the 80 px safe area %s" % [where, r.name, r.get_rect()])
				for i: int in regions.size():
					for j: int in range(i + 1, regions.size()):
						assert_false(regions[i].get_rect().intersects(regions[j].get_rect()),
							"%s: %s overlaps %s" % [where, regions[i].name, regions[j].name])
					assert_false(regions[i].get_rect().intersects(hud.reticle.get_rect()), "%s: %s covers the reticle" % [where, regions[i].name])
				assert_true(hud.prompt_card.position.y > hud.reticle.get_rect().end.y, "%s: prompt below the reticle" % where)
				_assert_no_overflow(hud, where)
				_free(hud)
	assert_eq(UiText.missing(), [] as Array[String], "every HUD string has English text")


func test_V07_tablet_fits_and_every_node_scrolls_fully_into_view() -> void:
	for locale: String in LOCALES:
		UiText.set_locale(locale)
		for size: Vector2 in SIZES:
			for scale: int in SCALES:
				var tablet: PanelContainer = _tablet(size, scale)
				var where: String = "tablet %dx%d @%d%% %s" % [size.x, size.y, scale, locale]
				for nid: String in ["JE", "GRID"]:  # JE carries the longest evidence list
					tablet.select(nid)
					Fixture.settle(tablet)
					_assert_no_overflow(tablet, where + " " + nid, [tablet.map, tablet.detail_scroll])
					var bar: VScrollBar = tablet.detail_scroll.get_v_scroll_bar()
					var content_h: float = tablet.detail_scroll.get_child(0).get_combined_minimum_size().y
					if content_h > tablet.detail_scroll.size.y + 0.5:
						assert_true(bar.visible, "%s %s: long evidence shows a scroll position indicator" % [where, nid])
					assert_true(Fixture.rect_inside(tablet.ping_button.get_global_rect(), tablet.get_global_rect()),
						"%s %s: Ping is never below the fold" % [where, nid])
				var map: Container = tablet.map
				for nid: String in map.nodes:
					map.ensure_visible(nid)
					Fixture.settle(tablet)
					var r: Rect2 = map.node_rect(nid)
					if r.size.x <= map.size.x and r.size.y <= map.size.y:
						assert_true(Fixture.rect_inside(r, Rect2(Vector2.ZERO, map.size)), "%s: node %s scrolls fully into view" % [where, nid])
					else:
						assert_true(false, "%s: node %s %s is larger than the map %s" % [where, nid, r.size, map.size])
					_assert_no_overflow(map.nodes[nid], "%s node %s" % [where, nid])
				_free(tablet)
	assert_eq(UiText.missing(), [] as Array[String], "every tablet string has English text")


func test_V07_hud_follows_the_reference_layout_at_100_percent() -> void:
	var hud: Container = _hud(Vector2(1920, 1080), 100, Fixture.hud_view(_ctx))
	assert_eq(hud.objective_card.position, Vector2(80, 80), "objective top-left at the safe area (S06 x=80)")
	assert_eq(hud.objective_card.size.x, 420.0, "420 px objective card")
	assert_eq(hud.crew_card.get_rect().end.x, 1840.0, "crew top-right")
	assert_eq(hud.reticle.get_rect().get_center(), Vector2(960, 540), "reticle at the center")
	assert_eq(hud.prompt_card.position, Vector2(680, 680), "prompt at x=680, y=680, 560 px wide (S06)")
	assert_eq(hud.prompt_card.size.x, 560.0)
	assert_eq(hud.tool_card.position.x, 80.0, "tools bottom-left")
	assert_eq(hud.tool_card.get_rect().end.y, 1000.0)
	assert_eq(hud.event_card.get_rect().end, Vector2(1840, 1000), "event bottom-right")
	var rows: Array[Node] = hud.objective_card.find_children("Objective_*", "", true, false)
	assert_true(rows.size() <= 3, "at most three objective rows (blueprint p.11)")


func test_V07_objective_card_never_shows_more_than_three_rows() -> void:
	var view: Dictionary = Fixture.worst_hud_view()
	var many: Array[Dictionary] = []
	for i: int in 6:
		many.append({"id": "O%d" % i, "text_key": "objective.c01.extract", "status": "active"})
	view["objectives"] = many
	var hud: Container = _hud(Vector2(1920, 1080), 100, view)
	assert_eq(hud.objective_card.find_children("Objective_*", "", true, false).size(), int(_tokens["max_objective_rows"]))


# ---------- status: icon + text + token color ----------

func test_V07_every_status_widget_is_icon_text_and_token_color() -> void:
	var hud: Container = _hud(Vector2(1920, 1080), 150, Fixture.worst_hud_view())
	var tablet: PanelContainer = _tablet(Vector2(1920, 1080), 150)
	tablet.select("JE")
	var chips: Array[Control] = []
	for root: Control in [hud, tablet]:
		for c: Control in Fixture.controls(root):
			if c.get_script() == StatusChip:
				chips.append(c)
	assert_true(chips.size() >= 25, "chips found: %d" % chips.size())
	var groups: Dictionary = {}
	for chip: Control in chips:
		var e: Dictionary = StatusChip.entry(chip.group, chip.state)
		var where: String = "%s.%s" % [chip.group, chip.state]
		groups[chip.group] = true
		assert_false(e.is_empty(), "%s is a state in status_states.json" % where)
		var tint: Color = ThemeTokens.color(_tokens, str(e["color"]))
		var label: Label = chip.label
		var icon: TextureRect = chip.icon_rect
		assert_false(label.text.strip_edges().is_empty(), "%s has text, not color alone" % where)
		assert_eq(label.get_theme_color("font_color"), tint, "%s text in its token color" % where)
		assert_eq(icon.self_modulate, tint, "%s icon tinted with its token color" % where)
		assert_true(icon.texture != null, "%s has an icon" % where)
		if icon.texture != null:
			assert_eq(icon.texture.resource_path, IconRaster.export_path(str(e["icon"]),
				IconRaster.export_px_for_scale(ceili(icon.get_meta("scale_percent")))), "%s draws its own icon at the scale's export" % where)
		assert_true(icon.is_visible_in_tree() and label.is_visible_in_tree(), "%s icon and text both shown" % where)
	for g: String in ["objectives", "other", "supply", "findings", "equipment"]:
		assert_true(groups.has(g), "chips cover %s" % g)


func test_V07_tablet_shows_measured_values_only() -> void:
	var view: Dictionary = Fixture.tablet_view(_ctx)
	var n: Dictionary = view["nodes"]
	assert_eq([n["APT_W"]["status_state"], n["MARKET"]["status_state"]], ["restored", "restored"], "west on grid supply")
	assert_eq(n["PUMP"]["status_state"], "temporary", "pump on the generator")
	assert_eq(n["PUB"]["status_state"], "dark")
	assert_eq([n["JE"]["status_group"], n["JE"]["status_state"]], ["findings", "NO_SOURCE"], "JE: Mira's measurement")
	assert_true((n["JE"]["findings"] as Array).any(func(f: Dictionary) -> bool: return f["code"] == "FEED_OPEN"), "broken trunk measured")
	assert_eq([n["TEMP"]["status_group"], n["TEMP"]["status_state"]], ["other", "unknown"], "never inspected: unknown")
	assert_has_text(n["TEMP"]["lines"], UiText.t("tablet.unknown_measure"))
	assert_true(n["JW"]["needs_reinspect"], "JW changed since P1 measured it before the repair")
	assert_has_text(n["JW"]["lines"], UiText.t("tablet.reinspect"))
	assert_has_text(n["GRID"]["lines"], UiText.tf("tablet.source_load", [9, 24]))
	assert_eq(n["JE"].get("worker_text"), UiText.tf("tablet.worker", ["Mira", UiText.t("repair.c01.east_trunk")]), "lock owner shown")
	assert_false(n["JE"].has("access_key"), "the drained basement opened the east repair")
	var hud: Dictionary = Fixture.hud_view(_ctx)
	var mira: Dictionary = (hud["crew"] as Array).filter(func(r: Dictionary) -> bool: return r["player"] == "P2")[0]
	assert_eq([mira["task_state"], mira["task_text"]], ["lock_owner", UiText.t("repair.c01.east_trunk")], "crew row shows the lock")
	assert_eq((hud["crew"] as Array)[0]["player"], "P1", "the local player is listed first")
	var styles: Dictionary = {}
	for e: Dictionary in view["edges"]:
		styles[e["id"]] = e["style"]
	assert_eq(styles["E_GRID_JW"], "energized_grid")
	assert_eq(styles["E_GEN_TEMP"], "energized_temp")
	assert_eq(styles["E_GRID_JE"], "fault", "the broken trunk shows only because the meter measured it")
	assert_eq(styles["E_TEMP_PUB"], "unknown", "an unmeasured dead route is not shown as fact")
	var tablet_nodes: Array = []
	for cell: Dictionary in Fixture.content()["tablet"]["nodes"]:
		tablet_nodes.append(cell["id"])
	tablet_nodes.sort()
	var grid_nodes: Array = (Fixture.content()["grid"]["nodes"] as Array).map(func(x: Dictionary) -> String: return x["id"])
	grid_nodes.sort()
	assert_eq(tablet_nodes, grid_nodes, "tablet.json places every grid node exactly once")


func test_V07_every_content_text_key_has_english_text() -> void:
	var keys: Dictionary = {}
	_keys_in(Runner.json("res://content/ui/status_states.json"), keys)
	_keys_in(Runner.json("res://content/comms.json"), keys)
	for f: String in ["mission.json", "repairs.json", "tablet.json"]:
		_keys_in(Runner.json(Fixture.C01.path_join(f)), keys)
	assert_true(keys.size() > 60, "keys found: %d" % keys.size())
	var missing: Array = keys.keys().filter(func(k: String) -> bool: return not UiText.has(k))
	missing.sort()
	assert_eq(missing, [], "content keys without English text in content/ui/strings/en.json")


func test_V07_pseudo_locale_is_35_percent_longer_and_keeps_placeholders() -> void:
	var text: String = UiText.pseudo("Measured: %d / %d PU")
	assert_true(text.length() >= ceili("Measured: %d / %d PU".length() * 1.35), text)
	assert_eq(text.count("%d"), 2, "placeholders survive")
	assert_eq((text % [9, 12]).contains("9"), true)
	UiText.set_locale(UiText.LOCALE_PSEUDO)
	assert_ne(UiText.t("tablet.title"), "Network tablet")
	assert_eq(UiText.binding("interact", UiText.DEVICE_KBM), "E", "key caps are not pseudo-localized")


# ---------- helpers ----------

func assert_has_text(lines: Array, text: String) -> void:
	assert_true(lines.has(text), "%s in %s" % [text, str(lines)])


func _assert_no_overflow(root: Control, where: String, skip_below: Array = []) -> void:
	var screen: Rect2 = root.get_global_rect()
	for c: Control in Fixture.controls(root):
		if not c.is_visible_in_tree() or c == root:
			continue
		if skip_below.any(func(s: Control) -> bool: return s != c and s.is_ancestor_of(c)):
			continue
		var parent: Control = c.get_parent() as Control
		if parent != null and not (parent is ScrollContainer):
			if not Fixture.rect_inside(c.get_global_rect(), parent.get_global_rect()):
				assert_true(false, "%s: %s %s spills out of %s %s" % [where, c.name, c.get_global_rect(), parent.name, parent.get_global_rect()])
				return
		var min_size: Vector2 = c.get_combined_minimum_size()
		if c.size.x + 0.75 < min_size.x or c.size.y + 0.75 < min_size.y:
			assert_true(false, "%s: %s squeezed below its minimum %s < %s" % [where, c.name, c.size, min_size])
			return
		if c is Label:
			var l: Label = c
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF and l.get_line_count() > l.get_visible_line_count():
				assert_true(false, "%s: label '%s' hides lines" % [where, l.text])
				return
		if not Fixture.rect_inside(c.get_global_rect(), screen):
			assert_true(false, "%s: %s outside the screen" % [where, c.name])
			return
	assert_true(true)


func _hud(size: Vector2, scale: int, view: Dictionary) -> Container:
	var hud: Container = FieldHud.new()
	_root().add_child(hud)
	_owned.append(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = size
	hud.ui_scale_percent = scale
	hud.apply(view)
	Fixture.settle(hud)
	return hud


func _tablet(size: Vector2, scale: int, live: bool = false) -> PanelContainer:
	var frame: Control = Control.new()  # the screen: the tablet takes its scale from its parent, never from itself
	_root().add_child(frame)
	frame.size = size
	var tablet: PanelContainer = NetworkTablet.new()
	frame.add_child(tablet)
	_owned.append(frame)
	tablet.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tablet.size = size
	tablet.ui_scale_percent = scale
	var peer: int = _ctx["peers"][TABLET_PLAYER]
	var outbox: RefCounted = IntentOutbox.new(Runner.SESSION, func(bytes: PackedByteArray) -> Dictionary:
		return _ctx["host"].receive(peer, bytes) if live else {})
	outbox.sent.connect(func(env: Dictionary) -> void: _sent.append(env))
	tablet.setup(outbox)
	tablet.show_data(Fixture.tablet_view(_ctx), _ctx["mission"].objectives())
	Fixture.settle(tablet)
	return tablet


func _free(n: Node) -> void:
	if n is NetworkTablet:
		n = n.get_parent()  # its screen frame
	_owned.erase(n)
	n.get_parent().remove_child(n)
	n.free()


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _action(action: StringName) -> InputEventAction:
	var ev: InputEventAction = InputEventAction.new()
	ev.action = action
	ev.pressed = true
	return ev


func _reach(graph: Dictionary, start: Control) -> Dictionary:
	var seen: Dictionary = {start: true}
	var queue: Array[Control] = [start]
	while not queue.is_empty():
		var c: Control = queue.pop_front()
		for n: Control in graph[c]:
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


func _keys_in(v: Variant, out: Dictionary) -> void:
	if v is Dictionary:
		for k: Variant in v:
			if str(k) in ["text_key", "name_key"] and v[k] is String:
				out[v[k]] = true
			else:
				_keys_in(v[k], out)
	elif v is Array:
		for x: Variant in v:
			_keys_in(x, out)


func test_V07_hud_and_tablet_scenes_load_their_scripts() -> void:
	for pair: Array in [["res://scenes/ui/field_hud.tscn", FieldHud], ["res://scenes/ui/network_tablet.tscn", NetworkTablet]]:
		var ps: PackedScene = load(pair[0]) as PackedScene
		assert_true(ps != null, "%s loads" % pair[0])
		if ps == null:
			continue
		var n: Node = ps.instantiate()
		assert_eq(n.get_script(), pair[1], "%s root runs its view script" % pair[0])
		n.free()
