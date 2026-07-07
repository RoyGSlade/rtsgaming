class_name EconomyController
extends Node

## The authoritative runtime owner of the demo economy (DEMO_PLAN.md §4): the
## central stockpile, the job board, every placed resource node, and every
## production station. The HUD and other UI *read* from here and never own
## resource state themselves. Stations are ticked from here so a single game
## loop drives all production.
##
## Testable without the scene tree: construct it, register nodes/stations, add
## stock, tick. Its StorageInventory is added as a child so it's freed with the
## controller.

signal stock_changed(item_id: StringName, amount: int)
signal production_finished(station_id: StringName, recipe_id: StringName)
signal building_completed(building_id: StringName)
signal build_site_added(site: BuildSite)

var job_board := JobBoard.new()

var _stock: StorageInventory
var _nodes: Array[ResourceNode] = []
var _stations: Array[ProductionStation] = []
var _build_sites: Array[BuildSite] = []


func _init(capacity_per_item: int = 9999) -> void:
	_stock = StorageInventory.new()
	_stock.capacity_per_item = capacity_per_item
	add_child(_stock)


# ----- central stockpile -----

func get_stock(item_id: StringName) -> int:
	return _stock.get_amount(item_id)


## Snapshot of the whole stockpile as a plain dict (for the HUD, the diagnoser,
## and saves).
func stock_snapshot() -> Dictionary:
	return _stock.items.duplicate()


func add_stock(item_id: StringName, amount: int) -> int:
	var accepted := _stock.add_item(item_id, amount)
	if accepted > 0:
		stock_changed.emit(item_id, _stock.get_amount(item_id))
	return accepted


func remove_stock(item_id: StringName, amount: int) -> int:
	var removed := _stock.remove_item(item_id, amount)
	if removed > 0:
		stock_changed.emit(item_id, _stock.get_amount(item_id))
	return removed


func can_afford(cost: Dictionary) -> bool:
	for key in cost.keys():
		if _stock.get_amount(StringName(key)) < int(cost[key]):
			return false
	return true


## Deduct a cost dict atomically; returns false and changes nothing if the full
## cost isn't covered.
func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for key in cost.keys():
		remove_stock(StringName(key), int(cost[key]))
	return true


func seed_stock(initial: Dictionary) -> void:
	for key in initial.keys():
		add_stock(StringName(key), int(initial[key]))


# ----- resource nodes -----

func register_node(node: ResourceNode) -> void:
	_nodes.append(node)


func nodes() -> Array[ResourceNode]:
	return _nodes


func nodes_of(resource_id: StringName) -> Array[ResourceNode]:
	var out: Array[ResourceNode] = []
	for n in _nodes:
		if n.resource_id == resource_id and not n.is_depleted():
			out.append(n)
	return out


## Nearest non-depleted node of a resource with units still free to reserve.
## The seed of worker gather-target selection.
func nearest_available_node(resource_id: StringName, from: Vector3) -> ResourceNode:
	var best: ResourceNode = null
	var best_d := INF
	for n in _nodes:
		if n.resource_id != resource_id or n.available() <= 0:
			continue
		var d := from.distance_squared_to(n.world_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## Register every node in a planned scenario, sampling world height from chunk.
func populate_from_manifest(manifest: ScenarioManifest, chunk: ChunkData) -> void:
	for node in ScenarioPlanner.to_resource_nodes(manifest, chunk):
		register_node(node)


# ----- production stations -----

func register_station(station: ProductionStation) -> void:
	station.production_finished.connect(func(recipe_id: StringName, _outputs: Dictionary) -> void:
		production_finished.emit(station.station_id, recipe_id))
	_stations.append(station)


func stations() -> Array[ProductionStation]:
	return _stations


func stations_of(station_type: StringName) -> Array[ProductionStation]:
	var out: Array[ProductionStation] = []
	for s in _stations:
		if s.station_id == station_type:
			out.append(s)
	return out


## Advance every station. The central stockpile is the shared buffer: each
## station pulls a craft's worth of inputs from stock, crafts, and pushes its
## outputs back to stock, so gathered raw materials flow through the whole chain
## into swords without per-station micromanagement. (The visible hauler *between*
## stockpile and station is abstracted for now — villagers still visibly haul
## raw materials *into* the stockpile; inter-station hauling is a later polish.)
func tick(delta: float) -> void:
	for station in _stations:
		_feed_station(station)
		if not station.is_active() and station.can_start():
			station.start()
		station.tick(delta)
		_drain_station(station)


# ----- construction -----

## Register a site and post a construct job so a builder claims and raises it.
func register_build_site(site: BuildSite) -> void:
	site.completed.connect(func() -> void: building_completed.emit(site.building_id))
	_build_sites.append(site)
	job_board.post(&"construct", {"site": site}, 5, &"builder")
	build_site_added.emit(site)


func build_sites() -> Array[BuildSite]:
	return _build_sites


## Can the stockpile currently afford one block's materials for this site?
func can_afford_block(site: BuildSite) -> bool:
	return can_afford(site.material_for_block())


## Consume one block's materials from the stockpile. Returns false (unchanged)
## if the stockpile can't cover it.
func take_block_materials(site: BuildSite) -> bool:
	return pay(site.material_for_block())


## Pull inputs from central stock into a station — but only when a full craft is
## affordable, so partial inputs aren't hoarded into a stalled station.
func _feed_station(station: ProductionStation) -> void:
	if station.recipe == null or station.is_active():
		return
	for key in station.recipe.inputs.keys():
		var need := int(station.recipe.inputs[key])
		if station.input.get_amount(StringName(key)) + get_stock(StringName(key)) < need:
			return
	for key in station.recipe.inputs.keys():
		var need := int(station.recipe.inputs[key])
		var have := station.input.get_amount(StringName(key))
		if have < need:
			var move := mini(need - have, get_stock(StringName(key)))
			if move > 0:
				remove_stock(StringName(key), move)
				station.input.add_item(StringName(key), move)


## Push finished goods from a station's output back into central stock.
func _drain_station(station: ProductionStation) -> void:
	for item_id in station.output.items.keys():
		var amount := station.output.get_amount(StringName(item_id))
		if amount > 0:
			var accepted := add_stock(StringName(item_id), amount)
			station.output.remove_item(StringName(item_id), accepted)


# ----- readability -----

## Why can't we make `target_item` right now? Traces the bottleneck against the
## current stockpile (DEMO_PLAN.md §4 "why are swords slow").
func diagnose(target_item: StringName, count: int = 1) -> Dictionary:
	return DemoChain.diagnose(target_item, stock_snapshot(), count)
