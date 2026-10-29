extends Container
## Directed network map for the S07 tablet (blueprint p.23, reference p.43). Nodes sit on the authored tablet.json grid;
## edges are drawn from grid.json, solid when energized (teal from the grid, amber from temporary supply), dashed coral when a
## meter measured the feed broken, dashed gray-blue when nothing is known (never shown as certain).
## Controller: the left stick / D-pad moves focus to the adjacent node in that direction (graph neighbors first), the right
## stick pans, the triggers zoom. Focusing a node scrolls it fully into view, so every node is usable at 150 % UI scale.

signal node_activated(node_id: String)
signal node_focused(node_id: String)

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const TabletNode := preload("res://scripts/ui/tablet_node.gd")
const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")

const NODE_WIDTH_PX: int = 230
const COL_GAP_PX: int = 44
const ROW_GAP_PX: int = 64
const PAD_PX: int = 28
const LANE_PX: int = 22
const ARROW_PX: int = 11
const DASH_PX: int = 10
const LIVE_WIDTH_PX: float = 4.0
const DASHED_WIDTH_PX: float = 3.0
const ZOOM_LEVELS: Array[float] = [0.6, 0.8, 1.0, 1.25, 1.5]
const DIRECTION_CONE: float = 0.35  # cos of the widest angle still counted as "in that direction"
const PAN_SPEED_PX: float = 900.0

var tokens: Dictionary = {}
var scale_percent: float = 100.0
var zoom_index: int = 2
var _wanted_zoom_index: int = 2  # the player's choice; zoom_index is it, capped by what fits
var offset: Vector2 = Vector2.ZERO
var nodes: Dictionary = {}  # node id -> TabletNode
var _view: Dictionary = {}
var _cell_rects: Dictionary = {}  # node id -> Rect2 in unzoomed map space
var _content_size: Vector2 = Vector2.ZERO
var _max_zoom_index: int = ZOOM_LEVELS.size() - 1  # the largest zoom that still shows the biggest node whole
var exits: Dictionary = {}  # Side -> Control outside the map, for directions with no node (the tablet sets these)


func _init() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(theme_tokens: Dictionary, effective_percent: float, view: Dictionary) -> void:
	tokens = theme_tokens
	scale_percent = effective_percent
	_view = view
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	nodes.clear()
	for nid: String in view["order"]:
		var n: PanelContainer = TabletNode.new()
		n.setup(tokens, scale_percent, view["nodes"][nid])
		n.activated.connect(func(id: String) -> void: node_activated.emit(id))
		n.focus_entered.connect(_on_node_focus.bind(nid))
		add_child(n)
		nodes[nid] = n
	queue_sort()


func zoom() -> float:
	return ZOOM_LEVELS[zoom_index]


func set_zoom_index(i: int) -> void:
	_wanted_zoom_index = clampi(i, 0, _max_zoom_index)
	zoom_index = _wanted_zoom_index
	queue_sort()


func center_view() -> void:
	offset = (size - _content_size * zoom()) * 0.5
	queue_sort()


func pan(delta: Vector2) -> void:
	offset -= delta
	queue_sort()


## Rect of a node in map coordinates at the current pan and zoom.
func node_rect(nid: String) -> Rect2:
	var r: Rect2 = _cell_rects.get(nid, Rect2())
	return Rect2(offset + r.position * zoom(), r.size * zoom())


func ensure_visible(nid: String) -> void:
	var margin: float = ThemeTokens.px(PAD_PX, scale_percent)
	var r: Rect2 = node_rect(nid).grow(margin)
	var shift: Vector2 = Vector2.ZERO
	if r.size.x > size.x or r.position.x < 0.0:
		shift.x = -r.position.x
	elif r.end.x > size.x:
		shift.x = size.x - r.end.x
	if r.size.y > size.y or r.position.y < 0.0:
		shift.y = -r.position.y
	elif r.end.y > size.y:
		shift.y = size.y - r.end.y
	if shift != Vector2.ZERO:
		offset += shift
		queue_sort()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or not nodes.values().has(get_viewport().gui_get_focus_owner()):
		return  # the right stick pans the map while a node has focus; the evidence panel scrolls with it otherwise
	var stick: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick != Vector2.ZERO:
		pan(stick * PAN_SPEED_PX * scale_percent / 100.0 * delta)


