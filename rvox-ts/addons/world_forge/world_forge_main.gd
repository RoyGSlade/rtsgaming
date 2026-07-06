@tool
extends Control

const DocumentScript := preload("res://addons/world_forge/model/forge_document.gd")
const HistoryScript := preload("res://addons/world_forge/model/forge_history.gd")
const ShapeFactory := preload("res://addons/world_forge/model/shape_geometry_factory.gd")
const SnapResolver := preload("res://addons/world_forge/model/component_snap_resolver.gd")
const ShapeRegistryScript := preload("res://addons/world_forge/model/shape_registry.gd")
const ComponentRegistryScript := preload("res://addons/world_forge/model/component_registry.gd")
const MarkerRegistryScript := preload("res://addons/world_forge/model/marker_registry.gd")
const PartRegistryScript := preload("res://addons/world_forge/model/part_registry.gd")
const MaterialRegistryScript := preload("res://addons/world_forge/model/material_registry.gd")
const PartGeometryFactory := preload("res://addons/world_forge/model/part_geometry_factory.gd")
const PartSnapResolver := preload("res://addons/world_forge/model/part_snap_resolver.gd")
## Pipeline utilities absorbed from the retired block_building_editor addon.
const BlueprintSerializerScript := preload("res://addons/world_forge/pipeline/blueprint_serializer.gd")
const TextureArrayPackerScript := preload("res://addons/world_forge/pipeline/texture_array_packer.gd")
const AssetPackImporterScript := preload("res://addons/world_forge/pipeline/external_asset_pack_importer.gd")
const ThumbnailBackfillScript := preload("res://addons/world_forge/pipeline/blueprint_thumbnail_backfill.gd")
## WFC building generation (shared with the runtime, so generated buildings
## can eventually also be produced in-game).
const ModuleLibraryScript := preload("res://scripts/buildings/generation/building_module_library.gd")
const WFCGeneratorScript := preload("res://scripts/buildings/generation/building_wfc_generator.gd")
## Shared fire/light effect for light-source blocks (torch, lantern, brazier).
const LightFixtureScript := preload("res://scripts/rendering/light_fixture_effect.gd")
## Synchronous isometric preview icon for the blueprint browser.
const ThumbnailRendererScript := preload("res://scripts/rendering/blueprint_thumbnail_renderer.gd")

## SHAPES/COMPONENTS/MARKERS used to be hardcoded literal arrays here. They
## now load from data/world_forge/{shapes,components,markers}/*.tres via the
## registries above - see _load_catalogs() - so palette content is authored
## as data instead of code, matching the block palette's existing convention.
## Downstream code (SnapResolver, placement, rendering) is unchanged: these
## still end up as Array[Dictionary] with exactly the same shape as before.
var _shapes: Array[Dictionary] = []
var _components: Array[Dictionary] = []
var _markers: Array[Dictionary] = []
## Palette entries for the Parts tab: {id, name, color}. Unlike shapes/
## components/markers, _part_registry itself stays alive (not freed after
## catalog load) because rendering placed parts needs it on every
## _refresh_world() call, not just once at startup.
var _parts: Array[Dictionary] = []
var _part_registry: PartRegistry
var _material_registry: MaterialRegistry

## Placed parts live on a fine grid at 1/8 the size of a structure cell.
## The Workshop picker and height control support true sub-cell placement;
## compatible sockets may then refine that position continuously.
const FINE_CELLS_PER_UNIT := int(1.0 / DocumentScript.FINE_CELL_SIZE)

var _plugin: EditorPlugin
var _document: ForgeDocument
var _history: ForgeHistory
var _current_path := ""

## Blueprint browser (see _build_library_panel/_refresh_library): each
## visible entry is a clickable "card" Control, not a Tree row, so it can
## show a preview thumbnail + stats instead of just a filename.
var _library_list: VBoxContainer
var _library_cards: Array[Button] = []
var _selected_library_item_path := ""
var _library_type_filter: OptionButton
var _library_search: LineEdit
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world: Node3D
var _content_root: Node3D
var _camera: Camera3D
var _status: Label
var _block_list: ItemList
var _block_search: LineEdit
var _block_category: OptionButton
var _shape_selector: OptionButton
var _component_list: ItemList
var _marker_list: ItemList
var _part_list: ItemList
var _layer_spin: SpinBox
var _fine_layer_spin: SpinBox
var _undo_button: Button
var _redo_button: Button
var _finalize_button: Button
var _name_edit: LineEdit
var _id_edit: LineEdit
var _tool_button_row: HBoxContainer
var _context_label: Label
var _mirror_x_spin: SpinBox
var _mirror_z_spin: SpinBox
var _kind_selector: OptionButton
## Which module library (hut/blacksmith/keep/castle/custom) the CURRENT
## document is tagged as - separate from _library_type_filter, which filters
## the browser list above.
var _building_type_selector: OptionButton
## Generate (WFC) tab state.
var _gen_type: OptionButton
var _gen_tier: OptionButton
var _gen_seed: SpinBox
var _gen_clear_check: CheckBox
var _gen_result: Label
var _gen_library_paths: PackedStringArray = PackedStringArray()
## Tiny solid-color ItemList icons, cached by color so palette refreshes
## don't rebuild hundreds of identical 12x12 textures.
var _swatch_cache: Dictionary = {}
var _autosave_timer: Timer
var _dirty := false
var _updating_identity := false

const AUTOSAVE_PATH := "user://world_forge_autosave.json"

## Header tool button order; index maps to hotkeys 1..7 in the viewport.
const TOOL_ORDER: Array[String] = ["select", "place", "line", "fill", "box", "shell", "connected"]

const ASSET_SOURCE_PATHS := {
	"kaykit_blocks": "res://assets/external/kaykit/block_bits_source.tres",
	"kaykit_resources": "res://assets/external/kaykit/resource_bits_source.tres",
	"kenney_voxel": "res://assets/external/kenney/voxel_pack_source.tres",
}

var _tool := "select"
var _place_kind := "block"
var _selected_block_id: StringName = &"stone"
var _selected_shape_id := "cube"
var _selected_component_id := "forge_firebox"
var _selected_marker_id := "worker_position"
var _selected_part_id: StringName = &"steel_rod"
var _selected_cells: Dictionary = {}
var _selected_component_ids: Dictionary = {}
var _selected_marker_ids: Dictionary = {}
var _selected_part_keys: Dictionary = {}
var _clipboard: Array[Dictionary] = []
var _paste_armed := false
var _move_armed := false
var _move_source_keys: Array[String] = []
var _move_entity_kind := ""
var _move_entity_id := ""
var _move_nested_armed := false
var _selected_nested_id := ""
var _anchor_cell: Variant = null
var _active_layer := 0
## Sub-cell height within the current structure layer, in fine-grid steps
## (0..FINE_CELLS_PER_UNIT-1) - only meaningful for _place_kind == "part".
var _fine_layer := 0
var _fine_grid_center := Vector3.ZERO
var _brush_rotation := 0
var _staged_blueprint_path := ""
## Mirror placement: block edits (place/erase and the two-point tools) are
## reflected across the X and/or Z plane so symmetric builds only have to be
## drawn once. _mirror_x/_mirror_z are the cell columns that stay fixed -
## the geometric plane runs through that column's center (cell + 0.5).
var _mirror_mode := "off" # off | x | z | xz
var _mirror_x := 0
var _mirror_z := 0
var _block_colors: Dictionary = {}
var _block_catalog: Array[Dictionary] = []
## Per-block visual info for textured rendering: generated-atlas layer name,
## texture_scale, roughness, and an optional explicit albedo_texture, all
## read from BlockDefinition alongside the palette in _load_block_palette().
var _block_texture_info: Dictionary = {}
var _block_materials: Dictionary = {}
## block_id -> {color, energy, range, flame} for light-source blocks
## (BlockDefinition.light_energy > 0); drives preview OmniLights + flames.
var _block_light_info: Dictionary = {}
var _materials: Dictionary = {}
var _hover_mesh: Node3D
var _gamepad_reticle: Label
var _gamepad_prev_buttons: Dictionary = {}
var _hover_valid_material: StandardMaterial3D
var _hover_invalid_material: StandardMaterial3D
var _hover_select_material: StandardMaterial3D
var _camera_yaw := deg_to_rad(45.0)
var _camera_pitch := deg_to_rad(38.0)
var _camera_distance := 20.0
var _camera_focus := Vector3(3, 1, 3)
var _orbiting := false
var _panning := false
var _id_sequence := 0


func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_document = DocumentScript.new()
	_history = HistoryScript.new()
	_document.changed.connect(_on_document_changed)
	_history.changed.connect(_refresh_history_buttons)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_catalogs()
	_build_ui()
	_autosave_timer = Timer.new()
	_autosave_timer.one_shot = true
	_autosave_timer.wait_time = 8.0
	_autosave_timer.timeout.connect(_autosave_now)
	add_child(_autosave_timer)
	_load_block_palette()
	_refresh_library()
	_refresh_world()
	_sync_identity_fields()


## Loads shapes/components/markers from data/world_forge/*/*.tres and
## converts each resource into the Array[Dictionary] shape the rest of this
## editor (SnapResolver, placement, rendering, saved documents) already
## expects, so nothing downstream needed to change for this to become data.
func _load_catalogs() -> void:
	var shape_registry: ShapeRegistry = ShapeRegistryScript.new()
	for id: StringName in shape_registry.list_ids():
		var shape: BlockShapeProfile = shape_registry.get_shape(id)
		_shapes.append({"id": String(shape.id), "name": shape.display_name})
	shape_registry.free()

	var component_registry: ComponentRegistry = ComponentRegistryScript.new()
	for id: StringName in component_registry.list_ids():
		_components.append(_component_to_dict(component_registry.get_component(id)))
	component_registry.free()

	var marker_registry: MarkerRegistry = MarkerRegistryScript.new()
	for id: StringName in marker_registry.list_ids():
		var marker: MarkerDefinition = marker_registry.get_marker(id)
		_markers.append({"id": String(marker.id), "name": marker.display_name, "color": marker.color})
	marker_registry.free()

	# Kept alive (not freed): rendering placed parts on every _refresh_world()
	# call needs _part_registry, unlike shapes/components/markers which are
	# only read once here to build the palette catalog.
	_part_registry = PartRegistryScript.new()
	_material_registry = MaterialRegistryScript.new()
	for id: StringName in _part_registry.list_ids():
		var part: PartProfile = _part_registry.get_part(id)
		_parts.append({"id": String(part.id), "name": part.display_name, "color": part.color})


## FunctionalComponentDefinition.ports/rules are already Array[Dictionary]
## with the exact keys SnapResolver and the placement/rendering code expect
## (id/type/accepts/cell/facing for ports; free-form channel/effect/... for
## rules), so they pass through untouched. Only footprint (Array[Vector3i])
## and capabilities (PackedStringArray) need converting to the plain
## Array/PackedStringArray-as-Array shapes the dict form has always used.
func _component_to_dict(definition: FunctionalComponentDefinition) -> Dictionary:
	var footprint: Array = []
	for cell: Vector3i in definition.footprint:
		footprint.append([cell.x, cell.y, cell.z])
	var dict := {
		"id": String(definition.id),
		"name": definition.display_name,
		"color": definition.color,
		"footprint": footprint,
		"ports": definition.ports.duplicate(true),
		"capabilities": Array(definition.capabilities),
	}
	if definition.snap_required:
		dict["snap_required"] = true
	if not definition.rules.is_empty():
		dict["rules"] = definition.rules.duplicate(true)
	return dict


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	root.add_child(_build_header())
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 245
	root.add_child(split)
	split.add_child(_build_library_panel())
	var center_right := HSplitContainer.new()
	center_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_right.split_offset = -310
	split.add_child(center_right)
	center_right.add_child(_build_viewport_panel())
	center_right.add_child(_build_palette_panel())


func _build_header() -> Control:
	var panel := PanelContainer.new()
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	panel.add_child(rows)

	# Row 1: title, File/Pipeline menus, and a persistent context readout so
	# the current tool/brush is always visible without hunting for the
	# pressed toggle.
	var menu_row := HBoxContainer.new()
	menu_row.add_theme_constant_override("separation", 6)
	rows.add_child(menu_row)
	var title := Label.new()
	title.text = "  WORLD FORGE"
	title.add_theme_font_size_override("font_size", 18)
	menu_row.add_child(title)
	menu_row.add_child(_build_file_menu())
	menu_row.add_child(_build_pipeline_menu())
	var menu_spacer := Control.new()
	menu_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_row.add_child(menu_spacer)
	_context_label = Label.new()
	_context_label.add_theme_color_override("font_color", Color(0.64, 0.71, 0.8))
	menu_row.add_child(_context_label)
	var menu_pad := Control.new()
	menu_pad.custom_minimum_size.x = 10.0
	menu_row.add_child(menu_pad)

	# Row 2: tools (hotkeys 1..7), layers, and mirror. The mirror plane
	# spinboxes only appear while mirroring is on.
	var tool_row := HBoxContainer.new()
	tool_row.add_theme_constant_override("separation", 6)
	rows.add_child(tool_row)
	_tool_button_row = tool_row
	tool_row.add_child(_row_caption("  Tools"))
	for index in TOOL_ORDER.size():
		var tool_id := TOOL_ORDER[index]
		var button := Button.new()
		button.text = tool_id.capitalize()
		button.tooltip_text = "%s tool (%d)" % [tool_id.capitalize(), index + 1]
		button.toggle_mode = true
		button.button_pressed = tool_id == _tool
		button.set_meta("tool", tool_id)
		button.pressed.connect(_select_tool.bind(tool_id, tool_row))
		tool_row.add_child(button)
	tool_row.add_child(VSeparator.new())
	tool_row.add_child(_row_caption("Layer"))
	_layer_spin = SpinBox.new()
	_layer_spin.min_value = 0
	_layer_spin.max_value = 128
	_layer_spin.tooltip_text = "Structure layer (Y) placement plane"
	_layer_spin.value_changed.connect(func(value: float) -> void:
		_active_layer = int(value)
		_refresh_grid()
		_update_context()
	)
	tool_row.add_child(_layer_spin)
	tool_row.add_child(_row_caption("Fine"))
	_fine_layer_spin = SpinBox.new()
	_fine_layer_spin.min_value = 0
	_fine_layer_spin.max_value = FINE_CELLS_PER_UNIT - 1
	_fine_layer_spin.tooltip_text = "Sub-cell height for part placement (Workshop fine grid)"
	_fine_layer_spin.value_changed.connect(func(value: float) -> void:
		_fine_layer = int(value)
	)
	tool_row.add_child(_fine_layer_spin)
	tool_row.add_child(VSeparator.new())
	tool_row.add_child(_row_caption("Mirror"))
	var mirror_selector := OptionButton.new()
	for entry: Array in [["Off", "off"], ["X", "x"], ["Z", "z"], ["X+Z", "xz"]]:
		mirror_selector.add_item(entry[0])
		mirror_selector.set_item_metadata(mirror_selector.item_count - 1, entry[1])
	mirror_selector.tooltip_text = "Mirror block placement and erase across the X and/or Z plane"
	mirror_selector.item_selected.connect(func(index: int) -> void:
		_mirror_mode = str(mirror_selector.get_item_metadata(index))
		var mirroring := _mirror_mode != "off"
		_mirror_x_spin.visible = _mirror_mode == "x" or _mirror_mode == "xz"
		_mirror_z_spin.visible = _mirror_mode == "z" or _mirror_mode == "xz"
		_refresh_grid()
		_set_status("Mirror: %s" % mirror_selector.get_item_text(index) if mirroring else "Mirror off")
	)
	tool_row.add_child(mirror_selector)
	_mirror_x_spin = SpinBox.new()
	_mirror_x_spin.min_value = -128
	_mirror_x_spin.max_value = 128
	_mirror_x_spin.tooltip_text = "Mirror plane X (the cell column that stays fixed)"
	_mirror_x_spin.visible = false
	_mirror_x_spin.value_changed.connect(func(value: float) -> void:
		_mirror_x = int(value)
		_refresh_grid()
	)
	tool_row.add_child(_mirror_x_spin)
	_mirror_z_spin = SpinBox.new()
	_mirror_z_spin.min_value = -128
	_mirror_z_spin.max_value = 128
	_mirror_z_spin.tooltip_text = "Mirror plane Z (the cell row that stays fixed)"
	_mirror_z_spin.visible = false
	_mirror_z_spin.value_changed.connect(func(value: float) -> void:
		_mirror_z = int(value)
		_refresh_grid()
	)
	tool_row.add_child(_mirror_z_spin)

	# Row 3: edit actions, with the destructive/major ones pushed right.
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	rows.add_child(action_row)
	action_row.add_child(_row_caption("  Edit"))
	_undo_button = _header_button("Undo", _undo)
	_redo_button = _header_button("Redo", _redo)
	action_row.add_child(_undo_button)
	action_row.add_child(_redo_button)
	action_row.add_child(VSeparator.new())
	for entry: Array in [["Copy", _copy_selection, "Ctrl+C"], ["Paste", _arm_paste, "Ctrl+V"], ["Move", _arm_move, "G"], ["Duplicate", _duplicate_selection, "Ctrl+D"], ["Rotate", _rotate_selection_or_brush, "R"], ["Replace", _replace_selection, ""], ["All", _select_all_blocks, "Ctrl+A"], ["Delete", _delete_selection, "Delete"]]:
		var button := _header_button(entry[0], entry[1])
		button.tooltip_text = "%s%s" % [entry[0], " (%s)" % entry[2] if not entry[2].is_empty() else ""]
		action_row.add_child(button)
	var action_spacer := Control.new()
	action_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(action_spacer)
	_finalize_button = _header_button("Finalize Blueprint", _finalize_nested_blueprints)
	_finalize_button.tooltip_text = "Bake staged nested blueprints into this document"
	action_row.add_child(_finalize_button)
	_update_context()
	return panel


