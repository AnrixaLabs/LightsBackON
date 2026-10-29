extends "res://tests/test_case.gd"
## F04 (draft): connection failures end with a reason and bounded waits; reconnect and host-leave never hang.

const Flow := preload("res://scripts/network/connection_flow.gd")

var _limits: Dictionary
var _flow: Flow
var _now: int = 0


func before_each() -> void:
	_limits = JSON.parse_string(FileAccess.get_file_as_string("res://content/network.json"))
	_flow = Flow.new()
	_flow.configure(_limits)
	_now = 0


func test_F04_happy_path_reaches_session() -> void:
	_flow.start("enet_dev", false)
	assert_eq(_flow.state, Flow.STATE_CONNECTING)
	_flow.on_transport_connected()
	_flow.on_handshake_reply({"ok": true})
	assert_eq(_flow.state, Flow.STATE_JOINING, "frozen in the joining screen until the snapshot applies")
	_flow.on_snapshot_applied()
	assert_eq(_flow.state, Flow.STATE_IN_SESSION)
	assert_eq(_flow.ticks_left(), -1)


func test_NET08_wrong_version_fails_with_update_reason() -> void:
	for code: String in ["PROTOCOL_MISMATCH", "CONTENT_MISMATCH"]:
		_flow.start("enet_dev", false)
		_flow.on_transport_connected()
		_flow.on_handshake_reply({"ok": false, "code": code})
		assert_eq(_flow.state, Flow.STATE_ENDED)
		assert_eq(_flow.end_reason, code)
		assert_eq(_flow.actions, [Flow.ACTION_UPDATE, Flow.ACTION_BACK] as Array[String])


func test_UX06_REL02_steam_unavailable_offers_offline_solo() -> void:
	_flow.start("steam", false)
	assert_eq(_flow.end_reason, "STEAM_UNAVAILABLE")
	assert_true(_flow.actions.has(Flow.ACTION_OFFLINE))
	_flow.start(Flow.MODE_OFFLINE, false)
	assert_eq(_flow.state, Flow.STATE_IN_SESSION, "solo works without any network")
	_flow.on_transport_lost()
	_flow.on_host_left()
	assert_eq(_flow.state, Flow.STATE_IN_SESSION, "offline solo has no network failure paths")


func test_F04_each_wait_has_a_deadline() -> void:
	_flow.start("enet_dev", false)
	_run(int(_limits["connect_timeout_ticks"]))
	assert_eq(_flow.end_reason, "CONNECT_TIMEOUT")
	_flow.start("enet_dev", false)
	_flow.on_transport_connected()
	_run(int(_limits["handshake_timeout_ticks"]))
	assert_eq(_flow.end_reason, "HANDSHAKE_TIMEOUT")
	_flow.start("enet_dev", false)
	_flow.on_transport_connected()
	_flow.on_handshake_reply({"ok": true})
	_run(int(_limits["snapshot_timeout_ticks"]))
	assert_eq(_flow.end_reason, "SNAPSHOT_TIMEOUT")


func test_F04_bounded_reconnect_then_clear_failure() -> void:
	_in_session()
	_flow.on_transport_lost()
	var attempts: int = 0
	var waited: Array[int] = []
	for _guard: int in 10000:
		var before: int = _now
		if _flow.state == Flow.STATE_ENDED:
			break
		if _flow.state == Flow.STATE_RECONNECT_WAIT:
			while not _flow.tick(_now + 1):
				_now += 1
			_now += 1
			waited.append(_now - before)
			attempts += 1
		else:
			_now += 1
			_flow.tick(_now)  # connection attempt never succeeds
	assert_eq(attempts, int(_limits["reconnect_attempts"]))
	var base: int = int(_limits["reconnect_backoff_ticks"])
	assert_eq(waited, [base, base * 2, base * 4] as Array[int], "doubling backoff")
	assert_eq(_flow.end_reason, "RECONNECT_FAILED")
	assert_eq(_flow.actions, [Flow.ACTION_RETRY, Flow.ACTION_BACK] as Array[String])


