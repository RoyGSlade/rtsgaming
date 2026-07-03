# Voxel RTS Modular Project Layout

## Project Assumptions

- Engine: Godot 4.x
- Primary language: GDScript
- Architecture style: data-driven, modular, editor-tool-first
- Core idea: buildings are created in a Godot-based block editor, saved as blueprints, then constructed in-game by workers using gathered resources.
- Main design rule: every file should have one mission. If a file starts doing five jobs, it gets split before it turns into a haunted drawer.

---

# Top-Level Folder Layout

```text
res://
├── addons/
│   └── voxel_building_editor/
├── core_game/
├── data/
├── assets/
├── scenes/
├── scripts/
├── tests/
├── debug/
└── docs/
```

## Folder Mission Summary

| Folder | Mission |
|---|---|
| `addons/voxel_building_editor/` | Custom Godot editor plugin for creating building blueprints, blocks, layers, sockets, recipes, paths, and preview simulations. |
| `core_game/` | Runtime game systems: economy, workers, construction, combat, AI, logistics, pathing, camera, UI, and world simulation. |
| `data/` | Data definitions for blocks, buildings, units, recipes, resources, factions, eras, terrain, and tech. |
| `assets/` | Visual/audio/source assets: models, textures, sounds, animations, icons, materials, shaders. |
| `scenes/` | Godot scene files for runtime entities, UI screens, buildings, units, effects, and prototypes. |
| `scripts/` | Shared reusable scripts that are not specific to editor or core runtime systems. |
| `tests/` | Automated and manual test scenes/scripts for validating construction, recipes, pathing, and simulation. |
| `debug/` | Developer overlays, inspectors, cheats, profiling tools, and visualization helpers. |
| `docs/` | Planning docs, conventions, architecture notes, production chain notes, and design rules. |

---

# 1. Building Editor Plugin

```text
res://addons/voxel_building_editor/
├── plugin.cfg
├── plugin.gd
├── editor_main.gd
├── building_editor_state.gd
├── placement_and_ui/
├── camera/
├── blocks/
├── layers/
├── sockets/
├── pathing/
├── storage/
├── recipes/
├── workers/
├── simulation_preview/
├── validation/
├── export/
└── ui/
```

## Root Files

### `plugin.cfg`
Declares the Godot plugin metadata.

Mission:
- Give Godot the plugin name, description, author, version, and main script path.
- Keep this boring. Boring config is good config, which is tragic but true.

### `plugin.gd`
Bootstraps the building editor plugin.

Mission:
- Register the plugin with the Godot editor.
- Add/remove custom docks, menus, shortcuts, and editor screens.
- Instantiate `editor_main.gd`.
- Clean up editor state when the plugin is disabled.

### `editor_main.gd`
Main controller for the building editor.

Mission:
- Coordinate editor modules.
- Switch between editor modes: blocks, layers, sockets, pathing, storage, recipes, workers, simulation, validation.
- Own the main editor viewport reference.
- Route user input to the active tool.
- Avoid containing actual tool logic. It is the conductor, not the orchestra, because apparently even code needs management.

### `building_editor_state.gd`
Stores active editor state.

Mission:
- Track current building blueprint.
- Track selected blocks, active tool, active layer, active resource, selected socket, selected recipe.
- Store undo/redo command references.
- Provide clean signals when state changes.

---

## 1.1 Placement and UI

```text
placement_and_ui/
├── placement_cursor.gd
├── grid_hover_detector.gd
├── selection_box.gd
├── placement_rules_preview.gd
├── build_area_bounds.gd
├── editor_gizmo_manager.gd
└── input_router.gd
```

### `placement_cursor.gd`
Moves the block placement ghost around the editor grid.

Mission:
- Convert mouse position to grid coordinate.
- Display the ghost block or selected tool preview.
- Change preview color/state based on valid/invalid placement.

### `grid_hover_detector.gd`
Detects what grid cell or block the user is pointing at.

Mission:
- Raycast from editor camera into the grid.
- Return grid coordinate, face normal, selected block, or empty space.
- Serve all placement tools so each tool does not invent its own raycast stupidity.

### `selection_box.gd`
Handles drag selection for blocks and sockets.

Mission:
- Let the user select multiple blocks.
- Support box select, additive select, subtractive select.
- Provide selected coordinate groups to other tools.

### `placement_rules_preview.gd`
Shows whether the current building blueprint would be placeable in-game.

Mission:
- Preview footprint, clearance, blocked cells, entrance positions, and terrain requirements.
- Highlight rule failures before export.

### `build_area_bounds.gd`
Defines the editable building space.

Mission:
- Store maximum width, depth, and height.
- Prevent placing blocks outside the allowed editor volume.
- Allow blueprint-specific bounds later.

### `editor_gizmo_manager.gd`
Draws helper gizmos.

Mission:
- Show arrows, sockets, path lines, storage markers, stage markers, and labels.
- Toggle gizmo categories on/off.

### `input_router.gd`
Routes editor input to the active editor mode.

Mission:
- Translate clicks, drags, hotkeys, wheel zoom, and modifiers.
- Prevent every tool from fighting for input like raccoons in a trash bag.

---

## 1.2 Camera

```text
camera/
├── editor_camera_movement.gd
├── editor_camera_orbit.gd
├── editor_camera_zoom.gd
├── editor_camera_presets.gd
├── runtime_cutaway_camera_preview.gd
└── view_angle_controller.gd
```

### `editor_camera_movement.gd`
Moves the user camera while building.

Mission:
- Pan the editor camera.
- Handle WASD/middle-mouse movement.
- Keep movement independent from orbit and zoom.

### `editor_camera_orbit.gd`
Rotates the camera around the building preview.

Mission:
- Orbit around blueprint center.
- Snap to common angles.
- Keep camera rotation stable and readable.

### `editor_camera_zoom.gd`
Handles zooming in the building editor.

Mission:
- Scroll zoom in/out.
- Clamp zoom range.
- Keep zoom centered around cursor or blueprint center.

### `editor_camera_presets.gd`
Stores camera presets.

Mission:
- Provide top, front, side, isometric, interior, and construction-stage views.
- Let the user jump to consistent angles while editing.

### `runtime_cutaway_camera_preview.gd`
Previews how the building will look when selected in-game.

Mission:
- Simulate the runtime camera framing.
- Hide/fade layers according to the selected cutaway mode.
- Help verify that interiors are readable.

### `view_angle_controller.gd`
Controls fixed view angles for in-game building inspection.

Mission:
- Define the angle used when a player clicks a building to see inside.
- Store zoom, rotation, vertical offset, and focus target.
- Export camera hints into the building blueprint.

---

## 1.3 Blocks

```text
blocks/
├── block_palette.gd
├── block_definition.gd
├── block_instance_data.gd
├── block_placer.gd
├── block_remover.gd
├── block_painter.gd
├── block_replacer.gd
├── block_fill_tool.gd
├── block_mirror_tool.gd
├── block_rotation_tool.gd
├── block_material_variant_tool.gd
└── block_tag_tool.gd
```

### `block_palette.gd`
Displays available blocks to place.

Mission:
- Load block definitions from `data/blocks/`.
- Group blocks by era, category, material, and function.
- Provide selected block to placement tools.

### `block_definition.gd`
Defines a reusable block type.

Mission:
- Store block id, display name, mesh, material, icon, collision, tags, cost, weight, durability, flammability, and era.
- This is the source data for a block type, not an individual placed block.

### `block_instance_data.gd`
Stores one block placed inside a building blueprint.

Mission:
- Store position, rotation, block id, layer, stage, tags, damage state, and optional metadata.
- Keep placed-block data lightweight and serializable.

