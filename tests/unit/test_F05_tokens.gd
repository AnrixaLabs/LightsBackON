extends "res://tests/test_case.gd"
## F05 (cloud part): design tokens, status icon list derived from real states, theme build, kit dimensions.

const ThemeTokens := preload("res://scripts/ui/theme_tokens.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const MeterModel := preload("res://scripts/simulation/meter_model.gd")

var _tokens: Dictionary
var _states: Dictionary


func before_each() -> void:
	_tokens = _json("res://content/ui/tokens.json")
	_states = _json("res://content/ui/status_states.json")


func test_F05_tokens_match_blueprint_screen_specification() -> void:
	var want: Dictionary = {"background": "#111B25", "panel": "#1B2A38", "elevated": "#243748", "text": "#F3F5EF",
		"text_muted": "#B9C6CF", "restored": "#65D6B4", "action": "#FFC86B", "fault": "#F28B82", "unknown": "#7E93A3"}
	assert_eq(_tokens["colors"], want)
	assert_eq(int(_tokens["type_px"]["body"]), 22)
	assert_eq(int(_tokens["type_px"]["button"]), 26)
	assert_eq(int(_tokens["min_target_px"]), 48)
	assert_eq(int(_tokens["safe_area_px"]), 80)
	assert_eq([int(_tokens["ui_scale_percent"]["min"]), int(_tokens["ui_scale_percent"]["max"])], [80, 150])


func test_F05_every_real_state_has_one_icon_and_text_and_nothing_invented() -> void:
	var repair: Array = (_states["repair_states"] as Dictionary).keys()
	repair.sort()
	var code_states: Array = Interaction.STATES.duplicate()
	code_states.sort()
	assert_eq(repair, code_states, "repair icons = interaction_service STATES")
	var findings: Array = (_states["findings"] as Dictionary).keys()
	findings.sort()
	var codes: Array = MeterModel.FINDING_CODES.duplicate()
	codes.sort()
	assert_eq(findings, codes, "finding icons = meter_model FINDING_CODES")
	var icons: Dictionary = {}
	var pings: Array = (_states["pings"] as Dictionary).keys()
	pings.sort()
	var comms_types: Array = []
	for t: Dictionary in _json("res://content/comms.json")["ping_types"]:
		comms_types.append(t["id"])
	comms_types.sort()
	assert_eq(pings, comms_types, "ping icons = comms ping types")
	for group: String in ["repair_states", "findings", "supply", "other", "pings", "tools", "equipment"]:
		for state: String in _states[group]:
			var e: Dictionary = _states[group][state]
			assert_true(_tokens["colors"].has(e["color"]), "%s.%s color is a token" % [group, state])
			assert_false(str(e["text_key"]).is_empty(), "%s.%s has text (icon + text, never color only)" % [group, state])
			assert_false(icons.has(e["icon"]), "icon %s used once" % e["icon"])
			icons[e["icon"]] = true


func test_F05_finding_codes_list_matches_what_the_meter_emits() -> void:
	var src: String = FileAccess.get_file_as_string("res://scripts/simulation/meter_model.gd")
	var re: RegEx = RegEx.create_from_string("_finding\\(\"([A-Z_]+)\"")
	var emitted: Array = []
	for m: RegExMatch in re.search_all(src):
		if not emitted.has(m.get_string(1)):
			emitted.append(m.get_string(1))
	emitted.sort()
	var codes: Array = MeterModel.FINDING_CODES.duplicate()
	codes.sort()
	assert_eq(emitted, codes)


func test_F05_theme_builds_from_tokens() -> void:
	var theme: Theme = ThemeTokens.build(_tokens)
	assert_eq(theme.default_font_size, 22)
	assert_eq(theme.get_font_size("font_size", "Button"), 26)
	assert_eq(theme.get_color("font_color", "Label"), Color.html("#F3F5EF"))
	var panel: StyleBoxFlat = theme.get_stylebox("panel", "PanelContainer")
	assert_eq(panel.bg_color.a, 1.0, "text panels are opaque (contrast addendum, ADR-004)")
	var focus: StyleBoxFlat = theme.get_stylebox("focus", "Button")
	assert_eq(focus.border_color, Color.html("#FFC86B"))


func test_F05_font_is_the_recorded_licensed_noto_sans() -> void:
	var font: Dictionary = _tokens["font"]
	assert_eq(FileAccess.get_sha256(str(font["path"])), str(font["sha256"]), "committed font = the recorded download")
	assert_eq(str(font["license"]), "OFL-1.1")
	assert_true(FileAccess.get_file_as_string(str(font["license_file"])).contains("SIL Open Font License, Version 1.1"),
		"OFL text ships next to the font")
	var theme: Theme = ThemeTokens.build(_tokens)
	var body: FontVariation = theme.default_font as FontVariation
	assert_true(body != null and body.base_font != null, "theme font is the variable font at a set weight")
	if body == null or body.base_font == null:
		return
	assert_eq(body.base_font.get_font_name(), "Noto Sans")
	var wght: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	assert_eq(int(body.variation_opentype[wght]), 400, "body weight")
	for t: String in ["Button", "HeaderLarge", "HeaderMedium"]:
		var strong: FontVariation = theme.get_font("font", t) as FontVariation
		assert_eq(int(strong.variation_opentype[wght]) if strong else -1, 600, "%s weight" % t)
	# Latin UI text, the unknown reading, pseudo-locale accents (blueprint p.11 35 % expansion test), the PU unit
	for ch: String in "AZaz09?!%/:-+ÀÉÎÕÜçñßØå".split(""):
		assert_true(body.base_font.has_char(ch.unicode_at(0)), "glyph %s" % ch)


func test_F05_kit_and_interaction_dimensions_agree() -> void:
	var kit: Dictionary = _json("res://content/world/kit_dimensions.json")
	assert_eq(int(kit["module_cm"]), 400)
	assert_eq(int(kit["module_cm"]) % int(kit["placement_increment_cm"]), 0, "module is a whole number of increments")
	assert_true(int(kit["panel_height_min_cm"]) == 120 and int(kit["panel_height_max_cm"]) == 160)
	assert_true(int(kit["circulation_min_width_cm"]) >= 240 and int(kit["door_clear_width_min_cm"]) >= 110)
	assert_eq(int(kit["interact_ray_cm"]), int(_json("res://content/interaction.json")["ray_length_cm"]), "one source for the 2.3 m ray")


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
