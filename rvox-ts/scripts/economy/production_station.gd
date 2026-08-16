class_name ProductionStation
extends RefCounted

## A building that turns inputs into outputs over time — the "buildings are
## machines" pillar. Holds its own input and output inventories and one active
## recipe. Inputs are consumed when a craft starts; outputs are deposited when
## it finishes. If the output store is full at completion the finished goods
## are held in `_pending_output` and re-deposited on later ticks, so nothing is
## ever silently destroyed. See DEMO_PLAN.md §4 and the gameplan Phase 6.

signal production_started(recipe_id: StringName)
signal production_finished(recipe_id: StringName, outputs: Dictionary)
signal production_blocked(reason: String)

var station_id: StringName = &""
var recipe: RecipeDefinition
var input: StorageInventory
var output: StorageInventory

var _active: bool = false
var _progress: float = 0.0
## Finished goods that didn't fit in `output` yet; drained before a new craft.
var _pending_output: Dictionary = {}


func _init(p_station_id: StringName = &"", p_recipe: RecipeDefinition = null, p_capacity: int = 100) -> void:
	station_id = p_station_id
	recipe = p_recipe
	input = StorageInventory.new()
	input.capacity_per_item = p_capacity
	output = StorageInventory.new()
	output.capacity_per_item = p_capacity


## StorageInventory extends Node, so the two we own must be freed explicitly
## when this RefCounted station is released — otherwise they orphan.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if is_instance_valid(input) and input.get_parent() == null:
			input.free()
		if is_instance_valid(output) and output.get_parent() == null:
			output.free()


func is_active() -> bool:
	return _active


func progress_fraction() -> float:
	if recipe == null or recipe.duration_seconds <= 0.0:
		return 1.0 if _active else 0.0
	return clampf(_progress / recipe.duration_seconds, 0.0, 1.0)


## True when every input is present and the outputs will fit. Also false while
## a craft is already running or finished goods are still waiting to deposit.
func can_start() -> bool:
	if recipe == null or _active or not _pending_output.is_empty():
		return false
	if not input.has_items(recipe.inputs):
		return false
	return _outputs_fit(recipe.outputs)


## Begin a craft: consume inputs immediately and start the timer. Returns false
## (with a `production_blocked` reason) if it couldn't start.
func start() -> bool:
	if recipe == null:
		production_blocked.emit("no recipe assigned")
		return false
	if _active:
		return false
	if not _pending_output.is_empty():
		production_blocked.emit("output backed up")
		return false
	if not input.has_items(recipe.inputs):
		production_blocked.emit("missing inputs")
		return false
	if not _outputs_fit(recipe.outputs):
		production_blocked.emit("output full")
		return false
	for item_key in recipe.inputs.keys():
		input.remove_item(StringName(item_key), int(recipe.inputs[item_key]))
	_active = true
	_progress = 0.0
	production_started.emit(recipe.id)
	return true


## Advance the active craft. Returns true on the tick a craft completes.
## Always first tries to drain any backed-up output so a station un-jams once a
## hauler frees space.
func tick(delta: float) -> bool:
	_drain_pending()
	if not _active:
		return false
	_progress += delta
	if _progress < recipe.duration_seconds:
		return false
	_active = false
	_progress = 0.0
	for item_key in recipe.outputs.keys():
		_pending_output[StringName(item_key)] = int(_pending_output.get(StringName(item_key), 0)) + int(recipe.outputs[item_key])
	_drain_pending()
	production_finished.emit(recipe.id, recipe.outputs.duplicate())
	return true


## Move as much pending output as fits into the output store.
func _drain_pending() -> void:
	if _pending_output.is_empty():
		return
	var cleared: Array = []
	for item_id in _pending_output.keys():
		var want := int(_pending_output[item_id])
		var moved := output.add_item(item_id, want)
		if moved >= want:
			cleared.append(item_id)
		elif moved > 0:
			_pending_output[item_id] = want - moved
	for item_id in cleared:
		_pending_output.erase(item_id)


func _outputs_fit(outputs: Dictionary) -> bool:
	for item_key in outputs.keys():
		if not output.can_add(StringName(item_key), int(outputs[item_key])):
			return false
	return true
