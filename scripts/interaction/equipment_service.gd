extends RefCounted
## Host-side portable equipment (G05; blueprint p.7-8): generator carry, anchored placement, cable route toggles,
## start/stop, breaker reset, stowing and the always-available recovery action.
##
## Invariant: a generator that is not placed at an anchor is stopped and has no connected routes. Every intent
## is validated first and then applied completely, or refused with one reason and no change. Grid changes go
## through power_grid.gd, so an unsafe source tie (two energized routes into one consumer) is refused by the grid
## before any mutation and reported here as GRID_REFUSED with the grid's code and the conflicting IDs.
##
## Cables are authored curves between sockets; this service only knows which route edges are connected.
## Pure: no scene tree, no autoloads. Sender identity and range verdicts come from the host.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")

const SCHEMA: int = 1
const RETURN_DISCONNECT: String = "carrier_disconnected"

var revision: int = 0
var _grid: PowerGrid
var _meter: MeterModel
var _items: Dictionary = {}  # id -> {"id", "source", "breaker", "anchor": String ("" while carried), "carrier", "last_anchor"}
var _anchors: Dictionary = {}  # id -> {"id", "storage": bool, "routes": Array}
var _recovery_anchor: String = ""


## definition: content/contracts/<c>/equipment.json. Returns diagnostics; empty means loaded.
func load_definition(definition: Dictionary, grid: PowerGrid, meter: MeterModel) -> Array[Dictionary]:
	_grid = grid
	_meter = meter
	_items = {}
	_anchors = {}
	revision = 0
	var st: Dictionary = grid.canonical_state()
	var errs: Array[Dictionary] = []
	for rec: Variant in definition.get("anchors", []):
		var a: Dictionary = rec if rec is Dictionary else {}
		var aid: Variant = a.get("id")
		if not PowerGrid.is_valid_id(aid) or _anchors.has(aid):
			errs.append(PowerGrid.diag("INVALID_ID", "anchor id %s is invalid or duplicate" % str(aid), []))
			continue
		var routes: Array[String] = []
		for r: Variant in a.get("routes", []):
			if not (r is String and st["edges"].has(r)):
				errs.append(PowerGrid.diag("BAD_ROUTE", "%s: route %s is not a grid edge" % [aid, str(r)], [aid]))
			else:
				routes.append(r)
		_anchors[aid] = {"id": aid, "storage": a.get("storage") == true, "routes": routes}
	for rec: Variant in definition.get("equipment", []):
		var e: Dictionary = rec if rec is Dictionary else {}
		var eid: Variant = e.get("id")
		var src: Variant = e.get("source")
		var brk: Variant = e.get("breaker")
		var start: Variant = e.get("start_anchor")
		if not PowerGrid.is_valid_id(eid) or _items.has(eid):
			errs.append(PowerGrid.diag("INVALID_ID", "equipment id %s is invalid or duplicate" % str(eid), []))
		elif not (src is String and st["nodes"].has(src) and st["nodes"][src]["kind"] == PowerGrid.KIND_SOURCE):
			errs.append(PowerGrid.diag("BAD_EQUIPMENT", "%s: source must be a grid source" % eid, [eid]))
		elif not (brk is String and st["nodes"].has(brk) and st["nodes"][brk]["kind"] == PowerGrid.KIND_JUNCTION):
			errs.append(PowerGrid.diag("BAD_EQUIPMENT", "%s: breaker must be a grid junction" % eid, [eid]))
		elif not (start is String and _anchors.has(start) and _anchors[start]["storage"]):
			errs.append(PowerGrid.diag("BAD_EQUIPMENT", "%s: start_anchor must be a storage anchor" % eid, [eid]))
		elif st["nodes"][src]["online"]:
			errs.append(PowerGrid.diag("BAD_EQUIPMENT", "%s: portable source must start offline" % eid, [eid, src]))
		else:
			_items[eid] = {"id": eid, "source": src, "breaker": brk, "anchor": start, "carrier": "", "last_anchor": start}
	var rec_anchor: Variant = definition.get("recovery_anchor")
	if not (rec_anchor is String and _anchors.has(rec_anchor) and _anchors[rec_anchor]["storage"]):
		errs.append(PowerGrid.diag("BAD_EQUIPMENT", "recovery_anchor must be a storage anchor", []))
	else:
		_recovery_anchor = rec_anchor
	for aid: String in _anchors:
		for r: String in _anchors[aid]["routes"]:
			if st["edges"][r]["enabled"]:
				errs.append(PowerGrid.diag("BAD_ROUTE", "%s: route %s must start disconnected" % [aid, r], [aid, r]))
	if not errs.is_empty():
		_items = {}
		_anchors = {}
	return errs


