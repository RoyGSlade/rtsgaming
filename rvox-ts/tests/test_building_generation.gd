@tool
extends McpTestSuite

const ModuleLibrary := preload("res://scripts/buildings/generation/building_module_library.gd")
const WFCGenerator := preload("res://scripts/buildings/generation/building_wfc_generator.gd")
const ThumbnailRenderer := preload("res://scripts/rendering/blueprint_thumbnail_renderer.gd")


func suite_name() -> String:
	return "building_generation"


func test_module_libraries_load_and_validate() -> void:
	var paths := ModuleLibrary.list_library_paths()
	assert_gt(paths.size(), 0, "Expected module libraries in data/buildings/module_libraries")
	var registry := track(BlockRegistry.new()) as BlockRegistry
	registry.load_blocks()
	for path in paths:
		var library := ModuleLibrary.load_library(path)
		assert_true(not library.is_empty(), "Library should parse: %s" % path)
		var errors := ModuleLibrary.validate_library(library, registry)
		assert_true(errors.is_empty(), "%s should validate: %s" % [path, errors])


func test_generation_is_deterministic() -> void:
	var library := ModuleLibrary.load_library("res://data/buildings/module_libraries/hut.json")
	var first := WFCGenerator.new().generate(library, 2, 1234)
	var second := WFCGenerator.new().generate(library, 2, 1234)
	assert_true(not first.has("error"), "Generation should succeed: %s" % first.get("error", ""))
	assert_eq(first["blueprint"]["blocks"], second["blueprint"]["blocks"], "Same seed must produce the same building")
	assert_eq(first["stats"]["seed"], second["stats"]["seed"])


func test_tiers_scale_block_cost() -> void:
	var library := ModuleLibrary.load_library("res://data/buildings/module_libraries/hut.json")
	var small := WFCGenerator.new().generate(library, 1, 42)
	var large := WFCGenerator.new().generate(library, 3, 42)
	assert_true(not small.has("error") and not large.has("error"), "Both tiers should generate")
	assert_gt(int(large["stats"]["total_blocks"]), int(small["stats"]["total_blocks"]),
			"Higher tier must cost more blocks")


func test_generated_blueprint_round_trips() -> void:
	var library := ModuleLibrary.load_library("res://data/buildings/module_libraries/blacksmith.json")
	var result := WFCGenerator.new().generate(library, 2, 99)
	assert_true(not result.has("error"), "Generation should succeed: %s" % result.get("error", ""))
	var data: Dictionary = result["blueprint"]

	for block in data["blocks"]:
		assert_true(String(block["block_id"]) != "air", "Air must never appear in the buildable block list")

	assert_gt((data["interior_cells"] as Array).size(), 0, "Building should enclose interior air")
	assert_eq((data["sockets"] as Array).size(), 1, "Generated building should have a door socket")

	var path := "user://test_generated_blueprint.json"
	assert_eq(BlueprintSerializer.save_blueprint_json(path, data), OK, "Blueprint should save")
	var blueprint := BuildingBlueprintLoader.load_from_json(path)
	assert_true(blueprint != null, "Generated blueprint should load through the standard loader")
	if blueprint == null:
		return
	assert_true(blueprint.validate_basic().is_empty(), "Generated blueprint should pass basic validation")
	assert_gt(blueprint.blocks.size(), 0, "Generated blueprint should contain blocks")


func test_thumbnail_renderer_produces_a_nonblank_image() -> void:
	var blocks: Array = [
		{"pos": [0, 0, 0], "block_id": "stone"},
		{"pos": [1, 0, 0], "block_id": "stone"},
		{"pos": [0, 1, 0], "block_id": "wood_planks"},
		{"pos": [0, 0, 1], "block_id": "air"},  # Air must be skipped, not rendered.
	]
	var colors := {&"stone": Color(0.5, 0.5, 0.5), &"wood_planks": Color(0.6, 0.4, 0.2)}
	var image := ThumbnailRenderer.render(blocks, colors)
	assert_eq(image.get_width(), ThumbnailRenderer.CANVAS_SIZE.x)
	var painted := false
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				painted = true
				break
		if painted:
			break
	assert_true(painted, "Thumbnail should have at least one non-transparent pixel")


func test_thumbnail_renderer_handles_empty_input() -> void:
	var image := ThumbnailRenderer.render([], {})
	assert_eq(image.get_width(), ThumbnailRenderer.CANVAS_SIZE.x)
	assert_eq(image.get_pixel(image.get_width() / 2, image.get_height() / 2).a, 0.0,
			"An empty block list should produce a fully transparent (not crashed) image")