### `block_placer.gd`
Places blocks into the active blueprint.

Mission:
- Add a block at a grid coordinate.
- Validate placement against bounds and occupancy.
- Record undo/redo commands.

### `block_remover.gd`
Removes blocks from the active blueprint.

Mission:
- Remove one or more blocks.
- Clean up linked layer assignments, socket links, and flow references if needed.

### `block_painter.gd`
Changes existing blocks without moving them.

Mission:
- Paint material variants.
- Paint block categories.
- Paint visual themes like damaged, mossy, upgraded, industrial, or sci-fi variants.

### `block_replacer.gd`
Swaps one block type for another.

Mission:
- Replace selected blocks while keeping position, rotation, layer, and construction stage.
- Useful for rapid era reskins.

### `block_fill_tool.gd`
Fills rectangular volumes.

Mission:
- Fill floors, walls, roofs, foundations, and mass structures.
- Prevent manual block placement from becoming digital finger painting in a thunderstorm.

### `block_mirror_tool.gd`
Mirrors selected blocks across X/Z axes.

Mission:
- Support symmetrical buildings.
- Copy or move mirrored block groups.

### `block_rotation_tool.gd`
Rotates selected block groups.

Mission:
- Rotate blocks and their metadata around a pivot.
- Preserve socket/path references where possible.

### `block_material_variant_tool.gd`
Applies material variants.

Mission:
- Change block skin without changing block identity.
- Example: `stone_wall` can become clean, cracked, mossy, scorched, frozen, or upgraded.

### `block_tag_tool.gd`
Assigns gameplay tags to selected blocks.

Mission:
- Mark blocks as support, flammable, load-bearing, roof, wall, workstation, powered, water, storage, fragile, reinforced, etc.

---

## 1.4 Layers

```text
layers/
├── layer_definition.gd
├── layer_assignment_tool.gd
├── layer_hider.gd
├── layer_fader.gd
├── cutaway_profile.gd
├── cutaway_preview_controller.gd
└── layer_visibility_rules.gd
```

### `layer_definition.gd`
Defines valid visibility/building layers.

Mission:
- Store layer ids such as foundation, floor, walls, roof, interior, workstation, storage, decoration, fx, power, water.
- Define default visibility behavior.

### `layer_assignment_tool.gd`
Assigns selected blocks to layers.

Mission:
- Let the designer mark selected blocks as roof, wall, interior, floor, workstation, etc.
- Provide batch layer assignment.

### `layer_hider.gd`
Handles hiding selected layers.

Mission:
- Hide roof/front wall/interior layers in editor previews and runtime cutaway mode.
- Provide simple visibility toggles.

### `layer_fader.gd`
Handles transparency instead of full hiding.

Mission:
- Fade roof or walls for cutaway views.
- Support smooth transitions when selecting/deselecting buildings.

### `cutaway_profile.gd`
Stores named visibility presets.

Mission:
- Define Normal, Interior, Production, Damage, Repair, and Debug views.
- Each profile says which layers are visible, hidden, faded, or highlighted.

### `cutaway_preview_controller.gd`
Previews cutaway profiles in the editor.

Mission:
- Let the designer test how the building looks in-game.
- Toggle roof hiding, wall hiding, production highlighting, and worker visibility.

### `layer_visibility_rules.gd`
Runtime rules for contextual layer visibility.

Mission:
- Decide when layers hide/fade based on selection, camera angle, zoom level, player mode, or debug mode.

---

## 1.5 Sockets

```text
sockets/
├── socket_definition.gd
├── socket_instance_data.gd
├── socket_placement_tool.gd
├── socket_linker.gd
├── worker_socket_tool.gd
├── storage_socket_tool.gd
├── fx_socket_tool.gd
├── entrance_socket_tool.gd
└── socket_validator.gd
```

### `socket_definition.gd`
Defines socket types.

Mission:
- Store allowed socket categories: worker stand, entrance, material dropoff, output pickup, storage, workstation, rally point, attack point, repair point, fx point.

### `socket_instance_data.gd`
Stores one socket placed in a blueprint.

Mission:
- Store socket id, type, position, rotation, linked block, allowed worker roles, and recipe references.

### `socket_placement_tool.gd`
Places invisible gameplay sockets.

Mission:
- Add sockets on the grid or attached to blocks.
- Show labels and gizmos.

### `socket_linker.gd`
Links sockets to blocks, recipes, paths, or storage.

Mission:
- Link an anvil socket to the anvil block.
- Link material dropoff to recipe input storage.
- Link output pickup to weapon rack.

### `worker_socket_tool.gd`
Places worker positions.

Mission:
- Define where workers stand while producing, repairing, researching, teaching, healing, training, etc.

### `storage_socket_tool.gd`
Places storage locations.

Mission:
- Define where resources visually appear inside the building.
- Allow shelves, crates, hooks, racks, bins, tanks, or pallets.

### `fx_socket_tool.gd`
Places effect points.

Mission:
- Smoke, sparks, fire, dust, water, steam, magic glow, electricity arcs, robot arms, sci-fi nonsense, etc.

### `entrance_socket_tool.gd`
Defines entrances and exits.

Mission:
- Mark where workers enter/exit.
- Connect external pathing to internal pathing.

### `socket_validator.gd`
Checks socket sanity.

Mission:
- Ensure required sockets exist.
- Ensure linked blocks exist.
- Ensure workers can reach their sockets.

---

## 1.6 Internal Pathing

```text
pathing/
├── internal_path_graph.gd
├── path_node_data.gd
├── path_edge_data.gd
├── path_draw_tool.gd
├── path_validator.gd
├── path_preview_worker.gd
└── path_exporter.gd
```

### `internal_path_graph.gd`
Stores building-internal navigation.

Mission:
- Store path nodes and edges inside a building.
- Connect entrance, storage, workstation, and output sockets.

### `path_node_data.gd`
Stores one internal path node.

Mission:
- Hold local position, node type, floor, and optional linked socket.

### `path_edge_data.gd`
Stores one connection between path nodes.

Mission:
- Define walkable connections, cost, width, stair/ladder/elevator status, and access restrictions.

### `path_draw_tool.gd`
Lets designer draw worker paths.

Mission:
- Click path points.
- Connect points.
- Link paths to sockets.

### `path_validator.gd`
Validates internal navigation.

Mission:
- Confirm workers can reach each required socket from an entrance.
- Detect blocked path segments.

### `path_preview_worker.gd`
Spawns a fake worker in editor preview.

Mission:
- Simulate worker movement through a recipe path.
- Catch path problems early, before they become runtime goblins.

### `path_exporter.gd`
Exports internal path data into blueprint format.

Mission:
- Serialize path graph into runtime-readable data.
- Strip editor-only gizmo data.

---

## 1.7 Storage

```text
storage/
├── storage_definition.gd
├── storage_zone_tool.gd
├── storage_visual_slot.gd
├── storage_capacity_calculator.gd
├── storage_filter_tool.gd
└── storage_preview.gd
```

### `storage_definition.gd`
Defines storage behavior for a building.

Mission:
- Store accepted resources, capacity, priority, visual display rules, and pickup/dropoff sockets.

### `storage_zone_tool.gd`
Places storage zones in a building.

Mission:
- Define shelves, crates, racks, bins, tanks, cold rooms, armories, ore piles, etc.

### `storage_visual_slot.gd`
Defines where stored items appear visually.

Mission:
- Let ingots appear on shelves, swords on racks, leather on hooks, grain in sacks.

### `storage_capacity_calculator.gd`
Calculates capacity from storage slots.

Mission:
- Turn placed storage blocks/slots into capacity numbers.
- Example: each crate adds 20 small items; each rack holds 8 swords.

