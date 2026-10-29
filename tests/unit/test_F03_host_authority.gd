extends "res://tests/test_case.gd"
## F03 (draft on the development path): host command authority. Duplicate command changes the switch once;
## invalid peer and entity IDs are rejected; identity comes from the transport; every reply carries the revision.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const SessionHost := preload("res://scripts/network/session_host.gd")
const Transport := preload("res://scripts/network/transport_adapter.gd")
const Cases := preload("res://tests/support/grid_cases.gd")
const C01: String = "res://content/contracts/c01_alder_street/"
const SESSION: String = "S_TEST_0001"
const TOOLS: Array[String] = ["screwdriver", "puller", "cutter", "crimper", "meter"]
const HOST_PEER: int = 1
const PEER_A: int = 2
const PEER_B: int = 3

var _grid: PowerGrid
var _host: SessionHost
var _out_of_range: Dictionary = {}  # "player|entity" -> true
var _seq: Dictionary = {}


func before_each() -> void:
	_grid = PowerGrid.new()
	_grid.load_definition(Cases.definition_for(Cases.load_doc(), {}, false))
	var meter: MeterModel = MeterModel.new()
	meter.load_definition(_json(C01 + "meter.json"), _grid)
	var inter: Interaction = Interaction.new()
	inter.load_definition(_json("res://content/interaction.json"), _json(C01 + "repairs.json"), _grid, meter)
	var eq: Equipment = Equipment.new()
	eq.load_definition(_json(C01 + "equipment.json"), _grid, meter)
	_host = SessionHost.new()
	var errs: Array[Dictionary] = _host.configure(_json("res://content/network.json"), 1, "REV_A", SESSION, _grid, meter, inter, eq,
		_json(C01 + "switches.json"), func(player: String, entity: String) -> bool: return not _out_of_range.has(player + "|" + entity))
	assert_true(errs.is_empty(), str(errs))
	# spawn: the host player goes through the same path as remote players
	for pair: Array in [[HOST_PEER, "HOST"], [PEER_A, "P1"], [PEER_B, "P2"]]:
		assert_true(_host.admit(pair[0], pair[1], 1, "REV_A", TOOLS)["ok"])


func after_each() -> void:
	_host = null  # the range-check lambda references this test; dropping the host breaks the cycle


func test_F03_duplicate_command_changes_switch_once() -> void:
	var bytes: PackedByteArray = _bytes(1, "toggle_switch", "SW_SIGN", {"value": true})
	var first: Dictionary = _host.receive(PEER_A, bytes)
	assert_eq(first["ok"], true)
	var rev: int = first["revision"]
	assert_eq(_grid.canonical_state()["nodes"]["SIGN"]["enabled"], true)
	var hash_after_first: String = _host.state_hash()
	var again: Dictionary = _host.receive(PEER_A, bytes)
	assert_eq(again["duplicate"], true)
	assert_eq(again["revision"], rev, "acknowledges the same durable revision")
	assert_eq(_host.revision, rev, "no second state change")
	# a different body under an already used seq is still the old command, never applied
	var replay: Dictionary = _host.receive(PEER_A, _bytes(1, "toggle_switch", "SW_SIGN", {"value": false}))
	assert_eq(replay["duplicate"], true)
	assert_eq(_grid.canonical_state()["nodes"]["SIGN"]["enabled"], true)
	assert_eq(_host.state_hash(), hash_after_first)


func test_F03_invalid_peer_rejected_without_mutation() -> void:
	var before: String = _host.state_hash()
	var res: Dictionary = _host.receive(99, _bytes(1, "toggle_switch", "SW_SIGN", {"value": true}))
	assert_eq(res["code"], "UNKNOWN_PEER")
	assert_eq(_host.state_hash(), before)
	_host.remove(PEER_B)
	assert_eq(_host.receive(PEER_B, _bytes(1, "toggle_switch", "SW_SIGN", {"value": true}))["code"], "UNKNOWN_PEER", "left peers are rejected")