func test_thumbnail_renderer_saves_a_loadable_png() -> void:
	var blocks: Array = [{"pos": [0, 0, 0], "block_id": "stone"}]
	var path := "res://data/buildings/thumbnails/test_thumbnail_unit.png"
	assert_true(ThumbnailRenderer.render_and_save(blocks, {&"stone": Color.GRAY}, path), "Should save successfully")
	assert_true(FileAccess.file_exists(path))
	var reloaded := Image.load_from_file(ProjectSettings.globalize_path(path))
	assert_true(reloaded != null and not reloaded.is_empty(), "Saved PNG should be re-loadable as raw pixels")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_world_forge_browser_resolves_building_type_and_bounds() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)

	assert_eq(editor.call("_entry_building_type", {"building_type": "keep"}), "keep")
	assert_eq(editor.call("_entry_building_type", {"metadata": {"building": {"generator": {"library": "castle"}}}}), "castle")
	assert_eq(editor.call("_entry_building_type", {"generator": {"library": "blacksmith"}}), "blacksmith")
	assert_eq(editor.call("_entry_building_type", {}), "custom")

	var bounds: Vector3i = editor.call("_entry_block_bounds", {"blocks": [
		{"pos": [1, 0, 2]}, {"pos": [3, 4, 2]}, {"pos": [2, 1, 5]},
	]})
	assert_eq(bounds, Vector3i(3, 5, 4), "Bounds should be (max-min+1) per axis across all blocks")
	assert_eq(editor.call("_entry_block_bounds", {"blocks": []}), Vector3i.ONE, "No blocks should return a 1x1x1 fallback, not crash")


func test_generated_buildings_use_detail_shapes() -> void:
	var library := ModuleLibrary.load_library("res://data/buildings/module_libraries/hut.json")
	var result := WFCGenerator.new().generate(library, 3, 909)
	assert_true(not result.has("error"), "Manor should generate: %s" % result.get("error", ""))
	var blueprint: Dictionary = result["blueprint"]
	var shapes_seen := {}
	var floor_levels := {}
	var has_column := false
	var has_glass := false
	var roof_stair_rotations := {}
	for block: Dictionary in blueprint["blocks"]:
		var shape := String(block.get("shape_id", "cube"))
		shapes_seen[shape] = true
		if String(block["layer"]) == "floor" and shape == "cube":
			floor_levels[int((block["pos"] as Array)[1])] = true
		if "support" in (block["tags"] as Array):
			has_column = true
		if String(block["block_id"]) == "glass":
			has_glass = true
		if String(block["layer"]) == "roof" and shape == "stair":
			roof_stair_rotations[int(block.get("rotation_steps", 0))] = true
	assert_true(shapes_seen.has("stair"), "Pyramid roof should be built from stair blocks")
	assert_true(shapes_seen.has("slab"), "Roof ridge should be capped with slabs")
	assert_true(has_glass, "Windows should be glass, not holes")
	assert_true(has_column, "Large rooms should have support columns")
	assert_eq(roof_stair_rotations.size(), 4, "Roof stairs should face outward on all four sides")
	assert_gt(floor_levels.size(), 1, "Manor should be multi-story")


func test_light_source_blocks_are_registered() -> void:
	var registry := track(BlockRegistry.new()) as BlockRegistry
	registry.load_blocks()
	for block_id: StringName in [&"torch", &"lantern", &"brazier"]:
		assert_true(registry.has_block(block_id), "Missing light block: %s" % block_id)
		var definition := registry.get_block(block_id)
		assert_gt(definition.light_energy, 0.0, "%s should emit light" % block_id)
	assert_true(registry.get_block(&"torch").flame_effect, "Torches should have a flame effect")
	assert_true(not registry.get_block(&"lantern").flame_effect, "Lanterns are enclosed — no open flame")


func test_generator_places_lighting() -> void:
	var library := ModuleLibrary.load_library("res://data/buildings/module_libraries/hut.json")
	var result := WFCGenerator.new().generate(library, 2, 4242)
	assert_true(not result.has("error"), "Generation should succeed: %s" % result.get("error", ""))
	var blueprint: Dictionary = result["blueprint"]
	var lights: Array = blueprint.get("lights", [])
	assert_gt(lights.size(), 0, "Cottage should have light fixtures")
	var torch_count := 0
	var lantern_count := 0
	for block: Dictionary in blueprint["blocks"]:
		if "light" in (block["tags"] as Array):
			assert_true(String(block["shape_id"]) != "cube", "Light fixtures should use fixture shapes")
			match String(block["block_id"]):
				"torch": torch_count += 1
				"lantern": lantern_count += 1
	assert_gt(torch_count, 0, "Interior walls should carry torches")
	assert_gt(lantern_count, 0, "Entrance should be flanked by lanterns")
	assert_eq(lights.size(), torch_count + lantern_count, "lights array should index every light block")


func test_castle_courtyard_gets_braziers() -> void:
	var library := ModuleLibrary.load_library("res://data/buildings/module_libraries/castle.json")
	var result := WFCGenerator.new().generate(library, 3, 777)
	assert_true(not result.has("error"), "Castle should generate: %s" % result.get("error", ""))
	var has_brazier := false
	for block: Dictionary in result["blueprint"]["blocks"]:
		if String(block["block_id"]) == "brazier":
			has_brazier = true
			break
	assert_true(has_brazier, "Castle courtyard should have braziers")


