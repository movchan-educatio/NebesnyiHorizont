"""Build modular high-detail 3D military diorama props and brass shell casings in Blender 5.2.

Generates 8 cohesive, beveled, UV-mapped GLB assets with baked procedural PBR
textures (Albedo, Roughness/Metallic, Normal, and optional Emission) under:
  Assets/Drones/hangar_diorama/

Assets generated:
  1. ammo_crate_wood.glb     - Slatted olive ordnance crate with steel brackets, clasps & rope handles
  2. ammo_can_m2a1.glb       - Embossed stamped steel M2A1 ammo can with hinged lid, latch & bail handle
  3. pelican_fpv_case.glb    - Ribbed waterproof tactical FPV hard case with latches, valve & ID plate
  4. sandbag_cluster.glb     - Organic berm of 5 overlapping woven burlap sandbags with tied ears
  5. tactical_radio.glb      - Ruggedized AN/PRC relay radio with knobs, backlit LCD & curved whip antenna
  6. ordnance_tube.glb       - Ribbed fiberglass HE/RPG canister with EPDM endcaps & hazard bands
  7. workbench_deck.glb      - Armored steel bunker workbench slab with recessed tactical anti-slip mat (top Z=0)
  8. brass_shell_casing.glb  - Bottlenecked rifle casing (7.62x51 hero scale, hollow mouth & struck primer)

Run from workspace root:
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" --background --python tools/blender_build_hangar_diorama.py
"""

import json
import math
import os
import shutil
import struct
import tempfile
import zlib

import bpy
import bmesh
import mathutils
import numpy as np


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT_DIR = os.path.join(ROOT, "Assets", "Drones", "hangar_diorama")

_TMP_DIR = None
_TMP_PNGS = []


# ---------------------------------------------------------------------------
# Pure-Python PNG encoder & Blender 5.2 safe pack (avoids zero-black PNG bug)
# ---------------------------------------------------------------------------
def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def _write_png_rgba(path: str, rgba: np.ndarray) -> None:
    h, w, c = rgba.shape
    assert c == 4
    arr = np.ascontiguousarray(rgba, dtype=np.uint8)
    raw = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", ihdr)
        + _png_chunk(b"IDAT", zlib.compress(raw, 6))
        + _png_chunk(b"IEND", b"")
    )
    with open(path, "wb") as f:
        f.write(png)


def make_packed_image(name: str, rgba: np.ndarray, colorspace: str = "sRGB"):
    """Write deterministic temp PNG and load+pack into Blender (Blender 5.2 safe)."""
    global _TMP_DIR
    if _TMP_DIR is None:
        _TMP_DIR = tempfile.mkdtemp(prefix="blender_diorama_")
    tmp_path = os.path.join(_TMP_DIR, f"{name}.png")
    _write_png_rgba(tmp_path, rgba)
    _TMP_PNGS.append(tmp_path)
    img = bpy.data.images.load(tmp_path, check_existing=False)
    img.name = name
    img.colorspace_settings.name = colorspace
    img.pack()
    return img


def cleanup_temp_pngs():
    global _TMP_DIR
    while _TMP_PNGS:
        p = _TMP_PNGS.pop()
        try:
            if os.path.exists(p):
                os.remove(p)
        except OSError:
            pass
    if _TMP_DIR is not None:
        shutil.rmtree(_TMP_DIR, ignore_errors=True)
        _TMP_DIR = None


# ---------------------------------------------------------------------------
# Bitmap stencil font (ASCII + Ukrainian tactical glyphs) & normal map helpers
# ---------------------------------------------------------------------------
_FONT_5X7 = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11100", "10010", "10001", "10001", "10001", "10010", "11100"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["01110", "10000", "11110", "10001", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
    "Б": ["11111", "10000", "10000", "11110", "10001", "10001", "11110"],
    "Ч": ["10001", "10001", "10001", "01111", "00001", "00001", "00001"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
}


def draw_text(img: np.ndarray, x0: int, y0: int, text: str, scale: int, color: tuple, alpha_blend: float = 0.92):
    h, w, _ = img.shape
    cx = x0
    for ch in text.upper():
        gly = _FONT_5X7.get(ch, _FONT_5X7[" "])
        for ry, row in enumerate(gly):
            for rx, bit in enumerate(row):
                if bit == "1":
                    px0 = max(0, cx + rx * scale)
                    py0 = max(0, y0 + ry * scale)
                    px1 = min(w, cx + (rx + 1) * scale)
                    py1 = min(h, y0 + (ry + 1) * scale)
                    if px1 > px0 and py1 > py0:
                        for c in range(3):
                            orig = img[py0:py1, px0:px1, c].astype(np.float32)
                            img[py0:py1, px0:px1, c] = np.clip(
                                orig * (1.0 - alpha_blend) + color[c] * alpha_blend, 0, 255
                            ).astype(np.uint8)
        cx += 6 * scale


