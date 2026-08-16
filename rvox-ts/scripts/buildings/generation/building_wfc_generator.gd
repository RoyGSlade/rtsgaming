@tool
class_name BuildingWFCGenerator
extends RefCounted

## Generates BuildingBlueprint-compatible dictionaries by running a
## constrained Wave Function Collapse solve inside a role skeleton.
##
## A tier picks a layout — "box" (single shell), "tower" (round tower), or
## "castle" (round corner towers + curtain walls + arched gatehouse +
## optional central keep) — which stamps a role field (foundation, walls,
## corners, interior air, floors, roofs, parapets, spires). WFC then decides
## which unlocked module fills each cell via socket/adjacency rules, so
## buildings of the same type/tier vary but stay coherent. "Empty air" is a
## real module with its own sockets, and interior air cells are exported in
## the blueprint JSON (interior_cells) for the future component/fluid sim.
## Same library + tier + seed always yields the same building.

const MAX_RESTARTS := 15

const ROLE_FOUNDATION := "foundation"
const ROLE_FLOOR := "floor"
const ROLE_WALL := "wall"
const ROLE_CORNER := "corner"
const ROLE_INTERIOR := "interior"
const ROLE_ROOF := "roof"
const ROLE_PARAPET := "parapet"
## Conical tower roofs. Separate from ROLE_ROOF so spires can be shingled
## while flat decks stay stone in the same solve.
const ROLE_SPIRE := "spire"
## Interior structural support columns in large rooms. Only stamped when the
## tier actually unlocks a column-role module.
const ROLE_COLUMN := "column"

const DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
]

var _modules: Array[Dictionary] = []
var _comp_h: Array = []   # [a][b] -> bool, horizontal neighbors
var _comp_up: Array = []  # [a][b] -> bool, a directly below b


## Returns { "blueprint": Dictionary, "stats": Dictionary } or { "error": String }.
func generate(library: Dictionary, tier_number: int, p_seed: int = 0) -> Dictionary:
	var tier := _find_tier(library, tier_number)
	if tier.is_empty():
		return {"error": "Library '%s' has no tier %d" % [library.get("id", "?"), tier_number]}

	var used_seed := p_seed
	if used_seed == 0:
		var seeder := RandomNumberGenerator.new()
		seeder.randomize()
		used_seed = seeder.randi_range(1, 999_999_999)

	if not _prepare_modules(library, tier):
		return {"error": "Tier %d of '%s' references unknown modules" % [tier_number, library.get("id", "?")]}

	var rng := RandomNumberGenerator.new()
	rng.seed = used_seed

	var layout: Dictionary = tier.get("layout", {})
	var skeleton: Dictionary
	match String(layout.get("type", "box")):
		"castle":
			skeleton = _build_castle_field(layout, rng)
		"tower":
			skeleton = _build_tower_field(layout, rng)
		_:
			skeleton = _build_box_field(tier, rng)
	if skeleton.has("error"):
		return skeleton

	var roles: Dictionary = skeleton["roles"]
	var cells: Array[Vector3i] = skeleton["cells"]

	_place_lighting(tier.get("lighting", {}), roles, skeleton)

	var initial_domains := _initial_domains(cells, roles)
	if initial_domains.is_empty():
		return {"error": "A role has no unlocked modules at tier %d — check the library's tier module list" % tier_number}

	var solved := {}
	var restarts := 0
	for attempt in MAX_RESTARTS:
		var attempt_rng := RandomNumberGenerator.new()
		attempt_rng.seed = used_seed + attempt * 7919
		solved = _solve(cells, roles, initial_domains, attempt_rng)
		if not solved.is_empty():
			restarts = attempt
			break
	if solved.is_empty():
		solved = _greedy_fill(cells, initial_domains)
		restarts = MAX_RESTARTS

	return _emit(library, tier, tier_number, solved, roles, cells, skeleton, used_seed, restarts)


# --- Setup --------------------------------------------------------------------

func _find_tier(library: Dictionary, tier_number: int) -> Dictionary:
	for tier in library.get("tiers", []):
		if int(tier.get("tier", -1)) == tier_number:
			return tier
	return {}

func _prepare_modules(library: Dictionary, tier: Dictionary) -> bool:
	_modules.clear()
	var by_id: Dictionary = library.get("modules_by_id", {})
	if by_id.is_empty():
		for module in library.get("modules", []):
			by_id[String(module.get("id", ""))] = module
	for module_id in tier.get("modules", []):
		var module: Dictionary = by_id.get(String(module_id), {})
		if module.is_empty():
			return false
		_modules.append(_with_defaults(module))
	_precompute_compatibility()
	return not _modules.is_empty()

