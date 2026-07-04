@tool
extends McpTestSuite

const DocumentScript := preload("res://addons/world_forge/model/forge_document.gd")
const HistoryScript := preload("res://addons/world_forge/model/forge_history.gd")
const RecipeScript := preload("res://addons/world_forge/model/forge_recipe_definition.gd")
const AssemblyScript := preload("res://addons/world_forge/model/assembly_definition.gd")
const RuleScript := preload("res://addons/world_forge/model/simulation_rule_definition.gd")
const ShapeFactory := preload("res://addons/world_forge/model/shape_geometry_factory.gd")
const SnapResolver := preload("res://addons/world_forge/model/component_snap_resolver.gd")
const MaterialPropertiesScript := preload("res://addons/world_forge/model/material_properties.gd")
const PartProfileScript := preload("res://addons/world_forge/model/part_profile.gd")
const MaterialRegistryScript := preload("res://addons/world_forge/model/material_registry.gd")
const PartRegistryScript := preload("res://addons/world_forge/model/part_registry.gd")
const ShapeRegistryScript := preload("res://addons/world_forge/model/shape_registry.gd")
const ComponentRegistryScript := preload("res://addons/world_forge/model/component_registry.gd")
const MarkerRegistryScript := preload("res://addons/world_forge/model/marker_registry.gd")
const PartGeometryFactory := preload("res://addons/world_forge/model/part_geometry_factory.gd")
const PartSnapResolver := preload("res://addons/world_forge/model/part_snap_resolver.gd")
const PartKineticsCompiler := preload("res://addons/world_forge/model/part_kinetics_compiler.gd")


func suite_name() -> String:
	return "world_forge"


func test_editor_script_compiles() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	assert_true(script != null, "World Forge main-screen script should load")
	if script != null:
		assert_true(script.can_instantiate(), "World Forge main-screen script should compile")
		var editor: Control = track(script.new()) as Control
		editor.setup(null)
		assert_gt(editor.get_child_count(), 0, "World Forge should construct its full-screen UI")


func test_document_roundtrip_preserves_editor_element_types() -> void:
	var document: ForgeDocument = DocumentScript.new()
	document.document_id = "fixture_camp"
	document.template_kind = "encounter"
	document.set_block(Vector3i(2, 1, 3), {"block_id": "stone", "shape_id": "stair"})
	document.components.append({"id": "forge", "component_id": "forge_firebox", "pos": [3, 1, 3]})
	document.markers.append({"id": "spawn", "marker_type": "unit_spawn", "pos": [0, 0, 0]})
	document.nested_instances.append({"id": "hut", "source_path": "res://data/buildings/hut.json", "origin": [5, 0, 5], "finalized": false})
	var path := "user://world_forge_roundtrip.json"
	assert_eq(document.save_json(path), OK)
	var loaded: ForgeDocument = DocumentScript.load_json(path)
	assert_true(loaded != null)
	if loaded == null:
		return
	assert_eq(loaded.document_id, "fixture_camp")
	assert_eq(loaded.template_kind, "encounter")
	assert_true(loaded.has_block(Vector3i(2, 1, 3)))
	assert_eq(loaded.components.size(), 1)
	assert_eq(loaded.markers.size(), 1)
	assert_eq(loaded.nested_instances.size(), 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_history_treats_multi_block_edit_as_one_transaction() -> void:
	var document: ForgeDocument = DocumentScript.new()
	var history: ForgeHistory = HistoryScript.new()
	var before := document.snapshot()
	document.set_block(Vector3i(0, 0, 0), {"block_id": "stone"})
	document.set_block(Vector3i(1, 0, 0), {"block_id": "stone"})
	document.set_block(Vector3i(2, 0, 0), {"block_id": "stone"})
	history.record("Draw line", before, document.snapshot())
	assert_eq(document.blocks.size(), 3)
	assert_eq(history.undo(document), "Draw line")
	assert_eq(document.blocks.size(), 0, "One undo should remove the whole line")
	assert_eq(history.redo(document), "Draw line")
	assert_eq(document.blocks.size(), 3)


func test_legacy_blueprint_blocks_are_normalized() -> void:
	var path := "user://world_forge_legacy.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": "legacy", "blocks": [{"pos": [4, 2, 1], "block_id": "wood_planks"}]}))
	file.close()
	var document: ForgeDocument = DocumentScript.load_json(path)
	assert_true(document != null)
	if document != null:
		assert_true(document.has_block(Vector3i(4, 2, 1)))
		assert_eq(document.get_block(Vector3i(4, 2, 1)).get("kind"), "block")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_rules_recipes_and_assemblies_are_capability_driven() -> void:
	var recipe = RecipeScript.new()
	recipe.required_capabilities = PackedStringArray(["heat_source", "smelting_chamber"])
	assert_true(recipe.validates_capabilities(PackedStringArray(["heat_source", "smelting_chamber", "exhaust"])))
	assert_false(recipe.validates_capabilities(PackedStringArray(["heat_source"])))
	var assembly = AssemblyScript.new()
	assembly.required_pieces.append({"component_id": "firebox", "amount": 1})
	assembly.required_pieces.append({"component_id": "brick", "amount": 8})
	assert_eq(assembly.required_piece_count(), 9)
	var fire_rule = RuleScript.new()
	fire_rule.required_source_tags = PackedStringArray(["fire"])
	fire_rule.required_target_tags = PackedStringArray(["flammable"])
	assert_true(fire_rule.can_consider(PackedStringArray(["fire"]), PackedStringArray(["wood", "flammable"])))
	assert_false(fire_rule.can_consider(PackedStringArray(["fire"]), PackedStringArray(["stone"])))


func test_shape_factory_builds_distinct_procedural_shapes() -> void:
	var material := StandardMaterial3D.new()
	var cube: Node3D = track(ShapeFactory.create_shape("cube", 0, 0, material)) as Node3D
	var slab: Node3D = track(ShapeFactory.create_shape("slab", 0, 0, material)) as Node3D
	var stair: Node3D = track(ShapeFactory.create_shape("stair", 1, 0, material)) as Node3D
	var fence: Node3D = track(ShapeFactory.create_shape("fence", 0, ShapeFactory.NORTH | ShapeFactory.EAST, material)) as Node3D
	assert_eq(cube.get_child_count(), 1)
	assert_eq(slab.get_child_count(), 1)
	assert_eq(stair.get_child_count(), 2)
	assert_eq(fence.get_child_count(), 5, "Post plus two rails for each connected direction")
	assert_true(not is_zero_approx(stair.rotation.y), "Stairs should honor placement rotation")


func test_connected_shape_mask_tracks_cardinal_neighbors() -> void:
	var document: ForgeDocument = DocumentScript.new()
	document.set_block(Vector3i.ZERO, {"block_id": "wood", "shape_id": "fence"})
	document.set_block(Vector3i.RIGHT, {"block_id": "wood", "shape_id": "fence"})
	document.set_block(Vector3i(0, 0, -1), {"block_id": "stone", "shape_id": "cube"})
	var mask: int = ShapeFactory.connection_mask_for(document, Vector3i.ZERO, "fence")
	assert_true(bool(mask & ShapeFactory.EAST))
	assert_true(bool(mask & ShapeFactory.NORTH))
	assert_false(bool(mask & ShapeFactory.SOUTH))


