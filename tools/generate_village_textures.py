#!/usr/bin/env python3
"""Generate tileable village PBR textures (albedo/normal/roughness).

The first frontline textures were near-flat noise, which made every wall look
like painted cardboard.  These are deliberately simple but high-frequency:
plaster stains and cracks, brick courses with mortar, terracotta roof tiles and
weathered wood planks.  No external assets or licences are involved.

Run: python tools/generate_village_textures.py
"""

from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
OUT = Path(__file__).resolve().parent.parent / "Assets" / "frontline" / "village_textures"
OUT.mkdir(parents=True, exist_ok=True)


def _noise(size: int, octaves: int = 5) -> np.ndarray:
    rng = np.random.default_rng(20261104)
    out = np.zeros((size, size), dtype=np.float32)
    amplitude = 1.0
    total = 0.0
    for octave in range(octaves):
        cells = 4 * (2 ** octave)
        grid = rng.random((cells, cells)).astype(np.float32)
        # Tileable bilinear upscale.
        ys = (np.arange(size) * cells / size).astype(np.int32) % cells
        xs = (np.arange(size) * cells / size).astype(np.int32) % cells
        y0 = ys
        y1 = (ys + 1) % cells
        x0 = xs
        x1 = (xs + 1) % cells
        fy = (np.arange(size) * cells / size - np.floor(np.arange(size) * cells / size))[:, None]
        fx = (np.arange(size) * cells / size - np.floor(np.arange(size) * cells / size))[None, :]
        top = grid[y0][:, x0] * (1 - fx) + grid[y0][:, x1] * fx
        bottom = grid[y1][:, x0] * (1 - fx) + grid[y1][:, x1] * fx
        layer = top * (1 - fy) + bottom * fy
        out += layer * amplitude
        total += amplitude
        amplitude *= 0.52
    out /= total
    # Light blur removes the grid seams of the value-noise octaves.
    img = Image.fromarray(np.clip(out * 255, 0, 255).astype(np.uint8))
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    return np.asarray(img).astype(np.float32) / 255.0


def _normal_from_height(height: np.ndarray, strength: float = 2.0) -> Image.Image:
    # Sobel gradients, tileable at the edges.
    gx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    gy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx /= length
    ny /= length
    nz /= length
    rgb = np.stack(((nx * 0.5 + 0.5) * 255, (ny * 0.5 + 0.5) * 255,
                    (nz * 0.5 + 0.5) * 255), axis=-1)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))


def _roughness(base: float, variation: np.ndarray, contrast: float = 26.0) -> Image.Image:
    values = np.clip(base + (variation - 0.5) * contrast, 20, 245)
    return Image.fromarray(values.astype(np.uint8))


def _save(name: str, albedo: Image.Image, height: np.ndarray, rough: Image.Image,
          normal_strength: float = 2.0) -> None:
    albedo.save(OUT / f"{name}_albedo.png")
    _normal_from_height(height, normal_strength).save(OUT / f"{name}_normal.png")
    rough.save(OUT / f"{name}_rough.png")
    print("[textures]", name, "->", OUT)


def make_plaster() -> None:
    n1 = _noise(SIZE, 5)
    n2 = _noise(SIZE, 7)
    fine = _noise(SIZE, 9)
    base = np.array([0.78, 0.70, 0.57], dtype=np.float32)
    stain = np.clip((n1 - 0.48) * 2.2, 0, 1)
    color = base[None, None, :] * (0.82 + 0.30 * n2)[:, :, None]
    color *= (1.0 - 0.22 * stain)[:, :, None]
    color += (fine[:, :, None] - 0.5) * 0.05

    # Hairline cracks.
    img = Image.fromarray(np.clip(color * 255, 0, 255).astype(np.uint8))
    draw = ImageDraw.Draw(img)
    rng = random.Random(4411)
    for _ in range(24):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        points = [(x, y)]
        for _step in range(rng.randrange(8, 22)):
            x = (x + rng.randrange(-18, 19)) % SIZE
            y = (y + rng.randrange(10, 28)) % SIZE
            points.append((x, y))
        draw.line(points, fill=(92, 82, 66), width=rng.choice((1, 1, 2)))
    img = img.filter(ImageFilter.GaussianBlur(0.35))
    height = n2 * 0.55 + fine * 0.25 + 0.20
    _save("plaster", img, height, _roughness(205, n2, 22.0), 1.2)


