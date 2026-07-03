class_name FogOfWar
extends RefCounted

## Binary explored-mask over a chunk_size x chunk_size cell grid, revealed
## around the camera's ground-plane focus point (no unit/vision gameplay
## exists yet, so "reveal as the camera pans" is the v1 trigger). Feeds
## both the terrain shader (darkens unexplored 3D terrain) and the minimap
## (blacks out unexplored cells).

var width: int
var depth: int

var _image: Image
var _texture: ImageTexture
var _dirty := false

func _init(map_width: int, map_depth: int) -> void:
    width = maxi(1, map_width)
    depth = maxi(1, map_depth)
    _image = Image.create(width, depth, false, Image.FORMAT_R8)
    _image.fill(Color(0, 0, 0, 0))
    _texture = ImageTexture.create_from_image(_image)

## Returns true if any previously-unexplored cell was revealed, so callers
## can skip expensive recomposition (e.g. minimap redraw) when nothing changed.
func reveal(world_x: float, world_z: float, radius: float) -> bool:
    var r := maxf(0.0, radius)
    var min_x := clampi(int(floor(world_x - r)), 0, width - 1)
    var max_x := clampi(int(ceil(world_x + r)), 0, width - 1)
    var min_z := clampi(int(floor(world_z - r)), 0, depth - 1)
    var max_z := clampi(int(ceil(world_z + r)), 0, depth - 1)
    var r_sq := r * r
    var changed := false
    for x in range(min_x, max_x + 1):
        for z in range(min_z, max_z + 1):
            if _image.get_pixel(x, z).r > 0.5:
                continue
            var dx := float(x) - world_x
            var dz := float(z) - world_z
            if dx * dx + dz * dz <= r_sq:
                _image.set_pixel(x, z, Color(1, 0, 0, 1))
                _dirty = true
                changed = true
    return changed

func is_explored(x: int, z: int) -> bool:
    if x < 0 or x >= width or z < 0 or z >= depth:
        return false
    return _image.get_pixel(x, z).r > 0.5

func reset() -> void:
    _image.fill(Color(0, 0, 0, 0))
    _dirty = true

func get_texture() -> ImageTexture:
    if _dirty:
        _texture.update(_image)
        _dirty = false
    return _texture

func get_image() -> Image:
    return _image
