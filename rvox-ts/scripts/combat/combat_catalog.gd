class_name CombatCatalog
extends RefCounted

## Demo combat profiles (DEMO_PLAN.md §6, RUN_RULES.md raids). Code-defined for
## the demo; migrates to `.tres` alongside the rest of the data later. Tuned so
## a small band of swordsmen backed by a watchtower can turn back an early raid
## but is overwhelmed by the night-3 wave without preparation.

static func _stats(id: StringName, hp: int, dmg: int, armor: int, atk_range: float, interval: float) -> CombatStats:
	var s := CombatStats.new()
	s.id = id
	s.max_hp = hp
	s.damage = dmg
	s.armor = armor
	s.attack_range = atk_range
	s.attack_interval = interval
	return s


static func swordsman() -> CombatStats:
	return _stats(&"swordsman", 24, 6, 2, 1.6, 1.0)


static func raider() -> CombatStats:
	return _stats(&"raider", 14, 4, 0, 1.4, 1.1)


## Static defender: high hp/armor, hits hard at range, but can't move.
static func watchtower() -> CombatStats:
	return _stats(&"watchtower", 60, 7, 4, 8.0, 1.4)


static func stats_for(id: StringName) -> CombatStats:
	match id:
		&"swordsman": return swordsman()
		&"raider": return raider()
		&"watchtower": return watchtower()
	return _stats(id, 10, 3, 0, 1.5, 1.0)


## Build a line of `count` copies of a profile (for skirmish resolution).
static func line_of(id: StringName, count: int) -> Array:
	var out: Array = []
	for i in count:
		out.append(stats_for(id))
	return out
