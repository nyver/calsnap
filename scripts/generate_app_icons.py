#!/usr/bin/env python3
"""Generate the Android launcher icons from apps/client/assets/branding/app_icon.png.

Requires Pillow and NumPy (pip install pillow numpy). Run from anywhere:

    python scripts/generate_app_icons.py

Outputs into apps/client/android/app/src/main/res:
  - mipmap-*/ic_launcher.png            legacy icon (API < 26): rounded square, transparent corners
  - mipmap-*/ic_launcher_foreground.png adaptive foreground layer (108dp canvas)
  - mipmap-*/ic_launcher_background.png adaptive background layer (108dp canvas)
  - mipmap-anydpi-v26/ic_launcher.xml   adaptive icon definition
and apps/client/assets/branding/play_store_icon.png (512x512, for store listings).
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "apps/client/assets/branding/app_icon.png"
STORE_ICON = ROOT / "apps/client/assets/branding/play_store_icon.png"
RES = ROOT / "apps/client/android/app/src/main/res"

# density -> pixels per dp
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
LEGACY_DP = 48
ADAPTIVE_DP = 108
# The launcher mask may clip the outer 18dp of each side, so the artwork (fork and leaves
# reach close to its edge) is scaled into the inner part of the visible 72dp area.
ADAPTIVE_ART_DP = 64

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
"""


def cut_out_artwork(src: Image.Image) -> Image.Image:
    """Return the rounded-square artwork cropped to its bounds with a transparent surround."""
    rgb = src.convert("RGB")
    marker = (255, 0, 255)
    flooded = rgb.copy()
    # The source has a flat white surround; flood it from all four corners.
    for corner in ((0, 0), (rgb.width - 1, 0), (0, rgb.height - 1), (rgb.width - 1, rgb.height - 1)):
        ImageDraw.floodfill(flooded, corner, marker, thresh=24)
    is_surround = np.all(np.asarray(flooded) == marker, axis=-1)
    alpha = Image.fromarray(np.where(is_surround, 0, 255).astype(np.uint8), "L")
    # Pull the edge in a little and soften it to drop the white fringe left by anti-aliasing.
    alpha = alpha.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
    art = rgb.convert("RGBA")
    art.putalpha(alpha)
    return art.crop(art.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())


def square(art: Image.Image) -> Image.Image:
    side = max(art.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(art, ((side - art.width) // 2, (side - art.height) // 2))
    return canvas


def background_layer(art: Image.Image, size: int) -> Image.Image:
    """Bilinear gradient sampled near the artwork corners, so the adaptive background matches."""
    rgb = np.asarray(art.convert("RGB")).astype(np.float64)
    h, w, _ = rgb.shape

    def sample(fx: float, fy: float) -> np.ndarray:
        cx, cy, r = int(fx * w), int(fy * h), max(4, w // 40)
        patch = rgb[cy - r : cy + r, cx - r : cx + r].reshape(-1, 3)
        return np.median(patch, axis=0)

    tl, tr = sample(0.16, 0.16), sample(0.84, 0.10)
    bl, br = sample(0.16, 0.84), sample(0.84, 0.84)
    u = np.linspace(0, 1, size)[None, :, None]
    v = np.linspace(0, 1, size)[:, None, None]
    grid = (tl * (1 - u) + tr * u) * (1 - v) + (bl * (1 - u) + br * u) * v
    return Image.fromarray(np.clip(grid, 0, 255).astype(np.uint8), "RGB")


def main() -> None:
    art = square(cut_out_artwork(Image.open(SOURCE)))

    STORE_ICON.parent.mkdir(parents=True, exist_ok=True)
    art.resize((512, 512), Image.LANCZOS).save(STORE_ICON, optimize=True)

    for name, scale in DENSITIES.items():
        out = RES / f"mipmap-{name}"
        out.mkdir(parents=True, exist_ok=True)

        legacy = round(LEGACY_DP * scale)
        art.resize((legacy, legacy), Image.LANCZOS).save(out / "ic_launcher.png", optimize=True)

        canvas = round(ADAPTIVE_DP * scale)
        inner = round(ADAPTIVE_ART_DP * scale)
        foreground = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
        offset = (canvas - inner) // 2
        foreground.paste(art.resize((inner, inner), Image.LANCZOS), (offset, offset))
        foreground.save(out / "ic_launcher_foreground.png", optimize=True)

        background_layer(art, canvas).save(out / "ic_launcher_background.png", optimize=True)

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(ADAPTIVE_XML, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
