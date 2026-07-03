@tool
class_name BlueprintSerializer
extends RefCounted

static func save_blueprint_json(path: String, blueprint_data: Dictionary) -> Error:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return FileAccess.get_open_error()
    file.store_string(JSON.stringify(blueprint_data, "  "))
    return OK

static func load_blueprint_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        push_error("Blueprint does not exist: %s" % path)
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("Could not open blueprint: %s" % path)
        return {}
    var parsed := JSON.parse_string(file.get_as_text())
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Blueprint JSON root must be a dictionary: %s" % path)
        return {}
    return parsed
