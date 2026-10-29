extends RefCounted
## Client-side mirror of the host's authoritative state (G07; blueprint p.10 join/reconnect, CLAUDE.md section 4).
##
## The client never decides whether a building is supplied: it only applies what the host published and checks
## that the result hashes to the host's hash. Join/reconnect: status "joining" (UI freezes the player) while the
## snapshot manifest and chunks arrive; deltas that arrive meanwhile are queued. The snapshot is verified against
## the manifest hash and content revision, then queued deltas newer than the snapshot revision are applied in order.
## A gap queues the delta; a duplicate is ignored; a hash mismatch or an overfull queue sets status "desync" and the
## client asks for a fresh snapshot (needs_snapshot()).
##
## Pure: no scene tree, no autoloads. Messages are the decoded JSON the transport delivered.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

const STATUS_IDLE: String = "idle"
const STATUS_JOINING: String = "joining"
const STATUS_SYNCED: String = "synced"
const STATUS_DESYNC: String = "desync"

var status: String = STATUS_IDLE
var revision: int = -1
var state: Dictionary = {}
var last_issue: String = ""
var _content_revision: String = ""
var _max_queued: int = 0
var _manifest: Dictionary = {}
var _chunks: Dictionary = {}  # index -> data
var _queued: Array[Dictionary] = []


func configure(content_revision: String, max_queued_deltas: int) -> void:
	_content_revision = content_revision
	_max_queued = max_queued_deltas


func on_message(raw: Dictionary) -> void:
	var msg: Dictionary = PowerGrid.json_ints(raw)
	match msg.get("type"):
		"snapshot_manifest":
			if msg.get("content_revision") != _content_revision:
				_desync("CONTENT_MISMATCH")
				return
			_manifest = msg
			_chunks = {}
			status = STATUS_JOINING
		"snapshot_chunk":
			if status != STATUS_JOINING:
				return
			_chunks[int(msg["index"])] = str(msg["data"])
			if _chunks.size() == int(_manifest["chunks"]):
				_apply_snapshot()
		"delta":
			if status == STATUS_JOINING or status == STATUS_IDLE:
				_queue(msg)
			elif status == STATUS_SYNCED:
				_queue(msg)
				_drain()


func needs_snapshot() -> bool:
	return status == STATUS_DESYNC or status == STATUS_IDLE


func state_hash() -> String:
	return PowerGrid.serialize(state).sha256_text()


## Mirror of the authoritative grid view for presentation (service_location.gd reads supplied from here).
func is_supplied(node_id: String) -> bool:
	return state.get("grid", {}).get("nodes", {}).get(node_id, {}).get("supplied", false)


func _apply_snapshot() -> void:
	var parts: PackedStringArray = []
	for i: int in int(_manifest["chunks"]):
		if not _chunks.has(i):
			_desync("SNAPSHOT_INCOMPLETE")
			return
		parts.append(_chunks[i])
	var text: String = "".join(parts)
	if text.length() != int(_manifest["bytes"]) or text.sha256_text() != _manifest["hash"]:
		_desync("SNAPSHOT_HASH_MISMATCH")
		return
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		_desync("SNAPSHOT_MALFORMED")
		return
	state = PowerGrid.json_ints(json.data)
	revision = int(_manifest["revision"])
	status = STATUS_SYNCED
	last_issue = ""
	_manifest = {}
	_chunks = {}
	_drain()


func _queue(delta: Dictionary) -> void:
	if _queued.size() >= _max_queued:
		_desync("QUEUE_OVERFLOW")
		return
	_queued.append(delta)


## Applies queued deltas whose "from" matches the current revision, in order; drops ones already covered.
func _drain() -> void:
	while status == STATUS_SYNCED:
		var pending: Array[Dictionary] = []
		for d: Dictionary in _queued:
			if int(d["to"]) > revision:
				pending.append(d)  # older or duplicate deltas are already reflected in the state
		_queued = pending
		var next: int = -1
		for i: int in _queued.size():
			if int(_queued[i]["from"]) == revision:
				next = i
				break
		if next < 0:
			return
		var d: Dictionary = _queued[next]
		_queued.remove_at(next)
		_apply_delta(d)


func _apply_delta(d: Dictionary) -> void:
	var next: Dictionary = state.duplicate(true)
	for op: Dictionary in d["ops"]:
		var path: Array = op["path"]
		var node: Dictionary = next
		for i: int in path.size() - 1:
			if not node.has(path[i]) or not node[path[i]] is Dictionary:
				node[path[i]] = {}
			node = node[path[i]]
		if op["op"] == "del":
			node.erase(path[-1])
		else:
			node[path[-1]] = op["value"]
	if PowerGrid.serialize(next).sha256_text() != d["hash"]:
		_desync("DELTA_HASH_MISMATCH")
		return
	state = next
	revision = int(d["to"])


func _desync(reason: String) -> void:
	status = STATUS_DESYNC
	last_issue = reason
	_queued = []
