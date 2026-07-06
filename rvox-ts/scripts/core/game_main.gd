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
# Preloaded rather than referenced by class_name so a fresh checkout runs
# before the editor has rescanned and registered the new global class.
const DynamicResolutionControllerScript := preload("res://scripts/rendering/dynamic_resolution_controller.gd")
const RtsHudScript := preload("res://scripts/ui/rts_hud.gd")
const BuildingPlacementControllerScript := preload("res://scripts/buildings/building_placement_controller.gd")

var _minimap_generator := MinimapGenerator.new()
# Cached minimap state: _minimap_base_image holds the unmasked terrain
# colors (built once per world generation - O(map area), same cost the old
# per-frame rebuild paid every single frame the fog reveal touched a new
# cell). _minimap_display_image is what's actually shown, starting all
# black and having individual cells copied in from the base image as fog
# reveals them, so a panning camera costs O(newly revealed cells) per
# frame instead of O(map area).
var _minimap_base_image: Image
var _minimap_display_image: Image
var _minimap_texture: ImageTexture
var _environment_controller := EnvironmentController.new()
var _command_controller: RtsCommandController
var _worker: Unit
var _soldier: Unit
## Wildlife/monster actors spawned near world center as a first pass at
## Sketchfab-sourced wandering creatures - see docs/ASSET_CREDITS.md for
## sourcing. Re-seated on regenerate like the starter units.
var _creatures: Array[Creature] = []
# Typed via the preload consts (not class_name) for the same fresh-checkout
# reason as DynamicResolutionControllerScript above.
var _rts_hud: RtsHudScript
var _placement_controller: BuildingPlacementControllerScript
var _buildings_root: Node3D
## Units spawned from the HUD's Units tab, re-seated on regenerate like the
## two starter units.
var _trained_units: Array[Unit] = []

## Where the demo soldier stands relative to the worker (world center).
const SOLDIER_SPAWN_OFFSET := Vector3(4.0, 0.0, 0.0)

## Wildlife/monster spawns near world center. Wild critters (deer, rabbit)
## are SKITTISH - they graze and bolt from approaching units; the monsters
## are HOSTILE - they chase units in aggro range and swing (animation-only:
## units have no health yet, Creature._strike is the damage hook). The
## facing_offset of PI is shared by every directional rig here - all four
## are authored facing -Z (verified via scenes/dev/creature_preview.tscn);
## the slime is radially symmetric so its offset is moot. Monsters spawn a
## bit farther out than the critters so the starter units aren't instantly
## swarmed.
const CREATURE_SPAWNS := [
	{"model": "res://assets/models/deer.glb", "offset": Vector3(-8.0, 0.0, -8.0),
	 "archetype": Creature.Archetype.SKITTISH, "radius": 7.0, "facing": PI,
	 "move_speed": 1.5, "run_speed": 5.0,
	 "loop_clips": ["Idle", "Idle2", "Walk", "Running"]},
	{"model": "res://assets/models/rabbit.glb", "offset": Vector3(-4.0, 0.0, -10.0),
	 "archetype": Creature.Archetype.SKITTISH, "radius": 4.0, "facing": PI,
	 "move_speed": 1.2, "run_speed": 3.5,
	 "loop_clips": ["Idle", "Walk", "Eat", "LookAround"]},
	{"model": "res://assets/models/evilwolf.glb", "offset": Vector3(14.0, 0.0, -9.0),
	 "archetype": Creature.Archetype.HOSTILE, "radius": 6.0, "facing": PI,
	 "move_speed": 1.8, "run_speed": 4.5, "run_clip": "Walk2", "attack_range": 1.3,
	 "loop_clips": ["Idle", "Walk", "Walk2"]},
	{"model": "res://assets/models/zombie.glb", "offset": Vector3(15.0, 0.0, 6.0),
	 "archetype": Creature.Archetype.HOSTILE, "radius": 5.0, "facing": PI,
	 "move_speed": 1.2, "run_speed": 4.0, "attack_range": 1.6,
	 "loop_clips": ["Idle", "Walk", "Running"]},
	{"model": "res://assets/models/slime.glb", "offset": Vector3(-13.0, 0.0, 5.0),
	 "archetype": Creature.Archetype.HOSTILE, "radius": 4.0, "facing": 0.0,
	 "move_speed": 1.5, "run_speed": 2.5, "attack_range": 1.0,
	 "loop_clips": ["Idle", "Walk"]},
]


