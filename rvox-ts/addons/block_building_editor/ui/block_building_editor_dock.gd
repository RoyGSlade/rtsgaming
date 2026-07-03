@tool
extends VBoxContainer

signal blueprint_load_requested(path: String)
signal mode_changed(mode: StringName)
signal block_selected(block_id: StringName)

const BUILD_LAYERS := ["foundation", "floor", "wall", "interior", "workstation", "storage", "roof", "fx", "decoration"]

var _status_label: Label
var _blueprint_path: LineEdit

# Block palette state.
var _block_grid: GridContainer
var _palette_search: LineEdit
var _palette_category: OptionButton
var _selected_label: Label
var _selected_block_id: StringName = &""

# Build / stacking state.
var _build_blocks: Array[Dictionary] = []
var _column_heights: Dictionary = {}   # Vector2i(x, z) -> next free Y
var _build_x: SpinBox
var _build_z: SpinBox
var _build_layer: OptionButton
var _build_list: ItemList
var _build_count_label: Label
var _build_selected_label: Label
var _save_path: LineEdit
var _save_id: LineEdit

func _ready() -> void:
    _build_ui()

func _build_ui() -> void:
    for child in get_children():
        child.queue_free()

    var title := Label.new()
    title.text = "Block Building Editor"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    add_child(title)

    _status_label = Label.new()
    _status_label.text = "Status: idle"
    add_child(_status_label)

    _blueprint_path = LineEdit.new()
    _blueprint_path.text = "res://data/buildings/forge_blueprint_example.json"
    _blueprint_path.placeholder_text = "Blueprint JSON path"
    add_child(_blueprint_path)

    var load_button := Button.new()
    load_button.text = "Load Blueprint JSON"
    load_button.pressed.connect(_on_load_blueprint_pressed)
    add_child(load_button)

    var tabs := TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    add_child(tabs)

    _add_blocks_tab(tabs)
    _add_build_tab(tabs)
    _add_external_assets_tab(tabs)
    _add_terrain_textures_tab(tabs)
    _add_tab(tabs, "Layers", [
        "Tag blocks as roof, wall, floor, interior, workstation, storage, FX.",
        "Used for cutaway view and roof hiding."
    ])
    _add_tab(tabs, "Sockets", [
        "Place worker stand points, door entries, drop-offs, pickups, rally points.",
        "Workers use these for production and construction."
    ])
    _add_tab(tabs, "Storage", [
        "Define visible storage slots for inputs and outputs.",
        "Example: iron ingot shelf, leather wrap hook, sword rack."
    ])
    _add_tab(tabs, "Recipes", [
        "Define inputs, outputs, station requirements, craft time, and animation.",
        "Example: iron_ingot + leather_wrap + wood_handle → iron_sword."
    ])
    _add_tab(tabs, "Preview", [
        "Test Normal, Cutaway, Production, and Damage views.",
        "Future: simulate worker path through the building."
    ])

func _add_tab(tabs: TabContainer, tab_name: String, lines: Array[String]) -> void:
    var box := VBoxContainer.new()
    box.name = tab_name
    box.size_flags_vertical = Control.SIZE_EXPAND_FILL

    for line in lines:
        var label := Label.new()
        label.text = line
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        box.add_child(label)

    var button := Button.new()
    button.text = "Set Mode: %s" % tab_name
    button.pressed.connect(func() -> void:
        emit_signal("mode_changed", StringName(tab_name.to_lower()))
        _set_status("Mode: %s" % tab_name)
    )
    box.add_child(button)

    tabs.add_child(box)

# --- Block palette ("block choices") -----------------------------------------

func _add_blocks_tab(tabs: TabContainer) -> void:
    var box := VBoxContainer.new()
    box.name = "Blocks"
    box.size_flags_vertical = Control.SIZE_EXPAND_FILL

    _selected_label = Label.new()
    _selected_label.text = "Selected block: (none)"
    box.add_child(_selected_label)

    var filter_row := HBoxContainer.new()
    filter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(filter_row)

    _palette_search = LineEdit.new()
    _palette_search.placeholder_text = "Search blocks..."
    _palette_search.clear_button_enabled = true
    _palette_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _palette_search.text_changed.connect(func(_text: String) -> void: _refresh_block_palette())
    filter_row.add_child(_palette_search)

    _palette_category = OptionButton.new()
    _palette_category.item_selected.connect(func(_index: int) -> void: _refresh_block_palette())
    filter_row.add_child(_palette_category)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(scroll)

    _block_grid = GridContainer.new()
    _block_grid.columns = 2
    _block_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_block_grid)

    _populate_category_filter()
    _refresh_block_palette()

    tabs.add_child(box)

