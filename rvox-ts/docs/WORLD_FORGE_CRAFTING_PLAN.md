# World Forge: Component Crafting, Kinetics & Thermal Simulation Plan

This plan extends World Forge from a *structure* editor (place blocks and
pre-made components) into a *fabrication* editor: build the components
themselves — a furnace, a forge, a catapult, a chair — out of stock parts
(wood beams, steel rods, steel sheets, wheels, rope), give them real motion
(hinges, bearings, throwing, driving) and real process behavior (heat,
melting, casting, production), then reuse them anywhere like a mod system.

Reference point: "a light version of Scrap Mechanic, but a bit more complex" —
plus heat/metallurgy, and authenticity as the goal. Not beautiful; *plausible*.
The machine should look like it works the way the real one works.

---

## 1. Where we are (foundation this builds on)

Already shipped in `addons/world_forge/` (see `WORLD_FORGE_ARCHITECTURE.md`):

- One document format (`ForgeDocument`) with orthogonal lanes: blocks,
  components, markers, nested blueprints, metadata.
- Block shapes decoupled from materials (`BlockShapeProfile`), rotation per
  instance, connection-aware fences/panes.
- Components with multi-cell footprints and **typed directional ports**
  (`firebox.heat_out (up) <-> furnace.heat_in (down)`), snap-required
  placement, collision validation (`FunctionalComponentDefinition`,
  `ComponentSnapResolver`).
- Data-driven simulation vocabulary that is *already serialized* but not yet
  evaluated: `SimulationRuleDefinition` (triggers/scopes/effects),
  `AssemblyDefinition` (required pieces, stages, granted capabilities),
  `ForgeRecipeDefinition` (capability-based recipes: `heat_source +
  smelting_chamber + exhaust` instead of "furnace").
- Nested blueprint staging → finalize with provenance
  (`parent_blueprint_id`, `source_instance_id`).
- The "rule illusion" philosophy: local, readable rules, not universal physics.

The pasted priority roadmap (editing controls, data-driven library, prefab
workflow, assembly stages, worker logistics, cutaway, validation, runtime
export) remains valid. This plan slots the new systems between those
milestones — section 8 gives the merged order.

---

## 2. The big architectural addition: two build scales

Everything the user described falls out of one structural decision. World
Forge gets a second, finer authoring scale, and a document can nest one
inside the other:

```text
STRUCTURE SCALE (exists today)          PART SCALE (new: "the Workshop")
1 m voxel cells                         0.125 m fine grid (1/8 cell)
blocks: stone, wood, plank...           stock parts: rod, sheet, beam, wheel...
components placed as units              components BUILT from parts
buildings, camps, ruins                 furnaces, catapults, chairs, tools
```

- **Workshop documents** (`purpose = "part_assembly"`) author a single
  component/prop on the fine grid out of stock parts, joints, and behavior
  markers. Output: a `CraftedComponentDefinition` — which is a
  `FunctionalComponentDefinition` (same ports/capabilities/footprint
  contract) *plus* a part graph.
- **Structure documents** keep working exactly as today, but the component
  palette now contains crafted components alongside hand-authored ones. The
  furnace you built in the Workshop snaps into a house by its ports like any
  built-in component.
- A crafted component's structure-scale footprint is derived automatically
  from its part bounds, rounded up to whole cells.

This is what makes "the editor is effectively a mod tool" true: nothing about
a crafted component is code — it's parts + joints + tagged behaviors + an
optional attached script, all serialized.

---

## 3. Stock part library (the raw vocabulary)

New resource: **`PartProfile`** (`model/part_profile.gd`), the part-scale
sibling of `BlockShapeProfile`. All parts are data (`.tres` under
`data/world_forge/parts/`), so adding a new part never touches code.

```gdscript
class_name PartProfile extends Resource
@export var id: StringName                 # &"steel_rod_4"
@export var display_name: String
@export var category: StringName           # structural | mechanical | flexible | vessel | tool
@export var geometry: Mesh                 # or parametric kind + params
@export var collision_boxes: Array[AABB]
@export var material_id: StringName        # -> MaterialProperties (section 4)
@export var occupancy: Array[Vector3i]     # fine-grid cells, for overlap checks
@export var sockets: Array[Dictionary]     # typed attach points (section 5)
@export var mass_kg: float                 # derived from material density * volume if 0
@export var stock_recipe_id: StringName    # how this stock is produced (rolling, sawing, casting)
```

Initial catalog (each in 2–4 lengths/sizes, parametric where cheap):

| Category    | Parts                                                                 |
|-------------|-----------------------------------------------------------------------|
| structural  | wood beam, wood plank, wood block, steel rod, steel sheet, steel plate, brick, firebrick |
| mechanical  | wheel, gear, axle, bearing block, hinge plate, pulley, crank, spring, latch/trigger |
| flexible    | rope segment, chain link, leather strap, cloth panel (drapeable)       |
| vessel      | crucible/pot, trough, mold (ingot/tool shapes), pipe, funnel, barrel   |
| tool/detail | anvil face, hammer head, tongs, bellows body, grindstone, hook, nail/peg |

