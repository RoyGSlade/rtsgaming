@tool
class_name BlockPlacementCursor
extends Node3D

@export var grid_size: float = 1.0
@export var current_block_id: StringName = &"grass"
@export var current_layer: StringName = &"floor"

var grid_position: Vector3i = Vector3i.ZERO

func set_from_world_position(world_position: Vector3) -> void:
    grid_position = Vector3i(
        roundi(world_position.x / grid_size),
        roundi(world_position.y / grid_size),
        roundi(world_position.z / grid_size)
    )
    global_position = Vector3(grid_position) * grid_size

func make_block_dictionary() -> Dictionary:
    return {
        "pos": [grid_position.x, grid_position.y, grid_position.z],
        "block_id": String(current_block_id),
        "layer": String(current_layer),
        "tags": [],
        "build_stage": String(current_layer),
        "requires_support": grid_position.y > 0
    }
