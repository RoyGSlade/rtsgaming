class_name MinimapGenerator
extends RefCounted

## Builds a top-down Image of a chunk by sampling each column's surface
## block color (BlockDefinition.albedo_color — already set on every block,
## no separate minimap palette needed).
func build_image(chunk: ChunkData, block_registry: BlockRegistry) -> Image:
    var image := Image.create(chunk.chunk_size, chunk.chunk_size, false, Image.FORMAT_RGBA8)
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            var height := chunk.get_surface_height(x, z)
            var block_id := chunk.get_block(x, height, z)
            image.set_pixel(x, z, _color_for_block(block_id, block_registry))
    return image

func _color_for_block(block_id: StringName, block_registry: BlockRegistry) -> Color:
    if block_registry != null:
        var definition := block_registry.get_block(block_id)
        if definition != null:
            return definition.albedo_color
    return Color(0.8, 0.15, 0.8)