def height_to_normal(height: np.ndarray, strength: float = 2.0) -> np.ndarray:
    gx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    gy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -gx * strength
    ny = -gy * strength
    nz = np.ones_like(height)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    nx *= inv_len
    ny *= inv_len
    nz *= inv_len
    out = np.empty((height.shape[0], height.shape[1], 4), dtype=np.uint8)
    out[:, :, 0] = np.clip((nx * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    out[:, :, 1] = np.clip((ny * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    out[:, :, 2] = np.clip((nz * 0.5 + 0.5) * 255.0, 0, 255).astype(np.uint8)
    out[:, :, 3] = 255
    return out


def pack_orm(ao: np.ndarray, rgh: np.ndarray, met: np.ndarray) -> np.ndarray:
    """Pack R=AO, G=Roughness, B=Metallic into an RGBA texture for SeparateColor."""
    out = np.empty((rgh.shape[0], rgh.shape[1], 4), dtype=np.uint8)
    out[:, :, 0] = np.clip(ao * 255.0, 0, 255).astype(np.uint8)
    out[:, :, 1] = np.clip(rgh * 255.0, 0, 255).astype(np.uint8)
    out[:, :, 2] = np.clip(met * 255.0, 0, 255).astype(np.uint8)
    out[:, :, 3] = 255
    return out


# ---------------------------------------------------------------------------
# Procedural PBR Texture Sets (512x512 for props, 256x256 for shell casings)
# ---------------------------------------------------------------------------
def gen_wood_crate_pbr(size: int = 512):
    """Olive-drab painted military crate timber with grain, plank wear & stencil."""
    rng = np.random.default_rng(101)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size

    # Wood grain fibers along U axis + knots
    wave = (
        np.sin(yy * 56.0 + np.sin(xx * 9.0) * 1.6) * 0.45
        + np.sin(yy * 145.0 + np.cos(xx * 21.0) * 0.8) * 0.25
        + rng.normal(0.0, 0.10, (size, size)).astype(np.float32)
    )
    streak = np.repeat(rng.normal(0.0, 0.03, (size, 1)), size, axis=1).astype(np.float32)
    grain = np.clip(0.5 + 0.26 * wave + streak, 0.0, 1.0)

    # Worn horizontal bands where paint chipped away revealing pine timber
    band_wear = (
        np.exp(-((yy - 0.14) / 0.015) ** 2)
        + np.exp(-((yy - 0.88) / 0.014) ** 2)
        + np.clip(rng.normal(-0.55, 0.42, (size, size)), 0.0, 1.0) * 0.45
    )
    wear = np.clip(band_wear * (0.45 + 0.55 * grain), 0.0, 1.0)

    # Rich earthy olive military crate paint vs raw pine under scratches
    paint = np.array([35.0, 43.0, 24.0], dtype=np.float32)
    pine = np.array([106.0, 82.0, 48.0], dtype=np.float32)

    alb = np.empty((size, size, 4), dtype=np.uint8)
    for c in range(3):
        col = paint[c] * (0.76 + 0.36 * grain)
        col = col * (1.0 - wear * 0.65) + (pine[c] * (0.76 + 0.32 * grain)) * (wear * 0.65)
        alb[:, :, c] = np.clip(col, 10, 210).astype(np.uint8)
    alb[:, :, 3] = 255

    # Crisp centered tactical stencil (never clipped near brackets)
    draw_text(alb, 118, int(size * 0.37), "UA  БЧ-82", 4, (212, 184, 92), 0.90)
    draw_text(alb, 112, int(size * 0.50), "FPV-5 ORDNANCE", 3, (198, 178, 102), 0.88)

    rgh = np.clip(0.80 - 0.10 * grain + 0.08 * wear, 0.58, 0.95)
    met = np.zeros_like(rgh)
    nrm = height_to_normal(grain, strength=2.6)
    orm = pack_orm(np.clip(0.88 + 0.12 * grain, 0.0, 1.0), rgh, met)
    return alb, orm, nrm


def gen_steel_ammo_can_pbr(size: int = 512):
    """Stamped M2A1 olive steel ammo can with hammer-tone enamel & NATO stencil."""
    rng = np.random.default_rng(202)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size

    hammer = (
        np.sin(xx * 95.0) * np.cos(yy * 95.0) * 0.04
        + rng.normal(0.0, 0.025, (size, size)).astype(np.float32)
    )
    edge_dist = np.minimum(np.minimum(xx, 1.0 - xx), np.minimum(yy, 1.0 - yy))
    chip_noise = rng.uniform(0.0, 1.0, (size, size)).astype(np.float32)
    chip_mask = np.where((edge_dist < 0.042) & (chip_noise > 0.60), 1.0, 0.0)
    scratches = np.where(
        (np.abs(np.sin(xx * 14.0 + yy * 9.0)) > 0.996) & (chip_noise > 0.45), 0.70, 0.0
    )
    bare_steel = np.clip(np.maximum(chip_mask, scratches), 0.0, 1.0)

    enamel = np.array([34.0, 42.0, 23.0], dtype=np.float32)
    steel = np.array([112.0, 118.0, 122.0], dtype=np.float32)
    alb = np.empty((size, size, 4), dtype=np.uint8)
    for c in range(3):
        col = enamel[c] * (1.0 + hammer * 2.2)
        col = col * (1.0 - bare_steel) + steel[c] * bare_steel
        alb[:, :, c] = np.clip(col, 10, 210).astype(np.uint8)
    alb[:, :, 3] = 255

    # Centered side NATO yellow stencil (mapped strictly to side wall UVs)
    draw_text(alb, 118, int(size * 0.40), "200 RDS", 4, (218, 174, 44), 0.94)
    draw_text(alb, 106, int(size * 0.52), "7.62 NATO", 4, (218, 174, 44), 0.94)

    rgh = np.clip(0.54 - 0.20 * bare_steel + hammer * 0.9, 0.22, 0.76)
    met = np.clip(0.16 + 0.68 * bare_steel, 0.0, 0.90)
    nrm = height_to_normal(np.clip(0.5 + hammer * 3.0 - bare_steel * 0.25, 0.0, 1.0), strength=2.2)
    orm = pack_orm(np.ones_like(rgh), rgh, met)
    return alb, orm, nrm


def gen_pelican_polymer_pbr(size: int = 512):
    """Pebbled dark charcoal-olive tactical hard case polymer with amber ID plate."""
    rng = np.random.default_rng(303)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size

    pebble = (
        rng.normal(0.0, 0.08, (size, size)).astype(np.float32)
        + 0.05 * np.sin(xx * 220.0) * np.sin(yy * 220.0)
    )
    scuff = np.where((np.abs(yy - 0.5 + 0.12 * np.sin(xx * 7.0)) < 0.012) & (xx > 0.15) & (xx < 0.85), 0.25, 0.0)
    base = np.array([23.0, 26.0, 23.0], dtype=np.float32)
    alb = np.empty((size, size, 4), dtype=np.uint8)
    for c in range(3):
        col = base[c] * (1.0 + pebble * 1.3 + scuff * 0.5)
        alb[:, :, c] = np.clip(col, 10, 190).astype(np.uint8)
    alb[:, :, 3] = 255

    # Center tactical ID label strip (mapped strictly to top center placard face)
    lbl = (xx > 0.16) & (xx < 0.84) & (yy > 0.36) & (yy < 0.62)
    border = lbl & ((xx < 0.18) | (xx > 0.82) | (yy < 0.38) | (yy > 0.60))
    for c, col_v in enumerate((18, 20, 20)):
        alb[:, :, c] = np.where(lbl, col_v, alb[:, :, c])
    for c, col_v in enumerate((204, 150, 38)):
        alb[:, :, c] = np.where(border, col_v, alb[:, :, c])

    draw_text(alb, 112, int(size * 0.41), "FPV FIELD KIT", 4, (222, 170, 48), 0.95)
    draw_text(alb, 128, int(size * 0.51), "ELRS-915 // UA", 3, (176, 188, 180), 0.90)

    rgh = np.clip(0.62 + pebble * 0.42 - np.where(lbl, 0.15, 0.0), 0.30, 0.84)
    met = np.where(lbl, 0.12, 0.02).astype(np.float32)
    nrm = height_to_normal(np.clip(0.5 + pebble * 2.2, 0.0, 1.0), strength=2.4)
    orm = pack_orm(np.ones_like(rgh), rgh, met)
    return alb, orm, nrm


def gen_burlap_sandbag_pbr(size: int = 512):
    """Coarse woven earthy khaki-olive jute burlap fabric with dirt shading."""
    rng = np.random.default_rng(404)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size

    rep = 54.0
    wu = np.sin(xx * rep * 2.0 * math.pi)
    wv = np.sin(yy * rep * 2.0 * math.pi)
    ix = np.floor(xx * rep).astype(np.int32)
    iy = np.floor(yy * rep).astype(np.int32)
    warp = ((ix + iy) % 2) == 0

    thread = np.where(warp, 0.5 + 0.5 * wu * (0.75 + 0.25 * wv), 0.5 + 0.5 * wv * (0.75 + 0.25 * wu))
    fiber_jit = rng.normal(0.0, 0.06, (size, size)).astype(np.float32)
    stain = (
        0.14 * np.sin(xx * 9.0 + 0.7) * np.cos(yy * 7.0)
        + 0.09 * np.sin(xx * 21.0 - yy * 15.0)
    )

    hfield = np.clip(0.30 + 0.60 * thread + fiber_jit * 0.8, 0.0, 1.0)
    base = np.array([76.0, 66.0, 44.0], dtype=np.float32)
    alb = np.empty((size, size, 4), dtype=np.uint8)
    for c in range(3):
        col = base[c] * (0.70 + 0.34 * thread + stain + fiber_jit * 0.5)
        alb[:, :, c] = np.clip(col, 14, 185).astype(np.uint8)
    alb[:, :, 3] = 255

    # Faint stitched seam line
    seam = np.exp(-((yy - 0.12) / 0.008) ** 2)
    for c in range(3):
        alb[:, :, c] = np.clip(alb[:, :, c] * (1.0 - 0.38 * seam), 10, 185).astype(np.uint8)

    rgh = np.clip(0.91 + 0.07 * (1.0 - thread), 0.80, 0.98)
    met = np.zeros_like(rgh)
    nrm = height_to_normal(hfield, strength=3.4)
    orm = pack_orm(np.clip(0.78 + 0.22 * thread, 0.0, 1.0), rgh, met)
    return alb, orm, nrm


def gen_ordnance_tube_pbr(size: int = 512):
    """Deep olive fiberglass ordnance tube with amber HE hazard bands and stencil."""
    rng = np.random.default_rng(505)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size

    noise = rng.normal(0.0, 0.025, (size, size)).astype(np.float32)
    rib_ring = np.sin(xx * 42.0 * math.pi) * 0.02
    base = np.array([38.0, 48.0, 26.0], dtype=np.float32)
    alb = np.empty((size, size, 4), dtype=np.uint8)
    for c in range(3):
        alb[:, :, c] = np.clip(base[c] * (1.0 + noise + rib_ring), 10, 195).astype(np.uint8)
    alb[:, :, 3] = 255

    # Twin vivid NATO hazard stripes along tube circumference (X is axis)
    stripe = ((xx > 0.20) & (xx < 0.25)) | ((xx > 0.74) & (xx < 0.79))
    for c, col_v in enumerate((192, 142, 24)):
        alb[:, :, c] = np.where(stripe, col_v, alb[:, :, c])

    draw_text(alb, 164, int(size * 0.44), "HE-82 // БЧ", 4, (206, 174, 52), 0.93)

    rgh = np.clip(0.52 + np.abs(noise) * 1.4, 0.36, 0.74)
    met = np.zeros_like(rgh)
    nrm = height_to_normal(np.clip(0.5 + noise * 2.0 + rib_ring * 3.0, 0.0, 1.0), strength=2.0)
    orm = pack_orm(np.ones_like(rgh), rgh, met)
    return alb, orm, nrm


def gen_workbench_deck_pbr(size: int = 512):
    """Dark brushed gunmetal border & matte charcoal tactical workbench mat."""
    rng = np.random.default_rng(606)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size

    brush = np.repeat(rng.normal(0.0, 0.025, (size, 1)), size, axis=1).astype(np.float32)
    grain = rng.normal(0.0, 0.022, (size, size)).astype(np.float32)

    grid_x = np.abs(((xx * 10.0) % 1.0) - 0.5)
    grid_y = np.abs(((yy * 10.0) % 1.0) - 0.5)
    grid = (grid_x > 0.485) | (grid_y > 0.485)
    diamond = np.abs(np.sin((xx + yy) * 72.0 * math.pi)) * np.abs(np.cos((xx - yy) * 72.0 * math.pi))

    alb = np.empty((size, size, 4), dtype=np.uint8)
    base = np.array([20.0, 24.0, 23.0], dtype=np.float32)
    for c in range(3):
        col = base[c] * (1.0 + brush * 1.5 + grain * 1.3 + diamond * 0.14)
        col = np.where(grid, col + 9.0, col)
        alb[:, :, c] = np.clip(col, 8, 120).astype(np.uint8)
    alb[:, :, 3] = 255

    # Subtle amber calibration tick edge accents
    tick = (yy > 0.90) & (yy < 0.94) & (((xx * 18.0).astype(np.int32) % 2) == 0)
    for c, col_v in enumerate((138, 100, 28)):
        alb[:, :, c] = np.where(tick, col_v, alb[:, :, c])

    rgh = np.clip(0.60 - diamond * 0.12 + np.abs(grain) * 1.2, 0.38, 0.80)
    met = np.clip(0.28 + diamond * 0.14, 0.12, 0.55)
    nrm = height_to_normal(np.clip(0.45 + diamond * 0.42 + grain * 1.6, 0.0, 1.0), strength=2.4)
    orm = pack_orm(np.ones_like(rgh), rgh, met)
    return alb, orm, nrm


def gen_radio_faceplate_pbr(size: int = 256):
    """Tactical transceiver panel with backlit OLED readout & speaker grille."""
    rng = np.random.default_rng(707)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    grain = rng.normal(0.0, 0.02, (size, size)).astype(np.float32)

    alb = np.empty((size, size, 4), dtype=np.uint8)
    base = np.array([38.0, 45.0, 36.0], dtype=np.float32)
    for c in range(3):
        alb[:, :, c] = np.clip(base[c] * (1.0 + grain * 2.0), 10, 220).astype(np.uint8)
    alb[:, :, 3] = 255

    # OLED telemetry LCD window in upper half
    lcd = (xx > 0.14) & (xx < 0.86) & (yy > 0.14) & (yy < 0.44)
    for c, col_v in enumerate((12, 34, 24)):
        alb[:, :, c] = np.where(lcd, col_v, alb[:, :, c])
    draw_text(alb, 46, int(size * 0.19), "ELRS 915", 3, (110, 248, 172), 0.95)
    draw_text(alb, 46, int(size * 0.30), "LINK OK", 3, (140, 255, 190), 0.95)

    # Emissive map for screen readout
    emi = np.zeros((size, size, 4), dtype=np.uint8)
    emi[:, :, 3] = 255
    mask_lit = lcd & ((alb[:, :, 1] > 120))
    emi[:, :, 0] = np.where(mask_lit, 90, 0).astype(np.uint8)
    emi[:, :, 1] = np.where(mask_lit, 245, 0).astype(np.uint8)
    emi[:, :, 2] = np.where(mask_lit, 155, 0).astype(np.uint8)

    # Speaker vent grille slots in lower half
    slot = (xx > 0.22) & (xx < 0.78) & (yy > 0.56) & (yy < 0.84) & (((yy * 40.0) % 1.0) > 0.55)
    for c in range(3):
        alb[:, :, c] = np.where(slot, 16, alb[:, :, c])

    rgh = np.clip(0.46 + np.where(lcd, -0.26, 0.0) + np.abs(grain), 0.16, 0.72)
    met = np.where(lcd, 0.08, 0.52).astype(np.float32)
    nrm = height_to_normal(np.clip(0.5 - np.where(slot, 0.35, 0.0) + grain * 2.0, 0.0, 1.0), strength=2.6)
    orm = pack_orm(np.ones_like(rgh), rgh, met)
    return alb, orm, nrm, emi


def gen_brass_casing_pbr(size: int = 256):
    """UV layout: V in [0..1] runs bottom-to-top along cartridge from base primer -> mouth cavity.
    V bands:
      0.00..0.10 : center primer cup & pocket (copper-nickel silver primer)
      0.10..0.18 : rim & head face
      0.18..0.28 : extractor groove (darkened oil crevice)
      0.28..0.72 : spun gleaming brass case wall
      0.72..0.84 : heat-annealed bronze-violet shoulder
      0.84..0.93 : brass neck + carbon soot mouth rim
      0.93..1.00 : deep dark carbon hollow interior cavity
    """
    rng = np.random.default_rng(808)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    v = 1.0 - yy  # Blender UV bottom=0 -> top=1 (numpy row 0 is top of image)

    lathe_ring = np.repeat(rng.normal(0.0, 0.025, (size, 1)), size, axis=1).astype(np.float32)
    fine_groove = np.sin(v * 210.0 * math.pi) * 0.015
    micro = rng.normal(0.0, 0.012, (size, size)).astype(np.float32)

    brass = np.array([228.0, 184.0, 78.0], dtype=np.float32)
    anneal = np.array([154.0, 108.0, 62.0], dtype=np.float32)
    primer = np.array([204.0, 178.0, 142.0], dtype=np.float32)
    soot = np.array([34.0, 31.0, 28.0], dtype=np.float32)

    alb_f = np.empty((size, size, 3), dtype=np.float32)
    for c in range(3):
        alb_f[:, :, c] = brass[c] * (1.0 + lathe_ring + micro)

    # Blend heat annealing around shoulder
    anneal_w = np.exp(-((v - 0.77) / 0.055) ** 2)
    for c in range(3):
        alb_f[:, :, c] = alb_f[:, :, c] * (1.0 - anneal_w * 0.78) + anneal[c] * (anneal_w * 0.78)

    # Primer region
    p_mask = v < 0.095
    for c in range(3):
        alb_f[:, :, c] = np.where(p_mask, primer[c] * (1.0 + micro), alb_f[:, :, c])

    # Firing-pin strike dimple darkening right at V < 0.032
    dimple = v < 0.032
    for c in range(3):
        alb_f[:, :, c] = np.where(dimple, alb_f[:, :, c] * 0.48, alb_f[:, :, c])

    # Extractor groove shadow
    ex_w = np.exp(-((v - 0.22) / 0.028) ** 2)
    for c in range(3):
        alb_f[:, :, c] = alb_f[:, :, c] * (1.0 - ex_w * 0.45)

    # Powder soot at neck mouth & dark hollow bore
    soot_w = np.clip((v - 0.87) / 0.065, 0.0, 1.0)
    bore_mask = v > 0.925
    for c in range(3):
        alb_f[:, :, c] = alb_f[:, :, c] * (1.0 - soot_w * 0.84) + soot[c] * (soot_w * 0.84)
        alb_f[:, :, c] = np.where(bore_mask, 16.0 + micro * 10.0, alb_f[:, :, c])

    alb = np.empty((size, size, 4), dtype=np.uint8)
    alb[:, :, :3] = np.clip(alb_f, 8, 250).astype(np.uint8)
    alb[:, :, 3] = 255

    rgh = np.clip(0.20 + lathe_ring * 0.7 + anneal_w * 0.14 + soot_w * 0.56, 0.14, 0.90)
    rgh = np.where(bore_mask, 0.90, rgh)
    met = np.clip(0.93 - anneal_w * 0.08 - soot_w * 0.72, 0.15, 0.95)
    met = np.where(bore_mask, 0.12, met)

    hfield = np.clip(0.55 + lathe_ring * 2.0 + fine_groove - ex_w * 0.25 - np.where(v < 0.095, 0.15, 0.0), 0.0, 1.0)
    nrm = height_to_normal(hfield, strength=1.8)
    orm = pack_orm(np.ones_like(rgh), rgh, met)
    return alb, orm, nrm


# ---------------------------------------------------------------------------
# Material Builder (ShaderNodeSeparateColor G=Roughness, B=Metallic -> Principled)
# ---------------------------------------------------------------------------
def build_pbr_material(
    name: str,
    base_color=(0.5, 0.5, 0.5, 1.0),
    metallic=0.0,
    roughness=0.5,
    alb_img=None,
    orm_img=None,
    nrm_img=None,
    emi_img=None,
    nrm_strength=0.85,
    emission_strength=1.4,
):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    bsdf.inputs["Base Color"].default_value = base_color
    bsdf.inputs["Metallic"].default_value = float(metallic)
    bsdf.inputs["Roughness"].default_value = float(roughness)

    if alb_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = alb_img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])

    if orm_img is not None:
        otex = nt.nodes.new("ShaderNodeTexImage")
        otex.image = orm_img
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.mode = "RGB"
        nt.links.new(otex.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])

    if nrm_img is not None:
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = nrm_img
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = float(nrm_strength)
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    if emi_img is not None:
        etex = nt.nodes.new("ShaderNodeTexImage")
        etex.image = emi_img
        if "Emission Color" in bsdf.inputs:
            nt.links.new(etex.outputs["Color"], bsdf.inputs["Emission Color"])
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = float(emission_strength)

    return mat


# ---------------------------------------------------------------------------
# Scene & Mesh Construction Helpers
# ---------------------------------------------------------------------------
def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def set_smooth_with_sharp_edges(obj, angle_deg: float = 38.0):
    mesh = obj.data
    for p in mesh.polygons:
        p.use_smooth = True
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.edges.ensure_lookup_table()
    thresh = math.radians(angle_deg)
    for e in bm.edges:
        if len(e.link_faces) == 2:
            ang = e.link_faces[0].normal.angle(e.link_faces[1].normal, 0.0)
            e.smooth = ang <= thresh
        else:
            e.smooth = False
    bm.to_mesh(mesh)
    bm.free()


def apply_box_uv(bm: bmesh.types.BMesh, scale: float = 2.0):
    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                u, v = co.x * scale + 0.5, co.y * scale + 0.5
            elif ax >= ay and ax >= az:
                u, v = co.y * scale + 0.5, co.z * scale + 0.5
            else:
                u, v = co.x * scale + 0.5, co.z * scale + 0.5
            loop[uv_layer].uv = (u, v)


def apply_planar_stencil_uv(bm: bmesh.types.BMesh, cx: float, cz: float, w: float, h: float):
    """Map front/top faces cleanly onto [0.05..0.95] so stencil lands centered."""
    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        n = f.normal
        for loop in f.loops:
            co = loop.vert.co
            if abs(n.y) > 0.65:
                u = (co.x - cx) / max(w, 1e-4) + 0.5
                v = (co.z - cz) / max(h, 1e-4) + 0.5
            elif abs(n.z) > 0.65:
                u = (co.x - cx) / max(w, 1e-4) + 0.5
                v = (co.y) / max(h, 1e-4) + 0.5
            else:
                u = co.y * 2.0 + 0.5
                v = (co.z - cz) / max(h, 1e-4) + 0.5
            loop[uv_layer].uv = (u, v)


def apply_front_only_stencil_uv(bm: bmesh.types.BMesh, cx: float, cz: float, w: float, h: float):
    """Map stencil strictly to front/back walls; other faces sample clean painted band V in [0.04..0.28]."""
    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        n = f.normal
        if abs(n.y) > 0.72:
            sign = -1.0 if n.y > 0.0 else 1.0
            for loop in f.loops:
                co = loop.vert.co
                u = sign * (co.x - cx) / max(w, 1e-4) + 0.5
                v = (co.z - cz) / max(h, 1e-4) + 0.5
                loop[uv_layer].uv = (max(0.02, min(0.98, u)), max(0.02, min(0.98, v)))
        else:
            for loop in f.loops:
                co = loop.vert.co
                u = (co.x * 1.4 + co.y * 0.9) % 0.8 + 0.1
                v = ((co.y + co.z) * 0.6) % 0.20 + 0.05
                loop[uv_layer].uv = (u, v)


def apply_pelican_placard_uv(bm: bmesh.types.BMesh, half_w: float, half_d: float, lid_z: float):
    """Map yellow ID label ONLY to center top placard pad; rest is clean pebbled polymer."""
    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        n = f.normal
        ctr = f.calc_center_median()
        if n.z > 0.85 and ctr.z >= lid_z - 0.005 and abs(ctr.x) < half_w and abs(ctr.y) < half_d:
            for loop in f.loops:
                co = loop.vert.co
                u = (co.x / max(half_w * 2.0, 1e-4)) * 0.68 + 0.5
                v = (co.y / max(half_d * 2.0, 1e-4)) * 0.28 + 0.50
                loop[uv_layer].uv = (max(0.16, min(0.84, u)), max(0.36, min(0.62, v)))
        else:
            for loop in f.loops:
                co = loop.vert.co
                u = (co.x * 1.8 + co.y * 0.9) % 0.8 + 0.1
                v = ((co.y + co.z) * 0.7) % 0.22 + 0.04
                loop[uv_layer].uv = (u, v)


def bm_to_object(name: str, bm: bmesh.types.BMesh, mat, uv_fn=None, smooth_deg: float = 35.0):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    if uv_fn is not None:
        uv_fn(bm)
    else:
        apply_box_uv(bm, scale=2.2)
    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if mat is not None:
        obj.data.materials.append(mat)
    set_smooth_with_sharp_edges(obj, smooth_deg)
    return obj


def bm_add_beveled_box(
    bm: bmesh.types.BMesh,
    center: tuple,
    size: tuple,
    bevel: float = 0.003,
    segments: int = 1,
    rot_euler: tuple = (0.0, 0.0, 0.0),
):
    sx, sy, sz = size
    prev_verts = set(bm.verts)
    mat = mathutils.Matrix.Translation(center) @ mathutils.Euler(rot_euler, "XYZ").to_matrix().to_4x4()
    res = bmesh.ops.create_cube(bm, size=1.0)
    verts = res["verts"]
    for v in verts:
        v.co = mathutils.Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
    if bevel > 0.0:
        edges = list({e for v in verts if v.is_valid for e in v.link_edges})
        bmesh.ops.bevel(
            bm,
            geom=edges,
            offset=bevel,
            offset_type="OFFSET",
            segments=segments,
            profile=0.5,
            affect="EDGES",
        )
    new_verts = [v for v in bm.verts if v not in prev_verts and v.is_valid]
    for v in new_verts:
        v.co = mat @ v.co
    return new_verts


def bm_add_cylinder(
    bm: bmesh.types.BMesh,
    center: tuple,
    radius: float,
    depth: float,
    segs: int = 16,
    rot_euler: tuple = (0.0, 0.0, 0.0),
    bevel_cap: float = 0.0,
):
    prev_verts = set(bm.verts)
    res = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=radius,
        radius2=radius,
        depth=depth,
    )
    verts = res["verts"]
    if bevel_cap > 0.0:
        cap_edges = list({
            e for v in verts if v.is_valid for e in v.link_edges
            if len(e.link_faces) == 2 and abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-4
        })
        if cap_edges:
            bmesh.ops.bevel(bm, geom=cap_edges, offset=bevel_cap, segments=1, affect="EDGES")
    mat = mathutils.Matrix.Translation(center) @ mathutils.Euler(rot_euler, "XYZ").to_matrix().to_4x4()
    new_verts = [v for v in bm.verts if v not in prev_verts and v.is_valid]
    for v in new_verts:
        v.co = mat @ v.co
    return new_verts


