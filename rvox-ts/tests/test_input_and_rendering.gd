@tool
extends McpTestSuite

## Pure-logic coverage for the touch/dynamic-resolution slice: the adaptive
## render-scale hysteresis and the camera's twist-angle wrapping. Both are
## static helpers so they run without a viewport, frame loop, or touchscreen.

const DynRes := preload("res://scripts/rendering/dynamic_resolution_controller.gd")
const Camera := preload("res://scripts/camera/rts_camera_controller.gd")


func suite_name() -> String:
	return "input_and_rendering"


func test_scale_drops_when_below_target() -> void:
	# 40 fps against a 60 target is well below 0.90x -> step down.
	var next := DynRes.compute_next_scale(1.0, 40.0, 60.0, 0.5, 1.0, 0.05)
	assert_true(is_equal_approx(next, 0.95), "Under target should drop one step")


func test_scale_climbs_when_above_target() -> void:
	# A comfortably-met target with headroom recovers resolution.
	var next := DynRes.compute_next_scale(0.7, 60.0, 60.0, 0.5, 1.0, 0.05)
	assert_true(is_equal_approx(next, 0.75), "At/above target should climb one step")


func test_scale_holds_inside_dead_band() -> void:
	# 57 fps is between 0.90x (54) and 0.98x (58.8) of 60 -> no change.
	var next := DynRes.compute_next_scale(0.8, 57.0, 60.0, 0.5, 1.0, 0.05)
	assert_true(is_equal_approx(next, 0.8), "Inside the dead-band the scale holds")


func test_scale_clamps_to_bounds() -> void:
	var floor_scale := DynRes.compute_next_scale(0.5, 10.0, 60.0, 0.5, 1.0, 0.05)
	assert_true(is_equal_approx(floor_scale, 0.5), "Scale never drops below min")
	var ceil_scale := DynRes.compute_next_scale(1.0, 120.0, 60.0, 0.5, 1.0, 0.05)
	assert_true(is_equal_approx(ceil_scale, 1.0), "Scale never rises above max")


func test_scale_no_change_without_target() -> void:
	var next := DynRes.compute_next_scale(0.7, 10.0, 0.0, 0.5, 1.0, 0.05)
	assert_true(is_equal_approx(next, 0.7), "A zero/unknown target leaves scale untouched")


func test_twist_takes_the_short_way_around() -> void:
	# From +170deg to -170deg is a +20deg turn, not a -340deg spin.
	var delta := Camera.angle_delta(deg_to_rad(170.0), deg_to_rad(-170.0))
	assert_true(is_equal_approx(delta, deg_to_rad(20.0)), "Twist wraps across the PI seam the short way")


func test_twist_zero_delta() -> void:
	assert_true(is_equal_approx(Camera.angle_delta(1.2, 1.2), 0.0), "No rotation yields no yaw change")