func _all_block_definitions() -> Array:
    var registry := BlockRegistry.new()
    registry.load_blocks()
    var definitions: Array = []
    for block_id in registry.list_ids():
        var definition := registry.get_block(block_id)
        if definition == null or definition.id == &"air":
            continue
        definitions.append(definition)
    registry.free()
    return definitions

func _populate_category_filter() -> void:
    _palette_category.clear()
    _palette_category.add_item("All categories")
    var categories := {}
    for definition in _all_block_definitions():
        categories[String(definition.category)] = true
    var names: Array = categories.keys()
    names.sort()
    for category_name in names:
        _palette_category.add_item(category_name)

func _refresh_block_palette() -> void:
    if _block_grid == null:
        return
    for child in _block_grid.get_children():
        child.queue_free()

    var filter_text := _palette_search.text.strip_edges().to_lower() if _palette_search else ""
    var category_filter := ""
    if _palette_category and _palette_category.selected > 0:
        category_filter = _palette_category.get_item_text(_palette_category.selected)

    var shown := 0
    for definition in _all_block_definitions():
        if category_filter != "" and String(definition.category) != category_filter:
            continue
        if filter_text != "":
            var haystack := "%s %s %s" % [definition.display_name, definition.id, definition.category]
            if not filter_text in haystack.to_lower():
                continue
        _block_grid.add_child(_make_block_button(definition))
        shown += 1

    if shown == 0:
        var empty := Label.new()
        empty.text = "No blocks match the current filter."
        _block_grid.add_child(empty)

func _make_block_button(definition) -> Button:
    var button := Button.new()
    button.toggle_mode = true
    button.text = definition.display_name
    button.tooltip_text = "%s · %s" % [definition.id, definition.category]
    button.custom_minimum_size = Vector2(138.0, 48.0)
    button.button_pressed = definition.id == _selected_block_id
    var icon: Texture2D = definition.preview_icon
    if icon == null:
        icon = definition.albedo_texture
    if icon != null:
        button.icon = icon
        button.expand_icon = true
        button.icon_max_width = 36
    var block_id: StringName = definition.id
    button.set_meta("block_id", block_id)
    button.pressed.connect(func() -> void: _select_block(block_id))
    return button

func _select_block(block_id: StringName) -> void:
    _selected_block_id = block_id
    if _selected_label:
        _selected_label.text = "Selected block: %s" % block_id
    if _build_selected_label:
        _build_selected_label.text = "Placing: %s" % block_id
    # Keep the toggled highlight in sync without a full rebuild.
    if _block_grid:
        for child in _block_grid.get_children():
            if child is Button and child.has_meta("block_id"):
                (child as Button).button_pressed = child.get_meta("block_id") == block_id
    block_selected.emit(block_id)
    _set_status("Selected block: %s" % block_id)

# --- Build / stacking --------------------------------------------------------

func _add_build_tab(tabs: TabContainer) -> void:
    var box := VBoxContainer.new()
    box.name = "Build"
    box.size_flags_vertical = Control.SIZE_EXPAND_FILL

    _build_selected_label = Label.new()
    _build_selected_label.text = "Placing: (select a block in Blocks tab)"
    box.add_child(_build_selected_label)

    var help := Label.new()
    help.text = "Pick a grid column (X, Z). Placing repeatedly stacks blocks upward on that column."
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(help)

    var coord_row := HBoxContainer.new()
    box.add_child(coord_row)
    coord_row.add_child(_labeled("X", func() -> Control:
        _build_x = _make_coord_spin()
        return _build_x
    ))
    coord_row.add_child(_labeled("Z", func() -> Control:
        _build_z = _make_coord_spin()
        return _build_z
    ))
    coord_row.add_child(_labeled("Layer", func() -> Control:
        _build_layer = OptionButton.new()
        for layer in BUILD_LAYERS:
            _build_layer.add_item(layer)
        return _build_layer
    ))

    var button_row := HBoxContainer.new()
    box.add_child(button_row)

    var place_button := Button.new()
    place_button.text = "Place / Stack Block"
    place_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    place_button.pressed.connect(_on_place_block)
    button_row.add_child(place_button)

    var remove_button := Button.new()
    remove_button.text = "Remove Top"
    remove_button.pressed.connect(_on_remove_top)
    button_row.add_child(remove_button)

    var clear_button := Button.new()
    clear_button.text = "Clear"
    clear_button.pressed.connect(_on_clear_build)
    button_row.add_child(clear_button)

    _build_count_label = Label.new()
    _build_count_label.text = "Blocks: 0"
    box.add_child(_build_count_label)

    _build_list = ItemList.new()
    _build_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _build_list.custom_minimum_size = Vector2(0.0, 120.0)
    box.add_child(_build_list)

    var save_row := HBoxContainer.new()
    box.add_child(save_row)
    _save_id = LineEdit.new()
    _save_id.text = "new_building"
    _save_id.placeholder_text = "blueprint id"
    _save_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_row.add_child(_save_id)

    _save_path = LineEdit.new()
    _save_path.text = "res://data/buildings/new_building_blueprint.json"
    _save_path.placeholder_text = "save path"
    _save_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_row.add_child(_save_path)

    var save_button := Button.new()
    save_button.text = "Save Blueprint JSON"
    save_button.pressed.connect(_on_save_blueprint)
    box.add_child(save_button)

    tabs.add_child(box)

