extends "res://tests/test_case.gd"
## V01: Alder Street graybox (blueprint p.5-6), generated from content/world/alder_street.json.
## Acceptance: "All routes traversable solo/controller; first restoration visible from the van." Automated here: the
## committed scene matches the data, locations sit at the blueprint centers, circulation is wide and clear, every C01
## target is reached on foot by a CharacterBody3D at the content walk speed (keyboard-equivalent input; a controller run
## by a person is UX01, pending local), and rays from the van and the east junction reach the restored facades.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const Probe := preload("res://tests/support/district_probe.gd")
const C01: String = "res://content/contracts/c01_alder_street"

## Blueprint p.5-6 location table: the six services plus the two junctions and the van.
const SERVICES: Array[String] = ["APT_W", "MARKET", "PUB", "APT_E", "WORKSHOP", "PUMP_HOUSE"]
const BLUEPRINT_PROPS: Dictionary = {"VAN": [8, 9], "CABINET_JW": [30, 24], "CABINET_JE": [73, 24]}
const CENTER_TOLERANCE_CM: int = 200
const ENVELOPE_CM: Array[int] = [11000, 7000]
const ARRIVE_M: float = 0.3
const ANCHOR_REACH_M: float = 1.0
const SIGHT_STOP_SHORT_M: float = 0.3
const WINDOW_CENTER_CM: int = 175  # kit window_wall opening spans 100-250 cm
const ROUTE_HEADROOM_CM: int = 210

var _d: Dictionary
var _kit: Dictionary
var _dims: Dictionary
var _probe: Probe = null


func before_each() -> void:
	_d = DistrictBuilder.load_district()
	_kit = KitBuilder.load_kit()
	_dims = JSON.parse_string(FileAccess.get_file_as_string("res://content/world/kit_dimensions.json"))


func after_each() -> void:
	if _probe:
		_probe.free_scene()
		_probe = null


func test_V01_committed_scene_matches_the_data() -> void:
	var ps: PackedScene = load(str(_d["scene"])) as PackedScene
	assert_true(ps != null, "%s loads" % _d["scene"])
	if ps == null:
		return
	var loaded: Node3D = ps.instantiate()
	var built: Node3D = DistrictBuilder.build(_d, _kit)
	var a: Array[String] = DistrictBuilder.describe(loaded)
	var b: Array[String] = DistrictBuilder.describe(built)
	assert_eq(a.size(), b.size(), "node count; rerun tools/godot/build_district.gd")
	for i: int in mini(a.size(), b.size()):
		if a[i] != b[i]:
			assert_eq(a[i], b[i], "first stale node; rerun tools/godot/build_district.gd")
			break
	assert_true(a == b, "scene is stale")
	loaded.free()
	built.free()


func test_V01_locations_sit_at_their_blueprint_centers() -> void:
	var seen: Array[String] = []
	for b: Dictionary in _d["buildings"]:
		if not b.has("blueprint_center_m"):
			continue
		seen.append(str(b["id"]))
		var c: Vector2i = Vector2i(int(b["min_cm"][0]) + int(b["size_cm"][0]) / 2, int(b["min_cm"][1]) + int(b["size_cm"][1]) / 2)
		_assert_near_blueprint(str(b["id"]), c, b["blueprint_center_m"])
	for id: String in SERVICES:
		assert_true(seen.has(id), "service %s is blocked out" % id)
	var props: Dictionary = _by_id(_d["props"])
	for id: String in BLUEPRINT_PROPS:
		assert_true(props.has(id), id)
		if not props.has(id):
			continue
		var p: Dictionary = props[id]
		assert_eq(_ints(p["blueprint_center_m"]), BLUEPRINT_PROPS[id], "%s uses the blueprint table" % id)
		var c: Vector2i = Vector2i(int(p["min_cm"][0]) + int(p["size_cm"][0]) / 2, int(p["min_cm"][2]) + int(p["size_cm"][2]) / 2)
		_assert_near_blueprint(id, c, p["blueprint_center_m"])
	assert_eq(str(props["CABINET_JW"]["junction"]), "JW")
	assert_eq(str(props["CABINET_JE"]["junction"]), "JE")
	var labels: Array = (_d["labels"] as Array).map(func(l: Dictionary) -> String: return str(l["text"]))
	assert_true(labels.has("JW") and labels.has("JE"), "JW/JE are labelled")