func test_component_ports_snap_and_rotate() -> void:
	var document: ForgeDocument = DocumentScript.new()
	var firebox := {"id": "firebox", "footprint": [[0, 0, 0]], "ports": [{"type": "heat", "accepts": ["heat"], "cell": [0, 0, 0], "facing": [0, 1, 0]}]}
	var chamber := {"id": "chamber", "footprint": [[0, 0, 0]], "ports": [{"type": "heat", "accepts": ["heat"], "cell": [0, 0, 0], "facing": [0, -1, 0]}]}
	document.components.append({"id": "base", "component_id": "firebox", "pos": [2, 0, 2], "rotation_steps": 0, "definition": firebox})
	var result: Dictionary = SnapResolver.find_snapped_origin(document, Vector3i(2, 1, 2), chamber, 0, [firebox, chamber])
	assert_true(result.get("found", false))
	assert_eq(result.get("origin"), Vector3i(2, 1, 2))
	assert_eq(result.get("port"), "heat")
	assert_eq(SnapResolver.rotate_offset(Vector3i(1, 0, 0), 1), Vector3i(0, 0, 1))


func test_shell_and_box_build_as_single_undoable_actions() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var document: ForgeDocument = editor.get("_document")
	editor.set("_tool", "shell")
	editor.call("_handle_two_point_tool", Vector3i.ZERO)
	editor.call("_handle_two_point_tool", Vector3i(2, 2, 2))
	assert_eq(document.blocks.size(), 26, "A 3x3x3 hollow shell has 26 boundary cells")
	editor.call("_undo")
	assert_eq(document.blocks.size(), 0, "One undo should remove the entire shell")
	editor.set("_tool", "box")
	editor.call("_handle_two_point_tool", Vector3i.ZERO)
	editor.call("_handle_two_point_tool", Vector3i(2, 2, 2))
	assert_eq(document.blocks.size(), 27, "Filled box should include its center")


func test_connected_selection_crosses_mixed_structural_materials() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var document: ForgeDocument = editor.get("_document")
	document.set_block(Vector3i.ZERO, {"block_id": "stone", "shape_id": "cube"})
	document.set_block(Vector3i.RIGHT, {"block_id": "wood", "shape_id": "stair"})
	document.set_block(Vector3i(2, 0, 0), {"block_id": "glass", "shape_id": "pane"})
	document.set_block(Vector3i(8, 0, 0), {"block_id": "stone", "shape_id": "cube"})
	editor.call("_select_connected", Vector3i.ZERO)
	var selected: Dictionary = editor.get("_selected_cells")
	assert_eq(selected.size(), 3, "Connected select should follow the structure, not only one material")


# --- Crafting-plan foundation: MaterialProperties / PartProfile (plan section 3-4) ---


func test_material_properties_expose_thermal_and_flammability_helpers() -> void:
	var material: MaterialProperties = MaterialPropertiesScript.new()
	material.density_kg_m3 = 7850.0
	material.ignition_temp_c = -1.0
	material.melting_temp_c = 1450.0
	material.working_temp_c = 850.0
	assert_false(material.is_flammable(), "Steel-like material should not be flammable")
	assert_true(material.can_melt())
	assert_true(material.can_forge())
	assert_eq(material.mass_for_volume(2.0), 15700.0)
	var wood: MaterialProperties = MaterialPropertiesScript.new()
	wood.ignition_temp_c = 300.0
	wood.melting_temp_c = -1.0
	assert_true(wood.is_flammable())
	assert_false(wood.can_melt())


func test_material_registry_loads_starter_material_set() -> void:
	var registry: MaterialRegistry = track(MaterialRegistryScript.new()) as MaterialRegistry
	registry.load_materials()
	for id: StringName in [&"oak", &"steel", &"bronze", &"iron_ore", &"bloom_iron", &"charcoal", &"water", &"firebrick"]:
		assert_true(registry.has_material(id), "Missing starter material: %s" % id)
	var steel: MaterialProperties = registry.get_material(&"steel")
	assert_true(steel != null)
	if steel != null:
		assert_true(steel.can_melt())
		assert_eq(steel.molten_material_id, &"molten_steel")


func test_material_molten_references_resolve_to_registered_materials() -> void:
	# Every material that melts into something must name a molten material
	# that actually exists - a dangling molten_material_id would silently
	# break Phase 6 casting later, so this is checked now while the data set
	# is still small enough to eyeball.
	var registry: MaterialRegistry = track(MaterialRegistryScript.new()) as MaterialRegistry
	registry.load_materials()
	for id: StringName in registry.list_ids():
		var material: MaterialProperties = registry.get_material(id)
		if material.molten_material_id != &"":
			assert_true(registry.has_material(material.molten_material_id),
				"%s names molten_material_id %s which is not a registered material" % [id, material.molten_material_id])


func test_part_profile_resolves_mass_from_material_when_unset() -> void:
	var part: PartProfile = PartProfileScript.new()
	part.collision_boxes = [AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1.0, 1.0, 1.0))]
	part.mass_kg = 0.0
	var steel: MaterialProperties = MaterialPropertiesScript.new()
	steel.density_kg_m3 = 8000.0
	assert_eq(part.bounds_volume_m3(), 1.0)
	assert_eq(part.resolved_mass_kg(steel), 8000.0)
	part.mass_kg = 42.0
	assert_eq(part.resolved_mass_kg(steel), 42.0, "An explicit mass_kg should override the derived value")


func test_part_profile_occupancy_for_box_matches_cell_grid() -> void:
	var cells := PartProfileScript.occupancy_for_box(Vector3(0.2, 0.05, 1.0), 0.125)
	assert_eq(cells.size(), 2 * 1 * 8, "0.2/0.05/1.0m at a 0.125m cell size should be a 2x1x8 grid")
	assert_true(Vector3i(0, 0, 0) in cells)
	assert_true(Vector3i(1, 0, 7) in cells)
	assert_false(Vector3i(2, 0, 0) in cells)


func test_part_registry_loads_starter_parts_with_valid_material_and_sockets() -> void:
	var materials: MaterialRegistry = track(MaterialRegistryScript.new()) as MaterialRegistry
	materials.load_materials()
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	for id: StringName in [&"steel_rod", &"steel_sheet", &"wood_beam", &"wood_plank", &"wheel", &"axle", &"rope_segment", &"crucible"]:
		assert_true(parts.has_part(id), "Missing starter part: %s" % id)
		var part: PartProfile = parts.get_part(id)
		assert_true(materials.has_material(part.material_id),
			"%s references material_id %s which is not registered" % [id, part.material_id])
		assert_gt(part.sockets.size(), 0, "%s should expose at least one socket" % id)
		assert_gt(part.occupancy.size(), 0, "%s should occupy at least one fine-grid cell" % id)
	var rod: PartProfile = parts.get_part(&"steel_rod")
	var weld_sockets := rod.sockets_of_kind("weld")
	assert_eq(weld_sockets.size(), 2, "Steel rod should weld/hinge at both ends")
	var wheel: PartProfile = parts.get_part(&"wheel")
	var bearing_sockets := wheel.sockets_of_kind("bearing")
	assert_eq(bearing_sockets.size(), 1, "Wheel should expose exactly one bore socket")


# --- Crafting-plan foundation: SHAPES/COMPONENTS/MARKERS as .tres (plan section 2) ---


func test_shape_registry_loads_starter_shape_set_in_palette_order() -> void:
	var registry: ShapeRegistry = track(ShapeRegistryScript.new()) as ShapeRegistry
	registry.load_shapes()
	var expected: Array[StringName] = [&"cube", &"slab", &"slab_top", &"stair", &"fence", &"pane", &"plate"]
	for id: StringName in expected:
		assert_true(registry.has_shape(id), "Missing starter shape: %s" % id)
	assert_eq(registry.list_ids(), expected, "Shape palette order should match the original hardcoded array")
	var stair: BlockShapeProfile = registry.get_shape(&"stair")
	assert_true(stair.supports_rotation, "Stairs should still be marked rotatable")