Stock parts are also **items**: `steel_rod` exists in the item/recipe economy
(a smith *produces* rods from ingots — section 7), and the same id is what
you grab in the Workshop palette. One namespace, no translation layer.

---

## 4. Material property database (one table drives everything)

New resource: **`MaterialProperties`** (`data/world_forge/materials/*.tres`).
Physics mass, thermal behavior, and flammability all read from here, which is
what keeps the simulation *coherent* — the same steel that's heavy is the
steel that holds heat.

```gdscript
class_name MaterialProperties extends Resource
@export var id: StringName                  # &"steel", &"oak", &"clay_fired", &"bronze"
@export var density_kg_m3: float
@export var specific_heat: float            # J/(kg·K) — lumped model
@export var conductivity: float             # relative 0..1 contact-transfer factor
@export var ignition_temp_c: float          # < 0 = non-flammable
@export var melting_temp_c: float           # < 0 = never melts (in our range)
@export var working_temp_c: float           # forgeable/softening threshold (smithing)
@export var strength: float                 # joint/beam break threshold (section 5)
@export var molten_material_id: StringName  # what liquid it becomes (&"molten_iron")
```

Starter set: oak, pine, stone, brick, firebrick, clay (raw/fired), iron ore,
bloom iron, wrought iron, steel, bronze, charcoal, coal, leather, wool cloth,
rope fiber, water. ~15 rows, all tunable without code.

---

## 5. Sockets, joints, and rigging (how parts connect)

Parts connect through **typed sockets** — the part-scale generalization of the
component ports that already exist. A socket entry:

```text
{ id, position, axis, kinds: [weld|hinge|bearing|slider|rope_anchor|
                              item_port|heat_contact|power_shaft],
  accepts: [tags] }
```

Placement UX reuses the proven `ComponentSnapResolver` flow: drag a part near
a compatible exposed socket → it snaps, orientation-aware; incompatible or
overlapping → red ghost, rejected.

Joint kinds and what they map to at runtime (Jolt is already the physics
engine — `project.godot` sets `3d/physics_engine="Jolt Physics"`):

| Socket kind  | Runtime mapping                                | Enables |
|--------------|------------------------------------------------|---------|
| weld         | merged into same RigidBody (no joint cost)     | chairs, frames, 95% of connections |
| hinge        | `HingeJoint3D` (limits optional)               | doors, lids, catapult arm stop |
| bearing      | `HingeJoint3D` free-spinning, no limits        | wheels, axles, water wheel, pulley spin |
| slider       | `SliderJoint3D`                                | bellows, plunger, latch travel |
| rope_anchor  | rope run between two+ anchors (section 6c)     | pulleys, trebuchet sling, well bucket |
| power_shaft  | logical rotation network edge (not physics)    | mill drive, crank → grindstone |
| item_port    | logical item in/out (existing port concept)    | hopper → crucible, mold output |
| heat_contact | thermal graph edge (section 6b)                | firebox → pot, quench trough |

**Structural strength:** each physical joint stores a break impulse derived
from the weaker material's `strength`. Overload a beam or fling a catapult
too hard and the joint snaps — authenticity through failure, and it is one
number per joint, not stress FEA.

**Behavior markers** (Workshop-scale markers, same pattern as existing
worker/entrance markers): `trigger`, `counterweight`, `payload_seat`,
`operator_station`, `fuel_slot`, `pour_spout`, `mold_cavity`, `drape_over`.
Markers are how generic physics parts acquire machine meaning without code.

**Custom scripts:** `CraftedComponentDefinition.behavior_script: GDScript`
(optional, one per component; power users can also put scripts on parts). The
script extends `ForgeBehavior` with a fixed, documented event surface:

```gdscript
class_name ForgeBehavior extends RefCounted
func on_ready(ctx): pass          # ctx exposes parts, joints, markers, ports
func on_tick(ctx, dt): pass
func on_activated(ctx, who): pass          # operator/worker uses the component
func on_heat_changed(ctx, part, temp_c): pass
func on_power(ctx, shaft, rpm, torque): pass
func on_item_received(ctx, port, item): pass
func on_joint_broken(ctx, joint): pass
```

That single hook makes the editor moddable in the full sense: parts + data
for the 90% case, a script for the exotic 10% (a trap that fires when a unit
steps on a plate, a bell that rings at dawn).

---

## 6. The three simulations (kept deliberately separate)

The "rule illusion" philosophy survives, but graduates: instead of one rule
evaluator trying to fake everything, there are **three small, honest
simulators**, each running on the graph the editor already knows.

