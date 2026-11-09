import os
import numpy as np
from PIL import Image

QA = r"C:\Users\USER_UA\Desktop\Новий симулятор\qa_shots\vegetation"

for f in ["oak_a", "pine_a", "oak_hero", "grass_clump"]:
    img = np.asarray(Image.open(os.path.join(QA, f + ".png")).convert("RGB"),
                     dtype=np.float32) / 255.0
    h, w = img.shape[:2]
    print(f"\n== {f} {w}x{h}")
    # sky mask: bluish
    sky = (img[..., 2] > img[..., 0] + 0.06) & (img[..., 2] > 0.35)
    # trunk-ish: warm brown
    warm = (img[..., 0] > img[..., 1] + 0.02) & (img[..., 1] > img[..., 2] + 0.02) \
           & (img[..., 0] < 0.75) & (img[..., 0] > 0.06)
    # bright gray blades (grass preview)
    gray = (img[..., 0] > 0.6) & (abs(img[..., 0] - img[..., 1]) < 0.12) \
           & (abs(img[..., 1] - img[..., 2]) < 0.12)
    for band in range(0, h, 75):
        sl = slice(band, min(band + 75, h))
        s = sky[sl].mean() * 100
        wr = warm[sl].mean() * 100
        g = gray[sl].mean() * 100
        # mean color of non-sky pixels
        ns = img[sl][~sky[sl]]
        mc = ns.mean(axis=0) if len(ns) else np.zeros(3)
        print(f"  band {band:4d}-{band+74:4d} sky={s:5.1f}% warm={wr:5.1f}% "
              f"gray={g:5.1f}% nonsky_mean=({mc[0]:.2f},{mc[1]:.2f},{mc[2]:.2f})")
