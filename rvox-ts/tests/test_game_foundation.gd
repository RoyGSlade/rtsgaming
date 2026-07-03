@tool
extends McpTestSuite


func suite_name() -> String:
	return "game_foundation"


func test_world_generation_is_deterministic() -> void:
	var config := WorldGenConfig.new()
	config.world_seed = 4242
	config.chunk_size = 8
	config.max_height = 20
	config.water_level = 6
	config.generate_trees = false
	var generator := WorldGenerator.new()
	var first := generator.generate_chunk(Vector2i.ZERO, config)
	var second := generator.generate_chunk(Vector2i.ZERO, config)
	assert_eq(first.surface_heightmap, second.surface_heightmap, "Same seed must produce the same heights")
	assert_eq(first.blocks, second.blocks, "Same seed must produce the same block volume")


func test_forge_blueprint_loads_and_validates() -> void:
	var blueprint := BuildingBlueprintLoader.load_from_json("res://data/buildings/forge_blueprint_example.json")
	assert_true(blueprint != null, "Forge blueprint should load")
	if blueprint == null:
		return
	assert_eq(blueprint.id, &"forge", "Expected the starter forge blueprint")
	assert_gt(blueprint.blocks.size(), 0, "Forge blueprint should contain blocks")
	assert_true(blueprint.validate_basic().is_empty(), "Forge blueprint should pass basic validation")


func test_storage_inventory_never_overfills() -> void:
	var inventory := track(StorageInventory.new()) as StorageInventory
	inventory.capacity_per_item = 10
	assert_eq(inventory.add_item(&"stone", 14), 10, "Only available capacity should be accepted")
	assert_eq(inventory.get_amount(&"stone"), 10)
	assert_eq(inventory.remove_item(&"stone", 4), 4)
	assert_eq(inventory.get_amount(&"stone"), 6)


func test_starter_blocks_are_registered() -> void:
	var registry := track(BlockRegistry.new()) as BlockRegistry
	registry.load_blocks()
	for block_id: StringName in [&"grass", &"stone_bricks", &"wood_planks", &"tile_floor", &"roof_shingles"]:
		assert_true(registry.has_block(block_id), "Missing starter block: %s" % block_id)
