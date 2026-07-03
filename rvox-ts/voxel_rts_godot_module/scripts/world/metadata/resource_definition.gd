class_name ResourceDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var category: StringName = &"raw"
@export var stack_limit: int = 50
@export var weight: float = 1.0
@export var perishable: bool = false
@export var spoil_time_seconds: float = 0.0
@export var value: int = 1
