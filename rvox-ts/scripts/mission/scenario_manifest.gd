class_name ScenarioManifest
extends Resource

## The complete, recorded output of the scenario-placement pass (DEMO_PLAN.md
## §3): where the camp, resources, and raider camp are for one seed. A Resource
## so it serializes directly into the run save (§8) and could seed a
## multiplayer match. Everything here is in local chunk cell coordinates
## (Vector2i x,z); world Y is sampled from the heightmap at spawn time.

@export var seed: int = 0
@export var valid: bool = false
@export var failure_reason: String = ""

@export var camp_site: Vector2i = Vector2i.ZERO
@export var camp_radius: int = 6
@export var safety_radius: int = 24
@export var raider_camp: Vector2i = Vector2i.ZERO

## Each entry: { "resource_id": StringName, "cell": Vector2i, "amount": int }
@export var resource_nodes: Array[Dictionary] = []


func nodes_of(resource_id: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in resource_nodes:
		if StringName(n.get("resource_id", &"")) == resource_id:
			out.append(n)
	return out


func total_yield(resource_id: StringName) -> int:
	var sum := 0
	for n in nodes_of(resource_id):
		sum += int(n.get("amount", 0))
	return sum


## JSON-safe dictionary (Vector2i -> [x, y]) for the run save (§8). ResourceSaver
## could persist this Resource directly, but JSON keeps saves human-readable and
## migratable, which the plan wants.
func to_dict() -> Dictionary:
	var nodes: Array = []
	for n in resource_nodes:
		var cell: Vector2i = n["cell"]
		nodes.append({
			"resource_id": String(n["resource_id"]),
			"cell": [cell.x, cell.y],
			"amount": int(n["amount"]),
		})
	return {
		"seed": seed,
		"valid": valid,
		"failure_reason": failure_reason,
		"camp_site": [camp_site.x, camp_site.y],
		"camp_radius": camp_radius,
		"safety_radius": safety_radius,
		"raider_camp": [raider_camp.x, raider_camp.y],
		"resource_nodes": nodes,
	}


static func _to_cell(v: Variant) -> Vector2i:
	var arr: Array = v
	return Vector2i(int(arr[0]), int(arr[1]))


static func from_dict(data: Dictionary) -> ScenarioManifest:
	var m := ScenarioManifest.new()
	m.seed = int(data.get("seed", 0))
	m.valid = bool(data.get("valid", false))
	m.failure_reason = String(data.get("failure_reason", ""))
	m.camp_site = _to_cell(data.get("camp_site", [0, 0]))
	m.camp_radius = int(data.get("camp_radius", 6))
	m.safety_radius = int(data.get("safety_radius", 24))
	m.raider_camp = _to_cell(data.get("raider_camp", [0, 0]))
	var nodes: Array[Dictionary] = []
	for n in data.get("resource_nodes", []):
		nodes.append({
			"resource_id": StringName(n["resource_id"]),
			"cell": _to_cell(n["cell"]),
			"amount": int(n["amount"]),
		})
	m.resource_nodes = nodes
	return m
