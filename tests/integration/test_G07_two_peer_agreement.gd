extends "res://tests/test_case.gd"
## G07 (draft, logic level): every action goes through the host; clients mirror revisioned deltas and snapshots and agree
## with the host by canonical hash after repair, trip, reset and reconnect. Messages pass through JSON like the wire.
## In-process delivery, not real peers: DONE needs F06 (two real PCs).

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const SessionHost := preload("res://scripts/network/session_host.gd")
const SessionClient := preload("res://scripts/network/session_client.gd")
const Cases := preload("res://tests/support/grid_cases.gd")
const C01: String = "res://content/contracts/c01_alder_street/"
const SESSION: String = "S_G07"
const REV: String = "REV_A"
const TOOLS: Array[String] = ["screwdriver", "puller", "cutter", "crimper", "meter"]
const WEST_TOOLS: Dictionary = {"open": "screwdriver", "remove": "puller", "install": "puller", "test": "meter"}
const EAST_TOOLS: Dictionary = {"open": "screwdriver", "remove": "cutter", "install": "crimper", "test": "meter"}

var _host: SessionHost
var _inter: Interaction
var _clients: Dictionary = {}  # peer id -> SessionClient (connected ones receive deltas)
var _seq: Dictionary = {}
var _now: int = 0


func before_each() -> void:
	var grid: PowerGrid = PowerGrid.new()
	grid.load_definition(Cases.definition_for(Cases.load_doc(), {}, false))
	var meter: MeterModel = MeterModel.new()
	meter.load_definition(_json(C01 + "meter.json"), grid)
	_inter = Interaction.new()
	_inter.load_definition(_json("res://content/interaction.json"), _json(C01 + "repairs.json"), grid, meter)
	var eq: Equipment = Equipment.new()
	eq.load_definition(_json(C01 + "equipment.json"), grid, meter)
	_host = SessionHost.new()
	_host.configure(_json("res://content/network.json"), 1, REV, SESSION, grid, meter, _inter, eq, _json(C01 + "switches.json"),
		func(_p: String, _e: String) -> bool: return true)
	_join(2, "P1")
	_join(3, "P2")


func after_each() -> void:
	_host = null


func test_G07_two_peers_agree_after_repair_trip_reset_and_reconnect() -> void:
	_agree("after join")
	# repair (west, by P1)
	_repair(2, "R_JW_FUSE", "PANEL_JW", WEST_TOOLS)
	_agree("after west repair")
	assert_true((_clients[3] as SessionClient).is_supplied("APT_W"), "P2 sees the west restored from host state")
	# east repair by P2 once the mission director grants access
	_inter.set_access("PUMP_HOUSE_DRAINED", true)
	_repair(3, "R_JE_TRUNK", "PANEL_JE", EAST_TOOLS)
	_agree("after east repair")
	# trip: sign overload for 15 ticks
	assert_true(_cmd(2, "toggle_switch", "SW_SIGN", {"value": true})["ok"])
	var trips: int = 0
	for _i: int in 15:
		for ev: Dictionary in _tick():
			if ev.get("type") == "trip":
				trips += 1
	assert_eq(trips, 1)
	_agree("after trip")
	assert_eq((_clients[2] as SessionClient).state["grid"]["nodes"]["JE"]["tripped"], true)
	# reset: refused while the sign is on, accepted after
	var refused: Dictionary = _cmd(3, "toggle_switch", "SW_JE_BREAKER", {"value": false})
	assert_eq(refused["grid_code"], "RESET_OVERLOADED")
	assert_true(_cmd(3, "toggle_switch", "SW_SIGN", {"value": false})["ok"])
	assert_true(_cmd(3, "toggle_switch", "SW_JE_BREAKER", {"value": false})["ok"])
	_agree("after reset")
	assert_true((_clients[2] as SessionClient).is_supplied("PUB"))
	# reconnect: P2 drops, the world changes, P2 rejoins with a new peer ID and converges
	_host.remove(3)
	_clients.erase(3)
	assert_true(_cmd(2, "place_item", "GEN_PORTABLE", {"action": "pickup"})["ok"])
	_tick()
	_join(5, "P2")
	_agree("after reconnect")
	assert_eq((_clients[5] as SessionClient).state["equipment"]["items"]["GEN_PORTABLE"]["carrier"], "P1")


func test_NET04_logic_join_during_live_changes_queues_newer_deltas() -> void:
	_repair(2, "R_JW_FUSE", "PANEL_JW", WEST_TOOLS)
	_publish()
	assert_true(_host.admit(6, "P3", 1, REV, TOOLS)["ok"])
	var late: SessionClient = _client()
	var snap: Dictionary = _host.snapshot()
	_publish()
	late.on_message(_wire(snap["manifest"]))
	assert_eq(late.status, SessionClient.STATUS_JOINING, "frozen in the joining screen")
	# while chunks are still in flight the host keeps ticking and publishing
	var in_flight: Array[Dictionary] = []
	for _i: int in 3:
		_now += 1
		_host.tick(_now)
		in_flight.append(_host.publish())
	_cmd_unpublished(2, "toggle_switch", "SW_SIGN", {"value": true})
	in_flight.append(_host.publish())
	for d: Dictionary in in_flight:
		late.on_message(_wire(d))
	for chunk: Dictionary in snap["chunks"]:
		late.on_message(_wire(chunk))
	assert_eq(late.status, SessionClient.STATUS_SYNCED)
	assert_eq(late.revision, _host.revision)
	assert_eq(late.state_hash(), _host.state_hash(), "snapshot plus queued deltas converge")
	assert_eq(late.state["grid"]["nodes"]["SIGN"]["enabled"], true)


