class_name WaterDebugOverlay
extends Node3D

@export var arrow_length: float = 0.8

func print_water_summary(chunk: ChunkData) -> void:
    var water_count := 0
    var flow_count := 0
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            var cell: WaterCell = chunk.get_water_cell(x, z)
            if cell:
                water_count += 1
                if cell.flow_speed > 0.0:
                    flow_count += 1
    print("Water cells: %s, flowing cells: %s" % [water_count, flow_count])
