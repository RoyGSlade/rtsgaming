class_name ResourceNode
extends RefCounted

## A finite source of one raw resource in the world (a tree cluster, an ore
## vein outcrop, a coal seam). Pure yield/reservation accounting — placement
## and visuals are a separate scene-layer concern, so this stays fully
## unit-testable. See DEMO_PLAN.md §4: resource nodes have finite yields and
## workers reserve before they haul, so two workers never fight over the same
## deposit.

signal depleted

var resource_id: StringName = &""
var total: int = 0
var remaining: int = 0
## Amount promised to workers who have claimed a gather job but not yet
## extracted. available() subtracts this so a second worker can't reserve the
## same units.
var reserved: int = 0
var world_position: Vector3 = Vector3.ZERO


func _init(p_resource_id: StringName = &"", p_amount: int = 0, p_position: Vector3 = Vector3.ZERO) -> void:
	resource_id = p_resource_id
	total = maxi(0, p_amount)
	remaining = total
	world_position = p_position


## Units still free to reserve: what's left minus what's already promised.
func available() -> int:
	return maxi(0, remaining - reserved)


func is_depleted() -> bool:
	return remaining <= 0


## Promise up to `amount` units to a worker. Returns how many were actually
## reserved (may be fewer than requested near depletion).
func reserve(amount: int) -> int:
	var granted := clampi(amount, 0, available())
	reserved += granted
	return granted


## Give back an unused reservation — a worker abandoned the gather job before
## extracting (blocked path, reassigned, killed).
func release(amount: int) -> void:
	reserved = maxi(0, reserved - amount)


## Fulfil a reservation: consume `amount` from the deposit and clear that much
## reservation. Returns the amount actually extracted. Emits `depleted` when
## the deposit runs dry so the world layer can remove/replace the node.
func extract(amount: int) -> int:
	var taken := clampi(amount, 0, remaining)
	remaining -= taken
	reserved = maxi(0, reserved - amount)
	if remaining <= 0:
		remaining = 0
		depleted.emit()
	return taken
