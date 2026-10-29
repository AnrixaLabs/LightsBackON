extends RefCounted
## Pure grid evaluation (blueprint section 5 steps 1-8, ADR-003).
##
## No scene tree, no autoloads, no Steam: only value types, so it runs headless in unit tests and is
## compared byte for byte with reference/lbo_grid.py by tools/cross_check_reference.py. Keep the two in
## step: a rule change here is a rule change there.
##
## The grid never holds an invalid topology. load_definition() rejects a bad definition, and every
## command goes through apply(), which validates a trial state and restores the old one on refusal
## ("refused before any state change").
##
## Records are plain Dictionaries mirroring the content JSON so the port reads like the reference.
## All PU are int. IDs match ^[A-Z0-9_]+$ and every traversal runs in ascending ID order (SIM11).
##
## Time is integer ticks: the host calls step() at the grid rate (10 Hz). Each protection watches one edge and
## trips the junction breaker that edge feeds once the edge has been overloaded for trip_ticks consecutive ticks.

const SCHEMA: int = 2
const KIND_SOURCE: String = "source"
const KIND_JUNCTION: String = "junction"
const KIND_CONSUMER: String = "consumer"
const KIND_EDGE: String = "edge"
const KINDS: Array[String] = [KIND_SOURCE, KIND_JUNCTION, KIND_CONSUMER]
# JSON numbers arrive as float in Godot; an integral float within this range is an int (ADR-003).
const MAX_SAFE_INT: float = 9007199254740991.0

const NODE_FIELDS: Dictionary = {
	KIND_SOURCE: {"capacity": TYPE_INT, "online": TYPE_BOOL},
	KIND_JUNCTION: {"isolated": TYPE_BOOL, "failed": TYPE_BOOL, "tripped": TYPE_BOOL},
	KIND_CONSUMER: {"demand": TYPE_INT, "enabled": TYPE_BOOL, "healthy": TYPE_BOOL},
}
const NODE_DEFAULTS: Dictionary = {
	KIND_SOURCE: {"online": false},
	KIND_JUNCTION: {"isolated": false, "failed": false, "tripped": false},
	KIND_CONSUMER: {"enabled": true, "healthy": true},
}
const EDGE_FIELDS: Dictionary = {"from": TYPE_STRING, "to": TYPE_STRING, "capacity": TYPE_INT, "enabled": TYPE_BOOL, "healthy": TYPE_BOOL}
const EDGE_DEFAULTS: Dictionary = {"enabled": true, "healthy": true}
const PROTECTION_FIELDS: Dictionary = {"element": TYPE_STRING, "breaker": TYPE_STRING}
# Fields a command may change at runtime; capacities, demands and endpoints are authored content.
const SETTABLE: Dictionary = {
	KIND_SOURCE: ["online"],
	KIND_JUNCTION: ["isolated", "failed", "tripped"],
	KIND_CONSUMER: ["enabled", "healthy"],
	KIND_EDGE: ["enabled", "healthy"],
}

var tick: int = 0
var _nodes: Dictionary = {}  # id -> record (includes "kind")
var _edges: Dictionary = {}  # id -> record
var _protections: Dictionary = {}  # id -> {"id", "element": edge id, "breaker": junction id}
var _overload_ticks: Dictionary = {}  # protection id -> consecutive overloaded ticks
var _trip_ticks: int = 0
# evaluation result (steps 3-4); rebuilt by evaluate()
var _energized: Dictionary = {}  # node id -> true
var _live: Dictionary = {}  # edge id -> true (active edge leaving a node that passes supply)
var _supplied: Dictionary = {}  # consumer id -> true
var _flow: Dictionary = {}  # edge id -> int PU
var _load: Dictionary = {}  # source id -> int PU


# ---------- loading / validation ----------

