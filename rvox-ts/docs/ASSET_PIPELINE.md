# Blender → Godot Asset Pipeline

How 3D assets get from Blender into the game. Keeps `.blend` sources in-repo
and exports `.glb` (glTF binary) that Godot imports automatically.

## Folders

```text
assets/
├── blender/     .blend source files (editable master, one per asset)
└── models/      exported .glb files Godot imports and the game loads
```

Source and export are kept side by side and named the same
(`assets/blender/worker.blend` → `assets/models/worker.glb`) so the master
for any in-game model is obvious.

## Authoring conventions

- **Up axis:** model in Blender (Z-up); export with **+Y up** so it lands
  correct in Godot (Y-up). The glTF exporter's `export_yup=True` does this.
- **Scale = world units.** 1 Blender unit = 1 Godot unit = 1 voxel block.
  A character ~1.7 units tall reads right next to the block terrain.
- **Origin at the feet** (bottom-center). Units are positioned by their feet
  on the terrain, so the model origin must be there — no code offset needed.
  In Blender: 3D cursor to world origin, `Object ▸ Set Origin ▸ Origin to 3D
  Cursor` with the mesh feet at Z=0.
- **Low-poly, flat-shaded, flat material colors.** Match the blocky terrain.
  A handful of materials per asset (one per color) is plenty.
- **Apply scale/rotation** before export (`Object ▸ Apply ▸ Scale`) so
  transforms are baked into the mesh.

## Export (from Blender)

Select the asset, then export glTF binary to `assets/models/<name>.glb`:

```python
bpy.ops.export_scene.gltf(
    filepath="/home/donaven/Desktop/rtsgaming/rvox-ts/assets/models/worker.glb",
    export_format='GLB',
    use_selection=True,   # only the selected asset, not lights/cameras
    export_yup=True,      # Blender Z-up -> Godot Y-up
    export_apply=True,    # apply modifiers
    export_materials='EXPORT',
)
```

Also save the source once (`save_as_mainfile(..., copy=True)` keeps your live
session unchanged) to `assets/blender/<name>.blend`.

This can be driven interactively through the Blender MCP (`execute_blender_code`)
or done by hand in Blender — the conventions above are what matter.

## Import + use (in Godot)

Godot imports a dropped-in `.glb` as a **PackedScene** automatically the next
time the editor has focus (it writes a `.import` sidecar). No manual step.

Load and instance it in code:

```gdscript
const WORKER_MODEL_PATH := "res://assets/models/worker.glb"

if ResourceLoader.exists(WORKER_MODEL_PATH):
    var scene := load(WORKER_MODEL_PATH) as PackedScene
    add_child(scene.instantiate())
```

`scripts/units/unit.gd` does exactly this, with a capsule fallback so the
game still runs before the editor has imported the `.glb`.

## Adding a new asset (checklist)

1. Model it in Blender at world scale, Z-up, origin at the logical placement
   point (feet for characters, base-center for buildings/props).
2. Apply scale; keep materials flat and few.
3. Export `.glb` to `assets/models/`, save `.blend` to `assets/blender/`.
4. Let the Godot editor import it (open/focus the editor).
5. `load()` + `instantiate()` where you need it (or drag the `.glb` into a
   scene in the editor).

## Rigged / animated assets

Characters carry a skeleton and animations through the same `.glb`:

- Build limbs as separate segments (thigh/shin, upper/lower arm) so each
  rigidly follows one bone — clean low-poly articulation without smooth
  skinning.
- Give each mesh part a **vertex group named exactly after its bone** at
  weight 1.0 before joining, then parent to the armature with plain
  `ARMATURE` deform (not automatic weights) — deterministic, no bleed.
- Export with `export_apply=False` (baking modifiers would destroy the
  skin), `export_skins=True`, `export_animations=True`.
- Godot imports it as `Node3D ▸ Skeleton3D + skinned MeshInstance3D +
  AnimationPlayer`. Clips are **not** looping on import — set
  `loop_mode` in code (see `unit.gd`).
- `unit.gd` finds the `AnimationPlayer` and plays "Walk" while the unit is
  moving, stops it on arrival.

## Mixamo route (character animations)

For humanoid characters we can borrow Mixamo's free animation library instead
of hand-authoring. Mixamo re-rigs the mesh with its own ~65/33-bone skeleton,
so this *replaces* any hand-built rig:

1. Export the mesh **mesh-only, in a T/A-pose** (arms out — Mixamo's auto-rig
   needs to tell arms from torso). FBX or OBJ. Ours: `worker_for_mixamo.fbx`.
2. mixamo.com ▸ **Upload Character** → place the auto-rig markers → it rigs +
   previews animations on our mesh.
3. For each clip: enable **In Place** (locomotion — our code moves the unit),
   **Download** as **FBX Binary**; first clip **With Skin** (gives mesh +
   skeleton), the rest can be With or Without Skin.
4. In Blender: import the skinned clip, import each other clip, move its action
   onto the first armature (same bone names), delete the duplicate mesh/rig.
   Purge any stale non-`mixamorig` actions before exporting.
5. Export one `.glb`, `export_animation_mode='ACTIONS'`, each action becoming a
   named glTF animation.

Raw Mixamo downloads are kept in `assets/blender/mixamo_fbx/` for provenance.
Scale came in at world size (~1.8 u) and our 4 materials survived the round-trip.

## Current assets

**Characters** (`assets/models/*.glb`, Mixamo route):

| Asset   | Upload FBX (`assets/blender/mixamo_fbx/`) | Export                     | Rig / anims                       | Status                  |
|---------|-------------------------------------------|----------------------------|-----------------------------------|-------------------------|
| worker  | `worker_for_mixamo_upload.fbx`            | `assets/models/worker.glb` | Mixamo 33-bone · `Idle`,`Walk`,`Running`,`Digging`,`Carrying` | live in `unit.gd`       |
| soldier | `soldier_for_mixamo_upload.fbx`           | `assets/models/soldier.glb`| Mixamo 33-bone · **Sword & Shield pack** (49 clips) | live in game (demo spawn) |
| archer  | `archer_for_mixamo_upload.fbx`            | (pending Mixamo)           | —                                 | mesh rebuilt (open A-pose), awaiting rig |

> **Riggability:** Mixamo's auto-rigger can only place the wrist/elbow markers
> if each arm is clearly separated from the torso. Model characters in a real
> **A-pose** — arms embedded at the shoulder but swung ~30° out so the armpit
> is an open wedge (see `assets/blender/soldier.blend`). Arms tucked flush to
> the torso, or swung so far the shoulder detaches, both fail the auto-rig.

### Animation packs (Mixamo)

A Mixamo **pack** (e.g. Sword & Shield) downloads as a **zip of one FBX per
clip** plus the rigged mesh (`<char>_for_mixamo.fbx`). To bundle into one glb:
import the rigged mesh as the base armature, then for each clip FBX import it,
rename the single new action to a clean name + `use_fake_user=True`, and delete
the imported duplicate armature/mesh. Pack downloads have **no In-Place option**,
so locomotion clips carry root travel in the `mixamorig:Hips` location — flatten
the horizontal axis (the one whose keyframe range is large, >0.3) to 0 so the
clip plays in place (our code moves the unit). Export `export_animation_mode=
'ACTIONS'`. `soldier.glb` was built this way (49 clips, `soldier.blend` master).

**Item props** (`assets/models/items/*.glb`, static, no rig): sword, axe, hammer,
bow, arrow, quiver, chestplate, shield. Low-poly, flat materials, origin at
geometry center. Meant to be attached to character hand/back bones or dropped
in the world.
