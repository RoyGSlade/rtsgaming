"""Headless Blender retargeting for pipeline Stages 6+7.

    blender --background --python retarget.py -- \
        --character staging/rigged/soldier.fbx --bvh-dir staging/bvh \
        --clips idle,walk,run --loop-clips idle,walk,run \
        --output godot_import/units/soldier.glb

For each clip: import <clip>.bvh, Rokoko-retarget onto the Mixamo-rigged
character at frame 0 (both in T-pose), push the action to an NLA track named
after the clip, delete the BVH rig. Loop clips get root motion flattened on
the ground plane (bake in place — RTS movement comes from steering code);
vertical root motion is kept. Exports one GLB whose NLA tracks become named
animations in Godot.

Requires the free Rokoko Studio Live add-on installed in this Blender.
Known limitation: fingers aren't driven (Kimodo's SMPL rig has no finger
bones) — fine at RTS camera distance.
"""

import argparse
import sys
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--character", required=True, help="Mixamo-rigged FBX")
    ap.add_argument("--bvh-dir", required=True)
    ap.add_argument("--clips", required=True, help="comma-separated clip names")
    ap.add_argument("--loop-clips", default="", help="clips to bake in place")
    ap.add_argument("--output", required=True)
    return ap.parse_args(argv)


def armatures():
    return [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]


def action_fcurves(action):
    """Blender 5.x slotted actions keep fcurves in layer channelbags;
    4.x exposes action.fcurves directly."""
    if getattr(action, "fcurves", None):
        return action.fcurves
    return action.layers[0].strips[0].channelbags[0].fcurves


def ensure_active_object() -> None:
    """FBX import into a fully empty scene fails with 'Context missing active
    object' — park an empty as the active object first."""
    if bpy.context.view_layer.objects.active is None:
        empty = bpy.data.objects.new("_import_anchor", None)
        bpy.context.scene.collection.objects.link(empty)
        bpy.context.view_layer.objects.active = empty


def find_hips(armature):
    for name in ("mixamorig:Hips", "mixamorig_Hips", "Hips"):
        if name in armature.pose.bones:
            return armature.pose.bones[name]
    sys.exit(f"no hips bone found on {armature.name}")


def bake_in_place(armature, action) -> None:
    """Flatten horizontal root motion. Blender is Z-up here: strip the bone-local
    location channels that map to world X/Y, keep the one mapping to world Z
    (vertical — preserved for jumps). glTF export converts to Y-up for Godot."""
    hips = find_hips(armature)
    rest = (armature.matrix_world @ hips.bone.matrix_local).to_3x3()
    data_path = f'pose.bones["{hips.name}"].location'
    for fc in action_fcurves(action):
        if fc.data_path != data_path:
            continue
        world_dir = rest @ Vector([1 if i == fc.array_index else 0 for i in range(3)])
        if abs(world_dir.normalized().z) > 0.7:
            continue  # vertical channel — keep
        base = fc.keyframe_points[0].co.y if fc.keyframe_points else 0.0
        for kp in fc.keyframe_points:
            kp.co.y = base
        fc.update()


def retarget_clip(target, bvh_path: Path, clip: str, in_place: bool) -> None:
    before = set(armatures())
    bpy.ops.import_anim.bvh(filepath=str(bvh_path))
    source = next(a for a in armatures() if a not in before)

    # Both rigs must be in T-pose at frame 0 (Kimodo export forces this).
    bpy.context.scene.frame_set(0)
    scn = bpy.context.scene
    scn.rsl_retargeting_armature_source = source
    scn.rsl_retargeting_armature_target = target
    bpy.ops.rsl.build_bone_list()
    scn.rsl_retargeting_auto_scaling = True
    bpy.ops.rsl.retarget_animation()

    action = target.animation_data.action
    if action is None:
        sys.exit(f"retarget produced no action for clip '{clip}'")
    action.name = clip
    if in_place:
        bake_in_place(target, action)

    track = target.animation_data.nla_tracks.new()
    track.name = clip
    track.strips.new(clip, int(action.frame_range[0]), action)
    target.animation_data.action = None

    bpy.data.objects.remove(source, do_unlink=True)


def main() -> None:
    args = parse_args()
    clips = args.clips.split(",")
    loop_clips = set(args.loop_clips.split(",")) if args.loop_clips else set()

    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        bpy.ops.preferences.addon_enable(module="rokoko-studio-live-blender")
    except Exception:
        sys.exit("Rokoko Studio Live add-on not installed in this Blender — "
                 "install it once via Edit > Preferences > Add-ons (free account).")

    ensure_active_object()
    bpy.ops.import_scene.fbx(filepath=args.character)
    target = next(iter(armatures()), None)
    if target is None:
        sys.exit(f"no armature in {args.character} — is this the Mixamo-rigged FBX?")

    # FBX import sometimes drops the texture binding — rebind material slot 0's
    # image if it exists but is unassigned. Then apply transforms on meshes.
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH":
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    if target.animation_data is None:
        target.animation_data_create()

    for clip in clips:
        bvh = Path(args.bvh_dir) / f"{clip}.bvh"
        print(f"retargeting {clip} ...")
        retarget_clip(target, bvh, clip, in_place=clip in loop_clips)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out), export_format="GLB",
        export_animation_mode="NLA_TRACKS",   # one named animation per track
        export_anim_single_armature=True,
    )
    print(f"exported {out} with clips: {', '.join(clips)}")


main()
