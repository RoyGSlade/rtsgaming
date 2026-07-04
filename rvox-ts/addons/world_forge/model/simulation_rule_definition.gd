@tool
class_name SimulationRuleDefinition
extends Resource

enum Trigger { PLACED, REMOVED, STATE_CHANGED, NEIGHBOR_CHANGED, SIMULATION_TICK, RECIPE_STEP }
enum Scope { SELF, ADJACENT, CONNECTED_NETWORK, ASSEMBLY }

@export var id: StringName
@export var display_name := "Simulation Rule"
@export var trigger := Trigger.STATE_CHANGED
@export var scope := Scope.ADJACENT
@export var priority := 0
@export var required_source_tags: PackedStringArray = []
@export var required_target_tags: PackedStringArray = []
@export var conditions: Array[Dictionary] = []
@export var effects: Array[Dictionary] = []
@export var debug_description := ""


func can_consider(source_tags: PackedStringArray, target_tags: PackedStringArray) -> bool:
	for tag: String in required_source_tags:
		if tag not in source_tags:
			return false
	for tag: String in required_target_tags:
		if tag not in target_tags:
			return false
	return true
