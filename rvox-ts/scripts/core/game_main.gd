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


func _ready() -> void:
	_environment_controller.setup($WorldEnvironment)
	time_dial.sun_moon_rig = sun_moon_rig
	world.world_generated.connect(_on_world_generated)
	$HUD/Root/Margin/Layout/Regenerate.pressed.connect(_regenerate_world)
	$HUD/Root/Margin/Layout/ToggleRain.pressed.connect(_toggle_rain)
	rain_controller.rain_intensity_changed.connect(_on_rain_intensity_changed)
	if world.current_chunk != null:
		_on_world_generated(world.get_summary())
	call_deferred("_focus_camera")


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


func _regenerate_world() -> void:
	world.regenerate_with_seed(world.config.world_seed + 1)
	_focus_camera()


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
