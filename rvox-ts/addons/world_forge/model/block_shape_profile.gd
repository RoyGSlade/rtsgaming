@tool
class_name BlockShapeProfile
extends Resource

enum GeometryKind { CUBE, SLAB, STAIR, FENCE, PANE, PLATE, FLUID_SURFACE, CUSTOM }
enum ConnectionKind { NONE, CARDINAL_SAME_TAG, CARDINAL_SOLID, NETWORK }

@export var id: StringName = &"cube"
@export var display_name := "Cube"
## Palette display order (ascending); ties break on id. Not simulation state.
@export var sort_order := 0
@export var geometry_kind := GeometryKind.CUBE
@export var connection_kind := ConnectionKind.NONE
@export var supports_rotation := false
@export var occupies_full_cell := true
@export var blocks_visibility := true
@export var blocks_movement := true
@export var support_fraction := 1.0
@export var collision_boxes: Array[AABB] = [AABB(Vector3.ZERO, Vector3.ONE)]
@export var custom_scene: PackedScene


func rotated_steps(steps: int) -> int:
	return posmod(steps, 4) if supports_rotation else 0
