@tool
extends McpTestSuite

## The raid resolution logic and signal wiring (DEMO_PLAN.md §6). The live
## marching visuals need a full night to see; the mechanics are tested here.


func suite_name() -> String:
	return "raid_controller"


func test_strong_garrison_defends_small_raid() -> void:
	# Plenty of swordsmen + a watchtower vs an early raid -> defended.
	var outcome := RaidController.resolve(5, 1, 3)
	assert_true(bool(outcome["defended"]), "A prepared settlement repels the night-1 raid")


func test_unprepared_settlement_falls_to_big_wave() -> void:
	# No trained swordsmen (just the base militia) vs the night-3 wave -> lost.
	var outcome := RaidController.resolve(0, 0, 12)
	assert_false(bool(outcome["defended"]), "The night-3 wave overruns an undefended camp")


func test_more_swordsmen_flip_the_outcome() -> void:
	# Same raid, more defenders: there is a threshold where it flips to defended.
	var size := 10
	var few := RaidController.resolve(1, 0, size)
	var many := RaidController.resolve(8, 1, size)
	assert_false(bool(few["defended"]), "A token defense loses to 10 raiders")
	assert_true(bool(many["defended"]), "A full garrison holds the same wave")


func test_watchtowers_strengthen_the_defense() -> void:
	# A wave that overruns the swordsmen alone is held once a tower is built.
	var size := 8
	var no_tower := RaidController.resolve(1, 0, size)
	var with_tower := RaidController.resolve(1, 1, size)
	assert_false(bool(no_tower["defended"]), "A thin garrison alone falls to 8 raiders")
	assert_true(bool(with_tower["defended"]), "A watchtower turns the same fight")


func test_completed_watchtower_is_counted_in_resolution() -> void:
	# A watchtower completing (economy.building_completed) must be factored into
	# the next raid, ending it in a defense instead of a loss.
	var eco := track(EconomyController.new()) as EconomyController
	var raid := track(RaidController.new()) as RaidController
	var dir := track(MissionDirector.new()) as MissionDirector
	dir.present_briefing()
	dir.begin_run()
	raid.bind(dir, null, Vector3.ZERO, Vector3(50, 0, 50), eco)
	assert_eq(raid._watchtowers, 0, "No towers yet")
	eco.building_completed.emit(&"watchtower")
	assert_eq(raid._watchtowers, 1, "A completed watchtower is counted")
	# A thin garrison that would fall alone survives once the tower is counted.
	dir.swordsmen_trained = 1
	raid._pending = true
	raid._pending_size = 8
	raid._process(0.1)
	assert_eq(dir.outcome, MissionDirector.Outcome.NONE, "Tower-backed garrison survives (run continues)")


func test_raid_incoming_marks_pending_raid() -> void:
	# Detached from the tree (no world), so no visuals spawn — but the signal
	# still arms the raid with its size, which _process would then march/resolve.
	var raid := track(RaidController.new()) as RaidController
	var dir := track(MissionDirector.new()) as MissionDirector
	raid.bind(dir, null, Vector3.ZERO, Vector3(50, 0, 50))
	dir.present_briefing()
	dir.begin_run()
	dir.raid_incoming.emit(1, 4, &"haulers")
	assert_true(raid._pending, "raid_incoming arms a pending raid")
	assert_eq(raid._pending_size, 4, "Pending raid carries the wave size")


func test_lost_raid_destroys_town_hall() -> void:
	# With no visuals, _march_raiders returns arrived immediately, so a ticked
	# _process resolves at once. A hopeless raid must end the run in defeat.
	var raid := track(RaidController.new()) as RaidController
	var dir := track(MissionDirector.new()) as MissionDirector
	var ended := {"outcome": MissionDirector.Outcome.NONE}
	dir.run_ended.connect(func(o: int) -> void: ended["outcome"] = o)
	raid.bind(dir, null, Vector3.ZERO, Vector3(50, 0, 50))
	dir.present_briefing()
	dir.begin_run()
	raid._pending = true
	raid._pending_size = 20 # overwhelming, 0 swordsmen
	raid._process(0.1)
	assert_eq(ended["outcome"], MissionDirector.Outcome.LOSS, "A hopeless raid loses the run")
