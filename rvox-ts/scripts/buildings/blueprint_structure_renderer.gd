class_name BlueprintStructureRenderer
extends RefCounted

## Turns a blueprint's blocks array (pos/block_id/shape_id/rotation_steps
## dictionaries, the BuildingBlueprint JSON format) into batched runtime
## geometry: one ArrayMesh surface per block_id, real stair/slab/door/fence
## shapes via ShapeGeometryFactory.shape_boxes, textured from the generated
## terrain PNGs when present (albedo_color fallback otherwise).
##
## This replaces the gray PlaceholderBuilding box for any catalog entry that
## has a real blueprint JSON. Interior cube faces (cube touching cube) are
## culled, which removes the large majority of faces in a solid building.

const GENERATED_TEXTURES_DIR := "res://data/textures/generated"
## Godot's default per-mesh OmniLight budget is tight; a big build full of
## torches/lamps would blow past it and flicker, so cap what we spawn.
const MAX_LIGHTS := 16

static var _block_registry: BlockRegistry = null
static var _material_cache: Dictionary = {}

## Face definitions: axis normal, and the two tangent axes used for UVs.
const FACES: Array[Dictionary] = [
	{"normal": Vector3(1, 0, 0), "u": Vector3(0, 0, 1), "v": Vector3(0, 1, 0)},
	{"normal": Vector3(-1, 0, 0), "u": Vector3(0, 0, -1), "v": Vector3(0, 1, 0)},
	{"normal": Vector3(0, 1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, 1)},
	{"normal": Vector3(0, -1, 0), "u": Vector3(1, 0, 0), "v": Vector3(0, 0, -1)},
	{"normal": Vector3(0, 0, 1), "u": Vector3(-1, 0, 0), "v": Vector3(0, 1, 0)},
	{"normal": Vector3(0, 0, -1), "u": Vector3(1, 0, 0), "v": Vector3(0, 1, 0)},
]


## Builds the structure node. Blocks are recentred so the node origin sits at
## the footprint's XZ center on the ground plane, matching how
## PlaceholderBuilding (and therefore the placement controller) positions
## buildings. Returns null when blocks is empty.
static func build(blocks: Array) -> Node3D:
	if blocks.is_empty():
		return null
	var registry := _registry()

	var min_cell := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var max_cell := -min_cell
	var cube_cells := {}
	var parsed: Array[Dictionary] = []
	for block: Variant in blocks:
		if not block is Dictionary:
			continue
		var data: Dictionary = block
		var pos: Array = data.get("pos", [0, 0, 0])
		if pos.size() != 3:
			continue
		var cell := Vector3i(int(pos[0]), int(pos[1]), int(pos[2]))
		var block_id := StringName(str(data.get("block_id", "")))
		if block_id == &"" or block_id == &"air":
			continue
		var shape_id := str(data.get("shape_id", "cube"))
		min_cell = Vector3i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y), mini(min_cell.z, cell.z))
		max_cell = Vector3i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y), maxi(max_cell.z, cell.z))
		if shape_id == "cube":
			cube_cells[cell] = true
		parsed.append({
			"cell": cell,
			"block_id": block_id,
			"shape_id": shape_id,
			"rotation_steps": posmod(int(data.get("rotation_steps", 0)), 4),
		})
	if parsed.is_empty():
		return null

	# Footprint-centered origin, base at y = 0.
	var offset := Vector3(
		-(float(min_cell.x) + float(max_cell.x + 1)) * 0.5,
		-float(min_cell.y),
		-(float(min_cell.z) + float(max_cell.z + 1)) * 0.5,
	)

	var surface_tools := {}
	var lights_spawned := 0
	var root := Node3D.new()
	root.name = "BlueprintStructure"
	for entry: Dictionary in parsed:
		var cell: Vector3i = entry["cell"]
		var block_id: StringName = entry["block_id"]
		if not surface_tools.has(block_id):
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface_tools[block_id] = tool
		var st: SurfaceTool = surface_tools[block_id]
		var cell_center := Vector3(cell) + Vector3(0.5, 0.0, 0.5) + offset
		if entry["shape_id"] == "cube":
			_emit_culled_cube(st, cell, cell_center, cube_cells)
		else:
			var boxes: Array[Dictionary] = ShapeGeometryFactory.shape_boxes(entry["shape_id"], 0, 0.02)
			var steps: int = entry["rotation_steps"] if entry["shape_id"] in ShapeGeometryFactory.ROTATABLE_SHAPES else 0
			for box: Dictionary in boxes:
				var size: Vector3 = box["size"]
				var center: Vector3 = box["position"]
				for _i in steps:
					center = Vector3(-center.z, center.y, center.x)
					size = Vector3(size.z, size.y, size.x)
				_emit_box(st, cell_center + center, size * 0.5)

		var definition := registry.get_block(block_id) if registry != null else null
		if definition != null and definition.light_energy > 0.0 and lights_spawned < MAX_LIGHTS:
			var light := OmniLight3D.new()
			light.light_energy = definition.light_energy
			light.light_color = definition.light_color
			light.omni_range = definition.light_range
			light.position = cell_center + Vector3(0.0, 0.6, 0.0)
			light.shadow_enabled = false
			root.add_child(light)
			lights_spawned += 1

	for block_id: StringName in surface_tools:
		var st: SurfaceTool = surface_tools[block_id]
		var mesh := st.commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _material_for(block_id)
		instance.name = "Blocks_%s" % block_id
		root.add_child(instance)
	return root


