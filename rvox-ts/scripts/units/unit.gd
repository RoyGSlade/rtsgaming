class_name Unit
extends Node3D

## A single commandable worker. Moves horizontally toward a move order at
## move_speed, staying glued to the terrain surface via a ground sampler
## the world supplies. Kept deliberately simple (straight-line, no
## pathfinding/avoidance yet) - this is the first playable unit, the seed
## the rest of the RTS loop (construction, hauling) hangs off of.
##
## Builds its own visual body and a pick Area3D in _ready() so GameMain can
## spawn one in code without a separate scene file. Movement math lives in
## the static step_toward() so it can be unit-tested without a running scene.

const ARRIVE_EPSILON := 0.05
## Scene group all player units join, so creatures (flee/aggro scans) can
## find them without holding references.
const GROUP := "player_units"
# Units sit on their own physics layer (2) so the command controller can
# raycast for "did I click a unit" separately from "did I click the ground"
# (terrain collision is layer 1).
const PICK_LAYER := 2
const BODY_HEIGHT := 1.6
const BODY_RADIUS := 0.35
# The modeled worker from the Blender -> glTF asset pipeline
# (assets/blender/worker.blend, exported to this .glb). If it hasn't been
# imported by the Godot editor yet, the unit falls back to a capsule so the
# game still runs - the visual is cosmetic, the pick area/movement are not.
const WORKER_MODEL_PATH := "res://assets/models/worker.glb"

## Model + clip config, data-driven so one Unit script drives every rig. The
## worker and soldier ship different clip names, so which clips exist and what
## the idle/walk/run states play is configured per unit (see GameMain spawns).
@export_file("*.glb") var model_path: String = WORKER_MODEL_PATH
@export var idle_clip := "Idle"
@export var walk_clip := "Walk"
@export var run_clip := "Running"
## Clips looped when played (idle + locomotion + any held poses). Names the
## model doesn't have are skipped at load; one-shot clips (attacks, deaths)
## are deliberately left out so they don't loop.
@export var loop_clips: PackedStringArray = ["Idle", "Walk", "Running", "Digging", "Carrying"]
## Item props mounted on skeleton bones via BoneAttachment3D so they follow the
## hands through every clip. Each entry: {"scene": glb path, "bone": bone name,
## "position": Vector3, "rotation_deg": Vector3, "scale": float}. Empty = unarmed.
@export var attachments: Array = []

## Stationary pose held when not travelling. The worker's gather/build/haul
## loop sets DIG/CARRY; rigs without those clips fall back to their idle clip.
enum Stance { IDLE, DIG, CARRY }

@export var move_speed := 6.0
@export var turn_speed := 9.0
# Yaw offset so the model's front faces its travel direction. Mixamo glTF
# characters import facing +Z, while facing math below aligns +Z to travel,
# so 0 is correct for them; flip to PI if a model faces backward.
@export var facing_offset := 0.0
## Play the faster run clip instead of walk while travelling.
@export var run := false:
	set(value):
		run = value
		_refresh_anim()
@export var selected := false:
	set(value):
		selected = value
		if _selection_ring != null:
			_selection_ring.visible = value

## Set by GameMain to WorldRuntime.get_ground_height so the unit rides the
## terrain. Takes (world_x, world_z) and returns the surface Y. If unset
## (e.g. in a pure logic test) the unit keeps whatever Y it was given.
var ground_sampler: Callable = Callable()

var _has_target := false
var _target := Vector3.ZERO
var _stance: int = Stance.IDLE
var _selection_ring: MeshInstance3D
# AnimationPlayer from the imported worker.glb (null when using the capsule
# fallback, or if the model has no animations).
var _anim_player: AnimationPlayer


func _ready() -> void:
	add_to_group(GROUP)
	_build_body()
	_snap_to_ground()


## Issue a move order to a world position (Y is resolved from the ground).
func move_to(world_position: Vector3) -> void:
	_target = world_position
	_has_target = true
	_refresh_anim()


func is_moving() -> bool:
	return _has_target


func _physics_process(delta: float) -> void:
	if not _has_target:
		return
	var flat_dir := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	var result := step_toward(global_position, _target, move_speed, delta)
	global_position = _grounded(result.position)
	if flat_dir.length() > 0.05:
		_face_direction(flat_dir, delta)
	if result.arrived:
		_has_target = false
		_refresh_anim()


## Smoothly turn the unit so its front points along its travel direction.
func _face_direction(flat_dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(flat_dir.x, flat_dir.z) + facing_offset
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * turn_speed))


## Pure movement step, horizontally (XZ) only - Y is resolved separately by
## the ground sampler so terrain height never interferes with the "have I
## arrived" test. Returns the new position and whether the target is reached.
static func step_toward(from: Vector3, target: Vector3, speed: float, delta: float) -> Dictionary:
	var from_flat := Vector3(from.x, 0.0, from.z)
	var target_flat := Vector3(target.x, 0.0, target.z)
	var to_target := target_flat - from_flat
	var distance := to_target.length()
	var step := speed * delta
	if distance <= step or distance <= ARRIVE_EPSILON:
		return {"position": Vector3(target.x, from.y, target.z), "arrived": true}
	var next := from_flat + to_target / distance * step
	return {"position": Vector3(next.x, from.y, next.z), "arrived": false}


