@tool
extends EditorPlugin

const DockScript := preload("res://addons/block_building_editor/ui/block_building_editor_dock.gd")

var dock: Control

func _enter_tree() -> void:
    dock = DockScript.new()
    dock.name = "Block Building Editor"
    dock.blueprint_load_requested.connect(_on_blueprint_load_requested)
    add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

func _exit_tree() -> void:
    if dock:
        remove_control_from_docks(dock)
        dock.queue_free()
        dock = null

func _on_blueprint_load_requested(path: String) -> void:
    var blueprint := BuildingBlueprintLoader.load_from_json(path)
    if blueprint == null:
        dock.set_status("Blueprint load failed")
        return
    var counts := blueprint.get_required_block_counts()
    dock.set_status("Loaded %s · %d blocks" % [blueprint.display_name, blueprint.blocks.size()])
    print("[Block Building Editor] %s required blocks: %s" % [blueprint.display_name, counts])
