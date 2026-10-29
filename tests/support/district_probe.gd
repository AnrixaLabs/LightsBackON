extends RefCounted
## V01 test support: mounts a district scene in the running SceneTree and asks the physics world about it.
## Reachability is a 50 cm grid: a cell is standable when a ray finds a floor under it and a capsule slightly wider
## than the player fits there; neighbours connect when their floors differ by at most nav_max_step_cm (ramps, not
## ledges: the body has no step-up). A path found on the grid is then walked by a real CharacterBody3D at the content
## walk speed, so the claim "traversable" rests on move_and_slide against the scene's collision, not on the grid alone.

const CELL_M: float = 0.5
const RAY_TOP_M: float = 1.0  # below every roof and storey slab; starting inside a block building skips it
const RAY_BOTTOM_M: float = -3.0
const CLEARANCE_MARGIN_M: float = 0.05
const LIFT_M: float = 0.1  # keeps the query capsule off a 27 degree ramp it is standing on
const WAYPOINT_REACHED_M: float = 0.15
const MAX_STEPS_PER_WAYPOINT: int = 90
const GRAVITY_M_S2: float = 9.8

var root: Node3D
var space: PhysicsDirectSpaceState3D
var radius_m: float
var height_m: float
var max_step_m: float
var floor_angle_deg: float
var nx: int
var nz: int
var floor_h: PackedFloat32Array  # NAN where the cell has no floor or the capsule does not fit
var last_blocker: String = ""  # what the walker last slid against when it got stuck, for failure messages
var last_steps: int = 0  # physics ticks the last walk took


func _init(scene_path: String, dims: Dictionary, envelope_cm: Array) -> void:
	root = (load(scene_path) as PackedScene).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	space = root.get_world_3d().direct_space_state
	radius_m = float(dims["player_radius_cm"]) / 100.0
	height_m = float(dims["player_height_cm"]) / 100.0
	max_step_m = float(dims["nav_max_step_cm"]) / 100.0
	floor_angle_deg = float(dims["floor_max_angle_deg"])
	nx = int(float(envelope_cm[0]) / 100.0 / CELL_M)
	nz = int(float(envelope_cm[1]) / 100.0 / CELL_M)


func free_scene() -> void:
	if root:
		root.get_parent().remove_child(root)
		root.free()
		root = null


## Height of the first floor below (x, from_y, z), or NAN.
func floor_at(x: float, z: float, from_y: float = RAY_TOP_M) -> float:
	var hit: Dictionary = ray(Vector3(x, from_y, z), Vector3(x, RAY_BOTTOM_M, z))
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


func ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.hit_from_inside = false
	return space.intersect_ray(q)


## True when a player-sized capsule (plus margin) standing on feet touches nothing.
func capsule_fits(feet: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = radius_m + CLEARANCE_MARGIN_M
	cap.height = height_m
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, LIFT_M + height_m * 0.5, 0.0))
	return space.intersect_shape(q, 1).is_empty()


## Names of the collision objects overlapping an axis-aligned box (meters).
func box_overlaps(center: Vector3, size: Vector3) -> Array[String]:
	var box := BoxShape3D.new()
	box.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, center)
	var out: Array[String] = []
	for hit: Dictionary in space.intersect_shape(q, 8):
		out.append(str(root.get_path_to(hit["collider"] as Node)))
	return out


func build_grid() -> void:
	floor_h = PackedFloat32Array()
	floor_h.resize(nx * nz)
	for j: int in nz:
		for i: int in nx:
			var c: Vector3 = cell_center(i + j * nx)
			var h: float = floor_at(c.x, c.z)
			if not is_nan(h) and not capsule_fits(Vector3(c.x, h, c.z)):
				h = NAN
			floor_h[i + j * nx] = h


func cell_center(idx: int) -> Vector3:
	return Vector3((float(idx % nx) + 0.5) * CELL_M, 0.0, (float(idx / nx) + 0.5) * CELL_M)


