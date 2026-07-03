@tool
class_name ProceduralTextureGenerator
extends RefCounted

const FORMAT := Image.FORMAT_RGBA8


func generate_albedo_image(recipe: TextureRecipe) -> Image:
	var size := recipe.resolution
	var image := Image.create(size, size, false, FORMAT)
	var rng := RandomNumberGenerator.new()
	rng.seed = recipe.noise_seed
	match recipe.pattern:
		TextureRecipe.Pattern.SPECKLE:
			_fill_speckle(image, recipe, rng)
		TextureRecipe.Pattern.MOTTLE:
			_fill_mottle(image, recipe, rng)
		TextureRecipe.Pattern.STRIPES:
			_fill_stripes(image, recipe)
		TextureRecipe.Pattern.GRAIN:
			_fill_grain(image, recipe, rng)
		TextureRecipe.Pattern.CRACKS:
			_fill_cracks(image, recipe, rng)
		_:
			_fill_solid(image, recipe)
	_apply_contrast(image, recipe.contrast)
	return image


## Derives a tangent-space normal map from an albedo image's luminance via
## a Sobel filter, so hand-authored height maps aren't needed for a basic
## pixel-art bump.
func generate_normal_image(albedo: Image) -> Image:
	var size := albedo.get_width()
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			var c := albedo.get_pixel(x, y)
			heights[y * size + x] = c.r * 0.3 + c.g * 0.59 + c.b * 0.11

	var normal := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var strength := 2.0
	for y in size:
		for x in size:
			var hl := heights[y * size + _clamp_index(x - 1, size)]
			var hr := heights[y * size + _clamp_index(x + 1, size)]
			var hu := heights[_clamp_index(y - 1, size) * size + x]
			var hd := heights[_clamp_index(y + 1, size) * size + x]
			var dx := (hl - hr) * strength
			var dz := (hu - hd) * strength
			var n := Vector3(dx, dz, 1.0).normalized()
			normal.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	return normal


func generate_and_save(recipe: TextureRecipe, out_dir: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var albedo := generate_albedo_image(recipe)
	var normal := generate_normal_image(albedo)
	var albedo_path := out_dir.path_join("%s.png" % recipe.layer_name)
	var normal_path := out_dir.path_join("%s_normal.png" % recipe.layer_name)
	return {
		"layer_name": String(recipe.layer_name),
		"albedo_path": albedo_path,
		"normal_path": normal_path,
		"albedo_error": albedo.save_png(albedo_path),
		"normal_error": normal.save_png(normal_path),
	}


func _clamp_index(v: int, size: int) -> int:
	return clampi(v, 0, size - 1)


func _apply_contrast(image: Image, contrast: float) -> void:
	if is_equal_approx(contrast, 1.0):
		return
	var size := image.get_width()
	for y in size:
		for x in size:
			var c := image.get_pixel(x, y)
			var r := clampf((c.r - 0.5) * contrast + 0.5, 0.0, 1.0)
			var g := clampf((c.g - 0.5) * contrast + 0.5, 0.0, 1.0)
			var b := clampf((c.b - 0.5) * contrast + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(r, g, b, c.a))


func _fill_solid(image: Image, recipe: TextureRecipe) -> void:
	image.fill(recipe.base_color)


func _fill_speckle(image: Image, recipe: TextureRecipe, rng: RandomNumberGenerator) -> void:
	image.fill(recipe.base_color)
	var size := image.get_width()
	for y in size:
		for x in size:
			if rng.randf() < recipe.accent_density:
				image.set_pixel(x, y, recipe.accent_color)


## Blotchy patches: scatter blob centers, blend base/accent by falloff.
func _fill_mottle(image: Image, recipe: TextureRecipe, rng: RandomNumberGenerator) -> void:
	var size := image.get_width()
	var blob_count := maxi(1, int(size * size * recipe.accent_density * 0.02))
	var centers: Array[Vector2] = []
	for i in blob_count:
		centers.append(Vector2(rng.randf_range(0, size), rng.randf_range(0, size)))
	var radius := size * 0.18
	for y in size:
		for x in size:
			var weight := 0.0
			for center in centers:
				var d := Vector2(x, y).distance_to(center)
				weight = maxf(weight, clampf(1.0 - d / radius, 0.0, 1.0))
			image.set_pixel(x, y, recipe.base_color.lerp(recipe.accent_color, weight))


func _fill_stripes(image: Image, recipe: TextureRecipe) -> void:
	var size := image.get_width()
	var band := maxi(1, int(size / 8.0))
	for y in size:
		var use_accent := (y / band) % 2 == 1
		var row_color := recipe.accent_color if use_accent else recipe.base_color
		for x in size:
			image.set_pixel(x, y, row_color)


## Wavy vertical bands, like wood grain.
func _fill_grain(image: Image, recipe: TextureRecipe, rng: RandomNumberGenerator) -> void:
	var size := image.get_width()
	var band_width := maxf(1.0, size * 0.12 * recipe.accent_density)
	for y in size:
		var wobble := sin(float(y) * 0.35 + rng.randf() * 0.5) * size * 0.05
		for x in size:
			var band := fmod(float(x) + wobble + size, size * 0.12) < band_width
			image.set_pixel(x, y, recipe.accent_color if band else recipe.base_color)


## Jagged single-pixel-wide cracks meandering top to bottom.
func _fill_cracks(image: Image, recipe: TextureRecipe, rng: RandomNumberGenerator) -> void:
	image.fill(recipe.base_color)
	var size := image.get_width()
	var crack_count := maxi(1, int(size * recipe.accent_density * 0.3))
	for i in crack_count:
		var x := rng.randi_range(0, size - 1)
		var y := 0
		while y < size:
			if x >= 0 and x < size:
				image.set_pixel(x, y, recipe.accent_color)
				if x + 1 < size:
					image.set_pixel(x + 1, y, recipe.accent_color)
			x = clampi(x + rng.randi_range(-1, 1), 0, size - 1)
			y += 1
