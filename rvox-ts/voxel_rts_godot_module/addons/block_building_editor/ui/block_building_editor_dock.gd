@tool
extends VBoxContainer

signal blueprint_load_requested(path: String)
signal mode_changed(mode: StringName)

var _status_label: Label
var _blueprint_path: LineEdit

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

    _add_tab(tabs, "Blocks", [
        "Place/remove block cells.",
        "Future: palette, brush, fill, mirror, rotate."
    ])
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

func _on_load_blueprint_pressed() -> void:
    var path := _blueprint_path.text.strip_edges()
    _set_status("Load requested: %s" % path)
    emit_signal("blueprint_load_requested", path)

func _set_status(text: String) -> void:
    if _status_label:
        _status_label.text = "Status: %s" % text

func set_status(text: String) -> void:
    _set_status(text)
