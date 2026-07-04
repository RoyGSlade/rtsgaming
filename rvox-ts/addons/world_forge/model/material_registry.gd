@tool
class_name MaterialRegistry
extends Node

## Loads MaterialProperties .tres resources from a data folder, mirroring
## scripts/world/metadata/block_registry.gd's convention so both editors and
## the future thermal/kinetics simulators share one lookup pattern.

@export var material_folder: String = "res://data/world_forge/materials"

var materials: Dictionary = {}


func _ready() -> void:
	load_materials()


func load_materials() -> void:
	materials.clear()
	if not DirAccess.dir_exists_absolute(material_folder):
		push_warning("Material folder does not exist: %s" % material_folder)
		return
	_load_folder_recursive(material_folder)


func _load_folder_recursive(folder: String) -> void:
	var files := DirAccess.get_files_at(folder)
	for file_name: String in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := folder.path_join(file_name)
		var resource := load(path)
		if resource is MaterialProperties:
			materials[resource.id] = resource
	for directory_name: String in DirAccess.get_directories_at(folder):
		_load_folder_recursive(folder.path_join(directory_name))


func get_material(id: StringName) -> MaterialProperties:
	if materials.is_empty():
		load_materials()
	return materials.get(id, null)


func has_material(id: StringName) -> bool:
	if materials.is_empty():
		load_materials()
	return materials.has(id)


func list_ids() -> Array[StringName]:
	if materials.is_empty():
		load_materials()
	var ids: Array[StringName] = []
	for key: StringName in materials.keys():
		ids.append(key)
	ids.sort()
	return ids
