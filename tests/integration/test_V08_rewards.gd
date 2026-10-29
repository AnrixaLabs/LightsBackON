extends "res://tests/test_case.gd"
## V08: personal reward receipts. Replay/reconnect results never duplicate credits; separate campaigns stay separate.

const Runner := preload("res://tests/support/solution_runner.gd")
const Rewards := preload("res://scripts/progression/reward_service.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")
const Codec := preload("res://scripts/persistence/checkpoint_codec.gd")
const C01: String = "res://content/contracts/c01_alder_street"
const NOW: String = "2026-10-29T15:00:00Z"

var _economy: Dictionary
var _order: Array
var _saves: SaveService
var _accounts: Array[String] = []


func before_each() -> void:
	_economy = Runner.json("res://content/economy.json")
	_order = Runner.json("res://content/campaign.json")["contracts"]
	_saves = SaveService.new()
	_saves.configure(1, "test-build", "test-content")
	var tag: String = "t%d%d" % [Time.get_ticks_usec(), randi() % 1000]
	_accounts = ["host_" + tag, "guest_" + tag]


func after_each() -> void:
	for a: String in _accounts:
		_rm_tree(SaveService.profile_dir(a))


func test_V08_completion_results_and_credits_from_a_real_c01_run() -> void:
	var trace: Dictionary = Runner.json(C01.path_join("solution.json"))
	var ctx: Dictionary = Runner.build(C01, trace["players"], trace["tools"])
	Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"]))
	var results: Dictionary = ctx["mission"].results()
	assert_eq(results["required_restored"], 5)
	assert_eq(results["trips"], 0)
	assert_eq(results["stars"], 3, "completion + no optional services in C01 + no preventable trips")
	assert_eq(results["equipment_collected"], true)
	assert_eq(Rewards.credits_for(results, _economy), 650, "500 base + 100 completion + 50 restowed (blueprint p.12)")
	var receipts: Array[Dictionary] = Rewards.make_receipts("CAMP_A", Rewards.contract_instance_id("CAMP_A", "C01", 1), "C01", _accounts, results, _economy)
	assert_eq(receipts.size(), 2, "one personal receipt per participant")
	assert_ne(receipts[0]["receipt_key"], receipts[1]["receipt_key"])


func test_V08_tutorial_trip_is_free_later_trips_cost_the_third_star() -> void:
	var trace: Dictionary = Runner.json(C01.path_join("solution.json"))
	var ctx: Dictionary = Runner.build(C01, trace["players"], trace["tools"])
	ctx["mission"].note_events([{"type": "trip"}] as Array[Dictionary])
	Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"]))
	assert_eq(ctx["mission"].results()["stars"], 3, "the sign tutorial warning trip is allowed")
	var ctx2: Dictionary = Runner.build(C01, trace["players"], trace["tools"])
	ctx2["mission"].note_events([{"type": "trip"}, {"type": "trip"}] as Array[Dictionary])
	Runner.run(ctx2, trace["steps"], int(trace["pace_ticks_per_command"]))
	assert_eq(ctx2["mission"].results()["preventable_trips"], 1)
	assert_eq(ctx2["mission"].results()["stars"], 2, "no speed star exists; only preventable trips cost the third")


func test_V08_results_are_frozen_at_completion() -> void:
	var trace: Dictionary = Runner.json(C01.path_join("solution.json"))
	var ctx: Dictionary = Runner.build(C01, trace["players"], trace["tools"])
	Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"]))
	var at_completion: Dictionary = ctx["mission"].results()
	var carrier: String = str(trace["players"][0])
	var r: Dictionary = Runner.send(ctx, carrier, "place_item", "GEN_PORTABLE", {"action": "pickup"})
	assert_true(r["ok"], "the stowed generator can still be picked up after completion: %s" % str(r))
	Runner.ticks(ctx, 5)
	assert_eq(ctx["mission"].results(), at_completion, "unstowing after completion does not change the report")
	assert_eq(Rewards.credits_for(ctx["mission"].results(), _economy), 650, "nor the restow bonus")
	(ctx["mission"].results() as Dictionary)["stars"] = 0
	assert_eq(ctx["mission"].results()["stars"], 3, "callers get a copy, not the frozen report itself")


