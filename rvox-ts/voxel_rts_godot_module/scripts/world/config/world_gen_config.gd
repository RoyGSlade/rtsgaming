class_name WorldGenConfig
extends Resource

@export var world_seed: int = 1337
@export var world_size: Vector2i = Vector2i(256, 256)
@export var chunk_size: int = 32
@export var max_height: int = 48
@export var water_level: int = 15

@export var height_scale: float = 72.0
@export var height_power: float = 1.35
@export var octaves: int = 5
@export var lacunarity: float = 2.0
@export var persistence: float = 0.5

@export var ridge_scale: float = 110.0
@export_range(0.0, 1.0, 0.01) var ridge_mix: float = 0.22
@export var detail_scale: float = 28.0
@export_range(0.0, 1.0, 0.01) var detail_mix: float = 0.08

@export var sand_line: int = 17
@export var tree_line: int = 32
@export var pine_line: int = 37
@export var snow_line: int = 41

@export_range(0.0, 1.0, 0.01) var tree_density: float = 0.16
@export_range(0.0, 1.0, 0.01) var ore_density: float = 0.12
@export_range(0.0, 1.0, 0.01) var wildlife_density: float = 0.05

@export var generate_trees: bool = true
@export var generate_ores: bool = true
@export var generate_water: bool = true

func get_clamped_water_level() -> int:
    return clampi(water_level, 0, max_height - 1)