### `storage_filter_tool.gd`
Sets what resources can go into each storage zone.

Mission:
- Mark one shelf for ingots, one hook rack for leather wraps, one rack for swords.

### `storage_preview.gd`
Shows fake resources in storage slots.

Mission:
- Preview how the building looks when storage is empty, half full, or full.

---

## 1.8 Recipes and Production

```text
recipes/
├── recipe_definition.gd
├── recipe_editor.gd
├── recipe_step_data.gd
├── recipe_chain_view.gd
├── production_timing_tool.gd
├── input_output_mapper.gd
├── workstation_requirement_tool.gd
└── recipe_validator.gd
```

### `recipe_definition.gd`
Defines a production recipe.

Mission:
- Store recipe id, inputs, outputs, required stations, worker roles, timing, animation, and output destination.

### `recipe_editor.gd`
UI/controller for editing recipes.

Mission:
- Create, edit, delete recipes for the current building.
- Attach recipes to sockets, workstations, and storage zones.

### `recipe_step_data.gd`
Stores one step in a recipe.

Mission:
- Example: heat ingot, hammer blade, wrap handle, polish sword.
- Store step duration, station, required worker role, animation, and FX.

### `recipe_chain_view.gd`
Shows the full input-output dependency chain.

Mission:
- Visualize how raw ore, leather, wood, and labor become a sword.
- Highlight missing upstream data.

### `production_timing_tool.gd`
Sets time per item or step.

Mission:
- Define how long each product takes.
- Support modifiers from worker skill, upgrades, tools, power, and era.

### `input_output_mapper.gd`
Maps inputs/outputs to storage sockets.

Mission:
- Define where iron ingots arrive.
- Define where leather wraps go.
- Define where finished swords appear.

### `workstation_requirement_tool.gd`
Links recipes to required workstations.

Mission:
- Require an anvil, furnace, loom, tanning rack, laboratory bench, reactor, etc.

### `recipe_validator.gd`
Validates production setup.

Mission:
- Ensure recipes have inputs, outputs, stations, worker sockets, and storage routes.

---

## 1.9 Workers

```text
workers/
├── worker_role_definition.gd
├── required_worker_tool.gd
├── worker_animation_mapper.gd
├── worker_preview_spawner.gd
├── worker_schedule_tool.gd
└── worker_capacity_calculator.gd
```

### `worker_role_definition.gd`
Defines worker role types.

Mission:
- Store roles like miner, tanner, blacksmith, hauler, builder, scholar, medic, engineer, farmer.

### `required_worker_tool.gd`
Sets required workers for a building.

Mission:
- Define worker slots.
- Example: Forge requires 1 blacksmith, optional 1 apprentice, optional 1 hauler.

### `worker_animation_mapper.gd`
Maps work actions to animations.

Mission:
- hammering, carrying, sawing, tanning, reading, healing, repairing, welding, typing, operating controls.

### `worker_preview_spawner.gd`
Spawns preview workers in the editor.

Mission:
- Show workers inside the building.
- Test whether worker sockets and animations look correct.

### `worker_schedule_tool.gd`
Defines production rhythm.

Mission:
- Set whether the building runs continuously, by shift, by order, by recipe queue, or only when demanded.

### `worker_capacity_calculator.gd`
Calculates building throughput from worker slots.

Mission:
- Determine max simultaneous tasks.
- Example: two anvils and two blacksmith sockets allow two swords in parallel.

---

## 1.10 Simulation Preview

```text
simulation_preview/
├── preview_sim_controller.gd
├── preview_resource_spawner.gd
├── preview_worker_agent.gd
├── preview_recipe_runner.gd
├── preview_time_controller.gd
├── preview_event_log.gd
└── preview_bottleneck_report.gd
```

### `preview_sim_controller.gd`
Runs editor-only production simulations.

Mission:
- Simulate workers, resources, paths, recipes, and storage without launching the full game.

### `preview_resource_spawner.gd`
Creates fake resources for testing.

Mission:
- Spawn fake iron ingots, leather wraps, raw ore, swords, etc.
- Fill storage to chosen levels.

### `preview_worker_agent.gd`
Simple editor-only worker AI.

Mission:
- Move through path graph.
- Pick up fake resources.
- Play preview animations.

### `preview_recipe_runner.gd`
Runs one selected recipe.

Mission:
- Execute recipe steps.
- Verify timing, sockets, storage, animation, and output.

### `preview_time_controller.gd`
Controls preview speed.

Mission:
- Pause, play, step, fast-forward.

### `preview_event_log.gd`
Logs preview events.

Mission:
- Show messages like `Iron ingot delivered`, `Blacksmith reached anvil`, `Sword complete`, or `Path blocked`.

### `preview_bottleneck_report.gd`
Reports production issues.

Mission:
- Show missing sockets, missing inputs, invalid storage, blocked paths, or impossible recipes.

---

## 1.11 Validation

```text
validation/
├── blueprint_validator.gd
├── construction_validator.gd
├── recipe_validator.gd
├── pathing_validator.gd
├── layer_validator.gd
├── socket_validator.gd
├── storage_validator.gd
├── balance_validator.gd
└── validation_report.gd
```

### `blueprint_validator.gd`
Runs full validation on a building blueprint.

Mission:
- Call all specialized validators.
- Return warnings/errors before export.

### `construction_validator.gd`
Validates build order and materials.

Mission:
- Ensure foundation comes before walls, walls/supports before roofs, and required construction materials exist.

### `recipe_validator.gd`
Validates recipes.

Mission:
- Ensure recipe inputs, outputs, stations, workers, storage, and timing are complete.

### `pathing_validator.gd`
Validates internal paths.

Mission:
- Confirm workers can move from entrances to storage and workstations.

### `layer_validator.gd`
Validates visibility layers.

Mission:
- Ensure roofs are tagged, cutaway works, and required interior content remains visible.

### `socket_validator.gd`
Validates sockets.

Mission:
- Check that every required socket exists and is linked properly.

### `storage_validator.gd`
Validates storage.

Mission:
- Check that resources have legal input/output storage locations.

### `balance_validator.gd`
Flags suspicious balance values.

Mission:
- Warn if recipe time, output rate, cost, worker count, or storage capacity is obviously absurd.
- Not perfect. Just prevents `1 wood = orbital laser` because humans keep needing guardrails.

### `validation_report.gd`
Formats validation results.

Mission:
- Show errors, warnings, suggestions, and export readiness.

---

## 1.12 Export

```text
export/
├── blueprint_exporter.gd
├── blueprint_importer.gd
├── blueprint_serializer.gd
├── blueprint_deserializer.gd
├── runtime_scene_baker.gd
├── thumbnail_generator.gd
├── mesh_layer_baker.gd
└── export_manifest_writer.gd
```

### `blueprint_exporter.gd`
Exports the current building blueprint.

Mission:
- Validate blueprint.
- Save blueprint as `.tres`, `.res`, `.json`, or a combined format.

### `blueprint_importer.gd`
Imports existing blueprints.

Mission:
- Load saved building data into the editor.

### `blueprint_serializer.gd`
Converts editor data to serialized format.

Mission:
- Strip editor-only UI data.
- Preserve runtime-needed blocks, sockets, paths, layers, recipes, and storage.

### `blueprint_deserializer.gd`
Converts saved data back into editor data.

Mission:
- Rebuild editable blueprint state from disk.

### `runtime_scene_baker.gd`
Builds optimized runtime scene versions.

Mission:
- Convert editable blueprint into runtime-friendly nodes/scenes.
- Keep interactable objects separate.

### `thumbnail_generator.gd`
Creates building preview icons.

Mission:
- Render small preview images for build menus.

