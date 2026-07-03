class_name VoxelBuildingEditorPrototype
extends Node3D

const DRAFT_PATH := "user://blueprints/draft_building.json"
const BLOCK_SIZE := 1.0
const BLOCK_FOLDER := "res://data/blocks"
const DEFAULT_BLOCK_ID := &"stone_block"
const MAX_STACK := 64

@onready var camera: Camera3D = $CameraRig/Camera3D
@onready var block_container: Node3D = $BlockContainer
@onready var hover_preview: MeshInstance3D = $HoverPreview
@onready var status_label: Label = $EditorUI/Root/Margin/Layout/Status
@onready var _ui_root: Control = $EditorUI/Root

var blueprint := BlockEditorDraftBlueprint.new()
var active_layer := 0
var _hovered_cell := Vector3i.ZERO
var _place_target := Vector3i.ZERO
var _has_hovered_cell := false
var _block_material: StandardMaterial3D
var _preview_valid_material: StandardMaterial3D
var _preview_invalid_material: StandardMaterial3D

var _selected_block_id: StringName = DEFAULT_BLOCK_ID
var _block_defs: Dictionary = {}          # StringName -> BlockDefinition
var _material_cache: Dictionary = {}      # StringName -> StandardMaterial3D
var _palette_list: ItemList
var _palette_search: LineEdit


func _ready() -> void:
	_load_block_definitions()
	_create_materials()
	_setup_scene_visuals()
	hover_preview.mesh = BoxMesh.new()
	hover_preview.mesh.size = Vector3.ONE * 0.96
	blueprint.changed.connect(_on_blueprint_changed)
	$EditorUI/Root/Margin/Layout/Actions/Clear.pressed.connect(_clear_blueprint)
	$EditorUI/Root/Margin/Layout/Actions/Save.pressed.connect(_save_blueprint)
	$EditorUI/Root/Margin/Layout/Actions/Load.pressed.connect(_load_blueprint)
	$EditorUI/Root/Margin/Layout/Help.text = "Left click: place / stack   Right click: remove\nWASD: pan   Middle drag: orbit   Wheel: zoom   Q/E: build height"
	_build_layer_controls()
	_build_palette_ui()
	_on_blueprint_changed()


func _process(_delta: float) -> void:
	_update_hovered_cell()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_change_layer(1)
			get_viewport().set_input_as_handled()
			return
		elif event.keycode == KEY_Q:
			_change_layer(-1)
			get_viewport().set_input_as_handled()
			return
	if not _has_hovered_cell or _pointer_is_over_ui():
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_place_block(_place_target)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_remove_block(_hovered_cell)
			get_viewport().set_input_as_handled()


func _update_hovered_cell() -> void:
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse)
	var ray_direction := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, float(active_layer) * BLOCK_SIZE)
	var intersection: Variant = plane.intersects_ray(ray_origin, ray_direction)
	_has_hovered_cell = intersection != null
	hover_preview.visible = _has_hovered_cell and not _pointer_is_over_ui()
	if not _has_hovered_cell:
		return
	var point: Vector3 = intersection
	_hovered_cell = Vector3i(floori(point.x), active_layer, floori(point.z))
	# Placement stacks upward: land on the first open cell at or above the build height.
	_place_target = _hovered_cell
	var guard := 0
	while blueprint.has_block(_place_target) and guard < MAX_STACK:
		_place_target.y += 1
		guard += 1
	hover_preview.position = _cell_to_world(_place_target)
	hover_preview.material_override = _preview_valid_material


func _place_block(cell: Vector3i) -> void:
	blueprint.place_block(BlockInstanceData.new(cell, _selected_block_id))


func _remove_block(cell: Vector3i) -> void:
	# Right click peels the top block of the hovered column at or above the build height.
	var top := _column_top(cell.x, cell.z, active_layer)
	if top == null:
		return
	blueprint.remove_block(Vector3i(cell.x, int(top), cell.z))


func _column_top(x: int, z: int, min_y: int) -> Variant:
	var best: Variant = null
	for block in blueprint.get_blocks():
		var position := block.grid_position
		if position.x == x and position.z == z and position.y >= min_y:
			if best == null or position.y > int(best):
				best = position.y
	return best


