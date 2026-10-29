extends SceneTree
## Writes the default input actions (blueprint section 6, p.8) into res://project.godot.
## tools/ is Godot-ignored, so run it by absolute path from the repo root:
##   godot --headless --path . -s "$PWD/tools/godot/generate_input_map.gd"
## Every action here is remappable at runtime through InputMap; these are only the defaults.
## Keyboard keys use physical keycodes so WASD stays in place on AZERTY/QWERTZ layouts.
## Hold/radial behaviour (drop = hold west, tool radial = hold right bumper) is decided in code, not here.

const DEADZONE_STICK: float = 0.2
const DEADZONE_BUTTON: float = 0.5

# action -> list of [kind, code, axis_sign]; kind: "key" | "mouse" | "joy_button" | "joy_axis"
const ACTIONS: Dictionary = {
	"move_forward": [["key", KEY_W, 0], ["joy_axis", JOY_AXIS_LEFT_Y, -1]],
	"move_back": [["key", KEY_S, 0], ["joy_axis", JOY_AXIS_LEFT_Y, 1]],
	"move_left": [["key", KEY_A, 0], ["joy_axis", JOY_AXIS_LEFT_X, -1]],
	"move_right": [["key", KEY_D, 0], ["joy_axis", JOY_AXIS_LEFT_X, 1]],
	# mouse look is read from InputEventMouseMotion; these are the controller look axes
	"look_up": [["joy_axis", JOY_AXIS_RIGHT_Y, -1]],
	"look_down": [["joy_axis", JOY_AXIS_RIGHT_Y, 1]],
	"look_left": [["joy_axis", JOY_AXIS_RIGHT_X, -1]],
	"look_right": [["joy_axis", JOY_AXIS_RIGHT_X, 1]],
	"interact": [["key", KEY_E, 0], ["joy_button", JOY_BUTTON_A, 0]],
	"tool_primary": [["mouse", MOUSE_BUTTON_LEFT, 0], ["joy_axis", JOY_AXIS_TRIGGER_RIGHT, 1]],
	"tool_secondary": [["mouse", MOUSE_BUTTON_RIGHT, 0], ["joy_axis", JOY_AXIS_TRIGGER_LEFT, 1]],
	"tool_slot_1": [["key", KEY_1, 0]],
	"tool_slot_2": [["key", KEY_2, 0]],
	"tool_slot_3": [["key", KEY_3, 0]],
	"tool_slot_4": [["key", KEY_4, 0]],
	"tool_next": [["mouse", MOUSE_BUTTON_WHEEL_DOWN, 0]],
	"tool_prev": [["mouse", MOUSE_BUTTON_WHEEL_UP, 0]],
	"tool_radial": [["joy_button", JOY_BUTTON_RIGHT_SHOULDER, 0]],
	"drop_item": [["key", KEY_G, 0], ["joy_button", JOY_BUTTON_X, 0]],
	"map_meter": [["key", KEY_TAB, 0], ["joy_button", JOY_BUTTON_BACK, 0]],
	"ping": [["mouse", MOUSE_BUTTON_MIDDLE, 0], ["joy_button", JOY_BUTTON_LEFT_SHOULDER, 0]],
	"sprint": [["key", KEY_SHIFT, 0], ["joy_button", JOY_BUTTON_LEFT_STICK, 0]],
	"crouch": [["key", KEY_CTRL, 0], ["joy_button", JOY_BUTTON_RIGHT_STICK, 0]],
	"pause": [["key", KEY_ESCAPE, 0], ["joy_button", JOY_BUTTON_START, 0]],
	# menus and the network tablet (V07): Godot's built-in ui_accept / ui_cancel have no controller button, so A and B are added
	"ui_accept": [["key", KEY_ENTER, 0], ["key", KEY_KP_ENTER, 0], ["key", KEY_SPACE, 0], ["joy_button", JOY_BUTTON_A, 0]],
	"ui_cancel": [["key", KEY_ESCAPE, 0], ["joy_button", JOY_BUTTON_B, 0]],
}


func _initialize() -> void:
	var names: Array = ACTIONS.keys()
	names.sort()
	for action_name: String in names:
		var events: Array[InputEvent] = []
		var uses_stick: bool = false
		for spec: Array in ACTIONS[action_name]:
			events.append(_make_event(spec))
			if spec[0] == "joy_axis" and int(spec[1]) <= JOY_AXIS_RIGHT_Y:
				uses_stick = true
		var deadzone: float = DEADZONE_STICK if uses_stick else DEADZONE_BUTTON
		ProjectSettings.set_setting("input/" + action_name, {"deadzone": deadzone, "events": events})
	var err: Error = ProjectSettings.save()
	print("input actions written: %d (err=%d)" % [names.size(), err])
	quit(0 if err == OK else 1)


func _make_event(spec: Array) -> InputEvent:
	var kind: String = spec[0]
	var code: int = spec[1]
	match kind:
		"key":
			var k := InputEventKey.new()
			k.device = -1  # any keyboard, like editor-created events
			k.physical_keycode = code as Key
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.device = -1
			m.button_index = code as MouseButton
			return m
		"joy_button":
			var b := InputEventJoypadButton.new()
			b.device = -1
			b.button_index = code as JoyButton
			return b
		_:
			var a := InputEventJoypadMotion.new()
			a.device = -1
			a.axis = code as JoyAxis
			a.axis_value = float(spec[2])
			return a
