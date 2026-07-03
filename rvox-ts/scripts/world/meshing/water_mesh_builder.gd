class_name WaterMeshBuilder
extends RefCounted

## Builds the visible water surface: one top quad per WaterCell, at
## cell.surface_y. No side/bottom faces — this game's fixed-pitch orbit
## camera rarely sees water from the side, and skipping them avoids real
## meshing complexity (basin rims, cross-chunk neighbors) for limited
## visual payoff. Vertex winding/UV layout matches ChunkMesher's existing
## top face (FACE_DEFS[2]) for consistency.

const TOP_VERTS := [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)]
const TOP_UV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
const TOP_INDICES := [0, 2, 1, 0, 3, 2]
const TOP_NORMAL := Vector3(0, 1, 0)

func build_water_mesh(chunk: ChunkData) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var vertex_count := 0

    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            var cell: WaterCell = chunk.get_water_cell(x, z)
            if cell == null:
                continue
            _emit_top_quad(st, Vector3(x, cell.surface_y, z))
            vertex_count += 6

    var mesh := ArrayMesh.new()
    if vertex_count == 0:
        return mesh
    st.generate_normals()
    st.commit(mesh)
    return mesh

func _emit_top_quad(st: SurfaceTool, origin: Vector3) -> void:
    for idx in TOP_INDICES:
        st.set_normal(TOP_NORMAL)
        st.set_uv(TOP_UV[idx])
        st.add_vertex(origin + TOP_VERTS[idx])