def bm_add_swept_tube(bm: bmesh.types.BMesh, points: list, radius: float, ring_segs: int = 8):
    """Build a smooth closed-cap curved tube along a list of 3D Vector points."""
    rings = []
    n_pts = len(points)
    for i, pt in enumerate(points):
        p = mathutils.Vector(pt)
        if i == 0:
            tan = (mathutils.Vector(points[1]) - p).normalized()
        elif i == n_pts - 1:
            tan = (p - mathutils.Vector(points[i - 1])).normalized()
        else:
            tan = (mathutils.Vector(points[i + 1]) - mathutils.Vector(points[i - 1])).normalized()
        up = mathutils.Vector((0.0, 0.0, 1.0))
        if abs(tan.dot(up)) > 0.92:
            up = mathutils.Vector((1.0, 0.0, 0.0))
        side = tan.cross(up).normalized()
        binorm = side.cross(tan).normalized()
        ring = []
        for s in range(ring_segs):
            a = 2.0 * math.pi * s / ring_segs
            v_pos = p + (side * math.cos(a) + binorm * math.sin(a)) * radius
            ring.append(bm.verts.new(v_pos))
        rings.append(ring)

    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for s in range(ring_segs):
            sn = (s + 1) % ring_segs
            bm.faces.new((r0[s], r0[sn], r1[sn], r1[s]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])