func test_NET06_logic_reconnect_succeeds_and_resets_attempts() -> void:
	_in_session()
	_flow.on_transport_lost()
	assert_eq(_flow.state, Flow.STATE_RECONNECT_WAIT)
	_run(int(_limits["reconnect_backoff_ticks"]))
	assert_eq(_flow.state, Flow.STATE_CONNECTING)
	_flow.on_transport_connected()
	_flow.on_handshake_reply({"ok": true})
	_flow.on_snapshot_applied()
	assert_eq(_flow.state, Flow.STATE_IN_SESSION)
	assert_eq(_flow.reconnect_attempt, 0)


func test_F04_stalled_reconnect_handshake_or_snapshot_uses_remaining_attempts() -> void:
	# review finding: a handshake/snapshot timeout during reconnect ended the flow after the first attempt
	_in_session()
	_flow.on_transport_lost()
	_run(int(_limits["reconnect_backoff_ticks"]))
	_flow.on_transport_connected()
	_run(int(_limits["handshake_timeout_ticks"]))
	assert_eq(_flow.state, Flow.STATE_RECONNECT_WAIT, "handshake stall schedules attempt 2")
	assert_eq(_flow.reconnect_attempt, 2)
	_run(int(_limits["reconnect_backoff_ticks"]) * 2)
	_flow.on_transport_connected()
	_flow.on_handshake_reply({"ok": true})
	_run(int(_limits["snapshot_timeout_ticks"]))
	assert_eq(_flow.state, Flow.STATE_RECONNECT_WAIT, "snapshot stall schedules attempt 3")
	assert_eq(_flow.reconnect_attempt, 3)


func test_NET07_host_left_ends_immediately_without_reconnect_loop() -> void:
	_in_session()
	_flow.on_host_left()
	assert_eq(_flow.state, Flow.STATE_ENDED)
	assert_eq(_flow.end_reason, "HOST_LEFT")
	assert_eq(_flow.actions, [Flow.ACTION_BACK] as Array[String])
	_flow.on_transport_lost()
	_run(1000)
	assert_eq(_flow.end_reason, "HOST_LEFT", "a later transport drop does not restart anything")


func test_F04_never_hangs_under_random_event_sequences() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4242  # deterministic
	var bound: int = 2000  # far above every deadline + all backoffs
	for trial: int in 300:
		_flow = Flow.new()
		_flow.configure(_limits)
		_now = 0
		_flow.start(["enet_dev", "steam", "offline"][rng.randi() % 3], rng.randi() % 2 == 0)
		for _e: int in rng.randi() % 12:
			match rng.randi() % 6:
				0: _flow.on_transport_connected()
				1: _flow.on_handshake_reply({"ok": rng.randi() % 3 != 0, "code": "PROTOCOL_MISMATCH"})
				2: _flow.on_snapshot_applied()
				3: _flow.on_transport_lost()
				4: _flow.on_host_left()
				5: _run(rng.randi() % 60)
		# no more events from the outside world: the flow must settle on its own
		_run(bound)
		var settled: bool = [Flow.STATE_IN_SESSION, Flow.STATE_ENDED].has(_flow.state)
		assert_true(settled, "trial %d stuck in %s" % [trial, _flow.state])
		if _flow.state == Flow.STATE_ENDED:
			assert_ne(_flow.end_reason, "", "trial %d ended without a reason" % trial)
			assert_false(_flow.actions.is_empty(), "trial %d offers no action" % trial)


func _in_session() -> void:
	_flow.start("enet_dev", false)
	_flow.on_transport_connected()
	_flow.on_handshake_reply({"ok": true})
	_flow.on_snapshot_applied()


func _run(ticks: int) -> void:
	for _i: int in ticks:
		_now += 1
		_flow.tick(_now)
