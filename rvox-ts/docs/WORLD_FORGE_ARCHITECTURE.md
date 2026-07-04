# World Forge Architecture

World Forge is the full-screen authoring surface for buildings, assemblies, encounter camps, discoverable ruins, and world-generation templates. It intentionally uses one document format so a ruin with resource nodes and an enemy camp do not require separate incompatible editors.

## Current milestone

The Godot main-screen plugin provides:

- Blueprint library grouped by purpose.
- Live 3D grid with orbit, pan, zoom, and height layers.
- Separate Blocks, Components, Markers, Parts, Items, and Rules palettes.
- Search across every placeable catalog, with category filtering for blocks.
- Place, line, rectangle fill, single select, whole-structure connected select across mixed block types, and select-all.
- Filled-box and hollow-shell volume tools.
- Unified select, move, duplicate, rotate, delete, undo, and redo across blocks, components, markers, parts, and nested blueprints. Block selections additionally support copy, anchored paste, and replace.
- Cube, bottom/top slab, stair, fence, pane/bars, and plate geometry.
- Orientation-aware shape placement; fences and panes connect to cardinal neighbors.
- Multi-cell component footprints, visible component ports, collision validation, and compatible-port snapping.
- Staged nested-blueprint placement.
- Move/rotate staged blueprints, then explicitly finalize them into independent blocks, components, markers, and fine-grid parts while preserving parent provenance.
- Workshop-scale part placement on a 1/8-cell grid, local fine-grid preview, exact socket snapping, and fine-height layers.
- Editable blueprint name/ID, explicit Save As, dirty-state feedback, idle autosave/recovery, and catalog-reference validation.
- Building, assembly, encounter, ruin, generation-template, and interior-assembly document purposes.
- Worker, entrance, drop-off, pickup, unit-spawn, resource-node, and patrol markers.

Middle-drag orbits, Shift+middle-drag pans, and the wheel zooms. Ctrl+A/C/V/Z/Y, Ctrl+D, G, R, Delete, and Escape provide the expected selection, duplicate, move, rotate, delete, and cancel shortcuts.

## Shape and snapping model

Shape is stored independently from block material. The same stone or wood definition can therefore be placed as a cube, slab, stair, fence, pane, or plate without multiplying gameplay materials. Rotation lives on each placed instance.

Fence and pane visuals derive cardinal connection arms from neighboring shapes. Component definitions use rotated cell footprints and typed directional ports:

```text
firebox.heat_out (up) <-> furnace.heat_in (down)
furnace.exhaust_out (up) <-> chimney.exhaust_in (down)
bellows.air_out (east) <-> firebox.air_in (west)
```

When a snap-required component is placed near a compatible exposed port, World Forge computes its origin and orientation-aware footprint. Placement is rejected when its cells overlap structural blocks or another component. Port types describe assembly topology only; fluid and effect behavior remain outside this tool's lane.

## Document model

`ForgeDocument` stores orthogonal element lanes:

```text
blocks             structural cells and shapes
components         furnaces, anvils, storage, water/fire sources, machines
markers            workers, entrances, logistics, spawns, resources, patrols
placed_parts       fine-grid beams, rods, sheets, axles, wheels, rope, vessels
nested_instances   staged blueprints kept as one transactional object
metadata           rules, generation tags, resource-node configuration
```

Blueprints from the older building JSON format are normalized on load. Saving uses format version 3. Document edits are batchable, so large line/fill/box/shell operations emit one viewport refresh and one undo transaction rather than rebuilding once per cell.

## Nested blueprint lifecycle

```text
library blueprint
  -> stage
  -> place as one linked object (one undo operation)
  -> reposition/rotate/edit placement metadata (next milestone)
  -> finalize
  -> expand all authored element lanes into independent descendants
```

Finalized descendants retain `parent_blueprint_id` and `source_instance_id`. This supports provenance, upgrades, debugging, and selecting pieces by their original assembly without keeping them permanently locked to the source.

## Simulation-ready definitions

- `BlockShapeProfile`: reusable geometry, collision boxes, rotation, connection behavior, movement/visibility occupancy, and custom scenes.
- `FunctionalComponentDefinition`: footprints, capabilities, rule tags, ports, construction recipe, and runtime-node policy.
- `SimulationRuleDefinition`: trigger, scope, source/target tags, conditions, effects, priority, and debug description.
- `AssemblyDefinition`: required/optional pieces, construction stages, granted capabilities, clearance, and rules.
- `ForgeRecipeDefinition`: item crafting, assembly, construction, operation, upgrade, repair, and deconstruction recipes.

Recipes ask for capabilities rather than hard-coded building names. A medieval furnace and future industrial smelter can both satisfy `heat_source + smelting_chamber + exhaust` through different installed pieces.

## Rule illusion model

Rules are deliberately local and readable rather than attempting universal physics:

```text
fire emits thermal energy
flammable neighbors can ignite
metal receives heat
water supplies fluid level and directional force
a wheel receiving water force can provide rotation
rotation can satisfy a mill component's power capability
```

Placed components already serialize their capabilities and rule emitters. The evaluator and debug overlay are later milestones; editor data will not need another format migration when they arrive.

## Runtime visibility policy

Structural blocks may be baked by visibility layer. Interactive components remain runtime nodes. Worker markers default to `simulation_proxy`: the simulation retains their station, task, and state when distant or hidden, while the visual worker may be culled. Cutaway/interior views can render actual workers and visible production steps near the camera.

## Next milestones

1. Add custom-scene shape profiles and matching collision generation.
2. Add visible axis/plane transform gizmos and numeric property inspector for selected elements.
3. Add drag-box selection and predicates by material, shape, layer, parent, component, and tag.
4. Add general socket/path linking and a port-visibility toggle.
5. Add assembly graph editing and construction-stage preview.
6. Add cutaway and worker-path simulation preview.
