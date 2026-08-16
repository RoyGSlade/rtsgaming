@tool
class_name ForgeDocument
extends RefCounted

signal changed

const FORMAT_VERSION := 3
## World-unit size of one Workshop fine-grid cell (plan section 2: 1/8 of a
## structure cell). Canonical home for this value - PartProfile's
## occupancy_for_box/occupancy_for_cylinder default to the same 0.125
## independently since a bare PartProfile resource has no document to read
## it from; both describe the same grid.
const FINE_CELL_SIZE := 0.125

var document_id := "new_blueprint"
var display_name := "New Blueprint"
## Free-form, matching the existing purposes (building, assembly, encounter,
## ruin, generation_template, interior_assembly) - "part_assembly" is the
## new Workshop purpose from plan section 2: a single crafted component
## (furnace, catapult, chair) built from stock parts on the fine grid rather
## than a structure built from blocks on the 1m grid.
var template_kind := "building"
## Which module library this building belongs to (hut, blacksmith, keep,
## castle, ...), independent of template_kind (the document's purpose).
## Set automatically when generated via WFC; "custom" for hand-built
## documents until the author picks one from the Building Type dropdown.
var building_type := "custom"
var blocks: Dictionary = {} # "x,y,z" -> placed block data
var components: Array[Dictionary] = []
var markers: Array[Dictionary] = []
var nested_instances: Array[Dictionary] = []
## Workshop-scale placed parts: "x,y,z" (fine-grid cell, same key format as
## blocks) -> {pos, part_id, rotation_steps, joints, pos_exact?}. Only
## meaningful when template_kind == "part_assembly"; empty on every
## structure-scale document. The dictionary key is a spatial BUCKET, not
## necessarily the authoritative position: a part placed via
## PartSnapResolver's socket alignment (Step 6) will essentially never land
## exactly on a fine-grid cell, so such parts additionally carry
## `pos_exact` (a continuous float [x,y,z]) which is authoritative when
## present - see placed_part_world_position(). Parts placed without a snap
## (set_placed_part) have no pos_exact and are rendered at their quantized
## cell, matching Step 5's original behavior exactly.
var placed_parts: Dictionary = {}
var metadata: Dictionary = {
	"simulation_rules": [],
	"generation_tags": [],
	"resource_nodes": [],
}

var _batch_depth := 0
var _change_pending := false


func begin_batch() -> void:
	_batch_depth += 1


func end_batch() -> void:
	_batch_depth = maxi(0, _batch_depth - 1)
	if _batch_depth == 0 and _change_pending:
		_change_pending = false
		changed.emit()


func notify_changed() -> void:
	if _batch_depth > 0:
		_change_pending = true
	else:
		changed.emit()


static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


static func key_cell(key: String) -> Vector3i:
	var parts := key.split(",")
	if parts.size() != 3:
		return Vector3i.ZERO
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))


func has_block(cell: Vector3i) -> bool:
	return blocks.has(cell_key(cell))


func get_block(cell: Vector3i) -> Dictionary:
	return blocks.get(cell_key(cell), {})


func set_block(cell: Vector3i, block_data: Dictionary) -> void:
	var data := block_data.duplicate(true)
	data["pos"] = [cell.x, cell.y, cell.z]
	data["kind"] = "block"
	blocks[cell_key(cell)] = data
	notify_changed()


func erase_block(cell: Vector3i) -> void:
	if blocks.erase(cell_key(cell)):
		notify_changed()


func has_placed_part(cell: Vector3i) -> bool:
	return placed_parts.has(cell_key(cell))


func get_placed_part(cell: Vector3i) -> Dictionary:
	return placed_parts.get(cell_key(cell), {})


func set_placed_part(cell: Vector3i, part_data: Dictionary) -> void:
	var data := part_data.duplicate(true)
	data["pos"] = [cell.x, cell.y, cell.z]
	data["kind"] = "placed_part"
	placed_parts[cell_key(cell)] = data
	notify_changed()


## Nearest fine-grid cell to a continuous world position - the bucket key
## set_placed_part_at stores under. Rounds rather than floors (unlike
## structure-cell block picking) since this is just a spatial bucket, not
## the part's actual position.
static func cell_for_position(position: Vector3) -> Vector3i:
	return Vector3i(
		roundi(position.x / FINE_CELL_SIZE),
		roundi(position.y / FINE_CELL_SIZE),
		roundi(position.z / FINE_CELL_SIZE),
	)


## Places a part at a continuous world position rather than a quantized
## fine-grid cell - used when PartSnapResolver finds a precise socket
## alignment (Step 6), which will essentially never land exactly on a fine
## cell. Still keyed by the nearest cell so placed_parts stays one spatial
## dictionary, but that key is a bucket, not the authoritative position:
## `pos_exact` is (see placed_part_world_position). Returns the bucket cell
## used, so a caller that also needs the key doesn't recompute the rounding.
func set_placed_part_at(position: Vector3, part_data: Dictionary) -> Vector3i:
	var cell := cell_for_position(position)
	var data := part_data.duplicate(true)
	data["pos"] = [cell.x, cell.y, cell.z]
	data["pos_exact"] = [position.x, position.y, position.z]
	data["kind"] = "placed_part"
	placed_parts[cell_key(cell)] = data
	notify_changed()
	return cell


