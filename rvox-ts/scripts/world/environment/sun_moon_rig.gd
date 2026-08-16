class_name SunMoonRig
extends Node3D

## Drives a DirectionalLight3D sun and moon through a day/night cycle, plus
## a 4-keyframe (DAWN/MIDDAY/DUSK/NIGHT) sky/sea/sun color palette — the
## same "blend between adjacent named scenes" technique as the reference
## ocean/sky shader (waterLightCode.md), keyed off time_of_day instead of
## scroll position. Storm/rain is deliberately NOT a 5th keyframe here —
## RainController/EnvironmentController already own that axis and blend it
## on top of whichever time-of-day keyframe is active.

@onready var sun: DirectionalLight3D = $Sun
@onready var moon: DirectionalLight3D = $Moon

@export var day_length_seconds := 900.0
@export_range(0.0, 1.0) var time_of_day := 0.25
@export var paused := false

## Multiplies sun/moon light_energy on top of the day/night curve, so
## weather systems (rain) can dim the light without fighting this script
## for ownership of light_energy every frame.
@export_range(0.0, 1.0) var weather_energy_multiplier := 1.0

## 0 = full night, 1 = full day. Read by EnvironmentController to drive
## ambient/background/fog alongside weather, since ambient light otherwise
## swamps the ~2.0 vs 0.0 sun_energy swing and day/night reads as flat.
var daylight_factor := 1.0

# Keyframe order: NIGHT, DAWN, MIDDAY, DUSK (wraps back to NIGHT), aligned
# to sun_direction.y's actual phase (nadir at t=0, horizon-rising at
# t=0.25, zenith at t=0.5, horizon-setting at t=0.75 — see _update_lighting).
const SKY_TOP := [Color(0.01, 0.01, 0.05), Color(0.20, 0.11, 0.30), Color(0.05, 0.24, 0.68), Color(0.26, 0.11, 0.10)]
const SKY_HORIZON := [Color(0.03, 0.05, 0.14), Color(0.90, 0.58, 0.34), Color(0.42, 0.62, 0.90), Color(0.86, 0.46, 0.24)]
const SUN_COLOR := [Color(0.70, 0.75, 0.94), Color(1.0, 0.74, 0.46), Color(1.0, 0.96, 0.80), Color(1.0, 0.60, 0.34)]
const SEA_DEEP := [Color(0.00, 0.01, 0.03), Color(0.08, 0.05, 0.12), Color(0.03, 0.14, 0.34), Color(0.10, 0.06, 0.04)]
const SEA_SHALLOW := [Color(0.04, 0.06, 0.16), Color(0.28, 0.17, 0.24), Color(0.09, 0.38, 0.60), Color(0.24, 0.13, 0.06)]
const FOG_COLOR := [Color(0.02, 0.03, 0.08), Color(0.80, 0.64, 0.50), Color(0.58, 0.72, 0.90), Color(0.76, 0.54, 0.38)]
const MOON_COLOR := Color(0.45, 0.55, 0.9)

# Resolved palette, recomputed each frame — read by EnvironmentController
# and forwarded to the water material by game_main.gd.
var sky_top_color := Color.BLACK
var sky_horizon_color := Color.BLACK
var sun_color := Color.WHITE
var sea_deep_color := Color.BLACK
var sea_shallow_color := Color.BLACK
var fog_color := Color.BLACK
var sun_direction := Vector3.UP
var moon_direction := Vector3.DOWN
var moon_color := MOON_COLOR
var sun_glow := 0.0
var moon_glow := 0.0
var night_amount := 0.0

func _process(delta: float) -> void:
    if not paused:
        time_of_day = fmod(time_of_day + delta / day_length_seconds, 1.0)
    _update_lighting()

func _update_lighting() -> void:
    var angle := time_of_day * TAU - PI * 0.5

    sun_direction = Vector3(cos(angle), sin(angle), 0.25).normalized()
    moon_direction = -sun_direction

    _position_directional_light(sun, sun_direction)
    _position_directional_light(moon, moon_direction)

    var sun_height := clampf(sun_direction.y, 0.0, 1.0)
    var moon_height := clampf(moon_direction.y, 0.0, 1.0)
    # Wider than raw sun_height so dawn/dusk keep usable ambient light
    # instead of collapsing to near-night as the sun nears the horizon.
    daylight_factor = smoothstep(-0.08, 0.35, sun_direction.y)
    sun_glow = smoothstep(-0.10, 0.06, sun_direction.y)
    moon_glow = smoothstep(0.0, 0.3, moon_height)
    night_amount = 1.0 - smoothstep(0.0, 0.3, sun_height)

    sun.visible = sun_height > 0.01
    moon.visible = moon_height > 0.01

    sun.light_energy = lerpf(0.0, 2.0, smoothstep(0.0, 0.30, sun_height)) * weather_energy_multiplier
    moon.light_energy = lerpf(0.0, 0.28, smoothstep(0.0, 0.45, moon_height)) * weather_energy_multiplier

    var raw: float = time_of_day * 4.0
    var scene_index: int = int(raw) % 4
    var blend: float = fmod(raw, 1.0)

    sky_top_color = _keyframe(SKY_TOP, scene_index, blend)
    sky_horizon_color = _keyframe(SKY_HORIZON, scene_index, blend)
    sun_color = _keyframe(SUN_COLOR, scene_index, blend)
    sea_deep_color = _keyframe(SEA_DEEP, scene_index, blend)
    sea_shallow_color = _keyframe(SEA_SHALLOW, scene_index, blend)
    fog_color = _keyframe(FOG_COLOR, scene_index, blend)
    moon_color = MOON_COLOR

    sun.light_color = sun_color
    moon.light_color = moon_color

func _keyframe(colors: Array, scene_index: int, blend: float) -> Color:
    var a: Color = colors[scene_index]
    var b: Color = colors[(scene_index + 1) % colors.size()]
    return a.lerp(b, blend)

func _position_directional_light(light: DirectionalLight3D, dir: Vector3) -> void:
    light.global_position = dir * 100.0
    light.look_at(Vector3.ZERO, Vector3.UP)
