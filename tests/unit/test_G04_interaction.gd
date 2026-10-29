extends "res://tests/test_case.gd"
## G04: repair state machine, locks, isolation preconditions, durable cancel, supplies consumed once, target selection.
## Logic-level parts of NET01/NET02/SIM12; real clients and transport are F03/G07.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const TargetSelector := preload("res://scripts/interaction/target_selector.gd")
const Cases := preload("res://tests/support/grid_cases.gd")
const C01: String = "res://content/contracts/c01_alder_street/"
const ALL_TOOLS: Array[String] = ["screwdriver", "puller", "cutter", "crimper", "meter"]
const WEST_TOOLS: Dictionary = {"open": "screwdriver", "remove": "puller", "install": "puller", "test": "meter"}
const EAST_TOOLS: Dictionary = {"open": "screwdriver", "remove": "cutter", "install": "crimper", "test": "meter"}

var _grid: PowerGrid
var _meter: MeterModel
var _svc: Interaction


func before_each() -> void:
	_grid = PowerGrid.new()
	_grid.load_definition(Cases.definition_for(Cases.load_doc(), {}, false))
	_meter = MeterModel.new()
	_meter.load_definition(_json(C01 + "meter.json"), _grid)
	_svc = Interaction.new()
	var errs: Array[Dictionary] = _svc.load_definition(_json("res://content/interaction.json"), _json(C01 + "repairs.json"), _grid, _meter)
	assert_true(errs.is_empty(), "C01 repairs load: %s" % str(errs))
	_svc.join("P1", ALL_TOOLS)
	_svc.join("P2", ALL_TOOLS)


func test_G04_full_west_repair_restores_9_pu_and_releases_lock() -> void:
	_lock("P1", "R_JW_FUSE")
	_walk("P1", "R_JW_FUSE", WEST_TOOLS, "restore")
	assert_eq(_svc.repair_state("R_JW_FUSE"), "restored")
	assert_eq(_svc.lock_owner("R_JW_FUSE"), "", "lock released on completion")
	assert_eq(_svc.supply("FUSE_W"), 0)
	var st: Dictionary = _grid.canonical_state()
	assert_eq(st["nodes"]["APT_W"]["supplied"], true)
	assert_eq(st["nodes"]["MARKET"]["supplied"], true)
	assert_eq(st["nodes"]["GRID"]["load"], 9)


func test_G04_live_repair_refused_and_nothing_changes() -> void:
	_lock("P1", "R_JW_FUSE")
	_walk("P1", "R_JW_FUSE", WEST_TOOLS, "open")  # diagnosed, isolated, opened
	# someone closes the isolator mid-repair: the panel is live again
	assert_true(_grid.apply({"op": "set", "id": "JW", "field": "isolated", "value": false})["ok"])
	var before_grid: String = _grid.canonical_string()
	var before: Dictionary = _svc.canonical_state()
	_equip("P1", "puller")
	var res: Dictionary = _step("P1", "R_JW_FUSE", "remove")
	assert_eq(res["code"], "ISOLATE_FIRST")
	assert_eq(res["ids"], ["JW", "R_JW_FUSE"], "reason points at the live junction")
	assert_eq(res["key"], "interaction.refused.isolate_first")
	assert_eq(_svc.canonical_state(), before, "refused step changes no repair state, supply or revision")
	assert_eq(_grid.canonical_string(), before_grid)


func test_G04_steps_follow_the_state_machine_order() -> void:
	_lock("P1", "R_JW_FUSE")
	var res: Dictionary = _step("P1", "R_JW_FUSE", "diagnose")
	assert_eq(res["code"], "NOT_INSPECTED", "diagnosis needs meter evidence")
	_meter.inspect("PANEL_JW", _grid)
	assert_true(_step("P1", "R_JW_FUSE", "diagnose")["ok"])
	res = _step("P1", "R_JW_FUSE", "open")
	assert_eq(res["code"], "WRONG_STEP", "cannot skip isolation")
	assert_true(res["message"].contains("isolate"))
	assert_eq(_svc.repair_state("R_JW_FUSE"), "diagnosed")


func test_NET01_logic_one_lock_owner_and_others_see_the_worker() -> void:
	assert_true(_svc.handle("P1", {"type": "request_lock", "repair": "R_JW_FUSE", "in_range": true})["ok"])
	var res: Dictionary = _svc.handle("P2", {"type": "request_lock", "repair": "R_JW_FUSE", "in_range": true})
	assert_eq(res["code"], "LOCKED_BY_OTHER")
	assert_true((res["ids"] as Array).has("P1"), "refusal names who is working")
	assert_eq(_svc.lock_owner("R_JW_FUSE"), "P1")
	assert_eq(_step("P2", "R_JW_FUSE", "diagnose")["code"], "NOT_LOCK_OWNER")