func _on_node_focus(nid: String) -> void:
	ensure_visible(nid)
	node_focused.emit(nid)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_layout()
	elif what == NOTIFICATION_RESIZED and _content_size != Vector2.ZERO:
		_clamp_offset()


func _layout() -> void:
	if nodes.is_empty():
		return
	var s: float = scale_percent
	var w: float = ThemeTokens.px(NODE_WIDTH_PX, s)
	var pad: float = ThemeTokens.px(PAD_PX, s)
	var row_h: Dictionary = {}
	var cols: int = 0
	var rows: int = 0
	for nid: String in nodes:
		var n: Control = nodes[nid]
		if not is_equal_approx(n.size.x, w):
			n.size = Vector2(w, n.size.y)  # labels wrap at the node width before the height is read
		var v: Dictionary = _view["nodes"][nid]
		row_h[v["row"]] = maxf(float(row_h.get(v["row"], 0.0)), n.get_combined_minimum_size().y)
		cols = maxi(cols, int(v["col"]) + 1)
		rows = maxi(rows, int(v["row"]) + 1)
	var row_y: Array[float] = []
	var y: float = pad
	for r: int in rows:
		row_y.append(y)
		y += float(row_h.get(r, 0.0)) + ThemeTokens.px(ROW_GAP_PX, s)
	_content_size = Vector2(pad * 2.0 + cols * w + (cols - 1) * ThemeTokens.px(COL_GAP_PX, s) + ThemeTokens.px(LANE_PX * 2, s),
		y - ThemeTokens.px(ROW_GAP_PX, s) + pad)
	for nid: String in nodes:
		var v: Dictionary = _view["nodes"][nid]
		var x: float = pad + int(v["col"]) * (w + ThemeTokens.px(COL_GAP_PX, s))
		_cell_rects[nid] = Rect2(Vector2(x, row_y[int(v["row"])]), Vector2(w, float(row_h[v["row"]])))
	_fit_zoom(w, row_h.values().max() if not row_h.is_empty() else 0.0, pad)
	_clamp_offset()
	for nid: String in nodes:
		var n: Control = nodes[nid]
		var r: Rect2 = _cell_rects[nid]
		n.scale = Vector2(zoom(), zoom())
		n.position = offset + r.position * zoom()
		n.size = r.size
	_link_focus()
	queue_redraw()


## Zoom levels at which the biggest node would not fit the view are skipped, so focusing any node shows all of it.
func _fit_zoom(node_w: float, node_h: float, margin: float) -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_max_zoom_index = 0
	for i: int in ZOOM_LEVELS.size():
		if (node_w + margin * 2.0) * ZOOM_LEVELS[i] <= size.x and (node_h + margin * 2.0) * ZOOM_LEVELS[i] <= size.y:
			_max_zoom_index = i
	zoom_index = mini(_wanted_zoom_index, _max_zoom_index)


## Keeps some of the map on screen; a map smaller than the view stays centered.
func _clamp_offset() -> void:
	var content: Vector2 = _content_size * zoom()
	for axis: int in 2:
		if content[axis] <= size[axis]:
			offset[axis] = (size[axis] - content[axis]) * 0.5
		else:
			offset[axis] = clampf(offset[axis], size[axis] - content[axis], 0.0)