func _ready() -> void:
	_environment_controller.setup($WorldEnvironment)
	time_dial.sun_moon_rig = sun_moon_rig
	world.world_generated.connect(_on_world_generated)
	$HUD/Root/Margin/Layout/Regenerate.pressed.connect(_regenerate_world)
	$HUD/Root/Margin/Layout/ToggleRain.pressed.connect(_toggle_rain)
	rain_controller.rain_intensity_changed.connect(_on_rain_intensity_changed)
	minimap.gui_input.connect(_on_minimap_gui_input)
	_setup_display()
	_setup_units()
	_setup_creatures()
	_setup_rts_ui()
	if world.current_chunk != null:
		_on_world_generated(world.get_summary())
	call_deferred("_focus_camera")


func _setup_units() -> void:
	_command_controller = RtsCommandController.new()
	_command_controller.camera = camera_rig.camera
	_command_controller.world = world
	_command_controller.camera_rig = camera_rig
	_command_controller.touch_enabled = DisplayServer.is_touchscreen_available()
	add_child(_command_controller)
	_spawn_worker(world.get_world_center())
	_spawn_soldier(world.get_world_center() + SOLDIER_SPAWN_OFFSET)


## Adaptive render-scale controller (holds framerate on weak GPUs) plus, on
## touchscreen devices, a controls hint describing the gesture scheme instead
## of the keyboard/mouse one.
func _setup_display() -> void:
	var dynamic_resolution := DynamicResolutionControllerScript.new()
	dynamic_resolution.status_label = $HUD/Root/Margin/Layout/QualityStatus
	add_child(dynamic_resolution)
	if DisplayServer.is_touchscreen_available():
		$HUD/Root/Margin/Layout/Controls.text = "1-finger drag pan · pinch zoom · twist rotate · tap select/move"


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
		_apply_soldier_loadout(_soldier)
		_soldier.ground_sampler = world.get_ground_height
		add_child(_soldier)
	_soldier.global_position = Vector3(world_position.x, 0.0, world_position.z)
	_soldier.global_position.y = world.get_ground_height(world_position.x, world_position.z)


## Sword in the right hand, shield on the left forearm. Offsets tuned in
## scenes/dev/unit_preview.tscn — the bone axes seat both cleanly at zero.
## Shared by the starter soldier and soldiers trained from the HUD.
func _apply_soldier_loadout(unit: Unit) -> void:
	unit.model_path = "res://assets/models/soldier.glb"
	unit.idle_clip = "Idle"
	unit.walk_clip = "Walk"
	unit.run_clip = "Run"
	unit.loop_clips = PackedStringArray(["Idle", "Walk", "Run", "BlockIdle"])
	unit.attachments = [
		{"scene": "res://assets/models/items/sword.glb", "bone": "mixamorig:RightHand",
		 "position": Vector3.ZERO, "rotation_deg": Vector3.ZERO, "scale": 1.0},
		{"scene": "res://assets/models/items/shield.glb", "bone": "mixamorig:LeftForeArm",
		 "position": Vector3(0.0, 0.16, -0.10), "rotation_deg": Vector3(-90.0, 0.0, 0.0), "scale": 1.0},
	]


## Spawns the CREATURE_SPAWNS list once, near world center. Re-seating on
## regenerate is handled by _regenerate_world snapping global_position.y like
## the trained units and buildings.
func _setup_creatures() -> void:
	var center := world.get_world_center()
	for spawn in CREATURE_SPAWNS:
		var creature := Creature.new()
		creature.model_path = spawn.model
		creature.archetype = spawn.archetype
		creature.wander_radius = spawn.radius
		creature.facing_offset = spawn.facing
		creature.move_speed = spawn.move_speed
		creature.run_speed = spawn.run_speed
		creature.loop_clips = PackedStringArray(spawn.loop_clips)
		creature.run_clip = spawn.get("run_clip", "Running")
		creature.attack_range = spawn.get("attack_range", 1.4)
		creature.ground_sampler = world.get_ground_height
		creature.min_wander_height = float(world.config.water_level)
		add_child(creature)
		var spot: Vector3 = center + spawn.offset
		creature.global_position = Vector3(spot.x, world.get_ground_height(spot.x, spot.z), spot.z)
		_creatures.append(creature)


