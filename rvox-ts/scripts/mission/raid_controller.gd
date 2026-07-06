class_name RaidController
extends Node

## Turns the director's `raid_incoming` into an actual raid (DEMO_PLAN.md §6):
## spawns raiders at the raider camp, marches them to the settlement, and — when
## they arrive — resolves the fight with the tested combat core. A defended raid
## clears the raiders; a lost raid destroys the town hall (director handles the
## loss). The resolution is a pure static function so it's fully testable; the
## marching visuals are scene glue.

## Town guards always present, so an unprepared settlement still puts up a
## fight (and the run isn't decided the instant night falls with 0 swordsmen).
const BASE_MILITIA := 2
const RAIDER_SPEED := 8.0
const ARRIVE_DISTANCE := 2.5
const RAIDER_COLOR := Color(0.85, 0.2, 0.2)

var director: MissionDirector
var world: WorldRuntime
var economy: EconomyController
var camp_position: Vector3
var raider_camp_position: Vector3

var _raiders: Array[MeshInstance3D] = []
var _pending := false
var _pending_size := 0
## Completed watchtowers strengthen the garrison in raid resolution.
var _watchtowers := 0


func bind(new_director: MissionDirector, new_world: WorldRuntime, camp: Vector3, raider_camp: Vector3, new_economy: EconomyController = null) -> void:
	if director != null and director.raid_incoming.is_connected(_on_raid_incoming):
		director.raid_incoming.disconnect(_on_raid_incoming)
	director = new_director
	world = new_world
	economy = new_economy
	camp_position = camp
	raider_camp_position = raider_camp
	_clear_raiders()
	_pending = false
	_watchtowers = 0
	if director != null:
		director.raid_incoming.connect(_on_raid_incoming)
	if economy != null:
		economy.building_completed.connect(_on_building_completed)


func _on_building_completed(building_id: StringName) -> void:
	if building_id == &"watchtower":
		_watchtowers += 1


## Resolve a raid with the combat core. `swordsmen` trained defenders (plus the
## base militia, plus a watchtower if built) face `raid_size` raiders. Returns
## { defended: bool, result: <skirmish dict> }.
static func resolve(swordsmen: int, watchtower_count: int, raid_size: int) -> Dictionary:
	var garrison := CombatCatalog.line_of(&"swordsman", swordsmen + BASE_MILITIA)
	for i in maxi(0, watchtower_count):
		garrison.append(CombatCatalog.watchtower())
	var raiders := CombatCatalog.line_of(&"raider", raid_size)
	var result := CombatMath.simulate_skirmish(garrison, raiders)
	# garrison is the "attackers" arg, so it holds when it "wins".
	return {"defended": result["winner"] == "attackers", "result": result}


func _on_raid_incoming(_night: int, size: int, _target: StringName) -> void:
	_pending = true
	_pending_size = size
	if is_inside_tree() and world != null:
		_spawn_raider_visuals(size)


func _process(delta: float) -> void:
	if not _pending:
		return
	if _march_raiders(delta):
		_pending = false
		_resolve_and_apply()


## March every raider toward the settlement; returns true once the lead raider
## reaches it (or there are no visuals, so the raid resolves immediately).
func _march_raiders(delta: float) -> bool:
	if _raiders.is_empty():
		return true
	var arrived := false
	for raider in _raiders:
		if not is_instance_valid(raider):
			continue
		var to := camp_position - raider.global_position
		to.y = 0.0
		var dist := to.length()
		if dist <= ARRIVE_DISTANCE:
			arrived = true
			continue
		var next := raider.global_position + to / dist * RAIDER_SPEED * delta
		if world != null:
			next.y = world.get_ground_height(next.x, next.z)
		raider.global_position = next
	return arrived


func _resolve_and_apply() -> void:
	if director == null:
		return
	var outcome := RaidController.resolve(director.swordsmen_trained, _watchtowers, _pending_size)
	if bool(outcome["defended"]):
		_clear_raiders() # repelled
	else:
		director.notify_town_hall_destroyed() # the run is lost


func _spawn_raider_visuals(size: int) -> void:
	for i in size:
		var raider := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.6
		raider.mesh = capsule
		var mat := StandardMaterial3D.new()
		mat.albedo_color = RAIDER_COLOR
		mat.emission_enabled = true
		mat.emission = RAIDER_COLOR
		mat.emission_energy_multiplier = 0.3
		raider.material_override = mat
		add_child(raider)
		var angle := TAU * float(i) / float(maxi(1, size))
		var spot := raider_camp_position + Vector3(cos(angle), 0.0, sin(angle)) * 2.0
		if world != null:
			spot.y = world.get_ground_height(spot.x, spot.z) + 0.8
		raider.global_position = spot
		_raiders.append(raider)


func _clear_raiders() -> void:
	for raider in _raiders:
		if is_instance_valid(raider):
			raider.queue_free()
	_raiders.clear()
