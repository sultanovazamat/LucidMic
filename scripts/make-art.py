"""Draws the LucidMic app icon and the DMG installer background.

Run: uv run --no-project --with pillow python scripts/make-art.py
Writes Resources/AppIcon.icns and Resources/dmg-background.tiff (committed, so builds don't need Pillow).
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Resources"
SF = "/System/Library/Fonts/SFNS.ttf"

INK = (22, 28, 45)
MUTED = (92, 102, 125)
ACCENT = (64, 110, 255)
ACCENT2 = (22, 196, 190)


def font(size: float, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(SF, int(size))
    f.set_variation_by_name(weight)
    return f


def gradient(size: tuple[int, int], top: tuple, bottom: tuple) -> Image.Image:
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        for x in range(w):
            px[x, y] = c
    return img


def waveform(draw: ImageDraw.ImageDraw, cx: float, cy: float, scale: float, color, width: float) -> None:
    """Symmetric voice waveform: tall in the middle, small at the edges."""
    heights = [0.18, 0.34, 0.56, 0.82, 1.0, 0.82, 0.56, 0.34, 0.18]
    gap = width * 1.9
    x0 = cx - gap * (len(heights) - 1) / 2
    for i, hgt in enumerate(heights):
        x = x0 + i * gap
        half = hgt * scale / 2
        draw.rounded_rectangle([x - width / 2, cy - half, x + width / 2, cy + half], radius=width / 2, fill=color)


def make_icon() -> None:
    size = 1024
    art = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    body = gradient((824, 824), (70, 104, 255), (24, 200, 190)).convert("RGBA")
    mask = Image.new("L", (824, 824), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, 823, 823], radius=185, fill=255)
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([100, 118, 924, 942], radius=185, fill=(0, 0, 0, 90))
    art.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18)))
    art.paste(body, (100, 100), mask)
    d = ImageDraw.Draw(art)
    waveform(d, 512, 512, 470, (255, 255, 255, 245), 46)
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for px in [16, 32, 64, 128, 256, 512, 1024]:
            img = art.resize((px, px), Image.LANCZOS)
            if px <= 512:
                img.save(iconset / f"icon_{px}x{px}.png")
            if px >= 32:
                img.save(iconset / f"icon_{px // 2}x{px // 2}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(RES / "AppIcon.icns")], check=True)


def chip(d: ImageDraw.ImageDraw, x: float, y: float, text: str, s: float) -> float:
    f = font(13 * s, "Medium")
    w = d.textlength(text, font=f) + 30 * s
    d.rounded_rectangle([x, y, x + w, y + 28 * s], radius=14 * s, fill=(255, 255, 255), outline=(214, 222, 240), width=max(1, int(s)))
    d.ellipse([x + 11 * s, y + 11 * s, x + 17 * s, y + 17 * s], fill=ACCENT2)
    d.text((x + 22 * s, y + 14 * s), text, font=f, fill=INK, anchor="lm")
    return w


def make_background(s: int) -> Image.Image:
    W, H = 660 * s, 460 * s
    img = gradient((W, H), (250, 251, 255), (232, 238, 250)).convert("RGBA")
    d = ImageDraw.Draw(img)

    d.text((W / 2, 38 * s), "LucidMic", font=font(30 * s, "Bold"), fill=INK, anchor="mm")
    d.text((W / 2, 70 * s), "Your voice, crystal clear — in every app.", font=font(15 * s, "Regular"), fill=MUTED, anchor="mm")

    # Arrow from the app icon (x=165) to Applications (x=495), icons centered at y=175.
    y = 175 * s
    d.text((W / 2, y - 26 * s), "Drag to Applications", font=font(13 * s, "Semibold"), fill=ACCENT, anchor="mm")
    x0, x1 = 258 * s, 400 * s
    for i in range(0, int(x1 - x0) - 18 * s, 14 * s):  # dashed shaft
        d.rounded_rectangle([x0 + i, y - 2 * s, x0 + i + 8 * s, y + 2 * s], radius=2 * s, fill=ACCENT)
    d.polygon([(x1 + 2 * s, y), (x1 - 14 * s, y - 10 * s), (x1 - 14 * s, y + 10 * s)], fill=ACCENT)

    # "What it removes" panel.
    top = 292 * s
    d.rounded_rectangle([24 * s, top, W - 24 * s, H - 20 * s], radius=16 * s, fill=(255, 255, 255, 170), outline=(220, 227, 242), width=max(1, s))
    d.text((44 * s, top + 22 * s), "Removes in real time", font=font(14 * s, "Semibold"), fill=INK, anchor="lm")
    d.text((W - 44 * s, top + 22 * s), "~70 ms · runs on your Mac", font=font(12 * s, "Regular"), fill=MUTED, anchor="rm")
    rows = [["Keyboard clicks", "Café buzz", "Fans & AC", "Traffic & street"],
            ["Munching & crunching", "Dogs & doors", "Hum & hiss", "Echoey rooms"]]
    for r, items in enumerate(rows):
        f = font(13 * s, "Medium")
        widths = [d.textlength(t, font=f) + 30 * s for t in items]
        gap = 10 * s
        x = (W - (sum(widths) + gap * (len(items) - 1))) / 2
        for t in items:
            x += chip(d, x, top + (42 + r * 36) * s, t, s) + gap
    d.text((W / 2, H - 38 * s), "No setup: open LucidMic, flip the switch. Zoom, Meet, Teams, FaceTime and Voice Memos just work.",
           font=font(12 * s, "Regular"), fill=MUTED, anchor="mm")
    return img.convert("RGB")


if __name__ == "__main__":
    RES.mkdir(exist_ok=True)
    make_icon()
    with tempfile.TemporaryDirectory() as tmp:
        one, two = Path(tmp) / "bg.png", Path(tmp) / "bg@2x.png"
        make_background(1).save(one)
        make_background(2).save(two)
        subprocess.run(["tiffutil", "-cathidpicheck", str(one), str(two), "-out", str(RES / "dmg-background.tiff")],
                       check=True, capture_output=True)
        make_background(2).save(ROOT / "build" / "dmg-background-preview.png")
    print("wrote Resources/AppIcon.icns and Resources/dmg-background.tiff")
