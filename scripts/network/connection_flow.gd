extends RefCounted
## Client connection lifecycle (F04; blueprint p.10, UX06, REL02, NET07, NET08). Every non-final state has a deadline
## in ticks (content/network.json), so no path can hang: it either reaches "in_session" or ends with one specific
## reason and the actions the screen offers (retry / back / play offline / update).
##
## The flow only decides states; the transport adapter and session client do the I/O and report events here.
## Pure: no scene tree, no autoloads.

const STATE_IDLE: String = "idle"
const STATE_CONNECTING: String = "connecting"
const STATE_HANDSHAKE: String = "handshake"
const STATE_JOINING: String = "joining"
const STATE_IN_SESSION: String = "in_session"
const STATE_RECONNECT_WAIT: String = "reconnect_wait"
const STATE_ENDED: String = "ended"
const MODE_OFFLINE: String = "offline"
const ACTION_RETRY: String = "retry"
const ACTION_BACK: String = "back"
const ACTION_OFFLINE: String = "play_offline"
const ACTION_UPDATE: String = "update_game"

var state: String = STATE_IDLE
var end_reason: String = ""
var actions: Array[String] = []
var reconnect_attempt: int = 0
var _limits: Dictionary = {}
var _deadline: int = -1
var _now: int = 0
var _mode: String = ""
var _was_in_session: bool = false


func configure(limits: Dictionary) -> void:
	_limits = limits


## mode: offline | enet_dev | steam. steam_available: the Steam client/API initialised (always false until F02).
func start(mode: String, steam_available: bool) -> void:
	_mode = mode
	reconnect_attempt = 0
	_was_in_session = false
	if mode == MODE_OFFLINE:
		_enter(STATE_IN_SESSION, -1)  # solo: host-local, same command path, no network wait
		return
	if mode == "steam" and not steam_available:
		_end("STEAM_UNAVAILABLE", [ACTION_OFFLINE, ACTION_RETRY, ACTION_BACK])
		return
	_enter(STATE_CONNECTING, int(_limits["connect_timeout_ticks"]))


func on_transport_connected() -> void:
	if state == STATE_CONNECTING:
		_enter(STATE_HANDSHAKE, int(_limits["handshake_timeout_ticks"]))


## reply: the host's admit() answer ({"ok": true} or {"ok": false, "code"}).
func on_handshake_reply(reply: Dictionary) -> void:
	if state != STATE_HANDSHAKE:
		return
	if reply.get("ok", false):
		_enter(STATE_JOINING, int(_limits["snapshot_timeout_ticks"]))
		return
	var code: String = str(reply.get("code", "JOIN_REFUSED"))
	if code == "PROTOCOL_MISMATCH" or code == "CONTENT_MISMATCH":
		_end(code, [ACTION_UPDATE, ACTION_BACK])  # NET08: rejected before spawning, with the update reason
	else:
		_end(code, [ACTION_RETRY, ACTION_BACK])


func on_snapshot_applied() -> void:
	if state == STATE_JOINING:
		reconnect_attempt = 0
		_was_in_session = true
		_enter(STATE_IN_SESSION, -1)


## Transport dropped without the host saying goodbye: bounded reconnect while the host may still be there.
func on_transport_lost() -> void:
	if state == STATE_ENDED or state == STATE_IDLE or _mode == MODE_OFFLINE:
		return
	if not _was_in_session:
		_end("CONNECTION_LOST", [ACTION_RETRY, ACTION_BACK])
		return
	_schedule_reconnect()


## The host ended the session or left (NET07): no reconnect loop, clear end screen; the host keeps its checkpoint.
func on_host_left() -> void:
	if state != STATE_ENDED and _mode != MODE_OFFLINE:
		_end("HOST_LEFT", [ACTION_BACK])


## Returns true when the caller should start a new transport connection attempt now.
func tick(now: int) -> bool:
	_now = now
	if _deadline < 0 or now < _deadline:
		return false
	match state:
		STATE_CONNECTING:
			if _was_in_session:
				_schedule_reconnect()
			else:
				_end("CONNECT_TIMEOUT", [ACTION_RETRY, ACTION_BACK])
		STATE_HANDSHAKE, STATE_JOINING:
			if _was_in_session:
				_schedule_reconnect()  # a stalled reconnect uses the remaining bounded attempts
			else:
				_end("HANDSHAKE_TIMEOUT" if state == STATE_HANDSHAKE else "SNAPSHOT_TIMEOUT", [ACTION_RETRY, ACTION_BACK])
		STATE_RECONNECT_WAIT:
			_enter(STATE_CONNECTING, int(_limits["connect_timeout_ticks"]))
			return true
	return false


## Ticks until the current state's deadline, or -1 for states that wait on the player (in_session, ended, idle).
func ticks_left() -> int:
	return -1 if _deadline < 0 else maxi(0, _deadline - _now)


func _schedule_reconnect() -> void:
	if reconnect_attempt >= int(_limits["reconnect_attempts"]):
		_end("RECONNECT_FAILED", [ACTION_RETRY, ACTION_BACK])
		return
	var wait: int = int(_limits["reconnect_backoff_ticks"]) << reconnect_attempt  # 2 s, 4 s, 8 s
	reconnect_attempt += 1
	_enter(STATE_RECONNECT_WAIT, wait)


func _enter(next: String, timeout_ticks: int) -> void:
	state = next
	end_reason = ""
	actions = []
	_deadline = -1 if timeout_ticks < 0 else _now + timeout_ticks


func _end(reason: String, offered: Array[String]) -> void:
	state = STATE_ENDED
	end_reason = reason
	actions = offered
	_deadline = -1
