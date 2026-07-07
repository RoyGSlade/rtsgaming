class_name DemoBuildings
extends RefCounted

## Data-driven catalog of the demo's buildings (the gameplan's Priority 1:
## data-driven buildings). One place defines each building's block count,
## per-block material cost, the production stations it brings online when
## finished, and whether it's a watchtower (for raid defense). RunCoordinator,
## the HUD, and the raid controller all read from here so costs stay consistent
## and a new building is one entry, not code scattered across files.

const DEFAULT_COLOR := Color(0.6, 0.55, 0.5)

const CATALOG := {
	&"storage_yard": {"blocks": 5, "material": {&"wood": 2}, "stations": [], "is_watchtower": false, "color": Color(0.55, 0.42, 0.26)},
	&"watchtower": {"blocks": 4, "material": {&"stone": 3}, "stations": [], "is_watchtower": true, "color": Color(0.5, 0.52, 0.55)},
	&"smelter": {"blocks": 6, "material": {&"stone": 3}, "stations": [&"smelt_iron_ingot"], "is_watchtower": false, "color": Color(0.5, 0.32, 0.28)},
	&"forge": {"blocks": 6, "material": {&"wood": 2, &"stone": 2}, "stations": [&"make_wood_handle", &"craft_iron_sword"], "is_watchtower": false, "color": Color(0.6, 0.38, 0.22)},
}


static func has_building(id: StringName) -> bool:
	return CATALOG.has(id)


static func blocks(id: StringName) -> int:
	return int(CATALOG.get(id, {}).get("blocks", 1))


static func material(id: StringName) -> Dictionary:
	return (CATALOG.get(id, {}).get("material", {}) as Dictionary).duplicate()


## Recipe ids for the stations this building activates on completion.
static func stations_for(id: StringName) -> Array:
	return (CATALOG.get(id, {}).get("stations", []) as Array).duplicate()


static func is_watchtower(id: StringName) -> bool:
	return bool(CATALOG.get(id, {}).get("is_watchtower", false))


## Display color for the finished building (BuildController renders it once the
## blocks are all placed).
static func color(id: StringName) -> Color:
	return CATALOG.get(id, {}).get("color", DEFAULT_COLOR)


## Build a construction site for a building id at a world position.
static func make_site(id: StringName, position: Vector3) -> BuildSite:
	return BuildSite.new(id, blocks(id), material(id), position)