## Loads a definition ({"nodes": [...], "edges": [...]}). Returns diagnostics; empty means loaded and evaluated.
## On any diagnostic the grid stays empty.
func load_definition(definition: Dictionary) -> Array[Dictionary]:
	_clear()
	var errs: Array[Dictionary] = []
	for rec: Variant in definition.get("nodes", []):
		var kind: Variant = (rec as Dictionary).get("kind") if rec is Dictionary else null
		if not (kind is String and KINDS.has(kind)):
			var rid: Variant = (rec as Dictionary).get("id") if rec is Dictionary else rec
			errs.append(diag("BAD_KIND", "node %s: kind must be one of %s" % [str(rid), str(KINDS)], []))
			continue
		var checked: Array = _check_record(rec, NODE_FIELDS[kind], NODE_DEFAULTS[kind], "node")
		errs.append_array(checked[1])
		if checked[0] == null:
			continue
		var n: Dictionary = checked[0]
		var nid: String = n["id"]
		if _nodes.has(nid):
			errs.append(diag("DUPLICATE_ID", "duplicate node id %s" % nid, [nid]))
			continue
		n["kind"] = kind
		_nodes[nid] = n
	for rec: Variant in definition.get("edges", []):
		var checked: Array = _check_record(rec, EDGE_FIELDS, EDGE_DEFAULTS, "edge")
		errs.append_array(checked[1])
		if checked[0] == null:
			continue
		var e: Dictionary = checked[0]
		var eid: String = e["id"]
		if _edges.has(eid) or _nodes.has(eid):
			errs.append(diag("DUPLICATE_ID", "duplicate id %s" % eid, [eid]))
			continue
		_edges[eid] = e
	for rec: Variant in definition.get("protections", []):
		var checked: Array = _check_record(rec, PROTECTION_FIELDS, {}, "protection")
		errs.append_array(checked[1])
		if checked[0] == null:
			continue
		var pr: Dictionary = checked[0]
		var pid: String = pr["id"]
		if _protections.has(pid) or _edges.has(pid) or _nodes.has(pid):
			errs.append(diag("DUPLICATE_ID", "duplicate id %s" % pid, [pid]))
			continue
		_protections[pid] = pr
		_overload_ticks[pid] = 0
	if not _protections.is_empty():
		var trip: Variant = to_int(definition.get("trip_ticks"))
		if trip == null or int(trip) < 1:
			errs.append(diag("BAD_VALUE", "trip_ticks must be an int >= 1 when protections exist", []))
		else:
			_trip_ticks = int(trip)
	if errs.is_empty():
		errs = validate()
	if not errs.is_empty():
		_clear()
		return errs
	evaluate()
	return errs


func _clear() -> void:
	tick = 0
	_nodes = {}
	_edges = {}
	_protections = {}
	_overload_ticks = {}
	_trip_ticks = 0


func validate() -> Array[Dictionary]:
	var errs: Array[Dictionary] = _validate_structure()
	if not errs.is_empty():
		return errs
	return _validate_energized()


func _validate_structure() -> Array[Dictionary]:
	var errs: Array[Dictionary] = []
	for eid: String in _sorted_keys(_edges):
		var e: Dictionary = _edges[eid]
		var a: String = e["from"]
		var b: String = e["to"]
		if not _nodes.has(a) or not _nodes.has(b):
			errs.append(diag("UNKNOWN_NODE", "%s: endpoint %s does not exist" % [eid, b if _nodes.has(a) else a], [eid]))
			continue
		if a == b:
			errs.append(diag("SELF_LOOP", "%s: connects %s to itself" % [eid, a], [eid, a]))
		if _kind(b) == KIND_SOURCE:
			var what: String = "source-to-source connection" if _kind(a) == KIND_SOURCE else "backfeed into a source"
			errs.append(diag("SOURCE_BACKFEED", "%s: %s (%s -> %s)" % [eid, what, a, b], [eid, a, b]))
		if _kind(a) == KIND_CONSUMER:
			errs.append(diag("CONSUMER_OUTPUT", "%s: consumer %s cannot supply other nodes" % [eid, a], [eid, a]))
	for pid: String in _sorted_keys(_protections):
		var pr: Dictionary = _protections[pid]
		var element: String = pr["element"]
		var breaker: String = pr["breaker"]
		if not _edges.has(element):
			errs.append(diag("PROTECTION_ELEMENT", "%s: protected edge %s does not exist" % [pid, element], [pid]))
		elif _edges[element]["to"] != breaker or not _nodes.has(breaker) or _kind(breaker) != KIND_JUNCTION:
			# tripping the junction the edge feeds is what removes the edge's load, so a trip always clears it
			errs.append(diag("PROTECTION_BREAKER", "%s: breaker %s must be the junction fed by %s" % [pid, breaker, element], [pid, element]))
	if not errs.is_empty():
		return errs
	var cycle: Array[String] = _find_cycle()
	if not cycle.is_empty():
		errs.append(diag("CYCLE", "supply paths form a loop: " + " -> ".join(cycle), cycle))
	return errs