func test_G07_out_of_order_and_duplicate_deltas() -> void:
	var a: SessionClient = _clients[2]
	_cmd_unpublished(2, "toggle_switch", "SW_SIGN", {"value": true})
	var d1: Dictionary = _host.publish()
	_cmd_unpublished(2, "toggle_switch", "SW_SIGN", {"value": false})
	var d2: Dictionary = _host.publish()
	a.on_message(_wire(d2))
	assert_eq(a.revision, int(d1["from"]), "gap: d2 waits for d1")
	a.on_message(_wire(d1))
	a.on_message(_wire(d1))
	assert_eq(a.revision, _host.revision)
	assert_eq(a.state_hash(), _host.state_hash())


func test_G07_tampered_delta_and_wrong_content_detected() -> void:
	var a: SessionClient = _clients[2]
	_cmd_unpublished(2, "toggle_switch", "SW_SIGN", {"value": true})
	var d: Dictionary = _host.publish()
	(d["ops"] as Array).append({"op": "set", "path": ["grid", "nodes", "PUB", "supplied"], "value": true})
	a.on_message(_wire(d))
	assert_eq(a.status, SessionClient.STATUS_DESYNC)
	assert_eq(a.last_issue, "DELTA_HASH_MISMATCH", "client never accepts a state the host did not hash")
	assert_true(a.needs_snapshot())
	var other: SessionClient = SessionClient.new()
	other.configure("REV_B", 16)
	other.on_message(_wire(_host.snapshot()["manifest"]))
	assert_eq(other.last_issue, "CONTENT_MISMATCH")


func test_G07_host_loop_requests_checkpoints() -> void:
	var due: Array[String] = []
	for _i: int in 600:
		for ev: Dictionary in _tick():
			if ev.get("type") == "checkpoint_due":
				due.append(ev["reason"])
	assert_eq(due, ["interval"] as Array[String], "every 60 s at 10 Hz")
	var last: Dictionary = _repair(2, "R_JW_FUSE", "PANEL_JW", WEST_TOOLS)
	assert_eq(last.get("checkpoint_due"), true, "and after durable repair completion")


# ---------- helpers ----------

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _wire(msg: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(msg))


func _client() -> SessionClient:
	var c: SessionClient = SessionClient.new()
	c.configure(REV, int(_json("res://content/network.json")["max_queued_deltas"]))
	return c


func _join(peer: int, player: String) -> void:
	assert_true(_host.admit(peer, player, 1, REV, TOOLS)["ok"])
	var c: SessionClient = _client()
	var snap: Dictionary = _host.snapshot()
	for d: Dictionary in snap["deltas"]:
		_broadcast(d)
	c.on_message(_wire(snap["manifest"]))
	for chunk: Dictionary in snap["chunks"]:
		c.on_message(_wire(chunk))
	_clients[peer] = c
	_seq[peer] = 0


func _broadcast(delta: Dictionary) -> void:
	for peer: int in _clients:
		(_clients[peer] as SessionClient).on_message(_wire(delta))


func _publish() -> void:
	var d: Dictionary = _host.publish()
	if not d.is_empty():
		_broadcast(d)


func _cmd(peer: int, kind: String, entity: String, payload: Dictionary) -> Dictionary:
	var reply: Dictionary = _cmd_unpublished(peer, kind, entity, payload)
	_publish()
	return reply


## Sends a command without publishing, for tests that control delta delivery themselves.
func _cmd_unpublished(peer: int, kind: String, entity: String, payload: Dictionary) -> Dictionary:
	_seq[peer] = int(_seq.get(peer, 0)) + 1
	var bytes: PackedByteArray = JSON.stringify({"session": SESSION, "seq": _seq[peer], "type": kind, "entity": entity,
		"payload": payload}).to_utf8_buffer()
	return _host.receive(peer, bytes)


func _tick() -> Array[Dictionary]:
	_now += 1
	var events: Array[Dictionary] = _host.tick(_now)
	_publish()
	return events


func _repair(peer: int, repair: String, panel: String, tools: Dictionary) -> Dictionary:
	assert_true(_cmd(peer, "request_lock", repair, {})["ok"], "lock %s" % repair)
	assert_true(_cmd(peer, "inspect", panel, {})["ok"])
	var last: Dictionary = {}
	for step: String in Interaction.STEPS:
		_cmd(peer, "equip", repair, {"tool": tools.get(step, "")})
		last = _cmd(peer, "repair_step", repair, {"step": step})
		assert_true(last["ok"], "%s %s: %s" % [repair, step, str(last)])
	return last


func _agree(label: String) -> void:
	var want: String = _host.state_hash()
	for peer: int in _clients:
		var c: SessionClient = _clients[peer]
		assert_eq(c.status, SessionClient.STATUS_SYNCED, "%s: peer %d synced (%s)" % [label, peer, c.last_issue])
		assert_eq(c.revision, _host.revision, "%s: peer %d revision" % [label, peer])
		assert_eq(c.state_hash(), want, "%s: peer %d canonical hash" % [label, peer])
