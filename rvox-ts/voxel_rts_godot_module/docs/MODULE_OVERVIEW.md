# Module Overview

## World System

```text
scripts/world/
├── metadata/     Block, biome, resource definitions and registries
├── config/       World generation presets and tunable parameters
├── chunks/       Data-only voxel chunk storage
├── generation/   Noise-based terrain, biome, tree, ore, and water fill generation
├── water/        Water cells, maps, and simple surface-flow direction
├── meshing/      Visible-face chunk meshing prototype
└── debug/        Tiny viewer and overlays for testing
```

## Building System

```text
scripts/buildings/
├── building_blueprint.gd       Stores block-by-block structures plus metadata
├── building_blueprint_loader.gd Loads JSON blueprints into resources
├── construction_site.gd        Runtime planned building state and job queue
└── layer_visibility_controller.gd Hides roof/walls/interior layers
```

## Worker System

```text
scripts/workers/
└── worker_construction_agent.gd Starter FSM for build jobs
```

## Editor Addon

```text
addons/block_building_editor/
├── plugin.cfg
├── block_building_editor_plugin.gd
├── ui/block_building_editor_dock.gd
└── tools/
    ├── editor_camera_orbit.gd
    ├── block_placement_cursor.gd
    ├── blueprint_serializer.gd
    └── layer_hider_tool.gd
```

## Data

```text
data/
├── blocks/          Example `.tres` block resources
├── world_presets/   Example world generation config
└── buildings/       Example forge blueprint JSON
```
