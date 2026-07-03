class_name StorageInventory
extends Node

@export var capacity_per_item: int = 100
var items: Dictionary = {}

func get_amount(item_id: StringName) -> int:
    return int(items.get(item_id, 0))

func can_add(item_id: StringName, amount: int) -> bool:
    return get_amount(item_id) + amount <= capacity_per_item

func add_item(item_id: StringName, amount: int) -> int:
    var current := get_amount(item_id)
    var accepted := mini(amount, capacity_per_item - current)
    items[item_id] = current + accepted
    return accepted

func remove_item(item_id: StringName, amount: int) -> int:
    var current := get_amount(item_id)
    var removed := mini(current, amount)
    items[item_id] = current - removed
    return removed

func has_items(requirements: Dictionary) -> bool:
    for key in requirements.keys():
        if get_amount(StringName(key)) < int(requirements[key]):
            return false
    return true
