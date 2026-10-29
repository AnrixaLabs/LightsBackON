extends RefCounted
## Builds the field HUD view (field_hud.gd apply()) from authoritative state the player can see: mission objective rows,
## the crew list with repair locks and carried equipment, the local loadout. Pure; no scene tree.
## The HUD tracks only what the player measured or directly observed (S06): it shows no grid values.

const UiText := preload("res://scripts/ui/ui_text.gd")
const MissionDirector := preload("res://scripts/simulation/mission_director.gd")


## state: session_host authoritative_state(); objectives: mission_director objectives();
## ctx: {"local_player", "names": {player: display name}, "tools": Array, "selected_slot", "repairs": repairs.json,
##       "equipment": equipment.json, "district_key", "contract_key", "prompt", "event", "max_rows"}.
static func build(state: Dictionary, objectives: Array[Dictionary], ctx: Dictionary) -> Dictionary:
	var local: String = str(ctx.get("local_player", ""))
	var view: Dictionary = {
		"district_key": ctx.get("district_key", "district.alder_street"),
		"contract_key": ctx.get("contract_key", "contract.c01"),
		"objectives": objective_rows(objectives, int(ctx.get("max_rows", 3))),
		"crew": crew_rows(state, ctx),
		"tools": ctx.get("tools", []),
		"selected_slot": int(ctx.get("selected_slot", 1)),
		"carrying": carried_kind(state, local, ctx.get("equipment", {})),
		"prompt": ctx.get("prompt", {}),
		"event": ctx.get("event", {}),
	}
	return view


## The last finished objective, then the visible open ones, at most max_rows (blueprint p.11: three rows).
static func objective_rows(objectives: Array[Dictionary], max_rows: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var last_done: Dictionary = {}
	for o: Dictionary in objectives:
		if o["status"] == MissionDirector.STATUS_DONE:
			last_done = o
	if not last_done.is_empty():
		out.append(last_done)
	for o: Dictionary in objectives:
		if o["status"] == MissionDirector.STATUS_ACTIVE and o.get("visible", true) and out.size() < max_rows:
			out.append(o)
	return out


## Local player first, then the others by player ID. A repair lock or a carried item is the player's current task: the chip's
## icon says which (lock = working on it, generator = carrying it), its text names the repair or item (S06 "current task").
static func crew_rows(state: Dictionary, ctx: Dictionary) -> Array[Dictionary]:
	var local: String = str(ctx.get("local_player", ""))
	var names: Dictionary = ctx.get("names", {})
	var players: Array[String] = []
	players.assign(state.get("crew", []))
	players.sort()
	if players.has(local):
		players.erase(local)
		players.push_front(local)
	var repair_names: Dictionary = {}
	for r: Dictionary in (ctx.get("repairs", {}) as Dictionary).get("repairs", []):
		repair_names[r["id"]] = r["name_key"]
	var out: Array[Dictionary] = []
	for p: String in players:
		var row: Dictionary = {"player": p, "name": names.get(p, p), "local": p == local}
		var repairs: Dictionary = (state.get("repairs", {}) as Dictionary).get("repairs", {})
		for rid: String in repairs:
			if repairs[rid].get("lock_owner", "") == p:
				row.merge({"task_group": "other", "task_state": "lock_owner",
					"task_text": UiText.t(str(repair_names.get(rid, rid)))})
		var kind: String = carried_kind(state, p, ctx.get("equipment", {}))
		if kind != "" and not row.has("task_group"):
			row.merge({"task_group": "equipment", "task_state": kind,
				"task_text": UiText.t("equipment." + kind)})
		out.append(row)
	return out


static func carried_kind(state: Dictionary, player: String, equipment_def: Dictionary) -> String:
	var kinds: Dictionary = {}
	for e: Dictionary in equipment_def.get("equipment", []):
		kinds[e["id"]] = e["kind"]
	var items: Dictionary = (state.get("equipment", {}) as Dictionary).get("items", {})
	for iid: String in items:
		if items[iid].get("carrier", "") == player and player != "":
			return str(kinds.get(iid, ""))
	return ""
