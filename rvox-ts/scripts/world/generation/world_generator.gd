class_name WorldGenerator
extends RefCounted

var height_generator := TerrainHeightGenerator.new()
var surface_resolver := SurfaceBlockResolver.new()
var biome_classifier := BiomeClassifier.new()
var resource_generator := ResourceVeinGenerator.new()
var tree_generator := TreeGenerator.new()
var lake_generator := LakeGenerator.new()
var river_generator := RiverGenerator.new()
var ocean_seeder := OceanSeeder.new()

func configure(config: WorldGenConfig) -> void:
    height_generator.configure(config)
    biome_classifier.configure(config)
    resource_generator.configure(config)
    tree_generator.configure(config)

func generate_chunk(chunk_position: Vector2i, config: WorldGenConfig, water_simulator: WaterFlowSimulator = null) -> ChunkData:
    configure(config)
    var chunk := ChunkData.new()
    chunk.setup(chunk_position, config.chunk_size, config.max_height)

    for local_x in config.chunk_size:
        for local_z in config.chunk_size:
            var global_x := chunk.get_global_x(local_x)
            var global_z := chunk.get_global_z(local_z)
            var height := height_generator.get_height(global_x, global_z, config)
            var biome_id := biome_classifier.classify(global_x, global_z, height, config)

            chunk.set_surface_height(local_x, local_z, height)
            chunk.set_biome(local_x, local_z, biome_id)

            for y in range(0, config.max_height):
                if y <= height:
                    var block_id := surface_resolver.resolve_subsurface_block(y, height, config)
                    var ore_id := resource_generator.resolve_ore(global_x, y, global_z, height, config)
                    if ore_id != &"":
                        block_id = ore_id
                    chunk.set_block(local_x, y, local_z, block_id)

            if tree_generator.should_place_tree(global_x, global_z, height, biome_id, config):
                tree_generator.place_oak_tree(chunk, local_x, height, local_z)

    lake_generator.mark_lakes(chunk, config, water_simulator)
    river_generator.carve_rivers(chunk, config, water_simulator)
    ocean_seeder.seed_ocean_sources(chunk, config, water_simulator)

    chunk.clear_dirty()
    return chunk
