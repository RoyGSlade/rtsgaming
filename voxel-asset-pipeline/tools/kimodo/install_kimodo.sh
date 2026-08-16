#!/usr/bin/env bash
# Install NVIDIA Kimodo (text-to-motion) with the community quantized text
# encoder so it runs fully offline in ~6GB VRAM (~2GB with --offload).
# Linux port of the reference one-click .bat installer.
# Requires: git, python3.11-3.13. First run downloads models (~15 min).
set -euo pipefail
cd "$(dirname "$0")"

# Weights already downloaded 2026-07-06 to
#   ../../../ComfyUI/models/huggingface/nvidia/Kimodo-SOMA-RP-v1.1
# TODO(donaven): pin these to the exact repos from the reference workflow —
# the Kimodo *runtime* repo and Arowx's GGUF-quantized text encoder release.
KIMODO_REPO="${KIMODO_REPO:?set KIMODO_REPO to the Kimodo git URL}"
ENCODER_URL="${ENCODER_URL:?set ENCODER_URL to the quantized text encoder download URL}"

if [ ! -d kimodo ]; then
    git clone "$KIMODO_REPO" kimodo
fi
cd kimodo
python3 -m venv venv
./venv/bin/pip install -U pip
./venv/bin/pip install -r requirements.txt

mkdir -p models/text_encoder
if [ ! -f "models/text_encoder/$(basename "$ENCODER_URL")" ]; then
    curl -L "$ENCODER_URL" -o "models/text_encoder/$(basename "$ENCODER_URL")"
fi

echo "Done. Start the web UI with tools/kimodo/start_kimodo.sh"
