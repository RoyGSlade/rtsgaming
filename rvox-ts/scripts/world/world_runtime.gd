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

# The terrain is meshed as a grid of REGION_SIZE x REGION_SIZE column
# regions, each its own MeshInstance3D + trimesh collider, so a block edit
# (mining, building) remeshes one small region instead of the whole map.
# Remeshing is budgeted per frame; a burst of edits queues regions and they
# drain a few per frame rather than spiking one frame.
const REGION_SIZE := 32
const MAX_REGION_REMESH_PER_FRAME := 2

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
var _region_instances: Dictionary = {} # Vector2i region coord -> MeshInstance3D
var _dirty_regions: Dictionary = {} # Vector2i region coord -> true


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
	_terrain_material = TerrainMaterialResolver.make_terrain_material(
		_texture_atlas, _overlay_state.get_texture(), _fog_of_war.get_texture(), float(config.chunk_size)
	)
	_build_all_regions()
	# Connected only now: generation-time edits (rivers, trees, settling
	# water) shouldn't queue remeshes of regions that were just built.
	current_chunk.terrain_block_changed.connect(_on_terrain_block_changed)
	grass.build(current_chunk, _block_registry)

	_water_depth_map = WaterDepthMap.new(config.chunk_size, config.chunk_size)
	_water_depth_map.populate(current_chunk, _water_simulator)
	water_mesh.mesh = _water_mesh_builder.build_water_mesh(current_chunk, _water_simulator)
	_water_material = WaterMaterialResolver.make_water_material(
		_water_depth_map.get_texture(), _fog_of_war.get_texture(), float(config.chunk_size)
	)
	water_mesh.material_override = _water_material
	# Presettling and the build above already account for every column that
	# moved during generation; drain that history now so the live loop's
	# first dirty check reflects only what changes after this point.
	_water_simulator.pop_dirty_columns()

	world_generated.emit(_build_summary())


func _process(delta: float) -> void:
	if current_chunk == null:
		return

	_water_tick_accumulator += delta
	var ticks_this_frame := 0
	while _water_tick_accumulator >= WATER_TICK_INTERVAL and ticks_this_frame < MAX_TICKS_PER_FRAME:
		_water_tick_accumulator -= WATER_TICK_INTERVAL
		ticks_this_frame += 1
		_water_simulator.tick(current_chunk)
		# tick()'s own return only reports whether _dirty_columns is
		# non-empty, which never resets on its own - pop_dirty_columns()
		# is what actually drains it. Without this drain the flag below
		# gets stuck true forever after the first water movement ever
		# happens, which was forcing a full-map water mesh + depth-map
		# rebuild every WATER_REBUILD_INTERVAL for the rest of the game
		# even once the water had fully settled - the actual cause of the
		# "low GPU/CPU usage but choppy frame" stutter on large maps (a
		# full O(map area) rebuild every 0.2s pins one CPU core and stalls
		# the render thread waiting on it).
		if not _water_simulator.pop_dirty_columns().is_empty():
			_water_dirty_since_rebuild = true

	_water_rebuild_accumulator += delta
	if _water_dirty_since_rebuild and _water_rebuild_accumulator >= WATER_REBUILD_INTERVAL:
		_water_rebuild_accumulator = 0.0
		_water_dirty_since_rebuild = false
		_rebuild_water_visuals()

	var remeshed := 0
	while not _dirty_regions.is_empty() and remeshed < MAX_REGION_REMESH_PER_FRAME:
		var region_coord: Vector2i = _dirty_regions.keys()[0]
		_dirty_regions.erase(region_coord)
		_remesh_region(region_coord)
		remeshed += 1


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


## (Re)builds every terrain region mesh under the TerrainMesh container
## node. TerrainMesh itself renders nothing anymore; each region is a child
## MeshInstance3D covering REGION_SIZE x REGION_SIZE columns with its own
## trimesh StaticBody collider so camera raycasts can hit the ground.
func _build_all_regions() -> void:
	for child in terrain_mesh.get_children():
		child.queue_free()
	_region_instances.clear()
	_dirty_regions.clear()
	terrain_mesh.mesh = null

	var regions_per_axis := ceili(float(config.chunk_size) / float(REGION_SIZE))
	for rx in regions_per_axis:
		for rz in regions_per_axis:
			var instance := MeshInstance3D.new()
			instance.name = "Region_%d_%d" % [rx, rz]
			instance.material_override = _terrain_material
			terrain_mesh.add_child(instance)
			_region_instances[Vector2i(rx, rz)] = instance
			_remesh_region(Vector2i(rx, rz))


func _region_rect(region_coord: Vector2i) -> Rect2i:
	return Rect2i(region_coord.x * REGION_SIZE, region_coord.y * REGION_SIZE, REGION_SIZE, REGION_SIZE)


func _remesh_region(region_coord: Vector2i) -> void:
	var instance: MeshInstance3D = _region_instances.get(region_coord)
	if instance == null or current_chunk == null:
		return
	instance.mesh = _mesher.build_region_mesh(current_chunk, _region_rect(region_coord), _block_registry, _texture_atlas)
	for child in instance.get_children():
		if child is StaticBody3D:
			child.queue_free()
	instance.create_trimesh_collision()


## A block change on a region border also changes which faces the adjacent
## region's edge blocks expose, so any region within one block of the edit
## gets queued, not just the one containing it.
func _on_terrain_block_changed(local_x: int, _y: int, local_z: int) -> void:
	var regions_per_axis := ceili(float(config.chunk_size) / float(REGION_SIZE))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var region_coord := Vector2i((local_x + dx) / REGION_SIZE, (local_z + dz) / REGION_SIZE)
			if region_coord.x < 0 or region_coord.y < 0 or region_coord.x >= regions_per_axis or region_coord.y >= regions_per_axis:
				continue
			_dirty_regions[region_coord] = true


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
		# Tree blocks are edits, so counting them stays exact. Ore is now
		# procedural-on-demand (never enumerated), so the summary samples a
		# strided sub-grid of columns and scales up — same number the old
		# full-volume count approximated, at a fraction of the noise calls.
		"tree_blocks": current_chunk.count_block(&"oak_log"),
		"ore_blocks": _estimate_ore_blocks(),
	}


func _estimate_ore_blocks() -> int:
	if not config.generate_ores:
		return 0
	var stride := maxi(4, config.chunk_size / 32)
	var ore_generator := _generator.resource_generator
	var sampled := 0
	for x in range(0, config.chunk_size, stride):
		for z in range(0, config.chunk_size, stride):
			var height := current_chunk.get_surface_height(x, z)
			var global_x := current_chunk.get_global_x(x)
			var global_z := current_chunk.get_global_z(z)
			for y in range(0, height - 1):
				if ore_generator.resolve_ore(global_x, y, global_z, height, config) != &"":
					sampled += 1
	return sampled * stride * stride