## Builds the RTS management layer: placed-building container, ghost placement
## controller, and the HUD (resource bar, build/train tabs, MVP overview).
## The HUD owns the placeholder resource stock; costs are deducted when the
## placement controller confirms a site, not when the button is clicked.
func _setup_rts_ui() -> void:
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)

	_placement_controller = BuildingPlacementControllerScript.new()
	_placement_controller.camera = camera_rig.camera
	_placement_controller.world = world
	_placement_controller.buildings_root = _buildings_root
	add_child(_placement_controller)
	_command_controller.placement_controller = _placement_controller

	_rts_hud = RtsHudScript.new()
	_rts_hud.command_controller = _command_controller
	$HUD.add_child(_rts_hud)

	_rts_hud.building_chosen.connect(_placement_controller.begin)
	_placement_controller.building_placed.connect(_rts_hud.on_building_placed)
	_rts_hud.unit_train_requested.connect(_on_unit_train_requested)


## Spawns a unit from the HUD's Units tab near the world center. The HUD has
## already validated and paid the (placeholder) cost.
func _on_unit_train_requested(entry: Dictionary) -> void:
	var unit := Unit.new()
	if String(entry.get("id", "")) == "soldier":
		_apply_soldier_loadout(unit)
	unit.ground_sampler = world.get_ground_height
	add_child(unit)
	_trained_units.append(unit)
	var angle := randf() * TAU
	var spot := world.get_world_center() + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(2.5, 6.0)
	unit.global_position = Vector3(spot.x, world.get_ground_height(spot.x, spot.z), spot.z)


func _process(_delta: float) -> void:
	_environment_controller.set_palette(sun_moon_rig)
	WaterMaterialResolver.set_lighting(world.get_water_material(), sun_moon_rig)

	var fog := world.get_fog_of_war()
	if fog == null:
		return
	var revealed := fog.reveal(camera_rig.global_position.x, camera_rig.global_position.z, FOG_REVEAL_RADIUS)
	if revealed:
		world.refresh_fog_of_war()
		_reveal_minimap_cells(revealed)


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
	for unit in _trained_units:
		unit.global_position.y = world.get_ground_height(unit.global_position.x, unit.global_position.z)
	for creature in _creatures:
		creature.global_position.y = world.get_ground_height(creature.global_position.x, creature.global_position.z)
		creature.min_wander_height = float(world.config.water_level)
	if _buildings_root != null:
		for building in _buildings_root.get_children():
			var node := building as Node3D
			node.position.y = world.get_ground_height(node.position.x, node.position.z)


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


## Full minimap rebuild - O(map area), so this only runs once per world
## generation. Caches the unmasked terrain-color image and starts the
## displayed image all-black (fog is freshly all-unexplored at this point);
## _reveal_minimap_cells then keeps the displayed image in sync per-frame
## without ever repeating this full scan.
func _refresh_minimap() -> void:
	if minimap == null or world.current_chunk == null:
		return
	_minimap_base_image = _minimap_generator.build_image(world.current_chunk, world.get_block_registry())
	_minimap_display_image = Image.create(_minimap_base_image.get_width(), _minimap_base_image.get_height(), false, Image.FORMAT_RGBA8)
	_minimap_display_image.fill(Color.BLACK)
	_minimap_texture = ImageTexture.create_from_image(_minimap_display_image)
	minimap.texture = _minimap_texture


## Copies just the newly fog-revealed cells from the cached base image into
## the displayed image and pushes one texture update - the incremental
## counterpart to _refresh_minimap's full rebuild, called every frame the
## camera reveals new cells (i.e. essentially every frame it's moving).
func _reveal_minimap_cells(cells: Array[Vector2i]) -> void:
	if minimap == null or _minimap_display_image == null:
		return
	for cell in cells:
		_minimap_display_image.set_pixel(cell.x, cell.y, _minimap_base_image.get_pixel(cell.x, cell.y))
	_minimap_texture.update(_minimap_display_image)
