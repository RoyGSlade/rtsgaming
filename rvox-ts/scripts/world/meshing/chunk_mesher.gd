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

# Quad corners -> two CW triangles (Godot front faces are clockwise).
const QUAD_INDICES := [0, 2, 1, 0, 3, 2]

## All opaque blocks share a single surface/material now that texture
## selection happens per-face via a UV2-encoded Texture2DArray layer index
## (see TerrainTextureAtlas / terrain_array.gdshader) rather than one
## StandardMaterial3D per block id. atlas may be null (e.g. before the
## "Rebuild Texture Array" editor step has ever run) — faces still mesh
## correctly, just with layer index 0 until an atlas exists.
##
## Meshing is O(exposed shell), not O(volume): each column only scans the
## y-band that can possibly show a face — from the lowest neighboring
## surface up to its own surface, widened by any edited cells (trees above,
## dug holes below) in itself or its four neighbors. The untouched deep
## underground is never visited, which is what keeps large maps meshable;
## it gets meshed for real only once digging edits it.
func build_mesh(chunk: ChunkData, block_registry: BlockRegistry = null, atlas: TerrainTextureAtlas = null) -> ArrayMesh:
	return build_region_mesh(chunk, Rect2i(0, 0, chunk.chunk_size, chunk.chunk_size), block_registry, atlas)

## Meshes only the columns inside `region` (in local column coordinates).
## Faces are emitted against true neighbor data even across the region
## border, so adjacent region meshes tile seamlessly.
func build_region_mesh(chunk: ChunkData, region: Rect2i, block_registry: BlockRegistry = null, atlas: TerrainTextureAtlas = null) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	var x_end := mini(region.position.x + region.size.x, chunk.chunk_size)
	var z_end := mini(region.position.y + region.size.y, chunk.chunk_size)
	for x in range(maxi(region.position.x, 0), x_end):
		for z in range(maxi(region.position.y, 0), z_end):
			var bounds := _column_scan_bounds(chunk, x, z)
			for y in range(bounds.x, bounds.y + 1):
				var block_id := chunk.get_block(x, y, z)
				if block_id == &"air":
					continue
				if block_id == &"water":
					continue # water uses its own transparent pass (WaterMeshBuilder)
				var definition: BlockDefinition = block_registry.get_block(block_id) if block_registry != null else null
				_emit_visible_faces(verts, normals, uvs, uv2s, indices, chunk, x, y, z, definition, atlas)

	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Inclusive (lo, hi) y-band a column must scan. Pristine flat ground scans
## a single voxel; cliffs scan down to the lowest adjacent surface so their
## side walls (where buried ore naturally outcrops) still emit; edits widen
## the band by one so faces revealed above/below an edited cell are seen.
## Map-border columns scan to bedrock so the world's edge skirt stays solid.
func _column_scan_bounds(chunk: ChunkData, x: int, z: int) -> Vector2i:
	var size := chunk.chunk_size
	var heightmap := chunk.surface_heightmap
	var ci := z * size + x
	var lo := heightmap[ci]
	var hi := lo
	if chunk.edit_max_y[ci] >= 0:
		lo = mini(lo, chunk.edit_min_y[ci] - 1)
		hi = maxi(hi, chunk.edit_max_y[ci] + 1)

	var at_border := x == 0 or z == 0 or x == size - 1 or z == size - 1
	if at_border:
		lo = 0
	for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx := x + offset.x
		var nz := z + offset.y
		if nx < 0 or nx >= size or nz < 0 or nz >= size:
			continue
		var nci := nz * size + nx
		lo = mini(lo, heightmap[nci])
		if chunk.edit_max_y[nci] >= 0:
			lo = mini(lo, chunk.edit_min_y[nci] - 1)
			hi = maxi(hi, chunk.edit_max_y[nci] + 1)

	return Vector2i(maxi(lo, 0), mini(hi, chunk.max_height - 1))

func _emit_visible_faces(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, uv2s: PackedVector2Array, indices: PackedInt32Array, chunk: ChunkData, x: int, y: int, z: int, definition: BlockDefinition, atlas: TerrainTextureAtlas) -> void:
	var origin := Vector3(x, y, z)
	for face_index in FACE_DEFS.size():
		var face: Dictionary = FACE_DEFS[face_index]
		if not FaceCulling.should_render_face(chunk, x, y, z, face["offset"]):
			continue
		var layer := _resolve_layer_index(definition, atlas, face_index)
		var base := verts.size()
		var face_verts: Array = face["verts"]
		var normal: Vector3 = face["normal"]
		var uv2 := Vector2(layer, 0.0)
		verts.append(origin + face_verts[0])
		verts.append(origin + face_verts[1])
		verts.append(origin + face_verts[2])
		verts.append(origin + face_verts[3])
		for i in 4:
			normals.append(normal)
			uv2s.append(uv2)
		uvs.append(Vector2(0, 0))
		uvs.append(Vector2(1, 0))
		uvs.append(Vector2(1, 1))
		uvs.append(Vector2(0, 1))
		for idx: int in QUAD_INDICES:
			indices.append(base + idx)

func _resolve_layer_index(definition: BlockDefinition, atlas: TerrainTextureAtlas, face_index: int) -> int:
	if definition == null or atlas == null:
		return 0
	var layer := atlas.layer_index(definition.get_face_layer_name(face_index))
	return maxi(layer, 0)