func test_component_registry_loads_starter_components_with_correct_fields() -> void:
	var registry: ComponentRegistry = track(ComponentRegistryScript.new()) as ComponentRegistry
	registry.load_components()
	for id: StringName in [&"forge_firebox", &"forge_furnace", &"forge_chimney", &"anvil", &"workbench", &"bellows", &"storage_crate", &"water_source", &"fire_source"]:
		assert_true(registry.has_component(id), "Missing starter component: %s" % id)
	var firebox: FunctionalComponentDefinition = registry.get_component(&"forge_firebox")
	assert_eq(firebox.display_name, "Forge Firebox")
	assert_eq(firebox.color, Color("d65a31"), "Color should round-trip through the .tres exactly")
	assert_false(firebox.snap_required)
	assert_eq(firebox.ports.size(), 2)
	assert_true(firebox.has_capability(&"heat_source"))
	assert_eq(firebox.rules.size(), 1)
	assert_eq(float(firebox.rules[0].get("temperature", 0.0)), 900.0)
	var furnace: FunctionalComponentDefinition = registry.get_component(&"forge_furnace")
	assert_true(furnace.snap_required, "Furnace chamber should still require snapping to a firebox")
	var chimney: FunctionalComponentDefinition = registry.get_component(&"forge_chimney")
	assert_eq(chimney.footprint, [Vector3i(0, 0, 0), Vector3i(0, 1, 0)], "Chimney should keep its 1x2 footprint")


func test_marker_registry_loads_starter_marker_set_with_correct_colors() -> void:
	var registry: MarkerRegistry = track(MarkerRegistryScript.new()) as MarkerRegistry
	registry.load_markers()
	for id: StringName in [&"worker_position", &"entrance", &"item_dropoff", &"item_pickup", &"unit_spawn", &"resource_node", &"patrol_point"]:
		assert_true(registry.has_marker(id), "Missing starter marker: %s" % id)
	var worker_marker: MarkerDefinition = registry.get_marker(&"worker_position")
	assert_eq(worker_marker.color, Color("54d6a1"), "Color should round-trip through the .tres exactly")


func test_editor_catalogs_load_from_registries_and_preserve_dict_shape() -> void:
	# End-to-end: the editor's _shapes/_components/_markers arrays (consumed
	# by SnapResolver and rendering) must come out identical in shape to the
	# dictionaries they replaced, not just the underlying resources loading.
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var shapes: Array = editor.get("_shapes")
	var components: Array = editor.get("_components")
	var markers: Array = editor.get("_markers")
	assert_eq(shapes.size(), 7)
	assert_eq(components.size(), 9)
	assert_eq(markers.size(), 7)
	var firebox: Dictionary = editor.call("_find_definition", components, "forge_firebox")
	assert_eq(firebox.get("name"), "Forge Firebox")
	assert_eq(firebox.get("color"), Color("d65a31"))
	assert_eq(firebox.get("footprint"), [[0, 0, 0]])
	assert_false(firebox.has("snap_required"), "snap_required should be omitted (falsy) exactly like the original literal dicts")
	var furnace: Dictionary = editor.call("_find_definition", components, "forge_furnace")
	assert_true(bool(furnace.get("snap_required", false)))
	var worker_marker: Dictionary = editor.call("_find_definition", markers, "worker_position")
	assert_eq(worker_marker.get("color"), Color("54d6a1"))


# --- Crafting-plan Phase 3 slice: PartGeometryFactory + Workshop documents ---


func test_part_geometry_factory_builds_distinct_geometry_kinds() -> void:
	var material := StandardMaterial3D.new()
	var box_part: PartProfile = PartProfileScript.new()
	box_part.geometry_kind = PartProfile.GeometryKind.BOX
	box_part.geometry_params = {"size": Vector3(0.1, 0.1, 2.0)}
	var box_root: Node3D = track(PartGeometryFactory.create_part(box_part, material)) as Node3D
	assert_eq(box_root.get_child_count(), 1)
	var box_mesh: MeshInstance3D = box_root.get_child(0)
	assert_true(box_mesh.mesh is BoxMesh)

	var cyl_part: PartProfile = PartProfileScript.new()
	cyl_part.geometry_kind = PartProfile.GeometryKind.CYLINDER
	cyl_part.geometry_params = {"radius": 0.025, "height": 1.0}
	var cyl_root: Node3D = track(PartGeometryFactory.create_part(cyl_part, material)) as Node3D
	assert_eq(cyl_root.get_child_count(), 1)
	var cyl_mesh: MeshInstance3D = cyl_root.get_child(0)
	assert_true(cyl_mesh.mesh is CylinderMesh)
	var up_on_default_axis: Vector3 = cyl_mesh.quaternion * Vector3.UP
	assert_true(up_on_default_axis.is_equal_approx(Vector3(0, 0, 1)), "Default long_axis (Z) should rotate the mesh's +Y onto +Z")

	var vessel_part: PartProfile = PartProfileScript.new()
	vessel_part.geometry_kind = PartProfile.GeometryKind.CYLINDER
	vessel_part.geometry_params = {"radius": 0.15, "height": 0.25}
	vessel_part.long_axis = Vector3(0, 1, 0)
	var vessel_root: Node3D = track(PartGeometryFactory.create_part(vessel_part, material)) as Node3D
	var vessel_mesh: MeshInstance3D = vessel_root.get_child(0)
	var up_on_vessel_axis: Vector3 = vessel_mesh.quaternion * Vector3.UP
	assert_true(up_on_vessel_axis.is_equal_approx(Vector3(0, 1, 0)), "A vessel's long_axis (Y) should leave the mesh's own +Y pointing up, unrotated")

	var sphere_part: PartProfile = PartProfileScript.new()
	sphere_part.geometry_kind = PartProfile.GeometryKind.SPHERE
	sphere_part.geometry_params = {"radius": 0.2}
	var sphere_root: Node3D = track(PartGeometryFactory.create_part(sphere_part, material)) as Node3D
	assert_true((sphere_root.get_child(0) as MeshInstance3D).mesh is SphereMesh)

	var custom_part: PartProfile = PartProfileScript.new()
	custom_part.geometry_kind = PartProfile.GeometryKind.CUSTOM
	var custom_root: Node3D = track(PartGeometryFactory.create_part(custom_part, material)) as Node3D
	assert_eq(custom_root.get_child_count(), 0, "CUSTOM with no custom_mesh assigned should build nothing rather than guess")


func test_part_palette_lists_starter_parts() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var parts: Array = editor.get("_parts")
	assert_eq(parts.size(), 8)
	var part_list: ItemList = editor.get("_part_list")
	assert_true(part_list != null)
	assert_eq(part_list.item_count, 8)


func test_placing_a_part_stores_it_on_the_fine_grid_and_renders() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	editor.set("_selected_part_id", &"wood_beam")
	editor.set("_place_kind", "part")
	editor.set("_brush_rotation", 1)
	var content_root: Node3D = editor.get("_content_root")
	var children_before := content_root.get_child_count()
	# _place_at's "part" branch still takes a coarse structure cell and
	# converts internally (via _place_part_at_fine_cell) - this keeps every
	# existing macro/test/command that calls _place_at directly working
	# unchanged. Genuine sub-cell fine-grid placement (the actual point of
	# this step) goes through _place_part_at_fine_cell directly instead -
	# see test_placing_a_part_at_a_true_sub_cell_fine_position below.
	var fine_cell := Vector3i(16, 0, 24)
	editor.call("_place_at", Vector3i(2, 0, 3))
	var document: ForgeDocument = editor.get("_document")
	assert_true(document.has_placed_part(fine_cell), "Part should be stored at the fine-grid cell")
	assert_false(document.has_placed_part(Vector3i(2, 0, 3)), "Part should not be stored at raw structure-cell-sized coordinates")
	var stored := document.get_placed_part(fine_cell)
	assert_eq(stored.get("part_id"), "wood_beam")
	assert_eq(stored.get("rotation_steps"), 1)
	# set_placed_part_at emits `changed`, which is wired to _refresh_world()
	# in setup() - rendering should have already happened as a side effect
	# of placement, the same way it does for blocks/components/markers.
	assert_gt(content_root.get_child_count(), children_before, "Placing a part should add a rendered visual to the viewport")


