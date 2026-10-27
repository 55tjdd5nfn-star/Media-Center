import os
from PIL import Image, ImageDraw

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "MediaCenter", "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(OUT, exist_ok=True)

SIZE = 1024

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def draw_master():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    top = (48, 64, 196)
    bottom = (16, 180, 168)
    radius = int(SIZE * 0.22)

    grad = Image.new("RGB", (SIZE, SIZE))
    gd = ImageDraw.Draw(grad)
    for y in range(SIZE):
        gd.line([(0, y), (SIZE, y)], fill=lerp(top, bottom, y / SIZE))
    mask = Image.new("L", (SIZE, SIZE), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    cx, cy = SIZE / 2, SIZE / 2

    s = SIZE * 0.30
    tri = [
        (cx - s * 0.55, cy - s * 0.62),
        (cx - s * 0.55, cy + s * 0.62),
        (cx + s * 0.72, cy),
    ]
    d.polygon(tri, fill=(255, 255, 255, 255))

    nx, ny = int(SIZE * 0.72), int(SIZE * 0.70)
    d.ellipse([nx - 26, ny - 8, nx + 26, ny + 30], fill=(255, 255, 255, 255))
    d.rectangle([nx + 14, ny - 130, nx + 30, ny + 10], fill=(255, 255, 255, 255))
    d.polygon([(nx + 14, ny - 130), (nx + 92, ny - 96), (nx + 92, ny - 58), (nx + 30, ny - 88)],
              fill=(255, 255, 255, 255))
    return img

SIZES = [
    ("icon_16_16.png", 16), ("icon_16_16@2x.png", 32),
    ("icon_32_32.png", 32), ("icon_32_32@2x.png", 64),
    ("icon_128_128.png", 128), ("icon_128_128@2x.png", 256),
    ("icon_256_256.png", 256), ("icon_256_256@2x.png", 512),
    ("icon_512_512.png", 512), ("icon_512_512@2x.png", 1024),
]

master = draw_master()
for name, px in SIZES:
    master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
print("wrote", len(SIZES), "icons to", OUT)
