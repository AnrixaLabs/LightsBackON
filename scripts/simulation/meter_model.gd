extends RefCounted
## Meter and evidence model (G03; blueprint p.8, pillar 1).
##
## The meter shows source presence, continuity, branch demand, capacity and breaker reason for a panel.
## Every reading is unknown ("?") until the panel is inspected, and an unknown is never reported as 0.
## inspect() takes a measured snapshot. A snapshot stays valid only while every measured quantity on that
## panel is unchanged; if any of them changes, the whole panel reverts to unknown and asks for a re-inspect.
## Reverting the whole panel, not the one changed field, keeps a boolean from leaking its new value.
##
## Findings are observations derived from known readings (e.g. COMPONENT_OPEN), never repair instructions:
## markers may point at a panel but must not reveal the exact repair.
##
## Pure like power_grid.gd: reads the grid only through canonical_state(), no scene tree, no autoloads.
## The host owns one instance per mission; readings are crew-shared.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const SCHEMA: int = 1
const UNKNOWN_TEXT: String = "?"
const REASON_FAULT: String = "fault"
const REASON_OVERLOAD: String = "overload"
const INITIAL_REASONS: Array[String] = [REASON_FAULT]
const FEED_PREFIX: String = "feed_"
const VALUE_KEY_PREFIX: String = "meter.value."
const JUNCTION_FIELDS: Array[String] = [
	"source_present", "component", "isolator", "breaker", "breaker_reason", "load_pu", "capacity_pu", "demand_pu",
	"trip_load_pu", "trip_capacity_pu",
]
const SOURCE_FIELDS: Array[String] = ["online", "load_pu", "capacity_pu"]
## Every finding code findings() can emit; the status icon list (content/ui/status_states.json) must cover each.
const FINDING_CODES: Array[String] = [
	"NO_SOURCE", "FEED_OPEN", "FEED_SWITCHED_OFF", "COMPONENT_OPEN", "ISOLATED", "TRIPPED_FAULT", "TRIPPED_OVERLOAD",
	"TRIPPED_UNKNOWN", "DEMAND_OVER_CAPACITY", "SOURCE_OFFLINE", "SOURCE_OVERLOADED",
]

var _panels: Dictionary = {}  # panel id -> {"id", "target"}
var _trip_reasons: Dictionary = {}  # junction id -> {"reason", and for overload: "element", "flow", "capacity", "tick"}
var _snapshots: Dictionary = {}  # panel id -> {"tick": int, "values": Dictionary}


## definition: content meter.json. Returns diagnostics; empty means loaded.
func load_definition(definition: Dictionary, grid: PowerGrid) -> Array[Dictionary]:
	_panels = {}
	_trip_reasons = {}
	_snapshots = {}
	var nodes: Dictionary = grid.canonical_state()["nodes"]
	var errs: Array[Dictionary] = []
	for rec: Variant in definition.get("panels", []):
		var r: Dictionary = rec if rec is Dictionary else {}
		var pid: Variant = r.get("id")
		var target: Variant = r.get("target")
		if not PowerGrid.is_valid_id(pid):
			errs.append(PowerGrid.diag("INVALID_ID", "panel id %s must match ^[A-Z0-9_]+$" % str(pid), []))
		elif _panels.has(pid) or nodes.has(pid):
			errs.append(PowerGrid.diag("DUPLICATE_ID", "duplicate id %s" % pid, [pid]))
		elif not (target is String and nodes.has(target)):
			errs.append(PowerGrid.diag("UNKNOWN_TARGET", "%s: target %s is not a grid node" % [pid, str(target)], [pid]))
		elif not [PowerGrid.KIND_SOURCE, PowerGrid.KIND_JUNCTION].has(nodes[target]["kind"]):
			errs.append(PowerGrid.diag("BAD_TARGET_KIND", "%s: panels attach to sources or junctions" % pid, [pid, target]))
		else:
			_panels[pid] = {"id": pid, "target": target}
	var reasons: Dictionary = definition.get("initial_breaker_reasons", {})
	for jid: Variant in reasons:
		var reason: Variant = reasons[jid]
		if not (jid is String and nodes.has(jid) and nodes[jid]["kind"] == PowerGrid.KIND_JUNCTION and nodes[jid]["tripped"]):
			errs.append(PowerGrid.diag("BAD_REASON", "%s: initial breaker reason needs a junction that starts tripped" % str(jid), []))
		elif not (reason is String and INITIAL_REASONS.has(reason)):
			errs.append(PowerGrid.diag("BAD_REASON", "%s: reason must be one of %s" % [jid, str(INITIAL_REASONS)], [jid]))
		else:
			_trip_reasons[jid] = {"reason": reason}
	if not errs.is_empty():
		_panels = {}
		_trip_reasons = {}
	return errs


