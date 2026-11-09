from PIL import Image, ImageDraw
import os

base = r'C:\Users\USER_UA\Desktop\Новий симулятор\qa_shots\diag\drones'
w, h = 480, 270
sheet = Image.new('RGB', (w * 4, h * 3), (20, 22, 20))
draw = ImageDraw.Draw(sheet)
for i in range(12):
    path = os.path.join(base, f'p{i}.png')
    if not os.path.exists(path):
        continue
    im = Image.open(path).convert('RGB').resize((w, h), Image.LANCZOS)
    x = (i % 4) * w
    y = (i // 4) * h
    sheet.paste(im, (x, y))
    draw.rectangle([x, y, x + w - 1, y + h - 1], outline=(120, 200, 150))
    draw.text((x + 8, y + 6), f'P{i}', fill=(255, 220, 120))
out = os.path.join(base, 'contact_sheet.png')
sheet.save(out)
print(out)
