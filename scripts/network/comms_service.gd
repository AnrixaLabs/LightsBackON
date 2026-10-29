extends RefCounted
## Crew communication (V06): context pings, radial phrases and short text chat. No voice chat exists or is implied;
## C01 must be completable with pings alone.
##
## Host side: validates and rate-limits every ping, phrase and chat line, then returns broadcast events. Comms are
## ephemeral presentation, not authoritative game state, so they never enter the state hash or saves.
## Client side (static helpers): display_text() makes chat safe to show (control characters stripped, BBCode
## brackets escaped so no [url] or markup can form, so no URL launching), and mute filtering happens per viewer.
##
## Pure: no scene tree, no autoloads. Positions come from the host's movement layer, never from the client.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")

var _ping_types: Dictionary = {}  # id -> record
var _phrases: Dictionary = {}  # id -> record
var _lifetime: int = 0
var _max_active: int = 0
var _ping_rate: Array[int] = [0, 0]  # count, window ticks
var _chat_rate: Array[int] = [0, 0]
var _chat_max: int = 0
var _active: Dictionary = {}  # player -> Array of {"id", "type", "entity", "position_cm", "expires"}
var _recent_pings: Dictionary = {}  # player -> Array[int] ticks
var _recent_chat: Dictionary = {}  # player -> Array[int] ticks
var _next_ping: int = 1
var _now: int = 0


func load_definition(def: Dictionary) -> Array[Dictionary]:
	var errs: Array[Dictionary] = []
	for rec: Variant in def.get("ping_types", []):
		if rec is Dictionary and PowerGrid.is_valid_id(rec.get("id")) and rec.get("text_key") is String and rec.get("icon") is String:
			_ping_types[rec["id"]] = rec
		else:
			errs.append(PowerGrid.diag("BAD_COMMS", "ping type needs id, text_key, icon", []))
	for rec: Variant in def.get("phrases", []):
		if rec is Dictionary and PowerGrid.is_valid_id(rec.get("id")) and rec.get("text_key") is String:
			_phrases[rec["id"]] = rec
		else:
			errs.append(PowerGrid.diag("BAD_COMMS", "phrase needs id and text_key", []))
	var ints: Dictionary = {}
	for key: String in ["ping_lifetime_ticks", "max_active_pings_per_player", "chat_max_chars"]:
		var v: Variant = PowerGrid.to_int(def.get(key))
		if v == null or int(v) < 1:
			errs.append(PowerGrid.diag("BAD_COMMS", "%s must be an int >= 1" % key, []))
		else:
			ints[key] = int(v)
	for key: String in ["ping_rate", "chat_rate"]:
		var r: Dictionary = def.get(key, {})
		var c: Variant = PowerGrid.to_int(r.get("count"))
		var w: Variant = PowerGrid.to_int(r.get("window_ticks"))
		if c == null or w == null or int(c) < 1 or int(w) < 1:
			errs.append(PowerGrid.diag("BAD_COMMS", "%s needs count and window_ticks >= 1" % key, []))
		else:
			ints[key] = [int(c), int(w)] as Array[int]
	if _ping_types.size() != 4:
		errs.append(PowerGrid.diag("BAD_COMMS", "exactly four context ping types (blueprint V06)", []))
	if errs.is_empty():
		_lifetime = ints["ping_lifetime_ticks"]
		_max_active = ints["max_active_pings_per_player"]
		_chat_max = ints["chat_max_chars"]
		_ping_rate = ints["ping_rate"]
		_chat_rate = ints["chat_rate"]
	return errs


## A context ping at the host's position for the player, optionally on a target entity (panel, item, anchor).
## A player's oldest ping is replaced once they have max_active_pings_per_player.
func ping(player: String, ping_type: Variant, entity: String, position_cm: Vector3i) -> Dictionary:
	if not (ping_type is String and _ping_types.has(ping_type)):
		return _refuse("UNKNOWN_PING", "unknown ping type")
	if not _allow(_recent_pings, player, _ping_rate):
		return _refuse("RATE_LIMITED", "too many pings; wait a moment")
	var mine: Array = _active.get(player, [])
	var events: Array[Dictionary] = []
	if mine.size() >= _max_active:
		var oldest: Dictionary = mine.pop_front()
		events.append({"type": "ping_removed", "ping": oldest["id"], "reason": "replaced"})
	var p: Dictionary = {"id": "PING_%d" % _next_ping, "type": ping_type, "player": player, "entity": entity,
		"position_cm": [position_cm.x, position_cm.y, position_cm.z], "expires": _now + _lifetime}
	_next_ping += 1
	mine.append(p)
	_active[player] = mine
	var shown: Dictionary = p.duplicate()
	shown["text_key"] = _ping_types[ping_type]["text_key"]
	shown["icon"] = _ping_types[ping_type]["icon"]
	events.append({"type": "ping_added", "ping": shown})
	return {"ok": true, "events": events}


