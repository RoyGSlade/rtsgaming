class_name LayerVisibilityController
extends Node

@export var root_node: Node
@export var roof_layer_name: StringName = &"roof"
@export var front_wall_layer_name: StringName = &"front_wall"

func set_normal_view() -> void:
    set_layer_visible(roof_layer_name, true)
    set_layer_visible(front_wall_layer_name, true)

func set_cutaway_view() -> void:
    set_layer_visible(roof_layer_name, false)
    set_layer_visible(front_wall_layer_name, false)

func set_production_view() -> void:
    set_layer_visible(roof_layer_name, false)
    set_layer_visible(front_wall_layer_name, false)
    # Future: fade decoration and highlight workstation/storage nodes.

func set_layer_visible(layer: StringName, visible: bool) -> void:
    var root := root_node if root_node else get_parent()
    if root == null:
        return
    for node in root.find_children("*", "Node", true, false):
        if node.has_meta("building_layer") and node.get_meta("building_layer") == layer:
            if node is Node3D:
                node.visible = visible
            elif node is CanvasItem:
                node.visible = visible