func test_V08_optional_services_are_reported_and_earn_the_second_star() -> void:
	var trace: Dictionary = Runner.json(C01.path_join("solution.json"))
	# content variants: APT_W is on grid supply at completion; PUMP runs only on the (stowed) generator, so it is not
	var ctx: Dictionary = Runner.build(C01, trace["players"], trace["tools"], {"optional_services": ["APT_W"]})
	assert_true((ctx["errors"] as Array).is_empty(), str(ctx["errors"]))
	Runner.run(ctx, trace["steps"], int(trace["pace_ticks_per_command"]))
	var won: Dictionary = ctx["mission"].results()
	assert_eq(won["optional_services"], ["APT_W"] as Array[String])
	assert_eq(won["stars"], 3)
	assert_eq(Rewards.credits_for(won, _economy), 650 + int(_economy["optional_service_bonus_each"]), "optional bonus paid")
	var ctx2: Dictionary = Runner.build(C01, trace["players"], trace["tools"], {"optional_services": ["APT_W", "PUMP"]})
	Runner.run(ctx2, trace["steps"], int(trace["pace_ticks_per_command"]))
	var partial: Dictionary = ctx2["mission"].results()
	assert_eq(partial["optional_services"], ["APT_W"] as Array[String], "only restored services are listed")
	assert_eq(partial["optional_total"], 2)
	assert_eq(partial["stars"], 2, "not every optional service restored: no second star")


func test_V08_checkpoint_keeps_scoring_counters() -> void:
	var trace: Dictionary = Runner.json(C01.path_join("solution.json"))
	var steps: Array = trace["steps"]
	var pace: int = int(trace["pace_ticks_per_command"])
	var a: Dictionary = Runner.build(C01, trace["players"], trace["tools"])
	a["mission"].note_events([{"type": "trip"}, {"type": "trip"}, {"type": "player_recovered"}] as Array[Dictionary])
	var half: int = steps.size() / 2
	Runner.run(a, steps.slice(0, half), pace)
	var payload: Dictionary = Codec.encode("CAMP_A", "C01", a["grid"], a["interaction"], a["equipment"], a["mission"])
	var b: Dictionary = Runner.build(C01, trace["players"], trace["tools"])
	var errs: Array[Dictionary] = Codec.restore(payload, "C01", b["grid"], b["interaction"], b["equipment"], b["mission"])
	assert_true(errs.is_empty(), str(errs))
	assert_eq(b["mission"].durable_state(), a["mission"].durable_state(), "mission progress survives the checkpoint")
	Runner.run(b, steps.slice(half), pace)
	var res: Dictionary = b["mission"].results()
	assert_eq(res["trips"], 2)
	assert_eq(res["crew_recoveries"], 1)
	assert_eq(res["stars"], 2, "a save and load does not wipe the preventable trip")
	assert_eq(Codec.restore(payload, "C01", Runner.build(C01, [], [])["grid"], b["interaction"], b["equipment"])[0]["code"],
		"BAD_SAVE", "mission state with no director to receive it is refused, not dropped")
	var forged: Dictionary = payload.duplicate(true)
	forged["mission"]["latched"]["NO_SUCH_LATCH"] = 1
	var c: Dictionary = Runner.build(C01, trace["players"], trace["tools"])
	var before: Dictionary = c["mission"].durable_state()
	assert_eq(c["mission"].restore_state(forged["mission"])[0]["code"], "BAD_SAVE")
	assert_eq(c["mission"].durable_state(), before, "a refused mission state changes nothing")


func test_SAVE04_replaying_or_reopening_a_receipt_applies_credits_once() -> void:
	var r: Dictionary = _receipt(_accounts[1], "CAMP_A", 1, "C01")
	var first: Dictionary = Rewards.receive(_saves, _accounts[1], [r], _order, NOW)
	assert_true(first["ok"], str(first))
	assert_eq(first["profile"]["credits"], 650)
	var again: Dictionary = Rewards.receive(_saves, _accounts[1], [r, r], _order, NOW)
	assert_eq(again["profile"]["credits"], 650, "same receipt re-sent twice more: still once")
	var reopen: Dictionary = Rewards.receive(_saves, _accounts[1], [], _order, NOW)
	assert_eq(reopen["profile"]["credits"], 650, "reopening the game applies nothing new")
	assert_eq(reopen["acks"], [r["receipt_key"]] as Array[String], "the host can drop it once acknowledged")


func test_SAVE04_crash_between_inbox_and_profile_write_heals_without_double_pay() -> void:
	var r: Dictionary = _receipt(_accounts[1], "CAMP_A", 1, "C01")
	# simulate: the inbox was written, then the process died before the profile write
	var inbox_path: String = SaveService.profile_dir(_accounts[1]).path_join("receipts.json")
	assert_true(_saves.write_record(inbox_path, "receipts", _accounts[1], {"receipts": {r["receipt_key"]: r}}, NOW)["ok"])
	var healed: Dictionary = Rewards.receive(_saves, _accounts[1], [r], _order, NOW)
	assert_eq(healed["profile"]["credits"], 650, "applied exactly once after restart")


