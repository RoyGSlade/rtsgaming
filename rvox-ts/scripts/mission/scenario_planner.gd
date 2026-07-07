class_name ScenarioPlanner
extends RefCounted

## The scenario-placement pass (DEMO_PLAN.md §3). Runs after terrain
## generation: finds a viable dry/flat camp, places finite resource nodes tied
## to the real biomes and ore veins, puts a raider camp outside the safety
## radius, and validates that every mandatory landmark is path-reachable from
## the camp. Deterministic for a given seed; a seed that can't satisfy the
## rules is rejected so the caller can bump and retry.
##
## Pure logic over ChunkData + WorldGenConfig — fully unit-testable, no scene
## tree. RUN_RULES.md fixes the numeric guarantees this enforces.

# Camp: an (2*CAMP_HALF+1) square must be dry with height range <= FLAT_TOLERANCE.
const CAMP_HALF := 5
const FLAT_TOLERANCE := 3
const CAMP_SCAN_STRIDE := 4

# Resource nodes sit in a ring around the camp and keep MIN_SEPARATION apart.
const MIN_RESOURCE_DIST := 8
const MAX_RESOURCE_DIST := 48
const MIN_SEPARATION := 6

# BFS walkability: a cell is walkable if dry, and a step to a neighbour is only
# taken if the height change is within MAX_STEP.
const MAX_STEP := 3

const DEFAULT_YIELDS := {
	&"wood": 60,
	&"raw_ore": 80,
	&"coal": 40,
}
const NODE_COUNTS := {
	&"wood": 3,
	&"raw_ore": 2,
	&"coal": 2,
}


## Plan a scenario for an already-generated chunk. Returns a ScenarioManifest;
## check `.valid` and `.failure_reason`.
func plan(chunk: ChunkData, config: WorldGenConfig) -> ScenarioManifest:
	var manifest := ScenarioManifest.new()
	manifest.seed = config.world_seed
	manifest.safety_radius = 24

	var camp := _find_camp_site(chunk, config)
	if camp.x < 0:
		manifest.valid = false
		manifest.failure_reason = "no flat, dry camp site"
		return manifest
	manifest.camp_site = camp
	manifest.camp_radius = CAMP_HALF + 1

	# One BFS from camp gives reachability + walking distance for everything.
	var reach := _bfs_distances(chunk, config, camp)

	var ore_gen := ResourceVeinGenerator.new()
	ore_gen.configure(config)

	var placed: Array[Dictionary] = []
	var occupied: Array[Vector2i] = [camp]
	for resource_id: StringName in [&"wood", &"raw_ore", &"coal"]:
		var count := int(NODE_COUNTS[resource_id])
		var chosen := _pick_nodes(chunk, config, ore_gen, reach, camp, occupied, resource_id, count)
		if chosen.size() < count:
			manifest.valid = false
			manifest.failure_reason = "not enough reachable %s within the gather ring" % resource_id
			return manifest
		for cell in chosen:
			placed.append({
				"resource_id": resource_id,
				"cell": cell,
				"amount": int(DEFAULT_YIELDS[resource_id]),
			})
			occupied.append(cell)
	manifest.resource_nodes = placed

	var raider := _pick_raider_camp(reach, camp, manifest.safety_radius)
	if raider.x < 0:
		manifest.valid = false
		manifest.failure_reason = "no reachable raider-camp site outside the safety radius"
		return manifest
	manifest.raider_camp = raider

	manifest.valid = true
	return manifest


## Plan, bumping the seed up to `max_retries` times until a valid scenario is
## found. Regenerates the chunk each attempt via the supplied generator.
## Returns the first valid manifest (or the last invalid one if all fail).
func plan_or_retry(config: WorldGenConfig, generator: WorldGenerator, max_retries: int = 8) -> ScenarioManifest:
	var last: ScenarioManifest = null
	for attempt in max_retries:
		var chunk := generator.generate_chunk(Vector2i.ZERO, config)
		last = plan(chunk, config)
		if last.valid:
			return last
		config.world_seed += 1
	return last


## Build live ResourceNode objects from a manifest, sampling world Y from the
## chunk surface. The bridge from placement data to the runtime economy.
static func to_resource_nodes(manifest: ScenarioManifest, chunk: ChunkData) -> Array[ResourceNode]:
	var out: Array[ResourceNode] = []
	for entry in manifest.resource_nodes:
		var cell: Vector2i = entry["cell"]
		var y := float(chunk.get_surface_height(cell.x, cell.y) + 1)
		var pos := Vector3(cell.x + 0.5, y, cell.y + 0.5)
		out.append(ResourceNode.new(StringName(entry["resource_id"]), int(entry["amount"]), pos))
	return out


# ----- camp -----

func _find_camp_site(chunk: ChunkData, config: WorldGenConfig) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_range := FLAT_TOLERANCE + 1
	var size := chunk.chunk_size
	for cx in range(CAMP_HALF, size - CAMP_HALF, CAMP_SCAN_STRIDE):
		for cz in range(CAMP_HALF, size - CAMP_HALF, CAMP_SCAN_STRIDE):
			var span := _region_flatness(chunk, config, cx, cz)
			if span < 0:
				continue # contained a wet cell
			if span < best_range:
				best_range = span
				best = Vector2i(cx, cz)
				if span == 0:
					return best # perfectly flat — can't do better
	return best


