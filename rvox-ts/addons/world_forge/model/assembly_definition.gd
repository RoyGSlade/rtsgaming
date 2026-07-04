@tool
class_name AssemblyDefinition
extends Resource

@export var id: StringName
@export var display_name := "Assembly"
@export var required_pieces: Array[Dictionary] = []
@export var optional_pieces: Array[Dictionary] = []
@export var construction_stages: Array[Dictionary] = []
@export var granted_capabilities: PackedStringArray = []
@export var required_clearance: Array[Vector3i] = []
@export var rules: Array[Resource] = []


func required_piece_count() -> int:
	var total := 0
	for piece: Dictionary in required_pieces:
		total += int(piece.get("amount", 1))
	return total
