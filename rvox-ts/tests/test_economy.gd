@tool
extends McpTestSuite

## Covers the demo production-chain backend: finite resource nodes with
## reservations, the job board's atomic claim/abandon, production stations
## crafting over time without losing goods, and the bottleneck diagnoser.
## See DEMO_PLAN.md §4 and tests-checklist §14.


func suite_name() -> String:
	return "economy"


# ----- ResourceNode -----

func test_resource_node_reserve_reduces_available() -> void:
	var node := ResourceNode.new(&"wood", 10)
	assert_eq(node.available(), 10, "Fresh node offers its full total")
	assert_eq(node.reserve(4), 4, "Reserving within stock grants the full amount")
	assert_eq(node.available(), 6, "Reserved units are no longer available")


func test_resource_node_two_workers_cannot_over_reserve() -> void:
	var node := ResourceNode.new(&"raw_ore", 5)
	assert_eq(node.reserve(4), 4, "First worker reserves 4")
	assert_eq(node.reserve(4), 1, "Second worker only gets the remaining 1")
	assert_eq(node.available(), 0, "Nothing left to reserve")


func test_resource_node_release_restores_availability() -> void:
	var node := ResourceNode.new(&"coal", 8)
	node.reserve(5)
	node.release(3)
	assert_eq(node.available(), 6, "Released reservation returns to the pool")


func test_resource_node_extract_consumes_and_clears_reservation() -> void:
	var node := ResourceNode.new(&"wood", 10)
	node.reserve(4)
	assert_eq(node.extract(4), 4, "Extract fulfils the reservation")
	assert_eq(node.remaining, 6, "Deposit shrinks by the extracted amount")
	assert_eq(node.reserved, 0, "Reservation is cleared on extract")
	assert_eq(node.available(), 6, "Remaining stock is fully available again")


func test_resource_node_depletes() -> void:
	var node := ResourceNode.new(&"coal", 3)
	var fired := [false]
	node.depleted.connect(func() -> void: fired[0] = true)
	node.reserve(3)
	assert_eq(node.extract(3), 3, "Extract the whole deposit")
	assert_true(node.is_depleted(), "Node reports depleted")
	assert_true(fired[0], "depleted signal fires when the deposit empties")


# ----- JobBoard -----

func test_job_board_claim_removes_from_open_pool() -> void:
	var board := JobBoard.new()
	board.post(&"gather", {"resource": &"wood"})
	assert_eq(board.open_count(), 1, "Posted job sits open")
	var job := board.claim_next(7)
	assert_eq(int(job["id"]), 1, "Worker claims the job")
	assert_eq(board.open_count(), 0, "Claimed job leaves the open pool")
	assert_eq(board.claimed_count(), 1, "And moves to the claimed set")


func test_job_board_second_worker_cannot_claim_same_job() -> void:
	var board := JobBoard.new()
	board.post(&"haul", {})
	var first := board.claim_next(1)
	var second := board.claim_next(2)
	assert_false(first.is_empty(), "First worker gets the job")
	assert_true(second.is_empty(), "No job left for the second worker")


func test_job_board_serves_highest_priority_first() -> void:
	var board := JobBoard.new()
	board.post(&"gather", {"r": &"wood"}, 1)
	board.post(&"construct", {"b": &"forge"}, 10)
	board.post(&"gather", {"r": &"coal"}, 5)
	var job := board.claim_next(1)
	assert_eq(job["type"], &"construct", "Priority 10 job is served before lower ones")


func test_job_board_role_gating() -> void:
	var board := JobBoard.new()
	board.post(&"craft", {}, 0, &"blacksmith")
	var wrong := board.claim_next(1, [&"miner"])
	assert_true(wrong.is_empty(), "A miner cannot claim a blacksmith-only job")
	var right := board.claim_next(2, [&"blacksmith", &"hauler"])
	assert_false(right.is_empty(), "A blacksmith can claim it")


func test_job_board_abandon_recovers_job() -> void:
	var board := JobBoard.new()
	var id := board.post(&"gather", {})
	board.claim_next(1)
	assert_true(board.abandon(id), "Abandon succeeds for a claimed job")
	assert_eq(board.open_count(), 1, "Abandoned job returns to the open pool")
	var reclaimed := board.claim_next(2)
	assert_eq(int(reclaimed["id"]), id, "Another worker can now reclaim it")


func test_job_board_abandon_all_for_dead_worker() -> void:
	var board := JobBoard.new()
	board.post(&"gather", {})
	board.post(&"haul", {})
	board.claim_next(9)
	board.claim_next(9)
	assert_eq(board.abandon_all_for(9), 2, "Both jobs are released when the worker dies")
	assert_eq(board.open_count(), 2, "Both return to the open pool")


# ----- ProductionStation -----

