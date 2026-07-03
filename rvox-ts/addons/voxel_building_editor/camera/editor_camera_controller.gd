class_name EditorCameraController
extends Node3D

@export var pan_speed := 12.0
@export var orbit_sensitivity := 0.008
@export var zoom_step := 1.5
@export var min_zoom := 5.0
@export var max_zoom := 35.0

@onready var camera: Camera3D = $Camera3D

var _orbiting := false
var _pitch := -0.75
var _yaw := -0.75
var _zoom := 18.0


func _ready() -> void:
	_apply_camera_transform()


func _process(delta: float) -> void:
	var input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	if input.is_zero_approx():
		return
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	global_position += (right * input.x + forward * -input.y) * pan_speed * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(min_zoom, _zoom - zoom_step)
			_apply_camera_transform()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(max_zoom, _zoom + zoom_step)
			_apply_camera_transform()
	elif event is InputEventMouseMotion and _orbiting:
		_yaw -= event.relative.x * orbit_sensitivity
		_pitch = clampf(_pitch - event.relative.y * orbit_sensitivity, -1.45, -0.2)
		_apply_camera_transform()
		get_viewport().set_input_as_handled()


func _apply_camera_transform() -> void:
	rotation = Vector3(0.0, _yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, _zoom)
	camera.rotation = Vector3(_pitch, 0.0, 0.0)