func test_F03_invalid_entity_ids_rejected_without_mutation() -> void:
	var before: String = _host.state_hash()
	assert_eq(_send(PEER_A, "toggle_switch", "SW_NOPE", {"value": true})["code"], "UNKNOWN_ENTITY")
	assert_eq(_send(PEER_A, "request_lock", "R_NOPE", {})["code"], "UNKNOWN_ENTITY")
	assert_eq(_send(PEER_A, "inspect", "PANEL_NOPE", {})["code"], "UNKNOWN_ENTITY")
	assert_eq(_send(PEER_A, "place_item", "GEN_NOPE", {"action": "pickup"})["code"], "UNKNOWN_ITEM")
	assert_eq(_send(PEER_A, "toggle_switch", "sw sign; drop", {"value": true})["code"], "UNKNOWN_ENTITY")
	assert_eq(_host.state_hash(), before)


func test_F03_identity_comes_from_transport_not_payload() -> void:
	assert_true(_send(PEER_A, "request_lock", "R_JW_FUSE", {})["ok"])
	# P2 claims to be P1 inside the payload; the host ignores it
	var res: Dictionary = _send(PEER_B, "repair_step", "R_JW_FUSE", {"step": "diagnose", "player": "P1"})
	assert_eq(res["code"], "NOT_LOCK_OWNER")
	var other: Dictionary = _send(PEER_B, "request_lock", "R_JW_FUSE", {})
	assert_eq(other["code"], "LOCKED_BY_OTHER")
	assert_true((other["ids"] as Array).has("P1"), "others see who is working")


func test_F03_revision_acknowledges_only_durable_changes() -> void:
	var r0: int = _host.revision
	var refused: Dictionary = _send(PEER_A, "request_lock", "R_JE_TRUNK", {})
	assert_eq(refused["code"], "NO_ACCESS")
	assert_eq(refused["revision"], r0, "refusal does not advance the revision")
	var lock: Dictionary = _send(PEER_A, "request_lock", "R_JW_FUSE", {})
	assert_eq(lock["revision"], r0 + 1)
	assert_eq(_send(PEER_A, "heartbeat", "R_JW_FUSE", {})["revision"], r0 + 1, "heartbeat is not a durable change")
	assert_eq(_send(PEER_A, "inspect", "PANEL_JW", {})["revision"], r0 + 2, "inspection result is shared crew state")


func test_F03_envelope_session_sequence_and_size_checks() -> void:
	var good: Dictionary = {"session": SESSION, "seq": 1, "type": "toggle_switch", "entity": "SW_SIGN", "payload": {"value": true}}
	var wrong_session: Dictionary = good.duplicate(true)
	wrong_session["session"] = "S_OTHER"
	assert_eq(_host.receive(PEER_A, _raw(wrong_session))["code"], "WRONG_SESSION")
	var extra: Dictionary = good.duplicate(true)
	extra["player"] = "P2"
	assert_eq(_host.receive(PEER_A, _raw(extra))["code"], "MALFORMED", "no identity or extra fields in the envelope")
	assert_eq(_host.receive(PEER_A, "not json".to_utf8_buffer())["code"], "MALFORMED")
	var big: Dictionary = good.duplicate(true)
	big["payload"] = {"value": "x".repeat(3000)}
	assert_eq(_host.receive(PEER_A, _raw(big))["code"], "TOO_LARGE")
	var nested: Dictionary = good.duplicate(true)
	nested["payload"] = {"value": {"deep": true}}
	assert_eq(_host.receive(PEER_A, _raw(nested))["code"], "MALFORMED")
	var zero: Dictionary = good.duplicate(true)
	zero["seq"] = 0
	assert_eq(_host.receive(PEER_A, _raw(zero))["code"], "MALFORMED")