func test_V08_reconnect_gets_pending_receipts_until_acknowledged() -> void:
	var q: Rewards.HostQueue = Rewards.HostQueue.new()
	var receipts: Array[Dictionary] = [_receipt(_accounts[0], "CAMP_A", 1, "C01"), _receipt(_accounts[1], "CAMP_A", 1, "C01")]
	q.issue(receipts)
	q.issue(receipts)  # host issues again after a reconnect: still one entry each
	assert_eq(q.pending_for(_accounts[1]).size(), 1)
	var got: Dictionary = Rewards.receive(_saves, _accounts[1], q.pending_for(_accounts[1]), _order, NOW)
	for k: String in got["acks"]:
		q.ack(_accounts[1], k)
	assert_eq(q.pending_for(_accounts[1]).size(), 0)
	assert_eq(q.pending_for(_accounts[0]).size(), 1, "the other player's receipt is untouched")


func test_V08_a_new_run_is_a_new_receipt_but_the_same_run_never_pays_twice() -> void:
	var run1: Dictionary = _receipt(_accounts[1], "CAMP_A", 1, "C01")
	var run2: Dictionary = _receipt(_accounts[1], "CAMP_A", 2, "C01")
	assert_ne(run1["receipt_key"], run2["receipt_key"])
	var p: Dictionary = Rewards.receive(_saves, _accounts[1], [run1, run2, run1], _order, NOW)["profile"]
	assert_eq(p["credits"], 1300, "two runs, two receipts (replay economy is bounded later by CT07)")


func test_SAVE05_guest_completion_unlocks_board_and_never_touches_their_own_campaign() -> void:
	var guest: String = _accounts[1]
	var own_campaign: String = SaveService.checkpoint_path(guest, "CAMP_GUEST_OWN")
	assert_true(_saves.write_record(own_campaign, "checkpoint", "CAMP_GUEST_OWN", {"repairs": {"R_JW_FUSE": "opened"}}, NOW)["ok"])
	var before: PackedByteArray = FileAccess.get_file_as_bytes(own_campaign)
	var c08: Dictionary = _receipt(guest, "CAMP_HOST", 4, "C08")
	var p: Dictionary = Rewards.receive(_saves, guest, [c08], _order, NOW)["profile"]
	assert_eq(p["unlocked_through"], 9, "C08 and everything before it unlocked, next is C09")
	assert_eq(FileAccess.get_file_as_bytes(own_campaign), before, "the guest's own campaign world is not overwritten")
	var host_p: Dictionary = Rewards.receive(_saves, _accounts[0], [], _order, NOW)["profile"]
	assert_eq(host_p["credits"], 0, "credits are personal")


func test_V08_receipts_for_other_accounts_or_forged_keys_are_refused() -> void:
	var p: Dictionary = Rewards.new_profile(_accounts[1])
	var theirs: Dictionary = _receipt(_accounts[0], "CAMP_A", 1, "C01")
	assert_eq(Rewards.apply_receipt(p, theirs, _order)["code"], "WRONG_ACCOUNT")
	var forged: Dictionary = _receipt(_accounts[1], "CAMP_A", 1, "C01")
	forged["contract_instance_id"] = "CAMP_A_C01_R99"
	assert_eq(Rewards.apply_receipt(p, forged, _order)["code"], "BAD_RECEIPT", "key must match its own fields")
	var unknown: Dictionary = _receipt(_accounts[1], "CAMP_A", 1, "C99")
	assert_eq(Rewards.apply_receipt(p, unknown, _order)["code"], "BAD_RECEIPT")
	assert_eq(p["credits"], 0)


func test_V08_unreadable_profile_is_never_reset() -> void:
	var dir: String = SaveService.profile_dir(_accounts[1])
	DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(dir.path_join("profile.json"), FileAccess.WRITE)
	f.store_string("{corrupt")
	f.close()
	var res: Dictionary = Rewards.receive(_saves, _accounts[1], [_receipt(_accounts[1], "CAMP_A", 1, "C01")], _order, NOW)
	assert_eq(res["ok"], false)
	assert_eq(res["code"], "CORRUPT", "refuses instead of starting a fresh profile")
	assert_eq(FileAccess.get_file_as_string(dir.path_join("profile.json")), "{corrupt", "bytes kept")


# ---------- helpers ----------

func _receipt(account: String, campaign: String, run: int, contract: String) -> Dictionary:
	var results: Dictionary = {"optional_services": [], "equipment_collected": true, "stars": 3}
	return Rewards.make_receipts(campaign, Rewards.contract_instance_id(campaign, contract, run), contract, [account], results, _economy)[0]


func _rm_tree(path: String) -> void:
	var d: DirAccess = DirAccess.open(path)
	if d == null:
		return
	for f: String in d.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for sub: String in d.get_directories():
		_rm_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
