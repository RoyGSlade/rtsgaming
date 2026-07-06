# Building Asset Naming & Scene Conventions

Naming scheme for buildings as they move from "blueprint in World Forge" to
"real thing placeable in the game." Scoped to buildings only — not the
broader Workshop/part-assembly pipeline (see `WORLD_FORGE_CRAFTING_PLAN.md`
for that).

## Building type slugs

`building_type` is the module library id a building was generated from, or
`custom` for hand-built ones. It's the stable identifier used everywhere
below — in filenames, folder names, and the World Forge Building Type
dropdown.

| Slug         | Source                                            |
| ------------ | -------------------------------------------------- |
| `hut`        | `data/buildings/module_libraries/hut.json`         |
| `blacksmith` | `data/buildings/module_libraries/blacksmith.json`  |
| `keep`       | `data/buildings/module_libraries/keep.json`        |
| `castle`     | `data/buildings/module_libraries/castle.json`      |
| `custom`     | hand-built in World Forge, not generated           |

Adding a new building type is just dropping a new
`data/buildings/module_libraries/<slug>.json` — it shows up in every
dropdown and folder convention below automatically (see
`_building_type_catalog()` in `world_forge_main.gd`).

## Building id

`<building_type>_t<tier>` for anything WFC-generated (e.g. `hut_t2`,
`castle_t3`) — matches what the generator already emits as
`blueprint["id"]`. Hand-built buildings pick their own snake_case id
(`corner_watchtower`, not `Corner Watchtower` or `corner-watchtower`) —
enforced by `_sanitize_id()` in the World Forge Name/ID fields.

## Files per pipeline stage

```text
data/buildings/module_libraries/<type>.json     # WFC module + tier definitions (source of truth for a type)
data/world_forge/<id>.json                      # ForgeDocument in-progress save (editable, not game-ready)
data/buildings/<id>_blueprint.json              # exported BuildingBlueprint (what BuildingBlueprintLoader reads)
data/buildings/thumbnails/<id>.png              # cached browser preview icon (BlueprintThumbnailRenderer)
scenes/buildings/<type>/<id>.tscn               # FUTURE: the placeable, functional in-game building (see below)
scenes/buildings/<type>/<id>.gd                 # FUTURE: its behavior script, if it needs one beyond the base
```

The thumbnail and the exported blueprint are always keyed by `id` alone
(not `type/id`) since `BuildingBlueprintLoader` and the World Forge browser
both look them up by id directly — nesting them under a type subfolder
would just mean extra path-guessing for no benefit.

## What a building scene needs (not yet implemented)

Today, `BuildingBlueprint` is pure data (blocks/sockets/storage_slots/
recipes/lights/interior_cells) and `ConstructionSite` only tracks the block-
by-block build job queue — nothing yet instances a *finished* building as
something a unit can walk into, work at, or path around. That's the next
milestone this naming scheme is set up for. When it's built, each
`scenes/buildings/<type>/<id>.tscn` should wire up:

- **Collision** — a `StaticBody3D` (or per-block `CollisionShape3D`s) built
  from `blocks`, so the building actually blocks movement/projectiles.
- **Navigation** — a `NavigationObstacle3D` (or a cut region in the nav
  mesh) matching the footprint, so units path around it instead of through.
- **Sockets** — each blueprint `sockets` entry (currently just `entry`
  type) becomes a real `Marker3D` or `Area3D`, so workers/units have an
  actual node to path to and interact through.
- **Storage slots** — each `storage_slots` entry becomes a visible item
  display node, driven by `StorageInventory` (already exists — see
  `scripts/buildings/`).
- **Recipes** — each `recipes` entry needs a worker-facing production loop;
  `worker_socket_id`/`animation` in the recipe data already point at which
  socket and anim to use, they just don't drive anything yet.
- **Lights** — each `lights` entry (block-source torches/lanterns/
  braziers) becomes a live `LightFixtureEffect`
  (`scripts/rendering/light_fixture_effect.gd`) — this one already has its
  runtime piece built, just not wired into a building scene yet.
- **Interior cells** — `interior_cells` (enclosed air volume) is reserved
  for the future component/fluid sim per `WORLD_FORGE_CRAFTING_PLAN.md`; a
  building scene doesn't need to do anything with it yet beyond keeping it
  in the exported JSON.

A base scene/script most buildings can share (handling collision, nav
obstacle, and the generic socket/light/storage wiring from blueprint data)
is the natural starting point, with `scenes/buildings/<type>/<id>.gd`
reserved for type-specific behavior on top of that base — e.g. a
blacksmith's furnace heat logic wouldn't belong on a hut.
