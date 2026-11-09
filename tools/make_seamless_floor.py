from PIL import Image
import os

BASE = os.path.join("Assets", "frontline", "industrial_hall")
OUT_PREFIX = os.path.join(BASE, "concrete_floor_seamless")


def mirrored_2x2(img, normal=False):
    w, h = img.size
    tl = img
    tr = img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    bl = img.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    br = img.transpose(Image.Transpose.ROTATE_180)
    if normal:
        tr = tr.copy()
        tr.putdata([(255 - r, g, b) for r, g, b in tr.getdata()])
        bl = bl.copy()
        bl.putdata([(r, 255 - g, b) for r, g, b in bl.getdata()])
        br = br.copy()
        br.putdata([(255 - r, 255 - g, b) for r, g, b in br.getdata()])
    canvas = Image.new("RGB", (w * 2, h * 2))
    canvas.paste(tl, (0, 0))
    canvas.paste(tr, (w, 0))
    canvas.paste(bl, (0, h))
    canvas.paste(br, (w, h))
    return canvas.resize((w, h), Image.Resampling.LANCZOS)


src_paths = {
    "diff": os.path.join(BASE, "concrete_floor_damaged_01_diff.jpg"),
    "rough": os.path.join(BASE, "concrete_floor_damaged_01_rough.jpg"),
    "nor_gl": os.path.join(BASE, "concrete_floor_damaged_01_nor_gl.jpg"),
}
for key, path in src_paths.items():
    image = Image.open(path).convert("RGB")
    out = f"{OUT_PREFIX}_{key}.jpg"
    mirrored_2x2(image, normal=(key == "nor_gl")).save(
        out, quality=92, subsampling=0)
    print(out, Image.open(out).size)
