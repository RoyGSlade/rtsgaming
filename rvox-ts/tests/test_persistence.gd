@tool
extends McpTestSuite

## Save/load integrity (DEMO_PLAN.md §8, a release gate): atomic writes with
## backup, corruption recovery, profile round-trips, unlock-exactly-once, and
## exact run resume. Writes to a throwaway user:// dir cleaned up in teardown.


func suite_name() -> String:
	return "persistence"


var _dir := "user://__test_saves__"


func setup() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(_dir)


func teardown() -> void:
	_cleanup()


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(_dir):
		for f in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir + "/" + f)
		DirAccess.remove_absolute(_dir)


# ----- SaveIO -----

func test_save_io_round_trip() -> void:
	var path := _dir + "/rt.json"
	assert_true(SaveIO.write_json(path, {"a": 1, "b": "two"}), "Write succeeds")
	var back := SaveIO.read_json(path)
	assert_eq(int(back["a"]), 1, "Int round-trips")
	assert_eq(String(back["b"]), "two", "String round-trips")


func test_save_io_keeps_backup_on_overwrite() -> void:
	var path := _dir + "/bak.json"
	SaveIO.write_json(path, {"v": 1})
	SaveIO.write_json(path, {"v": 2})
	assert_true(FileAccess.file_exists(path + ".bak"), "Backup written on overwrite")
	var live := SaveIO.read_json(path)
	assert_eq(int(live["v"]), 2, "Live file has the newest data")


func test_save_io_recovers_from_corrupt_live_file() -> void:
	var path := _dir + "/corrupt.json"
	SaveIO.write_json(path, {"v": 1}) # good
	SaveIO.write_json(path, {"v": 2}) # good + backup of v1
	# Corrupt the live file.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ this is not valid json ]")
	f.close()
	var recovered := SaveIO.read_json(path, {"v": -1})
	assert_eq(int(recovered["v"]), 1, "Falls back to the backup when live is corrupt")


func test_save_io_missing_file_returns_fallback() -> void:
	var back := SaveIO.read_json(_dir + "/nope.json", {"default": true})
	assert_true(bool(back["default"]), "Missing file yields the fallback")


# ----- ProfileStore -----

func test_profile_round_trip() -> void:
	var path := _dir + "/profile.json"
	var store := ProfileStore.new(path)
	store.award_unlock(&"stone_walls")
	store.record_run_result(true, 3)
	store.set_setting("colorblind", true)
	assert_true(store.save_profile(), "Profile saves")

	var reloaded := ProfileStore.new(path)
	reloaded.load_profile()
	assert_true(reloaded.is_unlocked(&"stone_walls"), "Unlock persisted")
	assert_eq(int(reloaded.data["stats"]["wins"]), 1, "Win recorded")
	assert_eq(int(reloaded.data["stats"]["swords_forged"]), 3, "Swords recorded")
	assert_true(bool(reloaded.get_setting("colorblind")), "Setting persisted")


func test_unlock_awarded_exactly_once() -> void:
	var store := ProfileStore.new(_dir + "/once.json")
	assert_true(store.award_unlock(&"watchtower_ii"), "First award grants")
	assert_false(store.award_unlock(&"watchtower_ii"), "Second award is a no-op")
	assert_eq(store.unlocked_blueprints().size(), 1, "Only one copy of the unlock")


func test_profile_migration_fills_missing_keys() -> void:
	var path := _dir + "/old.json"
	# An older/partial save missing stats and version.
	SaveIO.write_json(path, {"unlocked_blueprints": ["forge_ii"]})
	var store := ProfileStore.new(path)
	store.load_profile()
	assert_eq(int(store.data["version"]), ProfileStore.PROFILE_VERSION, "Version stamped")
	assert_true(store.data["stats"].has("wins"), "Missing stats filled from defaults")
	assert_true(store.is_unlocked(&"forge_ii"), "Existing data preserved through migration")


# ----- RunStore (exact resume) -----

func test_run_save_and_exact_resume() -> void:
	var config := WorldGenConfig.new()
	config.world_seed = 13579
	config.chunk_size = 72
	config.max_height = 34
	config.water_level = 10
	var generator := WorldGenerator.new()
	var chunk := generator.generate_chunk(Vector2i.ZERO, config)
	var manifest := ScenarioPlanner.new().plan(chunk, config)
	assert_true(manifest.valid, "Scenario valid: %s" % manifest.failure_reason)

	var eco := track(EconomyController.new()) as EconomyController
	eco.populate_from_manifest(manifest, chunk)
	eco.add_stock(&"iron_ingot", 5)
	eco.add_stock(&"wood", 40)

	var director := track(MissionDirector.new()) as MissionDirector
	director.present_briefing()
	director.begin_run()
	director.advance(MissionDirector.DAY_SECONDS + 1.0) # into night 1
	director.record_sword_produced(2)

	var store := RunStore.new(_dir + "/run.json")
	assert_true(store.save(manifest, eco, director), "Run saves")
	assert_true(store.has_run(), "Run save exists")

	# Simulate a fresh boot: new objects, load the run, apply state.
	var run := store.load_run()
	assert_eq(int(run["seed"]), 13579, "Seed restored for deterministic regen")
	var restored_manifest := ScenarioManifest.from_dict(run["manifest"])
	assert_eq(restored_manifest.camp_site, manifest.camp_site, "Manifest camp restored")
	assert_eq(restored_manifest.resource_nodes, manifest.resource_nodes, "Manifest nodes restored")

	var eco2 := track(EconomyController.new()) as EconomyController
	var director2 := track(MissionDirector.new()) as MissionDirector
	store.apply(run, eco2, director2)
	assert_eq(eco2.get_stock(&"iron_ingot"), 5, "Stock restored exactly")
	assert_eq(eco2.get_stock(&"wood"), 40, "Second stock restored exactly")
	assert_eq(director2.day, 1, "Director day restored")
	assert_eq(director2.phase, MissionDirector.Phase.NIGHT, "Director phase restored")
	assert_eq(director2.swords_produced, 2, "Objective progress restored")


func test_clear_removes_run() -> void:
	var store := RunStore.new(_dir + "/clearme.json")
	SaveIO.write_json(store.path, {"version": 1})
	assert_true(store.has_run(), "Run present before clear")
	store.clear()
	assert_false(store.has_run(), "Run gone after clear")
