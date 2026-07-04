class_name WaterDepthMap
extends RefCounted

## Per-cell normalized water depth (0..1), sampled by water.gdshader for
## depth-based color and edge foam — same Image/ImageTexture pattern as
## OverlayStateMap/FogOfWar, sampled by world_xz / world_extent. Water now
## flows live via WaterFlowSimulator, so populate() is called on the same
## throttled cadence as the water mesh rebuild rather than once at
## generation time.

# Simulated lakes/rivers/coastal water are typically 1-4 blocks deep (the
# old value of 12 was tuned for the flat-fill ocean's depths). Normalizing
# against too large a maximum squashed every real depth into the shader's
# shore-foam band (foam_band 0.12) and the most-transparent end of the
# depth-alpha ramp, rendering entire ponds as a pale, washed-out foam
# sheet instead of blue water.
const MAX_EXPECTED_DEPTH := 6.0

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

func populate(chunk: ChunkData, water_simulator: WaterFlowSimulator) -> void:
    _image.fill(Color(0, 0, 0, 0))
    for x in mini(width, chunk.chunk_size):
        for z in mini(depth, chunk.chunk_size):
            var spans := water_simulator.get_column_spans(chunk, x, z)
            if spans.is_empty():
                continue
            var span: WaterSpan = spans[0]
            var normalized := clampf(span.depth() / MAX_EXPECTED_DEPTH, 0.0, 1.0)
            _image.set_pixel(x, z, Color(normalized, 0, 0, 1))
    _texture.update(_image)

func get_texture() -> ImageTexture:
    return _texture