### `mesh_layer_baker.gd`
Bakes blocks into layer meshes.

Mission:
- Combine visual blocks by layer for performance.
- Keep roof, walls, floor, interior, and props separable for hiding/fading.

### `export_manifest_writer.gd`
Writes export metadata.

Mission:
- Track blueprint version, dependencies, block library version, author, validation status, and required resources.

---

## 1.13 Editor UI

```text
ui/
├── editor_main_panel.tscn
├── editor_toolbar.tscn
├── block_palette_panel.tscn
├── layer_panel.tscn
├── socket_panel.tscn
├── pathing_panel.tscn
├── storage_panel.tscn
├── recipe_panel.tscn
├── worker_panel.tscn
├── validation_panel.tscn
├── simulation_panel.tscn
└── export_panel.tscn
```

### `editor_main_panel.tscn`
Main editor UI layout.

Mission:
- Hold viewport and major panels.

### `editor_toolbar.tscn`
Top-level tool selector.

Mission:
- Switch between block, layer, socket, pathing, storage, recipe, worker, simulation, and export modes.

### `block_palette_panel.tscn`
UI for choosing blocks.

Mission:
- Display block categories, search, filters, and variants.

### `layer_panel.tscn`
UI for assigning/hiding layers.

Mission:
- Choose active layer.
- Toggle visibility/fade.

### `socket_panel.tscn`
UI for socket creation and editing.

Mission:
- Choose socket type.
- Edit socket role, links, and rules.

### `pathing_panel.tscn`
UI for internal pathing.

Mission:
- Draw, edit, validate, and preview paths.

### `storage_panel.tscn`
UI for storage logic.

Mission:
- Assign storage slots, accepted resources, and capacity.

### `recipe_panel.tscn`
UI for production recipes.

Mission:
- Define inputs, outputs, steps, times, stations, and animations.

### `worker_panel.tscn`
UI for worker role requirements.

Mission:
- Define worker slots, roles, animations, and work capacity.

### `validation_panel.tscn`
UI for validation errors/warnings.

Mission:
- Show what must be fixed before export.

### `simulation_panel.tscn`
UI for preview simulation.

Mission:
- Run fake worker/resource tests inside the building editor.

### `export_panel.tscn`
UI for saving/exporting blueprints.

Mission:
- Save blueprint, bake runtime scene, generate thumbnail, write manifest.

---

# 2. Core Game Runtime

```text
res://core_game/
├── bootstrap/
├── camera/
├── ui_ux/
├── world/
├── terrain/
├── resources/
├── economy/
├── logistics/
├── construction/
├── buildings/
├── workers/
├── units/
├── pathing/
├── ai/
├── combat/
├── factions/
├── tech/
├── eras/
├── save_load/
└── multiplayer/
```

---

## 2.1 Bootstrap

```text
bootstrap/
├── game_bootstrap.gd
├── service_locator.gd
├── game_state.gd
├── tick_manager.gd
├── signal_bus.gd
└── config_loader.gd
```

### `game_bootstrap.gd`
Starts the game systems.

Mission:
- Load configs.
- Initialize managers.
- Load first map or test scene.

### `service_locator.gd`
Central registry for major systems.

Mission:
- Provide clean access to economy, logistics, construction, workers, pathing, UI, and debug systems.
- Use carefully. This is useful glue, not a trash can with functions.

### `game_state.gd`
Stores high-level game state.

Mission:
- Track current mode, selected objects, paused state, speed, victory/loss state, and current era.

### `tick_manager.gd`
Controls simulation timing.

Mission:
- Run economy ticks, AI ticks, logistics ticks, and construction updates.
- Separate simulation updates from rendering.

### `signal_bus.gd`
Global event bus.

Mission:
- Emit major events: resource moved, building placed, construction complete, recipe finished, worker died, raid started.

### `config_loader.gd`
Loads game-wide config files.

Mission:
- Load tuning data, debug flags, map settings, and difficulty values.

---

## 2.2 Runtime Camera

```text
camera/
├── rts_camera_controller.gd
├── rts_camera_movement.gd
├── rts_camera_zoom.gd
├── rts_camera_rotation.gd
├── camera_bounds.gd
├── camera_focus_controller.gd
├── selected_building_view_controller.gd
└── cutaway_camera_controller.gd
```

### `rts_camera_controller.gd`
Coordinates all runtime camera behavior.

Mission:
- Own camera mode.
- Route input to movement, zoom, rotation, and focus systems.

### `rts_camera_movement.gd`
Moves the camera across the world.

Mission:
- WASD, edge pan, drag pan.

### `rts_camera_zoom.gd`
Handles zoom levels.

Mission:
- Zoom smoothly.
- Trigger LOD/visibility changes based on distance.

### `rts_camera_rotation.gd`
Handles camera rotation.

Mission:
- Rotate/snap to cardinal or isometric angles.

### `camera_bounds.gd`
Limits camera movement.

Mission:
- Prevent the player from scrolling into the abyss, where unfinished features live.

### `camera_focus_controller.gd`
Focuses camera on objects.

Mission:
- Jump/focus selected units, buildings, alerts, raids, or bottlenecks.

### `selected_building_view_controller.gd`
Frames selected buildings.

Mission:
- When a player selects a building, move/focus camera enough to inspect activity.

### `cutaway_camera_controller.gd`
Controls camera behavior when seeing inside buildings.

Mission:
- Apply blueprint-defined view angles.
- Trigger roof/wall hiding based on camera angle and selection.

---

## 2.3 UI/UX

```text
ui_ux/
├── hud_controller.gd
├── selection_panel.gd
├── build_menu.gd
├── resource_bar.gd
├── bottleneck_panel.gd
├── production_chain_view.gd
├── building_inspector.gd
├── worker_inspector.gd
├── alert_panel.gd
├── tooltip_controller.gd
├── command_bar.gd
├── minimap_controller.gd
└── debug_ui_bridge.gd
```

### `hud_controller.gd`
Coordinates main UI.

Mission:
- Show resource bar, command bar, selection panel, alerts, minimap.

### `selection_panel.gd`
Displays selected object info.

Mission:
- Show selected unit/building stats and actions.

### `build_menu.gd`
Shows placeable buildings.

Mission:
- List available building blueprints by era/category.
- Launch placement mode.

### `resource_bar.gd`
Displays global/available resources.

Mission:
- Show stored resources, shortages, and income/consumption rates.

### `bottleneck_panel.gd`
Shows why production is blocked.

Mission:
- Explain missing resources, bad logistics, storage overflow, worker shortage, pathing failure, or damaged building.

### `production_chain_view.gd`
Shows dependency chains.

Mission:
- Let player click `Iron Sword` and see ore → ingot → leather wrap → handle → forge → sword.

### `building_inspector.gd`
Shows building internals.

Mission:
- Show storage, workers, active recipe, queue, cutaway toggle, and repair needs.

### `worker_inspector.gd`
Shows worker state.

Mission:
- Display role, task, carried item, destination, skill, health, morale.

### `alert_panel.gd`
Displays important events.

Mission:
- Raids, fires, blocked production, starvation, storage full, research complete.

### `tooltip_controller.gd`
Handles tooltips.

Mission:
- Centralize tooltip generation so the UI does not become a pile of inconsistent sticky notes.

### `command_bar.gd`
Shows available commands.

Mission:
- Build, move, gather, attack, repair, upgrade, assign, cancel.

### `minimap_controller.gd`
Manages minimap.

Mission:
- Show terrain, units, buildings, threats, trade routes, alerts.

### `debug_ui_bridge.gd`
Connects debug tools to runtime UI.

Mission:
- Toggle overlays and inspect hidden simulation data.

---

## 2.4 World and Terrain

