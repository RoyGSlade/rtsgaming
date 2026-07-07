class_name BuilderBrain
extends RefCounted

## Raises a BuildSite block by block (DEMO_PLAN.md §5). A builder claims a
## construct job, then loops: walk to the stockpile, pick up one block's worth
## of material, carry it to the site, and place the block — progress reads
## "3/5" as the structure rises. Decoupled from the Unit so it's unit-testable,
## like WorkerBrain: `tick(delta, pos)` returns { state, move_target, stance }.

enum State { IDLE, TO_STOCKPILE, TO_SITE, PLACING }

const ARRIVE_EPSILON := 1.2
const PLACE_SECONDS := 1.0
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
var _site: BuildSite = null
var _place_elapsed: float = 0.0


func _init(p_worker_id: int, p_board: JobBoard, p_economy: EconomyController, p_stockpile: Vector3, p_roles: Array = [&"builder"]) -> void:
	worker_id = p_worker_id
	_board = p_board
	_economy = p_economy
	stockpile_position = p_stockpile
	roles = p_roles


func has_job() -> bool:
	return _job_id != -1


func tick(delta: float, world_position: Vector3) -> Dictionary:
	match state:
		State.IDLE:
			_try_claim_construct_job()
			return _intent(null, STANCE_IDLE)

		State.TO_STOCKPILE:
			if _site == null or not _site.needs_block():
				_finish()
				return _intent(null, STANCE_IDLE)
			if _reached(world_position, stockpile_position):
				# Pick up one block's materials, if the stockpile can cover it.
				if _economy.can_afford_block(_site) and _economy.take_block_materials(_site):
					state = State.TO_SITE
					return _intent(_site.position, STANCE_CARRY)
				return _intent(null, STANCE_IDLE) # wait for materials
			return _intent(stockpile_position, STANCE_IDLE)

		State.TO_SITE:
			if _site == null:
				_finish()
				return _intent(null, STANCE_IDLE)
			if _reached(world_position, _site.position):
				state = State.PLACING
				_place_elapsed = 0.0
				return _intent(null, STANCE_DIG)
			return _intent(_site.position, STANCE_CARRY)

		State.PLACING:
			_place_elapsed += delta
			if _place_elapsed < PLACE_SECONDS:
				return _intent(null, STANCE_DIG)
			if _site != null:
				_site.place_block() # emits block_placed(placed, total) -> "3/5"
			if _site != null and _site.needs_block():
				state = State.TO_STOCKPILE
				return _intent(stockpile_position, STANCE_IDLE)
			_finish()
			return _intent(null, STANCE_IDLE)

	return _intent(null, STANCE_IDLE)


# ----- internals -----

func _try_claim_construct_job() -> void:
	var job := _board.claim_next(worker_id, roles)
	if job.is_empty():
		return
	if StringName(job["type"]) != &"construct":
		_board.abandon(int(job["id"]))
		return
	var site: BuildSite = job["data"].get("site")
	if site == null or site.is_complete():
		_board.complete(int(job["id"])) # nothing to do; retire the job
		return
	_job_id = int(job["id"])
	_site = site
	state = State.TO_STOCKPILE


func _finish() -> void:
	if _job_id != -1:
		_board.complete(_job_id)
		_job_id = -1
	_site = null
	state = State.IDLE


func _reached(a: Vector3, b: Vector3) -> bool:
	return Vector3(a.x, 0.0, a.z).distance_to(Vector3(b.x, 0.0, b.z)) <= ARRIVE_EPSILON


func _intent(move_target: Variant, stance: int) -> Dictionary:
	return {"state": state, "move_target": move_target, "stance": stance}
