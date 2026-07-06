#!/usr/bin/env python3
"""Scrape GrabCraft blueprints into World Forge building JSONs.

GrabCraft serves each blueprint's voxel data as a JS file
(/js/RenderObject/myRenderObject_<id>.js) keyed level -> x -> z, with
human-readable Minecraft block names. This tool fetches blueprint pages
(or whole category listings), maps Minecraft blocks onto the project's
block palette (res://data/blocks), and writes JSONs matching the schema
in data/buildings/forge_blueprint_example.json, loadable by
BlueprintSerializer.load_blueprint_json().

Usage:
  # Single blueprints
  python3 grabcraft_scraper.py https://www.grabcraft.com/minecraft/druids-hut/wooden-houses

  # Whole category (paginated), capped at 10 builds
  python3 grabcraft_scraper.py https://www.grabcraft.com/minecraft/wooden-houses --limit 10

  # Custom block mapping overrides
  python3 grabcraft_scraper.py <url> --map my_mapping.json

Only depends on the Python standard library. Requests are rate-limited
and cached on disk so re-runs don't re-hit the site.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

BASE = "https://www.grabcraft.com"
USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"

# Ordered keyword rules: first match on the lowercased Minecraft block
# name wins. Target None means the block is skipped (decoration, air,
# windows-as-holes, redstone, etc.). Extend/override with --map.
DEFAULT_RULES: list[tuple[str, str | None]] = [
    # No "air" rule: GrabCraft's sparse voxel dict never enumerates empty
    # cells (they're just absent), and matching "air" as a substring used to
    # swallow every "...Stairs..." name (st-AIR-s), silently deleting every
    # staircase from every converted building. See load_rules() for how
    # keyword-length ordering additionally prevents this class of bug.
    ("torch", "torch"),
    ("lever", None),
    ("button", None),
    ("tripwire", None),
    ("redstone", None),
    ("rail", None),
    ("carpet", None),
    ("banner", None),
    ("painting", None),
    ("item frame", None),
    ("flower", None),
    ("rose", None),
    ("dandelion", None),
    ("sapling", None),
    ("mushroom", None),
    ("tall grass", None),
    ("fern", None),
    ("dead bush", None),
    ("vines", None),
    ("vine", None),
    ("lily", None),
    ("cobweb", None),
    ("cauldron", None),
    ("foor", "wood_door"),  # GrabCraft typo for "door"
    ("glass", None),
    ("pane", None),
    ("bed", None),
    ("cake", None),
    ("pot", None),
    ("skull", None),
    ("head", None),
    ("leaves", "oak_leaves"),
    # Wood family. Checked before generic "wood"/"log" so that planks,
    # stairs, fences, doors etc. become wood_planks.
    ("plank", "wood_planks"),
    ("fence", "wood_planks"),
    ("gate", "wood_planks"),
    ("door", "wood_door"),
    ("trapdoor", "wood_planks"),
    ("ladder", "wood_planks"),
    ("sign", "wood_planks"),
    ("bookshelf", "wood_planks"),
    ("chest", "wood_planks"),
    ("crafting table", "wood_planks"),
    ("slab", "wood_planks"),
    ("wood stairs", "wood_planks"),
    ("log", "oak_log"),
    ("bark", "oak_log"),
    ("wood", "oak_log"),
    # Ores before generic stone.
    ("coal ore", "coal_ore"),
    ("iron ore", "iron_ore"),
    ("copper", "copper_ore"),
    # Roof-ish materials.
    ("terracotta", "roof_shingles"),
    ("hardened clay", "roof_shingles"),
    ("stained clay", "roof_shingles"),
    ("nether brick", "roof_shingles"),
    ("wool", "roof_shingles"),
    # Floors.
    ("quartz", "tile_floor"),
    ("polished", "tile_floor"),
    # Stone family.
    ("stone brick", "stone_bricks"),
    ("brick", "stone_bricks"),
    ("cobblestone", "stone"),
    ("mossy", "stone"),
    ("andesite", "stone"),
    ("granite", "stone"),
    ("diorite", "stone"),
    ("bedrock", "stone"),
    ("gravel", "stone"),
    ("obsidian", "stone"),
    ("furnace", "stone"),
    ("anvil", "stone"),
    ("stone", "stone"),
    # Ground.
    ("farmland", "dirt"),
    ("podzol", "dirt"),
    ("coarse dirt", "dirt"),
    ("grass path", "dirt"),
    ("dirt", "dirt"),
    ("mycelium", "dirt"),
    ("grass", "grass"),
    ("sandstone", "sand"),
    ("sand", "sand"),
    ("snow", "snow"),
    ("ice", "water"),
    ("water", "water"),
    # New palette additions: ores, farm produce, decor, glow blocks.
    ("gold ore", "gold_ore"),
    ("diamond ore", "diamond_ore"),
    ("diamond block", "diamond_block"),
    ("block of coal", "coal_block"),
    ("coal block", "coal_block"),
    ("hay bale", "hay_bale"),
    ("iron bars", "iron_bars"),
    ("melon", "melon"),
    ("bone block", "bone_block"),
    ("jack-o-lantern", "carved_pumpkin"),
    ("jack o lantern", "carved_pumpkin"),
    ("pumpkin", "pumpkin"),
    ("magma", "magma"),
    ("lava", "magma"),
    ("netherrack", "scorched_stone"),
    ("sugar cane", "sugarcane"),
    ("wheat", "wheat"),
    ("red tulip", "wildflower_red"),
    ("pink tulip", "wildflower_red"),
    ("poppy", "wildflower_red"),
    ("white tulip", "wildflower_white"),
    ("oxeye daisy", "wildflower_white"),
    ("azure bluet", "wildflower_white"),
    ("orange tulip", "wildflower_gold"),
    ("allium", "wildflower_purple"),
    ("blue orchid", "wildflower_purple"),
    ("tulip", "wildflower_red"),
    ("sea lantern", "crystal_lamp"),
    ("beacon", "crystal_lamp"),
    ("lantern", "crystal_lamp"),
    ("clay", "clay"),
    # Redstone/mechanism blocks have no equivalent system in this game.
    ("note block", None),
    ("jukebox", None),
    ("brewing stand", None),
    ("enchantment table", None),
    ("piston", None),
    ("end rod", None),
    ("command block", None),
    ("tnt", None),
    ("pressure plate", None),
    ("hopper", None),
    ("fire", None),
]

FALLBACK_BLOCK = "stone"


def fetch(url: str, cache_dir: Path, delay: float) -> str:
    key = hashlib.sha256(url.encode()).hexdigest()[:24]
    cached = cache_dir / key
    if cached.exists():
        return cached.read_text(encoding="utf-8")
    time.sleep(delay)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=30) as resp:
        text = resp.read().decode("utf-8", errors="replace")
    cache_dir.mkdir(parents=True, exist_ok=True)
    cached.write_text(text, encoding="utf-8")
    return text


def is_blueprint_url(url: str) -> bool:
    # Blueprint pages are /minecraft/<slug>/<category>, listings are /minecraft/<category>.
    path = url.split("//", 1)[-1].split("/", 1)[-1]
    parts = [p for p in path.split("/") if p]
    return len(parts) >= 3 and parts[0] == "minecraft"


def collect_category(url: str, cache_dir: Path, delay: float, limit: int) -> list[str]:
    """Walk a category listing (with pagination) and return blueprint URLs."""
    seen: list[str] = []
    page = 1
    base = url.rstrip("/")
    if "/pg/" in base:
        base = base.split("/pg/")[0]
    while len(seen) < limit:
        page_url = base if page == 1 else f"{base}/pg/{page}"
        try:
            html = fetch(page_url, cache_dir, delay)
        except urllib.error.HTTPError:
            break
        links = re.findall(r'href="(/minecraft/[a-z0-9-]+/[a-z0-9-]+)"', html)
        new = [BASE + l for l in dict.fromkeys(links) if BASE + l not in seen]
        if not new:
            break
        seen.extend(new)
        page += 1
    return seen[:limit]


def load_rules(map_file: str | None) -> list[tuple[str, str | None]]:
    # Sort by descending keyword length (stable, so same-length ties keep
    # their original relative order) so a specific multi-word/longer keyword
    # like "bedrock" or "sandstone" always wins over a shorter catch-all like
    # "bed" or "stone", regardless of which was written first in the table.
    # Without this, "Bedrock" silently matched "bed" -> None (deleted) and
    # every "Sandstone" variant matched the generic "stone" rule before ever
    # reaching the dedicated "sandstone" -> "sand" rule below it.
    defaults = sorted(DEFAULT_RULES, key=lambda rule: -len(rule[0]))
    if not map_file:
        return defaults
    overrides = json.loads(Path(map_file).read_text(encoding="utf-8"))
    # User overrides always take priority over the table, regardless of length.
    return [(k.lower(), v) for k, v in overrides.items()] + defaults


def map_block(name: str, rules: list[tuple[str, str | None]], unmapped: dict[str, int]) -> str | None:
    lowered = name.lower()
    for keyword, target in rules:
        if keyword in lowered:
            return target
    unmapped[name] = unmapped.get(name, 0) + 1
    return FALLBACK_BLOCK


# Cardinal facing -> World Forge rotation_steps. Matches
# ShapeGeometryFactory's convention: rotation.y = -steps * 90deg with the
# unrotated stair's high side (and the door panel's facing) toward +Z.
# If stairs come out consistently 90/180 degrees off in-game, adjust this
# one table - every shape reads from it.
FACING_TO_STEPS = {"south": 0, "west": 1, "north": 2, "east": 3}

_FACING_RE = re.compile(r"\b(north|south|east|west)\b")


def parse_shape(name: str) -> tuple[str, int]:
    """Shape + rotation for a GrabCraft block name; ("cube", 0) default.

    GrabCraft names carry orientation in parens: "Oak Wood Stairs (East,
    Upside-down)", "Stone Slab (Upper)", "Oak Door (Lower, Facing East,
    Closed)". "Double ... Slab" is a full block in Minecraft, so it stays
    a cube.
    """
    lowered = name.lower()
    facing_match = _FACING_RE.search(lowered)
    steps = FACING_TO_STEPS[facing_match.group(1)] if facing_match else 0

    if "stairs" in lowered:
        return ("stair_top" if "upside-down" in lowered else "stair", steps)
    if "slab" in lowered and "double" not in lowered:
        return ("slab_top" if "upper" in lowered or "top" in lowered else "slab", 0)
    if "trapdoor" in lowered:
        return ("slab_top" if "top half" in lowered else "slab", 0)
    if "door" in lowered or "foor" in lowered:
        return ("door", steps)
    if "fence" in lowered or "gate" in lowered:
        return ("fence", 0)
    if "torch" in lowered:
        return ("torch", steps)
    return ("cube", 0)


def slugify(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", title.lower()).strip("_")
    return slug or "unnamed_building"


def parse_render_object(js_text: str) -> dict:
    payload = js_text.strip()
    payload = re.sub(r"^var\s+myRenderObject\s*=\s*", "", payload)
    payload = payload.rstrip(";\n ")
    return json.loads(payload)


def convert(page_url: str, cache_dir: Path, delay: float,
            rules: list[tuple[str, str | None]], unmapped: dict[str, int]) -> dict | None:
    html = fetch(page_url, cache_dir, delay)

    match = re.search(r"(/js/RenderObject/myRenderObject_\d+\.js)", html)
    if not match:
        print(f"  !! no render object found on {page_url}", file=sys.stderr)
        return None
    render = parse_render_object(fetch(BASE + match.group(1), cache_dir, delay))

    title_match = re.search(r'<h1 id="content-title"[^>]*>([^<]+)</h1>', html)
    title = title_match.group(1).strip() if title_match else page_url.rstrip("/").split("/")[-2]
    category_slug = page_url.rstrip("/").split("/")[-1]

    # render is {y: {x: {z: entry}}} with 1-based string keys.
    raw_blocks: list[tuple[int, int, int, str]] = []
    for y_key, x_map in render.items():
        for x_key, z_map in x_map.items():
            for z_key, entry in z_map.items():
                raw_blocks.append((int(entry["x"]), int(entry["y"]), int(entry["z"]), entry["name"]))
    if not raw_blocks:
        print(f"  !! empty render object on {page_url}", file=sys.stderr)
        return None

    min_x = min(b[0] for b in raw_blocks)
    min_y = min(b[1] for b in raw_blocks)
    min_z = min(b[2] for b in raw_blocks)

    placed: dict[tuple[int, int, int], tuple[str, str, int]] = {}
    for x, y, z, name in raw_blocks:
        block_id = map_block(name, rules, unmapped)
        if block_id is None:
            continue
        shape_id, rotation_steps = parse_shape(name)
        placed[(x - min_x, y - min_y, z - min_z)] = (block_id, shape_id, rotation_steps)
    if not placed:
        print(f"  !! all blocks skipped on {page_url}", file=sys.stderr)
        return None

    max_y = max(pos[1] for pos in placed)
    size_x = max(pos[0] for pos in placed) + 1
    size_z = max(pos[2] for pos in placed) + 1

    blocks = []
    for (x, y, z), (block_id, shape_id, rotation_steps) in sorted(
            placed.items(), key=lambda kv: (kv[0][1], kv[0][0], kv[0][2])):
        if y == 0:
            layer = "foundation"
        elif block_id in ("oak_leaves", "roof_shingles") or y == max_y:
            layer = "roof"
        else:
            layer = "wall"
        entry = {
            "pos": [x, y, z],
            "block_id": block_id,
            "layer": layer,
            "tags": [layer],
            "build_stage": layer,
            "requires_support": y > 0,
        }
        # World Forge defaults absent fields to cube/0, so only non-cube
        # shapes carry the extra keys - keeps the JSONs a third smaller.
        if shape_id != "cube":
            entry["shape_id"] = shape_id
            entry["rotation_steps"] = rotation_steps
        blocks.append(entry)

    return {
        "id": slugify(title),
        "display_name": title,
        "category": category_slug,
        "era": "village",
        "footprint": [size_x, size_z],
        "health": min(2000, max(100, len(blocks) * 5)),
        "workers_required": 1,
        "required_functional_tags": ["foundation"],
        "blocks": blocks,
        "sockets": [],
        "storage_slots": [],
        "recipes": [],
        "source_url": page_url,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="GrabCraft -> World Forge blueprint converter")
    parser.add_argument("urls", nargs="+", help="Blueprint or category URLs on grabcraft.com")
    parser.add_argument("--out", default=str(Path(__file__).resolve().parent.parent / "data" / "buildings" / "imported"),
                        help="Output directory (default: rvox-ts/data/buildings/imported)")
    parser.add_argument("--limit", type=int, default=20, help="Max blueprints per category URL (default 20)")
    parser.add_argument("--delay", type=float, default=1.5, help="Seconds between uncached requests (default 1.5)")
    parser.add_argument("--map", dest="map_file", help="JSON file of {keyword: block_id|null} mapping overrides")
    args = parser.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    cache_dir = out_dir / ".cache"
    rules = load_rules(args.map_file)

    blueprint_urls: list[str] = []
    for url in args.urls:
        if is_blueprint_url(url):
            blueprint_urls.append(url.split("#")[0])
        else:
            print(f"Scanning category {url} ...")
            found = collect_category(url, cache_dir, args.delay, args.limit)
            print(f"  found {len(found)} blueprints")
            blueprint_urls.extend(found)
    blueprint_urls = list(dict.fromkeys(blueprint_urls))

    unmapped: dict[str, int] = {}
    written = 0
    for url in blueprint_urls:
        print(f"Converting {url}")
        try:
            blueprint = convert(url, cache_dir, args.delay, rules, unmapped)
        except (urllib.error.URLError, json.JSONDecodeError, KeyError, ValueError) as exc:
            print(f"  !! failed: {exc}", file=sys.stderr)
            continue
        if blueprint is None:
            continue
        out_path = out_dir / f"{blueprint['id']}.json"
        out_path.write_text(json.dumps(blueprint, indent=2) + "\n", encoding="utf-8")
        print(f"  -> {out_path} ({len(blueprint['blocks'])} blocks, {blueprint['footprint'][0]}x{blueprint['footprint'][1]})")
        written += 1

    print(f"\nDone: {written}/{len(blueprint_urls)} blueprints written to {out_dir}")
    if unmapped:
        print("Unrecognized block names (mapped to fallback 'stone'); add --map overrides if wrong:")
        for name, count in sorted(unmapped.items(), key=lambda kv: -kv[1]):
            print(f"  {count:5d}x {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
