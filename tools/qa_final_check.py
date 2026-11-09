import os
import numpy as np
from PIL import Image

ROOT = r"C:\Users\USER_UA\Desktop\Новий симулятор"
V = os.path.join(ROOT, "qa_shots", "vegetation")
F = os.path.join(ROOT, "qa_shots", "final")


def load(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32) / 255.0


def stats(p):
    img = load(p)
    h, w = img.shape[:2]
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    sky = (b > r + 0.06) & (b > 0.35)
    leaf = (g > b + 0.05) & (r > g - 0.035) & (g < 0.55) & (b < 0.30)
    dark = (~sky) & (r < 0.06) & (g < 0.06) & (b < 0.06)
    low = img[int(h * 0.55):]
    low_leaf = ((low[..., 1] > low[..., 2] + 0.05)
                & (low[..., 0] > low[..., 1] - 0.035)).mean() * 100
    print(f"{os.path.basename(p):24s} leaf={leaf.mean()*100:5.1f}% "
          f"dark={dark.mean()*100:4.1f}% lower_leaf={low_leaf:5.1f}%")


print("== final screenshots")
for name in ["VillageLevel.png", "IndustrialLevel.png", "SteppeLevel.png",
             "WetlandsLevel.png", "VillageLevel_LOW.png"]:
    p = os.path.join(F, name)
    if os.path.exists(p):
        stats(p)
    else:
        print("MISSING", name)

print("== vegetation shots")
for name in ["tree_close.png", "aerial_village.png", "hero_oak_sway_a.png"]:
    p = os.path.join(V, name)
    if os.path.exists(p):
        stats(p)

a = load(os.path.join(V, "hero_oak_sway_a.png"))
b = load(os.path.join(V, "hero_oak_sway_b.png"))
d = np.abs(a - b).mean(axis=2)
print(f"hero sway delta overall={d.mean():.5f} center={d[150:600, 350:950].mean():.5f} "
      f"pixels>0.03={(d > 0.03).mean()*100:.2f}%")
