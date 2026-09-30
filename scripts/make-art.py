"""Package the committed logo master and render LucidMic's repository/installer art.

Run: uv run --no-project --with-requirements requirements-dev.txt python scripts/make-art.py
The logo master is docs/assets/logo.png; regeneration does not call an image API.
"""

import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "Resources"
ASSETS = ROOT / "docs/assets"
SF = "/System/Library/Fonts/SFNS.ttf"
INK = (15, 26, 47)
MUTED = (90, 107, 133)
BLUE = (22, 112, 255)
CYAN = (49, 227, 229)


def font(size: int, weight: str = "Regular") -> ImageFont.FreeTypeFont:
    result = ImageFont.truetype(SF, size)
    result.set_variation_by_name(weight)
    return result


def gradient(size: tuple[int, int], top: tuple[int, ...], bottom: tuple[int, ...]) -> Image.Image:
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        color = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom, strict=True))
        draw.line((0, y, size[0], y), fill=color)
    return image.convert("RGBA")


def logo(size: int) -> Image.Image:
    with Image.open(ASSETS / "logo.png") as source:
        return source.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)


def make_icon() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        iconset = Path(temporary) / "AppIcon.iconset"
        iconset.mkdir()
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                suffix = "@2x" if scale == 2 else ""
                logo(size * scale).save(iconset / f"icon_{size}x{size}{suffix}.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(RES / "AppIcon.icns")], check=True)


def pill(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, scale: int = 1, dark: bool = False) -> int:
    face = font(14 * scale, "Medium")
    width = int(draw.textlength(text, font=face)) + 32 * scale
    draw.rounded_rectangle(
        (x, y, x + width, y + 34 * scale),
        radius=17 * scale,
        fill=(21, 43, 64) if dark else (231, 240, 255),
    )
    draw.text((x + 16 * scale, y + 17 * scale), text, font=face, fill=CYAN if dark else BLUE, anchor="lm")
    return width


def make_banner() -> None:
    image = gradient((1600, 600), (7, 18, 35), (13, 35, 53))
    draw = ImageDraw.Draw(image)
    draw.text((82, 76), "LucidMic", font=font(34, "Bold"), fill=(245, 250, 255))
    draw.text((78, 148), "Your voice.", font=font(86, "Bold"), fill=(245, 250, 255))
    draw.text((78, 242), "Minus the noise.", font=font(86, "Bold"), fill=CYAN)
    draw.text((82, 381), "Free, on-device AI noise removal for macOS.", font=font(28), fill=(177, 198, 219))
    x = 82
    for text in ("100% on-device", "One switch", "Free & open source"):
        x += pill(draw, x, 469, text, dark=True) + 12
    image.alpha_composite(logo(470), (1050, 64))
    image.convert("RGB").save(ASSETS / "banner.png", optimize=True)

    wordmark = Image.new("RGBA", (1200, 340))
    wordmark.alpha_composite(logo(320), (0, 10))
    ImageDraw.Draw(wordmark).text((350, 170), "LucidMic", font=font(128, "Bold"), fill=INK, anchor="lm")
    wordmark.save(ASSETS / "wordmark.png", optimize=True)


def make_background(scale: int) -> Image.Image:
    width, height = 660 * scale, 460 * scale
    image = gradient((width, height), (250, 252, 255), (233, 242, 253))
    draw = ImageDraw.Draw(image)
    draw.text((width / 2, 37 * scale), "LucidMic", font=font(30 * scale, "Bold"), fill=INK, anchor="mm")
    draw.text(
        (width / 2, 70 * scale),
        "Your voice. Minus the noise.",
        font=font(15 * scale),
        fill=MUTED,
        anchor="mm",
    )
    draw.text(
        (width / 2, 146 * scale),
        "Drag to Applications",
        font=font(13 * scale, "Semibold"),
        fill=BLUE,
        anchor="mm",
    )
    draw.line((268 * scale, 179 * scale, 390 * scale, 179 * scale), fill=BLUE, width=3 * scale)
    draw.line(
        (381 * scale, 171 * scale, 390 * scale, 179 * scale, 381 * scale, 187 * scale), fill=BLUE, width=3 * scale
    )
    draw.rounded_rectangle(
        (24 * scale, 290 * scale, 636 * scale, 434 * scale),
        radius=18 * scale,
        fill=(255, 255, 255),
    )
    draw.text(
        (width / 2, 318 * scale),
        "A quieter microphone. A clearer conversation.",
        font=font(18 * scale, "Semibold"),
        fill=INK,
        anchor="mm",
    )
    labels = ("On-device AI", "One switch", "Free & open source")
    widths = [int(draw.textlength(label, font=font(14 * scale, "Medium"))) + 32 * scale for label in labels]
    x = (width - sum(widths) - 20 * scale) // 2
    for label in labels:
        x += pill(draw, x, 346 * scale, label, scale) + 10 * scale
    draw.text(
        (width / 2, 405 * scale),
        "Open LucidMic from Applications, then turn on Noise removal.",
        font=font(12 * scale),
        fill=MUTED,
        anchor="mm",
    )
    return image.convert("RGB")


def make_ui_previews() -> None:
    """Frame the actual native UI snapshots for light/dark README appearances."""
    for mode, top, bottom in (
        ("light", (228, 237, 252), (244, 240, 234)),
        ("dark", (14, 23, 40), (25, 29, 37)),
    ):
        with Image.open(ASSETS / f"menu-{mode}.png") as snapshot:
            card = snapshot.convert("RGBA")
        canvas = gradient((1200, 560), top, bottom)
        x, y = (canvas.width - card.width) // 2, (canvas.height - card.height) // 2
        shadow = Image.new("RGBA", canvas.size)
        ImageDraw.Draw(shadow).rounded_rectangle(
            (x, y + 12, x + card.width, y + card.height + 12), radius=24, fill=(0, 0, 0, 65)
        )
        canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(25)))
        mask = Image.new("L", card.size)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, card.width - 1, card.height - 1), radius=24, fill=255)
        card.putalpha(ImageChops.multiply(card.getchannel("A"), mask))
        canvas.alpha_composite(card, (x, y))
        canvas.convert("RGB").save(ASSETS / f"hero-{mode}.png", optimize=True)


if __name__ == "__main__":
    RES.mkdir(exist_ok=True)
    (ROOT / "build").mkdir(exist_ok=True)
    make_icon()
    make_banner()
    make_ui_previews()
    with tempfile.TemporaryDirectory() as temporary:
        one, two = Path(temporary) / "background.png", Path(temporary) / "background@2x.png"
        make_background(1).save(one)
        make_background(2).save(two)
        subprocess.run(
            ["tiffutil", "-cathidpicheck", str(one), str(two), "-out", str(RES / "dmg-background.tiff")],
            check=True,
            capture_output=True,
        )
    make_background(2).save(ROOT / "build/dmg-background-preview.png")
    print("Wrote app icon, wordmark, README banner, and installer background")
