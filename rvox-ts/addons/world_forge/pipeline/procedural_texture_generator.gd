@tool
class_name ProceduralTextureGenerator
extends RefCounted

## Generates each TextureRecipe's albedo (and derived normal map) PNG.
##
## Patterns are built from seamless FastNoiseLite fields plus deterministic
## hashes instead of raw per-pixel RNG, so every layer tiles cleanly and has
## multi-scale detail: large tonal patches, mid-scale features (bricks,
## grain, clumps), and a fine micro-noise pass over everything. The recipe
## contract is unchanged - base_color/accent_color/accent_density/noise_seed
## /contrast steer each pattern the same way they always did, just with much
## richer output.

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
	_apply_detail_noise(image, recipe)
	_apply_contrast(image, recipe.contrast)
	return image


## Derives a tangent-space normal map from the albedo's luminance. The
## height field is box-blurred once before the Sobel pass so single-pixel
## speckles read as gentle bumps instead of shot noise.
func generate_normal_image(albedo: Image) -> Image:
	var size := albedo.get_width()
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	for y in size:
		for x in size:
			var c := albedo.get_pixel(x, y)
			heights[y * size + x] = c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	heights = _blur_heights(heights, size)

	var normal := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var strength := 2.4
	for y in size:
		for x in size:
			var hl := heights[y * size + _wrap_index(x - 1, size)]
			var hr := heights[y * size + _wrap_index(x + 1, size)]
			var hu := heights[_wrap_index(y - 1, size) * size + x]
			var hd := heights[_wrap_index(y + 1, size) * size + x]
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


## Seamless fBm noise field in [0, 1], one value per pixel. Noise.
## get_seamless_image wraps the field on a torus, which is what keeps every
## pattern tileable - the old per-pixel RNG patterns were not.
func _noise_field(noise_seed: int, features: float, octaves: int, size: int) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = features / float(size)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	var img := noise.get_seamless_image(size, size)
	var field := PackedFloat32Array()
	field.resize(size * size)
	for y in size:
		for x in size:
			field[y * size + x] = img.get_pixel(x, y).r
	return field


## Cellular (Worley) field in [0, 1] - sharp-edged clumps for ore veins,
## pebbles, and leaf clusters.
func _cellular_field(noise_seed: int, features: float, size: int) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = noise_seed
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = features / float(size)
	noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	var img := noise.get_seamless_image(size, size)
	var field := PackedFloat32Array()
	field.resize(size * size)
	for y in size:
		for x in size:
			field[y * size + x] = img.get_pixel(x, y).r
	return field


## Fine per-pixel luminance variation layered over every pattern - the
## difference between "flat color regions" and something that reads as a
## surface. Two seamless octave bands: a broad +-6% tonal drift and a
## high-frequency +-5% micro grain.
func _apply_detail_noise(image: Image, recipe: TextureRecipe) -> void:
	var size := image.get_width()
	var broad := _noise_field(recipe.noise_seed + 91, 3.0, 3, size)
	var fine := _noise_field(recipe.noise_seed + 92, 24.0, 2, size)
	for y in size:
		for x in size:
			var index := y * size + x
			var factor := 0.94 + broad[index] * 0.12
			factor *= 0.95 + fine[index] * 0.10
			var c := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(
				clampf(c.r * factor, 0.0, 1.0),
				clampf(c.g * factor, 0.0, 1.0),
				clampf(c.b * factor, 0.0, 1.0),
				c.a))


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
	# Even "solid" gets a faint large-scale drift toward the accent so flat
	# overlay layers stop looking like untextured plastic.
	var size := image.get_width()
	var drift := _noise_field(recipe.noise_seed, 2.0, 3, size)
	for y in size:
		for x in size:
			image.set_pixel(x, y, recipe.base_color.lerp(recipe.accent_color, drift[y * size + x] * 0.3))


