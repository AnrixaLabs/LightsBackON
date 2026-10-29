extends RefCounted
## Host-side repair interactions (G04; blueprint p.8, CLAUDE.md section 3 "Repair state machine").
##
## Owns repair locks, isolation preconditions, discrete repair transitions and supply consumption. Clients only
## send intentions; the host passes the sender identity it took from the transport (never from the payload) and
## its own range verdict. Every durable transition is atomic: it either happens completely (grid change, supply
## consumed, state advanced) or is refused with one specific reason and changes nothing. Cancelling just drops
## the lock, so the last durable state is kept.
##
## Pure like power_grid.gd: no scene tree, no autoloads. Time is the integer grid tick passed to tick().
## Sequence-number dedupe across the network is F03 (session_host.gd); here a repeated step is idempotent by state.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")

const SCHEMA: int = 1
const STATES: Array[String] = [
	"undiagnosed", "diagnosed", "isolated", "opened", "component_removed", "replacement_installed", "closed", "tested", "restored",
]
## STEPS[i] moves a repair from STATES[i] to STATES[i + 1].
const STEPS: Array[String] = ["diagnose", "isolate", "open", "remove", "install", "close", "test", "restore"]
## Steps that touch the opened panel; the panel must be isolated for each of them (live repair refused).
const NEEDS_ISOLATION: Array[String] = ["open", "remove", "install", "close", "test"]
const RELEASE_CANCEL: String = "cancel"
const RELEASE_OUT_OF_RANGE: String = "out_of_range"
const RELEASE_DISCONNECT: String = "disconnect"
const RELEASE_HEARTBEAT: String = "heartbeat_timeout"
const RELEASE_COMPLETED: String = "completed"

var revision: int = 0
var _grid: PowerGrid
var _meter: MeterModel
var _heartbeat_timeout_ticks: int = 0
var _max_hold_ticks: int = 0
var _now: int = 0
var _repairs: Dictionary = {}  # repair id -> content record
var _state: Dictionary = {}  # repair id -> index into STATES
var _locks: Dictionary = {}  # repair id -> {"owner": player id, "last_seen": tick}
var _supplies: Dictionary = {}  # item id -> int count (crew stock)
var _players: Dictionary = {}  # player id -> {"tools": Array[String], "equipped": String}
var _access: Dictionary = {}  # access flag -> true (set by the mission director)


## tuning: content/interaction.json; definition: content/contracts/<c>/repairs.json. Returns diagnostics.
func load_definition(tuning: Dictionary, definition: Dictionary, grid: PowerGrid, meter: MeterModel) -> Array[Dictionary]:
	_grid = grid
	_meter = meter
	_repairs = {}
	_state = {}
	_locks = {}
	_supplies = {}
	revision = 0
	var errs: Array[Dictionary] = []
	var timeout: Variant = PowerGrid.to_int(tuning.get("lock_heartbeat_timeout_ticks"))
	var max_hold: Variant = PowerGrid.to_int(tuning.get("max_hold_ticks"))
	if timeout == null or int(timeout) < 1 or max_hold == null or int(max_hold) < 1:
		errs.append(PowerGrid.diag("BAD_VALUE", "tuning needs lock_heartbeat_timeout_ticks and max_hold_ticks >= 1", []))
	else:
		_heartbeat_timeout_ticks = int(timeout)
		_max_hold_ticks = int(max_hold)
	var supplies: Dictionary = definition.get("supplies", {})
	for item: Variant in supplies:
		var n: Variant = PowerGrid.to_int(supplies[item])
		if not PowerGrid.is_valid_id(item) or n == null or int(n) < 0:
			errs.append(PowerGrid.diag("BAD_VALUE", "supply %s needs an ID and a count >= 0" % str(item), []))
		else:
			_supplies[item] = int(n)
	var nodes: Dictionary = grid.canonical_state()["nodes"]
	for rec: Variant in definition.get("repairs", []):
		var r: Dictionary = rec if rec is Dictionary else {}
		var rid: Variant = r.get("id")
		var err: Dictionary = _check_repair(r, nodes)
		if not err.is_empty():
			errs.append(err)
		elif _repairs.has(rid):
			errs.append(PowerGrid.diag("DUPLICATE_ID", "duplicate repair %s" % rid, [rid]))
		else:
			_repairs[rid] = r
			_state[rid] = 0
	if not errs.is_empty():
		_repairs = {}
		_state = {}
	return errs


