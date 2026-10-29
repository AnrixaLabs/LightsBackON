extends RefCounted
## Builds the S07 network tablet view (blueprint p.23) from content and the state the player can know. Pure; no scene tree.
## Rules from S07: the map shows energized paths (lit buildings make them visible) but never shows unmeasured values as fact.
## Junction loads and faults come only from current meter snapshots (meter_model readings()/findings(): unknown is "?");
## a snapshot that no longer matches the network reads "Changed since inspection - inspect again".

const UiText := preload("res://scripts/ui/ui_text.gd")
const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const EDGE_GRID: String = "energized_grid"
const EDGE_TEMP: String = "energized_temp"
const EDGE_FAULT: String = "fault"
const EDGE_UNKNOWN: String = "unknown"


## content: {"grid": grid.json, "tablet": tablet.json, "meter": meter.json, "repairs": repairs.json, "grid_source": id};
## known: {"grid": grid canonical_state, "readings": {panel: readings()}, "findings": {panel: findings()},
##         "repairs": interaction canonical_state, "names": {player: name}}.
## Returns {"nodes": {id: node view}, "edges": Array, "order": node IDs by row then column}.
static func build(content: Dictionary, known: Dictionary) -> Dictionary:
	var grid_state: Dictionary = known["grid"]
	var nodes_state: Dictionary = grid_state["nodes"]
	var edges_state: Dictionary = grid_state["edges"]
	var panels: Dictionary = {}  # node id -> panel id
	for p: Dictionary in (content["meter"] as Dictionary)["panels"]:
		panels[p["target"]] = p["id"]
	var grid_source: String = str(content.get("grid_source", "GRID"))
	var out_nodes: Dictionary = {}
	var order: Array[String] = []
	var cells: Array = (content["tablet"] as Dictionary)["nodes"]
	var sorted_cells: Array = cells.duplicate()
	sorted_cells.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return [int(a["row"]), int(a["col"])] < [int(b["row"]), int(b["col"])])
	for cell: Dictionary in sorted_cells:
		var nid: String = cell["id"]
		order.append(nid)
		var n: Dictionary = nodes_state[nid]
		var panel: String = panels.get(nid, "")
		var r: Dictionary = (known.get("readings", {}) as Dictionary).get(panel, {})
		var v: Dictionary = {"id": nid, "kind": n["kind"], "col": int(cell["col"]), "row": int(cell["row"]),
			"name_key": cell["name_key"], "panel": panel, "lines": [] as Array[String], "findings": [] as Array[Dictionary],
			"needs_reinspect": false, "measured": false}
		var root: String = root_source(nid, nodes_state, edges_state)
		var supply_state: String = "dark" if root == "" else ("restored" if root == grid_source else "temporary")
		match n["kind"]:
			PowerGrid.KIND_CONSUMER:
				_status(v, "supply", supply_state)
				(v["lines"] as Array).append(UiText.tf("tablet.demand", [int(n["demand"])]))
			PowerGrid.KIND_SOURCE:
				if n["online"]:
					_status(v, "supply", "restored" if nid == grid_source else "temporary")
				else:
					_status(v, "findings", "SOURCE_OFFLINE")
				(v["lines"] as Array).append(UiText.tf("tablet.source_limit", [int(n["capacity"])]))
				if _known(r, "load_pu"):
					(v["lines"] as Array).append(UiText.tf("tablet.source_load", [int(r["load_pu"]["value"]), int(n["capacity"])]))
			_:
				_junction(v, r, (known.get("findings", {}) as Dictionary).get(panel, []), supply_state)
		_source_line(v, nid, nodes_state, edges_state, content["tablet"])
		_worker_and_access(v, panel, content.get("repairs", {}), known)
		out_nodes[nid] = v
	var out_edges: Array[Dictionary] = []
	var edge_ids: Array = edges_state.keys()
	edge_ids.sort()
	for eid: String in edge_ids:
		var e: Dictionary = edges_state[eid]
		var style: String = EDGE_UNKNOWN
		if e["energized"]:
			style = EDGE_GRID if root_source(e["from"], nodes_state, edges_state) == grid_source else EDGE_TEMP
		elif _feed_measured_open(eid, e, panels, known):
			style = EDGE_FAULT
		out_edges.append({"id": eid, "from": e["from"], "to": e["to"], "style": style})
	return {"nodes": out_nodes, "edges": out_edges, "order": order}


