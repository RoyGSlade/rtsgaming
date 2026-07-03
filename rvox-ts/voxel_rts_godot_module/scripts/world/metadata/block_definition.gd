class_name BlockDefinition
extends Resource

@export var id: StringName = &"air"
@export var display_name: String = "Air"
@export var category: StringName = &"terrain"

@export var solid: bool = false
@export var transparent: bool = true
@export var walkable: bool = false
@export var buildable: bool = false
@export var diggable: bool = false
@export var fluid: bool = false

@export var hardness: float = 0.0
@export var fertility: float = 0.0
@export var moisture: float = 0.0
@export var flammability: float = 0.0
@export var path_cost: float = 1.0

@export var harvest_resource_id: StringName = &""
@export var harvest_amount: int = 0
@export var tool_required: StringName = &""

@export var mesh_id: int = -1
@export var material_id: StringName = &"default"

func can_harvest_with(tool_id: StringName) -> bool:
    if harvest_resource_id == &"" or harvest_amount <= 0:
        return false
    if tool_required == &"":
        return true
    return tool_required == tool_id

func blocks_path() -> bool:
    return solid and not walkable

func is_air() -> bool:
    return id == &"air"
