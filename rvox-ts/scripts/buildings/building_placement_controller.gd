class_name BuildingPlacementController
extends Node

## Runs the place-a-building flow: HUD picks a catalog entry via begin(), a
## translucent ghost then follows the terrain under the cursor (snapped to the
## block grid), and left-click drops a solid placeholder into buildings_root.
## Right-click or Escape cancels. RtsCommandController checks is_active() so
## unit select/move commands stay quiet while a ghost is up.
##
## Validity is deliberately simple for this first pass: footprint inside the
## chunk, ground reasonably flat, no overlap with an already-placed footprint.
## Water/resource-node checks come with the real construction system.

signal building_placed(entry: Dictionary, world_position: Vector3)
signal placement_cancelled

const PlaceholderBuildingScript := preload("res://scripts/buildings/placeholder_building.gd")

const RAY_LENGTH := 4000.0
const GROUND_MASK := 1
## Max height difference across the footprint corners still counted as
## buildable ground.
const MAX_HEIGHT_SPREAD := 1.5

var camera: Camera3D
var world: WorldRuntime
## Parent for placed placeholder buildings (created by GameMain).
var buildings_root: Node3D

var _ghost: PlaceholderBuilding
var _entry: Dictionary
var _valid := false
## XZ footprints of everything placed so far, for overlap rejection.
var _placed_rects: Array[Rect2] = []


func is_active() -> bool:
	return _ghost != null


func begin(entry: Dictionary) -> void:
	cancel()
	_entry = entry
	_ghost = PlaceholderBuildingScript.new()
	_ghost.setup(entry)
	add_child(_ghost)
	_ghost.set_ghost(false)
	_valid = false
	_update_ghost(get_viewport().get_mouse_position())


func cancel() -> void:
	if _ghost == null:
		return
	_ghost.queue_free()
	_ghost = null
	_entry = {}
	placement_cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _ghost == null or camera == null:
		return
	if event is InputEventMouseMotion:
		_update_ghost(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if _valid:
				_place()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel()
		get_viewport().set_input_as_handled()


func _update_ghost(screen_position: Vector2) -> void:
	var hit := _raycast_ground(screen_position)
	if hit.is_empty():
		_ghost.visible = false
		_valid = false
		return
	_ghost.visible = true

	var footprint: Array = _entry.get("footprint", [3, 3])
	var width := float(footprint[0])
	var depth := float(footprint[1])
	# Snap the footprint's min corner to the block grid so placeholder walls
	# line up with terrain blocks regardless of odd/even footprint sizes.
	var left := roundf(hit.position.x - width * 0.5)
	var back := roundf(hit.position.z - depth * 0.5)
	var center_x := left + width * 0.5
	var center_z := back + depth * 0.5

	var lowest := INF
	var highest := -INF
	for corner: Vector2 in [
		Vector2(left, back), Vector2(left + width, back),
		Vector2(left, back + depth), Vector2(left + width, back + depth),
		Vector2(center_x, center_z),
	]:
		var ground := world.get_ground_height(corner.x, corner.y)
		lowest = minf(lowest, ground)
		highest = maxf(highest, ground)

	_ghost.position = Vector3(center_x, highest, center_z)

	var rect := Rect2(left, back, width, depth)
	var chunk_size := float(world.config.chunk_size)
	var in_bounds := left >= 0.0 and back >= 0.0 \
		and left + width <= chunk_size and back + depth <= chunk_size
	var flat_enough := (highest - lowest) <= MAX_HEIGHT_SPREAD
	var overlaps := false
	for placed in _placed_rects:
		if placed.intersects(rect):
			overlaps = true
			break

	_valid = in_bounds and flat_enough and not overlaps
	_ghost.set_ghost(_valid)


func _place() -> void:
	var building := PlaceholderBuildingScript.new()
	building.setup(_entry)
	buildings_root.add_child(building)
	building.position = _ghost.position

	var footprint: Array = _entry.get("footprint", [3, 3])
	var width := float(footprint[0])
	var depth := float(footprint[1])
	_placed_rects.append(Rect2(_ghost.position.x - width * 0.5, _ghost.position.z - depth * 0.5, width, depth))

	var entry := _entry
	var position := _ghost.position
	_ghost.queue_free()
	_ghost = null
	_entry = {}
	building_placed.emit(entry, position)


func _raycast_ground(screen_position: Vector2) -> Dictionary:
	var from := camera.project_ray_origin(screen_position)
	var to := from + camera.project_ray_normal(screen_position) * RAY_LENGTH
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = GROUND_MASK
	return camera.get_world_3d().direct_space_state.intersect_ray(params)
