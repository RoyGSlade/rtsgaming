@tool
class_name ShapeGeometryFactory
extends RefCounted

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8


static func create_shape(
	shape_id: String,
	rotation_steps: int,
	connection_mask: int,
	material: Material,
	inset := 0.04
) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = -float(posmod(rotation_steps, 4)) * PI * 0.5 if shape_id == "stair" else 0.0
	root.position = Vector3(0.5, 0.0, 0.5)
	match shape_id:
		"slab":
			_add_box(root, Vector3(1.0 - inset, 0.5 - inset, 1.0 - inset), Vector3(0, 0.25, 0), material)
		"slab_top":
			_add_box(root, Vector3(1.0 - inset, 0.5 - inset, 1.0 - inset), Vector3(0, 0.75, 0), material)
		"stair":
			_add_box(root, Vector3(1.0 - inset, 0.5 - inset, 1.0 - inset), Vector3(0, 0.25, 0), material)
			_add_box(root, Vector3(1.0 - inset, 0.5 - inset, 0.5 - inset), Vector3(0, 0.75, 0.25), material)
		"fence":
			_add_fence(root, connection_mask, material)
		"pane":
			_add_pane(root, connection_mask, material)
		"plate":
			_add_box(root, Vector3(0.72, 0.08, 0.72), Vector3(0, 0.04, 0), material)
		_:
			_add_box(root, Vector3.ONE * (1.0 - inset), Vector3(0, 0.5, 0), material)
	return root


static func connection_mask_for(document: ForgeDocument, cell: Vector3i, shape_id: String) -> int:
	if shape_id not in ["fence", "pane"]:
		return 0
	var mask := 0
	var checks := [
		[NORTH, Vector3i(0, 0, -1)], [EAST, Vector3i(1, 0, 0)],
		[SOUTH, Vector3i(0, 0, 1)], [WEST, Vector3i(-1, 0, 0)],
	]
	for check: Array in checks:
		var neighbor := document.get_block(cell + (check[1] as Vector3i))
		if neighbor.is_empty():
			continue
		var neighbor_shape := str(neighbor.get("shape_id", "cube"))
		if neighbor_shape == shape_id or neighbor_shape in ["cube", "fence", "pane"]:
			mask |= int(check[0])
	return mask


static func _add_fence(root: Node3D, mask: int, material: Material) -> void:
	_add_box(root, Vector3(0.24, 1.0, 0.24), Vector3(0, 0.5, 0), material)
	if mask == 0:
		return
	for height: float in [0.38, 0.72]:
		if mask & NORTH:
			_add_box(root, Vector3(0.14, 0.14, 0.5), Vector3(0, height, -0.25), material)
		if mask & SOUTH:
			_add_box(root, Vector3(0.14, 0.14, 0.5), Vector3(0, height, 0.25), material)
		if mask & EAST:
			_add_box(root, Vector3(0.5, 0.14, 0.14), Vector3(0.25, height, 0), material)
		if mask & WEST:
			_add_box(root, Vector3(0.5, 0.14, 0.14), Vector3(-0.25, height, 0), material)


static func _add_pane(root: Node3D, mask: int, material: Material) -> void:
	_add_box(root, Vector3(0.12, 1.0, 0.12), Vector3(0, 0.5, 0), material)
	if mask == 0:
		_add_box(root, Vector3(1.0, 0.84, 0.08), Vector3(0, 0.5, 0), material)
		return
	if mask & NORTH:
		_add_box(root, Vector3(0.08, 0.84, 0.5), Vector3(0, 0.5, -0.25), material)
	if mask & SOUTH:
		_add_box(root, Vector3(0.08, 0.84, 0.5), Vector3(0, 0.5, 0.25), material)
	if mask & EAST:
		_add_box(root, Vector3(0.5, 0.84, 0.08), Vector3(0.25, 0.5, 0), material)
	if mask & WEST:
		_add_box(root, Vector3(0.5, 0.84, 0.08), Vector3(-0.25, 0.5, 0), material)


static func _add_box(root: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	root.add_child(instance)
