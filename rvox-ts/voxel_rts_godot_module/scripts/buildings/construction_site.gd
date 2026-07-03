class_name ConstructionSite
extends Node3D

signal block_built(block_index: int, block_data: Dictionary)
signal construction_completed()

@export var blueprint: BuildingBlueprint

var placed_block_indices: Dictionary = {}
var construction_jobs: Array[Dictionary] = []
var assigned_workers: Array[Node] = []
var status: StringName = &"planned"

func initialize_from_blueprint(p_blueprint: BuildingBlueprint) -> void:
    blueprint = p_blueprint
    placed_block_indices.clear()
    _build_job_queue()
    status = &"planned"

func _build_job_queue() -> void:
    construction_jobs.clear()
    if blueprint == null:
        return

    var stage_order := blueprint.get_build_stage_order()
    for stage in stage_order:
        for i in blueprint.blocks.size():
            var block := blueprint.blocks[i]
            if StringName(block.get("build_stage", "decoration")) != stage:
                continue
            construction_jobs.append({
                "job_type": "build_block",
                "block_index": i,
                "block_id": block.get("block_id", ""),
                "stage": String(stage),
                "pos": block.get("pos", [0, 0, 0]),
                "assigned": false,
                "completed": false
            })

func get_next_available_job() -> Dictionary:
    for job in construction_jobs:
        if not bool(job.get("assigned", false)) and not bool(job.get("completed", false)):
            job["assigned"] = true
            return job
    return {}

func mark_job_completed(block_index: int) -> void:
    if blueprint == null:
        return
    placed_block_indices[block_index] = true
    for job in construction_jobs:
        if int(job.get("block_index", -1)) == block_index:
            job["completed"] = true
            break
    emit_signal("block_built", block_index, blueprint.blocks[block_index])
    if is_complete():
        status = &"complete"
        emit_signal("construction_completed")

func is_complete() -> bool:
    if blueprint == null:
        return false
    return placed_block_indices.size() >= blueprint.blocks.size()

func get_completion_percent() -> float:
    if blueprint == null or blueprint.blocks.is_empty():
        return 0.0
    return float(placed_block_indices.size()) / float(blueprint.blocks.size())

func get_required_block_counts_remaining() -> Dictionary:
    var counts := {}
    if blueprint == null:
        return counts
    for i in blueprint.blocks.size():
        if placed_block_indices.has(i):
            continue
        var block_id := StringName(blueprint.blocks[i].get("block_id", ""))
        counts[block_id] = counts.get(block_id, 0) + 1
    return counts