## Stone/ore/grass speckling: soft-edged cellular clumps sized and thinned
## by accent_density, over a gently mottled base - replaces the old
## single-pixel white-noise dots.
func _fill_speckle(image: Image, recipe: TextureRecipe, _rng: RandomNumberGenerator) -> void:
	var size := image.get_width()
	var patches := _noise_field(recipe.noise_seed, 4.0, 3, size)
	var clumps := _cellular_field(recipe.noise_seed + 7, 22.0, size)
	var sparkle := _noise_field(recipe.noise_seed + 13, 40.0, 2, size)
	var threshold := 1.0 - clampf(recipe.accent_density, 0.02, 0.9)
	for y in size:
		for x in size:
			var index := y * size + x
			var color := recipe.base_color.lerp(recipe.accent_color, 0.06 + patches[index] * 0.16)
			if clumps[index] > threshold:
				var edge := clampf((clumps[index] - threshold) / maxf(0.001, 1.0 - threshold), 0.0, 1.0)
				color = color.lerp(recipe.accent_color, 0.5 + edge * 0.5)
				# Occasional bright fleck inside a clump - ore glint.
				if sparkle[index] > 0.82:
					color = color.lightened(0.18)
			image.set_pixel(x, y, color)


## Organic blotches: fBm blend between base and accent with a second field
## modulating brightness - replaces the old radial blob stamps.
func _fill_mottle(image: Image, recipe: TextureRecipe, _rng: RandomNumberGenerator) -> void:
	var size := image.get_width()
	var blend := _noise_field(recipe.noise_seed, 5.0, 4, size)
	var tone := _noise_field(recipe.noise_seed + 31, 11.0, 3, size)
	var spread := clampf(recipe.accent_density * 2.0, 0.3, 1.0)
	for y in size:
		for x in size:
			var index := y * size + x
			var weight := smoothstep(0.5 - spread * 0.4, 0.5 + spread * 0.4, blend[index])
			var color := recipe.base_color.lerp(recipe.accent_color, weight)
			var brightness := 0.92 + tone[index] * 0.16
			image.set_pixel(x, y, Color(
				clampf(color.r * brightness, 0.0, 1.0),
				clampf(color.g * brightness, 0.0, 1.0),
				clampf(color.b * brightness, 0.0, 1.0),
				color.a))


## Bricks/shingles/tiles: running-bond courses with per-brick tonal jitter
## and darker mortar seams - replaces the old flat alternating bands.
func _fill_stripes(image: Image, recipe: TextureRecipe) -> void:
	var size := image.get_width()
	var course := maxi(2, size / 8)
	var brick := course * 2
	var mortar := recipe.base_color.lerp(recipe.accent_color, 0.5).darkened(0.35)
	var surface := _noise_field(recipe.noise_seed + 47, 18.0, 2, size)
	for y in size:
		var row := y / course
		var offset := (row % 2) * (brick / 2)
		var seam_y := y % course == 0
		for x in size:
			var shifted := posmod(x + offset, size)
			var column := shifted / brick
			var seam_x := shifted % brick == 0
			var color: Color
			if seam_y or seam_x:
				color = mortar
			else:
				var jitter := _hash01(recipe.noise_seed, row, column)
				color = recipe.base_color.lerp(recipe.accent_color, 0.2 + jitter * 0.6)
				# Slight top-edge highlight / bottom-edge shadow per course so
				# bricks read as beveled even before the normal map.
				if y % course == 1:
					color = color.lightened(0.06)
				elif y % course == course - 1:
					color = color.darkened(0.08)
				color = color.darkened((1.0 - surface[y * size + x]) * 0.08)
			image.set_pixel(x, y, color)


