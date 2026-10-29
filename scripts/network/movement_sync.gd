extends RefCounted
## Movement replication (V05; blueprint p.10: 30 Hz host movement, 15 Hz snapshots, ~100 ms remote interpolation,
## local prediction and reconciliation; CLAUDE.md section 4: clients send intentions only).
##
## HostMovement   host-authoritative positions. Clients send inputs (never positions); each packet repeats the last few
##                inputs so a lost packet loses nothing. The host applies at most one input per tick per player and keeps a
##                small buffer, so sending inputs faster than 30 Hz does not move anyone faster.
## Predictor      client-side prediction: applies its own inputs at once, then on each snapshot resets to the host
##                position at the acknowledged input and replays the rest (reconciliation).
## Interpolator   remote players drawn interpolation_delay_ms behind the estimated host clock between 15 Hz
##                snapshots; a lost snapshot is bridged by at most one snapshot interval of extrapolation.
## Smoother       cosmetic easing for anchored equipment between host-decided anchors (the host decides, clients ease).
## All pure: no scene tree; time is passed in (ms or ticks).

const Model := preload("res://scripts/actors/movement_model.gd")


class HostMovement:
	var _model: Model
	var _redundancy: int
	var _max_buffer: int
	var _axis_max: int
	var _pos: Dictionary = {}  # player -> Vector3i mm
	var _ack: Dictionary = {}  # player -> last applied input seq
	var _buffer: Dictionary = {}  # player -> Array[Dictionary] inputs, ascending seq
	var _last: Dictionary = {}  # player -> last applied input (repeated never; idle means stand still)

	func _init(model: Model, tuning: Dictionary) -> void:
		_model = model
		_redundancy = int(tuning["input_redundancy"])
		_max_buffer = int(tuning["max_buffered_inputs"])
		_axis_max = int(tuning["input_axis_max"])

	func spawn(player: String, pos_mm: Vector3i) -> void:
		_pos[player] = pos_mm
		_ack[player] = 0
		_buffer[player] = [] as Array[Dictionary]

	## A packet of up to input_redundancy inputs. Anything other than seq/x/z/sprint/crouch is ignored, positions included.
	## Returns how many new inputs were accepted.
	func receive(player: String, inputs: Array) -> int:
		if not _pos.has(player):
			return 0
		var buf: Array[Dictionary] = _buffer[player]
		var accepted: int = 0
		for raw: Variant in inputs.slice(0, _redundancy):
			if not raw is Dictionary:
				continue
			var seq: Variant = raw.get("seq")
			if not (seq is int or seq is float) or int(seq) <= int(_ack[player]):
				continue
			if buf.any(func(b: Dictionary) -> bool: return b["seq"] == int(seq)):
				continue
			if buf.size() >= _max_buffer:
				break  # a client sending faster than the host ticks only fills the buffer; the rest is dropped
			buf.append({"seq": int(seq), "x": clampi(int(raw.get("x", 0)), -_axis_max, _axis_max),
				"z": clampi(int(raw.get("z", 0)), -_axis_max, _axis_max),
				"sprint": raw.get("sprint") == true, "crouch": raw.get("crouch") == true})
			accepted += 1
		buf.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["seq"] < b["seq"])
		return accepted

	## One 30 Hz host tick: each player consumes their oldest buffered input. carrying: player -> bool from equipment.
	func tick(carrying: Dictionary) -> void:
		for player: String in _pos:
			var buf: Array[Dictionary] = _buffer[player]
			if buf.is_empty():
				continue
			var input: Dictionary = buf.pop_front()
			_pos[player] = _model.step(_pos[player], input, carrying.get(player, false))
			_ack[player] = input["seq"]

	## 15 Hz snapshot: authoritative position and the last applied input seq per player.
	func snapshot() -> Dictionary:
		var out: Dictionary = {}
		for player: String in _pos:
			var p: Vector3i = _pos[player]
			out[player] = {"pos": [p.x, p.y, p.z], "ack": _ack[player]}
		return out

	func position_of(player: String) -> Vector3i:
		return _pos.get(player, Vector3i.ZERO)


