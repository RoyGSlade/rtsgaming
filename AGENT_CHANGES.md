# Agent Changes

This file is the running handoff log for changes made by coding agents. Add the newest entry at the top and include the intent, files touched, verification performed, and any known follow-up work.

## 2026-07-04 — Touch controls and adaptive dynamic resolution

### Intent

Make the game playable on a touchscreen and hold framerate on weaker GPUs, per a direct user request ("touch screen controls in game and dynamic resolution smart controls too if available"). Camera and unit commands previously assumed keyboard + 3-button mouse; add a touch scheme alongside them without disturbing desktop input, and add adaptive 3D render scaling that only lowers internal resolution under GPU load.

### Changes

- Camera (`rts_camera_controller.gd`): added multi-touch gestures next to the existing mouse path — one-finger drag grab-pans the map (pan scales with zoom so the world tracks the finger at any distance), two-finger pinch zooms, two-finger twist rotates yaw. Tracks live touches in a dict; `is_gesture_active()` reports whether a two-finger gesture is in progress (stays true until every finger lifts). Twist uses a shortest-path `angle_delta()` static helper so a rotation across the ±PI seam doesn't spin the long way.
- Commands (`rts_command_controller.gd`): added a touch mode (set by GameMain when `DisplayServer.is_touchscreen_available()`). With no right-click on touch, a single-finger TAP unifies select + move — tap a unit to select, tap the ground with a unit selected to order it there. Commands fire on tap-RELEASE with a travel threshold (`TAP_MAX_TRAVEL`) so a pan-drag isn't a command, and are suppressed while `camera_rig.is_gesture_active()` so the first finger of a two-finger gesture (which emulates a mouse click) doesn't issue a stray order. Desktop mouse behavior (left select / right move on press) is unchanged.
- New `scripts/rendering/dynamic_resolution_controller.gd` (`DynamicResolutionController`): samples framerate every 0.5s and nudges the viewport's `scaling_3d_scale` down when below ~0.90x the target FPS and back up when above ~0.98x, with a dead-band to avoid oscillation. Target FPS follows the monitor refresh rate by default. Only the 3D world is scaled (UI is untouched). "Smart when available": when a RenderingDevice is present (Forward+/Mobile) the downscaled image is upscaled with FSR 2, and FSR 2 is engaged only while actually upscaling so native rendering pays no temporal-upscaler cost; otherwise bilinear. The scale decision is a pure static `compute_next_scale()` so the hysteresis is unit-testable.
- `game_main.gd`: instantiates the dynamic-resolution controller (preloaded, not by class_name, so a fresh checkout runs before the editor rescans), points it at a new `QualityStatus` HUD label, wires `camera_rig`/`touch_enabled` into the command controller, and swaps the on-screen controls hint to the gesture scheme on touchscreen devices.
- `GameMain.tscn`: added the `QualityStatus` HUD label (render scale + fps readout).
- `project.godot`: added `[input_devices] pointing/emulate_mouse_from_touch=true` explicitly — single-finger taps reach the command controller as emulated left-clicks and HUD buttons stay tappable, while multi-finger camera gestures come from the raw touch events (index 1+ is never emulated, so no conflict).

### Verification

- New `tests/test_input_and_rendering.gd`: 7 tests (scale steps down/up/holds/clamps/no-op-without-target, twist short-way wrap, zero delta) — all pass.
- Full suite: 78 tests passed (71 prior + 7 new), no regressions.
- Launched GameMain in Godot 4.7 via MCP: game went live with no runtime errors from the changed scripts (the only retained errors were pre-existing deliberate error-path world_forge tests). This dev machine has no touchscreen, so the touch paths are covered by the pure-logic tests and by-construction reasoning rather than a live tap — handed to the user to verify on a touch device.

### Follow-up