func _labeled(text: String, builder: Callable) -> Control:
    var wrap := VBoxContainer.new()
    var label := Label.new()
    label.text = text
    wrap.add_child(label)
    wrap.add_child(builder.call())
    return wrap

func _make_coord_spin() -> SpinBox:
    var spin := SpinBox.new()
    spin.min_value = -64.0
    spin.max_value = 64.0
    spin.step = 1.0
    spin.value = 0.0
    return spin

func _on_place_block() -> void:
    if _selected_block_id == &"":
        _set_status("Select a block first (Blocks tab).")
        return
    var x := int(_build_x.value)
    var z := int(_build_z.value)
    var key := Vector2i(x, z)
    var y: int = _column_heights.get(key, 0)
    var layer: String = BUILD_LAYERS[_build_layer.selected] if _build_layer.selected >= 0 else "floor"
    _build_blocks.append({
        "pos": [x, y, z],
        "block_id": String(_selected_block_id),
        "layer": layer,
        "tags": [],
        "build_stage": layer,
        "requires_support": y > 0,
    })
    _column_heights[key] = y + 1
    _refresh_build_list()
    _set_status("Placed %s at (%d, %d, %d)" % [_selected_block_id, x, y, z])

func _on_remove_top() -> void:
    var x := int(_build_x.value)
    var z := int(_build_z.value)
    var key := Vector2i(x, z)
    var height: int = _column_heights.get(key, 0)
    if height <= 0:
        _set_status("Column (%d, %d) is empty." % [x, z])
        return
    var top_y := height - 1
    for i in range(_build_blocks.size() - 1, -1, -1):
        var pos: Array = _build_blocks[i]["pos"]
        if pos[0] == x and pos[1] == top_y and pos[2] == z:
            _build_blocks.remove_at(i)
            break
    _column_heights[key] = top_y
    _refresh_build_list()
    _set_status("Removed top of column (%d, %d)" % [x, z])

func _on_clear_build() -> void:
    _build_blocks.clear()
    _column_heights.clear()
    _refresh_build_list()
    _set_status("Cleared build.")

func _refresh_build_list() -> void:
    if _build_list == null:
        return
    _build_list.clear()
    for block in _build_blocks:
        var pos: Array = block["pos"]
        _build_list.add_item("%s @ (%d, %d, %d) [%s]" % [block["block_id"], pos[0], pos[1], pos[2], block["layer"]])
    _build_count_label.text = "Blocks: %d" % _build_blocks.size()

func _on_save_blueprint() -> void:
    if _build_blocks.is_empty():
        _set_status("Nothing to save — place some blocks first.")
        return
    var blueprint_id := _save_id.text.strip_edges()
    if blueprint_id.is_empty():
        blueprint_id = "new_building"
    var data := {
        "id": blueprint_id,
        "display_name": blueprint_id.replace("_", " ").capitalize(),
        "category": "production",
        "era": "village",
        "footprint": [1, 1],
        "health": 100,
        "workers_required": 1,
        "required_functional_tags": [],
        "blocks": _build_blocks,
        "sockets": [],
        "storage_slots": [],
        "recipes": [],
    }
    var path := _save_path.text.strip_edges()
    var error := BlueprintSerializer.save_blueprint_json(path, data)
    if error != OK:
        _set_status("Save failed (%s): %s" % [error_string(error), path])
        push_error("Blueprint save failed: %s" % error_string(error))
        return
    if Engine.is_editor_hint():
        var fs := EditorInterface.get_resource_filesystem()
        if fs:
            fs.scan()
    _set_status("Saved %d blocks → %s" % [_build_blocks.size(), path])

