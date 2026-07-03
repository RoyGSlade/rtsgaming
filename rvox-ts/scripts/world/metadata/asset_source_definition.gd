@tool
class_name AssetSourceDefinition
extends Resource

enum DefinitionKind {
	AUTO,
	BLOCK,
	RESOURCE,
}

@export var id: StringName = &"external_pack"
@export var display_name := "External Asset Pack"
@export_dir var root_path := "res://assets/external"
@export var default_definition_kind := DefinitionKind.AUTO
@export var preferred_model_extensions := PackedStringArray(["glb", "gltf", "fbx", "obj"])
@export_multiline var license_note := ""


func is_valid() -> bool:
	return id != &"" and not root_path.is_empty() and DirAccess.dir_exists_absolute(root_path)
