class_name RunCoordinator
extends Node

## Wires the tested backend systems into the live scene (DEMO_PLAN.md §3/§4/§7):
## on each world generation it plans a scenario, builds the economy from the
## manifest, starts the run director, and drops in-world markers so the camp,
## resource nodes, and raider camp are visible. GameMain owns one of these and
## connects the HUD to `economy`/`director`.
##
## Everything is additive and null-guarded: if planning fails or the world
## isn't ready, the rest of the scene is unaffected.

signal scenario_ready(manifest: ScenarioManifest)
signal economy_ready(economy: EconomyController)
## Emitted when a forged sword is turned into a swordsman; GameMain spawns the
## visual soldier at the given position.
signal swordsman_trained(spawn_position: Vector3)

## Emitted once a run ends, after the reward is banked; carries the outcome and
## the blueprint unlocked this run (&"" if none/loss). GameMain shows results.
signal run_resolved(outcome: int, unlock_id: StringName)

## Auto-train up to this many swordsmen from banked swords (the objective goal).
const SWORDSMAN_GOAL := 3
const TRAIN_INTERVAL := 1.0

## Blueprints a win can unlock, in award order (DEMO_PLAN.md §9). The Blueprint
## Gallery is the demo's trophy room; each win banks the next locked one.
const UNLOCKABLES: Array[StringName] = [
	&"stone_walls", &"watchtower_ii", &"reinforced_hall", &"granary", &"training_yard",
]

## Starting stockpile — mirrors the HUD's old placeholder so bar values are
## unchanged when the HUD switches to reading the controller.
const STARTING_STOCK := {
	&"wood": 250, &"stone": 180, &"food": 120,
	&"raw_ore": 0, &"coal": 0, &"iron_ingot": 0,
}

const MARKER_COLORS := {
	&"wood": Color(0.45, 0.30, 0.15),
	&"raw_ore": Color(0.50, 0.42, 0.55),
	&"coal": Color(0.12, 0.12, 0.14),
}

var world: WorldRuntime
var stockpile_position: Vector3
var raider_camp_position: Vector3

var economy: EconomyController
var director: MissionDirector
var manifest: ScenarioManifest

var profile: ProfileStore

var _planner := ScenarioPlanner.new()
var _markers_root: Node3D
var _train_accum := 0.0


func _ready() -> void:
	profile = ProfileStore.new()
	profile.load_profile()
	if world == null:
		push_warning("RunCoordinator has no world; skipping run setup")
		return
	world.world_generated.connect(_on_world_generated)
	if world.current_chunk != null:
		_rebuild()


func _on_world_generated(_summary: Dictionary) -> void:
	_rebuild()


func _process(delta: float) -> void:
	if director != null:
		director.advance(delta)
	if economy != null:
		economy.tick(delta)
		_train_accum += delta
		if _train_accum >= TRAIN_INTERVAL:
			_train_accum = 0.0
			_try_train_swordsman()


## Turn one banked sword into a swordsman, up to the objective goal. The forged
## sword is the gate (RUN_RULES: recruit + iron_sword -> swordsman); the visual
## soldier is spawned by GameMain via the swordsman_trained signal.
func _try_train_swordsman() -> void:
	if economy == null or director == null:
		return
	if director.swordsmen_trained >= SWORDSMAN_GOAL:
		return
	if economy.get_stock(&"iron_sword") > 0:
		economy.remove_stock(&"iron_sword", 1)
		director.record_swordsman_trained(1)
		swordsman_trained.emit(stockpile_position)


## (Re)build the whole run for the current world. Safe to call on every
## regenerate — old systems are torn down first.
func _rebuild() -> void:
	_teardown()

	manifest = _planner.plan(world.current_chunk, world.config)

	# The stockpile — where villagers spawn, deposit, and the camera frames — is
	# the planned camp, not the map centre (nodes are placed around the camp).
	if manifest.valid:
		stockpile_position = _cell_to_world(manifest.camp_site)
		raider_camp_position = _cell_to_world(manifest.raider_camp)
	else:
		stockpile_position = world.get_world_center()
		raider_camp_position = world.get_world_center()

	economy = EconomyController.new()
	economy.name = "Economy"
	add_child(economy)
	economy.seed_stock(STARTING_STOCK)
	_register_stations()
	economy.production_finished.connect(_on_production_finished)

	if manifest.valid:
		economy.populate_from_manifest(manifest, world.current_chunk)
		_spawn_markers()
		_spawn_starter_building()
	else:
		push_warning("Scenario invalid for seed %d: %s" % [world.config.world_seed, manifest.failure_reason])

	director = MissionDirector.new()
	director.name = "Director"
	add_child(director)
	director.run_ended.connect(_on_run_ended)
	director.present_briefing()
	director.begin_run()

	economy_ready.emit(economy)
	scenario_ready.emit(manifest)
	print("[RunCoordinator] seed=%d scenario_valid=%s nodes=%d camp=%s raider=%s" % [
		world.config.world_seed, manifest.valid, manifest.resource_nodes.size(),
		manifest.camp_site, manifest.raider_camp])


