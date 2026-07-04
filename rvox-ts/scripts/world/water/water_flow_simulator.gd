class_name WaterFlowSimulator
extends RefCounted

## Tick-based cellular-automaton water flow: water spawns at seeded source
## voxels, flows downward (gravity takes priority over spreading sideways),
## and a flowing voxel that's been stationary long enough and is surrounded
## by enough other water solidifies into a permanent source. State lives
## here rather than on ChunkData - this is an active simulation service
## operating on a passive `chunk` argument, matching how WorldGenerator/
## LakeGenerator/etc. already work.
##
## Only active cells are ever processed (see `_active_queue`): once nothing
## is changing, the queue drains to empty and tick() is a no-op, which is
## what keeps "continuous simulation" cheap at steady state. A future
## mining feature wakes the simulation back up near a change by calling
## `notify_block_changed()`.
##
## Sideways spread is budget-limited (see MAX_FLOW_DISTANCE) the same way
## Minecraft's water works: each hop away from a source costs one unit,
## falling is free. This is what makes it safe for a generator to seed
## densely across a feature's whole footprint (a lake's every cell, a
## river's every carved step, every below-sea-level column) without first
## proving the area is perfectly enclosed - an unnoticed gap in the terrain
## only leaks a few cells past the seed, never floods the map.
##
## Correctness note: tick() computes every move from a frozen snapshot of
## the active queue, then applies them all in a second pass. Reading/
## writing chunk state mid-iteration would let two adjacent cells "trade"
## the same slot within one tick (cell A drains down, freeing its old
## spot; cell B spreads into that freed spot; meanwhile A gets refilled
## from above) which can oscillate forever - snapshot-then-apply avoids
## that class of bug entirely.

const HORIZONTAL_DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const STATIONARY_TICKS_TO_SOURCE := 60
# 3x3x3 Moore neighborhood minus self = 26 cells. A 6-face-adjacent count
# could never reach a threshold of 9, so this needs the full neighborhood -
# it reads as "roughly a third of the surrounding space is wet," which is
# also more forgiving of a single air pocket at a shoreline edge than a
# stricter 6-neighbor "fully surrounded" test would be.
const SOURCE_CONVERSION_THRESHOLD := 9
# Sideways spread costs one hop of this budget per step (falling is free,
# matching the source Minecraft mechanic this is modeled on); a flowing
# voxel that's used up its budget can still fall further but stops
# spreading sideways. This is what makes seeding safe even when a
# generator can't prove a basin/channel is fully enclosed - a leak through
# an unnoticed gap is bounded to a few cells past the seed, never an
# unbounded flood across the map, regardless of terrain topology.
const MAX_FLOW_DISTANCE := 4

var _sources: Dictionary = {} # Vector3i -> true
var _flowing: Dictionary = {} # Vector3i -> int (ticks_stationary)
var _flow_distance: Dictionary = {} # Vector3i -> int, sideways hops from the nearest source
var _active_queue: Dictionary = {} # Vector3i -> true, cells to evaluate next tick
var _dirty_columns: Dictionary = {} # Vector2i -> true, since last pop_dirty_columns()
var _column_water_y: Dictionary = {} # Vector2i -> Dictionary[int, true], y's that are water


func seed_source(chunk: ChunkData, pos: Vector3i) -> void:
	if not chunk.is_in_bounds(pos.x, pos.y, pos.z):
		return
	if chunk.get_block(pos.x, pos.y, pos.z) != &"air":
		return
	_sources[pos] = true
	chunk.set_block(pos.x, pos.y, pos.z, &"water")
	_add_water_column_entry(pos)
	_mark_column_dirty(pos)
	_active_queue[pos] = true


## Runs one simulation step. Returns true if any column changed since the
## last pop_dirty_columns() call (callers use this to decide whether the
## water mesh needs rebuilding).
func tick(chunk: ChunkData) -> bool:
	if not _active_queue.is_empty():
		var snapshot := _active_queue.keys()
		_active_queue.clear()

		var mutations: Array = []
		for pos: Vector3i in snapshot:
			if _sources.has(pos):
				_step_source(chunk, pos, mutations)
			elif _flowing.has(pos):
				_step_flowing(chunk, pos, mutations)

		_apply_mutations(chunk, mutations)

	return not _dirty_columns.is_empty()


