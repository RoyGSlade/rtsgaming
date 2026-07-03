class_name BuildingBlueprint
extends Resource

@export var id: StringName = &"unknown_building"
@export var display_name: String = "Unknown Building"
@export var category: StringName = &"production"
@export var era: StringName = &"village"
@export var footprint: Vector2i = Vector2i(1, 1)
@export var health: int = 100
@export var workers_required: int = 1
@export var required_functional_tags: PackedStringArray = PackedStringArray()

# Each block dictionary should include:
# pos: [x,y,z], block_id, layer, tags, build_stage, requires_support
@export var blocks: Array[Dictionary] = []

# Each socket dictionary should include:
# id, socket_type, pos: [x,y,z], facing: [x,y,z], role
@export var sockets: Array[Dictionary] = []

# Each storage dictionary should include:
# id, item_id, capacity, pos: [x,y,z], visible
@export var storage_slots: Array[Dictionary] = []

# Each recipe dictionary should include:
# id, display_name, inputs, outputs, duration_seconds, required_station, worker_socket_id, animation
@export var recipes: Array[Dictionary] = []

func get_required_block_counts() -> Dictionary:
    var counts := {}
    for block in blocks:
        var block_id := StringName(block.get("block_id", ""))
        if block_id == &"":
            continue
        counts[block_id] = counts.get(block_id, 0) + 1
    return counts

func get_blocks_by_layer(layer_id: StringName) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for block in blocks:
        if StringName(block.get("layer", "")) == layer_id:
            result.append(block)
    return result

func get_blocks_by_stage(stage_id: StringName) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for block in blocks:
        if StringName(block.get("build_stage", "")) == stage_id:
            result.append(block)
    return result

func get_build_stage_order() -> Array[StringName]:
    var order: Array[StringName] = [&"foundation", &"floor", &"wall", &"workstation", &"storage", &"roof", &"fx", &"decoration"]
    var seen := {}
    for stage in order:
        seen[stage] = true
    for block in blocks:
        var stage := StringName(block.get("build_stage", "decoration"))
        if not seen.has(stage):
            order.append(stage)
            seen[stage] = true
    return order

func validate_basic() -> PackedStringArray:
    var errors := PackedStringArray()
    if id == &"" or id == &"unknown_building":
        errors.append("Blueprint id is missing or still default.")
    if blocks.is_empty():
        errors.append("Blueprint has no blocks.")
    if footprint.x <= 0 or footprint.y <= 0:
        errors.append("Blueprint footprint must be positive.")
    return errors
