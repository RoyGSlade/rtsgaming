class_name BlockQuery
extends RefCounted

static func is_empty(block_id: StringName) -> bool:
    return block_id == &"" or block_id == &"air"

static func is_water(block_id: StringName) -> bool:
    return block_id == &"water"

static func is_ore(block_id: StringName) -> bool:
    return String(block_id).ends_with("_ore")

static func is_tree(block_id: StringName) -> bool:
    return block_id == &"oak_log" or block_id == &"oak_leaves"