## Directed cycle over all potential edges (enabled or not). Returns the node and edge IDs on the loop, or [].
func _find_cycle() -> Array[String]:
	var adjacency: Dictionary = _adjacency()
	var state: Dictionary = {}  # node id -> 1 on path, 2 done
	for nid: String in _sorted_keys(_nodes):
		if not state.has(nid):
			var stack: Array[String] = []
			var found: Array[String] = _cycle_visit(nid, adjacency, state, stack)
			if not found.is_empty():
				return found
	return []


func _cycle_visit(nid: String, adjacency: Dictionary, state: Dictionary, stack: Array[String]) -> Array[String]:
	state[nid] = 1
	stack.append(nid)  # alternating node, edge, node, ... along the DFS path
	for eid: String in adjacency[nid]:
		var to: String = _edges[eid]["to"]
		if state.get(to, 0) == 1:
			var loop: Array[String] = stack.slice(stack.find(to))
			loop.append(eid)
			return loop
		if not state.has(to):
			stack.append(eid)
			var found: Array[String] = _cycle_visit(to, adjacency, state, stack)
			if not found.is_empty():
				return found
			stack.pop_back()
	stack.pop_back()
	state[nid] = 2
	return []


func _validate_energized() -> Array[Dictionary]:
	var energized: Dictionary = {}
	var live: Dictionary = {}
	_energize(energized, live)
	var incoming: Dictionary = {}  # node id -> Array[String] of live edge ids
	for eid: String in _sorted_keys(live):
		var to: String = _edges[eid]["to"]
		if not incoming.has(to):
			incoming[to] = [] as Array[String]
		(incoming[to] as Array[String]).append(eid)
	var errs: Array[Dictionary] = []
	for nid: String in _sorted_keys(incoming):
		var routes: Array[String] = incoming[nid]
		if routes.size() > 1:
			var ids: Array[String] = [nid]
			ids.append_array(routes)
			errs.append(diag("DUAL_SUPPLY", "%s would receive supply from %s at once" % [nid, " and ".join(routes)], ids))
	return errs


# ---------- evaluation (steps 2-5) ----------

func evaluate() -> void:
	_energized = {}
	_live = {}
	_energize(_energized, _live)
	_supplied = {}
	for nid: String in _sorted_keys(_nodes):
		var n: Dictionary = _nodes[nid]
		if n["kind"] == KIND_CONSUMER and _energized.has(nid) and n["enabled"] and n["healthy"]:
			_supplied[nid] = true
	_flow = {}
	_load = {}
	var adjacency: Dictionary = _adjacency()
	for nid: String in _sorted_keys(_nodes):
		if _kind(nid) == KIND_SOURCE:
			_load[nid] = _downstream(nid, adjacency)


## Steps 2-3: drop disabled/broken edges and blocked junctions, traverse out from online sources in ID order.
func _energize(energized: Dictionary, live: Dictionary) -> void:
	var adjacency: Dictionary = _adjacency()
	var frontier: Array[String] = []
	for nid: String in _sorted_keys(_nodes):
		if _passes(nid, energized):
			frontier.append(nid)
	for nid: String in frontier:
		energized[nid] = true
	while not frontier.is_empty():
		var next: Array[String] = []
		for nid: String in frontier:
			if not _passes(nid, energized):
				continue
			for eid: String in adjacency[nid]:
				var e: Dictionary = _edges[eid]
				if not (e["enabled"] and e["healthy"]):
					continue
				live[eid] = true
				var to: String = e["to"]
				if not energized.has(to):
					energized[to] = true
					next.append(to)
		next.sort()
		frontier = next