func test_V01_layout_uses_the_4m_module_and_25cm_increment_inside_the_envelope() -> void:
	assert_eq(_ints(_d["envelope_cm"]), ENVELOPE_CM, "110 m x 70 m playable envelope (p.5)")
	var module: int = int(_dims["module_cm"])
	var step: int = int(_dims["placement_increment_cm"])
	for b: Dictionary in _d["buildings"]:
		for axis: int in 2:
			assert_eq(int(b["size_cm"][axis]) % module, 0, "%s size on the 4 m module" % b["id"])
			assert_eq(int(b["min_cm"][axis]) % step, 0, "%s corner on the 25 cm grid" % b["id"])
		_assert_inside(str(b["id"]), b["min_cm"], b["size_cm"])
		for face: String in DistrictBuilder.FACES:
			for lists: Dictionary in [b["ground"], b["upper"]]:
				var n: int = DistrictBuilder.face_pieces(b, face, lists).size()
				var want: int = int(b["size_cm"][0 if face == "south" or face == "north" else 1]) / module
				assert_eq(n, want, "%s %s face has one piece per module" % [b["id"], face])
	for r: Dictionary in _d["routes"]:
		_assert_on_grid(str(r["id"]), r["min_cm"] + r["size_cm"], step)
		_assert_inside(str(r["id"]), r["min_cm"], r["size_cm"])
	for p: Dictionary in _d["props"]:
		var footprint: Array = [p["min_cm"][0], p["min_cm"][2], p["size_cm"][0], p["size_cm"][2]]
		_assert_on_grid(str(p["id"]), footprint, step)
		_assert_inside(str(p["id"]), [p["min_cm"][0], p["min_cm"][2]], [p["size_cm"][0], p["size_cm"][2]])
	for p: Dictionary in _d["kit_placements"]:
		_assert_on_grid(str(p["id"]), p["pos_cm"], step)
	var pit: Dictionary = _d["ground"]["pit"]
	_assert_on_grid("pit", pit["min_cm"] + pit["size_cm"] + [pit["depth_cm"]], step)
	for m: Dictionary in _d["markers"]:
		_assert_inside(str(m["id"]), [m["pos_cm"][0], m["pos_cm"][2]], [0, 0])
	var area: int = 0
	for s: Dictionary in DistrictBuilder.ground_slabs(_d):
		area += int(s["size"][0]) * int(s["size"][2])
	assert_eq(area, ENVELOPE_CM[0] * ENVELOPE_CM[1], "ground slabs and pit floor tile the envelope exactly")


func test_V01_circulation_is_at_least_2_4m_wide_and_clear() -> void:
	_mount()
	var min_w: int = int(_dims["circulation_min_width_cm"])
	for r: Dictionary in _d["routes"]:
		var size: Array = r["size_cm"]
		assert_true(mini(int(size[0]), int(size[1])) >= min_w, "%s is %d cm wide" % [r["id"], mini(int(size[0]), int(size[1]))])
		# 1 cm inset so a wall exactly on the route edge does not count as standing in it
		var lo: Vector3 = KitBuilder.cm([r["min_cm"][0], 5, r["min_cm"][1]])
		var dims: Vector3 = KitBuilder.cm([int(size[0]) - 2, ROUTE_HEADROOM_CM, int(size[1]) - 2])
		var hits: Array[String] = _probe.box_overlaps(lo + Vector3(0.01, 0.0, 0.01) + dims * 0.5, dims)
		assert_true(hits.is_empty(), "%s is clear of collision: %s" % [r["id"], str(hits)])
	var stair: Dictionary = _piece("stair_flight")
	assert_true(int(stair["envelope_cm"][0]) >= min_w, "basement stair is circulation width")


func test_V01_panels_and_switches_sit_at_interaction_height() -> void:
	_mount()
	var lo: int = int(_dims["panel_height_min_cm"])
	var hi: int = int(_dims["panel_height_max_cm"])
	var n: int = 0
	for m: Dictionary in _d["markers"]:
		if m["kind"] != "panel" and m["kind"] != "switch":
			continue
		n += 1
		var p: Vector3 = KitBuilder.cm(m["pos_cm"])
		var floor_y: float = _probe.floor_at(p.x, p.z, p.y)
		assert_false(is_nan(floor_y), "%s has a floor under it" % m["id"])
		var h: int = roundi((p.y - floor_y) * 100.0)
		assert_true(h >= lo and h <= hi, "%s at %d cm above its floor" % [m["id"], h])
	assert_true(n >= 6, "panels and switches are placed")


