class_name RecipeDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var inputs: Dictionary = {}
@export var outputs: Dictionary = {}
@export var duration_seconds: float = 1.0
@export var required_station: StringName
@export var worker_role: StringName
@export var animation_id: StringName
