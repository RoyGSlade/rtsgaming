@tool
class_name BlueprintThumbnailRenderer
extends RefCounted

## Renders a small isometric preview icon for a set of placed blocks,
## entirely through Image pixel operations - no SubViewport, no camera, no
## waiting on a render frame. That makes it safe to call synchronously from
## editor code (and from tests) right after a save/export, instead of
## juggling an async viewport capture whose timing is hard to guarantee
## inside an EditorPlugin main screen.
##
## Used by World Forge's blueprint browser to give each library entry a
## recognizable thumbnail instead of a bare filename.

const CANVAS_SIZE := Vector2i(160, 160)
const PADDING := 14.0
## Classic 2:1 "dimetric" tile projection: X-Z gives horizontal spread,
## X+Z gives vertical spread, Y lifts straight up the screen.
const TILE_X := 1.0
const TILE_Y := 0.5
const TILE_Y_LIFT := 1.0


## Renders every block (each a Dictionary with "pos": [x,y,z] and
## "block_id") into a transparent-background isometric icon, sized and
## centered to fit whatever bounding box the blocks span. block_colors maps
## block_id (String or StringName) -> Color, e.g. World Forge's _block_colors.
static func render(blocks: Array, block_colors: Dictionary, canvas_size: Vector2i = CANVAS_SIZE) -> Image:
	var image := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	var solid_blocks: Array[Dictionary] = []
	for block: Variant in blocks:
		if block is Dictionary and str((block as Dictionary).get("block_id", "")) not in ["", "air"]:
			solid_blocks.append(block)
	if solid_blocks.is_empty():
		return image

	var projected: Array[Dictionary] = []
	var min_iso := Vector2(INF, INF)
	var max_iso := Vector2(-INF, -INF)
	for block: Dictionary in solid_blocks:
		var pos: Array = block.get("pos", [0, 0, 0])
		var cell := Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		var color: Color = block_colors.get(StringName(str(block.get("block_id", ""))), Color(0.55, 0.57, 0.6))
		var iso := _iso_project(cell + Vector3(0.5, 0.5, 0.5))
		min_iso = Vector2(minf(min_iso.x, iso.x), minf(min_iso.y, iso.y))
		max_iso = Vector2(maxf(max_iso.x, iso.x), maxf(max_iso.y, iso.y))
		projected.append({"cell": cell, "color": color, "depth": cell.x + cell.y + cell.z})

	var span := Vector2(maxf(max_iso.x - min_iso.x, 0.001), maxf(max_iso.y - min_iso.y, 0.001))
	var available := Vector2(canvas_size) - Vector2.ONE * PADDING * 2.0
	var scale := clampf(minf(available.x / (span.x + 1.6), available.y / (span.y + 1.6)), 4.0, 26.0)
	var center_iso := (min_iso + max_iso) * 0.5
	var center_screen := Vector2(canvas_size) * 0.5

	# Painter's algorithm: draw far-to-near so nearer cubes correctly
	# overwrite the far faces they occlude.
	projected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] < b["depth"])

	for entry: Dictionary in projected:
		var origin: Vector3 = entry["cell"]
		_draw_cube(image, origin, entry["color"], scale, center_iso, center_screen)
	return image


## Renders and writes the PNG to out_path, creating parent directories as
## needed. Returns false (without raising) if the image can't be saved.
static func render_and_save(blocks: Array, block_colors: Dictionary, out_path: String) -> bool:
	var image := render(blocks, block_colors)
	var dir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return false
	return image.save_png(out_path) == OK


static func _iso_project(point: Vector3) -> Vector2:
	return Vector2(
		(point.x - point.z) * TILE_X,
		(point.x + point.z) * TILE_Y - point.y * TILE_Y_LIFT,
	)


static func _to_screen(point: Vector3, scale: float, center_iso: Vector2, center_screen: Vector2) -> Vector2:
	return (_iso_project(point) - center_iso) * scale + center_screen


## Draws one unit cube's three visible faces (top, +X, +Z) as shaded
## quads - a fixed pseudo-3D approximation good enough for a small preview
## icon. Stairs/slabs/fixtures are simplified to plain cubes here; getting
## their exact silhouette right isn't worth the complexity at thumbnail size.
static func _draw_cube(image: Image, origin: Vector3, color: Color, scale: float,
		center_iso: Vector2, center_screen: Vector2) -> void:
	var corners := {}
	for dx in range(2):
		for dy in range(2):
			for dz in range(2):
				var key := Vector3i(dx, dy, dz)
				corners[key] = _to_screen(origin + Vector3(dx, dy, dz), scale, center_iso, center_screen)

	_fill_quad(image, [corners[Vector3i(0, 1, 0)], corners[Vector3i(1, 1, 0)], corners[Vector3i(1, 1, 1)], corners[Vector3i(0, 1, 1)]], color)
	_fill_quad(image, [corners[Vector3i(1, 0, 0)], corners[Vector3i(1, 1, 0)], corners[Vector3i(1, 1, 1)], corners[Vector3i(1, 0, 1)]], color.darkened(0.25))
	_fill_quad(image, [corners[Vector3i(0, 0, 1)], corners[Vector3i(1, 0, 1)], corners[Vector3i(1, 1, 1)], corners[Vector3i(0, 1, 1)]], color.darkened(0.45))


## Fills a convex quad via horizontal scanline rasterization: for each row,
## find where the polygon's edges cross that scanline and fill between the
## outermost crossings. Correct for any convex polygon, not just axis-aligned
## ones, which is all three visible cube faces are under this projection.
static func _fill_quad(image: Image, points: Array, color: Color) -> void:
	var min_y := image.get_height()
	var max_y := 0
	for p: Vector2 in points:
		min_y = mini(min_y, floori(p.y))
		max_y = maxi(max_y, ceili(p.y))
	min_y = maxi(min_y, 0)
	max_y = mini(max_y, image.get_height() - 1)
	var count := points.size()
	for y in range(min_y, max_y + 1):
		var scan_y := float(y) + 0.5
		var xs: Array[float] = []
		for i in count:
			var a: Vector2 = points[i]
			var b: Vector2 = points[(i + 1) % count]
			if (a.y <= scan_y and b.y > scan_y) or (b.y <= scan_y and a.y > scan_y):
				xs.append(a.x + (b.x - a.x) * (scan_y - a.y) / (b.y - a.y))
		if xs.size() < 2:
			continue
		xs.sort()
		var x0 := maxi(floori(xs[0]), 0)
		var x1 := mini(ceili(xs[xs.size() - 1]), image.get_width() - 1)
		for x in range(x0, x1 + 1):
			image.set_pixel(x, y, color)
