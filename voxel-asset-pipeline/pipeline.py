#!/usr/bin/env python3
"""Voxel RTS asset pipeline orchestrator.

    pipeline.py build <asset>     run all stages for one asset (pauses at Mixamo for units)
    pipeline.py resume <asset>    continue a unit after the manual Mixamo rigging step
    pipeline.py status [asset]    show per-asset stage progress
    pipeline.py list              list manifest assets
    pipeline.py animations        check/report the shared BVH library (staging/bvh/)
    pipeline.py redo <asset> <stage>   clear one stage (and everything after it) and rerun

Stage state lives in staging/.state/<asset>.json so any stage can be rerun
or resumed without redoing earlier work. Delete that file to start an asset over.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent
MANIFEST = ROOT / "manifest" / "assets.yaml"
ANIMATIONS = ROOT / "manifest" / "animations.yaml"
STATE_DIR = ROOT / "staging" / ".state"

DEFAULT_TRIS = {"prop": 2000, "unit": 4000}

# Tool locations — override via pipeline_config.yaml next to this file.
CONFIG_DEFAULTS = {
    "blender": "blender",                      # Blender binary
    "comfyui_url": "http://127.0.0.1:8188",    # running ComfyUI instance
    "comfyui_output": "/home/donaven/Desktop/rtsgaming/ComfyUI/output",
}


def load_config() -> dict:
    cfg = dict(CONFIG_DEFAULTS)
    cfg_file = ROOT / "pipeline_config.yaml"
    if cfg_file.exists():
        cfg.update(yaml.safe_load(cfg_file.read_text()) or {})
    return cfg


def load_manifest() -> dict:
    return yaml.safe_load(MANIFEST.read_text())["assets"]


def load_animations() -> dict:
    return yaml.safe_load(ANIMATIONS.read_text())


def asset_spec(name: str) -> dict:
    assets = load_manifest()
    if name not in assets:
        sys.exit(f"error: '{name}' not in manifest/assets.yaml (have: {', '.join(sorted(assets))})")
    spec = dict(assets[name])
    spec["name"] = name
    spec.setdefault("tris", DEFAULT_TRIS[spec["type"]])
    spec.setdefault("lods", False)
    spec.setdefault("voxelize", False)
    if spec["type"] == "unit":
        spec.setdefault("animations", list(load_animations()["clips"]))
    return spec


# --- state ------------------------------------------------------------------

def state_path(name: str) -> Path:
    return STATE_DIR / f"{name}.json"


def load_state(name: str) -> dict:
    p = state_path(name)
    return json.loads(p.read_text()) if p.exists() else {"done": []}


def mark_done(name: str, stage: str) -> None:
    st = load_state(name)
    if stage not in st["done"]:
        st["done"].append(stage)
    st[f"{stage}_at"] = time.strftime("%Y-%m-%d %H:%M:%S")
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_path(name).write_text(json.dumps(st, indent=2))


# --- stages -----------------------------------------------------------------
# Each stage fn returns None on success and raises/exits on failure.
# File-existence checks double as "already done" guards for manual steps.

def run(cmd: list[str], **kw) -> None:
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    subprocess.run([str(c) for c in cmd], check=True, **kw)


def stage_image(spec: dict, cfg: dict) -> None:
    """Stage 1: ComfyUI + FLUX.2 Klein GGUF + voxel LoRA -> concept image."""
    workflow = "unit_concept.json" if spec["type"] == "unit" else "prop_concept.json"
    out = ROOT / "staging" / "images" / f"{spec['name']}.png"
    run([sys.executable, ROOT / "tools" / "comfyui" / "run_workflow.py",
         "--workflow", ROOT / "tools" / "comfyui" / "workflows" / workflow,
         "--prompt", spec["prompt"],
         "--server", cfg["comfyui_url"],
         "--timeout", 600,
         "--out", out])


def stage_mesh(spec: dict, cfg: dict) -> None:
    """Stage 2: Pixal3D GGUF (in ComfyUI) image -> textured GLB (raw, high poly)."""
    img = ROOT / "staging" / "images" / f"{spec['name']}.png"
    out = ROOT / "staging" / "meshes_raw" / f"{spec['name']}.glb"
    run([sys.executable, ROOT / "tools" / "comfyui" / "run_workflow.py",
         "--workflow", ROOT / "tools" / "comfyui" / "workflows" / "image_to_3d.json",
         "--image", img,
         "--prefix", spec["name"],
         "--server", cfg["comfyui_url"],
         "--comfy-output", cfg["comfyui_output"],
         "--timeout", 3600,
         "--out", out])


def stage_cleanup(spec: dict, cfg: dict) -> None:
    """Stage 3: Blender headless cleanup + decimate. Props -> final GLB,
    units -> FBX for Mixamo."""
    raw = ROOT / "staging" / "meshes_raw" / f"{spec['name']}.glb"
    if spec["type"] == "prop":
        out = ROOT / "godot_import" / "props" / f"{spec['name']}.glb"
    else:
        out = ROOT / "staging" / "for_mixamo" / f"{spec['name']}.fbx"
    cmd = [cfg["blender"], "--background", "--python",
           ROOT / "tools" / "blender" / "cleanup.py", "--",
           "--input", raw, "--output", out, "--tris", spec["tris"]]
    if spec["lods"]:
        cmd.append("--lods")
    if spec["voxelize"]:
        cmd.append("--voxelize")
    run(cmd)


def stage_mixamo(spec: dict, cfg: dict) -> None:
    """Stage 4 (manual): rig at mixamo.com. Pauses the pipeline."""
    rigged = ROOT / "staging" / "rigged" / f"{spec['name']}.fbx"
    if rigged.exists():
        return  # user already dropped the rigged file in — treat as done
    print(f"""
