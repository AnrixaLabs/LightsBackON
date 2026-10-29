extends RefCounted
## Builds the full host stack for a contract from content and replays a solution trace through session_host.gd,
## exactly like remote commands (JSON bytes, sender from the "transport" peer ID). Used by the V02 tests and by
## tools/godot/validate_solution.gd. Range checks always pass until the V01 graybox gives positions.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const MissionDirector := preload("res://scripts/simulation/mission_director.gd")
const SessionHost := preload("res://scripts/network/session_host.gd")
const Comms := preload("res://scripts/network/comms_service.gd")

const SESSION: String = "S_SOLUTION"
const CONTENT_REVISION: String = "REV_SOLUTION"
const FIRST_PEER: int = 2


static func json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Returns a context: {"host", "grid", "meter", "interaction", "equipment", "mission", "peers": {player: peer},
## "seq": {peer: int}, "now": int, "events": Array, "errors": Array}.
static func build(contract_dir: String, players: Array, tools: Array) -> Dictionary:
	var ctx: Dictionary = {"errors": [] as Array[Dictionary]}
	var grid: PowerGrid = PowerGrid.new()
	(ctx["errors"] as Array).append_array(grid.load_definition(json(contract_dir.path_join("grid.json"))))
	var meter: MeterModel = MeterModel.new()
	(ctx["errors"] as Array).append_array(meter.load_definition(json(contract_dir.path_join("meter.json")), grid))
	var inter: Interaction = Interaction.new()
	(ctx["errors"] as Array).append_array(inter.load_definition(json("res://content/interaction.json"),
		json(contract_dir.path_join("repairs.json")), grid, meter))
	var eq: Equipment = Equipment.new()
	(ctx["errors"] as Array).append_array(eq.load_definition(json(contract_dir.path_join("equipment.json")), grid, meter))
	var mission: MissionDirector = MissionDirector.new()
	(ctx["errors"] as Array).append_array(mission.load_definition(json(contract_dir.path_join("mission.json")), grid, inter, eq))
	var host: SessionHost = SessionHost.new()
	(ctx["errors"] as Array).append_array(host.configure(json("res://content/network.json"), 1, CONTENT_REVISION, SESSION, grid,
		meter, inter, eq, json(contract_dir.path_join("switches.json")), func(_p: String, _e: String) -> bool: return true))
	host.set_mission(mission)
	var comms: Comms = Comms.new()
	(ctx["errors"] as Array).append_array(comms.load_definition(json("res://content/comms.json")))
	host.set_comms(comms)
	var typed_tools: Array[String] = []
	typed_tools.assign(tools)
	var peers: Dictionary = {}
	var peer: int = FIRST_PEER
	for p: Variant in players:
		host.admit(peer, str(p), 1, CONTENT_REVISION, typed_tools)
		host.confirm_synced(peer, host.revision)  # solo/in-process: the "client" already sees the host state
		peers[str(p)] = peer
		peer += 1
	ctx.merge({"host": host, "grid": grid, "meter": meter, "interaction": inter, "equipment": eq, "mission": mission, "comms": comms,
		"peers": peers, "seq": {}, "now": 0, "events": [] as Array[Dictionary]})
	return ctx


## Sends one intent as player; returns the host reply.
static func send(ctx: Dictionary, player: String, intent: String, entity: String, payload: Dictionary) -> Dictionary:
	var peer: int = ctx["peers"].get(player, 99)
	var seq: int = int((ctx["seq"] as Dictionary).get(peer, 0)) + 1
	ctx["seq"][peer] = seq
	var bytes: PackedByteArray = JSON.stringify({"session": SESSION, "seq": seq, "type": intent, "entity": entity,
		"payload": payload}).to_utf8_buffer()
	var reply: Dictionary = (ctx["host"] as SessionHost).receive(peer, bytes)
	if reply.has("events"):
		(ctx["events"] as Array).append_array(reply["events"])
	return reply


## Advances n host ticks; returns the events of those ticks.
static func ticks(ctx: Dictionary, n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for _i: int in n:
		ctx["now"] = int(ctx["now"]) + 1
		out.append_array((ctx["host"] as SessionHost).tick(ctx["now"]))
	(ctx["events"] as Array).append_array(out)
	return out


## Replays trace steps; returns a list of human-readable mismatches (empty = every expectation held).
static func run(ctx: Dictionary, steps: Array, pace_ticks: int = 0) -> Array[String]:
	var failures: Array[String] = []
	var index: int = 0
	for s: Dictionary in steps:
		index += 1
		if s.has("note"):
			continue
		if s.has("ticks"):
			var evs: Array[Dictionary] = ticks(ctx, int(s["ticks"]))
			for want: Variant in s.get("expect_events", []):
				if not _has_event(evs, str(want)):
					failures.append("step %d: expected event %s within %d ticks" % [index, want, int(s["ticks"])])
			continue
		if s.has("zone"):
			(ctx["host"] as SessionHost).set_in_zone(s["as"], s["zone"], s["inside"])
			continue
		var reply: Dictionary = send(ctx, s["as"], s["intent"], s["entity"], s.get("payload", {}))
		var want_code: String = s.get("expect", "ok")
		var got: String = "ok" if reply.get("ok", false) else str(reply.get("code", "?"))
		if got != want_code:
			failures.append("step %d (%s %s %s): expected %s, got %s %s" % [index, s["as"], s["intent"], s["entity"], want_code, got,
				reply.get("message", "")])
		if pace_ticks > 0:
			ticks(ctx, pace_ticks)  # players act at human speed, inside the per-sender rate limit
	return failures


static func _has_event(evs: Array, kind: String) -> bool:
	for e: Dictionary in evs:
		if e.get("type") == kind:
			return true
	return false
