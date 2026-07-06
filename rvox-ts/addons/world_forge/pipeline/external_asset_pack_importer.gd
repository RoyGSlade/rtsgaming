@tool
class_name ExternalAssetPackImporter
extends RefCounted

const BLOCK_OUTPUT := "res://data/blocks/generated"
const RESOURCE_OUTPUT := "res://data/resources/generated"
const SUPPORTED_EXTENSIONS := ["glb", "gltf", "fbx", "obj", "png"]
const MODEL_RANK := {
	"glb": 0,
	"gltf": 1,
	"fbx": 2,
	"obj": 3,
	"png": 4,
}


func import_folder(
	folder_path: String,
	source: AssetSourceDefinition,
	allow_overwrite := false
) -> Dictionary:
	var report := _new_report(folder_path, source)
	if source == null:
		report.errors.append("Asset source definition is null")
		return report
	if not DirAccess.dir_exists_absolute(folder_path):
		report.errors.append("Asset folder does not exist: %s" % folder_path)
		return report

	_ensure_output_directories()
	var candidates := _collect_candidates(folder_path)
	var keys: Array = candidates.keys()
	keys.sort()
	for key: String in keys:
		_import_candidate(candidates[key], source, allow_overwrite, report)
	return report


func import_source(source: AssetSourceDefinition, allow_overwrite := false) -> Dictionary:
	if source == null:
		return _new_report("", null)
	return import_folder(source.root_path, source, allow_overwrite)


func _collect_candidates(folder_path: String) -> Dictionary:
	var files: Array[String] = []
	_collect_files_recursive(folder_path, files)
	var candidates := {}
	for path in files:
		var extension := path.get_extension().to_lower()
		if extension not in SUPPORTED_EXTENSIONS:
			continue
		var key := _canonical_asset_key(path, folder_path)
		var current_path: String = candidates.get(key, "")
		if current_path.is_empty() or _format_rank(path) < _format_rank(current_path):
			candidates[key] = path
	return candidates


