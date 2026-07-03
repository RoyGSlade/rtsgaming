class_name WorldRuntime
extends Node3D

signal world_generated(summary: Dictionary)

const TEXTURE_ATLAS_PATH := "res://data/textures/terrain_texture_atlas.tres"

@export var config: WorldGenConfig
@export var chunk_position := Vector2i.ZERO

@onready var terrain_mesh: MeshInstance3D = $TerrainMesh
@onready var grass: GrassScatter = $Grass
@onready var water_mesh: MeshInstance3D = $WaterMesh

var current_chunk: ChunkData
var _generator := WorldGenerator.new()
var _water_solver := WaterFlowSolver.new()
var _mesher := ChunkMesher.new()
var _water_mesh_builder := WaterMeshBuilder.new()
var _block_registry := BlockRegistry.new()
var _texture_atlas: TerrainTextureAtlas
var _overlay_state: OverlayStateMap
var _fog_of_war: FogOfWar
var _water_depth_map: WaterDepthMap
var _terrain_material: ShaderMaterial
var _water_material: ShaderMaterial


func _ready() -> void:
	add_child(_block_registry)
	_block_registry.load_blocks()
	if config == null:
		config = load("res://data/world_presets/default_world_gen_config.tres") as WorldGenConfig
	if ResourceLoader.exists(TEXTURE_ATLAS_PATH):
		_texture_atlas = load(TEXTURE_ATLAS_PATH) as TerrainTextureAtlas
	generate_world()


func generate_world() -> void:
	if config == null:
		push_error("WorldRuntime requires a WorldGenConfig")
		return
	current_chunk = _generator.generate_chunk(chunk_position, config)
	_water_solver.build_surface_water_cells(current_chunk, config)
	_overlay_state = OverlayStateMap.new(config.chunk_size, config.chunk_size)
	_fog_of_war = FogOfWar.new(config.chunk_size, config.chunk_size)
	terrain_mesh.mesh = _mesher.build_mesh(current_chunk, _block_registry, _texture_atlas)
	_terrain_material = TerrainMaterialResolver.make_terrain_material(
		_texture_atlas, _overlay_state.get_texture(), _fog_of_war.get_texture(), float(config.chunk_size)
	)
	terrain_mesh.material_override = _terrain_material
	grass.build(current_chunk, _block_registry)

	_water_depth_map = WaterDepthMap.new(config.chunk_size, config.chunk_size)
	_water_depth_map.populate(current_chunk)
	water_mesh.mesh = _water_mesh_builder.build_water_mesh(current_chunk)
	_water_material = WaterMaterialResolver.make_water_material(
		_water_depth_map.get_texture(), _fog_of_war.get_texture(), float(config.chunk_size)
	)
	water_mesh.material_override = _water_material

	world_generated.emit(_build_summary())


func get_block_registry() -> BlockRegistry:
	return _block_registry


func get_overlay_state() -> OverlayStateMap:
	return _overlay_state


func get_fog_of_war() -> FogOfWar:
	return _fog_of_war


func get_water_material() -> ShaderMaterial:
	return _water_material


## Call after mutating _fog_of_war so the GPU-side texture (already bound
## to _terrain_material) picks up the change.
func refresh_fog_of_war() -> void:
	if _fog_of_war != null:
		_fog_of_war.get_texture()


## Call after mutating _overlay_state so the GPU-side texture (already
## bound to _terrain_material) picks up the change.
func refresh_overlay_state() -> void:
	if _overlay_state != null:
		_overlay_state.get_texture()


func regenerate_with_seed(new_seed: int) -> void:
	config.world_seed = new_seed
	generate_world()


func get_world_center() -> Vector3:
	if config == null:
		return Vector3.ZERO
	return Vector3(config.chunk_size * 0.5, config.max_height * 0.5, config.chunk_size * 0.5)


func get_summary() -> Dictionary:
	return _build_summary() if current_chunk != null else {}


func _build_summary() -> Dictionary:
	var minimum_height := config.max_height
	var maximum_height := 0
	var water_cells := 0
	for x in current_chunk.chunk_size:
		for z in current_chunk.chunk_size:
			var height := current_chunk.get_surface_height(x, z)
			minimum_height = mini(minimum_height, height)
			maximum_height = maxi(maximum_height, height)
			if current_chunk.get_water_cell(x, z) != null:
				water_cells += 1
	return {
		"seed": config.world_seed,
		"chunk_size": config.chunk_size,
		"minimum_height": minimum_height,
		"maximum_height": maximum_height,
		"water_cells": water_cells,
		"tree_blocks": current_chunk.count_block(&"oak_log"),
		"ore_blocks": current_chunk.count_block(&"iron_ore") + current_chunk.count_block(&"coal_ore") + current_chunk.count_block(&"copper_ore"),
	}
