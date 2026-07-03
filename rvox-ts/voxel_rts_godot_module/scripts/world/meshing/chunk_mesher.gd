class_name ChunkMesher
extends RefCounted

const FACE_DEFS := [
    {"normal": Vector3(1, 0, 0), "offset": Vector3i(1, 0, 0), "verts": [Vector3(1,0,0), Vector3(1,1,0), Vector3(1,1,1), Vector3(1,0,1)]},
    {"normal": Vector3(-1, 0, 0), "offset": Vector3i(-1, 0, 0), "verts": [Vector3(0,0,1), Vector3(0,1,1), Vector3(0,1,0), Vector3(0,0,0)]},
    {"normal": Vector3(0, 1, 0), "offset": Vector3i(0, 1, 0), "verts": [Vector3(0,1,1), Vector3(1,1,1), Vector3(1,1,0), Vector3(0,1,0)]},
    {"normal": Vector3(0, -1, 0), "offset": Vector3i(0, -1, 0), "verts": [Vector3(0,0,0), Vector3(1,0,0), Vector3(1,0,1), Vector3(0,0,1)]},
    {"normal": Vector3(0, 0, 1), "offset": Vector3i(0, 0, 1), "verts": [Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1), Vector3(0,0,1)]},
    {"normal": Vector3(0, 0, -1), "offset": Vector3i(0, 0, -1), "verts": [Vector3(0,0,0), Vector3(0,1,0), Vector3(1,1,0), Vector3(1,0,0)]},
]

func build_mesh(chunk: ChunkData) -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    for x in chunk.chunk_size:
        for y in chunk.max_height:
            for z in chunk.chunk_size:
                var block_id := chunk.get_block(x, y, z)
                if block_id == &"air":
                    continue
                if block_id == &"water":
                    continue # water should use its own transparent pass later
                _emit_visible_faces(st, chunk, x, y, z)

    st.generate_normals()
    return st.commit()

func _emit_visible_faces(st: SurfaceTool, chunk: ChunkData, x: int, y: int, z: int) -> void:
    for face in FACE_DEFS:
        if FaceCulling.should_render_face(chunk, x, y, z, face["offset"]):
            _emit_quad(st, Vector3(x, y, z), face["verts"], face["normal"])

func _emit_quad(st: SurfaceTool, origin: Vector3, verts: Array, normal: Vector3) -> void:
    var uv := [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]
    # Godot's front faces use clockwise winding in screen space.
    var indices := [0, 2, 1, 0, 3, 2]
    for idx in indices:
        st.set_normal(normal)
        st.set_uv(uv[idx])
        st.add_vertex(origin + verts[idx])
