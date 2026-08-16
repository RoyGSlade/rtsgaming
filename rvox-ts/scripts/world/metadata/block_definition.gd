class_name BlockDefinition
extends Resource

@export var id: StringName = &"air"
@export var display_name: String = "Air"
@export var category: StringName = &"terrain"

@export var solid: bool = false
@export var transparent: bool = true
@export var walkable: bool = false
@export var buildable: bool = false
@export var diggable: bool = false
@export var fluid: bool = false

@export var hardness: float = 0.0
@export var fertility: float = 0.0
@export var moisture: float = 0.0
@export var flammability: float = 0.0
@export var path_cost: float = 1.0

@export_group("World Forge")
## Reusable geometry profile. Existing definitions default to a full cube.
@export var shape_id: StringName = &"cube"
## Declarative interaction tags such as flammable, heat_sink, conductive, or waterloggable.
@export var rule_tags: PackedStringArray = []
## Item delivered by logistics workers when this block is constructed.
@export var construction_item_id: StringName = &""
@export var construction_item_count: int = 1
@export var durability: float = 100.0

@export var harvest_resource_id: StringName = &""
@export var harvest_amount: int = 0
@export var tool_required: StringName = &""

@export var mesh_id: int = -1
@export var material_id: StringName = &"default"
@export_group("Visuals")
@export var albedo_texture: Texture2D
@export var albedo_color: Color = Color.WHITE
@export_range(0.1, 16.0, 0.1) var texture_scale: float = 1.0
@export var roughness: float = 0.9

@export_group("Light Emission")
## Blocks with light_energy > 0 are light sources (torch, lantern, brazier):
## renderers spawn an OmniLight3D and an emissive material for them.
@export var light_energy: float = 0.0
@export var light_color: Color = Color(1.0, 0.72, 0.38)
@export var light_range: float = 6.0
## Adds a flame particle effect and light flicker on top of the fixture.
@export var flame_effect: bool = false

@export_group("Terrain Texture")
## Layer name into TerrainTextureAtlas for the top (+Y) face.
@export var texture_top: StringName = &""
## Layer name into TerrainTextureAtlas for the bottom (-Y) face.
@export var texture_bottom: StringName = &""
## Layer name into TerrainTextureAtlas for the four side faces.
@export var texture_side: StringName = &""

@export_group("External Asset")
@export var mesh_scene: PackedScene
@export var preview_icon: Texture2D
@export var source_pack: String = ""
@export_multiline var license_note: String = ""

func can_harvest_with(tool_id: StringName) -> bool:
    if harvest_resource_id == &"" or harvest_amount <= 0:
        return false
    if tool_required == &"":
        return true
    return tool_required == tool_id

func blocks_path() -> bool:
    return solid and not walkable

func is_air() -> bool:
    return id == &"air"

## face_index must match ChunkMesher.FACE_DEFS order: 2 is +Y (top),
## 3 is -Y (bottom), everything else is a side face. Falls back to
## texture_side when texture_top/texture_bottom are unset.
func get_face_layer_name(face_index: int) -> StringName:
    if face_index == 2 and texture_top != &"":
        return texture_top
    if face_index == 3 and texture_bottom != &"":
        return texture_bottom
    return texture_side
