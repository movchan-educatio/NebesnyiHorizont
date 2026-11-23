"""Generate 'after' PNGs from the owner's real mobile-menu screenshots.
This is a design proposal only: the game is not modified."""
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
DARK = (6, 16, 12, 255)
CHIP = (12, 30, 22, 245)


def font(size):
    return ImageFont.truetype(FONT, size)


def load(name):
    return Image.open(os.path.join(SRC, name + ".png")).convert("RGBA")


def save(img, name):
    img.convert("RGB").save(os.path.join(OUT, name + ".png"))
    print("after", name)


def relabel(img, box, text, size=27, color=WHITE, bg=DARK, anchor="lt"):
    """Cover the original small label and redraw it larger."""
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = box[0], box[1] - 9, box[2], box[3] + 15
    d.rectangle((x0, y0, x1, y1), fill=bg)
    f = font(size)
    x, y = x0 + 2, y0 + 4
    if anchor == "mt":
        bb = d.textbbox((0, 0), text, font=f)
        x = x0 + (x1 - x0 - (bb[2] - bb[0])) // 2
    d.text((x, y), text, fill=color, font=f)


def chip(img, box, text, accent=GREEN, size=22):
    """Rebuild a status chip: solid readable background, brighter text/border."""
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = box
    d.rounded_rectangle(box, radius=12, fill=CHIP, outline=accent, width=2)
    f = font(size)
    bb = d.textbbox((0, 0), text, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text((x0 + (x1 - x0 - tw) // 2, y0 + (y1 - y0 - th) // 2 - bb[1]),
           text, fill=accent, font=f)


def cta_glow(img, box, color=AMBER):
    """Emphasize the existing primary CTA without adding a new control."""
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow, "RGBA")
    gd.rounded_rectangle(box, radius=16, outline=(*color[:3], 190), width=10)
    glow = glow.filter(ImageFilter.GaussianBlur(9))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle(box, radius=14, outline=color, width=4)


def uniform_button(img, box, color=GREEN):
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle(box, radius=14, outline=(*color[:3], 220), width=3)


# ---- 1. Chips: main + play -------------------------------------------------
chips = [
    ((1792, 18, 1950, 64), "РЕКОРДИ", AMBER),
    ((1970, 18, 2043, 64), "UA", GREEN),
    ((2050, 18, 2192, 64), "ELRS: НЕМАЄ", GREEN),
    ((2198, 18, 2328, 64), "ВХІД: —", GREEN),
]
for name in ["main", "play", "controls", "rates", "hangar", "settings"]:
    img = load(name)
    for box, text, col in chips:
        # top-right chips are present on every mobile screen
        chip(img, box, text, col, 22)
    save(img, name)

# ---- 2. Primary CTA on 'play' ---------------------------------------------
img = Image.open(os.path.join(OUT, "play.png")).convert("RGBA")
cta_glow(img, (880, 918, 1475, 992))
save(img, "play")

# ---- 3. Font size: controls ------------------------------------------------
img = Image.open(os.path.join(OUT, "controls.png")).convert("RGBA")
relabel(img, (1030, 218, 1420, 252), "ОСНОВНІ КАНАЛИ СТІКІВ", 27, AMBER, DARK)
for y, text in [
    (282, "КРЕН (ROLL)"),
    (352, "ТАНГАЖ (PITCH)"),
    (422, "ГАЗ (THROTTLE)"),
    (492, "РИСКАННЯ (YAW)"),
]:
    relabel(img, (1030, y, 1310, y + 38), text, 27, WHITE, DARK)
relabel(img, (1030, 612, 1450, 646), "БОЙОВІ ФУНКЦІЇ, СКИД ТА ПІДРИВ", 27, AMBER, DARK)
for y, text in [
    (655, "АРМУВАННЯ ДВИГУНІВ (ARM)"),
    (735, "СКИД БОЄПРИПАСУ (DROP)"),
    (815, "ПІДРИВ ДРОНА / БЧ (ДЕТОНАТЕ)"),
]:
    relabel(img, (1030, y, 1600, y + 38), text, 27, WHITE, DARK)
save(img, "controls")

# ---- 4. Font size: rates ---------------------------------------------------
img = Image.open(os.path.join(OUT, "rates.png")).convert("RGBA")
for y, text in [
    (194, "ROLL RATE: 667 deg/s"),
    (280, "ROLL EXPO: 0.20"),
    (352, "PITCH RATE: 667 deg/s"),
    (418, "PITCH EXPO: 0.20"),
    (505, "YAW RATE: 667 deg/s"),
    (570, "YAW EXPO: 0.20"),
]:
    relabel(img, (1190, y, 1700, y + 40), text, 27, WHITE, DARK)
save(img, "rates")

# ---- 5. Button uniformity: compare strip ----------------------------------
img = Image.open(os.path.join(OUT, "controls.png")).convert("RGBA")
uniform_button(img, (40, 825, 1000, 880))
save(img, "controls")
img = Image.open(os.path.join(OUT, "rates.png")).convert("RGBA")
uniform_button(img, (1200, 830, 2280, 890))
save(img, "rates")
img = Image.open(os.path.join(OUT, "hangar.png")).convert("RGBA")
uniform_button(img, (60, 1000, 1160, 1060))
save(img, "hangar")

print("done")
