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

@export_group("External Asset")
@export var mesh_scene: PackedScene
@export var preview_icon: Texture2D
@export var source_pack: String = ""
@export_multiline var license_note: String = ""
