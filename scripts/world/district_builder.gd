extends RefCounted
## Builds a graybox district scene from content/world/<district>.json (V01). The data is integer centimeters in world
## space; the conversion to meters goes through KitBuilder.cm. Facades are instances of the F05 kit scenes so the art
## pass can swap pieces without moving anything. Used by tools/godot/build_district.gd to write the committed .tscn
## and by the V01 tests to prove the committed scene still matches the data.
##
## Collision is deliberately simpler than the visuals (blueprint p.6): a 'block' building is one box and its kit
## instances have their collision layers cleared, so corner posts, sills and roof edges cannot snag a player. Only a
## 'kit' building, whose interior is walkable, keeps the kit pieces' own boxes.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const ALDER_PATH: String = "res://content/world/alder_street.json"
const MODULE_CM: int = 400
## Yaw that turns a kit piece (exterior on its local -Z side) to face outward on that side of a footprint.
const FACE_YAW: Dictionary = {"south": 0, "north": 180, "west": 90, "east": 270}
const FACES: Array[String] = ["south", "north", "west", "east"]
const ENTRANCE_STAND_OFF_CM: int = 75  # where a player stands in front of a door, outside the building's collision
const LABEL_FONT_SIZE: int = 96
const LABEL_PIXEL_SIZE: float = 0.01
const LABEL_ABOVE_ROOF_CM: int = 150
const WATER_ALPHA: float = 0.55