## The world position a placed part should actually render/snap-search at:
## `pos_exact` when present (a precisely-snapped part), otherwise its
## quantized fine-grid cell (`pos`) times FINE_CELL_SIZE - Step 5's original
## behavior for parts placed without a snap.
static func placed_part_world_position(part_data: Dictionary) -> Vector3:
	if part_data.has("pos_exact"):
		var exact: Array = part_data["pos_exact"]
		return Vector3(float(exact[0]), float(exact[1]), float(exact[2]))
	var cell_pos: Array = part_data.get("pos", [0, 0, 0])
	return Vector3(float(cell_pos[0]), float(cell_pos[1]), float(cell_pos[2])) * FINE_CELL_SIZE


func erase_placed_part(cell: Vector3i) -> void:
	if placed_parts.erase(cell_key(cell)):
		notify_changed()


func clear() -> void:
	blocks.clear()
	components.clear()
	markers.clear()
	nested_instances.clear()
	placed_parts.clear()
	metadata = {"simulation_rules": [], "generation_tags": [], "resource_nodes": []}
	notify_changed()


func snapshot() -> Dictionary:
	return to_dictionary().duplicate(true)


func restore_snapshot(data: Dictionary) -> void:
	_load_dictionary(data)
	notify_changed()


func to_dictionary() -> Dictionary:
	var block_list: Array[Dictionary] = []
	var keys := blocks.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var ac := key_cell(a)
		var bc := key_cell(b)
		if ac.y != bc.y: return ac.y < bc.y
		if ac.z != bc.z: return ac.z < bc.z
		return ac.x < bc.x
	)
	for key: String in keys:
		block_list.append((blocks[key] as Dictionary).duplicate(true))
	var part_list: Array[Dictionary] = []
	var part_keys := placed_parts.keys()
	part_keys.sort_custom(func(a: String, b: String) -> bool:
		var ac := key_cell(a)
		var bc := key_cell(b)
		if ac.y != bc.y: return ac.y < bc.y
		if ac.z != bc.z: return ac.z < bc.z
		return ac.x < bc.x
	)
	for key: String in part_keys:
		part_list.append((placed_parts[key] as Dictionary).duplicate(true))
	return {
		"format_version": FORMAT_VERSION,
		"id": document_id,
		"display_name": display_name,
		"template_kind": template_kind,
		"building_type": building_type,
		"blocks": block_list,
		"components": components.duplicate(true),
		"markers": markers.duplicate(true),
		"nested_instances": nested_instances.duplicate(true),
		"placed_parts": part_list,
		"metadata": metadata.duplicate(true),
	}


func save_json(path: String) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dictionary(), "  "))
	return OK


static func load_json(path: String) -> ForgeDocument:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return null
	var result := ForgeDocument.new()
	result._load_dictionary(parsed)
	return result


func _load_dictionary(data: Dictionary) -> void:
	document_id = str(data.get("id", data.get("blueprint_id", "new_blueprint")))
	display_name = str(data.get("display_name", document_id.replace("_", " ").capitalize()))
	template_kind = str(data.get("template_kind", data.get("category", "building")))
	# Exported BuildingBlueprint JSON has no explicit building_type field but
	# does carry generator.library when WFC-made; fall back to that so
	# opening an exported file for editing still shows the right type.
	var generator_variant: Variant = data.get("generator", {})
	var inferred_type := str(generator_variant.get("library", "custom")) if generator_variant is Dictionary else "custom"
	building_type = str(data.get("building_type", inferred_type))
	blocks.clear()
	for item: Variant in data.get("blocks", []):
		if not item is Dictionary:
			continue
		var block: Dictionary = item.duplicate(true)
		var pos: Array = block.get("pos", block.get("position", [0, 0, 0]))
		if pos.size() != 3:
			continue
		var cell := Vector3i(int(pos[0]), int(pos[1]), int(pos[2]))
		block["pos"] = [cell.x, cell.y, cell.z]
		block["kind"] = "block"
		blocks[cell_key(cell)] = block
	components = _dictionary_array(data.get("components", []))
	markers = _dictionary_array(data.get("markers", []))
	nested_instances = _dictionary_array(data.get("nested_instances", []))
	placed_parts.clear()
	for item: Variant in data.get("placed_parts", []):
		if not item is Dictionary:
			continue
		var part: Dictionary = item.duplicate(true)
		var pos: Array = part.get("pos", part.get("position", [0, 0, 0]))
		if pos.size() != 3:
			continue
		var cell := Vector3i(int(pos[0]), int(pos[1]), int(pos[2]))
		part["pos"] = [cell.x, cell.y, cell.z]
		part["kind"] = "placed_part"
		placed_parts[cell_key(cell)] = part
	var loaded_metadata: Variant = data.get("metadata", {})
	metadata = loaded_metadata.duplicate(true) if loaded_metadata is Dictionary else {}
	metadata.get_or_add("simulation_rules", [])
	metadata.get_or_add("generation_tags", [])
	metadata.get_or_add("resource_nodes", [])


static func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	if value is Array:
		for item: Variant in value:
			if item is Dictionary:
				output.append(item.duplicate(true))
	return output
