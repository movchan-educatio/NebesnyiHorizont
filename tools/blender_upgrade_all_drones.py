"""Visually upgrade all 13 shipped drone GLBs in Blender 5.2.

Preserves all runtime propulsion, duct, payload, warhead, and flag nodes
expected by DroneCatalog.gd, DronePropellerSystem.gd, combat_system.gd,
and optimize_mobile_airframes.py. Fixes detached geometry on chaklun_jet,
furia_a1sm, and leleka_100, replaces flat/low-res materials with rich
procedural PBR textures, and adds grounded hardware details per airframe.

Run from workspace root:
  blender --background --python tools/blender_upgrade_all_drones.py
"""

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
ASSETS = os.path.join(ROOT, "Assets")
DEFAULT_BACKUP = (
    r"C:\Users\USER_UA\.gemini\antigravity\brain\3e1fc674-fea9-4635-a574-57c85e14dad7"
    r"\scratch\orig_drones_backup"
)

_TMP_DIR = None
_TMP_PNGS = []
_AUDIT_ISSUES = []


# ---------------------------------------------------------------------------
# Pure-Python PNG encoder & Blender 5.2 safe pack (never packed zero-black)
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
    """Write PNG via Python and pack via bpy.data.images.load (Blender 5.2 safe)."""
    global _TMP_DIR
    if _TMP_DIR is None:
        _TMP_DIR = tempfile.mkdtemp(prefix="blender_upg_")
    tmp_path = os.path.join(_TMP_DIR, f"{name}.png")
    _write_png_rgba(tmp_path, rgba)
    _TMP_PNGS.append(tmp_path)
    img = bpy.data.images.load(tmp_path, check_existing=False)
    img.name = name
    img.colorspace_settings.name = colorspace
    img.pack()
    return img


def replace_existing_image(old_img, name: str, rgba: np.ndarray, colorspace: str = "sRGB"):
    """Load fresh PNG data and pack into scene, replacing references cleanly."""
    new_img = make_packed_image(name + "_new", rgba, colorspace=colorspace)
    for mat in bpy.data.materials:
        if mat and mat.node_tree:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image == old_img:
                    node.image = new_img
    old_name = old_img.name
    try:
        bpy.data.images.remove(old_img)
    except Exception:
        pass
    new_img.name = old_name
    return new_img


def read_blender_image_rgba_topdown(img) -> np.ndarray:
    """Read Blender image pixels as top-down uint8 RGBA array."""
    w, h = img.size[0], img.size[1]
    pix = np.array(img.pixels[:], dtype=np.float32).reshape((h, w, 4))
    topdown = np.flipud(pix)
    return np.clip(topdown * 255.0 + 0.5, 0, 255).astype(np.uint8)


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
# Procedural PBR texture generators (vectorized numpy)
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
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
}


def draw_text(img: np.ndarray, x0: int, y0: int, text: str, scale: int, color: tuple):
    h, w, _ = img.shape
    cx = x0
    for ch in text.upper():
        gly = _FONT_5X7.get(ch, _FONT_5X7[" "])
        for ry, row in enumerate(gly):
            for rx, bit in enumerate(row):
                if bit == "1":
                    px0 = cx + rx * scale
                    py0 = y0 + ry * scale
                    px1 = min(w, px0 + scale)
                    py1 = min(h, py0 + scale)
                    if px1 > 0 and py1 > 0:
                        img[max(0, py0):py1, max(0, px0):px1, :3] = color
        cx += 6 * scale


def height_to_normal(height: np.ndarray, strength: float = 2.0) -> np.ndarray:
    """Convert 2D float32 heightfield in [0..1] to tangent-space RGBA normal map."""
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


def gen_carbon_pbr(size: int = 512, repeats: int = 16, base_level: float = 0.14):
    """3K 2x2 twill carbon weave albedo, roughness, and normal maps."""
    u = (np.arange(size, dtype=np.float32) / size) * repeats
    v = (np.arange(size, dtype=np.float32) / size) * repeats
    uu, vv = np.meshgrid(u, v)

    ix = np.floor(uu).astype(np.int32)
    iy = np.floor(vv).astype(np.int32)
    fx = uu - ix
    fy = vv - iy

    # 2x2 twill state: 1 = warp on top, 0 = weft on top
    phase = (ix + iy) % 4
    warp = (phase < 2)

    warp_prof = np.sin(np.pi * fx) ** 0.65 * (0.85 + 0.15 * np.sin(np.pi * fy))
    weft_prof = np.sin(np.pi * fy) ** 0.65 * (0.85 + 0.15 * np.sin(np.pi * fx))
    fiber = np.where(warp, warp_prof, weft_prof)

    # Subtle micro-filament grain along fiber direction
    strand_w = np.sin(uu * 24.0 * math.pi) * 0.03
    strand_f = np.sin(vv * 24.0 * math.pi) * 0.03
    grain = np.where(warp, strand_f, strand_w)

    hfield = np.clip(0.25 + 0.72 * fiber + grain, 0.0, 1.0)
    spec_shift = np.where(warp, 0.04, -0.02)

    lum = np.clip(base_level + 0.13 * fiber + spec_shift + grain * 0.4, 0.04, 0.42)
    alb = np.empty((size, size, 4), dtype=np.uint8)
    alb[:, :, 0] = np.clip(lum * 255.0, 0, 255).astype(np.uint8)
    alb[:, :, 1] = np.clip(lum * 255.0 * 1.01, 0, 255).astype(np.uint8)
    alb[:, :, 2] = np.clip(lum * 255.0 * 1.05, 0, 255).astype(np.uint8)
    alb[:, :, 3] = 255

    rgh_val = np.clip(0.46 - 0.16 * fiber - spec_shift * 0.6, 0.22, 0.68)
    rgh = np.empty((size, size, 4), dtype=np.uint8)
    r8 = np.clip(rgh_val * 255.0, 0, 255).astype(np.uint8)
    rgh[:, :, 0] = r8
    rgh[:, :, 1] = r8
    rgh[:, :, 2] = r8
    rgh[:, :, 3] = 255

    nrm = height_to_normal(hfield, strength=2.4)
    return alb, rgh, nrm


