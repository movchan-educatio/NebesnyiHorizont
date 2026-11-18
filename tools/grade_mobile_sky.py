"""Grade the existing baked sky panoramas into a cinematic golden-hour sky.

The shipped mobile panorama (sky_static.png) is a midday blue sky with a white
sun.  BigLevel.gd sets warm per-map sun colours, but the baked sky overrides
that cue and makes every map read as flat daylight.  This script recolours the
SAME real panorama (no generated/AI art) into a warm low-sun sky with deeper
blue at the zenith, an amber horizon and a soft golden sun.  The result keeps
the original cloud shapes and baked sun azimuth, so align_sky_to_sun() stays
correct and there is zero extra per-frame cost.

Usage: python tools/grade_mobile_sky.py
Outputs: Assets/textures/sky_static_golden.png, sky_mountains_golden.png
"""

from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    ("sky_static.png", "sky_static_golden.png"),
    ("sky_mountains.png", "sky_mountains_golden.png"),
]


def smoothstep(t: np.ndarray) -> np.ndarray:
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def grade(src: Path, dst: Path) -> None:
    img = Image.open(src).convert("RGB")
    arr = np.asarray(img, dtype=np.float32) / 255.0
    h, w, _ = arr.shape

    # Upper hemisphere: zenith deep blue -> horizon warm amber.
    upper = arr[: h // 2]
    t = smoothstep(np.linspace(0.0, 1.0, upper.shape[0])[:, None, None])
    zenith = np.array([0.66, 0.78, 1.00], dtype=np.float32)
    horizon = np.array([1.26, 0.96, 0.72], dtype=np.float32)
    grade_rgb = zenith[None, None, :] * (1.0 - t) + horizon[None, None, :] * t

    # Warm the baked sun and take the highlight off pure white.
    lum = upper.mean(axis=2, keepdims=True)
    sun_mask = smoothstep((lum - 0.55) / 0.35) * smoothstep((0.85 - t) / 0.5)
    sun_rgb = np.array([1.10, 0.92, 0.66], dtype=np.float32)[None, None, :]
    grade_rgb = grade_rgb * (1.0 - sun_mask) + sun_rgb * sun_mask
    highlight_rolloff = 1.0 - 0.20 * sun_mask

    out_upper = upper * grade_rgb * highlight_rolloff

    # Lower hemisphere is hidden by terrain; keep it as a warm ground tone so
    # reflections and the horizon seam stay coherent.
    lower = arr[h // 2 :]
    ground = np.array([0.82, 0.70, 0.56], dtype=np.float32)[None, None, :]
    out_lower = np.clip(lower * ground * 0.82, 0.0, 1.0)

    out = np.concatenate([np.clip(out_upper, 0.0, 1.0), out_lower], axis=0)
    Image.fromarray((out * 255.0 + 0.5).astype(np.uint8), "RGB").save(dst)
    print(f"[SKY_GRADE] {src.name} -> {dst.name} {w}x{h}")


def main() -> None:
    tex_dir = ROOT / "Assets" / "textures"
    for src_name, dst_name in SOURCES:
        grade(tex_dir / src_name, tex_dir / dst_name)


if __name__ == "__main__":
    main()
