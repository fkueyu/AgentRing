#!/usr/bin/env python3
"""Render a 24-LED ring frame as a PNG (for README images and quick checks).

    python3 tools/render-ring.py --frame /tmp/frame.bin --out ring.png
    python3 tools/render-ring.py --url http://127.0.0.1:7801/frame --out ring.png --state http://127.0.0.1:7801/state
"""

import argparse
import json
import math
import urllib.request

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 420
RADIUS = 150
DOT = 15


def load(url=None, path=None):
    if url:
        return urllib.request.urlopen(url, timeout=3).read()
    with open(path, "rb") as fh:
        return fh.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frame")
    ap.add_argument("--url")
    ap.add_argument("--state")
    ap.add_argument("--out", default="ring.png")
    ap.add_argument("--title", default="")
    args = ap.parse_args()

    data = load(url=args.url, path=args.frame)
    leds = [(data[i * 3], data[i * 3 + 1], data[i * 3 + 2]) for i in range(len(data) // 3)]

    img = Image.new("RGB", (SIZE, SIZE), (11, 13, 18))
    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    d = ImageDraw.Draw(img)
    g = ImageDraw.Draw(glow)
    cx = cy = SIZE / 2

    # track
    d.ellipse(
        [cx - RADIUS - DOT * 1.9, cy - RADIUS - DOT * 1.9, cx + RADIUS + DOT * 1.9, cy + RADIUS + DOT * 1.9],
        outline=(28, 33, 44),
        width=int(DOT * 1.9),
    )

    for i, (r, gr, b) in enumerate(leds):
        a = (i / len(leds)) * math.tau - math.pi / 2
        x, y = cx + math.cos(a) * RADIUS, cy + math.sin(a) * RADIUS
        box = [x - DOT, y - DOT, x + DOT, y + DOT]
        if r + gr + b > 6:
            d.ellipse(box, fill=(r, gr, b))
            g.ellipse([x - DOT * 1.5, y - DOT * 1.5, x + DOT * 1.5, y + DOT * 1.5], fill=(r, gr, b))
        else:
            d.ellipse(box, fill=(22, 26, 34))

    img = Image.blend(img, Image.new("RGB", img.size, (255, 255, 255)), 0.0)
    halo = glow.filter(ImageFilter.GaussianBlur(18))
    img = Image.fromarray(
        __import__("numpy").clip(
            __import__("numpy").asarray(img, dtype=int) + __import__("numpy").asarray(halo, dtype=int), 0, 255
        ).astype("uint8")
    )

    if args.state:
        state = json.loads(urllib.request.urlopen(args.state, timeout=3).read())
        d = ImageDraw.Draw(img)
        try:
            font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 15)
        except OSError:
            font = ImageFont.load_default()
        lines = [f"{a['source']}  {a['state']}" + (f"  {a['tool']}" if a.get("tool") else "") for a in state["agents"]]
        y = SIZE - 18 - 18 * len(lines)
        for line in lines:
            d.text((20, y), line, fill=(150, 160, 180), font=font)
            y += 18

    if args.title:
        d = ImageDraw.Draw(img)
        try:
            font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 16)
        except OSError:
            font = ImageFont.load_default()
        d.text((20, 18), args.title, fill=(200, 210, 230), font=font)

    img.save(args.out)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
