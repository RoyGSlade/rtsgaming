class_name ResourceRegistry
extends Node

@export var resource_folder := "res://data/resources"

var resources: Dictionary = {}


func _ready() -> void:
	load_resources()


func load_resources() -> void:
	resources.clear()
	if not DirAccess.dir_exists_absolute(resource_folder):
		push_warning("Resource folder does not exist: %s" % resource_folder)
		return
	_load_folder_recursive(resource_folder)


func _load_folder_recursive(folder: String) -> void:
	for file_name in DirAccess.get_files_at(folder):
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var definition := load(folder.path_join(file_name)) as ResourceDefinition
		if definition != null:
			resources[definition.id] = definition
	for directory_name in DirAccess.get_directories_at(folder):
		_load_folder_recursive(folder.path_join(directory_name))


func get_resource(id: StringName) -> ResourceDefinition:
	if resources.is_empty():
		load_resources()
	return resources.get(id, null)


func has_resource(id: StringName) -> bool:
	if resources.is_empty():
		load_resources()
	return resources.has(id)


func list_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(resources.keys())
	ids.sort()
	return ids