## Dimmed group caption for header rows — replaces the old pattern of
## appending an anonymous Label and fishing it back out of the child list.
func _row_caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	return label


func _build_file_menu() -> MenuButton:
	var menu := MenuButton.new()
	menu.text = "File"
	menu.flat = false
	var popup := menu.get_popup()
	popup.add_item("New Blueprint", 0)
	popup.add_item("Open Selected", 1)
	popup.add_item("Save", 2)
	popup.set_item_tooltip(popup.get_item_index(2), "Ctrl+S while the viewport has focus")
	popup.add_item("Save As New Copy", 3)
	popup.add_separator()
	popup.add_item("Recover Autosave", 4)
	popup.add_item("Validate Document", 5)
	popup.add_separator()
	popup.add_item("Export Building Blueprint JSON", 6)
	popup.set_item_tooltip(popup.get_item_index(6), "Write this document as a game-ready BuildingBlueprint (res://data/buildings)")
	popup.id_pressed.connect(func(id: int) -> void:
		match id:
			0: _new_document()
			1: _open_selected_library_item()
			2: _save_document()
			3: _save_as_document()
			4: _recover_autosave()
			5: _validate_document()
			6: _export_building_blueprint()
	)
	return menu


## Asset/texture pipeline actions absorbed from the retired block editor
## dock: procedural block textures, the terrain texture array, and external
## asset pack imports.
func _build_pipeline_menu() -> MenuButton:
	var menu := MenuButton.new()
	menu.text = "Pipeline"
	menu.flat = false
	var popup := menu.get_popup()
	popup.add_item("Generate Block Textures", 0)
	popup.add_item("Rebuild Texture Array", 1)
	popup.add_separator()
	popup.add_item("Import KayKit Block Bits", 2)
	popup.add_item("Import KayKit Resource Bits", 3)
	popup.add_item("Import Kenney Voxel Pack", 4)
	popup.add_check_item("Allow Import Overwrite", 5)
	popup.add_separator()
	popup.add_item("Reload Block Palette", 6)
	popup.add_item("Generate Missing Thumbnails", 7)
	popup.id_pressed.connect(_on_pipeline_menu.bind(popup))
	return menu


func _on_pipeline_menu(id: int, popup: PopupMenu) -> void:
	match id:
		0:
			var report := TextureArrayPackerScript.new().generate_all()
			EditorInterface.get_resource_filesystem().scan()
			_set_status("Generated %d texture(s), %d failed" % [report.generated, report.failed])
			if report.failed > 0:
				push_error("Texture generation errors: %s" % report.errors)
		1:
			var report := TextureArrayPackerScript.new().pack()
			EditorInterface.get_resource_filesystem().scan()
			if report.failed > 0:
				_set_status("Texture array rebuild failed: %s" % report.errors)
				push_error("Texture array packing errors: %s" % report.errors)
			else:
				_set_status("Packed %d layer(s) → %s" % [report.packed, report.atlas_path])
		2: _run_external_import(ASSET_SOURCE_PATHS["kaykit_blocks"], _import_overwrite_enabled(popup))
		3: _run_external_import(ASSET_SOURCE_PATHS["kaykit_resources"], _import_overwrite_enabled(popup))
		4: _run_external_import(ASSET_SOURCE_PATHS["kenney_voxel"], _import_overwrite_enabled(popup))
		5:
			var index := popup.get_item_index(5)
			popup.set_item_checked(index, not popup.is_item_checked(index))
		6:
			_load_block_palette()
			_set_status("Block palette reloaded")
		7:
			var report: Dictionary = ThumbnailBackfillScript.generate_missing(_block_colors)
			var failed: Array = report["failed"]
			EditorInterface.get_resource_filesystem().scan()
			_invalidate_library_scan()
			_refresh_library()
			_set_status("Thumbnails: %d generated, %d skipped, %d failed" % [
				report["generated"], report["skipped"], failed.size(),
			])
			if not failed.is_empty():
				push_error("Thumbnail render failures: %s" % ", ".join(failed))


func _import_overwrite_enabled(popup: PopupMenu) -> bool:
	return popup.is_item_checked(popup.get_item_index(5))


func _run_external_import(source_path: String, allow_overwrite: bool) -> void:
	var source := load(source_path) as AssetSourceDefinition
	if source == null:
		_set_status("Missing asset source: %s" % source_path)
		return
	var report := AssetPackImporterScript.new().import_source(source, allow_overwrite)
	_set_status("%s: %d created, %d updated, %d skipped, %d failed" % [
		source.display_name, report.created, report.updated, report.skipped, report.failed,
	])
	if report.failed > 0:
		push_error("External asset import errors: %s" % report.errors)
	_load_block_palette()


## Header context readout: what a click will currently do, at a glance.
func _update_context() -> void:
	if _context_label == null:
		return
	var brush := ""
	match _place_kind:
		"block": brush = String(_selected_block_id)
		"component": brush = _selected_component_id
		"marker": brush = _selected_marker_id
		"part": brush = String(_selected_part_id)
	_context_label.text = "%s · %s: %s · layer %d" % [_tool.capitalize(), _place_kind, brush, _active_layer]


func _header_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	return button


func _build_library_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 280.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var heading := Label.new()
	heading.text = " BLUEPRINTS & SCENES"
	heading.add_theme_font_size_override("font_size", 15)
	box.add_child(heading)

	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	box.add_child(filter_row)
	_library_search = LineEdit.new()
	_library_search.placeholder_text = "Search…"
	_library_search.clear_button_enabled = true
	_library_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_search.text_changed.connect(func(_text: String) -> void: _refresh_library())
	filter_row.add_child(_library_search)
	_library_type_filter = OptionButton.new()
	_library_type_filter.add_item("All Types")
	_library_type_filter.set_item_metadata(0, "")
	for entry: Dictionary in _building_type_catalog():
		_library_type_filter.add_item(entry["label"])
		_library_type_filter.set_item_metadata(_library_type_filter.item_count - 1, entry["id"])
	_library_type_filter.item_selected.connect(func(_index: int) -> void: _refresh_library())
	filter_row.add_child(_library_type_filter)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_library_list = VBoxContainer.new()
	_library_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_library_list)

	# Only the two actions that operate on the selected card live here;
	# document-level actions (New/Save/Validate/...) live in the File menu.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	var open_button := Button.new()
	open_button.text = "Open"
	open_button.tooltip_text = "Open the selected blueprint for editing (clicking its card again also works)"
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button.pressed.connect(_open_selected_library_item)
	actions.add_child(open_button)
	var stage_button := Button.new()
	stage_button.text = "Stage"
	stage_button.tooltip_text = "Stage the selected blueprint as one piece, then click the grid to place it into the current document"
	stage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage_button.pressed.connect(_stage_selected_library_item)
	actions.add_child(stage_button)

	box.add_child(HSeparator.new())
	var current_heading := Label.new()
	current_heading.text = " CURRENT DOCUMENT"
	current_heading.add_theme_font_size_override("font_size", 12)
	current_heading.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
	box.add_child(current_heading)
	var identity := GridContainer.new()
	identity.columns = 2
	box.add_child(identity)
	identity.add_child(_small_label("Name"))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Blueprint name"
	_name_edit.text_submitted.connect(func(_text: String) -> void: _commit_identity())
	_name_edit.focus_exited.connect(_commit_identity)
	identity.add_child(_name_edit)
	identity.add_child(_small_label("ID"))
	_id_edit = LineEdit.new()
	_id_edit.placeholder_text = "blueprint_id"
	_id_edit.text_submitted.connect(func(_text: String) -> void: _commit_identity())
	_id_edit.focus_exited.connect(_commit_identity)
	identity.add_child(_id_edit)
	identity.add_child(_small_label("Template purpose"))
	_kind_selector = OptionButton.new()
	for entry: Array in [["Building", "building"], ["Encounter Camp", "encounter"], ["Discoverable Ruin", "ruin"], ["Generation Template", "generation"], ["Interior Assembly", "assembly"]]:
		_kind_selector.add_item(entry[0])
		_kind_selector.set_item_metadata(_kind_selector.item_count - 1, entry[1])
	_kind_selector.item_selected.connect(func(index: int) -> void:
		_document.template_kind = str(_kind_selector.get_item_metadata(index))
	)
	identity.add_child(_kind_selector)
	identity.add_child(_small_label("Building type"))
	_building_type_selector = OptionButton.new()
	for entry: Dictionary in _building_type_catalog():
		_building_type_selector.add_item(entry["label"])
		_building_type_selector.set_item_metadata(_building_type_selector.item_count - 1, entry["id"])
	_building_type_selector.tooltip_text = "Which module library this building belongs to — set automatically by Generate, or pick one for a hand-built document"
	_building_type_selector.item_selected.connect(func(index: int) -> void:
		if _updating_identity:
			return
		_document.building_type = str(_building_type_selector.get_item_metadata(index))
		_document.notify_changed()
	)
	identity.add_child(_building_type_selector)
	return panel


## Every module library plus a trailing "custom" catch-all, as
## {id, label} — shared by the browser's type filter and the current
## document's Building Type dropdown so both always list the same set.
func _building_type_catalog() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	for path in ModuleLibraryScript.list_library_paths():
		var library: Dictionary = ModuleLibraryScript.load_library(path)
		var id := str(library.get("id", path.get_file().get_basename()))
		catalog.append({"id": id, "label": str(library.get("display_name", id.capitalize()))})
	catalog.append({"id": "custom", "label": "Custom"})
	return catalog


func _small_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _build_viewport_panel() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Wrapped in a plain Control (not the VBoxContainer directly) so the
	# gamepad reticle can overlay the viewport as a sibling anchored to the
	# same rect, instead of stacking below it the way VBoxContainer would.
	var viewport_stack := Control.new()
	viewport_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(viewport_stack)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewport_container.gui_input.connect(_on_viewport_input)
	viewport_stack.add_child(_viewport_container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1000, 700)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	_viewport_container.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_content_root = Node3D.new()
	_content_root.name = "ForgeContent"
	_world.add_child(_content_root)
	_camera = Camera3D.new()
	_camera.fov = 48.0
	_world.add_child(_camera)
	_update_camera()
	_hover_mesh = Node3D.new()
	_hover_valid_material = _ghost_material(Color(0.35, 0.65, 1.0, 0.32))
	_hover_invalid_material = _ghost_material(Color(1.0, 0.25, 0.2, 0.38))
	_hover_select_material = _ghost_material(Color(1.0, 0.8, 0.25, 0.3))
	_hover_mesh.visible = false
	_world.add_child(_hover_mesh)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("161b22")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8c4d4")
	env.ambient_light_energy = 0.55
	# Filmic tonemapping + SSAO make the textured blocks read as solid
	# geometry instead of flat-lit color; both are cheap at this viewport
	# size and no-ops in headless test runs.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	environment.environment = env
	_world.add_child(environment)
	# Gamepad aim reticle: fixed at viewport center, matching how
	# _gamepad_place_or_select()/_gamepad_erase() resolve "where to act" -
	# there's no mouse cursor to hover with when playing entirely by
	# controller. Hidden until a joypad is actually detected (_process).
	_gamepad_reticle = Label.new()
	_gamepad_reticle.text = "+"
	_gamepad_reticle.add_theme_font_size_override("font_size", 26)
	_gamepad_reticle.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_gamepad_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_gamepad_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gamepad_reticle.visible = false
	viewport_stack.add_child(_gamepad_reticle)
	_status = Label.new()
	_status.text = "Ready"
	_status.custom_minimum_size.y = 26.0
	box.add_child(_status)
	return box


func _build_palette_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 280.0
	var box := VBoxContainer.new()
	panel.add_child(box)
	var heading := Label.new()
	heading.text = " PALETTE & GENERATION"
	heading.add_theme_font_size_override("font_size", 15)
	box.add_child(heading)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	tabs.add_child(_build_generate_tab())
	var blocks_tab := VBoxContainer.new()
	blocks_tab.name = "Blocks"
	var block_filters := HBoxContainer.new()
	blocks_tab.add_child(block_filters)
	_block_search = LineEdit.new()
	_block_search.placeholder_text = "Search blocks…"
	_block_search.clear_button_enabled = true
	_block_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_block_search.text_changed.connect(func(_text: String) -> void: _refresh_block_palette())
	block_filters.add_child(_block_search)
	_block_category = OptionButton.new()
	_block_category.item_selected.connect(func(_index: int) -> void: _refresh_block_palette())
	block_filters.add_child(_block_category)
	_shape_selector = OptionButton.new()
	for shape: Dictionary in _shapes:
		_shape_selector.add_item(shape["name"])
		_shape_selector.set_item_metadata(_shape_selector.item_count - 1, shape["id"])
	_shape_selector.item_selected.connect(func(index: int) -> void:
		_selected_shape_id = str(_shape_selector.get_item_metadata(index))
		_set_status("Shape: %s · rotation %d°" % [_selected_shape_id, _brush_rotation * 90])
	)
	block_filters.add_child(_shape_selector)
	_block_list = _palette_list("BlockList")
	_block_list.item_selected.connect(_on_block_selected)
	blocks_tab.add_child(_block_list)
	tabs.add_child(blocks_tab)
	var components_tab := VBoxContainer.new()
	components_tab.name = "Components"
	var component_search := LineEdit.new()
	component_search.placeholder_text = "Search components…"
	component_search.clear_button_enabled = true
	components_tab.add_child(component_search)
	_component_list = _palette_list("ComponentList")
	_component_list.item_selected.connect(_on_component_selected)
	_filter_catalog_list("", _component_list, _components)
	component_search.text_changed.connect(_filter_catalog_list.bind(_component_list, _components))
	components_tab.add_child(_component_list)
	tabs.add_child(components_tab)
	var markers_tab := VBoxContainer.new()
	markers_tab.name = "Markers"
	var marker_search := LineEdit.new()
	marker_search.placeholder_text = "Search markers…"
	marker_search.clear_button_enabled = true
	markers_tab.add_child(marker_search)
	_marker_list = _palette_list("MarkerList")
	_marker_list.item_selected.connect(_on_marker_selected)
	_filter_catalog_list("", _marker_list, _markers)
	marker_search.text_changed.connect(_filter_catalog_list.bind(_marker_list, _markers))
	markers_tab.add_child(_marker_list)
	tabs.add_child(markers_tab)
	var parts_tab := VBoxContainer.new()
	parts_tab.name = "Parts"
	var part_search := LineEdit.new()
	part_search.placeholder_text = "Search parts…"
	part_search.clear_button_enabled = true
	parts_tab.add_child(part_search)
	_part_list = _palette_list("PartList")
	_part_list.item_selected.connect(_on_part_selected)
	_filter_catalog_list("", _part_list, _parts)
	part_search.text_changed.connect(_filter_catalog_list.bind(_part_list, _parts))
	parts_tab.add_child(_part_list)
	tabs.add_child(parts_tab)
	var items := VBoxContainer.new()
	items.name = "Items"
	var item_help := Label.new()
	item_help.text = "Item display slots and recipe parts live here. They remain separate from structural blocks so stored goods can appear, move, and disappear during simulation."
	item_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	items.add_child(item_help)
	tabs.add_child(items)
	var rules := VBoxContainer.new()
	rules.name = "Rules"
	var rule_help := Label.new()
	rule_help.text = "Rule channels\n\nHeat · burns or heats neighbors\nFluid · flows or drives components\nForce · supports, turns, or breaks\nPower · supplies machine capability\nVisibility · cutaway and simulation LOD\n\nRules are saved as blueprint metadata; the runtime evaluator is the next milestone."
	rule_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_child(rule_help)
	tabs.add_child(rules)
	return panel


