@tool
extends McpTestSuite

## Block-by-block construction (DEMO_PLAN.md §5): the BuildSite block model and
## its economy registration (a construct job is posted for a builder to claim).


func suite_name() -> String:
	return "build_site"


func test_site_places_blocks_to_completion() -> void:
	var site := BuildSite.new(&"forge", 5, {&"wood": 2})
	var progress: Array = []
	site.block_placed.connect(func(placed: int, total: int) -> void: progress.append([placed, total]))
	var done := {"fired": false}
	site.completed.connect(func() -> void: done["fired"] = true)

	for i in 5:
		assert_true(site.place_block(), "Block %d placed" % (i + 1))
	assert_false(site.place_block(), "No block placed past completion")
	assert_true(site.is_complete(), "Site complete after all blocks")
	assert_true(done["fired"], "completed signal fired once")
	assert_eq(progress, [[1, 5], [2, 5], [3, 5], [4, 5], [5, 5]], "Progress reads 1/5 … 5/5")


func test_progress_fraction_and_needs_block() -> void:
	var site := BuildSite.new(&"wall", 4, {})
	assert_true(site.needs_block(), "Fresh site needs blocks")
	site.place_block()
	site.place_block()
	assert_eq(site.progress_fraction(), 0.5, "Half raised")
	site.place_block()
	site.place_block()
	assert_false(site.needs_block(), "No blocks needed once complete")
	assert_eq(site.progress_fraction(), 1.0, "Fully raised")


func test_material_for_block_is_a_copy() -> void:
	var site := BuildSite.new(&"mine", 3, {&"wood": 1, &"stone": 2})
	var mats := site.material_for_block()
	mats[&"wood"] = 999
	assert_eq(site.material_for_block()[&"wood"], 1, "Callers can't mutate the site's bill")


func test_registering_a_site_posts_a_builder_job() -> void:
	var eco := track(EconomyController.new()) as EconomyController
	var site := BuildSite.new(&"smelter", 5, {&"stone": 2})
	eco.register_build_site(site)
	assert_eq(eco.build_sites().size(), 1, "Site tracked")
	var job := eco.job_board.claim_next(1, [&"builder"])
	assert_false(job.is_empty(), "A construct job was posted for a builder")
	assert_eq(job["type"], &"construct", "It is a construct job")
	assert_eq(job["data"]["site"], site, "The job carries the site")


func test_completing_a_site_emits_building_completed() -> void:
	var eco := track(EconomyController.new()) as EconomyController
	var site := BuildSite.new(&"tower", 2, {})
	var built := {"id": &""}
	eco.building_completed.connect(func(id: StringName) -> void: built["id"] = id)
	eco.register_build_site(site)
	site.place_block()
	site.place_block()
	assert_eq(built["id"], &"tower", "building_completed fires with the id")


func test_afford_and_take_block_materials() -> void:
	var eco := track(EconomyController.new()) as EconomyController
	var site := BuildSite.new(&"hall", 3, {&"wood": 4})
	eco.add_stock(&"wood", 6)
	assert_true(eco.can_afford_block(site), "Can afford the first block")
	assert_true(eco.take_block_materials(site), "Materials consumed for a block")
	assert_eq(eco.get_stock(&"wood"), 2, "Stockpile drops by the block cost")
	assert_false(eco.can_afford_block(site), "Not enough for another block")
	assert_false(eco.take_block_materials(site), "Refused when unaffordable")
	assert_eq(eco.get_stock(&"wood"), 2, "Refused take changes nothing")
