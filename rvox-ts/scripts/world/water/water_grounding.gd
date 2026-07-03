class_name WaterGrounding
extends RefCounted

# Removes any water cell whose surface sits meaningfully above an adjacent
# dry column's ground height — i.e. water with no visible support on that
# side. The water mesh only draws top faces (see water_mesh_builder.gd),
# so an unsupported edge reads as literally floating water rather than a
# pond/river/lake seated in a depression. Iterates to a fixed point since
# clearing one cell can expose a previously-fine neighbor as unsupported
# in turn.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const HEIGHT_TOLERANCE := 1
const MAX_PASSES := 64

static func enforce_grounding(chunk: ChunkData, config: WorldGenConfig) -> void:
    var changed := true
    var safety := 0
    while changed and safety < MAX_PASSES:
        changed = false
        safety += 1
        for x in chunk.chunk_size:
            for z in chunk.chunk_size:
                var cell: WaterCell = chunk.get_water_cell(x, z)
                if cell == null:
                    continue
                if _is_overhanging(chunk, config, x, z, cell.surface_y):
                    _clear_water_cell(chunk, x, z, cell)
                    changed = true

static func _is_overhanging(chunk: ChunkData, config: WorldGenConfig, x: int, z: int, surface_y: int) -> bool:
    for dir in DIRECTIONS:
        var nx := x + dir.x
        var nz := z + dir.y
        if not chunk.is_in_bounds(nx, 0, nz):
            continue
        var neighbor: WaterCell = chunk.get_water_cell(nx, nz)
        if neighbor != null:
            continue
        var ground := chunk.get_surface_height(nx, nz)
        if ground <= config.water_level:
            continue # will be flooded by the ocean fill later, not a real gap
        if ground < surface_y - HEIGHT_TOLERANCE:
            return true
    return false

static func _clear_water_cell(chunk: ChunkData, x: int, z: int, cell: WaterCell) -> void:
    var ground := int(cell.surface_y - cell.depth)
    for y in range(ground + 1, cell.surface_y + 1):
        if chunk.get_block(x, y, z) == &"water":
            chunk.set_block(x, y, z, &"air")
    chunk.set_water_cell(x, z, null)
    chunk.set_surface_height(x, z, ground)