## The online source feeding a node through energized edges, or "" when the node is dark.
static func root_source(nid: String, nodes: Dictionary, edges: Dictionary) -> String:
	var at: String = nid
	for _i: int in nodes.size():
		var n: Dictionary = nodes[at]
		if n["kind"] == PowerGrid.KIND_SOURCE:
			return at if n["online"] else ""
		if not (n.get("energized", false) or n.get("supplied", false)):  # junctions are energized, consumers supplied
			return ""
		var up: String = ""
		for eid: String in edges:
			if edges[eid]["to"] == at and edges[eid]["energized"]:
				up = edges[eid]["from"]
		if up == "":
			return ""
		at = up
	return ""


## True when the node has a fault or overload the player has measured (ping type FAULT instead of LOOK).
static func shows_fault(v: Dictionary) -> bool:
	return v["status_group"] == "findings" or (v["status_group"] == "other" and v["status_state"] == "breaker_tripped")


static func _junction(v: Dictionary, r: Dictionary, findings: Array, supply_state: String) -> void:
	var panel_info: Dictionary = r.get("_panel", {})
	var current: bool = panel_info.has("tick")
	v["needs_reinspect"] = bool(panel_info.get("needs_reinspect", false))
	v["measured"] = current
	if not current:
		_status(v, "other", "unknown")
		(v["lines"] as Array).append(UiText.t("tablet.reinspect" if v["needs_reinspect"] else "tablet.unknown_measure"))
		return
	var typed: Array[Dictionary] = []
	typed.assign(findings)
	v["findings"] = typed
	if not typed.is_empty():
		_status(v, "findings", str(typed[0]["code"]))
	else:
		_status(v, "supply", supply_state)
	if _known(r, "load_pu") and _known(r, "capacity_pu"):
		(v["lines"] as Array).append(UiText.tf("tablet.measured", [int(r["load_pu"]["value"]), int(r["capacity_pu"]["value"])]))
	else:
		(v["lines"] as Array).append(UiText.t("tablet.unknown_measure"))


## Source section: the feeding edge's authored capacity (printed on the cabinet), from the energized feed or the first one.
static func _source_line(v: Dictionary, nid: String, nodes: Dictionary, edges: Dictionary, tablet: Dictionary) -> void:
	if nodes[nid]["kind"] == PowerGrid.KIND_SOURCE:
		return
	var feed: String = ""
	var ids: Array = edges.keys()
	ids.sort()
	for eid: String in ids:
		if edges[eid]["to"] == nid and (feed == "" or edges[eid]["energized"]):
			feed = eid
	if feed == "":
		return
	var from: String = edges[feed]["from"]
	var name_key: String = from
	for cell: Dictionary in tablet["nodes"]:
		if cell["id"] == from:
			name_key = cell["name_key"]
	v["source_text"] = UiText.tf("tablet.branch_limit", [UiText.t(name_key), int(edges[feed]["capacity"])])


static func _worker_and_access(v: Dictionary, panel: String, repairs_def: Dictionary, known: Dictionary) -> void:
	if panel == "":
		return
	var repairs: Dictionary = (known.get("repairs", {}) as Dictionary).get("repairs", {})
	var access: Array = (known.get("repairs", {}) as Dictionary).get("access", [])
	var names: Dictionary = known.get("names", {})
	for r: Dictionary in repairs_def.get("repairs", []):
		if r["panel"] != panel:
			continue
		var owner: String = str((repairs.get(r["id"], {}) as Dictionary).get("lock_owner", ""))
		if owner != "":
			v["worker_text"] = UiText.tf("tablet.worker", [names.get(owner, owner), UiText.t(str(r["name_key"]))])
		if r.has("access") and not access.has(r["access"]):
			v["access_key"] = "access." + str(r["access"]).to_lower()


static func _feed_measured_open(eid: String, e: Dictionary, panels: Dictionary, known: Dictionary) -> bool:
	var panel: String = panels.get(e["to"], "")
	var r: Dictionary = (known.get("readings", {}) as Dictionary).get(panel, {})
	return _known(r, "feed_" + eid) and r["feed_" + eid]["value"] == "open"


static func _known(r: Dictionary, field: String) -> bool:
	return r.has(field) and (r[field] as Dictionary).get("known", false)


static func _status(v: Dictionary, group: String, state: String) -> void:
	v["status_group"] = group
	v["status_state"] = state
