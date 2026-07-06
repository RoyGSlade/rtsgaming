class_name PlaceholderBuilding
extends Node3D

## Visual stand-in for a building, built from a catalog entry. Used three
## ways: the rotating preview in the HUD, the placement ghost, and the
## placed "construction". Entries whose blueprint JSON exists (explicit
## "blueprint" path, or res://data/buildings/<id>.json) render the real
## block structure via BlueprintStructureRenderer; everything else keeps
## the classic box-and-roof placeholder. Origin sits at the footprint
## center on the ground plane so placement can set position.y to the
## sampled terrain height directly.

var entry: Dictionary
var _mesh_instances: Array[MeshInstance3D] = []
var _base_colors: Array[Color] = []
var _label: Label3D
## Actual block-structure height when rendering a real blueprint, so the
## name label clears the roof instead of sitting at placeholder height.
var _structure_height := 0.0


func setup(new_entry: Dictionary) -> void:
	entry = new_entry
	var footprint: Array = entry.get("footprint", [3, 3])
	var width := float(footprint[0])
	var depth := float(footprint[1])
	var height := float(entry.get("height", 3))
	var color := Color.from_string(String(entry.get("color", "#888888")), Color.GRAY)

	if _setup_structure():
		height = maxf(height, _structure_height)
	else:
		_add_box(Vector3(width, height, depth), Vector3(0.0, height * 0.5, 0.0), color)
		_add_box(Vector3(width + 0.4, 0.35, depth + 0.4), Vector3(0.0, height + 0.175, 0.0), color.darkened(0.35))

	_label = Label3D.new()
	_label.text = String(entry.get("name", "Building"))
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, height + 1.1, 0.0)
	_label.font_size = 48
	_label.pixel_size = 0.01
	_label.modulate = Color(1.0, 1.0, 1.0, 0.9)
	add_child(_label)


## Tries to render the entry's real blueprint blocks. Returns false when the
## entry has no blueprint JSON (caller falls back to the placeholder box).
func _setup_structure() -> bool:
	var path := String(entry.get("blueprint", ""))
	if path.is_empty():
		path = "res://data/buildings/%s.json" % String(entry.get("id", ""))
	if not BlueprintStructureRenderer.blueprint_has_blocks(path):
		return false
	var blueprint := BuildingBlueprintLoader.load_from_json(path)
	if blueprint == null or blueprint.blocks.is_empty():
		return false
	var structure := BlueprintStructureRenderer.build(blueprint.blocks)
	if structure == null:
		return false
	for block: Dictionary in blueprint.blocks:
		var pos: Array = block.get("pos", [0, 0, 0])
		if pos.size() == 3:
			_structure_height = maxf(_structure_height, float(pos[1]) + 1.0)
	add_child(structure)
	# Ghost tinting mutates materials, and the renderer caches them across
	# buildings — give this instance private copies so tinting one ghost
	# never tints already-placed neighbors.
	for child in structure.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.material_override == null:
			continue
		var material := instance.material_override.duplicate() as StandardMaterial3D
		instance.material_override = material
		_mesh_instances.append(instance)
		_base_colors.append(material.albedo_color)
	return not _mesh_instances.is_empty()


## Ghost mode: translucent, tinted green (placeable) or red (blocked).
func set_ghost(valid: bool) -> void:
	var tint := Color(0.35, 1.0, 0.45) if valid else Color(1.0, 0.3, 0.3)
	for i in _mesh_instances.size():
		var material := _mesh_instances[i].material_override as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = _base_colors[i].lerp(tint, 0.55)
		material.albedo_color.a = 0.5
	if _label != null:
		_label.modulate.a = 0.6


## Restore the opaque catalog colors (placed building / preview).
func set_solid() -> void:
	for i in _mesh_instances.size():
		var material := _mesh_instances[i].material_override as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		material.albedo_color = _base_colors[i]
	if _label != null:
		_label.modulate.a = 0.9


func _add_box(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	instance.material_override = material
	add_child(instance)
	_mesh_instances.append(instance)
	_base_colors.append(color)
