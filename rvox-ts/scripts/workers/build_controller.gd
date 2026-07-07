class_name BuildController
extends Node

## Spawns builders and renders construction (DEMO_PLAN.md §5, the "block-built"
## pillar). Each builder is driven by a BuilderBrain; as it places blocks, a
## block mesh appears at the site so the structure visibly rises "1/5 → 5/5".
## Rebinds cleanly when the economy is rebuilt (regenerate).

const BUILDER_COUNT := 2
const SPAWN_OFFSET := 2.0
const BLOCK_SIZE := 0.8
const BLOCK_COLOR := Color(0.62, 0.52, 0.40)

var economy: EconomyController
var world: WorldRuntime
var stockpile_position: Vector3

# Each: { "unit": Unit, "brain": BuilderBrain, "last_target": Variant }
var _builders: Array[Dictionary] = []
var _site_roots: Dictionary = {} # BuildSite -> Node3D holding its block meshes


func bind(new_economy: EconomyController, new_world: WorldRuntime, stockpile: Vector3) -> void:
	_clear()
	economy = new_economy
	world = new_world
	stockpile_position = stockpile
	if economy == null or world == null:
		return
	economy.build_site_added.connect(_on_build_site_added)
	# Any sites registered before we bound (e.g. the starter building) still
	# get visuals.
	for site in economy.build_sites():
		_on_build_site_added(site)
	for i in BUILDER_COUNT:
		_spawn_builder(i)


func _process(delta: float) -> void:
	for b in _builders:
		var unit: Unit = b["unit"]
		var brain: BuilderBrain = b["brain"]
		if not is_instance_valid(unit):
			continue
		var intent := brain.tick(delta, unit.global_position)
		var target: Variant = intent["move_target"]
		if target != null and b["last_target"] != target:
			unit.move_to(target)
			b["last_target"] = target
		unit.set_stance(int(intent["stance"]))


func _on_build_site_added(site: BuildSite) -> void:
	if _site_roots.has(site):
		return
	var root := Node3D.new()
	root.name = "Site_%s" % site.building_id
	add_child(root)
	_site_roots[site] = root
	site.block_placed.connect(func(placed: int, _total: int) -> void: _add_block_mesh(site, placed))
	site.completed.connect(func() -> void: _on_site_completed(site))


## Add one block mesh, arranged in a small rising 3-wide footprint so the
## building grows a recognisable little structure as blocks land.
func _add_block_mesh(site: BuildSite, placed: int) -> void:
	var root: Node3D = _site_roots.get(site)
	if root == null:
		return
	var block := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	block.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BLOCK_COLOR
	block.material_override = mat
	root.add_child(block)
	# Fill a 3x3 layer then rise; centre the footprint on the site.
	var index := placed - 1
	var gx := index % 3
	var gz := int(index / 3.0) % 3
	var gy := int(index / 9.0)
	block.global_position = site.position + Vector3(
		(gx - 1) * BLOCK_SIZE, gy * BLOCK_SIZE + BLOCK_SIZE * 0.5, (gz - 1) * BLOCK_SIZE)


## On completion, clear the rising construction blocks and drop a single solid
## building coloured by type, so the site reads as a finished structure.
func _on_site_completed(site: BuildSite) -> void:
	var root: Node3D = _site_roots.get(site)
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()
	var building := MeshInstance3D.new()
	var box := BoxMesh.new()
	var height := 2.6 if DemoBuildings.is_watchtower(site.building_id) else 1.8
	box.size = Vector3(2.6, height, 2.6)
	building.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = DemoBuildings.color(site.building_id)
	building.material_override = mat
	building.position = site.position + Vector3(0.0, height * 0.5, 0.0)
	root.add_child(building)


func _spawn_builder(index: int) -> void:
	var unit := Unit.new()
	unit.ground_sampler = world.get_ground_height
	add_child(unit)
	var angle := TAU * float(index) / float(BUILDER_COUNT) + 0.5
	var spot := stockpile_position + Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_OFFSET
	unit.global_position = Vector3(spot.x, world.get_ground_height(spot.x, spot.z), spot.z)
	var brain := BuilderBrain.new(2000 + index, economy.job_board, economy, stockpile_position, [&"builder"])
	_builders.append({"unit": unit, "brain": brain, "last_target": null})


func _clear() -> void:
	for b in _builders:
		var unit: Unit = b["unit"]
		if is_instance_valid(unit):
			unit.queue_free()
	_builders.clear()
	for root in _site_roots.values():
		if is_instance_valid(root):
			root.queue_free()
	_site_roots.clear()
