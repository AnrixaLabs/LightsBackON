extends "res://tests/test_case.gd"
## V04: four-player snapshot flow. Join during pump/repair converges to the canonical state; no duplicate actors.
## In-process delivery through JSON (like the wire). Real remote joins are local (F02 tuple).

const Runner := preload("res://tests/support/solution_runner.gd")
const SessionClient := preload("res://scripts/network/session_client.gd")
const ContentHash := preload("res://scripts/network/content_hash.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const C01: String = "res://content/contracts/c01_alder_street"
const TOOLS: Array[String] = ["screwdriver", "puller", "cutter", "crimper", "meter"]
const EAST_TOOLS: Dictionary = {"open": "screwdriver", "remove": "cutter", "install": "crimper", "test": "meter"}

var _ctx: Dictionary
var _clients: Dictionary = {}  # peer -> SessionClient


func before_each() -> void:
	_ctx = Runner.build(C01, ["HOSTP"], TOOLS)  # peer 2 plays the host's own player in this harness
	_clients = {}


func after_each() -> void:
	_ctx = {}
	_clients = {}


func test_V04_four_players_join_mid_pump_and_mid_repair_and_converge() -> void:
	var host: Variant = _ctx["host"]
	# P2 joins while the pump drains
	_cmd("HOSTP", "place_item", "GEN_PORTABLE", {"action": "pickup"})
	_cmd("HOSTP", "place_item", "GEN_PORTABLE", {"action": "place", "anchor": "PAD_PUMP"})
	_cmd("HOSTP", "place_item", "GEN_PORTABLE", {"action": "connect", "route": "E_TEMP_PUMP"})
	_cmd("HOSTP", "place_item", "GEN_PORTABLE", {"action": "start"})
	_tick(40)
	_join_while_live(3, "P2", 5)
	_tick(80)
	assert_true(_ctx["mission"].is_latched("LATCH_PUMP_DRAIN"))
	# P3 joins halfway through the east repair, which P2 is doing
	_cmd("P2", "request_lock", "R_JE_TRUNK", {})
	_cmd("P2", "inspect", "PANEL_JE", {})
	for step: String in ["diagnose", "isolate", "open", "remove"]:
		_cmd("P2", "equip", "R_JE_TRUNK", {"tool": EAST_TOOLS.get(step, "")})
		assert_true(_cmd("P2", "repair_step", "R_JE_TRUNK", {"step": step})["ok"])
	_join_while_live(4, "P3", 3)
	for step: String in ["install", "close", "test", "restore"]:
		_cmd("P2", "equip", "R_JE_TRUNK", {"tool": EAST_TOOLS.get(step, "")})
		assert_true(_cmd("P2", "repair_step", "R_JE_TRUNK", {"step": step})["ok"])
	_join_while_live(5, "P4", 2)
	_tick(10)
	_assert_all_converged("after four joins")
	var crew: Array = host.authoritative_state()["crew"]
	assert_eq(crew, ["HOSTP", "P2", "P3", "P4"], "four actors, no duplicates")
	for peer: int in _clients:
		assert_eq((_clients[peer] as SessionClient).state["repairs"]["repairs"]["R_JE_TRUNK"]["state"], "restored")
	assert_eq(host.admit(6, "P5", 1, Runner.CONTENT_REVISION, TOOLS)["code"], "SESSION_FULL", "1-4 players")


func test_V04_revision_barrier_refuses_commands_until_the_snapshot_is_applied() -> void:
	var host: Variant = _ctx["host"]
	assert_true(host.admit(3, "P2", 1, Runner.CONTENT_REVISION, TOOLS)["needs_snapshot"])
	var before: String = host.state_hash()
	var r: Dictionary = host.receive(3, _bytes(1, "toggle_switch", "SW_SIGN", {"value": true}))
	assert_eq(r["code"], "NOT_SYNCED", "frozen in the joining screen")
	assert_eq(host.state_hash(), before)
	assert_eq(host.confirm_synced(3, 0)["code"], "STALE_SNAPSHOT", "a snapshot from before this connection does not count")
	assert_true(host.confirm_synced(3, host.revision)["ok"])
	assert_true(host.receive(3, _bytes(2, "toggle_switch", "SW_SIGN", {"value": true}))["ok"])


func test_V04_reconnect_on_a_new_connection_replaces_the_ghost() -> void:
	var host: Variant = _ctx["host"]
	_join_while_live(3, "P2", 0)
	_cmd("P2", "request_lock", "R_JW_FUSE", {})
	# P2's old connection hangs (no disconnect seen yet) and P2 comes back on a new one
	var res: Dictionary = host.admit(7, "P2", 1, Runner.CONTENT_REVISION, TOOLS)
	assert_true(res["ok"])
	assert_true((res["replaced"] as Array).any(func(e: Dictionary) -> bool: return e.get("reason") == "disconnect"), "old lock released")
	_clients.erase(3)
	_ctx["peers"]["P2"] = 7
	_sync_new_client(7)
	assert_eq(host.authoritative_state()["crew"], ["HOSTP", "P2"], "one actor for P2")
	assert_eq(host.receive(3, _bytes(50, "toggle_switch", "SW_SIGN", {"value": true}))["code"], "UNKNOWN_PEER", "the ghost is gone")
	_tick(2)
	_assert_all_converged("after reconnect")


func test_V04_content_handshake_uses_the_real_content_hash() -> void:
	var h: String = ContentHash.content_revision()
	assert_eq(h.length(), 64)
	assert_eq(h, ContentHash.content_revision(), "deterministic")
	var grid_only: String = ContentHash.content_revision("res://content/contracts")
	assert_ne(grid_only, h, "any difference in content changes the hash")
	assert_eq(_ctx["host"].admit(8, "PX", 1, h, TOOLS)["code"], "CONTENT_MISMATCH", "a build with other content is refused before spawning")


func test_V04_snapshot_chunks_are_bounded() -> void:
	var limit: int = int(Runner.json("res://content/network.json")["snapshot_chunk_bytes"])
	var snap: Dictionary = _ctx["host"].snapshot()
	assert_true((snap["chunks"] as Array).size() > 1, "C01 state needs several chunks")
	for c: Dictionary in snap["chunks"]:
		assert_true(JSON.stringify(c).to_utf8_buffer().size() <= limit, "encoded chunk message <= %d bytes" % limit)


# ---------- helpers ----------

func _bytes(seq: int, kind: String, entity: String, payload: Dictionary) -> PackedByteArray:
	return JSON.stringify({"session": Runner.SESSION, "seq": seq, "type": kind, "entity": entity, "payload": payload}).to_utf8_buffer()


func _wire(msg: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(msg))


func _publish() -> void:
	var d: Dictionary = _ctx["host"].publish()
	if d.is_empty():
		return
	for peer: int in _clients:
		(_clients[peer] as SessionClient).on_message(_wire(d))


func _cmd(player: String, intent: String, entity: String, payload: Dictionary) -> Dictionary:
	var r: Dictionary = Runner.send(_ctx, player, intent, entity, payload)
	_tick(1)
	return r


func _tick(n: int) -> void:
	for _i: int in n:
		Runner.ticks(_ctx, 1)
		_publish()


func _new_client() -> SessionClient:
	var c: SessionClient = SessionClient.new()
	c.configure(Runner.CONTENT_REVISION, int(Runner.json("res://content/network.json")["max_queued_deltas"]))
	return c


## Admits a player and delivers their snapshot while the host keeps running for `live_ticks` (deltas arrive before
## the chunks finish), then lifts the revision barrier.
func _join_while_live(peer: int, player: String, live_ticks: int) -> void:
	assert_true(_ctx["host"].admit(peer, player, 1, Runner.CONTENT_REVISION, TOOLS)["ok"])
	_ctx["peers"][player] = peer
	var c: SessionClient = _new_client()
	var snap: Dictionary = _ctx["host"].snapshot()
	for d: Dictionary in snap["deltas"]:
		for other: int in _clients:
			(_clients[other] as SessionClient).on_message(_wire(d))
	c.on_message(_wire(snap["manifest"]))
	_clients[peer] = c  # receives live deltas from now on, queued while joining
	_tick(live_ticks)
	for chunk: Dictionary in snap["chunks"]:
		c.on_message(_wire(chunk))
	assert_eq(c.status, SessionClient.STATUS_SYNCED, "%s synced (%s)" % [player, c.last_issue])
	assert_true(_ctx["host"].confirm_synced(peer, c.revision)["ok"])


func _sync_new_client(peer: int) -> void:
	var c: SessionClient = _new_client()
	var snap: Dictionary = _ctx["host"].snapshot()
	for d: Dictionary in snap["deltas"]:
		for other: int in _clients:
			(_clients[other] as SessionClient).on_message(_wire(d))
	c.on_message(_wire(snap["manifest"]))
	for chunk: Dictionary in snap["chunks"]:
		c.on_message(_wire(chunk))
	_clients[peer] = c
	assert_true(_ctx["host"].confirm_synced(peer, c.revision)["ok"])


func _assert_all_converged(label: String) -> void:
	var want: String = _ctx["host"].state_hash()
	for peer: int in _clients:
		var c: SessionClient = _clients[peer]
		assert_eq(c.status, SessionClient.STATUS_SYNCED, "%s peer %d (%s)" % [label, peer, c.last_issue])
		assert_eq(c.state_hash(), want, "%s peer %d canonical hash" % [label, peer])
		assert_eq(c.revision, _ctx["host"].revision, "%s peer %d revision" % [label, peer])