def gen_composite_aerospace_pbr(
    size: int,
    base_rgb: tuple,
    panel_delta: float,
    seam_rgb: tuple,
    stripe_rgb: tuple = None,
    seed: int = 7,
):
    """High-detail aerospace composite skin with panels, rivets, and matte weave."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size

    # Multi-frequency composite cloth & spray grain
    noise = (
        0.55 * rng.normal(0.0, 0.015, (size, size)).astype(np.float32)
        + 0.008 * np.sin(xx * size * 0.45) * np.sin(yy * size * 0.45)
        + 0.006 * np.sin(xx * 18.0) * np.cos(yy * 14.0)
    )

    # Panel grid tonal variance (subtle 3x4 aerospace access zones)
    px = (xx * 3.0).astype(np.int32)
    py = (yy * 4.0).astype(np.int32)
    panel_hash = (((px * 73 + py * 139 + seed) % 7) - 3) / 3.0 * panel_delta

    # Seam lines along panel boundaries + mid-sub-panels
    seam_mask = np.zeros((size, size), dtype=np.float32)
    lw = max(1.3, size / 512.0 * 1.4)
    for gx in [0.0, 0.25, 0.50, 0.75, 1.0]:
        dist = np.abs(xx - gx) * size
        seam_mask = np.maximum(seam_mask, np.clip(1.0 - dist / lw, 0.0, 1.0))
    for gy in [0.0, 0.333, 0.666, 1.0]:
        dist = np.abs(yy - gy) * size
        seam_mask = np.maximum(seam_mask, np.clip(1.0 - dist / lw, 0.0, 1.0))

    # Diagonal stiffener seam + inspection hatch corners
    hatch = (np.abs(xx - 0.5) < 0.14) & (np.abs(yy - 0.5) < 0.10)
    h_edge_x = np.abs(np.abs(xx - 0.5) - 0.14) * size
    h_edge_y = np.abs(np.abs(yy - 0.5) - 0.10) * size
    on_hatch = ((h_edge_x < lw * 1.1) & (np.abs(yy - 0.5) <= 0.102)) | (
        (h_edge_y < lw * 1.1) & (np.abs(xx - 0.5) <= 0.142)
    )
    seam_mask = np.maximum(seam_mask, on_hatch.astype(np.float32) * 0.9)

    # Flush rivet / Dzus fastener dots alongside panel boundaries
    rivet_mask = np.zeros((size, size), dtype=np.float32)
    step = max(24, size // 20)
    rivet_r = max(1.8, size / 512.0 * 2.2)
    for ry in range(step // 2, size, step):
        for gx in [0.25, 0.50, 0.75]:
            cx = int(gx * size)
            for dx in (-int(6 * size / 512), int(6 * size / 512)):
                x0, x1 = max(0, cx + dx - 4), min(size, cx + dx + 5)
                y0, y1 = max(0, ry - 4), min(size, ry + 5)
                ry_g, rx_g = np.mgrid[y0:y1, x0:x1]
                d = np.sqrt((rx_g - (cx + dx)) ** 2 + (ry_g - ry) ** 2)
                rivet_mask[y0:y1, x0:x1] = np.maximum(
                    rivet_mask[y0:y1, x0:x1], np.clip(1.0 - d / rivet_r, 0.0, 1.0)
                )

    alb = np.empty((size, size, 4), dtype=np.uint8)
    for ch in range(3):
        base_f = base_rgb[ch] / 255.0
        seam_f = seam_rgb[ch] / 255.0
        col = np.clip(base_f + panel_hash + noise, 0.02, 0.98)
        col = col * (1.0 - seam_mask * 0.72) + seam_f * (seam_mask * 0.72)
        col = col * (1.0 - rivet_mask * 0.35) + (seam_f * 0.6 + 0.12) * (rivet_mask * 0.35)
        alb[:, :, ch] = np.clip(col * 255.0, 0, 255).astype(np.uint8)
    alb[:, :, 3] = 255

    if stripe_rgb is not None:
        # Subtle recessed safety/tactical trim stripe along band near y=0.17
        ym = (yy > 0.162) & (yy < 0.176)
        for ch in range(3):
            c_old = alb[:, :, ch].astype(np.float32)
            alb[:, :, ch] = np.where(ym, c_old * 0.25 + stripe_rgb[ch] * 0.75, alb[:, :, ch])

    hfield = np.clip(0.75 + noise * 3.0 - seam_mask * 0.55 - rivet_mask * 0.28, 0.0, 1.0)
    nrm = height_to_normal(hfield, strength=2.6)

    rgh_val = np.clip(0.50 + panel_hash * 0.5 + seam_mask * 0.26 - noise * 1.5, 0.28, 0.85)
    rgh = np.empty((size, size, 4), dtype=np.uint8)
    r8 = np.clip(rgh_val * 255.0, 0, 255).astype(np.uint8)
    rgh[:, :, 0] = r8
    rgh[:, :, 1] = r8
    rgh[:, :, 2] = r8
    rgh[:, :, 3] = 255
    return alb, rgh, nrm


def gen_battery_pbr(
    w: int = 512,
    h: int = 256,
    label: str = "6S 4500MAH",
    sub: str = "LIPO-HV 130C",
    sleeve_rgb=(28, 31, 36),
    band_rgb=(218, 128, 24),
    text_rgb=(236, 240, 244),
):
    """Tactical heat-shrink LiPo / Li-Ion battery sleeve with cell seams & specs."""
    rng = np.random.default_rng(42)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    u = xx / w
    v = yy / h

    micro = rng.normal(0.0, 0.014, (h, w)).astype(np.float32)
    cell_groove = np.zeros_like(u)
    for c_idx in range(1, 6):
        cx = c_idx / 6.0
        cell_groove = np.maximum(cell_groove, np.exp(-((u - cx) / 0.012) ** 2))

    # Top/bottom shrink-wrap fold ridge
    end_seam = np.maximum(np.exp(-((v - 0.08) / 0.025) ** 2), np.exp(-((v - 0.92) / 0.025) ** 2))

    alb = np.empty((h, w, 4), dtype=np.uint8)
    for ch in range(3):
        base = sleeve_rgb[ch] / 255.0 + micro - cell_groove * 0.05
        alb[:, :, ch] = np.clip(base * 255.0, 0, 255).astype(np.uint8)
    alb[:, :, 3] = 255

    # Colored tactical capacity band across middle-bottom
    band_mask = (v > 0.54) & (v < 0.72)
    accent_edge = (v > 0.24) & (v < 0.28)
    for ch in range(3):
        alb[:, :, ch] = np.where(band_mask, int(band_rgb[ch] * 0.88), alb[:, :, ch])
        alb[:, :, ch] = np.where(accent_edge, band_rgb[ch], alb[:, :, ch])

    # Matte label plate
    plate_mask = (u > 0.10) & (u < 0.90) & (v > 0.30) & (v < 0.52)
    for ch in range(3):
        alb[:, :, ch] = np.where(plate_mask, min(255, sleeve_rgb[ch] + 24), alb[:, :, ch])

    draw_text(alb, int(w * 0.13), int(h * 0.34), label, max(2, h // 96), text_rgb)
    draw_text(alb, int(w * 0.14), int(h * 0.57), sub, max(2, h // 110), (22, 24, 26))

    hfield = np.clip(0.75 + micro * 2.5 - cell_groove * 0.45 - end_seam * 0.25, 0.0, 1.0)
    nrm = height_to_normal(hfield, strength=2.2)

    rgh_val = np.clip(0.56 - cell_groove * 0.15 - band_mask.astype(np.float32) * 0.14, 0.28, 0.78)
    r8 = np.clip(rgh_val * 255.0, 0, 255).astype(np.uint8)
    rgh = np.stack([r8, r8, r8, np.full_like(r8, 255)], axis=-1)
    return alb, rgh, nrm


def gen_metal_pbr(size: int = 256, base_rgb=(135, 142, 150), brushed: bool = True):
    rng = np.random.default_rng(99)
    row_var = rng.normal(0.0, 0.035, (size, 1)).astype(np.float32)
    pix_var = rng.normal(0.0, 0.015, (size, size)).astype(np.float32)
    streak = row_var * (1.0 if brushed else 0.25) + pix_var

    alb = np.empty((size, size, 4), dtype=np.uint8)
    for ch in range(3):
        alb[:, :, ch] = np.clip(base_rgb[ch] * (1.0 + streak), 8, 250).astype(np.uint8)
    alb[:, :, 3] = 255

    nrm = height_to_normal(np.clip(0.5 + streak * 1.4, 0.0, 1.0), strength=1.5)
    r_val = np.clip((0.28 if brushed else 0.36) + np.abs(streak) * 0.8, 0.14, 0.55)
    r8 = np.clip(r_val * 255.0, 0, 255).astype(np.uint8)
    rgh = np.stack([r8, r8, r8, np.full_like(r8, 255)], axis=-1)
    return alb, rgh, nrm


def gen_velcro_strap_pbr(size: int = 256, base_rgb=(28, 30, 32), stripe_rgb=(175, 130, 50)):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    weave = 0.5 * np.sin(xx * size * 1.1) + 0.5 * np.cos(yy * size * 0.9)
    n_h = np.clip(0.5 + weave * 0.25, 0.0, 1.0)
    alb = np.empty((size, size, 4), dtype=np.uint8)
    center_stitch = (np.abs(xx - 0.5) < 0.05) | (np.abs(xx - 0.14) < 0.03) | (np.abs(xx - 0.86) < 0.03)
    for ch in range(3):
        col = base_rgb[ch] + weave * 10.0
        col = np.where(center_stitch, stripe_rgb[ch] * 0.65, col)
        alb[:, :, ch] = np.clip(col, 4, 240).astype(np.uint8)
    alb[:, :, 3] = 255
    nrm = height_to_normal(n_h, strength=2.6)
    return alb, nrm


def gen_starlink_dish_pbr(size: int = 256):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32) / size
    grid_x = np.abs(((xx * 6.0) % 1.0) - 0.5)
    grid_y = np.abs(((yy * 4.0) % 1.0) - 0.5)
    seam = (grid_x > 0.46) | (grid_y > 0.46)
    border = (xx < 0.06) | (xx > 0.94) | (yy < 0.06) | (yy > 0.94)
    rng = np.random.default_rng(17)
    grain = rng.normal(0.0, 4.0, (size, size)).astype(np.float32)

    alb = np.empty((size, size, 4), dtype=np.uint8)
    for ch, c_base in enumerate((178, 182, 186)):
        c = c_base + grain - seam.astype(np.float32) * 32.0
        c = np.where(border, 44.0 + grain * 0.5, c)
        alb[:, :, ch] = np.clip(c, 15, 228).astype(np.uint8)
    alb[:, :, 3] = 255
    h = np.clip(0.8 - seam.astype(np.float32) * 0.35 - border.astype(np.float32) * 0.15, 0.0, 1.0)
    nrm = height_to_normal(h, strength=1.8)
    return alb, nrm


# ---------------------------------------------------------------------------
# Blender material & UV-mapped geometry helpers
# ---------------------------------------------------------------------------
def build_pbr_material(
    name: str,
    base_color=(0.5, 0.5, 0.5, 1.0),
    metallic=0.0,
    roughness=0.5,
    alb_img=None,
    rgh_img=None,
    nrm_img=None,
    nrm_strength=0.6,
    emission_color=None,
    emission_strength=0.0,
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
    if rgh_img is not None:
        rtex = nt.nodes.new("ShaderNodeTexImage")
        rtex.image = rgh_img
        nt.links.new(rtex.outputs["Color"], bsdf.inputs["Roughness"])
    if nrm_img is not None:
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = nrm_img
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = float(nrm_strength)
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    if emission_color is not None and emission_strength > 0.0:
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = emission_color
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = float(emission_strength)
    return mat


def _apply_box_uv_to_bm(bm: bmesh.types.BMesh, scale: float = 4.0):
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


def ensure_uv_map(obj, scale: float = 5.0, force: bool = False):
    if obj.type != "MESH" or not obj.data.vertices:
        return
    if force or len(obj.data.uv_layers) == 0:
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        _apply_box_uv_to_bm(bm, scale=scale)
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
    elif obj.data.uv_layers[0].name != "UVMap" and len(obj.data.uv_layers) == 1:
        obj.data.uv_layers[0].name = "UVMap"


def translate_world(obj, world_delta: mathutils.Vector):
    if obj.parent is not None:
        local_delta = obj.parent.matrix_world.inverted().to_3x3() @ world_delta
        obj.location += local_delta
    else:
        obj.location += world_delta
    bpy.context.view_layer.update()


def create_mesh_object(name: str, bm: bmesh.types.BMesh, mat=None, parent=None, uv_scale: float = 5.0):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _apply_box_uv_to_bm(bm, scale=uv_scale)
    me = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    if mat is not None:
        obj.data.materials.append(mat)
    return obj


def add_box(
    name: str,
    center: tuple,
    size: tuple,
    mat=None,
    parent=None,
    bevel: float = 0.0,
    rot_euler: tuple = (0.0, 0.0, 0.0),
    uv_scale: float = 6.0,
):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=size, verts=bm.verts)
    if bevel > 0.0:
        bmesh.ops.bevel(
            bm,
            geom=list(bm.edges),
            offset=min(bevel, min(size) * 0.35),
            segments=2,
            affect="EDGES",
        )
    rot_m = mathutils.Euler(rot_euler, "XYZ").to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=mathutils.Matrix.Translation(center) @ rot_m, verts=bm.verts)
    return create_mesh_object(name, bm, mat=mat, parent=parent, uv_scale=uv_scale)


def add_cylinder(
    name: str,
    p0: tuple,
    p1: tuple,
    r0: float,
    r1: float = None,
    segs: int = 20,
    mat=None,
    parent=None,
    uv_scale: float = 6.0,
):
    if r1 is None:
        r1 = r0
    v0 = mathutils.Vector(p0)
    v1 = mathutils.Vector(p1)
    dv = v1 - v0
    length = max(dv.length, 1e-5)
    mid = (v0 + v1) * 0.5
    q = dv.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    bm = bmesh.new()
    bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segs,
        radius1=r0,
        radius2=r1,
        depth=length,
    )
    bmesh.ops.transform(bm, matrix=mathutils.Matrix.Translation(mid) @ q, verts=bm.verts)
    return create_mesh_object(name, bm, mat=mat, parent=parent, uv_scale=uv_scale)


def add_tube_polyline(
    name: str,
    pts: list,
    radius: float,
    segs: int = 10,
    mat=None,
    parent=None,
):
    """Build single continuous smooth tube mesh along 3D polyline points."""
    bm = bmesh.new()
    rings = []
    vectors = [mathutils.Vector(p) for p in pts]
    for idx, p in enumerate(vectors):
        if idx == 0:
            tan = (vectors[1] - vectors[0]).normalized()
        elif idx == len(vectors) - 1:
            tan = (vectors[-1] - vectors[-2]).normalized()
        else:
            tan = (vectors[idx + 1] - vectors[idx - 1]).normalized()
        rot = tan.to_track_quat("Z", "Y").to_matrix()
        ring = []
        for k in range(segs):
            ang = 2.0 * math.pi * k / segs
            offset = rot @ mathutils.Vector((math.cos(ang) * radius, math.sin(ang) * radius, 0.0))
            ring.append(bm.verts.new(p + offset))
        rings.append(ring)
    for i in range(len(rings) - 1):
        r0, r1 = rings[i], rings[i + 1]
        for k in range(segs):
            kn = (k + 1) % segs
            bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return create_mesh_object(name, bm, mat=mat, parent=parent, uv_scale=8.0)


def add_strap_loop(
    name: str,
    x_center: float,
    y_center: float,
    width_y: float,
    thick: float,
    x_min: float,
    x_max: float,
    z_min: float,
    z_max: float,
    mat_strap,
    mat_buckle=None,
    parent=None,
):
    """Create rectangular rounded Velcro strap hugging a battery box on all 4 sides."""
    pad = 0.0012
    x0, x1 = x_min - pad, x_max + pad
    z0, z1 = z_min - pad, z_max + pad
    # Four tightly mitered panels + top buckle
    w = width_y
    h_box = z1 - z0
    w_box = x1 - x0
    objs = []
    objs.append(add_box(name + "_Top", (0.5 * (x0 + x1), y_center, z1 + thick * 0.5), (w_box + 2 * thick, w, thick), mat_strap, parent, bevel=thick * 0.35))
    objs.append(add_box(name + "_Bot", (0.5 * (x0 + x1), y_center, z0 - thick * 0.5), (w_box + 2 * thick, w, thick), mat_strap, parent, bevel=thick * 0.35))
    objs.append(add_box(name + "_L", (x0 - thick * 0.5, y_center, 0.5 * (z0 + z1)), (thick, w, h_box), mat_strap, parent, bevel=thick * 0.35))
    objs.append(add_box(name + "_R", (x1 + thick * 0.5, y_center, 0.5 * (z0 + z1)), (thick, w, h_box), mat_strap, parent, bevel=thick * 0.35))
    if mat_buckle is not None:
        objs.append(add_box(name + "_Buckle", (x_max - 0.003, y_center, z1 + thick * 0.7), (0.006, w + 0.0025, thick * 1.4), mat_buckle, parent, bevel=thick * 0.25))
    return objs


def find_root_parent():
    for o in bpy.data.objects:
        if o.type == "EMPTY" and o.parent is None and (
            "root" in o.name.lower() or "uman_freestyle" in o.name.lower()
        ):
            return o
    return None


def world_bounds(obj) -> tuple:
    vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
    return (
        mathutils.Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))),
        mathutils.Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs))),
    )


def closest_dist_between(obj, target_objs) -> float:
    vs = [obj.matrix_world @ v.co for v in obj.data.vertices]
    if not vs:
        return 0.0
    pts = list(vs)
    for e in obj.data.edges:
        v0 = obj.matrix_world @ obj.data.vertices[e.vertices[0]].co
        v1 = obj.matrix_world @ obj.data.vertices[e.vertices[1]].co
        pts.append((v0 + v1) * 0.5)
    for poly in obj.data.polygons:
        pts.append(obj.matrix_world @ poly.center)
    sample = pts[::max(1, len(pts) // 160)]
    best = 999.0
    for ref in target_objs:
        if ref == obj or ref.type != "MESH" or not ref.data.polygons:
            continue
        inv = ref.matrix_world.inverted()
        for v in sample:
            ok, loc, _, _ = ref.closest_point_on_mesh(inv @ v)
            if ok:
                best = min(best, ((ref.matrix_world @ loc) - v).length)
    return best


def strip_prior_upgrades():
    to_del = [o for o in bpy.data.objects if o.name.startswith("Upgrade_")]
    for o in to_del:
        bpy.data.objects.remove(o, do_unlink=True)


# ---------------------------------------------------------------------------
# Per-drone upgrade implementations
# ---------------------------------------------------------------------------
def upgrade_composite_plane_skins(preset_key: str):
    """Replace flat Composite_* materials with high-res 1024x1024 panel-lined PBR."""
    palettes = {
        "leleka": {
            "white": ((174, 180, 178), 0.032, (50, 58, 56), (124, 132, 128)),
            "grey": ((128, 136, 134), 0.034, (38, 44, 44), None),
            "dark": ((36, 40, 44), 0.025, (14, 16, 18), None),
        },
        "furia": {
            "white": ((118, 128, 118), 0.030, (36, 42, 38), (195, 118, 32)),
            "grey": ((92, 104, 94), 0.035, (28, 34, 30), (46, 54, 48)),
            "dark": ((34, 38, 40), 0.024, (14, 16, 18), None),
        },
        "chaklun": {
            "white": ((74, 80, 86), 0.028, (22, 24, 28), (190, 92, 28)),
            "grey": ((48, 53, 58), 0.034, (16, 18, 22), (185, 88, 24)),
            "dark": ((28, 31, 35), 0.026, (10, 11, 14), None),
        },
    }[preset_key]

    carb_alb, carb_rgh, carb_nrm = gen_carbon_pbr(512, repeats=18, base_level=0.11)
    im_carb_a = make_packed_image(f"upg_{preset_key}_carb_a", carb_alb, "sRGB")
    im_carb_r = make_packed_image(f"upg_{preset_key}_carb_r", carb_rgh, "Non-Color")
    im_carb_n = make_packed_image(f"upg_{preset_key}_carb_n", carb_nrm, "Non-Color")

    met_alb, met_rgh, met_nrm = gen_metal_pbr(256, (152, 158, 166), brushed=True)
    im_met_a = make_packed_image(f"upg_{preset_key}_met_a", met_alb, "sRGB")
    im_met_r = make_packed_image(f"upg_{preset_key}_met_r", met_rgh, "Non-Color")
    im_met_n = make_packed_image(f"upg_{preset_key}_met_n", met_nrm, "Non-Color")

    for mat in list(bpy.data.materials):
        low = mat.name.lower()
        if "composite_white" in low:
            cfg = palettes["white"]
            a, r, n = gen_composite_aerospace_pbr(1024, *cfg, seed=11)
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.03, roughness=0.64,
                alb_img=make_packed_image(f"upg_{preset_key}_cw_a", a, "sRGB"),
                rgh_img=make_packed_image(f"upg_{preset_key}_cw_r", r, "Non-Color"),
                nrm_img=make_packed_image(f"upg_{preset_key}_cw_n", n, "Non-Color"),
                nrm_strength=0.65,
            )
        elif "composite_grey" in low:
            cfg = palettes["grey"]
            a, r, n = gen_composite_aerospace_pbr(1024, *cfg, seed=23)
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.04, roughness=0.64,
                alb_img=make_packed_image(f"upg_{preset_key}_cg_a", a, "sRGB"),
                rgh_img=make_packed_image(f"upg_{preset_key}_cg_r", r, "Non-Color"),
                nrm_img=make_packed_image(f"upg_{preset_key}_cg_n", n, "Non-Color"),
                nrm_strength=0.72,
            )
        elif "composite_dark" in low or "dark_composite" in low:
            cfg = palettes["dark"]
            a, r, n = gen_composite_aerospace_pbr(1024, *cfg, seed=37)
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.08, roughness=0.58,
                alb_img=make_packed_image(f"upg_{preset_key}_cd_a", a, "sRGB"),
                rgh_img=make_packed_image(f"upg_{preset_key}_cd_r", r, "Non-Color"),
                nrm_img=make_packed_image(f"upg_{preset_key}_cd_n", n, "Non-Color"),
                nrm_strength=0.70,
            )
        elif "carbon" in low:
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.12, roughness=0.38,
                alb_img=im_carb_a, rgh_img=im_carb_r, nrm_img=im_carb_n, nrm_strength=0.75,
            )
        elif "machined_alloy" in low or "alloy_panel" in low:
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.88, roughness=0.28,
                alb_img=im_met_a, rgh_img=im_met_r, nrm_img=im_met_n, nrm_strength=0.5,
            )


def upgrade_chaklun_jet():
    parent = find_root_parent()
    upgrade_composite_plane_skins("chaklun")
    carb_mat = bpy.data.materials.get("Carbon_Weave")
    grey_mat = bpy.data.materials.get("Composite_Grey")
    alloy_mat = bpy.data.materials.get("Machined_Alloy")

    body = bpy.data.objects["Chaklun_Body"]
    wing = bpy.data.objects["Chaklun_Wing"]

    # 1) Fix floating rear V-tail fins + tips by seating inner roots 14mm into Chaklun_Body
    for side in (-1, 1):
        fin = bpy.data.objects.get(f"Chaklun_Fin_{side}")
        tip = bpy.data.objects.get(f"Chaklun_FinTip_{side}")
        if fin:
            # Find the lowest Z inner edge vertices at the fin root
            inv_body = body.matrix_world.inverted()
            fin_vs = [fin.matrix_world @ v.co for v in fin.data.vertices]
            root_vs = sorted(fin_vs, key=lambda v: v.z)[:6]
            root_center = sum(root_vs, mathutils.Vector()) / len(root_vs)
            ok, loc, _, _ = body.closest_point_on_mesh(inv_body @ root_center)
            if ok:
                target_pt = body.matrix_world @ loc
                # Embed inner edge 1.2cm cleanly inside fuselage skin along inward-down normal
                radial = mathutils.Vector((target_pt.x, 0.0, target_pt.z))
                inward = -radial.normalized() * 0.014 if radial.length > 1e-4 else mathutils.Vector((0, 0, -0.014))
                delta = (target_pt + inward) - root_center
                translate_world(fin, delta)
                if tip:
                    translate_world(tip, delta)

                # Sculpted aerodynamic V-tail root fairing cuff
                fmin, fmax = world_bounds(fin)
                fair_cx = target_pt.x - side * 0.004
                fair_cy = 0.5 * (fmin.y + fmax.y)
                fair_cz = target_pt.z + 0.004
                tilt = side * math.radians(-34.0)
                add_box(
                    f"Upgrade_Chaklun_FinRootFairing_{side}",
                    (fair_cx, fair_cy, fair_cz),
                    (0.022, 0.165, 0.036),
                    mat=carb_mat,
                    parent=parent,
                    bevel=0.007,
                    rot_euler=(0.0, tilt, 0.0),
                )

    # 2) Remove all floating WingSeam & spine Seam bars above wing/fuselage (panel lines are now baked in 1024px textures)
    for o in list(bpy.data.objects):
        if o.name.startswith("Chaklun_WingSeam") or o.name.startswith("Chaklun_Seam_"):
            bpy.data.objects.remove(o, do_unlink=True)

    # 3) Snap wingtip NavGreen / NavRed onto Chaklun_Wing tips inside sleek carbon pods
    bpy.context.view_layer.update()
    inv_w = wing.matrix_world.inverted()
    for side, nav_name in ((1, "Chaklun_NavGreen"), (-1, "Chaklun_NavRed")):
        nav = bpy.data.objects.get(nav_name)
        if nav:
            bmin, bmax = world_bounds(nav)
            nc = 0.5 * (bmin + bmax)
            ok, loc, _, _ = wing.closest_point_on_mesh(inv_w @ nc)
            if ok:
                wloc = wing.matrix_world @ loc
                target = mathutils.Vector((side * 0.742, wloc.y, wloc.z))
                translate_world(nav, target - nc)
                # Wingtip protective nav pod seated firmly onto wingtip edge + static wick
                add_box(
                    f"Upgrade_Chaklun_NavPod_{side}",
                    (side * 0.733, wloc.y - 0.012, wloc.z),
                    (0.024, 0.068, 0.020),
                    mat=carb_mat,
                    parent=parent,
                    bevel=0.005,
                )
                add_cylinder(
                    f"Upgrade_Chaklun_StaticWick_{side}",
                    (side * 0.740, wloc.y - 0.044, wloc.z),
                    (side * 0.742, wloc.y - 0.115, wloc.z),
                    0.0018, 0.0010, 8, mat=alloy_mat, parent=parent
                )

    # 4) Flush dorsal SATCOM teardrop + wing actuator fairings + titanium exhaust ring
    ok, loc, _, _ = body.closest_point_on_mesh(body.matrix_world.inverted() @ mathutils.Vector((0.0, -0.24, 0.25)))
    sat_z = (body.matrix_world @ loc).z if ok else 0.088
    add_cylinder(
        "Upgrade_Chaklun_SatcomDome",
        (0.0, -0.24, sat_z - 0.008),
        (0.0, -0.24, sat_z + 0.018),
        0.042, 0.020, 24, mat=grey_mat, parent=parent
    )
    add_cylinder(
        "Upgrade_Chaklun_ExhaustCollar",
        (0.0, -0.805, 0.0),
        (0.0, -0.848, 0.0),
        0.074, 0.068, 28, mat=alloy_mat, parent=parent
    )
    for side in (-1, 1):
        ok, wloc, _, _ = wing.closest_point_on_mesh(inv_w @ mathutils.Vector((side * 0.36, -0.04, -0.10)))
        w_pt = wing.matrix_world @ wloc if ok else mathutils.Vector((side * 0.36, -0.04, -0.015))
        add_box(
            f"Upgrade_Chaklun_ServoFairing_{side}",
            (w_pt.x, w_pt.y, w_pt.z - 0.004),
            (0.020, 0.095, 0.016),
            mat=carb_mat,
            parent=parent,
            bevel=0.004,
        )


def upgrade_furia():
    parent = find_root_parent()
    upgrade_composite_plane_skins("furia")
    carb_mat = bpy.data.materials.get("Carbon_Weave")
    alloy_mat = bpy.data.materials.get("Machined_Alloy")

    body = bpy.data.objects["Furia_Body"]
    wing = bpy.data.objects["Furia_Wing"]

    # 1) Move floating NavGreen / NavRed directly onto outer leading surface of winglets inside carbon pods
    for side, nav_name, wlet_name in (
        (1, "Furia_NavGreen", "Furia_Winglet_1"),
        (-1, "Furia_NavRed", "Furia_Winglet_-1"),
    ):
        nav = bpy.data.objects.get(nav_name)
        wlet = bpy.data.objects.get(wlet_name)
        if nav and wlet:
            wmin, wmax = world_bounds(wlet)
            bmin, bmax = world_bounds(nav)
            nc = 0.5 * (bmin + bmax)
            # Seat flush on outer winglet leading/mid wall (zero gap)
            target = mathutils.Vector((
                (wmax.x if side > 0 else wmin.x) + side * 0.001,
                0.5 * (wmin.y + wmax.y) + 0.012,
                wmin.z + 0.065,
            ))
            translate_world(nav, target - nc)
            add_box(
                f"Upgrade_Furia_NavPod_{side}",
                (target.x - side * 0.009, target.y - 0.010, target.z),
                (0.024, 0.056, 0.020),
                mat=carb_mat,
                parent=parent,
                bevel=0.004,
            )
            # Winglet-to-wing root fillet
            add_box(
                f"Upgrade_Furia_WingletFillet_{side}",
                (side * 0.914, 0.072, wmin.z + 0.006),
                (0.050, 0.145, 0.022),
                mat=carb_mat,
                parent=parent,
                bevel=0.005,
            )

    # 2) Move Furia_Pitot to upper nose spine (clear of Furia_Lens) with solid mounting collar into Furia_Body
    pitot = bpy.data.objects.get("Furia_Pitot")
    if pitot:
        pmin, pmax = world_bounds(pitot)
        pc = 0.5 * (pmin + pmax)
        translate_world(pitot, mathutils.Vector((0.0, 0.610, 0.148)) - pc)
        add_cylinder(
            "Upgrade_Furia_PitotMast",
            (0.0, 0.490, 0.148),
            (0.0, 0.555, 0.148),
            0.007, 0.005, 12, mat=alloy_mat, parent=parent
        )

    # 3) Underwing servo actuator blisters & launch hook (flush against Wing/Body via surface probe)
    inv_f_wing = wing.matrix_world.inverted()
    for side in (-1, 1):
        ok, wloc, _, _ = wing.closest_point_on_mesh(inv_f_wing @ mathutils.Vector((side * 0.54, -0.08, 0.02)))
        wp = wing.matrix_world @ wloc if ok else mathutils.Vector((side * 0.54, -0.08, 0.088))
        add_box(
            f"Upgrade_Furia_ServoPod_{side}",
            (wp.x, wp.y, wp.z - 0.004),
            (0.022, 0.085, 0.018),
            mat=carb_mat,
            parent=parent,
            bevel=0.004,
        )
    add_box(
        "Upgrade_Furia_LaunchSkid",
        (0.0, 0.24, 0.044),
        (0.026, 0.16, 0.014),
        mat=carb_mat,
        parent=parent,
        bevel=0.003,
    )


def upgrade_leleka():
    parent = find_root_parent()
    upgrade_composite_plane_skins("leleka")
    carb_mat = bpy.data.materials.get("Carbon_Weave")
    alloy_mat = bpy.data.materials.get("Machined_Alloy")

    fuse = bpy.data.objects["Leleka_Fuselage"]
    wing = bpy.data.objects["Leleka_Wing"]

    # 1) Wingtip fairing pods wrapping NavGreen / NavRed cleanly to wingtips
    for side, nav_name in ((1, "Leleka_NavGreen"), (-1, "Leleka_NavRed")):
        nav = bpy.data.objects.get(nav_name)
        if nav:
            bmin, bmax = world_bounds(nav)
            nc = 0.5 * (bmin + bmax)
            ok, loc, _, _ = wing.closest_point_on_mesh(wing.matrix_world.inverted() @ nc)
            if ok:
                wloc = wing.matrix_world @ loc
                target = mathutils.Vector((side * 0.996, wloc.y, wloc.z))
                translate_world(nav, target - nc)
                add_box(
                    f"Upgrade_Leleka_NavPod_{side}",
                    (side * 0.990, target.y - 0.012, target.z),
                    (0.022, 0.072, 0.022),
                    mat=carb_mat,
                    parent=parent,
                    bevel=0.005,
                )

    # 2) Strobe base fairing collar connecting Leleka_Strobe flush to fuselage tail cone
    strobe = bpy.data.objects.get("Leleka_Strobe")
    if strobe:
        smin, smax = world_bounds(strobe)
        sc = 0.5 * (smin + smax)
        add_cylinder(
            "Upgrade_Leleka_StrobeCollar",
            (0.0, sc.y + 0.020, sc.z - 0.032),
            (0.0, sc.y, sc.z - 0.004),
            0.014, 0.009, 14, mat=carb_mat, parent=parent
        )

    # 3) V-Tail root fairings + CNC landing-gear strut damper boots
    for side in (-1, 1):
        add_box(
            f"Upgrade_Leleka_VTailFillet_{side}",
            (side * 0.038, -0.445, 0.165),
            (0.028, 0.145, 0.028),
            mat=carb_mat,
            parent=parent,
            bevel=0.005,
            rot_euler=(0.0, side * math.radians(-38.0), 0.0),
        )
        add_cylinder(
            f"Upgrade_Leleka_GearCollar_{side}",
            (side * 0.068, 0.060, 0.078),
            (side * 0.095, 0.060, 0.042),
            0.011, 0.011, 12, mat=alloy_mat, parent=parent
        )


def upgrade_grim7():
    parent = find_root_parent()
    # Replace flat glowing blue battery material (Material.001) cleanly
    batt_alb, batt_rgh, batt_nrm = gen_battery_pbr(
        512, 256, label="6S2P 8000MAH", sub="GRIM-7 TACTICAL",
        sleeve_rgb=(26, 29, 34), band_rgb=(215, 118, 22), text_rgb=(235, 240, 245)
    )
    mat_batt = build_pbr_material(
        "Material.001", (1, 1, 1, 1), metallic=0.06, roughness=0.52,
        alb_img=make_packed_image("upg_grim7_batt_a", batt_alb, "sRGB"),
        rgh_img=make_packed_image("upg_grim7_batt_r", batt_rgh, "Non-Color"),
        nrm_img=make_packed_image("upg_grim7_batt_n", batt_nrm, "Non-Color"),
        nrm_strength=0.6,
    )
    strap_a, strap_n = gen_velcro_strap_pbr(256, (24, 26, 28), (195, 120, 32))
    mat_strap = build_pbr_material(
        "Upgrade_Grim7_StrapMat", (1, 1, 1, 1), metallic=0.04, roughness=0.78,
        alb_img=make_packed_image("upg_grim7_strap_a", strap_a, "sRGB"),
        nrm_img=make_packed_image("upg_grim7_strap_n", strap_n, "Non-Color"),
        nrm_strength=0.7,
    )
    met_a, met_r, met_n = gen_metal_pbr(256, (128, 134, 142), brushed=True)
    mat_alu = build_pbr_material(
        "Upgrade_Grim7_AluMat", (1, 1, 1, 1), metallic=0.88, roughness=0.28,
        alb_img=make_packed_image("upg_grim7_alu_a", met_a, "sRGB"),
        rgh_img=make_packed_image("upg_grim7_alu_r", met_r, "Non-Color"),
        nrm_img=make_packed_image("upg_grim7_alu_n", met_n, "Non-Color"),
    )
    mat_xt60 = build_pbr_material("Upgrade_Grim7_XT60Mat", (0.86, 0.56, 0.04, 1.0), metallic=0.1, roughness=0.42)
    mat_wire_r = build_pbr_material("Upgrade_Grim7_WireR", (0.68, 0.06, 0.06, 1.0), metallic=0.02, roughness=0.45)
    mat_wire_b = build_pbr_material("Upgrade_Grim7_WireB", (0.04, 0.04, 0.05, 1.0), metallic=0.02, roughness=0.45)
    mat_tpu = build_pbr_material("Upgrade_Grim7_TPU", (0.08, 0.09, 0.10, 1.0), metallic=0.05, roughness=0.65)

    # Locate battery mesh on grim7 (was Material.001)
    batt_obj = None
    for o in bpy.data.objects:
        if o.type == "MESH" and o.data.materials and "Material.001" in o.data.materials[0].name:
            batt_obj = o
            break
    if batt_obj:
        ensure_uv_map(batt_obj, scale=6.0, force=True)
        bmin, bmax = world_bounds(batt_obj)
        cx = 0.5 * (bmin.x + bmax.x)
        # Dual woven Velcro straps wrapping snugly around battery box
        for idx, y_frac in enumerate((0.28, 0.72)):
            sy = bmin.y + (bmax.y - bmin.y) * y_frac
            add_strap_loop(
                f"Upgrade_Grim7_Strap{idx}", cx, sy, 0.015, 0.0022,
                bmin.x, bmax.x, bmin.z - 0.002, bmax.z,
                mat_strap, mat_alu, parent=parent
            )
        # XT60 plug & Silicone 12AWG battery leads at rear of battery -> top deck
        add_box(
            "Upgrade_Grim7_XT60",
            (cx - 0.008, bmin.y - 0.008, bmin.z + 0.006),
            (0.014, 0.014, 0.009),
            mat=mat_xt60, parent=parent, bevel=0.0015
        )
        add_tube_polyline(
            "Upgrade_Grim7_LeadR",
            [(cx - 0.005, bmin.y + 0.005, bmin.z + 0.024),
             (cx - 0.012, bmin.y - 0.018, bmin.z + 0.018),
             (cx - 0.008, bmin.y - 0.014, bmin.z + 0.006)],
            0.0024, mat=mat_wire_r, parent=parent
        )
        add_tube_polyline(
            "Upgrade_Grim7_LeadB",
            [(cx + 0.002, bmin.y + 0.005, bmin.z + 0.022),
             (cx + 0.004, bmin.y - 0.016, bmin.z + 0.015),
             (cx - 0.004, bmin.y - 0.014, bmin.z + 0.006)],
            0.0024, mat=mat_wire_b, parent=parent
        )

    # Frame center X=-0.0145, keep rear VTX stub & Immortal-T strictly y < 0.05 (behind FPV cam at y=0.068)
    cx_frame = -0.0145
    # Low-profile CNC camera protective cheek plates hugging lens bay cleanly
    for side in (-1, 1):
        add_box(
            f"Upgrade_Grim7_CamCheek_{side}",
            (cx_frame + side * 0.017, 0.036, 0.005),
            (0.0024, 0.018, 0.014),
            mat=mat_alu, parent=parent, bevel=0.0006
        )
    # Rear TPU mast + VTX lollipop + ELRS Immortal-T dipole embedded solidly in rear deck
    add_box("Upgrade_Grim7_AntMount", (cx_frame, -0.095, 0.012), (0.024, 0.024, 0.020), mat=mat_tpu, parent=parent, bevel=0.002)
    add_cylinder("Upgrade_Grim7_VTXStem", (cx_frame, -0.098, 0.020), (cx_frame, -0.118, 0.068), 0.0022, 0.0020, 10, mat=mat_wire_b, parent=parent)
    add_cylinder("Upgrade_Grim7_VTXCap", (cx_frame, -0.117, 0.062), (cx_frame, -0.123, 0.076), 0.0075, 0.0065, 14, mat=mat_tpu, parent=parent)
    add_cylinder("Upgrade_Grim7_ELRS_T", (cx_frame - 0.048, -0.095, 0.014), (cx_frame + 0.048, -0.095, 0.014), 0.0018, 0.0018, 10, mat=mat_tpu, parent=parent)


def upgrade_grim7m():
    parent = find_root_parent()
    strap_a, strap_n = gen_velcro_strap_pbr(256, (22, 24, 26), (175, 130, 50))
    mat_strap = build_pbr_material(
        "Upgrade_Grim7M_StrapMat", (1, 1, 1, 1), metallic=0.04, roughness=0.78,
        alb_img=make_packed_image("upg_grim7m_strap_a", strap_a, "sRGB"),
        nrm_img=make_packed_image("upg_grim7m_strap_n", strap_n, "Non-Color"),
    )
    met_a, met_r, met_n = gen_metal_pbr(256, (132, 140, 148), brushed=True)
    mat_alu = build_pbr_material(
        "Upgrade_Grim7M_AluMat", (1, 1, 1, 1), metallic=0.90, roughness=0.26,
        alb_img=make_packed_image("upg_grim7m_alu_a", met_a, "sRGB"),
        rgh_img=make_packed_image("upg_grim7m_alu_r", met_r, "Non-Color"),
        nrm_img=make_packed_image("upg_grim7m_alu_n", met_n, "Non-Color"),
    )
    carb_a, carb_r, carb_n = gen_carbon_pbr(512, repeats=16, base_level=0.12)
    mat_carb = build_pbr_material(
        "Upgrade_Grim7M_CarbMat", (1, 1, 1, 1), metallic=0.1, roughness=0.40,
        alb_img=make_packed_image("upg_grim7m_carb_a", carb_a, "sRGB"),
        rgh_img=make_packed_image("upg_grim7m_carb_r", carb_r, "Non-Color"),
        nrm_img=make_packed_image("upg_grim7m_carb_n", carb_n, "Non-Color"),
    )
    mat_bronze = build_pbr_material("Upgrade_Grim7M_BronzeMat", (0.72, 0.45, 0.14, 1.0), metallic=0.92, roughness=0.25)

    # Top deck battery is within Object_4 (x=[-0.036..0.036], y=[-0.08..0.06], z=[0.01..0.072])
    # Wrap battery straps squarely around battery envelope on top plate
    for idx, sy in enumerate((-0.042, 0.012)):
        add_strap_loop(
            f"Upgrade_Grim7M_Strap{idx}", 0.0, sy, 0.016, 0.0024,
            -0.035, 0.035, 0.003, 0.070, mat_strap, mat_alu, parent=parent
        )
    # Protective top carbon rollbar arch + titanium standoffs flanking rear/mid deck (clear of FPV at y=0.12)
    for side in (-1, 1):
        add_cylinder(
            f"Upgrade_Grim7M_Standoff_{side}",
            (side * 0.032, 0.075, -0.010),
            (side * 0.032, 0.075, 0.012),
            0.0032, 0.0032, 10, mat=mat_bronze, parent=parent
        )
        add_box(
            f"Upgrade_Grim7M_CamArmor_{side}",
            (side * 0.024, 0.085, 0.004),
            (0.004, 0.032, 0.022),
            mat=mat_carb, parent=parent, bevel=0.001
        )
    # Center arm cross-brace skid rails mounted solidly under bottom plate
    for side in (-1, 1):
        add_cylinder(
            f"Upgrade_Grim7M_SkidBrace_{side}",
            (side * 0.042, -0.060, -0.012),
            (side * 0.042, 0.065, -0.012),
            0.0035, 0.0035, 10, mat=mat_carb, parent=parent
        )


def upgrade_strila8_or_tactical(is_tactical: bool):
    parent = find_root_parent()
    tag = "Tac" if is_tactical else "Strila8"

    if is_tactical:
        # Distinct dark tactical gunmetal-olive palette for Military FPV so it does not mirror Strila-8
        img0 = bpy.data.images.get("Image_0")
        if img0 is not None:
            arr = read_blender_image_rgba_topdown(img0).astype(np.float32)
            # Shift orange/warm hues into tactical slate-coyote & darken mid-plate to matte stealth carbon
            lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
            arr[:, :, 0] = np.clip(arr[:, :, 0] * 0.72 + lum * 0.14, 0, 255)
            arr[:, :, 1] = np.clip(arr[:, :, 1] * 0.80 + lum * 0.16, 0, 255)
            arr[:, :, 2] = np.clip(arr[:, :, 2] * 0.76 + lum * 0.12, 0, 255)
            replace_existing_image(img0, "Image_0_tac", np.clip(arr, 0, 255).astype(np.uint8), "sRGB")

    # crisp battery wrap overlay around batt_low_DRONE_0
    batt = bpy.data.objects.get("batt_low_DRONE_0")
    carb_a, carb_r, carb_n = gen_carbon_pbr(512, repeats=16, base_level=0.11)
    mat_carb = build_pbr_material(
        f"Upgrade_{tag}_CarbMat", (1, 1, 1, 1), metallic=0.10, roughness=0.40,
        alb_img=make_packed_image(f"upg_{tag}_carb_a", carb_a, "sRGB"),
        rgh_img=make_packed_image(f"upg_{tag}_carb_r", carb_r, "Non-Color"),
        nrm_img=make_packed_image(f"upg_{tag}_carb_n", carb_n, "Non-Color"),
    )
    strap_a, strap_n = gen_velcro_strap_pbr(
        256, (22, 24, 24), (110, 130, 88) if is_tactical else (210, 118, 25)
    )
    mat_strap = build_pbr_material(
        f"Upgrade_{tag}_StrapMat", (1, 1, 1, 1), metallic=0.04, roughness=0.76,
        alb_img=make_packed_image(f"upg_{tag}_strap_a", strap_a, "sRGB"),
        nrm_img=make_packed_image(f"upg_{tag}_strap_n", strap_n, "Non-Color"),
    )
    met_a, met_r, met_n = gen_metal_pbr(256, (118, 124, 132), brushed=True)
    mat_alu = build_pbr_material(
        f"Upgrade_{tag}_AluMat", (1, 1, 1, 1), metallic=0.88, roughness=0.28,
        alb_img=make_packed_image(f"upg_{tag}_alu_a", met_a, "sRGB"),
        rgh_img=make_packed_image(f"upg_{tag}_alu_r", met_r, "Non-Color"),
        nrm_img=make_packed_image(f"upg_{tag}_alu_n", met_n, "Non-Color"),
    )

    if batt:
        bmin, bmax = world_bounds(batt)
        # Dual Velcro straps + buckles directly embracing battery
        for idx, y_frac in enumerate((0.26, 0.74)):
            sy = bmin.y + (bmax.y - bmin.y) * y_frac
            add_strap_loop(
                f"Upgrade_{tag}_Strap{idx}", 0.0, sy, 0.011, 0.0016,
                bmin.x, bmax.x, bmin.z, bmax.z, mat_strap, mat_alu, parent=parent
            )

    # Side CNC camera guard plates touching camera holder cleanly (outboard of lens FOV)
    for side in (-1, 1):
        add_box(
            f"Upgrade_{tag}_CamGuard_{side}",
            (side * 0.0108, 0.041, 0.005),
            (0.0032, 0.020, 0.016),
            mat=mat_alu, parent=parent, bevel=0.0008
        )

    if is_tactical:
        # Distinct frontline tactical armored interceptor silhouette (low-profile open rollcage + CRPA + flared skids):
        olive_a, olive_r, olive_n = gen_composite_aerospace_pbr(
            512, (74, 82, 64), 0.025, (28, 32, 24), stripe_rgb=(172, 138, 62), seed=55
        )
        mat_armor = build_pbr_material(
            "Upgrade_Tac_ArmorMat", (1, 1, 1, 1), metallic=0.04, roughness=0.62,
            alb_img=make_packed_image("upg_tac_armor_a", olive_a, "sRGB"),
            rgh_img=make_packed_image("upg_tac_armor_r", olive_r, "Non-Color"),
            nrm_img=make_packed_image("upg_tac_armor_n", olive_n, "Non-Color"),
        )
        # Fine micro-scale 3K carbon material for open cage struts & skids
        mat_carb = build_pbr_material(
            "Upgrade_Tac_MicroCarbMat", (1, 1, 1, 1), metallic=0.08, roughness=0.44,
            alb_img=make_packed_image("upg_tac_mcarb_a", carb_a, "sRGB"),
            rgh_img=make_packed_image("upg_tac_mcarb_r", carb_r, "Non-Color"),
            nrm_img=make_packed_image("upg_tac_mcarb_n", carb_n, "Non-Color"),
            nrm_strength=0.55,
        )
        # 1) Sleek low-profile ballistic composite top armor cap hovering 3mm over battery on 4 open cage posts (y <= 0.024)
        add_box(
            "Upgrade_Tac_TopShroud",
            (0.0, -0.026, 0.062),
            (0.032, 0.094, 0.0045),
            mat=mat_armor, parent=parent, bevel=0.0018, uv_scale=8.0
        )
        for side in (-1, 1):
            for py in (-0.066, 0.012):
                add_cylinder(
                    f"Upgrade_Tac_CagePost_{side}_{py:+.2f}",
                    (side * 0.014, py, 0.009),
                    (side * 0.014, py, 0.062),
                    0.0022, 0.0020, 8, mat=mat_carb, parent=parent, uv_scale=24.0
                )
        add_cylinder(
            "Upgrade_Tac_CRPA_Dome",
            (0.0, -0.056, 0.064),
            (0.0, -0.056, 0.072),
            0.013, 0.010, 18, mat=mat_armor, parent=parent, uv_scale=8.0
        )
        # 2) Heavy lateral landing rails (flared carbon skid tubes) + diagonal risers outboard of MORKVA warhead
        for side in (-1, 1):
            add_tube_polyline(
                f"Upgrade_Tac_SkidRail_{side}",
                [
                    (side * 0.056, -0.092, -0.036),
                    (side * 0.056, -0.065, -0.044),
                    (side * 0.056, 0.025, -0.044),
                    (side * 0.056, 0.052, -0.036),
                ],
                0.0032, segs=10, mat=mat_carb, parent=parent
            )
            for ry in (-0.065, 0.025):
                add_cylinder(
                    f"Upgrade_Tac_SkidStrut_{side}_{ry:.2f}",
                    (side * 0.034, ry, 0.003),
                    (side * 0.056, ry, -0.045),
                    0.0026, 0.0026, 8, mat=mat_carb, parent=parent, uv_scale=24.0
                )


def upgrade_quad5():
    """Upgrade battery wrap, straps & rear hardware on quad5; NEVER touch Quad5_Warhead_*!"""
    parent = find_root_parent()
    batt_alb, batt_rgh, batt_nrm = gen_battery_pbr(
        512, 256, label="6S 2600MAH", sub="HV COMBAT-FPV",
        sleeve_rgb=(24, 27, 32), band_rgb=(205, 128, 22), text_rgb=(240, 244, 248)
    )
    mat_batt = build_pbr_material(
        "battery_wrap", (1, 1, 1, 1), metallic=0.06, roughness=0.52,
        alb_img=make_packed_image("upg_q5_batt_a", batt_alb, "sRGB"),
        rgh_img=make_packed_image("upg_q5_batt_r", batt_rgh, "Non-Color"),
        nrm_img=make_packed_image("upg_q5_batt_n", batt_nrm, "Non-Color"),
    )
    strap_a, strap_n = gen_velcro_strap_pbr(256, (22, 24, 26), (208, 128, 24))
    mat_strap = build_pbr_material(
        "Upgrade_Quad5_StrapMat", (1, 1, 1, 1), metallic=0.04, roughness=0.78,
        alb_img=make_packed_image("upg_q5_strap_a", strap_a, "sRGB"),
        nrm_img=make_packed_image("upg_q5_strap_n", strap_n, "Non-Color"),
    )
    mat_alu = bpy.data.materials.get("aluminium_gunmetal") or build_pbr_material(
        "Upgrade_Quad5_Alu", (0.45, 0.48, 0.52, 1), metallic=0.9, roughness=0.25
    )

    # Fix missing UVs on Object_334 (battery_wrap; forward axis on quad5 is +X!)
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.name.startswith("Quad5_Warhead") and o.data.materials:
            if o.data.materials[0].name == "battery_wrap":
                ensure_uv_map(o, scale=14.0, force=True)
                bmin, bmax = world_bounds(o)
                # Note quad5 forward = +X, so straps run perpendicular to X around (Y, Z)
                for idx, sx in enumerate((bmin.x + (bmax.x - bmin.x) * 0.28, bmin.x + (bmax.x - bmin.x) * 0.72)):
                    pad = 0.0012
                    y0, y1 = bmin.y - pad, bmax.y + pad
                    z0, z1 = bmin.z - pad, bmax.z + pad
                    add_box(f"Upgrade_Quad5_Strap{idx}_Top", (sx, 0.5*(y0+y1), z1+0.0012), (0.011, (y1-y0)+0.004, 0.0022), mat_strap, parent, bevel=0.0007)
                    add_box(f"Upgrade_Quad5_Strap{idx}_L", (sx, y0-0.0011, 0.5*(z0+z1)), (0.011, 0.0022, (z1-z0)), mat_strap, parent, bevel=0.0007)
                    add_box(f"Upgrade_Quad5_Strap{idx}_R", (sx, y1+0.0011, 0.5*(z0+z1)), (0.011, 0.0022, (z1-z0)), mat_strap, parent, bevel=0.0007)
                    add_box(f"Upgrade_Quad5_Buckle{idx}", (sx, y1-0.002, z1+0.0015), (0.013, 0.005, 0.0032), mat_alu, parent, bevel=0.0005)
                break

    # Compact rear ELRS T-antenna strictly behind fpv_cam_pos (x_b < -0.05) + mounting stalk
    mat_tpu = bpy.data.materials.get("black_plastic") or mat_alu
    add_box("Upgrade_Quad5_RearELRSMount", (-0.056, 0.0, 0.036), (0.034, 0.012, 0.008), mat=mat_tpu, parent=parent, bevel=0.0015)
    add_cylinder("Upgrade_Quad5_RearELRS", (-0.072, -0.042, 0.040), (-0.072, 0.042, 0.040), 0.0018, 0.0018, 8, mat=mat_tpu, parent=parent)


def upgrade_pisun_vtol():
    """Lift crushed black mid-body albedo & add crisp rings, bolts, pitot, and launch skids."""
    parent = find_root_parent()
    fus = bpy.data.objects["pisun_fuselage"]

    # Lift dark crushed mid-body shadow zones while preserving olive nosecone & markings
    img0 = bpy.data.images.get("Image_0")
    if img0 is not None:
        arr = read_blender_image_rgba_topdown(img0).astype(np.float32) / 255.0
        lum = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
        # Lift shadows cleanly around [0..0.14] up toward [0.14..0.24] charcoal-olive composite
        lift = np.clip((0.18 - lum) * 0.72, 0.0, 0.14)
        arr[:, :, 0] = np.clip(arr[:, :, 0] + lift * 0.90, 0, 1)
        arr[:, :, 1] = np.clip(arr[:, :, 1] + lift * 0.98, 0, 1)
        arr[:, :, 2] = np.clip(arr[:, :, 2] + lift * 0.88, 0, 1)
        replace_existing_image(img0, "Image_0_vtol", np.clip(arr * 255.0, 0, 255).astype(np.uint8), "sRGB")

    carb_a, carb_r, carb_n = gen_carbon_pbr(512, repeats=16, base_level=0.14)
    mat_carb = build_pbr_material(
        "Upgrade_VTOL_CarbMat", (1, 1, 1, 1), metallic=0.12, roughness=0.40,
        alb_img=make_packed_image("upg_vtol_carb_a", carb_a, "sRGB"),
        rgh_img=make_packed_image("upg_vtol_carb_r", carb_r, "Non-Color"),
        nrm_img=make_packed_image("upg_vtol_carb_n", carb_n, "Non-Color"),
    )
    met_a, met_r, met_n = gen_metal_pbr(256, (148, 154, 162), brushed=True)
    mat_alu = build_pbr_material(
        "Upgrade_VTOL_AluMat", (1, 1, 1, 1), metallic=0.88, roughness=0.28,
        alb_img=make_packed_image("upg_vtol_alu_a", met_a, "sRGB"),
        rgh_img=make_packed_image("upg_vtol_alu_r", met_r, "Non-Color"),
        nrm_img=make_packed_image("upg_vtol_alu_n", met_n, "Non-Color"),
    )
    mat_band = build_pbr_material("Upgrade_VTOL_BandMat", (0.76, 0.44, 0.08, 1.0), metallic=0.18, roughness=0.42)
    mat_glass = build_pbr_material("Upgrade_VTOL_SeekerMat", (0.06, 0.14, 0.22, 1.0), metallic=0.25, roughness=0.08)

    # Probe fuselage hull radius along 45-degree diagonal (avoiding 0/90/180/270 motor arms!)
    inv_f = fus.matrix_world.inverted()
    for z_ring, h_ring, r_extra, m_use, tag in (
        (0.085, 0.010, 0.0012, mat_band, "NoseCollar"),
        (0.020, 0.012, 0.0012, mat_carb, "MidClamp"),
        (-0.075, 0.010, 0.0012, mat_alu, "AftClamp"),
    ):
        ok, loc, _, _ = fus.closest_point_on_mesh(inv_f @ mathutils.Vector((0.065, 0.065, z_ring)))
        r_hull = (fus.matrix_world @ loc).xy.length if ok else 0.048
        add_cylinder(
            f"Upgrade_VTOL_{tag}",
            (0.0, 0.0, z_ring - h_ring * 0.5),
            (0.0, 0.0, z_ring + h_ring * 0.5),
            r_hull + r_extra, r_hull + r_extra, 32, mat=m_use, parent=parent
        )
        # Flush hex bolts seated onto clamping ring
        for b in range(4):
            ang = math.radians(45 + 90 * b)
            bx = math.cos(ang) * (r_hull + r_extra)
            by = math.sin(ang) * (r_hull + r_extra)
            add_cylinder(
                f"Upgrade_VTOL_{tag}_Bolt{b}",
                (bx * 0.94, by * 0.94, z_ring),
                (bx * 1.03, by * 1.03, z_ring),
                0.0022, 0.0022, 6, mat=mat_alu, parent=parent
            )

    # Seeker collar / optical window embedded around waist z=0.055 facing +Y (well below FPV cam at z=+0.125)
    ok, loc, _, _ = fus.closest_point_on_mesh(inv_f @ mathutils.Vector((0.0, 0.10, 0.055)))
    y_hull = (fus.matrix_world @ loc).y if ok else 0.053
    add_cylinder("Upgrade_VTOL_SeekerBezel", (0, y_hull - 0.008, 0.055), (0, y_hull + 0.003, 0.055), 0.015, 0.013, 18, mat=mat_alu, parent=parent)
    add_cylinder("Upgrade_VTOL_SeekerLens", (0, y_hull - 0.004, 0.055), (0, y_hull + 0.004, 0.055), 0.011, 0.010, 18, mat=mat_glass, parent=parent)

    # Lower fin landing shoes directly on the 4 bottom cruciform tail fins (0, 90, 180, -90 deg at z=-0.205, r=0.042)
    for idx, ang_deg in enumerate((0, 90, 180, -90)):
        ang = math.radians(ang_deg)
        fx, fy = math.cos(ang) * 0.041, math.sin(ang) * 0.041
        add_box(f"Upgrade_VTOL_FinShoe_{idx}", (fx, fy, -0.206), (0.008, 0.022, 0.016), mat=mat_carb, parent=parent, bevel=0.0025, rot_euler=(0, 0, ang + math.pi * 0.5))


def upgrade_baba_yaga():
    """Add Starlink Mini phased-array dish, dual CRPA domes, EO/IR turret & weathered olive PBR."""
    parent = find_root_parent()
    olive_a, olive_r, olive_n = gen_composite_aerospace_pbr(512, (84, 96, 70), 0.030, (28, 34, 24), stripe_rgb=(176, 146, 56), seed=71)
    mil_a, mil_r, mil_n = gen_composite_aerospace_pbr(512, (62, 72, 54), 0.025, (22, 26, 20), None, seed=82)
    carb_a, carb_r, carb_n = gen_carbon_pbr(512, repeats=18, base_level=0.11)
    met_a, met_r, met_n = gen_metal_pbr(256, (138, 144, 150), brushed=True)
    sl_a, sl_n = gen_starlink_dish_pbr(256)

    for mat in list(bpy.data.materials):
        low = mat.name.lower()
        if "olive_drab" in low:
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.06, roughness=0.54,
                alb_img=make_packed_image("upg_by_ol_a", olive_a, "sRGB"),
                rgh_img=make_packed_image("upg_by_ol_r", olive_r, "Non-Color"),
                nrm_img=make_packed_image("upg_by_ol_n", olive_n, "Non-Color"),
                nrm_strength=0.68,
            )
        elif "military_green" in low:
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.06, roughness=0.52,
                alb_img=make_packed_image("upg_by_mg_a", mil_a, "sRGB"),
                rgh_img=make_packed_image("upg_by_mg_r", mil_r, "Non-Color"),
                nrm_img=make_packed_image("upg_by_mg_n", mil_n, "Non-Color"),
            )
        elif "carbon" in low:
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.12, roughness=0.38,
                alb_img=make_packed_image("upg_by_cb_a", carb_a, "sRGB"),
                rgh_img=make_packed_image("upg_by_cb_r", carb_r, "Non-Color"),
                nrm_img=make_packed_image("upg_by_cb_n", carb_n, "Non-Color"),
            )
        elif "alloy_panel" in low:
            build_pbr_material(
                mat.name, (1, 1, 1, 1), metallic=0.88, roughness=0.28,
                alb_img=make_packed_image("upg_by_mt_a", met_a, "sRGB"),
                rgh_img=make_packed_image("upg_by_mt_r", met_r, "Non-Color"),
                nrm_img=make_packed_image("upg_by_mt_n", met_n, "Non-Color"),
            )

    mat_carb = bpy.data.materials.get("Carbon_Weave")
    mat_alu = bpy.data.materials.get("Alloy_Panel")
    mat_star = build_pbr_material(
        "Upgrade_BabaYaga_StarlinkMat", (1, 1, 1, 1), metallic=0.05, roughness=0.36,
        alb_img=make_packed_image("upg_by_sl_a", sl_a, "sRGB"),
        nrm_img=make_packed_image("upg_by_sl_n", sl_n, "Non-Color"),
    )
    mat_crpa = build_pbr_material("Upgrade_BabaYaga_CRPA", (0.76, 0.77, 0.74, 1.0), metallic=0.04, roughness=0.38)
    mat_glass = build_pbr_material("Upgrade_BabaYaga_Optic", (0.04, 0.12, 0.18, 1.0), metallic=0.25, roughness=0.06)

    # 1) Elevated carbon bridge deck cleanly spanning between left & right Battery_Case_±1 above Avionics_Top (z=0.237)
    for px in (-0.075, 0.075):
        for py in (-0.235, -0.095):
            add_cylinder(
                f"Upgrade_BY_BridgePost_{px:+.2f}_{py:+.2f}",
                (px, py, 0.232),
                (px, py, 0.422),
                0.008, 0.008, 12, mat=mat_alu, parent=parent
            )
    add_box("Upgrade_BY_BridgePlate", (0.0, -0.165, 0.424), (0.18, 0.18, 0.008), mat=mat_carb, parent=parent, bevel=0.002)

    # 2) Starlink Mini phased-array terminal mounted on tilted CNC gimbal bracket atop bridge
    add_box(
        "Upgrade_BY_StarlinkBezel",
        (0.0, -0.165, 0.448),
        (0.240, 0.195, 0.022),
        mat=mat_carb, parent=parent, bevel=0.008, rot_euler=(math.radians(-10.0), 0.0, 0.0)
    )
    add_box(
        "Upgrade_BY_StarlinkRadome",
        (0.0, -0.165, 0.453),
        (0.224, 0.178, 0.016),
        mat=mat_star, parent=parent, bevel=0.005, rot_euler=(math.radians(-10.0), 0.0, 0.0), uv_scale=4.2
    )

    # 3) Dual CRPA anti-jamming domes on front center avionics corridor (x=±0.052, y=+0.175, z=0.237..0.275)
    for side in (-1, 1):
        add_cylinder(f"Upgrade_BY_CRPA_Base_{side}", (side * 0.052, 0.175, 0.232), (side * 0.052, 0.175, 0.252), 0.028, 0.026, 20, mat=mat_alu, parent=parent)
        add_cylinder(f"Upgrade_BY_CRPA_Dome_{side}", (side * 0.052, 0.175, 0.252), (side * 0.052, 0.175, 0.276), 0.026, 0.018, 20, mat=mat_crpa, parent=parent)

    # 4) Armored forward chin EO/IR stabilized dual-optic turret (y=+0.28..+0.36, embedded into Avionics_Body)
    add_box("Upgrade_BY_TurretYoke", (0.0, 0.255, 0.110), (0.110, 0.065, 0.056), mat=mat_alu, parent=parent, bevel=0.008)
    add_cylinder("Upgrade_BY_TurretBall", (0.0, 0.295, 0.040), (0.0, 0.295, 0.088), 0.048, 0.048, 22, mat=mat_carb, parent=parent, uv_scale=20.0)
    add_cylinder("Upgrade_BY_TurretLensMain", (-0.018, 0.335, 0.064), (-0.018, 0.348, 0.064), 0.016, 0.015, 16, mat=mat_glass, parent=parent)
    add_cylinder("Upgrade_BY_TurretLensIR", (0.020, 0.335, 0.064), (0.020, 0.348, 0.064), 0.011, 0.010, 16, mat=mat_glass, parent=parent)

    # 5) Snap floating Nav_Green_Arm / Nav_Red_Arm onto actual outer hex arms (Arm_0..Arm_5) so nothing floats in rotor air
    arm_objs = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Arm_") and "Cable" not in o.name and "Clamp" not in o.name]
    for side, nav_name in ((1, "Nav_Green_Arm"), (-1, "Nav_Red_Arm")):
        nav = bpy.data.objects.get(nav_name)
        if nav and arm_objs:
            nmin, nmax = world_bounds(nav)
            nc = 0.5 * (nmin + nmax)
            best_pt = None
            best_d = 999.0
            for aobj in arm_objs:
                ok, loc, _, _ = aobj.closest_point_on_mesh(aobj.matrix_world.inverted() @ nc)
                if ok:
                    wp = aobj.matrix_world @ loc
                    d = (wp - nc).length
                    if d < best_d:
                        best_d = d
                        best_pt = wp
            if best_pt is not None and best_d > 0.002:
                translate_world(nav, best_pt - nc)


def upgrade_uman(size_inch: int):
    """Upgrade Uman_Freestyle_3/5/7 keeping motors, props, ducts & dimmed LED compatibility."""
    root_name = f"Uman_Freestyle_{size_inch}"
    parent = bpy.data.objects.get(root_name) or find_root_parent()

    # Crisp 512x512 carbon + normal + roughness
    carb_a, carb_r, carb_n = gen_carbon_pbr(512, repeats=16, base_level=0.16)
    batt_a, batt_r, batt_n = gen_battery_pbr(
        512, 256,
        label=("4S 1300MAH" if size_inch == 3 else "6S 1550MAH" if size_inch == 5 else "6S 4200MAH"),
        sub="UMAN FPV PRO",
        sleeve_rgb=(56, 60, 66),  # matte tactical graphite so *0.55 runtime multiplier reads sleek charcoal!
        band_rgb=(210, 132, 34),
        text_rgb=(238, 242, 248),
    )
    met_a, met_r, met_n = gen_metal_pbr(256, (176, 182, 190), brushed=True)

    # Ducts / accent nylon micro-grain preserving original green/orange/blue color signature
    rng = np.random.default_rng(size_inch)

    for im in list(bpy.data.images):
        ln = im.name.lower()
        if "battery" in ln:
            replace_existing_image(im, im.name, batt_a, "sRGB")
        elif "carbon_normal" in ln:
            replace_existing_image(im, im.name, carb_n, "Non-Color")
        elif "carbon" in ln:
            replace_existing_image(im, im.name, carb_a, "sRGB")
        elif "metal" in ln:
            replace_existing_image(im, im.name, met_a, "sRGB")
        elif "accent" in ln:
            orig_acc = read_blender_image_rgba_topdown(im).astype(np.float32)
            mr = float(np.mean(orig_acc[:, :, 0]))
            mg = float(np.mean(orig_acc[:, :, 1]))
            mb = float(np.mean(orig_acc[:, :, 2]))
            grain = rng.normal(0.0, 7.0, (256, 256)).astype(np.float32)
            acc_rgba = np.empty((256, 256, 4), dtype=np.uint8)
            acc_rgba[:, :, 0] = np.clip(mr + grain, 6, 250).astype(np.uint8)
            acc_rgba[:, :, 1] = np.clip(mg + grain, 6, 250).astype(np.uint8)
            acc_rgba[:, :, 2] = np.clip(mb + grain, 6, 250).astype(np.uint8)
            acc_rgba[:, :, 3] = 255
            replace_existing_image(im, im.name, acc_rgba, "sRGB")

    # Add normal maps cleanly to existing carbon & battery materials
    mat_carb = bpy.data.materials.get(f"{root_name}_carbon")
    mat_batt = bpy.data.materials.get(f"{root_name}_battery")
    mat_met = bpy.data.materials.get(f"{root_name}_metal")
    mat_dark = bpy.data.materials.get(f"{root_name}_dark")
    mat_acc = bpy.data.materials.get(f"{root_name}_accent")

    if mat_batt is not None:
        im_bn = make_packed_image(f"upg_u{size_inch}_bn", batt_n, "Non-Color")
        im_br = make_packed_image(f"upg_u{size_inch}_br", batt_r, "Non-Color")
        nt = mat_batt.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        t_n = nt.nodes.new("ShaderNodeTexImage"); t_n.image = im_bn
        nm = nt.nodes.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = 0.65
        t_r = nt.nodes.new("ShaderNodeTexImage"); t_r.image = im_br
        nt.links.new(t_n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
        nt.links.new(t_r.outputs["Color"], bsdf.inputs["Roughness"])

    # Ensure battery box looks clean and strapped rather than plain boxy yellow/red block
    batt_obj = bpy.data.objects.get(f"{root_name}_battery")
    strap_a, strap_n = gen_velcro_strap_pbr(256, (64, 68, 72), (220, 140, 38))
    mat_strap = build_pbr_material(
        f"{root_name}_strap", (1, 1, 1, 1), metallic=0.04, roughness=0.72,
        alb_img=make_packed_image(f"upg_u{size_inch}_strap_a", strap_a, "sRGB"),
        nrm_img=make_packed_image(f"upg_u{size_inch}_strap_n", strap_n, "Non-Color"),
    )
    if batt_obj:
        bmin, bmax = world_bounds(batt_obj)
        s = 0.72 if size_inch == 3 else 0.90 if size_inch == 5 else 1.15
        for idx, frac in enumerate((0.28, 0.72)):
            sy = bmin.y + (bmax.y - bmin.y) * frac
            add_strap_loop(
                f"Upgrade_U{size_inch}_Strap{idx}",
                0.5 * (bmin.x + bmax.x), sy, 0.009 * s, 0.0014 * s,
                bmin.x, bmax.x, bmin.z, bmax.z, mat_strap, mat_met, parent=parent
            )
        # XT60 plug embedded flush at back-right of battery + TPU rear SMA antenna stub + Immortal-T
        add_box(
            f"Upgrade_U{size_inch}_XT60",
            (bmax.x + 0.002 * s, bmin.y + 0.010 * s, bmin.z + 0.007 * s),
            (0.010 * s, 0.011 * s, 0.007 * s),
            mat=mat_acc, parent=parent, bevel=0.001 * s
        )
        # Rear VTX antenna & ELRS T mounted solidly into carbon deck (z <= bmin.z - 0.008)
        ry = bmin.y - 0.010 * s
        rz = bmin.z - 0.004 * s
        add_box(f"Upgrade_U{size_inch}_AntMount", (0.0, ry + 0.004 * s, rz), (0.018 * s, 0.022 * s, 0.014 * s), mat=mat_acc, parent=parent, bevel=0.002 * s)
        add_cylinder(f"Upgrade_U{size_inch}_VTXMast", (0.0, ry - 0.003 * s, rz + 0.004 * s), (0.0, ry - 0.014 * s, rz + 0.036 * s), 0.002 * s, 0.0018 * s, 10, mat=mat_dark, parent=parent)
        add_cylinder(f"Upgrade_U{size_inch}_VTXCap", (0.0, ry - 0.012 * s, rz + 0.029 * s), (0.0, ry - 0.016 * s, rz + 0.039 * s), 0.0055 * s, 0.0045 * s, 14, mat=mat_acc, parent=parent)
        add_cylinder(f"Upgrade_U{size_inch}_ELRS_T", (-0.038 * s, ry + 0.004 * s, rz + 0.001 * s), (0.038 * s, ry + 0.004 * s, rz + 0.001 * s), 0.0016 * s, 0.0016 * s, 8, mat=mat_dark, parent=parent)

        if size_inch == 7:
            # 7-inch Long-Range M10 GPS fin & puck behind battery anchored down into top plate
            add_box("Upgrade_U7_GPSPuck", (0.0, bmin.y - 0.022, bmin.z + 0.010), (0.022, 0.022, 0.009), mat=mat_dark, parent=parent, bevel=0.0025)
            add_box("Upgrade_U7_GPSFin", (0.0, bmin.y - 0.018, bmin.z - 0.002), (0.008, 0.024, 0.022), mat=mat_acc, parent=parent, bevel=0.002)


# ---------------------------------------------------------------------------
# Audit & Export Driver
# ---------------------------------------------------------------------------
def audit_model(label: str):
    bpy.context.view_layer.update()
    all_meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("propeller")]
    key_parts = ("Chaklun_Fin_1", "Chaklun_Fin_-1", "Chaklun_NavGreen", "Chaklun_NavRed", "Furia_NavGreen", "Furia_NavRed", "Furia_Pitot")
    max_gap = 0.0
    key_logs = []
    for o in all_meshes:
        if o.name.startswith("Upgrade_") or any(k in o.name for k in ("NavGreen", "NavRed", "Nav_", "Chaklun_Fin_", "Chaklun_Seam_", "Leleka_Strobe", "Furia_Pitot")):
            d_any = closest_dist_between(o, [m for m in all_meshes if m != o])
            if o.name in key_parts:
                key_logs.append(f"{o.name}={d_any:.4f}m")
            if d_any > 0.003:
                _AUDIT_ISSUES.append(f"{label}:{o.name} floating gap={d_any:.4f}m")
            max_gap = max(max_gap, d_any)
    extra = (" key=[" + ", ".join(key_logs) + "]") if key_logs else ""
    print(f"[AUDIT] {label}: meshes={len(all_meshes)}, max_gap={max_gap:.4f}m, images={len(bpy.data.images)}{extra}")


def process_one(rel_path: str, backup_name: str, upgrade_fn):
    out_path = os.path.normpath(os.path.join(ASSETS, rel_path))
    bak_path = os.path.join(DEFAULT_BACKUP, backup_name)
    src_path = bak_path if os.path.isfile(bak_path) else out_path
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src_path)
    strip_prior_upgrades()
    upgrade_fn()
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.name.startswith("propeller"):
            ensure_uv_map(o)
    audit_model(backup_name)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        use_selection=False,
        export_yup=True,
        export_apply=False,
        export_image_format="AUTO",
        export_materials="EXPORT",
    )
    cleanup_temp_pngs()
    print(f"[EXPORT] OK -> {out_path}")


def main():
    jobs = [
        ("Drones/ua_norm/grim7.glb", "grim7.glb", upgrade_grim7),
        ("Drones/ua_norm/grim7m.glb", "grim7m.glb", upgrade_grim7m),
        ("Drones/ua_norm/strila8.glb", "strila8.glb", lambda: upgrade_strila8_or_tactical(False)),
        ("Drones/ua_norm/quad5_custom.glb", "quad5_custom.glb", upgrade_quad5),
        ("Drones/ua_norm/pisun_vtol.glb", "pisun_vtol.glb", upgrade_pisun_vtol),
        ("Drones/ua_norm/tactical_uav.glb", "tactical_uav.glb", lambda: upgrade_strila8_or_tactical(True)),
        ("Drones/ua_norm/baba_yaga.glb", "baba_yaga.glb", upgrade_baba_yaga),
        ("Drones/ua_norm/leleka_100.glb", "leleka_100.glb", upgrade_leleka),
        ("Drones/ua_norm/furia_a1sm.glb", "furia_a1sm.glb", upgrade_furia),
        ("Drones/ua_norm/chaklun_jet.glb", "chaklun_jet.glb", upgrade_chaklun_jet),
        ("UmanFPV/drones/Uman_Freestyle_3.glb", "Uman_Freestyle_3.glb", lambda: upgrade_uman(3)),
        ("UmanFPV/drones/Uman_Freestyle_5.glb", "Uman_Freestyle_5.glb", lambda: upgrade_uman(5)),
        ("UmanFPV/drones/Uman_Freestyle_7.glb", "Uman_Freestyle_7.glb", lambda: upgrade_uman(7)),
    ]
    for rel, bak, fn in jobs:
        process_one(rel, bak, fn)

    print("=== BLENDER CONTACT AUDIT ===")
    if _AUDIT_ISSUES:
        for iss in _AUDIT_ISSUES:
            print("ISSUE:", iss)
    else:
        print("ALL_OK: zero floating gaps > 3mm")


if __name__ == "__main__":
    main()
