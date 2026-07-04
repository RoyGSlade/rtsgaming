@tool
class_name ComponentSnapResolver
extends RefCounted


static func rotate_offset(offset: Vector3i, steps: int) -> Vector3i:
	var result := offset
	for _step: int in range(posmod(steps, 4)):
		result = Vector3i(-result.z, result.y, result.x)
	return result


static func rotated_footprint(definition: Dictionary, steps: int) -> Array[Vector3i]:
	var output: Array[Vector3i] = []
	for value: Variant in definition.get("footprint", [[0, 0, 0]]):
		output.append(rotate_offset(_vector3i(value), steps))
	return output


static func can_place(
	document: ForgeDocument,
	origin: Vector3i,
	definition: Dictionary,
	steps: int,
	ignore_component_id := ""
) -> bool:
	var cells := {}
	for offset: Vector3i in rotated_footprint(definition, steps):
		var cell := origin + offset
		cells[ForgeDocument.cell_key(cell)] = true
		if not bool(definition.get("allow_block_overlap", false)) and document.has_block(cell):
			return false
	for component: Dictionary in document.components:
		if str(component.get("id", "")) == ignore_component_id:
			continue
		var component_origin := _vector3i(component.get("pos", [0, 0, 0]))
		var component_definition: Dictionary = component.get("definition", {})
		for offset: Vector3i in rotated_footprint(component_definition, int(component.get("rotation_steps", 0))):
			if cells.has(ForgeDocument.cell_key(component_origin + offset)):
				return false
	return true


static func find_snapped_origin(
	document: ForgeDocument,
	requested: Vector3i,
	new_definition: Dictionary,
	new_steps: int,
	definitions: Array
) -> Dictionary:
	var best := {"found": false, "origin": requested, "distance": 999999.0, "port": ""}
	for existing: Dictionary in document.components:
		var existing_definition := _find_definition(definitions, str(existing.get("component_id", "")))
		var existing_origin := _vector3i(existing.get("pos", [0, 0, 0]))
		var existing_steps := int(existing.get("rotation_steps", 0))
		for old_port: Dictionary in existing_definition.get("ports", []):
			var old_facing := rotate_offset(_vector3i(old_port.get("facing", [0, 0, 1])), existing_steps)
			var old_cell := existing_origin + rotate_offset(_vector3i(old_port.get("cell", [0, 0, 0])), existing_steps)
			for new_port: Dictionary in new_definition.get("ports", []):
				if not _ports_match(old_port, new_port):
					continue
				var new_facing := rotate_offset(_vector3i(new_port.get("facing", [0, 0, -1])), new_steps)
				if new_facing != -old_facing:
					continue
				var local_new := rotate_offset(_vector3i(new_port.get("cell", [0, 0, 0])), new_steps)
				var candidate := old_cell + old_facing - local_new
				var distance := Vector3(candidate).distance_to(Vector3(requested))
				if distance <= 2.25 and distance < float(best["distance"]) and can_place(document, candidate, new_definition, new_steps):
					best = {"found": true, "origin": candidate, "distance": distance, "port": str(old_port.get("type", ""))}
	return best


static func _ports_match(first: Dictionary, second: Dictionary) -> bool:
	var first_type := str(first.get("type", ""))
	var second_type := str(second.get("type", ""))
	var first_accepts: Array = first.get("accepts", [first_type])
	var second_accepts: Array = second.get("accepts", [second_type])
	return second_type in first_accepts and first_type in second_accepts


static func _find_definition(definitions: Array, id: String) -> Dictionary:
	for definition: Dictionary in definitions:
		if str(definition.get("id", "")) == id:
			return definition
	return {}


static func _vector3i(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and value.size() == 3:
		return Vector3i(int(value[0]), int(value[1]), int(value[2]))
	return Vector3i.ZERO
