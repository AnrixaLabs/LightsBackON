extends SceneTree
## Renders the V07 field HUD over the V01 graybox (from the van eye toward the west services) and the network tablet, on the
## real GPU, and measures WCAG contrast of every HUD text and icon against the pixels actually rendered behind it (F05's last
## open item, ADR-004 point 3). Needs a GPU window, so it does not run headless or in CI.
##   godot --path . --resolution 1920x1080 -s "$PWD/tools/godot/capture_hud.gd" -- --out-dir=build/v07
## Writes <out-dir>/V07_hud_<light>_<scale>.png, V07_tablet_<scale>.png and V07_contrast.json. Exit 0 = every probe passes.
##
## Method: each view is drawn twice. Frame A is the HUD as shown. Frame B is the same layout with only the ink hidden (label
## text, icons, the reticle, map edges: alpha 0), so B holds the real background under every glyph: opaque panels over the
## 3D scene, the scene itself under the reticle. For each probe the worst pixel decides: min over B pixels in the probe rect
## of contrast(token color, pixel). "rendered_peak" is the best A-vs-B contrast in the rect, a check that the glyphs drew.
## Thresholds (WCAG 2.2 AA): 4.5:1 body text, 3:1 large text (>= 24 px, blueprint large_text_px) and icons/graphics.
## Lighting: "dark" is the graybox as built; "restored" adds warm emissive panes and lights in the west windows, as
## capture_district_views.gd does (the presentation layer that drives real window states does not exist yet).

const Fixture := preload("res://tests/support/ui_fixture.gd")
const KitBuilder := preload("res://scripts/world/kit_builder.gd")
const DistrictBuilder := preload("res://scripts/world/district_builder.gd")
const FieldHud := preload("res://scripts/ui/field_hud.gd")
const NetworkTablet := preload("res://scripts/ui/network_tablet.gd")
const IntentOutbox := preload("res://scripts/ui/intent_outbox.gd")
const Runner := preload("res://tests/support/solution_runner.gd")
const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")

const SETTLE_FRAMES: int = 12
const FOV_DEG: float = 75.0
const SKY := Color(0.42, 0.5, 0.58)
const AMBIENT := Color(0.55, 0.62, 0.7)
const WINDOW_GLOW := Color(1.0, 0.8, 0.45)
const WINDOW_PANE_CM: Array[int] = [150, 150, 5]
const WINDOW_SILL_CM: int = 100
const WINDOW_LIGHT_RANGE_M: float = 5.0
const BODY_MIN: float = 4.5
const LARGE_MIN: float = 3.0
const ICON_MIN: float = 3.0
const SCALES: Array[int] = [100, 150]
const FONT_COLOR_KEYS: Array[String] = ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
	"font_hover_pressed_color", "font_disabled_color"]

var _tokens: Dictionary
var _report: Array[Dictionary] = []
var _failed: int = 0