def export_glb(filename: str):
    os.makedirs(OUT_DIR, exist_ok=True)
    out_path = os.path.join(OUT_DIR, filename)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    return out_path


# ---------------------------------------------------------------------------
# 1. WOODEN MILITARY ORDNANCE CRATE (ammo_crate_wood.glb)
#    Target: ~0.56 x 0.28 x 0.34 m (Godot X, Y, Z), base at Z=0
# ---------------------------------------------------------------------------
def build_ammo_crate_wood():
    clear_scene()
    alb_w, orm_w, nrm_w = gen_wood_crate_pbr(512)
    mat_wood = build_pbr_material(
        "Diorama_CrateTimber",
        metallic=0.0,
        roughness=0.78,
        alb_img=make_packed_image("crate_timber_alb", alb_w, "sRGB"),
        orm_img=make_packed_image("crate_timber_orm", orm_w, "Non-Color"),
        nrm_img=make_packed_image("crate_timber_nrm", nrm_w, "Non-Color"),
        nrm_strength=0.95,
    )
    mat_steel = build_pbr_material(
        "Diorama_CrateIron",
        base_color=(0.045, 0.050, 0.048, 1.0),
        metallic=0.68,
        roughness=0.46,
    )
    mat_rope = build_pbr_material(
        "Diorama_CrateRope",
        base_color=(0.24, 0.20, 0.12, 1.0),
        metallic=0.0,
        roughness=0.92,
    )

    # Dimensions in Blender (X=width 0.54, Y=depth 0.32, Z=height 0.26)
    W, D, H = 0.54, 0.32, 0.26
    # Slatted timber body + core shadow backing
    bm_wood = bmesh.new()
    # Recessed dark backing box (provides deep inter-plank crevices)
    bm_add_beveled_box(bm_wood, (0.0, 0.0, H * 0.48), (W - 0.036, D - 0.036, H - 0.032), bevel=0.002)

    # Front & Back: 4 horizontal beveled planks with 3mm vertical gaps
    plank_h = 0.052
    plank_gap = 0.004
    for side_y in (-D * 0.5 + 0.009, D * 0.5 - 0.009):
        for p_idx in range(4):
            pz = 0.022 + plank_h * 0.5 + p_idx * (plank_h + plank_gap)
            bm_add_beveled_box(bm_wood, (0.0, side_y, pz), (W - 0.016, 0.014, plank_h), bevel=0.0022, segments=1)

    # Left & Right ends: 4 planks + 2 vertical edge cleats + 2 horizontal top/bottom battens
    for sx_sign in (-1.0, 1.0):
        ex = sx_sign * (W * 0.5 - 0.010)
        for p_idx in range(4):
            pz = 0.022 + plank_h * 0.5 + p_idx * (plank_h + plank_gap)
            bm_add_beveled_box(bm_wood, (ex, 0.0, pz), (0.014, D - 0.024, plank_h), bevel=0.002, segments=1)
        for cy_sign in (-1.0, 1.0):
            bm_add_beveled_box(
                bm_wood,
                (sx_sign * (W * 0.5 - 0.002), cy_sign * (D * 0.5 - 0.032), H * 0.5),
                (0.018, 0.044, H - 0.016),
                bevel=0.0025,
                segments=1,
            )

    # Top lid: 4 longitudinal planks + 2 raised transverse lid battens
    lid_z = H - 0.010
    plank_d = (D - 0.024) / 4.0
    for p_idx in range(4):
        py = -D * 0.5 + 0.012 + plank_d * 0.5 + p_idx * plank_d
        bm_add_beveled_box(bm_wood, (0.0, py, lid_z), (W + 0.012, plank_d - 0.004, 0.016), bevel=0.0022, segments=1)
    for bx in (-W * 0.34, W * 0.34):
        bm_add_beveled_box(bm_wood, (bx, 0.0, H + 0.005), (0.048, D + 0.012, 0.016), bevel=0.0025, segments=1)

    # Bottom skids (two longitudinal runners touching Z=0 cleanly)
    for sy in (-D * 0.36, D * 0.36):
        bm_add_beveled_box(bm_wood, (0.0, sy, 0.009), (W * 0.96, 0.042, 0.018), bevel=0.002, segments=1)

    bm_to_object(
        "AmmoCrateWood",
        bm_wood,
        mat_wood,
        uv_fn=lambda bm: apply_front_only_stencil_uv(bm, 0.0, H * 0.50, W * 0.90, H * 0.85),
        smooth_deg=32.0,
    )

    # Dark Steel Corner Brackets, Toggle Hasps, Rear Hinges, Rivets
    bm_iron = bmesh.new()
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            cx = sx * (W * 0.5 - 0.018)
            cy = sy * (D * 0.5 - 0.004)
            # Top & bottom corner L-straps
            for cz in (0.030, H - 0.024):
                bm_add_beveled_box(bm_iron, (cx, cy, cz), (0.056, 0.028, 0.024), bevel=0.0015)
                bm_add_beveled_box(bm_iron, (sx * (W * 0.5 + 0.002), sy * (D * 0.5 - 0.028), cz), (0.012, 0.052, 0.024), bevel=0.0015)
                bm_add_cylinder(bm_iron, (sx * (W * 0.5 - 0.032), sy * (D * 0.5 + 0.003), cz), 0.004, 0.006, segs=8, rot_euler=(math.pi * 0.5, 0.0, 0.0))

    # Front twin toggle-latch hasps (facing -Y in Blender = +Z front in Godot)
    front_y = -D * 0.5 - 0.005
    for lx in (-W * 0.25, W * 0.25):
        # Upper lid bracket + catch bar
        bm_add_beveled_box(bm_iron, (lx, front_y, H - 0.022), (0.028, 0.012, 0.034), bevel=0.0015)
        # Hinged toggle arm + lower catch plate
        bm_add_beveled_box(bm_iron, (lx, front_y - 0.003, H * 0.58), (0.022, 0.010, 0.068), bevel=0.0015)
        bm_add_beveled_box(bm_iron, (lx, front_y, H * 0.36), (0.030, 0.014, 0.024), bevel=0.0015)
        bm_add_cylinder(bm_iron, (lx, front_y - 0.007, H * 0.44), 0.0045, 0.026, segs=8, rot_euler=(0.0, math.pi * 0.5, 0.0))

    # Rear strap hinges (+Y back)
    back_y = D * 0.5 + 0.003
    for hx in (-W * 0.32, W * 0.32):
        bm_add_beveled_box(bm_iron, (hx, back_y, H - 0.036), (0.032, 0.008, 0.054), bevel=0.0012)
        bm_add_cylinder(bm_iron, (hx, back_y + 0.003, H - 0.012), 0.006, 0.036, segs=10, rot_euler=(0.0, math.pi * 0.5, 0.0))

    # Side rope anchor eyelets
    for sx in (-1.0, 1.0):
        for dy in (-0.055, 0.055):
            bm_add_beveled_box(bm_iron, (sx * (W * 0.5 + 0.006), dy, H * 0.56), (0.014, 0.020, 0.020), bevel=0.0015)

    bm_to_object("AmmoCrateIron", bm_iron, mat_steel, smooth_deg=35.0)

    # Braided Rope Side Carry Handles
    bm_rope = bmesh.new()
    for sx in (-1.0, 1.0):
        ex = sx * (W * 0.5 + 0.008)
        arc_pts = []
        for i in range(9):
            t = i / 8.0
            a = t * math.pi
            y = -0.055 + 0.110 * t
            z = H * 0.56 - math.sin(a) * 0.058
            x = ex + sx * math.sin(a) * 0.026
            arc_pts.append((x, y, z))
        bm_add_swept_tube(bm_rope, arc_pts, radius=0.0075, ring_segs=8)
    bm_to_object("AmmoCrateRopeHandles", bm_rope, mat_rope, smooth_deg=60.0)

    return export_glb("ammo_crate_wood.glb")


