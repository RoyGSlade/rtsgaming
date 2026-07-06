class_name ChunkData
extends Resource

## Voxel storage for one map. The underground is NOT materialized: only the
## per-column surface heightmap/biome plus a sparse `edits` dictionary are
## stored, and everything below the surface is computed on demand from the
## same deterministic noise the generator would have used (see
## _baseline_block). This is what lets map size scale by area instead of
## volume — a fresh 256x256 world stores ~65k ints + a few thousand edits
## (trees, carved rivers, water) instead of ~3.1M block Variants.
##
## `edits` holds every deviation from that procedural baseline: water cells,
## tree logs/leaves, carved river channels, and — later — anything mined out
## or built. set_block() automatically stores/erases edits by comparing
## against the baseline, so callers keep using the same get/set API as when
## the volume was dense.

## Fired when a change is visible to the terrain mesh (i.e. not an
## air<->water swap, which the terrain mesher ignores). WorldRuntime uses
## this to remesh just the affected region.
signal terrain_block_changed(local_x: int, y: int, local_z: int)

@export var chunk_position: Vector2i = Vector2i.ZERO
@export var chunk_size: int = 32
@export var max_height: int = 48

var surface_heightmap: PackedInt32Array = PackedInt32Array()
var biome_map: Array = []
var water_map: Array = []
var resource_map: Array = []
var dirty: bool = true

## Vector3i(local_x, y, local_z) -> StringName block id.
var edits: Dictionary = {}
## Per-column min/max edited y, conservative scan hints for the mesher.
## min sentinel = max_height, max sentinel = -1 (i.e. "no edits").
var edit_min_y: PackedInt32Array = PackedInt32Array()
var edit_max_y: PackedInt32Array = PackedInt32Array()

# Procedural baseline providers, installed by WorldGenerator. Without them
# (bare ChunkData in tests/tools) the baseline is all-air, matching the old
# freshly-setup dense volume.
var _surface_resolver: SurfaceBlockResolver
var _ore_generator: ResourceVeinGenerator
var _config: WorldGenConfig

func setup(p_chunk_position: Vector2i, p_chunk_size: int, p_max_height: int) -> void:
    chunk_position = p_chunk_position
    chunk_size = p_chunk_size
    max_height = p_max_height
    edits.clear()
    var area := chunk_size * chunk_size
    surface_heightmap.resize(area)
    surface_heightmap.fill(0)
    edit_min_y.resize(area)
    edit_min_y.fill(max_height)
    edit_max_y.resize(area)
    edit_max_y.fill(-1)
    biome_map.resize(area)
    water_map.resize(area)
    resource_map.resize(area)
    for i in area:
        biome_map[i] = &"unknown"
        water_map[i] = null
        resource_map[i] = &""
    dirty = true

func set_procedural_source(surface_resolver: SurfaceBlockResolver, ore_generator: ResourceVeinGenerator, config: WorldGenConfig) -> void:
    _surface_resolver = surface_resolver
    _ore_generator = ore_generator
    _config = config

func is_in_bounds(local_x: int, y: int, local_z: int) -> bool:
    return local_x >= 0 and local_x < chunk_size and y >= 0 and y < max_height and local_z >= 0 and local_z < chunk_size

func _column_index(local_x: int, local_z: int) -> int:
    return local_z * chunk_size + local_x

## What the generator would have put at this cell — surface/dirt/stone bands
## with deterministic ore veins. Never allocates; safe to call for any cell.
func _baseline_block(local_x: int, y: int, local_z: int) -> StringName:
    var surface_height := surface_heightmap[_column_index(local_x, local_z)]
    if y > surface_height:
        return &"air"
    if _surface_resolver == null or _config == null:
        return &"air"
    if _ore_generator != null:
        var ore := _ore_generator.resolve_ore(get_global_x(local_x), y, get_global_z(local_z), surface_height, _config)
        if ore != &"":
            return ore
    return _surface_resolver.resolve_subsurface_block(y, surface_height, _config)

func get_block(local_x: int, y: int, local_z: int) -> StringName:
    if not is_in_bounds(local_x, y, local_z):
        return &"air"
    var key := Vector3i(local_x, y, local_z)
    var edited: Variant = edits.get(key)
    if edited != null:
        return edited
    return _baseline_block(local_x, y, local_z)

static func _invisible_to_terrain(block_id: StringName) -> bool:
    return block_id == &"air" or block_id == &"water"

func set_block(local_x: int, y: int, local_z: int, block_id: StringName) -> void:
    if not is_in_bounds(local_x, y, local_z):
        return
    var key := Vector3i(local_x, y, local_z)
    var baseline := _baseline_block(local_x, y, local_z)
    var old: StringName = edits.get(key, baseline)
    if old == block_id:
        return
    if block_id == baseline:
        edits.erase(key)
    else:
        edits[key] = block_id
        var ci := _column_index(local_x, local_z)
        edit_min_y[ci] = mini(edit_min_y[ci], y)
        edit_max_y[ci] = maxi(edit_max_y[ci], y)
    dirty = true
    if not (_invisible_to_terrain(old) and _invisible_to_terrain(block_id)):
        terrain_block_changed.emit(local_x, y, local_z)

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

## Counts EDITED blocks with this id (trees, placed structures, water...).
## The procedural underground is unbounded-cheap precisely because it isn't
## enumerated, so baseline stone/ore can't be counted here.
func count_block(block_id: StringName) -> int:
    var count := 0
    for value: StringName in edits.values():
        if value == block_id:
            count += 1
    return count
