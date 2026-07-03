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

## All opaque blocks share a single surface/material now that texture
## selection happens per-face via a UV2-encoded Texture2DArray layer index
## (see TerrainTextureAtlas / terrain_array.gdshader) rather than one
## StandardMaterial3D per block id. atlas may be null (e.g. before the
## "Rebuild Texture Array" editor step has ever run) — faces still mesh
## correctly, just with layer index 0 until an atlas exists.
func build_mesh(chunk: ChunkData, block_registry: BlockRegistry = null, atlas: TerrainTextureAtlas = null) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertex_count := 0

	for x in chunk.chunk_size:
		for y in chunk.max_height:
			for z in chunk.chunk_size:
				var block_id := chunk.get_block(x, y, z)
				if block_id == &"air":
					continue
				if block_id == &"water":
					continue # water should use its own transparent pass later
				var definition: BlockDefinition = block_registry.get_block(block_id) if block_registry != null else null
				vertex_count += _emit_visible_faces(st, chunk, x, y, z, definition, atlas)

	var mesh := ArrayMesh.new()
	if vertex_count == 0:
		return mesh
	st.generate_normals()
	st.commit(mesh)
	return mesh

func _emit_visible_faces(st: SurfaceTool, chunk: ChunkData, x: int, y: int, z: int, definition: BlockDefinition, atlas: TerrainTextureAtlas) -> int:
	var emitted := 0
	for face_index in FACE_DEFS.size():
		var face: Dictionary = FACE_DEFS[face_index]
		if FaceCulling.should_render_face(chunk, x, y, z, face["offset"]):
			var layer := _resolve_layer_index(definition, atlas, face_index)
			_emit_quad(st, Vector3(x, y, z), face["verts"], face["normal"], layer)
			emitted += 6
	return emitted

func _resolve_layer_index(definition: BlockDefinition, atlas: TerrainTextureAtlas, face_index: int) -> int:
	if definition == null or atlas == null:
		return 0
	var layer := atlas.layer_index(definition.get_face_layer_name(face_index))
	return maxi(layer, 0)

func _emit_quad(st: SurfaceTool, origin: Vector3, verts: Array, normal: Vector3, layer_index: int) -> void:
	var uv := [Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)]
	var uv2 := Vector2(layer_index, 0.0)
	# Godot's front faces use clockwise winding in screen space.
	var indices := [0, 2, 1, 0, 3, 2]
	for idx in indices:
		st.set_normal(normal)
		st.set_uv(uv[idx])
		st.set_uv2(uv2)
		st.add_vertex(origin + verts[idx])
