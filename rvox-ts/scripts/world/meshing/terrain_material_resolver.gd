class_name TerrainMaterialResolver
extends RefCounted

const TERRAIN_SHADER := preload("res://scripts/world/meshing/shaders/terrain_array.gdshader")

const OVERLAY_WET_LAYER := &"overlay_wet"
const OVERLAY_MUD_LAYER := &"overlay_mud"
const OVERLAY_SNOW_LAYER := &"overlay_snow"
const OVERLAY_DAMAGE_LAYER := &"overlay_damage"

## Builds the single shared ShaderMaterial used for the whole merged
## terrain surface (see ChunkMesher). Overlay layer indices are resolved
## once from the atlas; -1 (not packed yet) tells the shader to skip that
## blend rather than sample a nonexistent array layer.
static func make_terrain_material(atlas: TerrainTextureAtlas, overlay_state: Texture2D, fog_of_war: Texture2D, world_extent: float) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = TERRAIN_SHADER
    material.set_shader_parameter("world_extent", world_extent)
    material.set_shader_parameter("overlay_state", overlay_state)
    material.set_shader_parameter("fog_of_war", fog_of_war)
    if atlas != null:
        material.set_shader_parameter("albedo_array", atlas.albedo_array)
        material.set_shader_parameter("normal_array", atlas.normal_array)
        material.set_shader_parameter("overlay_wet_layer", atlas.layer_index(OVERLAY_WET_LAYER))
        material.set_shader_parameter("overlay_mud_layer", atlas.layer_index(OVERLAY_MUD_LAYER))
        material.set_shader_parameter("overlay_snow_layer", atlas.layer_index(OVERLAY_SNOW_LAYER))
        material.set_shader_parameter("overlay_damage_layer", atlas.layer_index(OVERLAY_DAMAGE_LAYER))
    return material

static func make_debug_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.45, 0.65, 0.35)
    return material
