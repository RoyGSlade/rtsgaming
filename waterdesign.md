# Best approach

For your kind of game, the best water setup is:

```text id="0ap0g8"
Voxel/gameplay water
= simple grid data: depth, flow direction, water level

Visual water
= chunked water surface mesh + shader

Extra effects
= foam, rain ripples, splashes, wet ground, sound
```

Do **not** simulate every water vertex or every droplet in GDScript unless your goal is to make a very wet PowerPoint presentation.

Godot’s procedural mesh/shader path is strong enough for good water: use a `MeshInstance3D` water surface, a `ShaderMaterial`, moving normal maps, depth-based color, edge foam, and optional SSR/reflection probes. Spatial shaders expose outputs like `ALBEDO`, `ALPHA`, `ROUGHNESS`, `SPECULAR`, and `NORMAL_MAP`, which are exactly the knobs water needs. Godot also supports depth texture sampling through `hint_depth_texture`, which is useful for shoreline foam and depth tinting. ([Godot Engine documentation][1])

---

# The winning setup

## Scene structure

```text id="n5r9qf"
WaterChunk.tscn
└── WaterChunk : Node3D
    ├── WaterSurface : MeshInstance3D
    ├── SplashParticles : GPUParticles3D
    └── FoamParticles : GPUParticles3D optional
```

For a voxel world:

```text id="jms4le"
Chunk
├── Terrain mesh
├── Water top-surface mesh
├── Water side faces if exposed
└── Water metadata grid
```

Your water data should track:

```gdscript id="n5hwe1"
class_name WaterCell
extends Resource

var level: int = 0 # 0-8
var flow_dir: Vector3i = Vector3i.ZERO
var is_source: bool = false
var is_ocean: bool = false
```

Then the shader makes it pretty. The simulation makes it useful.

---

# Water visual stack

You want these features, in this order:

| Feature               |     Importance |        Cost | Notes                            |
| --------------------- | -------------: | ----------: | -------------------------------- |
| Scrolling normal maps |      Very high |         Low | Makes water feel alive           |
| Fresnel rim           |      Very high |         Low | Makes glancing angles reflective |
| Depth color           |           High |      Medium | Shallow = lighter, deep = darker |
| Edge foam             |           High |      Medium | Makes shorelines look good       |
| Vertex waves          |         Medium |  Low/medium | Good for rivers/lakes            |
| SSR/reflections       |    Medium/high | Medium/high | Nice but has Godot limitations   |
| Planar reflections    |  High-end only |        High | Best-looking, expensive          |
| Real fluid sim        | Only if needed |        High | Gameplay-first, not visual-first |

Godot’s built-in Screen-Space Reflections are available in **Forward+**, not Mobile or Compatibility, and are good for contact reflections like objects near water. But SSR has screen-space limits and only reflects what is visible to the camera. Godot also notes that transparent materials are not reflected by SSR because they do not write to the depth buffer, which matters because water usually wants transparency. Annoying, yes. Technically coherent, also yes. ([Godot Engine documentation][2])

---

# Recommended water shader

Create:

```text id="irnpck"
res://world/shaders/water.gdshader
```

Use this as your starter shader:

```glsl id="kcabva"
shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.18, 0.55, 0.65);
uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.26);
uniform vec3 foam_color : source_color = vec3(0.85, 0.95, 1.0);

uniform sampler2D normal_map_a : hint_normal;
uniform sampler2D normal_map_b : hint_normal;

uniform sampler2D depth_texture : hint_depth_texture;

uniform float wave_speed_a = 0.035;
uniform float wave_speed_b = 0.022;
uniform float normal_strength = 0.55;

uniform float alpha_amount = 0.72;
uniform float roughness_amount = 0.035;
uniform float specular_amount = 0.8;

uniform float wave_height = 0.08;
uniform float wave_scale = 1.8;
uniform float foam_distance = 1.15;
uniform float depth_fade_distance = 8.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float wave_a = sin((VERTEX.x + TIME * 1.7) * wave_scale);
	float wave_b = cos((VERTEX.z + TIME * 1.2) * wave_scale * 0.73);

	VERTEX.y += (wave_a + wave_b) * wave_height;
}

float get_scene_depth(vec2 screen_uv) {
	float depth = texture(depth_texture, screen_uv).x;

	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;

	return -view.z;
}

void fragment() {
	vec2 uv_a = UV * 2.5 + vec2(TIME * wave_speed_a, TIME * wave_speed_a * 0.4);
	vec2 uv_b = UV * 4.0 + vec2(-TIME * wave_speed_b * 0.7, TIME * wave_speed_b);

	vec3 n_a = texture(normal_map_a, uv_a).rgb * 2.0 - 1.0;
	vec3 n_b = texture(normal_map_b, uv_b).rgb * 2.0 - 1.0;
	vec3 mixed_normal = normalize(mix(n_a, n_b, 0.5));

	NORMAL_MAP = mixed_normal.xy * normal_strength;

	float scene_depth = get_scene_depth(SCREEN_UV);
	float water_depth = clamp(scene_depth - FRAGCOORD.z, 0.0, depth_fade_distance);
	float depth_factor = clamp(water_depth / depth_fade_distance, 0.0, 1.0);

	vec3 water_color = mix(shallow_color, deep_color, depth_factor);

	float foam_mask = 1.0 - smoothstep(0.0, foam_distance, water_depth);
	float foam_noise = sin(world_pos.x * 6.0 + TIME * 2.0) * 0.5 + 0.5;
	foam_mask *= smoothstep(0.35, 0.75, foam_noise);

	ALBEDO = mix(water_color, foam_color, foam_mask);

	ROUGHNESS = roughness_amount;
	SPECULAR = specular_amount;
	ALPHA = alpha_amount;
}
```

## Important note

The `FRAGCOORD.z` depth comparison above is a simplified starting point. For better depth accuracy, convert both water and scene positions into linear/view-space depth. Godot’s docs explain that Godot 4.3+ uses a reversed-Z depth buffer and that depth texture values are nonlinear, so serious depth effects should be linearized with `INV_PROJECTION_MATRIX`. ([Godot Engine documentation][3])

Translation from engine-speak: if foam looks weird, your depth math is lying. Shocking development.

---

# Normal maps

Use two seamless water normal maps:

```text id="2tba0l"
normal_map_a: broad waves
normal_map_b: tiny ripples
```

Import settings:

```text id="agc8nu"
Repeat: Enabled
Filter: Enabled
Mipmaps: Enabled
Normal Map: Enabled
```

Godot’s material docs note that normal maps affect lighting without changing geometry, which is exactly why they are perfect for water ripples. They also note Godot expects OpenGL-style normal maps, so if the water looks inverted, flip the green/Y channel. ([Godot Engine documentation][4])

---

# Better shader features to add next

## 1. Fresnel

Add this in `fragment()`:

```glsl id="qva97l"
float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
ALBEDO = mix(ALBEDO, vec3(0.75, 0.9, 1.0), fresnel * 0.35);
ALPHA = mix(alpha_amount, 0.95, fresnel);
```

This makes water more reflective at glancing angles.

## 2. Flow direction

For rivers, pass flow direction from your chunk/cell data:

```glsl id="g9we30"
uniform vec2 flow_direction = vec2(1.0, 0.0);
uniform float flow_speed = 0.05;
```

Then replace scrolling UVs with:

```glsl id="g61zcm"
vec2 flow = normalize(flow_direction) * TIME * flow_speed;
vec2 uv_a = UV * 2.5 + flow;
vec2 uv_b = UV * 4.0 - flow * 0.6;
```

## 3. Rain ripples

When raining, increase small ripple strength:

```glsl id="2d59u5"
uniform float rain_intensity = 0.0;

NORMAL_MAP *= normal_strength + rain_intensity * 0.35;
ROUGHNESS = mix(roughness_amount, 0.12, rain_intensity);
```

