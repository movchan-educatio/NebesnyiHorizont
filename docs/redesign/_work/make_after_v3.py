"""Final clean 'after' images. Whole text columns are covered, then labels redrawn."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "current", "mobile")
OUT = os.path.join(ROOT, "after")

FONT = "C:/Windows/Fonts/segoeui.ttf"
AMBER = (226, 185, 106, 255)
GREEN = (188, 213, 155, 255)
WHITE = (232, 240, 233, 255)
CHIP = (12, 30, 22, 245)
PANEL = (6, 16, 12, 255)


def f(size):
    return ImageFont.truetype(FONT, size)


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")


def save(img, name):
    img.convert("RGB").save(os.path.join(OUT, name + ".png"))


def chip(img, box, text, accent, size=22):
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius=12, fill=CHIP, outline=accent, width=2)
    ft = f(size)
    bb = d.textbbox((0, 0), text, font=ft)
    d.text((x0 + (x1 - x0 - (bb[2] - bb[0])) // 2,
            y0 + (y1 - y0 - (bb[3] - bb[1])) // 2 - bb[1]), text, fill=accent, font=ft)


# chips on every screen
chip_defs = [
    ((1792, 18, 1950, 64), "РЕКОРДИ", AMBER),
    ((1970, 18, 2043, 64), "UA", GREEN),
    ((2050, 18, 2192, 64), "ELRS: НЕМАЄ", GREEN),
    ((2198, 18, 2328, 64), "ВХІД: —", GREEN),
]
for name in ["main", "play", "controls", "rates", "hangar", "settings"]:
    img = load(name)
    for box, text, col in chip_defs:
        chip(img, box, text, col)
    save(img, name)

# CTA emphasis on play
img = Image.open(os.path.join(OUT, "play.png")).convert("RGBA")
glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
ImageDraw.Draw(glow, "RGBA").rounded_rectangle((880, 918, 1475, 992), radius=16,
                                               outline=(*AMBER[:3], 190), width=10)
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(9)))
ImageDraw.Draw(img, "RGBA").rounded_rectangle((880, 918, 1475, 992), radius=14, outline=AMBER, width=4)
save(img, "play")

# Controls: cover the two text columns completely, then redraw larger labels
img = Image.open(os.path.join(OUT, "controls.png")).convert("RGBA")
d = ImageDraw.Draw(img, "RGBA")
d.rectangle((1030, 205, 1318, 545), fill=PANEL)
d.text((1035, 222), "ОСНОВНІ КАНАЛИ СТІКІВ", fill=AMBER, font=f(27))
for cy, text in [(290, "КРЕН (ROLL)"), (360, "ТАНГАЖ (PITCH)"),
                 (430, "ГАЗ (THROTTLE)"), (500, "РИСКАННЯ (YAW)")]:
    d.text((1035, cy - 17), text, fill=WHITE, font=f(27))

d.rectangle((1030, 600, 1620, 995), fill=PANEL)
d.text((1035, 612), "БОЙОВІ ФУНКЦІЇ, СКИД ТА ПІДРИВ", fill=AMBER, font=f(27))
for cy, text in [(665, "АРМУВАННЯ ДВИГУНІВ (ARM)"),
                 (745, "СКИД БОЄПРИПАСУ (DROP)"),
                 (825, "ПІДРИВ ДРОНА / БЧ (ДЕТОНАТЕ)")]:
    d.text((1035, cy - 17), text, fill=WHITE, font=f(27))
d.text((1035, 915), "РЕЖИМИ ПОЛЬОТУ ТА АСИСТЕНТИ", fill=AMBER, font=f(27))
d.text((1035, 960), "ЦИКЛ РЕЖИМІВ (CYCLE MODES)", fill=WHITE, font=f(27))
d.rounded_rectangle((40, 825, 1000, 880), radius=14, outline=(*GREEN[:3], 220), width=3)
save(img, "controls")

# Rates: cover the rate label column, redraw larger
img = Image.open(os.path.join(OUT, "rates.png")).convert("RGBA")
d = ImageDraw.Draw(img, "RGBA")
d.rectangle((1185, 185, 1720, 620), fill=PANEL)
for cy, text in [(205, "ROLL RATE: 667 deg/s"), (275, "ROLL EXPO: 0.20"),
                 (355, "PITCH RATE: 667 deg/s"), (420, "PITCH EXPO: 0.20"),
                 (505, "YAW RATE: 667 deg/s"), (575, "YAW EXPO: 0.20")]:
    d.text((1190, cy - 17), text, fill=WHITE, font=f(27))
d.rounded_rectangle((1200, 830, 2280, 890), radius=14, outline=(*GREEN[:3], 220), width=3)
save(img, "rates")

# Hangar: uniform button outline
img = Image.open(os.path.join(OUT, "hangar.png")).convert("RGBA")
ImageDraw.Draw(img, "RGBA").rounded_rectangle((60, 1000, 1160, 1060), radius=14,
                                              outline=(*GREEN[:3], 220), width=3)
save(img, "hangar")

print("done")
