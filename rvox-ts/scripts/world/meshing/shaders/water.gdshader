shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

// All lighting/reflection math below runs in world space (not Godot's
// usual view-space NORMAL/VIEW convention) and writes straight to ALBEDO
// as additive terms, mirroring how the reference shader (waterLightCode.md)
// computes final pixel color directly rather than feeding a lighting
// pipeline — this sidesteps needing tangent-space NORMAL_MAP data (the
// water mesh only has normals/UVs, no generated tangents) since the wave
// normal, sky reflection, and sun/moon specular are all derived from the
// same world-space wave_height() function and combined by hand.

// Per-cell (chunk_size x chunk_size) static water depth (0..1, from
// WaterDepthMap) and the shared fog-of-war explored mask, both sampled by
// world XZ the same way terrain_array.gdshader already does.
uniform sampler2D water_depth : filter_linear, repeat_disable;
uniform sampler2D fog_of_war : filter_linear, repeat_disable;

// Sky/sun/moon colors + directions, pushed every frame from SunMoonRig via
// game_main.gd — the same palette sky.gdshader renders, so water's
// reflection tint and specular highlights stay visually consistent with
// the actual sky instead of hardcoded colors.
uniform vec3 sky_top_color : source_color = vec3(0.42, 0.62, 0.90);
uniform vec3 sky_horizon_color : source_color = vec3(0.42, 0.62, 0.90);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.80);
uniform vec3 moon_color : source_color = vec3(0.45, 0.55, 0.9);
uniform vec3 sea_deep_color : source_color = vec3(0.03, 0.14, 0.34);
uniform vec3 sea_shallow_color : source_color = vec3(0.09, 0.38, 0.60);
uniform vec3 sun_direction = vec3(0.3, 0.7, 0.2);
uniform vec3 moon_direction = vec3(-0.3, -0.7, -0.2);
uniform float sun_glow : hint_range(0.0, 1.0) = 1.0;
uniform float moon_glow : hint_range(0.0, 1.0) = 0.0;

uniform vec3 foam_color : source_color = vec3(0.85, 0.95, 1.0);

uniform float alpha_amount : hint_range(0.0, 1.0) = 0.78;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.05;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.8;

// Tuned for this project's block-scale world (1 unit = 1 voxel) and a
// fairly distant RTS orbit camera — the reference shader's values assumed
// a normalized ray-marching coordinate space and were nearly invisible
// here (a lake a handful of blocks wide barely covered a fraction of one
// wave cycle, and 0.09 units of bob is under a tenth of a block height).
uniform float wave_scale = 1.2;
uniform float wave_amp = 0.35;
uniform float foam_band : hint_range(0.0, 1.0) = 0.12;

uniform float world_extent = 32.0;
uniform float unexplored_darken : hint_range(0.0, 1.0) = 0.15;

// Set by RainController via game_main.gd — bigger waves + more foam while
// it's raining ("rain ripples" from the design doc).
uniform float rain_intensity : hint_range(0.0, 1.0) = 0.0;

varying vec2 world_xz;
varying vec3 world_pos;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Multi-octave swell + noise height field — same shape as the reference
// shader's waveH(), reused for both vertex displacement and the analytic
// normal (finite differences of this same function).
float wave_height(vec2 p, float t, float amp, float storm) {
    float h = 0.0;

    vec2 swell1 = normalize(vec2(1.0, 0.28));
    vec2 swell2 = normalize(vec2(-0.48, 0.88));
    vec2 swell3 = normalize(vec2(0.82, -0.16));

    float d1 = dot(p, swell1);
    float d2 = dot(p, swell2);
    float d3 = dot(p, swell3);

    h += amp * 0.66 * sin(d1 * 0.42 + t * 0.38);
    h += amp * 0.22 * sin(d1 * 0.94 - t * 0.62);
    h += amp * 0.14 * sin(d2 * 1.18 - t * 0.82);
    h += amp * 0.09 * sin(d3 * 1.82 + t * 1.04);

    h += amp * (0.11 + storm * 0.07) * sin(p.x * 1.45 - t * 0.76 + p.y * 0.66);
    h += amp * (0.07 + storm * 0.05) * sin(p.x * 2.85 + t * 1.06 - p.y * 0.52);

    float micro = noise(p * 4.0 + vec2(t * 0.18, t * 0.06)) - 0.5;
    h += micro * amp * (0.10 + storm * 0.08);

    return h;
}

void vertex() {
    world_xz = VERTEX.xz;
    VERTEX.y += wave_height(VERTEX.xz * wave_scale, TIME, wave_amp, rain_intensity);
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 wp = world_xz * wave_scale;
    float e = 0.05;

    float h_l = wave_height(wp - vec2(e, 0.0), TIME, wave_amp, rain_intensity);
    float h_r = wave_height(wp + vec2(e, 0.0), TIME, wave_amp, rain_intensity);
    float h_d = wave_height(wp - vec2(0.0, e), TIME, wave_amp, rain_intensity);
    float h_u = wave_height(wp + vec2(0.0, e), TIME, wave_amp, rain_intensity);
    float h_c = wave_height(wp, TIME, wave_amp, rain_intensity);

    vec3 n = normalize(vec3(-(h_r - h_l) / (2.0 * e), 1.0, -(h_u - h_d) / (2.0 * e)));
    vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);

    vec3 refl = reflect(-view_dir, n);
    float rh = clamp(refl.y, 0.0, 1.0);
    vec3 refl_sky = mix(sky_horizon_color, sky_top_color, pow(rh, 0.42));

    float fresnel = pow(1.0 - clamp(dot(n, view_dir), 0.0, 1.0), 4.0);

    vec2 cell_uv = clamp(world_xz / world_extent, 0.0, 1.0);
    float water_depth_value = texture(water_depth, cell_uv).r;
    vec3 water_color = mix(sea_shallow_color, sea_deep_color, water_depth_value);

    vec3 albedo = mix(water_color, refl_sky, 0.15 + fresnel * 0.34);

    float sun_spec = pow(max(dot(reflect(-sun_direction, n), view_dir), 0.0), 200.0);
    albedo += sun_color * sun_spec * 1.1 * sun_glow;

    float moon_spec = pow(max(dot(reflect(-moon_direction, n), view_dir), 0.0), 400.0);
    albedo += moon_color * moon_spec * 0.35 * moon_glow;

    float curvature = h_r + h_l + h_u + h_d - 4.0 * h_c;
    float wave_foam = clamp(curvature * (32.0 + rain_intensity * 16.0), 0.0, 1.0);
    float shore_foam = 1.0 - smoothstep(0.0, foam_band, water_depth_value);
    float foam_mask = clamp(wave_foam + shore_foam, 0.0, 1.0);
    albedo = mix(albedo, foam_color, foam_mask);

    float explored = texture(fog_of_war, cell_uv).r;
    albedo *= mix(unexplored_darken, 1.0, explored);

    ALBEDO = albedo;
    ALPHA = mix(alpha_amount, 0.95, fresnel);
    ROUGHNESS = mix(roughness_amount, 0.12, rain_intensity);
    SPECULAR = specular_amount;
}