func pop_dirty_columns() -> Array[Vector2i]:
	var cols: Array[Vector2i] = []
	for key: Vector2i in _dirty_columns.keys():
		cols.append(key)
	_dirty_columns.clear()
	return cols


## Contiguous vertical runs of water in this column, topmost first. 0 or 1
## entries today; callers should still treat this as a list (not assume a
## single span) so a later second, deeper span - e.g. a mined-out flooded
## shaft below a surface lake - is additive rather than a rewrite.
func get_column_spans(chunk: ChunkData, x: int, z: int) -> Array:
	if not chunk.is_in_bounds(x, 0, z):
		return []
	var col_key := Vector2i(x, z)
	if not _column_water_y.has(col_key):
		return []
	var ys: Array = _column_water_y[col_key].keys()
	ys.sort()

	var spans: Array = []
	var span: WaterSpan = null
	for i in range(ys.size() - 1, -1, -1):
		var y: int = ys[i]
		if span == null:
			span = WaterSpan.new()
			span.surface_y = y
			span.floor_y = y
		elif y == span.floor_y - 1:
			span.floor_y = y
		else:
			spans.append(span)
			span = WaterSpan.new()
			span.surface_y = y
			span.floor_y = y
	if span != null:
		spans.append(span)
	return spans


## Future mining hook: call when a solid block at `pos` is removed so any
## adjacent standing water re-evaluates whether it can now flow into the gap.
func notify_block_changed(chunk: ChunkData, pos: Vector3i) -> void:
	if not chunk.is_in_bounds(pos.x, pos.y, pos.z):
		return
	_enqueue_neighbors(pos)


func _step_source(chunk: ChunkData, pos: Vector3i, mutations: Array) -> void:
	var has_open_neighbor := false
	var down := pos + Vector3i.DOWN
	if _is_open(chunk, down):
		mutations.append({"action": "spawn", "at": down, "distance": 0})
		has_open_neighbor = true
	for dir in HORIZONTAL_DIRS:
		var npos := pos + dir
		if _is_open(chunk, npos):
			mutations.append({"action": "spawn", "at": npos, "distance": 0})
			has_open_neighbor = true
	if has_open_neighbor:
		mutations.append({"action": "requeue", "at": pos})


func _step_flowing(chunk: ChunkData, pos: Vector3i, mutations: Array) -> void:
	var distance: int = _flow_distance.get(pos, 0)
	var down := pos + Vector3i.DOWN
	if _is_open(chunk, down):
		mutations.append({"action": "move", "from": pos, "to": down, "distance": distance})
		return
	if distance < MAX_FLOW_DISTANCE:
		for dir in HORIZONTAL_DIRS:
			var npos := pos + dir
			if _is_open(chunk, npos):
				mutations.append({"action": "spread", "from": pos, "to": npos, "distance": distance + 1})
				return
	# Fully blocked this tick. Below the threshold, just keep counting - cheap.
	# Past it, pay for the 26-neighbor scan exactly once: a cell this settled
	# won't change on its own, so if it fails to convert here it goes dormant
	# (dropped from the active queue) rather than re-running that scan every
	# remaining tick forever. It only wakes up again if a neighbor actually
	# changes later (see _enqueue_neighbors / notify_block_changed) - dense
	# seeding can leave thousands of cells in this exact blocked state at
	# once, so re-scanning all of them every tick was the actual cost blowup.
	var ticks: int = _flowing.get(pos, 0)
	if ticks <= STATIONARY_TICKS_TO_SOURCE:
		mutations.append({"action": "increment_stationary", "at": pos})
	elif _should_convert_to_source(pos):
		mutations.append({"action": "convert_to_source", "at": pos})
	else:
		mutations.append({"action": "go_dormant", "at": pos})