func has_panel(panel_id: String) -> bool:
	return _panels.has(panel_id)


## Feed the grid's step() events here every tick so trip reasons are known (blueprint step 8 events).
func record_events(events: Array[Dictionary], grid: PowerGrid) -> void:
	observe(grid)
	for ev: Dictionary in events:
		if ev.get("type") == "trip":
			_trip_reasons[ev["breaker"]] = {"reason": REASON_OVERLOAD, "element": ev["element"], "flow": ev["flow"],
				"capacity": ev["capacity"], "tick": ev["tick"]}


## Call after every applied grid command: a breaker that is no longer tripped forgets why it tripped.
func observe(grid: PowerGrid) -> void:
	var nodes: Dictionary = grid.canonical_state()["nodes"]
	for jid: String in _trip_reasons.keys():
		if not nodes[jid]["tripped"]:
			_trip_reasons.erase(jid)


## The inspect command: take a measured snapshot of one panel. {"ok": true} or a refusal with code/message/ids.
func inspect(panel_id: String, grid: PowerGrid) -> Dictionary:
	if not _panels.has(panel_id):
		return {"ok": false, "code": "UNKNOWN_PANEL", "message": "no meter panel %s" % panel_id, "ids": []}
	observe(grid)
	_snapshots[panel_id] = {"tick": grid.tick, "values": _measure(panel_id, grid.canonical_state())}
	return {"ok": true}


## Readings for display: field -> {"known": bool, "display": String, "value": Variant only when known}.
## Also "_panel": {"inspected": bool, "needs_reinspect": bool, "tick": int (only when known)}.
func readings(panel_id: String, grid: PowerGrid) -> Dictionary:
	if not _panels.has(panel_id):
		return {"_panel": {"inspected": false, "needs_reinspect": false}}
	observe(grid)
	var state: Dictionary = grid.canonical_state()
	var live: Dictionary = _measure(panel_id, state)
	var snap: Dictionary = _snapshots.get(panel_id, {})
	var current: bool = not snap.is_empty() and PowerGrid.serialize(snap["values"]) == PowerGrid.serialize(live)
	var out: Dictionary = {}
	for field: String in _fields(panel_id, state):
		var values: Dictionary = snap.get("values", {})
		if current and values.has(field):
			out[field] = {"known": true, "value": values[field], "display": display_text(values[field])}
		else:
			out[field] = {"known": false, "display": UNKNOWN_TEXT}
	var panel: Dictionary = {"inspected": not snap.is_empty(), "needs_reinspect": not snap.is_empty() and not current}
	if current:
		panel["tick"] = snap["tick"]
	out["_panel"] = panel
	return out


## Evidence for the selected panel: observations derived from known readings only. Empty when unknown.
## Each finding: {"code", "key": localization key, "ids"}.
func findings(panel_id: String, grid: PowerGrid) -> Array[Dictionary]:
	var r: Dictionary = readings(panel_id, grid)
	var out: Array[Dictionary] = []
	if not r["_panel"].has("tick"):
		return out
	var target: String = _panels[panel_id]["target"]
	if r.has("online"):
		if not _value(r, "online"):
			out.append(_finding("SOURCE_OFFLINE", [target]))
		if _value(r, "load_pu") > _value(r, "capacity_pu"):
			out.append(_finding("SOURCE_OVERLOADED", [target]))
		return out
	if not _value(r, "source_present"):
		out.append(_finding("NO_SOURCE", [target]))
	for field: String in _sorted(r.keys()):
		if field.begins_with(FEED_PREFIX):
			var edge: String = field.trim_prefix(FEED_PREFIX)
			if _value(r, field) == "open":
				out.append(_finding("FEED_OPEN", [edge]))
			elif _value(r, field) == "switched_off":
				out.append(_finding("FEED_SWITCHED_OFF", [edge]))
	if _value(r, "component") == "open":
		out.append(_finding("COMPONENT_OPEN", [target]))
	if _value(r, "isolator") == "open":
		out.append(_finding("ISOLATED", [target]))
	if _value(r, "breaker") == "tripped":
		var reason: Variant = r["breaker_reason"].get("value")
		if reason == REASON_OVERLOAD:
			out.append(_finding("TRIPPED_OVERLOAD", [target, _trip_reasons[target]["element"]]))
		elif reason == REASON_FAULT:
			out.append(_finding("TRIPPED_FAULT", [target]))
		else:
			out.append(_finding("TRIPPED_UNKNOWN", [target]))
	if r["demand_pu"]["known"] and r["capacity_pu"]["known"] and _value(r, "demand_pu") > _value(r, "capacity_pu"):
		out.append(_finding("DEMAND_OVER_CAPACITY", [target]))
	return out