func test_part_profile_occupancy_for_cylinder_matches_rod_like_parts() -> void:
	# Rod/axle/rope/wheel default long_axis is Z (their end/bore sockets are
	# authored along Z); this helper should reproduce those cell counts
	# exactly.
	assert_eq(PartProfileScript.occupancy_for_cylinder(0.025, 1.0).size(), 8) # steel_rod
	assert_eq(PartProfileScript.occupancy_for_cylinder(0.02, 0.6).size(), 5) # axle
	assert_eq(PartProfileScript.occupancy_for_cylinder(0.01, 0.5).size(), 4) # rope_segment
	assert_eq(PartProfileScript.occupancy_for_cylinder(0.25, 0.08).size(), 16) # wheel


func test_part_profile_long_axis_resolves_the_vessel_orientation_gap() -> void:
	# Step 3 found that occupancy_for_cylinder's Z-height assumption didn't
	# match the crucible's hand-authored Y-height occupancy (both totaled 18
	# cells, but as different cell sets). long_axis fixes that: the crucible
	# is authored with long_axis = (0,1,0), and passing it through should now
	# reproduce its exact hand-authored cell set, not just the same count.
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var crucible: PartProfile = parts.get_part(&"crucible")
	assert_eq(crucible.long_axis, Vector3(0, 1, 0))
	var radius: float = crucible.geometry_params.get("radius")
	var height: float = crucible.geometry_params.get("height")
	var derived := PartProfileScript.occupancy_for_cylinder(radius, height, crucible.long_axis)
	var derived_set := {}
	for cell: Vector3i in derived:
		derived_set[cell] = true
	assert_eq(derived.size(), crucible.occupancy.size(), "Cell count should match")
	for cell: Vector3i in crucible.occupancy:
		assert_true(derived_set.has(cell), "Derived occupancy should reproduce the hand-authored cell %s exactly, not just match its count" % cell)
	# Rod-like parts still default to Z and are unaffected by this fix.
	var rod: PartProfile = parts.get_part(&"steel_rod")
	assert_eq(rod.long_axis, Vector3(0, 0, 1))


func test_forge_document_placed_parts_round_trip() -> void:
	var document: ForgeDocument = DocumentScript.new()
	document.template_kind = "part_assembly"
	document.document_id = "fixture_chair"
	var cell := Vector3i(4, 2, 1)
	document.set_placed_part(cell, {"id": "leg_a", "part_id": "wood_beam", "rotation_steps": 1, "joints": []})
	assert_true(document.has_placed_part(cell))
	assert_eq(document.get_placed_part(cell).get("part_id"), "wood_beam")
	var path := "user://world_forge_workshop_roundtrip.json"
	assert_eq(document.save_json(path), OK)
	var loaded: ForgeDocument = DocumentScript.load_json(path)
	assert_true(loaded != null)
	if loaded != null:
		assert_eq(loaded.template_kind, "part_assembly")
		assert_true(loaded.has_placed_part(cell))
		assert_eq(loaded.get_placed_part(cell).get("part_id"), "wood_beam")
		assert_eq(loaded.get_placed_part(cell).get("rotation_steps"), 1)
	document.erase_placed_part(cell)
	assert_false(document.has_placed_part(cell))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_forge_document_without_placed_parts_key_loads_as_empty() -> void:
	# Format-version bump (2 -> 3) must stay backward compatible: a document
	# saved before placed_parts existed should load with an empty lane, not
	# fail or crash.
	var path := "user://world_forge_pre_workshop.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": "old_building", "blocks": []}))
	file.close()
	var document: ForgeDocument = DocumentScript.load_json(path)
	assert_true(document != null)
	if document != null:
		assert_eq(document.placed_parts.size(), 0)


# --- Crafting-plan Phase 3 slice: PartSnapResolver (plan section 5) ---


func test_part_snap_resolver_world_sockets_applies_yaw_rotation() -> void:
	var rod: PartProfile = PartProfileScript.new()
	rod.sockets = [{"id": "end_b", "position": Vector3(0, 0, 0.5), "axis": Vector3(0, 0, 1), "kinds": ["weld"], "accepts": ["weld"]}]
	var unrotated := PartSnapResolver.world_sockets(rod, Vector3(1, 0, 2), 0)
	assert_eq(unrotated.size(), 1)
	assert_true((unrotated[0].position as Vector3).is_equal_approx(Vector3(1, 0, 2.5)))
	assert_true((unrotated[0].axis as Vector3).is_equal_approx(Vector3(0, 0, 1)))
	# 180 degrees about Y negates X and Z, leaves Y untouched - a
	# rotation-formula-agnostic check rather than trusting a hand-derived
	# 90-degree value.
	var half_turn := PartSnapResolver.world_sockets(rod, Vector3(1, 0, 2), 2)
	assert_true((half_turn[0].position as Vector3).is_equal_approx(Vector3(1, 0, 1.5)))
	assert_true((half_turn[0].axis as Vector3).is_equal_approx(Vector3(0, 0, -1)))


func test_part_snap_resolver_finds_snap_for_two_rods_welded_end_to_end() -> void:
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var document: ForgeDocument = DocumentScript.new()
	var rod: PartProfile = parts.get_part(&"steel_rod")
	# Placed rod's end_b sits at world (0, 0, 0.5) (its local end_b position,
	# unrotated). A second rod placed so its end_a lands close to that point,
	# facing back at it, should snap exactly onto it.
	document.set_placed_part(Vector3i.ZERO, {"part_id": "steel_rod", "rotation_steps": 0})
	var candidate_start := Vector3(0.05, 0.02, 0.98)  # close to, but not exactly, the ideal snap point
	var result := PartSnapResolver.find_snap(document, parts.get_part, rod, candidate_start, 0)
	assert_true(result.get("found", false), "Two rod ends with opposing weld axes within tolerance should snap")
	assert_eq(result.get("candidate_socket"), "end_a")
	assert_eq(result.get("target_socket"), "end_b")
	var snapped: Vector3 = result.get("position")
	# The candidate's end_a (local z=-0.5) should land exactly on the placed
	# rod's end_b (world z=0.5): snapped.z - 0.5 == 0.5 -> snapped.z == 1.0.
	assert_true(snapped.is_equal_approx(Vector3(0, 0, 1.0)))


func test_part_snap_resolver_mounts_a_wheel_coaxially_on_an_axle() -> void:
	# This is the scenario that found the coaxial-vs-opposing bug: a wheel's
	# bore and the axle end it mounts on point the SAME way (coaxial), not
	# opposite ways like a weld. Confirms the fix, not just the absence of a
	# crash - the pre-fix behavior was that this snap was silently never
	# found because it demanded axes point away from each other.
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var document: ForgeDocument = DocumentScript.new()
	document.set_placed_part(Vector3i.ZERO, {"part_id": "axle", "rotation_steps": 0})
	var wheel: PartProfile = parts.get_part(&"wheel")
	# Axle's end_b sits at world (0, 0, 0.3); place the wheel candidate so
	# its bore (local origin) lands right there.
	var result := PartSnapResolver.find_snap(document, parts.get_part, wheel, Vector3(0, 0, 0.3), 0)
	assert_true(result.get("found", false), "A wheel bore should snap coaxially onto an axle end, not be rejected as 'not opposing'")
	assert_eq(result.get("candidate_socket"), "bore")
	assert_eq(result.get("target_socket"), "end_b")


