import sys
import numpy as np
from PIL import Image

p = sys.argv[1]
img = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32) / 255.0
h, w = img.shape[:2]
r, g, b = img[..., 0], img[..., 1], img[..., 2]
sky = (b > r + 0.06) & (b > 0.35)
# olive / leaf: green above blue clearly, g>=r slightly, not too bright
leaf = (g > b + 0.05) & (r > g - 0.035) & (g < 0.55) & (b < 0.30)
bright_leaf = (g > r + 0.04) & (g > b + 0.05) & (g > 0.12)
dark = (~sky) & (r < 0.06) & (g < 0.06) & (b < 0.06)
print(f"{p} {w}x{h} leaf={leaf.mean()*100:.2f}% bright_leaf={bright_leaf.mean()*100:.2f}% "
      f"dark={dark.mean()*100:.2f}%")
lum = img.mean(axis=2)
for band in range(0, h, 120):
    sl = slice(band, min(band + 120, h))
    ns = img[sl][~sky[sl]]
    mc = ns.mean(axis=0) if len(ns) else np.zeros(3)
    print(f"  band {band:4d}-{band+119:4d} leaf={leaf[sl].mean()*100:5.2f}% "
          f"bright_leaf={bright_leaf[sl].mean()*100:5.2f}% dark={dark[sl].mean()*100:5.2f}% "
          f"nonsky=({mc[0]:.2f},{mc[1]:.2f},{mc[2]:.2f})")
