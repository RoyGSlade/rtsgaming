#!/usr/bin/env bash
# Start the Kimodo web UI. Pass --offload to drop VRAM use to ~2GB
# (weights spill to system RAM, slower). Free the GPU first — don't run
# while ComfyUI or Hunyuan3D are loaded.
set -euo pipefail
cd "$(dirname "$0")/kimodo"
exec ./venv/bin/python app.py "$@"
