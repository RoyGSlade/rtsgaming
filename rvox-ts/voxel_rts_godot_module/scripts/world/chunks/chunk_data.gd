class_name ChunkData
extends Resource

@export var chunk_position: Vector2i = Vector2i.ZERO
@export var chunk_size: int = 32
@export var max_height: int = 48

var blocks: Array = []
var surface_heightmap: PackedInt32Array = PackedInt32Array()
var biome_map: Array = []
var water_map: Array = []
var resource_map: Array = []
var dirty: bool = true

func setup(p_chunk_position: Vector2i, p_chunk_size: int, p_max_height: int) -> void:
    chunk_position = p_chunk_position
    chunk_size = p_chunk_size
    max_height = p_max_height
    var volume := chunk_size * max_height * chunk_size
    blocks.resize(volume)
    for i in volume:
        blocks[i] = &"air"
    var area := chunk_size * chunk_size
    surface_heightmap.resize(area)
    biome_map.resize(area)
    water_map.resize(area)
    resource_map.resize(area)
    for i in area:
        surface_heightmap[i] = 0
        biome_map[i] = &"unknown"
        water_map[i] = null
        resource_map[i] = &""
    dirty = true

func is_in_bounds(local_x: int, y: int, local_z: int) -> bool:
    return local_x >= 0 and local_x < chunk_size and y >= 0 and y < max_height and local_z >= 0 and local_z < chunk_size

func _block_index(local_x: int, y: int, local_z: int) -> int:
    return y * chunk_size * chunk_size + local_z * chunk_size + local_x

func _column_index(local_x: int, local_z: int) -> int:
    return local_z * chunk_size + local_x

func get_block(local_x: int, y: int, local_z: int) -> StringName:
    if not is_in_bounds(local_x, y, local_z):
        return &"air"
    return blocks[_block_index(local_x, y, local_z)]

func set_block(local_x: int, y: int, local_z: int, block_id: StringName) -> void:
    if not is_in_bounds(local_x, y, local_z):
        return
    blocks[_block_index(local_x, y, local_z)] = block_id
    dirty = true

func get_surface_height(local_x: int, local_z: int) -> int:
    if local_x < 0 or local_x >= chunk_size or local_z < 0 or local_z >= chunk_size:
        return 0
    return surface_heightmap[_column_index(local_x, local_z)]

func set_surface_height(local_x: int, local_z: int, height: int) -> void:
    if local_x < 0 or local_x >= chunk_size or local_z < 0 or local_z >= chunk_size:
        return
    surface_heightmap[_column_index(local_x, local_z)] = clampi(height, 0, max_height - 1)
    dirty = true

func set_biome(local_x: int, local_z: int, biome_id: StringName) -> void:
    if local_x < 0 or local_x >= chunk_size or local_z < 0 or local_z >= chunk_size:
        return
    biome_map[_column_index(local_x, local_z)] = biome_id

func get_biome(local_x: int, local_z: int) -> StringName:
    if local_x < 0 or local_x >= chunk_size or local_z < 0 or local_z >= chunk_size:
        return &"unknown"
    return biome_map[_column_index(local_x, local_z)]

func set_water_cell(local_x: int, local_z: int, cell: Variant) -> void:
    if local_x < 0 or local_x >= chunk_size or local_z < 0 or local_z >= chunk_size:
        return
    water_map[_column_index(local_x, local_z)] = cell

func get_water_cell(local_x: int, local_z: int) -> Variant:
    if local_x < 0 or local_x >= chunk_size or local_z < 0 or local_z >= chunk_size:
        return null
    return water_map[_column_index(local_x, local_z)]

func mark_dirty() -> void:
    dirty = true

func clear_dirty() -> void:
    dirty = false

func get_global_x(local_x: int) -> int:
    return chunk_position.x * chunk_size + local_x

func get_global_z(local_z: int) -> int:
    return chunk_position.y * chunk_size + local_z

func count_block(block_id: StringName) -> int:
    var count := 0
    for value in blocks:
        if value == block_id:
            count += 1
    return count
