extends RefCounted
## Personal reward receipts (V08; blueprint p.10 "Save and progression contract", p.12 economy).
##
## Credits are personal, never a shared balance. On completion the host issues one receipt per participant, keyed by
## campaign_id + contract_instance_id + account_key, and keeps it queued for that account until the client
## acknowledges it (so a reconnecting player still receives it). Each client applies a receipt to its own profile
## at most once: the applied keys live inside the profile record itself, so one atomic profile write carries both
## the credits and the dedupe mark and a crash can never pay twice (SAVE04).
##
## Receipts only touch the personal profile (credits, board unlocks, best stars). They never touch any campaign
## world: a guest's own campaign keeps its repair state (SAVE05).
##
## Persistence goes through save_service.gd (atomic replace, backup, checksum). Pure apart from that.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const SaveService := preload("res://scripts/persistence/save_service.gd")

const PROFILE_SCHEMA: int = 1
const KIND_PROFILE: String = "profile"
const KIND_RECEIPTS: String = "receipts"


# ---------- host side ----------

## Contract instance ID: unique per run of a contract inside one campaign (run counter kept by the host campaign).
static func contract_instance_id(campaign_id: String, contract_id: String, run: int) -> String:
	return "%s_%s_R%d" % [campaign_id, contract_id, run]


static func receipt_key(campaign_id: String, contract_instance_id: String, account_key: String) -> String:
	return ("%s|%s|%s" % [campaign_id, contract_instance_id, account_key]).sha256_text()


## Credits for one participant from the mission results and the economy content (blueprint p.12). A poor run still
## earns the base reward on successful completion; there is no negative balance.
static func credits_for(results: Dictionary, economy: Dictionary) -> int:
	if results.is_empty():
		return 0
	var optional_bonus: int = mini(int(economy["optional_service_bonus_each"]) * (results["optional_services"] as Array).size(),
		int(economy["optional_service_bonus_cap"]))
	var restowed: int = int(economy["equipment_restowed_bonus"]) if results["equipment_collected"] else 0
	return int(economy["contract_base"]) + int(economy["completion_bonus"]) + optional_bonus + restowed


## One receipt per account that took part (connected at completion). Account keys are local random/hashed keys.
static func make_receipts(campaign_id: String, contract_instance: String, contract_id: String, accounts: Array,
		results: Dictionary, economy: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var sorted_accounts: Array = accounts.duplicate()
	sorted_accounts.sort()
	for acct: Variant in sorted_accounts:
		out.append({"receipt_key": receipt_key(campaign_id, contract_instance, str(acct)), "campaign_id": campaign_id,
			"contract_instance_id": contract_instance, "contract_id": contract_id, "account_key": str(acct),
			"credits": credits_for(results, economy), "stars": int(results.get("stars", 0))})
	return out


## Host receipts queue: receipts wait per account until acknowledged, and are re-sent after a reconnect.
class HostQueue:
	var _pending: Dictionary = {}  # account -> {receipt_key: receipt}

	func issue(receipts: Array[Dictionary]) -> void:
		for r: Dictionary in receipts:
			if not _pending.has(r["account_key"]):
				_pending[r["account_key"]] = {}
			(_pending[r["account_key"]] as Dictionary)[r["receipt_key"]] = r  # same key twice = one entry

	func pending_for(account: String) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		var mine: Dictionary = _pending.get(account, {})
		var keys: Array = mine.keys()
		keys.sort()
		for k: Variant in keys:
			out.append(mine[k])
		return out

	func ack(account: String, key: String) -> void:
		if _pending.has(account):
			(_pending[account] as Dictionary).erase(key)


# ---------- client side: the personal profile ----------

static func new_profile(account_key: String) -> Dictionary:
	return {"profile_schema": PROFILE_SCHEMA, "account_key": account_key, "credits": 0, "unlocked_through": 1,
		"best_stars": {}, "applied_receipts": {}}


## Applies a receipt to a profile dictionary (pure). Returns {"ok", "applied": bool, "code"?}. A receipt for another
## account is refused; an already applied receipt changes nothing.
static func apply_receipt(profile: Dictionary, receipt: Dictionary, campaign_order: Array) -> Dictionary:
	if receipt.get("account_key") != profile.get("account_key"):
		return {"ok": false, "applied": false, "code": "WRONG_ACCOUNT"}
	var key: String = str(receipt.get("receipt_key", ""))
	var expect: String = receipt_key(str(receipt.get("campaign_id")), str(receipt.get("contract_instance_id")), str(profile["account_key"]))
	if key != expect:
		return {"ok": false, "applied": false, "code": "BAD_RECEIPT"}
	if (profile["applied_receipts"] as Dictionary).has(key):
		return {"ok": true, "applied": false}
	var credits: Variant = PowerGrid.to_int(receipt.get("credits"))
	var stars: Variant = PowerGrid.to_int(receipt.get("stars"))
	var position: int = campaign_order.find(receipt.get("contract_id")) + 1
	if credits == null or int(credits) < 0 or stars == null or position < 1:
		return {"ok": false, "applied": false, "code": "BAD_RECEIPT"}
	profile["credits"] = int(profile["credits"]) + int(credits)
	# completing a contract unlocks it and every earlier one, so earlier prerequisites are never replayed (blueprint p.11)
	profile["unlocked_through"] = maxi(int(profile["unlocked_through"]), mini(position + 1, campaign_order.size()))
	var best: Dictionary = profile["best_stars"]
	best[receipt["contract_id"]] = maxi(int(best.get(receipt["contract_id"], 0)), int(stars))
	(profile["applied_receipts"] as Dictionary)[key] = true
	return {"ok": true, "applied": true}


## Client inbox: write the received receipts to receipts.json first, then apply every one not yet applied and save the
## profile. Running it again (after a crash, or with re-sent receipts) applies nothing twice. Returns the receipt keys
## to acknowledge to the host.
static func receive(saves: SaveService, account_key: String, receipts: Array, campaign_order: Array, saved_at_utc: String) -> Dictionary:
	var dir: String = SaveService.profile_dir(account_key)
	var inbox_path: String = dir.path_join("receipts.json")
	var profile_path: String = dir.path_join("profile.json")
	var inbox: Dictionary = {}
	var read_inbox: Dictionary = saves.read_record(inbox_path)
	if read_inbox["ok"]:
		inbox = read_inbox["payload"].get("receipts", {})
	elif read_inbox["code"] != "NOT_FOUND":
		return {"ok": false, "code": read_inbox["code"]}
	for r: Variant in receipts:
		if r is Dictionary and r.get("account_key") == account_key:
			inbox[r["receipt_key"]] = r
	var w: Dictionary = saves.write_record(inbox_path, KIND_RECEIPTS, account_key, {"receipts": inbox}, saved_at_utc)
	if not w["ok"]:
		return w
	var profile: Dictionary = new_profile(account_key)
	var read_profile: Dictionary = saves.read_record(profile_path)
	if read_profile["ok"]:
		profile = read_profile["payload"]
	elif read_profile["code"] != "NOT_FOUND":
		return {"ok": false, "code": read_profile["code"]}  # never reset a profile we could not read
	var acks: Array[String] = []
	var keys: Array = inbox.keys()
	keys.sort()
	for k: Variant in keys:
		var res: Dictionary = apply_receipt(profile, inbox[k], campaign_order)
		if res["ok"]:
			acks.append(str(k))
	w = saves.write_record(profile_path, KIND_PROFILE, account_key, profile, saved_at_utc)
	if not w["ok"]:
		return w
	return {"ok": true, "acks": acks, "profile": profile}