## Step 4: downstream PU below a node, recording flow on each live edge. The energized graph is a tree
## (dual supply is refused), so each edge is visited once.
func _downstream(nid: String, adjacency: Dictionary) -> int:
	var n: Dictionary = _nodes[nid]
	if n["kind"] == KIND_CONSUMER:
		return int(n["demand"]) if _supplied.has(nid) else 0
	if not _passes(nid, _energized):
		return 0
	var total: int = 0
	for eid: String in adjacency[nid]:
		if _live.has(eid):
			var f: int = _downstream(_edges[eid]["to"], adjacency)
			_flow[eid] = f
			total += f
	return total


func _passes(nid: String, energized: Dictionary) -> bool:
	var n: Dictionary = _nodes[nid]
	if n["kind"] == KIND_SOURCE:
		return n["online"]
	if n["kind"] == KIND_JUNCTION:
		return energized.has(nid) and not (n["isolated"] or n["failed"] or n["tripped"])
	return false


# ---------- commands (refused before mutation) ----------

## Applies one command. Returns {"ok": true} or {"ok": false, "code", "message", "ids"}; a refusal leaves the
## grid exactly as it was. Commands: {"op": "set", "id", "field", "value": bool}, {"op": "add_edge", "edge": {...}},
## {"op": "remove_edge", "id"}.
func apply(cmd: Dictionary) -> Dictionary:
	var saved_nodes: Dictionary = _nodes.duplicate(true)
	var saved_edges: Dictionary = _edges.duplicate(true)
	var resets: String = _resetting_breaker(cmd)
	var err: Dictionary = _mutate(cmd)
	if err.is_empty():
		var errs: Array[Dictionary] = validate()
		if not errs.is_empty():
			err = errs[0]
	if err.is_empty():
		evaluate()
		if resets != "":
			err = _reset_refusal(resets)
	if not err.is_empty():
		_nodes = saved_nodes
		_edges = saved_edges
		evaluate()
		return {"ok": false, "code": err["code"], "message": err["message"], "ids": err["ids"]}
	return {"ok": true}


## Step 6 at one tick: count consecutive overloaded ticks per protection, trip breakers whose count reaches
## trip_ticks, then recompute (step 7). Returns the authoritative events of this tick (step 8), in protection ID order.
func step() -> Array[Dictionary]:
	tick += 1
	var events: Array[Dictionary] = []
	for pid: String in _sorted_keys(_protections):
		var element: String = _protections[pid]["element"]
		if _flow.get(element, 0) > int(_edges[element]["capacity"]):
			_overload_ticks[pid] = int(_overload_ticks[pid]) + 1
		else:
			_overload_ticks[pid] = 0  # healthy demand resets the timer (SIM09)
		if int(_overload_ticks[pid]) >= _trip_ticks:
			var breaker: String = _protections[pid]["breaker"]
			_nodes[breaker]["tripped"] = true
			_overload_ticks[pid] = 0
			# flow/capacity at the moment of the trip: after the recompute the edge carries 0, and the meter needs the cause
			events.append({"type": "trip", "tick": tick, "protection": pid, "element": element, "breaker": breaker,
				"flow": int(_flow[element]), "capacity": int(_edges[element]["capacity"])})
	if not events.is_empty():
		evaluate()
	return events


## A command that clears a tripped breaker is a reset; returns that junction's id, else "".
func _resetting_breaker(cmd: Dictionary) -> String:
	var tid: Variant = cmd.get("id")
	if cmd.get("op") is String and cmd.get("op") == "set" and cmd.get("field") is String and cmd.get("field") == "tripped" \
			and cmd.get("value") is bool and cmd.get("value") == false and tid is String and _nodes.has(tid) \
			and _kind(tid) == KIND_JUNCTION and _nodes[tid]["tripped"]:
		return tid
	return ""


## Step 7: a reset is accepted only if no edge protected by that breaker would be overloaded afterwards, so a
## refused reset never starts a trip cycle (SIM10). Call on the evaluated trial state.
func _reset_refusal(breaker: String) -> Dictionary:
	for pid: String in _sorted_keys(_protections):
		var element: String = _protections[pid]["element"]
		if _protections[pid]["breaker"] == breaker and _flow.get(element, 0) > int(_edges[element]["capacity"]):
			return diag("RESET_OVERLOADED", "%s cannot reset: %s would carry %d PU over its %d PU limit" % [
				breaker, element, int(_flow[element]), int(_edges[element]["capacity"])], [breaker, element])
	return {}


