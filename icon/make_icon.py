"""Draws the ACOM Control app icon (1024 px master) and writes AppIcon.icns.

Design: macOS-style rounded tile, deep navy gradient, amber analogue power
meter with a red over-power zone, white needle and a small "700S" badge.
"""
import math, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
S = 4096                      # supersampled canvas, downscaled to 1024
k = S / 1024                  # scale helper: design in 1024-unit coordinates
FONT = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"

def u(v): return int(round(v * k))

img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# --- Tile: Apple's icon grid puts an 824 px tile inside the 1024 canvas.
pad, radius = 100, 185
tile_box = (u(pad), u(pad), u(1024 - pad), u(1024 - pad))

# soft drop shadow
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle(
    (tile_box[0], tile_box[1] + u(14), tile_box[2], tile_box[3] + u(14)),
    radius=u(radius), fill=(0, 0, 0, 110))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(u(18))))

# vertical gradient fill
grad = Image.new("RGBA", (S, S))
gd = ImageDraw.Draw(grad)
top, bot = (34, 52, 86), (10, 16, 30)
for y in range(S):
    t = y / S
    gd.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bot)) + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(tile_box, radius=u(radius), fill=255)
img.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(img)
# subtle top highlight edge
d.rounded_rectangle(tile_box, radius=u(radius), outline=(255, 255, 255, 38), width=u(4))

# --- Meter geometry
cx, cy, R = 512, 600, 300
a0, a1 = 210, 330             # PIL angles (0 = 3 o'clock, clockwise): arc spans 120°
def pt(angle, r):
    rad = math.radians(angle)
    return (u(cx + r * math.cos(rad)), u(cy + r * math.sin(rad)))
box = lambda r: (u(cx - r), u(cy - r), u(cx + r), u(cy + r))

# meter face glow
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).pieslice(box(R + 40), a0 - 6, a1 + 6, fill=(255, 170, 40, 60))
img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(u(40))))
d = ImageDraw.Draw(img)

# scale band: amber up to 80 %, red beyond
split = a0 + (a1 - a0) * 0.8
d.arc(box(R), a0, split, fill=(255, 176, 46, 255), width=u(34))
d.arc(box(R), split, a1, fill=(235, 64, 52, 255), width=u(34))

# tick marks
for i in range(11):
    ang = a0 + (a1 - a0) * i / 10
    major = i % 2 == 0
    r_in = R - (78 if major else 58)
    col = (235, 64, 52, 255) if ang > split else (255, 236, 200, 235)
    d.line([pt(ang, r_in), pt(ang, R - 30)], fill=col, width=u(12 if major else 7))

# needle (at ~68 % of scale) with soft shadow
na = a0 + (a1 - a0) * 0.68
tip, tail = pt(na, R - 18), pt(na + 180, 46)
perp = math.radians(na + 90)
w = 16
base1 = (u(cx + w * math.cos(perp)), u(cy + w * math.sin(perp)))
base2 = (u(cx - w * math.cos(perp)), u(cy - w * math.sin(perp)))
nsh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
off = u(10)
ImageDraw.Draw(nsh).polygon([(x + off, y + off) for x, y in (tip, base1, tail, base2)], fill=(0, 0, 0, 130))
img.alpha_composite(nsh.filter(ImageFilter.GaussianBlur(u(10))))
d = ImageDraw.Draw(img)
d.polygon([tip, base1, tail, base2], fill=(250, 250, 252, 255))

# hub
d.ellipse(box(44), fill=(30, 40, 62, 255), outline=(250, 250, 252, 255), width=u(10))
d.ellipse(box(14), fill=(255, 176, 46, 255))

# "W" scale label and model badge
f_small = ImageFont.truetype(FONT, u(56))
d.text((u(cx), u(cy - 150)), "W", font=f_small, fill=(255, 236, 200, 170), anchor="mm")

f_badge = ImageFont.truetype(FONT, u(92))
label = "700S"
tw = d.textlength(label, font=f_badge)
bx0, bx1 = u(cx) - tw / 2 - u(44), u(cx) + tw / 2 + u(44)
by0, by1 = u(712), u(828)
d.rounded_rectangle((bx0, by0, bx1, by1), radius=u(58), fill=(255, 176, 46, 255))
d.text((u(cx), (by0 + by1) / 2), label, font=f_badge, fill=(16, 24, 42, 255), anchor="mm")

master = img.resize((1024, 1024), Image.LANCZOS)
master.save(f"{OUT}/AppIcon-1024.png")
master.save(f"{OUT}/AppIcon.icns",
            sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
print("wrote", f"{OUT}/AppIcon-1024.png", f"{OUT}/AppIcon.icns")
