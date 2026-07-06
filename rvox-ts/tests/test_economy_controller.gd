@tool
extends McpTestSuite

## Covers the runtime economy coordinator: authoritative stockpile, resource
## node registry + nearest-node targeting, station ticking with auto-start, and
## the manifest bridge. See DEMO_PLAN.md §4.


func suite_name() -> String:
	return "economy_controller"


func _controller() -> EconomyController:
	return track(EconomyController.new()) as EconomyController


func test_stockpile_add_remove_afford_pay() -> void:
	var eco := _controller()
	eco.add_stock(&"wood", 100)
	assert_eq(eco.get_stock(&"wood"), 100, "Stock reflects added wood")
	assert_true(eco.can_afford({&"wood": 40}), "Can afford within stock")
	assert_false(eco.can_afford({&"wood": 40, &"stone": 1}), "Missing item -> cannot afford")
	assert_true(eco.pay({&"wood": 40}), "Payment succeeds")
	assert_eq(eco.get_stock(&"wood"), 60, "Payment deducted")
	assert_false(eco.pay({&"wood": 999}), "Overdraft refused")
	assert_eq(eco.get_stock(&"wood"), 60, "Refused payment changes nothing")


func test_stock_changed_signal_fires() -> void:
	var eco := _controller()
	var seen := {"item": &"", "amount": -1}
	eco.stock_changed.connect(func(item: StringName, amount: int) -> void:
		seen["item"] = item
		seen["amount"] = amount)
	eco.add_stock(&"coal", 5)
	assert_eq(seen["item"], &"coal", "Signal carries the item id")
	assert_eq(seen["amount"], 5, "Signal carries the new total")


func test_node_registry_and_nodes_of_excludes_depleted() -> void:
	var eco := _controller()
	var a := ResourceNode.new(&"wood", 10, Vector3(1, 0, 1))
	var b := ResourceNode.new(&"wood", 5, Vector3(9, 0, 9))
	eco.register_node(a)
	eco.register_node(b)
	assert_eq(eco.nodes_of(&"wood").size(), 2, "Both wood nodes listed")
	# Deplete b.
	b.reserve(5)
	b.extract(5)
	assert_eq(eco.nodes_of(&"wood").size(), 1, "Depleted node drops out")


func test_nearest_available_node() -> void:
	var eco := _controller()
	var near := ResourceNode.new(&"raw_ore", 20, Vector3(2, 0, 2))
	var far := ResourceNode.new(&"raw_ore", 20, Vector3(40, 0, 40))
	eco.register_node(far)
	eco.register_node(near)
	var picked := eco.nearest_available_node(&"raw_ore", Vector3(0, 0, 0))
	assert_eq(picked, near, "Closest node is chosen")
	# Fully reserve the near node -> nearest falls through to the far one.
	near.reserve(20)
	assert_eq(eco.nearest_available_node(&"raw_ore", Vector3(0, 0, 0)), far, "Reserved-out node is skipped")


func test_station_auto_starts_and_produces_on_tick() -> void:
	var eco := _controller()
	var recipe := DemoChain.recipe_by_id(&"smelt_iron_ingot")
	var smelter := ProductionStation.new(&"smelter", recipe)
	smelter.input.add_item(&"raw_ore", 2)
	smelter.input.add_item(&"coal", 1)
	var finished := {"station": &"", "recipe": &""}
	eco.production_finished.connect(func(sid: StringName, rid: StringName) -> void:
		finished["station"] = sid
		finished["recipe"] = rid)
	eco.register_station(smelter)

	# tick() should auto-start the idle station (inputs ready) and, after the
	# duration, produce and relay the finished signal.
	eco.tick(1.0)
	assert_true(smelter.is_active(), "Controller auto-started the ready station")
	eco.tick(recipe.duration_seconds)
	# Output is drained into central stock, not left sitting in the station.
	assert_eq(eco.get_stock(&"iron_ingot"), 1, "Ingot produced and banked to stock")
	assert_eq(finished["station"], &"smelter", "Finished signal names the station")
	assert_eq(finished["recipe"], &"smelt_iron_ingot", "Finished signal names the recipe")


