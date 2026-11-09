import sys
import numpy as np
from PIL import Image

p = sys.argv[1]
img = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32) / 255.0
h, w = img.shape[:2]
r, g, b = img[..., 0], img[..., 1], img[..., 2]
sky = (b > r + 0.06) & (b > 0.35)
green = (g > r + 0.03) & (g > b + 0.03) & (g > 0.10)
bark = (r > g + 0.03) & (g > b + 0.02) & (r > 0.08) & (r < 0.55) & (r * 1.15 < g + 0.25)
print(f"{p} {w}x{h}")
print(f"sky={sky.mean()*100:.1f}% green={green.mean()*100:.2f}% bark={bark.mean()*100:.2f}%")
for band in range(0, h, 120):
    sl = slice(band, min(band + 120, h))
    print(f"  band {band:4d}-{band+119:4d} sky={sky[sl].mean()*100:5.1f}% "
          f"green={green[sl].mean()*100:5.2f}% bark={bark[sl].mean()*100:5.2f}%")
