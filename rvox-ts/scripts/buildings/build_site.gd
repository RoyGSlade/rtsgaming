class_name BuildSite
extends RefCounted

## A building under construction, raised block by block (DEMO_PLAN.md §5, the
## gameplan's "block-built construction" pillar). A builder hauls the material
## for one block from the stockpile, carries it to the site, and places it —
## progress reads "3/5" as the structure rises. Pure logic; the scene layer
## renders a block mesh per `block_placed` and drives a BuilderBrain.

signal block_placed(placed: int, total: int)
signal completed

enum Status { UNDER_CONSTRUCTION, COMPLETE }

var building_id: StringName
var position: Vector3
var total_blocks: int
var placed_blocks: int = 0
## Materials consumed per block placed (e.g. {&"wood": 2}); the builder pulls
## these from the stockpile before carrying the block to the site.
var material_per_block: Dictionary = {}
var status: int = Status.UNDER_CONSTRUCTION


func _init(p_building_id: StringName, p_total_blocks: int, p_material_per_block: Dictionary = {}, p_position: Vector3 = Vector3.ZERO) -> void:
	building_id = p_building_id
	total_blocks = maxi(1, p_total_blocks)
	position = p_position
	for key in p_material_per_block.keys():
		material_per_block[StringName(key)] = int(p_material_per_block[key])


func is_complete() -> bool:
	return status == Status.COMPLETE


## True while there are still blocks left to raise.
func needs_block() -> bool:
	return status != Status.COMPLETE and placed_blocks < total_blocks


func material_for_block() -> Dictionary:
	return material_per_block.duplicate()


## Place one block. Returns true if a block was placed (emitting `block_placed`
## with the new "placed/total"); completes the site on the last block.
func place_block() -> bool:
	if not needs_block():
		return false
	placed_blocks += 1
	block_placed.emit(placed_blocks, total_blocks)
	if placed_blocks >= total_blocks:
		status = Status.COMPLETE
		completed.emit()
	return true


func progress_fraction() -> float:
	return clampf(float(placed_blocks) / float(total_blocks), 0.0, 1.0)
