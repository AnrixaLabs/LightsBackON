extends "res://tests/test_case.gd"
## F03 over the real ENet DEVELOPMENT transport on localhost (one process, two peers). This is a smoke test of the
## command path through a real transport; it is not a network test and never satisfies F02/F06 (CLAUDE.md section 4).

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const SessionHost := preload("res://scripts/network/session_host.gd")
const Transport := preload("res://scripts/network/transport_adapter.gd")
const Cases := preload("res://tests/support/grid_cases.gd")
const C01: String = "res://content/contracts/c01_alder_street/"
const SESSION: String = "S_ENET_DEV"
const TIMEOUT_MS: int = 3000


func test_F03_enet_dev_duplicate_resend_changes_switch_once() -> void:
	var grid: PowerGrid = PowerGrid.new()
	grid.load_definition(Cases.definition_for(Cases.load_doc(), {}, false))
	var meter: MeterModel = MeterModel.new()
	meter.load_definition(_json(C01 + "meter.json"), grid)
	var inter: Interaction = Interaction.new()
	inter.load_definition(_json("res://content/interaction.json"), _json(C01 + "repairs.json"), grid, meter)
	var eq: Equipment = Equipment.new()
	eq.load_definition(_json(C01 + "equipment.json"), grid, meter)
	var host: SessionHost = SessionHost.new()
	host.configure(_json("res://content/network.json"), 1, "REV_A", SESSION, grid, meter, inter, eq,
		_json(C01 + "switches.json"), func(_p: String, _e: String) -> bool: return true)

	var port: int = int(_json("res://content/network.json")["enet_dev_port"]) + randi() % 500
	var server_res: Dictionary = Transport.create_host(Transport.MODE_ENET_DEV, port)
	assert_true(server_res["ok"], "ENet dev host on port %d: %s" % [port, str(server_res)])
	if not server_res["ok"]:
		return
	var server: ENetMultiplayerPeer = server_res["peer"]
	var client: ENetMultiplayerPeer = Transport.create_client(Transport.MODE_ENET_DEV, "127.0.0.1", port)["peer"]
	var joined: Array[int] = []
	server.peer_connected.connect(func(id: int) -> void: joined.append(id))
	var start: int = Time.get_ticks_msec()
	while (joined.is_empty() or client.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED) \
			and Time.get_ticks_msec() - start < TIMEOUT_MS:
		server.poll()
		client.poll()
		OS.delay_msec(5)
	assert_eq(joined.size(), 1, "client connected over ENet within %d ms" % TIMEOUT_MS)
	if joined.size() != 1:
		return
	var peer_id: int = joined[0]
	assert_true(host.admit(peer_id, "P1", 1, "REV_A", [] as Array[String])["ok"])

	var cmd: PackedByteArray = JSON.stringify({"session": SESSION, "seq": 1, "type": "toggle_switch", "entity": "SW_SIGN",
		"payload": {"value": true}}).to_utf8_buffer()
	Transport.send(client, 1, cmd)
	Transport.send(client, 1, cmd)  # resend of the same durable command
	var replies: Array[Dictionary] = []
	start = Time.get_ticks_msec()
	while replies.size() < 2 and Time.get_ticks_msec() - start < TIMEOUT_MS:
		for pkt: Dictionary in Transport.receive_all(server):
			assert_eq(pkt["peer"], peer_id, "sender identity comes from the transport")
			var reply: Dictionary = host.receive(pkt["peer"], pkt["bytes"])
			Transport.send(server, pkt["peer"], JSON.stringify(reply).to_utf8_buffer())
		for pkt: Dictionary in Transport.receive_all(client):
			assert_eq(pkt["peer"], 1, "replies come from the host")
			replies.append(JSON.parse_string((pkt["bytes"] as PackedByteArray).get_string_from_utf8()))
		OS.delay_msec(5)
	assert_eq(replies.size(), 2, "both replies arrived")
	if replies.size() == 2:
		assert_eq(replies[0]["ok"], true)
		assert_false(replies[0].has("duplicate"))
		assert_eq(replies[1]["duplicate"], true)
		assert_eq(replies[1]["revision"], replies[0]["revision"])
	assert_eq(grid.canonical_state()["nodes"]["SIGN"]["enabled"], true)
	client.close()
	server.close()


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
