class_name RtsCommandController
extends Node

## Translates mouse clicks into unit commands via camera raycasts:
##   left-click  -> select the unit under the cursor, or deselect if none
##   right-click -> order the selected unit to the ground point under the cursor
##
## Ground picks hit the terrain's trimesh collider (physics layer 1); unit
## picks hit each Unit's pick Area3D (layer 2). Kept single-select for this
## first slice - box-select and unit groups come once there's more than one
## thing worth selecting.

const GROUND_MASK := 1
const UNIT_MASK := 2
const RAY_LENGTH := 4000.0

var camera: Camera3D
var world: WorldRuntime

var _selected: Unit


func _unhandled_input(event: InputEvent) -> void:
	if camera == null or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_select(event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_move_order(event.position)


func get_selected() -> Unit:
	return _selected


func _handle_select(screen_position: Vector2) -> void:
	var hit := _raycast(screen_position, UNIT_MASK, true)
	var unit := _unit_from_hit(hit)
	_set_selected(unit)


func _handle_move_order(screen_position: Vector2) -> void:
	if _selected == null:
		return
	var hit := _raycast(screen_position, GROUND_MASK, false)
	if hit.is_empty():
		return
	_selected.move_to(hit.position)


func _set_selected(unit: Unit) -> void:
	if _selected == unit:
		return
	if _selected != null:
		_selected.selected = false
	_selected = unit
	if _selected != null:
		_selected.selected = true


func _unit_from_hit(hit: Dictionary) -> Unit:
	if hit.is_empty():
		return null
	var collider = hit.get("collider")
	# The pick shape lives on an Area3D child of the Unit.
	var node := collider as Node
	while node != null:
		if node is Unit:
			return node
		node = node.get_parent()
	return null


func _raycast(screen_position: Vector2, mask: int, hit_areas: bool) -> Dictionary:
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * RAY_LENGTH
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = mask
	params.collide_with_areas = hit_areas
	params.collide_with_bodies = not hit_areas
	return camera.get_world_3d().direct_space_state.intersect_ray(params)
