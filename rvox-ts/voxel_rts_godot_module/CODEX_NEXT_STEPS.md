# Codex MCP Next Steps

Use these in order. Do not let Codex rewrite half the project in one prompt unless you enjoy digital raccoons with commit access.

## Step 1: Verify scripts compile

```text
Use godot-ai MCP to inspect the project. Open the Godot output/errors panel if available. Verify the scripts under res://scripts/world, res://scripts/buildings, and res://addons/block_building_editor compile. Make the smallest fixes needed for Godot 4.7 compatibility. Report every file changed.
```

## Step 2: Run debug world viewer

```text
Open res://scenes/world/WorldDebugViewer.tscn and run it. It should generate a tiny terrain preview using cube MeshInstance3D nodes. Fix only errors needed to make the debug scene run. Report every file changed.
```

## Step 3: Enable the editor plugin

```text
Enable the Block Building Editor plugin. Confirm a right-side dock appears with tabs for Blocks, Layers, Sockets, Storage, Recipes, and Preview. Do not implement new features yet. Fix only plugin load errors.
```

## Step 4: Add one real editor action

```text
In the Block Building Editor dock, add a button that loads data/buildings/forge_blueprint_example.json using BuildingBlueprintLoader and prints the required block counts to the Godot output.
```

## Step 5: Build runtime blueprint preview

```text
Create a scene that loads forge_blueprint_example.json and displays its blocks using cube MeshInstance3D nodes grouped by layer. Add a keyboard toggle to hide/show the roof layer.
```

## Step 6: Construction vertical slice

```text
Create a ConstructionSite scene that loads forge_blueprint_example.json, creates construction jobs, and lets a debug key build one block at a time in stage order. Show completion percent.
```

## Step 7: Worker hauling stub

```text
Create a simple WorkerConstructionAgent test scene. The worker should claim the next construction job, simulate hauling time, mark the block built, and repeat until the blueprint is complete.
```
