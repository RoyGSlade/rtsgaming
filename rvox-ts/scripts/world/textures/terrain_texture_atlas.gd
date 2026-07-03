@tool
class_name TerrainTextureAtlas
extends Resource

## Packed terrain texture arrays plus the layer-name -> layer-index mapping
## shared by both arrays. Built by TextureArrayPacker, consumed by
## TerrainMaterialResolver and ChunkMesher.

@export var layer_names: PackedStringArray = PackedStringArray()
@export var albedo_array: Texture2DArray
@export var normal_array: Texture2DArray

var _index_cache: Dictionary = {}


func layer_index(layer_name: StringName) -> int:
    if _index_cache.size() != layer_names.size():
        _rebuild_index_cache()
    return _index_cache.get(String(layer_name), -1)


func _rebuild_index_cache() -> void:
    _index_cache.clear()
    for i in layer_names.size():
        _index_cache[layer_names[i]] = i
