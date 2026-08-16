class_name MinimapGenerator
extends RefCounted

## Builds a top-down Image of a chunk by sampling each column's surface
## block color (BlockDefinition.albedo_color — already set on every block,
## no separate minimap palette needed). O(map area) — call once (e.g. on
## world generation), not per-frame; see color_for_column for a per-cell
## incremental update.
func build_image(chunk: ChunkData, block_registry: BlockRegistry) -> Image:
    var image := Image.create(chunk.chunk_size, chunk.chunk_size, false, Image.FORMAT_RGBA8)
    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            image.set_pixel(x, z, color_for_column(chunk, block_registry, x, z))
    return image

## Single-column version of build_image's per-pixel sample, for callers
## (fog-of-war reveal) that only need to refresh a handful of newly
## revealed cells rather than rebuild the whole map image.
func color_for_column(chunk: ChunkData, block_registry: BlockRegistry, x: int, z: int) -> Color:
    var height := chunk.get_surface_height(x, z)
    var block_id := chunk.get_block(x, height, z)
    return _color_for_block(block_id, block_registry)

func _color_for_block(block_id: StringName, block_registry: BlockRegistry) -> Color:
    if block_registry != null:
        var definition := block_registry.get_block(block_id)
        if definition != null:
            return definition.albedo_color
    return Color(0.8, 0.15, 0.8)
