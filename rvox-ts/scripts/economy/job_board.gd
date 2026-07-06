class_name JobBoard
extends RefCounted

## Central job pool with atomic claim/abandon — the gameplan's Priority 2
## (generic job system) and Priority 3 (shared resource movement). Every kind
## of worker task is one job: gather, haul, construct, craft, repair, train,
## fight. A claimed job leaves the open pool, so two workers can never take the
## same job; abandoning returns it to the pool so a stalled task recovers
## instead of vanishing. See DEMO_PLAN.md §4.
##
## Jobs are lightweight Dictionaries so callers can attach whatever payload a
## job type needs (a target node path, a resource id, an amount) without a
## class per type. Every job carries at least:
##   id: int, type: StringName, priority: int, role: StringName (&"" = any),
##   claimed_by: int (-1 = open), data: Dictionary

signal job_posted(job: Dictionary)
signal job_completed(job: Dictionary)
signal job_abandoned(job: Dictionary)

const JOB_TYPES := [&"gather", &"haul", &"construct", &"repair", &"craft", &"train", &"fight"]

var _open: Array[Dictionary] = []
var _claimed: Dictionary = {} # id -> job
var _next_id: int = 1


## Add a job to the open pool. Higher `priority` is served first. `role`
## restricts which workers may claim it (&"" means any worker). Returns the
## new job id.
func post(type: StringName, data: Dictionary = {}, priority: int = 0, role: StringName = &"") -> int:
	var id := _next_id
	_next_id += 1
	var job := {
		"id": id,
		"type": type,
		"priority": priority,
		"role": role,
		"claimed_by": -1,
		"data": data,
	}
	_open.append(job)
	job_posted.emit(job)
	return id


## Claim the highest-priority open job this worker is eligible for. A job with
## a non-empty role is only offered to workers whose `roles` include it.
## Returns the claimed job, or {} if nothing suitable is open. Atomic: the
## returned job is removed from the open pool before this call returns.
func claim_next(worker_id: int, roles: Array = []) -> Dictionary:
	var best_index := -1
	var best_priority := -2147483648
	for i in _open.size():
		var job := _open[i]
		var role: StringName = job["role"]
		if role != &"" and not roles.has(role):
			continue
		if int(job["priority"]) > best_priority:
			best_priority = int(job["priority"])
			best_index = i
	if best_index < 0:
		return {}
	var claimed: Dictionary = _open[best_index]
	_open.remove_at(best_index)
	claimed["claimed_by"] = worker_id
	_claimed[int(claimed["id"])] = claimed
	return claimed


## Mark a claimed job finished; it leaves the board entirely.
func complete(job_id: int) -> bool:
	if not _claimed.has(job_id):
		return false
	var job: Dictionary = _claimed[job_id]
	_claimed.erase(job_id)
	job_completed.emit(job)
	return true


## Return a claimed job to the open pool (worker blocked, reassigned, or
## killed). The recovery path that keeps the economy from silently stalling.
func abandon(job_id: int) -> bool:
	if not _claimed.has(job_id):
		return false
	var job: Dictionary = _claimed[job_id]
	_claimed.erase(job_id)
	job["claimed_by"] = -1
	_open.append(job)
	job_abandoned.emit(job)
	return true


## Abandon every job currently claimed by a worker (used when a worker dies).
func abandon_all_for(worker_id: int) -> int:
	var ids: Array = []
	for id in _claimed.keys():
		if int(_claimed[id]["claimed_by"]) == worker_id:
			ids.append(id)
	for id in ids:
		abandon(id)
	return ids.size()


func open_count() -> int:
	return _open.size()


func claimed_count() -> int:
	return _claimed.size()


func total_count() -> int:
	return _open.size() + _claimed.size()


## Snapshot of open jobs (for the job-board debug view the gameplan asks for
## early — "why is Bob standing in a barrel"). Returns copies so callers can't
## mutate board state.
func open_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for job in _open:
		out.append(job.duplicate(true))
	return out
