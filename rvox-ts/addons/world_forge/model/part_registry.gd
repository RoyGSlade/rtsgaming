@tool
class_name PartRegistry
extends Node

## Loads PartProfile .tres resources from a data folder, mirroring
## scripts/world/metadata/block_registry.gd's convention. Kept separate from
## MaterialRegistry so the Workshop palette (parts) and material table
## (physics/thermal properties) can be authored and reloaded independently.

@export var part_folder: String = "res://data/world_forge/parts"

var parts: Dictionary = {}


func _ready() -> void:
	load_parts()


func load_parts() -> void:
	parts.clear()
	if not DirAccess.dir_exists_absolute(part_folder):
		push_warning("Part folder does not exist: %s" % part_folder)
		return
	_load_folder_recursive(part_folder)


func _load_folder_recursive(folder: String) -> void:
	var files := DirAccess.get_files_at(folder)
	for file_name: String in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := folder.path_join(file_name)
		var resource := load(path)
		if resource is PartProfile:
			parts[resource.id] = resource
	for directory_name: String in DirAccess.get_directories_at(folder):
		_load_folder_recursive(folder.path_join(directory_name))


func get_part(id: StringName) -> PartProfile:
	if parts.is_empty():
		load_parts()
	return parts.get(id, null)


func has_part(id: StringName) -> bool:
	if parts.is_empty():
		load_parts()
	return parts.has(id)


func list_ids() -> Array[StringName]:
	if parts.is_empty():
		load_parts()
	var ids: Array[StringName] = []
	for key: StringName in parts.keys():
		ids.append(key)
	ids.sort()
	return ids


func list_by_category(category: int) -> Array[StringName]:
	if parts.is_empty():
		load_parts()
	var ids: Array[StringName] = []
	for key: StringName in parts.keys():
		var part: PartProfile = parts[key]
		if part.category == category:
			ids.append(key)
	ids.sort()
	return ids
