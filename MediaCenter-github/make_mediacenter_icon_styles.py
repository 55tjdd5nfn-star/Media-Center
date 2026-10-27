import os
from PIL import Image, ImageDraw, ImageFont

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(BASE), "MediaCenter-icon-styles")
os.makedirs(OUT, exist_ok=True)
SIZE = 1024
RADIUS = int(SIZE * 0.22)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(top, bottom, diagonal=False):
    grad = Image.new("RGB", (SIZE, SIZE))
    gd = ImageDraw.Draw(grad)
    for y in range(SIZE):
        gd.line([(0, y), (SIZE, y)], fill=lerp(top, bottom, y / SIZE))
    if diagonal:

        g2 = Image.new("RGB", (SIZE, SIZE))
        d2 = ImageDraw.Draw(g2)
        for x in range(SIZE):
            d2.line([(x, 0), (x, SIZE)], fill=lerp(top, bottom, x / SIZE))
        grad = Image.blend(grad, g2, 0.5)
    return grad

def rounded_mask():
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=RADIUS, fill=255)
    return mask

def base_with(bg):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    img.paste(bg, (0, 0), rounded_mask())
    return img

def play_triangle(d, cx, cy, s, fill=(255, 255, 255, 255)):
    d.polygon([(cx - s * 0.55, cy - s * 0.62), (cx - s * 0.55, cy + s * 0.62),
               (cx + s * 0.72, cy)], fill=fill)

def music_note(d, nx, ny, scale=1.0, fill=(255, 255, 255, 255)):
    d.ellipse([nx - 26 * scale, ny - 8 * scale, nx + 26 * scale, ny + 30 * scale], fill=fill)
    d.rectangle([nx + 14 * scale, ny - 130 * scale, nx + 30 * scale, ny + 10 * scale], fill=fill)
    d.polygon([(nx + 14 * scale, ny - 130 * scale), (nx + 92 * scale, ny - 96 * scale),
               (nx + 92 * scale, ny - 58 * scale), (nx + 30 * scale, ny - 88 * scale)], fill=fill)

def style_a():
    """Sunset pop: hot pink top -> indigo -> deep purple bottom."""
    img = base_with(gradient((255, 77, 141), (76, 44, 178), diagonal=True))
    d = ImageDraw.Draw(img)
    play_triangle(d, SIZE / 2 - 20, SIZE / 2 - 30, SIZE * 0.32)
    music_note(d, int(SIZE * 0.70), int(SIZE * 0.72), scale=0.9)
    return img

def style_b():
    """Glass bubble: indigo/pink blobs, frosted white circle, pink play."""
    bg = Image.new("RGB", (SIZE, SIZE), (38, 32, 110))
    d0 = ImageDraw.Draw(bg, "RGBA")
    d0.ellipse([-200, -200, 620, 620], fill=(255, 77, 141, 255))
    d0.ellipse([500, 480, 1250, 1230], fill=(0, 190, 180, 255))
    d0.ellipse([380, -120, 900, 400], fill=(150, 90, 255, 220))
    img = base_with(bg)
    d = ImageDraw.Draw(img, "RGBA")

    d.ellipse([SIZE * 0.14, SIZE * 0.14, SIZE * 0.86, SIZE * 0.86],
              fill=(255, 255, 255, 92), outline=(255, 255, 255, 200), width=6)
    play_triangle(d, SIZE / 2 - 10, SIZE / 2, SIZE * 0.26, fill=(255, 77, 141, 255))
    return img

def style_c():
    """Vinyl pink: dark charcoal, pink record with grooves, white play."""
    img = base_with(Image.new("RGB", (SIZE, SIZE), (28, 26, 34)))
    d = ImageDraw.Draw(img, "RGBA")
    cx, cy = SIZE / 2, SIZE / 2
    r = SIZE * 0.38
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 77, 141, 255))
    for rr in (r * 0.82, r * 0.62, r * 0.42):
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=(255, 255, 255, 70), width=5)
    d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=(28, 26, 34, 255))
    play_triangle(d, cx + 12, cy, SIZE * 0.20)
    return img

def style_d():
    """Wave bars: teal/indigo gradient, pink + purple equaliser bars, white play."""
    img = base_with(gradient((16, 120, 170), (60, 40, 160), diagonal=True))
    d = ImageDraw.Draw(img, "RGBA")
    bars = [(0.20, 0.42, (255, 77, 141)), (0.32, 0.62, (255, 255, 255)),
            (0.44, 0.34, (190, 120, 255)), (0.56, 0.55, (255, 77, 141)),
            (0.68, 0.30, (255, 255, 255)), (0.80, 0.48, (190, 120, 255))]
    bw = SIZE * 0.075
    for fx, fh, col in bars:
        x = SIZE * fx
        h = SIZE * fh
        d.rounded_rectangle([x - bw / 2, SIZE * 0.78 - h, x + bw / 2, SIZE * 0.78],
                            radius=int(bw / 2), fill=col + (255,))
    play_triangle(d, SIZE / 2, SIZE * 0.32, SIZE * 0.20)
    return img

STYLES = {"a-sunset-pop": style_a, "b-glass-bubble": style_b,
          "c-vinyl-pink": style_c, "d-wave-bars": style_d}
SIZES = [("icon_16_16.png", 16), ("icon_16_16@2x.png", 32),
         ("icon_32_32.png", 32), ("icon_32_32@2x.png", 64),
         ("icon_128_128.png", 128), ("icon_128_128@2x.png", 256),
         ("icon_256_256.png", 256), ("icon_256_256@2x.png", 512),
         ("icon_512_512.png", 512), ("icon_512_512@2x.png", 1024)]

masters = {}
for name, fn in STYLES.items():
    master = fn()
    masters[name] = master
    master.save(os.path.join(OUT, f"{name}-1024.png"))
    dest = os.path.join(OUT, name, "AppIcon.appiconset")
    os.makedirs(dest, exist_ok=True)
    for fname, px in SIZES:
        master.resize((px, px), Image.LANCZOS).save(os.path.join(dest, fname))
    print("wrote", name)

try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 44)
    small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 32)
except Exception:
    font = ImageFont.load_default(); small = font
cell = 560
grid = Image.new("RGB", (cell * 2 + 60, cell * 2 + 180), (245, 245, 247))
gd = ImageDraw.Draw(grid)
labels = {"a-sunset-pop": "A — Sunset Pop", "b-glass-bubble": "B — Glass Bubble",
          "c-vinyl-pink": "C — Vinyl Pink", "d-wave-bars": "D — Wave Bars"}
for i, (name, master) in enumerate(masters.items()):
    x = 20 + (i % 2) * (cell + 20)
    y = 20 + (i // 2) * (cell + 60)
    grid.paste(master.resize((cell, cell), Image.LANCZOS), (x, y))
    gd.text((x + 8, y + cell + 8), labels[name], fill=(20, 20, 20), font=font)
grid.save(os.path.join(OUT, "preview.png"))
print("preview:", os.path.join(OUT, "preview.png"))