func _with_defaults(module: Dictionary) -> Dictionary:
	var result := module.duplicate(true)
	if not result.has("weight"):
		result["weight"] = 1.0
	if not result.has("sockets_h"):
		result["sockets_h"] = ["default"]
	if not result.has("sockets_up"):
		result["sockets_up"] = ["default"]
	if not result.has("sockets_down"):
		result["sockets_down"] = ["default"]
	if not result.has("forbid_h"):
		result["forbid_h"] = []
	if not result.has("forbid_v"):
		result["forbid_v"] = []
	if not result.has("tags"):
		result["tags"] = []
	return result

func _precompute_compatibility() -> void:
	var count := _modules.size()
	_comp_h = []
	_comp_up = []
	for a in count:
		var row_h := []
		var row_up := []
		for b in count:
			row_h.append(_sockets_match(_modules[a]["sockets_h"], _modules[b]["sockets_h"])
					and not _is_forbidden(_modules[a], _modules[b], "forbid_h"))
			row_up.append(_sockets_match(_modules[a]["sockets_up"], _modules[b]["sockets_down"])
					and not _is_forbidden(_modules[a], _modules[b], "forbid_v"))
		_comp_h.append(row_h)
		_comp_up.append(row_up)

func _sockets_match(a: Array, b: Array) -> bool:
	for tag in a:
		if tag in b:
			return true
	return false

func _is_forbidden(a: Dictionary, b: Dictionary, key: String) -> bool:
	return String(b["id"]) in a[key] or String(a["id"]) in b[key]

## Whether any module unlocked at this tier can fill the given role — used
## to skip optional skeleton features (support columns) the tier can't build.
func _role_available(role: String) -> bool:
	for module in _modules:
		if role in module.get("roles", []):
			return true
	return false

## The heaviest-weighted non-air block a role resolves to — used for
## deterministic forced details (interior stair runs) that should match the
## surrounding material.
func _primary_block_for_role(role: String) -> String:
	var best := ""
	var best_weight := -1.0
	for module in _modules:
		if role in module.get("roles", []) and String(module.get("block_id", "air")) != "air":
			if float(module["weight"]) > best_weight:
				best_weight = float(module["weight"])
				best = String(module.get("block_id"))
	return best


# --- Skeleton helpers -----------------------------------------------------------

func _pick_range(bounds: Array, rng: RandomNumberGenerator) -> int:
	var low := int(bounds[0])
	var high := int(bounds[bounds.size() - 1])
	return rng.randi_range(low, high)

## Wraps a finished role field into the skeleton dictionary _emit expects.
func _finish_skeleton(roles: Dictionary, door_cells: Array[Vector3i], sockets: Array,
		forced_blocks: Array[Dictionary]) -> Dictionary:
	var cells: Array[Vector3i] = []
	var max_pos := Vector3i.ZERO
	for pos: Vector3i in roles:
		cells.append(pos)
		max_pos = Vector3i(maxi(max_pos.x, pos.x), maxi(max_pos.y, pos.y), maxi(max_pos.z, pos.z))
	cells.sort()
	return {
		"roles": roles,
		"cells": cells,
		"door_cells": door_cells,
		"sockets": sockets,
		"forced_blocks": forced_blocks,
		"size": max_pos + Vector3i.ONE,
	}

func _entry_socket(id: String, pos: Vector3i, facing: Vector3i) -> Dictionary:
	return {
		"id": id,
		"socket_type": "entry",
		"pos": [pos.x, pos.y, pos.z],
		"facing": [facing.x, facing.y, facing.z],
		"role": "any",
	}

func _forced_block(pos: Vector3i, block_id: String, layer: String, stage: String,
		tags: Array, shape_id: String = "cube", rotation: int = 0) -> Dictionary:
	return {"pos": pos, "block_id": block_id, "layer": layer, "build_stage": stage,
			"tags": tags, "shape_id": shape_id, "rotation_steps": rotation}


# --- Lighting post-pass -----------------------------------------------------------