func _change_layer(delta: int) -> void:
	active_layer = clampi(active_layer + delta, 0, MAX_STACK)
	status_label.text = "%d blocks · build height %d" % [blueprint.block_count(), active_layer]


func _on_blueprint_changed() -> void:
	for child in block_container.get_children():
		child.queue_free()
	for block in blueprint.get_blocks():
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3.ONE * 0.94
		mesh_instance.mesh = box
		mesh_instance.material_override = _material_for(block.block_id)
		mesh_instance.position = _cell_to_world(block.grid_position)
		mesh_instance.name = "Block_%d_%d_%d" % [block.grid_position.x, block.grid_position.y, block.grid_position.z]
		block_container.add_child(mesh_instance)
	status_label.text = "%d blocks · build height %d" % [blueprint.block_count(), active_layer]


func _clear_blueprint() -> void:
	blueprint.clear()
	status_label.text = "Draft cleared"


func _save_blueprint() -> void:
	var error := blueprint.save_json(DRAFT_PATH)
	status_label.text = "Saved %d blocks" % blueprint.block_count() if error == OK else "Save failed: %s" % error_string(error)


func _load_blueprint() -> void:
	var loaded := BlockEditorDraftBlueprint.load_json(DRAFT_PATH)
	if loaded == null:
		status_label.text = "No valid draft found"
		return
	if blueprint.changed.is_connected(_on_blueprint_changed):
		blueprint.changed.disconnect(_on_blueprint_changed)
	blueprint = loaded
	blueprint.changed.connect(_on_blueprint_changed)
	_on_blueprint_changed()
	status_label.text = "Loaded %d blocks" % blueprint.block_count()


func _cell_to_world(cell: Vector3i) -> Vector3:
	return (Vector3(cell) + Vector3(0.5, 0.5, 0.5)) * BLOCK_SIZE


func _pointer_is_over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered != _ui_root


# --- Block choices -----------------------------------------------------------

func _load_block_definitions() -> void:
	_block_defs.clear()
	var registry := BlockRegistry.new()
	registry.block_folder = BLOCK_FOLDER
	registry.load_blocks()
	for block_id in registry.list_ids():
		var definition := registry.get_block(block_id)
		if definition == null or definition.id == &"air":
			continue
		_block_defs[block_id] = definition
	registry.free()
	if not _block_defs.has(_selected_block_id):
		var ids: Array = _block_defs.keys()
		ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
		if not ids.is_empty():
			_selected_block_id = ids[0]


func _build_palette_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "Palette"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -268.0
	panel.offset_top = 14.0
	panel.offset_right = -14.0
	panel.offset_bottom = 470.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_ui_root.add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var heading := Label.new()
	heading.text = "Block Palette"
	vbox.add_child(heading)

	_palette_search = LineEdit.new()
	_palette_search.placeholder_text = "Search blocks..."
	_palette_search.clear_button_enabled = true
	_palette_search.text_changed.connect(func(_text: String) -> void: _refresh_palette())
	vbox.add_child(_palette_search)

	_palette_list = ItemList.new()
	_palette_list.custom_minimum_size = Vector2(240.0, 380.0)
	_palette_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_list.item_selected.connect(_on_palette_selected)
	vbox.add_child(_palette_list)

	_refresh_palette()
	_update_preview_tint()


func _refresh_palette() -> void:
	if _palette_list == null:
		return
	_palette_list.clear()
	var filter := _palette_search.text.strip_edges().to_lower() if _palette_search else ""
	var ids: Array = _block_defs.keys()
	ids.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	var selected_index := -1
	for block_id: StringName in ids:
		var definition: BlockDefinition = _block_defs[block_id]
		var label: String = definition.display_name if definition != null else String(block_id)
		if filter != "" and not (filter in label.to_lower() or filter in String(block_id).to_lower()):
			continue
		var index := _palette_list.add_item(label)
		_palette_list.set_item_metadata(index, block_id)
		_palette_list.set_item_custom_bg_color(index, _color_for_block(block_id).darkened(0.45))
		_palette_list.set_item_tooltip(index, "%s · %s" % [block_id, definition.category if definition != null else &""])
		if block_id == _selected_block_id:
			selected_index = index
	if selected_index >= 0:
		_palette_list.select(selected_index)