func test_part_snap_resolver_rejects_incompatible_kinds() -> void:
	# A rope segment's rope_anchor socket has no business welding to a rod's
	# weld/hinge/power_shaft end - confirms kind matching actually filters,
	# not just axis/distance.
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var document: ForgeDocument = DocumentScript.new()
	document.set_placed_part(Vector3i.ZERO, {"part_id": "steel_rod", "rotation_steps": 0})
	var rope: PartProfile = parts.get_part(&"rope_segment")
	var result := PartSnapResolver.find_snap(document, parts.get_part, rope, Vector3(0, 0, 0.5), 0)
	assert_false(result.get("found", false), "rope_anchor should not match a rod's weld/hinge/power_shaft socket")


func test_part_snap_resolver_rejects_same_direction_rod_ends() -> void:
	# Real steel_rod ends carry weld+hinge+power_shaft together, all
	# non-coaxial kinds (COAXIAL_KINDS is bearing-only - see the module
	# comment on why power_shaft is deliberately excluded even though a
	# wheel's bearing IS coaxial: a driveshaft extends in a straight line
	# tip-to-tip just like a weld does, it doesn't stack two rods facing the
	# same way). Two rod ends placed close together but facing the SAME
	# direction should not snap - that would mean the rods overlap instead
	# of extending each other.
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var rod: PartProfile = parts.get_part(&"steel_rod")
	var document: ForgeDocument = DocumentScript.new()
	document.set_placed_part(Vector3i.ZERO, {"part_id": "steel_rod", "rotation_steps": 0})
	# A candidate placed exactly overlapping the placed rod (same position)
	# makes end_a coincide with end_a and end_b with end_b - both pairs
	# face the same direction. (Placing the candidate offset by a full rod
	# length instead would - as an earlier version of this test did wrong -
	# accidentally create a *valid*, closer opposing end_a/end_b pairing via
	# the rod's other end, which the resolver correctly prefers; overlapping
	# them entirely is the only way to test the same-direction pairs in
	# isolation, since a rod's other end is always 1m - outside tolerance -
	# from wherever its near end lands.)
	var result := PartSnapResolver.find_snap(document, parts.get_part, rod, Vector3.ZERO, 0)
	assert_false(result.get("found", false), "Same-direction rod ends should not snap even though weld/hinge/power_shaft kinds match")


func test_part_snap_resolver_rejects_same_direction_weld_only_sockets() -> void:
	# Synthetic minimal case isolating just "weld", with no power_shaft in
	# the mix at all, to confirm the opposing-axis rule on its own (not
	# relying on steel_rod's specific kind combination).
	var rod_a: PartProfile = PartProfileScript.new()
	rod_a.sockets = [{"id": "tip", "position": Vector3(0, 0, 0.5), "axis": Vector3(0, 0, 1), "kinds": ["weld"], "accepts": ["weld"]}]
	var rod_b: PartProfile = PartProfileScript.new()
	rod_b.sockets = [{"id": "tip", "position": Vector3(0, 0, -0.5), "axis": Vector3(0, 0, 1), "kinds": ["weld"], "accepts": ["weld"]}]
	var document: ForgeDocument = DocumentScript.new()
	document.set_placed_part(Vector3i.ZERO, {"part_id": "rod_a", "rotation_steps": 0})
	var lookup := func(id: StringName) -> PartProfile:
		return rod_a if id == &"rod_a" else null
	var result := PartSnapResolver.find_snap(document, lookup, rod_b, Vector3(0, 0, 0.95), 0)
	assert_false(result.get("found", false), "Same-direction (non-opposing) weld sockets should not snap")


func test_part_snap_resolver_respects_tolerance() -> void:
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var document: ForgeDocument = DocumentScript.new()
	var rod: PartProfile = parts.get_part(&"steel_rod")
	document.set_placed_part(Vector3i.ZERO, {"part_id": "steel_rod", "rotation_steps": 0})
	var far_away := Vector3(0, 0, 5.0)
	var result := PartSnapResolver.find_snap(document, parts.get_part, rod, far_away, 0, 0.3)
	assert_false(result.get("found", false), "A compatible socket far outside tolerance should not snap")


# --- Wiring PartSnapResolver into real placement (plan section 5, follow-up to Step 6) ---


func test_forge_document_set_placed_part_at_stores_exact_position_and_bucket_cell() -> void:
	var document: ForgeDocument = DocumentScript.new()
	var position := Vector3(0.05, 0.02, 0.98)
	var cell := document.set_placed_part_at(position, {"part_id": "steel_rod", "rotation_steps": 0})
	assert_eq(cell, ForgeDocument.cell_for_position(position))
	assert_true(document.has_placed_part(cell))
	var stored := document.get_placed_part(cell)
	var exact: Array = stored.get("pos_exact")
	assert_true(Vector3(exact[0], exact[1], exact[2]).is_equal_approx(position), "pos_exact should be the exact continuous position, not rounded to the bucket cell")
	var resolved := ForgeDocument.placed_part_world_position(stored)
	assert_true(resolved.is_equal_approx(position))


func test_forge_document_placed_part_world_position_falls_back_without_pos_exact() -> void:
	# Parts placed the Step 5 way (set_placed_part, no snap) have no
	# pos_exact - placed_part_world_position must still resolve them at
	# their quantized cell, unchanged from Step 5's original behavior.
	var document: ForgeDocument = DocumentScript.new()
	document.set_placed_part(Vector3i(0, 0, 8), {"part_id": "wood_beam", "rotation_steps": 0})
	var stored := document.get_placed_part(Vector3i(0, 0, 8))
	assert_false(stored.has("pos_exact"))
	var resolved := ForgeDocument.placed_part_world_position(stored)
	assert_true(resolved.is_equal_approx(Vector3(0, 0, 1.0)))


func test_placing_a_part_via_place_at_snaps_to_a_nearby_compatible_socket() -> void:
	# _place_at's "part" branch still takes a coarse structure cell (see
	# comment on test_placing_a_part_stores_it_on_the_fine_grid_and_renders).
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	editor.set("_selected_part_id", &"steel_rod")
	editor.set("_place_kind", "part")
	editor.set("_brush_rotation", 0)
	# First rod at the origin: its end_b lands at world z=0.5.
	editor.call("_place_at", Vector3i(0, 0, 0))
	# Second rod clicked one structure cell further along Z. A steel_rod is
	# exactly 1m long and a structure cell is exactly 1m, so this already
	# puts the candidate's end_a exactly on the first rod's end_b -
	# PartSnapResolver reports this as a found snap at zero distance rather
	# than silently no-op'ing, and _place_at should act on that result (set
	# pos_exact, report a "snapped" status) rather than only reacting when a
	# snap changes the position. Step 6's own tests already prove the
	# resolver corrects a genuinely off-grid position; this test's job is
	# only to prove _place_at's wiring calls it and uses its result.
	editor.call("_place_at", Vector3i(0, 0, 1))
	var document: ForgeDocument = editor.get("_document")
	var second_cell := ForgeDocument.cell_for_position(Vector3(0, 0, 1.0))
	assert_true(document.has_placed_part(second_cell))
	var stored := document.get_placed_part(second_cell)
	assert_true(stored.has("pos_exact"), "Placing a part should always record pos_exact")
	var status: Label = editor.get("_status")
	assert_true(status != null)
	if status != null:
		assert_true("snapped" in status.text.to_lower(), "Status should report the snap, not a generic 'Part placed' message: %s" % status.text)
	# The snap must be recorded as a joint, not just used to nudge the
	# position - PartKineticsCompiler (Phase 5) needs to rebuild this
	# connection later without re-running the snap search.
	var joints: Array = stored.get("joints", [])
	assert_eq(joints.size(), 1, "A found snap should record exactly one joint entry")
	var joint: Dictionary = joints[0]
	assert_eq(joint.get("own_socket"), "end_a")
	assert_eq(joint.get("target_socket"), "end_b")
	assert_eq(joint.get("target_key"), ForgeDocument.cell_key(Vector3i.ZERO))


