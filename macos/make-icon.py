#!/usr/bin/env python3
"""Generate the AgentRing app icon and the template menu-bar icon from the logo.

Usage:
    make-icon.py macos/Resources/Logo.png dist/icon-1024.png \
        dist/MenuBarIcon.png dist/MenuBarIcon@2x.png

The app icon keeps the light brand backdrop and gets the rounded-square mask
macOS expects. The menu-bar image is a monochrome ring silhouette with an alpha
channel; AppKit marks it as a template so it follows the menu-bar appearance.
"""

import sys

from PIL import Image, ImageDraw, ImageOps

APP_SIZE = 1024
APP_CORNER_RADIUS = 0.22
MENUBAR_SIZES = (18, 36)
MENUBAR_PADDING = 0.08
SATURATION_THRESHOLD = 50
APP_CROP_PADDING = 0.10
SUPERSAMPLE = 4


def content_box(img: Image.Image) -> tuple[int, int, int, int]:
    """Return a square crop around the colourful ring, ignoring the light backdrop."""
    probe = img.copy()
    probe.thumbnail((256, 256))
    rgb = probe.convert("RGB")
    width, height = rgb.size
    pixels = rgb.load()
    min_x, min_y, max_x, max_y = width, height, 0, 0
    for y in range(height):
        for x in range(width):
            r, g, b = pixels[x, y]
            if max(r, g, b) - min(r, g, b) > SATURATION_THRESHOLD:
                min_x, min_y = min(min_x, x), min(min_y, y)
                max_x, max_y = max(max_x, x), max(max_y, y)

    if max_x <= min_x or max_y <= min_y:
        min_x, min_y, max_x, max_y = 0, 0, width, height

    scale = img.width / width
    box = (int(min_x * scale), int(min_y * scale), int(max_x * scale), int(max_y * scale))
    side = max(box[2] - box[0], box[3] - box[1])
    pad = int(side * APP_CROP_PADDING)
    side += pad * 2
    center_x = (box[0] + box[2]) // 2
    center_y = (box[1] + box[3]) // 2
    left = center_x - side // 2
    top = center_y - side // 2
    return left, top, left + side, top + side


def app_icon(logo: Image.Image) -> Image.Image:
    icon = logo.crop(content_box(logo))
    icon = ImageOps.fit(icon, (APP_SIZE, APP_SIZE), method=Image.Resampling.LANCZOS)

    mask = Image.new("L", (APP_SIZE * SUPERSAMPLE, APP_SIZE * SUPERSAMPLE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, APP_SIZE * SUPERSAMPLE - 1, APP_SIZE * SUPERSAMPLE - 1],
        radius=int(APP_SIZE * SUPERSAMPLE * APP_CORNER_RADIUS),
        fill=255,
    )
    mask = mask.resize((APP_SIZE, APP_SIZE), Image.Resampling.LANCZOS)
    icon.putalpha(mask)
    return icon


def menu_bar_alpha(logo: Image.Image) -> Image.Image:
    """Return a high-resolution alpha mask of the ring, trimmed and padded square."""
    crop = logo.crop(content_box(logo)).convert("RGB")
    work = 512
    crop = ImageOps.fit(crop, (work, work), method=Image.Resampling.LANCZOS)
    mask = Image.new("L", (work, work), 0)
    source = crop.load()
    target = mask.load()
    for y in range(work):
        for x in range(work):
            r, g, b = source[x, y]
            if max(r, g, b) - min(r, g, b) > SATURATION_THRESHOLD:
                target[x, y] = 255

    bbox = mask.getbbox()
    if not bbox:
        raise SystemExit("logo does not contain a colourful ring")
    mask = mask.crop(bbox)
    side = max(mask.size)
    padded = int(side * (1 + MENUBAR_PADDING * 2))
    canvas = Image.new("L", (padded, padded), 0)
    canvas.paste(mask, ((padded - mask.width) // 2, (padded - mask.height) // 2))
    return canvas


def menu_bar_icon(alpha: Image.Image, size: int) -> Image.Image:
    mask = alpha.resize((size, size), Image.Resampling.LANCZOS)
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.putalpha(mask)
    return icon


def main(source: str, app_out: str, menu_1x: str, menu_2x: str) -> None:
    logo = Image.open(source).convert("RGBA")

    app_icon(logo).save(app_out)

    alpha = menu_bar_alpha(logo)
    menu_bar_icon(alpha, MENUBAR_SIZES[0]).save(menu_1x)
    menu_bar_icon(alpha, MENUBAR_SIZES[1]).save(menu_2x)
    print(f"wrote {app_out}, {menu_1x}, {menu_2x}")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: make-icon.py <Logo.png> <app-icon.png> <MenuBarIcon.png> <MenuBarIcon@2x.png>"
        )
    main(*sys.argv[1:])