func _should_convert_to_source(pos: Vector3i) -> bool:
	var count := 0
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				if dx == 0 and dy == 0 and dz == 0:
					continue
				var npos := pos + Vector3i(dx, dy, dz)
				if _sources.has(npos) or _flowing.has(npos):
					count += 1
	return count >= SOURCE_CONVERSION_THRESHOLD


func _is_open(chunk: ChunkData, pos: Vector3i) -> bool:
	return chunk.is_in_bounds(pos.x, pos.y, pos.z) and chunk.get_block(pos.x, pos.y, pos.z) == &"air"


func _apply_mutations(chunk: ChunkData, mutations: Array) -> void:
	for m: Dictionary in mutations:
		match m["action"]:
			"spawn":
				var at: Vector3i = m["at"]
				if not _is_open(chunk, at):
					continue # another mutation already claimed this cell this tick
				chunk.set_block(at.x, at.y, at.z, &"water")
				_flowing[at] = 0
				_flow_distance[at] = m["distance"]
				_active_queue[at] = true
				_add_water_column_entry(at)
				_mark_column_dirty(at)
			"move":
				var from: Vector3i = m["from"]
				var to: Vector3i = m["to"]
				if not _flowing.has(from) or not _is_open(chunk, to):
					continue
				chunk.set_block(from.x, from.y, from.z, &"air")
				chunk.set_block(to.x, to.y, to.z, &"water")
				_flowing.erase(from)
				_flowing[to] = 0
				_flow_distance.erase(from)
				_flow_distance[to] = m["distance"]
				_active_queue[to] = true
				_remove_water_column_entry(from)
				_add_water_column_entry(to)
				_enqueue_neighbors(from)
				_mark_column_dirty(from)
				_mark_column_dirty(to)
			"spread":
				var spread_from: Vector3i = m["from"]
				var spread_to: Vector3i = m["to"]
				if not _is_open(chunk, spread_to):
					continue
				chunk.set_block(spread_to.x, spread_to.y, spread_to.z, &"water")
				_flowing[spread_to] = 0
				_flow_distance[spread_to] = m["distance"]
				if _flowing.has(spread_from):
					_flowing[spread_from] = 0
				_active_queue[spread_to] = true
				_active_queue[spread_from] = true
				_add_water_column_entry(spread_to)
				_mark_column_dirty(spread_to)
			"requeue":
				_active_queue[m["at"]] = true
			"increment_stationary":
				var stationary_pos: Vector3i = m["at"]
				if _flowing.has(stationary_pos):
					_flowing[stationary_pos] += 1
					_active_queue[stationary_pos] = true
			"convert_to_source":
				var convert_pos: Vector3i = m["at"]
				if _flowing.has(convert_pos):
					_flowing.erase(convert_pos)
					_flow_distance.erase(convert_pos)
					_sources[convert_pos] = true
					_enqueue_neighbors(convert_pos)
			"go_dormant":
				pass # Deliberately not requeued - see _step_flowing's comment.


func _enqueue_neighbors(pos: Vector3i) -> void:
	_active_queue[pos] = true
	for dir in HORIZONTAL_DIRS:
		_active_queue[pos + dir] = true
	_active_queue[pos + Vector3i.UP] = true
	_active_queue[pos + Vector3i.DOWN] = true


func _mark_column_dirty(pos: Vector3i) -> void:
	_dirty_columns[Vector2i(pos.x, pos.z)] = true


func _add_water_column_entry(pos: Vector3i) -> void:
	var col_key := Vector2i(pos.x, pos.z)
	if not _column_water_y.has(col_key):
		_column_water_y[col_key] = {}
	_column_water_y[col_key][pos.y] = true


func _remove_water_column_entry(pos: Vector3i) -> void:
	var col_key := Vector2i(pos.x, pos.z)
	if not _column_water_y.has(col_key):
		return
	_column_water_y[col_key].erase(pos.y)
	if _column_water_y[col_key].is_empty():
		_column_water_y.erase(col_key)