func test_NET02_logic_duplicate_install_consumes_replacement_once() -> void:
	_lock("P1", "R_JW_FUSE")
	_walk("P1", "R_JW_FUSE", WEST_TOOLS, "install")
	var rev: int = _svc.revision
	var dup: Dictionary = _step("P1", "R_JW_FUSE", "install")
	assert_eq(dup["ok"], true)
	assert_eq(dup["duplicate"], true)
	assert_eq(_svc.supply("FUSE_W"), 0, "consumed exactly once")
	assert_eq(_svc.revision, rev, "duplicate is not a state transition")
	assert_eq(_svc.repair_state("R_JW_FUSE"), "replacement_installed")


func test_G04_disconnect_releases_lock_and_keeps_progress() -> void:
	_lock("P1", "R_JW_FUSE")
	_walk("P1", "R_JW_FUSE", WEST_TOOLS, "open")
	var events: Array[Dictionary] = _svc.disconnect_player("P1")
	assert_eq(events.size(), 1)
	assert_eq(events[0]["reason"], "disconnect")
	assert_eq(events[0]["state"], "opened")
	assert_eq(_svc.lock_owner("R_JW_FUSE"), "")
	_lock("P2", "R_JW_FUSE")
	_equip("P2", "puller")
	assert_true(_step("P2", "R_JW_FUSE", "remove")["ok"], "remaining crew continues from the durable state")


func test_G04_cancel_keeps_last_durable_state() -> void:
	_lock("P1", "R_JW_FUSE")
	_walk("P1", "R_JW_FUSE", WEST_TOOLS, "remove")
	var res: Dictionary = _svc.handle("P1", {"type": "release", "repair": "R_JW_FUSE"})
	assert_eq(res["events"][0]["reason"], "cancel")
	assert_eq(_svc.repair_state("R_JW_FUSE"), "component_removed")
	assert_eq(_grid.canonical_state()["nodes"]["JW"]["isolated"], true, "cancel does not undo isolation")


func test_G04_heartbeat_timeout_releases_after_2_s() -> void:
	_svc.tick(100)
	_lock("P1", "R_JW_FUSE")
	assert_eq(_svc.tick(115).size(), 0)
	assert_true(_svc.handle("P1", {"type": "heartbeat", "repair": "R_JW_FUSE"})["ok"])
	assert_eq(_svc.tick(134).size(), 0, "heartbeat at 115 keeps the lock until 135")
	var events: Array[Dictionary] = _svc.tick(135)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["reason"], "heartbeat_timeout")
	assert_eq(_svc.lock_owner("R_JW_FUSE"), "")


func test_G04_out_of_range_refused_and_releases() -> void:
	assert_eq(_svc.handle("P1", {"type": "request_lock", "repair": "R_JW_FUSE", "in_range": false})["code"], "NOT_IN_RANGE")
	_lock("P1", "R_JW_FUSE")
	_meter.inspect("PANEL_JW", _grid)
	assert_eq(_svc.handle("P1", {"type": "repair_step", "repair": "R_JW_FUSE", "step": "diagnose", "in_range": false})["code"], "NOT_IN_RANGE")
	var events: Array[Dictionary] = _svc.left_range("P1", "R_JW_FUSE")
	assert_eq(events[0]["reason"], "out_of_range")


func test_G04_wrong_tool_refused_without_change() -> void:
	_lock("P1", "R_JW_FUSE")
	_walk("P1", "R_JW_FUSE", WEST_TOOLS, "isolate")
	_equip("P1", "meter")
	var res: Dictionary = _step("P1", "R_JW_FUSE", "open")
	assert_eq(res["code"], "MISSING_TOOL")
	assert_true(res["message"].contains("screwdriver"))
	assert_eq(_svc.repair_state("R_JW_FUSE"), "isolated")
	_svc.join("P3", [] as Array[String])
	assert_eq(_svc.handle("P3", {"type": "equip", "tool": "screwdriver"})["code"], "MISSING_TOOL")
	assert_eq(_svc.handle("NOBODY", {"type": "equip", "tool": ""})["code"], "UNKNOWN_PLAYER")


func test_SIM12_logic_east_repair_refused_until_pump_house_access() -> void:
	var res: Dictionary = _svc.handle("P1", {"type": "request_lock", "repair": "R_JE_TRUNK", "in_range": true})
	assert_eq(res["code"], "NO_ACCESS")
	_svc.set_access("PUMP_HOUSE_DRAINED", true)
	_lock("P1", "R_JE_TRUNK")
	_walk("P1", "R_JE_TRUNK", EAST_TOOLS, "restore")
	assert_eq(_grid.canonical_state()["edges"]["E_GRID_JE"]["flow"], 11)


