@tool
class_name ShapeGeometryFactory
extends RefCounted

const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8


## Shapes whose geometry is direction-dependent and honors rotation_steps.
const ROTATABLE_SHAPES: Array[String] = ["stair", "stair_top", "door"]


static func create_shape(
	shape_id: String,
	rotation_steps: int,
	connection_mask: int,
	material: Material,
	inset := 0.04
) -> Node3D:
	var root := Node3D.new()
	root.rotation.y = -float(posmod(rotation_steps, 4)) * PI * 0.5 if shape_id in ROTATABLE_SHAPES else 0.0
	root.position = Vector3(0.5, 0.0, 0.5)
	for box: Dictionary in shape_boxes(shape_id, connection_mask, inset):
		_add_box(root, box["size"], box["position"], material)
	return root


## Box decomposition of a shape, in cell-center-relative coordinates (the
## same frame create_shape's root uses: origin at the cell's bottom-center,
## before rotation). Shared by the editor's node-based renderer above and
## BlueprintStructureRenderer's batched runtime meshing, so both always
## agree on what each shape looks like.
static func shape_boxes(shape_id: String, connection_mask: int, inset := 0.04) -> Array[Dictionary]:
	var boxes: Array[Dictionary] = []
	match shape_id:
		"slab":
			boxes.append({"size": Vector3(1.0 - inset, 0.5 - inset, 1.0 - inset), "position": Vector3(0, 0.25, 0)})
		"slab_top":
			boxes.append({"size": Vector3(1.0 - inset, 0.5 - inset, 1.0 - inset), "position": Vector3(0, 0.75, 0)})
		"stair":
			boxes.append({"size": Vector3(1.0 - inset, 0.5 - inset, 1.0 - inset), "position": Vector3(0, 0.25, 0)})
			boxes.append({"size": Vector3(1.0 - inset, 0.5 - inset, 0.5 - inset), "position": Vector3(0, 0.75, 0.25)})
		"stair_top":
			# Upside-down stair: full upper half, lower step on the same
			# side the regular stair's high step sits on.
			boxes.append({"size": Vector3(1.0 - inset, 0.5 - inset, 1.0 - inset), "position": Vector3(0, 0.75, 0)})
			boxes.append({"size": Vector3(1.0 - inset, 0.5 - inset, 0.5 - inset), "position": Vector3(0, 0.25, 0.25)})
		"door":
			# Full-height thin panel hung on the cell's -Z edge; two stacked
			# door cells read as one two-block-tall double door leaf.
			boxes.append({"size": Vector3(0.94, 1.0, 0.12), "position": Vector3(0, 0.5, -0.42)})
		"fence":
			_append_fence_boxes(boxes, connection_mask)
		"pane":
			_append_pane_boxes(boxes, connection_mask)
		"plate":
			boxes.append({"size": Vector3(0.72, 0.08, 0.72), "position": Vector3(0, 0.04, 0)})
		"torch":
			# Thin upright stick with a slightly wider head.
			boxes.append({"size": Vector3(0.1, 0.5, 0.1), "position": Vector3(0, 0.25, 0)})
			boxes.append({"size": Vector3(0.16, 0.14, 0.16), "position": Vector3(0, 0.56, 0)})
		"lantern":
			# Hanging-style lantern body with a cap and a ground spike.
			boxes.append({"size": Vector3(0.3, 0.34, 0.3), "position": Vector3(0, 0.32, 0)})
			boxes.append({"size": Vector3(0.2, 0.08, 0.2), "position": Vector3(0, 0.53, 0)})
			boxes.append({"size": Vector3(0.06, 0.16, 0.06), "position": Vector3(0, 0.08, 0)})
		"brazier":
			# Bowl on a pedestal.
			boxes.append({"size": Vector3(0.22, 0.4, 0.22), "position": Vector3(0, 0.2, 0)})
			boxes.append({"size": Vector3(0.62, 0.2, 0.62), "position": Vector3(0, 0.5, 0)})
		_:
			boxes.append({"size": Vector3.ONE * (1.0 - inset), "position": Vector3(0, 0.5, 0)})
	return boxes


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


static func _append_fence_boxes(boxes: Array[Dictionary], mask: int) -> void:
	boxes.append({"size": Vector3(0.24, 1.0, 0.24), "position": Vector3(0, 0.5, 0)})
	if mask == 0:
		return
	for height: float in [0.38, 0.72]:
		if mask & NORTH:
			boxes.append({"size": Vector3(0.14, 0.14, 0.5), "position": Vector3(0, height, -0.25)})
		if mask & SOUTH:
			boxes.append({"size": Vector3(0.14, 0.14, 0.5), "position": Vector3(0, height, 0.25)})
		if mask & EAST:
			boxes.append({"size": Vector3(0.5, 0.14, 0.14), "position": Vector3(0.25, height, 0)})
		if mask & WEST:
			boxes.append({"size": Vector3(0.5, 0.14, 0.14), "position": Vector3(-0.25, height, 0)})


static func _append_pane_boxes(boxes: Array[Dictionary], mask: int) -> void:
	boxes.append({"size": Vector3(0.12, 1.0, 0.12), "position": Vector3(0, 0.5, 0)})
	if mask == 0:
		boxes.append({"size": Vector3(1.0, 0.84, 0.08), "position": Vector3(0, 0.5, 0)})
		return
	if mask & NORTH:
		boxes.append({"size": Vector3(0.08, 0.84, 0.5), "position": Vector3(0, 0.5, -0.25)})
	if mask & SOUTH:
		boxes.append({"size": Vector3(0.08, 0.84, 0.5), "position": Vector3(0, 0.5, 0.25)})
	if mask & EAST:
		boxes.append({"size": Vector3(0.5, 0.84, 0.08), "position": Vector3(0.25, 0.5, 0)})
	if mask & WEST:
		boxes.append({"size": Vector3(0.5, 0.84, 0.08), "position": Vector3(-0.25, 0.5, 0)})


static func _add_box(root: Node3D, size: Vector3, position: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	root.add_child(instance)
