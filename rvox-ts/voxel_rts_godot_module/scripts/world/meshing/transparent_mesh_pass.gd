class_name TransparentMeshPass
extends RefCounted

# Planned pass for water, leaves, glass, roof-fade layers, and magic blocks.
# Keep it separate from solid meshing so transparency sorting does not poison the terrain mesh.

func build_transparent_mesh(_chunk: ChunkData) -> ArrayMesh:
    return ArrayMesh.new()