func test_V01_every_c01_target_is_reached_on_foot_from_the_van() -> void:
	_mount()
	_probe.build_grid()
	var start: int = _probe.cell_of(_marker_pos(str(_d["spawn"])))
	assert_true(_probe.standable(start), "spawn cell is standable")
	var parent: PackedInt32Array = _probe.search(start)
	var speed: float = _walk_speed()
	var targets: Array[Dictionary] = _targets()
	assert_true(targets.size() >= 20, "%d targets" % targets.size())
	for t: Dictionary in targets:
		var goal: int = _goal_cell(t, parent)
		assert_true(goal >= 0, "%s (%s) is reachable from the van" % [t["id"], t["rule"]])
		if goal < 0:
			continue
		var path: Array[Vector3] = _probe.path_to(parent, goal)
		var end: Vector3 = _probe.walk(path, speed)
		var miss: float = end.distance_to(_probe.feet(goal))
		assert_true(miss <= ARRIVE_M, "walked to %s: ended %.2f m from the goal at %s" % [t["id"], miss, str(end)])


func test_V01_rear_loop_walks_all_the_way_round() -> void:
	_mount()
	_probe.build_grid()
	var routes: Dictionary = _by_id(_d["routes"])
	var loop: Array = _d["loop"]
	assert_eq(str(loop[0]), str(loop[loop.size() - 1]), "the loop closes")
	assert_true(loop.has("REAR_ALLEY") and loop.has("MAIN_STREET"), "street loop includes the rear service alley")
	var speed: float = _walk_speed()
	for i: int in loop.size() - 1:
		var a: int = _probe.cell_of(_route_center(routes[loop[i]]))
		var b: int = _probe.cell_of(_route_center(routes[loop[i + 1]]))
		var path: Array[Vector3] = _probe.path_to(_probe.search(a), b)
		assert_false(path.is_empty(), "%s -> %s connected" % [loop[i], loop[i + 1]])
		if path.is_empty():
			continue
		var end: Vector3 = _probe.walk(path, speed)
		assert_true(end.distance_to(_probe.feet(b)) <= ARRIVE_M, "walked %s -> %s" % [loop[i], loop[i + 1]])


func test_V01_first_restoration_is_visible_from_the_van_and_east_from_JE() -> void:
	_mount()
	var buildings: Dictionary = _by_id(_d["buildings"])
	var lines: Array = _d["sightlines"]
	assert_eq(str(lines[0]["from"]), "VAN_EYE")
	assert_eq(lines[0]["to"], ["APT_W", "MARKET"], "the west branch is the first restoration (p.7 step 1)")
	for line: Dictionary in lines:
		var eye: Vector3 = _marker_pos(str(line["from"]))
		assert_eq(roundi(eye.y * 100.0) - roundi(_probe.floor_at(eye.x, eye.z) * 100.0), int(_dims["camera_height_cm"]),
			"%s at first-person eye height" % line["from"])
		for id: String in line["to"]:
			var windows: Array[Vector3] = _front_windows(buildings[id])
			assert_false(windows.is_empty(), "%s has front windows" % id)
			for w: Vector3 in windows:
				var to: Vector3 = w - (w - eye).normalized() * SIGHT_STOP_SHORT_M
				var hit: Dictionary = _probe.ray(eye, to)
				assert_true(hit.is_empty(), "%s -> %s window at %s blocked by %s" % [line["from"], id, str(w),
					str(_probe.root.get_path_to(hit["collider"])) if not hit.is_empty() else ""])


