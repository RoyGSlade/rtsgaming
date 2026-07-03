@tool
class_name TextureRecipe
extends Resource

## Data-driven description of one procedurally generated terrain texture
## layer. ProceduralTextureGenerator turns this into an albedo PNG (and a
## derived normal-map PNG); TextureArrayPacker packs the results into a
## shared Texture2DArray keyed by layer_name.

enum Pattern {
    SOLID,
    SPECKLE,
    MOTTLE,
    STRIPES,
    GRAIN,
    CRACKS,
}

@export var layer_name: StringName = &""
@export_range(4, 256, 1) var resolution: int = 64
@export var pattern: Pattern = Pattern.SOLID
@export var base_color: Color = Color(0.5, 0.5, 0.5)
@export var accent_color: Color = Color(0.4, 0.4, 0.4)
@export_range(0.0, 1.0, 0.01) var accent_density: float = 0.25
@export var noise_seed: int = 0
@export_range(0.0, 2.0, 0.01) var contrast: float = 1.0