Then your `RainController` can update the shader param.

---

# Water mesh generation

For Minecraft-like water, do not make one giant plane. Generate water surfaces per chunk.

```text id="wgcweq"
For each water cell:
  if top is visible:
    add top quad
  if side is exposed:
    add side quad
  if neighboring water level is lower:
    slope or stair-step the surface
```

Simple top quad:

```gdscript id="1sp1pg"
func add_water_top(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	x: int,
	y: int,
	z: int,
	level: float
) -> void:
	var base_index := vertices.size()
	var h := y + level

	vertices.append(Vector3(x, h, z))
	vertices.append(Vector3(x + 1, h, z))
	vertices.append(Vector3(x + 1, h, z + 1))
	vertices.append(Vector3(x, h, z + 1))

	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(1, 0))
	uvs.append(Vector2(1, 1))
	uvs.append(Vector2(0, 1))

	indices.append_array([
		base_index, base_index + 1, base_index + 2,
		base_index, base_index + 2, base_index + 3
	])
```

Then commit it:

```gdscript id="mmfqep"
func build_water_mesh(
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)

	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
```

---

# Recommended render settings

Use **Forward+** for the prettiest water, because SSR is Forward+ only. ([Godot Engine documentation][2])

```text id="la3e18"
Project Settings:
  Rendering Method: Forward+
  Environment:
    SSR: On if you can afford it
    Glow: On, low strength
    Fog: Optional, good for lakes/oceans
    Tonemapping: Filmic/AgX-style look
```

For the water material:

```text id="egykxr"
Transparency: enabled through shader ALPHA
Roughness: 0.02 - 0.12
Specular: 0.6 - 1.0
Metallic: 0.0
Normal strength: 0.3 - 0.8
Alpha: 0.55 - 0.85
```

---

# Reflection options

## Cheap

```text id="s5rjqr"
Sky reflection + normal maps + Fresnel
```

Best for rivers, ponds, and voxel water.

## Medium

```text id="m8f8j4"
ReflectionProbe near important lakes/cities
SSR enabled in Forward+
```

Good enough for most games.

## Expensive but pretty

```text id="cl96wc"
Planar reflection using SubViewport + mirrored camera
```

Best for still lakes, ocean, palace pools, dramatic “the moon reflects off the blood river” nonsense.

Do not use planar reflection everywhere. Use it for hero areas only.

---

# What I’d build for your game

Given your voxel/RTS direction, I’d build three water types:

## 1. Block water

```text id="v4kkx8"
Used for:
  rivers
  lakes
  shorelines
  canals
  gameplay flow

Rendering:
  chunk mesh + water shader

Simulation:
  level 0-8
  flow direction
  source blocks
```

## 2. Decorative water plane

```text id="4sechk"
Used for:
  distant ocean
  huge lakes
  background scenery

Rendering:
  large subdivided plane
  Gerstner/vertex waves
  no simulation
```

## 3. Wetness/rain layer

```text id="ro3xbx"
Used for:
  rain
  puddles
  muddy roads
  wet roofs

Rendering:
  material parameter change
  roughness down
  darker albedo
  ripple normal map
```

That gives you water that looks good, supports gameplay, and doesn’t require inventing a fake PhD in computational fluid dynamics.

[1]: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html "Spatial shaders — Godot Engine (stable) documentation in English"
[2]: https://docs.godotengine.org/en/stable/tutorials/3d/environment_and_post_processing.html "Environment and post-processing — Godot Engine (stable) documentation in English"
[3]: https://docs.godotengine.org/en/latest/tutorials/shaders/advanced_postprocessing.html "Advanced post-processing — Godot Engine (latest) documentation in English"
[4]: https://docs.godotengine.org/en/latest/tutorials/3d/standard_material_3d.html "Standard Material 3D and ORM Material 3D — Godot Engine (latest) documentation in English"