## Height range across the camp square, or -1 if any cell is at/below water.
func _region_flatness(chunk: ChunkData, config: WorldGenConfig, cx: int, cz: int) -> int:
	var lo := chunk.max_height
	var hi := 0
	for x in range(cx - CAMP_HALF, cx + CAMP_HALF + 1):
		for z in range(cz - CAMP_HALF, cz + CAMP_HALF + 1):
			var h := chunk.get_surface_height(x, z)
			if h <= config.water_level:
				return -1
			lo = mini(lo, h)
			hi = maxi(hi, h)
	return hi - lo


# ----- reachability -----

func _is_dry(chunk: ChunkData, config: WorldGenConfig, x: int, z: int) -> bool:
	if x < 0 or x >= chunk.chunk_size or z < 0 or z >= chunk.chunk_size:
		return false
	return chunk.get_surface_height(x, z) > config.water_level


## 4-connected BFS from the camp over dry, low-slope terrain. Returns
## cell(Vector2i) -> walking distance in steps.
func _bfs_distances(chunk: ChunkData, config: WorldGenConfig, start: Vector2i) -> Dictionary:
	var dist: Dictionary = {}
	if not _is_dry(chunk, config, start.x, start.y):
		return dist
	dist[start] = 0
	var queue: Array[Vector2i] = [start]
	var head := 0
	var neighbours := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		var cur_h := chunk.get_surface_height(cur.x, cur.y)
		var cur_d := int(dist[cur])
		for step in neighbours:
			var nxt: Vector2i = cur + step
			if dist.has(nxt):
				continue
			if not _is_dry(chunk, config, nxt.x, nxt.y):
				continue
			if absi(chunk.get_surface_height(nxt.x, nxt.y) - cur_h) > MAX_STEP:
				continue
			dist[nxt] = cur_d + 1
			queue.append(nxt)
	return dist


# ----- resource nodes -----

func _pick_nodes(chunk: ChunkData, config: WorldGenConfig, ore_gen: ResourceVeinGenerator, reach: Dictionary, camp: Vector2i, occupied: Array[Vector2i], resource_id: StringName, count: int) -> Array[Vector2i]:
	# Score every reachable cell in the ring; higher score = better site.
	var scored: Array = []
	for cell in reach.keys():
		var d := int(reach[cell])
		if d < MIN_RESOURCE_DIST or d > MAX_RESOURCE_DIST:
			continue
		var score := _resource_score(chunk, config, ore_gen, cell, resource_id)
		if score <= 0:
			continue
		# Deterministic order: score desc, then distance asc, then cell order.
		scored.append({"cell": cell, "score": score, "dist": d})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		if a["dist"] != b["dist"]:
			return a["dist"] < b["dist"]
		var ca: Vector2i = a["cell"]
		var cb: Vector2i = b["cell"]
		if ca.x != cb.x:
			return ca.x < cb.x
		return ca.y < cb.y
	)

	var chosen: Array[Vector2i] = []
	var taken: Array[Vector2i] = occupied.duplicate()
	for entry in scored:
		if chosen.size() >= count:
			break
		var cell: Vector2i = entry["cell"]
		if _too_close(cell, taken, MIN_SEPARATION):
			continue
		chosen.append(cell)
		taken.append(cell)
	return chosen


## How well a cell suits a resource: biome fit plus, for ore/coal, a real vein
## in the top few metres so miners dig where the metal actually is.
func _resource_score(chunk: ChunkData, config: WorldGenConfig, ore_gen: ResourceVeinGenerator, cell: Vector2i, resource_id: StringName) -> int:
	var biome := chunk.get_biome(cell.x, cell.y)
	match resource_id:
		&"wood":
			if chunk.get_block(cell.x, chunk.get_surface_height(cell.x, cell.y) + 1, cell.y) == &"oak_log":
				return 3 # a tree is literally standing here
			if biome == &"forest":
				return 2
			if biome == &"grassland":
				return 1
			return 0
		&"raw_ore":
			var base := 2 if (biome == &"rocky_hills" or biome == &"pine_highland") else 1
			if _has_vein(chunk, config, ore_gen, cell, &"iron_ore"):
				base += 2
			return base
		&"coal":
			var base := 2 if (biome == &"rocky_hills" or biome == &"pine_highland") else 1
			if _has_vein(chunk, config, ore_gen, cell, &"coal_ore"):
				base += 2
			return base
	return 0


func _has_vein(chunk: ChunkData, config: WorldGenConfig, ore_gen: ResourceVeinGenerator, cell: Vector2i, ore_id: StringName) -> bool:
	var h := chunk.get_surface_height(cell.x, cell.y)
	var gx := chunk.get_global_x(cell.x)
	var gz := chunk.get_global_z(cell.y)
	for y in range(maxi(0, h - 8), maxi(1, h - 1)):
		if ore_gen.resolve_ore(gx, y, gz, h, config) == ore_id:
			return true
	return false


func _too_close(cell: Vector2i, others: Array[Vector2i], min_sep: int) -> bool:
	for o in others:
		if absi(cell.x - o.x) + absi(cell.y - o.y) < min_sep:
			return true
	return false


# ----- raider camp -----

## Farthest reachable cell that is beyond the safety radius (Chebyshev) from
## camp. Farthest keeps the raiders' approach a real march the player can see.
func _pick_raider_camp(reach: Dictionary, camp: Vector2i, safety_radius: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := -1
	for cell in reach.keys():
		var c: Vector2i = cell
		var cheb := maxi(absi(c.x - camp.x), absi(c.y - camp.y))
		if cheb <= safety_radius:
			continue
		var d := int(reach[cell])
		if d > best_dist or (d == best_dist and _cell_less(c, best)):
			best_dist = d
			best = c
	return best


func _cell_less(a: Vector2i, b: Vector2i) -> bool:
	if b.x < 0:
		return true
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y
