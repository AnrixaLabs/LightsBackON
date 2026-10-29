extends RefCounted
## Builds graybox kit scenes from content/world/kit_pieces.json (F05). Data is integer centimeters; scenes are meters
## (1 engine unit = 1 m), so the conversion lives here and nowhere else. Used by tools/godot/build_blockout_kit.gd to write
## the committed .tscn files and by the F05 kit test to prove the committed files still match the data.

const CM_PER_M: float = 100.0
const KIT_PATH: String = "res://content/world/kit_pieces.json"


static func load_kit(path: String = KIT_PATH) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func cm(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2])) / CM_PER_M


## Returns an unparented tree whose descendants are owned by the root, ready for PackedScene.pack().
static func build(def: Dictionary, materials: Dictionary) -> Node3D:
	var root: Node3D = StaticBody3D.new() if def["root"] == "static_body" else Node3D.new()
	root.name = str(def["id"]).to_pascal_case()
	var mats: Dictionary = {}
	for part: Dictionary in def["parts"]:
		var key: String = part["material"]
		if not mats.has(key):
			mats[key] = material(key, materials[key])
		var mi := MeshInstance3D.new()
		mi.name = part["name"]
		mi.mesh = _mesh(part)
		mi.mesh.resource_scene_unique_id = "mesh_" + str(part["name"])
		mi.material_override = mats[key]
		mi.position = _center(part)
		_add(root, mi)
	var i: int = 0
	for col: Dictionary in def["collision"]:
		i += 1
		var cs := CollisionShape3D.new()
		cs.name = "Collision%02d" % i
		if col["shape"] == "wedge":
			cs.shape = _wedge(col)  # points are piece-local, so the node stays at the origin
		else:
			var box := BoxShape3D.new()
			box.size = cm(col["size"])
			cs.shape = box
			cs.position = _center(col)
		cs.shape.resource_scene_unique_id = "shape_%02d" % i
		_add(root, cs)
	for a: Dictionary in def["anchors"]:
		var m := Marker3D.new()
		m.name = a["name"]
		m.position = cm(a["pos"])
		_add(root, m)
	return root


static func _add(root: Node3D, child: Node) -> void:
	root.add_child(child)
	child.owner = root


static func _center(part: Dictionary) -> Vector3:
	return cm(part["min"]) + cm(part["size"]) * 0.5


static func material(key: String, hex: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(hex)
	m.roughness = 1.0
	m.resource_scene_unique_id = "mat_" + key
	return m


static func _mesh(part: Dictionary) -> Mesh:
	var size: Vector3 = cm(part["size"])
	match str(part["shape"]):
		"box":
			var b := BoxMesh.new()
			b.size = size
			return b
		"capsule":
			var c := CapsuleMesh.new()
			c.radius = size.x * 0.5
			c.height = size.y
			return c
		"sphere":
			var s := SphereMesh.new()
			s.radius = size.x * 0.5
			s.height = size.y
			return s
		"cylinder":
			var y := CylinderMesh.new()
			y.top_radius = size.x * 0.5
			y.bottom_radius = size.x * 0.5
			y.height = size.y
			return y
	push_error("kit part %s: unknown shape %s" % [part["name"], part["shape"]])
	return BoxMesh.new()


## Ramp rising along +Z from the min corner: stairs collide as a slope so players do not snag on step edges.
static func _wedge(col: Dictionary) -> ConvexPolygonShape3D:
	var lo: Vector3 = cm(col["min"])
	var hi: Vector3 = lo + cm(col["size"])
	var s := ConvexPolygonShape3D.new()
	s.points = PackedVector3Array([
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z),
	])
	return s


## Union of every mesh's box in the root's space (children are unrotated, one level deep).
static func mesh_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	for c: Node in root.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var box: AABB = mi.mesh.get_aabb()
			box.position += mi.position
			out = box if first else out.merge(box)
			first = false
	return out


## Stable text description of a built or loaded tree, in whole centimeters, for drift checks.
static func describe(root: Node3D) -> Array[String]:
	var out: Array[String] = ["%s|%s" % [root.name, root.get_class()]]
	for c: Node in root.get_children():
		var line: String = "%s|%s" % [c.name, c.get_class()]
		if c is Node3D:
			line += "|pos=" + describe_cm((c as Node3D).position)
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			line += "|aabb=" + describe_cm(mi.mesh.get_aabb().size)
			var mat: StandardMaterial3D = mi.material_override
			line += "|color=" + (mat.albedo_color.to_html(false) if mat else "none")
		if c is CollisionShape3D:
			var shape: Shape3D = (c as CollisionShape3D).shape
			line += "|" + shape.get_class()
			if shape is BoxShape3D:
				line += "=" + describe_cm((shape as BoxShape3D).size)
			elif shape is ConvexPolygonShape3D:
				for p: Vector3 in (shape as ConvexPolygonShape3D).points:
					line += ";" + describe_cm(p)
		out.append(line)
	return out


static func describe_cm(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * CM_PER_M), roundi(v.y * CM_PER_M), roundi(v.z * CM_PER_M)]
