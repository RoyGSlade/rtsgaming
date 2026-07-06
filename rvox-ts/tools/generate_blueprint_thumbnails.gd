extends SceneTree

## Headless backfill of blueprint browser thumbnails. Safe under --headless:
## BlueprintThumbnailRenderer is pure Image pixel work, no viewport/GPU.
##
##   godot --headless --path rvox-ts --script res://tools/generate_blueprint_thumbnails.gd
##
## Exits non-zero if any blueprint failed to render, so it can gate CI.

const BackfillScript := preload("res://addons/world_forge/pipeline/blueprint_thumbnail_backfill.gd")
const BlockRegistryScript := preload("res://scripts/world/metadata/block_registry.gd")


func _init() -> void:
	var registry: Node = BlockRegistryScript.new()
	registry.load_blocks()
	var block_colors := {}
	for block_id: StringName in registry.list_ids():
		block_colors[block_id] = registry.get_block(block_id).albedo_color
	registry.free()

	var report: Dictionary = BackfillScript.generate_missing(block_colors)
	var failed: Array = report["failed"]
	print("Thumbnails: %d generated, %d skipped (existing or blockless), %d failed" % [
		report["generated"], report["skipped"], failed.size(),
	])
	for path: String in failed:
		printerr("  failed: %s" % path)
	quit(1 if not failed.is_empty() else 0)
