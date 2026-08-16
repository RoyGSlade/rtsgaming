@tool
extends McpTestSuite

## Verifies the scenario-placement guarantees from DEMO_PLAN.md §3/§14 against
## real generated terrain across many seeds: a viable camp, one of each
## resource within a reachable gather ring, and a raider camp outside the
## safety radius but path-reachable. Determinism is checked too (same seed ->
## same manifest).


func suite_name() -> String:
	return "scenario_planner"


func _make_config(seed_value: int) -> WorldGenConfig:
	var config := WorldGenConfig.new()
	config.world_seed = seed_value
	config.chunk_size = 96
	config.max_height = 40
	config.water_level = 12
	# Keep trees on (wood nodes prefer them) but generation stays fast.
	return config


func test_manifest_satisfies_all_guarantees() -> void:
	var config := _make_config(2026)
	var generator := WorldGenerator.new()
	var chunk := generator.generate_chunk(Vector2i.ZERO, config)
	var planner := ScenarioPlanner.new()
	var manifest := planner.plan(chunk, config)

	assert_true(manifest.valid, "Seed 2026 should yield a valid scenario: %s" % manifest.failure_reason)
	# One of each resource type, in the counts RUN_RULES fixes.
	assert_eq(manifest.nodes_of(&"wood").size(), 3, "Three wood nodes")
	assert_eq(manifest.nodes_of(&"raw_ore").size(), 2, "Two ore nodes")
	assert_eq(manifest.nodes_of(&"coal").size(), 2, "Two coal nodes")
	# Yields cover the 3-sword goal with slack (RUN_RULES economy table).
	assert_gt(manifest.total_yield(&"raw_ore"), 12, "Ore yield covers 3 swords")
	assert_gt(manifest.total_yield(&"coal"), 6, "Coal yield covers 3 swords")


func test_all_landmarks_reachable_from_camp() -> void:
	var config := _make_config(555)
	var generator := WorldGenerator.new()
	var chunk := generator.generate_chunk(Vector2i.ZERO, config)
	var planner := ScenarioPlanner.new()
	var manifest := planner.plan(chunk, config)
	assert_true(manifest.valid, "Scenario valid: %s" % manifest.failure_reason)

	var reach := planner._bfs_distances(chunk, config, manifest.camp_site)
	for node in manifest.resource_nodes:
		assert_true(reach.has(node["cell"]), "Resource node %s at %s must be reachable" % [node["resource_id"], node["cell"]])
	assert_true(reach.has(manifest.raider_camp), "Raider camp must be reachable from camp")


func test_raider_camp_outside_safety_radius() -> void:
	var config := _make_config(777)
	var generator := WorldGenerator.new()
	var chunk := generator.generate_chunk(Vector2i.ZERO, config)
	var planner := ScenarioPlanner.new()
	var manifest := planner.plan(chunk, config)
	assert_true(manifest.valid, "Scenario valid: %s" % manifest.failure_reason)

	var camp := manifest.camp_site
	var raider := manifest.raider_camp
	var cheb: int = maxi(absi(raider.x - camp.x), absi(raider.y - camp.y))
	assert_gt(cheb, manifest.safety_radius, "Raider camp must sit beyond the safety radius")


func test_resource_nodes_not_stacked_on_camp() -> void:
	var config := _make_config(4242)
	var generator := WorldGenerator.new()
	var chunk := generator.generate_chunk(Vector2i.ZERO, config)
	var planner := ScenarioPlanner.new()
	var manifest := planner.plan(chunk, config)
	assert_true(manifest.valid, "Scenario valid: %s" % manifest.failure_reason)

	for node in manifest.resource_nodes:
		var cell: Vector2i = node["cell"]
		var d: int = absi(cell.x - manifest.camp_site.x) + absi(cell.y - manifest.camp_site.y)
		assert_gt(d, 7, "Node %s should sit outside the reserved camp core" % cell)


func test_manifest_is_deterministic() -> void:
	var config_a := _make_config(31337)
	var config_b := _make_config(31337)
	var generator := WorldGenerator.new()
	var chunk_a := generator.generate_chunk(Vector2i.ZERO, config_a)
	var chunk_b := generator.generate_chunk(Vector2i.ZERO, config_b)
	var planner := ScenarioPlanner.new()
	var a := planner.plan(chunk_a, config_a)
	var b := planner.plan(chunk_b, config_b)
	assert_eq(a.camp_site, b.camp_site, "Same seed -> same camp site")
	assert_eq(a.raider_camp, b.raider_camp, "Same seed -> same raider camp")
	assert_eq(a.resource_nodes, b.resource_nodes, "Same seed -> identical node placement")


func test_to_resource_nodes_bridges_to_economy() -> void:
	var config := _make_config(909)
	var generator := WorldGenerator.new()
	var chunk := generator.generate_chunk(Vector2i.ZERO, config)
	var planner := ScenarioPlanner.new()
	var manifest := planner.plan(chunk, config)
	assert_true(manifest.valid, "Scenario valid: %s" % manifest.failure_reason)

	var nodes := ScenarioPlanner.to_resource_nodes(manifest, chunk)
	assert_eq(nodes.size(), manifest.resource_nodes.size(), "One ResourceNode per manifest entry")
	var wood_total := 0
	for n in nodes:
		if n.resource_id == &"wood":
			wood_total += n.remaining
		assert_gt(n.world_position.y, 0.0, "Node has a sampled world height")
	assert_eq(wood_total, manifest.total_yield(&"wood"), "Live nodes carry the manifest yields")


func test_many_seeds_produce_valid_scenarios() -> void:
	# The DEMO_PLAN §14 "no impossible start" guarantee, in miniature: most
	# seeds must plan cleanly, and plan_or_retry must always recover a valid one.
	var generator := WorldGenerator.new()
	var planner := ScenarioPlanner.new()
	var valid_count := 0
	var sample := 12
	for i in sample:
		var config := _make_config(1000 + i * 37)
		var chunk := generator.generate_chunk(Vector2i.ZERO, config)
		if planner.plan(chunk, config).valid:
			valid_count += 1
	assert_gt(valid_count, sample / 2, "Most sampled seeds plan cleanly (%d/%d)" % [valid_count, sample])

	# Retry must always land a valid scenario, even starting from a bad seed.
	var retry_config := _make_config(1000)
	var recovered := planner.plan_or_retry(retry_config, generator, 10)
	assert_true(recovered.valid, "plan_or_retry recovers a valid scenario")
