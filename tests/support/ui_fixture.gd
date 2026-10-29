extends RefCounted
## V07 helpers: C01 HUD/tablet data from a real host run (solution trace replayed partway), a worst-case HUD view for layout
## tests, and a synchronous layout pass for headless tests (the runner cannot await frames between assertions).

const Runner := preload("res://tests/support/solution_runner.gd")
const HudPresenter := preload("res://scripts/ui/hud_presenter.gd")
const TabletPresenter := preload("res://scripts/ui/tablet_presenter.gd")
const UiText := preload("res://scripts/ui/ui_text.gd")
const C01: String = "res://content/contracts/c01_alder_street"
const PLAYERS: Array[String] = ["P1", "P2", "P3", "P4"]
const NAMES: Dictionary = {"P1": "Rowan", "P2": "Mira", "P3": "Alex", "P4": "Jo"}
const TOOLS: Array[String] = ["meter", "screwdriver", "puller", "cutter", "crimper"]
const PACE_TICKS: int = 3
const WEST_DONE_STEP: int = 24  # solution.json steps before this one: west repaired, generator running on the pump
const DRAIN_TICKS: int = 125  # past the 120-tick pump latch (mission.json), so the east repair is reachable


## Host context partway through C01: west restored, the generator has drained the basement and still runs the pump,
## P2 (Mira) measured junction JE and holds the east trunk repair lock, P3 measured the grid source.
static func mid_shift() -> Dictionary:
	var ctx: Dictionary = Runner.build(C01, PLAYERS, TOOLS)
	var steps: Array = Runner.json(C01.path_join("solution.json"))["steps"]
	ctx["failures"] = Runner.run(ctx, steps.slice(0, WEST_DONE_STEP), PACE_TICKS)
	Runner.ticks(ctx, DRAIN_TICKS)
	Runner.send(ctx, "P2", "inspect", "PANEL_JE", {})
	Runner.send(ctx, "P2", "request_lock", "R_JE_TRUNK", {})
	Runner.send(ctx, "P3", "inspect", "PANEL_GRID", {})
	return ctx


static func content() -> Dictionary:
	return {"grid": Runner.json(C01.path_join("grid.json")), "tablet": Runner.json(C01.path_join("tablet.json")),
		"meter": Runner.json(C01.path_join("meter.json")), "repairs": Runner.json(C01.path_join("repairs.json")),
		"equipment": Runner.json(C01.path_join("equipment.json")),
		"grid_source": str(Runner.json(C01.path_join("mission.json"))["grid_source"])}


## Tablet view from what P1 can know in ctx (meter readings and findings of every panel, as the host computes them).
static func tablet_view(ctx: Dictionary) -> Dictionary:
	var c: Dictionary = content()
	var readings: Dictionary = {}
	var findings: Dictionary = {}
	for p: Dictionary in c["meter"]["panels"]:
		readings[p["id"]] = ctx["meter"].readings(p["id"], ctx["grid"])
		findings[p["id"]] = ctx["meter"].findings(p["id"], ctx["grid"])
	var state: Dictionary = ctx["host"].authoritative_state()
	return TabletPresenter.build(c, {"grid": state["grid"], "readings": readings, "findings": findings, "repairs": state["repairs"],
		"names": NAMES})


static func hud_view(ctx: Dictionary, local: String = "P1") -> Dictionary:
	var c: Dictionary = content()
	var mission_objectives: Array[Dictionary] = ctx["mission"].objectives()
	return HudPresenter.build(ctx["host"].authoritative_state(), mission_objectives, {
		"local_player": local, "names": NAMES, "tools": TOOLS.slice(0, 4), "selected_slot": 1,
		"repairs": c["repairs"], "equipment": c["equipment"],
		"prompt": {"object_key": "prompt.object.pad_pump", "action": "interact", "verb_key": "prompt.verb.connect",
			"detail_text": UiText.tf("prompt.detail.demand_capacity", [4, 6])},
		"event": {"group": "supply", "state": "restored", "text": UiText.t("event.west_restored")}})


## The fullest HUD the layout must hold: three objective rows, four busy crew, a prompt with a missing condition, five tools.
static func worst_hud_view() -> Dictionary:
	var objectives: Array[Dictionary] = [
		{"id": "OBJ_WEST", "text_key": "objective.c01.restore_west", "status": "done"},
		{"id": "OBJ_PUMP", "text_key": "objective.c01.drain_basement", "status": "active"},
		{"id": "OBJ_EAST", "text_key": "objective.c01.restore_east", "status": "active"}]
	var crew: Array[Dictionary] = []
	for p: String in PLAYERS:
		crew.append({"player": p, "name": NAMES[p], "local": p == "P1", "task_group": "other", "task_state": "lock_owner",
			"task_text": UiText.t("repair.c01.east_trunk")})
	return {"district_key": "district.alder_street", "contract_key": "contract.c01", "objectives": objectives, "crew": crew,
		"tools": TOOLS, "selected_slot": 2, "carrying": "generator",
		"prompt": {"object_key": "prompt.object.panel_je", "action": "interact", "verb_key": "prompt.verb.repair",
			"detail_group": "findings", "detail_state": "ISOLATED", "detail_text": UiText.t("prompt.missing.isolate_first")},
		"event": {"group": "other", "state": "breaker_tripped", "text": UiText.tf("event.breaker_tripped", [UiText.t("node.c01.je")])}}


## Runs container sorting top-down until sizes settle (wrapping labels change height once their width is known).
## Godot refreshes cached minimum sizes one frame later (deferred minimum_size_changed); a headless test cannot wait for
## frames, so every pass first invalidates the caches bottom-up, then sorts top-down.
static func settle(root: Node, passes: int = 6) -> void:
	for _i: int in passes:
		_invalidate(root)
		_sort(root)


static func _invalidate(n: Node) -> void:
	for c: Node in n.get_children():
		_invalidate(c)
	if n is Control:
		(n as Control).update_minimum_size()


static func _sort(n: Node) -> void:
	if n is Container:
		n.notification(Container.NOTIFICATION_SORT_CHILDREN)
	for c: Node in n.get_children():
		_sort(c)


## Every Control below root (pre-order), including root.
static func controls(root: Node, out: Array[Control] = []) -> Array[Control]:
	if root is Control:
		out.append(root)
	for c: Node in root.get_children():
		controls(c, out)
	return out


static func rect_inside(inner: Rect2, outer: Rect2, tolerance: float = 0.75) -> bool:
	return inner.position.x >= outer.position.x - tolerance and inner.position.y >= outer.position.y - tolerance \
		and inner.end.x <= outer.end.x + tolerance and inner.end.y <= outer.end.y + tolerance
