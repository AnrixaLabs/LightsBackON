extends "res://tests/test_case.gd"
## F01: project settings that later tasks rely on (renderer baseline, input defaults from blueprint p.8).

const KEYBOARD_MOUSE_AND_PAD: Array[String] = [
	"move_forward", "move_back", "move_left", "move_right", "interact", "tool_primary", "tool_secondary",
	"drop_item", "map_meter", "ping", "sprint", "crouch", "pause",
]
const PAD_ONLY: Array[String] = ["look_up", "look_down", "look_left", "look_right", "tool_radial"]
const KEYBOARD_MOUSE_ONLY: Array[String] = ["tool_slot_1", "tool_slot_2", "tool_slot_3", "tool_slot_4", "tool_next", "tool_prev"]


func test_F01_compatibility_renderer_is_baseline() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile"), "gl_compatibility")


func test_F01_every_action_has_keyboard_mouse_and_controller_defaults() -> void:
	for a: String in KEYBOARD_MOUSE_AND_PAD:
		assert_true(InputMap.has_action(a), "missing action %s" % a)
		assert_true(_has_kbm(a), "%s has no keyboard/mouse default" % a)
		assert_true(_has_pad(a), "%s has no controller default" % a)
	for a: String in PAD_ONLY:
		assert_true(InputMap.has_action(a) and _has_pad(a), "%s needs a controller default" % a)
	for a: String in KEYBOARD_MOUSE_ONLY:
		assert_true(InputMap.has_action(a) and _has_kbm(a), "%s needs a keyboard/mouse default" % a)


func test_F01_interact_defaults_match_blueprint() -> void:
	var key_ok: bool = false
	var pad_ok: bool = false
	for e: InputEvent in InputMap.action_get_events("interact"):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_E:
			key_ok = true
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			pad_ok = true
	assert_true(key_ok, "interact = E")
	assert_true(pad_ok, "interact = south face button")


func test_F01_actions_are_remappable_at_runtime() -> void:
	var original: Array[InputEvent] = InputMap.action_get_events("interact")
	var replacement := InputEventKey.new()
	replacement.physical_keycode = KEY_F
	InputMap.action_erase_events("interact")
	InputMap.action_add_event("interact", replacement)
	assert_eq(InputMap.action_get_events("interact").size(), 1)
	InputMap.action_erase_events("interact")
	for e: InputEvent in original:
		InputMap.action_add_event("interact", e)
	assert_eq(InputMap.action_get_events("interact").size(), original.size())


func _has_kbm(action: String) -> bool:
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			return true
	return false


func _has_pad(action: String) -> bool:
	for e: InputEvent in InputMap.action_get_events(action):
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			return true
	return false