func test_undo_redo_covers_part_placement_including_pos_exact() -> void:
	# _transact snapshots the whole document via to_dictionary()/
	# _load_dictionary(), which Step 3 and this step both extended for
	# placed_parts/pos_exact - confirming that extension actually threads
	# through undo/redo rather than assuming it does because the plumbing
	# looks right.
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	editor.set("_selected_part_id", &"wood_beam")
	editor.set("_place_kind", "part")
	editor.call("_place_at", Vector3i(2, 0, 3))  # _place_at still takes a coarse cell
	var document: ForgeDocument = editor.get("_document")
	var cell := ForgeDocument.cell_for_position(Vector3(2, 0, 3))
	assert_true(document.has_placed_part(cell))
	var before_exact: Array = document.get_placed_part(cell).get("pos_exact")
	editor.call("_undo")
	assert_false(document.has_placed_part(cell), "Undo should remove the placed part")
	editor.call("_redo")
	assert_true(document.has_placed_part(cell), "Redo should restore the placed part")
	var after_exact: Array = document.get_placed_part(cell).get("pos_exact")
	assert_eq(after_exact, before_exact, "Redo should restore pos_exact exactly, not just the bucket cell")


func test_fine_cell_for_point_converts_a_whole_structure_cell_click() -> void:
	# The pure geometry step behind _mouse_to_fine_cell: given a world point
	# already known to be on the placement plane, quantizes X/Z to the fine
	# grid and reads Y from the current structure layer + fine sub-layer.
	# Tested directly (no camera/raycast) since that's what makes it worth
	# splitting out of the raycast-dependent function.
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	editor.set("_active_layer", 2)
	editor.set("_fine_layer", 3)
	var cell: Vector3i = editor.call("_fine_cell_for_point", Vector3(1.0, 999.0, 3.0))
	# X/Z: 1.0/0.125 = 8, 3.0/0.125 = 24 (Y in the point argument is ignored -
	# the plane height, not the point, determines which layer this is).
	assert_eq(cell, Vector3i(8, 2 * 8 + 3, 24))
	# A point that isn't grid-aligned should floor, matching _mouse_to_cell's
	# floori convention for the coarse grid.
	var off_grid: Vector3i = editor.call("_fine_cell_for_point", Vector3(0.19, 0.0, -0.01))
	assert_eq(off_grid.x, 1)  # 0.19/0.125 = 1.52 -> floor 1
	assert_eq(off_grid.z, -1)  # -0.01/0.125 = -0.08 -> floor -1


func test_placing_a_part_at_a_true_sub_cell_fine_position() -> void:
	# The actual point of fine-grid picking: a position with no whole-
	# structure-cell equivalent at all (fine cell x=4 is world x=0.5,
	# exactly between two structure cells). _place_part_at_fine_cell is
	# what real mouse clicks call once _mouse_to_fine_cell resolves a fine
	# cell (_place_at itself stays coarse-only for backward compatibility -
	# see test_placing_a_part_stores_it_on_the_fine_grid_and_renders).
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	editor.set("_selected_part_id", &"steel_rod")
	editor.set("_place_kind", "part")
	var fine_cell := Vector3i(4, 0, 0)
	editor.call("_place_part_at_fine_cell", fine_cell)
	var document: ForgeDocument = editor.get("_document")
	assert_true(document.has_placed_part(fine_cell))
	var stored := document.get_placed_part(fine_cell)
	var exact: Array = stored.get("pos_exact")
	assert_true(Vector3(exact[0], exact[1], exact[2]).is_equal_approx(Vector3(0.5, 0.0, 0.0)), "A fine cell with no whole-structure-cell equivalent should still place at its exact world position")
	assert_eq((stored.get("joints", ["placeholder"]) as Array).size(), 0, "Placing into an empty document should record no joints - nothing was in range to snap to")


func test_document_batch_emits_one_change_for_large_edits() -> void:
	var document: ForgeDocument = DocumentScript.new()
	var changes := [0]
	document.changed.connect(func() -> void: changes[0] += 1)
	document.begin_batch()
	for x: int in range(20):
		for z: int in range(20):
			document.set_block(Vector3i(x, 0, z), {"block_id": "stone"})
	document.end_batch()
	assert_eq(changes[0], 1, "A 400-block operation should trigger one viewport refresh")


func test_world_forge_validation_reports_broken_catalog_references() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var document: ForgeDocument = editor.get("_document")
	document.set_block(Vector3i.ZERO, {"block_id": "does_not_exist"})
	var issues: PackedStringArray = editor.call("_document_issues")
	assert_true(issues.size() == 1)
	assert_true("unknown block" in issues[0])


func test_catalog_search_filters_parts_without_losing_identity() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var list: ItemList = editor.get("_part_list")
	var catalog: Array[Dictionary] = editor.get("_parts")
	editor.call("_filter_catalog_list", "wheel", list, catalog)
	assert_eq(list.item_count, 1)
	assert_eq(str(list.get_item_metadata(0)), "wheel")


func test_component_selection_and_duplicate_use_unique_instances() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var document: ForgeDocument = editor.get("_document")
	document.components.append({"id": "original", "component_id": "forge_firebox", "pos": [0, 0, 0], "rotation_steps": 0})
	document.notify_changed()
	editor.call("_select_single", Vector3i.ZERO)
	editor.call("_duplicate_selection")
	assert_eq(document.components.size(), 2)
	assert_ne(document.components[0].get("id"), document.components[1].get("id"))
	assert_eq(document.components[1].get("pos"), [1, 0, 0])


func test_finalize_nested_blueprint_preserves_all_authored_element_types() -> void:
	var source := DocumentScript.new()
	source.document_id = "nested_source"
	source.set_block(Vector3i.ZERO, {"block_id": "stone"})
	source.components.append({"id": "source_component", "component_id": "forge_firebox", "pos": [1, 0, 0], "rotation_steps": 0})
	source.markers.append({"id": "source_marker", "marker_type": "worker_position", "pos": [0, 0, 1], "rotation_steps": 0})
	source.set_placed_part(Vector3i(4, 0, 0), {"part_id": "steel_rod", "rotation_steps": 0})
	var path := "user://world_forge_nested_test.json"
	assert_eq(source.save_json(path), OK)
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var document: ForgeDocument = editor.get("_document")
	document.nested_instances.append({"id": "nested_1", "source_path": path, "origin": [2, 0, 3], "rotation_steps": 1})
	editor.call("_finalize_nested_blueprints")
	assert_eq(document.blocks.size(), 1)
	assert_eq(document.components.size(), 1)
	assert_eq(document.markers.size(), 1)
	assert_eq(document.placed_parts.size(), 1)
	assert_true(document.nested_instances.is_empty())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Crafting-plan Phase 5 slice: PartKineticsCompiler (plan section 9) ---