func _collect_files_recursive(folder_path: String, output: Array[String]) -> void:
	var directory := DirAccess.open(folder_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var path := folder_path.path_join(entry)
			if directory.current_is_dir():
				_collect_files_recursive(path, output)
			else:
				output.append(path)
		entry = directory.get_next()
	directory.list_dir_end()


func _import_candidate(
	asset_path: String,
	source: AssetSourceDefinition,
	allow_overwrite: bool,
	report: Dictionary
) -> void:
	var definition_kind := _guess_definition_kind(asset_path, source)
	var category := _guess_category(asset_path)
	var definition_id := _make_definition_id(asset_path, source)
	var output_folder := BLOCK_OUTPUT if definition_kind == AssetSourceDefinition.DefinitionKind.BLOCK else RESOURCE_OUTPUT
	var output_path := output_folder.path_join("%s.tres" % definition_id)
	var existed := ResourceLoader.exists(output_path)
	if existed and not allow_overwrite:
		report.skipped += 1
		report.skipped_paths.append(output_path)
		return

	var extension := asset_path.get_extension().to_lower()
	var mesh_scene: PackedScene = null
	var preview_icon: Texture2D = null
	if extension == "png":
		preview_icon = load(asset_path) as Texture2D
	else:
		mesh_scene = _load_as_packed_scene(asset_path)

	var definition: Resource
	if definition_kind == AssetSourceDefinition.DefinitionKind.BLOCK:
		definition = _make_block_definition(definition_id, asset_path, category, source, mesh_scene, preview_icon)
	else:
		definition = _make_resource_definition(definition_id, asset_path, category, source, mesh_scene, preview_icon)

	var error := ResourceSaver.save(definition, output_path)
	if error != OK:
		report.failed += 1
		report.errors.append("%s: %s" % [asset_path, error_string(error)])
		return
	if existed:
		report.updated += 1
	else:
		report.created += 1
	report.generated_paths.append(output_path)


func _make_block_definition(
	definition_id: String,
	asset_path: String,
	category: StringName,
	source: AssetSourceDefinition,
	packed_scene: PackedScene,
	icon: Texture2D
) -> BlockDefinition:
	var definition := BlockDefinition.new()
	definition.id = StringName(definition_id)
	definition.display_name = _display_name(asset_path)
	definition.category = category
	definition.solid = category not in [&"fluid", &"foliage", &"decoration"]
	definition.transparent = category in [&"fluid", &"foliage"] or "glass" in asset_path.to_lower()
	definition.walkable = category in [&"terrain", &"floor"]
	definition.buildable = category not in [&"character", &"item", &"fluid"]
	definition.diggable = category in [&"terrain", &"ore"]
	definition.mesh_scene = packed_scene
	definition.preview_icon = icon
	definition.source_pack = String(source.id)
	definition.license_note = source.license_note
	definition.set_meta("source_asset_path", asset_path)
	return definition


func _make_resource_definition(
	definition_id: String,
	asset_path: String,
	category: StringName,
	source: AssetSourceDefinition,
	packed_scene: PackedScene,
	icon: Texture2D
) -> ResourceDefinition:
	var definition := ResourceDefinition.new()
	definition.id = StringName(definition_id)
	definition.display_name = _display_name(asset_path)
	definition.category = category
	definition.mesh_scene = packed_scene
	definition.preview_icon = icon
	definition.source_pack = String(source.id)
	definition.license_note = source.license_note
	definition.set_meta("source_asset_path", asset_path)
	return definition


func _load_as_packed_scene(asset_path: String) -> PackedScene:
	var loaded := load(asset_path)
	if loaded is PackedScene:
		return loaded
	if loaded is Mesh:
		var root := Node3D.new()
		root.name = _display_name(asset_path).validate_node_name()
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mesh"
		mesh_instance.mesh = loaded
		root.add_child(mesh_instance)
		mesh_instance.owner = root
		var packed := PackedScene.new()
		var error := packed.pack(root)
		root.free()
		return packed if error == OK else null
	return null


func _guess_definition_kind(asset_path: String, source: AssetSourceDefinition) -> int:
	if source.default_definition_kind != AssetSourceDefinition.DefinitionKind.AUTO:
		return source.default_definition_kind
	var value := asset_path.to_lower()
	var resource_tokens := [
		"resourcebits", "/items/", "/characters/", "barrel", "jerrycan", "nugget",
		"bars", "parts", "textile", "pallet", "plank", "log", "weapon", "tool",
	]
	for token in resource_tokens:
		if token in value:
			return AssetSourceDefinition.DefinitionKind.RESOURCE
	return AssetSourceDefinition.DefinitionKind.BLOCK


func _guess_category(asset_path: String) -> StringName:
	var value := asset_path.to_lower()
	var rules := {
		"character": ["/characters/", "alien", "zombie", "skeleton", "gnome", "player_"],
		"item": ["/items/", "bar", "parts", "textile", "pallet", "tool", "weapon", "axe", "sword", "pickaxe"],
		"ore": ["_ore", "copper", "gold", "silver", "iron", "coal", "nugget"],
		"fluid": ["water", "lava", "fuel"],
		"foliage": ["tree", "leaves", "flower", "bush"],
		"terrain": ["dirt", "grass", "sand", "snow", "stone", "gravel", "/tiles/"],
		"construction": ["brick", "wood", "plank", "roof", "wall", "floor", "metal", "glass"],
		"effect": ["/particles/"],
	}
	for category: String in rules:
		for token: String in rules[category]:
			if token in value:
				return StringName(category)
	return &"decoration"


func _canonical_asset_key(asset_path: String, folder_path: String) -> String:
	var relative := asset_path.trim_prefix(folder_path).trim_prefix("/").to_lower()
	for format_folder in ["/gltf/", "/fbx/", "/fbx(unity)/", "/obj/"]:
		relative = relative.replace(format_folder, "/")
	return relative.get_basename()


func _make_definition_id(asset_path: String, source: AssetSourceDefinition) -> String:
	var source_prefix := _slug(String(source.id))
	var stem := _slug(asset_path.get_file().get_basename())
	return "%s_%s" % [source_prefix, stem]


func _slug(value: String) -> String:
	var result := value.to_snake_case().to_lower()
	var valid := "abcdefghijklmnopqrstuvwxyz0123456789_"
	var filtered := ""
	for character in result:
		if character in valid:
			filtered += character
	while "__" in filtered:
		filtered = filtered.replace("__", "_")
	return filtered.trim_prefix("_").trim_suffix("_")


func _display_name(asset_path: String) -> String:
	return asset_path.get_file().get_basename().replace("_", " ").capitalize()


func _format_rank(path: String) -> int:
	return int(MODEL_RANK.get(path.get_extension().to_lower(), 99))


func _ensure_output_directories() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BLOCK_OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RESOURCE_OUTPUT))


func _new_report(folder_path: String, source: AssetSourceDefinition) -> Dictionary:
	return {
		"source": String(source.id) if source != null else "",
		"folder": folder_path,
		"created": 0,
		"updated": 0,
		"skipped": 0,
		"failed": 0,
		"generated_paths": PackedStringArray(),
		"skipped_paths": PackedStringArray(),
		"errors": PackedStringArray(),
	}
