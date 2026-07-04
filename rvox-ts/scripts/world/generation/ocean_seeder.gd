class_name OceanSeeder
extends RefCounted

## Replaces the old flat "fill every column below water_level" block-write:
## seeds a source directly in every qualifying column instead. Dense,
## per-column seeding means no single source needs to reach far from where
## it's placed, and WaterFlowSimulator's distance-limited spread
## (MAX_FLOW_DISTANCE) keeps that safe regardless of how large or oddly
## shaped the connected below-sea-level region turns out to be.

func seed_ocean_sources(chunk: ChunkData, config: WorldGenConfig, water_simulator: WaterFlowSimulator) -> void:
	if not config.generate_water or water_simulator == null:
		return
	var water_level := config.get_clamped_water_level()
	for x in chunk.chunk_size:
		for z in chunk.chunk_size:
			if chunk.get_surface_height(x, z) <= water_level:
				water_simulator.seed_source(chunk, Vector3i(x, water_level, z))
