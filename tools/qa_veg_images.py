"""Quantitative QA for the generated vegetation previews and atlases.

For each render: sky/ground split, fraction of leaf-green pixels, bark-brown
pixels, and vertical extent of the tree.  For the sway pair: mean pixel delta.
For the atlases: per-cell alpha coverage (a cell must be 25-70% covered).
"""
import os
import sys

import numpy as np

QA = r"C:\Users\USER_UA\Desktop\Новий симулятор\qa_shots\vegetation"
ASSETS = r"C:\Users\USER_UA\Desktop\Новий симулятор\GodotDrone-master\Assets\frontline\vegetation"


def load(path):
    from PIL import Image
    img = Image.open(path).convert("RGBA")
    return np.asarray(img, dtype=np.float32) / 255.0


def report(name, img):
    h, w = img.shape[:2]
    rgb = img[..., :3]
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # leaf green: g clearly above r and b
    leaf = (g > r + 0.06) & (g > b + 0.05) & (g > 0.12)
    bark = (r > g + 0.04) & (g > b + 0.01) & (r > 0.10) & (r < 0.6)
    rows = np.any(leaf, axis=1)
    if np.any(rows):
        idx = np.where(rows)[0]
        top = h - idx.max() - 1
        bottom = h - idx.min() - 1
    else:
        top = bottom = -1
    print(f"{name:16s} leaf={leaf.mean()*100:5.1f}% bark={bark.mean()*100:5.1f}% "
          f"leaf_rows={int(top)}..{int(bottom)} (of {h})")


def report_grass(img):
    rgb = img[..., :3]
    bright = (rgb[..., 0] > 0.30) & (rgb[..., 1] > 0.30) & (rgb[..., 2] > 0.30)
    rows = np.any(bright, axis=1)
    if np.any(rows):
        idx = np.where(rows)[0]
        top = idx.min()
        bottom = idx.max()
    else:
        top = bottom = -1
    print(f"grass_clump      bright={bright.mean()*100:5.1f}% "
          f"rows={int(top)}..{int(bottom)} (of {img.shape[0]})")


for f in ["oak_a", "pine_a", "oak_hero"]:
    p = os.path.join(QA, f + ".png")
    if os.path.exists(p):
        report(f, load(p))

report_grass(load(os.path.join(QA, "grass_clump.png")))

a = load(os.path.join(QA, "oak_hero.png"))
b = load(os.path.join(QA, "oak_hero_sway.png"))
delta = np.abs(a[..., :3] - b[..., :3]).mean()
print(f"oak_hero sway delta = {delta*1000:.2f} /1000 (should be > 2)")

for name in ["leaf_atlas", "pine_atlas"]:
    img = load(os.path.join(ASSETS, name + ".png"))
    h, w = img.shape[:2]
    alpha = img[..., 3]
    solid = alpha > 0.5
    rgb = img[..., :3]
    mean_col = rgb[solid].mean(axis=0) if np.any(solid) else np.zeros(3)
    print(f"{name}: alpha coverage {alpha.mean()*100:.1f}% "
          f"solid RGB=({mean_col[0]:.2f},{mean_col[1]:.2f},{mean_col[2]:.2f})")
    for cy in range(2):
        for cx in range(2):
            cell = alpha[cy * h // 2:(cy + 1) * h // 2,
                         cx * w // 2:(cx + 1) * w // 2]
            print(f"  cell {cx},{cy}: {cell.mean()*100:5.1f}%")
