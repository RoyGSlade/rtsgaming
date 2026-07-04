class_name RtsCameraController
extends Node3D

@export var pan_speed := 32.0
@export var rotate_speed := 1.5
@export var tilt_speed := 1.0
@export var orbit_sensitivity := 0.008
@export var zoom_step := 4.0
@export var min_zoom := 8.0
@export var max_zoom := 240.0

## Touch feel. Pan scales with zoom so the world tracks the finger at any
## distance; pinch/twist convert raw pixel/angle deltas into zoom/yaw.
@export var touch_pan_sensitivity := 0.0016
@export var touch_pinch_sensitivity := 0.12
@export var touch_twist_sensitivity := 1.0

@onready var camera: Camera3D = $Camera3D

var _orbiting := false
var _yaw := -0.75
var _pitch := 0.68
var _zoom := 34.0

# Live touch state: index -> last screen position. Two or more fingers is a
# pinch/twist gesture; _multi_touch stays true until every finger lifts so a
# trailing tap-release during a two-finger gesture can be ignored downstream.
var _touches: Dictionary = {}
var _multi_touch := false
var _pinch_distance := 0.0
var _twist_angle := 0.0


func _ready() -> void:
	_apply_camera_transform()


func focus(world_position: Vector3) -> void:
	global_position = world_position


func _process(delta: float) -> void:
	var move := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if not move.is_zero_approx():
		var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		global_position += (right * move.x + forward * -move.y) * pan_speed * delta

	var turn := float(Input.is_key_pressed(KEY_Q)) - float(Input.is_key_pressed(KEY_E))
	if turn != 0.0:
		if Input.is_key_pressed(KEY_CTRL):
			# Ctrl+Q tilts down (steeper, more top-down); Ctrl+E tilts up
			# (levels the view toward the horizon).
			_pitch = clampf(_pitch + turn * tilt_speed * delta, 0.18, 1.45)
		else:
			# Q rotates left (yaw increases), E rotates right (yaw decreases) -
			# matches the mouse-drag-right -> yaw-decreases convention below.
			_yaw += turn * rotate_speed * delta
		_apply_camera_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(min_zoom, _zoom - zoom_step)
			_apply_camera_transform()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(max_zoom, _zoom + zoom_step)
			_apply_camera_transform()
	elif event is InputEventMouseMotion and _orbiting:
		_yaw -= event.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch + event.relative.y * orbit_sensitivity, 0.18, 1.45)
		_apply_camera_transform()
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


## True while the player is mid two-finger gesture (pinch/twist). The command
## controller queries this so the first finger's emulated mouse-click doesn't
## also fire a unit command while the camera is being manipulated.
func is_gesture_active() -> bool:
	return _multi_touch


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	if _touches.size() >= 2:
		_multi_touch = true
		_reset_gesture_baseline()
	elif _touches.is_empty():
		_multi_touch = false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() >= 2:
		_apply_pinch_twist()
	elif _touches.size() == 1 and not _multi_touch:
		_pan_touch(event.relative)


## Grab-the-world pan: dragging one finger slides the map under it, faster the
## farther the camera is zoomed out.
func _pan_touch(screen_delta: Vector2) -> void:
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var scale := _zoom * touch_pan_sensitivity
	global_position += (-right * screen_delta.x + forward * screen_delta.y) * scale


func _apply_pinch_twist() -> void:
	var pts := _two_touch_positions()
	var distance: float = pts[0].distance_to(pts[1])
	var angle: float = (pts[1] - pts[0]).angle()
	# Fingers spreading apart (distance grows) zooms in (_zoom decreases).
	_zoom = clampf(_zoom + (_pinch_distance - distance) * touch_pinch_sensitivity, min_zoom, max_zoom)
	_yaw += angle_delta(_twist_angle, angle) * touch_twist_sensitivity
	_pinch_distance = distance
	_twist_angle = angle
	_apply_camera_transform()


## Re-seat the pinch/twist reference from the current two fingers so gaining or
## losing the second finger never causes a zoom/rotation jump.
func _reset_gesture_baseline() -> void:
	var pts := _two_touch_positions()
	_pinch_distance = pts[0].distance_to(pts[1])
	_twist_angle = (pts[1] - pts[0]).angle()


func _two_touch_positions() -> Array:
	var indices := _touches.keys()
	indices.sort()
	return [_touches[indices[0]], _touches[indices[1]]]


## Shortest signed delta between two angles, wrapped to [-PI, PI] so a twist
## across the ±PI seam doesn't spin the camera the long way around.
static func angle_delta(from: float, to: float) -> float:
	return wrapf(to - from, -PI, PI)


func _apply_camera_transform() -> void:
	var horizontal_distance := cos(_pitch) * _zoom
	camera.position = Vector3(
		sin(_yaw) * horizontal_distance,
		sin(_pitch) * _zoom,
		cos(_yaw) * horizontal_distance
	)
	# look_at() takes a global-space target. The rig's own origin (its
	# global_position) is the focus point the camera orbits, not world
	# (0,0,0) - using Vector3.ZERO here made the camera aim at the world
	# origin instead of the panned focus point, skewing framing and
	# WASD/zoom feel more the farther the rig moved from world origin.
	camera.look_at(global_position, Vector3.UP)
