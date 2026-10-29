extends "res://tests/test_case.gd"
## F05 (local part): graybox block kit at 1 engine unit = 1 m, generated from content/world/kit_pieces.json.
## Acceptance: "Kit imports at 1 unit per meter". The kit is native .tscn (no glTF import step yet), so the check is that every
## committed scene loads, matches the data it was generated from, and measures in meters.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")

## Blueprint p.11: "wall, window wall, door wall, corner, roof edge, roof plane, floor, stair flight, railing, service panel recess".
const BLUEPRINT_PIECES: Array[String] = ["wall", "window_wall", "door_wall", "corner", "roof_edge", "roof_plane", "floor",
	"stair_flight", "railing", "service_panel_recess"]
## CharacterBody3D's default floor_max_angle; movement has no authored slope limit yet (V01/V05 revisit).
const MAX_WALKABLE_SLOPE_DEG: float = 45.0

var _kit: Dictionary
var _dims: Dictionary
var _defs: Dictionary


func before_each() -> void:
	_kit = KitBuilder.load_kit()
	_dims = JSON.parse_string(FileAccess.get_file_as_string("res://content/world/kit_dimensions.json"))
	_defs = {}
	for d: Dictionary in _kit["pieces"]:
		_defs[d["id"]] = d


func test_F05_kit_has_every_blueprint_piece_and_the_worker() -> void:
	for id: String in BLUEPRINT_PIECES:
		assert_true(_defs.has(id), "kit piece %s" % id)
	assert_true(_defs.has("worker_silhouette"), "worker silhouette for scale")
	assert_eq(_defs.size(), BLUEPRINT_PIECES.size() + 1, "nothing outside the blueprint list")


func test_F05_committed_scenes_match_the_data() -> void:
	for id: String in _defs:
		var def: Dictionary = _defs[id]
		var loaded: Node3D = _instance(def)
		if loaded == null:
			continue
		var built: Node3D = KitBuilder.build(def, _kit["materials"])
		assert_eq(KitBuilder.describe(loaded), KitBuilder.describe(built),
			"%s is stale: rerun tools/godot/build_blockout_kit.gd" % id)
		built.free()
		loaded.free()


func test_F05_kit_imports_at_one_unit_per_meter() -> void:
	var wall: Node3D = _instance(_defs["wall"])
	assert_eq(KitBuilder.mesh_bounds(wall), AABB(Vector3.ZERO, Vector3(4.0, 4.0, 0.25)), "4 m wall is 4 units")
	wall.free()
	for id: String in _defs:
		var def: Dictionary = _defs[id]
		var node: Node3D = _instance(def)
		var lo: Array = def.get("envelope_min_cm", [0, 0, 0])
		var want := AABB(KitBuilder.cm(lo), KitBuilder.cm(def["envelope_cm"]))
		var got: AABB = KitBuilder.mesh_bounds(node)
		assert_true(got.position.is_equal_approx(want.position) and got.size.is_equal_approx(want.size),
			"%s bounds %s, data envelope %s" % [id, str(got), str(want)])
		node.free()


func test_F05_module_pieces_span_one_4m_module() -> void:
	var module: int = int(_dims["module_cm"])
	for id: String in ["wall", "window_wall", "door_wall", "roof_edge", "railing", "service_panel_recess", "roof_plane", "floor"]:
		assert_eq(int(_defs[id]["envelope_cm"][0]), module, "%s length" % id)
	for id: String in ["wall", "window_wall", "door_wall", "corner", "service_panel_recess"]:
		assert_eq(int(_defs[id]["envelope_cm"][1]), module, "%s storey height" % id)
	for id: String in ["roof_plane", "floor"]:
		assert_eq(int(_defs[id]["envelope_cm"][2]), module, "%s depth" % id)
	var step: int = int(_dims["placement_increment_cm"])
	for id: String in BLUEPRINT_PIECES:
		for axis: int in [0, 2]:
			var v: int = int(_defs[id]["envelope_cm"][axis])
			assert_true(v % step == 0 or id == "railing", "%s footprint %d cm snaps to %d cm" % [id, v, step])


func test_F05_door_clears_the_minimum_width() -> void:
	var p: Dictionary = _parts(_defs["door_wall"])
	var clear: int = int(p["JambRight"]["min"][0]) - int(p["JambLeft"]["min"][0]) - int(p["JambLeft"]["size"][0])
	assert_true(clear >= int(_dims["door_clear_width_min_cm"]), "door clear %d cm" % clear)
	assert_true(int(p["Header"]["min"][1]) > int(_dims["camera_height_cm"]), "header above eye height")


func test_F05_stairs_are_wide_walkable_and_collide_as_a_ramp() -> void:
	var def: Dictionary = _defs["stair_flight"]
	var env: Array = def["envelope_cm"]
	assert_true(int(env[0]) >= int(_dims["circulation_min_width_cm"]), "stair width is a circulation route")
	var slope: float = rad_to_deg(atan2(float(env[1]), float(env[2])))
	assert_true(slope < MAX_WALKABLE_SLOPE_DEG, "stair slope %.1f deg" % slope)
	var cols: Array = def["collision"]
	assert_eq(cols.size(), 1)
	assert_eq(str(cols[0]["shape"]), "wedge", "one smooth ramp, no step edges to snag on")


func test_F05_service_panel_sits_at_interaction_height_and_reach() -> void:
	var anchor: Array = _anchor(_defs["service_panel_recess"], "PanelAnchor")
	var h: int = int(anchor[1])
	assert_true(h >= int(_dims["panel_height_min_cm"]) and h <= int(_dims["panel_height_max_cm"]), "panel at %d cm" % h)
	var eye: Array = _anchor(_defs["worker_silhouette"], "Eye")
	assert_eq(int(eye[1]), int(_dims["camera_height_cm"]), "worker eye = first-person camera height")
	# a worker standing just outside the 25 cm wall face reaches the recessed panel with the interact ray
	var standing := Vector3(float(anchor[0]), float(eye[1]), -50.0)
	var reach: float = standing.distance_to(Vector3(float(anchor[0]), float(h), float(anchor[2])))
	assert_true(reach <= float(_dims["interact_ray_cm"]), "reach %.0f cm" % reach)


func test_F05_static_pieces_have_collision_inside_their_envelope() -> void:
	for id: String in BLUEPRINT_PIECES:
		var def: Dictionary = _defs[id]
		assert_eq(str(def["root"]), "static_body", id)
		var cols: Array = def["collision"]
		assert_false(cols.is_empty(), "%s has collision" % id)
		var env: Array = def["envelope_cm"]
		for c: Dictionary in cols:
			for axis: int in 3:
				var lo: int = int(c["min"][axis])
				assert_true(lo >= 0 and lo + int(c["size"][axis]) <= int(env[axis]), "%s collision inside envelope" % id)
	assert_true((_defs["worker_silhouette"]["collision"] as Array).is_empty(), "silhouette is a scale reference, not a body")


func _instance(def: Dictionary) -> Node3D:
	var path: String = def["scene"]
	var ps: PackedScene = load(path) as PackedScene
	assert_true(ps != null, "%s loads" % path)
	return ps.instantiate() as Node3D if ps else null


func _parts(def: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for p: Dictionary in def["parts"]:
		out[p["name"]] = p
	return out


func _anchor(def: Dictionary, name: String) -> Array:
	for a: Dictionary in def["anchors"]:
		if a["name"] == name:
			return a["pos"]
	assert_true(false, "%s has anchor %s" % [def["id"], name])
	return [0, 0, 0]
