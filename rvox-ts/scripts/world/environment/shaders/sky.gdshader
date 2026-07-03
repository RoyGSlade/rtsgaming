shader_type sky;

// Colors/directions/factors are pushed as explicit uniforms from
// SunMoonRig (via game_main.gd) every frame rather than read through
// Godot's LIGHT0-3 sky built-ins — this project already computes this
// exact data for its own DirectionalLight3D sun/moon, and explicit
// uniforms avoid depending on undocumented LIGHT slot assignment order.
// Math (gradient/sun-glow/moon-glow/stars/clouds) ported from
// waterLightCode.md, adapted from WebGL's Z-forward raymarch convention
// to Godot's Y-up EYEDIR.

uniform vec3 sky_top_color : source_color = vec3(0.05, 0.24, 0.68);
uniform vec3 sky_horizon_color : source_color = vec3(0.42, 0.62, 0.90);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.80);
uniform vec3 moon_color : source_color = vec3(0.45, 0.55, 0.9);
uniform vec3 fog_color : source_color = vec3(0.58, 0.72, 0.90);

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);

uniform float sun_glow : hint_range(0.0, 1.0) = 1.0;
uniform float moon_glow : hint_range(0.0, 1.0) = 0.0;
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform float storm_amount : hint_range(0.0, 1.0) = 0.0;

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

float starField(vec2 uv) {
    vec2 gv = floor(uv);
    vec2 lv = fract(uv) - 0.5;

    float h = hash(gv);
    float size = mix(0.012, 0.0025, h);
    float d = length(lv + vec2(hash(gv + 3.1) - 0.5, hash(gv + 7.3) - 0.5) * 0.25);
    float star = smoothstep(size, 0.0, d);
    star *= smoothstep(0.82, 1.0, h);
    return star;
}

void sky() {
    vec3 dir = EYEDIR;
    float h = clamp(dir.y, 0.0, 1.0);
    vec3 col = mix(sky_horizon_color, sky_top_color, pow(h, 0.38));

    float cloud_band = noise(dir.x * 5.5 + vec2(dir.y * 3.0, TIME * 0.015));
    float cloud_band2 = noise(dir.x * 8.0 - vec2(dir.y * 4.0, TIME * 0.010));
    float clouds = smoothstep(0.62, 0.86, cloud_band * 0.65 + cloud_band2 * 0.35);
    clouds *= smoothstep(-0.02, 0.24, dir.y);
    clouds *= 0.08 + storm_amount * 0.18;

    vec3 cloud_color = mix(vec3(1.0, 0.82, 0.65), vec3(0.42, 0.48, 0.56), storm_amount);
    col = mix(col, mix(col * 0.97, cloud_color, 0.35), clouds);

    float sd = max(dot(dir, sun_direction), 0.0);
    col += sun_color * pow(sd, 380.0) * 6.8 * sun_glow;
    col += sun_color * pow(sd, 22.0) * 0.20 * sun_glow;
    col += sun_color * pow(sd, 5.0) * 0.09 * sun_glow;

    float sun_disk = smoothstep(0.99925, 0.99995, dot(dir, sun_direction));
    col += sun_color * sun_disk * 2.6 * sun_glow;

    float horizon_band = exp(-abs(dir.y) * 24.0);
    col += sun_color * horizon_band * 0.11 * sun_glow;

    float md = max(dot(dir, moon_direction), 0.0);
    col += moon_color * pow(md, 820.0) * 7.4 * moon_glow;
    col += moon_color * pow(md, 6.0) * 0.045 * moon_glow;

    if (night_amount > 0.02) {
        vec2 star_uv = dir.xz / max(0.12, dir.y + 1.6);
        star_uv *= 140.0;
        float stars = starField(star_uv) + starField(star_uv * 0.55 + 11.7) * 0.65;
        stars *= smoothstep(0.02, 0.26, dir.y);
        stars *= (1.0 - storm_amount * 0.85);
        col += vec3(0.80, 0.88, 1.0) * stars * night_amount * 0.82;
    }

    float horizon_mist = exp(-abs(dir.y) * mix(38.0, 22.0, storm_amount));
    col += fog_color * horizon_mist * (0.09 + storm_amount * 0.10);

    col = mix(col, col * vec3(0.91, 0.94, 0.98), storm_amount * 0.22);

    COLOR = clamp(col, 0.0, 1.0);
}