func test_V01_collision_is_simplified_convex_geometry() -> void:
	var root: Node3D = (load(str(_d["scene"])) as PackedScene).instantiate()
	for b: Dictionary in _d["buildings"]:
		var node: Node3D = root.get_node(NodePath("Buildings/" + str(b["id"])))
		for c: Node in node.get_children():
			if c is CollisionObject3D and c.scene_file_path != "":
				var layer: int = (c as CollisionObject3D).collision_layer
				assert_eq(layer != 0, b["collision"] == "kit", "%s/%s collides only in a kit-collision building" % [b["id"], c.name])
		if b["collision"] == "block":
			var shapes: Array[Node] = node.get_node("Collision").get_children()
			assert_eq(shapes.size(), 1, "%s is one collision box" % b["id"])
			assert_true((shapes[0] as CollisionShape3D).shape is BoxShape3D, "%s box" % b["id"])
	var shapes: Array[Node] = root.find_children("*", "CollisionShape3D", true, false)
	assert_true(shapes.size() > 0)
	for cs: Node in shapes:
		var shape: Shape3D = (cs as CollisionShape3D).shape
		var ok: bool = shape is BoxShape3D or (shape is ConvexPolygonShape3D and str(root.get_path_to(cs)).contains("STAIR"))
		assert_true(ok, "%s is a box (or the stair ramp)" % root.get_path_to(cs))
	root.free()


func test_V01_c01_anchors_and_van_zone_match_the_graybox() -> void:
	var markers: Dictionary = _by_id(_d["markers"])
	var eq: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(C01 + "/equipment.json"))
	for a: Dictionary in eq["anchors"]:
		assert_true(markers.has(a["id"]), "graybox has anchor %s" % a["id"])
		if markers.has(a["id"]):
			assert_eq(str(markers[a["id"]]["kind"]), "anchor")
			assert_eq(a["position_cm"], markers[a["id"]]["pos_cm"], "%s position matches the graybox" % a["id"])
	assert_true(markers.has(eq["recovery_anchor"]), "recovery anchor")
	var switches: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(C01 + "/switches.json"))
	for s: Dictionary in switches["switches"]:
		assert_true(markers.has(s["id"]), "switch %s has a place" % s["id"])
	var repairs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(C01 + "/repairs.json"))
	for r: Dictionary in repairs["repairs"]:
		assert_true(markers.has(r["panel"]), "repair panel %s has a place" % r["panel"])
	var mission: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(C01 + "/mission.json"))
	var zone_id: String = mission["extraction"]["zone"]
	var zones: Dictionary = _by_id(_d["zones"])
	assert_true(zones.has(zone_id), "graybox has %s" % zone_id)
	if not zones.has(zone_id):
		return
	var box := AABB(KitBuilder.cm(zones[zone_id]["min_cm"]), KitBuilder.cm(zones[zone_id]["size_cm"]))
	for id: String in markers:
		if markers[id]["kind"] == "spawn" or id == eq["recovery_anchor"]:
			assert_true(box.has_point(KitBuilder.cm(markers[id]["pos_cm"]) + Vector3(0.0, 0.01, 0.0)), "%s inside %s" % [id, zone_id])
	var root: Node3D = (load(str(_d["scene"])) as PackedScene).instantiate()
	assert_true(root.get_node_or_null(NodePath("Zones/" + zone_id)) is Area3D, "%s is an Area3D in the scene" % zone_id)
	assert_true(root.get_node_or_null("Markers/PAD_PUMP") is Marker3D, "stable authored marker path")
	root.free()


## Every place a C01 player must get to: route centers, service entrances, anchors, panels, switches and consumers.
func _targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in _d["routes"]:
		out.append({"id": r["id"], "rule": "stand", "pos": _route_center(r)})
	for b: Dictionary in _d["buildings"]:
		if b["service"]:
			var e: Array = DistrictBuilder.entrance_local_cm(b)
			out.append({"id": str(b["id"]) + " entrance", "rule": "stand",
				"pos": KitBuilder.cm([int(b["min_cm"][0]) + int(e[0]), 0, int(b["min_cm"][1]) + int(e[2])])})
	for m: Dictionary in _d["markers"]:
		match str(m["kind"]):
			"anchor":
				out.append({"id": m["id"], "rule": "anchor", "pos": KitBuilder.cm(m["pos_cm"])})
			"panel", "switch", "consumer":
				out.append({"id": m["id"], "rule": "reach", "pos": KitBuilder.cm(m["pos_cm"])})
	return out


