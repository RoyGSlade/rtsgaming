class_name GameMain
extends Node3D

@onready var world: WorldRuntime = $World
@onready var camera_rig: RtsCameraController = $CameraRig
@onready var status_label: Label = $HUD/Root/Margin/Layout/Status
@onready var minimap: TextureRect = $HUD/Root/Minimap
@onready var sun_moon_rig: SunMoonRig = $SunMoonRig
@onready var rain_controller: RainController = $RainController
@onready var time_dial: TimeDial = $HUD/Root/TimeDial

const FOG_REVEAL_RADIUS := 22.0
const RAIN_SUN_DIM := 0.55

var _minimap_generator := MinimapGenerator.new()
var _environment_controller := EnvironmentController.new()
var _command_controller: RtsCommandController
var _worker: Unit
var _soldier: Unit

## Where the demo soldier stands relative to the worker (world center).
const SOLDIER_SPAWN_OFFSET := Vector3(4.0, 0.0, 0.0)


func _ready() -> void:
	_environment_controller.setup($WorldEnvironment)
	time_dial.sun_moon_rig = sun_moon_rig
	world.world_generated.connect(_on_world_generated)
	$HUD/Root/Margin/Layout/Regenerate.pressed.connect(_regenerate_world)
	$HUD/Root/Margin/Layout/ToggleRain.pressed.connect(_toggle_rain)
	rain_controller.rain_intensity_changed.connect(_on_rain_intensity_changed)
	minimap.gui_input.connect(_on_minimap_gui_input)
	_setup_units()
	if world.current_chunk != null:
		_on_world_generated(world.get_summary())
	call_deferred("_focus_camera")


func _setup_units() -> void:
	_command_controller = RtsCommandController.new()
	_command_controller.camera = camera_rig.camera
	_command_controller.world = world
	add_child(_command_controller)
	_spawn_worker(world.get_world_center())
	_spawn_soldier(world.get_world_center() + SOLDIER_SPAWN_OFFSET)


## Places the single starter worker at a world position (X/Z used; Y comes
## from the terrain). Reused on regenerate to re-seat it on the new terrain.
func _spawn_worker(world_position: Vector3) -> void:
	if _worker == null:
		_worker = Unit.new()
		_worker.ground_sampler = world.get_ground_height
		add_child(_worker)
	_worker.global_position = Vector3(world_position.x, 0.0, world_position.z)
	_worker.global_position.y = world.get_ground_height(world_position.x, world_position.z)


## Places the demo sword-and-shield soldier. Selectable/movable like the worker
## (idle when standing, walk/run when ordered) — a preview of the Mixamo
## Sword & Shield pack; the other 45 clips ship in soldier.glb for later use.
func _spawn_soldier(world_position: Vector3) -> void:
	if _soldier == null:
		_soldier = Unit.new()
		_soldier.model_path = "res://assets/models/soldier.glb"
		_soldier.idle_clip = "Idle"
		_soldier.walk_clip = "Walk"
		_soldier.run_clip = "Run"
		_soldier.loop_clips = PackedStringArray(["Idle", "Walk", "Run", "BlockIdle"])
		# Sword in the right hand, shield on the left forearm. Offsets tuned in
		# scenes/dev/unit_preview.tscn — the bone axes seat both cleanly at zero.
		_soldier.attachments = [
			{"scene": "res://assets/models/items/sword.glb", "bone": "mixamorig:RightHand",
			 "position": Vector3.ZERO, "rotation_deg": Vector3.ZERO, "scale": 1.0},
			{"scene": "res://assets/models/items/shield.glb", "bone": "mixamorig:LeftForeArm",
			 "position": Vector3(0.0, 0.16, -0.10), "rotation_deg": Vector3(-90.0, 0.0, 0.0), "scale": 1.0},
		]
		_soldier.ground_sampler = world.get_ground_height
		add_child(_soldier)
	_soldier.global_position = Vector3(world_position.x, 0.0, world_position.z)
	_soldier.global_position.y = world.get_ground_height(world_position.x, world_position.z)


func _process(_delta: float) -> void:
	_environment_controller.set_palette(sun_moon_rig)
	WaterMaterialResolver.set_lighting(world.get_water_material(), sun_moon_rig)

	var fog := world.get_fog_of_war()
	if fog == null:
		return
	var revealed := fog.reveal(camera_rig.global_position.x, camera_rig.global_position.z, FOG_REVEAL_RADIUS)
	if revealed:
		world.refresh_fog_of_war()
		_refresh_minimap()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_regenerate_world()


func _focus_camera() -> void:
	camera_rig.focus(world.get_world_center())


## Left-click on the minimap jumps the camera rig's ground position to the
## clicked cell, keeping its current yaw/pitch/zoom and pivot height so only
## the horizontal focus point moves.
func _on_minimap_gui_input(event: InputEvent) -> void:
	if world.current_chunk == null:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var uv := (mouse_event.position / minimap.size).clamp(Vector2.ZERO, Vector2.ONE)
	var chunk_size := world.config.chunk_size
	var world_x := uv.x * chunk_size
	var world_z := uv.y * chunk_size
	camera_rig.focus(Vector3(world_x, camera_rig.global_position.y, world_z))


func _regenerate_world() -> void:
	world.regenerate_with_seed(world.config.world_seed + 1)
	_focus_camera()
	# New terrain heights - drop the worker back onto the fresh surface at
	# the world center so it isn't left floating or buried.
	if _worker != null:
		_spawn_worker(world.get_world_center())
	if _soldier != null:
		_spawn_soldier(world.get_world_center() + SOLDIER_SPAWN_OFFSET)


func _toggle_rain() -> void:
	rain_controller.rain_intensity = 0.0 if rain_controller.rain_intensity > 0.01 else 1.0


func _on_rain_intensity_changed(intensity: float) -> void:
	_environment_controller.set_rain_intensity(intensity)
	sun_moon_rig.weather_energy_multiplier = lerpf(1.0, RAIN_SUN_DIM, intensity)
	WaterMaterialResolver.set_rain_intensity(world.get_water_material(), intensity)


func _on_world_generated(summary: Dictionary) -> void:
	status_label.text = "Seed %d · %dx%d chunk · height %d–%d\n%d water cells · %d tree blocks · %d ore blocks" % [
		int(summary.seed),
		int(summary.chunk_size),
		int(summary.chunk_size),
		int(summary.minimum_height),
		int(summary.maximum_height),
		int(summary.water_cells),
		int(summary.tree_blocks),
		int(summary.ore_blocks),
	]
	_refresh_minimap()


## Rebuilds the minimap texture from the current chunk's surface colors,
## darkened by the fog-of-war explored mask (unexplored cells render black).
func _refresh_minimap() -> void:
	if minimap == null or world.current_chunk == null:
		return
	var base_image := _minimap_generator.build_image(world.current_chunk, world.get_block_registry())
	var fog := world.get_fog_of_war()
	if fog != null:
		var fog_image := fog.get_image()
		for x in base_image.get_width():
			for z in base_image.get_height():
				if fog_image.get_pixel(x, z).r <= 0.5:
					base_image.set_pixel(x, z, Color.BLACK)
	minimap.texture = ImageTexture.create_from_image(base_image)
