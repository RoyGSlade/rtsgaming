@tool
class_name ForgeRecipeDefinition
extends Resource

enum ProcessKind { CRAFT_ITEM, ASSEMBLE_COMPONENT, CONSTRUCT, OPERATE, UPGRADE, REPAIR, DECONSTRUCT }

@export var id: StringName
@export var display_name := "Recipe"
@export var process_kind := ProcessKind.CRAFT_ITEM
@export var inputs: Array[Dictionary] = []
@export var outputs: Array[Dictionary] = []
@export var required_capabilities: PackedStringArray = []
@export var required_tools: PackedStringArray = []
@export var worker_roles: PackedStringArray = []
@export var steps: Array[Dictionary] = []
@export var base_duration_seconds := 1.0
@export var preserves_parent_instance := false


func validates_capabilities(available: PackedStringArray) -> bool:
	for capability: String in required_capabilities:
		if capability not in available:
			return false
	return true
