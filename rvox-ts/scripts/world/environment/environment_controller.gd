class_name EnvironmentController
extends RefCounted

## Owns the WorldEnvironment's Environment/Sky resources. Background is now
## a real procedural sky (sky.gdshader) instead of a flat BG_COLOR — driven
## every frame by SunMoonRig's 4-keyframe palette via set_palette(). Ambient
## light/fog stay driven by the simpler daylight_factor + rain_intensity
## blend (same shape as before) rather than derived from the sky colors —
## keeps ambient predictable rather than tied to whichever keyframe's sky
## tones happen to be very saturated or very dark. Same RefCounted-utility
## shape as TerrainMaterialResolver/MinimapGenerator — no scene presence
## needed, the caller holds an instance and a WorldEnvironment node
## reference.

const SKY_SHADER := preload("res://scripts/world/environment/shaders/sky.gdshader")

const DAY_AMBIENT := Color("#d7e4df")
const NIGHT_AMBIENT := Color("#48546b")
const RAIN_AMBIENT := Color("#8a969c")

const DAY_AMBIENT_ENERGY := 0.65
const NIGHT_AMBIENT_ENERGY := 0.16

const CLEAR_FOG_DENSITY := 0.0028
const RAIN_FOG_DENSITY := 0.028

var environment: Environment
var _sky_material: ShaderMaterial
var _daylight := 1.0
var _rain := 0.0
var _fog_color := Color("#58729a")

func setup(world_environment: WorldEnvironment) -> void:
    _sky_material = ShaderMaterial.new()
    _sky_material.shader = SKY_SHADER

    var sky := Sky.new()
    sky.sky_material = _sky_material

    environment = Environment.new()
    environment.background_mode = Environment.BG_SKY
    environment.sky = sky
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    environment.fog_enabled = true
    environment.glow_enabled = true
    environment.glow_intensity = 0.35
    world_environment.environment = environment
    _apply()

## Called every frame from game_main.gd with the live SunMoonRig so the sky
## shader and ambient/fog colors track the current time-of-day keyframe.
func set_palette(rig: SunMoonRig) -> void:
    _daylight = clampf(rig.daylight_factor, 0.0, 1.0)
    _fog_color = rig.fog_color
    if _sky_material != null:
        _sky_material.set_shader_parameter("sky_top_color", rig.sky_top_color)
        _sky_material.set_shader_parameter("sky_horizon_color", rig.sky_horizon_color)
        _sky_material.set_shader_parameter("sun_color", rig.sun_color)
        _sky_material.set_shader_parameter("moon_color", rig.moon_color)
        _sky_material.set_shader_parameter("fog_color", rig.fog_color)
        _sky_material.set_shader_parameter("sun_direction", rig.sun_direction)
        _sky_material.set_shader_parameter("moon_direction", rig.moon_direction)
        _sky_material.set_shader_parameter("sun_glow", rig.sun_glow)
        _sky_material.set_shader_parameter("moon_glow", rig.moon_glow)
        _sky_material.set_shader_parameter("night_amount", rig.night_amount)
    _apply()

## intensity 0..1. Called from weather systems (rain) so lighting/fog/sky
## react without every system owning its own Environment writes.
func set_rain_intensity(intensity: float) -> void:
    _rain = clampf(intensity, 0.0, 1.0)
    if _sky_material != null:
        _sky_material.set_shader_parameter("storm_amount", _rain)
    _apply()

func _apply() -> void:
    if environment == null:
        return
    var ambient := NIGHT_AMBIENT.lerp(DAY_AMBIENT, _daylight).lerp(RAIN_AMBIENT, _rain * 0.5)
    var ambient_energy := lerpf(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, _daylight) * lerpf(1.0, 0.6, _rain)

    environment.ambient_light_color = ambient
    environment.ambient_light_energy = ambient_energy
    environment.fog_light_color = _fog_color.lerp(RAIN_AMBIENT, _rain * 0.6)
    environment.fog_density = lerpf(CLEAR_FOG_DENSITY, RAIN_FOG_DENSITY, _rain)
