class_name MissionDirector
extends Node

## Drives one run's structure (DEMO_PLAN.md §7, rules frozen in RUN_RULES.md):
## the phase/day-night state machine, the objective tracker, the raid schedule,
## and the win/loss checks. Pure time-driven logic — `advance(delta)` steps the
## whole thing, so a test can simulate a full run by ticking a fake clock. The
## scene layer connects the real day/night clock, the economy (sword/swordsman
## counts), and combat (raider camp, town hall, worker deaths) to the notify_*
## methods and reacts to the signals.

signal phase_changed(phase: int, day: int, is_night: bool)
signal raid_incoming(night: int, size: int, target_priority: StringName)
signal objective_updated(swords: int, swordsmen: int)
signal run_ended(outcome: int)

enum Phase { GENERATION, BRIEFING, DAY, NIGHT, RESOLUTION }
enum Outcome { NONE, WIN, LOSS }

# Timings (seconds) — RUN_RULES.md: ~3 min day, ~1 min night, 3 days.
const DAY_SECONDS := 180.0
const NIGHT_SECONDS := 60.0
const FINAL_DAY := 3

const SWORD_GOAL := 3
const SWORDSMAN_GOAL := 3

# Base raider counts per night; scaled by the difficulty multiplier. Index by
# night number (1-based). RUN_RULES.md raid table.
const RAID_BASE := {1: 3, 2: 5, 3: 10}
const RAID_TARGET := {1: &"haulers", 2: &"buildings", 3: &"town_hall"}
const DIFFICULTY := {&"easy": 0.7, &"normal": 1.0, &"hard": 1.4}

var difficulty: StringName = &"normal"

var phase: int = Phase.GENERATION
var day: int = 0
var is_night: bool = false
var outcome: int = Outcome.NONE

var swords_produced: int = 0
var swordsmen_trained: int = 0
var raider_camp_destroyed: bool = false
var town_hall_alive: bool = true
var workers_alive: int = 1

var _phase_elapsed: float = 0.0
## Nights whose raid_incoming has already fired, so we never double-fire.
var _raids_fired: Dictionary = {}


## Move from GENERATION to BRIEFING once the world + manifest are ready.
func present_briefing() -> void:
	_set_phase(Phase.BRIEFING)


## Player dismisses the briefing: start day 1.
func begin_run() -> void:
	day = 1
	is_night = false
	_phase_elapsed = 0.0
	_set_phase(Phase.DAY)


## Step the clock. Handles day->night->next-day transitions, fires raids at
## night start, and runs the win check at the end of the final night.
func advance(delta: float) -> void:
	if phase != Phase.DAY and phase != Phase.NIGHT:
		return
	if outcome != Outcome.NONE:
		return
	_phase_elapsed += delta

	if phase == Phase.DAY and _phase_elapsed >= DAY_SECONDS:
		_phase_elapsed = 0.0
		is_night = true
		_set_phase(Phase.NIGHT)
		_fire_raid(day)
	elif phase == Phase.NIGHT and _phase_elapsed >= NIGHT_SECONDS:
		_phase_elapsed = 0.0
		if day >= FINAL_DAY:
			# Survived the final night -> win.
			_end_run(Outcome.WIN)
		else:
			day += 1
			is_night = false
			_set_phase(Phase.DAY)


func time_left_in_phase() -> float:
	var total := NIGHT_SECONDS if phase == Phase.NIGHT else DAY_SECONDS
	return maxf(0.0, total - _phase_elapsed)


func raid_size(night: int) -> int:
	var base := int(RAID_BASE.get(night, RAID_BASE[FINAL_DAY]))
	var mult := float(DIFFICULTY.get(difficulty, 1.0))
	return maxi(1, int(round(base * mult)))


func objective_complete() -> bool:
	return swords_produced >= SWORD_GOAL and swordsmen_trained >= SWORDSMAN_GOAL


# ----- notifications from the rest of the game -----

func record_sword_produced(count: int = 1) -> void:
	swords_produced += count
	objective_updated.emit(swords_produced, swordsmen_trained)


func record_swordsman_trained(count: int = 1) -> void:
	swordsmen_trained += count
	objective_updated.emit(swords_produced, swordsmen_trained)


## Alternate win: raze the raider camp any time.
func notify_raider_camp_destroyed() -> void:
	raider_camp_destroyed = true
	if outcome == Outcome.NONE and phase != Phase.GENERATION and phase != Phase.BRIEFING:
		_end_run(Outcome.WIN)


func notify_town_hall_destroyed() -> void:
	town_hall_alive = false
	_check_loss()


func notify_workers_alive(count: int) -> void:
	workers_alive = count
	_check_loss()


# ----- internals -----

func _check_loss() -> void:
	if outcome != Outcome.NONE:
		return
	if not town_hall_alive or workers_alive <= 0:
		_end_run(Outcome.LOSS)


func _fire_raid(night: int) -> void:
	if _raids_fired.has(night):
		return
	_raids_fired[night] = true
	raid_incoming.emit(night, raid_size(night), StringName(RAID_TARGET.get(night, &"town_hall")))


func _set_phase(new_phase: int) -> void:
	phase = new_phase
	phase_changed.emit(phase, day, is_night)


func _end_run(result: int) -> void:
	outcome = result
	_set_phase(Phase.RESOLUTION)
	run_ended.emit(outcome)


# ----- save/resume (DEMO_PLAN.md §8) -----

## JSON-safe snapshot of the whole director state for the run save.
func capture_state() -> Dictionary:
	var fired: Array = []
	for night in _raids_fired.keys():
		fired.append(int(night))
	return {
		"difficulty": String(difficulty),
		"phase": phase,
		"day": day,
		"is_night": is_night,
		"outcome": outcome,
		"swords_produced": swords_produced,
		"swordsmen_trained": swordsmen_trained,
		"raider_camp_destroyed": raider_camp_destroyed,
		"town_hall_alive": town_hall_alive,
		"workers_alive": workers_alive,
		"phase_elapsed": _phase_elapsed,
		"raids_fired": fired,
	}


## Restore from a snapshot produced by capture_state(). Does not re-emit
## signals — the scene rebuilds visuals from the restored fields.
func restore_state(state: Dictionary) -> void:
	difficulty = StringName(state.get("difficulty", "normal"))
	phase = int(state.get("phase", Phase.GENERATION))
	day = int(state.get("day", 0))
	is_night = bool(state.get("is_night", false))
	outcome = int(state.get("outcome", Outcome.NONE))
	swords_produced = int(state.get("swords_produced", 0))
	swordsmen_trained = int(state.get("swordsmen_trained", 0))
	raider_camp_destroyed = bool(state.get("raider_camp_destroyed", false))
	town_hall_alive = bool(state.get("town_hall_alive", true))
	workers_alive = int(state.get("workers_alive", 1))
	_phase_elapsed = float(state.get("phase_elapsed", 0.0))
	_raids_fired.clear()
	for night in state.get("raids_fired", []):
		_raids_fired[int(night)] = true