```text
world/
├── world_manager.gd
├── world_grid.gd
├── world_chunk.gd
├── world_cell_data.gd
├── territory_manager.gd
├── map_generator.gd
└── world_event_manager.gd

terrain/
├── terrain_definition.gd
├── terrain_painter.gd
├── terrain_resource_spawner.gd
├── terrain_movement_costs.gd
├── water_manager.gd
└── biome_manager.gd
```

### `world_manager.gd`
Owns the world simulation.

Mission:
- Load chunks.
- Coordinate terrain, resources, buildings, units, and events.

### `world_grid.gd`
Stores grid coordinate logic.

Mission:
- Convert between world position and grid cells.
- Provide cell lookup, occupancy, and adjacency.

### `world_chunk.gd`
Represents one loaded map chunk.

Mission:
- Store cells, terrain, resources, local entities, and chunk-level updates.

### `world_cell_data.gd`
Stores one cell's data.

Mission:
- Terrain type, occupancy, resource node, road, building, claim status, movement cost.

### `territory_manager.gd`
Tracks controlled territory.

Mission:
- Determine where players can build.
- Expand territory via town halls, outposts, roads, towers, or claims.

### `map_generator.gd`
Generates maps.

Mission:
- Generate terrain, forests, water, ore, wildlife, ruins, and starting zones.

### `world_event_manager.gd`
Runs dynamic events.

Mission:
- Raids, fires, storms, shortages, wildlife migrations, faction events, disasters.

### `terrain_definition.gd`
Defines terrain types.

Mission:
- Store terrain id, movement cost, buildability, fertility, resource spawn rules.

### `terrain_painter.gd`
Paints terrain in dev/test tools.

Mission:
- Allow manual map editing for scenarios.

### `terrain_resource_spawner.gd`
Spawns resources on terrain.

Mission:
- Place trees, ore, clay, fish, animals, herbs, crystals.

### `terrain_movement_costs.gd`
Computes movement costs.

Mission:
- Roads fast, mud slow, forest slower, mountains painful, water impossible unless boat.

### `water_manager.gd`
Handles water cells.

Mission:
- Rivers, lakes, fishing zones, irrigation, docks, water-based placement.

### `biome_manager.gd`
Defines biome behavior.

Mission:
- Forest, plains, desert, mountains, snow, swamp, volcanic, alien, etc.

---

## 2.5 Resources and Economy

```text
resources/
├── resource_definition.gd
├── resource_stack.gd
├── resource_registry.gd
├── resource_node.gd
├── resource_converter.gd
└── resource_visualizer.gd

economy/
├── economy_manager.gd
├── recipe_runtime.gd
├── production_queue.gd
├── production_order.gd
├── throughput_calculator.gd
├── demand_manager.gd
├── shortage_detector.gd
└── item_lifecycle_tracker.gd
```

### `resource_definition.gd`
Defines a resource/item type.

Mission:
- Raw ore, iron ingot, leather wrap, sword, food, wood, stone, tools, etc.

### `resource_stack.gd`
Stores quantity of a resource.

Mission:
- Lightweight stack for inventories, storage, and haulers.

### `resource_registry.gd`
Central lookup for resource types.

Mission:
- Load all resource definitions from `data/resources/`.

### `resource_node.gd`
World resource source.

Mission:
- Tree, ore vein, animal source, fish zone, clay deposit, crystal node.

### `resource_converter.gd`
Converts raw resources into block/item equivalents.

Mission:
- Example: logs → planks, ore → ingots, hide → leather wraps.

### `resource_visualizer.gd`
Displays resources in storage/transport.

Mission:
- Show ore piles, ingots on shelves, swords on racks, food crates, leather hooks.

### `economy_manager.gd`
Coordinates production economy.

Mission:
- Track resource flows, active production, consumption, and shortages.

### `recipe_runtime.gd`
Runs a production recipe in-game.

Mission:
- Consume inputs, reserve workers, run steps, produce outputs.

### `production_queue.gd`
Stores queued recipes for a building.

Mission:
- Queue swords, tools, armor, bread, medicine, machine parts, etc.

### `production_order.gd`
One requested production task.

Mission:
- Produce 1 sword, 10 arrows, 5 bread, 1 gear, etc.

### `throughput_calculator.gd`
Calculates production rate.

Mission:
- Account for workers, skill, storage, input distance, building upgrades, power, damage.

### `demand_manager.gd`
Tracks needed items.

Mission:
- Soldiers need weapons, builders need blocks, citizens need food, factories need parts.

### `shortage_detector.gd`
Finds bottlenecks.

Mission:
- Detect missing inputs, storage overflow, worker shortage, path failure, transport backlog.

### `item_lifecycle_tracker.gd`
Optional system for item history.

Mission:
- Track where important items came from.
- Useful for legendary gear, trade goods, relics, or debugging.

---

## 2.6 Logistics

```text
logistics/
├── logistics_manager.gd
├── hauling_job.gd
├── job_board.gd
├── job_priority_calculator.gd
├── storage_manager.gd
├── storage_inventory.gd
├── storage_reservation.gd
├── transport_route.gd
├── road_network.gd
└── delivery_visualizer.gd
```

### `logistics_manager.gd`
Coordinates item movement.

Mission:
- Create hauling jobs.
- Assign haulers.
- Track deliveries.

### `hauling_job.gd`
One job to move an item from A to B.

Mission:
- Source storage, destination storage, resource type, quantity, priority.

### `job_board.gd`
Stores available jobs.

Mission:
- Construction jobs, hauling jobs, production jobs, repair jobs.

### `job_priority_calculator.gd`
Scores jobs.

Mission:
- Decide what matters most: food, construction, combat supplies, repair, production chain bottlenecks.

### `storage_manager.gd`
Coordinates all storage.

Mission:
- Find valid storage locations.
- Balance storage demand and capacity.

### `storage_inventory.gd`
Stores resources inside a building/storage node.

Mission:
- Add, remove, reserve, query resources.

### `storage_reservation.gd`
Prevents double-booking resources.

Mission:
- Reserve iron ingot for sword recipe so another worker does not steal it for a shovel like an economic little gremlin.

### `transport_route.gd`
Defines repeated movement routes.

Mission:
- Mine → smelter, smelter → forge, farm → granary, forge → armory.

### `road_network.gd`
Tracks road connectivity.

Mission:
- Improve path costs, hauling efficiency, trade, and expansion.

### `delivery_visualizer.gd`
Shows resource flow to the player.

Mission:
- Highlight moving items, routes, bottlenecks, and supply chain paths.

---

## 2.7 Construction

```text
construction/
├── construction_manager.gd
├── construction_site.gd
├── construction_job.gd
├── construction_stage.gd
├── construction_material_reserver.gd
├── block_build_order_solver.gd
├── construction_visualizer.gd
├── repair_manager.gd
├── repair_job.gd
└── demolition_manager.gd
```

### `construction_manager.gd`
Coordinates all active construction.

Mission:
- Create construction sites from blueprints.
- Generate jobs.
- Track completion.

### `construction_site.gd`
Runtime instance of a placed blueprint under construction.

Mission:
- Store placed blocks, missing blocks, assigned workers, reserved resources, stage, and completion percent.

### `construction_job.gd`
One task for a worker/builder.

Mission:
- Deliver material, place block, build stage, repair block, or clear debris.

### `construction_stage.gd`
Defines construction phases.

Mission:
- Foundation, floor, walls, roof, workstations, storage, finished.

### `construction_material_reserver.gd`
Reserves required blocks/resources.

Mission:
- Prevent resources needed for construction from being consumed elsewhere.

### `block_build_order_solver.gd`
Determines valid block construction order.

