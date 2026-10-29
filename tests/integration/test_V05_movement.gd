extends "res://tests/test_case.gd"
## V05: movement sync. Usable at 150 ms RTT; no client-authoritative movement, placement or repair.
## A seeded in-process network model (latency, jitter, loss) carries input and snapshot packets. Not a real network:
## the controlled-impairment test on real peers (NET09) is local.

const Model := preload("res://scripts/actors/movement_model.gd")
const Sync := preload("res://scripts/network/movement_sync.gd")

var _tuning: Dictionary
var _model: Model


func before_each() -> void:
	_tuning = JSON.parse_string(FileAccess.get_file_as_string("res://content/movement.json"))
	_model = Model.new()
	_model.configure(_tuning)


func test_V05_speeds_match_the_blueprint_and_diagonals_are_not_faster() -> void:
	assert_eq(_run_steps({"x": 0, "z": -127}, false, 30).z, -3990, "walk ~4.0 m/s (fixed-point truncation: -133 mm per tick)")
	assert_true(absi(_run_steps({"x": 0, "z": 127, "sprint": true}, false, 30).z - 5500) <= 30, "sprint 5.5 m/s")
	assert_true(absi(_run_steps({"x": 127, "z": 0, "sprint": true}, true, 30).x - 2800) <= 30, "carrying caps at 2.8 m/s, even sprinting")
	var diag: Vector3i = _run_steps({"x": 127, "z": 127}, false, 30)
	var diag_mm: float = sqrt(float(diag.x * diag.x + diag.z * diag.z))
	assert_true(diag_mm <= 4000.0, "diagonal %.0f mm/s is not faster than straight" % diag_mm)
	assert_eq(_run_steps({"x": 9000, "z": 0}, false, 30), _run_steps({"x": 127, "z": 0}, false, 30), "oversized input is clamped")


func test_V05_movement_is_bit_identical_on_host_and_client() -> void:
	var a: Vector3i = Vector3i(1000, 0, 2000)
	var b: Vector3i = a
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 600:
		var inp: Dictionary = {"x": rng.randi_range(-127, 127), "z": rng.randi_range(-127, 127), "sprint": rng.randi() % 2 == 0}
		a = _model.step(a, inp, false)
		b = _client_model().step(b, inp, false)  # a separately configured instance, like a client build
	assert_eq(a, b)


func test_V05_usable_at_150ms_rtt_3pct_loss_30ms_jitter() -> void:
	var r: Dictionary = _simulate(150, 3, 30, 10_000, 4242)
	assert_eq(r["host_final"], r["client_final"], "every input reached the host despite 3% loss (redundant inputs)")
	assert_eq(r["unacked"], 0, "host applied every input exactly once")
	assert_eq(r["corrections"], 0, "prediction never had to be corrected: the local player feels instant")
	assert_true(r["max_remote_jump_mm"] <= 300, "remote player never snaps more than 30 cm between frames (%d mm)" % r["max_remote_jump_mm"])
	assert_true(r["remote_lag_ms"] <= 300, "remote view lags truth by about delay + one-way latency (%d ms)" % r["remote_lag_ms"])


func test_V05_host_rule_change_is_corrected_and_converges() -> void:
	# host says the player is carrying (slower) while the client thinks not: reconciliation moves the client to the host
	var r: Dictionary = _simulate(150, 0, 0, 3_000, 9, true)
	assert_true(r["corrections"] > 0, "the client was corrected")
	assert_eq(r["host_final"], r["client_final"], "after the last snapshot the client matches the host")


func test_V05_sending_inputs_faster_than_the_host_ticks_does_not_speed_anyone_up() -> void:
	var host: Sync.HostMovement = Sync.HostMovement.new(_model, _tuning)
	host.spawn("CHEAT", Vector3i.ZERO)
	host.spawn("FAIR", Vector3i.ZERO)
	var cheat_seq: int = 0
	var fair_seq: int = 0
	for t: int in 60:
		var burst: Array = []
		for _k: int in 3:  # three inputs per host tick (90 Hz)
			cheat_seq += 1
			burst.append({"seq": cheat_seq, "x": 0, "z": -127, "sprint": true})
		host.receive("CHEAT", burst)
		fair_seq += 1
		host.receive("FAIR", [{"seq": fair_seq, "x": 0, "z": -127, "sprint": true}])
		host.tick({})
	assert_eq(host.position_of("CHEAT"), host.position_of("FAIR"), "one input per host tick, extra inputs dropped")


func test_V05_clients_cannot_send_positions_or_teleport() -> void:
	var host: Sync.HostMovement = Sync.HostMovement.new(_model, _tuning)
	host.spawn("P1", Vector3i(1000, 0, 2000))
	host.receive("P1", [{"seq": 1, "x": 0, "z": 0, "pos": [999999, 0, 999999], "position_cm": "60,0,16"}])
	host.tick({})
	assert_eq(host.position_of("P1"), Vector3i(1000, 0, 2000), "position fields are ignored")
	host.receive("P1", [{"seq": 1, "x": 127, "z": 0}])
	host.tick({})
	assert_eq(host.position_of("P1"), Vector3i(1000, 0, 2000), "an already applied seq is not replayed")
	assert_eq(host.receive("NOBODY", [{"seq": 1}]), 0)


