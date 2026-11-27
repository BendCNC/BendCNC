"""Generate BendCNC boot splash assets (Plymouth PNG + U-Boot 320x240 BMP)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).parent
FONTS = Path("C:/Windows/Fonts")
BG, RED, WHITE, GREY = (34, 34, 34), (237, 40, 45), (255, 255, 255), (110, 110, 110)


def font(name, size):
    return ImageFont.truetype(str(FONTS / name), size)


def draw(w, h):
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)
    s = w / 1366
    bold, light = font("segoeuib.ttf", int(150 * s)), font("segoeuil.ttf", int(150 * s))
    bw = d.textlength("BEND", font=bold)
    cw = d.textlength("CNC", font=light)
    x0 = (w - bw - cw) / 2
    y0 = h * 0.30
    d.text((x0, y0), "BEND", font=bold, fill=WHITE)
    d.text((x0 + bw, y0), "CNC", font=light, fill=RED)
    bar_y = y0 + 200 * s
    d.rectangle([x0, bar_y, x0 + bw + cw, bar_y + max(2, 6 * s)], fill=RED)
    if w >= 640:
        sub = font("segoeuil.ttf", int(46 * s))
        t = "Booting up system..."
        d.text(((w - d.textlength(t, font=sub)) / 2, bar_y + 50 * s), t, font=sub, fill=GREY)
        small = font("segoeui.ttf", int(24 * s))
        t = "(please allow 1-2 minutes)"
        d.text(((w - d.textlength(t, font=small)) / 2, bar_y + 120 * s), t, font=small, fill=GREY)
    return img


draw(1366, 768).save(OUT / "loading.png")
# Raw BGRX frame for bendcnc-fbsplash (1368x768 = press HDMI mode), zlib.
import struct, zlib
fb = draw(1368, 768).convert("RGBA")
r, g, b, a = fb.split()
raw = Image.merge("RGBA", (b, g, r, a)).tobytes()
(OUT / "splash.bgrx.z").write_bytes(struct.pack("<II", 1368, 768) + zlib.compress(raw, 9))
draw(320, 240).quantize(colors=16).save(OUT / "boot.bmp")
print("ok")
