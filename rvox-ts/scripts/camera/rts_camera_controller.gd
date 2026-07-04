class_name RtsCameraController
extends Node3D

@export var pan_speed := 32.0
@export var rotate_speed := 1.5
@export var tilt_speed := 1.0
@export var orbit_sensitivity := 0.008
@export var zoom_step := 4.0
@export var min_zoom := 8.0
@export var max_zoom := 240.0

@onready var camera: Camera3D = $Camera3D

var _orbiting := false
var _yaw := -0.75
var _pitch := 0.68
var _zoom := 34.0


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
