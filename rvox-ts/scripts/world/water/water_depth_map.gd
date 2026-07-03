class_name WaterDepthMap
extends RefCounted

## Per-cell normalized water depth (0..1), sampled by water.gdshader for
## depth-based color and edge foam — same Image/ImageTexture pattern as
## OverlayStateMap/FogOfWar, sampled by world_xz / world_extent. Unlike
## those, water depth is static after generation (no runtime mutation), so
## it's populated once per generate_world() rather than exposing a
## set_value()-style live-update API.

const MAX_EXPECTED_DEPTH := 12.0

var width: int
var depth: int

var _image: Image
var _texture: ImageTexture

func _init(map_width: int, map_depth: int) -> void:
    width = maxi(1, map_width)
    depth = maxi(1, map_depth)
    _image = Image.create(width, depth, false, Image.FORMAT_R8)
    _image.fill(Color(0, 0, 0, 0))
    _texture = ImageTexture.create_from_image(_image)

func populate(chunk: ChunkData) -> void:
    for x in mini(width, chunk.chunk_size):
        for z in mini(depth, chunk.chunk_size):
            var cell: WaterCell = chunk.get_water_cell(x, z)
            if cell == null:
                continue
            var normalized := clampf(cell.depth / MAX_EXPECTED_DEPTH, 0.0, 1.0)
            _image.set_pixel(x, z, Color(normalized, 0, 0, 1))
    _texture.update(_image)

func get_texture() -> ImageTexture:
    return _texture