func test_V05_anchored_equipment_eases_and_lands_exactly_on_the_host_anchor() -> void:
	var s: Sync.Smoother = Sync.Smoother.new(Vector3(10, 0, 20))
	s.retarget(Vector3(60, 0, 16), 1000, 250)
	var mid: Vector3 = s.position(1125)
	assert_true(mid.x > 10.0 and mid.x < 60.0, "moving between anchors")
	assert_eq(s.position(1250), Vector3(60, 0, 16), "ends exactly on the authoritative anchor")


# ---------- simulation ----------

func _client_model() -> Model:
	var m: Model = Model.new()
	m.configure(_tuning)
	return m



func _run_steps(input: Dictionary, carrying: bool, n: int) -> Vector3i:
	var p: Vector3i = Vector3i.ZERO
	for _i: int in n:
		p = _model.step(p, input, carrying)
	return p


## Runs a client walking a seeded random route for duration_ms through a lossy, jittery link to a 30 Hz host that sends
## 15 Hz snapshots back to that client and to a remote observer that interpolates the walker.
func _simulate(rtt_ms: int, loss_pct: int, jitter_ms: int, duration_ms: int, seed: int, host_says_carrying: bool = false) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed
	var tick_ms: float = 1000.0 / float(_tuning["host_hz"])
	var snap_every: int = int(_tuning["host_hz"]) / int(_tuning["snapshot_hz"])
	var host: Sync.HostMovement = Sync.HostMovement.new(_model, _tuning)
	host.spawn("P1", Vector3i.ZERO)
	var client: Sync.Predictor = Sync.Predictor.new(_model, _tuning, Vector3i.ZERO)
	var observer: Sync.Interpolator = Sync.Interpolator.new(_tuning)
	var in_flight: Array[Dictionary] = []  # {"at": ms, "to": "host"|"client"|"observer", "data": ...}
	var truth: Array[Dictionary] = []  # host positions over time, for the remote lag measurement
	var max_jump: int = 0
	var last_drawn: Vector3 = Vector3.INF
	var lag_samples: Array[int] = []
	var ticks: int = int(float(duration_ms) / tick_ms)
	var input: Dictionary = {"x": 0, "z": -127, "sprint": false}
	for t: int in ticks + 60:  # extra ticks with no input let everything arrive
		var now: int = int(float(t) * tick_ms)
		var sending: bool = t < ticks
		if sending:
			if t % 45 == 0:
				input = {"x": rng.randi_range(-127, 127), "z": rng.randi_range(-127, 127), "sprint": rng.randi() % 3 == 0}
			var packet: Array[Dictionary] = client.input(input["x"], input["z"], input["sprint"], false, false)
			_send(in_flight, rng, now, rtt_ms, loss_pct, jitter_ms, "host", packet)
		for msg: Dictionary in _arrived(in_flight, now):
			match msg["to"]:
				"host":
					host.receive("P1", msg["data"])
				"client":
					client.on_snapshot(msg["data"]["pos"], int(msg["data"]["ack"]))
				"observer":
					observer.add(int(msg["data"]["t"]), msg["data"]["pos"], now)
		host.tick({"P1": host_says_carrying})
		var hp: Vector3i = host.position_of("P1")
		truth.append({"t": now, "pos": hp})
		if t % snap_every == 0:
			var snap: Dictionary = host.snapshot()["P1"]
			_send(in_flight, rng, now, rtt_ms, loss_pct, jitter_ms, "client", snap)
			_send(in_flight, rng, now, rtt_ms, loss_pct, jitter_ms, "observer", {"t": now, "pos": snap["pos"]})
		# observer renders at 60 fps: two frames per host tick
		for f: int in 2:
			var frame_ms: int = now + int(float(f) * tick_ms / 2.0)
			var drawn: Vector3 = observer.sample(frame_ms)
			if last_drawn != Vector3.INF:
				max_jump = maxi(max_jump, int(drawn.distance_to(last_drawn)))
			last_drawn = drawn
			if t > 30 and t < ticks:
				lag_samples.append(_lag_ms(truth, drawn, frame_ms))
	lag_samples.sort()
	# final snapshot for both after the link is quiet
	client.on_snapshot(host.snapshot()["P1"]["pos"], int(host.snapshot()["P1"]["ack"]))
	return {"host_final": host.position_of("P1"), "client_final": client.predicted, "corrections": client.corrections,
		"unacked": ticks - int(host.snapshot()["P1"]["ack"]), "max_remote_jump_mm": max_jump,
		"remote_lag_ms": lag_samples[lag_samples.size() * 95 / 100] if not lag_samples.is_empty() else 0}


func _send(q: Array[Dictionary], rng: RandomNumberGenerator, now: int, rtt: int, loss: int, jitter: int, to: String, data: Variant) -> void:
	if rng.randi_range(1, 100) <= loss:
		return
	q.append({"at": now + rtt / 2 + rng.randi_range(0, jitter), "to": to, "data": data})


func _arrived(q: Array[Dictionary], now: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for m: Dictionary in q:
		if int(m["at"]) <= now:
			out.append(m)
		else:
			keep.append(m)
	q.assign(keep)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])
	return out


## How far in the past the drawn position is: the newest host time whose true position is within 5 cm of it.
func _lag_ms(truth: Array[Dictionary], drawn: Vector3, frame_ms: int) -> int:
	for i: int in range(truth.size() - 1, -1, -1):
		var p: Vector3i = truth[i]["pos"]
		if Vector3(p).distance_to(drawn) <= 50.0:
			return frame_ms - int(truth[i]["t"])
	return 99999
