extends "res://tests/test_case.gd"
## V02: C01 mission logic through the full host stack (session_host -> grid, interaction, equipment, mission director).
## Acceptance: the known solution completes; the optional pub sign never blocks campaign progress.

const Runner := preload("res://tests/support/solution_runner.gd")
const MissionDirector := preload("res://scripts/simulation/mission_director.gd")
const C01: String = "res://content/contracts/c01_alder_street"
const TOOLS: Array[String] = ["screwdriver", "puller", "cutter", "crimper", "meter"]
const WEST_TOOLS: Dictionary = {"open": "screwdriver", "remove": "puller", "install": "puller", "test": "meter"}
const EAST_TOOLS: Dictionary = {"open": "screwdriver", "remove": "cutter", "install": "crimper", "test": "meter"}

var _trace: Dictionary
var _ctx: Dictionary


func before_each() -> void:
	_trace = Runner.json(C01.path_join("solution.json"))
	_ctx = Runner.build(C01, ["P1", "P2"], TOOLS)
	assert_true((_ctx["errors"] as Array).is_empty(), "C01 content loads: %s" % str(_ctx["errors"]))


func after_each() -> void:
	_ctx = {}


func test_V02_known_solution_completes_through_the_host() -> void:
	var ctx: Dictionary = Runner.build(C01, _trace["players"], _trace["tools"])
	var failures: Array[String] = Runner.run(ctx, _trace["steps"], int(_trace["pace_ticks_per_command"]))
	assert_eq(failures, [] as Array[String])
	assert_true((ctx["mission"] as MissionDirector).is_complete(), "mission complete")
	assert_true(int(ctx["now"]) <= int(_trace["max_ticks"]), "within %d ticks (took %d)" % [int(_trace["max_ticks"]), int(ctx["now"])])
	var st: Dictionary = ctx["grid"].canonical_state()
	for c: String in ["APT_E", "APT_W", "MARKET", "PUB", "WORKSHOP"]:
		assert_true(st["nodes"][c]["supplied"], "%s restored" % c)
	assert_eq(st["nodes"]["SIGN"]["enabled"], false, "the solution never needs the sign")


func test_SIM12_east_repair_refused_until_12_continuous_supplied_seconds() -> void:
	_generator_on_pump()
	assert_eq(_send("P1", "request_lock", "R_JE_TRUNK")["code"], "NO_ACCESS")
	Runner.ticks(_ctx, 60)
	_now("P1", "place_item", "GEN_PORTABLE", {"action": "stop"})  # interrupted at 6 s: the drain timer resets
	Runner.ticks(_ctx, 5)
	assert_false(_mission().is_latched("LATCH_PUMP_DRAIN"))
	_now("P1", "place_item", "GEN_PORTABLE", {"action": "start"})
	Runner.ticks(_ctx, 119)
	assert_false(_mission().is_latched("LATCH_PUMP_DRAIN"), "119 continuous ticks are not enough")
	assert_eq(_now("P1", "request_lock", "R_JE_TRUNK").get("code", ""), "NO_ACCESS")
	Runner.ticks(_ctx, 1)
	assert_true(_mission().is_latched("LATCH_PUMP_DRAIN"), "latches at 120 continuous ticks (12 s)")
	assert_true(_send("P1", "request_lock", "R_JE_TRUNK")["ok"], "east trunk reachable after the drain")


func test_SIM13_stopping_the_generator_after_the_drain_keeps_the_latch() -> void:
	_generator_on_pump()
	Runner.ticks(_ctx, 120)
	_gen("P1", "stop")
	_gen("P1", "disconnect", {"route": "E_TEMP_PUMP"})
	Runner.ticks(_ctx, 200)
	assert_true(_mission().is_latched("LATCH_PUMP_DRAIN"), "switching the pump off does not refill the basement")
	_repair("P1", "R_JE_TRUNK", "PANEL_JE", EAST_TOOLS)
	assert_true(_ctx["grid"].canonical_state()["nodes"]["PUB"]["supplied"], "mission remains solvable")


func test_SIM14_losing_supply_during_final_verification_resets_it() -> void:
	_all_repairs_done()
	Runner.ticks(_ctx, 90)
	assert_false(_mission().verified(), "9 s is not 10 s")
	assert_true(_now("P1", "toggle_switch", "SW_JE_BREAKER", {"value": true})["ok"], "east breaker opened by hand at 9 s")
	Runner.ticks(_ctx, 5)
	assert_true(_now("P1", "toggle_switch", "SW_JE_BREAKER", {"value": false})["ok"])
	Runner.ticks(_ctx, 99)
	assert_false(_mission().verified(), "the 10 s restart from zero; no premature completion")
	var evs: Array[Dictionary] = Runner.ticks(_ctx, 1)
	assert_true(_mission().verified())
	assert_eq(evs.filter(func(e: Dictionary) -> bool: return e["type"] == "verified").size(), 1)
	assert_eq(_extract("P1", "start")["code"], "EQUIPMENT_NOT_STOWED", "verified is not enough on its own")


