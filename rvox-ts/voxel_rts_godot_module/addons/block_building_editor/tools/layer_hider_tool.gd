@tool
class_name LayerHiderTool
extends RefCounted

static func set_layer_visible(root: Node, layer_name: StringName, visible: bool) -> void:
    if root == null:
        return
    for node in root.find_children("*", "Node", true, false):
        if node.has_meta("building_layer") and node.get_meta("building_layer") == layer_name:
            if node is CanvasItem:
                node.visible = visible
            elif node is Node3D:
                node.visible = visible

static func set_roof_hidden(root: Node, hidden: bool) -> void:
    set_layer_visible(root, &"roof", not hidden)