# ---------------------------------------------------------------------------
# 2. STAMPED M2A1 STEEL AMMO CAN (ammo_can_m2a1.glb)
#    Target: ~0.30 x 0.19 x 0.15 m, base at Z=0
# ---------------------------------------------------------------------------
def build_ammo_can_m2a1():
    clear_scene()
    alb_m, orm_m, nrm_m = gen_steel_ammo_can_pbr(512)
    mat_can = build_pbr_material(
        "Diorama_M2A1Enamel",
        metallic=0.28,
        roughness=0.48,
        alb_img=make_packed_image("m2a1_alb", alb_m, "sRGB"),
        orm_img=make_packed_image("m2a1_orm", orm_m, "Non-Color"),
        nrm_img=make_packed_image("m2a1_nrm", nrm_m, "Non-Color"),
        nrm_strength=0.75,
    )
    mat_bare = build_pbr_material(
        "Diorama_M2A1ClaspHardware",
        base_color=(0.11, 0.12, 0.11, 1.0),
        metallic=0.74,
        roughness=0.40,
    )

    L, W, H = 0.30, 0.15, 0.185
    bm = bmesh.new()
    # Main drawn steel body (chamfered)
    bm_add_beveled_box(bm, (0.0, 0.0, (H - 0.025) * 0.5 + 0.002), (L, W, H - 0.026), bevel=0.005, segments=2)
    # Rolled bottom skirt rim resting cleanly at Z=0
    bm_add_beveled_box(bm, (0.0, 0.0, 0.005), (L + 0.006, W + 0.006, 0.010), bevel=0.002, segments=1)
    # Recessed gasket groove neck under lid
    bm_add_beveled_box(bm, (0.0, 0.0, H - 0.028), (L - 0.008, W - 0.008, 0.012), bevel=0.001)
    # Overhanging steel lid (with front/back overhang)
    bm_add_beveled_box(bm, (0.0, 0.0, H - 0.012), (L + 0.014, W + 0.014, 0.024), bevel=0.004, segments=2)
    # Top raised handle side shoulders flanking a central handle channel
    for sy in (-W * 0.34, W * 0.34):
        bm_add_beveled_box(bm, (0.0, sy, H + 0.003), (L - 0.020, W * 0.28, 0.010), bevel=0.0025, segments=1)

    # Embossed side stiffening ribs on both +/-Y long walls
    for sy_sign in (-1.0, 1.0):
        ry = sy_sign * (W * 0.5 + 0.002)
        for rx in (-L * 0.34, L * 0.34):
            bm_add_beveled_box(bm, (rx, ry, H * 0.44), (0.014, 0.006, H * 0.56), bevel=0.0018, segments=1)
        bm_add_beveled_box(bm, (0.0, ry, H * 0.72), (L * 0.68, 0.005, 0.012), bevel=0.0015, segments=1)

    # Stamped end stiffeners on +/-X
    for sx_sign in (-1.0, 1.0):
        bm_add_beveled_box(bm, (sx_sign * (L * 0.5 + 0.002), 0.0, H * 0.45), (0.006, W * 0.45, H * 0.50), bevel=0.0018, segments=1)

    bm_to_object(
        "AmmoCanM2A1",
        bm,
        mat_can,
        uv_fn=lambda b: apply_front_only_stencil_uv(b, 0.0, H * 0.46, L * 0.86, H * 0.78),
        smooth_deg=35.0,
    )

    # Tension Clasp Latch, Rear Hinge Knuckles & Folding Carry Handle Bail
    bm_hw = bmesh.new()
    # Front (-X end) heavy stamped tension lever + wire latch bail
    lx = -L * 0.5 - 0.010
    bm_add_beveled_box(bm_hw, (lx, 0.0, H * 0.52), (0.010, 0.044, 0.072), bevel=0.002, rot_euler=(0.0, -0.08, 0.0))
    bm_add_beveled_box(bm_hw, (lx - 0.005, 0.0, H * 0.31), (0.014, 0.048, 0.014), bevel=0.002)
    bm_add_beveled_box(bm_hw, (-L * 0.5 - 0.007, 0.0, H - 0.012), (0.012, 0.036, 0.014), bevel=0.0015)
    # Wire clasp loop
    bail_pts = [
        (-L * 0.5 - 0.006, -0.016, H - 0.012),
        (-L * 0.5 - 0.015, -0.016, H * 0.72),
        (-L * 0.5 - 0.012, 0.0, H * 0.56),
        (-L * 0.5 - 0.015, 0.016, H * 0.72),
        (-L * 0.5 - 0.006, 0.016, H - 0.012),
    ]
    bm_add_swept_tube(bm_hw, bail_pts, radius=0.0026, ring_segs=6)

    # Rear (+X end) hinge bar & mounting bracket
    bm_add_beveled_box(bm_hw, (L * 0.5 + 0.006, 0.0, H - 0.022), (0.010, 0.056, 0.032), bevel=0.0015)
    bm_add_cylinder(bm_hw, (L * 0.5 + 0.009, 0.0, H - 0.010), 0.005, 0.062, segs=8, rot_euler=(math.pi * 0.5, 0.0, 0.0))

    # Top folding wire carry handle resting along lid trough
    top_bail = [
        (-0.070, 0.0, H + 0.002),
        (-0.068, -0.026, H + 0.009),
        (-0.045, -0.028, H + 0.013),
        (0.045, -0.028, H + 0.013),
        (0.068, -0.026, H + 0.009),
        (0.070, 0.0, H + 0.002),
    ]
    bm_add_swept_tube(bm_hw, top_bail, radius=0.0038, ring_segs=8)
    for hx in (-0.070, 0.070):
        bm_add_beveled_box(bm_hw, (hx, 0.0, H + 0.002), (0.018, 0.016, 0.009), bevel=0.001)

    bm_to_object("AmmoCanM2A1Hardware", bm_hw, mat_bare, smooth_deg=45.0)
    return export_glb("ammo_can_m2a1.glb")


# ---------------------------------------------------------------------------
# 3. RUGGEDIZED WATERPROOF TACTICAL FPV CASE (pelican_fpv_case.glb)
#    Target: ~0.48 x 0.17 x 0.35 m, base at Z=0
# ---------------------------------------------------------------------------
def build_pelican_fpv_case():
    clear_scene()
    alb_p, orm_p, nrm_p = gen_pelican_polymer_pbr(512)
    mat_case = build_pbr_material(
        "Diorama_PelicanShell",
        metallic=0.02,
        roughness=0.58,
        alb_img=make_packed_image("pelican_alb", alb_p, "sRGB"),
        orm_img=make_packed_image("pelican_orm", orm_p, "Non-Color"),
        nrm_img=make_packed_image("pelican_nrm", nrm_p, "Non-Color"),
        nrm_strength=0.90,
    )
    mat_latch = build_pbr_material(
        "Diorama_PelicanLatch",
        base_color=(0.065, 0.070, 0.065, 1.0),
        metallic=0.10,
        roughness=0.48,
    )
    mat_amber = build_pbr_material(
        "Diorama_PelicanTrim",
        base_color=(0.64, 0.46, 0.10, 1.0),
        metallic=0.25,
        roughness=0.38,
    )

    W, D, H = 0.46, 0.34, 0.165
    bm = bmesh.new()
    # Lower tub
    bm_add_beveled_box(bm, (0.0, 0.0, 0.056), (W, D, 0.108), bevel=0.007, segments=2)
    # Recessed waterproof gasket seam groove
    bm_add_beveled_box(bm, (0.0, 0.0, 0.112), (W - 0.012, D - 0.012, 0.010), bevel=0.001)
    # Overhanging lid
    bm_add_beveled_box(bm, (0.0, 0.0, 0.139), (W + 0.006, D + 0.006, 0.044), bevel=0.007, segments=2)

    # Reinforced rubberized corner bumpers
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            bm_add_beveled_box(
                bm,
                (sx * (W * 0.5 - 0.016), sy * (D * 0.5 - 0.016), H * 0.5),
                (0.056, 0.056, H),
                bevel=0.006,
                segments=2,
            )

    # Molded structural top lid ribs (flanking central placard)
    for rx in (-W * 0.35, -W * 0.25, W * 0.25, W * 0.35):
        bm_add_beveled_box(bm, (rx, 0.0, H + 0.002), (0.018, D - 0.048, 0.012), bevel=0.003, segments=1)
    # Recessed center name-plate pad on lid top
    bm_add_beveled_box(bm, (0.0, 0.0, H + 0.001), (W * 0.36, D * 0.38, 0.006), bevel=0.002)

    # Side vertical stiffening ribs
    for sy_sign in (-1.0, 1.0):
        for rx in (-W * 0.30, -W * 0.10, W * 0.10, W * 0.30):
            bm_add_beveled_box(bm, (rx, sy_sign * (D * 0.5 + 0.003), 0.062), (0.016, 0.008, 0.088), bevel=0.002)

    # Bottom feet touching Z=0 cleanly
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            bm_add_beveled_box(bm, (sx * (W * 0.38), sy * (D * 0.38), 0.004), (0.05, 0.04, 0.008), bevel=0.001)

    bm_to_object(
        "PelicanFpvCase",
        bm,
        mat_case,
        uv_fn=lambda b: apply_pelican_placard_uv(b, W * 0.175, D * 0.185, H),
        smooth_deg=35.0,
    )

    # Heavy Draw-Latches, Guard Wings, Molded Front Carry Handle & Rear Hinges
    bm_l = bmesh.new()
    fy = -D * 0.5 - 0.005
    for lx in (-W * 0.28, W * 0.28):
        # Twin guard ribs flanking latch
        for gx in (-0.024, 0.024):
            bm_add_beveled_box(bm_l, (lx + gx, fy, 0.108), (0.008, 0.016, 0.068), bevel=0.002)
        # Double-throw latch paddle
        bm_add_beveled_box(bm_l, (lx, fy - 0.004, 0.108), (0.036, 0.012, 0.056), bevel=0.0025)

    # Front ergonomic carry handle & clevis brackets
    for cx in (-0.072, 0.072):
        bm_add_beveled_box(bm_l, (cx, fy - 0.006, 0.068), (0.022, 0.026, 0.028), bevel=0.003)
    handle_pts = [
        (-0.072, fy - 0.012, 0.068),
        (-0.068, fy - 0.044, 0.066),
        (-0.040, fy - 0.048, 0.066),
        (0.040, fy - 0.048, 0.066),
        (0.068, fy - 0.044, 0.066),
        (0.072, fy - 0.012, 0.068),
    ]
    bm_add_swept_tube(bm_l, handle_pts, radius=0.010, ring_segs=10)

    # Pressure purge valve boss beside handle
    bm_add_cylinder(bm_l, (W * 0.12, fy - 0.002, 0.052), 0.014, 0.010, segs=14, rot_euler=(math.pi * 0.5, 0.0, 0.0), bevel_cap=0.002)

    # Rear hinge knuckles (+Y)
    for hx in (-W * 0.30, W * 0.30):
        bm_add_beveled_box(bm_l, (hx, D * 0.5 + 0.005, 0.112), (0.046, 0.016, 0.038), bevel=0.003)

    bm_to_object("PelicanFpvHardware", bm_l, mat_latch, smooth_deg=42.0)

    # Tactical Steel Padlock Eyes (subtle amber/brass accent)
    bm_a = bmesh.new()
    for sx in (-1.0, 1.0):
        bm_add_beveled_box(bm_a, (sx * W * 0.40, fy - 0.002, 0.110), (0.018, 0.014, 0.020), bevel=0.002)
    bm_to_object("PelicanFpvPadlockTrim", bm_a, mat_amber, smooth_deg=35.0)
    return export_glb("pelican_fpv_case.glb")


