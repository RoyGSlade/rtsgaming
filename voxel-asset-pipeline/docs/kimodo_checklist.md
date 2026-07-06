# Kimodo BVH generation checklist

Generating the shared animation library (`pipeline.py animations` shows what's
missing). One BVH per clip from `manifest/animations.yaml`, saved to
`staging/bvh/<clip>.bvh`. The library is generated **once** and retargeted onto
every humanoid unit.

## Per clip

1. Free the GPU (stop ComfyUI / Hunyuan3D), then `tools/kimodo/start_kimodo.sh`
   (add `--offload` if VRAM is tight).
2. Skeleton: **SMPL human body** (best-tested rig).
3. Paste the clip's prompt from `animations.yaml` — prompts always start with
   **"a person..."**; set the frame count from the manifest (30 fps).
4. Multi-prompt timelines are allowed (different prompts on frame ranges) if a
   clip needs phases.
5. Constraints for precise key poses:
   - After **adding or editing any constraint, regenerate with the SAME seed**
     — otherwise the motion snaps between keyframes instead of blending.
6. **Before export: add a constraint forcing a T-pose at frame 0.**
   Retargeting fails without matching rest poses. A frame-0 constraint does
   *not* need a regenerate.
7. Export **BVH** → save as `staging/bvh/<clip>.bvh` (exact clip name).
8. `python pipeline.py animations` to confirm the library state.

## Loop clips (idle/walk/run/gather)

Aim for the last frame to roughly match the first pose; small mismatches are
hidden by AnimationTree blend times in Godot. Root motion is stripped
automatically at retarget time — don't worry about forward drift.