func _palette_list(name: String) -> ItemList:
	var list := ItemList.new()
	list.name = name
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.allow_reselect = true
	return list


func _filter_catalog_list(query: String, list: ItemList, catalog: Array[Dictionary]) -> void:
	list.clear()
	var needle := query.strip_edges().to_lower()
	for entry: Dictionary in catalog:
		if not needle.is_empty() and needle not in (str(entry.get("name", "")) + " " + str(entry.get("id", ""))).to_lower():
			continue
		list.add_item(str(entry.get("name", entry.get("id", "Unknown"))))
		list.set_item_metadata(list.item_count - 1, entry.get("id", ""))
		if entry.get("color") is Color:
			list.set_item_icon(list.item_count - 1, _swatch_icon(entry["color"]))


## Solid-color square used as an ItemList icon (size 12, palette entries) or
## as a placeholder blueprint-browser thumbnail (size 48, no render yet) so
## entries can be told apart at a glance either way. Cached per color+size.
func _swatch_icon(color: Color, size: int = 12) -> ImageTexture:
	var key := "%s|%d" % [color.to_html(), size]
	if _swatch_cache.has(key):
		return _swatch_cache[key]
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(color)
	var texture := ImageTexture.create_from_image(image)
	_swatch_cache[key] = texture
	return texture


# --- Generate (WFC) -----------------------------------------------------------

## One-click WFC building generation (module libraries in
## data/buildings/module_libraries). Generated blocks are written into the
## current document as a single undoable transaction, so every Forge tool
## (select/move/mirror/replace/...) works on the result immediately.
func _build_generate_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Generate"
	box.add_theme_constant_override("separation", 6)
	var help := Label.new()
	help.text = "Generate a building shell with WFC as a starting point, then refine it with the normal tools and export it as a game blueprint."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(_small_label("Type"))
	_gen_type = OptionButton.new()
	_gen_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gen_type.item_selected.connect(func(_index: int) -> void: _refresh_generate_tiers())
	grid.add_child(_gen_type)
	grid.add_child(_small_label("Tier"))
	_gen_tier = OptionButton.new()
	_gen_tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_gen_tier)
	grid.add_child(_small_label("Seed"))
	_gen_seed = SpinBox.new()
	_gen_seed.min_value = 0
	_gen_seed.max_value = 999999999
	_gen_seed.tooltip_text = "0 = random. Any other value reproduces the exact same building."
	_gen_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_gen_seed)
	_gen_clear_check = CheckBox.new()
	_gen_clear_check.text = "Replace current blocks"
	_gen_clear_check.tooltip_text = "On: the document's blocks are replaced and its name/ID follow the generated building.\nOff: generated blocks merge into whatever is already placed."
	_gen_clear_check.button_pressed = true
	box.add_child(_gen_clear_check)
	var generate_button := Button.new()
	generate_button.text = "Generate Building"
	generate_button.custom_minimum_size.y = 34.0
	generate_button.pressed.connect(_on_generate_building)
	box.add_child(generate_button)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var reroll := Button.new()
	reroll.text = "Reroll"
	reroll.tooltip_text = "Generate again with a fresh random seed"
	reroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reroll.pressed.connect(func() -> void:
		_gen_seed.value = 0
		_on_generate_building()
	)
	row.add_child(reroll)
	var rescan := Button.new()
	rescan.text = "Rescan"
	rescan.tooltip_text = "Re-read module libraries from data/buildings/module_libraries"
	rescan.pressed.connect(_refresh_generate_libraries)
	row.add_child(rescan)
	_gen_result = Label.new()
	_gen_result.text = "No building generated yet."
	_gen_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_gen_result)
	var export_button := Button.new()
	export_button.text = "Export Building Blueprint JSON"
	export_button.tooltip_text = "Write the current document as a game-ready BuildingBlueprint to res://data/buildings"
	export_button.pressed.connect(_export_building_blueprint)
	box.add_child(export_button)
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(filler)
	_refresh_generate_libraries()
	return box


func _refresh_generate_libraries() -> void:
	_gen_library_paths = ModuleLibraryScript.list_library_paths()
	_gen_type.clear()
	for path in _gen_library_paths:
		var library: Dictionary = ModuleLibraryScript.load_library(path)
		_gen_type.add_item(String(library.get("display_name", path.get_file())))
	_refresh_generate_tiers()


func _refresh_generate_tiers() -> void:
	_gen_tier.clear()
	var library := _selected_generate_library()
	for tier: Dictionary in library.get("tiers", []):
		var tier_number := int(tier.get("tier", 0))
		_gen_tier.add_item("T%d · %s" % [tier_number, String(tier.get("name", ""))], tier_number)


func _selected_generate_library() -> Dictionary:
	var index := _gen_type.selected
	if index < 0 or index >= _gen_library_paths.size():
		return {}
	# Reload on use so JSON edits are picked up without restarting.
	return ModuleLibraryScript.load_library(_gen_library_paths[index])


func _on_generate_building() -> void:
	var library := _selected_generate_library()
	if library.is_empty():
		_set_status("No module library selected — add JSON files under data/buildings/module_libraries")
		return
	var tier_number := _gen_tier.get_selected_id() if _gen_tier.selected >= 0 else 1
	var result: Dictionary = WFCGeneratorScript.new().generate(library, tier_number, int(_gen_seed.value))
	if result.has("error"):
		_set_status("Generation failed: %s" % result["error"])
		return
	var blueprint: Dictionary = result["blueprint"]
	var stats: Dictionary = result["stats"]
	var replace: bool = _gen_clear_check.button_pressed
	_transact("Generate %s" % blueprint["id"], func() -> void:
		if replace:
			_document.blocks.clear()
		for block: Dictionary in blueprint["blocks"]:
			var pos: Array = block["pos"]
			_document.set_block(Vector3i(int(pos[0]), int(pos[1]), int(pos[2])), {
				"block_id": String(block["block_id"]),
				"shape_id": String(block.get("shape_id", "cube")),
				"rotation_steps": int(block.get("rotation_steps", 0)),
				"layer": String(block.get("layer", "structure")),
				"tags": block.get("tags", []),
				"build_stage": String(block.get("build_stage", "wall")),
			})
		# Everything the game blueprint needs beyond raw blocks (sockets,
		# interior air cells, health, generator seed) rides along in document
		# metadata and comes back out via _export_building_blueprint().
		var meta: Dictionary = blueprint.duplicate(true)
		meta.erase("blocks")
		_document.metadata["building"] = meta
	)
	if replace:
		_document.document_id = String(blueprint["id"])
		_document.display_name = String(blueprint["display_name"])
		_document.template_kind = "building"
		_document.building_type = str(library.get("id", "custom"))
		_sync_identity_fields()
	var size: Array = stats["size"]
	_gen_result.text = "Seed %d · %d×%d×%d · %d blocks · interior %d cells\nCost: %s" % [
		int(stats["seed"]), int(size[0]), int(size[1]), int(size[2]),
		int(stats["total_blocks"]), int(stats["interior_volume"]),
		stats["block_counts"],
	]
	_set_status("Generated %s (%d blocks, seed %d) — undo to discard" % [blueprint["id"], int(stats["total_blocks"]), int(stats["seed"])])


## Converts the current document into the BuildingBlueprint JSON the game
## loads (BuildingBlueprintLoader/ConstructionSite) and saves it under
## res://data/buildings. Metadata captured at generation time (sockets,
## interior cells, health, generator seed) is preserved; footprint is
## recomputed from the blocks actually present so hand edits count.
func _export_building_blueprint() -> void:
	_commit_identity()
	if _document.blocks.is_empty():
		_set_status("Nothing to export — place or generate blocks first")
		return
	var meta_variant: Variant = _document.metadata.get("building", {})
	var meta: Dictionary = meta_variant if meta_variant is Dictionary else {}
	var blocks: Array = []
	var max_x := 0
	var max_z := 0
	for key: String in _document.blocks:
		var cell := DocumentScript.key_cell(key)
		var block: Dictionary = _document.blocks[key]
		var block_id := str(block.get("block_id", ""))
		if block_id.is_empty() or block_id == "air":
			continue
		var layer := str(block.get("layer", "wall"))
		if layer == "structure":
			layer = "wall"
		blocks.append({
			"pos": [cell.x, cell.y, cell.z],
			"block_id": block_id,
			"shape_id": str(block.get("shape_id", "cube")),
			"rotation_steps": int(block.get("rotation_steps", 0)),
			"layer": layer,
			"tags": block.get("tags", []),
			"build_stage": str(block.get("build_stage", layer)),
			"requires_support": cell.y > 0,
		})
		max_x = maxi(max_x, cell.x)
		max_z = maxi(max_z, cell.z)
	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["pos"] < b["pos"])
	# Recomputed from the blocks actually present (not generation metadata)
	# so hand-placed or deleted lights are reflected.
	var lights: Array = []
	for block: Dictionary in blocks:
		if "light" in (block["tags"] as Array):
			lights.append({"pos": block["pos"], "block_id": block["block_id"]})
	var data := {
		"id": _document.document_id,
		"display_name": _document.display_name,
		"category": str(meta.get("category", "production")),
		"era": str(meta.get("era", "village")),
		"footprint": [max_x + 1, max_z + 1],
		"health": int(meta.get("health", 100)),
		"workers_required": int(meta.get("workers_required", 1)),
		"required_functional_tags": meta.get("required_functional_tags", []),
		"blocks": blocks,
		"sockets": meta.get("sockets", []),
		"storage_slots": meta.get("storage_slots", []),
		"recipes": meta.get("recipes", []),
	}
	if meta.has("interior_cells"):
		data["interior_cells"] = meta["interior_cells"]
	if meta.has("generator"):
		data["generator"] = meta["generator"]
	data["lights"] = lights
	var path := "res://data/buildings/%s_blueprint.json" % _document.document_id
	var error: Error = BlueprintSerializerScript.save_blueprint_json(path, data)
	if error != OK:
		_set_status("Export failed (%s): %s" % [error_string(error), path])
		return
	_refresh_thumbnail(blocks)
	EditorInterface.get_resource_filesystem().scan()
	_invalidate_library_scan()
	_refresh_library()
	_set_status("Exported %d blocks → %s" % [blocks.size(), path])


func _load_block_palette() -> void:
	_block_catalog.clear()
	_block_colors.clear()
	_block_texture_info.clear()
	_block_materials.clear()
	_block_light_info.clear()
	var registry := BlockRegistry.new()
	registry.load_blocks()
	for block_id: StringName in registry.list_ids():
		if block_id == &"air":
			continue
		var definition := registry.get_block(block_id)
		_block_catalog.append({"id": block_id, "name": definition.display_name, "category": str(definition.category)})
		_block_colors[block_id] = definition.albedo_color
		if definition.light_energy > 0.0:
			_block_light_info[block_id] = {
				"color": definition.light_color,
				"energy": definition.light_energy,
				"range": definition.light_range,
				"flame": definition.flame_effect,
			}
		# The editor renders each block with one triplanar texture, so pick
		# the most representative face layer: the top if authored (grass
		# should read as grass, not its dirt side band), else the side.
		var layer := definition.texture_top if definition.texture_top != &"" else definition.texture_side
		_block_texture_info[block_id] = {
			"layer": String(layer),
			"scale": definition.texture_scale,
			"roughness": definition.roughness,
			"albedo_texture": definition.albedo_texture,
		}
	registry.free()
	_block_category.clear()
	_block_category.add_item("All")
	var categories := {}
	for block: Dictionary in _block_catalog:
		categories[block["category"]] = true
	var category_names := categories.keys()
	category_names.sort()
	for category: String in category_names:
		_block_category.add_item(category.capitalize())
		_block_category.set_item_metadata(_block_category.item_count - 1, category)
	_refresh_block_palette()


func _refresh_block_palette() -> void:
	if _block_list == null:
		return
	_block_list.clear()
	var query := _block_search.text.strip_edges().to_lower() if _block_search else ""
	var category := ""
	if _block_category and _block_category.selected > 0:
		category = str(_block_category.get_item_metadata(_block_category.selected))
	for block: Dictionary in _block_catalog:
		if category != "" and block["category"] != category:
			continue
		if query != "" and query not in (str(block["name"]) + " " + str(block["id"])).to_lower():
			continue
		_block_list.add_item(block["name"])
		_block_list.set_item_metadata(_block_list.item_count - 1, block["id"])
		var swatch_color: Variant = _block_colors.get(block["id"], Color(0.5, 0.5, 0.5))
		if swatch_color is Color:
			_block_list.set_item_icon(_block_list.item_count - 1, _swatch_icon(swatch_color))


## Rebuilds the blueprint browser as a scrollable list of preview cards,
## grouped by template purpose (Buildings/Assemblies/...), filtered by the
## search box and the Building Type dropdown. Empty groups are skipped
## entirely rather than shown as dead headers.
func _refresh_library() -> void:
	if _library_list == null:
		return
	for child: Node in _library_list.get_children():
		child.queue_free()
	_library_cards.clear()

	var search := _library_search.text.strip_edges().to_lower() if _library_search else ""
	var type_filter := ""
	if _library_type_filter and _library_type_filter.selected > 0:
		type_filter = str(_library_type_filter.get_item_metadata(_library_type_filter.selected))

	var group_order := ["Buildings", "Assemblies", "Encounters", "Ruins", "Generation", "Built"]
	var grouped := {}
	for group in group_order:
		grouped[group] = []

	for entry: Dictionary in _scanned_library_entries():
		if search != "" and search not in str(entry["path"]).to_lower():
			continue
		if type_filter != "" and entry["building_type"] != type_filter:
			continue
		(grouped[entry["category_label"]] as Array).append(entry)

	for group in group_order:
		var entries: Array = grouped[group]
		if entries.is_empty():
			continue
		var header := Label.new()
		header.text = group
		header.add_theme_font_size_override("font_size", 12)
		header.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
		_library_list.add_child(header)
		for entry: Dictionary in entries:
			var card := _make_library_card(entry)
			_library_cards.append(card)
			_library_list.add_child(card)


## Resolves which module library a blueprint belongs to, for the Building
## Type filter/dropdown. Checks, in order: an explicit "building_type" field
## (ForgeDocument saves), generation metadata nested under a Forge document's
## metadata.building (a document that's been through Generate but not yet
## exported), then a top-level "generator" block (exported BuildingBlueprint
## JSON) - falling back to "custom" for anything hand-built.
func _entry_building_type(data: Dictionary) -> String:
	if data.has("building_type"):
		var explicit := str(data["building_type"])
		if not explicit.is_empty():
			return explicit
	var metadata_variant: Variant = data.get("metadata", {})
	if metadata_variant is Dictionary:
		var building_meta: Variant = (metadata_variant as Dictionary).get("building", {})
		if building_meta is Dictionary:
			var generator: Variant = (building_meta as Dictionary).get("generator", {})
			if generator is Dictionary and (generator as Dictionary).has("library"):
				return str((generator as Dictionary)["library"])
	var top_generator: Variant = data.get("generator", {})
	if top_generator is Dictionary and (top_generator as Dictionary).has("library"):
		return str((top_generator as Dictionary)["library"])
	return "custom"


## Bounding-box size of a blueprint's placed blocks, used for the card
## subtitle. Works for both ForgeDocument saves and exported BuildingBlueprint
## JSON since both store blocks as an array of {"pos": [x,y,z], ...}.
func _entry_block_bounds(data: Dictionary) -> Vector3i:
	var blocks_variant: Variant = data.get("blocks", [])
	if not (blocks_variant is Array) or (blocks_variant as Array).is_empty():
		return Vector3i.ONE
	var min_pos := Vector3i(2147483647, 2147483647, 2147483647)
	var max_pos := Vector3i(-2147483648, -2147483648, -2147483648)
	for block: Variant in blocks_variant:
		if not block is Dictionary:
			continue
		var pos: Array = (block as Dictionary).get("pos", [0, 0, 0])
		if pos.size() != 3:
			continue
		var cell := Vector3i(int(pos[0]), int(pos[1]), int(pos[2]))
		min_pos = Vector3i(mini(min_pos.x, cell.x), mini(min_pos.y, cell.y), mini(min_pos.z, cell.z))
		max_pos = Vector3i(maxi(max_pos.x, cell.x), maxi(max_pos.y, cell.y), maxi(max_pos.z, cell.z))
	return max_pos - min_pos + Vector3i.ONE


