extends "res://tests/test_case.gd"
## V03: recovery routes. Out-of-bounds players, lost or misplaced items and guest disconnects cannot make C01 unsolvable.
## Each scenario injects an adverse event at a different point, then _finish() completes the contract from whatever
## state is left, using only normal player intents. If any scenario cannot finish, recovery has a hole.

const Runner := preload("res://tests/support/solution_runner.gd")
const MissionDirector := preload("res://scripts/simulation/mission_director.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const C01: String = "res://content/contracts/c01_alder_street"
const TOOLS: Array[String] = ["screwdriver", "puller", "cutter", "crimper", "meter"]
const REPAIRS: Dictionary = {
	"R_JW_FUSE": {"panel": "PANEL_JW", "tools": {"open": "screwdriver", "remove": "puller", "install": "puller", "test": "meter"}},
	"R_JE_TRUNK": {"panel": "PANEL_JE", "tools": {"open": "screwdriver", "remove": "cutter", "install": "crimper", "test": "meter"}},
}
const GEN: String = "GEN_PORTABLE"

var _ctx: Dictionary
var _positions: Dictionary = {}  # player -> Vector3i cm (host movement stand-in)


func before_each() -> void:
	_ctx = Runner.build(C01, ["P1", "P2"], TOOLS)
	assert_true((_ctx["errors"] as Array).is_empty(), str(_ctx["errors"]))
	_ctx["host"].set_position_provider(func(p: String) -> Vector3i: return _positions.get(p, Vector3i.ZERO))


func after_each() -> void:
	_ctx = {}


func test_V03_carrier_disconnect_mid_carry_stays_solvable() -> void:
	_gen("P2", "pickup")
	_ctx["host"].remove(_ctx["peers"]["P2"])
	assert_eq(_ctx["equipment"].anchor_of(GEN), "VAN_BAY", "generator back on the pad it was taken from")
	_finish("P1")


func test_V03_guest_drops_while_holding_a_half_done_repair() -> void:
	_lock_and_walk("P2", "R_JW_FUSE", "remove")  # fuse removed, replacement not installed yet
	_ctx["host"].remove(_ctx["peers"]["P2"])
	assert_eq(_ctx["interaction"].lock_owner("R_JW_FUSE"), "", "lock released")
	assert_eq(_ctx["interaction"].repair_state("R_JW_FUSE"), "component_removed", "durable progress kept")
	assert_eq(_ctx["interaction"].supply("FUSE_W"), 1, "the only replacement is still available")
	_finish("P1")


func test_V03_stranded_player_recovery_keeps_network_and_returns_item() -> void:
	_lock_and_walk("P1", "R_JW_FUSE", "restore")
	_deploy_pump()
	Runner.ticks(_ctx, 40)
	_gen("P1", "stop")
	_gen("P1", "disconnect", {"route": "E_TEMP_PUMP"})
	_gen("P1", "pickup")
	_lock("P1", "R_JE_TRUNK", "NO_ACCESS")
	var grid_before: Dictionary = _ctx["grid"].canonical_state()
	var r: Dictionary = _send("P1", "recover_self", "P1", {})
	assert_true(r["ok"])
	assert_true((r["events"] as Array).any(func(e: Dictionary) -> bool: return e["type"] == "player_recovered"))
	assert_eq(_ctx["equipment"].anchor_of(GEN), "PAD_PUMP", "carried generator returns to its last pad")
	assert_eq(_ctx["grid"].canonical_state()["nodes"], grid_before["nodes"], "recovery never resets the network")
	assert_eq(_ctx["interaction"].repair_state("R_JW_FUSE"), "restored", "permanent repair untouched")
	_finish("P1")


func test_V03_player_recovery_releases_locks_without_losing_parts() -> void:
	_lock_and_walk("P1", "R_JW_FUSE", "remove")
	var r: Dictionary = _send("P1", "recover_self", "P1", {})
	assert_true((r["events"] as Array).any(func(e: Dictionary) -> bool: return e.get("reason") == "player_recovered"))
	assert_eq(_ctx["interaction"].lock_owner("R_JW_FUSE"), "")
	assert_eq(_ctx["interaction"].supply("FUSE_W"), 1)
	_finish("P2")


func test_V03_dropped_item_snaps_to_nearest_free_anchor() -> void:
	_gen("P1", "pickup")
	_positions["P1"] = Vector3i(6440, 0, 1345)  # next to the pump-house store (V01 graybox) (an exact tie would go to the lower ID)
	var r: Dictionary = _send("P1", "place_item", GEN, {"action": "drop"})
	assert_eq(r["anchor"], "STORE_PUMP_HOUSE", "nearest by integer distance")
	_gen("P1", "pickup")
	_positions["P1"] = Vector3i(-90000, -5000, 70000)  # fell out of the world
	r = _send("P1", "place_item", GEN, {"action": "drop"})
	assert_eq(r["anchor"], "VAN_BAY", "an out-of-bounds drop still lands on a valid anchor")
	_finish("P1")


func test_V03_drop_payload_cannot_choose_the_position() -> void:
	_gen("P1", "pickup")
	_positions["P1"] = Vector3i(800, 0, 1300)  # host says: at the van (V01 VAN_BAY)
	var r: Dictionary = _send("P1", "place_item", GEN, {"action": "drop", "position_cm": "6250,0,1600"})
	assert_eq(r["anchor"], "VAN_BAY", "client-claimed positions are ignored")
	assert_eq(_send("P2", "place_item", GEN, {"action": "drop"})["code"], "NOT_CARRIER")


func test_V03_out_of_range_carrier_can_still_drop() -> void:
	_gen("P1", "pickup")
	_positions["P1"] = Vector3i(-90000, -5000, 70000)  # stranded far from every interaction target
	_ctx["host"]._range_check = func(_p: String, _e: String) -> bool: return false
	var r: Dictionary = _send("P1", "place_item", GEN, {"action": "drop"})
	assert_true(r["ok"], "a carrier never needs reach to let go: %s" % str(r))
	assert_eq(r["anchor"], "VAN_BAY", "the drop still snaps to a valid anchor")
	assert_eq(_send("P2", "place_item", GEN, {"action": "drop"})["code"], "NOT_CARRIER", "a non-carrier still cannot drop")
	assert_eq(_send("P1", "place_item", GEN, {"action": "pickup"})["code"], "NOT_IN_RANGE", "other actions still need reach")
	_ctx["host"]._range_check = func(_p: String, _e: String) -> bool: return true
	_finish("P1")


func test_V03_van_recovery_of_the_generator_mid_drain_stays_solvable() -> void:
	_deploy_pump()
	Runner.ticks(_ctx, 60)
	assert_true(_gen("P2", "recover")["ok"], "any player can use the van menu")
	assert_false(_ctx["mission"].is_latched("LATCH_PUMP_DRAIN"), "drain not finished, nothing latched")
	assert_eq(_ctx["equipment"].anchor_of(GEN), "VAN_BAY")
	_finish("P1")


func test_V03_wrong_attempts_never_destroy_the_last_replacement() -> void:
	_lock("P1", "R_JW_FUSE")
	_send("P1", "inspect", "PANEL_JW", {})
	for step: String in ["install", "remove", "open"]:
		assert_false(_send("P1", "repair_step", "R_JW_FUSE", {"step": step})["ok"], "%s out of order is refused" % step)
	assert_eq(_ctx["interaction"].supply("FUSE_W"), 1)
	_finish("P1")


func test_V03_every_stage_survives_a_guest_disconnect() -> void:
	# property check: drop P2 after each prefix of the known solution; the remaining crew always finishes
	var trace: Dictionary = Runner.json(C01.path_join("solution.json"))
	var steps: Array = trace["steps"]
	var cuts: Array[int] = [5, 15, 22, 27, 35, 45, 52]
	for cut: int in cuts:
		_ctx = Runner.build(C01, ["P1", "P2"], TOOLS)
		var prefix: Array = []
		for s: Dictionary in steps.slice(0, cut):
			var t: Dictionary = s.duplicate(true)
			if t.has("as"):
				t["as"] = "P2"  # the guest did this part of the work
			if t.has("expect_events"):
				t.erase("expect_events")
			prefix.append(t)
		Runner.run(_ctx, prefix, 1)
		_ctx["host"].remove(_ctx["peers"]["P2"])
		_finish("P1", "cut at step %d" % cut)


# ---------- generic completion from any state ----------

## Completes C01 from the current state with one player, using normal intents only. Asserts completion.
func _finish(player: String, label: String = "") -> void:
	var inter: Interaction = _ctx["interaction"]
	var mission: MissionDirector = _ctx["mission"]
	_send(player, "toggle_switch", "SW_SIGN", {"value": false})
	if inter.repair_state("R_JW_FUSE") != "restored":
		_repair_from_current(player, "R_JW_FUSE")
	if not mission.is_latched("LATCH_PUMP_DRAIN"):
		_bring_generator_to(player, "PAD_PUMP")
		_gen(player, "disconnect", {"route": "E_TEMP_PUB"})
		_gen(player, "connect", {"route": "E_TEMP_PUMP"})
		_gen(player, "reset_breaker")
		_gen(player, "start")
		Runner.ticks(_ctx, 120)
	if inter.repair_state("R_JE_TRUNK") != "restored":
		_repair_from_current(player, "R_JE_TRUNK")
	for breaker: String in ["SW_JW_BREAKER", "SW_JE_BREAKER"]:
		_send(player, "toggle_switch", breaker, {"value": false})
	_bring_generator_to(player, "VAN_BAY")
	Runner.ticks(_ctx, 100)
	for p: String in _ctx["peers"]:
		if _ctx["host"].member(_ctx["peers"][p]) != "":
			_ctx["host"].set_in_zone(p, "ZONE_VAN", true)
	var start: Dictionary = _send(player, "request_extract", "ZONE_VAN", {"action": "start"})
	assert_true(start["ok"], "%s extraction starts: %s" % [label, str(start)])
	Runner.ticks(_ctx, 50)
	assert_true(mission.is_complete(), "%s C01 still completes" % label)


func _repair_from_current(player: String, rid: String) -> void:
	var r: Dictionary = REPAIRS[rid]
	_lock(player, rid)
	_send(player, "inspect", r["panel"], {})
	var start: int = Interaction.STATES.find(_ctx["interaction"].repair_state(rid))
	for i: int in range(start, Interaction.STEPS.size()):
		var step: String = Interaction.STEPS[i]
		_send(player, "equip", rid, {"tool": (r["tools"] as Dictionary).get(step, "")})
		var res: Dictionary = _send(player, "repair_step", rid, {"step": step})
		assert_true(res["ok"], "%s %s from recovered state: %s" % [rid, step, str(res)])


func _bring_generator_to(player: String, anchor: String) -> void:
	var eq: Variant = _ctx["equipment"]
	if eq.anchor_of(GEN) == anchor:
		return
	if eq.carrier_of(GEN) != "" and eq.carrier_of(GEN) != player:
		_gen(player, "recover")  # someone else is holding it: the van menu always works
	_gen(player, "stop")
	_gen(player, "disconnect", {"route": "E_TEMP_PUMP"})
	_gen(player, "disconnect", {"route": "E_TEMP_PUB"})
	if eq.carrier_of(GEN) != player:
		assert_true(_gen(player, "pickup")["ok"], "pick up the generator")
	assert_true(_gen(player, "place", {"anchor": anchor})["ok"], "place at %s" % anchor)


# ---------- helpers ----------

func _send(player: String, intent: String, entity: String, payload: Dictionary) -> Dictionary:
	var r: Dictionary = Runner.send(_ctx, player, intent, entity, payload)
	Runner.ticks(_ctx, 1)
	return r


func _gen(player: String, action: String, extra: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = {"action": action}
	payload.merge(extra)
	return _send(player, "place_item", GEN, payload)


func _lock(player: String, rid: String, want: String = "ok") -> void:
	var r: Dictionary = _send(player, "request_lock", rid, {})
	assert_eq("ok" if r["ok"] else str(r.get("code")), want, "lock %s" % rid)


func _lock_and_walk(player: String, rid: String, last: String) -> void:
	_lock(player, rid)
	_send(player, "inspect", REPAIRS[rid]["panel"], {})
	for i: int in Interaction.STEPS.find(last) + 1:
		var step: String = Interaction.STEPS[i]
		_send(player, "equip", rid, {"tool": (REPAIRS[rid]["tools"] as Dictionary).get(step, "")})
		assert_true(_send(player, "repair_step", rid, {"step": step})["ok"], "%s %s" % [rid, step])


func _deploy_pump() -> void:
	assert_true(_gen("P1", "pickup")["ok"])
	assert_true(_gen("P1", "place", {"anchor": "PAD_PUMP"})["ok"])
	assert_true(_gen("P1", "connect", {"route": "E_TEMP_PUMP"})["ok"])
	assert_true(_gen("P1", "start")["ok"])
