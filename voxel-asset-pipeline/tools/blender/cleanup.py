"""Headless Blender mesh cleanup for pipeline Stage 3.

    blender --background --python cleanup.py -- \
        --input raw.glb --output out.glb --tris 4000 [--lods] [--voxelize]

Import GLB -> merge verts -> consistent normals -> 3D-Print non-manifold fix ->
(optional blocky voxel remesh) -> decimate to budget -> apply transforms ->
export. Output .glb goes straight to Godot; output .fbx is the Mixamo upload.
--lods additionally writes <name>_lod1/<name>_lod2 GLBs at 50%/25% of budget.
"""

import argparse
import math
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--tris", type=int, required=True)
    ap.add_argument("--lods", action="store_true")
    ap.add_argument("--voxelize", action="store_true",
                    help="Remesh(BLOCKS) pass for true voxel geometry")
    return ap.parse_args(argv)


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def total_tris() -> int:
    count = 0
    for obj in mesh_objects():
        eval_obj = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        count += sum(len(p.vertices) - 2 for p in eval_obj.data.polygons)
    return count


def select_only(objs) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def clean_mesh(obj) -> None:
    select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0001)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    # 3D-Print toolbox: degenerate + non-manifold cleanup. Bundled add-on in
    # Blender <=4.1; an extension after that — skip with a warning if absent.
    try:
        for module in ("object_print3d_utils", "bl_ext.blender_org.print3d_toolbox"):
            try:
                bpy.ops.preferences.addon_enable(module=module)
                break
            except Exception:
                continue
        bpy.ops.mesh.print3d_clean_non_manifold()
    except Exception as e:
        print(f"WARN: 3D-Print non-manifold cleanup unavailable ({e}) — "
              "install the 3D Print Toolbox extension for best results")


def decimate(obj, target_tris: int, current_tris: int) -> None:
    if current_tris <= target_tris:
        return
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = target_tris / current_tris
    select_only([obj])
    bpy.ops.object.modifier_apply(modifier=mod.name)


def voxel_remesh(obj) -> None:
    # Block size relative to object dimensions: ~32 blocks along largest axis.
    size = max(obj.dimensions) / 32 or 0.05
    mod = obj.modifiers.new("voxelize", "REMESH")
    mod.mode = "BLOCKS"
    mod.octree_depth = 6
    mod.use_remove_disconnected = False
    select_only([obj])
    bpy.ops.object.modifier_apply(modifier=mod.name)


def export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.suffix.lower() == ".fbx":
        bpy.ops.export_scene.fbx(filepath=str(path), path_mode="COPY", embed_textures=True)
    else:
        bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB")
    print(f"exported {path}")


def main() -> None:
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=args.input)

    objs = mesh_objects()
    if not objs:
        sys.exit(f"no mesh objects in {args.input}")

    # Join multi-part output into one mesh — simpler budgets, one draw call.
    if len(objs) > 1:
        select_only(objs)
        bpy.ops.object.join()
        objs = [bpy.context.view_layer.objects.active]
    obj = objs[0]

    clean_mesh(obj)
    if args.voxelize:
        voxel_remesh(obj)

    before = total_tris()
    decimate(obj, args.tris, before)

    # Apply all transforms — prevents scale/offset bugs downstream in retargeting.
    select_only([obj])
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    out = Path(args.output)
    print(f"tris: {before} -> {total_tris()} (budget {args.tris})")
    export(out)

    if args.lods and out.suffix.lower() == ".glb":
        for lod, factor in ((1, 0.5), (2, 0.25)):
            decimate(obj, math.floor(args.tris * factor), total_tris())
            export(out.with_stem(f"{out.stem}_lod{lod}"))


main()
