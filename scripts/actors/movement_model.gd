extends RefCounted
## Deterministic player movement step (V05), shared by the host simulation and client prediction so both compute the
## same result from the same input. Fixed point on purpose: positions in integer mm, inputs quantized to
## -input_axis_max..input_axis_max per world axis, one step per 30 Hz host tick. Integer maths gives bit-identical
## results on every machine, so reconciliation only corrects for real divergence (lost input, host-side rules).
##
## The client turns its camera yaw into a world-space move vector before sending; the host never needs trig and only
## clamps the vector's length. No collision yet: the V01 graybox adds the world (CharacterBody3D) around this step.

var host_hz: int
var _axis_max: int
var _speeds: Dictionary = {}


func configure(tuning: Dictionary) -> void:
	host_hz = int(tuning["host_hz"])
	_axis_max = int(tuning["input_axis_max"])
	for k: String in ["walk_mm_s", "sprint_mm_s", "carry_mm_s", "crouch_mm_s"]:
		_speeds[k] = int(tuning[k])


## input: {"seq": int, "x": int, "z": int, "sprint": bool, "crouch": bool}; carrying comes from host equipment state.
## Returns the new position (Vector3i, mm). The y axis (height) is untouched until the graybox adds floors.
func step(pos_mm: Vector3i, input: Dictionary, carrying: bool) -> Vector3i:
	var x: int = clampi(int(input.get("x", 0)), -_axis_max, _axis_max)
	var z: int = clampi(int(input.get("z", 0)), -_axis_max, _axis_max)
	var len_sq: int = x * x + z * z
	var max_sq: int = _axis_max * _axis_max
	if len_sq > max_sq:
		# diagonal (127, 127) must not be faster than straight ahead: scale to the unit circle with integer maths
		var length: int = _isqrt(len_sq)
		x = x * _axis_max / length
		z = z * _axis_max / length
	var speed: int = _speeds["walk_mm_s"]
	if carrying:
		speed = _speeds["carry_mm_s"]  # carrying the generator caps speed even while sprinting (p.8)
	elif input.get("crouch", false) == true:
		speed = _speeds["crouch_mm_s"]
	elif input.get("sprint", false) == true:
		speed = _speeds["sprint_mm_s"]
	var denom: int = _axis_max * host_hz
	return pos_mm + Vector3i(speed * x / denom, 0, speed * z / denom)


static func _isqrt(n: int) -> int:
	if n <= 0:
		return 0
	var r: int = int(sqrt(float(n)))
	while r * r > n:
		r -= 1
	while (r + 1) * (r + 1) <= n:
		r += 1
	return r
