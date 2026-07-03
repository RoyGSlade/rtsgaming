class_name SurfaceBlockResolver
extends RefCounted

func resolve_surface_block(height: int, config: WorldGenConfig) -> StringName:
    if height <= config.sand_line:
        return &"sand"
    if height >= config.snow_line:
        return &"snow"
    return &"grass"

func resolve_subsurface_block(y: int, surface_height: int, config: WorldGenConfig) -> StringName:
    if y == surface_height:
        return resolve_surface_block(surface_height, config)
    if y >= surface_height - 3:
        return &"dirt"
    if y < max(2, surface_height - 12):
        return &"deep_stone"
    return &"stone"
