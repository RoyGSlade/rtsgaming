@tool
extends McpTestSuite


func suite_name() -> String:
	return "units"


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func test_step_advances_toward_target_by_speed() -> void:
	var result := Unit.step_toward(Vector3(0, 5, 0), Vector3(10, 0, 0), 5.0, 1.0)
	assert_false(result.arrived, "Should not arrive when target is farther than one step")
	assert_true(_near(result.position.x, 5.0), "Should advance speed*delta along +x")
	assert_true(_near(result.position.z, 0.0), "Should not drift off-axis")
	assert_true(_near(result.position.y, 5.0), "Y is left to the ground sampler, not touched by the step")


func test_step_arrives_and_snaps_when_within_one_step() -> void:
	var result := Unit.step_toward(Vector3(8, 5, 0), Vector3(10, 0, 0), 5.0, 1.0)
	assert_true(result.arrived, "Should arrive when remaining distance is within one step")
	assert_true(_near(result.position.x, 10.0), "Should snap exactly to target X")
	assert_true(_near(result.position.z, 0.0), "Should snap exactly to target Z")


func test_step_moves_along_z_axis() -> void:
	var result := Unit.step_toward(Vector3(0, 0, 0), Vector3(0, 0, 10), 10.0, 0.5)
	assert_false(result.arrived, "Half a second at speed 10 covers 5 of 10 units")
	assert_true(_near(result.position.z, 5.0), "Should advance along +z")


func test_step_at_target_reports_arrived() -> void:
	var result := Unit.step_toward(Vector3(3, 0, 3), Vector3(3, 0, 3), 5.0, 1.0)
	assert_true(result.arrived, "Already at the target counts as arrived")
