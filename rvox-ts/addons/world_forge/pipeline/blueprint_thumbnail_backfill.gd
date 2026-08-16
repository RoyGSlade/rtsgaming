@tool
extends RefCounted

## Backfills the blueprint browser's thumbnail cache: renders one PNG under
## res://data/buildings/thumbnails/ for every library blueprint JSON that has
## blocks but no thumbnail yet (e.g. the ~100 GrabCraft imports, which are
## scraped straight to JSON and never pass through Save/Export where
## thumbnails are normally rendered).
##
## Shared by the World Forge Pipeline menu ("Generate Missing Thumbnails")
## and the headless CLI runner tools/generate_blueprint_thumbnails.gd.

const ThumbnailRendererScript := preload("res://scripts/rendering/blueprint_thumbnail_renderer.gd")

## Same folders the library browser scans (_scanned_library_entries).
const SCAN_FOLDERS: Array[String] = ["res://data/buildings", "res://data/world_forge"]
const THUMBNAIL_DIR := "res://data/buildings/thumbnails"


## block_colors maps block_id (StringName) -> Color, as built by
## _load_block_palette from each BlockDefinition's albedo_color.
## Returns {"generated": int, "skipped": int, "failed": Array[String]} where
## skipped counts entries that already have a thumbnail or have no blocks.
static func generate_missing(block_colors: Dictionary) -> Dictionary:
	var generated := 0
	var skipped := 0
	var failed: Array[String] = []
	var paths: Array[String] = []
	for folder: String in SCAN_FOLDERS:
		_collect_json(folder, paths)
	paths.sort()
	for path: String in paths:
		var data := _read_json(path)
		var blocks: Array = data.get("blocks", [])
		if blocks.is_empty():
			skipped += 1  # Catalogs/plans without block lists keep their
				# colored placeholder swatch; a blank PNG would be worse.
			continue
		# Same id resolution the library browser uses for thumbnail_path.
		var entry_id := str(data.get("id", path.get_file().get_basename()))
		var out_path := "%s/%s.png" % [THUMBNAIL_DIR, entry_id]
		if FileAccess.file_exists(out_path):
			skipped += 1
			continue
		if ThumbnailRendererScript.render_and_save(blocks, block_colors, out_path):
			generated += 1
		else:
			failed.append(path)
	return {"generated": generated, "skipped": skipped, "failed": failed}


static func _read_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var data: Variant = JSON.parse_string(text)
	return data if data is Dictionary else {}


static func _collect_json(folder: String, output: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file_name: String in DirAccess.get_files_at(folder):
		if file_name.ends_with(".json"):
			output.append(folder.path_join(file_name))
	for child: String in DirAccess.get_directories_at(folder):
		_collect_json(folder.path_join(child), output)
