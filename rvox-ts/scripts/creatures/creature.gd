class_name Creature
extends Node3D

## A wildlife/monster actor. Shares Unit's movement math (Unit.step_toward
## is static, so it's reused rather than duplicated) but skips the
## pick-area/selection-ring machinery units need for player commands -
## creatures aren't selectable or orderable.
##
## Behavior is a small state machine driven by an archetype:
##   PASSIVE  - wanders near its spawn, nothing more (ambient life).
##   SKITTISH - wanders, but bolts away from any player unit that gets
##              inside flee_radius, then settles down where it ended up.
##   HOSTILE  - wanders until a unit enters aggro_radius, then chases and
##              plays its attack clip in range. No damage is dealt yet -
##              units have no health; _strike() is the hook for that.
## Threat scanning runs on a timer (THINK_INTERVAL), not per frame, so a
## large population stays cheap.

enum Archetype { PASSIVE, SKITTISH, HOSTILE }
enum State { IDLE, WANDER, FLEE, CHASE, ATTACK }

const IDLE_MIN_SECONDS := 1.5
const IDLE_MAX_SECONDS := 4.0
const WANDER_TARGET_ATTEMPTS := 4
## Seconds between threat scans. Movement itself still updates every
## physics tick; only the "who's near me" group sweep is throttled.
const THINK_INTERVAL := 0.35
## Hysteresis so creatures don't flicker between calm/alert at the radius
## edge: disengage only past radius * this factor.
const DISENGAGE_FACTOR := 1.5

## Model + clip config, same data-driven shape as Unit so any glb/clip
## naming from the asset pipeline drops in without code changes.
@export_file("*.glb") var model_path: String
@export var idle_clip := "Idle"
@export var walk_clip := "Walk"
## Used when fleeing/chasing; rigs without it fall back to walk_clip.
@export var run_clip := "Running"
## One-shot swing played in attack range (HOSTILE only).
@export var attack_clip := "Attack"
@export var loop_clips: PackedStringArray = ["Idle", "Walk", "Running"]

@export var archetype: Archetype = Archetype.PASSIVE
@export var move_speed := 2.0
## Flee/chase speed - fear and hunger are faster than grazing.
@export var run_speed := 4.5
@export var turn_speed := 6.0
## Yaw offset so the model's front faces its travel direction. Sketchfab
## rigs don't share Mixamo's +Z-forward convention, so this is tuned per
## model (see CREATURE_SPAWNS in game_main.gd).
@export var facing_offset := 0.0
@export var wander_radius := 6.0
## SKITTISH: a unit closer than this triggers a bolt away from it.
@export var flee_radius := 5.0
## How far past the threat direction a fleeing creature runs per leg.
@export var flee_distance := 8.0
## HOSTILE: a unit closer than this is chased...
@export var aggro_radius := 9.0
## ...and swung at when inside this range.
@export var attack_range := 1.4
@export var attack_cooldown := 1.4

## Set by the spawner to WorldRuntime.get_ground_height, same contract as Unit.
var ground_sampler: Callable = Callable()
## Move targets sampling below this Y are rejected, e.g. water level, so
## creatures don't wade into lakes (fleeing creatures cornered against
## water accept the last attempt rather than freezing).
var min_wander_height := -INF

var _state: State = State.IDLE
var _wander_center := Vector3.ZERO
# Captured on the first physics tick, NOT in _ready: _ready runs inside the
# spawner's add_child, before the spawner has positioned the creature, so
# capturing there would anchor every creature's wander to the parent origin.
var _wander_center_set := false
var _target := Vector3.ZERO
var _has_target := false
var _idle_timer := 0.0
var _think_timer := randf() * THINK_INTERVAL
var _attack_timer := 0.0
var _threat: Node3D
var _anim_player: AnimationPlayer


func _ready() -> void:
	_build_visual()
	_snap_to_ground()
	_start_idle()


func _physics_process(delta: float) -> void:
	if not _wander_center_set:
		_wander_center = global_position
		_wander_center_set = true

	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_think()

	match _state:
		State.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				_pick_wander_target()
		State.WANDER:
			_step(delta, move_speed)
			if not _has_target:
				_enter_idle()
		State.FLEE:
			_step(delta, run_speed)
			if not _has_target:
				# Bolt leg finished; _think() decides whether to keep
				# running (threat still close) or settle here.
				_wander_center = global_position
				_enter_idle()
		State.CHASE:
			if _threat_gone():
				_enter_idle()
				return
			_target = _threat.global_position
			_has_target = true
			_step(delta, run_speed)
			if global_position.distance_to(_threat.global_position) <= attack_range:
				_enter_attack()
		State.ATTACK:
			if _threat_gone():
				_enter_idle()
				return
			var to_threat := _threat.global_position - global_position
			if to_threat.length() > attack_range * 1.25:
				_enter_chase(_threat)
				return
			_face_direction(Vector3(to_threat.x, 0.0, to_threat.z), delta)
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_attack_timer = attack_cooldown
				_strike()


## Walk toward a world position (Y resolved from the ground). Public so dev
## previews can drive a deterministic walk for facing checks.
func walk_to(world_position: Vector3) -> void:
	_target = world_position
	_has_target = true
	_state = State.WANDER
	_play_clip_or_fallback(walk_clip, walk_clip)


## Per-tick movement toward _target, terrain-glued, facing travel.
func _step(delta: float, speed: float) -> void:
	if not _has_target:
		return
	var flat_dir := Vector3(_target.x - global_position.x, 0.0, _target.z - global_position.z)
	var result := Unit.step_toward(global_position, _target, speed, delta)
	global_position = _grounded(result.position)
	if flat_dir.length() > 0.05:
		_face_direction(flat_dir, delta)
	if result.arrived:
		_has_target = false


