@tool
class_name FunctionalComponentDefinition
extends Resource

@export var id: StringName
@export var display_name := "Component"
@export var category: StringName = &"production"
## Palette display order (ascending); ties break on id. Not simulation state.
@export var sort_order := 0
@export var footprint: Array[Vector3i] = [Vector3i.ZERO]
@export var capabilities: PackedStringArray = []
@export var rule_tags: PackedStringArray = []
@export var ports: Array[Dictionary] = []
@export var construction_recipe_id: StringName
@export var visual_scene: PackedScene
@export var visible_during_simulation := true
@export var keep_as_runtime_node := true
## Palette/hover tint until visual_scene (or a Workshop-crafted mesh) exists.
@export var color := Color.ORANGE
## True when this component only places where SnapResolver finds a
## compatible exposed port (e.g. a furnace chamber must sit on a firebox).
@export var snap_required := false
## Lightweight inline rule-effect hints for the future evaluator, e.g.
## {"channel": "thermal", "effect": "emit", "temperature": 900.0}. Distinct
## from SimulationRuleDefinition, which describes capability-driven rules
## between placed pieces rather than a single component's own emissions.
@export var rules: Array[Dictionary] = []


func has_capability(capability: StringName) -> bool:
	return capability in capabilities
