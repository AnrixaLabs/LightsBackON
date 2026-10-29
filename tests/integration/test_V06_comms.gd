extends "res://tests/test_case.gd"
## V06: four context pings, radial phrases, short escaped chat, mute and rate limits, through the host.
## The human acceptance (two testers finish C01 with pings only) is local; here: the logic, and that C01 needs no chat.

const Runner := preload("res://tests/support/solution_runner.gd")
const Comms := preload("res://scripts/network/comms_service.gd")
const C01: String = "res://content/contracts/c01_alder_street"
const TOOLS: Array[String] = ["meter"]

var _ctx: Dictionary
var _positions: Dictionary = {}


func before_each() -> void:
	_ctx = Runner.build(C01, ["P1", "P2"], TOOLS)
	assert_true((_ctx["errors"] as Array).is_empty(), str(_ctx["errors"]))
	_ctx["host"].set_position_provider(func(p: String) -> Vector3i: return _positions.get(p, Vector3i.ZERO))


func after_each() -> void:
	_ctx = {}


func test_V06_four_context_pings_with_icon_text_and_host_position() -> void:
	_positions["P1"] = Vector3i(7300, 0, 2400)
	var r: Dictionary = _send("P1", "ping", "PANEL_JE", {"ping": "PING_FAULT", "position_cm": "0,0,0"})
	assert_true(r["ok"])
	var p: Dictionary = r["events"][0]["ping"]
	assert_eq(p["type"], "PING_FAULT")
	assert_eq(p["entity"], "PANEL_JE", "context: what the player pointed at")
	assert_eq(p["position_cm"], [7300, 0, 2400], "host position, not the client's claim")
	assert_eq(p["text_key"], "ping.fault_here")
	assert_eq(p["icon"], "icon_ping_fault", "icon + text for every ping (ADR-004)")
	for t: String in ["PING_LOOK", "PING_HELP", "PING_EQUIPMENT"]:
		assert_true(_send("P2", "ping", "", {"ping": t})["ok"], t)
	assert_eq(_send("P1", "ping", "", {"ping": "PING_DANCE"})["code"], "UNKNOWN_PING")
	assert_eq(_send("P1", "ping", "bad id!", {"ping": "PING_LOOK"})["code"], "UNKNOWN_ENTITY")


func test_V06_pings_expire_are_capped_and_rate_limited() -> void:
	var comms: Comms = _ctx["comms"]
	for i: int in 3:
		assert_true(_send("P1", "ping", "", {"ping": "PING_LOOK"})["ok"])
		Runner.ticks(_ctx, 6)
	var fourth: Dictionary = _send("P1", "ping", "", {"ping": "PING_HELP"})
	assert_eq(fourth["events"][0]["reason"], "replaced", "oldest ping replaced at 3 active")
	assert_eq(comms.active_pings().size(), 3)
	var burst: Array[String] = []
	for i: int in 6:
		burst.append(str(Runner.send(_ctx, "P2", "ping", "", {"ping": "PING_LOOK"}).get("code", "ok")))
	assert_eq(burst.count("RATE_LIMITED"), 2, "4 pings per 2 s window")
	var expired: Array[Dictionary] = Runner.ticks(_ctx, 81)
	assert_true(expired.any(func(e: Dictionary) -> bool: return e["type"] == "ping_removed" and e["reason"] == "expired"))
	assert_eq(comms.active_pings().size(), 0, "8 s lifetime")


func test_V06_radial_phrases_are_localization_keys() -> void:
	var r: Dictionary = _send("P1", "chat", "", {"phrase": "PHRASE_ON_MY_WAY"})
	assert_eq(r["events"][0]["text_key"], "phrase.on_my_way")
	assert_eq(_send("P1", "chat", "", {"phrase": "PHRASE_INSULT"})["code"], "UNKNOWN_PHRASE")


func test_V06_chat_is_cleaned_capped_and_escaped() -> void:
	var r: Dictionary = _send("P1", "chat", "", {"text": "  pub  is\n\tlive [url=https://evil]x[/url] \u202eabc\u0007 "})
	assert_true(r["ok"])
	var text: String = r["events"][0]["text"]
	assert_eq(text, "pub is live [url=https://evil]x[/url] abc", "whitespace collapsed, control and bidi characters removed")
	assert_eq(Comms.display_text(text), "pub is live [lb]url=https://evil]x[lb]/url] abc", "no markup or link can form")
	assert_eq(_send("P1", "chat", "", {"text": "x".repeat(121)})["code"], "TOO_LONG")
	assert_eq(_send("P1", "chat", "", {"text": "   \n "})["code"], "EMPTY")
	assert_true(_send("P2", "chat", "", {"text": "东侧主干线断了"})["ok"], "Simplified Chinese passes unchanged")


func test_V06_chat_rate_limit_and_viewer_mute() -> void:
	var codes: Array[String] = []
	for i: int in 5:
		codes.append(str(Runner.send(_ctx, "P1", "chat", "", {"text": "msg %d" % i}).get("code", "ok")))
	assert_eq(codes.count("RATE_LIMITED"), 2, "3 messages per 5 s")
	var muted: Dictionary = {"P1": true}
	assert_false(Comms.visible_to({"type": "chat", "player": "P1", "text": "hi"}, muted))
	assert_false(Comms.visible_to({"type": "phrase", "player": "P1"}, muted))
	assert_true(Comms.visible_to({"type": "ping_added", "ping": {"player": "P1"}}, muted), "pings stay visible: completable with pings alone")


func test_V06_comms_never_change_the_authoritative_state() -> void:
	var before: String = _ctx["host"].state_hash()
	var rev: int = _ctx["host"].revision
	Runner.send(_ctx, "P1", "ping", "PANEL_JW", {"ping": "PING_FAULT"})
	Runner.send(_ctx, "P1", "chat", "", {"text": "check JW"})
	assert_eq(_ctx["host"].state_hash(), before)
	assert_eq(_ctx["host"].revision, rev, "comms do not advance the durable revision")


func test_V06_leaving_player_takes_their_pings() -> void:
	_send("P2", "ping", "", {"ping": "PING_HELP"})
	var events: Array[Dictionary] = _ctx["host"].remove(_ctx["peers"]["P2"])
	assert_true(events.any(func(e: Dictionary) -> bool: return e["type"] == "ping_removed" and e["reason"] == "player_left"))
	assert_eq((_ctx["comms"] as Comms).active_pings().size(), 0)


func test_V06_known_solution_needs_no_chat_or_voice() -> void:
	var trace: Dictionary = Runner.json(C01.path_join("solution.json"))
	for s: Dictionary in trace["steps"]:
		assert_false(s.get("intent", "") == "chat", "the C01 solution uses no text chat")


func _send(player: String, intent: String, entity: String, payload: Dictionary) -> Dictionary:
	var r: Dictionary = Runner.send(_ctx, player, intent, entity, payload)
	Runner.ticks(_ctx, 1)
	return r
