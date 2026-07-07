@tool
extends McpTestSuite

## Drives the WorkerBrain state machine through the gather→haul loop by
## simulating movement (feeding the intent's move_target back as the next
## position). Covers a full delivery, depletion recovery, and idle-when-no-work.
## See DEMO_PLAN.md §4/§5.


func suite_name() -> String:
	return "worker_brain"


func _economy_with_node(resource_id: StringName, amount: int, node_pos: Vector3) -> EconomyController:
	var eco := track(EconomyController.new()) as EconomyController
	eco.register_node(ResourceNode.new(resource_id, amount, node_pos))
	return eco


## Run the brain until it returns to IDLE or a tick cap, simulating instant
## travel: whenever the intent asks to move, the worker "arrives" next tick.
func _drive(brain: WorkerBrain, start: Vector3, max_ticks: int = 200) -> int:
	var pos := start
	var ticks := 0
	var was_working := false
	while ticks < max_ticks:
		var intent := brain.tick(1.0, pos)
		ticks += 1
		if intent["move_target"] != null:
			pos = intent["move_target"]
		if brain.state == WorkerBrain.State.IDLE and was_working:
			return ticks
		if brain.has_job():
			was_working = true
	return ticks


func test_full_gather_haul_delivers_to_stockpile() -> void:
	var node_pos := Vector3(30, 0, 30)
	var stockpile := Vector3(0, 0, 0)
	var eco := _economy_with_node(&"wood", 60, node_pos)
	var board := JobBoard.new()
	board.post(&"gather", {"resource_id": &"wood"})

	var brain := WorkerBrain.new(1, board, eco, stockpile, [])
	_drive(brain, stockpile)

	assert_eq(eco.get_stock(&"wood"), WorkerBrain.CARRY_CAPACITY, "One trip delivers a full carry load")
	assert_eq(eco.nodes()[0].remaining, 60 - WorkerBrain.CARRY_CAPACITY, "Node depleted by the carried amount")
	assert_eq(eco.nodes()[0].reserved, 0, "Reservation cleared after extraction")
	assert_eq(board.total_count(), 0, "Gather job completed and left the board")
	assert_eq(brain.state, WorkerBrain.State.IDLE, "Worker idle again after delivering")


func test_worker_passes_through_all_states() -> void:
	var node_pos := Vector3(10, 0, 0)
	var eco := _economy_with_node(&"raw_ore", 40, node_pos)
	var board := JobBoard.new()
	board.post(&"gather", {"resource_id": &"raw_ore"})
	var brain := WorkerBrain.new(2, board, eco, Vector3.ZERO, [])

	# First tick: claims job, heads to source.
	brain.tick(1.0, Vector3.ZERO)
	assert_eq(brain.state, WorkerBrain.State.TO_SOURCE, "Claims job and travels to the node")
	# Arrive at node -> gathering.
	var intent := brain.tick(1.0, node_pos)
	assert_eq(brain.state, WorkerBrain.State.GATHERING, "Digs on arrival")
	assert_eq(int(intent["stance"]), WorkerBrain.STANCE_DIG, "Dig stance while gathering")
	# Finish gathering (GATHER_SECONDS) -> carrying.
	brain.tick(WorkerBrain.GATHER_SECONDS, node_pos)
	assert_eq(brain.state, WorkerBrain.State.TO_DROPOFF, "Carries load to the stockpile")
	assert_eq(brain.carried_amount(), WorkerBrain.CARRY_CAPACITY, "Carrying a full load")


func test_recovers_when_node_depletes_mid_trip() -> void:
	var node_pos := Vector3(20, 0, 20)
	var eco := _economy_with_node(&"coal", 10, node_pos)
	var board := JobBoard.new()
	board.post(&"gather", {"resource_id": &"coal"})
	var brain := WorkerBrain.new(3, board, eco, Vector3.ZERO, [])

	brain.tick(1.0, Vector3.ZERO) # claim + reserve, TO_SOURCE
	assert_eq(brain.state, WorkerBrain.State.TO_SOURCE, "En route to the coal")
	# Another actor drains the node before this worker arrives.
	var node := eco.nodes()[0]
	node.release(node.reserved) # drop this brain's reservation for the drain
	node.reserve(node.available())
	node.extract(node.reserved)
	assert_true(node.is_depleted(), "Node is now empty")
	# Next tick should notice and recover to IDLE, handing the job back.
	brain.tick(1.0, Vector3(10, 0, 10))
	assert_eq(brain.state, WorkerBrain.State.IDLE, "Recovers to idle when the node vanishes")
	assert_eq(board.open_count(), 1, "Job handed back to the board for another worker")


func test_idle_when_no_jobs() -> void:
	var eco := _economy_with_node(&"wood", 60, Vector3(5, 0, 5))
	var board := JobBoard.new() # no jobs posted
	var brain := WorkerBrain.new(4, board, eco, Vector3.ZERO, [])
	var intent := brain.tick(1.0, Vector3.ZERO)
	assert_eq(brain.state, WorkerBrain.State.IDLE, "Stays idle with no work")
	assert_eq(intent["move_target"], null, "No move order when idle")
	assert_false(brain.has_job(), "Holds no job")


func test_two_workers_split_two_jobs_no_double_claim() -> void:
	var eco := track(EconomyController.new()) as EconomyController
	eco.register_node(ResourceNode.new(&"wood", 60, Vector3(30, 0, 0)))
	eco.register_node(ResourceNode.new(&"wood", 60, Vector3(-30, 0, 0)))
	var board := JobBoard.new()
	board.post(&"gather", {"resource_id": &"wood"})
	board.post(&"gather", {"resource_id": &"wood"})

	var a := WorkerBrain.new(1, board, eco, Vector3.ZERO, [])
	var b := WorkerBrain.new(2, board, eco, Vector3.ZERO, [])
	a.tick(1.0, Vector3.ZERO)
	b.tick(1.0, Vector3.ZERO)
	assert_true(a.has_job(), "Worker A took a job")
	assert_true(b.has_job(), "Worker B took the other job")
	assert_eq(board.open_count(), 0, "Both jobs claimed, none left")

	_drive(a, Vector3.ZERO)
	_drive(b, Vector3.ZERO)
	assert_eq(eco.get_stock(&"wood"), WorkerBrain.CARRY_CAPACITY * 2, "Both workers delivered a load")
