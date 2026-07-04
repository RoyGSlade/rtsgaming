@tool
class_name MarkerRegistry
extends Node

## Loads MarkerDefinition .tres resources from a data folder, mirroring
## scripts/world/metadata/block_registry.gd's convention.

@export var marker_folder: String = "res://data/world_forge/markers"

var markers: Dictionary = {}


func _ready() -> void:
	load_markers()


func load_markers() -> void:
	markers.clear()
	if not DirAccess.dir_exists_absolute(marker_folder):
		push_warning("Marker folder does not exist: %s" % marker_folder)
		return
	_load_folder_recursive(marker_folder)


func _load_folder_recursive(folder: String) -> void:
	var files := DirAccess.get_files_at(folder)
	for file_name: String in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := folder.path_join(file_name)
		var resource := load(path)
		if resource is MarkerDefinition:
			markers[resource.id] = resource
	for directory_name: String in DirAccess.get_directories_at(folder):
		_load_folder_recursive(folder.path_join(directory_name))


func get_marker(id: StringName) -> MarkerDefinition:
	if markers.is_empty():
		load_markers()
	return markers.get(id, null)


func has_marker(id: StringName) -> bool:
	if markers.is_empty():
		load_markers()
	return markers.has(id)


## Palette order: ascending sort_order, ties broken by id.
func list_ids() -> Array[StringName]:
	if markers.is_empty():
		load_markers()
	var keys: Array = markers.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool:
		var order_a: int = markers[a].sort_order
		var order_b: int = markers[b].sort_order
		if order_a != order_b:
			return order_a < order_b
		return String(a) < String(b)
	)
	var ids: Array[StringName] = []
	for key: StringName in keys:
		ids.append(key)
	return ids
