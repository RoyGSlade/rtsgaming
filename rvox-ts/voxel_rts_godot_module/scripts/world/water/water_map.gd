class_name WaterMap
extends Resource

@export var chunk_size: int = 32
var cells: Array = []

func setup(p_chunk_size: int) -> void:
    chunk_size = p_chunk_size
    cells.resize(chunk_size * chunk_size)
    for i in cells.size():
        cells[i] = null

func _idx(x: int, z: int) -> int:
    return z * chunk_size + x

func is_in_bounds(x: int, z: int) -> bool:
    return x >= 0 and x < chunk_size and z >= 0 and z < chunk_size

func set_cell(x: int, z: int, cell: WaterCell) -> void:
    if is_in_bounds(x, z):
        cells[_idx(x, z)] = cell

func get_cell(x: int, z: int) -> WaterCell:
    if not is_in_bounds(x, z):
        return null
    return cells[_idx(x, z)]
