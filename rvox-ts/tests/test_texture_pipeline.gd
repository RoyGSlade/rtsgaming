@tool
extends McpTestSuite


func suite_name() -> String:
	return "texture_pipeline"


func test_recipe_generates_configured_resolution() -> void:
	var recipe := TextureRecipe.new()
	recipe.layer_name = &"test_swatch"
	recipe.resolution = 8
	recipe.pattern = TextureRecipe.Pattern.SPECKLE
	recipe.base_color = Color.RED
	recipe.accent_color = Color.BLUE
	var image := ProceduralTextureGenerator.new().generate_albedo_image(recipe)
	assert_eq(image.get_width(), 8, "Albedo image width should match recipe.resolution")
	assert_eq(image.get_height(), 8, "Albedo image height should match recipe.resolution")
	assert_eq(image.get_format(), Image.FORMAT_RGBA8, "Albedo image should be RGBA8")


func test_normal_image_matches_albedo_size() -> void:
	var recipe := TextureRecipe.new()
	recipe.layer_name = &"test_swatch"
	recipe.resolution = 8
	recipe.pattern = TextureRecipe.Pattern.GRAIN
	var generator := ProceduralTextureGenerator.new()
	var albedo := generator.generate_albedo_image(recipe)
	var normal := generator.generate_normal_image(albedo)
	assert_eq(normal.get_width(), albedo.get_width(), "Normal image should match albedo width")
	assert_eq(normal.get_height(), albedo.get_height(), "Normal image should match albedo height")


func test_block_definition_face_layer_fallback() -> void:
	var definition := BlockDefinition.new()
	definition.texture_side = &"stone"
	assert_eq(definition.get_face_layer_name(0), &"stone", "Side face should use texture_side")
	assert_eq(definition.get_face_layer_name(2), &"stone", "Top face falls back to texture_side when texture_top unset")
	assert_eq(definition.get_face_layer_name(3), &"stone", "Bottom face falls back to texture_side when texture_bottom unset")

	definition.texture_top = &"grass_top"
	definition.texture_bottom = &"dirt"
	assert_eq(definition.get_face_layer_name(2), &"grass_top", "Top face should use texture_top when set")
	assert_eq(definition.get_face_layer_name(3), &"dirt", "Bottom face should use texture_bottom when set")
	assert_eq(definition.get_face_layer_name(4), &"stone", "Non-top/bottom faces should still use texture_side")


func test_overlay_state_map_roundtrip() -> void:
	# RGBA8 storage quantizes to 1/255 steps, so compare with a tolerance
	# wider than is_equal_approx's default epsilon rather than exact/tight equality.
	var map := OverlayStateMap.new(4, 4)
	map.set_value(1, 2, OverlayStateMap.Channel.DAMAGE, 0.5)
	map.set_value(1, 2, OverlayStateMap.Channel.WETNESS, 0.25)
	map.set_value(1, 2, OverlayStateMap.Channel.MUD, 0.75)
	map.set_value(1, 2, OverlayStateMap.Channel.SNOW, 1.0)
	assert_true(absf(map.get_value(1, 2, OverlayStateMap.Channel.DAMAGE) - 0.5) < 0.01, "DAMAGE channel should round-trip")
	assert_true(absf(map.get_value(1, 2, OverlayStateMap.Channel.WETNESS) - 0.25) < 0.01, "WETNESS channel should round-trip")
	assert_true(absf(map.get_value(1, 2, OverlayStateMap.Channel.MUD) - 0.75) < 0.01, "MUD channel should round-trip")
	assert_true(absf(map.get_value(1, 2, OverlayStateMap.Channel.SNOW) - 1.0) < 0.01, "SNOW channel should round-trip")
	assert_eq(map.get_value(0, 0, OverlayStateMap.Channel.DAMAGE), 0.0, "Untouched cells should default to 0")


func test_fog_of_war_reveal_marks_radius() -> void:
	var fog := FogOfWar.new(16, 16)
	assert_false(fog.is_explored(8, 8), "Nothing should be explored initially")
	var changed := fog.reveal(8.0, 8.0, 2.0)
	assert_true(not changed.is_empty(), "First reveal over unexplored cells should report a change")
	assert_true(fog.is_explored(8, 8), "Center of reveal should be explored")
	assert_false(fog.is_explored(15, 15), "Far corner should remain unexplored")
	var changed_again := fog.reveal(8.0, 8.0, 2.0)
	assert_true(changed_again.is_empty(), "Re-revealing the same area should report no change")


func test_texture_array_packer_end_to_end() -> void:
	var fixture_dir := "user://test_texture_pipeline_fixture"
	var recipes_dir := fixture_dir.path_join("recipes")
	var textures_dir := fixture_dir.path_join("generated")
	var atlas_path := fixture_dir.path_join("atlas.tres")
	_remove_dir_recursive(fixture_dir)
	DirAccess.make_dir_recursive_absolute(recipes_dir)

	var recipe_a := TextureRecipe.new()
	recipe_a.layer_name = &"fixture_a"
	recipe_a.resolution = 8
	recipe_a.pattern = TextureRecipe.Pattern.SOLID
	recipe_a.base_color = Color.RED
	ResourceSaver.save(recipe_a, recipes_dir.path_join("fixture_a.tres"))

	var recipe_b := TextureRecipe.new()
	recipe_b.layer_name = &"fixture_b"
	recipe_b.resolution = 8
	recipe_b.pattern = TextureRecipe.Pattern.SOLID
	recipe_b.base_color = Color.BLUE
	ResourceSaver.save(recipe_b, recipes_dir.path_join("fixture_b.tres"))

	var packer := TextureArrayPacker.new()
	var gen_report := packer.generate_all(recipes_dir, textures_dir)
	assert_eq(gen_report.failed, 0, "Fixture generation should not fail: %s" % str(gen_report.errors))
	assert_eq(gen_report.generated, 2, "Both fixture recipes should generate")

	var pack_report := packer.pack(recipes_dir, textures_dir, atlas_path)
	assert_eq(pack_report.failed, 0, "Fixture packing should not fail: %s" % str(pack_report.errors))
	assert_eq(pack_report.packed, 2, "Both fixture layers should pack")

	var atlas := load(atlas_path) as TerrainTextureAtlas
	assert_true(atlas != null, "Packed atlas should load back from disk")
	if atlas != null:
		assert_eq(atlas.layer_names.size(), 2, "Atlas should contain both fixture layers")
		assert_eq(atlas.layer_index(&"fixture_a"), 0, "Layers should be sorted by name")
		assert_eq(atlas.layer_index(&"fixture_b"), 1, "Layers should be sorted by name")

	_remove_dir_recursive(fixture_dir)


func _remove_dir_recursive(path: String) -> void:
	var global_path := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(global_path):
		return
	var directory := DirAccess.open(global_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var entry_path := global_path.path_join(entry)
			if directory.current_is_dir():
				_remove_dir_recursive(entry_path)
			else:
				DirAccess.remove_absolute(entry_path)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(global_path)