def make_brick() -> None:
    brick_w, brick_h, mortar = 256, 128, 14
    color = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    color[:, :] = (0.42, 0.34, 0.27)
    height = np.zeros((SIZE, SIZE), dtype=np.float32)
    rng = random.Random(9911)
    fine = _noise(SIZE, 7)
    for row in range(SIZE // brick_h):
        offset = (brick_w // 2) if row % 2 else 0
        for col in range(-1, SIZE // brick_w + 1):
            x0 = col * brick_w + offset + mortar // 2
            y0 = row * brick_h + mortar // 2
            x1 = x0 + brick_w - mortar
            y1 = y0 + brick_h - mortar
            shade = rng.uniform(0.82, 1.16)
            warm = rng.uniform(-0.04, 0.04)
            for yy in range(max(0, y0), min(SIZE, y1)):
                for xx in range(max(0, x0), min(SIZE, x1)):
                    color[yy, xx] = (0.48 * shade + warm, 0.30 * shade,
                                     0.21 * shade)
                    height[yy, xx] = 0.78 + fine[yy, xx] * 0.10
    # Mortar tint and brick noise.
    mortar_mask = height < 0.2
    color[mortar_mask] = (0.58, 0.55, 0.48)
    color *= (0.88 + 0.24 * fine)[:, :, None]
    img = Image.fromarray(np.clip(color * 255, 0, 255).astype(np.uint8))
    img = img.filter(ImageFilter.GaussianBlur(0.25))
    _save("brick", img, np.clip(height + fine * 0.06, 0, 1),
          _roughness(226, fine, 18.0), 2.2)


def make_roof() -> None:
    tile_w, tile_h = 128, 112
    color = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    color[:, :] = (0.20, 0.08, 0.05)
    height = np.zeros((SIZE, SIZE), dtype=np.float32)
    rng = random.Random(772)
    fine = _noise(SIZE, 8)
    for row in range(SIZE // tile_h + 1):
        offset = (tile_w // 2) if row % 2 else 0
        for col in range(-1, SIZE // tile_w + 1):
            x0 = col * tile_w + offset
            y0 = row * tile_h
            shade = rng.uniform(0.75, 1.15)
            for yy in range(max(0, y0), min(SIZE, y0 + tile_h - 4)):
                t = (yy - y0) / tile_h
                for xx in range(max(0, x0), min(SIZE, x0 + tile_w - 4)):
                    u = (xx - x0) / tile_w
                    # Slightly curved tile profile.
                    curve = 0.90 + 0.10 * math.sin(u * math.pi)
                    color[yy, xx] = (0.52 * shade * curve, 0.20 * shade * curve,
                                     0.10 * shade * curve)
                    height[yy, xx] = max(height[yy, xx],
                                         0.55 + 0.42 * math.sin(u * math.pi) - 0.2 * t)
    # Dark gutter lines between courses.
    for row in range(SIZE // tile_h + 1):
        y = row * tile_h
        for yy in range(max(0, y - 4), min(SIZE, y + 5)):
            height[yy, :] = 0.12
            color[yy, :] *= 0.55
    color *= (0.84 + 0.28 * fine)[:, :, None]
    img = Image.fromarray(np.clip(color * 255, 0, 255).astype(np.uint8))
    img = img.filter(ImageFilter.GaussianBlur(0.4))
    _save("roof", img, np.clip(height + fine * 0.05, 0, 1),
          _roughness(214, fine, 26.0), 2.8)


def make_wood() -> None:
    planks = 8
    plank_w = SIZE // planks
    color = np.zeros((SIZE, SIZE, 3), dtype=np.float32)
    height = np.zeros((SIZE, SIZE), dtype=np.float32)
    rng = random.Random(551)
    grain = _noise(SIZE, 9)
    for p in range(planks):
        shade = rng.uniform(0.72, 1.15)
        x0 = p * plank_w
        for yy in range(SIZE):
            for xx in range(max(0, x0), min(SIZE, x0 + plank_w - 4)):
                g = grain[yy, xx]
                color[yy, xx] = (0.42 * shade * (0.82 + 0.30 * g),
                                 0.29 * shade * (0.82 + 0.30 * g),
                                 0.17 * shade * (0.82 + 0.30 * g))
                height[yy, xx] = 0.55 + 0.30 * g
        # Gap between planks.
        for xx in range(max(0, x0 + plank_w - 4), min(SIZE, x0 + plank_w)):
            color[:, xx] *= 0.32
            height[:, xx] = 0.08
    img = Image.fromarray(np.clip(color * 255, 0, 255).astype(np.uint8))
    img = img.filter(ImageFilter.GaussianBlur(0.3))
    _save("wood", img, np.clip(height + grain * 0.06, 0, 1),
          _roughness(222, grain, 24.0), 1.8)


def main() -> None:
    make_plaster()
    make_brick()
    make_roof()
    make_wood()


if __name__ == "__main__":
    main()
