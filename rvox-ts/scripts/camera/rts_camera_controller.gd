class_name RtsCameraController
extends Node3D

@export var pan_speed := 32.0
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
	var input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if input.is_zero_approx():
		return
	var forward := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	global_position += (right * input.x + forward * -input.y) * pan_speed * delta


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
	camera.look_at(Vector3.ZERO, Vector3.UP)