func cell_of(p: Vector3) -> int:
	var i: int = clampi(int(p.x / CELL_M), 0, nx - 1)
	var j: int = clampi(int(p.z / CELL_M), 0, nz - 1)
	return i + j * nx


func standable(idx: int) -> bool:
	return not is_nan(floor_h[idx])


func feet(idx: int) -> Vector3:
	var c: Vector3 = cell_center(idx)
	return Vector3(c.x, floor_h[idx], c.z)


## Breadth-first search over standable cells; returns parent indices (-1 unreached, start points to itself).
func search(start: int) -> PackedInt32Array:
	var parent := PackedInt32Array()
	parent.resize(nx * nz)
	parent.fill(-1)
	if not standable(start):
		return parent
	parent[start] = start
	var queue: Array[int] = [start]
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb: int in _neighbours(cur):
			if parent[nb] == -1:
				parent[nb] = cur
				queue.append(nb)
	return parent


func _neighbours(idx: int) -> Array[int]:
	var out: Array[int] = []
	var i: int = idx % nx
	var j: int = idx / nx
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var a: int = i + d.x
		var b: int = j + d.y
		if a < 0 or b < 0 or a >= nx or b >= nz:
			continue
		var nb: int = a + b * nx
		if not _step_ok(idx, nb):
			continue
		# diagonals only when both orthogonal cells are open, so a path never cuts a wall corner
		if d.x != 0 and d.y != 0 and not (_step_ok(idx, a + j * nx) and _step_ok(idx, i + b * nx)):
			continue
		out.append(nb)
	return out


func _step_ok(a: int, b: int) -> bool:
	return standable(a) and standable(b) and absf(floor_h[a] - floor_h[b]) <= max_step_m


func path_to(parent: PackedInt32Array, goal: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if parent[goal] == -1:
		return out
	var cur: int = goal
	while true:
		out.push_front(feet(cur))
		if parent[cur] == cur:
			break
		cur = parent[cur]
	return out


## Walks a CharacterBody3D (player capsule) through the waypoints at speed_m_s with gravity; returns where it ended.
func walk(path: Array[Vector3], speed_m_s: float) -> Vector3:
	var body := CharacterBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius_m
	cap.height = height_m
	cs.shape = cap
	cs.position.y = height_m * 0.5
	body.add_child(cs)
	body.floor_max_angle = deg_to_rad(floor_angle_deg)
	root.add_child(body)
	body.global_position = path[0] + Vector3(0.0, 0.05, 0.0)
	var dt: float = 1.0 / float(Engine.physics_ticks_per_second)
	# Outside a physics frame move_and_slide integrates over the *process* frame delta, which here is however long the
	# runner's first frame took (100+ ms on a cold start). Scale the velocity so every call moves exactly one physics tick.
	var frame_dt: float = root.get_process_delta_time()
	assert(frame_dt > 0.0, "walk() needs the runner to have finished one frame")
	var to_tick: float = dt / frame_dt
	var vy: float = 0.0
	last_steps = 0
	for wp: Vector3 in path:
		var steps: int = 0
		while _flat(wp - body.global_position).length() > WAYPOINT_REACHED_M and steps < MAX_STEPS_PER_WAYPOINT:
			var dir: Vector3 = _flat(wp - body.global_position).normalized()
			vy = 0.0 if body.is_on_floor() else vy - GRAVITY_M_S2 * dt
			body.velocity = Vector3(dir.x * speed_m_s, vy, dir.z * speed_m_s) * to_tick
			body.move_and_slide()
			steps += 1
			last_steps += 1
		if steps >= MAX_STEPS_PER_WAYPOINT:
			var hit: KinematicCollision3D = body.get_last_slide_collision()
			last_blocker = "%s at %s" % [hit.get_collider(), hit.get_position()] if hit else "nothing"
			break  # stuck: the caller compares the end point with the goal
	var end: Vector3 = body.global_position
	root.remove_child(body)
	body.free()
	return end


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