## Places light-source blocks after the skeleton is built, driven by the
## tier's "lighting" config:
##   wall_torch: block id mounted on interior walls, spread `spacing` apart
##   entrance:   block id placed on the ground flanking each entry socket
##   courtyard:  block id placed at castle courtyard corners
## Lights are forced blocks tagged "light" (and also listed in the exported
## blueprint's `lights` array), so runtime code can spawn OmniLights and
## flame effects without scanning every block.
func _place_lighting(lighting: Dictionary, roles: Dictionary, skeleton: Dictionary) -> void:
	if lighting.is_empty():
		return
	var forced: Array[Dictionary] = skeleton["forced_blocks"]

	var torch_block := String(lighting.get("wall_torch", ""))
	if not torch_block.is_empty():
		var spacing := maxi(2, int(lighting.get("spacing", 4)))
		var mount_height := int(lighting.get("height", 2))
		var candidates: Array[Vector3i] = []
		for pos: Vector3i in roles:
			if pos.y != mount_height or roles[pos] != ROLE_INTERIOR:
				continue
			for dir: Vector3i in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				if roles.get(pos + dir, "") == ROLE_WALL:
					candidates.append(pos)
					break
		candidates.sort()
		var accepted: Array[Vector3i] = []
		for pos in candidates:
			var clear := true
			for other in accepted:
				if absi(other.x - pos.x) + absi(other.y - pos.y) + absi(other.z - pos.z) < spacing:
					clear = false
					break
			if clear:
				accepted.append(pos)
				forced.append(_forced_block(pos, torch_block, "decoration", "decoration", ["light"], "torch"))

	var entrance_block := String(lighting.get("entrance", ""))
	if not entrance_block.is_empty():
		for socket: Dictionary in skeleton["sockets"]:
			var socket_pos: Array = socket["pos"]
			var pos := Vector3i(int(socket_pos[0]), int(socket_pos[1]), int(socket_pos[2]))
			var facing: Array = socket["facing"]
			var side := Vector3i(1, 0, 0) if int(facing[2]) != 0 else Vector3i(0, 0, 1)
			for offset: int in [-1, 1]:
				var lantern_pos := pos + side * offset
				if roles.has(lantern_pos):
					lantern_pos += side * offset  # Step outward past the wall edge.
				if roles.has(lantern_pos):
					continue
				forced.append(_forced_block(lantern_pos, entrance_block, "decoration", "decoration", ["light"], "lantern"))

	var courtyard_block := String(lighting.get("courtyard", ""))
	if not courtyard_block.is_empty() and skeleton.has("courtyard_rect"):
		var rect: Rect2i = skeleton["courtyard_rect"]
		var corners: Array[Vector2i] = [
			rect.position,
			rect.position + Vector2i(rect.size.x, 0),
			rect.position + Vector2i(0, rect.size.y),
			rect.position + rect.size,
		]
		for corner in corners:
			var pos := Vector3i(corner.x, 1, corner.y)
			if roles.has(pos):
				continue
			forced.append(_forced_block(pos, courtyard_block, "decoration", "decoration", ["light"], "brazier"))


# --- Box layout (single rectangular shell) --------------------------------------