func test_station_feeds_from_and_drains_to_central_stock() -> void:
	# The runtime buffering: a station pulls a craft's inputs from central stock
	# and pushes finished goods back, rather than hoarding either. Two smelts'
	# worth of raw materials in stock -> two ingots in stock, nothing stranded.
	var eco := _controller()
	var smelter := ProductionStation.new(&"smelter", DemoChain.recipe_by_id(&"smelt_iron_ingot"))
	eco.register_station(smelter)
	eco.add_stock(&"raw_ore", 4)
	eco.add_stock(&"coal", 2)

	for i in 40:
		eco.tick(1.0)

	assert_eq(eco.get_stock(&"iron_ingot"), 2, "Both smelts' ingots land in central stock")
	assert_eq(smelter.output.get_amount(&"iron_ingot"), 0, "Output drained to stock, not hoarded")
	assert_eq(eco.get_stock(&"raw_ore"), 0, "Ore pulled from stock and consumed")
	assert_eq(eco.get_stock(&"coal"), 0, "Coal pulled from stock and consumed")


func test_populate_from_manifest_bridges_nodes() -> void:
	var config := WorldGenConfig.new()
	config.world_seed = 2468
	config.chunk_size = 80
	config.max_height = 36
	config.water_level = 11
	var generator := WorldGenerator.new()
	var chunk := generator.generate_chunk(Vector2i.ZERO, config)
	var manifest := ScenarioPlanner.new().plan(chunk, config)
	assert_true(manifest.valid, "Scenario valid: %s" % manifest.failure_reason)

	var eco := _controller()
	eco.populate_from_manifest(manifest, chunk)
	assert_eq(eco.nodes().size(), manifest.resource_nodes.size(), "One live node per manifest entry")
	assert_gt(eco.nodes_of(&"wood").size(), 0, "Wood nodes registered")
	assert_gt(eco.nodes_of(&"raw_ore").size(), 0, "Ore nodes registered")


func test_stockpile_buffered_chain_produces_swords() -> void:
	# The runtime wiring: stations pull inputs from central stock and push
	# outputs back, so raw materials in the stockpile flow through the whole
	# chain into finished swords over repeated ticks. Mirrors RunCoordinator's
	# station set (smelter + two forges).
	var eco := _controller()
	eco.register_station(ProductionStation.new(&"smelter", DemoChain.recipe_by_id(&"smelt_iron_ingot")))
	eco.register_station(ProductionStation.new(&"forge", DemoChain.recipe_by_id(&"make_wood_handle")))
	eco.register_station(ProductionStation.new(&"forge", DemoChain.recipe_by_id(&"craft_iron_sword")))

	var swords := {"count": 0}
	eco.production_finished.connect(func(_sid: StringName, rid: StringName) -> void:
		if rid == &"craft_iron_sword":
			swords["count"] += 1)

	# Enough raw materials for a sword: 2 swords worth of ore/coal/wood.
	eco.add_stock(&"raw_ore", 8)
	eco.add_stock(&"coal", 4)
	eco.add_stock(&"wood", 4)

	# Run the chain: smelts (6s each) + handle (3s) + sword (8s) with buffering.
	for i in 120:
		eco.tick(1.0)

	assert_gt(eco.get_stock(&"iron_sword"), 0, "The buffered chain yields at least one sword")
	assert_gt(swords["count"], 0, "production_finished fired for the sword recipe")


func test_diagnose_delegates_to_chain() -> void:
	var eco := _controller()
	eco.add_stock(&"wood_handle", 4)
	eco.add_stock(&"coal", 4)
	var result := eco.diagnose(&"iron_sword")
	assert_false(bool(result["producible"]), "No ore in stock -> sword blocked")
	assert_eq(result["missing"], &"raw_ore", "Delegated diagnosis finds the ore shortage")
