@tool
extends McpTestSuite

## Drives the BuilderBrain through raising a building block by block, simulating
## movement (feeding the intent's move_target back as the next position). See
## DEMO_PLAN.md §5.


func suite_name() -> String:
	return "builder_brain"


func _drive(brain: BuilderBrain, start: Vector3, max_ticks: int = 400) -> void:
	var pos := start
	var ticks := 0
	var started := false
	while ticks < max_ticks:
		var intent := brain.tick(1.0, pos)
		ticks += 1
		if intent["move_target"] != null:
			pos = intent["move_target"]
		if brain.has_job():
			started = true
		elif started:
			return # finished the job and went idle


func test_builder_raises_a_building_block_by_block() -> void:
	var eco := track(EconomyController.new()) as EconomyController
	eco.add_stock(&"wood", 100)
	var site := BuildSite.new(&"forge", 5, {&"wood": 2}, Vector3(20, 0, 20))
	var progress: Array = []
	site.block_placed.connect(func(placed: int, _total: int) -> void: progress.append(placed))
	eco.register_build_site(site) # posts the construct job

	var brain := BuilderBrain.new(1, eco.job_board, eco, Vector3.ZERO, [&"builder"])
	_drive(brain, Vector3.ZERO)

	assert_true(site.is_complete(), "Building fully raised")
	assert_eq(progress, [1, 2, 3, 4, 5], "Blocks placed one at a time, 1..5")
	assert_eq(eco.get_stock(&"wood"), 100 - 5 * 2, "Each block consumed its materials from stock")
	assert_eq(eco.job_board.total_count(), 0, "Construct job completed")


func test_builder_passes_through_haul_and_place_states() -> void:
	var eco := track(EconomyController.new()) as EconomyController
	eco.add_stock(&"stone", 10)
	var site := BuildSite.new(&"wall", 2, {&"stone": 1}, Vector3(10, 0, 0))
	eco.register_build_site(site)
	var brain := BuilderBrain.new(2, eco.job_board, eco, Vector3.ZERO, [&"builder"])

	brain.tick(1.0, Vector3.ZERO) # claim -> head to stockpile (already at 0,0)
	# At the stockpile, picks up materials and heads to the site.
	var intent := brain.tick(1.0, Vector3.ZERO)
	assert_eq(brain.state, BuilderBrain.State.TO_SITE, "Carries a block to the site")
	assert_eq(int(intent["stance"]), BuilderBrain.STANCE_CARRY, "Carry stance en route")
	# Arrive, place (takes PLACE_SECONDS).
	brain.tick(1.0, site.position)
	assert_eq(brain.state, BuilderBrain.State.PLACING, "Places on arrival")
	brain.tick(BuilderBrain.PLACE_SECONDS, site.position)
	assert_eq(site.placed_blocks, 1, "First block down")


func test_builder_waits_without_materials_then_builds_when_stocked() -> void:
	var eco := track(EconomyController.new()) as EconomyController # empty stock
	var site := BuildSite.new(&"mine", 1, {&"wood": 3}, Vector3(5, 0, 5))
	eco.register_build_site(site)
	var brain := BuilderBrain.new(3, eco.job_board, eco, Vector3.ZERO, [&"builder"])

	brain.tick(1.0, Vector3.ZERO) # claim
	brain.tick(1.0, Vector3.ZERO) # at stockpile, can't afford -> waits
	assert_eq(brain.state, BuilderBrain.State.TO_STOCKPILE, "Waits at the stockpile for materials")
	assert_eq(site.placed_blocks, 0, "Nothing built yet")

	# Once materials arrive, the same builder picks up and finishes the building.
	eco.add_stock(&"wood", 3)
	_drive(brain, Vector3.ZERO)
	assert_true(site.is_complete(), "Builds once materials arrive")
