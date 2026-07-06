@tool
extends McpTestSuite

const StructureRenderer := preload("res://scripts/buildings/blueprint_structure_renderer.gd")
const ShapeFactory := preload("res://addons/world_forge/model/shape_geometry_factory.gd")


func suite_name() -> String:
	return "structure_renderer"


func test_shape_boxes_covers_every_shape() -> void:
	for shape_id: String in ["cube", "slab", "slab_top", "stair", "stair_top", "door",
			"fence", "pane", "plate", "torch", "lantern", "brazier"]:
		var boxes := ShapeFactory.shape_boxes(shape_id, 0)
		assert_gt(boxes.size(), 0, "%s should decompose into at least one box" % shape_id)
		for box: Dictionary in boxes:
			assert_true(box.has("size") and box.has("position"), "%s boxes need size+position" % shape_id)


func test_stair_and_inverted_stair_mirror_vertically() -> void:
	var stair := ShapeFactory.shape_boxes("stair", 0)
	var inverted := ShapeFactory.shape_boxes("stair_top", 0)
	assert_eq(stair.size(), 2, "Stair is a slab plus a step")
	assert_eq(inverted.size(), 2, "Inverted stair is a slab plus a step")
	# The full half swaps from bottom (y 0.25) to top (y 0.75).
	assert_true((stair[0]["position"] as Vector3).y < (inverted[0]["position"] as Vector3).y,
			"Inverted stair's slab should sit in the upper half")


func test_door_is_a_thin_edge_panel() -> void:
	var boxes := ShapeFactory.shape_boxes("door", 0)
	assert_eq(boxes.size(), 1, "Door is a single panel")
	var size: Vector3 = boxes[0]["size"]
	assert_true(size.z < 0.2, "Door panel should be thin on Z")
	assert_true(size.y >= 1.0, "Door panel should span the full cell height")
	assert_true((boxes[0]["position"] as Vector3).z < -0.3, "Door panel hangs on the cell edge")


func test_create_shape_rotates_rotatable_shapes() -> void:
	var material := StandardMaterial3D.new()
	for shape_id: String in ShapeFactory.ROTATABLE_SHAPES:
		var rotated: Node3D = ShapeFactory.create_shape(shape_id, 1, 0, material)
		assert_true(absf(rotated.rotation.y + PI * 0.5) < 0.001,
				"%s should honor rotation_steps" % shape_id)
		rotated.free()
	var slab: Node3D = ShapeFactory.create_shape("slab", 1, 0, material)
	assert_true(absf(slab.rotation.y) < 0.001, "Non-rotatable shapes must ignore rotation_steps")
	slab.free()


func test_build_batches_one_mesh_per_block_id() -> void:
	var blocks: Array = [
		{"pos": [0, 0, 0], "block_id": "stone"},
		{"pos": [1, 0, 0], "block_id": "stone"},
		{"pos": [0, 1, 0], "block_id": "wood_planks", "shape_id": "stair", "rotation_steps": 2},
		{"pos": [1, 1, 0], "block_id": "wood_door", "shape_id": "door", "rotation_steps": 1},
		{"pos": [2, 0, 0], "block_id": "air"},  # Air must be skipped.
	]
	var structure := StructureRenderer.build(blocks)
	assert_true(structure != null, "Structure should build")
	if structure == null:
		return
	var mesh_instances := 0
	for child in structure.get_children():
		if child is MeshInstance3D:
			mesh_instances += 1
			assert_true((child as MeshInstance3D).material_override != null, "Each batch needs a material")
	assert_eq(mesh_instances, 3, "One batched mesh per distinct block_id (air excluded)")
	structure.free()


func test_interior_cube_faces_are_culled() -> void:
	# A lone cube emits 6 faces = 12 tris = 36 vertices. Two adjacent cubes
	# share a hidden pair of faces: 2 * 36 - 2 * 6 = 60 vertices.
	var lone := StructureRenderer.build([{"pos": [0, 0, 0], "block_id": "stone"}])
	var pair := StructureRenderer.build([
		{"pos": [0, 0, 0], "block_id": "stone"},
		{"pos": [1, 0, 0], "block_id": "stone"},
	])
	assert_eq(_vertex_count(lone), 36, "Lone cube should emit all 6 faces")
	assert_eq(_vertex_count(pair), 60, "Adjacent cubes should cull the shared faces")
	lone.free()
	pair.free()


func test_light_blocks_spawn_lights() -> void:
	var structure := StructureRenderer.build([
		{"pos": [0, 0, 0], "block_id": "stone"},
		{"pos": [0, 1, 0], "block_id": "torch", "shape_id": "torch"},
	])
	assert_true(structure != null, "Structure should build")
	if structure == null:
		return
	var lights := 0
	for child in structure.get_children():
		if child is OmniLight3D:
			lights += 1
	assert_eq(lights, 1, "Torch block should spawn one OmniLight3D")
	structure.free()


func test_imported_blueprint_builds_end_to_end() -> void:
	var path := "res://data/buildings/imported/small_medieval_home_4.json"
	if not FileAccess.file_exists(path):
		return  # Imported set is optional; skip quietly when absent.
	var blueprint := BuildingBlueprintLoader.load_from_json(path)
	assert_true(blueprint != null, "Imported blueprint should load")
	if blueprint == null:
		return
	var structure := StructureRenderer.build(blueprint.blocks)
	assert_true(structure != null, "Imported blueprint should render")
	if structure != null:
		assert_gt(structure.get_child_count(), 0, "Rendered structure should have mesh children")
		structure.free()


func _vertex_count(structure: Node3D) -> int:
	var total := 0
	for child in structure.get_children():
		var instance := child as MeshInstance3D
		if instance == null:
			continue
		var mesh := instance.mesh as ArrayMesh
		for surface in mesh.get_surface_count():
			total += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	return total
