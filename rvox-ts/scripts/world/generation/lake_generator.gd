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
# bordering unvisited ground lower than its eventual rim — the exact
# shape of "floating" water WaterGrounding (water_grounding.gd) exists to
# catch, but this fixes the root cause instead of relying on cleanup:
# an earlier tolerance-based version of this flood got ~93% of its cells
# stripped as unsupported once the world was scaled up to 128x128, which
# is what surfaced the bug. Also rejects basins that touch the chunk edge
# (can't verify enclosure without neighbor-chunk data) or are too small
# to read as a pond, or that would rise implausibly far above their seed.

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# Tuned for a 128x128 chunk (4x the original 32x32 linear size — 16x the
# area). MAX_FEATURES/MAX_SEED_ATTEMPTS/MAX_BASIN_SIZE scale with the
# extra area; MIN_BASIN_SIZE/MAX_RISE_FROM_SEED stay small since those
# describe an individual pond's shape, not the map size.
const MAX_FEATURES := 10
const MAX_SEED_ATTEMPTS := 150
const MIN_BASIN_SIZE := 6
const MAX_BASIN_SIZE := 400
const MAX_RISE_FROM_SEED := 6

func mark_lakes(chunk: ChunkData, config: WorldGenConfig) -> void:
    if not config.generate_water:
        return
    var rng := RandomNumberGenerator.new()
    rng.seed = config.world_seed + 701

    var visited := {}
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            if chunk.get_surface_height(x, z) <= config.water_level:
                visited[Vector2i(x, z)] = true

    var placed := 0
    var attempts := 0
    while placed < MAX_FEATURES and attempts < MAX_SEED_ATTEMPTS:
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
        _fill_basin(chunk, basin.cells, basin.rim_height)
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
    return {"cells": pool.keys(), "rim_height": rim}

func _fill_basin(chunk: ChunkData, cells: Array, rim_height: int) -> void:
    for cell_pos: Vector2i in cells:
        var ground := chunk.get_surface_height(cell_pos.x, cell_pos.y)
        if ground >= rim_height:
            continue
        for y in range(ground + 1, rim_height + 1):
            chunk.set_block(cell_pos.x, y, cell_pos.y, &"water")
        var cell := WaterCell.new()
        cell.surface_y = rim_height
        cell.depth = float(rim_height - ground)
        cell.fish_density = clampf(cell.depth / 8.0, 0.0, 1.0)
        chunk.set_water_cell(cell_pos.x, cell_pos.y, cell)
        chunk.set_surface_height(cell_pos.x, cell_pos.y, rim_height)
