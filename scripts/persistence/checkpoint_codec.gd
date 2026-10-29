extends RefCounted
## Host checkpoint payload (G06): durable causes only. Grid runtime flags, added edges, tick and overload counters;
## repair states, supplies and access flags; equipment anchors. Derived power state (supplied, flow, load) is never
## stored and is recomputed on load; meter snapshots are not stored either, so every panel reads "?" after a load
## until it is inspected again (no stale or false readings).
##
## Restore onto freshly loaded content instances. If any part is refused, discard all three instances.

const PowerGrid := preload("res://scripts/simulation/power_grid.gd")
const Interaction := preload("res://scripts/interaction/interaction_service.gd")
const Equipment := preload("res://scripts/interaction/equipment_service.gd")

const KIND: String = "checkpoint"
const PAYLOAD_VERSION: int = 1


static func encode(campaign_id: String, contract_id: String, grid: PowerGrid, interaction: Interaction, equipment: Equipment) -> Dictionary:
	var repairs: Dictionary = interaction.canonical_state()
	repairs.erase("revision")
	var items: Dictionary = equipment.canonical_state()
	items.erase("revision")
	return {"payload_version": PAYLOAD_VERSION, "campaign_id": campaign_id, "contract_id": contract_id,
		"grid": grid.causes(), "repairs": repairs, "equipment": items}


## Returns diagnostics; empty means all three were restored.
static func restore(payload: Dictionary, contract_id: String, grid: PowerGrid, interaction: Interaction, equipment: Equipment) -> Array[Dictionary]:
	if payload.get("payload_version") != PAYLOAD_VERSION or payload.get("contract_id") != contract_id:
		return [PowerGrid.diag("BAD_SAVE", "checkpoint is for another contract or payload version", [])]
	var errs: Array[Dictionary] = grid.restore_causes(payload.get("grid", {}))
	if errs.is_empty():
		errs = interaction.restore_state(payload.get("repairs", {}))
	if errs.is_empty():
		errs = equipment.restore_state(payload.get("equipment", {}))
	return errs