## sender: transport identity. intent: {"type": pickup|place|connect|disconnect|start|stop|reset_breaker|recover,
## "item", "anchor", "route", "in_range": host range verdict}. Reply {"ok", "revision"} or a refusal.
func handle(sender: String, intent: Dictionary) -> Dictionary:
	var iid: Variant = intent.get("item")
	if not (iid is String and _items.has(iid)):
		return _refuse("UNKNOWN_ITEM", "no equipment %s" % str(iid), [])
	var it: Dictionary = _items[iid]
	var kind: Variant = intent.get("type")
	if kind == "recover":
		return _recover(it)  # the van-menu recovery action works from anywhere
	if intent.get("in_range") != true:
		return _refuse("NOT_IN_RANGE", "move closer to %s" % iid, [iid])
	match kind:
		"pickup":
			return _pickup(sender, it)
		"place":
			return _place(sender, it, intent.get("anchor"))
		"connect", "disconnect":
			return _route(it, intent.get("route"), kind == "connect")
		"start", "stop":
			if it["anchor"] == "" or (kind == "start" and _anchors[it["anchor"]]["storage"]):
				return _refuse("PLACE_FIRST", "place %s at a work pad first" % iid, [iid])
			return _grid_then({"op": "set", "id": it["source"], "field": "online", "value": kind == "start"}, iid)
		"reset_breaker":
			if not _node(it["breaker"])["tripped"]:
				return _refuse("NOT_TRIPPED", "%s breaker is not tripped" % iid, [iid, it["breaker"]])
			return _grid_then({"op": "set", "id": it["breaker"], "field": "tripped", "value": false}, iid)
	return _refuse("UNKNOWN_INTENT", "unknown intent %s" % str(kind), [])


func _pickup(sender: String, it: Dictionary) -> Dictionary:
	if it["carrier"] != "":
		return _refuse("CARRIED_BY_OTHER", "%s is carried by %s" % [it["id"], it["carrier"]], [it["id"], it["carrier"]])
	if _node(it["source"])["online"]:
		return _refuse("STOP_FIRST", "stop %s before moving it" % it["id"], [it["id"]])
	var connected: Array[String] = _connected_routes(it)
	if not connected.is_empty():
		var ids: Array = [it["id"]]
		ids.append_array(connected)
		return _refuse("DISCONNECT_FIRST", "disconnect the cables from %s first" % it["id"], ids)
	it["last_anchor"] = it["anchor"]
	it["anchor"] = ""
	it["carrier"] = sender
	revision += 1
	return _ok({})


func _place(sender: String, it: Dictionary, anchor: Variant) -> Dictionary:
	if it["carrier"] != sender:
		return _refuse("NOT_CARRIER", "pick up %s first" % it["id"], [it["id"]])
	if not (anchor is String and _anchors.has(anchor)):
		return _refuse("UNKNOWN_ANCHOR", "no anchor %s" % str(anchor), [it["id"]])
	for other: String in _items:
		if _items[other]["anchor"] == anchor and not _anchors[anchor]["storage"]:
			return _refuse("ANCHOR_OCCUPIED", "%s is occupied" % anchor, [anchor, other])
	it["anchor"] = anchor
	it["last_anchor"] = anchor
	it["carrier"] = ""
	revision += 1
	return _ok({})