func _mutate(cmd: Dictionary) -> Dictionary:
	var op: Variant = cmd.get("op")
	if op is String and op == "set":
		var tid: Variant = cmd.get("id")
		var field: Variant = cmd.get("field")
		var value: Variant = cmd.get("value")
		var rec: Dictionary
		var kind: String
		if tid is String and _nodes.has(tid):
			rec = _nodes[tid]
			kind = rec["kind"]
		elif tid is String and _edges.has(tid):
			rec = _edges[tid]
			kind = KIND_EDGE
		else:
			return diag("UNKNOWN_ID", "no node or edge %s" % str(tid), [])
		if not (field is String and (SETTABLE[kind] as Array).has(field)):
			return diag("FIELD_NOT_SETTABLE", "%s: %s cannot be changed on a %s" % [tid, str(field), kind], [tid])
		if not value is bool:
			return diag("BAD_VALUE", "%s: %s must be bool" % [tid, field], [tid])
		rec[field] = value
		return {}
	if op is String and op == "add_edge":
		var checked: Array = _check_record(cmd.get("edge"), EDGE_FIELDS, EDGE_DEFAULTS, "edge")
		var errs: Array[Dictionary] = checked[1]
		if not errs.is_empty():
			return errs[0]
		var e: Dictionary = checked[0]
		var eid: String = e["id"]
		if _edges.has(eid) or _nodes.has(eid):
			return diag("DUPLICATE_ID", "duplicate id %s" % eid, [eid])
		_edges[eid] = e
		return {}
	if op is String and op == "remove_edge":
		var rid: Variant = cmd.get("id")
		if not (rid is String and _edges.has(rid)):
			return diag("UNKNOWN_ID", "no edge %s" % str(rid), [])
		_edges.erase(rid)
		return {}
	return diag("UNKNOWN_OP", "unknown command %s" % str(op), [])


# ---------- canonical state (ADR-003) ----------

func canonical_state() -> Dictionary:
	var nodes: Dictionary = {}
	for nid: String in _nodes:
		var n: Dictionary = _nodes[nid]
		var k: String = n["kind"]
		if k == KIND_SOURCE:
			var load_pu: int = _load[nid]
			nodes[nid] = {"kind": k, "capacity": n["capacity"], "online": n["online"], "load": load_pu,
				"overloaded": load_pu > int(n["capacity"])}
		elif k == KIND_JUNCTION:
			nodes[nid] = {"kind": k, "isolated": n["isolated"], "failed": n["failed"], "tripped": n["tripped"],
				"energized": _energized.has(nid)}
		else:
			nodes[nid] = {"kind": k, "demand": n["demand"], "enabled": n["enabled"], "healthy": n["healthy"],
				"supplied": _supplied.has(nid)}
	var edges: Dictionary = {}
	for eid: String in _edges:
		var e: Dictionary = _edges[eid]
		var f: int = _flow.get(eid, 0)
		edges[eid] = {"from": e["from"], "to": e["to"], "capacity": e["capacity"], "enabled": e["enabled"],
			"healthy": e["healthy"], "energized": _live.has(eid), "flow": f, "overloaded": f > int(e["capacity"])}
	var protections: Dictionary = {}
	for pid: String in _protections:
		protections[pid] = {"element": _protections[pid]["element"], "breaker": _protections[pid]["breaker"],
			"overload_ticks": _overload_ticks[pid]}
	return {"schema": SCHEMA, "tick": tick, "trip_ticks": _trip_ticks, "nodes": nodes, "edges": edges, "protections": protections}


func canonical_string() -> String:
	return serialize(canonical_state())


func canonical_hash() -> String:
	return canonical_string().sha256_text()


## Sorted IDs of every overloaded source and edge (strictly greater than capacity; equality is allowed, SIM08).
func overloads() -> Array[String]:
	var out: Array[String] = []
	var st: Dictionary = canonical_state()
	for group: String in ["nodes", "edges"]:
		var recs: Dictionary = st[group]
		for rid: String in recs:
			if (recs[rid] as Dictionary).get("overloaded", false):
				out.append(rid)
	out.sort()
	return out


