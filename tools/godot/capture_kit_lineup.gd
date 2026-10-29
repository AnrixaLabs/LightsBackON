extends SceneTree
## Renders every F05 kit piece with a worker silhouette in front of it, for the owner's silhouette-and-scale approval
## (blueprint p.41 pipeline step 3). Needs a real GPU window, so it does not run headless or in CI.
##   godot --path . --resolution 1920x1080 -s "$PWD/tools/godot/capture_kit_lineup.gd" -- --out=build/kit_lineup.png
## --stairs renders a flight -> landing -> flight assembly (L turn) with workers instead, placed by the pieces' own anchors.
## Exit 0 = PNG written.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const PER_ROW: int = 5
const GAP_M: float = 1.5
const ROW_DEPTH_M: float = 7.0
const WORKER_IN_FRONT_M: float = 1.0
const SETTLE_FRAMES: int = 10


func _initialize() -> void:
	var out: String = "build/kit_lineup.png"
	var stairs: bool = false
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		stairs = stairs or a == "--stairs"
	var kit: Dictionary = KitBuilder.load_kit()
	var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/ui/tokens.json"))
	var world := Node3D.new()
	root.add_child(world)
	_environment(world, Color(str(tokens["colors"]["background"])))
	var worker: PackedScene = null
	var pieces: Array[Dictionary] = []
	for def: Dictionary in kit["pieces"]:
		if def["root"] == "static_body":
			pieces.append(def)
		else:
			worker = load(def["scene"])
	if stairs:
		_stair_assembly(world, pieces, worker)
	else:
		_lineup(world, pieces, worker)
	for i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var err: Error = img.save_png(out)
	print(("WROTE %s (%dx%d, %s)" % [out, img.get_width(), img.get_height(), RenderingServer.get_video_adapter_name()])
		if err == OK else "FAILED %s: %s" % [out, error_string(err)])
	quit(0 if err == OK else 1)


func _lineup(world: Node3D, pieces: Array[Dictionary], worker: PackedScene) -> void:
	var width: float = 0.0
	var x: float = 0.0
	for i: int in pieces.size():
		if i % PER_ROW == 0:
			x = 0.0
		var def: Dictionary = pieces[i]
		var piece: Node3D = (load(def["scene"]) as PackedScene).instantiate()
		# the camera looks along +Z, so screen-left is +X: lay the row out toward -X to read in data order
		piece.position = Vector3(-x - KitBuilder.cm(def["envelope_cm"]).x, 0.0, (i / PER_ROW) * ROW_DEPTH_M)
		world.add_child(piece)
		if worker:
			var w: Node3D = worker.instantiate()
			w.position = piece.position + Vector3(-0.5, 0.0, -WORKER_IN_FRONT_M)
			world.add_child(w)
		x += KitBuilder.cm(def["envelope_cm"]).x + GAP_M
		width = maxf(width, x)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(-width * 0.5, 7.0, -11.0), Vector3(-width * 0.5, 1.0, ROW_DEPTH_M * 0.5))
	cam.current = true


## Flight up to the landing, then a second flight turning off its right edge: the landing's anchors place both flights.
func _stair_assembly(world: Node3D, pieces: Array[Dictionary], worker: PackedScene) -> void:
	var defs: Dictionary = {}
	for d: Dictionary in pieces:
		defs[d["id"]] = d
	var flight: Dictionary = defs["stair_flight"]
	var landing: Dictionary = defs["stair_landing"]
	var first: Node3D = (load(flight["scene"]) as PackedScene).instantiate()
	world.add_child(first)
	var land: Node3D = (load(landing["scene"]) as PackedScene).instantiate()
	land.position = KitBuilder.cm(_anchor(flight, "Top")) - KitBuilder.cm(_anchor(landing, "EdgeNear"))
	world.add_child(land)
	var second: Node3D = (load(flight["scene"]) as PackedScene).instantiate()
	second.rotation_degrees = Vector3(0.0, 90.0, 0.0)  # the flight climbs along local +Z, which now points +X, away from the right edge
	second.position = land.position + KitBuilder.cm(_anchor(landing, "EdgeRight")) - second.basis * KitBuilder.cm(_anchor(flight, "Bottom"))
	world.add_child(second)
	if worker:
		for spot: Vector3 in [Vector3(1.25, 0.0, -1.0), land.position + KitBuilder.cm(_anchor(landing, "EdgeNear")) + Vector3(0.0, 0.0, 1.25)]:
			var w: Node3D = worker.instantiate()
			w.position = spot
			world.add_child(w)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.look_at_from_position(Vector3(-6.5, 6.0, -4.0), Vector3(2.5, 1.8, 4.0))
	cam.current = true


func _anchor(def: Dictionary, name: String) -> Array:
	for a: Dictionary in def["anchors"]:
		if a["name"] == name:
			return a["pos"]
	push_error("%s has no anchor %s" % [def["id"], name])
	return [0, 0, 0]


func _environment(world: Node3D, sky: Color) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.7)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.23, 0.26)
	ground.material_override = mat
	world.add_child(ground)
