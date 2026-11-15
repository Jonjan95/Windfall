# Draws the Windfall icon: a gold coin falling through wind streaks, with a
# leaf, on a dark green square.
#
# Usage: python -I tools/make_icon.py <dir with PIL> [out dir]
# Writes Media/icon.tga (64x64, for the game) and docs/icon-512.png (for
# CurseForge and GitHub).
import math
import os
import sys

sys.path.insert(0, sys.argv[1])
from PIL import Image, ImageDraw, ImageFilter

ROOT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
S = 1024  # drawn large, scaled down at the end


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# Background: radial green gradient in a rounded square.
bg = Image.new("RGBA", (S, S))
inner, outer = (52, 110, 62), (12, 34, 22)
px = bg.load()
cx, cy = S * 0.45, S * 0.40
for y in range(S):
    for x in range(S):
        d = min(1.0, math.hypot(x - cx, y - cy) / (S * 0.78))
        px[x, y] = lerp(inner, outer, d ** 0.9) + (255,)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.16), fill=255)
img.paste(bg, (0, 0), mask)

d = ImageDraw.Draw(img)

# Wind streaks, curving down from the top left behind the coin.
streaks = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(streaks)
for i, (y0, w, a) in enumerate([(0.20, 34, 120), (0.33, 26, 90), (0.46, 20, 70)]):
    pts = []
    for k in range(60):
        t = k / 59
        x = S * (0.08 + 0.50 * t)
        y = S * (y0 + 0.16 * t * t)
        pts.append((x, y))
    sd.line(pts, fill=(200, 240, 200, a), width=w, joint="curve")
    r = w / 2
    for p in (pts[0], pts[-1]):
        sd.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(200, 240, 200, a))
streaks = streaks.filter(ImageFilter.GaussianBlur(4))
img.alpha_composite(streaks)

# Coin: tilted ellipse with a rim, a face and a shine.
coin = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cd = ImageDraw.Draw(coin)
ccx, ccy, rx, ry = S * 0.60, S * 0.60, S * 0.27, S * 0.27
# Edge (thickness) below the face.
cd.ellipse([ccx - rx, ccy - ry + 34, ccx + rx, ccy + ry + 34], fill=(150, 98, 18, 255))
cd.ellipse([ccx - rx, ccy - ry, ccx + rx, ccy + ry], fill=(222, 164, 38, 255))
cd.ellipse([ccx - rx * 0.80, ccy - ry * 0.80, ccx + rx * 0.80, ccy + ry * 0.80], fill=(250, 206, 70, 255))
cd.ellipse([ccx - rx * 0.70, ccy - ry * 0.70, ccx + rx * 0.70, ccy + ry * 0.70], fill=(240, 186, 52, 255))
# A "W" stamped on the face.
wpts = [(-0.38, -0.30), (-0.20, 0.32), (0.0, -0.08), (0.20, 0.32), (0.38, -0.30)]
cd.line([(ccx + x * rx, ccy + y * ry) for x, y in wpts], fill=(170, 112, 22, 255), width=int(S * 0.045), joint="curve")
for x, y in (wpts[0], wpts[-1]):
    r = S * 0.0225
    cd.ellipse([ccx + x * rx - r, ccy + y * ry - r, ccx + x * rx + r, ccy + y * ry + r], fill=(170, 112, 22, 255))
coin = coin.rotate(-18, center=(ccx, ccy), resample=Image.BICUBIC)
# Soft shadow under the coin.
shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([ccx - rx + 30, ccy - ry + 60, ccx + rx + 30, ccy + ry + 60], fill=(0, 0, 0, 110))
img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(28)))
img.alpha_composite(coin)
# Shine.
shine = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shine).ellipse([ccx - rx * 0.62, ccy - ry * 0.78, ccx - rx * 0.12, ccy - ry * 0.42], fill=(255, 250, 220, 150))
img.alpha_composite(shine.filter(ImageFilter.GaussianBlur(14)))

# Leaf, top left, caught in the wind.
leaf = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ld = ImageDraw.Draw(leaf)
lx, ly, L = S * 0.27, S * 0.30, S * 0.15
body = []
for k in range(41):
    t = k / 40 * math.pi
    body.append((lx + math.cos(t) * L, ly - math.sin(t) * L * 0.45))
for k in range(41):
    t = math.pi + k / 40 * math.pi
    body.append((lx + math.cos(t) * L, ly - math.sin(t) * L * 0.45))
ld.polygon(body, fill=(126, 211, 107, 255))
ld.line([(lx - L * 1.15, ly), (lx + L * 0.85, ly)], fill=(60, 130, 60, 255), width=10)
leaf = leaf.rotate(28, center=(lx, ly), resample=Image.BICUBIC)
img.alpha_composite(leaf)

# Thin bright border.
border = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(border).rounded_rectangle([6, 6, S - 7, S - 7], radius=int(S * 0.155), outline=(126, 211, 107, 200), width=14)
img.alpha_composite(border)
img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (S, S), 0), mask))

media = os.path.join(ROOT, "Media")
os.makedirs(media, exist_ok=True)
docs = os.path.join(ROOT, "docs")
os.makedirs(docs, exist_ok=True)
img.resize((512, 512), Image.LANCZOS).save(os.path.join(docs, "icon-512.png"))

# The game wants an uncompressed 32-bit TGA with a power-of-two size.
small = img.resize((64, 64), Image.LANCZOS)
with open(os.path.join(media, "icon.tga"), "wb") as f:
    f.write(bytes([0, 0, 2]) + bytes(9) + (64).to_bytes(2, "little") * 2 + bytes([32, 0x28]))
    for y in range(64):
        for x in range(64):
            r, g, b, a = small.getpixel((x, y))
            f.write(bytes([b, g, r, a]))
print("wrote", media, "and", docs)
