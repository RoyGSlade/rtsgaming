class_name TerrainHeightGenerator
extends RefCounted

var height_noise := FastNoiseLite.new()
var ridge_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()

func configure(config: WorldGenConfig) -> void:
    _configure_noise(height_noise, config.world_seed, config.height_scale, config.octaves, config.lacunarity, config.persistence)
    _configure_noise(ridge_noise, config.world_seed + 101, config.ridge_scale, config.octaves, config.lacunarity, config.persistence)
    _configure_noise(detail_noise, config.world_seed + 202, config.detail_scale, 2, 2.0, 0.5)

func _configure_noise(noise: FastNoiseLite, noise_seed: int, scale: float, octaves: int, lacunarity: float, persistence: float) -> void:
    noise.seed = noise_seed
    noise.noise_type = FastNoiseLite.TYPE_PERLIN
    noise.frequency = 1.0 / maxf(scale, 0.001)
    noise.fractal_type = FastNoiseLite.FRACTAL_FBM
    noise.fractal_octaves = max(1, octaves)
    noise.fractal_lacunarity = lacunarity
    noise.fractal_gain = persistence

func get_height(global_x: int, global_z: int, config: WorldGenConfig) -> int:
    var base := _normalize(height_noise.get_noise_2d(global_x, global_z))
    var ridge := 1.0 - absf(ridge_noise.get_noise_2d(global_x, global_z))
    var detail := _normalize(detail_noise.get_noise_2d(global_x, global_z))

    var mixed := lerpf(base, ridge, config.ridge_mix)
    mixed = lerpf(mixed, detail, config.detail_mix)
    mixed = pow(clampf(mixed, 0.0, 1.0), config.height_power)

    var h := int(round(mixed * float(config.max_height - 1)))
    return clampi(h, 1, config.max_height - 1)

func _normalize(value: float) -> float:
    return clampf((value + 1.0) * 0.5, 0.0, 1.0)
