class_name WorldRuntime
extends Node3D

signal world_generated(summary: Dictionary)

const TEXTURE_ATLAS_PATH := "res://data/textures/terrain_texture_atlas.tres"

@export var config: WorldGenConfig
@export var chunk_position := Vector2i.ZERO

@onready var terrain_mesh: MeshInstance3D = $TerrainMesh
@onready var grass: GrassScatter = $Grass
@onready var water_mesh: MeshInstance3D = $WaterMesh

# Ticking cadence for the live water simulation - fast enough to look like
# flow, throttled separately from the (expensive, full-mesh-rebuild) water
# mesh refresh so a settled world costs ~0 per frame. See
# WaterFlowSimulator's active-queue design: tick() is a no-op once nothing
# is changing, so this loop is cheap even though it "always runs."
const WATER_TICK_INTERVAL := 0.1
const WATER_REBUILD_INTERVAL := 0.2
const MAX_TICKS_PER_FRAME := 5
# Runs synchronously right after generation so the first rendered frame
# isn't a completely empty world slowly filling in - purely a load-time
# convenience, not part of the ongoing live simulation.
const PRESETTLE_TICKS := 200

var current_chunk: ChunkData
var _generator := WorldGenerator.new()
var _water_simulator := WaterFlowSimulator.new()
var _mesher := ChunkMesher.new()
var _water_mesh_builder := WaterMeshBuilder.new()
var _block_registry := BlockRegistry.new()
var _texture_atlas: TerrainTextureAtlas
var _overlay_state: OverlayStateMap
var _fog_of_war: FogOfWar
var _water_depth_map: WaterDepthMap
var _terrain_material: ShaderMaterial
var _water_material: ShaderMaterial
var _water_tick_accumulator := 0.0
var _water_rebuild_accumulator := 0.0
var _water_dirty_since_rebuild := false


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
	# Fresh simulator per generation - regenerating must not carry stale
	# source/flowing voxel positions over from the previous ChunkData.
	_water_simulator = WaterFlowSimulator.new()
	_water_tick_accumulator = 0.0
	_water_rebuild_accumulator = 0.0
	_water_dirty_since_rebuild = false

	current_chunk = _generator.generate_chunk(chunk_position, config, _water_simulator)
	for i in PRESETTLE_TICKS:
		_water_simulator.tick(current_chunk)

	_overlay_state = OverlayStateMap.new(config.chunk_size, config.chunk_size)
	_fog_of_war = FogOfWar.new(config.chunk_size, config.chunk_size)
	terrain_mesh.mesh = _mesher.build_mesh(current_chunk, _block_registry, _texture_atlas)
	_terrain_material = TerrainMaterialResolver.make_terrain_material(
		_texture_atlas, _overlay_state.get_texture(), _fog_of_war.get_texture(), float(config.chunk_size)
	)
	terrain_mesh.material_override = _terrain_material
	_rebuild_terrain_collider()
	grass.build(current_chunk, _block_registry)

	_water_depth_map = WaterDepthMap.new(config.chunk_size, config.chunk_size)
	_water_depth_map.populate(current_chunk, _water_simulator)
	water_mesh.mesh = _water_mesh_builder.build_water_mesh(current_chunk, _water_simulator)
	_water_material = WaterMaterialResolver.make_water_material(
		_water_depth_map.get_texture(), _fog_of_war.get_texture(), float(config.chunk_size)
	)
	water_mesh.material_override = _water_material

	world_generated.emit(_build_summary())


func _process(delta: float) -> void:
	if current_chunk == null:
		return

	_water_tick_accumulator += delta
	var ticks_this_frame := 0
	while _water_tick_accumulator >= WATER_TICK_INTERVAL and ticks_this_frame < MAX_TICKS_PER_FRAME:
		_water_tick_accumulator -= WATER_TICK_INTERVAL
		ticks_this_frame += 1
		if _water_simulator.tick(current_chunk):
			_water_dirty_since_rebuild = true

	_water_rebuild_accumulator += delta
	if _water_dirty_since_rebuild and _water_rebuild_accumulator >= WATER_REBUILD_INTERVAL:
		_water_rebuild_accumulator = 0.0
		_water_dirty_since_rebuild = false
		_rebuild_water_visuals()


func _rebuild_water_visuals() -> void:
	_water_depth_map.populate(current_chunk, _water_simulator)
	water_mesh.mesh = _water_mesh_builder.build_water_mesh(current_chunk, _water_simulator)


func get_water_simulator() -> WaterFlowSimulator:
	return _water_simulator


## Surface Y at a world XZ, for standing units on the terrain. Samples the
## column heightmap (nearest cell) and returns the top of the surface block.
## Out-of-bounds falls back to the configured water level so a unit ordered
## off the map edge still gets a sane height rather than 0.
func get_ground_height(world_x: float, world_z: float) -> float:
	if current_chunk == null:
		return 0.0
	var cell_x := int(floor(world_x))
	var cell_z := int(floor(world_z))
	if cell_x < 0 or cell_x >= config.chunk_size or cell_z < 0 or cell_z >= config.chunk_size:
		return float(config.water_level)
	# +1: get_surface_height is the top solid block index; the walkable
	# surface is the top face of that block, one unit above its base.
	return float(current_chunk.get_surface_height(cell_x, cell_z) + 1)


## Rebuilds the terrain's trimesh StaticBody collider so camera raycasts can
## hit the ground (unit picking / move orders). create_trimesh_collision
## adds a fresh child each call, so the previous one is removed first to
## avoid stacking colliders across regenerations.
func _rebuild_terrain_collider() -> void:
	for child in terrain_mesh.get_children():
		if child is StaticBody3D:
			child.queue_free()
	terrain_mesh.create_trimesh_collision()


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
			if not _water_simulator.get_column_spans(current_chunk, x, z).is_empty():
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
