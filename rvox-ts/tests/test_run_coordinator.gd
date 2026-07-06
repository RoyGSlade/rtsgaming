@tool
extends McpTestSuite

## Unit-tests the RunCoordinator logic that isn't tied to the live scene: the
## swordsman auto-training gate (a banked sword becomes a swordsman, capped at
## the objective goal). See DEMO_PLAN.md §7 and RUN_RULES.md.


func suite_name() -> String:
	return "run_coordinator"


func _harness() -> Dictionary:
	var coord := track(RunCoordinator.new()) as RunCoordinator
	var eco := track(EconomyController.new()) as EconomyController
	var dir := track(MissionDirector.new()) as MissionDirector
	coord.economy = eco
	coord.director = dir
	coord.stockpile_position = Vector3.ZERO
	dir.present_briefing()
	dir.begin_run()
	return {"coord": coord, "eco": eco, "dir": dir}


func test_trains_swordsman_from_banked_sword() -> void:
	var h := _harness()
	var coord: RunCoordinator = h["coord"]
	var eco: EconomyController = h["eco"]
	var dir: MissionDirector = h["dir"]
	var spawns := [0]
	coord.swordsman_trained.connect(func(_p: Vector3) -> void: spawns[0] += 1)

	eco.add_stock(&"iron_sword", 2)
	coord._try_train_swordsman()
	assert_eq(dir.swordsmen_trained, 1, "One swordsman trained from the sword")
	assert_eq(eco.get_stock(&"iron_sword"), 1, "The sword was consumed")
	assert_eq(spawns[0], 1, "A spawn was requested")


func test_no_training_without_a_sword() -> void:
	var h := _harness()
	var coord: RunCoordinator = h["coord"]
	var dir: MissionDirector = h["dir"]
	coord._try_train_swordsman()
	assert_eq(dir.swordsmen_trained, 0, "No sword in stock -> no swordsman")


func test_training_caps_at_objective_goal() -> void:
	var h := _harness()
	var coord: RunCoordinator = h["coord"]
	var eco: EconomyController = h["eco"]
	var dir: MissionDirector = h["dir"]
	eco.add_stock(&"iron_sword", 10)
	for i in 8:
		coord._try_train_swordsman()
	assert_eq(dir.swordsmen_trained, RunCoordinator.SWORDSMAN_GOAL, "Auto-training stops at the goal")
	assert_eq(eco.get_stock(&"iron_sword"), 10 - RunCoordinator.SWORDSMAN_GOAL, "Only goal-many swords consumed")


func _harness_with_profile(profile_path: String) -> Dictionary:
	var h := _harness()
	var coord: RunCoordinator = h["coord"]
	coord.profile = ProfileStore.new(profile_path)
	return h


func test_win_banks_a_blueprint_unlock_once() -> void:
	var path := "user://__test_saves__/coord_profile.json"
	SaveIO.remove(path)
	var h := _harness_with_profile(path)
	var coord: RunCoordinator = h["coord"]
	var resolved := {"outcome": -1, "unlock": &""}
	coord.run_resolved.connect(func(o: int, u: StringName) -> void:
		resolved["outcome"] = o
		resolved["unlock"] = u)

	coord._on_run_ended(MissionDirector.Outcome.WIN)
	assert_eq(resolved["unlock"], RunCoordinator.UNLOCKABLES[0], "First win unlocks the first blueprint")
	assert_true(coord.profile.is_unlocked(RunCoordinator.UNLOCKABLES[0]), "Unlock recorded in the profile")

	# Persisted: a fresh store at the same path sees the unlock.
	var reloaded := ProfileStore.new(path)
	reloaded.load_profile()
	assert_true(reloaded.is_unlocked(RunCoordinator.UNLOCKABLES[0]), "Unlock survives a reload")
	assert_eq(int(reloaded.data["stats"]["wins"]), 1, "The win was recorded")
	SaveIO.remove(path)


func test_second_win_unlocks_the_next_blueprint() -> void:
	var path := "user://__test_saves__/coord_profile2.json"
	SaveIO.remove(path)
	var h := _harness_with_profile(path)
	var coord: RunCoordinator = h["coord"]
	coord._on_run_ended(MissionDirector.Outcome.WIN)
	coord._on_run_ended(MissionDirector.Outcome.WIN)
	assert_true(coord.profile.is_unlocked(RunCoordinator.UNLOCKABLES[0]), "First reward held")
	assert_true(coord.profile.is_unlocked(RunCoordinator.UNLOCKABLES[1]), "Second win unlocks the next reward")
	assert_eq(coord.profile.unlocked_blueprints().size(), 2, "Two distinct unlocks, no duplication")
	SaveIO.remove(path)


func test_loss_banks_no_unlock() -> void:
	var path := "user://__test_saves__/coord_profile3.json"
	SaveIO.remove(path)
	var h := _harness_with_profile(path)
	var coord: RunCoordinator = h["coord"]
	var resolved := {"unlock": &"x"}
	coord.run_resolved.connect(func(_o: int, u: StringName) -> void: resolved["unlock"] = u)
	coord._on_run_ended(MissionDirector.Outcome.LOSS)
	assert_eq(resolved["unlock"], &"", "A loss unlocks nothing")
	assert_eq(coord.profile.unlocked_blueprints().size(), 0, "No blueprint banked on a loss")
	assert_eq(int(coord.profile.data["stats"]["losses"]), 1, "The loss was recorded")
	SaveIO.remove(path)


func test_objective_completes_after_swords_and_swordsmen() -> void:
	var h := _harness()
	var coord: RunCoordinator = h["coord"]
	var eco: EconomyController = h["eco"]
	var dir: MissionDirector = h["dir"]
	# Simulate three swords forged (objective's first half) then trained.
	dir.record_sword_produced(3)
	eco.add_stock(&"iron_sword", 3)
	for i in 3:
		coord._try_train_swordsman()
	assert_true(dir.objective_complete(), "3 swords produced + 3 swordsmen trained completes the objective")
