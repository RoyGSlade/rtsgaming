class_name BuildingPreview
extends SubViewportContainer

## Small 3D preview panel in the HUD: renders the selected catalog entry's
## placeholder building in its own SubViewport world and slowly spins it.
## Swaps to the real blueprint mesh once the building editor produces them.

const PlaceholderBuildingScript := preload("res://scripts/buildings/placeholder_building.gd")

const SPIN_SPEED := 0.6

var _viewport: SubViewport
var _holder: Node3D
var _camera: Camera3D


func _ready() -> void:
	stretch = true
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
	_viewport.add_child(light)

	_camera = Camera3D.new()
	_camera.current = true
	_viewport.add_child(_camera)

	_holder = Node3D.new()
	_viewport.add_child(_holder)


func _process(delta: float) -> void:
	if _holder != null and _holder.get_child_count() > 0:
		_holder.rotate_y(delta * SPIN_SPEED)


func show_entry(entry: Dictionary) -> void:
	clear()
	if entry.is_empty():
		return
	var building := PlaceholderBuildingScript.new()
	building.setup(entry)
	_holder.add_child(building)

	var footprint: Array = entry.get("footprint", [3, 3])
	var height := float(entry.get("height", 3))
	var radius := maxf(maxf(float(footprint[0]), float(footprint[1])), height)
	_camera.position = Vector3(0.0, height * 0.6 + radius * 0.5, radius * 2.1)
	_camera.look_at(Vector3(0.0, height * 0.45, 0.0))


func clear() -> void:
	for child in _holder.get_children():
		child.queue_free()
