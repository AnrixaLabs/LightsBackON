extends RefCounted
## The UI's only way to act on the world (CLAUDE.md section 4): it builds ADR-009 command envelopes and hands the bytes to the
## transport (or, for the host player, to session_host.receive through the same path). The UI never touches simulation state.
## Each view gets a gate with the intents it may send; the network tablet's gate allows inspect and ping only (S07: clicking a
## node inspects information, it never toggles a remote switch).

signal sent(envelope: Dictionary)
signal replied(envelope: Dictionary, reply: Dictionary)

var session_id: String = ""
var _seq: int = 0
var _send: Callable  # (bytes: PackedByteArray) -> Dictionary reply, or {} when the reply arrives later


func _init(session: String, send_bytes: Callable) -> void:
	session_id = session
	_send = send_bytes


## Sends one intent; returns the reply when the transport answers in-process (host player, tests), else {}.
func send(kind: String, entity: String, payload: Dictionary) -> Dictionary:
	_seq += 1
	var envelope: Dictionary = {"session": session_id, "seq": _seq, "type": kind, "entity": entity, "payload": payload}
	sent.emit(envelope)
	var reply: Variant = _send.call(JSON.stringify(envelope).to_utf8_buffer())
	var out: Dictionary = reply if reply is Dictionary else {}
	if not out.is_empty():
		replied.emit(envelope, out)
	return out


## A restricted sender for one view.
func gate(allowed: Array[String]) -> Gate:
	return Gate.new(self, allowed)


class Gate:
	extends RefCounted
	var allowed: Array[String] = []
	var _outbox: RefCounted

	func _init(outbox: RefCounted, kinds: Array[String]) -> void:
		_outbox = outbox
		allowed = kinds.duplicate()

	## Refuses any intent outside the view's list before anything is sent.
	func send(kind: String, entity: String, payload: Dictionary) -> Dictionary:
		if not allowed.has(kind):
			push_error("UI gate refused intent %s (allowed: %s)" % [kind, str(allowed)])
			return {"ok": false, "code": "UI_INTENT_NOT_ALLOWED"}
		return _outbox.call("send", kind, entity, payload)