## Wood: plank columns with per-plank tone, wavy noise-warped grain lines,
## dark seams between planks, and staggered end joints.
func _fill_grain(image: Image, recipe: TextureRecipe, _rng: RandomNumberGenerator) -> void:
	var size := image.get_width()
	var plank := maxi(4, size / 4)
	var warp := _noise_field(recipe.noise_seed, 6.0, 3, size)
	var streaks := _noise_field(recipe.noise_seed + 17, 3.0, 2, size)
	var seam := recipe.accent_color.darkened(0.45)
	var lines := maxf(2.0, 10.0 * clampf(recipe.accent_density, 0.1, 1.0))
	for y in size:
		for x in size:
			var index := y * size + x
			var column := x / plank
			var plank_tone := _hash01(recipe.noise_seed, column, 0)
			# End joint: each plank column breaks at a hashed height (and its
			# half-offset), Minecraft-plank style.
			var joint := int(_hash01(recipe.noise_seed, column, 1) * size)
			var at_joint := y == joint or y == posmod(joint + size / 2, size)
			var at_seam := x % plank == 0
			if at_seam or at_joint:
				image.set_pixel(x, y, seam)
				continue
			# Grain: vertical wave field warped by seamless noise; taking the
			# fractional band gives long wavy fibers along Y.
			var phase := float(x) * lines / float(plank) + warp[index] * 3.0 + plank_tone * 7.0
			var fiber := absf(sin(phase * PI))
			var color := recipe.base_color.lerp(recipe.accent_color, 0.25 + plank_tone * 0.3)
			color = color.lerp(recipe.accent_color, (1.0 - fiber) * 0.5)
			color = color.darkened((1.0 - streaks[index]) * 0.10)
			image.set_pixel(x, y, color)


## Cracked rock: mottled base plus meandering cracks with a soft dark halo
## and occasional branching - replaces the plain 2px vertical scribbles.
func _fill_cracks(image: Image, recipe: TextureRecipe, rng: RandomNumberGenerator) -> void:
	var size := image.get_width()
	var blend := _noise_field(recipe.noise_seed, 5.0, 3, size)
	for y in size:
		for x in size:
			image.set_pixel(x, y, recipe.base_color.lerp(recipe.accent_color, blend[y * size + x] * 0.35))
	var crack_color := recipe.accent_color.darkened(0.4)
	var crack_count := maxi(1, int(size * recipe.accent_density * 0.25))
	for i in crack_count:
		_walk_crack(image, rng.randi_range(0, size - 1), 0, size, crack_color, rng, true)


func _walk_crack(image: Image, x: int, start_y: int, end_y: int, color: Color, rng: RandomNumberGenerator, may_branch: bool) -> void:
	var size := image.get_width()
	var y := start_y
	while y < end_y:
		var px := posmod(x, size)
		image.set_pixel(px, y, color)
		# Soft halo: blend the neighbors halfway instead of hard 2px lines.
		for offset: int in [-1, 1]:
			var hx := posmod(px + offset, size)
			image.set_pixel(hx, y, image.get_pixel(hx, y).lerp(color, 0.45))
		if may_branch and rng.randf() < 0.03:
			_walk_crack(image, px + rng.randi_range(-2, 2), y, mini(size, y + size / 3), color, rng, false)
		x += rng.randi_range(-1, 1)
		y += 1


func _blur_heights(heights: PackedFloat32Array, size: int) -> PackedFloat32Array:
	var blurred := PackedFloat32Array()
	blurred.resize(size * size)
	for y in size:
		for x in size:
			var total := 0.0
			for dy: int in [-1, 0, 1]:
				for dx: int in [-1, 0, 1]:
					total += heights[_wrap_index(y + dy, size) * size + _wrap_index(x + dx, size)]
			blurred[y * size + x] = total / 9.0
	return blurred


func _wrap_index(v: int, size: int) -> int:
	return posmod(v, size)


## Deterministic per-feature jitter (per brick, per plank) in [0, 1].
func _hash01(noise_seed: int, a: int, b: int) -> float:
	return float(hash([noise_seed, a, b]) % 10000) / 9999.0