## One clickable browser entry: a cached preview thumbnail (or a building-type
## colored placeholder swatch until one exists) plus name and a stats line.
## Built as a toggle Button with the visible content as a child overlay
## (mouse_filter IGNORE on every child) so the whole row is one click target
## while still laying out an icon + two-line label.
func _make_library_card(entry: Dictionary) -> Button:
	var card := Button.new()
	card.toggle_mode = true
	card.button_pressed = entry["path"] == _selected_library_item_path
	card.custom_minimum_size.y = 56.0
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.focus_mode = Control.FOCUS_NONE
	card.set_meta("path", entry["path"])
	card.pressed.connect(_on_library_card_pressed.bind(entry["path"]))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6.0
	row.offset_right = -6.0
	card.add_child(row)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(48, 48)
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cached_texture: Texture2D = _load_thumbnail_texture(entry["thumbnail_path"])
	thumb.texture = cached_texture if cached_texture != null else _swatch_icon(_building_type_color(entry["building_type"]), 48)
	row.add_child(thumb)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_box)
	var name_label := Label.new()
	name_label.text = str(entry["display_name"])
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(name_label)
	var subtitle := Label.new()
	var size: Vector3i = entry["size"]
	subtitle.text = "%s · %s · %d×%d×%d · %d blocks" % [
		entry["building_type_label"], entry["category_label"], size.x, size.y, size.z, entry["block_count"],
	]
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color(0.62, 0.68, 0.76))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(subtitle)

	return card


## Reads a cached thumbnail PNG's raw pixels directly, bypassing load()/the
## resource-import pipeline entirely - a thumbnail just written this same
## session has no .import sidecar yet, so load() fails until the next
## filesystem scan settles. Returns null (not an empty texture) on any
## failure so callers can fall back to the placeholder swatch.
func _load_thumbnail_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null  # The common case (no thumbnail yet) — checked first so
			# Image.load_from_file never logs an engine-level error for it.
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


## Deterministic placeholder color per building type (stable hash -> hue),
## so untagged/un-rendered entries are still visually distinguishable from
## each other before a thumbnail exists.
func _building_type_color(building_type: String) -> Color:
	var hash_value := building_type.hash()
	var hue := float(hash_value % 360) / 360.0
	return Color.from_hsv(hue, 0.45, 0.62)


func _on_library_card_pressed(path: String) -> void:
	if _selected_library_item_path == path:
		_open_selected_library_item()
		return
	_selected_library_item_path = path
	for card in _library_cards:
		card.button_pressed = str(card.get_meta("path")) == path


## Disk scan + JSON parse + field resolution for every library entry -
## memoized, since it's by far the expensive part of _refresh_library() (110+
## files in this project) and search/type-filter changes shouldn't re-read
## every file from disk on every keystroke. Invalidated by _invalidate_library_scan()
## whenever a save/export could have added, removed, or renamed a file.
##
## static so every World Forge main-screen instance in the process shares one
## scan: harmless for real usage (one editor session, one set of files on
## disk) and essential for the test suite, which constructs this Control
## repeatedly - without sharing, each instantiation re-scans all 110+ files.
static var _library_scan_cache: Array[Dictionary] = []
static var _library_scan_dirty := true

func _scanned_library_entries() -> Array[Dictionary]:
	if not _library_scan_dirty:
		return _library_scan_cache
	var paths: Array[String] = []
	_collect_json("res://data/buildings", paths)
	_collect_json("res://data/world_forge", paths)
	paths.sort()

	var type_labels := {}
	for entry: Dictionary in _building_type_catalog():
		type_labels[entry["id"]] = entry["label"]
	var group_key_by_kind := {"assembly": "Assemblies", "encounter": "Encounters", "ruin": "Ruins", "generation": "Generation", "built": "Built"}

	_library_scan_cache.clear()
	for path: String in paths:
		var data := _read_json(path)
		if data.is_empty():
			continue
		var building_type := _entry_building_type(data)
		var kind := str(data.get("template_kind", data.get("category", "building")))
		var group: String = group_key_by_kind.get(kind, "Buildings")
		var entry_id := str(data.get("id", path.get_file().get_basename()))
		_library_scan_cache.append({
			"path": path,
			"display_name": str(data.get("display_name", entry_id.capitalize())),
			"category_label": group,
			"building_type": building_type,
			"building_type_label": str(type_labels.get(building_type, building_type.capitalize())),
			"size": _entry_block_bounds(data),
			"block_count": (data.get("blocks", []) as Array).size(),
			"thumbnail_path": "res://data/buildings/thumbnails/%s.png" % entry_id,
		})
	_library_scan_dirty = false
	return _library_scan_cache


func _invalidate_library_scan() -> void:
	_library_scan_dirty = true


