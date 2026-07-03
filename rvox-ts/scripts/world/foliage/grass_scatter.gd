class_name GrassScatter
extends MultiMeshInstance3D

## Scatters a small cross-billboard blade mesh over grass-topped chunk
## columns. Static (no wind sway yet) — a plain lit StandardMaterial3D so
## it responds automatically to SunMoonRig's day/night light.

@export var blades_per_cell := 2
@export_range(0.0, 1.0) var coverage := 0.4
@export var blade_height := 0.55
@export var blade_width := 0.28
@export var noise_seed := 7

var _rng := RandomNumberGenerator.new()

func build(chunk: ChunkData, block_registry: BlockRegistry) -> void:
    if chunk == null:
        return

    var transforms: Array[Transform3D] = []
    _rng.seed = noise_seed

    for x in chunk.chunk_size:
        for z in chunk.chunk_size:
            if _rng.randf() > coverage:
                continue
            var height := chunk.get_surface_height(x, z)
            var block_id := chunk.get_block(x, height, z)
            if block_id != &"grass":
                continue
            for i in blades_per_cell:
                transforms.append(_random_blade_transform(x, height, z))

    var mm := MultiMesh.new()
    mm.transform_format = MultiMesh.TRANSFORM_3D
    mm.mesh = _build_blade_mesh()
    mm.instance_count = transforms.size()
    for i in transforms.size():
        mm.set_instance_transform(i, transforms[i])
    multimesh = mm

    if material_override == null:
        material_override = _build_material()

func _random_blade_transform(x: int, y: int, z: int) -> Transform3D:
    var jitter_x := _rng.randf_range(0.15, 0.85)
    var jitter_z := _rng.randf_range(0.15, 0.85)
    var origin := Vector3(x + jitter_x, y + 1.0, z + jitter_z)
    var scale_variance := _rng.randf_range(0.75, 1.25)
    var yaw := _rng.randf_range(0.0, TAU)
    var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_variance)
    return Transform3D(basis, origin)

func _build_blade_mesh() -> ArrayMesh:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _add_blade_quad(st, Vector3(1, 0, 0))
    _add_blade_quad(st, Vector3(0, 0, 1))
    st.generate_normals()
    return st.commit()

## One vertical quad along `right`, rooted at the origin and rising to
## blade_height, forming a cross-billboard with the second quad.
func _add_blade_quad(st: SurfaceTool, right: Vector3) -> void:
    var half := right * (blade_width * 0.5)
    var p0 := -half
    var p1 := half
    var p2 := half + Vector3.UP * blade_height
    var p3 := -half + Vector3.UP * blade_height
    var normal := right.cross(Vector3.UP).normalized()

    for p in [p0, p1, p2, p0, p2, p3]:
        st.set_normal(normal)
        st.add_vertex(p)

func _build_material() -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.32, 0.56, 0.22)
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED
    mat.roughness = 0.95
    return mat
