class_name WorkerConstructionAgent
extends Node

signal job_started(job: Dictionary)
signal job_finished(job: Dictionary)

@export var build_seconds_per_block: float = 1.5
@export var haul_seconds_per_block: float = 1.0

var construction_site: ConstructionSite
var current_job: Dictionary = {}
var busy: bool = false

func assign_site(site: ConstructionSite) -> void:
    construction_site = site

func start_next_job() -> void:
    if busy or construction_site == null:
        return
    current_job = construction_site.get_next_available_job()
    if current_job.is_empty():
        return
    busy = true
    emit_signal("job_started", current_job)
    _simulate_job()

func _simulate_job() -> void:
    # This is intentionally fake movement for the first vertical slice.
    # Later replace this with pathfinding: storage → construction site → block position.
    await get_tree().create_timer(haul_seconds_per_block + build_seconds_per_block).timeout
    var block_index := int(current_job.get("block_index", -1))
    if block_index >= 0 and construction_site:
        construction_site.mark_job_completed(block_index)
    emit_signal("job_finished", current_job)
    current_job = {}
    busy = false
    start_next_job()