func _collect_json(folder: String, output: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file_name: String in DirAccess.get_files_at(folder):
		if file_name.ends_with(".json"):
			output.append(folder.path_join(file_name))
	for child: String in DirAccess.get_directories_at(folder):
		_collect_json(folder.path_join(child), output)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _selected_library_path() -> String:
	return _selected_library_item_path


func _new_document() -> void:
	_autosave_now()
	_document.changed.disconnect(_on_document_changed)
	_document = DocumentScript.new()
	_document.changed.connect(_on_document_changed)
	_history.clear()
	_current_path = ""
	_dirty = false
	_clear_selection()
	_refresh_world()
	_sync_identity_fields()
	_set_status("New blueprint")


func _open_selected_library_item() -> void:
	var path := _selected_library_path()
	if path.is_empty():
		_set_status("Select a blueprint file first")
		return
	var loaded: ForgeDocument = DocumentScript.load_json(path)
	if loaded == null:
		_set_status("Could not load %s" % path)
		return
	_autosave_now()
	_document.changed.disconnect(_on_document_changed)
	_document = loaded
	_document.changed.connect(_on_document_changed)
	_current_path = path
	_history.clear()
	_dirty = false
	_clear_selection()
	_refresh_world()
	_sync_identity_fields()
	_set_status("Opened %s" % loaded.display_name)


func _stage_selected_library_item() -> void:
	var path := _selected_library_path()
	if path.is_empty():
		_set_status("Select a blueprint to stage")
		return
	_staged_blueprint_path = path
	_paste_armed = false
	_set_status("Blueprint staged as one piece — click the grid to place it")


func _save_document() -> void:
	_commit_identity()
	if _current_path.is_empty():
		_current_path = "res://data/world_forge/%s.json" % _document.document_id
	var error := _document.save_json(_current_path)
	if error != OK:
		_set_status("Save failed: %s" % error_string(error))
		return
	_dirty = false
	if _autosave_timer:
		_autosave_timer.stop()
	if not _document.blocks.is_empty():
		_refresh_thumbnail(_document.blocks.values())
	EditorInterface.get_resource_filesystem().scan()
	_invalidate_library_scan()
	_refresh_library()
	_set_status("Saved %s" % _current_path)


## Renders and caches the browser preview icon for the current document's id.
## Purely synchronous (see BlueprintThumbnailRenderer) so it's safe to call
## right inside Save/Export with no async/frame-timing concerns.
func _refresh_thumbnail(blocks: Array) -> void:
	ThumbnailRendererScript.render_and_save(blocks, _block_colors,
			"res://data/buildings/thumbnails/%s.png" % _document.document_id)


func _save_as_document() -> void:
	_current_path = ""
	_save_document()


func _commit_identity() -> void:
	if _updating_identity or _name_edit == null or _id_edit == null:
		return
	var new_name := _name_edit.text.strip_edges()
	var new_id := _sanitize_id(_id_edit.text)
	if new_name.is_empty():
		new_name = "New Blueprint"
	if new_id.is_empty():
		new_id = "new_blueprint"
	if new_name == _document.display_name and new_id == _document.document_id:
		return
	_document.display_name = new_name
	_document.document_id = new_id
	_sync_identity_fields()
	_document.notify_changed()


func _sanitize_id(value: String) -> String:
	var result := value.strip_edges().to_lower().replace(" ", "_")
	var valid := "abcdefghijklmnopqrstuvwxyz0123456789_-"
	var clean := ""
	for character: String in result:
		if character in valid:
			clean += character
	return clean


func _sync_identity_fields() -> void:
	if _name_edit == null or _id_edit == null:
		return
	_updating_identity = true
	_name_edit.text = _document.display_name
	_id_edit.text = _document.document_id
	if _kind_selector:
		for index in _kind_selector.item_count:
			if str(_kind_selector.get_item_metadata(index)) == _document.template_kind:
				_kind_selector.selected = index
				break
	if _building_type_selector:
		_building_type_selector.selected = _building_type_selector.item_count - 1  # "custom" fallback
		for index in _building_type_selector.item_count:
			if str(_building_type_selector.get_item_metadata(index)) == _document.building_type:
				_building_type_selector.selected = index
				break
	_updating_identity = false


func _on_document_changed() -> void:
	_dirty = true
	_refresh_world()
	if _autosave_timer and _autosave_timer.is_inside_tree():
		_autosave_timer.start()


func _autosave_now() -> void:
	if not _dirty or _document == null:
		return
	var error := _document.save_json(AUTOSAVE_PATH)
	if error != OK:
		_set_status("Autosave failed: %s" % error_string(error))


func _recover_autosave() -> void:
	var loaded := DocumentScript.load_json(AUTOSAVE_PATH)
	if loaded == null:
		_set_status("No World Forge autosave found")
		return
	_document.changed.disconnect(_on_document_changed)
	_document = loaded
	_document.changed.connect(_on_document_changed)
	_history.clear()
	_current_path = ""
	_dirty = true
	_clear_selection()
	_refresh_world()
	_sync_identity_fields()
	_set_status("Recovered autosave — use Save As to keep it")


func _validate_document() -> void:
	var issues := _document_issues()
	if issues.is_empty():
		_set_status("Validation passed")
		return
	var preview := "; ".join(Array(issues).slice(0, 3))
	if issues.size() > 3:
		preview += "; +%d more" % (issues.size() - 3)
	_set_status("Validation: %s" % preview)
	push_warning("World Forge validation for %s:\n- %s" % [_document.document_id, "\n- ".join(issues)])


func _document_issues() -> PackedStringArray:
	var issues := PackedStringArray()
	if _document.document_id.is_empty():
		issues.append("missing document ID")
	var known_blocks := {}
	for entry: Dictionary in _block_catalog:
		known_blocks[str(entry.get("id", ""))] = true
	for key: String in _document.blocks:
		var block_id := str(_document.blocks[key].get("block_id", ""))
		if not known_blocks.has(block_id):
			issues.append("unknown block '%s' at %s" % [block_id, key])
	var component_ids := {}
	for component: Dictionary in _document.components:
		var instance_id := str(component.get("id", ""))
		if instance_id.is_empty() or component_ids.has(instance_id):
			issues.append("missing or duplicate component instance ID")
		component_ids[instance_id] = true
		var type_id := str(component.get("component_id", ""))
		if _find_definition(_components, type_id).is_empty():
			issues.append("unknown component '%s'" % type_id)
	var marker_ids := {}
	for marker: Dictionary in _document.markers:
		var instance_id := str(marker.get("id", ""))
		if instance_id.is_empty() or marker_ids.has(instance_id):
			issues.append("missing or duplicate marker instance ID")
		marker_ids[instance_id] = true
		var type_id := str(marker.get("marker_type", ""))
		if _find_definition(_markers, type_id).is_empty():
			issues.append("unknown marker '%s'" % type_id)
	for key: String in _document.placed_parts:
		var part_id := StringName(_document.placed_parts[key].get("part_id", ""))
		if _part_registry == null or _part_registry.get_part(part_id) == null:
			issues.append("unknown part '%s' at %s" % [part_id, key])
	for instance: Dictionary in _document.nested_instances:
		var source_path := str(instance.get("source_path", ""))
		if source_path.is_empty() or not FileAccess.file_exists(source_path):
			issues.append("missing nested blueprint source '%s'" % source_path)
	return issues


func _select_tool(tool: String, toolbar: HBoxContainer) -> void:
	_tool = tool
	_anchor_cell = null
	for child: Node in toolbar.get_children():
		if child is Button and child.has_meta("tool"):
			(child as Button).button_pressed = child.get_meta("tool") == tool
	_update_context()
	_set_status("%s tool" % tool.capitalize())


func _cancel_pending_action() -> void:
	_anchor_cell = null
	_paste_armed = false
	_move_armed = false
	_move_nested_armed = false
	_move_source_keys.clear()
	_move_entity_kind = ""
	_move_entity_id = ""
	_staged_blueprint_path = ""
	if _hover_mesh:
		_hover_mesh.visible = false
	_set_status("Cancelled pending action")


func _on_block_selected(index: int) -> void:
	_selected_block_id = StringName(_block_list.get_item_metadata(index))
	_place_kind = "block"
	_tool = "place"
	_update_context()
	_set_status("Placing block: %s" % _selected_block_id)


func _on_component_selected(index: int) -> void:
	_selected_component_id = str(_component_list.get_item_metadata(index))
	_place_kind = "component"
	_tool = "place"
	_update_context()
	_set_status("Placing component: %s" % _selected_component_id)


func _on_marker_selected(index: int) -> void:
	_selected_marker_id = str(_marker_list.get_item_metadata(index))
	_place_kind = "marker"
	_tool = "place"
	_update_context()
	_set_status("Placing marker: %s" % _selected_marker_id)


func _on_part_selected(index: int) -> void:
	_selected_part_id = StringName(_part_list.get_item_metadata(index))
	_place_kind = "part"
	_tool = "place"
	_update_context()
	_set_status("Placing part: %s (1/8-cell grid + socket snapping)" % _selected_part_id)


func _on_viewport_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			_undo()
			accept_event()
		elif event.ctrl_pressed and (event.keycode == KEY_Y or (event.shift_pressed and event.keycode == KEY_Z)):
			_redo()
			accept_event()
		elif event.ctrl_pressed and event.keycode == KEY_C:
			_copy_selection()
			accept_event()
		elif event.ctrl_pressed and event.keycode == KEY_V:
			_arm_paste()
			accept_event()
		elif event.ctrl_pressed and event.keycode == KEY_A:
			_select_all_blocks()
			accept_event()
		elif event.ctrl_pressed and event.keycode == KEY_D:
			_duplicate_selection()
			accept_event()
		elif event.keycode == KEY_G:
			_arm_move()
			accept_event()
		elif event.keycode == KEY_ESCAPE:
			_cancel_pending_action()
			accept_event()
		elif event.keycode == KEY_R:
			_rotate_selection_or_brush()
			accept_event()
		elif event.keycode == KEY_DELETE:
			_delete_selection()
			accept_event()
		elif event.ctrl_pressed and event.keycode == KEY_S:
			_save_document()
			accept_event()
		elif not event.ctrl_pressed and event.keycode >= KEY_1 and event.keycode <= KEY_7:
			_select_tool(TOOL_ORDER[event.keycode - KEY_1], _tool_button_row)
			accept_event()
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _orbiting:
			_camera_yaw -= motion.relative.x * 0.008
			_camera_pitch = clampf(_camera_pitch - motion.relative.y * 0.008, deg_to_rad(12.0), deg_to_rad(82.0))
			_update_camera()
		elif _panning:
			var scale := _camera_distance * 0.0025
			var right := _camera.global_basis.x
			var forward := Vector3(-right.z, 0, right.x)
			_camera_focus += (-right * motion.relative.x + forward * motion.relative.y) * scale
			_update_camera()
		else:
			_update_hover(motion.position)
		return
	if not event is InputEventMouseButton or not event.pressed:
		if event is InputEventMouseButton:
			var released := event as InputEventMouseButton
			if released.button_index == MOUSE_BUTTON_MIDDLE:
				_orbiting = false
				_panning = false
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_camera_distance = maxf(4.0, _camera_distance * 0.88)
		_update_camera()
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_camera_distance = minf(80.0, _camera_distance * 1.14)
		_update_camera()
		return
	if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
		_panning = mouse_event.shift_pressed
		_orbiting = not _panning
		return
	# Parts place/erase on the fine grid (1/8 a structure cell); everything
	# else (blocks, components, markers, and every non-place tool) stays on
	# the coarse structure-cell raycast unchanged.
	if _place_kind == "part" and _tool == "place":
		var fine_value := _mouse_to_fine_cell(mouse_event.position)
		if fine_value == null:
			return
		var fine_cell: Vector3i = fine_value
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_transact("Erase part", func() -> void: _document.erase_placed_part(fine_cell))
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_place_part_at_fine_cell(fine_cell)
		return
	if _move_armed and _move_entity_kind == "part" and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		var fine_value := _mouse_to_fine_cell(mouse_event.position)
		if fine_value != null:
			_move_part_at_fine_cell(fine_value)
		return
	if _place_kind == "part" and _tool == "select" and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		var fine_value := _mouse_to_fine_cell(mouse_event.position)
		if fine_value != null:
			_select_part_at_fine_cell(fine_value)
		return
	var cell_value := _mouse_to_cell(mouse_event.position)
	if cell_value == null:
		return
	var cell: Vector3i = cell_value
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		var erase_cells := _mirror_cells(cell)
		_transact("Erase block", func() -> void:
			for target: Vector3i in erase_cells:
				_document.erase_block(target)
		)
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _staged_blueprint_path.is_empty():
		_place_staged_blueprint(cell)
		return
	if _paste_armed:
		_paste_at(cell)
		return
	if _move_armed:
		_move_at(cell)
		return
	if _move_nested_armed:
		_move_nested_at(cell)
		return
	match _tool:
		"place": _place_at(cell)
		"select": _select_single(cell)
		"connected": _select_connected(cell)
		"line", "fill", "box", "shell": _handle_two_point_tool(cell)


func _mouse_to_cell(mouse: Vector2) -> Variant:
	var viewport_mouse := mouse
	if _viewport_container.size.x > 0 and _viewport_container.size.y > 0:
		viewport_mouse *= Vector2(_viewport.size) / _viewport_container.size
	var ray_origin := _camera.project_ray_origin(viewport_mouse)
	var ray_direction := _camera.project_ray_normal(viewport_mouse)
	var point: Variant = Plane(Vector3.UP, float(_active_layer)).intersects_ray(ray_origin, ray_direction)
	if point == null:
		return null
	return Vector3i(floori(point.x), _active_layer, floori(point.z))


## Like _mouse_to_cell but resolves to the Workshop's fine grid (plan
## section 2: 1/8 of a structure cell) instead of whole structure cells -
## used only for _place_kind == "part". The height plane is the current
## structure layer PLUS a fine sub-layer (_fine_layer, 0..7), so parts can
## be positioned at any of the 8 fine heights within a structure cell, not
## just whole-meter steps.
func _mouse_to_fine_cell(mouse: Vector2) -> Variant:
	var viewport_mouse := mouse
	if _viewport_container.size.x > 0 and _viewport_container.size.y > 0:
		viewport_mouse *= Vector2(_viewport.size) / _viewport_container.size
	var ray_origin := _camera.project_ray_origin(viewport_mouse)
	var ray_direction := _camera.project_ray_normal(viewport_mouse)
	var plane_height := float(_active_layer) + float(_fine_layer) * DocumentScript.FINE_CELL_SIZE
	var point: Variant = Plane(Vector3.UP, plane_height).intersects_ray(ray_origin, ray_direction)
	if point == null:
		return null
	return _fine_cell_for_point(point)


## Pure geometry step split out of _mouse_to_fine_cell so the fine-grid
## quantization math is directly testable without a real camera raycast:
## given a world-space point already known to lie on the current placement
## plane, returns its fine-grid cell (X/Z quantized to FINE_CELL_SIZE, Y
## from the current structure layer + fine sub-layer).
func _fine_cell_for_point(point: Vector3) -> Vector3i:
	var fine := DocumentScript.FINE_CELL_SIZE
	var fine_y := _active_layer * FINE_CELLS_PER_UNIT + _fine_layer
	return Vector3i(floori(point.x / fine), fine_y, floori(point.z / fine))


func _place_at(cell: Vector3i) -> void:
	if _place_kind == "block":
		var placements := _mirror_placements(cell, _make_block_data())
		_transact("Place %s" % _selected_block_id, func() -> void:
			for placement: Dictionary in placements:
				_document.set_block(placement["cell"], placement["data"])
		)
	elif _place_kind == "component":
		var definition := _find_definition(_components, _selected_component_id)
		var snap: Dictionary = SnapResolver.find_snapped_origin(_document, cell, definition, _brush_rotation, _components)
		var origin: Vector3i = snap.get("origin", cell)
		if bool(definition.get("snap_required", false)) and not bool(snap.get("found", false)):
			_set_status("%s needs a compatible exposed port" % definition.get("name", _selected_component_id))
			return
		if not SnapResolver.can_place(_document, origin, definition, _brush_rotation):
			_set_status("Component footprint is occupied")
			return
		var stored_definition := {
			"footprint": definition.get("footprint", [[0, 0, 0]]).duplicate(true),
			"ports": definition.get("ports", []).duplicate(true),
			"allow_block_overlap": definition.get("allow_block_overlap", false),
		}
		_transact("Place component", func() -> void:
			_document.components.append({"id": _new_id("component"), "component_id": _selected_component_id, "pos": [origin.x, origin.y, origin.z], "rotation_steps": _brush_rotation, "definition": stored_definition, "capabilities": definition.get("capabilities", []).duplicate(), "rules": definition.get("rules", []).duplicate(true), "properties": {"snapped_port": snap.get("port", "")}})
			_document.notify_changed()
		)
		_set_status("Snapped via %s port" % snap.get("port", "") if snap.get("found", false) else "Component placed")
	elif _place_kind == "part":
		# Generic commands retain the coarse-cell contract used by the other
		# element types. Fine-grid mouse placement calls the dedicated helper.
		_place_part_at_fine_cell(Vector3i(
			cell.x * FINE_CELLS_PER_UNIT,
			cell.y * FINE_CELLS_PER_UNIT + _fine_layer,
			cell.z * FINE_CELLS_PER_UNIT,
		))
	else:
		_transact("Place marker", func() -> void:
			_document.markers.append({"id": _new_id("marker"), "marker_type": _selected_marker_id, "pos": [cell.x, cell.y, cell.z], "rotation_steps": 0, "properties": {"visibility_policy": "simulation_proxy" if _selected_marker_id == "worker_position" else "editor_and_runtime"}})
			_document.notify_changed()
		)


func _place_part_at_fine_cell(fine_cell: Vector3i) -> void:
	var raw_position := Vector3(fine_cell) * DocumentScript.FINE_CELL_SIZE
	var candidate_part: PartProfile = _part_registry.get_part(_selected_part_id) if _part_registry else null
	if candidate_part == null:
		_set_status("Unknown part: %s" % _selected_part_id)
		return
	var final_position := raw_position
	var status := "Part placed: %s" % _selected_part_id
	var joints: Array[Dictionary] = []
	var snap: Dictionary = PartSnapResolver.find_snap(_document, _part_registry.get_part, candidate_part, raw_position, _brush_rotation)
	if snap.get("found", false):
		final_position = snap.get("position")
		status = "Part snapped: %s → %s" % [snap.get("candidate_socket", ""), snap.get("target_socket", "")]
		# Recorded so PartKineticsCompiler (plan section 5, Phase 5) can later
		# rebuild this connection as a weld/hinge/bearing/slider without
		# re-running the snap search - the snap that happened at placement
		# time IS the joint; nothing downstream should have to guess it back
		# from proximity.
		joints.append({
			"target_key": snap.get("target_part_key", ""),
			"target_socket": snap.get("target_socket", ""),
			"own_socket": snap.get("candidate_socket", ""),
		})
	_transact("Place part", func() -> void:
		_document.set_placed_part_at(final_position, {"part_id": String(_selected_part_id), "rotation_steps": _brush_rotation, "joints": joints})
	)
	_set_status(status)


func _make_block_data() -> Dictionary:
	return {"block_id": String(_selected_block_id), "shape_id": _selected_shape_id, "rotation_steps": _brush_rotation, "layer": "structure", "tags": []}


## Which axis flips the current mirror mode implies, as [flip_x, flip_z]
## pairs. X+Z is three copies: across X, across Z, and across both.
func _mirror_flips() -> Array:
	match _mirror_mode:
		"x": return [[true, false]]
		"z": return [[false, true]]
		"xz": return [[true, false], [false, true], [true, true]]
	return []


func _mirrored_cell(cell: Vector3i, flip_x: bool, flip_z: bool) -> Vector3i:
	var result := cell
	if flip_x:
		result.x = 2 * _mirror_x - cell.x
	if flip_z:
		result.z = 2 * _mirror_z - cell.z
	return result


## Reflecting a yaw-rotated shape also reflects its facing: flipping X maps
## rotation steps r -> (4 - r) & 3, flipping Z maps r -> (2 - r) & 3, and
## flipping both is a plain half turn, (r + 2) & 3. (Derived by pushing the
## shape's forward vector through the reflection - a mirrored stair must
## face back toward the mirror plane, not away from it.)
func _mirrored_block_data(data: Dictionary, flip_x: bool, flip_z: bool) -> Dictionary:
	var copy := data.duplicate(true)
	var steps := int(copy.get("rotation_steps", 0))
	if flip_x and flip_z:
		steps = posmod(steps + 2, 4)
	elif flip_x:
		steps = posmod(4 - steps, 4)
	elif flip_z:
		steps = posmod(2 - steps, 4)
	copy["rotation_steps"] = steps
	return copy


## A block edit at `cell` plus its mirrored copies as {cell, data} entries,
## deduplicated - a cell sitting on the mirror plane maps onto itself and
## must not be written twice in one transaction.
func _mirror_placements(cell: Vector3i, data: Dictionary) -> Array[Dictionary]:
	var placements: Array[Dictionary] = [{"cell": cell, "data": data}]
	var seen := {ForgeDocument.cell_key(cell): true}
	for flip: Array in _mirror_flips():
		var mirrored := _mirrored_cell(cell, flip[0], flip[1])
		var key := ForgeDocument.cell_key(mirrored)
		if seen.has(key):
			continue
		seen[key] = true
		placements.append({"cell": mirrored, "data": _mirrored_block_data(data, flip[0], flip[1])})
	return placements


func _mirror_cells(cell: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for placement: Dictionary in _mirror_placements(cell, {}):
		cells.append(placement["cell"])
	return cells


func _select_single(cell: Vector3i) -> void:
	_clear_selection()
	if _document.has_block(cell):
		_selected_cells[ForgeDocument.cell_key(cell)] = true
	else:
		var component_id := _component_at(cell)
		if not component_id.is_empty():
			_selected_component_ids[component_id] = true
		else:
			var marker_id := _marker_at(cell)
			if not marker_id.is_empty():
				_selected_marker_ids[marker_id] = true
			else:
				_selected_nested_id = _find_nested_at(cell)
	_refresh_world()
	_set_status(_selection_summary())


func _select_part_at_fine_cell(cell: Vector3i) -> void:
	_clear_selection()
	var key := ForgeDocument.cell_key(cell)
	if _document.placed_parts.has(key):
		_selected_part_keys[key] = true
	else:
		# Precisely snapped parts may be bucketed in the nearest adjacent fine
		# cell. Pick the closest visible origin within one fine-cell radius.
		var requested := Vector3(cell) * DocumentScript.FINE_CELL_SIZE
		var best_key := ""
		var best_distance := DocumentScript.FINE_CELL_SIZE * 1.5
		for candidate_key: String in _document.placed_parts:
			var distance := DocumentScript.placed_part_world_position(_document.placed_parts[candidate_key]).distance_to(requested)
			if distance < best_distance:
				best_distance = distance
				best_key = candidate_key
		if not best_key.is_empty():
			_selected_part_keys[best_key] = true
	_refresh_world()
	_set_status(_selection_summary())


func _clear_selection() -> void:
	_selected_cells.clear()
	_selected_component_ids.clear()
	_selected_marker_ids.clear()
	_selected_part_keys.clear()
	_selected_nested_id = ""


func _selection_summary() -> String:
	if not _selected_nested_id.is_empty():
		return "Selected blueprint instance"
	var count := _selected_cells.size() + _selected_component_ids.size() + _selected_marker_ids.size() + _selected_part_keys.size()
	if count == 0:
		return "Nothing selected"
	return "Selected %d: %d blocks · %d components · %d markers · %d parts" % [count, _selected_cells.size(), _selected_component_ids.size(), _selected_marker_ids.size(), _selected_part_keys.size()]


func _component_at(cell: Vector3i) -> String:
	for component: Dictionary in _document.components:
		var definition := _find_definition(_components, str(component.get("component_id", "")))
		var origin := _array_cell(component.get("pos", [0, 0, 0]))
		for offset: Vector3i in SnapResolver.rotated_footprint(definition, int(component.get("rotation_steps", 0))):
			if origin + offset == cell:
				return str(component.get("id", ""))
	return ""


func _marker_at(cell: Vector3i) -> String:
	for marker: Dictionary in _document.markers:
		if _array_cell(marker.get("pos", [0, 0, 0])) == cell:
			return str(marker.get("id", ""))
	return ""


func _select_all_blocks() -> void:
	_clear_selection()
	for key: String in _document.blocks:
		_selected_cells[key] = true
	_refresh_world()
	_set_status("Selected all %d blocks" % _selected_cells.size())


func _select_connected(cell: Vector3i) -> void:
	_clear_selection()
	for connected: Vector3i in _connected_cells(cell):
		_selected_cells[ForgeDocument.cell_key(connected)] = true
	_refresh_world()
	_set_status("Selected %d connected structural blocks" % _selected_cells.size())


## Flood fill over face-adjacent structural blocks starting at `cell`.
## Shared by the Connected tool's click (_select_connected, no limit) and
## its hover preview (_update_connected_preview, capped so hovering a huge
## structure can't stall the editor every mouse move).
func _connected_cells(cell: Vector3i, limit: int = 1 << 30) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if not _document.has_block(cell):
		return cells
	var open: Array[Vector3i] = [cell]
	var visited := {}
	var directions := [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
	while not open.is_empty() and cells.size() < limit:
		var current: Vector3i = open.pop_back()
		var key := ForgeDocument.cell_key(current)
		if visited.has(key):
			continue
		visited[key] = true
		cells.append(current)
		for direction: Vector3i in directions:
			var neighbor: Vector3i = current + direction
			if _document.has_block(neighbor):
				open.append(neighbor)
	return cells


func _handle_two_point_tool(cell: Vector3i) -> void:
	if _anchor_cell == null:
		_anchor_cell = cell
		_set_status("Anchor set at %s — choose the second point" % cell)
		return
	var start: Vector3i = _anchor_cell
	_anchor_cell = null
	var cells := _tool_pattern_cells(_tool, start, cell)
	var label: String = {"line": "Draw line", "fill": "Fill rectangle", "box": "Fill box", "shell": "Build hollow shell"}.get(_tool, "Place blocks")
	_transact(label, func() -> void:
		for target: Vector3i in cells:
			for placement: Dictionary in _mirror_placements(target, _make_block_data()):
				_document.set_block(placement["cell"], placement["data"])
	)


## Every cell the given two-point tool would fill between start and finish.
## Shared by the actual edit (_handle_two_point_tool) and the live hover
## preview (_update_two_point_preview) so the preview is exactly what a
## click would place. Fill stays a single-layer rectangle on _active_layer,
## matching its original behavior.
func _tool_pattern_cells(tool: String, start: Vector3i, finish: Vector3i) -> Array[Vector3i]:
	if tool == "line":
		return _line_cells(start, finish)
	var cells: Array[Vector3i] = []
	if tool == "fill":
		for x: int in range(mini(start.x, finish.x), maxi(start.x, finish.x) + 1):
			for z: int in range(mini(start.z, finish.z), maxi(start.z, finish.z) + 1):
				cells.append(Vector3i(x, _active_layer, z))
		return cells
	var hollow := tool == "shell"
	for x: int in range(mini(start.x, finish.x), maxi(start.x, finish.x) + 1):
		for y: int in range(mini(start.y, finish.y), maxi(start.y, finish.y) + 1):
			for z: int in range(mini(start.z, finish.z), maxi(start.z, finish.z) + 1):
				if hollow and x not in [start.x, finish.x] and y not in [start.y, finish.y] and z not in [start.z, finish.z]:
					continue
				cells.append(Vector3i(x, y, z))
	return cells


func _line_cells(start: Vector3i, finish: Vector3i) -> Array[Vector3i]:
	var output: Array[Vector3i] = []
	var delta := finish - start
	var steps := maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z)))
	if steps == 0:
		return [start]
	for index: int in range(steps + 1):
		var t := float(index) / float(steps)
		output.append(Vector3i(roundi(lerpf(start.x, finish.x, t)), roundi(lerpf(start.y, finish.y, t)), roundi(lerpf(start.z, finish.z, t))))
	return output


func _copy_selection() -> void:
	_clipboard.clear()
	if _selected_cells.is_empty():
		_set_status("Nothing selected to copy")
		return
	var min_cell := Vector3i(100000, 100000, 100000)
	for key: String in _selected_cells:
		var cell := ForgeDocument.key_cell(key)
		min_cell = Vector3i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y), mini(min_cell.z, cell.z))
	for key: String in _selected_cells:
		var cell := ForgeDocument.key_cell(key)
		_clipboard.append({"offset": cell - min_cell, "data": _document.blocks[key].duplicate(true)})
	_set_status("Copied %d blocks" % _clipboard.size())


func _arm_paste() -> void:
	if _clipboard.is_empty():
		_set_status("Clipboard is empty")
		return
	_paste_armed = true
	_move_armed = false
	_set_status("Paste armed — click an origin on the grid")