func _check_repair(r: Dictionary, nodes: Dictionary) -> Dictionary:
	var rid: Variant = r.get("id")
	if not PowerGrid.is_valid_id(rid):
		return PowerGrid.diag("INVALID_ID", "repair id %s must match ^[A-Z0-9_]+$" % str(rid), [])
	var iso: Variant = r.get("isolate")
	if not (iso is String and nodes.has(iso) and nodes[iso]["kind"] == PowerGrid.KIND_JUNCTION):
		return PowerGrid.diag("BAD_REPAIR", "%s: isolate must name a grid junction" % rid, [rid])
	var fix: Variant = r.get("fix")
	if not (fix is Dictionary and (fix as Dictionary).get("op") == "set" and (fix as Dictionary).get("value") is bool):
		return PowerGrid.diag("BAD_REPAIR", "%s: fix must be a grid set command" % rid, [rid])
	if not (r.get("component") is String and _supplies.has(r["component"])):
		return PowerGrid.diag("BAD_REPAIR", "%s: component must be a listed supply" % rid, [rid])
	if not (r.get("panel") is String and _meter.has_panel(r["panel"])):
		return PowerGrid.diag("BAD_REPAIR", "%s: panel must name a meter panel" % rid, [rid])
	for key: String in ["tools", "hold_ticks"]:
		var per_step: Variant = r.get(key, {})
		if not per_step is Dictionary:
			return PowerGrid.diag("BAD_REPAIR", "%s: %s must be an object keyed by step" % [rid, key], [rid])
		for step: Variant in per_step:
			if not STEPS.has(step):
				return PowerGrid.diag("BAD_REPAIR", "%s: %s names unknown step %s" % [rid, key, str(step)], [rid])
	var holds: Dictionary = r.get("hold_ticks", {})
	for step: String in holds:
		var h: Variant = PowerGrid.to_int(holds[step])
		if h == null or int(h) < 0 or int(h) > _max_hold_ticks:
			# no uninterrupted hold longer than 1.2 s by default (blueprint p.8)
			return PowerGrid.diag("HOLD_TOO_LONG", "%s: %s hold must be 0..%d ticks" % [rid, step, _max_hold_ticks], [rid])
	return {}


# ---------- players and world facts supplied by the host ----------

func join(player: String, tools: Array[String]) -> void:
	_players[player] = {"tools": tools.duplicate(), "equipped": ""}


