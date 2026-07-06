class_name LakeGenerator
extends RefCounted

# Basin/lake and pond placement after terrain generation. Uses a true
# priority-flood watershed over the already-computed surface heightmap:
# repeatedly pop the LOWEST-height cell on the pool's frontier and admit
# it, so every admitted cell is provably no higher than the rim at the
# moment it's added — this guarantees the basin is fully enclosed by
# construction (no water can end up higher than a neighboring wall cell),
# unlike a simple "expand within tolerance" flood, which readily accepts
# cells early (before the rim has grown) and can leave the final basin
# bordering unvisited ground lower than its eventual rim — exactly the
# "floating" water shape a cleanup pass used to exist to catch, but this
# fixes the root cause instead of relying on cleanup (water is now seeded
# and settles live via WaterFlowSimulator, which can't produce a floating
# surface at all since it only ever moves water down or sideways into open
# space): an earlier tolerance-based version of this flood got ~93% of its cells
# stripped as unsupported once the world was scaled up to 128x128, which
# is what surfaced the bug. Also rejects basins that touch the chunk edge
# (can't verify enclosure without neighbor-chunk data) or are too small
# to read as a pond, or that would rise implausibly far above their seed.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# Feature count/attempts scale with map area (these values are the tuned
# 128x128 baseline); MIN/MAX_BASIN_SIZE and MAX_RISE_FROM_SEED stay fixed
# since they describe an individual pond's shape, not the map size — and a
# bounded basin also keeps the priority-flood's linear frontier-min scan
# cheap no matter how large the map gets.
const FEATURES_PER_128 := 10
const SEED_ATTEMPTS_PER_128 := 150
const MIN_BASIN_SIZE := 6
const MAX_BASIN_SIZE := 400
const MAX_RISE_FROM_SEED := 6

func mark_lakes(chunk: ChunkData, config: WorldGenConfig, water_simulator: WaterFlowSimulator = null) -> void:
    if not config.generate_water:
        return
    var area_scale := float(chunk.chunk_size * chunk.chunk_size) / (128.0 * 128.0)
    var max_features := maxi(1, roundi(FEATURES_PER_128 * area_scale))
    var max_seed_attempts := maxi(20, roundi(SEED_ATTEMPTS_PER_128 * area_scale))
    var rng := RandomNumberGenerator.new()
    rng.seed = config.world_seed + 701

    var visited := {}
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            if chunk.get_surface_height(x, z) <= config.water_level:
                visited[Vector2i(x, z)] = true

    var placed := 0
    var attempts := 0
    while placed < max_features and attempts < max_seed_attempts:
        attempts += 1
        var seed_pos := Vector2i(
            rng.randi_range(2, chunk.chunk_size - 3),
            rng.randi_range(2, chunk.chunk_size - 3)
        )
        if visited.has(seed_pos):
            continue
        var seed_height := chunk.get_surface_height(seed_pos.x, seed_pos.y)
        if seed_height <= config.water_level:
            continue
        if not _is_local_minimum(chunk, seed_pos, seed_height):
            continue

        var basin := _flood_basin(chunk, seed_pos, visited)
        if basin.is_empty():
            continue
        placed += 1
        _fill_basin(chunk, basin.cells, basin.rim_height, water_simulator)
        for cell_pos: Vector2i in basin.cells:
            visited[cell_pos] = true

func _is_local_minimum(chunk: ChunkData, pos: Vector2i, height: int) -> bool:
    for dir in DIRECTIONS:
        var npos := pos + dir
        if not chunk.is_in_bounds(npos.x, 0, npos.y):
            return false
        if chunk.get_surface_height(npos.x, npos.y) < height:
            return false
    return true

func _flood_basin(chunk: ChunkData, seed_pos: Vector2i, visited: Dictionary) -> Dictionary:
    var seed_height := chunk.get_surface_height(seed_pos.x, seed_pos.y)
    var max_height := seed_height + MAX_RISE_FROM_SEED

    var pool := {}
    var boundary := {seed_pos: seed_height} # Vector2i -> height, frontier not yet admitted
    var rim := seed_height
    var touched_edge := false

    while boundary.size() > 0 and pool.size() < MAX_BASIN_SIZE:
        var next_pos: Vector2i = boundary.keys()[0]
        var next_height: int = boundary[next_pos]
        for pos: Vector2i in boundary:
            var h: int = boundary[pos]
            if h < next_height:
                next_height = h
                next_pos = pos
        boundary.erase(next_pos)

        if next_height > max_height:
            break # remaining boundary only gets higher from here — stop growing

        pool[next_pos] = true
        rim = maxi(rim, next_height)

        for dir in DIRECTIONS:
            var npos := next_pos + dir
            if npos.x <= 0 or npos.x >= chunk.chunk_size - 1 or npos.y <= 0 or npos.y >= chunk.chunk_size - 1:
                touched_edge = true
                continue
            if pool.has(npos) or visited.has(npos) or boundary.has(npos):
                continue
            boundary[npos] = chunk.get_surface_height(npos.x, npos.y)

    if touched_edge or pool.size() < MIN_BASIN_SIZE:
        return {}
    # True-enclosure check against the actual terrain: every column just
    # outside the pool must be at least rim-high, or water seeded at rim
    # height escapes through the low neighbor. The flood alone can't prove
    # this, for two reasons: the size cap can cut it off with a low frontier
    # still unexplored, and cells pre-marked `visited` (ocean-level ground,
    # earlier lakes) are skipped during expansion without ever checking
    # their height - a basin butting up against ocean-level lowland would
    # otherwise pass as "enclosed" and drain out through it, coating the
    # terrain beyond in escaped water.
    for pos: Vector2i in pool:
        for dir in DIRECTIONS:
            var npos: Vector2i = pos + dir
            if pool.has(npos):
                continue
            if chunk.get_surface_height(npos.x, npos.y) < rim:
                return {}
    return {"cells": pool.keys(), "rim_height": rim}

## Basin cells are a natural heightmap depression - everything from each
## cell's own ground up through rim_height is already open air by
## construction (terrain generation never fills above a column's own
## height), so no digging is needed here, only seeding. Every qualifying
## cell gets its own source at rim_height (the basin's target surface, not
## its floor) rather than a single seed relying on cascading fill: dense
## seeding fills the whole basin in a couple of ticks instead of needing
## O(basin diameter) ticks to cascade out from one point, and
## WaterFlowSimulator's distance-limited spread (MAX_FLOW_DISTANCE) means
## seeding right up to the rim is safe even for a basin the flood-fill
## couldn't fully prove enclosed - any leak through an unnoticed gap is
## bounded to a few cells, not the whole map.
func _fill_basin(chunk: ChunkData, cells: Array, rim_height: int, water_simulator: WaterFlowSimulator) -> void:
    if water_simulator == null:
        return
    for cell_pos: Vector2i in cells:
        var ground := chunk.get_surface_height(cell_pos.x, cell_pos.y)
        if ground >= rim_height:
            continue
        water_simulator.seed_source(chunk, Vector3i(cell_pos.x, rim_height, cell_pos.y))