### 6a. Kinetics (Jolt rigid bodies + joints)

- At runtime (and in the Workshop's **Simulate mode**), a crafted component
  compiles to: welded groups merged into single `RigidBody3D`s (one convex
  collision shape per part, masses summed from materials) + physics joints
  from section 5. A fully-welded chair is exactly one static/rigid body —
  zero ongoing cost.
- Motion sources: worker/operator interaction (crank, bellows), power
  network (water wheel), gravity (counterweight), stored tension (spring +
  latch). A **latch/trigger part** holds a joint locked; releasing it is the
  catapult firing. Payload on a `payload_seat` marker is a free rigid body —
  Jolt does the throwing; no scripted ballistics.
- Islands sleep aggressively. A component with no moving joint compiles to a
  static body until an interaction wakes it.
- The **power network** (shafts/gears/pulley belts) is *logical*, not
  torque-accurate physics: a connected graph with rpm/torque values
  propagated with fixed ratios, visualized by actually spinning the wheel
  meshes. Physical where it's fun (catapult), abstract where physics would
  be a liability (gear trains).

### 6b. Thermal (lumped-capacitance part graph, fixed 2 Hz tick)

Per *part* (not per voxel): one temperature scalar. The graph edges are
`heat_contact` sockets plus detected part-part contact.

```text
T' = T + dt/C * ( Σ k_contact*(T_neighbor - T)   # conduction
                + P_source                        # firebox output (fuel-driven)
                - h*(T - T_ambient) )             # convection/radiation loss
```

- **Fuel model:** a firebox with charcoal in its `fuel_slot` emits power for
  a fuel-defined duration; a bellows pumping (kinetic!) multiplies output —
  the bellows→air_in port chain already sketched in the architecture doc
  becomes literal.
- **State machine per part** from `MaterialProperties`:
  `solid → working (forgeable) → molten`, plus `ignited → consumed` for
  flammables. Wooden handles on a too-hot pot char. Authenticity, one enum.
- **Molten & casting:** when a vessel's contents pass melting temp, the ore
  parts convert to a molten volume (liters) held by the vessel. Recipes gate
  the authentic steps: *skim slag* (worker step, removes impurity fraction),
  *pour* at a `pour_spout` into a reachable `mold_cavity`, cooling curve →
  solidifies into the mold's output part (ingot, tool head). Slag is a real
  output item. This is a **process graph, not fluid dynamics** — molten metal
  teleports spout→cavity behind a pour animation. Looks right, costs nothing.
- Caps: thermal graph only ticks components flagged `thermally_active`; a
  settled-cold component drops out of the tick entirely (same dormancy trick
  as the water simulator).

### 6c. Flexibles (rope, cloth) — authored look, bounded cost

- **Rope:** chain of short capsule rigid bodies with cone-limited joints
  between anchors, capped segment count (~12 per run); ropes in fully
  static assemblies bake to a curve mesh. Pulleys redirect a rope run and
  join the power/force network (hoist = crank + pulley + rope + hook).
- **Cloth/drape ("drape something over"):** in the *editor*, draping is a
  one-shot relax: the cloth panel lattice falls under gravity against
  collision until rest, then **bakes to a static mesh** (tanner's hides,
  table cloth, tent canvas). At *runtime* it's just a mesh. Optional wind
  sway via cheap vertex shader. Live soft-body cloth is explicitly out of
  scope.

---

## 7. Production, reuse, automation

- **Production:** already 90% designed — `ForgeRecipeDefinition` +
  capabilities. The new part is that crafted components *grant* capabilities
  from their working parts (crucible above melting temp grants
  `smelting_chamber`; anvil part + operator station grants `smithing`).
  Recipes then run as staged worker jobs (haul ore → load crucible → pump
  bellows → skim → pour → fetch ingot), each step gated on markers/ports
  existing and reachable — which is exactly the worker/logistics milestone
  already on the roadmap. Stock parts close the loop: smelter makes ingots,
  smith turns ingots into rods/sheets, rods/sheets build the next machine.
- **Reuse ("furnace into a lot of different houses, a bed"):** any selection
  (structure or workshop scale) → *Save as Assembly* into the library with a
  generated thumbnail. Paste into any document; staged-blueprint lifecycle
  (already built) handles it as one transactional object. The linked-vs-
  independent-copy decision from the pasted roadmap applies unchanged;
  crafted components default to **linked** (fix the furnace definition once,
  every placed furnace updates).
- **Automation (light, later):** item ports + a `conveyance` socket kind
  (chute/conveyor parts) let outputs flow to adjacent storage without a
  hauler. Deliberately last — workers hauling *is* the RTS charm; automation
  is an optimization layer, not the core.
- **Modding:** loader scans `user://mods/*/` (and `res://data/world_forge/`)
  for `PartProfile`/`MaterialProperties`/recipes/rules as `.tres` or JSON,
  plus `ForgeBehavior` scripts. Because everything above is id-referenced
  data, a mod is literally a folder. Version field + migration hook in the
  loader from day one (the document format already versions — keep that
  discipline).

---

## 8. Merged roadmap (pasted priorities + new systems)

The pasted 8-item roadmap stays; new work (★) interleaves where it has
dependencies. Order chosen so every phase ends in something you can click.

| Phase | Content | Demo that proves it |
|-------|---------|---------------------|
| 1 | **Professional editing controls** (drag-box/lasso, select-by predicates, gizmos, brush sizes, autosave/recovery) | comfortable large-building editing |
| 2 | **Data-driven shape/component library** (shapes/components → `.tres`, custom meshes, palette thumbnails/favorites) — prerequisite for everything ★ | add a new block shape with zero code |
| 3 | ★ **Part scale + Workshop documents** (fine grid, `PartProfile` catalog v1: structural+mechanical, socket snapping, weld-only) + `MaterialProperties` | build a **chair** and a **bed** from beams/planks, save as assembly |
| 4 | **Prefab & nested-blueprint workflow** (linked vs independent, unpack/relink/update-from-parent, variants) — now covers crafted components too | one furnace definition placed in 5 houses, edited once, all update |
| 5 | ★ **Kinetics** (hinge/bearing/slider joints, latch/trigger, counterweight, Workshop Simulate mode, joint-break strength) | working **catapult** throws a stone; door swings; bellows pumps |
| 6 | ★ **Thermal + casting** (2 Hz lumped model, fuel/firebox, state machine, molten/pour/mold process, slag step) | **bloomery run**: ore + charcoal + bellows → skim → pour → cool → ingot |
| 7 | **Assembly & construction stages** + ★ capability granting from parts (recipes bind to crafted machines) | construction bill auto-generated; smith **produces steel rods** on the new forge |
| 8 | **Worker & logistics layout** (stations, paths, reachability) — worker jobs drive the thermal/production steps from 6–7 | full smelting job chain run by workers, sim-proxy safe |
| 9 | ★ **Flexibles** (rope+pulley runs, one-shot cloth drape bake) + power network v1 (water wheel → mill) | hoist lifts a crate; tanner racks with draped hides; water-driven grindstone |
| 10 | **Cutaway & visibility editor**; **Validation & simulation preview** (now also validates ports/joints/thermal reachability: "why is my furnace not melting") | interior production view; validator explains missing bellows |
| 11 | **Runtime/export pipeline** (bake static by layer, keep interactive parts live, collision/nav, ★ behavior scripts + mod loader hardened) | village scene with 6 crafted machines at 60 fps |
| 12 | ★ **Automation-light** (chutes/conveyance, linked storage) + polish | ore chute feeds crucible without a hauler |

Rule of thumb baked into this order: *data before behavior* (2 before 3),
*motion before heat* (5 before 6 — casting needs pour/tip mechanics),
*machines before workers operate them* (6–7 before 8).

---

## 9. Performance & determinism guardrails

- Weld-merge is the golden rule: joints only where something actually moves.
  Budget alarm in the validator: warn past ~24 active bodies / 16 joints per
  component, hard cap with override.
- All three simulators tick fixed-step (physics 60, thermal 2, power 10) and
  sleep to zero when settled — same dormancy pattern proven by the water CA.
- Distant components: physics frozen (pose snapshot), thermal keeps ticking
  only if a job depends on it (simulation-proxy policy already in the doc).
- World-gen determinism untouched: crafted components are placed data;
  simulation state is runtime-only and never feeds back into generation.
- Save format: one `format_version` bump (2→3) adds `parts`, `joints`,
  `behavior` lanes to `ForgeDocument`; loader keeps normalizing v1/v2.

## 10. Explicit non-goals (scope armor)

- No CFD/fluid dynamics for molten metal or water inside machines (process
  graph + animation instead).
- No live soft-body cloth at runtime (bake-on-author only).
- No torque-accurate gear physics (logical power network).
- No per-voxel heat diffusion (per-part lumped model only).
- No free-form mesh sculpting — parts are the vocabulary; if a shape is
  missing, add a `PartProfile`, don't add a modeler.

## 11. Immediate next steps

1. Phase 1 editing controls (already the agreed next milestone — unchanged).
2. While that lands: write `PartProfile` + `MaterialProperties` resources and
   convert the existing hardcoded `SHAPES`/`COMPONENTS` arrays in
   `world_forge_main.gd` to `.tres` (Phase 2) — this is the load-bearing
   refactor everything else stands on.
3. Prototype spike (timeboxed): one Workshop document, fine grid, weld-only
   snapping, build a chair, save/place it in a structure document. Proves the
   two-scale document nesting before we commit UI polish to it.