## Releases every lock the player holds. Returns the release events.
func disconnect_player(player: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = _release_where(player, "", RELEASE_DISCONNECT)
	_players.erase(player)
	return events


## Host movement check says the player is no longer within interaction range of the repair.
func left_range(player: String, repair: String) -> Array[Dictionary]:
	return _release_where(player, repair, RELEASE_OUT_OF_RANGE)


## Mission director predicates (e.g. PUMP_HOUSE_DRAINED latched) that gate access to a repair.
func set_access(flag: String, granted: bool) -> void:
	if granted:
		_access[flag] = true
	else:
		_access.erase(flag)


## Advance host time; releases locks whose owner sent no valid heartbeat for the timeout.
func tick(now: int) -> Array[Dictionary]:
	_now = now
	var events: Array[Dictionary] = []
	for rid: String in _sorted(_locks.keys()):
		if _now - int(_locks[rid]["last_seen"]) >= _heartbeat_timeout_ticks:
			events.append(_release(rid, RELEASE_HEARTBEAT))
	return events


# ---------- intentions ----------

## sender: identity from the transport. intent: {"type": request_lock|release|heartbeat|equip|repair_step, "repair",
## "step", "tool", "in_range": host range verdict}. Reply: {"ok", "revision", ...} or a refusal with code/message/ids.
func handle(sender: String, intent: Dictionary) -> Dictionary:
	if not _players.has(sender):
		return _refuse("UNKNOWN_PLAYER", "player is not in this session", [])
	var kind: Variant = intent.get("type")
	if kind == "equip":
		return _equip(sender, intent.get("tool"))
	var rid: Variant = intent.get("repair")
	if not (rid is String and _repairs.has(rid)):
		return _refuse("UNKNOWN_REPAIR", "no repair %s" % str(rid), [])
	match kind:
		"request_lock":
			return _request_lock(sender, rid, intent.get("in_range") == true)
		"release":
			if not _owns(sender, rid):
				return _refuse("NOT_LOCK_OWNER", "%s is not working on %s" % [sender, rid], [rid])
			return _ok({"events": [_release(rid, RELEASE_CANCEL)]})
		"heartbeat":
			if not _owns(sender, rid):
				return _refuse("NOT_LOCK_OWNER", "%s is not working on %s" % [sender, rid], [rid])
			_locks[rid]["last_seen"] = _now
			return _ok({})
		"repair_step":
			return _repair_step(sender, rid, intent.get("step"), intent.get("in_range") == true)
	return _refuse("UNKNOWN_INTENT", "unknown intent %s" % str(kind), [])


func _equip(sender: String, tool: Variant) -> Dictionary:
	var p: Dictionary = _players[sender]
	if not (tool is String and (tool == "" or (p["tools"] as Array).has(tool))):
		return _refuse("MISSING_TOOL", "%s does not carry %s" % [sender, str(tool)], [])
	p["equipped"] = tool
	return _ok({})


func _request_lock(sender: String, rid: String, in_range: bool) -> Dictionary:
	if not in_range:
		return _refuse("NOT_IN_RANGE", "move closer to %s" % rid, [rid])
	var access: Variant = _repairs[rid].get("access")
	if access is String and not _access.has(access):
		return _refuse("NO_ACCESS", "%s cannot be reached yet" % rid, [rid, access])
	if _locks.has(rid):
		var owner: String = _locks[rid]["owner"]
		if owner == sender:
			_locks[rid]["last_seen"] = _now
			return _ok({"owner": owner})
		# other players see who is working (blueprint p.8)
		return _refuse("LOCKED_BY_OTHER", "%s is being worked on by %s" % [rid, owner], [rid, owner])
	if STATES[_state[rid]] == "restored":
		return _refuse("ALREADY_RESTORED", "%s is already restored" % rid, [rid])
	_locks[rid] = {"owner": sender, "last_seen": _now}
	revision += 1
	return _ok({"owner": sender})


func _repair_step(sender: String, rid: String, step: Variant, in_range: bool) -> Dictionary:
	if not _owns(sender, rid):
		return _refuse("NOT_LOCK_OWNER", "request the lock on %s first" % rid, [rid])
	if not in_range:
		return _refuse("NOT_IN_RANGE", "move closer to %s" % rid, [rid])
	if not (step is String and STEPS.has(step)):
		return _refuse("UNKNOWN_STEP", "unknown repair step %s" % str(step), [rid])
	_locks[rid]["last_seen"] = _now  # a valid repair request is a heartbeat
	var at: int = _state[rid]
	var want: int = STEPS.find(step)
	if want < at:
		# duplicate of a step that already happened: one state transition, nothing consumed twice (NET02 logic)
		return _ok({"duplicate": true, "state": STATES[at]})
	if want > at:
		return _refuse("WRONG_STEP", "%s needs %s next" % [rid, STEPS[at]], [rid])
	var r: Dictionary = _repairs[rid]
	var junction: String = r["isolate"]
	if NEEDS_ISOLATION.has(step) and not _grid.canonical_state()["nodes"][junction]["isolated"]:
		return _refuse("ISOLATE_FIRST", "%s is live: isolate %s first" % [rid, junction], [rid, junction])
	var tool: Variant = (r.get("tools", {}) as Dictionary).get(step)
	if tool is String and _players[sender]["equipped"] != tool:
		return _refuse("MISSING_TOOL", "%s needs the %s" % [step, tool], [rid])
	var err: Dictionary = _perform(rid, step)
	if not err.is_empty():
		return err
	_state[rid] = at + 1
	revision += 1
	var reply: Dictionary = {"state": STATES[at + 1]}
	if STATES[at + 1] == "restored":
		reply["events"] = [_release(rid, RELEASE_COMPLETED)]
	return _ok(reply)


## The side effects of one step. Either all happen or none (returns a refusal).
func _perform(rid: String, step: String) -> Dictionary:
	var r: Dictionary = _repairs[rid]
	var junction: String = r["isolate"]
	match step:
		"diagnose":
			if not _meter.readings(r["panel"], _grid)["_panel"].has("tick"):
				return _refuse("NOT_INSPECTED", "inspect %s with the meter first" % r["panel"], [rid, r["panel"]])
		"isolate":
			return _grid_apply({"op": "set", "id": junction, "field": "isolated", "value": true}, rid)
		"install":
			var item: String = r["component"]
			if int(_supplies.get(item, 0)) < 1:
				return _refuse("MISSING_COMPONENT", "no %s left" % item, [rid, item])
			var err: Dictionary = _grid_apply(r["fix"], rid)
			if not err.is_empty():
				return err
			_supplies[item] = int(_supplies[item]) - 1
		"restore":
			var was_isolated: bool = _grid.canonical_state()["nodes"][junction]["isolated"]
			var err: Dictionary = _grid_apply({"op": "set", "id": junction, "field": "isolated", "value": false}, rid)
			if not err.is_empty():
				return err
			if _grid.canonical_state()["nodes"][junction]["tripped"]:
				err = _grid_apply({"op": "set", "id": junction, "field": "tripped", "value": false}, rid)
				if not err.is_empty():
					if was_isolated:
						# re-isolating is always valid (it only removes supply); keeps restore atomic
						_grid.apply({"op": "set", "id": junction, "field": "isolated", "value": true})
						_meter.observe(_grid)
					return err
	return {}


func _grid_apply(cmd: Dictionary, rid: String) -> Dictionary:
	var res: Dictionary = _grid.apply(cmd)
	if res["ok"]:
		_meter.observe(_grid)
		return {}
	var ids: Array = (res["ids"] as Array).duplicate()
	ids.append(rid)
	var refusal: Dictionary = _refuse("GRID_REFUSED", res["message"], ids)
	refusal["grid_code"] = res["code"]
	return refusal


# ---------- state ----------

func repair_state(rid: String) -> String:
	return STATES[_state[rid]]


func lock_owner(rid: String) -> String:
	return _locks[rid]["owner"] if _locks.has(rid) else ""


func supply(item: String) -> int:
	return int(_supplies.get(item, 0))


## Durable causes for saves (G06) and join snapshots: repair states, supplies, locks, access flags.
func canonical_state() -> Dictionary:
	var repairs: Dictionary = {}
	for rid: String in _repairs:
		repairs[rid] = {"state": STATES[_state[rid]], "lock_owner": lock_owner(rid)}
	return {"schema": SCHEMA, "revision": revision, "repairs": repairs, "supplies": _supplies.duplicate(),
		"access": _sorted(_access.keys())}


## Restores durable repair progress, supplies and access flags from a checkpoint (G06). Locks are session state
## and are not restored. All-or-nothing: returns diagnostics and changes nothing on any problem.
func restore_state(saved: Dictionary) -> Array[Dictionary]:
	var errs: Array[Dictionary] = []
	var states: Dictionary = {}
	var repairs: Dictionary = saved.get("repairs", {})
	for rid: Variant in repairs:
		var st: Variant = (repairs[rid] as Dictionary).get("state") if repairs[rid] is Dictionary else null
		if not (rid is String and _repairs.has(rid) and st is String and STATES.has(st)):
			errs.append(PowerGrid.diag("BAD_SAVE", "saved repair %s is unknown or has a bad state" % str(rid), []))
		else:
			states[rid] = STATES.find(st)
	var supplies: Dictionary = {}
	var saved_supplies: Dictionary = saved.get("supplies", {})
	for item: Variant in saved_supplies:
		var n: Variant = PowerGrid.to_int(saved_supplies[item])
		if not (item is String and _supplies.has(item)) or n == null or int(n) < 0:
			errs.append(PowerGrid.diag("BAD_SAVE", "saved supply %s is unknown or negative" % str(item), []))
		else:
			supplies[item] = int(n)
	if not errs.is_empty():
		return errs
	_state.merge(states, true)
	_supplies.merge(supplies, true)
	_locks = {}
	_access = {}
	for flag: Variant in saved.get("access", []):
		if flag is String:
			_access[flag] = true
	revision += 1
	return errs


# ---------- helpers ----------

func _owns(sender: String, rid: String) -> bool:
	return _locks.has(rid) and _locks[rid]["owner"] == sender


func _release(rid: String, reason: String) -> Dictionary:
	var owner: String = _locks[rid]["owner"]
	_locks.erase(rid)
	revision += 1
	return {"type": "lock_released", "repair": rid, "owner": owner, "reason": reason, "state": STATES[_state[rid]]}


func _release_where(player: String, repair: String, reason: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for rid: String in _sorted(_locks.keys()):
		if _locks[rid]["owner"] == player and (repair == "" or repair == rid):
			events.append(_release(rid, reason))
	return events


func _ok(extra: Dictionary) -> Dictionary:
	var out: Dictionary = {"ok": true, "revision": revision}
	out.merge(extra)
	return out


func _refuse(code: String, message: String, ids: Array) -> Dictionary:
	var d: Dictionary = PowerGrid.diag(code, message, ids)
	return {"ok": false, "code": code, "key": "interaction.refused." + code.to_lower(), "message": message,
		"ids": d["ids"], "revision": revision}


static func _sorted(keys: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(keys)
	out.sort()
	return out
