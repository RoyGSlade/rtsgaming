class_name RiverGenerator
extends RefCounted

# Carves single-block-wide river channels downhill from a high source to
# the sea, a lake, or the chunk edge, via steepest-descent walk. Each
# carved column keeps its original bank-level surface_heightmap (water
# fills the dug channel back up to that height) so the river reads as a
# channel between existing banks, not a pit.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

const CHANNEL_DEPTH := 2
# 4x the original 40 — a river now needs to be able to cross a 128-wide
# chunk (up from 32) plus meander slack, not just the old map's diagonal.
const MAX_STEPS := 170
const SOURCE_HEIGHT_PERCENTILE := 0.8
const NO_SOURCE := Vector2i(-1, -1)

func carve_rivers(chunk: ChunkData, config: WorldGenConfig, water_simulator: WaterFlowSimulator = null) -> void:
    if not config.generate_water or config.river_count <= 0:
        return
    var rng := RandomNumberGenerator.new()
    rng.seed = config.world_seed + 801

    var threshold := _height_threshold(chunk, SOURCE_HEIGHT_PERCENTILE)
    for i in config.river_count:
        var source := _pick_source(chunk, threshold, rng)
        if source == NO_SOURCE:
            continue
        _carve_path(chunk, source, config, water_simulator)

func _height_threshold(chunk: ChunkData, percentile: float) -> int:
    var heights: Array[int] = []
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            heights.append(chunk.get_surface_height(x, z))
    heights.sort()
    var index := clampi(int(heights.size() * percentile), 0, heights.size() - 1)
    return heights[index]

func _pick_source(chunk: ChunkData, threshold: int, rng: RandomNumberGenerator) -> Vector2i:
    var candidates: Array[Vector2i] = []
    for x in range(1, chunk.chunk_size - 1):
        for z in range(1, chunk.chunk_size - 1):
            if chunk.get_surface_height(x, z) >= threshold and chunk.get_water_cell(x, z) == null:
                candidates.append(Vector2i(x, z))
    if candidates.is_empty():
        return NO_SOURCE
    return candidates[rng.randi_range(0, candidates.size() - 1)]

func _carve_path(chunk: ChunkData, start: Vector2i, config: WorldGenConfig, water_simulator: WaterFlowSimulator) -> void:
    var pos := start
    var visited := {}
    var steps := 0

    while steps < MAX_STEPS:
        steps += 1
        if pos.x <= 0 or pos.x >= chunk.chunk_size - 1 or pos.y <= 0 or pos.y >= chunk.chunk_size - 1:
            break

        var height := chunk.get_surface_height(pos.x, pos.y)
        if not visited.has(pos):
            _carve_channel_cell(chunk, pos, height, config, water_simulator)
            visited[pos] = true

        if height <= config.water_level:
            break

        var next := _steepest_descent_neighbor(chunk, pos, visited)
        if next == pos:
            break
        pos = next

func _carve_channel_cell(chunk: ChunkData, pos: Vector2i, bank_height: int, config: WorldGenConfig, water_simulator: WaterFlowSimulator) -> void:
    var carved_floor := maxi(bank_height - CHANNEL_DEPTH, config.water_level)
    if carved_floor >= bank_height:
        return
    for y in range(carved_floor + 1, bank_height + 1):
        chunk.set_block(pos.x, y, pos.y, &"air")
    # Seed ON THE CHANNEL BED (one block of water resting on the carved
    # floor), never at bank height: the trench walls physically contain a
    # bed-level stream, whereas a bank-level source on a slope pours over
    # the channel sides and - multiplied by every step of every river -
    # coats whole hillsides in stacked water mounds.
    if water_simulator != null:
        water_simulator.seed_source(chunk, Vector3i(pos.x, carved_floor + 1, pos.y))

func _steepest_descent_neighbor(chunk: ChunkData, pos: Vector2i, visited: Dictionary) -> Vector2i:
    var best := pos
    var best_height := chunk.get_surface_height(pos.x, pos.y)
    for dir in DIRECTIONS:
        var npos := pos + dir
        if visited.has(npos):
            continue
        if not chunk.is_in_bounds(npos.x, 0, npos.y):
            continue
        var nh := chunk.get_surface_height(npos.x, npos.y)
        if nh < best_height:
            best_height = nh
            best = npos
    return best