# ---------------------------------------------------------------------------
# 4. ORGANIC WOVEN BURLAP SANDBAG BERM CLUSTER (sandbag_cluster.glb)
#    Target: ~0.85 x 0.24 x 0.34 m curved berm of 5 bags, base at Z=0
# ---------------------------------------------------------------------------
def _add_sculpted_sandbag(
    bm: bmesh.types.BMesh,
    center: tuple,
    yaw: float,
    pitch: float,
    length: float,
    width: float,
    height: float,
    seed: int = 1,
):
    """Subdivided, gravity-sagged burlap pillow mesh with pinched stitched ears."""
    u_steps = 22
    v_steps = 12
    # Start from UV sphere then reshape organically into a slumped sandbag
    res = bmesh.ops.create_uvsphere(bm, u_segments=u_steps, v_segments=v_steps, radius=1.0)
    verts = res["verts"]

    rot = mathutils.Euler((pitch, 0.0, yaw), "XYZ").to_matrix()
    ctr = mathutils.Vector(center)

    min_local_z = 999.0
    local_coords = []
    for v in verts:
        x, y, z = v.co.x, v.co.y, v.co.z
        # Map sphere (radius 1) onto sandbag extents (X along length, Y along width, Z height)
        nx = x
        # Pinch inward tightly around x = +/- 0.80 (tied sack neck), then slightly flare cloth ear
        end_abs = abs(nx)
        neck_pinch = 1.0 - 0.68 * math.exp(-((end_abs - 0.79) / 0.10) ** 2)
        ear_flatten = 1.0 - 0.55 * max(0.0, (end_abs - 0.78) / 0.22)
        # Sagging plump lower belly & flat ground footprint
        belly = 1.0 + 0.18 * max(0.0, 1.0 - z * z)
        sx = nx * (length * 0.5)
        sy = y * (width * 0.5) * neck_pinch * belly
        sz = z * (height * 0.5) * neck_pinch * ear_flatten

        # Add natural gravity flatten on underside and soft cloth folds along bag
        if sz < -height * 0.24:
            sz = -height * 0.24 + (sz + height * 0.24) * 0.25
        crease = (
            0.0055 * math.sin(nx * 14.0 + seed * 1.7 + y * 2.5) * (1.0 - end_abs * 0.6)
            + 0.0040 * math.cos(y * 8.0 + seed * 3.1)
        )
        sz += crease
        # Slight gravity curve downward toward ends so bag drapes over neighbors
        sz -= (nx * nx) * height * 0.10
        lc = mathutils.Vector((sx, sy, sz))
        local_coords.append((v, lc))
        if lc.z < min_local_z:
            min_local_z = lc.z

    for v, lc in local_coords:
        v.co = ctr + (rot @ lc)


