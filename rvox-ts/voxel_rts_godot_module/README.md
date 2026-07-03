# Voxel RTS Godot Module Starter

This zip is a **copy-into-project module** for Godot 4.x. It is not a full Godot project. Drop the folders into the root of your existing Godot project, the same folder that contains `project.godot`.

It includes:

- Block metadata resources
- World generation config
- Chunk data model
- Terrain generation prototype
- Basic water map / flow data
- Chunk meshing prototype
- World debug viewer scene
- Starter block building editor addon
- Building blueprint / construction site data model
- Worker construction-agent starter
- Example block resources
- Example forge blueprint JSON

## Install

From the unzipped folder, copy these folders into your Godot project root:

```text
addons/
scripts/
data/
scenes/
```

Then open Godot and enable:

```text
Project → Project Settings → Plugins → Block Building Editor → Enable
```

Open this debug scene to test generation:

```text
res://scenes/world/WorldDebugViewer.tscn
```

## Intended first Codex/MCP task

Ask Codex to load the project, open `WorldDebugViewer.tscn`, run the scene, and fix any API differences caused by your exact Godot 4.7 build.

This is scaffolding. It gives the project bones instead of one cursed `world.gd` monolith. Naturally, the game still expects you to make art, gameplay, balance, UI, and the other small details that keep humans busy until the heat death of the universe.
