class_name VillagerController
extends Node

## Spawns a handful of autonomous villagers and drives each with a WorkerBrain,
## keeping a standing supply of gather jobs on the board so the settlement's
## logistics are visibly alive (DEMO_PLAN.md §5). Applies each brain's per-frame
## intent to its Unit (move order + dig/carry stance). Rebinds cleanly when the
## world regenerates and the economy is rebuilt.

const VILLAGER_COUNT := 3
const SPAWN_RADIUS := 3.5
const GATHER_ROTATION: Array[StringName] = [&"wood", &"raw_ore", &"coal"]

var economy: EconomyController
var world: WorldRuntime
var stockpile_position: Vector3

# Each entry: { "unit": Unit, "brain": WorkerBrain, "last_target": Variant }
var _villagers: Array[Dictionary] = []
var _rotation_index := 0


## (Re)build villagers for a freshly-created economy. Frees any previous units
## and their brains first, so a regenerate doesn't accumulate workers.
func bind(new_economy: EconomyController, new_world: WorldRuntime, stockpile: Vector3) -> void:
	_clear()
	economy = new_economy
	world = new_world
	stockpile_position = stockpile
	if economy == null or world == null:
		return
	for i in VILLAGER_COUNT:
		_spawn_villager(i)


func _process(delta: float) -> void:
	if economy == null:
		return
	_ensure_gather_jobs()
	for v in _villagers:
		var unit: Unit = v["unit"]
		var brain: WorkerBrain = v["brain"]
		if not is_instance_valid(unit):
			continue
		var intent := brain.tick(delta, unit.global_position)
		var target: Variant = intent["move_target"]
		# Only issue a fresh move order when the destination changes, so we
		# don't reset the unit's travel state every frame.
		if target != null and v["last_target"] != target:
			unit.move_to(target)
			v["last_target"] = target
		unit.set_stance(int(intent["stance"]))


## Keep at least one open gather job per villager, cycling wood/ore/coal and
## only posting for resources that still have an available node.
func _ensure_gather_jobs() -> void:
	var board := economy.job_board
	var attempts := 0
	while board.open_count() < VILLAGER_COUNT and attempts < GATHER_ROTATION.size():
		var resource := GATHER_ROTATION[_rotation_index]
		_rotation_index = (_rotation_index + 1) % GATHER_ROTATION.size()
		attempts += 1
		if economy.nearest_available_node(resource, stockpile_position) != null:
			board.post(&"gather", {"resource_id": resource}, 0, &"gatherer")


func _spawn_villager(index: int) -> void:
	var unit := Unit.new()
	unit.ground_sampler = world.get_ground_height
	add_child(unit)
	var angle := TAU * float(index) / float(VILLAGER_COUNT)
	var spot := stockpile_position + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
	unit.global_position = Vector3(spot.x, world.get_ground_height(spot.x, spot.z), spot.z)

	var brain := WorkerBrain.new(1000 + index, economy.job_board, economy, stockpile_position, [&"gatherer"])
	_villagers.append({"unit": unit, "brain": brain, "last_target": null})


func _clear() -> void:
	for v in _villagers:
		var unit: Unit = v["unit"]
		if is_instance_valid(unit):
			unit.queue_free()
	_villagers.clear()
	_rotation_index = 0