def build_sandbag_cluster():
    clear_scene()
    alb_b, orm_b, nrm_b = gen_burlap_sandbag_pbr(512)
    mat_burlap = build_pbr_material(
        "Diorama_SandbagBurlap",
        metallic=0.0,
        roughness=0.92,
        alb_img=make_packed_image("burlap_alb", alb_b, "sRGB"),
        orm_img=make_packed_image("burlap_orm", orm_b, "Non-Color"),
        nrm_img=make_packed_image("burlap_nrm", nrm_b, "Non-Color"),
        nrm_strength=1.1,
    )
    mat_twine = build_pbr_material(
        "Diorama_SandbagTwine",
        base_color=(0.38, 0.30, 0.19, 1.0),
        metallic=0.0,
        roughness=0.95,
    )

    bm = bmesh.new()
    # Bottom course (3 overlapping bags forming a gentle arc)
    # Note: rest Z positioned cleanly so flattened underside sits right at Z=0
    bags = [
        ((-0.26, 0.04, 0.040), math.radians(14.0), 0.0, 0.34, 0.20, 0.105, 11),
        ((0.02, -0.02, 0.041), math.radians(-4.0), 0.0, 0.36, 0.21, 0.108, 22),
        ((0.28, 0.05, 0.040), math.radians(-18.0), 0.0, 0.33, 0.20, 0.104, 33),
        # Upper course (2 staggered overlapping bags bridging the lower seams)
        ((-0.13, 0.01, 0.114), math.radians(8.0), math.radians(4.0), 0.34, 0.195, 0.102, 44),
        ((0.15, 0.02, 0.112), math.radians(-11.0), math.radians(-3.0), 0.33, 0.195, 0.100, 55),
    ]
    for pos, yaw, pitch, bl, bw, bh, sd in bags:
        _add_sculpted_sandbag(bm, pos, yaw, pitch, bl, bw, bh, seed=sd)

    # Clamp lowest vertex Z cleanly to Z = 0.0
    min_z = min(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= min_z
        if v.co.z < 0.002:
            v.co.z *= 0.2

    bm_to_object("SandbagCluster", bm, mat_burlap, uv_fn=lambda b: apply_box_uv(b, scale=3.2), smooth_deg=85.0)

    # Twine tie cords around pinched bag ears
    bm_t = bmesh.new()
    for pos, yaw, pitch, bl, bw, bh, _ in bags:
        rot = mathutils.Euler((pitch, 0.0, yaw), "XYZ").to_matrix()
        ctr = mathutils.Vector((pos[0], pos[1], pos[2] - min_z))
        for end_s in (-1.0, 1.0):
            ring_pts = []
            neck_x = end_s * bl * 0.395
            for s in range(11):
                a = 2.0 * math.pi * s / 10.0
                p = mathutils.Vector((neck_x, math.cos(a) * bw * 0.17, math.sin(a) * bh * 0.17 - bh * 0.04))
                ring_pts.append(ctr + (rot @ p))
            bm_add_swept_tube(bm_t, ring_pts, radius=0.0032, ring_segs=6)
    bm_to_object("SandbagTwine", bm_t, mat_twine, smooth_deg=60.0)
    return export_glb("sandbag_cluster.glb")


# ---------------------------------------------------------------------------
# 5. FIELD TACTICAL RADIO TRANSCEIVER + WHIP ANTENNA (tactical_radio.glb)
#    Target: ~0.22 x 0.28 m body + whip antenna to ~0.58 m, base at Z=0
# ---------------------------------------------------------------------------
def build_tactical_radio():
    clear_scene()
    alb_r, orm_r, nrm_r, emi_r = gen_radio_faceplate_pbr(256)
    mat_chassis = build_pbr_material(
        "Diorama_RadioChassis",
        base_color=(0.052, 0.064, 0.048, 1.0),
        metallic=0.35,
        roughness=0.52,
    )
    mat_panel = build_pbr_material(
        "Diorama_RadioFaceplate",
        metallic=0.25,
        roughness=0.38,
        alb_img=make_packed_image("radio_panel_alb", alb_r, "sRGB"),
        orm_img=make_packed_image("radio_panel_orm", orm_r, "Non-Color"),
        nrm_img=make_packed_image("radio_panel_nrm", nrm_r, "Non-Color"),
        emi_img=make_packed_image("radio_panel_emi", emi_r, "sRGB"),
        nrm_strength=0.95,
        emission_strength=1.55,
    )
    mat_black_metal = build_pbr_material(
        "Diorama_RadioWhip",
        base_color=(0.06, 0.065, 0.068, 1.0),
        metallic=0.35,
        roughness=0.52,
    )
    mat_brass = build_pbr_material(
        "Diorama_RadioBrassBNC",
        base_color=(0.82, 0.65, 0.28, 1.0),
        metallic=0.90,
        roughness=0.24,
    )

    W, D, H = 0.21, 0.12, 0.26
    bm = bmesh.new()
    # Lower battery box (chamfered)
    bm_add_beveled_box(bm, (0.0, 0.0, 0.044), (W, D, 0.088), bevel=0.005, segments=2)
    # Center locking clamp band
    bm_add_beveled_box(bm, (0.0, 0.0, 0.092), (W + 0.008, D + 0.008, 0.012), bevel=0.002)
    # Main upper transceiver housing
    bm_add_beveled_box(bm, (0.0, 0.0, 0.180), (W - 0.004, D - 0.004, 0.162), bevel=0.006, segments=2)

    # Cooling heat-sink fins along back (+Y)
    for fi in range(7):
        fx = -W * 0.36 + fi * (W * 0.12)
        bm_add_beveled_box(bm, (fx, D * 0.5 + 0.003, 0.175), (0.008, 0.010, 0.130), bevel=0.001)

    # Top guard rail / roll cage handles around antenna & dial deck
    for sx in (-1.0, 1.0):
        guard_pts = [
            (sx * (W * 0.44), -D * 0.35, H - 0.012),
            (sx * (W * 0.46), -D * 0.35, H + 0.026),
            (sx * (W * 0.46), D * 0.35, H + 0.026),
            (sx * (W * 0.44), D * 0.35, H - 0.012),
        ]
        bm_add_swept_tube(bm, guard_pts, radius=0.0065, ring_segs=8)

    bm_to_object("TacticalRadioBody", bm, mat_chassis, smooth_deg=35.0)

    # Front recessed control faceplate (with LCD + speaker slots)
    bm_p = bmesh.new()
    bm_add_beveled_box(bm_p, (0.0, -D * 0.5 - 0.002, 0.180), (W * 0.78, 0.008, 0.125), bevel=0.0015)
    bm_to_object(
        "TacticalRadioFaceplate",
        bm_p,
        mat_panel,
        uv_fn=lambda b: apply_planar_stencil_uv(b, 0.0, 0.180, W * 0.78, 0.125),
        smooth_deg=25.0,
    )

    # Knurled dials, rubber whip antenna & coiled cable
    bm_w = bmesh.new()
    # Two rotary top knobs
    for kx, kr in ((-0.042, 0.014), (0.006, 0.012)):
        bm_add_cylinder(bm_w, (kx, -0.014, H + 0.012), kr, 0.022, segs=14, bevel_cap=0.002)
    # PTT side button guard
    bm_add_beveled_box(bm_w, (-W * 0.5 - 0.006, 0.0, 0.185), (0.010, 0.036, 0.046), bevel=0.002)

    # Flexible gently curving tactical whip antenna rising cleanly to Z=0.56 m
    whip_pts = []
    ax0, ay0, az0 = W * 0.30, 0.010, H + 0.020
    for i in range(11):
        t = i / 10.0
        whip_pts.append((ax0 + 0.032 * (t ** 1.8), ay0 - 0.018 * (t ** 2.0), az0 + 0.295 * t))
    bm_add_swept_tube(bm_w, whip_pts, radius=0.0042, ring_segs=8)
    # Taper tip cap
    bm_add_cylinder(bm_w, whip_pts[-1], 0.0055, 0.014, segs=8, rot_euler=(0.08, 0.12, 0.0))

    # Short coiled handset cable looping from left side down toward deck
    coil_pts = []
    for i in range(19):
        t = i / 18.0
        a = t * 5.0 * 2.0 * math.pi
        cx = -W * 0.5 - 0.018 - 0.018 * math.sin(t * math.pi) + 0.006 * math.cos(a)
        cy = -0.018 + 0.008 * math.sin(a)
        cz = 0.205 * (1.0 - t * 0.78)
        coil_pts.append((cx, cy, cz))
    bm_add_swept_tube(bm_w, coil_pts, radius=0.0030, ring_segs=6)
    bm_to_object("TacticalRadioControlsAndWhip", bm_w, mat_black_metal, smooth_deg=55.0)

    # Brass BNC coax connector base
    bm_b = bmesh.new()
    bm_add_cylinder(bm_b, (ax0, ay0, H + 0.012), 0.011, 0.022, segs=12, bevel_cap=0.0015)
    bm_to_object("TacticalRadioBNC", bm_b, mat_brass, smooth_deg=45.0)

    return export_glb("tactical_radio.glb")


# ---------------------------------------------------------------------------
# 6. HORIZONTAL ORDNANCE TRANSPORT TUBE (ordnance_tube.glb)
#    Target: ~0.58 x 0.12 x 0.12 m horizontal canister resting at Z=0
# ---------------------------------------------------------------------------
def build_ordnance_tube():
    clear_scene()
    alb_o, orm_o, nrm_o = gen_ordnance_tube_pbr(512)
    mat_tube = build_pbr_material(
        "Diorama_OrdnanceTube",
        metallic=0.05,
        roughness=0.48,
        alb_img=make_packed_image("ordnance_alb", alb_o, "sRGB"),
        orm_img=make_packed_image("ordnance_orm", orm_o, "Non-Color"),
        nrm_img=make_packed_image("ordnance_nrm", nrm_o, "Non-Color"),
        nrm_strength=0.80,
    )
    mat_rubber = build_pbr_material(
        "Diorama_OrdnanceRubberCap",
        base_color=(0.045, 0.048, 0.046, 1.0),
        metallic=0.02,
        roughness=0.78,
    )
    mat_buckle = build_pbr_material(
        "Diorama_OrdnanceClasp",
        base_color=(0.24, 0.26, 0.25, 1.0),
        metallic=0.82,
        roughness=0.34,
    )

    L = 0.56
    R_cap = 0.056  # Outer rubber bumper cap radius -> axis Z = R_cap so Z_min == 0.0!
    R_body = 0.047
    cz = R_cap

    # Fiberglass tube body + molded stiffening bands (aligned along Blender X)
    bm = bmesh.new()
    bm_add_cylinder(bm, (0.0, 0.0, cz), R_body, L - 0.05, segs=24, rot_euler=(0.0, math.pi * 0.5, 0.0))
    for rx in (-0.15, 0.0, 0.15):
        bm_add_cylinder(bm, (rx, 0.0, cz), R_body + 0.0045, 0.022, segs=24, rot_euler=(0.0, math.pi * 0.5, 0.0), bevel_cap=0.0015)

    def uv_tube(b):
        uv_layer = b.loops.layers.uv.get("UVMap") or b.loops.layers.uv.new("UVMap")
        for f in b.faces:
            for loop in f.loops:
                co = loop.vert.co
                ang = math.atan2(co.z - cz, co.y) / (2.0 * math.pi) + 0.5
                u = (co.x / L) + 0.5
                loop[uv_layer].uv = (u, ang)

    bm_to_object("OrdnanceTubeBody", bm, mat_tube, uv_fn=uv_tube, smooth_deg=55.0)

    # Octagonal/ribbed EPDM rubber shock-absorber endcaps + sling strap collar
    bm_r = bmesh.new()
    for sx in (-1.0, 1.0):
        ex = sx * (L * 0.5 - 0.024)
        bm_add_cylinder(bm_r, (ex, 0.0, cz), R_cap, 0.068, segs=16, rot_euler=(0.0, math.pi * 0.5, 0.0), bevel_cap=0.004)
        bm_add_cylinder(bm_r, (ex + sx * 0.028, 0.0, cz), R_cap - 0.004, 0.018, segs=16, rot_euler=(0.0, math.pi * 0.5, 0.0), bevel_cap=0.002)
    bm_to_object("OrdnanceTubeEndcaps", bm_r, mat_rubber, smooth_deg=38.0)

    # Aluminum lid latch clasp + sling D-rings
    bm_c = bmesh.new()
    bm_add_beveled_box(bm_c, (-L * 0.5 + 0.032, -R_cap + 0.004, cz + 0.012), (0.044, 0.016, 0.018), bevel=0.002)
    for sx in (-0.19, 0.19):
        bm_add_beveled_box(bm_c, (sx, -R_body - 0.003, cz + 0.015), (0.018, 0.012, 0.024), bevel=0.002)
    bm_to_object("OrdnanceTubeHardware", bm_c, mat_buckle, smooth_deg=35.0)

    return export_glb("ordnance_tube.glb")


# ---------------------------------------------------------------------------
# 7. ARMORED WORKBENCH SLAB & TACTICAL MAT (workbench_deck.glb)
#    Top work surface EXACTLY at Z = 0.0 (extends downward to Z = -0.085)
# ---------------------------------------------------------------------------
def build_workbench_deck():
    clear_scene()
    alb_d, orm_d, nrm_d = gen_workbench_deck_pbr(512)
    mat_deck = build_pbr_material(
        "Diorama_WorkbenchSurface",
        metallic=0.35,
        roughness=0.52,
        alb_img=make_packed_image("workbench_alb", alb_d, "sRGB"),
        orm_img=make_packed_image("workbench_orm", orm_d, "Non-Color"),
        nrm_img=make_packed_image("workbench_nrm", nrm_d, "Non-Color"),
        nrm_strength=0.90,
    )
    mat_rim = build_pbr_material(
        "Diorama_WorkbenchSteelRim",
        base_color=(0.075, 0.090, 0.085, 1.0),
        metallic=0.76,
        roughness=0.38,
    )
    mat_bolts = build_pbr_material(
        "Diorama_WorkbenchBolts",
        base_color=(0.34, 0.36, 0.38, 1.0),
        metallic=0.88,
        roughness=0.28,
    )

    W, D = 1.72, 1.32
    # Main recessed tactical mat plate (top surface EXACT at Z = 0.0!)
    bm_m = bmesh.new()
    bm_add_beveled_box(bm_m, (0.0, 0.0, -0.022), (W - 0.08, D - 0.08, 0.044), bevel=0.002)
    bm_to_object(
        "WorkbenchDeckMat",
        bm_m,
        mat_deck,
        uv_fn=lambda b: apply_planar_stencil_uv(b, 0.0, 0.0, W - 0.08, D - 0.08),
        smooth_deg=28.0,
    )

    # Outer beveled armored steel frame rails & corner tie-down gussets (flush at Z = +0.002 edge lip)
    bm_f = bmesh.new()
    bm_add_beveled_box(bm_f, (0.0, 0.0, -0.048), (W, D, 0.052), bevel=0.008, segments=2)
    # Perimeter steel lip frame segments around the recessed mat (sits just outside mat, top flush Z = 0.003)
    rail_h = 0.026
    rail_z = -rail_h * 0.5 + 0.003
    for sy in (-D * 0.5 + 0.022, D * 0.5 - 0.022):
        bm_add_beveled_box(bm_f, (0.0, sy, rail_z), (W, 0.044, rail_h), bevel=0.004, segments=1)
    for sx in (-W * 0.5 + 0.022, W * 0.5 - 0.022):
        bm_add_beveled_box(bm_f, (sx, 0.0, rail_z), (0.044, D - 0.088, rail_h), bevel=0.004, segments=1)
    # 4 corner chamfered tie-down gusset plates
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            bm_add_beveled_box(
                bm_f,
                (sx * (W * 0.5 - 0.048), sy * (D * 0.5 - 0.048), 0.001),
                (0.095, 0.095, 0.010),
                bevel=0.003,
                segments=1,
            )
    bm_to_object("WorkbenchArmorFrame", bm_f, mat_rim, smooth_deg=32.0)

    # Hex corner anchor bolts
    bm_b = bmesh.new()
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            for dx, dy in ((0.0, 0.0), (-sx * 0.042, 0.0), (0.0, -sy * 0.042)):
                bm_add_cylinder(
                    bm_b,
                    (sx * (W * 0.5 - 0.032) + dx, sy * (D * 0.5 - 0.032) + dy, 0.007),
                    0.008,
                    0.006,
                    segs=6,
                    bevel_cap=0.001,
                )
    bm_to_object("WorkbenchHexBolts", bm_b, mat_bolts, smooth_deg=22.0)

    return export_glb("workbench_deck.glb")


# ---------------------------------------------------------------------------
# 8. BOTTLENECKED BRASS SHELL CASING (brass_shell_casing.glb)
#    Centered at (0,0,0), axis along Blender Y -> Godot Z
#    LENGTH = 0.072 m, BASE_RADIUS = 0.0092 m, hollow neck bore & primer cup
# ---------------------------------------------------------------------------
def build_brass_shell_casing():
    clear_scene()
    alb_c, orm_c, nrm_c = gen_brass_casing_pbr(256)
    mat_brass = build_pbr_material(
        "Diorama_BrassCartridge",
        metallic=0.90,
        roughness=0.22,
        alb_img=make_packed_image("casing_alb", alb_c, "sRGB"),
        orm_img=make_packed_image("casing_orm", orm_c, "Non-Color"),
        nrm_img=make_packed_image("casing_nrm", nrm_c, "Non-Color"),
        nrm_strength=0.65,
    )

    L = 0.072
    half_L = L * 0.5
    R_base = 0.0092

    # Profile along Blender Y (axis) from base (-half_L) -> mouth (+half_L) -> hollow bore
    # Each entry: (y_local, radius, uv_v)
    profile = [
        # Center firing-pin strike dimple inside primer
        (-half_L + 0.0005, 0.0000, 0.005),
        (-half_L + 0.0007, 0.0012, 0.028),
        (-half_L + 0.0003, 0.0026, 0.075),
        # Primer pocket wall to flat brass head face
        (-half_L + 0.0000, 0.0031, 0.098),
        (-half_L + 0.0000, 0.0084, 0.135),
        # Beveled rim
        (-half_L + 0.0008, R_base, 0.155),
        (-half_L + 0.0024, R_base, 0.175),
        # Extractor groove
        (-half_L + 0.0032, 0.0077, 0.205),
        (-half_L + 0.0046, 0.0077, 0.240),
        # Extraction shoulder bevel
        (-half_L + 0.0058, 0.0091, 0.280),
        # Slightly tapered main brass body
        (-half_L + 0.0260, 0.0088, 0.500),
        (-half_L + 0.0475, 0.0084, 0.720),
        # Bottleneck shoulder
        (-half_L + 0.0565, 0.0056, 0.835),
        # Cylindrical neck
        (+half_L - 0.0010, 0.0055, 0.905),
        # Chamfered open mouth lip
        (+half_L, 0.0051, 0.922),
        (+half_L - 0.0004, 0.0045, 0.940),
        # Deep hollow carbon-dark inner cavity
        (+half_L - 0.0155, 0.0042, 0.985),
        (+half_L - 0.0160, 0.0000, 0.998),
    ]

    segs = 28
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")

    rings = []
    for p_idx, (py, pr, pv) in enumerate(profile):
        if pr <= 1e-6:
            v = bm.verts.new((0.0, py, 0.0))
            rings.append(([v], pv, True))
        else:
            ring = []
            for s in range(segs):
                a = 2.0 * math.pi * s / segs
                v = bm.verts.new((math.cos(a) * pr, py, math.sin(a) * pr))
                ring.append(v)
            rings.append((ring, pv, False))

    for i in range(len(rings) - 1):
        r0, v0, c0 = rings[i]
        r1, v1, c1 = rings[i + 1]
        if c0 and not c1:
            apex = r0[0]
            for s in range(segs):
                sn = (s + 1) % segs
                f = bm.faces.new((apex, r1[sn], r1[s]))
                u0 = (s + 0.5) / segs
                for loop in f.loops:
                    if loop.vert == apex:
                        loop[uv_layer].uv = (u0, v0)
                    elif loop.vert == r1[sn]:
                        loop[uv_layer].uv = ((s + 1) / segs, v1)
                    else:
                        loop[uv_layer].uv = (s / segs, v1)
        elif c1 and not c0:
            apex = r1[0]
            for s in range(segs):
                sn = (s + 1) % segs
                f = bm.faces.new((r0[s], r0[sn], apex))
                u0 = (s + 0.5) / segs
                for loop in f.loops:
                    if loop.vert == apex:
                        loop[uv_layer].uv = (u0, v1)
                    elif loop.vert == r0[sn]:
                        loop[uv_layer].uv = ((s + 1) / segs, v0)
                    else:
                        loop[uv_layer].uv = (s / segs, v0)
        elif not c0 and not c1:
            for s in range(segs):
                sn = (s + 1) % segs
                f = bm.faces.new((r0[s], r0[sn], r1[sn], r1[s]))
                us0, us1 = s / segs, (s + 1) / segs
                f.loops[0][uv_layer].uv = (us0, v0)
                f.loops[1][uv_layer].uv = (us1, v0)
                f.loops[2][uv_layer].uv = (us1, v1)
                f.loops[3][uv_layer].uv = (us0, v1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new("BrassShellCasing_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new("BrassShellCasing", mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat_brass)
    set_smooth_with_sharp_edges(obj, angle_deg=44.0)

    return export_glb("brass_shell_casing.glb")


# ---------------------------------------------------------------------------
# Audit & Entry Point
# ---------------------------------------------------------------------------
def audit_exported_glbs(paths: list):
    print("\n=== Diorama GLB Export Self-Audit ===")
    for p in paths:
        sz_kb = os.path.getsize(p) / 1024.0
        # Inspect glTF JSON chunk & verify embedded PNG images + triangle count + bounds
        with open(p, "rb") as f:
            magic, ver, total_len = struct.unpack("<4sII", f.read(12))
            assert magic == b"glTF", f"Bad GLB header: {p}"
            c_len, c_type = struct.unpack("<II", f.read(8))
            assert c_type == 0x4E4F534A
            gltf = json.loads(f.read(c_len).decode("utf-8"))
            b_len, b_type = struct.unpack("<II", f.read(8))
            bin_blob = f.read(b_len)

        # Compute triangles & world min/max across accessors
        tris = 0
        min_v = [1e9, 1e9, 1e9]
        max_v = [-1e9, -1e9, -1e9]
        has_uv = False
        for m in gltf.get("meshes", []):
            for prim in m.get("primitives", []):
                attrs = prim.get("attributes", {})
                if "TEXCOORD_0" in attrs:
                    has_uv = True
                if "indices" in prim:
                    acc = gltf["accessors"][prim["indices"]]
                    tris += acc["count"] // 3
                if "POSITION" in attrs:
                    pos_acc = gltf["accessors"][attrs["POSITION"]]
                    pmin = pos_acc.get("min", [0, 0, 0])
                    pmax = pos_acc.get("max", [0, 0, 0])
                    for i in range(3):
                        min_v[i] = min(min_v[i], pmin[i])
                        max_v[i] = max(max_v[i], pmax[i])

        imgs = gltf.get("images", [])
        n_imgs = len(imgs)
        # Quick non-zero check on embedded PNG payload sizes
        for img_desc in imgs:
            bv = gltf["bufferViews"][img_desc["bufferView"]]
            chunk = bin_blob[bv["byteOffset"]:bv["byteOffset"] + bv["byteLength"]]
            assert chunk[:8] == b"\x89PNG\r\n\x1a\n", f"Non-PNG image in {p}"

        sz = [max_v[i] - min_v[i] for i in range(3)]
        print(
            f"  [OK] {os.path.basename(p):<24s} | {sz_kb:6.1f} KB | {tris:5d} tris | "
            f"UV={has_uv} | imgs={n_imgs} | size=({sz[0]:.3f}, {sz[1]:.3f}, {sz[2]:.3f}) "
            f"minY={min_v[1]:+.4f} maxY={max_v[1]:+.4f}"
        )


def main():
    builders = [
        build_ammo_crate_wood,
        build_ammo_can_m2a1,
        build_pelican_fpv_case,
        build_sandbag_cluster,
        build_tactical_radio,
        build_ordnance_tube,
        build_workbench_deck,
        build_brass_shell_casing,
    ]
    paths = []
    try:
        for fn in builders:
            p = fn()
            paths.append(p)
    finally:
        cleanup_temp_pngs()
    audit_exported_glbs(paths)


if __name__ == "__main__":
    main()
