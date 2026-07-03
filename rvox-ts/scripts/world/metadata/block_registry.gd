class_name BlockRegistry
extends Node

@export var block_folder: String = "res://data/blocks"

var blocks: Dictionary = {}

func _ready() -> void:
    load_blocks()

func load_blocks() -> void:
    blocks.clear()
    if not DirAccess.dir_exists_absolute(block_folder):
        push_warning("Block folder does not exist: %s" % block_folder)
        return
    _load_folder_recursive(block_folder)

func _load_folder_recursive(folder: String) -> void:
    var files := DirAccess.get_files_at(folder)
    for file_name in files:
        if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
            continue
        var path := folder.path_join(file_name)
        var resource := load(path)
        if resource is BlockDefinition:
            blocks[resource.id] = resource
    for directory_name in DirAccess.get_directories_at(folder):
        _load_folder_recursive(folder.path_join(directory_name))

func get_block(id: StringName) -> BlockDefinition:
    if blocks.is_empty():
        load_blocks()
    return blocks.get(id, null)

func has_block(id: StringName) -> bool:
    if blocks.is_empty():
        load_blocks()
    return blocks.has(id)

func get_or_air(id: StringName) -> BlockDefinition:
    var block := get_block(id)
    if block:
        return block
    return get_block(&"air")

func list_ids() -> Array[StringName]:
    var ids: Array[StringName] = []
    for key in blocks.keys():
        ids.append(key)
    ids.sort()
    return ids