Mission:
- Build supports before roofs.
- Build lower layers before upper layers.
- Respect blueprint-defined dependencies.

### `construction_visualizer.gd`
Shows ghosts, partial construction, and missing blocks.

Mission:
- Turn blueprint construction into readable visual progress.

### `repair_manager.gd`
Coordinates repairs.

Mission:
- Convert missing/damaged blocks into repair jobs.

### `repair_job.gd`
One repair task.

Mission:
- Bring replacement block/material and restore damaged section.

### `demolition_manager.gd`
Handles removing buildings.

Mission:
- Deconstruct structures, return salvage, create debris, update pathing.

---

## 2.8 Buildings

```text
buildings/
├── building_manager.gd
├── building_instance.gd
├── building_blueprint_runtime.gd
├── building_placement_controller.gd
├── building_runtime_layers.gd
├── building_cutaway_controller.gd
├── building_storage_component.gd
├── building_production_component.gd
├── building_worker_component.gd
├── building_damage_component.gd
├── building_upgrade_component.gd
└── building_power_component.gd
```

### `building_manager.gd`
Tracks all buildings.

Mission:
- Register, query, update, and remove buildings.

### `building_instance.gd`
Main runtime building node.

Mission:
- Own building components.
- Connect construction, production, storage, workers, damage, upgrades, and visibility.

### `building_blueprint_runtime.gd`
Runtime-readable blueprint data.

Mission:
- Load exported blueprint data.
- Provide block, layer, socket, recipe, storage, and path data.

### `building_placement_controller.gd`
Handles player placement.

Mission:
- Preview blueprint ghost.
- Validate terrain, footprint, clearance, territory, water/road/resource rules.

### `building_runtime_layers.gd`
Stores visual layer nodes.

Mission:
- Group roof, walls, floor, interior, workstations, fx, storage visuals.

### `building_cutaway_controller.gd`
Hides/fades layers in-game.

Mission:
- Hide roof when selected.
- Show interior, production, repair, or damage views.

### `building_storage_component.gd`
Adds storage behavior.

Mission:
- Manage accepted resources, capacity, reservations, visual storage slots.

### `building_production_component.gd`
Runs recipes.

Mission:
- Request inputs, assign workers, run recipe steps, create outputs.

### `building_worker_component.gd`
Manages assigned workers.

Mission:
- Track required roles, open slots, active workers, and workstations.

### `building_damage_component.gd`
Handles building health/block damage.

Mission:
- Damage blocks, disable systems, trigger repair jobs.

### `building_upgrade_component.gd`
Handles upgrades.

Mission:
- Upgrade from basic forge to ironworks to foundry to nanoforge without rewriting everything like a fool.

### `building_power_component.gd`
Handles power/fuel/utility needs.

Mission:
- Coal, electricity, water, magic, steam, sci-fi power grids.

---

## 2.9 Workers and Units

```text
workers/
├── worker_manager.gd
├── worker_agent.gd
├── worker_state_machine.gd
├── worker_inventory.gd
├── worker_job_claiming.gd
├── worker_movement.gd
├── worker_animation_controller.gd
├── worker_skill_component.gd
├── worker_needs_component.gd
└── worker_role_component.gd

units/
├── unit_manager.gd
├── unit_definition.gd
├── unit_instance.gd
├── unit_selection.gd
├── unit_command_controller.gd
├── unit_inventory.gd
├── unit_equipment_component.gd
└── unit_training_component.gd
```

### `worker_manager.gd`
Tracks all civilian workers.

Mission:
- Spawn, assign, update, and query workers.

### `worker_agent.gd`
Main worker node.

Mission:
- Hold components for movement, inventory, role, skills, animation, and job state.

### `worker_state_machine.gd`
Controls worker behavior states.

Mission:
- Idle, moving, hauling, gathering, building, crafting, repairing, fleeing, resting.

### `worker_inventory.gd`
Stores carried items.

Mission:
- Track what the worker is carrying and capacity.

### `worker_job_claiming.gd`
Claims available jobs.

Mission:
- Pick jobs based on role, distance, priority, tools, and skill.

### `worker_movement.gd`
Moves workers.

Mission:
- External world movement plus internal building path movement.

### `worker_animation_controller.gd`
Controls animations.

Mission:
- Carrying, hammering, mining, sawing, tanning, farming, building, fighting.

### `worker_skill_component.gd`
Stores worker skill progression.

Mission:
- Blacksmith skill speeds sword crafting. Builder skill speeds construction. You know, labor having value. Radical.

### `worker_needs_component.gd`
Optional worker needs.

Mission:
- Food, sleep, morale, health, housing, education.

### `worker_role_component.gd`
Stores worker role.

Mission:
- Worker can be miner, tanner, blacksmith, hauler, builder, farmer, scholar, medic, etc.

### `unit_manager.gd`
Tracks military/commandable units.

Mission:
- Register soldiers, scouts, guards, siege units, vehicles, drones.

### `unit_definition.gd`
Defines unit types.

Mission:
- Stats, equipment needs, training cost, role, movement, combat behavior.

### `unit_instance.gd`
Main military unit node.

Mission:
- Runtime stats, movement, commands, combat, equipment, inventory.

### `unit_selection.gd`
Handles selecting units.

Mission:
- Box select, click select, group select.

### `unit_command_controller.gd`
Executes player unit commands.

Mission:
- Move, attack, patrol, defend, retreat, gather, escort.

### `unit_inventory.gd`
Stores unit carried items.

Mission:
- Ammo, food, tools, loot, special gear.

### `unit_equipment_component.gd`
Handles weapons/armor.

Mission:
- Soldier equips sword from armory. No sword, no swordsman. Terribly logical.

### `unit_training_component.gd`
Handles unit creation/training.

Mission:
- Convert recruit + equipment + time into trained unit.

---

## 2.10 Pathing

```text
pathing/
├── pathing_manager.gd
├── grid_pathfinder.gd
├── flow_field_pathfinder.gd
├── local_avoidance.gd
├── internal_building_pathfinder.gd
├── path_request.gd
├── path_result.gd
└── path_debug_drawer.gd
```

### `pathing_manager.gd`
Coordinates path requests.

Mission:
- Choose correct pathing system for unit type and request.

### `grid_pathfinder.gd`
Pathfinds over world grid.

Mission:
- A* or similar for individual movement.

### `flow_field_pathfinder.gd`
Handles many units moving toward common targets.

Mission:
- Useful for armies or worker swarms.

### `local_avoidance.gd`
Prevents collisions/clumping.

Mission:
- Smooth movement around units/buildings.

### `internal_building_pathfinder.gd`
Pathfinds inside buildings.

Mission:
- Worker entrance → storage → workstation → output rack.

### `path_request.gd`
Data object for a path request.

Mission:
- Source, destination, unit type, movement mode, priority.

### `path_result.gd`
Data object for path result.

Mission:
- Path points, cost, success/failure, reason.

### `path_debug_drawer.gd`
Draws pathing debug visuals.

Mission:
- Show paths, blocked cells, internal nodes, bottlenecks.

---

## 2.11 AI, Combat, Factions, Tech, Eras

```text
ai/
├── ai_city_manager.gd
├── ai_city_state.gd
├── ai_economy_planner.gd
├── ai_expansion_planner.gd
├── ai_trade_planner.gd
├── ai_raid_director.gd
└── ai_personality_profile.gd

combat/
├── combat_manager.gd
├── attack_component.gd
├── health_component.gd
├── damage_resolver.gd
├── projectile_controller.gd
├── threat_detector.gd
└── combat_group_controller.gd

factions/
├── faction_definition.gd
├── faction_manager.gd
├── diplomacy_manager.gd
├── trade_agreement.gd
└── reputation_tracker.gd

tech/
├── tech_tree_manager.gd
├── tech_definition.gd
├── research_project.gd
├── unlock_manager.gd
└── research_queue.gd

eras/
├── era_definition.gd
├── era_manager.gd
├── era_transition_controller.gd
└── era_reskin_mapper.gd
```

