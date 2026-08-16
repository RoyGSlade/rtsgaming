class_name FaceCulling
extends RefCounted

static func should_render_face(chunk: ChunkData, x: int, y: int, z: int, neighbor_offset: Vector3i) -> bool:
    var n := Vector3i(x, y, z) + neighbor_offset
    if n.y < 0:
        return false # the world's underside is never visible — skip its quads
    if not chunk.is_in_bounds(n.x, n.y, n.z):
        return true
    var neighbor_id := chunk.get_block(n.x, n.y, n.z)
    return neighbor_id == &"air" or neighbor_id == &"water" or neighbor_id == &"oak_leaves"