## Directional focus: the nearest node in the cone of each direction, graph neighbors preferred. Where no node lies in a
## direction the path stays empty, so Godot's own search leaves the map toward the tabs, the detail panel or the footer.
func _link_focus() -> void:
	var adjacent: Dictionary = {}
	for e: Dictionary in _view["edges"]:
		adjacent[str(e["from"]) + ">" + str(e["to"])] = true
		adjacent[str(e["to"]) + ">" + str(e["from"])] = true
	var dirs: Dictionary = {SIDE_LEFT: Vector2.LEFT, SIDE_RIGHT: Vector2.RIGHT, SIDE_TOP: Vector2.UP, SIDE_BOTTOM: Vector2.DOWN}
	for a: String in nodes:
		var ca: Vector2 = (_cell_rects[a] as Rect2).get_center()
		for side: int in dirs:
			var best: String = ""
			var best_score: float = INF
			for b: String in nodes:
				if a == b:
					continue
				var d: Vector2 = (_cell_rects[b] as Rect2).get_center() - ca
				var along: float = d.normalized().dot(dirs[side])
				if along < DIRECTION_CONE:
					continue
				var score: float = d.length() / along * (0.6 if adjacent.has(a + ">" + b) else 1.0)
				if score < best_score:
					best_score = score
					best = b
			var target: Control = nodes[best] if best != "" else exits.get(side, null)
			var path: NodePath = (nodes[a] as Control).get_path_to(target) if target != null else NodePath()
			(nodes[a] as Control).set_focus_neighbor(side as Side, path)


func _draw() -> void:
	if nodes.is_empty():
		return
	for e: Dictionary in _view["edges"]:
		if not (nodes.has(e["from"]) and nodes.has(e["to"])):
			continue
		var pts: PackedVector2Array = _route(node_rect(e["from"]), node_rect(e["to"]))
		var style: String = e["style"]
		var token: String = {TabletPresenter.EDGE_GRID: "restored", TabletPresenter.EDGE_TEMP: "action",
			TabletPresenter.EDGE_FAULT: "fault"}.get(style, "unknown")
		var c: Color = ThemeTokens.color(tokens, token)
		var live: bool = style == TabletPresenter.EDGE_GRID or style == TabletPresenter.EDGE_TEMP
		var width: float = maxf(1.0, (LIVE_WIDTH_PX if live else DASHED_WIDTH_PX) * scale_percent / 100.0 * zoom())
		for i: int in pts.size() - 1:
			if live:
				draw_line(pts[i], pts[i + 1], c, width)
			else:
				draw_dashed_line(pts[i], pts[i + 1], c, width, DASH_PX * scale_percent / 100.0 * zoom())
		_arrow(pts[pts.size() - 2], pts[pts.size() - 1], c)


## Orthogonal route: same row = side to side; next row = down (or up) through the gap between the rows; further rows = out
## along a lane right of the target so the line never crosses another node.
func _route(a: Rect2, b: Rect2) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var row_gap: float = ThemeTokens.px(ROW_GAP_PX, scale_percent) * zoom()
	if absf(a.get_center().y - b.get_center().y) < 1.0:
		var right: bool = b.position.x > a.position.x
		pts.append(Vector2(a.end.x if right else a.position.x, a.get_center().y))
		pts.append(Vector2(b.position.x if right else b.end.x, b.get_center().y))
	elif b.position.y > a.end.y and b.position.y - a.end.y < row_gap * 1.5:
		var mid: float = (a.end.y + b.position.y) * 0.5
		pts.append_array([Vector2(a.get_center().x, a.end.y), Vector2(a.get_center().x, mid), Vector2(b.get_center().x, mid),
			Vector2(b.get_center().x, b.position.y)])
	elif b.end.y < a.position.y and a.position.y - b.end.y < row_gap * 1.5:
		var mid_up: float = (a.position.y + b.end.y) * 0.5
		pts.append_array([Vector2(a.get_center().x, a.position.y), Vector2(a.get_center().x, mid_up), Vector2(b.get_center().x, mid_up),
			Vector2(b.get_center().x, b.end.y)])
	else:
		var lane: float = maxf(a.end.x, b.end.x) + ThemeTokens.px(LANE_PX, scale_percent) * zoom()
		pts.append_array([Vector2(a.end.x, a.get_center().y), Vector2(lane, a.get_center().y), Vector2(lane, b.get_center().y),
			Vector2(b.end.x, b.get_center().y)])
	return pts


func _arrow(from: Vector2, to: Vector2, c: Color) -> void:
	var dir: Vector2 = (to - from).normalized()
	var s: float = ARROW_PX * scale_percent / 100.0 * zoom()
	var side: Vector2 = Vector2(-dir.y, dir.x) * s * 0.6
	draw_colored_polygon(PackedVector2Array([to, to - dir * s + side, to - dir * s - side]), c)
