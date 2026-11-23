from PIL import Image, ImageDraw, ImageFont
import os

base = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(os.path.dirname(base), "current", "mobile")
font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 18)

for name in ["controls", "rates", "play", "main", "hangar"]:
    img = Image.open(os.path.join(src, name + ".png")).convert("RGBA")
    draw = ImageDraw.Draw(img, "RGBA")
    for x in range(0, img.width, 100):
        draw.line([(x, 0), (x, img.height)], fill=(255, 80, 80, 100), width=1)
        draw.text((x + 3, 3), str(x), fill=(255, 220, 80, 255), font=font)
    for y in range(0, img.height, 100):
        draw.line([(0, y), (img.width, y)], fill=(255, 80, 80, 100), width=1)
        draw.text((3, y + 3), str(y), fill=(255, 220, 80, 255), font=font)
    img.convert("RGB").save(os.path.join(base, name + "_grid.jpg"), quality=88)
    print("grid", name)
