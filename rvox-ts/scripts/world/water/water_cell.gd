class_name WaterCell
extends Resource

@export var depth: float = 0.0
@export var surface_y: int = 0
@export var flow_direction: Vector2 = Vector2.ZERO
@export var flow_speed: float = 0.0
@export var source_id: StringName = &""
@export var pollution_level: float = 0.0
@export var fish_density: float = 0.0
@export var freshness: float = 1.0

func is_wet() -> bool:
    return depth > 0.001