# --- External assets ---------------------------------------------------------

func _add_external_assets_tab(tabs: TabContainer) -> void:
    var box := VBoxContainer.new()
    box.name = "External Assets"
    box.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var help := Label.new()
    help.text = "Import KayKit or Kenney assets into generated metadata. Existing generated definitions are preserved unless overwrite is enabled."
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(help)

    var overwrite := CheckBox.new()
    overwrite.text = "Allow overwrite"
    box.add_child(overwrite)

    var sources := {
        "Import KayKit Block Bits": "res://assets/external/kaykit/block_bits_source.tres",
        "Import KayKit Resource Bits": "res://assets/external/kaykit/resource_bits_source.tres",
        "Import Kenney Voxel Pack": "res://assets/external/kenney/voxel_pack_source.tres",
    }
    for label: String in sources:
        var button := Button.new()
        button.text = label
        var source_path: String = sources[label]
        button.pressed.connect(func() -> void:
            _run_external_import(source_path, overwrite.button_pressed)
        )
        box.add_child(button)

    var refresh := Button.new()
    refresh.text = "Refresh Block Palette"
    refresh.pressed.connect(func() -> void:
        _populate_category_filter()
        _refresh_block_palette()
        _set_status("Block palette refreshed.")
    )
    box.add_child(refresh)

    tabs.add_child(box)

func _run_external_import(source_path: String, allow_overwrite: bool) -> void:
    var source := load(source_path) as AssetSourceDefinition
    if source == null:
        _set_status("Missing asset source: %s" % source_path)
        return
    var report := ExternalAssetPackImporter.new().import_source(source, allow_overwrite)
    _set_status("%s: %d created, %d updated, %d skipped, %d failed" % [
        source.display_name,
        report.created,
        report.updated,
        report.skipped,
        report.failed,
    ])
    if report.failed > 0:
        push_error("External asset import errors: %s" % report.errors)

# --- Terrain textures ---------------------------------------------------------

func _add_terrain_textures_tab(tabs: TabContainer) -> void:
    var box := VBoxContainer.new()
    box.name = "Terrain Textures"
    box.size_flags_vertical = Control.SIZE_EXPAND_FILL

    var help := Label.new()
    help.text = "Generate procedural block/overlay textures from res://data/textures/recipes, then pack them into the shared Texture2DArray atlas used by the terrain shader."
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(help)

    var generate_button := Button.new()
    generate_button.text = "Generate Textures"
    generate_button.pressed.connect(_on_generate_terrain_textures)
    box.add_child(generate_button)

    var pack_button := Button.new()
    pack_button.text = "Rebuild Texture Array"
    pack_button.pressed.connect(_on_rebuild_texture_array)
    box.add_child(pack_button)

    tabs.add_child(box)

func _on_generate_terrain_textures() -> void:
    var report := TextureArrayPacker.new().generate_all()
    if Engine.is_editor_hint():
        var fs := EditorInterface.get_resource_filesystem()
        if fs:
            fs.scan()
    _set_status("Generated %d texture(s), %d failed" % [report.generated, report.failed])
    if report.failed > 0:
        push_error("Texture generation errors: %s" % report.errors)

func _on_rebuild_texture_array() -> void:
    var report := TextureArrayPacker.new().pack()
    if Engine.is_editor_hint():
        var fs := EditorInterface.get_resource_filesystem()
        if fs:
            fs.scan()
    if report.failed > 0:
        _set_status("Texture array rebuild failed: %s" % report.errors)
        push_error("Texture array packing errors: %s" % report.errors)
    else:
        _set_status("Packed %d layer(s) → %s" % [report.packed, report.atlas_path])

func _on_load_blueprint_pressed() -> void:
    var path := _blueprint_path.text.strip_edges()
    _set_status("Load requested: %s" % path)
    emit_signal("blueprint_load_requested", path)

func _set_status(text: String) -> void:
    if _status_label:
        _status_label.text = "Status: %s" % text

func set_status(text: String) -> void:
    _set_status(text)
