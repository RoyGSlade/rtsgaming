@tool
class_name ShapeRegistry
extends Node

## Loads BlockShapeProfile .tres resources from a data folder, mirroring
## scripts/world/metadata/block_registry.gd's convention. Rendering still
## dispatches on the shape id string (ShapeGeometryFactory.create_shape); the
## profile is the data-driven catalog entry the palette reads id/display_name
## from today, with the remaining fields available for Phase 2's next step
## (custom-scene shapes, generated collision).

@export var shape_folder: String = "res://data/world_forge/shapes"

var shapes: Dictionary = {}


func _ready() -> void:
	load_shapes()


func load_shapes() -> void:
	shapes.clear()
	if not DirAccess.dir_exists_absolute(shape_folder):
		push_warning("Shape folder does not exist: %s" % shape_folder)
		return
	_load_folder_recursive(shape_folder)


func _load_folder_recursive(folder: String) -> void:
	var files := DirAccess.get_files_at(folder)
	for file_name: String in files:
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var path := folder.path_join(file_name)
		var resource := load(path)
		if resource is BlockShapeProfile:
			shapes[resource.id] = resource
	for directory_name: String in DirAccess.get_directories_at(folder):
		_load_folder_recursive(folder.path_join(directory_name))


func get_shape(id: StringName) -> BlockShapeProfile:
	if shapes.is_empty():
		load_shapes()
	return shapes.get(id, null)


func has_shape(id: StringName) -> bool:
	if shapes.is_empty():
		load_shapes()
	return shapes.has(id)


## Palette order: ascending sort_order, ties broken by id.
func list_ids() -> Array[StringName]:
	if shapes.is_empty():
		load_shapes()
	var keys: Array = shapes.keys()
	keys.sort_custom(func(a: StringName, b: StringName) -> bool:
		var order_a: int = shapes[a].sort_order
		var order_b: int = shapes[b].sort_order
		if order_a != order_b:
			return order_a < order_b
		return String(a) < String(b)
	)
	var ids: Array[StringName] = []
	for key: StringName in keys:
		ids.append(key)
	return ids
