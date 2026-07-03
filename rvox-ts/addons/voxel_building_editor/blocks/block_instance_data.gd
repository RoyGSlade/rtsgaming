class_name BlockInstanceData
extends RefCounted

var grid_position: Vector3i
var block_id: StringName
var rotation_steps: int


func _init(
	position: Vector3i = Vector3i.ZERO,
	id: StringName = &"stone_block",
	rotation: int = 0
) -> void:
	grid_position = position
	block_id = id
	rotation_steps = posmod(rotation, 4)


func to_dictionary() -> Dictionary:
	return {
		"position": [grid_position.x, grid_position.y, grid_position.z],
		"block_id": String(block_id),
		"rotation_steps": rotation_steps,
	}


static func from_dictionary(data: Dictionary) -> BlockInstanceData:
	var position_data: Array = data.get("position", [0, 0, 0])
	if position_data.size() != 3:
		position_data = [0, 0, 0]
	return BlockInstanceData.new(
		Vector3i(int(position_data[0]), int(position_data[1]), int(position_data[2])),
		StringName(data.get("block_id", "stone_block")),
		int(data.get("rotation_steps", 0))
	)
