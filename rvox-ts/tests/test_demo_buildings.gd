@tool
extends McpTestSuite

## The data-driven building catalog (gameplan Priority 1): block counts, material
## costs, stations activated on completion, and watchtower flag — one entry per
## building, read by the run coordinator, HUD, and raid controller.


func suite_name() -> String:
	return "demo_buildings"


func test_catalog_describes_each_building() -> void:
	assert_true(DemoBuildings.has_building(&"forge"), "Forge is in the catalog")
	assert_false(DemoBuildings.has_building(&"space_elevator"), "Unknown buildings aren't")
	assert_eq(DemoBuildings.blocks(&"smelter"), 6, "Smelter block count")
	assert_eq(int(DemoBuildings.material(&"watchtower")[&"stone"]), 3, "Watchtower stone-per-block")


func test_stations_come_from_the_catalog() -> void:
	assert_eq(DemoBuildings.stations_for(&"smelter"), [&"smelt_iron_ingot"], "Smelter activates the smelt recipe")
	var forge := DemoBuildings.stations_for(&"forge")
	assert_eq(forge.size(), 2, "Forge activates two stations")
	assert_true(forge.has(&"craft_iron_sword"), "Including the sword recipe")
	assert_true(DemoBuildings.stations_for(&"storage_yard").is_empty(), "Storage yard has no stations")


func test_watchtower_flag() -> void:
	assert_true(DemoBuildings.is_watchtower(&"watchtower"), "Watchtower flagged")
	assert_false(DemoBuildings.is_watchtower(&"forge"), "Forge is not a watchtower")


func test_make_site_uses_catalog_values() -> void:
	var site := DemoBuildings.make_site(&"forge", Vector3(1, 2, 3))
	assert_eq(site.building_id, &"forge", "Site carries the id")
	assert_eq(site.total_blocks, 6, "Blocks from the catalog")
	assert_eq(site.position, Vector3(1, 2, 3), "Position set")
	assert_eq(int(site.material_for_block()[&"stone"]), 2, "Forge material-per-block from catalog")


func test_material_and_stations_are_copies() -> void:
	# Catalog callers must not be able to mutate the shared const data.
	var mat := DemoBuildings.material(&"forge")
	mat[&"wood"] = 999
	assert_eq(int(DemoBuildings.material(&"forge")[&"wood"]), 2, "material() returns a copy")
	var st := DemoBuildings.stations_for(&"forge")
	st.clear()
	assert_eq(DemoBuildings.stations_for(&"forge").size(), 2, "stations_for() returns a copy")