- Touch was validated by unit tests + a clean launch, not a live multi-touch session (no touchscreen on the dev box). User to confirm feel on a tablet/touch monitor: pan speed (`touch_pan_sensitivity`), pinch (`touch_pinch_sensitivity`), and twist (`touch_twist_sensitivity`) are exported for tuning.
- Optional: two-finger vertical drag for pitch/tilt (only yaw twist is a gesture today; pitch stays mouse/keyboard).
- Optional: a settings toggle / target-FPS picker for dynamic resolution (currently always-on adaptive, min scale 0.5).

## 2026-07-04 — World Forge crafting-plan foundation (materials, parts, kinetics) and Xbox controller support

### Intent

Move World Forge from a structure-only editor toward the full crafting-plan vision (`docs/WORLD_FORGE_CRAFTING_PLAN.md`): author machines and props from stock parts with real material properties, join them with sockets, and compile the result into physics-ready rigid-body groups. Iterated as a self-review loop — each step implemented, tested, and logged in `reporting.md` before moving to the next. Also added Xbox controller support per a direct user request, scoped to "pair to the PC directly" after confirming that was the intended setup over two wireless-phone-bridge alternatives.

### Changes

- Added `MaterialProperties`/`PartProfile` resources plus registries, and a starter catalog (14 materials, 8 parts — steel rod/sheet, wood beam/plank, wheel, axle, rope segment, crucible) under `data/world_forge/`.
- Converted the editor's hardcoded shape/component/marker arrays into `.tres` resources (`BlockShapeProfile`, `FunctionalComponentDefinition`, `MarkerDefinition`) loaded through registries, preserving palette order and exact runtime behavior.
- Added `PartGeometryFactory` for procedural part previews, with a per-part `long_axis` so vessels (Y-up) and rod-like parts (Z-axis) render and occupy fine-grid cells correctly.
- Added a Parts palette tab, fine-grid (1/8-cell) placement and picking with a dedicated sub-cell height control, and `PartSnapResolver` for socket-to-socket snapping (kind-compatible, axis-aware — coaxial for bearings, opposing for welds/hinges).
- Added `PartKineticsCompiler`: welds union-find parts into single rigid-body groups (summed mass), hinge/bearing/slider connections become real physics joints between groups, and power_shaft/item_port/heat_contact/rope_anchor connections are recorded for later phases (power network, thermal, rope) instead of guessed at now.
- Added Xbox-controller support to the editor: stick camera orbit/pan, trigger zoom, face-button place/erase/rotate/cycle-tool, LB/RB palette stepping, D-pad layer stepping, Start/Back undo/redo, aimed from a fixed viewport-center reticle since there's no mouse cursor when playing controller-only. No new app or networking involved — Godot reads a Bluetooth/USB-paired controller as a normal joypad.

### Verification

- World Forge suite: 57 tests passed (materials/parts/registries, snap-resolver kind and axis logic against real part data, kinetics-compiler grouping via the real placement pipeline, fine-grid picking, gamepad camera/button/reticle logic). Full project suite: 71 tests passed, confirmed stable across repeated runs.
- Godot 4.7 project launched via the editor with no runtime errors.

### Follow-up