static func load_district(path: String = ALDER_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Returns an unparented tree whose nodes are owned by the root, ready for PackedScene.pack(). Kit pieces are scene
## instances: their own children stay owned by the instance.
static func build(d: Dictionary, kit: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(d["district_id"]).to_pascal_case()
	var mats: Dictionary = {}
	for key: String in d["materials"]:
		mats[key] = KitBuilder.material(key, d["materials"][key])
	(mats["water"] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(mats["water"] as StandardMaterial3D).albedo_color.a = WATER_ALPHA
	var scenes: Dictionary = {}
	for def: Dictionary in kit["pieces"]:
		scenes[def["id"]] = def["scene"]
	_ground(root, d, mats)
	_boundary(root, d, mats)
	var routes: Node3D = _group(root, "Routes")
	for r: Dictionary in d["routes"]:
		var lo: Array = r["min_cm"]
		var size: Array = r["size_cm"]
		# visual paving only: the ground slab is the floor, so a 2 cm kerb cannot become a ledge to snag on
		_box_mesh(routes, r["id"], [lo[0], 0, lo[1]], [size[0], 2, size[1]], mats[r["material"]])
	var buildings: Node3D = _group(root, "Buildings")
	for b: Dictionary in d["buildings"]:
		_building(buildings, root, b, scenes, d)
	var placed: Node3D = _group(root, "KitPlacements")
	for p: Dictionary in d["kit_placements"]:
		var inst: Node3D = _kit_instance(placed, root, p["id"], scenes[p["piece"]])
		inst.position = KitBuilder.cm(p["pos_cm"])
		inst.rotation_degrees.y = float(p["yaw"])
	var props: Node3D = _group(root, "Props")
	for p: Dictionary in d["props"]:
		_prop(props, root, p, mats[p["material"]])
	var markers: Node3D = _group(root, "Markers")
	for m: Dictionary in d["markers"]:
		var mk := Marker3D.new()
		mk.name = m["id"]
		mk.position = KitBuilder.cm(m["pos_cm"])
		mk.set_meta("kind", m["kind"])
		_add(markers, root, mk)
	var zones: Node3D = _group(root, "Zones")
	for z: Dictionary in d["zones"]:
		var area := Area3D.new()
		area.name = z["id"]
		area.monitorable = false  # presentation polls who is inside; the host decides zone membership (ADR-012)
		area.position = KitBuilder.cm(z["min_cm"]) + KitBuilder.cm(z["size_cm"]) * 0.5
		_add(zones, root, area)
		_box_shape(area, root, "Shape", Vector3.ZERO, KitBuilder.cm(z["size_cm"]))
	var labels: Node3D = _group(root, "Labels")
	for l: Dictionary in d["labels"]:
		_label(labels, root, "Label" + str(l["text"]), str(l["text"]), KitBuilder.cm(l["pos_cm"]))
	return root


## Ground slabs fill the envelope except the basement pit, which gets its own floor slab; the pit walls are the
## neighbouring slabs' sides, so the basement needs no extra geometry.
static func ground_slabs(d: Dictionary) -> Array[Dictionary]:
	var env: Array = d["envelope_cm"]
	var g: Dictionary = d["ground"]
	var t: int = int(g["thickness_cm"])
	var pit: Dictionary = g["pit"]
	var px: int = int(pit["min_cm"][0])
	var pz: int = int(pit["min_cm"][1])
	var pw: int = int(pit["size_cm"][0])
	var pd: int = int(pit["size_cm"][1])
	var ex: int = int(env[0])
	var ez: int = int(env[1])
	return [
		{"name": "SlabWest", "min": [0, -t, 0], "size": [px, t, ez]},
		{"name": "SlabEast", "min": [px + pw, -t, 0], "size": [ex - px - pw, t, ez]},
		{"name": "SlabSouth", "min": [px, -t, 0], "size": [pw, t, pz]},
		{"name": "SlabNorth", "min": [px, -t, pz + pd], "size": [pw, t, ez - pz - pd]},
		{"name": "PitFloor", "min": [px, -t, pz], "size": [pw, t - int(pit["depth_cm"]), pd]},
	]


static func _ground(root: Node3D, d: Dictionary, mats: Dictionary) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	_add(root, root, body)
	for s: Dictionary in ground_slabs(d):
		_box_mesh(body, s["name"], s["min"], s["size"], mats[d["ground"]["material"]])
		_box_shape(body, root, str(s["name"]) + "Collision", _center(s["min"], s["size"]), KitBuilder.cm(s["size"]))


static func _boundary(root: Node3D, d: Dictionary, mats: Dictionary) -> void:
	var env: Array = d["envelope_cm"]
	var bd: Dictionary = d["boundary"]
	var h: int = int(bd["height_cm"])
	var t: int = int(bd["thickness_cm"])
	var ex: int = int(env[0])
	var ez: int = int(env[1])
	var body := StaticBody3D.new()
	body.name = "Boundary"
	_add(root, root, body)
	# just outside the envelope, corners included, so nothing inside the playable area is lost to the fence
	var walls: Array[Dictionary] = [
		{"name": "WallSouth", "min": [-t, 0, -t], "size": [ex + 2 * t, h, t]},
		{"name": "WallNorth", "min": [-t, 0, ez], "size": [ex + 2 * t, h, t]},
		{"name": "WallWest", "min": [-t, 0, 0], "size": [t, h, ez]},
		{"name": "WallEast", "min": [ex, 0, 0], "size": [t, h, ez]},
	]
	for w: Dictionary in walls:
		_box_mesh(body, w["name"], w["min"], w["size"], mats[bd["material"]])
		_box_shape(body, root, str(w["name"]) + "Collision", _center(w["min"], w["size"]), KitBuilder.cm(w["size"]))


static func _building(parent: Node3D, root: Node3D, b: Dictionary, scenes: Dictionary, d: Dictionary) -> void:
	var node := Node3D.new()
	node.name = b["id"]
	node.position = KitBuilder.cm([b["min_cm"][0], 0, b["min_cm"][1]])
	_add(parent, root, node)
	var w: int = int(b["size_cm"][0])
	var dz: int = int(b["size_cm"][1])
	var storeys: int = int(b["storeys"])
	var collide: bool = b["collision"] == "kit"
	for s: int in storeys:
		var lists: Dictionary = b["ground"] if s == 0 else b["upper"]
		for face: String in FACES:
			var pieces: Array = face_pieces(b, face, lists)
			for i: int in pieces.size():
				var inst: Node3D = _kit_instance(node, root, "%s%d_%d" % [face.capitalize(), s, i], scenes[pieces[i]], collide)
				_place_on_face(inst, face, i, s * MODULE_CM, w, dz)
		# corner posts sit outside the footprint so they never overlap a wall face (no z-fighting between colors)
		var post: int = 25
		var corners: Array = [[-post, -post], [w, -post], [-post, dz], [w, dz]]
		for c: int in corners.size():
			var inst: Node3D = _kit_instance(node, root, "Corner%d_%d" % [s, c], scenes["corner"], collide)
			inst.position = KitBuilder.cm([corners[c][0], s * MODULE_CM, corners[c][1]])
	var top: int = storeys * MODULE_CM
	for i: int in w / MODULE_CM:
		for j: int in dz / MODULE_CM:
			var inst: Node3D = _kit_instance(node, root, "Roof_%d_%d" % [i, j], scenes["roof_plane"], collide)
			inst.position = KitBuilder.cm([i * MODULE_CM, top, j * MODULE_CM])
	for face: String in FACES:
		var n: int = (w if face == "south" or face == "north" else dz) / MODULE_CM
		for i: int in n:
			var inst: Node3D = _kit_instance(node, root, "RoofEdge%s_%d" % [face.capitalize(), i], scenes["roof_edge"], collide)
			_place_on_face(inst, face, i, top, w, dz)
	if not collide:
		var body := StaticBody3D.new()
		body.name = "Collision"
		_add(node, root, body)
		var size: Array = [w, top, dz]
		_box_shape(body, root, "Block", _center([0, 0, 0], size), KitBuilder.cm(size))
	var entrance := Marker3D.new()
	entrance.name = "Entrance"
	entrance.position = KitBuilder.cm(entrance_local_cm(b))
	_add(node, root, entrance)
	if b["service"]:
		var front: Vector3 = entrance.position
		_label(node, root, "Label", str(b["id"]), Vector3(front.x, KitBuilder.cm([0, top + LABEL_ABOVE_ROOF_CM, 0]).y, front.z))


## Kit piece ids along one face of one storey: the authored list, or plain walls when the face is not listed.
static func face_pieces(b: Dictionary, face: String, lists: Dictionary) -> Array:
	var n: int = int(b["size_cm"][0 if face == "south" or face == "north" else 1]) / MODULE_CM
	if lists.has(face):
		return lists[face]
	var out: Array = []
	out.resize(n)
	out.fill("wall")
	return out


## Module i counts west to east on north/south faces and south to north on east/west faces, in building-local cm.
static func _place_on_face(inst: Node3D, face: String, i: int, y: int, w: int, dz: int) -> void:
	var at: int = i * MODULE_CM
	var origin: Array
	match face:
		"south":
			origin = [at, y, 0]
		"north":
			origin = [at + MODULE_CM, y, dz]
		"west":
			origin = [0, y, at + MODULE_CM]
		_:
			origin = [w, y, at]
	inst.position = KitBuilder.cm(origin)
	inst.rotation_degrees.y = float(FACE_YAW[face])


## Building-local point in front of the first door on the front face, outside the collision box.
static func entrance_local_cm(b: Dictionary) -> Array:
	var face: String = b["front"]
	var pieces: Array = face_pieces(b, face, b["ground"])
	var i: int = maxi(pieces.find("door_wall"), 0)
	var mid: int = i * MODULE_CM + MODULE_CM / 2
	var w: int = int(b["size_cm"][0])
	var dz: int = int(b["size_cm"][1])
	match face:
		"south":
			return [mid, 0, -ENTRANCE_STAND_OFF_CM]
		"north":
			return [mid, 0, dz + ENTRANCE_STAND_OFF_CM]
		"west":
			return [-ENTRANCE_STAND_OFF_CM, 0, mid]
	return [w + ENTRANCE_STAND_OFF_CM, 0, mid]


static func _prop(parent: Node3D, root: Node3D, p: Dictionary, mat: StandardMaterial3D) -> void:
	var holder: Node3D
	if p["collision"]:
		holder = StaticBody3D.new()
	else:
		holder = Node3D.new()
	holder.name = p["id"]
	holder.position = KitBuilder.cm(p["min_cm"])
	_add(parent, root, holder)
	_box_mesh(holder, "Mesh", [0, 0, 0], p["size_cm"], mat)
	if p["collision"]:
		_box_shape(holder, root, "Collision", _center([0, 0, 0], p["size_cm"]), KitBuilder.cm(p["size_cm"]))


static func _kit_instance(parent: Node3D, root: Node3D, name: String, scene_path: String, collide: bool = true) -> Node3D:
	var inst: Node3D = (load(scene_path) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	inst.name = name
	if not collide and inst is StaticBody3D:
		(inst as StaticBody3D).collision_layer = 0
		(inst as StaticBody3D).collision_mask = 0
	_add(parent, root, inst)
	return inst


static func _group(root: Node3D, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	_add(root, root, n)
	return n


static func _box_mesh(parent: Node3D, name: String, lo: Array, size: Array, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var box := BoxMesh.new()
	box.size = KitBuilder.cm(size)
	mi.mesh = box
	mi.material_override = mat
	mi.position = _center(lo, size)
	_add(parent, _owner_of(parent), mi)
	box.resource_scene_unique_id = _sub_id("mesh", mi)


static func _box_shape(parent: Node3D, root: Node3D, name: String, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = name
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	_add(parent, root, cs)
	box.resource_scene_unique_id = _sub_id("shape", cs)


static func _label(parent: Node3D, root: Node3D, name: String, text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.name = name
	l.text = text
	l.font_size = LABEL_FONT_SIZE
	l.pixel_size = LABEL_PIXEL_SIZE
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	_add(parent, root, l)


static func _add(parent: Node, root: Node, child: Node) -> void:
	parent.add_child(child)
	if child != root:
		child.owner = root


## The root of a tree under construction is the topmost ancestor (nodes are not in a SceneTree yet).
static func _owner_of(n: Node) -> Node:
	return n if n.owner == null else n.owner


## Sub-resource ids derived from the node path keep regenerated scenes byte-identical (Godot would pick random ones).
static func _sub_id(prefix: String, n: Node) -> String:
	var path: String = str(_owner_of(n).get_path_to(n)) if n.owner else str(n.name)
	return "%s_%08x" % [prefix, path.hash() & 0x7FFFFFFF]


static func _center(lo: Array, size: Array) -> Vector3:
	return KitBuilder.cm(lo) + KitBuilder.cm(size) * 0.5


## Stable recursive description of a built or loaded district, in whole centimeters and degrees, for drift checks.
## Kit instances are described by scene path, transform and collision layer; their insides are the F05 test's job.
static func describe(root: Node3D) -> Array[String]:
	var out: Array[String] = []
	_describe(root, root, out)
	return out


static func _describe(root: Node3D, n: Node, out: Array[String]) -> void:
	var line: String = "%s|%s" % [root.get_path_to(n), n.get_class()]
	if n is Node3D:
		var n3: Node3D = n
		line += "|pos=" + KitBuilder.describe_cm(n3.position) + "|yaw=%d" % posmod(roundi(n3.rotation_degrees.y), 360)
	var instance: bool = n != root and n.scene_file_path != ""
	if instance:
		line += "|scene=" + n.scene_file_path
	if n is CollisionObject3D:
		line += "|layer=%d" % (n as CollisionObject3D).collision_layer
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		line += "|aabb=" + KitBuilder.describe_cm(mi.mesh.get_aabb().size)
		var mat: StandardMaterial3D = mi.material_override
		line += "|color=" + (mat.albedo_color.to_html(true) if mat else "none")
	if n is CollisionShape3D:
		var shape: Shape3D = (n as CollisionShape3D).shape
		line += "|" + shape.get_class()
		if shape is BoxShape3D:
			line += "=" + KitBuilder.describe_cm((shape as BoxShape3D).size)
	if n is Label3D:
		line += "|text=" + (n as Label3D).text
	if n is Marker3D and n.has_meta("kind"):
		line += "|kind=" + str(n.get_meta("kind"))
	out.append(line)
	if instance:
		return
	for c: Node in n.get_children():
		_describe(root, c, out)