func test_light_fixture_effect_builds() -> void:
	var fixture := track(LightFixtureEffect.new()) as LightFixtureEffect
	fixture.configure(Color(1.0, 0.7, 0.4), 2.5, 7.0, true)
	var has_light := false
	var particle_count := 0
	for child in fixture.get_children():
		if child is OmniLight3D:
			has_light = true
		if child is CPUParticles3D:
			particle_count += 1
	assert_true(has_light, "Fixture should create an OmniLight3D")
	assert_eq(particle_count, 2, "Open flame should have flame + ember particles")


func test_castle_layout_has_towers_gate_and_keep() -> void:
	var library := ModuleLibrary.load_library("res://data/buildings/module_libraries/castle.json")
	var result := WFCGenerator.new().generate(library, 3, 777)
	assert_true(not result.has("error"), "Castle should generate: %s" % result.get("error", ""))
	if result.has("error"):
		return
	var blueprint: Dictionary = result["blueprint"]
	assert_eq((blueprint["sockets"] as Array).size(), 2, "Castle should have a gate and a keep entrance")
	var has_battlement := false
	var has_arch := false
	var has_spire := false
	for block: Dictionary in blueprint["blocks"]:
		var tags: Array = block["tags"]
		if "battlement" in tags:
			has_battlement = true
		if "arch" in tags:
			has_arch = true
		if String(block["block_id"]) == "roof_shingles":
			has_spire = true
	assert_true(has_battlement, "Curtain walls should be crenellated")
	assert_true(has_arch, "Gate should have arch shoulders")
	assert_true(has_spire, "Cone tower tops should be shingled")
	assert_gt(int(result["stats"]["total_blocks"]), 1200, "A fantasy castle should be thousands of blocks")
	assert_gt((blueprint["interior_cells"] as Array).size(), 100, "Towers and keep should enclose interior air")


func test_world_forge_generates_and_exports_blueprints() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var gen_type: OptionButton = editor.get("_gen_type")
	assert_gt(gen_type.item_count, 0, "World Forge should list module libraries")
	gen_type.selected = 0
	editor.call("_refresh_generate_tiers")
	(editor.get("_gen_tier") as OptionButton).selected = 0
	(editor.get("_gen_seed") as SpinBox).value = 555
	editor.call("_on_generate_building")
	var document: ForgeDocument = editor.get("_document")
	assert_gt(document.blocks.size(), 0, "Generation should write blocks into the document")
	assert_true(document.metadata.get("building", {}).has("generator"), "Generation metadata should ride along in the document")
	assert_eq(document.building_type, "blacksmith", "Generating from a library should tag the document with that library's id")
	editor.call("_undo")
	assert_eq(document.blocks.size(), 0, "Generate should be one undoable transaction")
	editor.call("_redo")
	assert_gt(document.blocks.size(), 0, "Redo should restore the generated building")

	(editor.get("_id_edit") as LineEdit).text = "test_wfc_export"
	editor.call("_export_building_blueprint")
	var path := "res://data/buildings/test_wfc_export_blueprint.json"
	assert_true(FileAccess.file_exists(path), "Export should write a blueprint JSON")
	var blueprint := BuildingBlueprintLoader.load_from_json(path)
	assert_true(blueprint != null, "Exported blueprint should load through the standard loader")
	if blueprint != null:
		assert_true(blueprint.validate_basic().is_empty(), "Exported blueprint should pass basic validation")
		assert_eq(blueprint.blocks.size(), document.blocks.size(), "Every document block should export")
	var thumbnail_path := "res://data/buildings/thumbnails/test_wfc_export.png"
	assert_true(FileAccess.file_exists(thumbnail_path), "Export should also cache a browser preview thumbnail")

	editor.call("_refresh_library")
	var entries: Array = editor.get("_library_cards")
	assert_gt(entries.size(), 0, "Browser should list at least the exported card")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(thumbnail_path))


func test_every_library_tier_generates() -> void:
	for path in ModuleLibrary.list_library_paths():
		var library := ModuleLibrary.load_library(path)
		for tier in library.get("tiers", []):
			var tier_number := int(tier.get("tier", 0))
			var result := WFCGenerator.new().generate(library, tier_number, 7)
			assert_true(not result.has("error"),
					"%s tier %d should generate: %s" % [library.get("id", path), tier_number, result.get("error", "")])
			if result.has("error"):
				continue
			assert_gt(int(result["stats"]["total_blocks"]), 0,
					"%s tier %d should produce blocks" % [library.get("id", path), tier_number])
			assert_eq(int(result["stats"]["restarts"]), 0,
					"%s tier %d should solve without WFC restarts" % [library.get("id", path), tier_number])
