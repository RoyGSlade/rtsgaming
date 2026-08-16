class_name WorkerBrain
extends RefCounted

## Turns job-board jobs into concrete gather→haul behaviour, decoupled from the
## Unit so it's fully unit-testable (DEMO_PLAN.md §4/§5). Each frame the scene
## calls `tick(delta, world_position)` and applies the returned intent:
##   { state, move_target: Vector3 or null, stance: Unit.Stance }
## The brain owns the economy interactions (reserve, extract, deposit) and
## claims/completes/abandons its job on the board, so a stalled trip recovers
## instead of stranding resources.
##
## Demo scope: the gather→stockpile loop — the visible logistics the pitch is
## built on. Crafting/inter-station hauling layer on top of the same pattern.

enum State { IDLE, TO_SOURCE, GATHERING, TO_DROPOFF }

const ARRIVE_EPSILON := 1.2
const GATHER_SECONDS := 2.0
const CARRY_CAPACITY := 10
# Unit.Stance values, referenced by number so this stays Unit-free/testable.
const STANCE_IDLE := 0
const STANCE_DIG := 1
const STANCE_CARRY := 2

var worker_id: int
var roles: Array = []
var stockpile_position: Vector3

var _board: JobBoard
var _economy: EconomyController

var state: int = State.IDLE
var _job_id: int = -1
var _node: ResourceNode = null
var _reserved: int = 0
var _carried_id: StringName = &""
var _carried: int = 0
var _gather_elapsed: float = 0.0


func _init(p_worker_id: int, p_board: JobBoard, p_economy: EconomyController, p_stockpile: Vector3, p_roles: Array = []) -> void:
	worker_id = p_worker_id
	_board = p_board
	_economy = p_economy
	stockpile_position = p_stockpile
	roles = p_roles


func carried_amount() -> int:
	return _carried


func has_job() -> bool:
	return _job_id != -1


## Advance the brain and return the intent for this frame.
func tick(delta: float, world_position: Vector3) -> Dictionary:
	match state:
		State.IDLE:
			_try_claim_gather_job()
			return _intent(null, STANCE_IDLE)

		State.TO_SOURCE:
			if _node == null or _node.is_depleted():
				# Target vanished (mined out by someone else) — recover.
				_abandon()
				return _intent(null, STANCE_IDLE)
			if _reached(world_position, _node.world_position):
				state = State.GATHERING
				_gather_elapsed = 0.0
				return _intent(null, STANCE_DIG)
			return _intent(_node.world_position, STANCE_IDLE)

		State.GATHERING:
			_gather_elapsed += delta
			if _gather_elapsed < GATHER_SECONDS:
				return _intent(null, STANCE_DIG)
			# Pull the reserved units out of the node into the worker's arms.
			_carried_id = _node.resource_id
			_carried = _node.extract(_reserved)
			_reserved = 0
			state = State.TO_DROPOFF
			return _intent(stockpile_position, STANCE_CARRY)

		State.TO_DROPOFF:
			if _reached(world_position, stockpile_position):
				if _carried > 0:
					_economy.add_stock(_carried_id, _carried)
				_carried = 0
				_carried_id = &""
				_board.complete(_job_id)
				_job_id = -1
				_node = null
				state = State.IDLE
				return _intent(null, STANCE_IDLE)
			return _intent(stockpile_position, STANCE_CARRY)

	return _intent(null, STANCE_IDLE)


# ----- internals -----

func _try_claim_gather_job() -> void:
	var job := _board.claim_next(worker_id, roles)
	if job.is_empty():
		return
	if StringName(job["type"]) != &"gather":
		# Not something this brain handles — hand it back for another worker.
		_board.abandon(int(job["id"]))
		return
	var resource_id := StringName(job["data"].get("resource_id", &""))
	var node := _economy.nearest_available_node(resource_id, stockpile_position)
	if node == null:
		# Nothing to gather right now; release the job so it can retry later.
		_board.abandon(int(job["id"]))
		return
	_job_id = int(job["id"])
	_node = node
	_reserved = node.reserve(CARRY_CAPACITY)
	if _reserved <= 0:
		_abandon()
		return
	state = State.TO_SOURCE


## Give everything back and return to idle: unreserve the node, hand the job
## back to the board. The recovery path the gameplan insists on.
func _abandon() -> void:
	if _node != null and _reserved > 0:
		_node.release(_reserved)
	_reserved = 0
	if _job_id != -1:
		_board.abandon(_job_id)
		_job_id = -1
	_node = null
	state = State.IDLE


func _reached(a: Vector3, b: Vector3) -> bool:
	return Vector3(a.x, 0.0, a.z).distance_to(Vector3(b.x, 0.0, b.z)) <= ARRIVE_EPSILON


func _intent(move_target: Variant, stance: int) -> Dictionary:
	return {"state": state, "move_target": move_target, "stance": stance}