## Nearest reachable cell that satisfies the target's rule, or -1.
func _goal_cell(t: Dictionary, parent: PackedInt32Array) -> int:
	var pos: Vector3 = t["pos"]
	var reach_m: float = float(_dims["interact_ray_cm"]) / 100.0
	var eye_m: float = float(_dims["camera_height_cm"]) / 100.0
	var best: int = -1
	var best_d: float = INF
	var r: int = ceili(reach_m / Probe.CELL_M) + 1
	var c: int = _probe.cell_of(pos)
	for dj: int in range(-r, r + 1):
		for di: int in range(-r, r + 1):
			var i: int = c % _probe.nx + di
			var j: int = c / _probe.nx + dj
			if i < 0 or j < 0 or i >= _probe.nx or j >= _probe.nz:
				continue
			var idx: int = i + j * _probe.nx
			if parent[idx] == -1:
				continue
			var f: Vector3 = _probe.feet(idx)
			var flat: float = Vector2(f.x - pos.x, f.z - pos.z).length()
			var ok: bool
			match str(t["rule"]):
				"stand":
					ok = flat <= Probe.CELL_M and absf(f.y - pos.y) <= ARRIVE_M
				"anchor":
					ok = flat <= ANCHOR_REACH_M and absf(f.y - pos.y) <= ARRIVE_M
				_:
					var eye: Vector3 = f + Vector3(0.0, eye_m, 0.0)
					ok = eye.distance_to(pos) <= reach_m and _probe.ray(eye, pos).is_empty()
			if ok and flat < best_d:
				best_d = flat
				best = idx
	return best


## World positions of the ground-storey window openings on a building's front face, just outside the facade.
func _front_windows(b: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var face: String = b["front"]
	var pieces: Array = DistrictBuilder.face_pieces(b, face, b["ground"])
	var module: int = int(_dims["module_cm"])
	for i: int in pieces.size():
		if pieces[i] != "window_wall":
			continue
		var along: int = int(b["min_cm"][0]) + i * module + module / 2
		var z: int = int(b["min_cm"][1]) - 1 if face == "south" else int(b["min_cm"][1]) + int(b["size_cm"][1]) + 1
		out.append(KitBuilder.cm([along, WINDOW_CENTER_CM, z]))
	return out


func _mount() -> void:
	_probe = Probe.new(str(_d["scene"]), _dims, _d["envelope_cm"])


func _walk_speed() -> float:
	var movement: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/movement.json"))
	return float(movement["walk_mm_s"]) / 1000.0


func _marker_pos(id: String) -> Vector3:
	return KitBuilder.cm(_by_id(_d["markers"])[id]["pos_cm"])


func _route_center(r: Dictionary) -> Vector3:
	return KitBuilder.cm([int(r["min_cm"][0]) + int(r["size_cm"][0]) / 2, 0, int(r["min_cm"][1]) + int(r["size_cm"][1]) / 2])


func _piece(id: String) -> Dictionary:
	for p: Dictionary in _kit["pieces"]:
		if p["id"] == id:
			return p
	return {}


func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for v: Variant in values:
		out.append(int(v))
	return out


func _by_id(items: Array) -> Dictionary:
	var out: Dictionary = {}
	for it: Dictionary in items:
		out[str(it["id"])] = it
	return out


func _assert_near_blueprint(id: String, center_cm: Vector2i, blueprint_m: Array) -> void:
	var want := Vector2(float(blueprint_m[0]) * 100.0, float(blueprint_m[1]) * 100.0)
	var off: float = Vector2(center_cm).distance_to(want)
	assert_true(off <= CENTER_TOLERANCE_CM, "%s center %s is %.0f cm from the blueprint %s" % [id, str(center_cm), off, str(blueprint_m)])


func _assert_on_grid(id: String, values: Array, step: int) -> void:
	for v: Variant in values:
		assert_eq(int(v) % step, 0, "%s value %d on the %d cm grid" % [id, int(v), step])


func _assert_inside(id: String, lo: Array, size: Array) -> void:
	var ok: bool = int(lo[0]) >= 0 and int(lo[1]) >= 0 and int(lo[0]) + int(size[0]) <= ENVELOPE_CM[0] \
		and int(lo[1]) + int(size[1]) <= ENVELOPE_CM[1]
	assert_true(ok, "%s inside the 110 x 70 m envelope" % id)