### `ai_city_manager.gd`
Tracks abstract AI cities.

Mission:
- Simulate distant economies, leaders, trade, expansion, raids, and diplomacy.

### `ai_city_state.gd`
Stores one AI city.

Mission:
- Population, resources, tech, military, trade needs, attitude, stability.

### `ai_economy_planner.gd`
Plans AI production.

Mission:
- Decide what AI cities produce, lack, trade, or fight over.

### `ai_expansion_planner.gd`
Plans AI territory growth.

Mission:
- Expand settlements, claim resources, build outposts.

### `ai_trade_planner.gd`
Plans trade routes.

Mission:
- Create supply/demand relationships between cities.

### `ai_raid_director.gd`
Controls enemy raids.

Mission:
- Spawn and direct threats based on world state and player vulnerability.

### `ai_personality_profile.gd`
Defines leader behavior.

Mission:
- Mayor, king, merchant prince, warlord, technocrat, druid, machine governor.

### `combat_manager.gd`
Coordinates combat.

Mission:
- Track combat encounters and route attack/damage events.

### `attack_component.gd`
Provides attack behavior.

Mission:
- Melee, ranged, siege, area, magic, guns, lasers.

### `health_component.gd`
Stores health.

Mission:
- Units/buildings/components can take damage.

### `damage_resolver.gd`
Calculates final damage.

Mission:
- Armor, material, block type, weapon type, fire, explosion, siege, era mismatch.

### `projectile_controller.gd`
Moves projectiles.

Mission:
- Arrows, stones, bullets, rockets, plasma bolts, because escalation is apparently inevitable.

### `threat_detector.gd`
Detects enemies.

Mission:
- Alert workers, towers, guards, and UI.

### `combat_group_controller.gd`
Controls squads/groups.

Mission:
- Formation, attack-move, guard, retreat, focus fire.

### `faction_definition.gd`
Defines a faction.

Mission:
- Name, ideology, units, buildings, trade preferences, diplomatic bias.

### `faction_manager.gd`
Tracks factions.

Mission:
- Player and AI faction state.

### `diplomacy_manager.gd`
Handles relationships.

Mission:
- War, peace, alliance, tribute, embargo, trade.

### `trade_agreement.gd`
Stores trade terms.

Mission:
- Resource exchange, route, duration, price, risk.

### `reputation_tracker.gd`
Tracks faction opinion.

Mission:
- Help, betrayal, trade, attacks, pollution, territory disputes.

### `tech_tree_manager.gd`
Controls research.

Mission:
- Load tech tree and apply unlocks.

### `tech_definition.gd`
Defines one technology.

Mission:
- Cost, prerequisites, unlocked buildings, recipes, units, blocks, bonuses.

### `research_project.gd`
Runtime research task.

Mission:
- Track current research progress.

### `unlock_manager.gd`
Applies unlocks.

Mission:
- Make new blocks, buildings, recipes, units, and UI options available.

### `research_queue.gd`
Stores queued research.

Mission:
- Manage what gets researched next.

### `era_definition.gd`
Defines an era.

Mission:
- Survival, Village, Kingdom, Arcane, Industrial, Modern, Sci-Fi.

### `era_manager.gd`
Tracks current era.

Mission:
- Apply era-specific rules, UI, unlocks, and world events.

### `era_transition_controller.gd`
Handles era advancement.

Mission:
- Trigger transition effects, unlocks, warnings, and new problems.

### `era_reskin_mapper.gd`
Maps old building concepts to new era variants.

Mission:
- Forge → foundry → factory → nanoforge.

---

# 3. Data Folder

```text
res://data/
├── blocks/
├── buildings/
├── resources/
├── recipes/
├── workers/
├── units/
├── factions/
├── tech/
├── eras/
├── terrain/
├── biomes/
└── balance/
```

## Data Folder Rules

- Prefer Godot `.tres` Resources for editor-friendly data.
- Allow JSON export if external tools need to read it.
- Keep data versioned.
- Never bury core balance numbers in random scripts unless future-you deserves punishment.

### `data/blocks/`
Reusable block definitions.

Mission:
- Store block type resources: stone floor, wood wall, roof tile, forge furnace, anvil, crate, ingot shelf.

### `data/buildings/`
Exported building blueprints.

Mission:
- Store all player-buildable structures.

### `data/resources/`
Resource/item definitions.

Mission:
- Raw ore, iron ingot, leather wrap, sword, food, wood, stone, tools, etc.

### `data/recipes/`
Shared recipe definitions.

Mission:
- Some recipes may be building-specific, but global recipe templates live here.

### `data/workers/`
Worker role definitions.

Mission:
- Miner, tanner, blacksmith, hauler, builder, farmer, scholar, engineer.

### `data/units/`
Military/civilian unit definitions.

Mission:
- Swordsman, archer, scout, guard, knight, rifleman, drone.

### `data/factions/`
Faction definitions.

Mission:
- AI city types, kingdoms, raiders, merchants, druids, machine city, etc.

### `data/tech/`
Technology definitions.

Mission:
- Research costs, prerequisites, unlocks.

### `data/eras/`
Era definitions.

Mission:
- Era names, thresholds, unlock sets, visual themes, rule changes.

### `data/terrain/`
Terrain definitions.

Mission:
- Grass, water, stone, forest, ore, fertile soil, swamp, desert, snow.

### `data/biomes/`
Biome definitions.

Mission:
- Spawn rules and environmental behavior.

### `data/balance/`
Balance tables.

Mission:
- Production rates, build times, costs, worker speeds, combat tuning.

---

# 4. Assets Folder

```text
res://assets/
├── models/
├── block_meshes/
├── unit_meshes/
├── building_props/
├── textures/
├── materials/
├── shaders/
├── animations/
├── audio/
├── icons/
├── particles/
└── source_files/
```

### `assets/models/`
General 3D models.

Mission:
- Non-block models and reusable props.

### `assets/block_meshes/`
Block geometry.

Mission:
- Cubes, slopes, stairs, beams, walls, roofs, pipes, rails, sci-fi panels.

### `assets/unit_meshes/`
Unit models.

Mission:
- Workers, soldiers, animals, monsters, machines.

### `assets/building_props/`
Interior/exterior props.

Mission:
- Anvils, furnaces, beds, racks, barrels, crates, desks, machines.

### `assets/textures/`
Texture files.

Mission:
- Original textures only. No Minecraft asset goblin behavior.

### `assets/materials/`
Godot material resources.

Mission:
- Materials for blocks, units, terrain, props, effects.

### `assets/shaders/`
Shader files.

Mission:
- Ghost placement, cutaway fade, outlines, resource highlights, damage overlays.

### `assets/animations/`
Animation files.

Mission:
- Worker actions, unit movement, crafting, gathering, combat.

### `assets/audio/`
Sound and music.

Mission:
- Hammering, sawing, mining, footsteps, combat, UI, ambience.

### `assets/icons/`
UI icons.

Mission:
- Buildings, resources, tools, warnings, recipes, units.

### `assets/particles/`
Particle effects.

Mission:
- Sparks, smoke, dust, fire, steam, magic, electricity.

### `assets/source_files/`
Source art files.

Mission:
- Blockbench, Blender, Aseprite, Krita, PSD, or other editable sources.

---

# 5. Scenes Folder