func _build_box_field(tier: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var size_cfg: Dictionary = tier.get("size", {})
	var width := _pick_range(size_cfg.get("width", [4, 4]), rng)
	var wall_height := _pick_range(size_cfg.get("wall_height", [3, 3]), rng)
	var depth := _pick_range(size_cfg.get("depth", [4, 4]), rng)
	if width < 3 or depth < 3 or wall_height < 2:
		return {"error": "Tier size too small for a shell (need width/depth >= 3, wall_height >= 2)"}
	var stories := maxi(1, int(tier.get("stories", 1)))

	var roles := {}
	var door_cells: Array[Vector3i] = []
	var shape_overrides := {}
	var stair_specs: Array[Dictionary] = []
	_stamp_box(roles, door_cells, shape_overrides, stair_specs, Vector3i.ZERO,
			width, depth, wall_height, String(tier.get("roof", "pyramid")), true,
			stories, _role_available(ROLE_COLUMN))

	var forced: Array[Dictionary] = []
	# Interior stair runs match the dominant floor material.
	var stair_block := _primary_block_for_role(ROLE_FLOOR)
	if not stair_block.is_empty():
		for spec in stair_specs:
			forced.append(_forced_block(spec["pos"], stair_block, "floor", "floor",
					["stairs"], "stair", int(spec["steps"])))
	if bool(tier.get("chimney", false)):
		forced.append_array(_chimney_column(roles, width, depth, wall_height, rng, stories > 1))

	# Doorstep: a stone step outside the entrance, high side against the wall.
	var door_x := width / 2
	var step_block := _primary_block_for_role(ROLE_FOUNDATION)
	if not step_block.is_empty():
		forced.append(_forced_block(Vector3i(door_x, 1, -1), step_block, "decoration",
				"decoration", ["doorstep"], "stair", 0))

	var sockets: Array = [_entry_socket("door_entry", Vector3i(door_x, 1, -1), Vector3i(0, 0, 1))]
	var skeleton := _finish_skeleton(roles, door_cells, sockets, forced)
	skeleton["shape_overrides"] = shape_overrides
	return skeleton

## Stamps a rectangular building shell at `origin`: foundation slab, corner
## posts, walls, floors, interior air, and a roof. When carve_door is true, a
## door opening is cut into the front (min-Z) face center.
##
## Detail features beyond the plain shell:
##   • pyramid roofs use outward-facing stair shapes on each ring and slab
##     caps on the ridge (via shape_overrides: pos -> {shape, rotation})
##   • stories > 1 inserts extra floor slabs every 3 cells of height, with a
##     climbable stair run along the west wall (emitted into stair_specs) and
##     an open stairwell above it
##   • columns=true drops support pillars (ROLE_COLUMN) on a 3-cell grid in
##     rooms at least 7 cells across
func _stamp_box(roles: Dictionary, door_cells: Array[Vector3i], shape_overrides: Dictionary,
		stair_specs: Array[Dictionary], origin: Vector3i, width: int, depth: int,
		wall_height: int, roof_style: String, carve_door: bool, stories: int = 1,
		columns: bool = false) -> void:
	# Multi-story needs 3 cells per story (floor + 2 of headroom) and room
	# for the stair run; fall back to one story instead of failing.
	if wall_height < 3 * stories or width < 5 or depth < 6:
		stories = 1

	for x in width:
		for z in depth:
			roles[origin + Vector3i(x, 0, z)] = ROLE_FOUNDATION

	var local_door: Array[Vector3i] = []
	if carve_door:
		var door_x := width / 2
		var door_height := 2 if wall_height >= 3 else 1
		for i in door_height:
			local_door.append(origin + Vector3i(door_x, 1 + i, 0))
			door_cells.append(origin + Vector3i(door_x, 1 + i, 0))

	var column_cells := {}
	if columns and mini(width, depth) >= 7:
		for cx in range(3, width - 2, 3):
			for cz in range(3, depth - 2, 3):
				column_cells[Vector2i(cx, cz)] = true

	for y in range(1, wall_height + 1):
		for x in width:
			for z in depth:
				var pos := origin + Vector3i(x, y, z)
				var on_x_edge := x == 0 or x == width - 1
				var on_z_edge := z == 0 or z == depth - 1
				if on_x_edge and on_z_edge:
					roles[pos] = ROLE_CORNER
				elif on_x_edge or on_z_edge:
					if pos in local_door:
						continue  # Door opening: no block, no WFC cell.
					roles[pos] = ROLE_WALL
				elif column_cells.has(Vector2i(x, z)):
					roles[pos] = ROLE_COLUMN
				elif (y - 1) % 3 == 0 and (y - 1) / 3 < stories:
					roles[pos] = ROLE_FLOOR
				else:
					roles[pos] = ROLE_INTERIOR

	# Stair run to each upper floor: three ascending steps along the west
	# wall, with the floor above the lower steps opened for headroom.
	for story in range(1, stories):
		var floor_y := 1 + 3 * story
		roles[origin + Vector3i(1, floor_y, 1)] = ROLE_INTERIOR
		roles[origin + Vector3i(1, floor_y, 2)] = ROLE_INTERIOR
		stair_specs.append({"pos": origin + Vector3i(1, floor_y - 2, 1), "steps": 0})
		stair_specs.append({"pos": origin + Vector3i(1, floor_y - 1, 2), "steps": 0})
		stair_specs.append({"pos": origin + Vector3i(1, floor_y, 3), "steps": 0})

	match roof_style:
		"flat":
			for x in width:
				for z in depth:
					roles[origin + Vector3i(x, wall_height + 1, z)] = ROLE_ROOF
		"parapet":
			for x in width:
				for z in depth:
					roles[origin + Vector3i(x, wall_height + 1, z)] = ROLE_ROOF
			for x in width:
				for z in depth:
					if x == 0 or x == width - 1 or z == 0 or z == depth - 1:
						roles[origin + Vector3i(x, wall_height + 2, z)] = ROLE_PARAPET
		_:  # "pyramid" (hip roof): shrinking stair rings with a slab ridge cap.
			var inset := 0
			while true:
				var x0 := inset
				var x1 := width - 1 - inset
				var z0 := inset
				var z1 := depth - 1 - inset
				if x1 < x0 or z1 < z0:
					break
				var y := wall_height + 1 + inset
				var cap := (x1 - x0) < 2 or (z1 - z0) < 2
				for x in range(x0, x1 + 1):
					for z in range(z0, z1 + 1):
						var on_ring := x == x0 or x == x1 or z == z0 or z == z1
						if not (cap or on_ring):
							continue
						var pos := origin + Vector3i(x, y, z)
						roles[pos] = ROLE_ROOF
						if cap:
							shape_overrides[pos] = {"shape": "slab"}
							continue
						# Ring edges slope outward as stairs (high side faces
						# the roof center); ring corners stay full cubes.
						var on_x_ring := x == x0 or x == x1
						var on_z_ring := z == z0 or z == z1
						if on_x_ring and on_z_ring:
							continue
						if z == z0:
							shape_overrides[pos] = {"shape": "stair", "rotation": 0}
						elif z == z1:
							shape_overrides[pos] = {"shape": "stair", "rotation": 2}
						elif x == x0:
							shape_overrides[pos] = {"shape": "stair", "rotation": 1}
						else:
							shape_overrides[pos] = {"shape": "stair", "rotation": 3}
				if cap:
					break
				inset += 1

func _chimney_column(roles: Dictionary, width: int, depth: int, wall_height: int,
		rng: RandomNumberGenerator, avoid_stairwell: bool = false) -> Array[Dictionary]:
	var corners: Array[Vector2i] = [
		Vector2i(1, 1), Vector2i(width - 2, 1),
		Vector2i(1, depth - 2), Vector2i(width - 2, depth - 2),
	]
	if avoid_stairwell:
		# The interior stair run occupies the west-front corner.
		corners.remove_at(0)
	var spot := corners[rng.randi_range(0, corners.size() - 1)]
	var top := wall_height + 1
	for pos: Vector3i in roles:
		if roles[pos] == ROLE_ROOF and pos.x == spot.x and pos.z == spot.y:
			top = maxi(top, pos.y)
	var forced: Array[Dictionary] = []
	for y in range(1, top + 2):
		forced.append(_forced_block(Vector3i(spot.x, y, spot.y), "stone", "wall", "wall", ["chimney"]))
	return forced


# --- Tower layout (single round tower) -------------------------------------------

func _build_tower_field(layout: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var tower_cfg: Dictionary = layout.get("tower", {})
	var radius := maxi(2, _pick_range(tower_cfg.get("radius", [2, 2]), rng))
	var height := maxi(3, _pick_range(tower_cfg.get("height", [6, 7]), rng))
	var top := String(tower_cfg.get("top", "parapet"))

	var roles := {}
	var forced: Array[Dictionary] = []
	var center := Vector2i(radius, radius)
	_stamp_round_tower(roles, forced, center, radius, height, top)

	# Entrance: carve the front (min-Z) shell column at ground level.
	var door_cells: Array[Vector3i] = []
	for y in range(1, 3):
		var pos := Vector3i(center.x, y, center.y - radius)
		if roles.has(pos):
			roles.erase(pos)
			door_cells.append(pos)

	var sockets: Array = [_entry_socket("door_entry", Vector3i(center.x, 1, center.y - radius - 1), Vector3i(0, 0, 1))]
	return _finish_skeleton(roles, door_cells, sockets, forced)

## Round-tower disk test: a Minecraft-style circle. Returns squared-distance
## threshold for a given radius.
func _disk_threshold(radius: int) -> int:
	return radius * radius + radius / 2

## Stamps a round tower: foundation disk, 1-thick circular shell with hollow
## interior, floor at y=1, a full deck slab above the walls, and either a
## deterministic crenellated rim or a conical spire on top.
func _stamp_round_tower(roles: Dictionary, forced: Array[Dictionary], center: Vector2i,
		radius: int, height: int, top: String) -> void:
	var outer := _disk_threshold(radius)
	var inner := _disk_threshold(radius - 1)
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var d2 := dx * dx + dz * dz
			if d2 > outer:
				continue
			var x := center.x + dx
			var z := center.y + dz
			roles[Vector3i(x, 0, z)] = ROLE_FOUNDATION
			var is_shell := d2 > inner
			for y in range(1, height + 1):
				var pos := Vector3i(x, y, z)
				if is_shell:
					roles[pos] = ROLE_WALL
				else:
					roles[pos] = ROLE_FLOOR if y == 1 else ROLE_INTERIOR
			roles[Vector3i(x, height + 1, z)] = ROLE_ROOF

	match top:
		"cone":
			# Shrinking shell rings; WFC fills them from the "spire" role.
			var level := 0
			while radius - level >= 1:
				var ring_radius := radius - level
				var ring_outer := _disk_threshold(ring_radius)
				var ring_inner := _disk_threshold(ring_radius - 1) if ring_radius >= 2 else -1
				var y := height + 2 + level
				for dx in range(-ring_radius, ring_radius + 1):
					for dz in range(-ring_radius, ring_radius + 1):
						var d2 := dx * dx + dz * dz
						if d2 > ring_outer:
							continue
						if ring_radius >= 2 and d2 <= ring_inner:
							continue
						roles[Vector3i(center.x + dx, y, center.y + dz)] = ROLE_SPIRE
				level += 1
		_:  # "parapet": deterministic alternating merlons around the rim.
			# WFC alternation needs an even cycle; a circular ring often is
			# not, so the tower rim is stamped directly instead of solved.
			var ring: Array[Vector3i] = []
			for dx in range(-radius, radius + 1):
				for dz in range(-radius, radius + 1):
					var d2 := dx * dx + dz * dz
					if d2 <= outer and d2 > inner:
						ring.append(Vector3i(center.x + dx, height + 2, center.y + dz))
			ring.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
				return atan2(float(a.z - center.y), float(a.x - center.x)) < atan2(float(b.z - center.y), float(b.x - center.x)))
			for index in ring.size():
				if index % 2 == 0:
					forced.append(_forced_block(ring[index], "stone_bricks", "roof", "roof", ["battlement"]))


# --- Castle layout (towers + curtain walls + gatehouse + keep) --------------------

## Composite fantasy-castle plan: a rectangular courtyard ringed by curtain
## walls with battlemented walkways, round towers on the four corners, an
## arched gate in the front wall, and an optional central keep. Each region
## is still WFC-solved for material variation; only the plan is fixed.
func _build_castle_field(layout: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var court_w := _pick_range(layout.get("courtyard", {}).get("width", [12, 14]), rng)
	var court_d := _pick_range(layout.get("courtyard", {}).get("depth", [12, 14]), rng)
	var tower_cfg: Dictionary = layout.get("tower", {})
	var tower_r := maxi(2, _pick_range(tower_cfg.get("radius", [2, 2]), rng))
	var tower_h := maxi(4, _pick_range(tower_cfg.get("height", [7, 8]), rng))
	var tower_top := String(tower_cfg.get("top", "parapet"))
	var curtain_cfg: Dictionary = layout.get("curtain", {})
	var wall_h := maxi(3, _pick_range(curtain_cfg.get("height", [4, 5]), rng))
	var wall_t := clampi(int(curtain_cfg.get("thickness", 1)), 1, 2)
	if court_w < 8 or court_d < 8:
		return {"error": "Castle courtyard must be at least 8x8"}

	var roles := {}
	var forced: Array[Dictionary] = []
	var shape_overrides := {}
	var stair_specs: Array[Dictionary] = []

	# Courtyard rectangle in world coords, offset so tower disks stay >= 0.
	var x0 := tower_r
	var x1 := tower_r + court_w - 1
	var z0 := tower_r
	var z1 := tower_r + court_d - 1

	# 1) Curtain walls along the perimeter (thickness grows inward), with a
	# crenellated parapet row on the outer edge above the walkway.
	for x in range(x0, x1 + 1):
		for t in wall_t:
			_stamp_wall_column(roles, Vector3i(x, 0, z0 + t), wall_h)
			_stamp_wall_column(roles, Vector3i(x, 0, z1 - t), wall_h)
		roles[Vector3i(x, wall_h + 1, z0)] = ROLE_PARAPET
		roles[Vector3i(x, wall_h + 1, z1)] = ROLE_PARAPET
	for z in range(z0, z1 + 1):
		for t in wall_t:
			_stamp_wall_column(roles, Vector3i(x0 + t, 0, z), wall_h)
			_stamp_wall_column(roles, Vector3i(x1 - t, 0, z), wall_h)
		roles[Vector3i(x0, wall_h + 1, z)] = ROLE_PARAPET
		roles[Vector3i(x1, wall_h + 1, z)] = ROLE_PARAPET

	# 2) Corner towers, overwriting whatever the walls stamped there.
	for corner: Vector2i in [Vector2i(x0, z0), Vector2i(x1, z0), Vector2i(x0, z1), Vector2i(x1, z1)]:
		_stamp_round_tower(roles, forced, corner, tower_r, tower_h, tower_top)

	var door_cells: Array[Vector3i] = []
	var sockets: Array = []

	# 3) Arched gate through the front wall center.
	var gate_x := (x0 + x1) / 2
	var gate_half := 1  # 3-wide opening
	var gate_h := 3
	for gx in range(gate_x - gate_half, gate_x + gate_half + 1):
		for gy in range(1, gate_h + 1):
			for t in wall_t:
				var pos := Vector3i(gx, gy, z0 + t)
				if roles.has(pos):
					roles.erase(pos)
					door_cells.append(pos)
	# Arch shoulders: refill the top corners of the opening in brick.
	for t in wall_t:
		for gx in [gate_x - gate_half, gate_x + gate_half]:
			var pos := Vector3i(gx, gate_h, z0 + t)
			door_cells.erase(pos)
			forced.append(_forced_block(pos, "stone_bricks", "wall", "wall", ["arch"]))
	sockets.append(_entry_socket("gate_entry", Vector3i(gate_x, 1, z0 - 1), Vector3i(0, 0, 1)))

	# 4) Optional central keep, pushed toward the back of the courtyard,
	# door facing the gate.
	var keep_cfg: Variant = layout.get("keep", null)
	if keep_cfg is Dictionary:
		var keep_w := _pick_range(keep_cfg.get("width", [6, 7]), rng)
		var keep_d := _pick_range(keep_cfg.get("depth", [6, 7]), rng)
		var keep_h := _pick_range(keep_cfg.get("wall_height", [6, 7]), rng)
		var keep_x := x0 + wall_t + maxi(1, (court_w - 2 * wall_t - keep_w) / 2)
		var keep_z := z1 - wall_t - keep_d - 1
		var keep_origin := Vector3i(keep_x, 0, keep_z)
		_stamp_box(roles, door_cells, shape_overrides, stair_specs, keep_origin,
				keep_w, keep_d, keep_h, String(keep_cfg.get("roof", "parapet")), true,
				maxi(1, int(keep_cfg.get("stories", 1))), _role_available(ROLE_COLUMN))
		sockets.append(_entry_socket("keep_entry", keep_origin + Vector3i(keep_w / 2, 1, -1), Vector3i(0, 0, 1)))
		var stair_block := _primary_block_for_role(ROLE_FLOOR)
		if not stair_block.is_empty():
			for spec in stair_specs:
				forced.append(_forced_block(spec["pos"], stair_block, "floor", "floor",
						["stairs"], "stair", int(spec["steps"])))

	var skeleton := _finish_skeleton(roles, door_cells, sockets, forced)
	skeleton["shape_overrides"] = shape_overrides
	# Inner courtyard bounds (inset one cell from the walls), for the
	# lighting pass and future decoration passes.
	skeleton["courtyard_rect"] = Rect2i(
		Vector2i(x0 + wall_t + 1, z0 + wall_t + 1),
		Vector2i(court_w - 2 * wall_t - 3, court_d - 2 * wall_t - 3))
	return skeleton

## One column of curtain wall: foundation at ground, solid wall body above.
func _stamp_wall_column(roles: Dictionary, base: Vector3i, wall_height: int) -> void:
	roles[base] = ROLE_FOUNDATION
	for y in range(1, wall_height + 1):
		roles[Vector3i(base.x, y, base.z)] = ROLE_WALL


# --- WFC solve ------------------------------------------------------------------

## Domain per cell: module indices legal for that cell's role and height.
## Returns {} if any cell starts with an empty domain (library authoring error).
func _initial_domains(cells: Array[Vector3i], roles: Dictionary) -> Dictionary:
	var domains := {}
	for pos in cells:
		var role: String = roles[pos]
		var options: Array[int] = []
		for i in _modules.size():
			var module := _modules[i]
			if not role in module.get("roles", []):
				continue
			if module.has("min_y") and pos.y < int(module["min_y"]):
				continue
			if module.has("max_y") and pos.y > int(module["max_y"]):
				continue
			options.append(i)
		if options.is_empty():
			push_error("BuildingWFCGenerator: no module can fill role '%s' at %s" % [role, pos])
			return {}
		domains[pos] = options
	return domains

func _solve(cells: Array[Vector3i], roles: Dictionary, initial: Dictionary,
		rng: RandomNumberGenerator) -> Dictionary:
	var domains := {}
	for pos in cells:
		domains[pos] = (initial[pos] as Array[int]).duplicate()

	# Height-restricted domains already constrain neighbors; settle them first.
	for pos in cells:
		if not _propagate(pos, domains, roles):
			return {}

	# Cells still holding more than one option. Pruned in place as the solve
	# collapses them so castle-sized grids (thousands of cells) don't rescan
	# every cell on every collapse.
	var open := cells.duplicate()
	while true:
		var target := _min_entropy_cell(open, domains, rng)
		if target == Vector3i(-1000, -1000, -1000):
			break  # Everything collapsed.
		var picked := _weighted_pick(domains[target], rng)
		domains[target] = [picked] as Array[int]
		if not _propagate(target, domains, roles):
			return {}

	var solved := {}
	for pos in cells:
		solved[pos] = (domains[pos] as Array)[0]
	return solved

## Minimum-entropy pick over `open`, removing already-collapsed cells from
## it (swap-remove) while scanning.
func _min_entropy_cell(open: Array[Vector3i], domains: Dictionary,
		rng: RandomNumberGenerator) -> Vector3i:
	var best_size := 0x7FFFFFFF
	var candidates: Array[Vector3i] = []
	var index := open.size() - 1
	while index >= 0:
		var pos := open[index]
		var size: int = (domains[pos] as Array).size()
		if size < 2:
			open[index] = open[open.size() - 1]
			open.remove_at(open.size() - 1)
		elif size < best_size:
			best_size = size
			candidates = [pos]
		elif size == best_size:
			candidates.append(pos)
		index -= 1
	if candidates.is_empty():
		return Vector3i(-1000, -1000, -1000)
	return candidates[rng.randi_range(0, candidates.size() - 1)]

func _weighted_pick(options: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for i: int in options:
		total += float(_modules[i]["weight"])
	var roll := rng.randf_range(0.0, total)
	for i: int in options:
		roll -= float(_modules[i]["weight"])
		if roll <= 0.0:
			return i
	return options[options.size() - 1]

## Arc-consistency propagation from a changed cell. Constraints only apply
## between cells sharing a role — the skeleton already guarantees the
## cross-role structure, which keeps every layout solvable.
func _propagate(start: Vector3i, domains: Dictionary, roles: Dictionary) -> bool:
	var queue: Array[Vector3i] = [start]
	while not queue.is_empty():
		var pos: Vector3i = queue.pop_back()
		for dir in DIRS:
			var neighbor := pos + dir
			if not domains.has(neighbor) or roles[neighbor] != roles[pos]:
				continue
			var kept: Array[int] = []
			for option: int in domains[neighbor]:
				if _supported(option, domains[pos], -dir):
					kept.append(option)
			if kept.size() == (domains[neighbor] as Array).size():
				continue
			if kept.is_empty():
				return false
			domains[neighbor] = kept
			queue.append(neighbor)
	return true

## True if `option` placed at a cell is compatible with at least one module in
## the neighbor's domain, where `dir` points from the option's cell toward the neighbor.
func _supported(option: int, neighbor_domain: Array, dir: Vector3i) -> bool:
	for other: int in neighbor_domain:
		var ok: bool
		if dir.y > 0:
			ok = _comp_up[option][other]
		elif dir.y < 0:
			ok = _comp_up[other][option]
		else:
			ok = _comp_h[option][other]
		if ok:
			return true
	return false

## Last-resort fill so a button press always yields a building even if the
## library's constraints are unsatisfiable: highest-weight module per role.
func _greedy_fill(cells: Array[Vector3i], initial: Dictionary) -> Dictionary:
	var solved := {}
	for pos in cells:
		var best := -1
		var best_weight := -1.0
		for option: int in initial[pos]:
			var weight := float(_modules[option]["weight"])
			if weight > best_weight:
				best_weight = weight
				best = option
		solved[pos] = best
	return solved


# --- Emission --------------------------------------------------------------------

func _emit(library: Dictionary, tier: Dictionary, tier_number: int, solved: Dictionary,
		roles: Dictionary, cells: Array[Vector3i], skeleton: Dictionary,
		used_seed: int, restarts: int) -> Dictionary:
	var forced_blocks: Array[Dictionary] = skeleton["forced_blocks"]
	var door_cells: Array[Vector3i] = skeleton["door_cells"]
	var size: Vector3i = skeleton["size"]

	var forced_positions := {}
	for entry in forced_blocks:
		forced_positions[entry["pos"]] = true
	var shape_overrides: Dictionary = skeleton.get("shape_overrides", {})

	var blocks: Array = []
	var interior_cells: Array = []
	var block_counts := {}

	for pos in cells:
		if forced_positions.has(pos):
			continue
		var module := _modules[solved[pos]]
		var block_id := String(module.get("block_id", "air"))
		var role: String = roles[pos]
		if block_id == "air":
			if role == ROLE_INTERIOR or role == ROLE_FLOOR:
				interior_cells.append([pos.x, pos.y, pos.z])
			continue
		var shape := String(module.get("shape_id", "cube"))
		var rotation := 0
		if shape_overrides.has(pos):
			var override: Dictionary = shape_overrides[pos]
			shape = String(override.get("shape", shape))
			rotation = int(override.get("rotation", 0))
		blocks.append(_make_block(pos, block_id, String(module.get("layer", role)),
				String(module.get("build_stage", role)), _merge_tags(module["tags"], role),
				shape, rotation))
		block_counts[block_id] = block_counts.get(block_id, 0) + 1

	for entry in forced_blocks:
		var pos: Vector3i = entry["pos"]
		blocks.append(_make_block(pos, entry["block_id"], entry["layer"], entry["build_stage"],
				entry["tags"], String(entry.get("shape_id", "cube")), int(entry.get("rotation_steps", 0))))
		block_counts[entry["block_id"]] = block_counts.get(entry["block_id"], 0) + 1

	for pos in door_cells:
		interior_cells.append([pos.x, pos.y, pos.z])

	# Convenience index of light-source blocks so runtime lighting doesn't
	# have to scan tags across the whole block list.
	var lights: Array = []
	for block: Dictionary in blocks:
		if "light" in (block["tags"] as Array):
			lights.append({"pos": block["pos"], "block_id": block["block_id"]})

	blocks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["pos"] < b["pos"])

	var library_id := String(library.get("id", "building"))
	var tier_name := String(tier.get("name", "Tier %d" % tier_number))
	var blueprint := {
		"id": "%s_t%d" % [library_id, tier_number],
		"display_name": "%s (%s)" % [String(library.get("display_name", library_id.capitalize())), tier_name],
		"category": String(library.get("category", "production")),
		"era": String(library.get("era", "village")),
		"footprint": [size.x, size.z],
		"health": int(tier.get("health", 100)),
		"workers_required": int(tier.get("workers_required", 1)),
		"required_functional_tags": ["foundation"],
		"blocks": blocks,
		"sockets": skeleton["sockets"],
		"storage_slots": [],
		"recipes": [],
		"interior_cells": interior_cells,
		"lights": lights,
		"generator": {
			"library": library_id,
			"tier": tier_number,
			"seed": used_seed,
			"size": [size.x, size.y, size.z],
		},
	}

	return {
		"blueprint": blueprint,
		"stats": {
			"total_blocks": blocks.size(),
			"block_counts": block_counts,
			"seed": used_seed,
			"size": [size.x, size.y, size.z],
			"restarts": restarts,
			"interior_volume": interior_cells.size(),
		},
	}

func _make_block(pos: Vector3i, block_id: String, layer: String, stage: String,
		tags: Array, shape_id: String = "cube", rotation: int = 0) -> Dictionary:
	return {
		"pos": [pos.x, pos.y, pos.z],
		"block_id": block_id,
		"shape_id": shape_id,
		"rotation_steps": rotation,
		"layer": layer,
		"tags": tags,
		"build_stage": stage,
		"requires_support": pos.y > 0,
	}

func _merge_tags(module_tags: Array, role: String) -> Array:
	var tags := module_tags.duplicate()
	if not role in tags:
		tags.append(role)
	return tags