## Periodic threat scan - the only place archetype behavior branches.
func _think() -> void:
	match archetype:
		Archetype.PASSIVE:
			return
		Archetype.SKITTISH:
			# Already mid-bolt: keep it, _physics_process handles the leg.
			if _state == State.FLEE and _has_target:
				return
			var threat := _nearest_unit(flee_radius if _state != State.FLEE else flee_radius * DISENGAGE_FACTOR)
			if threat != null:
				_enter_flee(threat)
		Archetype.HOSTILE:
			if _state == State.CHASE or _state == State.ATTACK:
				return
			var prey := _nearest_unit(aggro_radius)
			if prey != null:
				_enter_chase(prey)


## Closest node in the player-unit group within max_distance, or null.
func _nearest_unit(max_distance: float) -> Node3D:
	var best: Node3D = null
	var best_dist := max_distance
	for node in get_tree().get_nodes_in_group(Unit.GROUP):
		var unit := node as Node3D
		if unit == null:
			continue
		var dist := global_position.distance_to(unit.global_position)
		if dist <= best_dist:
			best_dist = dist
			best = unit
	return best


func _enter_idle() -> void:
	_state = State.IDLE
	_threat = null
	_has_target = false
	_play_clip_or_fallback(idle_clip, idle_clip)
	_start_idle()


func _enter_flee(threat: Node3D) -> void:
	_threat = threat
	_state = State.FLEE
	var away := global_position - threat.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
	away = away.normalized()
	# Try the straight-away line first, then swerve up to ±90 deg if it's
	# blocked by water. A cornered creature takes the last try regardless -
	# panicking beats freezing.
	var target := global_position + away * flee_distance
	for attempt in range(WANDER_TARGET_ATTEMPTS):
		var candidate_dir := away.rotated(Vector3.UP, randf_range(-PI * 0.5, PI * 0.5)) if attempt > 0 else away
		var candidate := global_position + candidate_dir * flee_distance
		target = candidate
		if _height_at(candidate) >= min_wander_height:
			break
	_target = target
	_has_target = true
	_play_clip_or_fallback(run_clip, walk_clip)


func _enter_chase(prey: Node3D) -> void:
	_threat = prey
	_state = State.CHASE
	_has_target = true
	_play_clip_or_fallback(run_clip, walk_clip)


func _enter_attack() -> void:
	_state = State.ATTACK
	_has_target = false
	# First swing lands immediately; cooldown gates the follow-ups.
	_attack_timer = 0.0


## One attack swing. Damage hook: units have no health yet, so this is
## animation-only until a combat/health pass adds the actual hit.
func _strike() -> void:
	if _anim_player != null and _anim_player.has_animation(attack_clip):
		_anim_player.stop()
		_anim_player.play(attack_clip)


func _threat_gone() -> bool:
	if _threat == null or not is_instance_valid(_threat):
		return true
	var disengage := (aggro_radius if archetype == Archetype.HOSTILE else flee_radius) * DISENGAGE_FACTOR
	return global_position.distance_to(_threat.global_position) > disengage


func _start_idle() -> void:
	_idle_timer = randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)


## Picks a random point within wander_radius of the spawn origin, retrying a
## few times if it lands below min_wander_height - a fresh point beats a
## creature that swims.
func _pick_wander_target() -> void:
	# Radius 0 = parked (dev previews); skip picking rather than sampling a
	# degenerate randf_range(1.0, 0.0).
	if wander_radius <= 0.0:
		_start_idle()
		return
	for _attempt in range(WANDER_TARGET_ATTEMPTS):
		var angle := randf() * TAU
		var candidate := _wander_center + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.0, wander_radius)
		if _height_at(candidate) >= min_wander_height:
			_target = Vector3(candidate.x, 0.0, candidate.z)
			_has_target = true
			_state = State.WANDER
			_play_clip_or_fallback(walk_clip, walk_clip)
			return
	_start_idle()


func _height_at(world_position: Vector3) -> float:
	if ground_sampler.is_valid():
		return ground_sampler.call(world_position.x, world_position.z)
	return world_position.y


func _face_direction(flat_dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(flat_dir.x, flat_dir.z) + facing_offset
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * turn_speed))


func _grounded(position: Vector3) -> Vector3:
	if ground_sampler.is_valid():
		position.y = ground_sampler.call(position.x, position.z)
	return position


func _snap_to_ground() -> void:
	global_position = _grounded(global_position)


func _build_visual() -> void:
	if model_path == "" or not ResourceLoader.exists(model_path):
		return
	var scene := load(model_path) as PackedScene
	if scene == null:
		return
	var model := scene.instantiate()
	add_child(model)
	_anim_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim_player == null:
		return
	# glTF import doesn't mark clips looping; loop the ones that cycle.
	for clip in loop_clips:
		if _anim_player.has_animation(clip):
			_anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_play_clip_or_fallback(idle_clip, idle_clip)


## Play `clip_name`, or `fallback` when the rig doesn't have it (e.g. the
## rabbit has no Running clip, so fleeing plays its Walk).
func _play_clip_or_fallback(clip_name: String, fallback: String) -> void:
	if _anim_player == null:
		return
	var chosen := clip_name if _anim_player.has_animation(clip_name) else fallback
	if _anim_player.has_animation(chosen) and _anim_player.current_animation != chosen:
		_anim_player.play(chosen)
