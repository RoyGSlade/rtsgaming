class_name BlockEditorDraftBlueprint
extends Resource

const FORMAT_VERSION := 1

var blueprint_id: StringName = &"draft_building"
var display_name := "Draft Building"
var _blocks: Dictionary[Vector3i, BlockInstanceData] = {}


func has_block(position: Vector3i) -> bool:
	return _blocks.has(position)


func place_block(block: BlockInstanceData) -> bool:
	if _blocks.has(block.grid_position):
		return false
	_blocks[block.grid_position] = block
	emit_changed()
	return true


func remove_block(position: Vector3i) -> bool:
	if not _blocks.erase(position):
		return false
	emit_changed()
	return true


func clear() -> void:
	if _blocks.is_empty():
		return
	_blocks.clear()
	emit_changed()


func get_blocks() -> Array[BlockInstanceData]:
	var result: Array[BlockInstanceData] = []
	result.assign(_blocks.values())
	result.sort_custom(func(a: BlockInstanceData, b: BlockInstanceData) -> bool:
		if a.grid_position.y != b.grid_position.y:
			return a.grid_position.y < b.grid_position.y
		if a.grid_position.z != b.grid_position.z:
			return a.grid_position.z < b.grid_position.z
		return a.grid_position.x < b.grid_position.x
	)
	return result


func block_count() -> int:
	return _blocks.size()


func to_dictionary() -> Dictionary:
	var serialized_blocks: Array[Dictionary] = []
	for block in get_blocks():
		serialized_blocks.append(block.to_dictionary())
	return {
		"format_version": FORMAT_VERSION,
		"blueprint_id": String(blueprint_id),
		"display_name": display_name,
		"blocks": serialized_blocks,
	}


func save_json(path: String) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	return OK


static func load_json(path: String) -> BlockEditorDraftBlueprint:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return null
	var data: Dictionary = parsed
	if int(data.get("format_version", 0)) != FORMAT_VERSION:
		return null
	var blueprint := BlockEditorDraftBlueprint.new()
	blueprint.blueprint_id = StringName(data.get("blueprint_id", "draft_building"))
	blueprint.display_name = str(data.get("display_name", "Draft Building"))
	var serialized_blocks: Array = data.get("blocks", [])
	for block_data: Variant in serialized_blocks:
		if block_data is Dictionary:
			var block := BlockInstanceData.from_dictionary(block_data)
			blueprint._blocks[block.grid_position] = block
	return blueprint
