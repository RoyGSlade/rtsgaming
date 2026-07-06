class_name CombatMath
extends RefCounted

## Combat resolution (DEMO_PLAN.md §6/§14): the damage formula and a
## deterministic skirmish simulator used to resolve a raid's outcome and to
## test that attributes/equipment actually matter. No randomness — same inputs,
## same result — so it's testable and save-safe.

## Damage after armor, always at least 1 so armor never makes a unit invincible.
static func resolve_hit(damage: int, armor: int) -> int:
	return maxi(1, damage - armor)


## Simulate two lines fighting to the death. Each combatant attacks the first
## living enemy every `attack_interval` seconds, dealing armor-adjusted damage.
## Fixed 0.1s step. Returns:
##   { winner: "attackers"|"defenders"|"draw",
##     attacker_survivors: int, defender_survivors: int, seconds: float }
static func simulate_skirmish(attackers: Array, defenders: Array, max_seconds: float = 600.0) -> Dictionary:
	var a := _make_line(attackers)
	var d := _make_line(defenders)
	var step := 0.1
	var elapsed := 0.0

	while elapsed < max_seconds and _any_alive(a) and _any_alive(d):
		elapsed += step
		_advance_line(a, d, step)
		_advance_line(d, a, step)

	var a_alive := _count_alive(a)
	var d_alive := _count_alive(d)
	var winner := "draw"
	if a_alive > 0 and d_alive == 0:
		winner = "attackers"
	elif d_alive > 0 and a_alive == 0:
		winner = "defenders"
	return {
		"winner": winner,
		"attacker_survivors": a_alive,
		"defender_survivors": d_alive,
		"seconds": elapsed,
	}


## Each combatant: { stats, hp, cooldown }.
static func _make_line(stats_list: Array) -> Array:
	var line: Array = []
	for stats in stats_list:
		var cs: CombatStats = stats
		line.append({"stats": cs, "hp": cs.max_hp, "cooldown": 0.0})
	return line


static func _advance_line(line: Array, foes: Array, step: float) -> void:
	var target: Variant = _first_alive(foes)
	if target == null:
		return
	for member in line:
		if member["hp"] <= 0:
			continue
		member["cooldown"] -= step
		if member["cooldown"] > 0.0:
			continue
		# Re-target if the current front foe died this step.
		if target["hp"] <= 0:
			target = _first_alive(foes)
			if target == null:
				return
		var stats: CombatStats = member["stats"]
		target["hp"] -= resolve_hit(stats.damage, target["stats"].armor)
		member["cooldown"] = stats.attack_interval


static func _first_alive(line: Array) -> Variant:
	for member in line:
		if member["hp"] > 0:
			return member
	return null


static func _any_alive(line: Array) -> bool:
	return _first_alive(line) != null


static func _count_alive(line: Array) -> int:
	var n := 0
	for member in line:
		if member["hp"] > 0:
			n += 1
	return n