## Register the demo production chain as stations feeding off central stock:
## smelter (ingots), forge-handles, forge-swords. Three stations because a
## station runs one recipe and the forge does two jobs in the demo chain.
## A starter Storage Yard next to the camp so a builder visibly raises a
## building block-by-block from the opening moments (DEMO_PLAN.md §5).
func _spawn_starter_building() -> void:
	var yard_pos := stockpile_position + Vector3(7.0, 0.0, 0.0)
	yard_pos.y = world.get_ground_height(yard_pos.x, yard_pos.z)
	economy.register_build_site(BuildSite.new(&"storage_yard", 5, {&"wood": 2}, yard_pos))
	# A watchtower the builders raise; once complete it strengthens raid defense.
	var tower_pos := stockpile_position + Vector3(-7.0, 0.0, 4.0)
	tower_pos.y = world.get_ground_height(tower_pos.x, tower_pos.z)
	economy.register_build_site(BuildSite.new(&"watchtower", 4, {&"stone": 3}, tower_pos))


func _register_stations() -> void:
	for recipe_id: StringName in [&"smelt_iron_ingot", &"make_wood_handle", &"craft_iron_sword"]:
		var recipe := DemoChain.recipe_by_id(recipe_id)
		if recipe != null:
			economy.register_station(ProductionStation.new(recipe.required_station, recipe))


func _on_production_finished(_station_id: StringName, recipe_id: StringName) -> void:
	if recipe_id == &"craft_iron_sword" and director != null:
		director.record_sword_produced(1)


## Bank the run result when it ends: a win unlocks the next locked blueprint
## (idempotently — the run ends exactly once, and award_unlock dedupes), stats
## are recorded, and the profile is saved atomically. Then results are shown.
func _on_run_ended(outcome: int) -> void:
	var won := outcome == MissionDirector.Outcome.WIN
	var unlock := &""
	if profile != null:
		if won:
			unlock = _next_unlock()
			if unlock != &"":
				profile.award_unlock(unlock)
		profile.record_run_result(won, director.swords_produced if director != null else 0)
		profile.save_profile()
	run_resolved.emit(outcome, unlock)


## The first blueprint not yet unlocked, or &"" once every reward is earned.
func _next_unlock() -> StringName:
	if profile == null:
		return &""
	for id in UNLOCKABLES:
		if not profile.is_unlocked(id):
			return id
	return &""


func _teardown() -> void:
	if economy != null:
		economy.queue_free()
		economy = null
	if director != null:
		director.queue_free()
		director = null
	if _markers_root != null:
		_markers_root.queue_free()
		_markers_root = null


## Drop simple emissive markers for each resource node, the camp, and the
## raider camp so the planned scenario is legible in-game before real props
## exist. World Y comes from the terrain sampler.
func _spawn_markers() -> void:
	_markers_root = Node3D.new()
	_markers_root.name = "ScenarioMarkers"
	add_child(_markers_root)

	for node in economy.nodes():
		_add_marker(node.world_position, MARKER_COLORS.get(node.resource_id, Color.WHITE), 0.6, 1.5)

	_add_marker(_cell_to_world(manifest.camp_site), Color(0.30, 0.85, 0.45), 1.2, 0.5)
	_add_marker(_cell_to_world(manifest.raider_camp), Color(0.90, 0.25, 0.25), 1.0, 2.0)


func _cell_to_world(cell: Vector2i) -> Vector3:
	var y := world.get_ground_height(float(cell.x) + 0.5, float(cell.y) + 0.5)
	return Vector3(cell.x + 0.5, y, cell.y + 0.5)


func _add_marker(base: Vector3, color: Color, radius: float, height: float) -> void:
	var m := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	m.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.4
	m.material_override = mat
	m.position = base + Vector3(0.0, height * 0.5, 0.0)
	_markers_root.add_child(m)