func _initialize() -> void:
	var out_dir: String = "build/v07"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out-dir="):
			out_dir = a.trim_prefix("--out-dir=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_tokens = Runner.json("res://content/ui/tokens.json")
	var ctx: Dictionary = Fixture.mid_shift()
	var d: Dictionary = DistrictBuilder.load_district()
	var world := Node3D.new()
	root.add_child(world)
	_environment(world)
	world.add_child((load(str(d["scene"])) as PackedScene).instantiate())
	var cam := Camera3D.new()
	cam.fov = FOV_DEG
	world.add_child(cam)
	cam.current = true
	var line: Dictionary = d["sightlines"][0]  # VAN_EYE -> APT_W, MARKET: the first restoration seen from the van
	var markers: Dictionary = {}
	for m: Dictionary in d["markers"]:
		markers[m["id"]] = KitBuilder.cm(m["pos_cm"])
	var buildings: Dictionary = {}
	for b: Dictionary in d["buildings"]:
		buildings[b["id"]] = b
	var look: Vector3 = Vector3.ZERO
	for id: String in line["to"]:
		look += _front_center(buildings[id])
	cam.look_at_from_position(markers[line["from"]], look / float((line["to"] as Array).size()))
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var hud: Container = FieldHud.new()
	layer.add_child(hud)
	hud.apply(Fixture.hud_view(ctx))
	var glow := Node3D.new()
	world.add_child(glow)
	for light: String in ["dark", "restored"]:
		if light == "restored":
			for id: String in line["to"]:
				_restore_windows(glow, buildings[id])
		for scale: int in SCALES:
			hud.set_ui_scale(scale)
			await _measure(hud, "hud_%s_%d" % [light, scale], out_dir)
	hud.visible = false
	var outbox: RefCounted = IntentOutbox.new(Runner.SESSION, func(_b: PackedByteArray) -> Dictionary: return {})
	var tablet: PanelContainer = NetworkTablet.new()
	layer.add_child(tablet)
	tablet.setup(outbox)
	tablet.show_data(Fixture.tablet_view(ctx), ctx["mission"].objectives())
	tablet.select("JE")
	for scale: int in SCALES:
		tablet.set_ui_scale(scale)
		await process_frame
		tablet.open()
		await _measure(tablet, "tablet_%d" % scale, out_dir)
	var f := FileAccess.open(out_dir.path_join("V07_contrast.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"resolution": [root.size.x, root.size.y], "failed": _failed, "probes": _report}, "  ", false))
	f.close()
	print("CONTRAST %s: %d probes, %d below AA (%s)" % ["PASS" if _failed == 0 else "FAIL", _report.size(), _failed,
		RenderingServer.get_video_adapter_name()])
	quit(0 if _failed == 0 else 1)


func _measure(view: Control, label: String, out_dir: String) -> void:
	for i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var shown: Image = root.get_texture().get_image()
	var path: String = out_dir.path_join("V07_%s.png" % label)
	shown.save_png(path)
	print("WROTE %s (%dx%d)" % [path, shown.get_width(), shown.get_height()])
	var probes: Array[Dictionary] = _probes(view)
	_hide_ink(view, true)
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var behind: Image = root.get_texture().get_image()
	_hide_ink(view, false)
	var worst: float = INF
	for p: Dictionary in probes:
		var r: Dictionary = _score(p, shown, behind)
		r["view"] = label
		_report.append(r)
		worst = minf(worst, float(r["worst"]) / float(r["min"]))
		if not r["pass"]:
			_failed += 1
			print("  BELOW AA %s %s %s: %.2f < %.1f" % [label, r["kind"], r["what"], r["worst"], r["min"]])
	print("  %s: %d probes, worst margin x%.2f of the AA minimum" % [label, probes.size(), worst])


## Text and icon probes: what is drawn, its rect on screen, its intended color and the AA minimum for its kind.
func _probes(view: Control) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c: Control in Fixture.controls(view):
		if not c.is_visible_in_tree():
			continue
		var rect: Rect2 = _visible_rect(c)
		if rect.size.x < 1.0 or rect.size.y < 1.0:
			continue  # scrolled or panned out of view: nothing of it is on screen
		if c is Label and (c as Label).text.strip_edges() != "":
			var l: Label = c
			var px: int = l.get_theme_font_size("font_size")
			var large: bool = px >= int(_tokens["large_text_px"])
			out.append({"what": l.text.left(40), "kind": "large_text" if large else "body_text", "rect": rect, "fg": l.get_theme_color("font_color"),
				"min": LARGE_MIN if large else BODY_MIN, "px": px})
		elif c is Button and (c as Button).text != "":
			var b: Button = c
			var box: StyleBox = b.get_theme_stylebox("normal")
			var inner: Rect2 = rect.grow_individual(-box.get_margin(SIDE_LEFT), -box.get_margin(SIDE_TOP), -box.get_margin(SIDE_RIGHT),
				-box.get_margin(SIDE_BOTTOM))
			var bpx: int = b.get_theme_font_size("font_size")
			var blarge: bool = bpx >= int(_tokens["large_text_px"])
			out.append({"what": b.text.left(40), "kind": "large_text" if blarge else "body_text", "rect": inner,
				"fg": b.get_theme_color("font_color"), "min": LARGE_MIN if blarge else BODY_MIN, "px": bpx})
		elif c is TextureRect and (c as TextureRect).texture != null:
			out.append({"what": str(c.get_meta("icon", (c as TextureRect).texture.resource_path.get_file())), "kind": "icon", "rect": rect,
				"fg": c.self_modulate, "min": ICON_MIN})
		elif c.get_script() == preload("res://scripts/ui/reticle.gd"):
			out.append({"what": "reticle", "kind": "reticle", "rect": rect, "fg": c.get("ink"), "fg2": c.get("outline"), "min": ICON_MIN})
		elif c.get_script() == preload("res://scripts/ui/tablet_map.gd"):
			var nodes: Array[Rect2] = []
			for n: Node in c.get_children():
				nodes.append((n as Control).get_global_rect().grow(ThemeTokens.px(8, float(view.get("scale_percent")))))
			for token: String in ["restored", "action", "fault", "unknown"]:
				out.append({"what": "map edge " + token, "kind": "graphic", "rect": rect, "fg": ThemeTokens.color(_tokens, token), "min": ICON_MIN,
					"sample_only_bg": true, "exclude": nodes})  # edges run over the map background between the nodes
	return out


## The part of a control left on screen by every clipping ancestor (scroll panels, the map).
func _visible_rect(c: Control) -> Rect2:
	var rect: Rect2 = c.get_global_rect()
	var a: Node = c.get_parent()
	while a is Control:
		if (a as Control).clip_contents:
			rect = rect.intersection((a as Control).get_global_rect())
		a = a.get_parent()
	return rect


func _hide_ink(view: Control, hide: bool) -> void:
	for c: Control in Fixture.controls(view):
		if c is Label or c is TextureRect or c.get_script() == preload("res://scripts/ui/reticle.gd") \
				or c.get_script() == preload("res://scripts/ui/tablet_map.gd"):
			var m: Color = c.self_modulate
			m.a = 0.0 if hide else 1.0
			c.self_modulate = m
		elif c is Button:
			for key: String in FONT_COLOR_KEYS:
				if hide:
					c.add_theme_color_override(key, Color(0, 0, 0, 0))
				else:
					c.remove_theme_color_override(key)


func _score(p: Dictionary, shown: Image, behind: Image) -> Dictionary:
	var r: Rect2i = Rect2i(Rect2(p["rect"])).intersection(Rect2i(0, 0, behind.get_width(), behind.get_height()))
	var fg: Color = p["fg"]
	var worst: float = INF
	var peak: float = 0.0
	var step: int = 2 if r.size.x * r.size.y > 40000 else 1
	for y: int in range(r.position.y, r.end.y, step):
		for x: int in range(r.position.x, r.end.x, step):
			if p.has("exclude") and (p["exclude"] as Array).any(func(e: Rect2) -> bool: return e.has_point(Vector2(x, y))):
				continue
			var bg: Color = behind.get_pixel(x, y)
			var c: float = _contrast(fg, bg)
			if p["kind"] == "reticle":
				c = maxf(c, _contrast(p["fg2"], bg))  # two-tone: either tone separates it from this pixel
			worst = minf(worst, c)
			if not p.get("sample_only_bg", false):
				peak = maxf(peak, _contrast(shown.get_pixel(x, y), bg))
	var out: Dictionary = {"what": p["what"], "kind": p["kind"], "rect": [r.position.x, r.position.y, r.size.x, r.size.y],
		"fg": "#" + fg.to_html(false), "min": p["min"], "worst": snappedf(worst, 0.01), "rendered_peak": snappedf(peak, 0.01),
		"pass": worst >= float(p["min"])}
	if p.has("px"):
		out["px"] = p["px"]
	return out


static func _contrast(a: Color, b: Color) -> float:
	var la: float = _luminance(a)
	var lb: float = _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _luminance(c: Color) -> float:
	var ch: Array[float] = []
	for v: float in [c.r, c.g, c.b]:
		ch.append(v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


## Warm pane and light in every front window_wall opening (same stand-in as capture_district_views.gd).
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
	sun.shadow_enabled = true
	world.add_child(sun)
