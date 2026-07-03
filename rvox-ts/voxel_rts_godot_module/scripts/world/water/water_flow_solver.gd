class_name WaterFlowSolver
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

func build_surface_water_cells(chunk: ChunkData, config: WorldGenConfig) -> void:
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            var surface := chunk.get_surface_height(x, z)
            if surface < config.water_level:
                var cell := WaterCell.new()
                cell.surface_y = config.water_level
                cell.depth = float(config.water_level - surface)
                cell.fish_density = clampf(cell.depth / 8.0, 0.0, 1.0)
                chunk.set_water_cell(x, z, cell)
    solve_flow_directions(chunk)

func solve_flow_directions(chunk: ChunkData) -> void:
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            var cell: WaterCell = chunk.get_water_cell(x, z)
            if cell == null:
                continue
            var current_height := chunk.get_surface_height(x, z)
            var best_dir := Vector2.ZERO
            var best_drop := 0
            for dir in DIRECTIONS:
                var nx: int = x + dir.x
                var nz: int = z + dir.y
                if nx < 0 or nx >= chunk.chunk_size or nz < 0 or nz >= chunk.chunk_size:
                    continue
                var other_height := chunk.get_surface_height(nx, nz)
                var drop := current_height - other_height
                if drop > best_drop:
                    best_drop = drop
                    best_dir = Vector2(dir.x, dir.y).normalized()
            cell.flow_direction = best_dir
            cell.flow_speed = float(best_drop)