func _paste_at(origin: Vector3i) -> void:
	_paste_armed = false
	if _clipboard_collides(origin, []):
		_set_status("Paste blocked by occupied cells")
		return
	_transact("Paste %d blocks" % _clipboard.size(), func() -> void:
		for entry: Dictionary in _clipboard:
			_document.set_block(origin + (entry["offset"] as Vector3i), entry["data"])
	)


func _arm_move() -> void:
	if _selected_cells.is_empty():
		if _selected_component_ids.size() == 1:
			_move_entity_kind = "component"
			_move_entity_id = str(_selected_component_ids.keys()[0])
			_move_armed = true
			_set_status("Move component armed — click its new origin")
			return
		if _selected_marker_ids.size() == 1:
			_move_entity_kind = "marker"
			_move_entity_id = str(_selected_marker_ids.keys()[0])
			_move_armed = true
			_set_status("Move marker armed — click its new origin")
			return
		if _selected_part_keys.size() == 1:
			_move_entity_kind = "part"
			_move_entity_id = str(_selected_part_keys.keys()[0])
			_move_armed = true
			_set_status("Move part armed — click its new fine-grid origin")
			return
		if not _selected_nested_id.is_empty():
			_move_nested_armed = true
			_set_status("Move blueprint armed — click its new origin")
			return
		_set_status("Select blocks or a staged blueprint to move")
		return
	_copy_selection()
	_move_source_keys.assign(_selected_cells.keys())
	_move_entity_kind = "blocks"
	_move_armed = true
	_paste_armed = false
	_set_status("Move armed — click the new origin")


func _move_at(origin: Vector3i) -> void:
	_move_armed = false
	if _move_entity_kind == "component":
		_move_component_at(origin)
		return
	if _move_entity_kind == "marker":
		_move_marker_at(origin)
		return
	if _clipboard_collides(origin, _move_source_keys):
		_set_status("Move blocked by occupied cells")
		return
	var old_keys := _move_source_keys.duplicate()
	_transact("Move %d blocks" % _clipboard.size(), func() -> void:
		for key: String in old_keys:
			_document.blocks.erase(key)
		_selected_cells.clear()
		for entry: Dictionary in _clipboard:
			var target := origin + (entry["offset"] as Vector3i)
			_document.set_block(target, entry["data"])
			_selected_cells[ForgeDocument.cell_key(target)] = true
		_document.notify_changed()
	)
	_move_source_keys.clear()
	_move_entity_kind = ""
	_move_entity_id = ""


func _move_component_at(origin: Vector3i) -> void:
	for component: Dictionary in _document.components:
		if str(component.get("id", "")) != _move_entity_id:
			continue
		var definition := _find_definition(_components, str(component.get("component_id", "")))
		if not SnapResolver.can_place(_document, origin, definition, int(component.get("rotation_steps", 0)), _move_entity_id):
			_set_status("Move blocked by occupied cells")
			_move_entity_kind = ""
			_move_entity_id = ""
			return
		_transact("Move component", func() -> void:
			component["pos"] = [origin.x, origin.y, origin.z]
			_document.notify_changed()
		)
		_set_status("Component moved")
		break
	_move_entity_kind = ""
	_move_entity_id = ""


func _move_marker_at(origin: Vector3i) -> void:
	for marker: Dictionary in _document.markers:
		if str(marker.get("id", "")) == _move_entity_id:
			_transact("Move marker", func() -> void:
				marker["pos"] = [origin.x, origin.y, origin.z]
				_document.notify_changed()
			)
			_set_status("Marker moved")
			break
	_move_entity_kind = ""
	_move_entity_id = ""


func _move_part_at_fine_cell(cell: Vector3i) -> void:
	_move_armed = false
	if not _document.placed_parts.has(_move_entity_id):
		_move_entity_kind = ""
		return
	var data: Dictionary = _document.placed_parts[_move_entity_id].duplicate(true)
	var position := Vector3(cell) * DocumentScript.FINE_CELL_SIZE
	var old_key := _move_entity_id
	var target_key := ForgeDocument.cell_key(DocumentScript.cell_for_position(position))
	if target_key != old_key and _document.placed_parts.has(target_key):
		_move_entity_kind = ""
		_move_entity_id = ""
		_set_status("Move blocked by another part")
		return
	_transact("Move part", func() -> void:
		_document.placed_parts.erase(old_key)
		var new_cell := _document.set_placed_part_at(position, data)
		_selected_part_keys.clear()
		_selected_part_keys[ForgeDocument.cell_key(new_cell)] = true
		_document.notify_changed()
	)
	_move_entity_kind = ""
	_move_entity_id = ""
	_set_status("Part moved")


func _move_nested_at(origin: Vector3i) -> void:
	_move_nested_armed = false
	for instance: Dictionary in _document.nested_instances:
		if str(instance.get("id", "")) != _selected_nested_id:
			continue
		_transact("Move nested blueprint", func() -> void:
			instance["origin"] = [origin.x, origin.y, origin.z]
			_document.notify_changed()
		)
		return


func _duplicate_selection() -> void:
	if _selected_cells.is_empty() and _selected_component_ids.size() == 1:
		var source_id := str(_selected_component_ids.keys()[0])
		for component: Dictionary in _document.components:
			if str(component.get("id", "")) != source_id:
				continue
			var copy := component.duplicate(true)
			var origin := _array_cell(copy.get("pos", [0, 0, 0])) + Vector3i.RIGHT
			var definition := _find_definition(_components, str(copy.get("component_id", "")))
			if not SnapResolver.can_place(_document, origin, definition, int(copy.get("rotation_steps", 0))):
				_set_status("Duplicate blocked; move the original or choose open space")
				return
			copy["id"] = _new_id("component")
			copy["pos"] = [origin.x, origin.y, origin.z]
			_transact("Duplicate component", func() -> void:
				_document.components.append(copy)
				_document.notify_changed()
			)
			_clear_selection()
			_selected_component_ids[copy["id"]] = true
			_refresh_world()
			_set_status("Component duplicated")
			return
	if _selected_cells.is_empty() and _selected_marker_ids.size() == 1:
		var source_id := str(_selected_marker_ids.keys()[0])
		for marker: Dictionary in _document.markers:
			if str(marker.get("id", "")) == source_id:
				var copy := marker.duplicate(true)
				var origin := _array_cell(copy.get("pos", [0, 0, 0])) + Vector3i.RIGHT
				copy["id"] = _new_id("marker")
				copy["pos"] = [origin.x, origin.y, origin.z]
				_transact("Duplicate marker", func() -> void:
					_document.markers.append(copy)
					_document.notify_changed()
				)
				_clear_selection()
				_selected_marker_ids[copy["id"]] = true
				_refresh_world()
				_set_status("Marker duplicated")
				return
	if _selected_cells.is_empty() and _selected_part_keys.size() == 1:
		var source_key := str(_selected_part_keys.keys()[0])
		var copy: Dictionary = _document.placed_parts[source_key].duplicate(true)
		var position := DocumentScript.placed_part_world_position(copy) + Vector3(DocumentScript.FINE_CELL_SIZE, 0, 0)
		var target_cell := DocumentScript.cell_for_position(position)
		if _document.has_placed_part(target_cell):
			_set_status("Duplicate blocked by another part")
			return
		_transact("Duplicate part", func() -> void:
			var new_cell := _document.set_placed_part_at(position, copy)
			_clear_selection()
			_selected_part_keys[ForgeDocument.cell_key(new_cell)] = true
		)
		_set_status("Part duplicated one fine-grid step right")
		_refresh_world()
		return
	if _selected_cells.is_empty() and not _selected_nested_id.is_empty():
		for instance: Dictionary in _document.nested_instances:
			if str(instance.get("id", "")) == _selected_nested_id:
				var copy := instance.duplicate(true)
				var origin := _array_cell(copy.get("origin", [0, 0, 0])) + Vector3i.RIGHT
				copy["id"] = _new_id("blueprint")
				copy["origin"] = [origin.x, origin.y, origin.z]
				_transact("Duplicate blueprint instance", func() -> void:
					_document.nested_instances.append(copy)
					_document.notify_changed()
				)
				_selected_nested_id = copy["id"]
				_set_status("Blueprint instance duplicated")
				return
	_copy_selection()
	if not _clipboard.is_empty():
		_paste_armed = true
		_move_armed = false
		_set_status("Duplicate armed — click its origin")


func _rotate_selection_or_brush() -> void:
	if _selected_cells.is_empty():
		if _selected_component_ids.size() == 1:
			var component_id := str(_selected_component_ids.keys()[0])
			for component: Dictionary in _document.components:
				if str(component.get("id", "")) != component_id:
					continue
				var next_steps := posmod(int(component.get("rotation_steps", 0)) + 1, 4)
				var definition := _find_definition(_components, str(component.get("component_id", "")))
				if not SnapResolver.can_place(_document, _array_cell(component.get("pos", [0, 0, 0])), definition, next_steps, component_id):
					_set_status("Component rotation is blocked")
					return
				_transact("Rotate component", func() -> void:
					component["rotation_steps"] = next_steps
					_document.notify_changed()
				)
				return
		if _selected_marker_ids.size() == 1:
			var marker_id := str(_selected_marker_ids.keys()[0])
			for marker: Dictionary in _document.markers:
				if str(marker.get("id", "")) == marker_id:
					_transact("Rotate marker", func() -> void:
						marker["rotation_steps"] = posmod(int(marker.get("rotation_steps", 0)) + 1, 4)
						_document.notify_changed()
					)
					return
		if _selected_part_keys.size() == 1:
			var part_key := str(_selected_part_keys.keys()[0])
			_transact("Rotate part", func() -> void:
				var part: Dictionary = _document.placed_parts[part_key]
				part["rotation_steps"] = posmod(int(part.get("rotation_steps", 0)) + 1, 4)
				_document.notify_changed()
			)
			return
		if not _selected_nested_id.is_empty():
			for instance: Dictionary in _document.nested_instances:
				if str(instance.get("id", "")) == _selected_nested_id:
					_transact("Rotate nested blueprint", func() -> void:
						instance["rotation_steps"] = posmod(int(instance.get("rotation_steps", 0)) + 1, 4)
						_document.notify_changed()
					)
					return
		_brush_rotation = posmod(_brush_rotation + 1, 4)
		_set_status("Placement rotation: %d°" % (_brush_rotation * 90))
		return
	var cells: Array[Vector3i] = []
	var min_cell := Vector3i(100000, 100000, 100000)
	var max_cell := Vector3i(-100000, -100000, -100000)
	for key: String in _selected_cells:
		var selected := ForgeDocument.key_cell(key)
		cells.append(selected)
		min_cell = Vector3i(mini(min_cell.x, selected.x), mini(min_cell.y, selected.y), mini(min_cell.z, selected.z))
		max_cell = Vector3i(maxi(max_cell.x, selected.x), maxi(max_cell.y, selected.y), maxi(max_cell.z, selected.z))
	var replacements := {}
	for selected: Vector3i in cells:
		var rotated := Vector3i(min_cell.x + (selected.z - min_cell.z), selected.y, min_cell.z + (max_cell.x - selected.x))
		var key := ForgeDocument.cell_key(rotated)
		if _document.blocks.has(key) and not _selected_cells.has(key):
			_set_status("Rotation blocked by occupied cells")
			return
		var data: Dictionary = _document.get_block(selected).duplicate(true)
		data["rotation_steps"] = posmod(int(data.get("rotation_steps", 0)) + 1, 4)
		replacements[key] = {"cell": rotated, "data": data}
	var old_keys := _selected_cells.keys()
	_transact("Rotate %d blocks" % old_keys.size(), func() -> void:
		for key: String in old_keys:
			_document.blocks.erase(key)
		_selected_cells.clear()
		for key: String in replacements:
			var entry: Dictionary = replacements[key]
			_document.set_block(entry["cell"], entry["data"])
			_selected_cells[key] = true
		_document.notify_changed()
	)


func _replace_selection() -> void:
	if _selected_cells.is_empty():
		_set_status("Select blocks to replace")
		return
	var keys := _selected_cells.keys()
	_transact("Replace %d blocks" % keys.size(), func() -> void:
		for key: String in keys:
			var old: Dictionary = _document.blocks[key]
			var replacement := _make_block_data()
			replacement["layer"] = old.get("layer", "structure")
			replacement["tags"] = old.get("tags", []).duplicate()
			_document.set_block(ForgeDocument.key_cell(key), replacement)
	)


func _clipboard_collides(origin: Vector3i, ignored_keys: Array[String]) -> bool:
	for entry: Dictionary in _clipboard:
		var key := ForgeDocument.cell_key(origin + (entry["offset"] as Vector3i))
		if _document.blocks.has(key) and key not in ignored_keys:
			return true
	return false


func _delete_selection() -> void:
	var total := _selected_cells.size() + _selected_component_ids.size() + _selected_marker_ids.size() + _selected_part_keys.size() + (0 if _selected_nested_id.is_empty() else 1)
	if total == 0:
		return
	var block_keys := _selected_cells.keys()
	var component_ids := _selected_component_ids.keys()
	var marker_ids := _selected_marker_ids.keys()
	var part_keys := _selected_part_keys.keys()
	var nested_id := _selected_nested_id
	_transact("Delete %d selected elements" % total, func() -> void:
		for key: String in block_keys:
			_document.blocks.erase(key)
		for index: int in range(_document.components.size() - 1, -1, -1):
			if str(_document.components[index].get("id", "")) in component_ids:
				_document.components.remove_at(index)
		for index: int in range(_document.markers.size() - 1, -1, -1):
			if str(_document.markers[index].get("id", "")) in marker_ids:
				_document.markers.remove_at(index)
		for key: String in part_keys:
			_document.placed_parts.erase(key)
		if not nested_id.is_empty():
			for index: int in range(_document.nested_instances.size() - 1, -1, -1):
				if str(_document.nested_instances[index].get("id", "")) == nested_id:
					_document.nested_instances.remove_at(index)
		_document.notify_changed()
	)
	_clear_selection()


func _place_staged_blueprint(origin: Vector3i) -> void:
	var path := _staged_blueprint_path
	_staged_blueprint_path = ""
	var source := DocumentScript.load_json(path)
	if source == null:
		_set_status("Staged blueprint could not be loaded")
		return
	var instance_id := _new_id("blueprint")
	_transact("Place nested blueprint", func() -> void:
		_document.nested_instances.append({"id": instance_id, "source_path": path, "source_id": source.document_id, "origin": [origin.x, origin.y, origin.z], "rotation_steps": _brush_rotation, "linked": true, "finalized": false})
		_document.notify_changed()
	)
	_selected_nested_id = instance_id
	_set_status("Placed %s as one editable blueprint instance" % source.display_name)


func _finalize_nested_blueprints() -> void:
	if _document.nested_instances.is_empty():
		_set_status("No staged blueprints to finalize")
		return
	var skipped := 0
	_transact("Finalize nested blueprints", func() -> void:
		for instance: Dictionary in _document.nested_instances:
			var source: ForgeDocument = DocumentScript.load_json(str(instance.get("source_path", "")))
			if source == null:
				continue
			var raw_origin: Array = instance.get("origin", [0, 0, 0])
			var origin := Vector3i(int(raw_origin[0]), int(raw_origin[1]), int(raw_origin[2]))
			var instance_steps := int(instance.get("rotation_steps", 0))
			for key: String in source.blocks:
				var destination := origin + SnapResolver.rotate_offset(ForgeDocument.key_cell(key), instance_steps)
				if _document.has_block(destination):
					skipped += 1
					continue
				var block: Dictionary = source.blocks[key].duplicate(true)
				block["rotation_steps"] = posmod(int(block.get("rotation_steps", 0)) + instance_steps, 4)
				block["parent_blueprint_id"] = source.document_id
				block["source_instance_id"] = instance.get("id", "")
				_document.set_block(destination, block)
			for component: Dictionary in source.components:
				var copy := component.duplicate(true)
				var pos: Array = copy.get("pos", [0, 0, 0])
				var rotated_pos := SnapResolver.rotate_offset(Vector3i(int(pos[0]), int(pos[1]), int(pos[2])), instance_steps) + origin
				copy["pos"] = [rotated_pos.x, rotated_pos.y, rotated_pos.z]
				copy["rotation_steps"] = posmod(int(copy.get("rotation_steps", 0)) + instance_steps, 4)
				copy["id"] = _new_id("component")
				copy["parent_blueprint_id"] = source.document_id
				copy["source_instance_id"] = instance.get("id", "")
				_document.components.append(copy)
			for marker: Dictionary in source.markers:
				var copy := marker.duplicate(true)
				var pos := _array_cell(copy.get("pos", [0, 0, 0]))
				var rotated_pos := SnapResolver.rotate_offset(pos, instance_steps) + origin
				copy["pos"] = [rotated_pos.x, rotated_pos.y, rotated_pos.z]
				copy["rotation_steps"] = posmod(int(copy.get("rotation_steps", 0)) + instance_steps, 4)
				copy["id"] = _new_id("marker")
				copy["parent_blueprint_id"] = source.document_id
				copy["source_instance_id"] = instance.get("id", "")
				_document.markers.append(copy)
			for key: String in source.placed_parts:
				var copy: Dictionary = source.placed_parts[key].duplicate(true)
				var local_position := DocumentScript.placed_part_world_position(copy)
				var world_position := Vector3(origin) + _rotate_vector_y(local_position, instance_steps)
				var target_cell := DocumentScript.cell_for_position(world_position)
				if _document.has_placed_part(target_cell):
					skipped += 1
					continue
				copy["rotation_steps"] = posmod(int(copy.get("rotation_steps", 0)) + instance_steps, 4)
				copy["parent_blueprint_id"] = source.document_id
				copy["source_instance_id"] = instance.get("id", "")
				_document.set_placed_part_at(world_position, copy)
		_document.nested_instances.clear()
		_document.notify_changed()
	)
	_selected_nested_id = ""
	_set_status("Finalized into independent pieces%s" % ("; %d occupied cells skipped" % skipped if skipped > 0 else ""))