func _route(it: Dictionary, route: Variant, enable: bool) -> Dictionary:
	if it["anchor"] == "":
		return _refuse("PLACE_FIRST", "place %s first" % it["id"], [it["id"]])
	if not (route is String and (_anchors[it["anchor"]]["routes"] as Array).has(route)):
		return _refuse("NO_SOCKET", "%s has no socket for %s here" % [it["id"], str(route)], [it["id"]])
	return _grid_then({"op": "set", "id": route, "field": "enabled", "value": enable}, it["id"])


## Always available (blueprint p.7): stop, disconnect every route, return to the van. Never touches repairs.
func _recover(it: Dictionary) -> Dictionary:
	for cmd: Dictionary in _recovery_commands(it):
		var res: Dictionary = _grid.apply(cmd)
		# stopping a source or opening a route removes supply, so it cannot create dual supply or a cycle
		assert(res["ok"], "recovery command refused: %s" % str(res))
	_meter.observe(_grid)
	it["anchor"] = _recovery_anchor
	it["last_anchor"] = _recovery_anchor
	it["carrier"] = ""
	revision += 1
	return _ok({"anchor": _recovery_anchor})


func _recovery_commands(it: Dictionary) -> Array[Dictionary]:
	var cmds: Array[Dictionary] = []
	if _node(it["source"])["online"]:
		cmds.append({"op": "set", "id": it["source"], "field": "online", "value": false})
	for r: String in _connected_routes(it):
		cmds.append({"op": "set", "id": r, "field": "enabled", "value": false})
	return cmds


## The carrier dropped out: the item returns to the last valid anchor it stood on (NET05 logic).
func disconnect_player(player: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for iid: String in _sorted(_items.keys()):
		var it: Dictionary = _items[iid]
		if it["carrier"] == player:
			it["carrier"] = ""
			it["anchor"] = it["last_anchor"]
			revision += 1
			events.append({"type": "item_returned", "item": iid, "anchor": it["anchor"], "reason": RETURN_DISCONNECT})
	return events


# ---------- state ----------

func anchor_of(iid: String) -> String:
	return _items[iid]["anchor"]


func carrier_of(iid: String) -> String:
	return _items[iid]["carrier"]


## Every portable item is at a storage anchor (C01 extraction precondition "equipment stowed").
func all_stowed() -> bool:
	for iid: String in _items:
		var a: String = _items[iid]["anchor"]
		if a == "" or not _anchors[a]["storage"]:
			return false
	return true


func canonical_state() -> Dictionary:
	var items: Dictionary = {}
	for iid: String in _items:
		var it: Dictionary = _items[iid]
		items[iid] = {"anchor": it["anchor"], "carrier": it["carrier"], "last_anchor": it["last_anchor"]}
	return {"schema": SCHEMA, "revision": revision, "items": items}


# ---------- helpers ----------

func _connected_routes(it: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if it["anchor"] == "":
		return out
	var edges: Dictionary = _grid.canonical_state()["edges"]
	for r: String in _anchors[it["anchor"]]["routes"]:
		if edges[r]["enabled"]:
			out.append(r)
	return out


func _node(nid: String) -> Dictionary:
	return _grid.canonical_state()["nodes"][nid]


func _grid_then(cmd: Dictionary, iid: String) -> Dictionary:
	var res: Dictionary = _grid.apply(cmd)
	if not res["ok"]:
		var ids: Array = (res["ids"] as Array).duplicate()
		ids.append(iid)
		var refusal: Dictionary = _refuse("GRID_REFUSED", res["message"], ids)
		refusal["grid_code"] = res["code"]
		return refusal
	_meter.observe(_grid)
	revision += 1
	return _ok({})


func _ok(extra: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": true, "revision": revision}
	out.merge(extra)
	return out


func _refuse(code: String, message: String, ids: Array) -> Dictionary:
	var d: Dictionary = PowerGrid.diag(code, message, ids)
	return {"ok": false, "code": code, "key": "equipment.refused." + code.to_lower(), "message": message,
		"ids": d["ids"], "revision": revision}


static func _sorted(keys: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(keys)
	out.sort()
	return out
