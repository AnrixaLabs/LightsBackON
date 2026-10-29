extends RefCounted
## Host checkpoint payload (G06): durable causes only. Grid runtime flags, added edges, tick and overload counters;
## repair states, supplies and access flags; equipment anchors; mission progress (latches, verification and scoring
## counters, frozen results) when a mission director is running, so a save and load cannot change a run's stars. Derived power state (supplied, flow, load) is never
## stored and is recomputed on load; meter snapshots are not stored either, so every panel reads "?" after a load
## until it is inspected again (no stale or false readings).
##
## Restore onto freshly loaded content instances. If any part is refused, discard all three instances.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")
const MissionDirector := preload("res://scripts/simulation/mission_director.gd")

const KIND: String = "checkpoint"
const PAYLOAD_VERSION: int = 1


static func encode(campaign_id: String, contract_id: String, grid: PowerGrid, interaction: Interaction, equipment: Equipment,
		mission: MissionDirector = null) -> Dictionary:
	var repairs: Dictionary = interaction.canonical_state()
	repairs.erase("revision")
	var items: Dictionary = equipment.canonical_state()
	items.erase("revision")
	var payload: Dictionary = {"payload_version": PAYLOAD_VERSION, "campaign_id": campaign_id, "contract_id": contract_id,
		"grid": grid.causes(), "repairs": repairs, "equipment": items}
	if mission != null:
		payload["mission"] = mission.durable_state()
	return payload


## Returns diagnostics; empty means every part was restored. A mission director must get the mission part back:
## restoring a checkpoint that carries mission state without one, or the other way round, is refused.
static func restore(payload: Dictionary, contract_id: String, grid: PowerGrid, interaction: Interaction, equipment: Equipment,
		mission: MissionDirector = null) -> Array[Dictionary]:
	if payload.get("payload_version") != PAYLOAD_VERSION or payload.get("contract_id") != contract_id:
		return [PowerGrid.diag("BAD_SAVE", "checkpoint is for another contract or payload version", [])]
	if payload.has("mission") != (mission != null) or (mission != null and not payload["mission"] is Dictionary):
		return [PowerGrid.diag("BAD_SAVE", "checkpoint mission state does not match the running contract", [])]
	var errs: Array[Dictionary] = grid.restore_causes(payload.get("grid", {}))
	if errs.is_empty():
		errs = interaction.restore_state(payload.get("repairs", {}))
	if errs.is_empty():
		errs = equipment.restore_state(payload.get("equipment", {}))
	if errs.is_empty() and mission != null:
		errs = mission.restore_state(payload["mission"])
	return errs
