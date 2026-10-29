extends "res://tests/test_case.gd"
## G05: portable generator placement, route toggles, 6 PU source, unsafe source tie refused before mutation.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const Cases := preload("res://tests/support/grid_cases.gd")
const C01: String = "res://content/contracts/c01_alder_street/"
const GEN: String = "GEN_PORTABLE"

var _doc: Dictionary
var _grid: PowerGrid
var _meter: MeterModel
var _eq: Equipment


func before_each() -> void:
	_doc = Cases.load_doc()
	_grid = PowerGrid.new()
	_grid.load_definition(Cases.definition_for(_doc, {}, false))
	_meter = MeterModel.new()
	_meter.load_definition(_json(C01 + "meter.json"), _grid)
	_eq = Equipment.new()
	var errs: Array[Dictionary] = _eq.load_definition(_json(C01 + "equipment.json"), _grid, _meter)
	assert_true(errs.is_empty(), "C01 equipment loads: %s" % str(errs))


func test_G05_pump_only_runs_on_6_pu_generator() -> void:
	_deploy_to_pump_pad()
	_ok(_do("connect", {"route": "E_TEMP_PUMP"}))
	_ok(_do("start"))
	var st: Dictionary = _grid.canonical_state()
	assert_eq(st["nodes"]["GEN"]["capacity"], 6)
	assert_eq(st["nodes"]["GEN"]["load"], 4)
	assert_eq(st["nodes"]["PUMP"]["supplied"], true)
	assert_eq(_grid.overloads(), [] as Array[String])


func test_G05_pub_only_runs_on_generator() -> void:
	_deploy_to_pump_pad()
	_ok(_do("connect", {"route": "E_TEMP_PUB"}))
	_ok(_do("start"))
	assert_eq(_grid.canonical_state()["nodes"]["PUB"]["supplied"], true)
	assert_eq(_grid.canonical_state()["nodes"]["GEN"]["load"], 4)


func test_SIM04_both_routes_overload_and_trip_then_reset_after_unplugging() -> void:
	_deploy_to_pump_pad()
	_ok(_do("connect", {"route": "E_TEMP_PUMP"}))
	_ok(_do("connect", {"route": "E_TEMP_PUB"}))
	_ok(_do("start"))
	assert_eq(_grid.overloads(), ["E_GEN_TEMP", "GEN"] as Array[String], "8/6 PU")
	var trips: Array[Dictionary] = []
	for _i: int in 15:
		trips.append_array(_grid.step())
	assert_eq(trips.size(), 1)
	assert_eq(_do("reset_breaker")["grid_code"], "RESET_OVERLOADED", "reset refused while both are plugged in")
	_ok(_do("disconnect", {"route": "E_TEMP_PUB"}))
	_ok(_do("reset_breaker"))
	assert_eq(_grid.canonical_state()["nodes"]["PUMP"]["supplied"], true)


func test_G05_unsafe_source_tie_refused_before_mutation() -> void:
	# pub already on grid supply after the east repair; plugging the generator into the pub must be refused
	for cmd: Dictionary in Cases.expand(["@repair_west", "@repair_east"], _doc["macros"]):
		var clean: Dictionary = cmd.duplicate()
		clean.erase("expect")
		_grid.apply(clean)
	_deploy_to_pump_pad()
	_ok(_do("start"))
	var grid_before: String = _grid.canonical_string()
	var eq_before: Dictionary = _eq.canonical_state()
	var res: Dictionary = _do("connect", {"route": "E_TEMP_PUB"})
	assert_eq(res["code"], "GRID_REFUSED")
	assert_eq(res["grid_code"], "DUAL_SUPPLY")
	assert_eq(res["ids"], ["E_JE_PUB", "E_TEMP_PUB", GEN, "PUB"], "names the conflicting tie")
	assert_eq(_grid.canonical_string(), grid_before, "grid unchanged")
	assert_eq(_eq.canonical_state(), eq_before, "equipment unchanged")


func test_G05_generator_only_runs_when_placed_at_a_work_pad() -> void:
	assert_eq(_do("start")["code"], "PLACE_FIRST", "in the van")
	_ok(_do("pickup"))
	assert_eq(_do("start")["code"], "PLACE_FIRST", "while carried")
	assert_eq(_do("connect", {"route": "E_TEMP_PUMP"})["code"], "PLACE_FIRST")
	_ok(_do("place", {"anchor": "PAD_PUMP"}))
	assert_eq(_do("connect", {"route": "E_JE_PUB"})["code"], "NO_SOCKET", "only the pad's own sockets")


