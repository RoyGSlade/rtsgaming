class_name BiomeDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var base_surface_block: StringName = &"grass"
@export var fertility_modifier: float = 1.0
@export var moisture_modifier: float = 1.0
@export var tree_density_modifier: float = 1.0
@export var ore_density_modifier: float = 1.0
@export var wildlife_density_modifier: float = 1.0
@export var movement_cost_modifier: float = 1.0
@export var danger_modifier: float = 1.0