func _on_palette_selected(index: int) -> void:
	var block_id: Variant = _palette_list.get_item_metadata(index)
	if block_id == null:
		return
	_selected_block_id = block_id
	_update_preview_tint()
	status_label.text = "Selected: %s" % block_id


func _build_layer_controls() -> void:
	var actions: HBoxContainer = $EditorUI/Root/Margin/Layout/Actions
	var down := Button.new()
	down.text = "Height -"
	down.pressed.connect(func() -> void: _change_layer(-1))
	actions.add_child(down)
	var up := Button.new()
	up.text = "Height +"
	up.pressed.connect(func() -> void: _change_layer(1))
	actions.add_child(up)


func _material_for(block_id: StringName) -> StandardMaterial3D:
	if _material_cache.has(block_id):
		return _material_cache[block_id]
	var material := StandardMaterial3D.new()
	material.roughness = 0.86
	var definition := _block_defs.get(block_id) as BlockDefinition
	if definition != null and definition.albedo_texture != null:
		material.albedo_texture = definition.albedo_texture
	else:
		material.albedo_color = _color_for_block(block_id)
	_material_cache[block_id] = material
	return material


func _color_for_block(block_id: StringName) -> Color:
	var definition := _block_defs.get(block_id) as BlockDefinition
	if definition != null and definition.albedo_color != Color.WHITE:
		return definition.albedo_color
	if definition != null:
		var category_color := _color_for_category(definition.category)
		if category_color != Color.WHITE:
			return category_color
	# Deterministic fallback hue so distinct blocks stay visually separable.
	var hue := float(hash(String(block_id)) % 360) / 360.0
	return Color.from_hsv(hue, 0.45, 0.8)


func _color_for_category(category: StringName) -> Color:
	match category:
		&"terrain": return Color("#84956b")
		&"construction": return Color("#b08d57")
		&"ore": return Color("#8a8f98")
		&"fluid": return Color("#3f7fbf")
		&"foliage": return Color("#4f8f4a")
		&"floor": return Color("#9a8b73")
		&"decoration": return Color("#a58fb0")
		_: return Color.WHITE


func _update_preview_tint() -> void:
	if _preview_valid_material == null:
		return
	var color := _color_for_block(_selected_block_id)
	color.a = 0.5
	_preview_valid_material.albedo_color = color


func _create_materials() -> void:
	_block_material = StandardMaterial3D.new()
	_block_material.albedo_color = Color("#84956b")
	_block_material.roughness = 0.86
	_preview_valid_material = StandardMaterial3D.new()
	_preview_valid_material.albedo_color = Color(0.30, 0.88, 0.55, 0.42)
	_preview_valid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_preview_invalid_material = StandardMaterial3D.new()
	_preview_invalid_material.albedo_color = Color(0.95, 0.25, 0.22, 0.42)
	_preview_invalid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _setup_scene_visuals() -> void:
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40.0, 40.0)
	floor_mesh.subdivide_width = 39
	floor_mesh.subdivide_depth = 39
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#20282a")
	floor_material.roughness = 1.0
	floor_mesh.material = floor_material
	$GridFloor.mesh = floor_mesh

	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	var grid_mesh := ImmediateMesh.new()
	grid_mesh.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	for coordinate in range(-20, 21):
		var line_color := Color("#708083") if coordinate != 0 else Color("#d6a85f")
		grid_mesh.surface_set_color(line_color)
		grid_mesh.surface_add_vertex(Vector3(float(coordinate), 0.015, -20.0))
		grid_mesh.surface_add_vertex(Vector3(float(coordinate), 0.015, 20.0))
		grid_mesh.surface_add_vertex(Vector3(-20.0, 0.015, float(coordinate)))
		grid_mesh.surface_add_vertex(Vector3(20.0, 0.015, float(coordinate)))
	grid_mesh.surface_end()
	$GridLines.mesh = grid_mesh

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#111719")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b6c8c2")
	environment.ambient_light_energy = 0.55
	$WorldEnvironment.environment = environment
