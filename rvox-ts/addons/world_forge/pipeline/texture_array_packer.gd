@tool
class_name TextureArrayPacker
extends RefCounted

const RECIPES_DIR := "res://data/textures/recipes"
const GENERATED_DIR := "res://data/textures/generated"
const ATLAS_PATH := "res://data/textures/terrain_texture_atlas.tres"


## Generates (or regenerates) every recipe's PNG pair via
## ProceduralTextureGenerator. Returns a report Dictionary.
func generate_all(recipes_dir := RECIPES_DIR, out_dir := GENERATED_DIR) -> Dictionary:
	var report := _new_report()
	var generator := ProceduralTextureGenerator.new()
	for recipe in _load_recipes(recipes_dir, report):
		var result := generator.generate_and_save(recipe, out_dir)
		if result.albedo_error != OK or result.normal_error != OK:
			report.failed += 1
			report.errors.append("%s: albedo=%s normal=%s" % [
				result.layer_name,
				error_string(result.albedo_error),
				error_string(result.normal_error),
			])
			continue
		report.generated += 1
		report.generated_paths.append(result.albedo_path)
		report.generated_paths.append(result.normal_path)
	return report


## Packs every recipe's already-generated PNG pair into a TerrainTextureAtlas
## saved at atlas_path. Reads PNG bytes directly (Image.load) rather than
## through the Texture2D import pipeline, since freshly generated PNGs may
## not have an .import sidecar yet.
func pack(recipes_dir := RECIPES_DIR, textures_dir := GENERATED_DIR, atlas_path := ATLAS_PATH) -> Dictionary:
	var report := _new_report()
	var recipes := _load_recipes(recipes_dir, report)
	recipes.sort_custom(func(a: TextureRecipe, b: TextureRecipe) -> bool:
		return String(a.layer_name) < String(b.layer_name))

	var layer_names := PackedStringArray()
	var albedo_images: Array[Image] = []
	var normal_images: Array[Image] = []
	var expected_size := -1

	for recipe in recipes:
		var albedo_path := textures_dir.path_join("%s.png" % recipe.layer_name)
		var normal_path := textures_dir.path_join("%s_normal.png" % recipe.layer_name)
		var albedo_image := Image.load_from_file(ProjectSettings.globalize_path(albedo_path))
		var normal_image := Image.load_from_file(ProjectSettings.globalize_path(normal_path))
		if albedo_image == null or normal_image == null:
			report.failed += 1
			report.errors.append("%s: missing generated PNG (run generate_all first)" % recipe.layer_name)
			continue
		if expected_size == -1:
			expected_size = albedo_image.get_width()
		elif albedo_image.get_width() != expected_size or normal_image.get_width() != expected_size:
			report.failed += 1
			report.errors.append("%s: size %dx%d does not match atlas size %dx%d" % [
				recipe.layer_name, albedo_image.get_width(), albedo_image.get_height(),
				expected_size, expected_size,
			])
			continue
		if albedo_image.get_format() != Image.FORMAT_RGBA8:
			albedo_image.convert(Image.FORMAT_RGBA8)
		if normal_image.get_format() != Image.FORMAT_RGBA8:
			normal_image.convert(Image.FORMAT_RGBA8)
		layer_names.append(String(recipe.layer_name))
		albedo_images.append(albedo_image)
		normal_images.append(normal_image)

	if albedo_images.is_empty():
		report.errors.append("No valid layers to pack")
		return report

	var atlas := TerrainTextureAtlas.new()
	atlas.layer_names = layer_names
	atlas.albedo_array = Texture2DArray.new()
	var albedo_create_error := atlas.albedo_array.create_from_images(albedo_images)
	atlas.normal_array = Texture2DArray.new()
	var normal_create_error := atlas.normal_array.create_from_images(normal_images)
	if albedo_create_error != OK or normal_create_error != OK:
		report.failed += 1
		report.errors.append("Texture2DArray.create_from_images failed: albedo=%s normal=%s" % [
			error_string(albedo_create_error), error_string(normal_create_error),
		])
		return report

	var error := ResourceSaver.save(atlas, atlas_path)
	if error != OK:
		report.failed += 1
		report.errors.append("Failed to save atlas: %s" % error_string(error))
		return report

	report.packed = layer_names.size()
	report.atlas_path = atlas_path
	return report


func _load_recipes(recipes_dir: String, report: Dictionary) -> Array[TextureRecipe]:
	var recipes: Array[TextureRecipe] = []
	var directory := DirAccess.open(recipes_dir)
	if directory == null:
		report.errors.append("Recipes folder does not exist: %s" % recipes_dir)
		return recipes
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.get_extension() == "tres":
			var recipe := load(recipes_dir.path_join(entry)) as TextureRecipe
			if recipe != null:
				recipes.append(recipe)
			else:
				report.errors.append("Not a TextureRecipe: %s" % entry)
		entry = directory.get_next()
	directory.list_dir_end()
	return recipes


func _new_report() -> Dictionary:
	return {
		"generated": 0,
		"packed": 0,
		"failed": 0,
		"atlas_path": "",
		"generated_paths": PackedStringArray(),
		"errors": PackedStringArray(),
	}