func test_G04_restore_refused_on_dual_supply_stays_isolated() -> void:
	_svc.set_access("PUMP_HOUSE_DRAINED", true)
	for cmd: Dictionary in [{"op": "set", "id": "E_TEMP_PUB", "field": "enabled", "value": true},
			{"op": "set", "id": "GEN", "field": "online", "value": true}]:
		assert_true(_grid.apply(cmd)["ok"])
	_lock("P1", "R_JE_TRUNK")
	_walk("P1", "R_JE_TRUNK", EAST_TOOLS, "test")
	var res: Dictionary = _step("P1", "R_JE_TRUNK", "restore")
	assert_eq(res["code"], "GRID_REFUSED")
	assert_eq(res["grid_code"], "DUAL_SUPPLY")
	assert_true((res["ids"] as Array).has("PUB"), "points at the conflicting tie")
	assert_eq(_svc.repair_state("R_JE_TRUNK"), "tested")
	assert_eq(_grid.canonical_state()["nodes"]["JE"]["isolated"], true)


func test_G04_invalid_repair_content_rejected() -> void:
	var def: Dictionary = _json(C01 + "repairs.json")
	(def["repairs"][0]["hold_ticks"] as Dictionary)["install"] = 13
	var svc: Interaction = Interaction.new()
	var errs: Array[Dictionary] = svc.load_definition(_json("res://content/interaction.json"), def, _grid, _meter)
	assert_eq(errs.size(), 1)
	assert_eq(errs[0]["code"], "HOLD_TOO_LONG", "no hold longer than 1.2 s")
	def = _json(C01 + "repairs.json")
	def["repairs"][0]["isolate"] = "PUB"
	assert_eq(Interaction.new().load_definition(_json("res://content/interaction.json"), def, _grid, _meter)[0]["code"], "BAD_REPAIR")


func test_G04_target_selector_ray_cone_reach_and_order() -> void:
	var tuning: Dictionary = _json("res://content/interaction.json")
	var reach: float = float(tuning["ray_length_cm"]) / 100.0
	var cone: float = float(tuning["aim_assist_cone_deg"])
	var panel := {"id": "PANEL_JW", "position": Vector3(0, 0, -2), "radius": 0.2}
	var near_cone := {"id": "PANEL_JE", "position": Vector3(0.15, 0, -1.8), "radius": 0.05}
	var far := {"id": "PANEL_GRID", "position": Vector3(0, 0, -3), "radius": 0.2}
	var cands: Array = [near_cone, far, panel]
	assert_eq(TargetSelector.select(Vector3.ZERO, Vector3.FORWARD, cands, reach, cone), "PANEL_JW", "ray hit beats cone match")
	var rev: Array = cands.duplicate()
	rev.reverse()
	assert_eq(TargetSelector.select(Vector3.ZERO, Vector3.FORWARD, rev, reach, cone), "PANEL_JW", "order independent")
	assert_eq(TargetSelector.select(Vector3.ZERO, Vector3.FORWARD, [near_cone, far], reach, cone), "PANEL_JE", "assist cone")
	assert_eq(TargetSelector.select(Vector3.ZERO, Vector3.FORWARD, [far], reach, cone), "", "beyond 2.3 m")
	assert_eq(TargetSelector.select(Vector3.ZERO, Vector3.BACK, cands, reach, cone), "", "behind the player")


func test_G04_interaction_service_is_pure() -> void:
	for path: String in ["res://scripts/interaction/interaction_service.gd", "res://scripts/interaction/target_selector.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		for forbidden: String in ["get_node", "get_tree", "Engine.", "extends Node", "OS.", "Time."]:
			assert_false(src.contains(forbidden), "%s must not use %s" % [path, forbidden])
	assert_ne(PowerGrid.serialize(_svc.canonical_state()), "")


# ---------- helpers ----------

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _lock(player: String, repair: String) -> void:
	var res: Dictionary = _svc.handle(player, {"type": "request_lock", "repair": repair, "in_range": true})
	assert_true(res["ok"], "%s lock %s: %s" % [player, repair, str(res)])


func _equip(player: String, tool: String) -> void:
	assert_true(_svc.handle(player, {"type": "equip", "tool": tool})["ok"])


func _step(player: String, repair: String, step: String) -> Dictionary:
	return _svc.handle(player, {"type": "repair_step", "repair": repair, "step": step, "in_range": true})


## Runs every step from the current state up to and including `last`, inspecting and equipping as needed.
func _walk(player: String, repair: String, tools: Dictionary, last: String) -> void:
	var panel: String = "PANEL_JW" if repair == "R_JW_FUSE" else "PANEL_JE"
	var start: int = Interaction.STATES.find(_svc.repair_state(repair))
	for i: int in range(start, Interaction.STEPS.find(last) + 1):
		var step: String = Interaction.STEPS[i]
		if step == "diagnose":
			_meter.inspect(panel, _grid)
		_equip(player, tools.get(step, ""))
		var res: Dictionary = _step(player, repair, step)
		assert_true(res["ok"], "%s %s: %s" % [repair, step, str(res)])