## A radial phrase: a fixed localization key, so it needs no escaping and reads in every language.
func phrase(player: String, phrase_id: Variant) -> Dictionary:
	if not (phrase_id is String and _phrases.has(phrase_id)):
		return _refuse("UNKNOWN_PHRASE", "unknown phrase")
	if not _allow(_recent_chat, player, _chat_rate):
		return _refuse("RATE_LIMITED", "too many messages; wait a moment")
	return {"ok": true, "events": [{"type": "phrase", "player": player, "phrase": phrase_id, "text_key": _phrases[phrase_id]["text_key"]}]}


## A short text line. Refused when empty or over chat_max_chars after cleaning; relayed as cleaned plain text.
func chat(player: String, text: Variant) -> Dictionary:
	if not text is String:
		return _refuse("MALFORMED", "chat text must be a string")
	var clean: String = clean_text(text)
	if clean.is_empty():
		return _refuse("EMPTY", "nothing to send")
	if clean.length() > _chat_max:
		return _refuse("TOO_LONG", "chat lines are at most %d characters" % _chat_max)
	if not _allow(_recent_chat, player, _chat_rate):
		return _refuse("RATE_LIMITED", "too many messages; wait a moment")
	return {"ok": true, "events": [{"type": "chat", "player": player, "text": clean}]}


## Expires pings whose lifetime ended. Call once per host tick.
func tick(now: int) -> Array[Dictionary]:
	_now = now
	var events: Array[Dictionary] = []
	for player: String in _active:
		var keep: Array = []
		for p: Dictionary in _active[player]:
			if int(p["expires"]) <= now:
				events.append({"type": "ping_removed", "ping": p["id"], "reason": "expired"})
			else:
				keep.append(p)
		_active[player] = keep
	return events


## A leaving player's pings disappear with them.
func player_left(player: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for p: Dictionary in _active.get(player, []):
		events.append({"type": "ping_removed", "ping": p["id"], "reason": "player_left"})
	_active.erase(player)
	_recent_pings.erase(player)
	_recent_chat.erase(player)
	return events


func active_pings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for player: String in _active:
		for p: Dictionary in _active[player]:
			out.append(p)
	return out


# ---------- text safety (host cleans; clients escape again before display) ----------

## Collapses whitespace runs to one space and removes control and format characters (including bidi overrides,
## which can make a line read backwards). Keeps every printable character, so Chinese and other scripts work.
static func clean_text(text: String) -> String:
	var out: PackedStringArray = []
	var last_space: bool = true
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		var is_space: bool = c == 0x20 or c == 0x09 or c == 0x0A or c == 0x0D or c == 0x3000
		if is_space:
			if not last_space:
				out.append(" ")
			last_space = true
			continue
		if c < 0x20 or (c >= 0x7F and c < 0xA0) or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) \
				or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF:
			continue
		out.append(text[i])
		last_space = false
	return "".join(out).strip_edges()


## Safe for a RichTextLabel: every "[" becomes "[lb]", so no tag (url, img, color, ...) can form. Plain Labels can
## show clean_text() directly. Either way chat never launches a URL.
static func display_text(clean: String) -> String:
	return clean.replace("[", "[lb]")


## Viewer-side mute: hides chat and phrases from muted players. Pings are kept so a muted teammate can still
## guide the crew (the game must be completable with pings alone).
static func visible_to(event: Dictionary, muted: Dictionary) -> bool:
	if event.get("type") == "chat" or event.get("type") == "phrase":
		return not muted.has(event.get("player"))
	return true


# ---------- helpers ----------

func _allow(recent: Dictionary, player: String, rate: Array[int]) -> bool:
	var ticks: Array = recent.get(player, [])
	while not ticks.is_empty() and _now - int(ticks[0]) >= rate[1]:
		ticks.pop_front()
	if ticks.size() >= rate[0]:
		recent[player] = ticks
		return false
	ticks.append(_now)
	recent[player] = ticks
	return true


static func _refuse(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "key": "comms.refused." + code.to_lower(), "message": message, "ids": []}
