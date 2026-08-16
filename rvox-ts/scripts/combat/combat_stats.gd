class_name CombatStats
extends Resource

## Data-driven combat profile for a unit type (DEMO_PLAN.md §6). Kept as a
## Resource so stats live in `.tres` later and combat stays tunable without
## code. Damage/armor/hp feed CombatMath; range/interval drive engagement.

@export var id: StringName = &""
@export var max_hp: int = 10
@export var damage: int = 3
@export var armor: int = 0
@export var attack_range: float = 1.5
@export var attack_interval: float = 1.0


func duplicate_stats() -> CombatStats:
	var c := CombatStats.new()
	c.id = id
	c.max_hp = max_hp
	c.damage = damage
	c.armor = armor
	c.attack_range = attack_range
	c.attack_interval = attack_interval
	return c