func test_G05_running_or_cabled_generator_cannot_be_picked_up() -> void:
	_deploy_to_pump_pad()
	_ok(_do("connect", {"route": "E_TEMP_PUMP"}))
	assert_eq(_do("pickup")["code"], "DISCONNECT_FIRST")
	_ok(_do("start"))
	assert_eq(_do("pickup")["code"], "STOP_FIRST")
	_ok(_do("stop"))
	_ok(_do("disconnect", {"route": "E_TEMP_PUMP"}))
	_ok(_do("pickup"))
	assert_eq(_eq.handle("P2", {"type": "pickup", "item": GEN, "in_range": true})["code"], "CARRIED_BY_OTHER")
	assert_eq(_eq.handle("P2", {"type": "place", "item": GEN, "anchor": "VAN_BAY", "in_range": true})["code"], "NOT_CARRIER")


func test_NET05_logic_carrier_disconnect_returns_generator_to_last_pad() -> void:
	_deploy_to_pump_pad()
	_ok(_do("pickup"))
	var events: Array[Dictionary] = _eq.disconnect_player("P1")
	assert_eq(events.size(), 1)
	assert_eq(events[0]["anchor"], "PAD_PUMP")
	assert_eq(_eq.anchor_of(GEN), "PAD_PUMP")
	assert_eq(_eq.carrier_of(GEN), "")
	_ok(_eq.handle("P2", {"type": "pickup", "item": GEN, "in_range": true}))


func test_G05_recovery_returns_generator_to_van_and_keeps_repairs() -> void:
	for cmd: Dictionary in Cases.expand(["@repair_west"], _doc["macros"]):
		var clean: Dictionary = cmd.duplicate()
		clean.erase("expect")
		_grid.apply(clean)
	_deploy_to_pump_pad()
	_ok(_do("connect", {"route": "E_TEMP_PUMP"}))
	_ok(_do("start"))
	var res: Dictionary = _eq.handle("P1", {"type": "recover", "item": GEN, "in_range": false})
	_ok(res)
	var st: Dictionary = _grid.canonical_state()
	assert_eq(st["nodes"]["GEN"]["online"], false)
	assert_eq(st["edges"]["E_TEMP_PUMP"]["enabled"], false)
	assert_eq(st["nodes"]["APT_W"]["supplied"], true, "permanent repair untouched")
	assert_eq(_eq.anchor_of(GEN), "VAN_BAY")
	assert_true(_eq.all_stowed())


func test_G05_stow_at_marked_storage_anchor() -> void:
	_deploy_to_pump_pad()
	assert_false(_eq.all_stowed())
	_ok(_do("pickup"))
	assert_false(_eq.all_stowed(), "carried is not stowed")
	_ok(_do("place", {"anchor": "STORE_PUMP_HOUSE"}))
	assert_true(_eq.all_stowed())
	assert_eq(_do("start")["code"], "PLACE_FIRST", "no running from a storage anchor")


func test_G05_bad_equipment_content_rejected() -> void:
	var def: Dictionary = _json(C01 + "equipment.json")
	def["anchors"][2]["routes"] = ["E_NOWHERE"]
	assert_eq(Equipment.new().load_definition(def, _grid, _meter)[0]["code"], "BAD_ROUTE")
	def = _json(C01 + "equipment.json")
	def["equipment"][0]["source"] = "TEMP"
	assert_eq(Equipment.new().load_definition(def, _grid, _meter)[0]["code"], "BAD_EQUIPMENT")
	def = _json(C01 + "equipment.json")
	def["equipment"][0]["start_anchor"] = "PAD_PUMP"
	assert_eq(Equipment.new().load_definition(def, _grid, _meter)[0]["code"], "BAD_EQUIPMENT")


func test_G05_out_of_range_refused_and_service_is_pure() -> void:
	assert_eq(_eq.handle("P1", {"type": "pickup", "item": GEN, "in_range": false})["code"], "NOT_IN_RANGE")
	var src: String = FileAccess.get_file_as_string("res://scripts/interaction/equipment_service.gd")
	for forbidden: String in ["get_node", "get_tree", "Engine.", "extends Node", "OS.", "Time."]:
		assert_false(src.contains(forbidden), "equipment_service.gd must not use %s" % forbidden)
	assert_ne(PowerGrid.serialize(_eq.canonical_state()), "")


# ---------- helpers ----------

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _do(kind: String, extra: Dictionary = {}) -> Dictionary:
	var intent: Dictionary = {"type": kind, "item": GEN, "in_range": true}
	intent.merge(extra)
	return _eq.handle("P1", intent)


func _ok(res: Dictionary) -> void:
	assert_true(res["ok"], str(res))


func _deploy_to_pump_pad() -> void:
	_ok(_do("pickup"))
	_ok(_do("place", {"anchor": "PAD_PUMP"}))
