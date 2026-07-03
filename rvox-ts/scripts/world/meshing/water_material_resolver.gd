class_name WaterMaterialResolver
extends RefCounted

## Builds the shared water ShaderMaterial. Wave normals are computed
## analytically in the shader from the same height function driving vertex
## displacement (see water.gdshader) — no normal-map textures needed, so
## unlike the previous version there's no texture generation here at all.

const WATER_SHADER := preload("res://scripts/world/meshing/shaders/water.gdshader")

static func make_water_material(water_depth_texture: Texture2D, fog_of_war_texture: Texture2D, world_extent: float) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = WATER_SHADER
    material.set_shader_parameter("water_depth", water_depth_texture)
    material.set_shader_parameter("fog_of_war", fog_of_war_texture)
    material.set_shader_parameter("world_extent", world_extent)
    return material

static func set_rain_intensity(material: ShaderMaterial, intensity: float) -> void:
    if material != null:
        material.set_shader_parameter("rain_intensity", clampf(intensity, 0.0, 1.0))

## Called every frame from game_main.gd with the live SunMoonRig so water's
## reflection tint and sun/moon specular track the current time-of-day
## palette — same colors sky.gdshader renders, for visual consistency.
static func set_lighting(material: ShaderMaterial, rig: SunMoonRig) -> void:
    if material == null:
        return
    material.set_shader_parameter("sky_top_color", rig.sky_top_color)
    material.set_shader_parameter("sky_horizon_color", rig.sky_horizon_color)
    material.set_shader_parameter("sun_color", rig.sun_color)
    material.set_shader_parameter("moon_color", rig.moon_color)
    material.set_shader_parameter("sea_deep_color", rig.sea_deep_color)
    material.set_shader_parameter("sea_shallow_color", rig.sea_shallow_color)
    material.set_shader_parameter("sun_direction", rig.sun_direction)
    material.set_shader_parameter("moon_direction", rig.moon_direction)
    material.set_shader_parameter("sun_glow", rig.sun_glow)
    material.set_shader_parameter("moon_glow", rig.moon_glow)