func test_V02_generator_supply_never_counts_as_grid_restoration() -> void:
	_generator_on_pump()
	Runner.ticks(_ctx, 120)
	_gen("P1", "disconnect", {"route": "E_TEMP_PUMP"})
	assert_true(_gen("P1", "connect", {"route": "E_TEMP_PUB"})["ok"], "pub on the temporary generator (east trunk still broken)")
	_repair("P1", "R_JW_FUSE", "PANEL_JW", WEST_TOOLS)
	Runner.ticks(_ctx, 150)
	assert_true(_ctx["grid"].canonical_state()["nodes"]["PUB"]["supplied"])
	assert_false(_mission().verified(), "pub lit by the generator does not satisfy final grid supply")
	assert_eq(_row("OBJ_EAST")["status"] != "done", true)


func test_V02_optional_sign_never_blocks_progress() -> void:
	_all_repairs_done()
	assert_true(_send("P1", "toggle_switch", "SW_SIGN", {"value": true})["ok"], "a player switches the training load on")
	var evs: Array[Dictionary] = Runner.ticks(_ctx, 15)
	assert_true(evs.any(func(e: Dictionary) -> bool: return e["type"] == "trip" and e["breaker"] == "JE"), "14/12 trips the east feeder")
	assert_eq(_send("P1", "toggle_switch", "SW_JE_BREAKER", {"value": false})["grid_code"], "RESET_OVERLOADED")
	assert_true(_send("P1", "toggle_switch", "SW_SIGN", {"value": false})["ok"])
	assert_true(_send("P1", "toggle_switch", "SW_JE_BREAKER", {"value": false})["ok"], "recoverable: sign off, reset")
	_stow_and_extract(["P1", "P2"])
	assert_true(_mission().is_complete(), "contract completes; the sign is excluded from every requirement")


func test_MIS04_leaving_the_zone_cancels_and_any_player_can_cancel() -> void:
	_all_repairs_done()
	_stow()
	Runner.ticks(_ctx, 100)
	_zone("P1", true)
	assert_eq(_extract("P1", "start")["code"], "CREW_NOT_IN_ZONE", "P2 is connected and not at the van")
	_zone("P2", true)
	assert_true(_now("P1", "request_extract", "ZONE_VAN", {"action": "start"})["ok"])
	Runner.ticks(_ctx, 20)
	var evs: Array[Dictionary] = _zone("P2", false)
	assert_eq(evs[0]["reason"], "player_left_zone")
	_zone("P2", true)
	assert_true(_now("P2", "request_extract", "ZONE_VAN", {"action": "start"})["ok"], "countdown restarts from 5 s")
	Runner.ticks(_ctx, 49)
	assert_false(_mission().is_complete(), "4.9 s into a 5 s countdown")
	var cancel: Dictionary = _now("P2", "request_extract", "ZONE_VAN", {"action": "cancel"})
	assert_true(cancel["ok"], "any player can cancel")
	Runner.ticks(_ctx, 10)
	assert_false(_mission().is_complete(), "no forced partial departure")


func test_V02_disconnected_players_are_not_required_for_extraction() -> void:
	_all_repairs_done()
	_stow()
	Runner.ticks(_ctx, 100)
	_zone("P1", true)
	(_ctx["host"]).remove(_ctx["peers"]["P2"])
	assert_true(_extract("P1", "start")["ok"], "P2 left the session")
	var evs: Array[Dictionary] = Runner.ticks(_ctx, 50)
	assert_true(evs.any(func(e: Dictionary) -> bool: return e["type"] == "mission_complete"))


func test_V02_countdown_cancels_if_equipment_is_taken_out_again() -> void:
	_all_repairs_done()
	_stow()
	Runner.ticks(_ctx, 100)
	_zone("P1", true)
	_zone("P2", true)
	assert_true(_now("P1", "request_extract", "ZONE_VAN", {"action": "start"})["ok"])
	assert_true(_now("P1", "place_item", "GEN_PORTABLE", {"action": "pickup"})["ok"])
	var evs: Array[Dictionary] = Runner.ticks(_ctx, 1)
	assert_true(evs.any(func(e: Dictionary) -> bool: return e["type"] == "countdown_cancelled" and e["reason"] == "equipment_not_stowed"))