func test_kinetics_compiler_welds_connected_rods_into_one_group_with_summed_mass() -> void:
	# Two rods placed end-to-end through the real UI path record a weld
	# connection (rod ends share weld+hinge+power_shaft) - the compiler
	# should merge them into a single rigid-body group with no physics
	# joint, and the group's mass should be both rods summed.
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	editor.set("_selected_part_id", &"steel_rod")
	editor.set("_place_kind", "part")
	editor.call("_place_at", Vector3i(0, 0, 0))
	editor.call("_place_at", Vector3i(0, 0, 1))
	var document: ForgeDocument = editor.get("_document")
	assert_eq(document.placed_parts.size(), 2)

	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var materials: MaterialRegistry = track(MaterialRegistryScript.new()) as MaterialRegistry
	materials.load_materials()
	var compiled := PartKineticsCompiler.compile(document, parts.get_part, materials.get_material)

	assert_eq((compiled["groups"] as Array).size(), 1, "Welded rods should compile into a single rigid-body group")
	assert_true((compiled["joints"] as Array).is_empty(), "A weld should not produce a physics joint")
	var group: Dictionary = compiled["groups"][0]
	assert_eq((group["member_keys"] as Array).size(), 2)
	var rod: PartProfile = parts.get_part(&"steel_rod")
	var steel: MaterialProperties = materials.get_material(&"steel")
	var single_rod_mass := rod.resolved_mass_kg(steel)
	assert_true(is_equal_approx(float(group["mass_kg"]), single_rod_mass * 2.0), "Group mass should be both rods summed, not just one")


func test_kinetics_compiler_creates_a_bearing_joint_between_axle_and_wheel_groups() -> void:
	# A wheel's bore only shares "bearing" with an axle end (not weld), so
	# the compiler should keep them as two separate groups joined by one
	# physics joint, not merge them.
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	editor.set("_selected_part_id", &"axle")
	editor.set("_place_kind", "part")
	editor.call("_place_part_at_fine_cell", Vector3i(0, 0, 0))
	editor.set("_selected_part_id", &"wheel")
	# Axle's end_b sits at world z=0.3 (fine cell z=2.4, not grid-aligned -
	# see Step 1's reporting note on the axle). Place the wheel candidate
	# with its bore (local origin) landing close enough to snap.
	editor.call("_place_part_at_fine_cell", Vector3i(0, 0, 2))
	var document: ForgeDocument = editor.get("_document")
	assert_eq(document.placed_parts.size(), 2)

	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var materials: MaterialRegistry = track(MaterialRegistryScript.new()) as MaterialRegistry
	materials.load_materials()
	var compiled := PartKineticsCompiler.compile(document, parts.get_part, materials.get_material)

	assert_eq((compiled["groups"] as Array).size(), 2, "A bearing connection should NOT merge the axle and wheel into one group")
	var joints: Array = compiled["joints"]
	assert_eq(joints.size(), 1, "There should be exactly one physics joint between the two groups")
	var joint: Dictionary = joints[0]
	assert_eq(joint.get("kind"), "bearing")
	assert_true(joint.get("group_a") != joint.get("group_b"))


func test_kinetics_compiler_gives_an_isolated_part_its_own_group_with_no_joints() -> void:
	var document: ForgeDocument = DocumentScript.new()
	document.set_placed_part(Vector3i.ZERO, {"part_id": "wood_beam", "rotation_steps": 0, "joints": []})
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var materials: MaterialRegistry = track(MaterialRegistryScript.new()) as MaterialRegistry
	materials.load_materials()
	var compiled := PartKineticsCompiler.compile(document, parts.get_part, materials.get_material)
	assert_eq((compiled["groups"] as Array).size(), 1)
	assert_true((compiled["joints"] as Array).is_empty())
	assert_true((compiled["logical_connections"] as Array).is_empty())
	var group: Dictionary = compiled["groups"][0]
	assert_eq((group["member_keys"] as Array).size(), 1)
	assert_gt(float(group["mass_kg"]), 0.0)


func test_kinetics_compiler_deduplicates_a_joint_recorded_from_both_sides() -> void:
	# world_forge_main.gd only records a joint on the newly-placed part's
	# side today, but the compiler shouldn't assume that stays true forever
	# (or that every document was authored only through that one code path)
	# - a connection recorded symmetrically should still produce exactly
	# one physics joint, not two.
	var document: ForgeDocument = DocumentScript.new()
	var axle_key := Vector3i(0, 0, 0)
	var wheel_key := Vector3i(0, 0, 2)
	document.set_placed_part(axle_key, {"part_id": "axle", "rotation_steps": 0, "joints": [
		{"target_key": ForgeDocument.cell_key(wheel_key), "target_socket": "bore", "own_socket": "end_b"},
	]})
	document.set_placed_part(wheel_key, {"part_id": "wheel", "rotation_steps": 0, "joints": [
		{"target_key": ForgeDocument.cell_key(axle_key), "target_socket": "end_b", "own_socket": "bore"},
	]})
	var parts: PartRegistry = track(PartRegistryScript.new()) as PartRegistry
	parts.load_parts()
	var materials: MaterialRegistry = track(MaterialRegistryScript.new()) as MaterialRegistry
	materials.load_materials()
	var compiled := PartKineticsCompiler.compile(document, parts.get_part, materials.get_material)
	assert_eq((compiled["groups"] as Array).size(), 2)
	assert_eq((compiled["joints"] as Array).size(), 1, "A symmetrically-recorded connection should still produce exactly one joint")


# --- Xbox controller support for World Forge (pair to PC, no phone/custom app) ---


func test_gamepad_camera_orbit_and_pan_respond_to_sticks() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var yaw_before: float = editor.get("_camera_yaw")
	var focus_before: Vector3 = editor.get("_camera_focus")
	editor.call("_apply_gamepad_camera", {"right_x": 1.0, "right_y": 0.0, "left_x": 0.0, "left_y": 0.0, "lt": 0.0, "rt": 0.0}, 0.5)
	assert_false(is_equal_approx(float(editor.get("_camera_yaw")), yaw_before), "Right stick X should orbit the camera (change yaw)")
	editor.set("_camera_yaw", yaw_before)
	editor.call("_apply_gamepad_camera", {"right_x": 0.0, "right_y": 0.0, "left_x": 1.0, "left_y": 0.0, "lt": 0.0, "rt": 0.0}, 0.5)
	var focus_after: Vector3 = editor.get("_camera_focus")
	assert_false(focus_after.is_equal_approx(focus_before), "Left stick should pan the camera focus")


func test_gamepad_zoom_responds_to_triggers_and_clamps() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	editor.set("_camera_distance", 20.0)
	editor.call("_apply_gamepad_camera", {"right_x": 0.0, "right_y": 0.0, "left_x": 0.0, "left_y": 0.0, "lt": 1.0, "rt": 0.0}, 1.0)
	assert_gt(float(editor.get("_camera_distance")), 20.0, "Left trigger should zoom out (increase distance)")
	editor.set("_camera_distance", 20.0)
	editor.call("_apply_gamepad_camera", {"right_x": 0.0, "right_y": 0.0, "left_x": 0.0, "left_y": 0.0, "lt": 0.0, "rt": 1.0}, 1.0)
	assert_true(float(editor.get("_camera_distance")) < 20.0, "Right trigger should zoom in (decrease distance)")
	editor.set("_camera_distance", 5.0)
	editor.call("_apply_gamepad_camera", {"right_x": 0.0, "right_y": 0.0, "left_x": 0.0, "left_y": 0.0, "lt": 0.0, "rt": 1.0}, 10.0)
	assert_true(float(editor.get("_camera_distance")) >= 4.0, "Zoom should clamp at the same minimum distance as mouse-wheel zoom")


