"""Cleaner 'after' PNGs: fully cover old labels before redrawing them larger."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "current", "mobile")
OUT = os.path.join(ROOT, "after")
os.makedirs(OUT, exist_ok=True)

FONT = "C:/Windows/Fonts/segoeui.ttf"
AMBER = (226, 185, 106, 255)
GREEN = (188, 213, 155, 255)
WHITE = (232, 240, 233, 255)
CHIP = (12, 30, 22, 245)
PANEL = (6, 16, 12, 255)


def font(size):
    return ImageFont.truetype(FONT, size)


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")


def save(img, name):
    img.convert("RGB").save(os.path.join(OUT, name + ".png"))


def relabel_cy(img, x, cy, width, text, size=27, color=WHITE):
    """Cover the whole old row with panel colour, then draw the larger label."""
    d = ImageDraw.Draw(img, "RGBA")
    y0, y1 = cy - 32, cy + 38
    d.rectangle((x - 6, y0, x + width, y1), fill=PANEL)
    d.text((x, cy - 17), text, fill=color, font=font(size))


def chip(img, box, text, accent, size=22):
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius=12, fill=CHIP, outline=accent, width=2)
    f = font(size)
    bb = d.textbbox((0, 0), text, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text((x0 + (x1 - x0 - tw) // 2, y0 + (y1 - y0 - th) // 2 - bb[1]),
           text, fill=accent, font=f)


def cta_glow(img, box, color=AMBER):
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow, "RGBA")
    gd.rounded_rectangle(box, radius=16, outline=(*color[:3], 190), width=10)
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(9)))
    ImageDraw.Draw(img, "RGBA").rounded_rectangle(box, radius=14, outline=color, width=4)


def uniform_button(img, box, color=GREEN):
    ImageDraw.Draw(img, "RGBA").rounded_rectangle(box, radius=14, outline=(*color[:3], 220), width=3)


chips = [
    ((1792, 18, 1950, 64), "РЕКОРДИ", AMBER),
    ((1970, 18, 2043, 64), "UA", GREEN),
    ((2050, 18, 2192, 64), "ELRS: НЕМАЄ", GREEN),
    ((2198, 18, 2328, 64), "ВХІД: —", GREEN),
]
for name in ["main", "play", "controls", "rates", "hangar", "settings"]:
    img = load(name)
    for box, text, col in chips:
        chip(img, box, text, col)
    save(img, name)

img = Image.open(os.path.join(OUT, "play.png")).convert("RGBA")
cta_glow(img, (880, 918, 1475, 992))
save(img, "play")

img = Image.open(os.path.join(OUT, "controls.png")).convert("RGBA")
relabel_cy(img, 1035, 233, 420, "ОСНОВНІ КАНАЛИ СТІКІВ", 27, AMBER)
for cy, text in [(290, "КРЕН (ROLL)"), (360, "ТАНГАЖ (PITCH)"),
                 (430, "ГАЗ (THROTTLE)"), (500, "РИСКАННЯ (YAW)")]:
    relabel_cy(img, 1035, cy, 270, text, 27)
relabel_cy(img, 1035, 627, 430, "БОЙОВІ ФУНКЦІЇ, СКИД ТА ПІДРИВ", 27, AMBER)
for cy, text in [(665, "АРМУВАННЯ ДВИГУНІВ (ARM)"),
                 (745, "СКИД БОЄПРИПАСУ (DROP)"),
                 (825, "ПІДРИВ ДРОНА / БЧ (ДЕТОНАТЕ)")]:
    relabel_cy(img, 1035, cy, 550, text, 27)
save(img, "controls")

img = Image.open(os.path.join(OUT, "rates.png")).convert("RGBA")
for cy, text in [(205, "ROLL RATE: 667 deg/s"), (275, "ROLL EXPO: 0.20"),
                 (355, "PITCH RATE: 667 deg/s"), (420, "PITCH EXPO: 0.20"),
                 (505, "YAW RATE: 667 deg/s"), (575, "YAW EXPO: 0.20")]:
    relabel_cy(img, 1190, cy, 480, text, 27)
save(img, "rates")

img = Image.open(os.path.join(OUT, "controls.png")).convert("RGBA")
uniform_button(img, (40, 825, 1000, 880))
save(img, "controls")
img = Image.open(os.path.join(OUT, "rates.png")).convert("RGBA")
uniform_button(img, (1200, 830, 2280, 890))
save(img, "rates")
img = Image.open(os.path.join(OUT, "hangar.png")).convert("RGBA")
uniform_button(img, (60, 1000, 1160, 1060))
save(img, "hangar")

for n in ["main", "play", "controls", "rates", "hangar", "settings"]:
    print("after", n)