func test_F03_stale_sequence_outside_dedupe_window_refused() -> void:
	for seq: int in range(1, 80):
		_host.tick(seq * 10)  # stay under the rate limit
		_host.receive(PEER_A, _bytes(seq, "toggle_switch", "SW_SIGN", {"value": seq % 2 == 1}))
	assert_eq(_host.receive(PEER_A, _bytes(3, "toggle_switch", "SW_SIGN", {"value": true}))["code"], "STALE_SEQUENCE")
	assert_eq(_host.receive(PEER_A, _bytes(70, "toggle_switch", "SW_SIGN", {"value": true}))["duplicate"], true)


func test_F03_rate_limit_per_sender() -> void:
	var limits: Dictionary = _json("res://content/network.json")
	var n: int = int(limits["rate_limit_commands"])
	for i: int in n:
		assert_true(_send(PEER_A, "heartbeat", "R_JW_FUSE", {}).has("seq"))
	assert_eq(_send(PEER_A, "heartbeat", "R_JW_FUSE", {})["code"], "RATE_LIMITED")
	assert_ne(_send(PEER_B, "heartbeat", "R_JW_FUSE", {}).get("code", ""), "RATE_LIMITED", "limits are per sender")
	_host.tick(int(limits["rate_limit_window_ticks"]))
	assert_ne(_send(PEER_A, "heartbeat", "R_JW_FUSE", {}).get("code", ""), "RATE_LIMITED", "window slides")


func test_F03_range_checked_by_host() -> void:
	_out_of_range["P1|SW_SIGN"] = true
	assert_eq(_send(PEER_A, "toggle_switch", "SW_SIGN", {"value": true})["code"], "NOT_IN_RANGE")
	assert_eq(_grid.canonical_state()["nodes"]["SIGN"]["enabled"], false)


func test_NET08_logic_version_mismatch_rejected_before_spawn() -> void:
	assert_eq(_host.admit(7, "P3", 2, "REV_A", TOOLS)["code"], "PROTOCOL_MISMATCH")
	assert_eq(_host.admit(7, "P3", 1, "REV_B", TOOLS)["code"], "CONTENT_MISMATCH")
	assert_eq(_host.member(7), "", "not spawned")
	assert_eq(_host.admit(7, "P1", 1, "REV_A", TOOLS)["code"], "ALREADY_JOINED")


func test_F03_disconnect_releases_lock_through_host() -> void:
	assert_true(_send(PEER_A, "request_lock", "R_JW_FUSE", {})["ok"])
	var events: Array[Dictionary] = _host.remove(PEER_A)
	assert_eq(events[0]["reason"], "disconnect")
	assert_true(_send(PEER_B, "request_lock", "R_JW_FUSE", {})["ok"])


func test_F03_deferred_intents_and_steam_refused_clearly() -> void:
	assert_eq(_send(PEER_A, "ping", "SW_SIGN", {})["code"], "UNSUPPORTED_INTENT")
	assert_eq(_send(PEER_A, "teleport", "SW_SIGN", {})["code"], "UNKNOWN_INTENT")
	assert_eq(Transport.create_host(Transport.MODE_STEAM, 0)["code"], "STEAM_NOT_QUALIFIED")
	assert_eq(Transport.create_client(Transport.MODE_OFFLINE, "", 0)["code"], "UNKNOWN_TRANSPORT")
	assert_true(Transport.create_host(Transport.MODE_OFFLINE, 0)["ok"])


# ---------- helpers ----------

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _raw(msg: Dictionary) -> PackedByteArray:
	return JSON.stringify(msg).to_utf8_buffer()


func _bytes(seq: int, kind: String, entity: String, payload: Dictionary) -> PackedByteArray:
	return _raw({"session": SESSION, "seq": seq, "type": kind, "entity": entity, "payload": payload})


func _send(peer: int, kind: String, entity: String, payload: Dictionary) -> Dictionary:
	var seq: int = int(_seq.get(peer, 0)) + 1
	_seq[peer] = seq
	return _host.receive(peer, _bytes(seq, kind, entity, payload))