func test_gamepad_deadzone_ignores_small_stick_drift() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var yaw_before: float = editor.get("_camera_yaw")
	var focus_before: Vector3 = editor.get("_camera_focus")
	# 0.05 is well inside GAMEPAD_DEADZONE (0.2) - real controllers rest
	# slightly off-center, and that drift should not slowly spin the camera.
	editor.call("_apply_gamepad_camera", {"right_x": 0.05, "right_y": 0.05, "left_x": 0.05, "left_y": -0.05, "lt": 0.0, "rt": 0.0}, 1.0)
	assert_eq(float(editor.get("_camera_yaw")), yaw_before)
	assert_true((editor.get("_camera_focus") as Vector3).is_equal_approx(focus_before))


func test_gamepad_buttons_are_edge_triggered_not_held() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var held := {"a": false, "b": false, "x": false, "y": false, "lb": false, "rb": false, "start": false, "back": false, "dpad_up": false, "dpad_down": false, "dpad_left": false, "dpad_right": false, "left_x": 0.0, "left_y": 0.0, "right_x": 0.0, "right_y": 0.0, "lt": 0.0, "rt": 0.0}
	var rotation_before: int = editor.get("_brush_rotation")
	held["x"] = true
	editor.call("_apply_gamepad_frame", held, 0.016)
	var rotation_after_first: int = editor.get("_brush_rotation")
	assert_eq(rotation_after_first, posmod(rotation_before + 1, 4), "X should rotate the brush on the frame it's first pressed")
	# Held for a second frame without releasing - should NOT rotate again.
	editor.call("_apply_gamepad_frame", held, 0.016)
	assert_eq(int(editor.get("_brush_rotation")), rotation_after_first, "Holding X should not repeat the action every frame")
	# Released then pressed again - should fire once more.
	held["x"] = false
	editor.call("_apply_gamepad_frame", held, 0.016)
	held["x"] = true
	editor.call("_apply_gamepad_frame", held, 0.016)
	assert_eq(int(editor.get("_brush_rotation")), posmod(rotation_after_first + 1, 4), "Releasing and pressing again should fire a second rotation")


func test_gamepad_dpad_steps_active_and_fine_layer() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var base := {"a": false, "b": false, "x": false, "y": false, "lb": false, "rb": false, "start": false, "back": false, "dpad_up": false, "dpad_down": false, "dpad_left": false, "dpad_right": false, "left_x": 0.0, "left_y": 0.0, "right_x": 0.0, "right_y": 0.0, "lt": 0.0, "rt": 0.0}
	var up := base.duplicate()
	up["dpad_up"] = true
	editor.call("_apply_gamepad_frame", up, 0.016)
	assert_eq(int(editor.get("_active_layer")), 1)
	editor.call("_apply_gamepad_frame", base, 0.016) # release
	editor.call("_apply_gamepad_frame", up, 0.016)
	assert_eq(int(editor.get("_active_layer")), 2)
	var down := base.duplicate()
	down["dpad_down"] = true
	editor.call("_apply_gamepad_frame", base, 0.016)
	editor.call("_apply_gamepad_frame", down, 0.016)
	assert_eq(int(editor.get("_active_layer")), 1)
	var right := base.duplicate()
	right["dpad_right"] = true
	editor.call("_apply_gamepad_frame", right, 0.016)
	assert_eq(int(editor.get("_fine_layer")), 1)


func test_gamepad_y_cycles_place_kind_through_every_tab() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	assert_eq(str(editor.get("_place_kind")), "block")
	var base := {"a": false, "b": false, "x": false, "y": false, "lb": false, "rb": false, "start": false, "back": false, "dpad_up": false, "dpad_down": false, "dpad_left": false, "dpad_right": false, "left_x": 0.0, "left_y": 0.0, "right_x": 0.0, "right_y": 0.0, "lt": 0.0, "rt": 0.0}
	var press_y := base.duplicate()
	press_y["y"] = true
	var expected := ["component", "marker", "part", "block"]
	for kind: String in expected:
		editor.call("_apply_gamepad_frame", press_y, 0.016)
		assert_eq(str(editor.get("_place_kind")), kind)
		editor.call("_apply_gamepad_frame", base, 0.016) # release before next press


func test_gamepad_lb_rb_cycle_the_selected_part() -> void:
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	# _on_part_selected only syncs _selected_part_id from whatever the
	# ItemList already has selected - it doesn't select anything itself
	# (that's normally the user's click). _cycle_list_selection reads the
	# ItemList's OWN selection to know "current", so it must actually be
	# selected here too, not just _place_kind/_selected_part_id set
	# directly - otherwise RB/LB compute their step from a phantom index 0
	# instead of wherever the part list really starts.
	var part_list: ItemList = editor.get("_part_list")
	part_list.select(0)
	editor.call("_on_part_selected", 0)
	var first := str(editor.get("_selected_part_id"))
	var base := {"a": false, "b": false, "x": false, "y": false, "lb": false, "rb": false, "start": false, "back": false, "dpad_up": false, "dpad_down": false, "dpad_left": false, "dpad_right": false, "left_x": 0.0, "left_y": 0.0, "right_x": 0.0, "right_y": 0.0, "lt": 0.0, "rt": 0.0}
	var press_rb := base.duplicate()
	press_rb["rb"] = true
	editor.call("_apply_gamepad_frame", press_rb, 0.016)
	var second := str(editor.get("_selected_part_id"))
	assert_true(second != first, "RB should move the selection to a different part")
	editor.call("_apply_gamepad_frame", base, 0.016)
	var press_lb := base.duplicate()
	press_lb["lb"] = true
	editor.call("_apply_gamepad_frame", press_lb, 0.016)
	assert_eq(str(editor.get("_selected_part_id")), first, "LB should step back to the previous part")


func test_gamepad_a_places_at_the_reticle_and_b_erases() -> void:
	# _mouse_to_cell's camera raycast only produces a real result when the
	# node is inside a live, processing SceneTree - Camera3D's projection
	# state isn't valid otherwise (confirmed by probing _mouse_to_cell out
	# of tree during development: it returned null every time). Every
	# earlier placement test sidestepped this by calling _place_at with a
	# pre-resolved cell directly; this is the first test to exercise the
	# actual screen-to-world raycast, so it needs the editor parented
	# somewhere live - EditorInterface.get_edited_scene_root() is already
	# used the same way by this test suite's own _add_control() helper.
	var script := load("res://addons/world_forge/world_forge_main.gd") as Script
	var editor: Control = track(script.new()) as Control
	editor.setup(null)
	var scene_root := EditorInterface.get_edited_scene_root()
	assert_true(scene_root != null, "Test requires a scene open in the editor to verify a real camera raycast")
	if scene_root == null:
		return
	scene_root.add_child(editor)
	editor.set("_tool", "place")
	editor.set("_place_kind", "block")
	var document: ForgeDocument = editor.get("_document")
	var blocks_before := document.blocks.size()
	var base := {"a": false, "b": false, "x": false, "y": false, "lb": false, "rb": false, "start": false, "back": false, "dpad_up": false, "dpad_down": false, "dpad_left": false, "dpad_right": false, "left_x": 0.0, "left_y": 0.0, "right_x": 0.0, "right_y": 0.0, "lt": 0.0, "rt": 0.0}
	var press_a := base.duplicate()
	press_a["a"] = true
	editor.call("_apply_gamepad_frame", press_a, 0.016)
	assert_gt(document.blocks.size(), blocks_before, "A should place a block at the reticle-aimed cell")
	var press_b := base.duplicate()
	press_b["b"] = true
	editor.call("_apply_gamepad_frame", base, 0.016)
	editor.call("_apply_gamepad_frame", press_b, 0.016)
	assert_eq(document.blocks.size(), blocks_before, "B should erase the block the reticle is aimed at")
	scene_root.remove_child(editor)



