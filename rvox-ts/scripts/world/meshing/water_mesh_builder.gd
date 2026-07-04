class_name WaterMeshBuilder
extends RefCounted

## Builds the visible water surface: one top quad per water span (as
## reported live by WaterFlowSimulator), plus a vertical skirt wall
## wherever a span borders dry land, the chunk edge, or neighboring water
## with a lower surface (in which case the wall only drops to that
## neighbor's surface - a 1-block "rapids lip" - instead of a full-depth
## curtain cutting through the neighbor's water). A column normally has
## 0 or 1 spans; the loops already support more (e.g. a future mined-out
## flooded shaft under a surface lake) without further changes here.
## Vertex winding/UV layout matches ChunkMesher's existing top face
## (FACE_DEFS[2]) for consistency.

const TOP_VERTS := [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)]
const TOP_UV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
const TOP_INDICES := [0, 2, 1, 0, 3, 2]
const TOP_NORMAL := Vector3(0, 1, 0)

# Where inside the top water block [surface_y, surface_y + 1) the surface
# plane is drawn. Near the top (not the bottom) for two reasons:
# - the shader's waves displace vertices by up to ~±0.45; a plane drawn at
#   the block's base would have its wave troughs sink through the terrain
#   beneath 1-block-deep water and visibly vanish in patches.
# - 0.1 below the block's lip keeps it clear of an equal-height solid
#   neighbor's top face (at surface_y + 1), so there's no coplanar z-fight
#   there either.
const SURFACE_HEIGHT := 0.9

# Neighbor direction -> the pair of top-surface XZ corners (from TOP_VERTS)
# bounding the footprint edge shared with that neighbor.
const WALL_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const WALL_EDGE_VERTS := [
	[Vector3(1, 0, 1), Vector3(1, 0, 0)], # +x
	[Vector3(0, 0, 0), Vector3(0, 0, 1)], # -x
	[Vector3(0, 0, 1), Vector3(1, 0, 1)], # +z
	[Vector3(1, 0, 0), Vector3(0, 0, 0)], # -z
]
# Pulls each wall slightly inward off the column-boundary plane: terrain
# side faces sit exactly on those integer planes, and a coplanar wall
# z-fights them (flickering/disappearing edges at shorelines).
const WALL_INSETS: Array[Vector3] = [
	Vector3(-0.02, 0, 0), # +x
	Vector3(0.02, 0, 0),  # -x
	Vector3(0, 0, -0.02), # +z
	Vector3(0, 0, 0.02),  # -z
]

func build_water_mesh(chunk: ChunkData, water_simulator: WaterFlowSimulator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertex_count := 0

	for x in chunk.chunk_size:
		for z in chunk.chunk_size:
			for span: WaterSpan in water_simulator.get_column_spans(chunk, x, z):
				var surface_y := float(span.surface_y) + SURFACE_HEIGHT
				_emit_top_quad(st, Vector3(x, surface_y, z))
				vertex_count += 6

				for i in WALL_DIRS.size():
					var nx := x + WALL_DIRS[i].x
					var nz := z + WALL_DIRS[i].y
					var wall_bottom := float(span.floor_y)
					var draw_wall := true
					if nx >= 0 and nx < chunk.chunk_size and nz >= 0 and nz < chunk.chunk_size:
						var neighbor_spans := water_simulator.get_column_spans(chunk, nx, nz)
						if not neighbor_spans.is_empty():
							var neighbor_top: WaterSpan = neighbor_spans[0]
							if neighbor_top.surface_y >= span.surface_y:
								draw_wall = false
							else:
								# Lip down to the lower neighbor's surface only.
								wall_bottom = maxf(wall_bottom, float(neighbor_top.surface_y) + SURFACE_HEIGHT)
					if draw_wall:
						_emit_wall_quad(st, Vector3(x, surface_y, z) + WALL_INSETS[i], wall_bottom, WALL_EDGE_VERTS[i])
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

## Emits a vertical quad along one footprint edge, from the water surface
## down to `wall_bottom` (the span's floor block base, or a lower water
## neighbor's surface).
func _emit_wall_quad(st: SurfaceTool, top_origin: Vector3, wall_bottom: float, edge: Array) -> void:
	var top_a: Vector3 = top_origin + edge[0]
	var top_b: Vector3 = top_origin + edge[1]
	var bottom_a := Vector3(top_a.x, wall_bottom, top_a.z)
	var bottom_b := Vector3(top_b.x, wall_bottom, top_b.z)
	var quad_verts := [top_a, top_b, bottom_b, bottom_a]
	for idx in TOP_INDICES:
		st.set_uv(TOP_UV[idx])
		st.add_vertex(quad_verts[idx])
