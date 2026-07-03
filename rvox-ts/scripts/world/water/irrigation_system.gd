class_name IrrigationSystem
extends RefCounted

func get_irrigation_score(chunk: ChunkData, local_x: int, local_z: int, radius: int = 4) -> float:
    var score := 0.0
    for dx in range(-radius, radius + 1):
        for dz in range(-radius, radius + 1):
            var x := local_x + dx
            var z := local_z + dz
            var cell: WaterCell = chunk.get_water_cell(x, z)
            if cell == null:
                continue
            var dist := Vector2(dx, dz).length()
            score += maxf(0.0, 1.0 - dist / float(radius + 1)) * cell.freshness
    return clampf(score, 0.0, 1.0)