func _rotate_vector_y(value: Vector3, steps: int) -> Vector3:
	var result := value
	for _step: int in range(posmod(steps, 4)):
		result = Vector3(-result.z, result.y, result.x)
	return result


func _transact(label: String, action: Callable) -> void:
	var before := _document.snapshot()
	_document.begin_batch()
	action.call()
	_document.end_batch()
	var after := _document.snapshot()
	_history.record(label, before, after)


func _undo() -> void:
	var label := _history.undo(_document)
	if label != "":
		_clear_selection()
		_set_status("Undid: %s" % label)


func _redo() -> void:
	var label := _history.redo(_document)
	if label != "":
		_clear_selection()
		_set_status("Redid: %s" % label)


func _refresh_history_buttons() -> void:
	if _undo_button:
		_undo_button.disabled = not _history.can_undo()
		_undo_button.tooltip_text = _history.undo_label()
	if _redo_button:
		_redo_button.disabled = not _history.can_redo()
		_redo_button.tooltip_text = _history.redo_label()


func _update_camera() -> void:
	if _camera == null:
		return
	var horizontal := cos(_camera_pitch) * _camera_distance
	var offset := Vector3(sin(_camera_yaw) * horizontal, sin(_camera_pitch) * _camera_distance, cos(_camera_yaw) * horizontal)
	_camera.look_at_from_position(_camera_focus + offset, _camera_focus)


## Xbox-controller support: pair the controller to the PC as a normal
## joypad (Bluetooth or USB - no phone or custom app involved) and Godot's
## own Input singleton sees it like any other gamepad. Left stick pans the
## camera focus, right stick orbits, triggers zoom, face buttons place/
## erase/rotate/cycle what's selected, D-pad steps structure/fine layers,
## Start/Back undo/redo. There's no mouse cursor to hover with when playing
## by controller alone, so placement/erase aim from a fixed reticle at the
## viewport center instead of a hover position.
const GAMEPAD_DEADZONE := 0.2
const GAMEPAD_ORBIT_SPEED := 1.6 # radians/sec at full stick deflection
const GAMEPAD_PAN_SPEED := 0.14 # fraction of camera distance/sec at full stick
const GAMEPAD_ZOOM_SPEED := 18.0 # camera-distance units/sec at full trigger
const GAMEPAD_PLACE_KIND_ORDER := ["block", "component", "marker", "part"]


func _process(_delta: float) -> void:
	if _viewport_container == null:
		return
	var device := _active_joypad_device()
	if _gamepad_reticle:
		_gamepad_reticle.visible = device != -1
	if device == -1:
		return
	_apply_gamepad_frame(_read_joypad_state(device), _delta)


## First connected joypad, or -1 if none - deliberately simple (one
## controller at a time) rather than letting multiple connected pads fight
## over the same camera/tool state.
func _active_joypad_device() -> int:
	var devices := Input.get_connected_joypads()
	return devices[0] if not devices.is_empty() else -1


## Reads live hardware state into a plain Dictionary so the actual gamepad
## logic (_apply_gamepad_frame and everything it calls) never touches the
## Input singleton directly and can be driven by a hand-built Dictionary in
## tests - the same "thin hardware shell around a pure function" split as
## _mouse_to_fine_cell/_fine_cell_for_point.
func _read_joypad_state(device: int) -> Dictionary:
	return {
		"left_x": Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		"left_y": Input.get_joy_axis(device, JOY_AXIS_LEFT_Y),
		"right_x": Input.get_joy_axis(device, JOY_AXIS_RIGHT_X),
		"right_y": Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y),
		"lt": Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT),
		"rt": Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT),
		"a": Input.is_joy_button_pressed(device, JOY_BUTTON_A),
		"b": Input.is_joy_button_pressed(device, JOY_BUTTON_B),
		"x": Input.is_joy_button_pressed(device, JOY_BUTTON_X),
		"y": Input.is_joy_button_pressed(device, JOY_BUTTON_Y),
		"lb": Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER),
		"rb": Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER),
		"start": Input.is_joy_button_pressed(device, JOY_BUTTON_START),
		"back": Input.is_joy_button_pressed(device, JOY_BUTTON_BACK),
		"dpad_up": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP),
		"dpad_down": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN),
		"dpad_left": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT),
		"dpad_right": Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT),
	}


func _apply_gamepad_frame(state: Dictionary, delta: float) -> void:
	_apply_gamepad_camera(state, delta)
	_apply_gamepad_actions(state)
	_gamepad_prev_buttons = state.duplicate()


func _apply_gamepad_camera(state: Dictionary, delta: float) -> void:
	var right_x := _gamepad_axis(state, "right_x")
	var right_y := _gamepad_axis(state, "right_y")
	var left_x := _gamepad_axis(state, "left_x")
	var left_y := _gamepad_axis(state, "left_y")
	var lt := clampf(float(state.get("lt", 0.0)), 0.0, 1.0)
	var rt := clampf(float(state.get("rt", 0.0)), 0.0, 1.0)
	var moved := false
	if right_x != 0.0 or right_y != 0.0:
		_camera_yaw -= right_x * GAMEPAD_ORBIT_SPEED * delta
		_camera_pitch = clampf(_camera_pitch - right_y * GAMEPAD_ORBIT_SPEED * delta, deg_to_rad(12.0), deg_to_rad(82.0))
		moved = true
	if left_x != 0.0 or left_y != 0.0:
		var right := Vector3(cos(_camera_yaw), 0.0, -sin(_camera_yaw))
		var forward := Vector3(-right.z, 0.0, right.x)
		var pan_scale := _camera_distance * GAMEPAD_PAN_SPEED * delta
		_camera_focus += (right * left_x + forward * -left_y) * pan_scale
		moved = true
	if lt > GAMEPAD_DEADZONE:
		_camera_distance = minf(80.0, _camera_distance + GAMEPAD_ZOOM_SPEED * lt * delta)
		moved = true
	if rt > GAMEPAD_DEADZONE:
		_camera_distance = maxf(4.0, _camera_distance - GAMEPAD_ZOOM_SPEED * rt * delta)
		moved = true
	if moved:
		_update_camera()


func _gamepad_axis(state: Dictionary, name: String) -> float:
	var value := float(state.get(name, 0.0))
	return value if absf(value) > GAMEPAD_DEADZONE else 0.0


func _apply_gamepad_actions(state: Dictionary) -> void:
	if _gamepad_button_just_pressed(state, "a"):
		_gamepad_place_or_select()
	if _gamepad_button_just_pressed(state, "b"):
		_gamepad_erase()
	if _gamepad_button_just_pressed(state, "x"):
		_rotate_selection_or_brush()
	if _gamepad_button_just_pressed(state, "y"):
		_cycle_place_kind()
	if _gamepad_button_just_pressed(state, "lb"):
		_cycle_palette_selection(-1)
	if _gamepad_button_just_pressed(state, "rb"):
		_cycle_palette_selection(1)
	# Sets _active_layer/_fine_layer directly rather than only setting the
	# SpinBox's .value and relying on its value_changed signal to update
	# them - that signal isn't guaranteed to fire synchronously outside a
	# live, processing tree, and updating our own state directly is the
	# correct source-of-truth direction anyway (the SpinBox is a display of
	# this state, not the owner of it). set_value_no_signal keeps the
	# spinbox's displayed number in sync without a redundant round-trip.
	if _gamepad_button_just_pressed(state, "dpad_up"):
		_active_layer += 1
		if _layer_spin:
			_layer_spin.set_value_no_signal(_active_layer)
		_refresh_grid()
	if _gamepad_button_just_pressed(state, "dpad_down"):
		_active_layer = maxi(0, _active_layer - 1)
		if _layer_spin:
			_layer_spin.set_value_no_signal(_active_layer)
		_refresh_grid()
	if _gamepad_button_just_pressed(state, "dpad_right"):
		_fine_layer = mini(FINE_CELLS_PER_UNIT - 1, _fine_layer + 1)
		if _fine_layer_spin:
			_fine_layer_spin.set_value_no_signal(_fine_layer)
	if _gamepad_button_just_pressed(state, "dpad_left"):
		_fine_layer = maxi(0, _fine_layer - 1)
		if _fine_layer_spin:
			_fine_layer_spin.set_value_no_signal(_fine_layer)
	if _gamepad_button_just_pressed(state, "start"):
		_undo()
	if _gamepad_button_just_pressed(state, "back"):
		_redo()


func _gamepad_button_just_pressed(state: Dictionary, name: String) -> bool:
	return bool(state.get(name, false)) and not bool(_gamepad_prev_buttons.get(name, false))


## The controller-only equivalent of a left mouse click: aims from the fixed
## viewport-center reticle rather than a hover position, then reuses
## whichever tool is currently active exactly the way a real click would.
## Deliberately covers only place/select/connected for this first pass -
## paste/move/staged-blueprint placement stay mouse-only for now.
func _gamepad_place_or_select() -> void:
	if _viewport_container == null:
		return
	var reticle := _viewport_container.size / 2.0
	if _place_kind == "part" and _tool == "place":
		var fine_value := _mouse_to_fine_cell(reticle)
		if fine_value != null:
			_place_at(fine_value)
		return
	var cell_value := _mouse_to_cell(reticle)
	if cell_value == null:
		return
	var cell: Vector3i = cell_value
	match _tool:
		"place":
			_place_at(cell)
		"select":
			_select_single(cell)
		"connected":
			_select_connected(cell)


## The controller-only equivalent of a right-click erase, aimed from the
## same fixed reticle _gamepad_place_or_select uses.
func _gamepad_erase() -> void:
	if _viewport_container == null:
		return
	var reticle := _viewport_container.size / 2.0
	if _place_kind == "part":
		var fine_value := _mouse_to_fine_cell(reticle)
		if fine_value != null:
			var fine_cell: Vector3i = fine_value
			_transact("Erase part", func() -> void: _document.erase_placed_part(fine_cell))
		return
	var cell_value := _mouse_to_cell(reticle)
	if cell_value != null:
		var erase_cells := _mirror_cells(cell_value)
		_transact("Erase block", func() -> void:
			for target: Vector3i in erase_cells:
				_document.erase_block(target)
		)


## Switches which palette tab is active (Block -> Component -> Marker ->
## Part -> back to Block), selecting that tab's first entry - lets a
## controller-only player change what they're placing without a mouse.
func _cycle_place_kind() -> void:
	var index := GAMEPAD_PLACE_KIND_ORDER.find(_place_kind)
	var next: String = GAMEPAD_PLACE_KIND_ORDER[(index + 1) % GAMEPAD_PLACE_KIND_ORDER.size()] if index != -1 else GAMEPAD_PLACE_KIND_ORDER[0]
	match next:
		"block":
			_cycle_list_selection(_block_list, 0, _on_block_selected, true)
		"component":
			_cycle_list_selection(_component_list, 0, _on_component_selected, true)
		"marker":
			_cycle_list_selection(_marker_list, 0, _on_marker_selected, true)
		"part":
			_cycle_list_selection(_part_list, 0, _on_part_selected, true)


## Steps the selection within the current palette tab forward/backward -
## picking a different block/component/marker/part without a mouse.
func _cycle_palette_selection(direction: int) -> void:
	match _place_kind:
		"block":
			_cycle_list_selection(_block_list, direction, _on_block_selected, false)
		"component":
			_cycle_list_selection(_component_list, direction, _on_component_selected, false)
		"marker":
			_cycle_list_selection(_marker_list, direction, _on_marker_selected, false)
		"part":
			_cycle_list_selection(_part_list, direction, _on_part_selected, false)


## Shared by _cycle_place_kind (jump_to_first=true, always index 0) and
## _cycle_palette_selection (step by `direction` from whatever's already
## selected). ItemList.select() does not emit item_selected, so the
## matching _on_*_selected callback is invoked explicitly.
func _cycle_list_selection(list: ItemList, direction: int, callback: Callable, jump_to_first: bool) -> void:
	if list == null or list.item_count == 0:
		return
	var next := 0
	if not jump_to_first:
		var selected := list.get_selected_items()
		var current := selected[0] if not selected.is_empty() else 0
		next = posmod(current + direction, list.item_count)
	list.select(next)
	callback.call(next)


func _update_hover(mouse: Vector2) -> void:
	if _hover_mesh == null:
		return
	if _place_kind == "part":
		_update_hover_part(mouse)
		return
	_set_fine_grid_visible(false)
	var value := _mouse_to_cell(mouse)
	_hover_mesh.visible = value != null
	if value == null:
		return
	for child: Node in _hover_mesh.get_children():
		child.queue_free()
	var requested: Vector3i = value
	if _tool in ["line", "fill", "box", "shell"] and _anchor_cell != null:
		_update_two_point_preview(requested)
		return
	if _tool == "connected":
		_update_connected_preview(requested)
		return
	if _place_kind == "block":
		_hover_mesh.position = Vector3(requested)
		_hover_mesh.add_child(ShapeFactory.create_shape(_selected_shape_id, _brush_rotation, 0, _hover_valid_material, 0.08))
		_add_mirror_ghosts(requested)
	elif _place_kind == "component":
		var definition := _find_definition(_components, _selected_component_id)
		var snap: Dictionary = SnapResolver.find_snapped_origin(_document, requested, definition, _brush_rotation, _components)
		var origin: Vector3i = snap.get("origin", requested)
		var valid := SnapResolver.can_place(_document, origin, definition, _brush_rotation) and (not bool(definition.get("snap_required", false)) or bool(snap.get("found", false)))
		_hover_mesh.position = Vector3(origin)
		for offset: Vector3i in SnapResolver.rotated_footprint(definition, _brush_rotation):
			var part: Node3D = ShapeFactory.create_shape("cube", 0, 0, _hover_valid_material if valid else _hover_invalid_material, 0.14)
			part.position += Vector3(offset)
			_hover_mesh.add_child(part)
	else:
		_hover_mesh.position = Vector3(requested)
		_hover_mesh.add_child(ShapeFactory.create_shape("plate", _brush_rotation, 0, _hover_valid_material, 0.08))


## The hover ghost of every mirrored copy the active mirror mode would
## place alongside the block under the cursor. Added as children of
## _hover_mesh (which sits at the hovered cell), so each ghost is offset
## by the mirrored cell's delta from the hovered one.
func _add_mirror_ghosts(cell: Vector3i) -> void:
	for flip: Array in _mirror_flips():
		var mirrored := _mirrored_cell(cell, flip[0], flip[1])
		if mirrored == cell:
			continue
		var data := _mirrored_block_data(_make_block_data(), flip[0], flip[1])
		var ghost: Node3D = ShapeFactory.create_shape(_selected_shape_id, int(data["rotation_steps"]), 0, _hover_valid_material, 0.08)
		ghost.position += Vector3(mirrored - cell)
		_hover_mesh.add_child(ghost)


## Hard cap on ghost instances per preview rebuild. Previews use one
## MultiMesh so even a large box stays a single draw call, but there is no
## point quantizing beyond this - a 6000-cell preview already reads as
## "the whole region".
const PREVIEW_CELL_LIMIT := 6000


## Live ghost of everything a two-point tool would place once the second
## point is clicked - pattern cells from the anchor to the hovered cell,
## mirrored copies included.
func _update_two_point_preview(cell: Vector3i) -> void:
	var seen := {}
	var cells: Array[Vector3i] = []
	for target: Vector3i in _tool_pattern_cells(_tool, _anchor_cell, cell):
		if cells.size() >= PREVIEW_CELL_LIMIT:
			break
		for expanded: Vector3i in _mirror_cells(target):
			var key := ForgeDocument.cell_key(expanded)
			if seen.has(key):
				continue
			seen[key] = true
			cells.append(expanded)
	_hover_mesh.position = Vector3.ZERO
	_hover_mesh.add_child(_cells_multimesh(cells, _hover_valid_material))
	_set_status("%s preview: %d blocks — click to confirm, Esc to cancel" % [_tool.capitalize(), cells.size()])


