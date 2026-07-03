class_name BuildingBlueprintLoader
extends RefCounted

static func load_from_json(path: String) -> BuildingBlueprint:
    if not FileAccess.file_exists(path):
        push_error("Blueprint JSON does not exist: %s" % path)
        return null
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Could not open blueprint JSON: %s" % path)
        return null
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Blueprint JSON root must be a dictionary: %s" % path)
        return null

    var blueprint := BuildingBlueprint.new()
    blueprint.id = StringName(parsed.get("id", "unknown_building"))
    blueprint.display_name = parsed.get("display_name", "Unknown Building")
    blueprint.category = StringName(parsed.get("category", "production"))
    blueprint.era = StringName(parsed.get("era", "village"))
    var footprint_arr: Array = parsed.get("footprint", [1, 1])
    blueprint.footprint = Vector2i(int(footprint_arr[0]), int(footprint_arr[1]))
    blueprint.health = int(parsed.get("health", 100))
    blueprint.workers_required = int(parsed.get("workers_required", 1))

    blueprint.blocks = _array_of_dicts(parsed.get("blocks", []))
    blueprint.sockets = _array_of_dicts(parsed.get("sockets", []))
    blueprint.storage_slots = _array_of_dicts(parsed.get("storage_slots", []))
    blueprint.recipes = _array_of_dicts(parsed.get("recipes", []))

    var required_tags := PackedStringArray()
    for tag in parsed.get("required_functional_tags", []):
        required_tags.append(String(tag))
    blueprint.required_functional_tags = required_tags
    return blueprint

static func _array_of_dicts(value: Variant) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if typeof(value) != TYPE_ARRAY:
        return result
    for item in value:
        if typeof(item) == TYPE_DICTIONARY:
            result.append(item)
    return result