## True when this blueprint JSON path exists and holds a non-empty blocks
## array — the placement flow uses this to decide placeholder vs structure.
static func blueprint_has_blocks(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed is Dictionary and not (parsed.get("blocks", []) as Array).is_empty()


static func _registry() -> BlockRegistry:
	if _block_registry == null:
		_block_registry = BlockRegistry.new()
		_block_registry.load_blocks()
	return _block_registry


static func _material_for(block_id: StringName) -> StandardMaterial3D:
	if _material_cache.has(block_id):
		return _material_cache[block_id]
	var material := StandardMaterial3D.new()
	var definition := _registry().get_block(block_id)
	if definition != null:
		material.albedo_color = definition.albedo_color
		material.roughness = definition.roughness
		var layer := String(definition.texture_side)
		if not layer.is_empty():
			var albedo_path := "%s/%s.png" % [GENERATED_TEXTURES_DIR, layer]
			if ResourceLoader.exists(albedo_path):
				material.albedo_texture = load(albedo_path)
				# The texture carries the color; keep the tint neutral so we
				# don't double-darken (albedo_color modulates the texture).
				material.albedo_color = Color.WHITE
				var normal_path := "%s/%s_normal.png" % [GENERATED_TEXTURES_DIR, layer]
				if ResourceLoader.exists(normal_path):
					material.normal_enabled = true
					material.normal_texture = load(normal_path)
		if definition.albedo_color.a < 0.999 and material.albedo_texture == null:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if definition.light_energy > 0.0:
			material.emission_enabled = true
			material.emission = definition.light_color
			material.emission_energy_multiplier = minf(definition.light_energy, 2.0)
	else:
		material.albedo_color = Color(0.55, 0.57, 0.6)
		material.roughness = 0.9
	_material_cache[block_id] = material
	return material


## Emits a full unit cube at cell, skipping any face that touches another
## cube cell (interior faces of solid walls/floors — the bulk of a building).
static func _emit_culled_cube(st: SurfaceTool, cell: Vector3i, cell_center: Vector3, cube_cells: Dictionary) -> void:
	var half := Vector3(0.5, 0.5, 0.5)
	var center := cell_center + Vector3(0.0, 0.5, 0.0)
	for face: Dictionary in FACES:
		var normal: Vector3 = face["normal"]
		if cube_cells.has(cell + Vector3i(normal)):
			continue
		_emit_face(st, center, half, face)


static func _emit_box(st: SurfaceTool, center: Vector3, half: Vector3) -> void:
	for face: Dictionary in FACES:
		_emit_face(st, center, half, face)


static func _emit_face(st: SurfaceTool, center: Vector3, half: Vector3, face: Dictionary) -> void:
	var normal: Vector3 = face["normal"]
	var u_axis: Vector3 = face["u"]
	var v_axis: Vector3 = face["v"]
	var face_center := center + normal * (half * normal.abs()).length()
	var u_half := u_axis * (half * u_axis.abs()).length()
	var v_half := v_axis * (half * v_axis.abs()).length()
	var corners := [
		face_center - u_half - v_half,
		face_center + u_half - v_half,
		face_center + u_half + v_half,
		face_center - u_half + v_half,
	]
	# Planar UVs from world position so the texture tiles continuously
	# across neighboring blocks of the same material.
	var uvs: Array[Vector2] = []
	for corner: Vector3 in corners:
		uvs.append(Vector2(corner.dot(u_axis), -corner.dot(v_axis)))
	# Two triangles, wound counter-clockwise as seen from outside.
	for index: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(uvs[index])
		st.add_vertex(corners[index])
