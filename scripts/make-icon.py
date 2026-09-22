#!/usr/bin/env python3
# Usage: scripts/make-icon.py Support/AppIcon.png   (needs Pillow)
"""Draws Support/AppIcon.png (1024x1024) on Apple's macOS icon grid."""
from PIL import Image, ImageDraw, ImageFilter
import math, sys

S = 4
N = 1024 * S
def px(v): return int(round(v * S))
def lerp(a, b, t): return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))

def vertical_gradient(stops):
    """stops: [(t, rgba)] top to bottom."""
    g = Image.new("RGBA", (1, N))
    for y in range(N):
        t = y / (N - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                g.putpixel((0, y), lerp(c0, c1, (t - t0) / (t1 - t0) if t1 > t0 else 0))
                break
    return g.resize((N, N))

def layer():
    return Image.new("RGBA", (N, N), (0, 0, 0, 0))

body_box = (px(100), px(100), px(924), px(924))
radius = px(185)
canvas = layer()

# Drop shadow.
sh = layer()
ImageDraw.Draw(sh).rounded_rectangle((body_box[0] + px(6), body_box[1] + px(18), body_box[2] - px(6), body_box[3] + px(18)), radius, fill=(30, 15, 80, 120))
canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(px(24))))

mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle(body_box, radius, fill=255)

# Indigo to violet, lit from above.
bg = vertical_gradient([(0, (124, 128, 255, 255)), (0.55, (99, 84, 240, 255)), (1, (112, 48, 214, 255))])
body = layer()
body.paste(bg, (0, 0), mask)
canvas.alpha_composite(body)

# Rim light.
rim = layer()
ImageDraw.Draw(rim).rounded_rectangle(body_box, radius, outline=(255, 255, 255, 70), width=px(3))
canvas.alpha_composite(rim)

# Content, centered on the body.
line_h = px(46)
left = px(262)
rows = [  # y, width, alpha
    (px(442), px(390), 150),
    (px(540), px(500), 255),
    (px(638), px(300), 150),
]

# Selection behind the middle line, with a soft glow.
sel = layer()
pad_x, pad_y = px(24), px(22)
y, w, _ = rows[1]
ImageDraw.Draw(sel).rounded_rectangle((left - pad_x, y - pad_y, left + w + pad_x, y + line_h + pad_y), px(26), fill=(255, 255, 255, 64))
canvas.alpha_composite(sel)

lines = layer()
ld = ImageDraw.Draw(lines)
for y, w, a in rows:
    ld.rounded_rectangle((left, y, left + w, y + line_h), line_h // 2, fill=(255, 255, 255, a))
# Text cursor right after the selection.
cx = left + rows[1][1] + pad_x + px(18)
ld.rounded_rectangle((cx, rows[1][0] - px(40), cx + px(14), rows[1][0] + line_h + px(40)), px(7), fill=(255, 255, 255, 255))
canvas.alpha_composite(lines)

# Sparkles, top right, clear of the lines.
spark = layer()
sd = ImageDraw.Draw(spark)
def sparkle(cx, cy, r, color, waist=0.26):
    pts = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * waist
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    sd.polygon(pts, fill=color)
sparkle(px(716), px(326), px(78), (255, 228, 140, 255))
sparkle(px(806), px(404), px(34), (255, 255, 255, 235))
canvas.alpha_composite(spark.filter(ImageFilter.GaussianBlur(px(12))))
canvas.alpha_composite(spark)

canvas.resize((1024, 1024), Image.LANCZOS).save(sys.argv[1])
