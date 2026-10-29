extends RefCounted
## UI strings by localization key (blueprint p.11: every string is a key from the first UI pass, none baked into images).
## English comes from content/ui/strings/en.json. The pseudo-locale stretches every English string by 35 % and accents its
## letters, so layouts are tested against longer text before translation (blueprint p.11, UX03). Simplified Chinese waits for
## the localization task and its fallback font (ADR-004 font addendum point 4).
## Binding labels read the live InputMap, so a remapped action shows its new key (ADR-004 point 3).

const STRINGS_PATH: String = "res://content/ui/strings/en.json"
const LOCALE_EN: String = "en"
const LOCALE_PSEUDO: String = "pseudo"
const PSEUDO_EXPANSION_PERCENT: int = 35
const PSEUDO_PAD: String = "~"
const DEVICE_KBM: String = "kbm"
const DEVICE_PAD: String = "pad"
const ACCENTS: Dictionary = {"a": "á", "e": "é", "i": "í", "o": "ö", "u": "ü", "c": "ç", "n": "ñ", "y": "ý", "A": "Á", "E": "É",
	"I": "Í", "O": "Ö", "U": "Ü", "C": "Ç", "N": "Ñ"}
const MOUSE_KEYS: Dictionary = {MOUSE_BUTTON_LEFT: "input.mouse.left", MOUSE_BUTTON_RIGHT: "input.mouse.right",
	MOUSE_BUTTON_MIDDLE: "input.mouse.middle", MOUSE_BUTTON_WHEEL_UP: "input.mouse.wheel_up",
	MOUSE_BUTTON_WHEEL_DOWN: "input.mouse.wheel_down"}
const PAD_BUTTON_KEYS: Dictionary = {JOY_BUTTON_A: "input.pad.a", JOY_BUTTON_B: "input.pad.b", JOY_BUTTON_X: "input.pad.x",
	JOY_BUTTON_Y: "input.pad.y", JOY_BUTTON_BACK: "input.pad.back", JOY_BUTTON_START: "input.pad.start",
	JOY_BUTTON_LEFT_SHOULDER: "input.pad.lb", JOY_BUTTON_RIGHT_SHOULDER: "input.pad.rb", JOY_BUTTON_LEFT_STICK: "input.pad.ls",
	JOY_BUTTON_RIGHT_STICK: "input.pad.rs"}
const PAD_AXIS_KEYS: Dictionary = {JOY_AXIS_TRIGGER_LEFT: "input.pad.lt", JOY_AXIS_TRIGGER_RIGHT: "input.pad.rt"}

static var _strings: Dictionary = {}
static var _locale: String = LOCALE_EN
static var _missing: Dictionary = {}


static func set_locale(locale: String) -> void:
	_locale = locale


static func locale() -> String:
	return _locale


## The string for a key in the current locale. A missing key shows the key itself and is recorded (tests fail on it).
static func t(key: String) -> String:
	var table: Dictionary = _table()
	if not table.has(key):
		_missing[key] = true
		return key
	var text: String = table[key]
	return pseudo(text) if _locale == LOCALE_PSEUDO else text


## t() with %s / %d arguments; arguments are inserted after localization so numbers and IDs are not accented.
static func tf(key: String, args: Array) -> String:
	return t(key) % args


static func has(key: String) -> bool:
	return _table().has(key)


static func missing() -> Array[String]:
	var out: Array[String] = []
	out.assign(_missing.keys())
	out.sort()
	return out


static func clear_missing() -> void:
	_missing.clear()


## Accented and 35 % longer, keeping %s / %d placeholders intact. Padding is spread over the words so wrapping is exercised
## the way a longer translation would exercise it.
static func pseudo(text: String) -> String:
	var words: PackedStringArray = text.split(" ")
	var extra: int = ceili(text.length() * PSEUDO_EXPANSION_PERCENT / 100.0)
	var per_word: int = ceili(float(extra) / float(maxi(1, words.size())))
	var out: Array[String] = []
	for w: String in words:
		var accented: String = ""
		var i: int = 0
		while i < w.length():
			var ch: String = w[i]
			if ch == "%" and i + 1 < w.length():
				accented += w.substr(i, 2)  # a format placeholder stays as it is
				i += 2
				continue
			accented += ACCENTS.get(ch, ch)
			i += 1
		var pad: int = mini(per_word, extra)
		extra -= pad
		out.append(accented + PSEUDO_PAD.repeat(pad))
	return " ".join(out)


## Text label of the first binding of an action for a device, e.g. "E", "Tab", "MMB", "A", "LB".
static func binding(action: String, device: String) -> String:
	if not InputMap.has_action(action):
		return t("input.unbound")
	for ev: InputEvent in InputMap.action_get_events(action):
		var label: String = _event_label(ev, device)
		if label != "":
			return label
	return t("input.unbound")


static func _event_label(ev: InputEvent, device: String) -> String:
	if device == DEVICE_KBM:
		if ev is InputEventKey:
			var k: InputEventKey = ev
			var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			if k.physical_keycode != KEY_NONE and DisplayServer.get_name() != "headless":
				code = DisplayServer.keyboard_get_label_from_physical(k.physical_keycode)  # the key cap on this layout
			return OS.get_keycode_string(code)
		if ev is InputEventMouseButton:
			return t(MOUSE_KEYS.get((ev as InputEventMouseButton).button_index, "input.unbound"))
		return ""
	if ev is InputEventJoypadButton:
		var b: JoyButton = (ev as InputEventJoypadButton).button_index
		if b >= JOY_BUTTON_DPAD_UP and b <= JOY_BUTTON_DPAD_RIGHT:
			return t("input.pad.dpad")
		return t(PAD_BUTTON_KEYS.get(b, "input.unbound"))
	if ev is InputEventJoypadMotion:
		var axis: JoyAxis = (ev as InputEventJoypadMotion).axis
		return t(PAD_AXIS_KEYS.get(axis, "input.pad.stick"))
	return ""


static func _table() -> Dictionary:
	if _strings.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_PATH))
		_strings = (data as Dictionary)["strings"] if data is Dictionary else {}
	return _strings