func test_station_crafts_after_duration() -> void:
	var recipe := DemoChain.recipe_by_id(&"smelt_iron_ingot")
	var station := ProductionStation.new(&"smelter", recipe)
	station.input.add_item(&"raw_ore", 2)
	station.input.add_item(&"coal", 1)
	assert_true(station.can_start(), "Inputs present, output empty -> can start")
	assert_true(station.start(), "Craft starts")
	assert_eq(station.input.get_amount(&"raw_ore"), 0, "Inputs consumed at start")
	# Not done before the duration elapses.
	assert_false(station.tick(recipe.duration_seconds - 1.0), "Not finished mid-craft")
	assert_eq(station.output.get_amount(&"iron_ingot"), 0, "No output yet")
	# Completes once the remaining time passes.
	assert_true(station.tick(2.0), "Craft finishes after full duration")
	assert_eq(station.output.get_amount(&"iron_ingot"), 1, "Iron ingot produced")
	assert_false(station.is_active(), "Station idle after finishing")


func test_station_cannot_start_without_inputs() -> void:
	var recipe := DemoChain.recipe_by_id(&"smelt_iron_ingot")
	var station := ProductionStation.new(&"smelter", recipe)
	station.input.add_item(&"raw_ore", 1) # need 2
	station.input.add_item(&"coal", 1)
	assert_false(station.can_start(), "Insufficient ore blocks the craft")
	assert_false(station.start(), "Start refuses")


func test_station_holds_output_when_full_then_drains() -> void:
	var recipe := DemoChain.recipe_by_id(&"make_wood_handle") # wood -> 2 handles
	var station := ProductionStation.new(&"forge", recipe, 100)
	# Pre-fill output near cap so the 2 new handles don't fit at completion.
	station.output.capacity_per_item = 1
	station.output.add_item(&"wood_handle", 1)
	station.input.add_item(&"wood", 1)
	# can_start is false because outputs won't fit right now.
	assert_false(station.can_start(), "Full output blocks a new craft")
	# Force a craft by raising cap, starting, then shrinking cap mid-craft to
	# simulate a hauler not arriving: goods must be held, not destroyed.
	station.output.capacity_per_item = 100
	assert_true(station.start(), "Craft starts when there is room")
	station.output.capacity_per_item = 1 # room vanishes before completion
	station.output.remove_item(&"wood_handle", 1) # 0 on hand, cap 1
	station.output.add_item(&"wood_handle", 1) # fill the single slot
	assert_true(station.tick(recipe.duration_seconds), "Craft completes")
	# Only 1 slot free-ness; 2 produced -> at most cap held in output, rest pending, none lost.
	station.output.capacity_per_item = 100
	station.tick(0.0) # drain pending now that room exists
	assert_eq(station.output.get_amount(&"wood_handle"), 3, "All produced handles survive (1 pre + 2 made)")


# ----- DemoChain diagnoser -----

func test_diagnose_reports_producible_when_stock_present() -> void:
	var result := DemoChain.diagnose(&"iron_sword", {&"iron_sword": 1})
	assert_true(bool(result["producible"]), "Already have the sword -> producible")


func test_diagnose_traces_sword_to_missing_ore() -> void:
	# Have handles and coal but no ore: swords are blocked by raw_ore.
	var stock := {&"wood_handle": 4, &"coal": 4}
	var result := DemoChain.diagnose(&"iron_sword", stock)
	assert_false(bool(result["producible"]), "Cannot make a sword")
	assert_eq(result["missing"], &"raw_ore", "Bottleneck traced to the missing raw ore")
	assert_contains(String(result["reason"]), "iron_sword", "Reason names the target")
	assert_contains(String(result["reason"]), "raw_ore", "Reason names the missing raw material")


func test_diagnose_traces_sword_to_missing_wood() -> void:
	# Plenty of ingots, but no wood for the handle sub-chain.
	var stock := {&"iron_ingot": 10}
	var result := DemoChain.diagnose(&"iron_sword", stock)
	assert_false(bool(result["producible"]), "Cannot make a sword without a handle")
	assert_eq(result["missing"], &"wood", "Bottleneck traced to missing wood")


func test_diagnose_intermediate_present_is_producible() -> void:
	# Enough raw materials on hand to make everything: not blocked.
	var stock := {&"raw_ore": 4, &"coal": 2, &"wood": 1}
	var result := DemoChain.diagnose(&"iron_sword", stock)
	assert_true(bool(result["producible"]), "All raw inputs present -> chain is unblocked")


func test_chain_has_expected_recipes() -> void:
	assert_eq(DemoChain.recipes().size(), 3, "Three demo recipes")
	assert_true(DemoChain.is_raw(&"wood"), "Wood is a raw resource")
	assert_false(DemoChain.is_raw(&"iron_sword"), "A sword is not raw")
	var by_output := DemoChain.recipes_by_output()
	assert_has_key(by_output, "iron_sword", "Sword is a produced output")
	assert_has_key(by_output, "iron_ingot", "Ingot is a produced output")