## Hand-written canonical JSON (ADR-003): sorted keys, no whitespace, int/bool/printable-ASCII strings, arrays,
## objects. Anything else (float, null, non-ASCII) cannot be canonical and yields "" so callers fail loudly on compare.
static func serialize(v: Variant) -> String:
	match typeof(v):
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_STRING, TYPE_STRING_NAME:
			var s: String = str(v)
			for i: int in s.length():
				var c: int = s.unicode_at(i)
				if c < 0x20 or c > 0x7E:
					return ""
			return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\""
		TYPE_ARRAY:
			var parts: PackedStringArray = []
			for x: Variant in v:
				var p: String = serialize(x)
				if p == "":
					return ""
				parts.append(p)
			return "[" + ",".join(parts) + "]"
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys: Array = d.keys()
			for k: Variant in keys:
				if not (k is String):
					return ""
			keys.sort()
			var parts: PackedStringArray = []
			for k: String in keys:
				var p: String = serialize(d[k])
				if p == "":
					return ""
				parts.append(serialize(k) + ":" + p)
			return "{" + ",".join(parts) + "}"
	return ""


# ---------- helpers ----------

static func diag(code: String, message: String, ids: Array) -> Dictionary:
	var unique: Dictionary = {}
	for i: Variant in ids:
		unique[str(i)] = true
	var sorted_ids: Array[String] = []
	sorted_ids.assign(unique.keys())
	sorted_ids.sort()
	return {"code": code, "message": message, "ids": sorted_ids}


static func is_valid_id(v: Variant) -> bool:
	if not v is String or (v as String).is_empty():
		return false
	var s: String = v
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		var ok: bool = (c >= 0x41 and c <= 0x5A) or (c >= 0x30 and c <= 0x39) or c == 0x5F
		if not ok:
			return false
	return true


## Returns [record or null, Array[Dictionary] diagnostics]. Converts integral JSON floats to int.
static func _check_record(rec: Variant, fields: Dictionary, defaults: Dictionary, where: String) -> Array:
	var errs: Array[Dictionary] = []
	if not rec is Dictionary:
		errs.append(diag("BAD_RECORD", "%s is not an object" % where, []))
		return [null, errs]
	var r: Dictionary = rec
	var rid: Variant = r.get("id")
	if not is_valid_id(rid):
		errs.append(diag("INVALID_ID", "%s id %s must match ^[A-Z0-9_]+$" % [where, str(rid)], []))
		return [null, errs]
	var out: Dictionary = {"id": rid}
	for k: String in fields:
		var want: int = fields[k]
		var v: Variant = r.get(k, defaults.get(k))
		if v == null:
			errs.append(diag("MISSING_FIELD", "%s: missing %s" % [rid, k], [rid]))
		elif want == TYPE_INT:
			var as_int: Variant = to_int(v)
			if as_int == null:
				errs.append(diag("BAD_VALUE", "%s: %s must be int" % [rid, k], [rid]))
			elif int(as_int) < 0:
				errs.append(diag("BAD_VALUE", "%s: %s must be >= 0" % [rid, k], [rid]))
			else:
				out[k] = int(as_int)
		elif typeof(v) != want:
			errs.append(diag("BAD_VALUE", "%s: %s must be %s" % [rid, k, type_string(want)], [rid]))
		else:
			out[k] = v
	return [null if not errs.is_empty() else out, errs]


static func to_int(v: Variant) -> Variant:
	if v is int:
		return v
	if v is float:
		var f: float = v
		if is_finite(f) and f == floorf(f) and absf(f) <= MAX_SAFE_INT:
			return int(f)
	return null


func _kind(nid: String) -> String:
	return _nodes[nid]["kind"]


## node id -> Array[String] of outgoing edge ids, ascending.
func _adjacency() -> Dictionary:
	var adjacency: Dictionary = {}
	for nid: String in _nodes:
		adjacency[nid] = [] as Array[String]
	for eid: String in _sorted_keys(_edges):
		var from: String = _edges[eid]["from"]
		if adjacency.has(from):
			(adjacency[from] as Array[String]).append(eid)
	return adjacency


static func _sorted_keys(d: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	keys.assign(d.keys())
	keys.sort()
	return keys