func test_V02_objectives_show_at_most_three_and_never_name_the_repair() -> void:
	var rows: Array[Dictionary] = _mission().objectives()
	assert_eq(rows.size(), 6)
	assert_eq(rows.filter(func(r: Dictionary) -> bool: return r["visible"]).size(), 3, "at most three rows (blueprint p.11)")
	assert_eq(_row("OBJ_WEST")["status"], "active")
	for r: Dictionary in rows:
		for leak: String in ["fuse", "trunk", "isolate", "breaker", "replace"]:
			assert_false(str(r["text_key"]).contains(leak), "%s must not reveal the exact repair (pillar 1)" % r["id"])
	_repair("P1", "R_JW_FUSE", "PANEL_JW", WEST_TOOLS)
	assert_eq(_row("OBJ_WEST")["status"], "done")


func test_V02_mission_state_is_part_of_the_authoritative_hash() -> void:
	var before: String = _ctx["host"].state_hash()
	_generator_on_pump()
	Runner.ticks(_ctx, 120)
	assert_ne(_ctx["host"].state_hash(), before)
	assert_true((_ctx["host"].authoritative_state() as Dictionary).has("mission"))


func test_V02_bad_mission_content_rejected() -> void:
	var def: Dictionary = Runner.json(C01.path_join("mission.json"))
	def["required_consumers"] = ["APT_W", "GRID"]
	var m: MissionDirector = MissionDirector.new()
	assert_eq(m.load_definition(def, _ctx["grid"], _ctx["interaction"], _ctx["equipment"])[0]["code"], "BAD_MISSION")
	def = Runner.json(C01.path_join("mission.json"))
	def["excluded_loads"] = ["PUB"]
	assert_eq(MissionDirector.new().load_definition(def, _ctx["grid"], _ctx["interaction"], _ctx["equipment"])[0]["code"], "BAD_MISSION")


# ---------- helpers ----------

func _mission() -> MissionDirector:
	return _ctx["mission"]


## Paced send: one tick after the command (human speed, inside the rate limit). Used for setup sequences.
func _send(player: String, intent: String, entity: String, payload: Dictionary = {}) -> Dictionary:
	var r: Dictionary = Runner.send(_ctx, player, intent, entity, payload)
	Runner.ticks(_ctx, 1)
	return r


## Unpaced send for timing-critical assertions: no tick passes.
func _now(player: String, intent: String, entity: String, payload: Dictionary = {}) -> Dictionary:
	return Runner.send(_ctx, player, intent, entity, payload)


func _gen(player: String, action: String, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action": action}
	payload.merge(extra)
	return _send(player, "place_item", "GEN_PORTABLE", payload)


func _extract(player: String, action: String) -> Dictionary:
	return _send(player, "request_extract", "ZONE_VAN", {"action": action})


func _zone(player: String, inside: bool) -> Array[Dictionary]:
	return _ctx["host"].set_in_zone(player, "ZONE_VAN", inside)


func _row(id: String) -> Dictionary:
	for r: Dictionary in _mission().objectives():
		if r["id"] == id:
			return r
	return {}


func _repair(player: String, rid: String, panel: String, tools: Dictionary) -> void:
	assert_true(_send(player, "request_lock", rid)["ok"], "lock %s" % rid)
	assert_true(_send(player, "inspect", panel)["ok"])
	for step: String in ["diagnose", "isolate", "open", "remove", "install", "close", "test", "restore"]:
		_send(player, "equip", rid, {"tool": tools.get(step, "")})
		var r: Dictionary = _send(player, "repair_step", rid, {"step": step})
		assert_true(r["ok"], "%s %s: %s" % [rid, step, str(r)])


func _generator_on_pump() -> void:
	assert_true(_gen("P1", "pickup")["ok"])
	assert_true(_gen("P1", "place", {"anchor": "PAD_PUMP"})["ok"])
	assert_true(_gen("P1", "connect", {"route": "E_TEMP_PUMP"})["ok"])
	assert_true(_gen("P1", "start")["ok"])


func _all_repairs_done() -> void:
	_repair("P1", "R_JW_FUSE", "PANEL_JW", WEST_TOOLS)
	_generator_on_pump()
	Runner.ticks(_ctx, 120)
	_gen("P1", "stop")
	_repair("P2", "R_JE_TRUNK", "PANEL_JE", EAST_TOOLS)


func _stow() -> void:
	_gen("P1", "disconnect", {"route": "E_TEMP_PUMP"})
	_gen("P1", "disconnect", {"route": "E_TEMP_PUB"})
	assert_true(_gen("P1", "pickup")["ok"])
	assert_true(_gen("P1", "place", {"anchor": "VAN_BAY"})["ok"])


func _stow_and_extract(players: Array) -> void:
	_stow()
	Runner.ticks(_ctx, 100)
	for p: Variant in players:
		_zone(str(p), true)
	assert_true(_extract("P1", "start")["ok"])
	Runner.ticks(_ctx, 50)
