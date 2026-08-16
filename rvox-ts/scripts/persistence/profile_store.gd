class_name ProfileStore
extends RefCounted

## The cross-run profile (DEMO_PLAN.md §8/§9, RUN_RULES.md): the only things
## that persist between runs — unlocked blueprints, run statistics, and
## settings. Unlocks are awarded exactly once (the release gate "reward banking
## cannot duplicate or disappear"). Versioned with a migration hook.

const PROFILE_VERSION := 1
const DEFAULT_PATH := "user://profile.json"

const DEFAULT_PROFILE := {
	"version": PROFILE_VERSION,
	"unlocked_blueprints": [],
	"stats": {"runs_played": 0, "wins": 0, "losses": 0, "swords_forged": 0},
	"settings": {},
}

var path: String
var data: Dictionary


func _init(save_path: String = DEFAULT_PATH) -> void:
	path = save_path
	data = DEFAULT_PROFILE.duplicate(true)


func load_profile() -> void:
	data = _migrate(SaveIO.read_json(path, DEFAULT_PROFILE))


func save_profile() -> bool:
	return SaveIO.write_json(path, data)


func unlocked_blueprints() -> Array:
	return data.get("unlocked_blueprints", [])


func is_unlocked(blueprint_id: StringName) -> bool:
	return unlocked_blueprints().has(String(blueprint_id))


## Grant a blueprint unlock. Idempotent: returns true only the first time, so a
## crash-and-replay of the reward flow can never double-award. Does not save;
## the caller decides when to persist (typically right after, atomically).
func award_unlock(blueprint_id: StringName) -> bool:
	var list: Array = data["unlocked_blueprints"]
	if list.has(String(blueprint_id)):
		return false
	list.append(String(blueprint_id))
	return true


func record_run_result(won: bool, swords_forged: int = 0) -> void:
	var stats: Dictionary = data["stats"]
	stats["runs_played"] = int(stats.get("runs_played", 0)) + 1
	if won:
		stats["wins"] = int(stats.get("wins", 0)) + 1
	else:
		stats["losses"] = int(stats.get("losses", 0)) + 1
	stats["swords_forged"] = int(stats.get("swords_forged", 0)) + swords_forged


func get_setting(key: String, fallback: Variant = null) -> Variant:
	return data.get("settings", {}).get(key, fallback)


func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value


## Bring an older save forward. Fills any missing keys with defaults and stamps
## the current version. Extend with per-version steps as the schema grows.
func _migrate(loaded: Dictionary) -> Dictionary:
	var out := DEFAULT_PROFILE.duplicate(true)
	for key in loaded.keys():
		out[key] = loaded[key]
	# Ensure nested defaults exist even if an old save omitted them.
	for stat_key in DEFAULT_PROFILE["stats"].keys():
		if not out["stats"].has(stat_key):
			out["stats"][stat_key] = DEFAULT_PROFILE["stats"][stat_key]
	out["version"] = PROFILE_VERSION
	return out