## Display token for a known value: a decimal PU number, or a localization key for states ("meter.value.tripped").
## Unknown values never reach here; readings() gives them UNKNOWN_TEXT. Units and wording are UI work.
static func display_text(value: Variant) -> String:
	if value is bool:
		return VALUE_KEY_PREFIX + ("yes" if value else "no")
	if value is int:
		return str(value)
	return VALUE_KEY_PREFIX + str(value)


func canonical_state() -> Dictionary:
	return {"schema": SCHEMA, "snapshots": _snapshots.duplicate(true), "trip_reasons": _trip_reasons.duplicate(true)}


# ---------- measurement ----------

## Live values of every measurable field on a panel. Fields with no meaning right now (breaker_reason of a
## closed breaker, trip loads without an overload trip) are omitted and read as unknown.
func _measure(panel_id: String, state: Dictionary) -> Dictionary:
	var target: String = _panels[panel_id]["target"]
	var nodes: Dictionary = state["nodes"]
	var edges: Dictionary = state["edges"]
	var n: Dictionary = nodes[target]
	if n["kind"] == PowerGrid.KIND_SOURCE:
		return {"online": n["online"], "load_pu": n["load"], "capacity_pu": n["capacity"]}
	var v: Dictionary = {
		"source_present": n["energized"],
		"component": "open" if n["failed"] else "intact",
		"isolator": "open" if n["isolated"] else "closed",
		"breaker": "tripped" if n["tripped"] else "closed",
		"demand_pu": _connected_demand(target, nodes, edges),
	}
	var feeds: Array[String] = _incoming(target, edges)
	var feed: String = ""
	for eid: String in feeds:
		var e: Dictionary = edges[eid]
		v[FEED_PREFIX + eid] = "open" if not e["healthy"] else ("switched_off" if not e["enabled"] else "closed")
		if e["energized"] and feed == "":
			feed = eid
	if feed == "" and not feeds.is_empty():
		feed = feeds[0]
	if feed != "":
		v["load_pu"] = edges[feed]["flow"]
		v["capacity_pu"] = edges[feed]["capacity"]
	if n["tripped"] and _trip_reasons.has(target):
		var rec: Dictionary = _trip_reasons[target]
		v["breaker_reason"] = rec["reason"]
		if rec["reason"] == REASON_OVERLOAD:
			v["trip_load_pu"] = rec["flow"]
			v["trip_capacity_pu"] = rec["capacity"]
	return v


## Demand the branch would draw: enabled healthy consumers below the junction through active edges and
## unblocked downstream junctions, ignoring this junction's own isolator/breaker/component.
func _connected_demand(jid: String, nodes: Dictionary, edges: Dictionary) -> int:
	var total: int = 0
	for eid: String in _sorted(edges.keys()):
		var e: Dictionary = edges[eid]
		if e["from"] != jid or not (e["enabled"] and e["healthy"]):
			continue
		var to: Dictionary = nodes[e["to"]]
		if to["kind"] == PowerGrid.KIND_CONSUMER:
			if to["enabled"] and to["healthy"]:
				total += int(to["demand"])
		elif to["kind"] == PowerGrid.KIND_JUNCTION and not (to["isolated"] or to["failed"] or to["tripped"]):
			total += _connected_demand(e["to"], nodes, edges)
	return total


func _fields(panel_id: String, state: Dictionary) -> Array[String]:
	var target: String = _panels.get(panel_id, {}).get("target", "")
	if target == "":
		return []
	if state["nodes"][target]["kind"] == PowerGrid.KIND_SOURCE:
		return SOURCE_FIELDS.duplicate()
	var out: Array[String] = JUNCTION_FIELDS.duplicate()
	for eid: String in _incoming(target, state["edges"]):
		out.append(FEED_PREFIX + eid)
	return out


static func _incoming(nid: String, edges: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for eid: String in _sorted(edges.keys()):
		if edges[eid]["to"] == nid:
			out.append(eid)
	return out


static func _value(r: Dictionary, field: String) -> Variant:
	return (r[field] as Dictionary).get("value")


static func _finding(code: String, ids: Array) -> Dictionary:
	var d: Dictionary = PowerGrid.diag(code, "", ids)
	return {"code": code, "key": "meter.finding." + code.to_lower(), "ids": d["ids"]}


static func _sorted(keys: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(keys)
	out.sort()
	return out
