@tool
class_name ComponentRegistry
extends Node

## Loads FunctionalComponentDefinition .tres resources from a data folder,
## mirroring scripts/world/metadata/block_registry.gd's convention.

@export var component_folder: String = "res://data/world_forge/components"

var components: Dictionary = {}


func _ready() -> void:
	load_components()


func load_components() -> void:
	components.clear()
	if not DirAccess.dir_exists_absolute(component_folder):
		push_warning("Component folder does not exist: %s" % component_folder)
		return
	_load_folder_recursive(component_folder)


func _load_folder_recursive(folder: String) -> void:
	var files := DirAccess.get_files_at(folder)
	for file_name: String in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := folder.path_join(file_name)
		var resource := load(path)
		if resource is FunctionalComponentDefinition:
			components[resource.id] = resource
	for directory_name: String in DirAccess.get_directories_at(folder):
		_load_folder_recursive(folder.path_join(directory_name))


func get_component(id: StringName) -> FunctionalComponentDefinition:
	if components.is_empty():
		load_components()
	return components.get(id, null)


func has_component(id: StringName) -> bool:
	if components.is_empty():
		load_components()
	return components.has(id)


## Palette order: ascending sort_order, ties broken by id.
func list_ids() -> Array[StringName]:
	if components.is_empty():
		load_components()
	var keys: Array = components.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool:
		var order_a: int = components[a].sort_order
		var order_b: int = components[b].sort_order
		if order_a != order_b:
			return order_a < order_b
		return String(a) < String(b)
	)
	var ids: Array[StringName] = []
	for key: StringName in keys:
		ids.append(key)
	return ids
