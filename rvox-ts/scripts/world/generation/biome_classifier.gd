class_name BiomeClassifier
extends RefCounted

var moisture_noise := FastNoiseLite.new()
var temperature_noise := FastNoiseLite.new()

func configure(config: WorldGenConfig) -> void:
    moisture_noise.seed = config.world_seed + 303
    moisture_noise.noise_type = FastNoiseLite.TYPE_PERLIN
    moisture_noise.frequency = 1.0 / 96.0

    temperature_noise.seed = config.world_seed + 404
    temperature_noise.noise_type = FastNoiseLite.TYPE_PERLIN
    temperature_noise.frequency = 1.0 / 128.0

func classify(global_x: int, global_z: int, height: int, config: WorldGenConfig) -> StringName:
    if height <= config.water_level + 1:
        return &"coast"
    if height >= config.snow_line:
        return &"snow_mountain"
    if height >= config.pine_line:
        return &"pine_highland"
    if height >= config.tree_line:
        return &"rocky_hills"

    var moisture := _normalize(moisture_noise.get_noise_2d(global_x, global_z))
    var temperature := _normalize(temperature_noise.get_noise_2d(global_x, global_z))

    if moisture > 0.68:
        return &"forest"
    if moisture < 0.25 and temperature > 0.55:
        return &"dry_plain"
    return &"grassland"

func _normalize(value: float) -> float:
    return clampf((value + 1.0) * 0.5, 0.0, 1.0)
