shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Per-face albedo/normal, selected by the UV2.x layer index ChunkMesher
// bakes into each vertex (see TerrainTextureAtlas.layer_index).
// filter_nearest_mipmap + repeat_disable is where "nearest filtering with
// mipmaps, repeat off" actually lives for these 64x64 pixel-art layers —
// Godot has no such per-file texture import setting, only sampler hints.
uniform sampler2DArray albedo_array : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2DArray normal_array : hint_normal, filter_nearest_mipmap, repeat_disable;

// Per-cell (chunk_size x chunk_size) runtime state, sampled by world XZ.
// overlay_state: R=damage, G=wetness, B=mud, A=snow, each 0..1 blend weight.
// fog_of_war: R=explored (0=unexplored, 1=explored).
uniform sampler2D overlay_state : filter_linear, repeat_disable;
uniform sampler2D fog_of_war : filter_linear, repeat_disable;

// Layer indices for the overlay swatches, resolved once from
// TerrainTextureAtlas.layer_index(); -1 means "not packed yet, skip".
uniform int overlay_wet_layer = -1;
uniform int overlay_mud_layer = -1;
uniform int overlay_snow_layer = -1;
uniform int overlay_damage_layer = -1;

uniform float world_extent = 32.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.9;
uniform float unexplored_darken : hint_range(0.0, 1.0) = 0.15;

varying flat float layer;
varying vec2 world_xz;

void vertex() {
    layer = UV2.x;
    world_xz = VERTEX.xz;
}

void fragment() {
    vec3 array_uv = vec3(UV, layer);
    vec4 base = texture(albedo_array, array_uv);
    vec3 albedo = base.rgb;

    vec2 cell_uv = clamp(world_xz / world_extent, 0.0, 1.0);
    vec4 state = texture(overlay_state, cell_uv);

    if (overlay_wet_layer >= 0) {
        vec3 wet = texture(albedo_array, vec3(UV, float(overlay_wet_layer))).rgb;
        albedo = mix(albedo, wet, state.g);
    }
    if (overlay_mud_layer >= 0) {
        vec3 mud = texture(albedo_array, vec3(UV, float(overlay_mud_layer))).rgb;
        albedo = mix(albedo, mud, state.b);
    }
    if (overlay_snow_layer >= 0) {
        vec3 snow = texture(albedo_array, vec3(UV, float(overlay_snow_layer))).rgb;
        albedo = mix(albedo, snow, state.a);
    }
    if (overlay_damage_layer >= 0) {
        vec3 damage = texture(albedo_array, vec3(UV, float(overlay_damage_layer))).rgb;
        albedo = mix(albedo, damage, state.r);
    }

    float explored = texture(fog_of_war, cell_uv).r;
    albedo *= mix(unexplored_darken, 1.0, explored);

    ALBEDO = albedo;
    ALPHA = base.a;
    NORMAL_MAP = texture(normal_array, array_uv).rgb;
    ROUGHNESS = roughness_value;
}
