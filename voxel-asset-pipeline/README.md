# Voxel Asset Pipeline

Text idea → game-ready GLB for the voxel RTS (Godot 4.x). Fully local and free.
Two lanes: **props** (no rig) and **units** (rigged + animated, shared clip
library). Full design: `docs/` + the overarching plan.

```
prompt ─ ComfyUI: FLUX.2 Klein GGUF ─ ComfyUI: Pixal3D GGUF ─ Blender cleanup ─┬─ prop → godot_import/props/
         + Klein voxel LoRA           (Trellis2-GGUF nodes)                     └─ unit → Mixamo (manual)
                                                                                          → Rokoko retarget of shared
                                                                                            Kimodo BVH library
                                                                                          → godot_import/units/
```

Stages 1 and 2 both run inside the **one ComfyUI install at
`../ComfyUI`** (launch: `../ComfyUI/run_comfyui.sh`), driven over its API by
`tools/comfyui/run_workflow.py`. Pixal3D GGUF Q8_0 + Klein Q4_K both fit the
RTX 4060 Ti 16GB; still don't run Kimodo at the same time.

## One-time setup (state as of 2026-07-06)

1. ~~ComfyUI + Trellis2/Pixal3D-GGUF + GGUF nodes~~ installed at `../ComfyUI`.
   Klein voxel LoRA in place as `voxel_style.safetensors`. **Still missing:
   Klein text encoder (Qwen3-8B) + flux2 VAE** — when they land in
   `models/text_encoders` / `models/vae`, put the real filenames into
   `tools/comfyui/workflows/{unit,prop}_concept.json` (marked EDIT-AFTER-DOWNLOAD).
2. Kimodo — weights downloading to `../ComfyUI/models/huggingface/nvidia/`;
   wire up `tools/kimodo/` scripts once the runtime choice is settled.
3. Blender — `pipeline_config.yaml` already points at this machine's
   `~/Desktop/blender-5.1.2-linux-x64/blender`. Two add-ons still needed in it:
   - **3D Print Toolbox** extension (cleanup runs without it but skips the
     non-manifold fix — currently not installed, verified 2026-07-06)
   - free **Rokoko Studio Live** add-on for retargeting. *Unverified on
     Blender 5.1* — if it won't enable, retarget from a Blender 4.2 LTS
     install instead (set `blender:` in `pipeline_config.yaml`).
4. `pip install pyyaml` for the orchestrator.
5. Generate the shared BVH library once: `docs/kimodo_checklist.md`,
   check with `python pipeline.py animations`.

## Daily use

```bash
# add 4-6 lines to manifest/assets.yaml, then:
python pipeline.py build torch          # prop: runs straight through
python pipeline.py build soldier        # unit: pauses at the Mixamo step
python pipeline.py resume soldier       # after saving the rigged FBX
python pipeline.py status               # where is everything?
python pipeline.py redo soldier cleanup # rerun a stage (and those after it)
```

Start ComfyUI before image/mesh stages: `../ComfyUI/run_comfyui.sh`.

Outputs land in `godot_import/props|units/` — copy/symlink into the Godot
project. Units export NLA tracks as named animations (idle, walk, ...).

## Known limitations (accepted for v1)

- Mixamo is a browser step (checklist: `docs/mixamo_checklist.md`).
- Fingers aren't animated (Kimodo SMPL rig → no finger bones). Fine at RTS zoom.
- Pixal3D hallucinates the back side (no multi-view yet) and its texturing is
  weak — acceptable at RTS camera distance. For a hero asset, retexture the
  mesh with the Trellis2 texturing workflow
  (`../ComfyUI/custom_nodes/ComfyUI-Trellis2-GGUF/example_workflows/TextureMesh.json`).
- Generated meshes are smooth geometry that *looks* voxel; set `voxelize: true`
  per asset for true blocky remesh (style decision, off by default).