- `PartKineticsCompiler.build_scene()`: turn compiled groups/joints into actual `RigidBody3D`/`HingeJoint3D`/`SliderJoint3D` nodes.
- Let a placement record *which* shared socket kind governs a connection (currently "weld" always wins when available, so two rod ends can't yet be joined as a hinge instead).
- Fine-grid click picking is still quantized through the coarse structure-cell raycast for `_place_at`'s generic contract; a dedicated Workshop viewport with true fine-grid mouse resolution is the natural next step.
- Part overlap/footprint validation (mirroring the existing component `can_place` check) doesn't exist yet.

## 2026-07-03 — World Forge shapes, snapping, and construction tools

### Intent

Keep World Forge focused on structural authoring while fluid/effect/recipe work proceeds independently: support real block shapes, orientation-aware assemblies, component snapping, and faster build manipulation.

### Changes

- Added procedural cube, slab, top-slab, stair, fence, pane/bars, and plate geometry.
- Added neighbor-derived fence/pane connections and rotated stair placement.
- Added shape-aware brush previews and invalid component-footprint previews.
- Added typed component ports, rotated multi-cell footprints, collision validation, and automatic compatible-port snapping.
- Added furnace/firebox/chimney and bellows/firebox snap chains plus rotatable multi-cell workbench components.
- Added filled-box, hollow-shell, move, duplicate, rotate, and replace tools.
- Added collision-safe paste/move operations.
- Added move/rotate support for staged nested blueprints, including rotation during finalization.

### Verification

- Godot 4.7 headless editor initialization completed without World Forge errors.
- Ran the expanded `world_forge` suite headlessly: 10 tests passed, covering shape construction, connected shapes/selection, port snapping/rotation, and transactional shell/box building.

### Follow-up

- Add selection and transform gizmos for components and markers.
- Add drag-box and predicate-based selection.
- Add custom-scene shape rendering and generated collision geometry.

## 2026-07-03 — World Forge full-screen editor foundation

### Intent

Replace the narrow building dock as the long-term authoring direction with one Halo-Forge-style tool for buildings, nested assemblies, encounter camps, ruins, and generation templates.

### Changes

- Added the full-screen World Forge Godot main-screen plugin.
- Added a three-panel blueprint library, live 3D grid, and separated Blocks/Components/Markers/Items/Rules workspace.
- Added block search/category filters, camera orbit/pan/zoom, height layers, placement, line, fill, connected/select-all, copy/paste, delete, and local transactional undo/redo.
- Added staged nested-blueprint placement and explicit finalization into independent descendants with parent provenance.
- Added component capabilities/rule emitters and scene markers for workers, logistics, spawns, resources, and patrols.
- Added shape, functional-component, simulation-rule, assembly, and multi-kind recipe Resource schemas.
- Extended block definitions with shape, rule, construction-item, and durability metadata.
- Added World Forge architecture documentation and automated coverage.

### Verification

- Started the project in Godot 4.7 headless editor mode with World Forge enabled and no plugin parse/runtime errors.
- Ran `world_forge`: 5 tests passed.
- Ran `game_foundation`: 4 tests passed.

### Follow-up

- Implement shape-profile rendering and collisions.
- Add staged-blueprint transform gizmos and component/marker property editing.
- Add recipe/assembly graph editing, cutaway worker previews, and the simulation-rule evaluator.

## 2026-07-02 — KayKit and Kenney metadata importer

### Intent

Replace the removed texture-pack integration with reusable KayKit/Kenney model and icon ingestion for block and resource metadata.

### Changes

- Added external source manifests with CC0 license notes for KayKit Block Bits, KayKit Resource Bits, and Kenney Voxel Pack.
- Extended block and resource metadata with packed scenes, preview icons, source-pack IDs, and license notes.
- Added a recursive, format-aware importer for GLB, GLTF, FBX, OBJ, and PNG assets.
- Added category/type inference, format deduplication, overwrite protection, and import reports.
- Added recursive block and resource registries for generated metadata.
- Added external-import controls to the Block Building Editor dock.
- Removed stale references to the deleted 128×128 texture pack.
- Generated 151 block definitions and 167 resource definitions.

### Verification

- Imported all three configured packs through Godot MCP.
- Re-ran with overwrite disabled and confirmed existing definitions were skipped.
- Verified generated definitions are discoverable through both registries.
- Ran importer and game-foundation test suites.

### Follow-up

- Generate rendered preview icons for model-only KayKit assets.
- Add per-source inclusion/exclusion filters for characters, spritesheets, and pack overview images.
- Build a runtime preview scene for generated `mesh_scene` assets.

## 2026-07-02 — Starter textured block library

### Intent

Connect the newly imported CC0 texture pack to block data, runtime voxel rendering, and the building-editor palette.

### Changes

- Extended block definitions with texture, tint, scale, and roughness metadata.
- Added stone-brick, wood-plank, tile-floor, and roof-shingle block resources.
- Assigned starter textures to grass and stone terrain blocks.
- Changed chunk meshing to create one named material surface per block type.
- Added a texture-backed block palette to the Block Building Editor dock.
- Added registry coverage for the starter visual blocks.

### Verification

- Scanned and reimported textures/resources through Godot MCP.
- Ran the foundation tests and the main world scene.
- Inspected the rendered terrain framebuffer and runtime logs.

### Follow-up

- Select final texture variants and tune tint/roughness values.
- Add dedicated textures for dirt, sand, snow, ores, logs, and leaves.
- Add a transparent water/foliage mesh pass.

## 2026-07-02 — Install voxel RTS module as game foundation

### Intent

Install the copy-into-project module and turn its data/world scaffolding into the launchable base of the game.

### Changes

- Installed the module's `scripts/`, `data/`, `scenes/`, and block-editor addon at the Godot project root.
- Preserved the original package under `voxel_rts_godot_module/` as a `.gdignore`d reference copy.
- Added a runtime world node that generates and meshes deterministic voxel terrain.
- Added a main game scene with RTS camera, lighting, environment, and generation HUD.
- Enabled the Block Building Editor plugin.
- Added foundation tests for deterministic generation, forge blueprint loading, and inventory limits.
- Renamed the earlier editor-only blueprint class to avoid conflicting with the runtime blueprint model.
- Fixed Godot 4.7 strict-typing errors in blueprint loading and water flow.

### Verification

- Scanned all installed resources through Godot MCP.
- Ran the world scene and confirmed chunk generation.
- Ran the main game scene and inspected its framebuffer and logs.
- Ran the `game_foundation` suite: 3 tests passed.

### Follow-up

- Add separate water and foliage mesh passes.
- Add chunk streaming around the camera.
- Connect block definitions to terrain materials instead of the debug material.
- Add headless tests for world determinism and blueprint loading.

## 2026-07-02 — Block editor foundation

### Intent

Create the first playable building-editor prototype before committing to the full planned editor architecture.

### Changes

- Added lightweight block-instance and building-blueprint data models.
- Added an interactive 3D block-editor prototype with snapped placement and removal.
- Added RTS-style editor camera movement, orbit, and zoom.
- Added draft clear, save, and load controls using JSON in `user://blueprints/`.
- Added the prototype as the project's main scene.

### Verification

- Created and inspected the scene through the Godot MCP editor connection.
- Ran the scene and checked Godot editor/game logs for script errors.

### Follow-up

- Add block palette data and multiple block types.
- Add height-layer controls and occupied-cell selection feedback.
- Add undo/redo commands before expanding placement tools.
- Add automated blueprint serialization tests.
## 2026-07-04 — World Forge production-authoring pass

### Intent

Make World Forge fast and safe enough for repeated RTS structure, assembly, camp, and ruin production while keeping its element model expandable.

### Changes

- Batched document change notifications so multi-cell tools rebuild the viewport once per operation.
- Unified selection, move, duplicate, rotate, and delete across blocks, components, markers, parts, and nested blueprints.
- Added true 1/8-cell part picking, fine-height control, local fine-grid preview, socket-aware hover, and collision-safe part movement.
- Added searchable component, marker, and part catalogs and split the crowded toolbar into tool/edit rows with shortcut hints.
- Added editable blueprint name/ID, Save As, dirty-state feedback, idle autosave/recovery, and reference validation.
- Made nested-blueprint finalization preserve blocks, components, markers, and placed parts with unique IDs and provenance.
- Added Ctrl+D duplicate, G move, Escape cancel, and regression coverage for batching, search, selection identity, validation, and nested finalization.

### Verification

- World Forge suite: 45 tests passed.
- Godot 4.7 headless editor project load completed successfully.

### Follow-up

- Add visible axis/plane transform gizmos and a numeric property inspector.
- Add drag-box/multi-type selection filters and general socket/path linking.
- Add construction-stage preview and blueprint lint overlays in the viewport.
