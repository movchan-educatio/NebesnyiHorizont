#!/usr/bin/env python3
"""Assemble the four Blender impostor renders into a 2x2 RGBA atlas.

Run after `create_infantry_billboard.py` with the project's Python environment
that provides Pillow. Frame order is front, right, back, left (row-major).
"""

from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TILE_DIR = Path.home() / "AppData" / "Local" / "Temp" / "opencode" / "infantry_impostor"
OUTPUT = ROOT / "Assets" / "combat" / "soldier_impostor_atlas.png"
TILE_SIZE = (256, 512)
LAYOUT = (("front", 0, 0), ("right", 1, 0), ("back", 0, 1), ("left", 1, 1))


def assemble() -> None:
    atlas = Image.new("RGBA", (TILE_SIZE[0] * 2, TILE_SIZE[1] * 2), (0, 0, 0, 0))
    for name, column, row in LAYOUT:
        path = TILE_DIR / f"{name}.png"
        with Image.open(path) as source:
            tile = source.convert("RGBA")
        if tile.size != TILE_SIZE:
            raise ValueError(f"{path} must be {TILE_SIZE}, got {tile.size}")
        atlas.alpha_composite(tile, (column * TILE_SIZE[0], row * TILE_SIZE[1]))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(OUTPUT, optimize=True)
    print(f"[IMPOSTOR_ATLAS] {OUTPUT} size={atlas.size} bytes={OUTPUT.stat().st_size}")


if __name__ == "__main__":
    assemble()
