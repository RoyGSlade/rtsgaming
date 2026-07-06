@tool
class_name LightFixtureEffect
extends Node3D

## Shared fire/light effect for light-source blocks (torch, lantern,
## brazier): an OmniLight3D plus, for open flames, a particle flame with
## ember sparks and light flicker. Works both in the World Forge editor
## preview and at runtime — configure() it from a BlockDefinition's
## light_* fields (or any custom values) after instancing.

var _light: OmniLight3D
var _base_energy := 2.0
var _flame_enabled := false
## Random phase so a row of torches doesn't flicker in sync.
var _flicker_phase := 0.0
var _time := 0.0


func configure(color: Color, energy: float, light_range: float, flame: bool,
		flame_scale: float = 1.0) -> void:
	_base_energy = energy
	_flame_enabled = flame
	_flicker_phase = fposmod(position.x * 12.9898 + position.z * 78.233, TAU)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = energy
	_light.omni_range = light_range
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0.25 * flame_scale, 0)
	add_child(_light)

	if flame:
		add_child(_make_flame(color, flame_scale))
		add_child(_make_embers(flame_scale))
	set_process(flame)


func _process(delta: float) -> void:
	if not _flame_enabled or _light == null:
		return
	_time += delta
	# Two incommensurate sine waves approximate firelight wander without
	# per-frame RNG (deterministic, cheap, and steady in the editor).
	var flicker := sin(_time * 9.3 + _flicker_phase) * 0.08 + sin(_time * 23.7 + _flicker_phase * 1.7) * 0.05
	_light.light_energy = _base_energy * (1.0 + flicker)


func _make_flame(color: Color, flame_scale: float) -> CPUParticles3D:
	var flame := CPUParticles3D.new()
	flame.amount = 14
	flame.lifetime = 0.55
	flame.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	flame.emission_sphere_radius = 0.06 * flame_scale
	flame.direction = Vector3.UP
	flame.spread = 8.0
	flame.gravity = Vector3(0, 2.6, 0)
	flame.initial_velocity_min = 0.25 * flame_scale
	flame.initial_velocity_max = 0.55 * flame_scale
	flame.scale_amount_min = 0.05 * flame_scale
	flame.scale_amount_max = 0.13 * flame_scale
	flame.scale_amount_curve = _fade_out_curve()
	flame.color = Color(color.r, color.g * 0.9, color.b * 0.5)
	flame.mesh = _glow_quad(Color(1.0, 0.82, 0.45))
	flame.local_coords = true
	flame.position = Vector3(0, 0.18 * flame_scale, 0)
	return flame


func _make_embers(flame_scale: float) -> CPUParticles3D:
	var embers := CPUParticles3D.new()
	embers.amount = 5
	embers.lifetime = 1.4
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	embers.emission_sphere_radius = 0.05 * flame_scale
	embers.direction = Vector3.UP
	embers.spread = 24.0
	embers.gravity = Vector3(0, 1.1, 0)
	embers.initial_velocity_min = 0.3 * flame_scale
	embers.initial_velocity_max = 0.8 * flame_scale
	embers.scale_amount_min = 0.015
	embers.scale_amount_max = 0.035
	embers.scale_amount_curve = _fade_out_curve()
	embers.color = Color(1.0, 0.55, 0.18)
	embers.mesh = _glow_quad(Color(1.0, 0.6, 0.2))
	embers.local_coords = true
	embers.position = Vector3(0, 0.2 * flame_scale, 0)
	return embers


## Small unshaded emissive billboard quad shared by flame and ember particles.
func _glow_quad(emission: Color) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = 1.6
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = material
	return quad


func _fade_out_curve() -> Curve:
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	return curve
