extends SceneTree
## Renders the V01 graybox for the sightline evidence and the owner's look: each sightline in the district data from
## its first-person eye marker (1.75 m), plus a top-down plan. Windows of the sightline's target buildings get a warm
## emissive pane and a light, standing in for the restored state the presentation layer will drive later; the graybox
## scene itself has no lighting states. Needs a real GPU window, so it does not run headless or in CI.
##   godot --path . --resolution 1920x1080 -s "$PWD/tools/godot/capture_district_views.gd" -- --out-dir=build/v01
## Writes <out-dir>/V01_<from>.png per sightline and V01_plan.png. Exit 0 = all written.

const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const SETTLE_FRAMES: int = 10
const FOV_DEG: float = 75.0  # Camera3D default; the game's FOV setting does not exist yet
const SKY := Color(0.42, 0.5, 0.58)  # cool overcast: recovery must read without darkness hiding the scene (pillar 3)
const AMBIENT := Color(0.55, 0.62, 0.7)
const WINDOW_GLOW := Color(1.0, 0.8, 0.45)
const WINDOW_PANE_CM: Array[int] = [150, 150, 5]
const WINDOW_SILL_CM: int = 100
const WINDOW_LIGHT_RANGE_M: float = 5.0
const PLAN_HEIGHT_M: float = 60.0
const PLAN_SIZE_M: float = 76.0


func _initialize() -> void:
	var out_dir: String = "build/v01"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out-dir="):
			out_dir = a.trim_prefix("--out-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	var d: Dictionary = DistrictBuilder.load_district()
	var world := Node3D.new()
	root.add_child(world)
	_environment(world)
	world.add_child((load(str(d["scene"])) as PackedScene).instantiate())
	var cam := Camera3D.new()
	cam.fov = FOV_DEG
	world.add_child(cam)
	cam.current = true
	var buildings: Dictionary = {}
	for b: Dictionary in d["buildings"]:
		buildings[b["id"]] = b
	var markers: Dictionary = {}
	for m: Dictionary in d["markers"]:
		markers[m["id"]] = KitBuilder.cm(m["pos_cm"])
	var failed: int = 0
	for line: Dictionary in d["sightlines"]:
		var glow := Node3D.new()
		world.add_child(glow)
		var look: Vector3 = Vector3.ZERO
		for id: String in line["to"]:
			_restore_windows(glow, buildings[id])
			look += _front_center(buildings[id])
		look /= float((line["to"] as Array).size())
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.look_at_from_position(markers[line["from"]], look)
		failed += await _shoot(out_dir.path_join("V01_%s.png" % line["from"]))
		glow.free()
	var env: Array = d["envelope_cm"]
	var mid := Vector3(float(env[0]) / 200.0, 0.0, float(env[1]) / 200.0)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = PLAN_SIZE_M
	# x to the right and z down the image, like the blueprint's (x, z) table read as screen coordinates
	cam.look_at_from_position(mid + Vector3(0.0, PLAN_HEIGHT_M, 0.0), mid, Vector3(0.0, 0.0, -1.0))
	failed += await _shoot(out_dir.path_join("V01_plan.png"))
	quit(1 if failed > 0 else 0)


func _shoot(path: String) -> int:
	for i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var err: Error = img.save_png(path)
	print(("WROTE %s (%dx%d, %s)" % [path, img.get_width(), img.get_height(), RenderingServer.get_video_adapter_name()])
		if err == OK else "FAILED %s: %s" % [path, error_string(err)])
	return 0 if err == OK else 1


## Warm pane and light in every front window_wall opening, all storeys.
func _restore_windows(parent: Node3D, b: Dictionary) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WINDOW_GLOW
	mat.emission_enabled = true
	mat.emission = WINDOW_GLOW
	mat.emission_energy_multiplier = 2.0
	var face: String = b["front"]
	for s: int in int(b["storeys"]):
		var pieces: Array = DistrictBuilder.face_pieces(b, face, b["ground"] if s == 0 else b["upper"])
		for i: int in pieces.size():
			if pieces[i] != "window_wall":
				continue
			var x: int = int(b["min_cm"][0]) + i * DistrictBuilder.MODULE_CM + DistrictBuilder.MODULE_CM / 2
			var z: int = int(b["min_cm"][1]) + 12 if face == "south" else int(b["min_cm"][1]) + int(b["size_cm"][1]) - 12
			var y: int = s * DistrictBuilder.MODULE_CM + WINDOW_SILL_CM + WINDOW_PANE_CM[1] / 2
			var pane := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = KitBuilder.cm(WINDOW_PANE_CM)
			pane.mesh = box
			pane.material_override = mat
			pane.position = KitBuilder.cm([x, y, z])
			parent.add_child(pane)
			var light := OmniLight3D.new()
			light.light_color = WINDOW_GLOW
			light.omni_range = WINDOW_LIGHT_RANGE_M
			light.position = pane.position + Vector3(0.0, 0.0, -1.0 if face == "south" else 1.0)
			parent.add_child(light)


func _front_center(b: Dictionary) -> Vector3:
	var x: int = int(b["min_cm"][0]) + int(b["size_cm"][0]) / 2
	var z: int = int(b["min_cm"][1]) if b["front"] == "south" else int(b["min_cm"][1]) + int(b["size_cm"][1])
	return KitBuilder.cm([x, 250, z])


func _environment(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	world.add_child(sun)