## Set the stationary pose (idle / digging / carrying). While the unit is
## travelling a locomotion clip takes over; the stance is restored on arrival.
func set_stance(stance: int) -> void:
	_stance = stance
	_refresh_anim()


## Play whichever clip matches the current movement + stance. Travelling plays
## the run or walk clip; standing plays the stance clip.
func _refresh_anim() -> void:
	if _has_target:
		_play_clip(run_clip if run else walk_clip)
	else:
		_play_clip(_stance_clip())


## Clip name for the current stance. DIG/CARRY are worker clips; any rig
## without them (e.g. the soldier) falls through to its idle clip.
func _stance_clip() -> String:
	match _stance:
		Stance.DIG:
			return "Digging"
		Stance.CARRY:
			return "Carrying"
		_:
			return idle_clip


func _play_clip(name: String) -> void:
	if _anim_player != null and _anim_player.has_animation(name) and _anim_player.current_animation != name:
		_anim_player.play(name)


func _grounded(position: Vector3) -> Vector3:
	if ground_sampler.is_valid():
		position.y = ground_sampler.call(position.x, position.z)
	return position


func _snap_to_ground() -> void:
	global_position = _grounded(global_position)


func _build_body() -> void:
	_build_visual()

	var area := Area3D.new()
	area.collision_layer = PICK_LAYER
	area.collision_mask = 0
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.radius = BODY_RADIUS
	capsule_shape.height = BODY_HEIGHT
	shape.shape = capsule_shape
	shape.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	area.add_child(shape)
	add_child(area)

	_selection_ring = _build_selection_ring()
	_selection_ring.visible = selected
	add_child(_selection_ring)


## The modeled worker if the glTF has been imported, otherwise a capsule
## placeholder. The model's origin is authored at the feet (in Blender), so
## it drops onto the unit origin with no offset.
func _build_visual() -> void:
	if ResourceLoader.exists(model_path):
		var scene := load(model_path) as PackedScene
		if scene != null:
			var model := scene.instantiate()
			add_child(model)
			_anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if _anim_player != null:
				# glTF import doesn't mark clips looping; loop the ones that cycle.
				for clip in loop_clips:
					if _anim_player.has_animation(clip):
						_anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				_refresh_anim()
			_mount_attachments(model)
			return
	# Fallback placeholder - feet at the unit origin.
	var mesh_instance := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = BODY_RADIUS
	capsule.height = BODY_HEIGHT
	mesh_instance.mesh = capsule
	mesh_instance.position = Vector3(0, BODY_HEIGHT * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.90, 0.78, 0.35)
	mesh_instance.material_override = material
	add_child(mesh_instance)


## Mount configured item props (sword, shield, ...) on the model's skeleton
## bones via BoneAttachment3D, so they ride the hands through every clip.
## Entries whose glb or bone is missing are skipped so an unarmed rig is safe.
func _mount_attachments(model: Node) -> void:
	if attachments.is_empty():
		return
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	for a in attachments:
		var scene_path: String = a.get("scene", "")
		var bone_idx := _resolve_bone(skeleton, a.get("bone", ""))
		if not ResourceLoader.exists(scene_path) or bone_idx == -1:
			continue
		var attach := BoneAttachment3D.new()
		attach.bone_name = skeleton.get_bone_name(bone_idx)
		skeleton.add_child(attach)
		var item := (load(scene_path) as PackedScene).instantiate() as Node3D
		attach.add_child(item)
		item.position = a.get("position", Vector3.ZERO)
		item.rotation_degrees = a.get("rotation_deg", Vector3.ZERO)
		var item_scale: float = a.get("scale", 1.0)
		item.scale = Vector3(item_scale, item_scale, item_scale)


## Resolve a glTF bone name to a skeleton index, tolerant of Godot's import
## sanitization (":" is illegal in node names so "mixamorig:RightHand" may land
## as "mixamorig_RightHand"). Falls back to a separator-insensitive match.
func _resolve_bone(skeleton: Skeleton3D, wanted: String) -> int:
	var idx := skeleton.find_bone(wanted)
	if idx != -1:
		return idx
	idx = skeleton.find_bone(wanted.replace(":", "_"))
	if idx != -1:
		return idx
	var target := wanted.replace(":", "").replace("_", "")
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).replace(":", "").replace("_", "") == target:
			return i
	return -1


func _build_selection_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = BODY_RADIUS + 0.15
	torus.outer_radius = BODY_RADIUS + 0.30
	ring.mesh = torus
	ring.position = Vector3(0, 0.05, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.95, 0.45)
	material.emission_enabled = true
	material.emission = Color(0.30, 0.95, 0.45)
	material.emission_energy_multiplier = 0.6
	ring.material_override = material
	return ring
