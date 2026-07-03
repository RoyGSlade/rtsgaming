class_name TreeGenerator
extends RefCounted

var tree_noise := FastNoiseLite.new()

func configure(config: WorldGenConfig) -> void:
    tree_noise.seed = config.world_seed + 601
    tree_noise.noise_type = FastNoiseLite.TYPE_PERLIN
    tree_noise.frequency = 1.0 / 18.0

func should_place_tree(global_x: int, global_z: int, height: int, biome_id: StringName, config: WorldGenConfig) -> bool:
    if not config.generate_trees:
        return false
    if height <= config.water_level + 2 or height >= config.tree_line:
        return false
    if biome_id == &"dry_plain" or biome_id == &"coast":
        return false
    var density := config.tree_density
    if biome_id == &"forest":
        density *= 2.2
    var value := clampf((tree_noise.get_noise_2d(global_x, global_z) + 1.0) * 0.5, 0.0, 1.0)
    return value > (1.0 - density)

func place_oak_tree(chunk: ChunkData, local_x: int, base_y: int, local_z: int) -> void:
    var trunk_height := 3
    for i in trunk_height:
        chunk.set_block(local_x, base_y + 1 + i, local_z, &"oak_log")

    var leaf_y := base_y + trunk_height + 1
    for dx in range(-2, 3):
        for dz in range(-2, 3):
            for dy in range(-1, 2):
                if abs(dx) + abs(dz) + abs(dy) > 4:
                    continue
                var x := local_x + dx
                var y := leaf_y + dy
                var z := local_z + dz
                if chunk.is_in_bounds(x, y, z) and chunk.get_block(x, y, z) == &"air":
                    chunk.set_block(x, y, z, &"oak_leaves")
