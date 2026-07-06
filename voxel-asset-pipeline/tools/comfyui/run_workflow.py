#!/usr/bin/env python3
"""Submit a workflow to a running ComfyUI server and collect the result file.
Drives both pipeline stages: text->image (FLUX.2 Klein) and image->3D
(Pixal3D GGUF). Stdlib only.

    run_workflow.py --workflow workflows/prop_concept.json \
        --prompt "a wooden torch" --out staging/images/torch.png

    run_workflow.py --workflow workflows/image_to_3d.json \
        --image staging/images/torch.png --prefix torch \
        --out staging/meshes_raw/torch.glb

Substitutions in workflow JSON string inputs: {PROMPT}, {IMAGE} (set to the
uploaded filename), {PREFIX}. Image outputs are downloaded via the API; mesh
outputs are picked up from the ComfyUI output dir (the Trellis2 export node
doesn't register files in history), matched by prefix, newest first.
"""

import argparse
import json
import mimetypes
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

COMFY_OUTPUT_DEFAULT = "/home/donaven/Desktop/rtsgaming/ComfyUI/output"


def api(server: str, path: str, payload: dict | None = None) -> dict:
    req = urllib.request.Request(
        server + path,
        data=json.dumps(payload).encode() if payload is not None else None,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def upload_image(server: str, path: Path) -> str:
    """POST multipart to /upload/image; returns the server-side filename."""
    boundary = uuid.uuid4().hex
    ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="image"; filename="{path.name}"\r\n'
        f"Content-Type: {ctype}\r\n\r\n"
    ).encode() + path.read_bytes() + (
        f"\r\n--{boundary}\r\n"
        f'Content-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n'
        f"--{boundary}--\r\n"
    ).encode()
    req = urllib.request.Request(
        server + "/upload/image", data=body,
        headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        info = json.loads(r.read())
    name = info["name"]
    if info.get("subfolder"):
        name = f"{info['subfolder']}/{name}"
    return name


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--workflow", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--prompt", help="fills {PROMPT}")
    ap.add_argument("--image", help="uploaded to the server, fills {IMAGE}")
    ap.add_argument("--prefix", help="fills {PREFIX}; used to find mesh outputs")
    ap.add_argument("--seed", type=int, help="override every seed input")
    ap.add_argument("--server", default="http://127.0.0.1:8188")
    ap.add_argument("--comfy-output", default=COMFY_OUTPUT_DEFAULT,
                    help="ComfyUI output dir (for outputs not exposed via API)")
    ap.add_argument("--timeout", type=int, default=1800)
    args = ap.parse_args()

    subs = {}
    if args.prompt:
        subs["{PROMPT}"] = args.prompt
    if args.prefix:
        subs["{PREFIX}"] = args.prefix
    if args.image:
        subs["{IMAGE}"] = upload_image(args.server, Path(args.image))

    graph = json.loads(Path(args.workflow).read_text())
    graph.pop("_comment", None)
    for node in graph.values():
        for key, val in node.get("inputs", {}).items():
            if isinstance(val, str):
                for token, repl in subs.items():
                    val = val.replace(token, repl)
                node["inputs"][key] = val
        if args.seed is not None and "seed" in node.get("inputs", {}):
            node["inputs"]["seed"] = args.seed

    started = time.time()
    try:
        resp = api(args.server, "/prompt", {"prompt": graph, "client_id": uuid.uuid4().hex})
    except urllib.error.URLError as e:
        sys.exit(f"cannot reach ComfyUI at {args.server} ({e.reason}) — "
                 "start it with ComfyUI/run_comfyui.sh")
    if "error" in resp:
        sys.exit(f"ComfyUI rejected the workflow: {json.dumps(resp, indent=2)}")
    prompt_id = resp["prompt_id"]
    print(f"queued {prompt_id}")

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.time() + args.timeout
    while time.time() < deadline:
        history = api(args.server, f"/history/{prompt_id}")
        if prompt_id in history:
            entry = history[prompt_id]
            status = entry.get("status", {})
            if status.get("status_str") == "error":
                sys.exit(f"generation failed: {json.dumps(status, indent=2)}")
            if status.get("completed"):
                images = [img for out in entry.get("outputs", {}).values()
                          for img in out.get("images", [])]
                if images:
                    img = images[0]
                    q = urllib.parse.urlencode({"filename": img["filename"],
                                                "subfolder": img.get("subfolder", ""),
                                                "type": img.get("type", "output")})
                    with urllib.request.urlopen(f"{args.server}/view?{q}", timeout=120) as r:
                        out_path.write_bytes(r.read())
                    print(f"saved {out_path}")
                    return
                if args.prefix:
                    candidates = [p for p in Path(args.comfy_output).rglob(f"{args.prefix}*")
                                  if p.suffix == out_path.suffix
                                  and p.stat().st_mtime >= started]
                    if candidates:
                        newest = max(candidates, key=lambda p: p.stat().st_mtime)
                        shutil.copy2(newest, out_path)
                        print(f"saved {out_path} (from {newest})")
                        return
                sys.exit("job completed but no output found — check the workflow's "
                         "export node prefix vs --prefix")
        time.sleep(3)
    sys.exit(f"timed out after {args.timeout}s waiting for prompt {prompt_id}")


if __name__ == "__main__":
    main()