── MANUAL STEP: Mixamo rigging ─────────────────────────────────────
  1. Go to mixamo.com and upload:
       staging/for_mixamo/{spec['name']}.fbx
  2. Place the auto-rig markers (chin, wrists, elbows, knees, groin).
  3. Download as FBX, **T-pose, no animation**.
  4. Save it as:
       staging/rigged/{spec['name']}.fbx
  5. Run:  python pipeline.py resume {spec['name']}
  (Full checklist: docs/mixamo_checklist.md)
────────────────────────────────────────────────────────────────────""")
    sys.exit(0)


def stage_retarget(spec: dict, cfg: dict) -> None:
    """Stages 6+7: Rokoko retarget every library BVH onto the rigged unit,
    bake locomotion in place, export one GLB with named NLA clips."""
    missing = check_bvh_library(spec["animations"])
    if missing:
        sys.exit(f"missing BVH clips in staging/bvh/: {', '.join(missing)}\n"
                 "Generate them with Kimodo first — see `pipeline.py animations`.")
    rigged = ROOT / "staging" / "rigged" / f"{spec['name']}.fbx"
    out = ROOT / "godot_import" / "units" / f"{spec['name']}.glb"
    loop_clips = [c for c, v in load_animations()["clips"].items() if v.get("loop")]
    run([cfg["blender"], "--background", "--python",
         ROOT / "tools" / "blender" / "retarget.py", "--",
         "--character", rigged,
         "--bvh-dir", ROOT / "staging" / "bvh",
         "--clips", ",".join(spec["animations"]),
         "--loop-clips", ",".join(loop_clips),
         "--output", out])


PROP_STAGES = [("image", stage_image), ("mesh", stage_mesh), ("cleanup", stage_cleanup)]
UNIT_STAGES = PROP_STAGES + [("mixamo", stage_mixamo), ("retarget", stage_retarget)]


def stages_for(spec: dict):
    return UNIT_STAGES if spec["type"] == "unit" else PROP_STAGES


# --- commands ---------------------------------------------------------------

def cmd_build(name: str) -> None:
    spec = asset_spec(name)
    cfg = load_config()
    st = load_state(name)
    for stage, fn in stages_for(spec):
        if stage in st["done"]:
            print(f"[{name}] {stage}: already done, skipping")
            continue
        print(f"[{name}] {stage}: running")
        fn(spec, cfg)
        mark_done(name, stage)
    dest = "godot_import/props" if spec["type"] == "prop" else "godot_import/units"
    print(f"[{name}] complete → {dest}/{name}.glb")


def cmd_status(name: str | None) -> None:
    names = [name] if name else sorted(load_manifest())
    for n in names:
        spec = asset_spec(n)
        st = load_state(n)
        marks = " ".join(f"{'✔' if s in st['done'] else '·'}{s}" for s, _ in stages_for(spec))
        print(f"{n:20} [{spec['type']:4}] {marks}")


def check_bvh_library(clips: list[str]) -> list[str]:
    return [c for c in clips if not (ROOT / "staging" / "bvh" / f"{c}.bvh").exists()]


def cmd_animations() -> None:
    anims = load_animations()
    missing = check_bvh_library(list(anims["clips"]))
    for clip, v in anims["clips"].items():
        have = "✔" if clip not in missing else "MISSING"
        print(f"{have:8} {clip:15} {v['frames']:>4}f  \"{v['prompt']}\"")
    if missing:
        print("\nGenerate missing clips in the Kimodo web UI "
              "(tools/kimodo/start_kimodo.sh), export BVH to staging/bvh/<clip>.bvh.")
        print("Remember: T-pose constraint at frame 0 before every export.")
    else:
        print("\nAnimation library complete.")


def cmd_redo(name: str, stage: str) -> None:
    spec = asset_spec(name)
    order = [s for s, _ in stages_for(spec)]
    if stage not in order:
        sys.exit(f"error: '{stage}' is not a stage of {name} (stages: {', '.join(order)})")
    st = load_state(name)
    st["done"] = [s for s in st["done"] if order.index(s) < order.index(stage)]
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    state_path(name).write_text(json.dumps(st, indent=2))
    cmd_build(name)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for c in ("build", "resume"):
        sub.add_parser(c).add_argument("asset")
    sub.add_parser("status").add_argument("asset", nargs="?")
    sub.add_parser("list")
    sub.add_parser("animations")
    p = sub.add_parser("redo")
    p.add_argument("asset")
    p.add_argument("stage")
    a = ap.parse_args()

    if a.cmd in ("build", "resume"):
        cmd_build(a.asset)          # resume is just build: done-stages are skipped
    elif a.cmd == "status":
        cmd_status(a.asset)
    elif a.cmd == "list":
        for n in sorted(load_manifest()):
            print(n)
    elif a.cmd == "animations":
        cmd_animations()
    elif a.cmd == "redo":
        cmd_redo(a.asset, a.stage)


if __name__ == "__main__":
    main()
