class_name RtsCommandController
extends Node

## Translates pointer input into unit commands via camera raycasts.
##
## Desktop (mouse):
##   left-click  -> select the unit under the cursor, or deselect if none
##   right-click -> order the selected unit to the ground point under the cursor
##
## Touch (touch_enabled, set by GameMain on touchscreen devices): there's no
## right-click, so a single-finger TAP unifies both - tap a unit to select it,
## tap the ground with a unit selected to order it there. Commands fire on the
## tap RELEASE (press+release with little travel) so a one-finger pan-drag or a
## two-finger camera gesture never issues a stray order.
##
## Ground picks hit the terrain's trimesh collider (physics layer 1); unit
## picks hit each Unit's pick Area3D (layer 2). Kept single-select for this
## first slice - box-select and unit groups come once there's more than one
## thing worth selecting.

const GROUND_MASK := 1
const UNIT_MASK := 2
const RAY_LENGTH := 4000.0
## Max pointer travel (pixels) between press and release still counted as a tap
## rather than a drag - a finger that moved farther than this was panning.
const TAP_MAX_TRAVEL := 18.0

var camera: Camera3D
var world: WorldRuntime
## Set true by GameMain when a touchscreen is present. Switches command firing
## from mouse-press to tap-release and unifies select/move into one tap.
var touch_enabled := false
## The camera rig, queried to suppress commands mid pinch/twist (its first
## finger emulates a mouse click that would otherwise select/move).
var camera_rig: RtsCameraController

var _selected: Unit
var _tap_pending := false
var _tap_travel := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	if touch_enabled:
		_handle_touch_input(event)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_select(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_move_order(event.position)


func _handle_touch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_tap_pending = true
			_tap_travel = 0.0
		else:
			var was_tap := _tap_pending and _tap_travel <= TAP_MAX_TRAVEL
			_tap_pending = false
			if was_tap and not _gesture_active():
				_handle_tap(event.position)
	elif event is InputEventMouseMotion and _tap_pending:
		_tap_travel += event.relative.length()


func _gesture_active() -> bool:
	return camera_rig != null and camera_rig.is_gesture_active()


## Touch tap: select the unit under the finger if there is one, otherwise order
## the already-selected unit to the tapped ground point.
func _handle_tap(screen_position: Vector2) -> void:
	var unit := _unit_from_hit(_raycast(screen_position, UNIT_MASK, true))
	if unit != null:
		_set_selected(unit)
		return
	if _selected != null:
		var ground := _raycast(screen_position, GROUND_MASK, false)
		if not ground.is_empty():
			_selected.move_to(ground.position)


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
