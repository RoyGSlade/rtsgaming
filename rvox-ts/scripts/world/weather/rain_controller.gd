class_name RainController
extends Node3D

## Follows the camera focus point and emits rain particles, while also
## driving puddle formation: accumulates OverlayStateMap wetness across the
## whole chunk while raining (decays back down while dry). Emits
## rain_intensity_changed so other systems (environment fog/ambient, day
## night light dimming) can react without owning weather state themselves.

signal rain_intensity_changed(intensity: float)

const PUDDLE_TICK_INTERVAL := 0.2
const PUDDLE_RISE_RATE := 0.12
const PUDDLE_FALL_RATE := 0.04

@export var target_path: NodePath
@export var world_path: NodePath
@export var height_above_target := 24.0

@export_range(0.0, 1.0) var rain_intensity: float = 0.0:
    set(value):
        rain_intensity = clampf(value, 0.0, 1.0)
        _apply_rain_intensity()

var target: Node3D
var world: WorldRuntime
var _rain: GPUParticles3D
var _puddle_accum_timer := 0.0

func _ready() -> void:
    if target_path != NodePath():
        target = get_node(target_path)
    if world_path != NodePath():
        world = get_node(world_path)
    _rain = _build_rain_particles()
    add_child(_rain)
    _apply_rain_intensity()

func _process(delta: float) -> void:
    if target != null:
        global_position.x = target.global_position.x
        global_position.z = target.global_position.z
        global_position.y = target.global_position.y + height_above_target

    _puddle_accum_timer += delta
    if _puddle_accum_timer >= PUDDLE_TICK_INTERVAL:
        _puddle_accum_timer = 0.0
        _tick_puddles()

func _apply_rain_intensity() -> void:
    if _rain != null:
        _rain.emitting = rain_intensity > 0.01
        _rain.amount_ratio = clampf(rain_intensity, 0.05, 1.0) if rain_intensity > 0.01 else 0.0
    rain_intensity_changed.emit(rain_intensity)

func _tick_puddles() -> void:
    if world == null:
        return
    var overlay := world.get_overlay_state()
    if overlay == null:
        return
    var rate := PUDDLE_RISE_RATE * rain_intensity if rain_intensity > 0.01 else -PUDDLE_FALL_RATE
    if rate == 0.0:
        return
    var changed := false
    for x in overlay.width:
        for z in overlay.depth:
            var current := overlay.get_value(x, z, OverlayStateMap.Channel.WETNESS)
            var next := clampf(current + rate, 0.0, 1.0)
            if not is_equal_approx(next, current):
                overlay.set_value(x, z, OverlayStateMap.Channel.WETNESS, next)
                changed = true
    if changed:
        world.refresh_overlay_state()

func _build_rain_particles() -> GPUParticles3D:
    var particles := GPUParticles3D.new()
    particles.name = "RainParticles"
    particles.amount = 1500
    particles.lifetime = 1.0
    particles.local_coords = true
    particles.emitting = false

    var quad := QuadMesh.new()
    quad.size = Vector2(0.025, 0.55)
    var quad_material := StandardMaterial3D.new()
    quad_material.albedo_color = Color(0.75, 0.83, 0.92, 0.45)
    quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    quad_material.cull_mode = BaseMaterial3D.CULL_DISABLED
    quad.material = quad_material
    particles.draw_pass_1 = quad

    var process_material := ParticleProcessMaterial.new()
    process_material.direction = Vector3(0.0, -1.0, 0.0)
    process_material.spread = 2.0
    process_material.gravity = Vector3(0.0, -9.0, 0.0)
    process_material.initial_velocity_min = 13.0
    process_material.initial_velocity_max = 17.0
    process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
    # Scaled up for the larger world/higher max camera zoom — covers a
    # bigger visible-ground footprint than the original 35x35 box did.
    process_material.emission_box_extents = Vector3(40.0, 0.5, 40.0)
    particles.process_material = process_material

    return particles
