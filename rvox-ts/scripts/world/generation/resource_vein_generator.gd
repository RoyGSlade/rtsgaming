class_name ResourceVeinGenerator
extends RefCounted

var iron_noise := FastNoiseLite.new()
var coal_noise := FastNoiseLite.new()
var copper_noise := FastNoiseLite.new()

func configure(config: WorldGenConfig) -> void:
    _setup(iron_noise, config.world_seed + 501, 42.0)
    _setup(coal_noise, config.world_seed + 502, 55.0)
    _setup(copper_noise, config.world_seed + 503, 38.0)

func _setup(noise: FastNoiseLite, noise_seed: int, scale: float) -> void:
    noise.seed = noise_seed
    noise.noise_type = FastNoiseLite.TYPE_PERLIN
    noise.frequency = 1.0 / scale
    noise.fractal_type = FastNoiseLite.FRACTAL_FBM
    noise.fractal_octaves = 3

func resolve_ore(global_x: int, y: int, global_z: int, surface_height: int, config: WorldGenConfig) -> StringName:
    if not config.generate_ores:
        return &""
    if y >= surface_height - 2:
        return &""

    var depth_factor := 1.0 - float(y) / maxf(float(config.max_height), 1.0)
    var threshold := 0.78 - config.ore_density * 0.25

    if _normalized(iron_noise.get_noise_3d(global_x, y, global_z)) * depth_factor > threshold:
        return &"iron_ore"
    if _normalized(coal_noise.get_noise_3d(global_x, y, global_z)) * depth_factor > threshold + 0.03:
        return &"coal_ore"
    if y < surface_height - 4 and _normalized(copper_noise.get_noise_3d(global_x, y, global_z)) * depth_factor > threshold + 0.04:
        return &"copper_ore"

    return &""

func _normalized(value: float) -> float:
    return clampf((value + 1.0) * 0.5, 0.0, 1.0)
