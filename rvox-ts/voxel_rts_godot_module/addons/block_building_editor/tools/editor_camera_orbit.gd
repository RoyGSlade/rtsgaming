@tool
class_name EditorCameraOrbit
extends Node3D

@export var orbit_target: Node3D
@export var camera: Camera3D
@export var distance: float = 18.0
@export var min_distance: float = 4.0
@export var max_distance: float = 80.0
@export var yaw: float = 45.0
@export var pitch: float = -35.0
@export var orbit_speed: float = 0.25
@export var zoom_speed: float = 1.5

func set_view_angle(p_yaw: float, p_pitch: float, p_distance: float = distance) -> void:
    yaw = p_yaw
    pitch = clampf(p_pitch, -85.0, -5.0)
    distance = clampf(p_distance, min_distance, max_distance)
    _apply_camera_transform()

func rotate_view(delta_yaw: float, delta_pitch: float) -> void:
    yaw += delta_yaw * orbit_speed
    pitch = clampf(pitch + delta_pitch * orbit_speed, -85.0, -5.0)
    _apply_camera_transform()

func zoom(delta: float) -> void:
    distance = clampf(distance + delta * zoom_speed, min_distance, max_distance)
    _apply_camera_transform()

func _apply_camera_transform() -> void:
    if camera == null:
        return
    var target_pos := Vector3.ZERO
    if orbit_target:
        target_pos = orbit_target.global_position
    var rot := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
    camera.global_position = target_pos + rot * Vector3(0.0, 0.0, distance)
    camera.look_at(target_pos, Vector3.UP)
