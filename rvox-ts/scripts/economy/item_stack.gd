class_name ItemStack
extends Resource

@export var item_id: StringName
@export var amount: int = 0

func is_empty() -> bool:
    return item_id == &"" or amount <= 0

func add(count: int) -> void:
    amount += max(0, count)

func remove(count: int) -> int:
    var removed := mini(amount, max(0, count))
    amount -= removed
    return removed
