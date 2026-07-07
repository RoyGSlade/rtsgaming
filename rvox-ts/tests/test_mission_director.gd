@tool
extends McpTestSuite

## Simulates whole runs through the MissionDirector state machine: phase
## progression, the raid schedule, and every win/loss path. See DEMO_PLAN.md §7
## and RUN_RULES.md.


func suite_name() -> String:
	return "mission_director"


func _director(difficulty: StringName = &"normal") -> MissionDirector:
	var d := track(MissionDirector.new()) as MissionDirector
	d.difficulty = difficulty
	return d


## Tick a director in small steps for `seconds` so transitions land cleanly.
func _run_for(d: MissionDirector, seconds: float) -> void:
	var step := 5.0
	var t := 0.0
	while t < seconds:
		d.advance(step)
		t += step


func test_briefing_then_begin_enters_day_one() -> void:
	var d := _director()
	assert_eq(d.phase, MissionDirector.Phase.GENERATION, "Starts in generation")
	d.present_briefing()
	assert_eq(d.phase, MissionDirector.Phase.BRIEFING, "Briefing after world ready")
	d.begin_run()
	assert_eq(d.phase, MissionDirector.Phase.DAY, "Begin run -> day phase")
	assert_eq(d.day, 1, "On day 1")
	assert_false(d.is_night, "Day 1 starts in daylight")


func test_day_transitions_to_night_and_fires_raid() -> void:
	var d := _director()
	var raids: Array = []
	d.raid_incoming.connect(func(night: int, size: int, target: StringName) -> void:
		raids.append({"night": night, "size": size, "target": target}))
	d.present_briefing()
	d.begin_run()
	_run_for(d, MissionDirector.DAY_SECONDS + 5.0)
	assert_eq(d.phase, MissionDirector.Phase.NIGHT, "After a full day it is night")
	assert_true(d.is_night, "Night flag set")
	assert_eq(raids.size(), 1, "Exactly one raid fired at night 1")
	assert_eq(int(raids[0]["night"]), 1, "It is the night-1 raid")
	assert_eq(raids[0]["target"], &"haulers", "Night 1 targets haulers")


func test_full_survival_run_wins_after_night_three() -> void:
	var d := _director()
	var ended := {"outcome": MissionDirector.Outcome.NONE}
	d.run_ended.connect(func(o: int) -> void: ended["outcome"] = o)
	d.present_briefing()
	d.begin_run()
	# Three full day+night cycles.
	var cycle := MissionDirector.DAY_SECONDS + MissionDirector.NIGHT_SECONDS
	_run_for(d, cycle * 3 + 10.0)
	assert_eq(ended["outcome"], MissionDirector.Outcome.WIN, "Surviving night 3 wins")
	assert_eq(d.phase, MissionDirector.Phase.RESOLUTION, "Run resolves")


func test_three_raids_fire_across_the_run() -> void:
	var d := _director()
	var nights: Array = []
	d.raid_incoming.connect(func(night: int, _size: int, _t: StringName) -> void: nights.append(night))
	d.present_briefing()
	d.begin_run()
	var cycle := MissionDirector.DAY_SECONDS + MissionDirector.NIGHT_SECONDS
	_run_for(d, cycle * 3 + 10.0)
	assert_eq(nights.size(), 3, "One raid per night, three nights")
	assert_eq(nights[2], 3, "Final raid is night 3")


func test_raider_camp_destroyed_wins_immediately() -> void:
	var d := _director()
	var ended := {"outcome": MissionDirector.Outcome.NONE}
	d.run_ended.connect(func(o: int) -> void: ended["outcome"] = o)
	d.present_briefing()
	d.begin_run()
	_run_for(d, 30.0) # early in day 1
	d.notify_raider_camp_destroyed()
	assert_eq(ended["outcome"], MissionDirector.Outcome.WIN, "Razing the camp wins")
	assert_eq(d.phase, MissionDirector.Phase.RESOLUTION, "Run resolves on camp destruction")


func test_town_hall_destroyed_loses() -> void:
	var d := _director()
	var ended := {"outcome": MissionDirector.Outcome.NONE}
	d.run_ended.connect(func(o: int) -> void: ended["outcome"] = o)
	d.present_briefing()
	d.begin_run()
	_run_for(d, 100.0)
	d.notify_town_hall_destroyed()
	assert_eq(ended["outcome"], MissionDirector.Outcome.LOSS, "Losing the town hall loses")


func test_all_workers_dead_loses() -> void:
	var d := _director()
	var ended := {"outcome": MissionDirector.Outcome.NONE}
	d.run_ended.connect(func(o: int) -> void: ended["outcome"] = o)
	d.present_briefing()
	d.begin_run()
	d.notify_workers_alive(0)
	assert_eq(ended["outcome"], MissionDirector.Outcome.LOSS, "No workers left -> loss")


func test_advance_is_inert_after_run_ends() -> void:
	var d := _director()
	var end_count := [0]
	d.run_ended.connect(func(_o: int) -> void: end_count[0] += 1)
	d.present_briefing()
	d.begin_run()
	d.notify_town_hall_destroyed() # loss now
	var cycle := MissionDirector.DAY_SECONDS + MissionDirector.NIGHT_SECONDS
	_run_for(d, cycle * 3)
	assert_eq(end_count[0], 1, "Run ends exactly once; later ticks are inert")


func test_difficulty_scales_raid_size() -> void:
	assert_eq(_director(&"easy").raid_size(3), 7, "Easy scales the night-3 raid down (10*0.7)")
	assert_eq(_director(&"normal").raid_size(3), 10, "Normal is the base size")
	assert_eq(_director(&"hard").raid_size(3), 14, "Hard scales up (10*1.4)")


func test_objective_tracking() -> void:
	var d := _director()
	assert_false(d.objective_complete(), "Objective starts incomplete")
	d.record_sword_produced(3)
	d.record_swordsman_trained(3)
	assert_true(d.objective_complete(), "Three swords + three swordsmen completes the objective")
