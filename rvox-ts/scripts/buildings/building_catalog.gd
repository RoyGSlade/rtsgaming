class_name BuildingCatalog
extends RefCounted

## Loads the data-driven building catalog (data/buildings/building_catalog.json)
## that backs the build menu, placement ghosts, and preview panel. Entries stay
## plain Dictionaries straight from JSON per the "data-driven buildings"
## architecture priority — no per-building classes until blueprints are real.
##
## Entry shape:
##   id: String            unique key ("forge")
##   name: String          display name ("Forge")
##   category: String      "core" | "economy" | "military"
##   description: String   one-line tooltip/preview text
##   footprint: [x, z]     size in world blocks
##   height: int           placeholder box height in blocks
##   color: String         hex color for the placeholder mesh
##   cost: Dictionary      resource id -> amount

const CATALOG_PATH := "res://data/buildings/building_catalog.json"

var entries: Array = []


func load_catalog() -> bool:
	entries = []
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("BuildingCatalog: cannot open %s" % CATALOG_PATH)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("buildings"):
		push_error("BuildingCatalog: %s is not a {\"buildings\": [...]} document" % CATALOG_PATH)
		return false
	entries = parsed["buildings"]
	return true


func get_entry(id: String) -> Dictionary:
	for entry in entries:
		if String(entry.get("id", "")) == id:
			return entry
	return {}
