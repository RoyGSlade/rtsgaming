class_name Health
extends RefCounted

## Hit points for one combatant (DEMO_PLAN.md §6). Pure state + signals, so it
## drives both the tested skirmish simulation and live units the same way.

signal damaged(amount: int, remaining: int)
signal died

var max_hp: int
var hp: int


func _init(p_max_hp: int = 10) -> void:
	max_hp = maxi(1, p_max_hp)
	hp = max_hp


func is_alive() -> bool:
	return hp > 0


func fraction() -> float:
	return clampf(float(hp) / float(max_hp), 0.0, 1.0)


## Apply damage; returns the amount actually dealt. Emits `damaged`, and `died`
## exactly once when hp first reaches zero.
func take_damage(amount: int) -> int:
	if amount <= 0 or hp <= 0:
		return 0
	var applied := mini(amount, hp)
	hp -= applied
	damaged.emit(applied, hp)
	if hp <= 0:
		died.emit()
	return applied


func heal(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	hp = mini(max_hp, hp + amount)
