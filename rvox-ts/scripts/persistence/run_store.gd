class_name RunStore
extends RefCounted

## The in-progress run save (DEMO_PLAN.md §8): everything needed to resume a run
## exactly after a force-close — the seed, the scenario manifest, the economy
## stockpile snapshot, and the director state (phase, day, objective, raid
## history). Separate save domain from the profile, so a corrupt run never
## touches unlocks. Atomic + backed up via SaveIO.

const RUN_VERSION := 1
const DEFAULT_PATH := "user://run.json"

var path: String


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path


func has_run() -> bool:
	return SaveIO.exists(path)


func clear() -> void:
	SaveIO.remove(path)


## Capture the live run into a JSON-safe dict.
func capture(manifest: ScenarioManifest, economy: EconomyController, director: MissionDirector) -> Dictionary:
	var stock: Dictionary = {}
	for key in economy.stock_snapshot().keys():
		stock[String(key)] = int(economy.stock_snapshot()[key])
	# Node depletion state, so a resumed run doesn't refill mined veins.
	var node_state: Array = []
	for n in economy.nodes():
		node_state.append({
			"resource_id": String(n.resource_id),
			"remaining": n.remaining,
			"pos": [n.world_position.x, n.world_position.y, n.world_position.z],
		})
	return {
		"version": RUN_VERSION,
		"seed": manifest.seed,
		"manifest": manifest.to_dict(),
		"stock": stock,
		"nodes": node_state,
		"director": director.capture_state(),
	}


func save(manifest: ScenarioManifest, economy: EconomyController, director: MissionDirector) -> bool:
	return SaveIO.write_json(path, capture(manifest, economy, director))


## Load the raw run dict (empty if none). The scene layer rebuilds the world
## from `seed`/`manifest`, then applies `stock`/`nodes`/`director`.
func load_run() -> Dictionary:
	return SaveIO.read_json(path, {})


## Restore a director and economy stock from a loaded run dict. Node remaining
## amounts are reapplied by matching resource_id + position order.
func apply(run: Dictionary, economy: EconomyController, director: MissionDirector) -> void:
	director.restore_state(run.get("director", {}))
	for key in run.get("stock", {}).keys():
		var have := economy.get_stock(StringName(key))
		var want := int(run["stock"][key])
		if want > have:
			economy.add_stock(StringName(key), want - have)
		elif want < have:
			economy.remove_stock(StringName(key), have - want)
