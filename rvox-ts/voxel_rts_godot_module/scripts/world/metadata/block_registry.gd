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
    var files := DirAccess.get_files_at(block_folder)
    for file_name in files:
        if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
            continue
        var path := block_folder.path_join(file_name)
        var resource := load(path)
        if resource is BlockDefinition:
            blocks[resource.id] = resource

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