class Predictor:
	var _model: Model
	var _redundancy: int
	var _seq: int = 0
	var _pending: Array[Dictionary] = []
	var predicted: Vector3i = Vector3i.ZERO
	var corrections: int = 0  # snapshots that moved the predicted position
	var max_correction_mm: int = 0

	func _init(model: Model, tuning: Dictionary, start_mm: Vector3i) -> void:
		_model = model
		_redundancy = int(tuning["input_redundancy"])
		predicted = start_mm

	## Applies a local input immediately and returns the packet to send (the last input_redundancy inputs).
	func input(x: int, z: int, sprint: bool, crouch: bool, carrying: bool) -> Array[Dictionary]:
		_seq += 1
		var inp: Dictionary = {"seq": _seq, "x": x, "z": z, "sprint": sprint, "crouch": crouch, "carrying": carrying}
		_pending.append(inp)
		predicted = _model.step(predicted, inp, carrying)
		var packet: Array[Dictionary] = []
		for p: Dictionary in _pending.slice(maxi(0, _pending.size() - _redundancy)):
			var sent: Dictionary = p.duplicate()
			sent.erase("carrying")  # the host uses its own carry state
			packet.append(sent)
		return packet

	## Reconciliation: start from the host position at the acknowledged input and replay everything newer.
	func on_snapshot(host_pos: Array, ack: int) -> void:
		var keep: Array[Dictionary] = []
		for p: Dictionary in _pending:
			if int(p["seq"]) > ack:
				keep.append(p)
		_pending = keep
		var pos: Vector3i = Vector3i(int(host_pos[0]), int(host_pos[1]), int(host_pos[2]))
		for p: Dictionary in _pending:
			pos = _model.step(pos, p, p["carrying"])
		var delta: Vector3i = pos - predicted
		var moved: int = absi(delta.x) + absi(delta.y) + absi(delta.z)
		if moved > 0:
			corrections += 1
			max_correction_mm = maxi(max_correction_mm, moved)
		predicted = pos


class Interpolator:
	var _delay_ms: int
	var _max_extrapolate_ms: int
	var _offset_ms: int = 2147483647  # smallest (arrival - host time) seen: the client's estimate of the host clock
	var _samples: Array[Dictionary] = []  # {"t": host ms, "pos": Vector3}

	func _init(tuning: Dictionary) -> void:
		_delay_ms = int(tuning["interpolation_delay_ms"])
		# a lost 15 Hz snapshot leaves one extra gap; cover it by extrapolating instead of freezing and then snapping
		_max_extrapolate_ms = 1000 / int(tuning["snapshot_hz"])

	## host_time_ms: when the host took the snapshot; arrival_ms: local clock when it arrived.
	func add(host_time_ms: int, pos_mm: Array, arrival_ms: int) -> void:
		_offset_ms = mini(_offset_ms, arrival_ms - host_time_ms)
		_samples.append({"t": host_time_ms, "pos": Vector3(float(pos_mm[0]), float(pos_mm[1]), float(pos_mm[2]))})
		_samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
		while _samples.size() > 32:
			_samples.pop_front()

	## Position (mm, float for rendering) delay ms behind the estimated host clock. Between samples: linear
	## interpolation. Past the newest sample: brief extrapolation along the last segment, then hold.
	func sample(now_ms: int) -> Vector3:
		if _samples.is_empty():
			return Vector3.ZERO
		var t: int = now_ms - _offset_ms - _delay_ms
		if t <= int(_samples[0]["t"]):
			return _samples[0]["pos"]
		for i: int in range(1, _samples.size()):
			var b: Dictionary = _samples[i]
			if t <= int(b["t"]):
				var a: Dictionary = _samples[i - 1]
				var w: float = float(t - int(a["t"])) / float(maxi(1, int(b["t"]) - int(a["t"])))
				return (a["pos"] as Vector3).lerp(b["pos"], w)
		var last: Dictionary = _samples[-1]
		if _samples.size() < 2:
			return last["pos"]
		var prev: Dictionary = _samples[-2]
		var span: int = maxi(1, int(last["t"]) - int(prev["t"]))
		var ahead: int = mini(t - int(last["t"]), _max_extrapolate_ms)
		return (last["pos"] as Vector3) + ((last["pos"] as Vector3) - (prev["pos"] as Vector3)) * (float(ahead) / float(span))


class Smoother:
	var _from: Vector3
	var _to: Vector3
	var _start_ms: int
	var _duration_ms: int

	func _init(at: Vector3) -> void:
		_from = at
		_to = at
		_start_ms = 0
		_duration_ms = 0

	## The host moved the item to a new anchor: ease towards it from wherever it is drawn now.
	func retarget(to: Vector3, now_ms: int, duration_ms: int) -> void:
		_from = position(now_ms)
		_to = to
		_start_ms = now_ms
		_duration_ms = duration_ms

	func position(now_ms: int) -> Vector3:
		if _duration_ms <= 0 or now_ms >= _start_ms + _duration_ms:
			return _to
		var w: float = clampf(float(now_ms - _start_ms) / float(_duration_ms), 0.0, 1.0)
		return _from.lerp(_to, w * w * (3.0 - 2.0 * w))  # smoothstep: cosmetic only; the anchor itself is authoritative