```text
res://scenes/
├── main/
├── world/
├── buildings/
├── workers/
├── units/
├── ui/
├── effects/
├── test_maps/
└── prototypes/
```

### `scenes/main/`
Main boot scenes.

Mission:
- Main menu, game root, loading scene.

### `scenes/world/`
World scenes.

Mission:
- Map root, chunk scene, terrain cells, resource nodes.

### `scenes/buildings/`
Runtime building scenes.

Mission:
- Base building node, construction site, storage nodes, production nodes.

### `scenes/workers/`
Worker scenes.

Mission:
- Base worker, role variants, preview worker.

### `scenes/units/`
Military/commandable units.

Mission:
- Swordsman, archer, guard, scout, vehicle, drone.

### `scenes/ui/`
Runtime UI scenes.

Mission:
- HUD, panels, menus, overlays, tooltips.

### `scenes/effects/`
Effect scenes.

Mission:
- Fire, smoke, sparks, construction dust, selection rings, placement ghosts.

### `scenes/test_maps/`
Manual test maps.

Mission:
- Small maps for testing economy, combat, pathing, construction.

### `scenes/prototypes/`
Throwaway prototypes.

Mission:
- Experiments that are allowed to be messy and then deleted before they breed.

---

# 6. Shared Scripts

```text
res://scripts/
├── math/
├── grid/
├── serialization/
├── commands/
├── events/
├── state_machines/
├── utilities/
└── interfaces/
```

### `math/`
Common math helpers.

Mission:
- Grid math, coordinate transforms, curves, interpolation.

### `grid/`
Grid utilities.

Mission:
- Grid positions, directions, bounds, rotations, footprints.

### `serialization/`
Save/load helpers.

Mission:
- Convert data to/from Godot resources, dictionaries, JSON.

### `commands/`
Undoable command objects.

Mission:
- Editor undo/redo and possibly runtime command replay.

### `events/`
Reusable event objects.

Mission:
- Typed event payloads for signal bus.

### `state_machines/`
Reusable state machine framework.

Mission:
- Workers, units, buildings, AI, production.

### `utilities/`
General helper functions.

Mission:
- Small helpers that do not belong to a specific domain.

### `interfaces/`
Shared contracts/base classes.

Mission:
- Interfaces like buildable, damageable, storable, selectable, interactable.

---

# 7. Debug Folder

```text
res://debug/
├── debug_overlay.gd
├── debug_command_console.gd
├── economy_debug_view.gd
├── logistics_debug_view.gd
├── pathing_debug_view.gd
├── construction_debug_view.gd
├── worker_debug_view.gd
├── ai_debug_view.gd
└── profiler_markers.gd
```

### `debug_overlay.gd`
Main debug overlay.

Mission:
- Toggle debug panels and overlays.

### `debug_command_console.gd`
Developer console.

Mission:
- Spawn resources, workers, buildings, raids, and test events.

### `economy_debug_view.gd`
Economy inspection.

Mission:
- Show production rates, shortages, demand, active recipes.

### `logistics_debug_view.gd`
Logistics inspection.

Mission:
- Show hauling jobs, storage reservations, routes, blocked deliveries.

### `pathing_debug_view.gd`
Pathing inspection.

Mission:
- Show world paths, internal building paths, blocked cells.

### `construction_debug_view.gd`
Construction inspection.

Mission:
- Show construction sites, missing blocks, assigned workers, build order.

### `worker_debug_view.gd`
Worker inspection.

Mission:
- Show states, jobs, carried items, destinations.

### `ai_debug_view.gd`
AI inspection.

Mission:
- Show AI city goals, raids, trade, diplomacy, expansion.

### `profiler_markers.gd`
Custom profiling helpers.

Mission:
- Mark expensive systems and track frame/tick costs.

---

# 8. Tests Folder

```text
res://tests/
├── unit_tests/
├── integration_tests/
├── editor_tests/
├── simulation_tests/
├── performance_tests/
└── manual_test_scenes/
```

### `unit_tests/`
Small isolated tests.

Mission:
- Validate resource math, recipe logic, build order, grid math.

### `integration_tests/`
Multi-system tests.

Mission:
- Worker hauls ore → smelter makes ingot → forge makes sword.

### `editor_tests/`
Building editor validation tests.

Mission:
- Save/load blueprint, layer hiding, path validation, export/import.

### `simulation_tests/`
Full loop simulations.

Mission:
- Run economy/construction/combat scenarios headlessly where possible.

### `performance_tests/`
Stress tests.

Mission:
- 100 workers, 500 workers, 100 buildings, many storage jobs, huge path requests.

### `manual_test_scenes/`
Godot scenes for hand-testing.

Mission:
- Visual tests that are faster than launching the whole game.

---

# 9. Docs Folder

```text
res://docs/
├── 00_project_overview.md
├── 01_modular_project_layout.md
├── 02_gameplan.md
├── 03_building_editor_design.md
├── 04_production_chain_design.md
├── 05_worker_ai_design.md
├── 06_construction_system.md
├── 07_cutaway_building_system.md
├── 08_data_conventions.md
├── 09_godot_style_guide.md
├── 10_testing_plan.md
└── 11_milestone_log.md
```

### `00_project_overview.md`
High-level concept and pillars.

Mission:
- Explain what the game is.

### `01_modular_project_layout.md`
This document.

Mission:
- Keep the project organized before it becomes a digital junkyard.

### `02_gameplan.md`
Overall production plan.

Mission:
- Define milestones, sprint order, MVP, vertical slice, and release path.

### `03_building_editor_design.md`
Detailed building editor spec.

Mission:
- Explain editor modes, data, UI, and export flow.

### `04_production_chain_design.md`
Production chain design.

Mission:
- Define how resources visibly flow into products.

### `05_worker_ai_design.md`
Worker behavior design.

Mission:
- Define worker state machine, job claiming, roles, skills, and hauling.

### `06_construction_system.md`
Construction system design.

Mission:
- Define block-by-block construction, repair, and demolition.

### `07_cutaway_building_system.md`
Building visibility design.

Mission:
- Explain roof hiding, layer fading, interior inspection, and production view.

### `08_data_conventions.md`
Data naming and structure rules.

Mission:
- Keep resources, blocks, recipes, and blueprints consistent.

### `09_godot_style_guide.md`
Code and scene conventions.

Mission:
- Naming, signals, node structure, folder rules, typing, comments.

### `10_testing_plan.md`
Testing strategy.

Mission:
- Explain what must be tested and how.

### `11_milestone_log.md`
Project history.

Mission:
- Track completed milestones and decisions.

---

# Naming Conventions

## Files

Use snake case:

```text
building_cutaway_controller.gd
worker_state_machine.gd
production_chain_view.gd
```

## Classes

Use PascalCase:

```gdscript
class_name BuildingCutawayController
class_name WorkerStateMachine
class_name ProductionChainView
```

## Resource IDs

Use lowercase snake case:

```text
iron_ingot
leather_wrap
wood_handle
iron_sword
basic_forge
```

## Scene Names

Use PascalCase:

```text
ForgeBuilding.tscn
WorkerAgent.tscn
MainHUD.tscn
```

---

# Core Rule

The game should be built around reusable systems, not one-off scripts.

Every building should be made from:

```text
1. Physical blocks
2. Visibility layers
3. Gameplay sockets
4. Internal paths
5. Storage definitions
6. Production recipes
7. Worker requirements
8. Construction rules
9. Damage/repair rules
10. Runtime export data
```

That structure lets a forge, tannery, bakery, barracks, school, clinic, factory, reactor, and nanoforge all use the same backbone.

That is how this project avoids becoming 900 scripts named `thing_final_REAL_v3.gd`, the traditional tombstone of human software ambition.