## Hovering with the Connected tool highlights the flood-fill region a
## click would select, so "what counts as connected" is visible up front.
func _update_connected_preview(cell: Vector3i) -> void:
	var cells := _connected_cells(cell, PREVIEW_CELL_LIMIT)
	_hover_mesh.visible = not cells.is_empty()
	if cells.is_empty():
		return
	_hover_mesh.position = Vector3.ZERO
	_hover_mesh.add_child(_cells_multimesh(cells, _hover_select_material))


func _cells_multimesh(cells: Array[Vector3i], material: StandardMaterial3D) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.98
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = cells.size()
	for index: int in cells.size():
		multimesh.set_instance_transform(index, Transform3D(Basis(), Vector3(cells[index]) + Vector3.ONE * 0.5))
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	return instance


## Part-mode hover: resolves on the fine grid (not the coarse structure
## grid _update_hover uses for everything else), previews the snapped
## position when a compatible socket is in range, and keeps the local
## fine-grid overlay following the cursor so the sub-cell resolution is
## actually visible, not just active.
func _update_hover_part(mouse: Vector2) -> void:
	var value := _mouse_to_fine_cell(mouse)
	_hover_mesh.visible = value != null
	if value == null:
		_set_fine_grid_visible(false)
		return
	for child: Node in _hover_mesh.get_children():
		child.queue_free()
	var fine_cell: Vector3i = value
	var raw_position := Vector3(fine_cell) * DocumentScript.FINE_CELL_SIZE
	var part_profile: PartProfile = _part_registry.get_part(_selected_part_id) if _part_registry else null
	var preview_position := raw_position
	if part_profile != null and _part_registry != null:
		var snap: Dictionary = PartSnapResolver.find_snap(_document, _part_registry.get_part, part_profile, raw_position, _brush_rotation)
		if snap.get("found", false):
			preview_position = snap.get("position")
	_hover_mesh.position = preview_position
	if part_profile != null:
		var preview := PartGeometryFactory.create_part(part_profile, _hover_valid_material)
		preview.rotation.y = -float(posmod(_brush_rotation, 4)) * PI * 0.5
		_hover_mesh.add_child(preview)
	_fine_grid_center = raw_position
	_set_fine_grid_visible(true)


func _refresh_world() -> void:
	if _content_root == null:
		return
	for child: Node in _content_root.get_children():
		child.queue_free()
	_refresh_grid()
	for key: String in _document.blocks:
		var block: Dictionary = _document.blocks[key]
		var block_id := StringName(block.get("block_id", "stone"))
		var material := _block_render_material(block_id, _selected_cells.has(key))
		var cell := ForgeDocument.key_cell(key)
		_add_block_shape(cell, block, material)
		if _block_light_info.has(block_id):
			_add_light_fixture(cell, _block_light_info[block_id])
	for component: Dictionary in _document.components:
		_add_component_visual(component)
	for marker: Dictionary in _document.markers:
		_add_marker(_array_cell(marker.get("pos", [0, 0, 0])), str(marker.get("marker_type", "worker_position")), _selected_marker_ids.has(str(marker.get("id", ""))))
	for instance: Dictionary in _document.nested_instances:
		_render_nested_instance(instance)
	for key: String in _document.placed_parts:
		_add_placed_part_visual(_document.placed_parts[key], _selected_part_keys.has(key))
	# _refresh_world() clears every child of _content_root above, including
	# the fine-grid overlay _update_hover_part added - redraw it immediately
	# if part mode is still active so a document change (e.g. placing a
	# part) doesn't make the grid flicker away until the mouse next moves.
	if _place_kind == "part":
		_refresh_fine_grid()
	_finalize_button.disabled = _document.nested_instances.is_empty() if _finalize_button else true


func _refresh_grid() -> void:
	if _content_root == null:
		return
	var old := _content_root.get_node_or_null("ForgeGrid")
	if old:
		old.queue_free()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var radius := 32
	for index: int in range(-radius, radius + 1):
		mesh.surface_add_vertex(Vector3(index, _active_layer + 0.005, -radius))
		mesh.surface_add_vertex(Vector3(index, _active_layer + 0.005, radius))
		mesh.surface_add_vertex(Vector3(-radius, _active_layer + 0.005, index))
		mesh.surface_add_vertex(Vector3(radius, _active_layer + 0.005, index))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "ForgeGrid"
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.25, 0.34, 0.44, 0.38)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	_content_root.add_child(instance)
	if _mirror_mode != "off":
		# Mirror plane indicator: the geometric plane runs through the center
		# of the fixed cell column (_mirror_x/_mirror_z + 0.5). A child of the
		# grid node so it's rebuilt/cleared together with the grid.
		var mirror_mesh := ImmediateMesh.new()
		mirror_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var height := _active_layer + 0.01
		if _mirror_mode in ["x", "xz"]:
			mirror_mesh.surface_add_vertex(Vector3(_mirror_x + 0.5, height, -radius))
			mirror_mesh.surface_add_vertex(Vector3(_mirror_x + 0.5, height, radius))
		if _mirror_mode in ["z", "xz"]:
			mirror_mesh.surface_add_vertex(Vector3(-radius, height, _mirror_z + 0.5))
			mirror_mesh.surface_add_vertex(Vector3(radius, height, _mirror_z + 0.5))
		mirror_mesh.surface_end()
		var mirror_instance := MeshInstance3D.new()
		mirror_instance.name = "MirrorPlaneGizmo"
		mirror_instance.mesh = mirror_mesh
		var mirror_material := StandardMaterial3D.new()
		mirror_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mirror_material.albedo_color = Color(1.0, 0.62, 0.25, 0.8)
		mirror_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mirror_instance.material_override = mirror_material
		instance.add_child(mirror_instance)


## Shows/hides the local Workshop fine-grid overlay (only relevant while
## _place_kind == "part"). Cheap to call every mouse-move: it rebuilds a
## small, fixed-size patch (not the whole world), the same way _refresh_grid
## already rebuilds the coarse grid on every _refresh_world() call.
func _set_fine_grid_visible(visible_flag: bool) -> void:
	if not visible_flag:
		var old := _content_root.get_node_or_null("WorkshopFineGrid") if _content_root else null
		if old:
			old.queue_free()
		return
	_refresh_fine_grid()


## Draws a small local patch of the 0.125m fine grid centered on
## _fine_grid_center (kept updated by _update_hover_part), at the current
## placement height. Deliberately local rather than covering the whole
## world like _refresh_grid: at fine-grid spacing a world-sized grid would
## be 8x8 as many lines per axis as the coarse grid already draws.
func _refresh_fine_grid() -> void:
	if _content_root == null:
		return
	var old := _content_root.get_node_or_null("WorkshopFineGrid")
	if old:
		old.queue_free()
	var fine := DocumentScript.FINE_CELL_SIZE
	var half_span := 12
	var center_x := roundi(_fine_grid_center.x / fine)
	var center_z := roundi(_fine_grid_center.z / fine)
	var height := _fine_grid_center.y + 0.008
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index: int in range(-half_span, half_span + 1):
		var x := float(center_x + index) * fine
		mesh.surface_add_vertex(Vector3(x, height, float(center_z - half_span) * fine))
		mesh.surface_add_vertex(Vector3(x, height, float(center_z + half_span) * fine))
		var z := float(center_z + index) * fine
		mesh.surface_add_vertex(Vector3(float(center_x - half_span) * fine, height, z))
		mesh.surface_add_vertex(Vector3(float(center_x + half_span) * fine, height, z))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "WorkshopFineGrid"
	instance.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.42, 0.68, 0.94, 0.5)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	instance.material_override = material
	_content_root.add_child(instance)


func _add_cube(cell: Vector3i, color: Color, scale: float) -> void:
	var instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * scale
	instance.mesh = box
	instance.position = Vector3(cell) + Vector3.ONE * 0.5
	instance.material_override = _material(color)
	_content_root.add_child(instance)


## Spawns the shared flicker-light/flame effect on a light-source block.
func _add_light_fixture(cell: Vector3i, info: Dictionary) -> void:
	var fixture: Node3D = LightFixtureScript.new()
	fixture.position = Vector3(cell) + Vector3(0.5, 0.55, 0.5)
	_content_root.add_child(fixture)
	fixture.configure(info["color"], float(info["energy"]), float(info["range"]), bool(info["flame"]))


func _add_block_shape(cell: Vector3i, block: Dictionary, material: StandardMaterial3D) -> void:
	var shape_id := str(block.get("shape_id", "cube"))
	var connections: int = ShapeFactory.connection_mask_for(_document, cell, shape_id)
	var visual: Node3D = ShapeFactory.create_shape(shape_id, int(block.get("rotation_steps", 0)), connections, material)
	visual.position += Vector3(cell)
	_content_root.add_child(visual)


func _add_component_visual(component: Dictionary) -> void:
	var definition := _find_definition(_components, str(component.get("component_id", "")))
	var origin := _array_cell(component.get("pos", [0, 0, 0]))
	var steps := int(component.get("rotation_steps", 0))
	var color: Color = definition.get("color", Color.ORANGE)
	if _selected_component_ids.has(str(component.get("id", ""))):
		color = color.lerp(Color("58a6ff"), 0.65)
	for offset: Vector3i in SnapResolver.rotated_footprint(definition, steps):
		_add_cube(origin + offset, color, 0.72)
	for port: Dictionary in definition.get("ports", []):
		var port_cell := origin + SnapResolver.rotate_offset(_array_cell(port.get("cell", [0, 0, 0])), steps)
		var facing := SnapResolver.rotate_offset(_array_cell(port.get("facing", [0, 0, 1])), steps)
		_add_port_gizmo(port_cell, facing, str(port.get("type", "port")))


func _add_port_gizmo(cell: Vector3i, facing: Vector3i, port_type: String) -> void:
	var instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	instance.mesh = sphere
	instance.position = Vector3(cell) + Vector3.ONE * 0.5 + Vector3(facing) * 0.48
	var color := {"heat": Color("ff7b54"), "airflow": Color("79c0ff"), "item": Color("d2a8ff")}.get(port_type, Color.WHITE)
	instance.material_override = _material(color)
	_content_root.add_child(instance)


func _add_marker(cell: Vector3i, marker_id: String, selected := false) -> void:
	var definition := _find_definition(_markers, marker_id)
	var instance := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.14
	cylinder.bottom_radius = 0.28
	cylinder.height = 1.4
	instance.mesh = cylinder
	instance.position = Vector3(cell) + Vector3(0.5, 0.7, 0.5)
	var color: Color = definition.get("color", Color.GREEN)
	if selected:
		color = color.lerp(Color("58a6ff"), 0.7)
	instance.material_override = _material(color)
	_content_root.add_child(instance)


## Renders a Workshop-scale placed part via PartGeometryFactory. Unlike a
## block cell (a corner), a part's fine-grid cell is its own authored origin
## (see PartProfile) - its geometry is already centered there - so the part
## is simply positioned at cell * FINE_CELL_SIZE with no additional offset.
func _add_placed_part_visual(part_data: Dictionary, selected := false) -> void:
	if _part_registry == null:
		return
	var part_id := StringName(part_data.get("part_id", ""))
	var part: PartProfile = _part_registry.get_part(part_id)
	if part == null:
		return
	var steps := int(part_data.get("rotation_steps", 0))
	var color := part.color.lerp(Color("58a6ff"), 0.7) if selected else part.color
	var visual := PartGeometryFactory.create_part(part, _material(color))
	visual.position = DocumentScript.placed_part_world_position(part_data)
	visual.rotation.y = -float(posmod(steps, 4)) * PI * 0.5
	_content_root.add_child(visual)


func _render_nested_instance(instance: Dictionary) -> void:
	var source: ForgeDocument = DocumentScript.load_json(str(instance.get("source_path", "")))
	if source == null:
		return
	var origin := _array_cell(instance.get("origin", [0, 0, 0]))
	var instance_steps := int(instance.get("rotation_steps", 0))
	var is_selected := str(instance.get("id", "")) == _selected_nested_id
	for key: String in source.blocks:
		var block: Dictionary = source.blocks[key]
		var color: Color = _block_colors.get(StringName(block.get("block_id", "stone")), Color.GRAY)
		color = color.lerp(Color("58a6ff") if is_selected else Color("a371f7"), 0.55)
		var cell := origin + SnapResolver.rotate_offset(ForgeDocument.key_cell(key), instance_steps)
		var visual: Node3D = ShapeFactory.create_shape(str(block.get("shape_id", "cube")), posmod(int(block.get("rotation_steps", 0)) + instance_steps, 4), 0, _material(color), 0.12)
		visual.position += Vector3(cell)
		_content_root.add_child(visual)


func _find_nested_at(cell: Vector3i) -> String:
	for instance: Dictionary in _document.nested_instances:
		var source: ForgeDocument = DocumentScript.load_json(str(instance.get("source_path", "")))
		if source == null:
			continue
		var origin := _array_cell(instance.get("origin", [0, 0, 0]))
		var steps := int(instance.get("rotation_steps", 0))
		for key: String in source.blocks:
			if origin + SnapResolver.rotate_offset(ForgeDocument.key_cell(key), steps) == cell:
				return str(instance.get("id", ""))
	return ""


const GENERATED_TEXTURE_DIR := "res://data/textures/generated"


## Textured, triplanar-mapped material for a placed block: the block's
## generated albedo + normal layer wrapped in world-space triplanar mapping
## so every shape (stairs, fences, panes) gets textured continuously across
## cells with no UV authoring. Falls back to the old flat palette color when
## the block has no texture layer, or the PNG isn't imported (headless
## tests). Selection is a blue albedo tint over the texture, replacing the
## flat-color lerp.
func _block_render_material(block_id: StringName, selected: bool) -> StandardMaterial3D:
	var key := "%s|%s" % [block_id, "sel" if selected else "std"]
	if _block_materials.has(key):
		return _block_materials[key]
	var info: Dictionary = _block_texture_info.get(block_id, {})
	var albedo: Texture2D = info.get("albedo_texture")
	var normal: Texture2D = null
	var layer := str(info.get("layer", ""))
	if not layer.is_empty():
		if albedo == null:
			var albedo_path := "%s/%s.png" % [GENERATED_TEXTURE_DIR, layer]
			if ResourceLoader.exists(albedo_path, "Texture2D"):
				albedo = load(albedo_path)
		var normal_path := "%s/%s_normal.png" % [GENERATED_TEXTURE_DIR, layer]
		if ResourceLoader.exists(normal_path, "Texture2D"):
			normal = load(normal_path)
	if albedo == null:
		var color: Color = _block_colors.get(block_id, Color("8b949e"))
		if selected:
			color = color.lerp(Color("58a6ff"), 0.65)
		if _block_light_info.has(block_id) and not selected:
			# Light-source fixtures glow with their own light color.
			var glow: Dictionary = _block_light_info[block_id]
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 0.6
			material.emission_enabled = true
			material.emission = glow["color"]
			material.emission_energy_multiplier = 0.9
			_block_materials[key] = material
			return material
		return _material(color)
	var material := StandardMaterial3D.new()
	material.albedo_texture = albedo
	material.albedo_color = Color.WHITE.lerp(Color("58a6ff"), 0.6) if selected else Color.WHITE
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = 0.7
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * float(info.get("scale", 1.0))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC
	material.roughness = float(info.get("roughness", 0.9))
	_block_materials[key] = material
	return material


func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html(true)
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if color.a < 0.999:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.88
	_materials[key] = material
	return material


func _ghost_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material


func _find_definition(definitions: Array, id: String) -> Dictionary:
	for definition: Dictionary in definitions:
		if definition.get("id", "") == id:
			return definition
	return {}


func _array_cell(value: Variant) -> Vector3i:
	var pos: Array = value if value is Array else [0, 0, 0]
	return Vector3i(int(pos[0]), int(pos[1]), int(pos[2])) if pos.size() == 3 else Vector3i.ZERO


func _new_id(prefix: String) -> String:
	_id_sequence += 1
	return "%s_%d_%d" % [prefix, Time.get_ticks_usec(), _id_sequence]


func _set_status(text: String) -> void:
	if _status:
		_status.text = "%s%s  ·  %d blocks  ·  %d components  ·  %d parts  ·  %d markers" % [
			text,
			"  • UNSAVED" if _dirty else "",
			_document.blocks.size(),
			_document.components.size(),
			_document.placed_parts.size(),
			_document.markers.size(),
		]
