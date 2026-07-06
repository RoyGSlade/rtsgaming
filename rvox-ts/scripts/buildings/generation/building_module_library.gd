@tool
class_name BuildingModuleLibrary
extends RefCounted

## Loads per-building-type WFC module libraries from JSON.
##
## A library describes one building type (hut, blacksmith, keep, ...): its
## block modules with socket/adjacency rules, and its tiers — each tier a
## bounding-volume size range plus the set of modules unlocked at that tier.

const LIBRARY_DIR := "res://data/buildings/module_libraries"


static func list_library_paths(dir_path: String = LIBRARY_DIR) -> PackedStringArray:
	var paths := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			paths.append(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


## Returns the parsed library with "modules_by_id" precomputed and tiers
## sorted by tier number, or {} on failure.
static func load_library(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Module library does not exist: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open module library: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Module library root must be a dictionary: %s" % path)
		return {}

	var library: Dictionary = parsed
	var by_id := {}
	for module in library.get("modules", []):
		by_id[String(module.get("id", ""))] = module
	library["modules_by_id"] = by_id

	var tiers: Array = library.get("tiers", [])
	tiers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("tier", 0)) < int(b.get("tier", 0)))
	library["tiers"] = tiers
	return library


## Structural validation. Pass a loaded BlockRegistry to also verify that
## every module's block_id is a registered block.
static func validate_library(library: Dictionary, block_registry: Object = null) -> PackedStringArray:
	var errors := PackedStringArray()
	var library_id := String(library.get("id", ""))
	if library_id.is_empty():
		errors.append("Library is missing an id.")

	var by_id: Dictionary = library.get("modules_by_id", {})
	if by_id.is_empty():
		errors.append("%s: library has no modules." % library_id)

	for module_id: String in by_id:
		var module: Dictionary = by_id[module_id]
		if (module.get("roles", []) as Array).is_empty():
			errors.append("%s: module '%s' declares no roles." % [library_id, module_id])
		var block_id := String(module.get("block_id", ""))
		if block_id.is_empty():
			errors.append("%s: module '%s' has no block_id." % [library_id, module_id])
		elif block_registry != null and not block_registry.has_block(StringName(block_id)):
			errors.append("%s: module '%s' uses unregistered block '%s'." % [library_id, module_id, block_id])
		for key in ["forbid_h", "forbid_v"]:
			for other in module.get(key, []):
				if not by_id.has(String(other)):
					errors.append("%s: module '%s' %s references unknown module '%s'." % [library_id, module_id, key, other])

	var tiers: Array = library.get("tiers", [])
	if tiers.is_empty():
		errors.append("%s: library has no tiers." % library_id)
	for tier in tiers:
		var tier_number := int(tier.get("tier", -1))
		if tier_number < 1:
			errors.append("%s: tier is missing a positive 'tier' number." % library_id)
		var layout: Dictionary = tier.get("layout", {})
		var layout_type := String(layout.get("type", "box"))
		match layout_type:
			"box":
				var size: Dictionary = tier.get("size", {})
				for axis in ["width", "depth"]:
					var bounds: Array = size.get(axis, [])
					if bounds.is_empty() or int(bounds[0]) < 3:
						errors.append("%s tier %d: %s must be at least 3." % [library_id, tier_number, axis])
				var height_bounds: Array = size.get("wall_height", [])
				if height_bounds.is_empty() or int(height_bounds[0]) < 2:
					errors.append("%s tier %d: wall_height must be at least 2." % [library_id, tier_number])
			"tower":
				pass  # Radius/height are clamped to safe minimums by the generator.
			"castle":
				var court: Dictionary = layout.get("courtyard", {})
				for axis in ["width", "depth"]:
					var bounds: Array = court.get(axis, [])
					if bounds.is_empty() or int(bounds[0]) < 8:
						errors.append("%s tier %d: castle courtyard %s must be at least 8." % [library_id, tier_number, axis])
			_:
				errors.append("%s tier %d: unknown layout type '%s'." % [library_id, tier_number, layout_type])
		var lighting: Dictionary = tier.get("lighting", {})
		for lighting_key in ["wall_torch", "entrance", "courtyard"]:
			var light_block := String(lighting.get(lighting_key, ""))
			if not light_block.is_empty() and block_registry != null and not block_registry.has_block(StringName(light_block)):
				errors.append("%s tier %d: lighting %s uses unregistered block '%s'." % [library_id, tier_number, lighting_key, light_block])
		var unlocked: Array = tier.get("modules", [])
		if unlocked.is_empty():
			errors.append("%s tier %d: unlocks no modules." % [library_id, tier_number])
		var roles_covered := {}
		for module_id in unlocked:
			var module: Dictionary = by_id.get(String(module_id), {})
			if module.is_empty():
				errors.append("%s tier %d: unknown module '%s'." % [library_id, tier_number, module_id])
				continue
			for role in module.get("roles", []):
				roles_covered[String(role)] = true
		for role in ["foundation", "corner", "wall", "floor", "interior", "roof"]:
			if not roles_covered.has(role):
				errors.append("%s tier %d: no module covers role '%s'." % [library_id, tier_number, role])
		if String(tier.get("roof", "pyramid")) == "parapet" and not roles_covered.has("parapet"):
			errors.append("%s tier %d: parapet roof but no parapet-role module." % [library_id, tier_number])
	return errors
